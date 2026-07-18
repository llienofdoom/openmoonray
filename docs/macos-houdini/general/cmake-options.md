# CMake Build Options

**Sources:**
- `CMakeLists.txt` (root)
- `cmake_modules/cmake/OMR_Platform.cmake`
- `CMakeMacOSPresets.json`
- `CMakeLinuxPresets.json`
- `building/macOS/CMakeLists.txt`

---

## MoonRay Build Options

These are passed to `cmake --preset macos-release` via `-D<FLAG>=<VALUE>` or by editing `CMakeMacOSPresets.json`.

### Core options (root `CMakeLists.txt`)

| Flag | Default | Effect |
|---|---|---|
| `BUILD_QT_APPS` | `YES` | Build `moonray_gui` and `arras_render`. Set `NO` to drop the Qt5 dep entirely. |
| `ABI_SET_VERSION` | `OFF` | Enable ABI versioning. |
| `ABI_VERSION` | `"6"` | ABI version number. Only used when `ABI_SET_VERSION=ON`. (Rocky9 preset sets this to `0`.) |
| `CMAKE_BUILD_TYPE` | `Release` | `Release` / `Debug` / `RelWithDebInfo`. Can also be driven by `$OPT_LEVEL` env var (`opt`, `debug`, `opt-debug`). |
| `CMAKE_INSTALL_PREFIX` | `<source>/release` | Where to install the final build. Preset sets this to `${sourceParentDir}/installs/openmoonray`. |

### macOS-specific options (`OMR_Platform.cmake`)

| Flag | Default | Effect |
|---|---|---|
| `MOONRAY_USE_METAL` | `YES` | Enable XPU mode and OIDN Metal denoising on Apple Silicon. Set `NO` to disable GPU path entirely. |

> **Note:** `MOONRAY_USE_OPTIX` is **Linux-only** and does not exist on macOS. The macOS GPU/XPU path goes through Metal, not CUDA. This is why `-exec_mode xpu` works on Apple Silicon — it's backed by Metal, not NVIDIA hardware.

### Houdini integration option (`CMakeMacOSPresets.json`)

| Flag | Default | Effect |
|---|---|---|
| `MOONRAY_USE_HOUDINI` | not set | Set `TRUE` to link against Houdini's USD instead of the built-from-source USD. Use the `macos-houdini-release` preset which sets this automatically. |

---

## macOS Platform Globals (set automatically, not user flags)

These are set by `OMR_Platform.cmake` for every Darwin build — listed here for reference, not for overriding.

| Variable | Value | Notes |
|---|---|---|
| `CMAKE_OSX_ARCHITECTURES` | `arm64` | Enforces Apple Silicon only |
| `CMAKE_IGNORE_PATH` | `/opt/homebrew` | Homebrew packages explicitly excluded |
| `CMAKE_IGNORE_PREFIX_PATH` | `/opt/homebrew` | Same — belt and braces |
| `GLOBAL_ISPC_INSTRUCTION_SETS` | `neon-i32x4` | NEON SIMD for arm64 |
| `GLOBAL_ISPC_FLAGS` | `-D__aarch64__ -D__APPLE__ -D__ARM_NEON__` | ISPC preprocessor defines |
| `GLOBAL_INSTALL_RPATH` | `@loader_path/` + `@loader_path/../lib` | macOS dylib runtime paths |
| `GLOBAL_LINK_FLAGS` | `-Wl,-ld_classic` | Uses classic linker (required for compatibility) |
| `CMAKE_XCODE_ATTRIBUTE_OTHER_CODE_SIGN_FLAGS` | `-o linker-signed` | Code signing |
| `ISPC_COMPILER` | `$ENV{ISPC}` | Picked up from env var set by preset |

ObjC++ is enabled automatically on macOS when the compiler supports it.

---

## Dependency Build Options

Passed to `cmake ../building/macOS` (the dep build step, not the MoonRay build).

| Flag | Default | Effect |
|---|---|---|
| `NO_USD` | not set | Set `1` to skip building USD. Required for Houdini builds (Houdini provides its own USD). |
| `InstallRoot` | `<source>/../../../installs` | Where to install built deps. Preset resolves this to `/Applications/MoonRay/installs`. |
| `PythonVer` | `3.9.6` | Python version string for dep builds. |
| `PythonRoot` | `/usr` | Python install prefix. USD build overrides this to the Xcode Python3.framework path explicitly. |

---

## Useful Combinations

**Minimal build — no GUI, no GPU:**
```bash
cmake --preset macos-release \
  -DBUILD_QT_APPS=NO \
  -DMOONRAY_USE_METAL=NO
```

**Debug build:**
```bash
cmake --preset macos-release \
  -DCMAKE_BUILD_TYPE=Debug
```
Or set `OPT_LEVEL=debug` in the environment before running cmake.

**Houdini build (skip USD in dep step, use houdini preset):**
```bash
# Dep build
cd /Applications/MoonRay/build-deps
cmake -DNO_USD=1 ../building/macOS
cmake --build .

# MoonRay build
cd /Applications/MoonRay/openmoonray
cmake --preset macos-houdini-release
cmake --build --preset macos-houdini-release
```

**Custom dep install location:**
```bash
cmake ../building/macOS -DInstallRoot=/my/custom/deps
```
Then make sure `DEPS_ROOT` in the preset (or env) points to the same path.
