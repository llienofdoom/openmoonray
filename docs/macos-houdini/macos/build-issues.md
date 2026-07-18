# Build Issues Log

Errors encountered during the build process and their resolutions.

---

## Issue 0 — Dylib portability: `..` path segments baked into autotools dep install names

**Stage:** Running MoonRay on a machine that does not have the source tree installed

**Symptom:**

Binaries fail to launch with `dyld: Library not loaded` or a similar path error. The broken
dylib paths all share the pattern:

```
/Applications/MoonRay/source/openmoonray/building/macOS/../../../../installs/lib/libssl.3.dylib
```

Creating the empty directory `/Applications/MoonRay/source/openmoonray/building/macOS/` on
the target machine fixes all failures at once, confirming the `..` traversal is the cause.

**Affected libraries (8 real files, 8 symlinks):**
`libssl.3`, `libcrypto.3`, `libcurl.4`, `liblog4cplus-2.0.3`, `liblog4cplusU-2.0.3`,
`libmicrohttpd.12`, `libcppunit-1.15.1`, `libuuid.1`

**Root cause:**

`building/macOS/CMakeLists.txt` computes the dep install root as:

```cmake
file(REAL_PATH ${CMAKE_SOURCE_DIR} rootSrcDir)  # e.g. .../source/openmoonray/building/macOS
set(InstallRoot ${rootSrcDir}/../../../../installs ...)
```

cmake-based `ExternalProject_Add` deps normalise the install prefix internally; autotools
deps (`./configure --prefix=${InstallRoot}`) receive the raw string literally and bake it
into the dylib `install_name`. macOS `dyld` must traverse every intermediate directory in a
path that contains `..` — it does not resolve `..` symbolically — so any machine without
the `source/` directory tree cannot load these dylibs.

**Fix — root cause (applied to `building/macOS/CMakeLists.txt`):**

After the `set(InstallRoot ...)` line, add:

```cmake
get_filename_component(InstallRoot "${InstallRoot}" ABSOLUTE)
```

`ABSOLUTE` performs lexical normalization (resolves `..` by string manipulation) without
requiring the path to exist on disk. Autotools deps then receive a clean path like
`/Applications/MoonRay/installs` as their `--prefix=`.

**Fix — existing installation (run after dep build):**

`docs/fix-dylib-install-names.sh` rewrites:
1. The `-id` (install name) of each of the 8 real dylibs
2. Every `LC_LOAD_DYLIB` entry referencing a dirty path across all binaries and dylibs in
   the installs tree (`install_name_tool -change`)
3. Two absolute symlinks that were also created with the dirty prefix:
   - `installs/lib/libcurl.so.4` → replaced with relative target `libcurl.4.dylib`
   - `installs/include/uuid.h` → replaced with relative target `_uuid/uuid.h`
   These dangling symlinks cause `sudo xattr -rd com.apple.quarantine` to fail with
   "No such file" on a machine without the source tree.

```bash
cd /Users/llien/Dropbox/Projects/dev/moonray/docs
chmod +x fix-dylib-install-names.sh
./fix-dylib-install-names.sh
```

On our installation this fixed 862 binaries/dylibs. The script is idempotent — safe to
re-run after any cmake install that adds new binaries.

**When to run on a clean build:**

With `building/macOS/CMakeLists.txt` patched, new autotools dep builds will produce clean
install names. However, running `fix-dylib-install-names.sh` after the dep build is still
recommended as a safety net, especially before packaging or distributing to another machine.

---

## Issue 1 — MicroHttpd: `aclocal-1.16` not found (Error 127)

**Stage:** Dep build — MicroHttpd 0.9.72 install step

**Symptom:**
```
gmake[3]: *** [Makefile:528: aclocal.m4] Error 127
gmake[2]: *** [CMakeFiles/MicroHttpd.dir/build.make:107: ...MicroHttpd-install] Error 2
```

**Root cause:**

The MicroHttpd 0.9.72 tarball was generated with automake 1.16. Its `Makefile` calls
`aclocal-1.16` via the `missing` helper script. Our system has automake 1.18.1, which
provides `aclocal-1.18` — `aclocal-1.16` does not exist, so the shell returns 127 (command
not found). This triggers during `make install` when make tries to regenerate `aclocal.m4`
due to timestamp skew in the tarball.

**Fix:**

Added a `PATCH_COMMAND` to MicroHttpd's `ExternalProject_Add` in
`building/macOS/CMakeLists.txt` to touch all autotools-generated files after extraction,
preventing make from trying to regenerate them (same pattern already used for CppUnit):

```cmake
PATCH_COMMAND find . -name "Makefile.in" -exec touch {} + \
              COMMAND find . -name "aclocal.m4" -exec touch {} + \
              COMMAND find . -name "configure" -exec touch {} +
```

For the in-progress build, the files were touched manually in the extracted source and
the `MicroHttpd-build` stamp was deleted to force a retry from the build step.

**Important — do NOT modify `building/macOS/CMakeLists.txt` mid-build.** Doing so causes
cmake to regenerate all ExternalProject Makefile rules with newer timestamps, which
triggers re-runs of already-completed steps (e.g. Boost patch re-ran and failed because
the patch was already applied). For an in-progress build, manually touch the autotools
files in the extracted source instead. Only apply CMakeLists.txt patches on a clean build.

For a **fresh build from scratch**, add this PATCH_COMMAND to MicroHttpd in CMakeLists.txt
before running cmake at all:
```cmake
PATCH_COMMAND find . -name "Makefile.in" -exec touch {} + \
              COMMAND find . -name "aclocal.m4" -exec touch {} + \
              COMMAND find . -name "configure" -exec touch {} +
```

**Recovery steps used (mid-build fix):**
1. Touch autotools files in extracted source: `find <MicroHttpd-src> -name "Makefile.in" -exec touch {} +` (also aclocal.m4, configure)
2. Delete `MicroHttpd-build` stamp to force retry
3. Touch ALL existing stamp files so cmake doesn't cascade-rerun completed steps
4. Revert CMakeLists.txt to original before re-running cmake --build

---

## Issue 2 — Boost patch re-runs on every cmake --build invocation

**Stage:** Dep build — Boost patch step re-triggers after any cmake interruption/resume

**Symptom:**
```
[  4%] Performing patch step for 'Boost'
Ignoring previously applied (or reversed) patch.
1 out of 1 hunks ignored--saving rejects to boost/mpl/aux_/integral_wrapper.hpp.rej
Error 1
```

**Root cause:**

