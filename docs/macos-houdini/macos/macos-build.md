# macOS Build Guide

**Sources:**
- https://docs.openmoonray.org/getting-started/installation/building-moonray/macOS_build/
- https://github.com/OpenMoonRay/openmoonray (repo — `building/macOS/macOS_build.md`, `CMakeMacOSPresets.json`, `building/macOS/CMakeLists.txt`)

---

## Platform Requirements

| Item | Requirement |
|---|---|
| Architecture | Apple Silicon (M-series) only — no x86_64 |
| macOS 14.6 Sonoma | Xcode 15.4 |
| macOS 15.6 Sequoia | Xcode 16.4 |
| macOS 26.0 Tahoe | Xcode 26.0 + `xcodebuild -downloadComponent MetalToolchain` |
| CMake | 3.26.5 or later (universal binary from cmake.org) |
| Git | With LFS support |

**CMake install:**
```bash
# Download universal binary DMG from:
# https://github.com/Kitware/CMake/releases/download/v3.26.5/cmake-3.26.5-macos-universal.dmg
sudo "/Applications/CMake.app/Contents/bin/cmake-gui" --install
```

**Homebrew is intentionally NOT used.** The dep build system explicitly passes
`-DCMAKE_IGNORE_PATH=/opt/homebrew` and `-DCMAKE_IGNORE_PREFIX_PATH=/opt/homebrew`
to every dependency. Everything is compiled from source into the isolated installs dir.

**Python source:** Xcode's bundled Python 3.9, not Homebrew:
```
/Applications/Xcode.app/Contents/Developer/Library/Frameworks/Python3.framework/Versions/3.9/
```

---

## Directory Layout

```
/Applications/MoonRay/
├── installs/              ← final install target (keep after build)
│   ├── bin/
│   ├── lib/
│   └── include/
├── build/                 ← MoonRay build dir (delete after install)
├── build-deps/            ← dependency build dir (delete after install)
└── source/
    └── openmoonray/       ← cloned repo
```

Create it all at once:
```bash
mkdir -p /Applications/MoonRay/{installs,build,build-deps,source}
mkdir -p /Applications/MoonRay/installs/{bin,lib,include}
```

---

## Step-by-Step Build

### Step 1 — Get the source

```bash
git lfs install
cd /Applications/MoonRay/source
git clone --recurse-submodules https://github.com/OpenMoonRay/openmoonray.git
```

### Step 2 — Create symlinks

```bash
cd /Applications/MoonRay
ln -s source/openmoonray/building .
ln -s source/openmoonray .
```

These symlinks let the preset paths resolve correctly (`${sourceParentDir}/installs` etc.).

### Step 3 — Build dependencies

```bash
cd /Applications/MoonRay/build-deps
cmake ../building/macOS
cmake --build . -- -j8
```

The `-j8` flag is passed through to the underlying make, parallelising each dep's own compilation. The dep chain itself is **serial** by design (each dep has `DEPENDS` on the previous) — this is intentional and cannot be parallelised.

**Houdini variant:** skip USD (Houdini provides its own):
```bash
cmake -DNOUSD=1 ../building/macOS
```

> **Warning:** If switching between USD and non-USD dep builds, delete `build-deps/` and `installs/` first. Leftover USD artifacts will cause linker failures in Step 4.

**Known issues during dep build** — see `build-issues.md` for full detail:
- Issue 1 & 3: MicroHttpd autotools version mismatch + missing `makeinfo` — requires `brew install texinfo` before building and `--disable-doc` in configure
- Issue 2: Boost patch re-triggers on resume — add `|| true` to patch command in generated `build.make`

**After the dep build completes, fix dylib portability:**

Several autotools deps (OpenSSL, libcurl, log4cplus, etc.) bake `..` path components from
the build directory into their dylib install names. This causes `dyld` failures on any
machine that lacks the `source/` directory tree. Run the fixup script once:

```bash
cd /Users/llien/Dropbox/Projects/dev/moonray/docs
./fix-dylib-install-names.sh
```

This rewrites 8 dylib install names and all `LC_LOAD_DYLIB` references across ~860+ binaries
and dylibs. Idempotent — safe to re-run. Full details in `build-issues.md` Issue 0.

> **Note:** `building/macOS/CMakeLists.txt` is patched with `get_filename_component(ABSOLUTE)`
> to prevent dirty install names on future clean dep builds. The fixup script remains
> necessary for the existing installation and as a safety net.

### Step 4 — Create FreeType symlinks

Required before building MoonRay. FreeType installs headers under `include/freetype2/freetype/` but MoonRay code uses `<freetype/freetype.h>`:

