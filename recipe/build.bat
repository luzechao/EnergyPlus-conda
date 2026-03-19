@echo off
:: EnergyPlus conda-forge build script (Windows)
::
:: Environment variables provided by rattler-build / conda-build:
::   SRC_DIR    - unpacked source tree
::   PREFIX     - conda install prefix (contains the host environment)
::   BUILD_PREFIX - conda build environment prefix
::   CPU_COUNT  - number of CPUs available
::   CMAKE_ARGS - injected by conda-forge (includes install prefix etc.)
::
:: conda-forge's activation scripts set VSINSTALLDIR and try to call vcvars,
:: but the vcvars call can fail if vswhere returns unexpected results.
:: We call vcvars64.bat ourselves to ensure cl.exe is on PATH.

setlocal EnableDelayedExpansion

:: --- Find and activate MSVC ---
set "VSINSTALLDIR="
for /F "usebackq tokens=*" %%i in (`vswhere.exe -nologo -products * -latest -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath 2^>nul`) do (
    set "VSINSTALLDIR=%%i\"
)

:: Fallbacks in order: Enterprise, BuildTools, Community, Professional
if not defined VSINSTALLDIR if exist "C:\Program Files\Microsoft Visual Studio\2022\Enterprise\" (
    set "VSINSTALLDIR=C:\Program Files\Microsoft Visual Studio\2022\Enterprise\"
)
if not defined VSINSTALLDIR if exist "C:\Program Files (x86)\Microsoft Visual Studio\2022\Enterprise\" (
    set "VSINSTALLDIR=C:\Program Files (x86)\Microsoft Visual Studio\2022\Enterprise\"
)
if not defined VSINSTALLDIR if exist "C:\Program Files\Microsoft Visual Studio\2022\BuildTools\" (
    set "VSINSTALLDIR=C:\Program Files\Microsoft Visual Studio\2022\BuildTools\"
)
if not defined VSINSTALLDIR if exist "C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\" (
    set "VSINSTALLDIR=C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\"
)
if not defined VSINSTALLDIR if exist "C:\Program Files\Microsoft Visual Studio\2022\Community\" (
    set "VSINSTALLDIR=C:\Program Files\Microsoft Visual Studio\2022\Community\"
)

if not defined VSINSTALLDIR (
    echo ERROR: Could not find Visual Studio 2022 installation.
    exit /b 1
)

echo Using VS at: %VSINSTALLDIR%
call "%VSINSTALLDIR%VC\Auxiliary\Build\vcvars64.bat"
if errorlevel 1 (
    echo ERROR: vcvars64.bat failed.
    exit /b 1
)

set BUILD_DIR=%SRC_DIR%\..\build_energyplus
if not exist "%BUILD_DIR%" mkdir "%BUILD_DIR%"

:: CMAKE_ARGS already contains:
::   -DCMAKE_BUILD_TYPE=Release
::   -DCMAKE_INSTALL_PREFIX=%PREFIX%\Library
:: We add EnergyPlus-specific flags and force Ninja (since vcvars is active).
cmake %CMAKE_ARGS% ^
  -GNinja ^
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

cmake --build "%BUILD_DIR%" --config Release --target install -j %CPU_COUNT%

if errorlevel 1 exit /b 1



