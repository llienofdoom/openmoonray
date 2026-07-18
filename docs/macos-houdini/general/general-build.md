# General Build Reference

**Source:** https://docs.openmoonray.org/getting-started/installation/building-moonray/general_build/

---

## Overview

Open MoonRay is split across **19 Git repositories**. The `openmoonray` meta-repo ties them together via submodules and enables single-command builds. Linux (Rocky 9) is the primary platform; macOS is supported but secondary.

---

## Getting the Source

```bash
git lfs install
git clone --recurse-submodules https://github.com/OpenMoonRay/openmoonray.git
```

Git LFS is required — some files are LFS-tracked and will be corrupt stubs without it.

---

## Dependency Build

The `/building/` directory contains platform-specific CMake projects that compile all third-party deps via `ExternalProject_Add`. Use the `macOS/` subdirectory on Mac.

```bash
mkdir /build && cd /build
cmake /source/building/macOS
cmake --build . -- -j $(nproc)
```

Custom install root (recommended to keep things isolated):
```bash
cmake /source/building/macOS -DInstallRoot=~/moonray/dependencies
cmake --build . -- -j $(nproc)
```

### Full Dependency List

Built from source by the CMake dependency project:

| Dependency | Notes |
|---|---|
| CPPUNIT | Unit testing |
| JsonCpp | JSON parsing |
| libcurl | HTTP |
| libunwind | Stack unwinding |
| log4cplus | Logging |
| Lua | Scripting |
| OpenSubdiv | Subdivision surfaces |
| OpenVDB | Volumetrics |
| Boost | General utilities |
| Embree | Ray traversal (Intel) |
| OpenColorIO | Color management |
| OpenImageIO | Image I/O |
| OpenEXR | EXR image format |
| OpenImageDenoise | AI denoising |
| MicroHttpd | Embedded HTTP server |
| Qt5 | GUI (moonray_gui, arras_render) |
| TBB | Threading |
| pxr (USD) | Universal Scene Description |

### Optional Dependency Skip Flags

- `--nocuda` — skip CUDA (no GPU support needed)
- `--noqt` — skip Qt5 (no GUI apps needed)

---

## Building MoonRay

### Basic (deps in /usr/local)

```bash
cmake <openmoonray root>
cmake --build . -- -j $(nproc)
cmake --install . --prefix <install directory>
```

### Optional CMake Flags

| Flag | Effect |
|---|---|
| `-DBUILD_QT_APPS=NO` | Skip moonray_gui / arras_render (removes Qt5 dep) |
| `-DMOONRAY_USE_OPTIX=NO` | Disable GPU/XPU (removes CUDA/OptiX dep) |
| `-DCMAKE_BUILD_TYPE=Release` | Release build |
| `-DPYTHON_EXECUTABLE=python3` | Rocky 9 specific |
| `-DBOOST_PYTHON_COMPONENT_NAME=python39` | Rocky 9 specific |
| `-DABI_VERSION=0` | Rocky 9 specific |

---

## Locating Non-Standard Dependencies

### Via `<PACKAGE>_ROOT` env vars (single-dir packages)

```bash
export JSONCPP_ROOT=/custom/path/jsoncpp
export LIBCURL_ROOT=/custom/path/libcurl
```

Supported: `CPPUNIT_ROOT`, `JSONCPP_ROOT`, `LIBCURL_ROOT`, `LIBUNWIND_ROOT`, `LOG4CPLUS_ROOT`, `LUA_DIR`, `OPENSUBDIV_ROOT`, `OPENVDB_ROOT`, `OPTIX_ROOT`, `ISPC` (set to binary path)

### Via `CMAKE_PREFIX_PATH` (CMake-built packages)

For packages that ship a `Config.cmake`:

```bash
export CMAKE_PREFIX_PATH=/path/boost:/path/tbb:${CMAKE_PREFIX_PATH}
cmake <openmoonray root>
```

Applies to: Boost, CUDA, Embree, OpenColorIO, OpenImageIO, OpenEXR, OpenImageDenoise, MicroHttpd, Qt, TBB, pxr

---

## Environment Setup After Install

```bash
source <install dir>/scripts/setup.sh
```

### Variables Set by setup.sh

| Variable | Points To | Purpose |
|---|---|---|
| `PATH` | `release/bin` | Required for Arras |
| `RDL2_DSO_PATH` | `release/rdl2dso` | Plugin location |
| `REZ_MOONRAY_ROOT` | `release` | XPU mode shader location |
| `ARRAS_SESSION_PATH` | `release/sessions` | Session files |
| `MOONRAY_CLASS_PATH` | `release/shader_json` | Hydra shader descriptions |
| `PXR_PLUGINPATH_NAME` | `release/plugin/usd` | Hydra plugins |

**Note:** `PYTHONPATH` is NOT set by setup.sh. USD Python module warnings are harmless if you don't need Python USD access.

### JSON Export (for Hydra plugin)

```bash
bin/rdl2_json_exporter --out <output dir>/ --sparse
```

Trailing slash on output dir is required.

---

## Verification / Smoke Tests

```bash
# Command-line render
moonray -in /source/testdata/rectangle.rdla -out /tmp/rectangle.exr

# GUI render (if built with Qt)
moonray_gui -in /source/testdata/rectangle.rdla -out /tmp/rectangle.exr

# Hydra / USD render
hd_render -in /source/testdata/sphere.usd -out /tmp/sphere.exr
```

---

## GPU / XPU Support Notes

- Requires OptiX **7.6 exactly** — newer versions are incompatible.
- Download OptiX 7.6 headers from NVIDIA (requires EULA acceptance).
- Place in `/usr/local/include/` or set `OPTIX_ROOT` env var.
- GPU device passthrough may not work in Docker; build with `-DMOONRAY_USE_OPTIX=NO` in containers.

---

## CMake Presets

Complex flag sets can be captured in `CMakeUserPresets.json` (user-specific, not version-controlled) or `CMakePresets.json`.
See: https://cmake.org/cmake/help/v3.23/manual/cmake-presets.7.html

---

## Building Repos Separately (Advanced)

Build order: `scene_rdl2` → `mcrt_denoise` / others → `moonray`

Required env setup before each:
```bash
export CMAKE_MODULES_ROOT=<path to cmake_modules repo>
export CMAKE_PREFIX_PATH=<scene_rdl2 install>:${CMAKE_PREFIX_PATH}
export PATH=<scene_rdl2 install>/bin:${PATH}
```

Build command:
```bash
cmake <repo root> \
  -DCMAKE_MODULE_PATH=${CMAKE_MODULES_ROOT}/cmake \
  -DPYTHON_EXECUTABLE=python3 \
  -DBOOST_PYTHON_COMPONENT_NAME=python39 \
  -DABI_VERSION=0
cmake --build . -- -j $(nproc)
cmake --install . --prefix <install dir>
```
