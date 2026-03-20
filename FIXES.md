# EnergyPlus conda packaging — build fix log

Chronological record of every issue hit while packaging EnergyPlus v25.2.0
as a rattler-build conda recipe targeting `linux-64`, `osx-arm64`, and `win-64`.

---

## 1. Linux — `fmt` v8 GCC 13+ diagnostics (`-Werror`)

**Commit:** `141bf62`  
**Platform:** linux-64  
**Error:** GCC 13+ emits new warnings (`-Wdangling-reference`, `-Wrestrict`) as errors in the bundled `fmt` 8.0.1 headers via btwxt.  
**Fix:** Pass `-Wno-dangling-reference -Wno-restrict` via `CMAKE_CXX_FLAGS`.

---

## 2. Linux — `CGas::m_DefaultGas` uninitialized member

**Commit:** `dfea50f`  
**Platform:** linux-64 (also affects others)  
**Error:** `GCC -Werror=uninitialized`: `bool m_DefaultGas` declared in `Gas.hpp` has no in-class initializer and is read before being set in constructors that delegate via `addGasItems()`.  
**Fix:** `sed` patch in `build.sh`: `bool m_DefaultGas;` → `bool m_DefaultGas = false;`

---

## 3. Linux — `third_party/ssc` missing `<cstdint>` for `SIZE_MAX`

**Commit:** `f7a38d3`  
**Platform:** linux-64 (also affects others)  
**Error:** `SIZE_MAX` undeclared in ssc sources.  
**Fix:** Add `-include cstdint` to `EXTRA_CXX_FLAGS` (both GCC and clang).

---

## 4. Linux — `ObjexxFCL` GCC 15 `-Wno-alloc-size-larger-than` false-positive

**Commit:** `c347a3b`  
**Platform:** linux-64  
**Error:** GCC 15 introduces `-Wno-alloc-size-larger-than` as a new warning that fires as a false-positive in ObjexxFCL.  
**Fix:** Add `-Wno-alloc-size-larger-than` to GCC-only `EXTRA_CXX_FLAGS`.

---

## 5. Linux — patchelf cannot grow ELF RPATH section

**Commit:** `6524859`  
**Platform:** linux-64  
**Error:** rattler-build uses patchelf post-install to rewrite `$ORIGIN`-relative RPATHs, but patchelf cannot grow a section — only shrink or keep it. The default baked RPATH is short (`$ORIGIN`, 7 chars) so the ELF section is too small.  
**Fix:** In `build.sh`, pad `CMAKE_INSTALL_RPATH` to 256 chars with harmless `/././` segments, and set `CMAKE_BUILD_WITH_INSTALL_RPATH=ON` so the long value is baked at link time (placed **after** `${CMAKE_ARGS}` to override any rattler-injected value).

---

## 6. EnergyPlus flat install layout — post-install PATH/import wiring

**Commit:** `f50403f`  
**Platform:** all Unix  
**Issue:** EnergyPlus installs everything flat to `$CMAKE_INSTALL_PREFIX/` — binary, `.so`, `pyenergyplus/`, IDD files — not to `$PREFIX/bin/`. The binary is not on PATH and `pyenergyplus` is not importable.  
**Fix:** Post-install steps in `build.sh`:
1. Create `$PREFIX/bin/energyplus` wrapper script that `exec`s `$PREFIX/energyplus "$@"` (so the binary runs from its install dir and finds co-located data files).
2. Write `$PREFIX` into `energyplus.pth` in site-packages so `import pyenergyplus` resolves.

---

## 7. macOS — BSD `sed -i` requires a backup extension

**Commit:** `e52bbe3`  
**Platform:** osx-arm64  
**Error:** `sed: 1: "...": extra characters at the end of d command` — macOS BSD `sed -i` requires a backup extension argument; GNU `sed -i` does not.  
**Fix:** Use `sed -i.bak` everywhere in `build.sh` — works on both GNU (Linux) and BSD (macOS); the `.bak` files are harmless.

---

## 8. macOS — C compiler mismatch: GCC rejects `-fcolor-diagnostics`