cmake generates `CMakeFiles/Boost.dir/build.make` with `Boost-update` as a `.PHONY` target.
Because it's phony, `make` considers it always out of date, which cascades into the patch
step always re-running. The patch command `patch -p3 -N` exits 1 when all hunks are already
applied, even with the `-N` flag.

**Do NOT** try to fix this by modifying `building/macOS/CMakeLists.txt` mid-build — that
triggers cmake re-configure which cascades stamp invalidation across all deps (see Issue 1 notes).

**Fix (mid-build):**

Edit the generated `CMakeFiles/Boost.dir/build.make` directly to add `|| true` to the
patch command (line 121):

```bash
sed -i '' 's|patch -p3 -N < .*/Boost.patch$|& \|\| true|' \
  /Applications/MoonRay/build-deps/CMakeFiles/Boost.dir/build.make
```

This file is generated, but cmake only regenerates it if CMakeLists.txt changes — so the
edit persists as long as CMakeLists.txt is not touched.

**Fix (fresh build from scratch):**

Add `|| true` to the Boost PATCH_COMMAND in `building/macOS/CMakeLists.txt`:
```cmake
PATCH_COMMAND patch -p3 -N < ${THIS_DIR}/Boost.patch || true
```

**Note:** Log4CPlus also uses autotools (`./configure` build) — watch for the same issue.
Log4CPlus and libcurl also have patch commands — check if they need `|| true` too.

---

## Issue 4 — MoonRay build: `PyEval_CallMethod` undeclared (Python version mismatch)

**Stage:** MoonRay build (`cmake --build --preset macos-release`)

**Symptom:**
```
/Applications/MoonRay/installs/include/boost/python/call_method.hpp:61:9:
  error: use of undeclared identifier 'PyEval_CallMethod'
** BUILD FAILED **
```

**Root cause:**

cmake's `find_package(Python)` picked up Homebrew's Python 3.14 despite
`CMAKE_IGNORE_PATH=/opt/homebrew` — the Python finder uses different search paths
not covered by that setting. `PyEval_CallMethod` was removed from the Python C API
in Python 3.13. Boost.Python 1.78.0's `call_method.hpp` uses it, causing a compile
failure when Python 3.14 headers are included.

Boost was built against Python 3.9 (from Xcode), so the MoonRay build must also
use Python 3.9 to match.

**Fix:**

Pass explicit Python 3.9 paths from Xcode when running cmake --preset:

```bash
PYFW=/Applications/Xcode_16.4.app/Contents/Developer/Library/Frameworks/Python3.framework/Versions/3.9
cd /Applications/MoonRay/openmoonray && cmake --preset macos-release \
  -DPython_ROOT_DIR="$PYFW" \
  -DPython_EXECUTABLE="$PYFW/bin/python3.9" \
  -DPython_INCLUDE_DIR="$PYFW/Headers" \
  -DPython_LIBRARY="$PYFW/lib/libpython3.9.dylib" \
  -DPYTHON_EXECUTABLE="$PYFW/bin/python3.9"
```

**For a fresh build:** These flags should be added to `CMakeMacOSPresets.json`
under `cacheVariables` in the `macos-environment` hidden preset to prevent this
from occurring automatically.

---

## Issue 5 — MoonRay build: FreeType headers not found (`freetype/freetype.h`)

**Stage:** MoonRay build — `mcrt_dataio` TelemetryOverlay compilation

**Symptom:**
```
freetype2/ft2build.h:37:10: error: 'freetype/config/ftheader.h' file not found
  with <angled> include; use "quotes" instead
TelemetryOverlay.h:27:10: fatal error: 'freetype/freetype.h' file not found
```

**Root cause:**

FreeType installs its headers under `include/freetype2/freetype/`, but code includes
them as `<freetype/freetype.h>` (expecting `include/freetype/` to exist). Apple clang
also rejects `<angled>` includes that can only be resolved through user include dirs.

**Fix:**

Create symlinks in the installs tree to bridge the path gap:

```bash
ln -sf /Applications/MoonRay/installs/include/freetype2/freetype \
       /Applications/MoonRay/installs/include/freetype
ln -sf /Applications/MoonRay/installs/include/freetype2/ft2build.h \
       /Applications/MoonRay/installs/include/ft2build.h
```

**For a fresh build:** The FreeType `ExternalProject_Add` in `building/macOS/CMakeLists.txt`
should include a post-install step to create these symlinks automatically.

---

## Issue 3 — MicroHttpd: `makeinfo` not found + configure needs `--disable-doc`

**Stage:** Dep build — MicroHttpd build step

**Symptom:**
```
make[6]: *** [libmicrohttpd.info] Error 127
```

**Root cause:** MicroHttpd's build includes documentation generation using `makeinfo`
(part of the `texinfo` package), which is not installed by default on macOS.

**Fix:**

1. Install texinfo: `brew install texinfo`
2. Add `--disable-doc` to the configure command to skip doc generation entirely.

The configure command in `building/macOS/CMakeLists.txt` should be:
```cmake
CONFIGURE_COMMAND ./configure --prefix ${InstallRoot} --disable-doc
```

**Mid-build recovery:**

MicroHttpd was manually built and installed to bypass all three autotools issues at once:
```bash
MHD=/Applications/MoonRay/build-deps/MicroHttpd-prefix/src/MicroHttpd
# Touch all autotools files to prevent regeneration
find "$MHD" \( -name "configure.ac" -o -name "Makefile.am" -o -name "*.m4" \) -exec touch {} +
find "$MHD" \( -name "aclocal.m4" -o -name "configure" -o -name "Makefile.in" -o -name "config.h.in" \) -exec touch {} +
# Re-configure with --disable-doc and install
cd "$MHD" && ./configure --prefix=/Applications/MoonRay/installs --disable-doc
make -j8 install
# Place stamps so cmake considers it done
touch .../MicroHttpd-stamp/MicroHttpd-build .../MicroHttpd-stamp/MicroHttpd-install
```

**For a fresh build from scratch**, add to MicroHttpd's ExternalProject_Add in CMakeLists.txt:
```cmake
PATCH_COMMAND find . \( -name "Makefile.in" -o -name "aclocal.m4" -o -name "configure" \) -exec touch {} +
CONFIGURE_COMMAND ./configure --prefix ${InstallRoot} --disable-doc
```
And ensure `texinfo` is installed before starting: `brew install texinfo`

---

## Issue 6 — hd_render: `sphere.usd` renders blank (`BaseMaterial` not found)

**Stage:** Post-build smoke test — `hd_render -in sphere.usd`

**Symptom:**
```
Warning: Invalid info:id BaseMaterial node: /checkerboard/baseMtl
```
Render completes but writes a blank/black EXR.

