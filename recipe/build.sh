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
sed -i.bak 's/bool m_DefaultGas;/bool m_DefaultGas = false;/' \
    "${SRC_DIR}/third_party/Windows-CalcEngine/src/Gases/src/Gas.hpp"

# third_party/kiva/vendor/boost-1.88.0: Boost.MPL integral_wrapper generates
# 'prior' and 'next' typedefs by computing (value - 1) / (value + 1) as
# non-type template arguments of an enum type.  In strict C++17, clang rejects
# this when the value falls outside the declared enumerator range, e.g. -1 is
# outside [0,3] for a 4-value enum:
#   "non-type template argument is not a constant expression"
#
# The root fix is to give each affected enum a fixed underlying type (': int').
# With a fixed underlying type, ALL integer values representable by 'int' are
# valid non-type template arguments, so (value - 1) = -1 is legal.
#
# The three Boost numeric-conversion enums that are used as mpl::integral_c
# template parameters and thus hit this path:
#   int_float_mixture_enum  (4 values: 0-3)
#   udt_builtin_mixture_enum (4 values: 0-3)
#   sign_mixture_enum        (4 values: 0-3)
_boost_nc="${SRC_DIR}/third_party/kiva/vendor/boost-1.88.0/boost/numeric/conversion"
sed -i.bak 's/enum int_float_mixture_enum$/enum int_float_mixture_enum : int/' \
    "${_boost_nc}/int_float_mixture_enum.hpp"
sed -i.bak 's/enum udt_builtin_mixture_enum$/enum udt_builtin_mixture_enum : int/' \
    "${_boost_nc}/udt_builtin_mixture_enum.hpp"
sed -i.bak 's/enum sign_mixture_enum$/enum sign_mixture_enum : int/' \
    "${_boost_nc}/sign_mixture_enum.hpp"

# Extra CXX flags to paper over third-party source issues.
# Flags are split by compiler because clang rejects GCC-only warning options
# with -Werror,-Wunknown-warning-option.
#
# Common (both GCC and clang):
#   -include cstdint         third_party/ssc uses SIZE_MAX without <cstdint>
#
# GCC-only:
#   -Wno-dangling-reference  (GCC 13+): false-positive in fmt/core.h via btwxt
#   -Wno-restrict            (GCC 15+): false-positive in fmt/format.h
#   -Wno-alloc-size-larger-than  (GCC 15+): false-positive in ObjexxFCL
#
# clang-only:
#   -Wno-deprecated-literal-operator  clang deprecates `operator"" _a`
#                                     (space before UDL identifier) in fmt 8.0.1
#   -Wno-deprecated-declarations      CLI11 2.4.2 uses std::wstring_convert
#                                     (deprecated in C++17); libc++ emits the
#                                     deprecation from inside its own header
#                                     body, so CLI11's own diagnostic push/pop
#                                     doesn't cover it — suppress globally.
#   -Wno-unknown-warning-option       kiva/compiler-flags.cmake adds
#                                     -Wno-enum-constexpr-conversion gated on
#                                     Clang>=16 / AppleClang>=15, but the
#                                     conda-forge clang on macos-14 may be
#                                     older and rejects the flag with
#                                     -Werror,-Wunknown-warning-option.
#                                     This suppresses that class of error safely.
#   -DFMT_USE_CONSTEVAL=0             fmt 8.0.1's FMT_STRING() macro wraps a
#                                     consteval constructor call. Clang 22
#                                     (conda-forge osx-arm64) enforces stricter
#                                     consteval rules and rejects the call in
#                                     format-inl.h:2530. This define disables
#                                     fmt's consteval usage, falling back to
#                                     constexpr, which all Clang versions accept.
EXTRA_CXX_FLAGS="-include cstdint"
if "${CXX:-c++}" --version 2>&1 | grep -q clang; then
    EXTRA_CXX_FLAGS="${EXTRA_CXX_FLAGS} -Wno-deprecated-literal-operator -Wno-deprecated-declarations -Wno-unknown-warning-option -DFMT_USE_CONSTEVAL=0"