```bash
ln -sf /Applications/MoonRay/installs/include/freetype2/freetype \
       /Applications/MoonRay/installs/include/freetype
ln -sf /Applications/MoonRay/installs/include/freetype2/ft2build.h \
       /Applications/MoonRay/installs/include/ft2build.h
```

### Step 5 — Configure MoonRay

`cmake find_package(Python)` will pick up Homebrew Python 3.14 despite `CMAKE_IGNORE_PATH` — Boost.Python was built against Python 3.9, so the MoonRay configure must also target 3.9. Pass the Xcode Python 3.9 paths explicitly:

```bash
cd /Applications/MoonRay/openmoonray
PYFW=/Applications/Xcode_16.4.app/Contents/Developer/Library/Frameworks/Python3.framework/Versions/3.9
cmake --preset macos-release \
  -DPython_ROOT_DIR="$PYFW" \
  -DPython_EXECUTABLE="$PYFW/bin/python3.9" \
  -DPython_INCLUDE_DIR="$PYFW/Headers" \
  -DPython_LIBRARY="$PYFW/lib/libpython3.9.dylib" \
  -DPYTHON_EXECUTABLE="$PYFW/bin/python3.9"
```

**Houdini variant:**
```bash
cmake --preset macos-houdini-release  # (Python flags may also be needed)
```

### Step 6 — Build MoonRay

```bash
cmake --build --preset macos-release
```

Uses the **Xcode generator** (not Makefiles). Build output goes to `/Applications/MoonRay/build/`.

**Houdini variant:**
```bash
cmake --build --preset macos-houdini-release
```

### Step 7 — Install MoonrayShader Python stubs

Suppresses `ModuleNotFoundError: No module named 'pxr.MoonrayShaderParser'` warnings from
standalone USD tools (`hd_usd2rdl`, `hd_render`, etc.). The stub `__init__.py` files exist
in source but are not installed by cmake:

```bash
PXR=/Applications/MoonRay/installs/lib/python/pxr
SRC=/Applications/MoonRay/source/openmoonray/moonray/hydra/moonray_sdr_plugins

mkdir -p "$PXR/MoonrayShaderParser" "$PXR/MoonrayShaderDiscovery"
cp "$SRC/moonrayShaderParser/__init__.py"   "$PXR/MoonrayShaderParser/__init__.py"
cp "$SRC/moonrayShaderDiscovery/__init__.py" "$PXR/MoonrayShaderDiscovery/__init__.py"
```

### Step 8 — Run smoke tests

```bash
source /Applications/MoonRay/installs/openmoonray-standalone/scripts/setup.sh
cd /Applications/MoonRay/openmoonray/testdata

# Headless CPU+GPU render (confirmed working):
moonray -exec_mode xpu -in rectangle.rdla -out /tmp/rectangle.exr

# GUI (opens render window):
moonray_gui -exec_mode xpu -info -in curves.rdla

# USD scene:
hd_render -in sphere.usd -out /tmp/sphere.exr
```

### Step 9 — Cleanup (optional, reclaims ~12.8 GB)

```bash
rm -rf /Applications/MoonRay/{build,build-deps}
```

---

## CMake Presets (from `CMakeMacOSPresets.json`)

### Configure presets

| Preset name | Use |
|---|---|
| `macos-release` | Standard standalone build |
| `macos-houdini-release` | Build against Houdini's USD |

### Key env vars set by the `macos-environment` hidden preset

| Variable | Value |
|---|---|
| `DEPS_ROOT` | `${sourceParentDir}/installs` |
| `BUILD_DIR` | `${sourceParentDir}/build` |
| `Boost_ROOT` | `$DEPS_ROOT` |
| `ISPC` | `$DEPS_ROOT/bin/ispc` |
| `PXR_USD_LOCATION` | `$DEPS_ROOT` |
| `PXR_INCLUDE_DIRS` | `$DEPS_ROOT/include` |
| `OIIO_PYTHON` | `$DEPS_ROOT/lib/python3.9/site-packages` |
| `CMAKE_PREFIX_PATH` | `$DEPS_ROOT` |

### Houdini extra env vars (`macos-environment-houdini`)

| Variable | Default value |
|---|---|
| `HOUDINI_INSTALL_DIR` | `/Applications/Houdini/Houdini20.5.939` ← **your install** (repo default was 20.0.751) |
| `PXR_LIB_PREFIX` | `$HOUDINI_INSTALL_DIR/.../Libraries` |
| `PXR_INCLUDE_PREFIX` | `$HOUDINI_INSTALL_DIR/.../toolkit/include` |
| `PXR_BOOST_PYTHON_LIB` | `libhboost_python39-mt-a64.dylib` |
| `MOONRAY_USE_HOUDINI` | `TRUE` |