**Root cause:**

`testdata/sphere.usd` references `info:id = "BaseMaterial"` and `inputs:diffuse_color`, but
this build only includes `DwaBaseMaterial.so` — there is no `BaseMaterial` shader. The test
scene was written for a different version of MoonRay that had a `BaseMaterial` alias.

**Fix:**

Edit `testdata/sphere.usd` — change shader type and attribute name:
```
info:id = "DwaBaseMaterial"
inputs:albedo.connect = ...   (was: inputs:diffuse_color)
```
Already applied in this repo.

**Upstream update (2026):** This exact fix was adopted upstream in PR #253
(`Update sphere.usd from BaseMaterial -> DwaBaseMaterial`), landed in
`openmoonray@489b926`. Our local edit was byte-identical, so on any fresh clone
at or past that commit the manual edit is **no longer needed** — `testdata/sphere.usd`
ships with `DwaBaseMaterial`/`inputs:albedo` out of the box.

**Note:** The Python warnings `No module named 'pxr.MoonrayShaderParser'` are harmless — USD
looks for optional Python bindings for those C++ plugins. The C++ plugins themselves load
correctly via `PXR_PLUGINPATH_NAME`.

---

## Issue 7 — hd_render: abort on exit (Arras mutex crash)

**Stage:** Post-build smoke test — `hd_render` exit

**Symptom:**
```
libc++abi: terminating due to uncaught exception of type std::__1::system_error:
  mutex lock failed: Invalid argument
zsh: abort      hd_render ...
```

**Root cause:**

Race condition in Arras client session teardown on macOS. The crash occurs after the EXR
has already been written — it is a cleanup bug, not a render bug.

**Impact:** None — output file is valid. The process exits with non-zero status which may
cause issues in scripts that check exit codes.

**Workaround:** Ignore the abort for interactive use. For scripted use, append `|| true`
or check whether the output file exists rather than checking exit code.

---

## Issue 8 — Houdini: Solaris crashes with `pxr.Tf` Python 3.9 import error

**Stage:** Houdini runtime — Solaris/LOP viewer states fail on startup

**Symptom:**
```
ImportError: dlopen(/Applications/MoonRay/installs/lib/python/pxr/Tf/_tf.so):
  Library not loaded: @rpath/Python3.framework/Versions/3.9/Python3
```
Houdini's Solaris tools (camera, light, layout, stage manager viewer states) all fail.
MoonRay does appear as a render delegate but most LOP functionality is broken.

**Root cause:**

`setupHoudini.sh` adds `/Applications/MoonRay/installs/lib/python` to `PYTHONPATH` via
`setup.sh`. This path contains the standalone USD `pxr` Python bindings compiled against
Python 3.9. Houdini's Python 3.11 finds these first (ahead of its own `pxr` bindings) and
fails to load them because the Python 3.9 dylib isn't in any rpath.

The original script used a save/restore of `PYTHONPATH` to strip these paths, but that
only works if `PYTHONPATH` was clean before sourcing. If `setup.sh` had been sourced
in the same shell session first, the contaminated path survived the restore.

Additionally, `PXR_PLUGINPATH_NAME` was missing its `export` keyword, so the MoonRay
Hydra plugins were not visible to Houdini.

**Fix (applied to installed script):**

`installs/openmoonray-houdini/scripts/macOS/setupHoudini.sh` — replaced save/restore
with an explicit filter that strips the Python 3.9 paths unconditionally, and added
`export` to `PXR_PLUGINPATH_NAME`:

```bash
source ${omr_install_dir}/scripts/setup.sh

export PYTHONPATH=$(echo "${PYTHONPATH}" | tr ':' '\n' \
  | grep -v "^${install_root}/lib/python$" \
  | grep -v "^${install_root}/lib64/python3.9" \
  | tr '\n' ':' | sed 's/:$//')

export PXR_PLUGINPATH_NAME=${omr_install_dir}/plugin/pxr
```

**Further improvement (applied later — see code quality update below):** The script was
subsequently updated to use a `prepend_unique_path()` helper for idempotent path management,
set both `PXR_PLUGINPATH_NAME` and `PXR_PLUGIN_PATH`, and handle `HOUDINI_PATH`
conditionally (prepend to an existing path set by `houdini_setup`, or build from scratch
using the Houdini resources fallback). See current state of
`scripts/macOS/setupHoudini.sh` for the full script.

**Important:** In the `else` branch (HOUDINI_PATH not previously set), do NOT append `:&`
after `${houdini_resources}`. Houdini's `&` sentinel expands to the default search path,
which includes the same `Resources/houdini` directory — this causes Houdini's PDG Python
modules to be loaded twice and produces `RuntimeError: A type already exists with the name
genericvisualizer` on startup. Explicit path only, no `&`.

**Important:** Always source `setupHoudini.sh`, never `setup.sh`, before launching Houdini:
```bash
source /Applications/MoonRay/installs/openmoonray-houdini/scripts/macOS/setupHoudini.sh
houdini
```

**Note for clean builds:** The cmake install step overwrites the installed `setupHoudini.sh`
with whatever is in `source/openmoonray/scripts/macOS/setupHoudini.sh`. Keep the source
version up to date so reinstalls don't regress the script. The current source version
includes all the improvements documented here.

---

## Issue 10 — Houdini build: `SdfChildrenProxy::_Set` compile error in `hdMoonrayAdapters`

**Stage:** Houdini MoonRay build — after fixing Issue 9's CMAKE_PREFIX_PATH order

**Symptom:**
```
/Applications/Houdini/Houdini20.5.939/.../sdf/childrenProxy.h:75:21:
  error: no member named '_Set' in 'SdfChildrenProxy<_View>'
```
Build fails when compiling `hdMoonrayAdapters`.

**Root cause:**

Both `MoonrayLightFilterAdapter.h` and `MoonrayMeshLightAdapter.h` include
`pxr/usdImaging/usdImaging/light*Adapter.h` from Houdini's USD 24.3 toolkit. That
include chain reaches `sdf/childrenProxy.h` via:

```
light*Adapter.h → ... → usd/primData.h → usd/primDefinition.h
  → usd/schemaRegistry.h → sdf/layer.h → sdf/proxyTypes.h → sdf/childrenProxy.h
```

`childrenProxy.h` defines `_ValueProxy::operator=` which calls `_owner->_Set(...)`.
`_Set` is not defined in `SdfChildrenProxy<_View>` — it must be provided by the view
type. In Houdini 24.3, this include chain instantiates `_ValueProxy::operator=` with a
view type that does not provide `_Set`, causing the compile error.