else
    # GCC
    EXTRA_CXX_FLAGS="${EXTRA_CXX_FLAGS} -Wno-dangling-reference -Wno-restrict -Wno-alloc-size-larger-than"
fi

# Set a long placeholder RPATH so patchelf can always rewrite it.
# rattler-build uses patchelf post-install to set $ORIGIN-relative RPATHs,
# but patchelf cannot grow the ELF RPATH section — it can only shrink or keep
# the same length.  Build dirs are short (/tmp/energyplusXXXXXX/...) so the
# default baked-in RPATH is short.  We pad the install RPATH to 256 chars with
# harmless /././ segments so the ELF section is allocated large enough.
# CMAKE_BUILD_WITH_INSTALL_RPATH=ON makes CMake bake that long value at link
# time rather than a short build-dir path.
# Note: our flags come AFTER ${CMAKE_ARGS} so they override anything rattler
# injects for CMAKE_INSTALL_RPATH.
_rpath="${PREFIX}/lib"
while [ ${#_rpath} -lt 256 ]; do _rpath="${_rpath}/././"; done

# shellcheck disable=SC2086  # CMAKE_ARGS and EXTRA_CXX_FLAGS must be word-split

# On macOS, rattler-build injects clang as CMAKE_CXX_COMPILER but gcc as
# CMAKE_C_COMPILER (via activate-gcc script before activate_clang).
# EnergyPlus's CompilerFlags.cmake adds -fcolor-diagnostics to project_options
# when CMAKE_CXX_COMPILER_ID is AppleClang, but project_options applies to ALL
# languages including C — and gcc's C compiler rejects -fcolor-diagnostics.
# Fix: force CMAKE_C_COMPILER to clang when CLANG is set (macOS only).
EXTRA_CMAKE_ARGS=""
if [ -n "${CLANG:-}" ]; then
    EXTRA_CMAKE_ARGS="-DCMAKE_C_COMPILER=${CLANG}"
fi

cmake ${CMAKE_ARGS} ${EXTRA_CMAKE_ARGS} \
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
  -DCMAKE_INSTALL_RPATH="${_rpath}" \
  -DCMAKE_BUILD_WITH_INSTALL_RPATH=ON \
  -B "${BUILD_DIR}" \
  -S "${SRC_DIR}"

cmake --build "${BUILD_DIR}" --target install -j"${CPU_COUNT:-2}"

# Remove GUI app bundles — they are CPack/installer artifacts not needed in a
# conda package, and rattler-build's codesign step fails on them (macOS).
rm -rf "${PREFIX}/PreProcess/EP-Launch-Lite.app"

# ---------------------------------------------------------------------------
# Post-install: wire up conda-friendly paths
# ---------------------------------------------------------------------------
# EnergyPlus installs everything flat to $PREFIX/ (not $PREFIX/bin/).
# We need to:
#   1. Put a wrapper on PATH so `energyplus` works from anywhere
#   2. Make pyenergyplus importable by Python

# 1. Create $PREFIX/bin/energyplus wrapper script
#    EnergyPlus must be invoked from its install dir so it finds co-located
#    IDD/data files (it uses relative paths from the binary location).
mkdir -p "${PREFIX}/bin"
cat > "${PREFIX}/bin/energyplus" << 'WRAPPER'
#!/usr/bin/env bash
# Wrapper: delegate to the real energyplus binary in $PREFIX
# The binary is one level up from $PREFIX/bin/
_ep_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec "${_ep_dir}/energyplus" "$@"
WRAPPER
chmod +x "${PREFIX}/bin/energyplus"

# 2. Make pyenergyplus importable: drop a .pth file in site-packages
#    pointing at $PREFIX so `import pyenergyplus` resolves to $PREFIX/pyenergyplus/
#    Use rattler-build-injected $SP_DIR (the site-packages that gets packaged).
mkdir -p "${SP_DIR}"
echo "${PREFIX}" > "${SP_DIR}/energyplus.pth"
