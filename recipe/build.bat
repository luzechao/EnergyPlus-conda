@echo off
:: EnergyPlus rattler-build script (Windows / win-64)
::
:: rattler-build activates compiler environments before calling this script.
:: CMAKE_ARGS is injected automatically and includes:
::   -DCMAKE_INSTALL_PREFIX=%PREFIX%\Library  (Windows conda convention)
::   compiler/linker flags, sysroot settings, etc.
::
:: DO NOT call vcvars64.bat here — the conda-forge compiler activation already
:: sets CC, CXX, FC and puts cl.exe / flang on PATH.

setlocal EnableDelayedExpansion

echo === Build environment ===
echo SRC_DIR    = %SRC_DIR%
echo PREFIX     = %PREFIX%
echo BUILD_PREFIX = %BUILD_PREFIX%
echo CPU_COUNT  = %CPU_COUNT%
echo CC  = %CC%
echo CXX = %CXX%
echo FC  = %FC%
echo CMAKE_ARGS = %CMAKE_ARGS%

set BUILD_DIR=%SRC_DIR%\..\build_energyplus
if not exist "%BUILD_DIR%" mkdir "%BUILD_DIR%"

:: CMAKE_ARGS already contains -DCMAKE_INSTALL_PREFIX and compiler flags.
:: -GNinja requires that ninja.exe is on PATH (it is, from the build env).
cmake %CMAKE_ARGS% ^
  -GNinja ^
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

cmake --build "%BUILD_DIR%" --config Release --target install -j %CPU_COUNT%

if errorlevel 1 exit /b 1