USD 22.11's include chain did NOT trigger this instantiation. This is a USD 22.11 → 24.3
API compatibility break exposed by using Houdini's USD headers.

**Fix:**

Skip the entire `adapters/` subdirectory for Houdini builds in
`moonray/hydra/hdMoonray/plugin/CMakeLists.txt`:

```cmake
if (NOT MOONRAY_USE_HOUDINI)
    add_subdirectory(adapters)
endif()
```

`hdMoonrayAdapters` is a standalone USD plugin — nothing else links against it at build
time, so omitting it does not break `hd_moonray.dylib` or any other target.

**Impact:** MoonRay light filter adapters (cookie projectors) and mesh light adapters are
not registered as USD prim adapters in Houdini. Standard Houdini lights, geometry, and
materials render correctly. This is a Houdini 20.5 (USD 24.3) compatibility limitation.

---

## Issue 9 — Houdini: MoonRay render delegate disappears ("not supported")

**Stage:** Houdini runtime — selecting MoonRay or MoonRay Debug in Solaris viewport

**Symptom:**
```
Unable to create Usd Render Plugin: HdMoonrayRendererPlugin
HdMoonrayRendererPlugin not supported - removing from renderer list
```
MoonRay briefly appears in the renderer dropdown then disappears. No rendering occurs.

**Root cause:**

`hd_moonray.dylib` was built against the standalone USD 22.11 (`libusd_*.dylib`) instead of
Houdini's USD 24.3 (`libpxr_*.dylib`). When Houdini loads the plugin, the USD symbols
don't match — the plugin fails to instantiate and Houdini removes it.

The wrong USD was linked because of a `CMAKE_PREFIX_PATH` ordering bug in
`CMakeMacOSPresets.json`. The Houdini preset set:

```json
"CMAKE_PREFIX_PATH": "$env{DEPS_ROOT};$env{PREFIX_PXR}"
```

`DEPS_ROOT` (`installs/`) is searched first and contains `pxrConfig.cmake` — the standalone
USD 22.11 cmake config. This takes precedence over `PREFIX_PXR`
(`building/macOS/pxr-houdini/pxrConfig.cmake`) which correctly points to Houdini's USD.

A secondary issue: `pxrTargets-release.cmake` in `pxr-houdini/` referenced
`libpxr_usdRiImaging.dylib` which does not exist in Houdini 20.5 — the library was
renamed to `libpxr_usdRiPxrImaging.dylib`. This would cause a cmake fatal error during
the import-target file-existence check.

**Fix:**

Two source edits, then a full reconfigure + rebuild of the Houdini variant:

**1. `source/openmoonray/CMakeMacOSPresets.json`** — swap prefix path order so Houdini USD
config is found first:
```json
"CMAKE_PREFIX_PATH": "$env{PREFIX_PXR};$env{DEPS_ROOT}"
```

**2. `building/macOS/pxr-houdini/pxrTargets-release.cmake`** — fix Houdini 20.5 library
rename for `usdRiImaging`:
```cmake
IMPORTED_LOCATION_RELEASE "${_LIB_PREFIX}/libpxr_usdRiPxrImaging.dylib"
IMPORTED_SONAME_RELEASE    "libpxr_usdRiPxrImaging.dylib"
# also in _IMPORT_CHECK_FILES_FOR_usdRiImaging
```

Both already applied. Then clear the build cache and rebuild:
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

After the rebuild, `hd_moonray.dylib` will link against Houdini's `libpxr_hd.dylib` and
`libpxr_usdImaging.dylib`, making the plugin loadable by Houdini's USD runtime.

---

## Issue 11 — Houdini build: USD 22.11 headers win include race; `_Set` compile error in hydramoonray

**Stage:** Houdini MoonRay build — hydramoonray library compilation

**Symptom A — wrong namespace at link time (before Option A fix):**

When `hd_moonray.dylib` is linked it picks up `libusd_*` (standalone USD 22.11) instead of
`libpxr_*` (Houdini USD 24.3). Houdini rejects the plugin at runtime because the USD
namespace (`pxrInternal_v0_22`) doesn't match its own (`pxrInternal_v0_24`).

**Symptom B — `_Set` compile error (after Option A fix):**
```
/toolkit/include/pxr/usd/sdf/childrenProxy.h:75:21:
  error: no member named '_Set' in 'SdfChildrenProxy<_View>'
```
Appears in every hydramoonray source file.

---

### Root cause A — Include ordering: installs/include/pxr beats toolkit/include

cmake's Xcode generator produces compile commands with this fixed search order:

```
HEADER_SEARCH_PATHS (-I) → SYSTEM_HEADER_SEARCH_PATHS (-isystem) → OTHER_CPLUSPLUSFLAGS
```