Generator used: **Xcode** (not Makefile or Ninja).

---

## Dependency Versions (from `building/macOS/CMakeLists.txt`)

All deps are built from source or downloaded as pre-built binaries. Homebrew is explicitly excluded from all dep searches.

| Dependency | Version / Tag | Notes |
|---|---|---|
| Blosc | 1.21.6 (`616f4b7`) | macOS 26 Tahoe tag |
| Boost | 1.78.0 | Built with clang toolset |
| JsonCpp | 1.9.5 | |
| Lua | 5.4.4 | |
| libmicrohttpd | 0.9.72 | |
| OpenSubdiv | v3.5.0 | No PTEX/OMP/TBB/CUDA/OpenCL |
| OpenEXR | v2.5.7 | Static build |
| TBB | 2020_U3 | Built with `arch=arm64` |
| OpenVDB | v9.1.0 | |
| log4cplus | 2.0.5 | |
| CppUnit | 1.15.1 | |
| Random123 | v1.14.0 | Header-only |
| ISPC | v1.20.0 | **Pre-built arm64 binary** (not compiled) |
| Embree | v4.2.0 | `EMBREE_MAX_ISA=NEON`, fully native arm64 |
| OpenColorIO | v2.0.2 | No SSE, no Python bindings |
| TIFF | v4.0.7 | |
| libjpeg-turbo | 2.0.1 | `WITH_SIMD=FALSE` |
| pybind11 | v2.13.6 | |
| OpenImageIO | 2.3.20.0 | With Python, without Qt |
| OpenImageDenoise | v2.2.0 | **Pre-built arm64 macOS binary** (not compiled) |
| Qt5 | 5.12.12 | Built from source, `arm64` only |
| USD | v22.11 | Python 3.9 from Xcode, skippable with `-DNOUSD=1` |
| libuuid | 1.0.3 | |
| OpenSSL | 3.0.8 | 3.1.0 has a bug on Apple Silicon — intentionally downgraded |
| libcurl | 7.88.1 | `--with-secure-transport` |
| FreeType | 2.13.2 | |
| GLFW | 3.4 | Shared, no examples/tests |

---

## Apple Silicon Notes

- Embree builds natively for arm64 with NEON ISA (`EMBREE_MAX_ISA=NEON`, `EMBREE_ISA_NEON=ON`) — no Rosetta.
- TBB explicitly built with `arch=arm64`.
- ISPC and OpenImageDenoise are downloaded as pre-built arm64 binaries.
- OpenSSL 3.1.0 is known-broken on Apple Silicon; the build uses 3.0.8 instead.
- GPU/XPU mode: **confirmed working on M1 Pro via Metal** (verified 2026-05-05). MoonRay loads `shaders/default.metallib`, builds a BVH on-device, and renders with `Using GPU: Apple M1 Pro`. CUDA is not involved.

---

## Houdini Build (verified 2026-05-05)

### Prerequisites

The `macos-release` preset now installs directly to `openmoonray-standalone`, so no rename
step is needed — the standalone and Houdini builds go to separate directories from the start.

### Files to edit before configuring

Before building the Houdini variant, edit these three files:

| File | Edit |
|---|---|
| `source/openmoonray/CMakeMacOSPresets.json` | `HOUDINI_INSTALL_DIR` → `/Applications/Houdini/Houdini20.5.939`; `PXR_BOOST_PYTHON_LIB` → `libhboost_python311-mt-a64.dylib`; `CMAKE_PREFIX_PATH` → `$env{PREFIX_PXR};$env{DEPS_ROOT}` (PREFIX_PXR first) |
| `source/openmoonray/scripts/macOS/setupHoudini.sh` | `HOUDINI_PATH` → `/Applications/Houdini/Houdini20.5.939` |
| `source/openmoonray/building/macOS/pxr-houdini/pxrTargets.cmake` | `HPYTHONLIB` and `HPYTHONINC` — update to Python 3.11 paths |
| `source/openmoonray/building/macOS/pxr-houdini/pxrTargets-release.cmake` | `usdRiImaging` entry: change `libpxr_usdRiImaging.dylib` → `libpxr_usdRiPxrImaging.dylib` (Houdini 20.5 rename) |

**Note on `PXR_BOOST_PYTHON_LIB`:** The preset default assumes `libhboost_python39-mt-a64.dylib`
(Houdini 20.0). **Houdini 20.5.939 ships `libhboost_python311-mt-a64.dylib`** — update
`PXR_BOOST_PYTHON_LIB` in `CMakeMacOSPresets.json` to match.