**Commit:** `8270f71`  
**Platform:** osx-arm64  
**Error:** rattler-build on macOS injects `gcc` as `CMAKE_C_COMPILER` (via `activate-gcc`) but `clang` as `CMAKE_CXX_COMPILER`. EnergyPlus's `CompilerFlags.cmake` adds `-fcolor-diagnostics` to `project_options` when `CMAKE_CXX_COMPILER_ID` is `AppleClang`; `project_options` applies to all languages including C — and GCC's C compiler rejects `-fcolor-diagnostics`.  
**Fix:** In `build.sh`, when the `$CLANG` env var is set (macOS only, set by rattler-build), pass `-DCMAKE_C_COMPILER=${CLANG}` so both C and C++ use clang.

---

## 9. Windows — `cmake_add_fortran_subdirectory` vs VS generator

**Commit:** `8270f71`  
**Platform:** win-64  
**Error:** Passing `-DCMAKE_Fortran_COMPILER` under the VS generator causes CMake to test the Fortran compiler through MSBuild, which always fails. EnergyPlus uses `cmake_add_fortran_subdirectory()` which expects no Fortran compiler under the VS generator and then invokes MinGW gfortran as an ExternalProject.  
**Fix:** Pass `-DMINGW_GFORTRAN=C:/msys64/mingw64/bin/x86_64-w64-mingw32-gfortran.exe` (not `CMAKE_Fortran_COMPILER`). Use forward slashes to avoid CMake escape-sequence misinterpretation.

---

## 10. macOS — kiva adds `-Wno-enum-constexpr-conversion` on older clang

**Commit:** `578710e`  
**Platform:** osx-arm64  
**Error:** `kiva/cmake/compiler-flags.cmake` gates `-Wno-enum-constexpr-conversion` on Clang≥16/AppleClang≥15. If the conda-forge clang is older, the flag is omitted — but EnergyPlus unconditionally adds `-Werror`, making any unknown `-Wno-*` flag fatal.  
**Fix:** Add `-Wno-unknown-warning-option` to clang-only `EXTRA_CXX_FLAGS` in `build.sh`.

---

## 11. macOS — Boost.MPL `integral_wrapper` C++17 enum range error (static_cast attempt — ineffective)