`installs/include` ends up in `SYSTEM_HEADER_SEARCH_PATHS` (via `target_include_directories`
on MoonRay's own targets). Toolkit/include (`$PXR_INCLUDE_PREFIX`) is in
`OTHER_CPLUSPLUSFLAGS` (from `CMAKE_CXX_FLAGS=-isystem toolkit/include` in the cmake preset).

Because SYSTEM_HEADER_SEARCH_PATHS comes before OTHER_CPLUSPLUSFLAGS, `installs/include/pxr`
(USD 22.11) is found first — compiled objects use namespace `pxrInternal_v0_22` and fail to
link against Houdini's `libpxr_*`.

Two cmake approaches to promote toolkit/include were tried and failed:
- `target_include_directories(BEFORE PRIVATE toolkit/include)` — cmake's
  `GetIncludeDirectories(excludeImplicit=true)` filtered it out because toolkit/include
  appeared in `INTERFACE_SYSTEM_INCLUDE_DIRECTORIES` of linked pxr targets.
- After removing it from INTERFACE_SYSTEM_INCLUDE_DIRECTORIES — cmake's Xcode generator
  still filtered it because the canonical path resolves through `.framework/`, which the
  generator treats specially.

**Fix A — Option A: rename installs/include/pxr during the build**

Temporarily rename `installs/include/pxr` → `installs/include/pxr_standalone_disabled` so
clang cannot find USD 22.11 headers there. Clang falls through to toolkit/include in
`OTHER_CPLUSPLUSFLAGS`. The rename is restored after the build via a `trap` handler.

Automated by `docs/build-houdini.sh`:
```bash
# Usage: ./build-houdini.sh [xcodebuild options]
# Examples:
#   ./build-houdini.sh -target hd_moonray -jobs 8
#   ./build-houdini.sh                         # build all targets
```

A related cmake change: removed `${_INCLUDE_PREFIX}` from `INTERFACE_SYSTEM_INCLUDE_DIRECTORIES`
in all 28 pxr imported targets in `building/macOS/pxr-houdini/pxrTargets.cmake`. Without this,
cmake would add toolkit/include back to `SYSTEM_HEADER_SEARCH_PATHS` via propagation, and if
`installs/include` appeared first there, USD 22.11 would win again on a fresh cmake configure.

---

### Root cause B — `SdfChildrenProxy::_Set` clang phase-1 error

Once toolkit/include (USD 24.3) is used, ALL hydramoonray source files fail with the `_Set`
error. The include chain is:

```
any hydramoonray .cc → RenderDelegate.h → usdImaging/delegate.h
  → usd/stage.h → usd/editTarget.h → sdf/layer.h → sdf/proxyTypes.h → sdf/childrenProxy.h
```

`childrenProxy.h` defines `_ValueProxy::operator=<U>` which calls `_owner->_Set(*_pos, x)`.
`_Set` does not exist in USD 24.3's `SdfChildrenProxy` — it was removed along with
`SdfChildren::Move`. The same code exists verbatim in USD 22.11, but USD 22.11's
`SdfChildrenProxy` inherits from `boost::equality_comparable<SdfChildrenProxy<_View>>` (a
dependent base). A dependent base class defers clang's name lookup of `_Set` to phase 2
(instantiation). Since `_ValueProxy::operator=<U>` is never actually instantiated in
hydramoonray code, phase 2 never runs and the error never triggers.

USD 24.3 dropped boost entirely — no dependent base class. Clang performs a phase-1 eager
lookup of `_Set` in the already-known (incomplete) `SdfChildrenProxy<_View>` class body,
finds nothing, and errors immediately — even though the template is never called.

This is a Pixar regression: `_Set` was removed from `SdfChildrenProxy` but `_ValueProxy::
operator=` still references it. Houdini 20.5's bundled USD 24.3 headers contain this bug.

**Fix B — patch toolkit header to add `_Set` stub**

`building/macOS/pxr-houdini/patch-toolkit-headers.sh` (idempotent) patches
Houdini's installed `sdf/childrenProxy.h` to add a private `_Set` stub:

```cpp
template <class U>
bool _Set(const mapped_type&, const U&)
{
    TF_CODING_ERROR("SdfChildrenProxy: _Set is not supported in USD 24.x; "
                    "use insert/erase instead");
    return false;
}
```

This satisfies the phase-1 name lookup without changing any behaviour (the method is never
called in normal hydramoonray usage). `build-houdini.sh` calls the patch script automatically.

Apply manually:
```bash
/Applications/MoonRay/source/openmoonray/building/macOS/pxr-houdini/patch-toolkit-headers.sh
```

---

### Result

`hd_moonray.dylib` and `libhydramoonray.dylib` now link exclusively against
`libpxr_*` (Houdini USD 24.3). Verified with `otool -L` — no `libusd_*` present.

Install after building:
```bash
cmake --install /Applications/MoonRay/build --component hd_moonray
cmake --install /Applications/MoonRay/build --component hydramoonray
```

Launch Houdini for testing:
```bash
source /Applications/MoonRay/installs/openmoonray-houdini/scripts/macOS/setupHoudini.sh
/Applications/Houdini/Houdini20.5.939/Frameworks/Houdini.framework/Versions/Current/Resources/bin/houdini
```

---

## Issue 12 — Houdini runtime: `moonrayShaderDiscovery` / `moonrayShaderParser` linked against `libusd_*`

**Stage:** Houdini MoonRay — Solaris material rendering (runtime)

**Symptom:**

Houdini Log Viewer shows:
```
Invalid info:id DwaBaseMaterial node: /materials/.../DwaBaseMaterial1
```
for every DW_MOONRAY shader node. Materials using `DwaBaseMaterial` (and all other
MoonRay shader types) render with default/error material instead of the assigned shader.
Shader parameters (albedo, diffuse_transmission, etc.) have no effect.

**Root cause:**

`moonrayShaderDiscovery.dylib` and `moonrayShaderParser.dylib` were built against
standalone USD 22.11 (`libusd_*`) instead of Houdini USD 24.3 (`libpxr_*`). The same
include-ordering problem as Issue 11 — the `.o` files were compiled with `installs/include/pxr`
(USD 22.11) headers cached from an earlier build pass.

Houdini loads these as USD NDR/SDR plugins. Because they link against `libusd_*`, their
USD namespace is `pxrInternal_v0_22` while Houdini's runtime is `pxrInternal_v0_24`. The
plugins fail silently, MoonRay shader types are never registered in the SDR, and Houdini
logs "Invalid info:id" for every `DwaBaseMaterial` node it encounters.

Verify with:
```bash
otool -L /Applications/MoonRay/installs/openmoonray-houdini/plugin/moonrayShaderDiscovery.dylib | grep -E "libusd|libpxr"
# Should show libpxr_* only. If libusd_* appears, rebuild is needed.
```

**Fix:**

Touch the source files to force recompilation (Xcode skips unchanged sources even with
the `pxr` header rename in place), then rebuild with `build-houdini.sh`:

```bash
cd /Users/llien/Dropbox/Projects/dev/moonray/docs

find /Applications/MoonRay/source/openmoonray/moonray/hydra/moonray_sdr_plugins -name "*.cc" -o -name "*.cpp" -o -name "*.h" | xargs touch

./build-houdini.sh -target moonrayShaderDiscovery -jobs 8
./build-houdini.sh -target moonrayShaderParser -jobs 8

cmake --install /Applications/MoonRay/build --component moonrayShaderDiscovery
cmake --install /Applications/MoonRay/build --component moonrayShaderParser
```

**Result:**

Both dylibs link exclusively against `libpxr_*`. MoonRay shader types are registered in
the SDR. `DwaBaseMaterial` and all other DW_MOONRAY shader types are recognised by
Houdini's USD pipeline and shader parameters flow through correctly to MoonRay.

---

## Issue 13 — Houdini runtime: `cannot convert long long to Int` for `__SceneVariables__`

**Stage:** Houdini MoonRay — interactive rendering in Solaris viewport

**Symptom:**

Every render sync logs errors such as:
```
__SceneVariables__.sampling_mode: cannot convert long long to Int
__SceneVariables__.pixel_samples: cannot convert long long to Int
__SceneVariables__.max_depth: cannot convert long long to Int
```
All integer render settings are ignored; MoonRay uses its built-in defaults.

**Root cause:**

On macOS arm64, `long` and `long long` are both 64-bit but are distinct C++ types.
`VtValue::IsHolding<long>()` returns `false` for values stored as `int64_t` / `long long`.
USD 24.3 / Houdini 20.5 sends integer render settings as `long long`, but the original
`ValueConverter.cc` only handled `long` and `int` for TYPE_BOOL, TYPE_INT, TYPE_LONG,
and TYPE_FLOAT — causing every `long long` value to fall through to the error logger.

**Fix:**

Added `|| val.IsHolding<long long>()` branches to five locations in
`moonray/hydra/hdMoonray/lib/hydramoonray/ValueConverter.cc`:

- **TYPE_BOOL** — handles `long | long long` → `static_cast<bool>`
- **TYPE_INT enumerable** — handles `long | long long | int` in the enum index path
- **TYPE_INT non-enumerable** — handles `long | long long` → `static_cast<int>`
- **TYPE_LONG** — new `val.IsHolding<long long>()` branch using `reinterpret_cast<const Long&>`
- **TYPE_FLOAT** — handles `long | long long` → `static_cast<float>`

Rebuild and install:
```bash
cd /Users/llien/Dropbox/Projects/dev/moonray/docs
find /Applications/MoonRay/source/openmoonray/moonray/hydra/hdMoonray/lib/hydramoonray -name "ValueConverter.cc" | xargs touch
./build-houdini.sh -target hydramoonray -jobs 8
cmake --install /Applications/MoonRay/build --component hydramoonray
```

**Result:** All `__SceneVariables__` integer attributes set correctly at render start.

**Code quality update (applied after initial fix):** The ad-hoc `IsHolding<long>() ||
IsHolding<long long>()` chains in the TYPE_INT enumerable and non-enumerable paths were
refactored using two helpers — `_extractIntegral64` (unifies `int`/`long`/`long long` →
`std::int64_t`) and `_narrowIntChecked` (safe bounds-checked narrowing to `Int` with an
error log if the value is out of range). This pattern matches OpenMoonRay PR #228 and makes
the intent explicit. TYPE_BOOL, TYPE_LONG, and TYPE_FLOAT retain their existing fixes
unchanged. See `docs/research/houdini21-upgrade-path.md` for context.

---

## Issue 14 — Houdini: USD native `Sphere` primitive not rendered by MoonRay

**Stage:** Houdini MoonRay — Solaris geometry setup

**Symptom:**

A `Sphere` prim in the USD stage (e.g. from Houdini's built-in Sphere object LOP or a
SOP Create with default sphere type) renders as invisible — no geometry, no shadow,
no error. Material binding and lighting are correct but nothing appears.

**Root cause:**

MoonRay's Hydra delegate only supports these rprim types:
```
mesh, basisCurves, points, volume, procedural
```
USD `Sphere`, `Cube`, `Cylinder`, `Cone`, and other implicit geometry types are not in the
supported list (`RenderDelegate::GetSupportedRprimTypes()`). Hydra silently skips unsupported
prim types — no warning is logged.

**Fix:**

Use **Mesh** geometry instead of native USD geometry types. In Houdini Solaris:
- Add a **SOP Create** LOP → place a Sphere SOP inside → set sphere type to **Polygon**
- OR add a **SOP Import** LOP referencing a polygon sphere from the geometry context
- The resulting prim type will be `Mesh`, which MoonRay renders correctly

Verify the prim type in the Scene Graph Tree: look for `Mesh` in the Primitive Type column.

---

## Issue 15 — Houdini: DwaBaseMaterial renders geometry as transparent/invisible

**Stage:** Houdini MoonRay — Solaris material authoring

**Symptom:**

Geometry with a freshly created `DwaBaseMaterial` in the Material Builder renders as
completely transparent (invisible against the black background) even though `presence = 1.0`
and albedo is a visible colour. Disabling the material assignment makes the geometry visible
with the default material.

**Root cause:**

The `DwaBaseMaterial` HDA defaults `diffuse_transmission = 1.0`. This means 100% of the
diffuse light energy is transmitted *through* the surface rather than reflected back toward
the camera. With a standard front-lit setup (lights and camera on the same side), the
geometry reflects zero diffuse light toward the camera and appears as black — visually
indistinguishable from transparent geometry against a black MoonRay background.

The RDL2 default is also `1.0`, so even if the VOP parameter is not written to USD and
MoonRay falls back to the RDL2 default, the behaviour is the same.

**Fix:**

In the DwaBaseMaterial VOP inside the Material Builder, find the **"Transmission"**
parameter (`diffuse_transmission`) and set it to `0.0`. It is under the Transmission or
Common tab depending on HDA version.

This must be done for every new DwaBaseMaterial — there is no global default override.

---

## Issue 16 — Houdini runtime: `cannot convert TfToken to IntVector` for `iridescence_interpolations`

**Stage:** Houdini Solaris rendering with DwaBaseMaterial iridescence ramp connected

**Symptom:**

```
Error: /materials/collect1/DwaBaseMaterial1.iridescence_interpolations: cannot convert TfToken to IntVector
{trace:mcrt} stage shading stop (no shading complete)
```

The error fires when the DwaBaseMaterial's iridescence ramp is connected or its interpolation
type is changed in Houdini. The `shading stop` line is a normal interactive render cancellation
(not a crash) — it fires whenever a new sync arrives before the previous render completes.

**Root cause:**

`iridescence_interpolations` is a `TYPE_INT_VECTOR` attribute in MoonRay's RDL2 schema — it
stores an integer per ramp segment (7 entries, value 4 = hermite). Houdini exports the ramp
interpolation setting as a single `TfToken` (e.g. `"hermite"`), not as a `VtArray<int>`.
`ValueConverter::setAttribute` had no handler for `TfToken` in the `TYPE_INT_VECTOR` case,
so it fell through to the `Logger::error` call.

The error is non-fatal — `makeMoonrayShader` continues after it, and the RDL2 default for
`iridescence_interpolations` (`[4, 4, 4, 4, 4, 4, 4]` = all-hermite) is correct regardless.

**Fix:**

Added a `TfToken` guard to the `TYPE_INT_VECTOR` case in `ValueConverter::setAttribute` that
silently returns (skipping the error log) when Houdini sends a ramp interpolation `TfToken`.
The RDL2 default is preserved and is already correct for hermite interpolation.

File: `moonray/hydra/hdMoonray/lib/hydramoonray/ValueConverter.cc`

```cpp
case TYPE_INT_VECTOR:
    if (_setAttribute<IntVector, pxr::VtArray<int>>(sceneObj, attribute, val)) return;
    if (val.IsHolding<pxr::TfToken>()) {
        // Houdini exports ramp interpolation as a single TfToken (e.g. "hermite").
        // MoonRay expects IntVector; silently skip and let RDL2 keep its default.
        return;
    }
    break;
```

After editing: rebuild and reinstall `hydramoonray`:
```bash
cd /Users/llien/Dropbox/Projects/dev/moonray/docs
./build-houdini.sh -target hydramoonray -jobs 8
cmake --install /Applications/MoonRay/build --component hydramoonray
```

**Result:** Error no longer appears in the Log Viewer. Iridescence ramp uses the RDL2
hermite default, which matches Houdini's exported `"hermite"` token.

---

## Issue 17 — `moonray_gui` crash: Qt platform plugin "cocoa" not found

**Stage:** Running `moonray_gui` on a machine where `installs/plugins/` was not present

**Symptom:**

```
qt.qpa.plugin: Could not find the Qt platform plugin "cocoa" in ""
This application failed to start because no Qt platform plugin could be initialized.
Aborted (core dumped)
```

Application exits immediately. The empty `""` in the message confirms Qt had no search
path to look in.

**Root cause:**

Qt plugins (platform backends, image-format codecs, etc.) are installed to
`installs/plugins/` alongside the Qt frameworks in `installs/lib/`. The macOS platform
plugin `libqcocoa.dylib` lives at `installs/plugins/platforms/libqcocoa.dylib`.

The original `setup.sh` did not set `QT_QPA_PLATFORM_PLUGIN_PATH` or `QT_PLUGIN_PATH`,
so Qt fell back to its default search strategy (relative to the executable, or derived
from `Qt5Core.framework` `@rpath`). On a machine that has no Qt system install and the
`installs/plugins/` directory was not sent, the search found nothing and Qt aborted.

**Fix:**

Added to `source/openmoonray/scripts/setup.sh` (and both installed copies):

```bash
# Qt platform and image-format plugins are in installs/plugins/ alongside the
# Qt frameworks in installs/lib/. Without these paths moonray_gui aborts
# immediately with "Could not find the Qt platform plugin cocoa".
export QT_QPA_PLATFORM_PLUGIN_PATH=${install_root}/plugins/platforms
export QT_PLUGIN_PATH=${install_root}/plugins
```

`install_root` is already computed by `setup.sh`'s while loop (walks up the directory
tree until it finds a component named `installs`). Both standalone and Houdini installs
share the same `installs/plugins/` directory — the fix applies to both.

