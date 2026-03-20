@echo off
:: EnergyPlus rattler-build script (Windows / win-64)
::
:: Uses Visual Studio 17 2022 for C/C++ (MSVC) and the msys64 gfortran
:: that is pre-installed on all GitHub windows-2022 runners, matching
:: the approach used by the upstream EnergyPlus release_windows.yml CI.
::
:: rattler-build injects CMAKE_ARGS with -DCMAKE_INSTALL_PREFIX=... pointing
:: at %PREFIX%\Library (the Windows conda Library tree).  We do NOT pass
:: -DCMAKE_C_COMPILER or -DCMAKE_CXX_COMPILER so that CMake auto-detects
:: the MSVC toolchain via the VS generator.  Fortran is provided by the
:: msys64 MinGW64 gfortran on PATH.

setlocal EnableDelayedExpansion

echo === Build environment ===
echo SRC_DIR      = %SRC_DIR%
echo PREFIX       = %PREFIX%
echo BUILD_PREFIX = %BUILD_PREFIX%
echo CPU_COUNT    = %CPU_COUNT%
echo CMAKE_ARGS   = %CMAKE_ARGS%

:: msys64 gfortran is at C:\msys64\mingw64\bin on windows-2022 runners.
:: Use forward slashes — CMake interprets backslashes as escape sequences.
:: We pass gfortran via MINGW_GFORTRAN (not CMAKE_Fortran_COMPILER) because
:: cmake_add_fortran_subdirectory requires that check_language(Fortran) returns
:: no compiler under the VS generator; it then invokes MinGW gfortran as an
:: ExternalProject.  Passing CMAKE_Fortran_COMPILER directly causes CMake to
:: try to test it through the VS build system, which always fails.
set "FC=C:\msys64\mingw64\bin\x86_64-w64-mingw32-gfortran.exe"
if not exist "%FC%" (
    echo ERROR: gfortran not found at %FC%
    exit /b 1
)
set "MINGW_GFORTRAN=C:/msys64/mingw64/bin/x86_64-w64-mingw32-gfortran.exe"
echo MINGW_GFORTRAN = %MINGW_GFORTRAN%

set "BUILD_DIR=%SRC_DIR%\..\build_energyplus"
if not exist "%BUILD_DIR%" mkdir "%BUILD_DIR%"

:: ---------------------------------------------------------------------------
:: Patch PythonCopyStandardLib.py to guard the Tcl/Tk copy behind an existence
:: check.  EnergyPlus unconditionally copies %PREFIX%\tcl during the build of
:: energyplusapi.dll, but in the conda h_env tcl is a separate package and that
:: directory does not exist under the Python prefix.
::
:: Write the patch script to a temp file first to avoid cmd.exe quoting issues
:: with double-quotes inside a -c "..." string.
:: ---------------------------------------------------------------------------
(
  echo import pathlib
  echo p = pathlib.Path(r'%SRC_DIR%\cmake\PythonCopyStandardLib.py'^)
  echo t = p.read_text(^)
  echo old = '    shutil.copytree(tcl_dir, target_dir, dirs_exist_ok=True^)'
  echo line1 = '    if os.path.exists(tcl_dir)' + chr(58^) + ''
  echo line2 = '        shutil.copytree(tcl_dir, target_dir, dirs_exist_ok=True^)'
  echo new = line1 + chr(10^) + line2
  echo p.write_text(t.replace(old, new^)^)
) > "%TEMP%\patch_pylib.py"
"%PREFIX%\python.exe" "%TEMP%\patch_pylib.py"
if errorlevel 1 exit /b 1

:: Use Visual Studio 17 2022 generator for C/C++; gfortran for Fortran.
:: CMAKE_ARGS provides -DCMAKE_INSTALL_PREFIX=%PREFIX%\Library and path hints.
cmake %CMAKE_ARGS% ^
  -G "Visual Studio 17 2022" -A x64 ^
  -DMINGW_GFORTRAN="%MINGW_GFORTRAN%" ^
  -DCMAKE_BUILD_TYPE=Release ^
  -DBUILD_FORTRAN=ON ^
  -DOPENGL_REQUIRED=OFF ^
  -DDOCUMENTATION_BUILD=DoNotBuild ^
  -DBUILD_TESTING=OFF ^
  -DBUILD_PACKAGE=OFF ^
  -DLINK_WITH_PYTHON=ON ^
  -DPython_ROOT_DIR="%PREFIX%" ^
  -DPython_FIND_STRATEGY=LOCATION ^
  -B "%BUILD_DIR%" ^
  -S "%SRC_DIR%"

if errorlevel 1 exit /b 1

cmake --build "%BUILD_DIR%" --config Release -j %CPU_COUNT%
if errorlevel 1 exit /b 1

cmake --install "%BUILD_DIR%" --config Release --prefix "%PREFIX%\Library"

if errorlevel 1 exit /b 1

:: ---------------------------------------------------------------------------
:: Post-install: wire up conda-friendly paths (Windows)
::
:: On Windows, rattler-build sets CMAKE_INSTALL_PREFIX=%PREFIX%\Library so
:: EnergyPlus installs everything flat to %PREFIX%\Library\ (energyplus.exe,
:: DLLs, IDD files, pyenergyplus\, etc.).
:: conda's PATH includes %PREFIX%\Library\bin but NOT %PREFIX%\Library\ itself.
::
:: Strategy:
:: 1. Create %PREFIX%\Library\bin\energyplus.bat — a thin wrapper that invokes
::    energyplus.exe relative to its own location using %~dp0 (cmd.exe runtime
::    variable that expands to the directory of the running .bat file).
::    %~dp0 always has a trailing backslash, so %~dp0..\energyplus.exe resolves
::    to %PREFIX%\Library\energyplus.exe regardless of install prefix.
::    This works in activated envs, non-interactive scripts, and subprocesses.
::
:: 2. Drop energyplus.pth in site-packages so `import pyenergyplus` works.
:: ---------------------------------------------------------------------------

:: 1. Wrapper bat in Library\bin\ (always on conda PATH)
:: Use Python to write the file so cmd.exe does not expand %~dp0 at write time.
:: The wrapper uses %~dp0 (cmd.exe runtime variable = directory of the .bat file)
:: to locate energyplus.exe one level up: Library\bin\..\energyplus.exe
if not exist "%PREFIX%\Library\bin" mkdir "%PREFIX%\Library\bin"
"%PREFIX%\python.exe" -c "open(r'%PREFIX%\Library\bin\energyplus.bat', 'w').write('@echo off\r\n\"%~dp0..\\energyplus.exe\" %*\r\n')"

:: 2. pyenergyplus .pth file
:: On Windows conda, site-packages is at %PREFIX%\Lib\site-packages.
:: EnergyPlus is at %PREFIX%\Library, so relative path is "..\..\Library".
:: Python resolves relative .pth entries relative to site-packages.
for /f "delims=" %%i in ('"%PREFIX%\python.exe" -c "import site; print(site.getsitepackages()[0])"') do set "SITE_PACKAGES=%%i"
echo ..\..\Library> "%SITE_PACKAGES%\energyplus.pth"
