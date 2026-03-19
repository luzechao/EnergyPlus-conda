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

# Suppress two fmt v8.0.1 warnings that become fatal errors under -Werror with
# GCC 13+.  Both are false-positive / overly-aggressive diagnostics in GCC
# that fire inside third_party/fmt-8.0.1 headers:
#   -Wdangling-reference  (GCC 13+): fires in fmt/core.h:1637 via btwxt
#   -Wrestrict            (GCC 15+): fires in fmt/format.h via generate_embeddable_epJSON_schema
# These flags are appended to whatever CXXFLAGS conda-forge already injects;
# they do NOT disable -Werror globally, only these two specific diagnostics.
EXTRA_CXX_FLAGS="-Wno-dangling-reference -Wno-restrict"

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