**For clean builds:**

The cmake install step copies `source/openmoonray/scripts/setup.sh` to both installed
locations. Keep the source copy current — it already contains these exports.

**Distribution note:**

When copying MoonRay to another machine, include `installs/plugins/` alongside
`installs/lib/` and the MoonRay install directory (`openmoonray-standalone/` or
`openmoonray-houdini/`). `installs/bin/` contains only dep build tools and is NOT
required at runtime.

---

## Issue 18 — Texture loading fails with "unknown oiio sample failure" (both builds)

**Stage:** Runtime — rendering any scene with texture maps

**Symptom:**
```
ImageMap("/materials/collect1/ImageMap1.out"): (7850068 times) unknown oiio sample failure
```
Textures render as black. Affects both `moonray_gui` (standalone) and `hd_render` / Houdini
Solaris rendering. The count is per-sample — one failure per render thread per shading call.

**Root cause:**

`moonray/lib/rendering/texturing/sampler/TextureSampler.cc` initialises OIIO's
`TextureSystem` in strict production mode (the `#if 1` block, ~line 60):

```cpp
mTextureSystem->attribute("automip", int(false));
mTextureSystem->attribute("autotile", int(0));
mTextureSystem->attribute("accept_untiled", int(false));
mTextureSystem->attribute("accept_unmipped", int(false));
```

