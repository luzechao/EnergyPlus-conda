@echo off
:: EnergyPlus conda-forge build script (Windows)
::
:: Environment variables provided by rattler-build / conda-build:
::   SRC_DIR   - unpacked source tree
::   PREFIX    - conda install prefix
::   CPU_COUNT - number of CPUs available
::   CMAKE_ARGS - injected by conda-forge

setlocal EnableDelayedExpansion

set BUILD_DIR=%SRC_DIR%\..\build_energyplus
if not exist "%BUILD_DIR%" mkdir "%BUILD_DIR%"

cmake %CMAKE_ARGS% ^
  -GNinja ^
  -DCMAKE_BUILD_TYPE=Release ^
  -DCMAKE_INSTALL_PREFIX="%PREFIX%" ^
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

cmake --build "%BUILD_DIR%" --target install -j %CPU_COUNT%

if errorlevel 1 exit /b 1
