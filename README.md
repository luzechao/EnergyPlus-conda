# EnergyPlus-conda

Conda packaging for [EnergyPlus](https://energyplus.net) — the U.S. Department of Energy's whole-building energy simulation program.

Packages are built with [rattler-build](https://github.com/prefix-dev/rattler-build) and published to the **[natlabrockies](https://prefix.dev/channels/natlabrockies)** channel on [prefix.dev](https://prefix.dev).

## Installing

### With pixi

```bash
pixi add --channel https://prefix.dev/natlabrockies energyplus
```

### With conda / mamba

```bash
conda install -c https://prefix.dev/natlabrockies energyplus
# or
mamba install -c https://prefix.dev/natlabrockies energyplus
```

## What's included

| Component | Description |
|-----------|-------------|
| `energyplus` | Main simulation binary |
| `pyenergyplus` | Python API (`from pyenergyplus.api import EnergyPlusAPI`) |
| IDD / data files | Energy+.idd and all required data files |
| `ReadVarEso` | Post-processing utility (built with Fortran) |

## Supported platforms

| Platform | Status |
|----------|--------|
| linux-64 | ✅ |
| osx-64 | ✅ |
| osx-arm64 | ✅ |
| win-64 | ✅ |

## Current version

EnergyPlus **25.2.0** — source: [NatLabRockies/EnergyPlus @ v25.2.0](https://github.com/NatLabRockies/EnergyPlus/tree/v25.2.0)

## Repository structure

```
recipe/
  recipe.yaml              # rattler-build v1 recipe (CEP-13 format)
  build.sh                 # CMake build script (Linux / macOS)
  build.bat                # CMake build script (Windows)
  conda_build_config.yaml  # Variant config for local builds
.github/workflows/
  build.yml                # CI: build all platforms, upload to prefix.dev
pixi.toml                  # Local dev environment (pixi)
```

## Building locally

Install [pixi](https://pixi.sh), then:

```bash
# Build for the current platform
pixi run build

# Build with verbose CMake output
pixi run build-verbose
```

The built `.conda` package will appear in `output/`.

## CI / publishing

GitHub Actions builds all four platforms on every push to `main` and uploads to the `natlabrockies` prefix.dev channel via OIDC trusted publishing (no API key stored as a secret).

Pull requests trigger a build but do **not** upload.

## Key CMake flags

| Flag | Value | Reason |
|------|-------|--------|
| `BUILD_FORTRAN` | `ON` | Builds `ReadVarEso` |
| `OPENGL_REQUIRED` | `OFF` | No GUI needed |
| `BUILD_PACKAGE` | `ON` | Enables CPack install rules |
| `LINK_WITH_PYTHON` | `ON` | Enables `pyenergyplus` API |
| `DOCUMENTATION_BUILD` | `DoNotBuild` | Skips LaTeX docs |
| `BUILD_TESTING` | `OFF` | Skips unit tests during packaging |

## License

EnergyPlus is released under a custom DOE/LBNL/UIUC BSD-style license (`LicenseRef-EnergyPlus`). See [LICENSE.txt](https://github.com/NatLabRockies/EnergyPlus/blob/v25.2.0/LICENSE.txt) in the upstream repository.

This packaging repository is maintained by [@luzechao](https://github.com/luzechao) / [NatLabRockies](https://github.com/NatLabRockies).