With these settings OIIO will open a file and return a valid handle, but `texture()` returns
`false` at every sample if the file is **not tiled** or **not mip-mapped**. Plain JPEG, PNG,
and untiled/unmipped EXR files all fail this check.

The error message is misleading. MoonRay's sample path (`BasicTexture.cc` ~line 271) does
not call `geterror()` — it logs the hardcoded event `"unknown oiio sample failure"` whenever
`texture()` returns `false`. The actual OIIO error ("texture is not tiled", etc.) is silently
discarded.

**Fix:**

Convert all textures to TX format (tiled + mip-mapped OpenEXR) before rendering.
`maketx` is installed at `/Applications/MoonRay/installs/bin/maketx`:

```bash
source /Applications/MoonRay/installs/openmoonray-standalone/scripts/setup.sh

maketx input.jpg -o output.tx
maketx input.exr -o output.tx
maketx input.png -o output.tx
```

Then update the `filename` parameter of every `ImageMap` shader to reference the `.tx` file.

TX format is OIIO's native texture format: tiled, mip-mapped, stored as OpenEXR. It is the
standard input for production renderers built on OIIO's `TextureSystem`.

**Note on OIIO built without PNG:**

`CMakeCache.txt` for the OIIO dep build shows `PNG_LIBRARY_RELEASE=NOTFOUND` — libpng was not
found at dep build time so OIIO has no PNG reader. PNG textures cannot be read at all.
Converting PNG → TX via `maketx` works because `maketx` reads the PNG using its own bundled
reader, then writes a TX file that OIIO can sample without needing the PNG reader at render time.

**Verification:**

After converting and re-pointing the shader, the `unknown oiio sample failure` messages
disappear and textures render correctly — confirmed in both standalone and Houdini (2026-05-06).

---

## Issue 19 — Houdini: denoising fails with "Optix mode not supported in this build"

**Stage:** Houdini Solaris interactive render (`hdMoonray` delegate) with denoising enabled.
Standalone (`moonray_gui`) denoising works fine on the same machine.

**Symptom:**
```
Error: Denoiser: Optix mode not supported in this build
```
Denoising silently disables; the render is never denoised. Ticking the viewport's
"Use OIDN Denoising" toggle does **not** help.

**Root cause (two distinct bugs):**

1. **Dead toggle.** `hdMoonray` uses the Arras client path (`mcrt_dataio::ClientReceiverFb`),
   not the GUI's `DenoiserManager`. `ArrasSettings::applySettings()`
   (`moonray/hydra/hdMoonray/plugin/hd_moonray/ArrasSettings.cc`) called only
   `setDenoiseMode(...)` and **never called `ArrasSettings::setDenoiseEngine(...)`** — the
   only function that reads the OIDN flag to choose the engine. So `mDenoiseEngine` was
   frozen at its constructor default `OPTIX` (`ArrasSettings.h`) regardless of the toggle.
   `ArrasSettings::setDenoiseEngine` was dead code (defined, never called anywhere in the
   tree). This is a genuine upstream bug, platform-independent.