**Commit:** `06b53c9` *(superseded by #12)*  
**Platform:** osx-arm64  
**Error:** `boost/mpl/aux_/integral_wrapper.hpp` generates `prior`/`next` typedefs by computing `value - 1` / `value + 1` as non-type template arguments of an enum type. Strict C++17 clang rejects out-of-range values: `"non-type template argument is not a constant expression"` (`-1` outside `[0,3]` for `udt_builtin_mixture_enum`).  
**Attempted fix:** Change `BOOST_MPL_AUX_STATIC_CAST` in `static_cast.hpp` from `static_cast<T>(expr)` to a C-style cast `(T)(expr)`. **This did not work** — a C-style cast to an enum type without fixed underlying type still produces an out-of-range value rejected as a non-type template argument.

---

## 12. macOS — Boost.MPL `integral_wrapper` C++17 enum range error (correct fix)

**Commit:** `2ef0eb3`  
**Platform:** osx-arm64  
**Error:** Same as #11.  
**Root cause:** The three Boost numeric-conversion enums (`int_float_mixture_enum`, `udt_builtin_mixture_enum`, `sign_mixture_enum`) have no fixed underlying type, so only their declared enumerator values `[0,3]` are valid as non-type template arguments in C++17. `value - 1 = -1` is outside this range.  
**Fix:** `sed` patches in `build.sh` that add `: int` (fixed underlying type) to each enum declaration:
```
enum int_float_mixture_enum  →  enum int_float_mixture_enum : int
enum udt_builtin_mixture_enum  →  enum udt_builtin_mixture_enum : int
enum sign_mixture_enum  →  enum sign_mixture_enum : int
```
With a fixed underlying type, all `int`-representable values are valid non-type template arguments.

---

## 13. Windows — `PythonCopyStandardLib.py` copies missing `tcl` directory

**Commit:** `2ef0eb3`  
**Platform:** win-64  
**Error:** `FileNotFoundError: [WinError 3] ... 'h_env\tcl'` — EnergyPlus's `PythonCopyStandardLib.py` unconditionally copies `<python_root>/tcl` into the build tree as an MSBuild post-link step for `energyplusapi.dll`. In the conda `h_env`, Tcl/Tk is a separate package not installed under the Python prefix, so `os.path.join(python_root_dir, 'tcl')` does not exist.  
**Fix:** Patch `PythonCopyStandardLib.py` before cmake runs using a Python one-liner in `build.bat`:
```python
# before:
shutil.copytree(tcl_dir, target_dir, dirs_exist_ok=True)
# after:
if os.path.exists(tcl_dir):
    shutil.copytree(tcl_dir, target_dir, dirs_exist_ok=True)
```

---

## 14. macOS — `std::wstring_convert` deprecated-declarations error from libc++

**Commit:** `e5017f4`  
**Platform:** osx-arm64  
**Error:** `error: 'wstring_convert<std::codecvt_utf8<wchar_t>>' is deprecated [-Werror,-Wdeprecated-declarations]` from inside `libc++`'s own `wstring_convert.h` header body, triggered via `third_party/CLI/CLI11.hpp:316`.  
**Root cause:** CLI11 2.4.2 uses `std::wstring_convert` (deprecated in C++17) and wraps its call site in `#pragma GCC diagnostic ignored "-Wdeprecated-declarations"`. However, libc++ emits the deprecation warning from inside its own function body definitions in `wstring_convert.h`, which are instantiated outside CLI11's pragma scope.  
**Fix:** Add `-Wno-deprecated-declarations` to clang-only `EXTRA_CXX_FLAGS` in `build.sh`.

---

## 15. Windows — `energyplus.exe` not on PATH after install

**Commits:** `c6fcc71`, `dc2959e`, `1745200`, `140643e`, `1edf54b`, `3949048`  
**Platform:** win-64  
**Error:** Test phase: `'energyplus.exe' is not recognized as an internal or external command` — rattler-build sets `CMAKE_INSTALL_PREFIX=%PREFIX%\Library` on Windows. EnergyPlus installs flat to `%PREFIX%\Library\energyplus.exe`, but conda's PATH includes `%PREFIX%\Library\bin`, not `%PREFIX%\Library\` itself.

**Fix history (several dead-ends before the correct solution):**

1. `c6fcc71`: wrapper with `cd /d "%PREFIX%\Library"` — baked build-time `%PREFIX%` into the wrapper, broken at install time.
2. `1745200`: changed `energyplus.exe` to `.\energyplus.exe` in the wrapper — still broken because `%PREFIX%` was hardcoded.
3. `140643e`: switched to `"%%~dp0..\energyplus.exe" %%*` — correct runtime-relative approach. `%~dp0` is a `cmd.exe` special variable that expands to the directory of the running `.bat` file at the moment of execution (not at build time). However, this was incorrectly diagnosed as broken and abandoned.
4. `1edf54b`: switched to `activate.d\energyplus.bat` that prepends `%CONDA_PREFIX%\Library` to PATH — works for activated environments but not for non-interactive use (subprocess calls, CI without activation, etc.).
5. `3949048`: changed the test to inline `set "PATH=%PREFIX%\Library;%PATH%"` — worked for CI tests but doesn't address user-facing non-interactive use.

**Correct fix (final):**
- `build.bat` writes `%PREFIX%\Library\bin\energyplus.bat` via **Python** (not `echo` in a `(...)` shell block). Using `echo` inside `(...)` causes `cmd.exe` to expand `%~dp0` at write time to the recipe directory, which rattler-build then replaces with its prefix placeholder — resulting in `%PREFIX%` literally in the wrapper at test time. Python writes the literal string `%~dp0` without expansion.
- The wrapper contains `"%~dp0..\energyplus.exe" %*`. At runtime, `%~dp0` expands to `Library\bin\`, so `%~dp0..` = `Library\` — correct at any install prefix.
- rattler-build test environments do NOT run conda activation, so `Library\bin` is not on PATH during tests. `recipe.yaml` calls the wrapper by full path on Windows: `"%PREFIX%\Library\bin\energyplus" --version`. `%PREFIX%` IS injected by rattler-build into test scripts.
- Normal user use (`conda activate` / `pixi shell`): `Library\bin` is on PATH, so `energyplus` works directly.
- `.pth` file uses relative `..\..\Library` (from site-packages) so `import pyenergyplus` works at any install path.
