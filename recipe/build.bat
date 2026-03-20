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

cmake --build "%BUILD_DIR%" --config Release --target install -j %CPU_COUNT%

if errorlevel 1 exit /b 1
