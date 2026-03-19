#!/usr/bin/env bash
set -euo pipefail

# EnergyPlus conda-forge build script (Unix: Linux / macOS)
#
# Environment variables provided by rattler-build / conda-build:
#   SRC_DIR   - unpacked source tree
#   PREFIX    - conda install prefix
#   CPU_COUNT - number of CPUs available
#   CMAKE_ARGS - injected by conda-forge (sysroot, deployment target, etc.)

BUILD_DIR="${SRC_DIR}/../build_energyplus"
mkdir -p "${BUILD_DIR}"

# ---------------------------------------------------------------------------
# Source patches for third-party code that has real bugs or missing includes
# which cause build failures with newer GCC / libstdc++.
# We patch in-tree so the upstream source is never permanently modified.
# ---------------------------------------------------------------------------

# third_party/Windows-CalcEngine: CGas::m_DefaultGas has no in-class initializer
# and is read before being set in the two constructors that delegate to
# addGasItems().  GCC -Werror=uninitialized correctly rejects this.
# Fix: add "= false" to the declaration in Gas.hpp.
sed -i 's/bool m_DefaultGas;/bool m_DefaultGas = false;/' \
    "${SRC_DIR}/third_party/Windows-CalcEngine/src/Gases/src/Gas.hpp"

# Extra CXX flags to paper over third-party source issues that cannot be fixed
# without modifying upstream code:
#
#   -Wno-dangling-reference  (GCC 13+): false-positive in fmt/core.h:1637 via
#                            third_party/btwxt (courierr.h)
#   -Wno-restrict            (GCC 15+): false-positive in fmt/format.h via
#                            third_party/idd generate_embeddable_epJSON_schema
#   -include cstdint         third_party/ssc/shared/lib_battery_dispatch.cpp
#                            uses SIZE_MAX without including <cstdint>; newer
#                            libstdc++ no longer pulls it in transitively.
#                            Force-including <cstdint> is safe (no side effects).
#   -Wno-alloc-size-larger-than  (GCC 15+): false-positive in ObjexxFCL/
#                            AlignedAllocator.hh:47. The ternary guard n > 0u
#                            correctly prevents zero/overflow allocation, but
#                            GCC's IPA analysis loses the guard after deep
#                            template inlining and reports worst-case SIZE_MAX*sizeof(T)+63.
EXTRA_CXX_FLAGS="-Wno-dangling-reference -Wno-restrict -include cstdint -Wno-alloc-size-larger-than"

# shellcheck disable=SC2086  # CMAKE_ARGS and EXTRA_CXX_FLAGS must be word-split
cmake ${CMAKE_ARGS} \
  -GNinja \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX="${PREFIX}" \
  -DCMAKE_CXX_FLAGS="${CXXFLAGS} ${EXTRA_CXX_FLAGS}" \
  -DBUILD_FORTRAN=ON \
  -DOPENGL_REQUIRED=OFF \
  -DDOCUMENTATION_BUILD=DoNotBuild \
  -DBUILD_TESTING=OFF \
  -DBUILD_PACKAGE=ON \
  -DLINK_WITH_PYTHON=ON \
  -DPython_ROOT_DIR="${PREFIX}" \
  -DPython_FIND_STRATEGY=LOCATION \
  -B "${BUILD_DIR}" \
  -S "${SRC_DIR}"

cmake --build "${BUILD_DIR}" --target install -j"${CPU_COUNT:-2}"