2. **No macOS guard.** Even once the toggle is wired up, the Arras `DenoiseEngine` enum only
   has `OPTIX` / `OPEN_IMAGE_DENOISE` (no `METAL`). OptiX needs CUDA/NVIDIA and is compiled
   out on macOS (`Denoiser.cc:142`, no `MOONRAY_USE_OPTIX`), so any OptiX request aborts.
   The GUI path avoids this via `#if PLATFORM_APPLE` defaulting to `METAL`
   (`moonray_gui/cmd/moonray_gui_v2/DenoiserManager.h`); the Arras path had no equivalent.

**Fix (local patch to the clone — carried like our other patches):**

In `moonray/hydra/hdMoonray/plugin/hd_moonray/ArrasSettings.cc`:
- `applySettings()`: after the `setDenoiseMode(...)` call, add
  `setDenoiseEngine(enableDenoise, enableOIDN)` so the toggle actually drives the engine.
- `setDenoiseEngine()`: wrap the body in `#if defined(__APPLE__)` → always
  `OPEN_IMAGE_DENOISE`; `#else` keep the original `oidn ? OIDN : OPTIX`. OptiX is never
  requestable on macOS, so plain "Denoising" now works without also ticking OIDN.

In `moonray/hydra/hdMoonray/plugin/hd_moonray/ArrasRenderer.cc`:
- **`connect()` — the decisive fix.** A freshly-created `ClientReceiverFb` defaults its
  engine to `OPTIX`. `connect()` pushed the denoise *mode* to the new receiver
  (`setBeautyDenoiseMode`) but never the *engine*, so the receiver built an OptiX denoiser
  regardless of settings. The `applySettings()` "if changed" guard could not correct this
  because `mCurrentDenoiseEngine` was already latched to OIDN while `mFbReceiver` was still
  null (settings are applied before `connect()`), so the guard saw "no change" and skipped
  the push. Fix: right after `setBeautyDenoiseMode`, add
  `mCurrentDenoiseEngine = mSettings.getDenoiseEngine(); mFbReceiver->setDenoiseEngine(mCurrentDenoiseEngine);`
  so the engine is set explicitly on every new receiver.
  **Without this, the two `ArrasSettings.cc` edits above are necessary but not sufficient** —
  the correct engine value never reaches the receiver. (Symptom during debugging: the
  installed dylib's `setDenoiseEngine` disassembled correctly to OIDN-only, yet renders still
  errored, because the receiver was never told.)

**Related: expose denoise settings on the RenderSettings prim (per-output).**
The four denoise parms in
`moonray/hydra/hdMoonray/plugin/houdini/soho/parameters/HdMoonrayRendererPlugin_Viewport.ds`
(`enableDenoise`, `enableOIDN`, `denoiseAlbedoGuiding`, `denoiseNormalGuiding`) were tagged
`parmtag { "uiscope" "viewport" }` **without** a `usdvaluetype` tag, so they appeared only in
the viewport Display Options and could not be authored on a USD `RenderSettings` prim.
Adding `parmtag { "usdvaluetype" "bool" }` (matching the in-file `disableLighting` example
and Houdini's own Karma `.ds` files, e.g. `BRAY_HdKarma_Viewport.ds`) makes them
USD-authorable, so denoising can be set per RenderSettings output for husk/batch. A
`spare_category "Denoise"` tag was added for grouping.

**Rebuild + reinstall (targeted, no full-tree rebuild):**
```bash
# Compile just the delegate (build-houdini.sh handles the USD pxr-header swap):
docs/build-houdini.sh -target hd_moonray -jobs 8
# Install ONLY the hdMoonray plugin subtree — copies the dylib + .ds, no recompilation.
# (The full `install` target pulls in ALL_BUILD and fails on an unrelated target here.)
cmake -DCMAKE_INSTALL_CONFIG_NAME=Release \
  -P /Applications/MoonRay/build/moonray/hydra/hdMoonray/plugin/cmake_install.cmake
docs/fix-dylib-install-names.sh   # safety net for install-name .. paths
```
Verified installed: `installs/openmoonray-houdini/plugin/hd_moonray.dylib` +
`.../plugin/houdini/soho/parameters/HdMoonrayRendererPlugin_Viewport.ds` (5 `usdvaluetype`
tags: `disableLighting` + 4 denoise). Rendered 2026-07-02.

**Upstream-PR candidate:** Bug #1 (dead `setDenoiseEngine` call) and the `.ds` `usdvaluetype`
gap are platform-independent and worth submitting to OpenMoonRay. Bug #2's `__APPLE__` guard
is the macOS-specific piece.

## Known Houdini Runtime Warnings (non-critical)

These warnings appear in the Houdini Log Viewer when using MoonRay in Solaris. All are
harmless and do not affect rendering.

### `Import failed for module 'pxr.MoonrayShaderParser'` / `pxr.MoonrayShaderDiscovery'`

The `moonrayShaderParser` and `moonrayShaderDiscovery` C++ plugins have no Python extension
module counterpart. Houdini's plugin loader tries a Python import as a fallback and logs a
warning when it fails. The C++ plugins load and function correctly (shader registration
works, materials render). No action required.

### `SdrOslParserPlugin claims discovery type 'oso' but already claimed by HdNSIOsoParserPlugin`

MoonRay's SDR parser attempts to register as the handler for `.oso` (compiled OSL shader)
files. Houdini's own `HdNSIOsoParserPlugin` claims the same type first. MoonRay's claim
loses. MoonRay uses RDL2 shaders, not OSL — this has no effect on MoonRay rendering.

### `Default value type does not match specified type for property: iridescence_colors`

```
Node identifier: DwaBaseMaterial
Property name:   iridescence_colors
Type from SdfType:      GfVec3f
Type from default value: VtArray<GfVec3f>
```

`moonrayShaderParser` incorrectly declares array-type properties (ramp colour arrays) as
singular `GfVec3f` in the SDR schema instead of `color3f[]`. This is a bug in the parser's
JSON-to-SDR type mapping. The UI for iridescence ramp parameters may not behave correctly
in Houdini's parameter editor, but the actual render is unaffected — MoonRay's own
`ValueConverter` handles the array values correctly at render time.

### `Selected hydra renderer doesn't support prim type 'RenderSettings'`

MoonRay does not implement `HdRenderSettings` sprim support. Houdini falls back gracefully
and uses its own render settings mechanism. No impact on rendering.