**Note on `CMAKE_PREFIX_PATH` order:** The Houdini preset must list `$env{PREFIX_PXR}` before
`$env{DEPS_ROOT}`. If `DEPS_ROOT` comes first, cmake finds the standalone USD 22.11
`pxrConfig.cmake` in `installs/` instead of Houdini's USD 24.3 stubs in `pxr-houdini/`.
This causes `hd_moonray.dylib` to link against `libusd_*` (wrong) instead of `libpxr_*`
(Houdini's USD), making the render delegate fail to load (see Issue 9).

### Configure and build

No dep rebuild needed — all deps reuse the existing `installs/` tree. Clear the build dir first (it has the standalone cmake cache), then configure with Houdini's Python 3.11:

```bash
rm -rf /Applications/MoonRay/build && mkdir /Applications/MoonRay/build

cd /Applications/MoonRay/openmoonray
PYFW=/Applications/Houdini/Houdini20.5.939/Frameworks/Houdini.framework/Versions/Current/Resources/Frameworks/Python.framework/Versions/3.11
cmake --preset macos-houdini-release \
  -DPython_ROOT_DIR="$PYFW" \
  -DPython_EXECUTABLE="$PYFW/bin/python3.11" \
  -DPython_INCLUDE_DIR="$PYFW/include/python3.11" \
  -DPython_LIBRARY="$PYFW/lib/libpython3.11.dylib" \
  -DPYTHON_EXECUTABLE="$PYFW/bin/python3.11"

cmake --build --preset macos-houdini-release
```

Installs to `installs/openmoonray-houdini/`.

### Running

```bash
# Standalone renderer
source /Applications/MoonRay/installs/openmoonray-standalone/scripts/setup.sh
moonray -in rectangle.rdla -out /tmp/out.exr

# Houdini variant — use setupHoudini.sh only, NOT setup.sh
# setupHoudini.sh internally sources setup.sh and strips the Python 3.9 pxr
# paths that would otherwise crash Houdini's Python 3.11 (see Issue 8)
source /Applications/MoonRay/installs/openmoonray-houdini/scripts/macOS/setupHoudini.sh
houdini
```

Houdini smoke test: Desktop → Solaris → scene view set to "stage" → place sphere → viewport → Persp → Moonray.

---

## Distributing to Another Machine

To copy MoonRay to a second Mac (same macOS version and architecture), copy these
directories from `installs/`:

| Directory | Required | Notes |
|---|---|---|
| `installs/lib/` | ✅ | Qt frameworks, all dep dylibs |
| `installs/plugins/` | ✅ | Qt platform plugin (`cocoa`) and image-format plugins — missing this causes `moonray_gui` to crash immediately |
| `installs/openmoonray-standalone/` | ✅ (standalone) | Binaries, rdl2dso, shader_json, scripts |
| `installs/openmoonray-houdini/` | ✅ (Houdini) | Houdini plugin and hydra dylibs |
| `installs/include/` | ❌ | Build-time headers only |
| `installs/bin/` | ❌ | Dep build tools (cmake, ninja, etc.) — not needed at runtime |

Minimum for standalone (`moonray`, `moonray_gui`, headless rendering):
```
installs/lib/
installs/plugins/
installs/openmoonray-standalone/
```

Also run `docs/fix-dylib-install-names.sh` before copying to ensure no `..` path segments
remain in dylib install names (see `build-issues.md` Issue 0). This is a no-op if the
`building/macOS/CMakeLists.txt` patch was applied on the original build.

The receiving machine also needs 4 Homebrew packages that `libcurl`, `libmicrohttpd`, and
`libfreetype` link against at runtime (these are not bundled in `installs/`):

```bash
brew install brotli gnutls libidn2 libnghttp2
```

Then source `setup.sh` as usual — `QT_QPA_PLATFORM_PLUGIN_PATH` and `QT_PLUGIN_PATH` are
set automatically (see `build-issues.md` Issue 17):

```bash
source /Applications/MoonRay/installs/openmoonray-standalone/scripts/setup.sh
moonray_gui
```

---

## Build Results (verified 2026-05-05, M1 Pro, macOS 15.7.4 Sequoia)

| Item | Result |
|---|---|
| Disk — installs/ | 1.3 GB |
| Disk — build-deps/ | 10 GB |
| Disk — build/ | 2.8 GB |
| XPU/Metal rendering | Confirmed working — loads `default.metallib`, uses Apple M1 Pro GPU |
| Headless render test | `moonray -in rectangle.rdla -out /tmp/rectangle.exr` ✅ |
| GUI launch | `moonray_gui` ✅ |

## Open Questions

- [ ] Actual total build time (multi-session, not precisely measured)
- [ ] Qt5 5.12.12 is old — any rendering/GUI issues on Sequoia/Tahoe?
- [ ] Whether the symlink step (Step 2) is strictly required or just convenient
