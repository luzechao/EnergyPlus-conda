@echo off
:: EnergyPlus rattler-build script (Windows / win-64, MinGW64 toolchain)
::
:: With c_stdlib=m2w64-msvcrt, rattler-build activates the MinGW64 compiler
:: environment (m2w64_c, m2w64_cxx, gfortran_win-64).  Compilers are:
::   CC  = x86_64-w64-mingw32-gcc.exe
::   CXX = x86_64-w64-mingw32-g++.exe
::   FC  = x86_64-w64-mingw32-gfortran.exe
::
:: We pass them explicitly to CMake to avoid any MSVC settings that may be
:: baked into CMAKE_ARGS by the conda-forge sysroot logic.

setlocal EnableDelayedExpansion

echo === Build environment ===
echo SRC_DIR      = %SRC_DIR%
echo PREFIX       = %PREFIX%
echo BUILD_PREFIX = %BUILD_PREFIX%
echo CPU_COUNT    = %CPU_COUNT%
echo CC           = %CC%
echo CXX          = %CXX%
echo FC           = %FC%
echo CMAKE_ARGS   = %CMAKE_ARGS%

set BUILD_DIR=%SRC_DIR%\..\build_energyplus
if not exist "%BUILD_DIR%" mkdir "%BUILD_DIR%"

:: Explicitly pass MinGW compilers so CMake does not accidentally pick up cl.exe.
:: CMAKE_ARGS still provides -DCMAKE_INSTALL_PREFIX and related flags.
cmake %CMAKE_ARGS% ^
  -GNinja ^
  -DCMAKE_BUILD_TYPE=Release ^
  -DCMAKE_C_COMPILER="%CC%" ^
  -DCMAKE_CXX_COMPILER="%CXX%" ^
  -DCMAKE_Fortran_COMPILER="%FC%" ^
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
