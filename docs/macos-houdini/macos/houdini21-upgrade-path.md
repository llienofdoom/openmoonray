# Houdini 21 Upgrade Path

Notes for when the build target moves from Houdini 20.5.x to Houdini 21.x. Based on analysis
of [OpenMoonRay PR #228](https://github.com/OpenMoonRay/openmoonray/pull/228) (rolledhand,
tested against Houdini 21.0.680 on macOS Tahoe, Xcode 26.0.1).

**Current target:** Houdini 20.5.939, macOS Sequoia, Xcode 16.4, Python 3.11.7
**Upgrade target:** Houdini 21.0.x, macOS Tahoe, Xcode 26.x, Python 3.11 (Houdini-bundled)

---

## What changes

### 1. Houdini install path

Every hardcoded Houdini path in the build changes from `Houdini20.5.939` to the new version.
Files to update:

- `CMakeMacOSPresets.json` — `HOUDINI_INSTALL_DIR`
- `scripts/macOS/setupHoudini.sh` — `houdini_resources` variable
- `building/macOS/pxr-houdini/pxrTargets.cmake` — `HPYTHONLIB`, `HPYTHONINC`
- `building/macOS/user-config.jam` — Python headers/lib paths

### 2. `libpxr_python.dylib` instead of `libhboost_python311`

In Houdini 21, using `libhboost_python311-mt-a64.dylib` for `PXR_BOOST_PYTHON_LIB` fails to
resolve all `pxr_boost::python` references at link time. Use `libpxr_python.dylib` instead.

`CMakeMacOSPresets.json`:
```json
"PXR_BOOST_PYTHON_LIB": "$env{HOUDINI_INSTALL_DIR}/Frameworks/Houdini.framework/Versions/Current/Libraries/libpxr_python.dylib"
```

Also add to `cacheVariables`:
```json
"BOOST_PYTHON_COMPONENT_NAME": "python311"
```

### 3. PXR version: 2205 → 2505 (USD 25.05)

Houdini 21 ships USD 25.05 instead of 22.05 / 24.3. Update
`building/macOS/pxr-houdini/pxrConfig.cmake`:

```cmake
set(PXR_MINOR_VERSION "25")
set(PXR_PATCH_VERSION "5")
set(PXR_VERSION "2505")
```

### 4. Library rename: `libpxr_usdRiImaging` → `libpxr_usdRiPxrImaging`

DreamWorks renamed this dylib in Houdini 21. Update
`building/macOS/pxr-houdini/pxrTargets-release.cmake` — find the `usdRiImaging` target and
change `IMPORTED_LOCATION_RELEASE` and `IMPORTED_SONAME_RELEASE` to
`libpxr_usdRiPxrImaging.dylib`.

### 5. Python 3.9 → 3.11 everywhere

Though Houdini 20.5 already used Python 3.11, the upstream source tree still references 3.9
in several places that must be updated for Houdini 21:

- `building/macOS/CMakeLists.txt` — `PythonVer 3.9.6` → `3.11`, all
  `-DPYTHON_EXECUTABLE`, `-DPYTHON_LIBRARY`, `-DPYTHON_INCLUDE_DIR`,
  `-DPYTHON_VERSION_MINOR` values
- `building/macOS/user-config.jam` — `using python : 3.9` → `3.11`
- `building/macOS/pxr-houdini/pxrTargets.cmake` — `HPYTHONLIB`, `HPYTHONINC` paths

### 6. Boost 1.78 → 1.82

Required for Python 3.11 support. `building/macOS/CMakeLists.txt`:
```cmake
URL https://sourceforge.net/projects/boost/files/boost/1.82.0/boost_1_82_0.tar.gz
```

Also change the patch command to be tolerant of already-applied state:
```cmake
PATCH_COMMAND patch -p3 -N < ${THIS_DIR}/Boost.patch || true
```

The `cmake_modules` submodule must also be updated to a version that supports Boost 1.82
macro changes — see PR #228 for the specific commit.

### 7. log4cplus: git tag → tarball

`building/macOS/CMakeLists.txt` — switch from `GIT_TAG REL_2_0_5` to the release tarball
for reproducibility, and add autotools timestamp touch commands:

```cmake
ExternalProject_Add(Log4CPlus
    URL https://github.com/log4cplus/log4cplus/releases/download/REL_2_0_5/log4cplus-2.0.5.tar.xz
    PATCH_COMMAND patch -p1 -N < ${THIS_DIR}/log4plus-limit-threads.patch || true
            COMMAND find . -name "Makefile.in" -exec touch {} +
            COMMAND touch aclocal.m4 configure config.h.in
    ...
)
```

### 8. `moonray_dcc_plugins`: add `python3.11libs`

`moonray/moonray_dcc_plugins/houdini/CMakeLists.txt` — add `python3.11libs` to the installed
directories list so the Python payload is found at the right path under Houdini 21.

### 9. setupHoudini.sh — no functional change needed

The `prepend_unique_path` improvements already incorporated in our script (Issue 8 / code
quality update) handle Houdini 21 cleanly. Only the `houdini_resources` path variable
needs updating to the new version string.

---

## Known limitations in PR #228 (as of 2026-04-29)

The PR author validated build/install/selectability only:

| Area | Status |
|---|---|
| Dependency build | Pass |
| Main configure/build | Pass |
| Install | Pass |
| MoonRay selectable in Solaris viewport | Pass |
| Native DWA material driving render changes | **Unresolved** |
| Light parameter live-update (e.g. `spread`) | **Unresolved** |
| Dome light with texture | **Unresolved** |

Runtime error seen during DWA material tests:
```
{dispatcherExit} Message Dispatcher [libcomputation_progmcrt.dylib] : exiting : reason is 'socket was disconnected'
{clientSocketError} SocketPeer::receive: Bad file descriptor
signal ... 15
```

This is the same Arras teardown signal we documented in Issue 7. It may be more severe in
the Houdini 21 build — investigate before declaring the DWA workflow resolved.

---

## Source

- PR: https://github.com/OpenMoonRay/openmoonray/pull/228
- Compatibility notes: https://github.com/rolledhand/openmoonray/blob/Moonray-Houdini21-macOS/docs/Houdini21_macOS_changes.md
- cmake_modules branch: https://github.com/rolledhand/cmake_modules/tree/boost-1.82-macro-update
- Background discussion: https://github.com/OpenMoonRay/openmoonray/discussions/222
