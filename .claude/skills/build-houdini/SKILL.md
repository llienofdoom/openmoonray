---
name: build-houdini
description: Build the MoonRay Houdini stack on macOS (hdMoonray delegate + DCC plugins), handling the USD 22.11-vs-24.3 pxr-header race. Use when asked to build/compile MoonRay for Houdini, rebuild the delegate, or reinstall the hd_moonray plugin.
---

# Build MoonRay for Houdini (macOS)

Builds against Houdini's bundled USD 24.3. The one non-obvious hazard: the standalone deps
ship USD **22.11** headers in `installs/include/pxr`, and Xcode's generator places
`-isystem installs/include` *before* the Houdini toolkit include, so the wrong USD namespace
wins and objects fail to link against `libpxr_*`. The build wrapper moves those headers aside
during compilation and restores them on exit.

Paths assume the standard layout: clone at `/Applications/MoonRay/source/openmoonray` with a
symlink `/Applications/MoonRay/openmoonray` → it (see root `CLAUDE.md` → Bootstrap).

## First-time configure (once per fresh build dir)

```bash
PYFRAME=/Applications/Houdini/Houdini20.5.939/Frameworks/Python.framework
cmake -S /Applications/MoonRay/openmoonray --preset macos-houdini-release \
  -DPython_ROOT_DIR="$PYFRAME/Versions/3.11" \
  -DPython_EXECUTABLE="$PYFRAME/Versions/3.11/bin/python3.11" \
  -DPython_INCLUDE_DIR="$PYFRAME/Versions/3.11/include/python3.11" \
  -DPython_LIBRARY="$PYFRAME/Versions/3.11/lib/libpython3.11.dylib" \
  -DPYTHON_EXECUTABLE="$PYFRAME/Versions/3.11/bin/python3.11"
```
The `macos-houdini-release` preset sets `BUILD_QT_APPS=NO` (Houdini-only; no Qt5/GUI).

## Build (always via the wrapper — it does the pxr-header swap)

```bash
# from the repo root:
docs/macos-houdini/macos/build-houdini.sh -jobs 8            # all targets
docs/macos-houdini/macos/build-houdini.sh -target hd_moonray -jobs 8   # delegate only
```
The wrapper is idempotent, runs `patch-toolkit-headers.sh` first, and always restores
`installs/include/pxr` on exit (even on failure). Never call `xcodebuild` directly for this
tree — you'll hit the header race.

## Targeted delegate reinstall (fast iteration)

The full `install` target pulls in `ALL_BUILD` and fails on an unrelated target here. To ship
just the delegate after editing `hdMoonray`:

```bash
docs/macos-houdini/macos/build-houdini.sh -target hd_moonray -jobs 8
# install ONLY the hdMoonray plugin subtree (dylib + .ds, no recompile):
cmake -DCMAKE_INSTALL_CONFIG_NAME=Release \
  -P /Applications/MoonRay/build/moonray/hydra/hdMoonray/plugin/cmake_install.cmake
docs/macos-houdini/macos/fix-dylib-install-names.sh    # rewrites '..' install-name paths
```
Result installs to `installs/openmoonray-houdini/plugin/hd_moonray.dylib` (+ its `.ds`).

## After building

Verify with the **`render-test`** skill (husk render + optional RDL2 dump). Known build
failures and their fixes are logged in `docs/macos-houdini/macos/build-issues.md`.
