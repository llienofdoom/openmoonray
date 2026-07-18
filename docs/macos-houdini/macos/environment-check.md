# Environment Check

System verified against build requirements on 2026-05-05.

---

## Results at a Glance

| Requirement | Required | Found | Status |
|---|---|---|---|
| macOS | 14.6+ (Sequoia = 15.x) | 15.7.4 Sequoia | ✅ |
| Xcode | 16.4 (for Sequoia) | 16.4 (Build 16F6, SDK macos15.5) | ✅ |
| CMake | 3.26.5+ | 3.31.5 | ✅ |
| Git | any | 2.50.1 | ✅ |
| Git LFS | required | 3.7.0 | ✅ |
| Clang | Apple Clang, arm64 | 17.0.0 arm64 | ✅ |
| Xcode Python 3.9 | needed for USD build | present | ✅ |
| Houdini 20.5.939 | for Houdini variant | present | ✅ |
| Houdini toolkit includes | needed for Houdini build | present | ✅ |
| Disk space (/Applications) | ~40GB estimated | **94GB free** | ✅ |
| `/Applications/MoonRay` | must not exist (clean) | does not exist | ✅ |

---

## Issues

### ✅ 1 — Xcode (resolved)

Switched to Xcode 16.4 (Build 16F6). Active SDK: `macosx15.5`. This is the exact version documented for macOS 15.x Sequoia.

**Installed Xcodes on this machine:**

| Version | Location |
|---|---|
| Xcode 16.4 ← active | `/Applications/Xcode_16.4.app` |
| Xcode 26.1.1 | `/Applications/Xcode.app` |

**Switching between them:**

```bash
# Check which is currently active
xcode-select -p
xcodebuild -version

# Switch to Xcode 16.4 (for MoonRay build / Sequoia)
sudo xcode-select -s /Applications/Xcode_16.4.app

# Switch back to Xcode 26.1.1
sudo xcode-select -s /Applications/Xcode.app
```

Note: `sudo xcode-select` requires entering your password in a real terminal. Running it via `! sudo xcode-select -s ...` in a Claude Code prompt will not work — use Terminal or iTerm directly.

---

### ✅ 2 — Disk Space (resolved)

94GB free on `/Applications` as of 2026-05-05. Estimated build needs ~35–58GB before cleanup, ~10–18GB after removing `build/` and `build-deps/`. No longer a concern.

---

### 🔴 3 — Houdini 20.5 uses Python 3.11, preset expects Python 3.9

The `CMakeMacOSPresets.json` Houdini configuration was written for Houdini 20.0 which shipped Python 3.9. **Houdini 20.5.939 ships Python 3.11.** Three things need updating before attempting the Houdini build variant.

**Actual paths on this system:**

| Item | Path |
|---|---|
| Boost Python lib | `.../Libraries/libhboost_python311-mt-a64.dylib` |
| Python include dir | `.../toolkit/include/python3.11/` |
| Python lib | `.../Frameworks/Python.framework/Versions/3.11/lib/libpython3.11.dylib` |

**Required edits to `source/openmoonray/CMakeMacOSPresets.json`:**

```json
"HOUDINI_INSTALL_DIR": "/Applications/Houdini/Houdini20.5.939",
"PXR_BOOST_PYTHON_LIB": "$env{HOUDINI_INSTALL_DIR}/Frameworks/Houdini.framework/Versions/Current/Libraries/libhboost_python311-mt-a64.dylib"
```

**Required edits to `source/openmoonray/building/macOS/pxr-houdini/pxrTargets.cmake`:**

```
HPYTHONINC → .../Frameworks/Houdini.framework/Versions/20.5/Resources/toolkit/include/python3.11
HPYTHONLIB → .../Frameworks/Houdini.framework/Versions/20.5/Resources/Frameworks/Python.framework/Versions/3.11/lib/libpython3.11.dylib
```

**Required edits to `source/openmoonray/scripts/macOS/setupHoudini.sh`:**
```
HOUDINI_PATH=/Applications/Houdini/Houdini20.5.939
```

---

## No Issues

- **Git LFS** is installed and active — safe to clone with submodules.
- **CMake 3.31.5** well above the 3.26.5 minimum.
- **Clang 17.0.0 arm64** — correct compiler, correct architecture.
- **Xcode Python 3.9 framework** is present at the exact path the USD CMakeLists hardcodes:
  `/Applications/Xcode.app/Contents/Developer/Library/Frameworks/Python3.framework/Versions/3.9/`
- **`/Applications/MoonRay` does not exist** — clean slate, no stale artifacts.
- **Houdini toolkit includes** present at `.../Resources/toolkit/include/`.
- **MetalToolchain component** — only needed for macOS 26 Tahoe; not required on Sequoia.
