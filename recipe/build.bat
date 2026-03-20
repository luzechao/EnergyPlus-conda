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
:: The patch script is base64-encoded to avoid all cmd.exe quoting/special-char
:: issues. At runtime Python decodes it, substitutes the real SRC_DIR path, and
:: execs it directly — no temp file needed, no heredoc fragility.
:: ---------------------------------------------------------------------------
"%PREFIX%\python.exe" -c "import base64; exec(base64.b64decode(b'aW1wb3J0IHBhdGhsaWIsIG9zCnAgPSBwYXRobGliLlBhdGgocidQTEFDRUhPTERFUi9jbWFrZS9QeXRob25Db3B5U3RhbmRhcmRMaWIucHknKQp0ID0gcC5yZWFkX3RleHQoKQpvbGQgPSAnICAgIHNodXRpbC5jb3B5dHJlZSh0Y2xfZGlyLCB0YXJnZXRfZGlyLCBkaXJzX2V4aXN0X29rPVRydWUpJwpuZXcgPSAnICAgIGlmIG9zLnBhdGguZXhpc3RzKHRjbF9kaXIpOicgKyBjaHIoMTApICsgJyAgICAgICAgc2h1dGlsLmNvcHl0cmVlKHRjbF9kaXIsIHRhcmdldF9kaXIsIGRpcnNfZXhpc3Rfb2s9VHJ1ZSknCnAud3JpdGVfdGV4dCh0LnJlcGxhY2Uob2xkLCBuZXcpKQo=').decode().replace('PLACEHOLDER', r'%SRC_DIR%'))"
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
  -DBUILD_PACKAGE=ON ^
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
:: Use base64-encoded script so rattler-build prefix replacement cannot mangle
:: the wrapper contents or the file path — PLACEHOLDER is substituted at runtime.
"%PREFIX%\python.exe" -c "import base64; exec(base64.b64decode(b'aW1wb3J0IG9zCmJhdF9wYXRoID0gb3MucGF0aC5qb2luKHInUExBQ0VIT0xERVInLCAnTGlicmFyeScsICdiaW4nLCAnZW5lcmd5cGx1cy5iYXQnKQpvcy5tYWtlZGlycyhvcy5wYXRoLmRpcm5hbWUoYmF0X3BhdGgpLCBleGlzdF9vaz1UcnVlKQp3aXRoIG9wZW4oYmF0X3BhdGgsICd3JykgYXMgZjoKICAgIGYud3JpdGUoJ0BlY2hvIG9mZicgKyBjaHIoMTMpK2NocigxMCkgKyAnc2V0ICJfZXA9JX5kcDAuLlxlbmVyZ3lwbHVzLmV4ZSInICsgY2hyKDEzKStjaHIoMTApICsgJyIlX2VwJSIgJSonICsgY2hyKDEzKStjaHIoMTApKQo=').decode().replace('PLACEHOLDER', r'%PREFIX%'))"
if errorlevel 1 exit /b 1

:: 2. pyenergyplus .pth file
:: rattler-build injects %SP_DIR% = the site-packages dir that will be packaged.
:: Use base64-encoded script to avoid rattler-build mangling %SP_DIR% path and
:: to avoid trailing-space bug from cmd.exe echo redirect.
"%PREFIX%\python.exe" -c "import base64; exec(base64.b64decode(b'aW1wb3J0IG9zCnB0aCA9IG9zLnBhdGguam9pbihyJ1BMQUNFSE9MREVSJywgJ2VuZXJneXBsdXMucHRoJykKb3MubWFrZWRpcnMob3MucGF0aC5kaXJuYW1lKHB0aCksIGV4aXN0X29rPVRydWUpCndpdGggb3BlbihwdGgsICd3JykgYXMgZjoKICAgIGYud3JpdGUoJy4uLy4uL0xpYnJhcnkKJykK').decode().replace('PLACEHOLDER', r'%SP_DIR%'))"
if errorlevel 1 exit /b 1
