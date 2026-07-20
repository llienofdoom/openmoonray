# DONE

Completed steps in the Moonray macOS build process.

## From-Scratch Build Sign-Off — COMPLETE ✅ (2026-07-20)

Ran the full documented bootstrap from a **freshly relocated/cloned tree** with empty
`installs/`, `build/`, `build-deps/` (new folder at `/Applications/MoonRay/source/openmoonray`,
symlinks re-created): deps build (`NO_USD`) → post-deps fixups → Houdini configure/build/install
→ husk render. **Result: verified end-to-end via all three render paths** —
1. **husk sign-off render** — `two_triangles_delta/scene.usd` (`RdlMeshGeometry` +
   `PerspectiveCamera` + `UsdPreviewSurface` + `DistantLight` in the RDL2 dump; EXR with real
   HDR content, Max 2.69 / Avg 0.22).
2. **Interactive Houdini** (user-confirmed) — prior scenes open and render as before; all
   accumulated delegate/otls/shader work survived the rebuild intact.
3. **CLI** (user-confirmed) — `moonusd` husk render passed.

26 deps built (USD excluded), full MoonRay + hdMoonray compiled clean, 163 shader `.so` + 175
`shader_json` installed.

**This is exactly the value of the sign-off: it surfaced five real defects on the documented
bootstrap path, all now fixed in committed source** (none were caught before because the prior
build tree was never rebuilt from zero):

1. **`NOUSD` → `NO_USD`** typo in CLAUDE.md + 4 build docs. The CMake option is `NO_USD`
   (`building/macOS/CMakeLists.txt` `if(NOT NO_USD)`); `-DNOUSD=1` is silently ignored (CMake
   warns "variable not used") and USD 22.11 gets built into `installs/` anyway — the stale-USD
   condition that breaks Houdini `libpxr_*` linkage.
2. **MicroHttpd autotools trap** (`building/macOS/CMakeLists.txt`) — the documented Issue 1/3 fix
   was never actually committed. The 0.9.72 tarball's Makefile hardcodes `aclocal-1.16`/
   `automake-1.16`; on automake 1.18 `make install` fails (Error 127). Fixed robustly by
   overriding the regen tools to no-ops (`ACLOCAL=: AUTOCONF=: AUTOMAKE=: AUTOHEADER=: MAKEINFO=:`)
   on build + install, plus `--disable-doc`. (Timestamp-touching — the old documented approach —
   is fragile: `./configure` re-establishes broken mtime orders. Verified the override installs
   `libmicrohttpd` cleanly.)
3. **`build-houdini.sh` hard-required `installs/include/pxr`** — but a `NO_USD` deps build never
   creates it, so the wrapper errored on its own happy path. Now: no standalone pxr = no USD
   22.11 header race, proceed directly against Houdini's toolkit USD.
4. **Xcode dependency cycle** `EnvLight` ↔ `moonray_rendering_pbr_tests` failed the full build.
   Tests aren't needed for the render path; added `BUILD_TESTING: OFF` to the
   `macos-houdini-release` preset (`CMakeMacOSPresets.json`).
5. **`render-usd.sh`** broke under macOS's default bash 3.2 (`set -u` + empty `"${CAM_ARG[@]}"`
   → unbound variable) on the no-camera invocation; and lacked its execute bit. Fixed the
   empty-array guard and `chmod +x`.

Operational note learned: the deps `ExternalProject` build **cannot be incrementally resumed** —
git-based deps re-run their `update` step on every `cmake --build` and cascade a rebuild
downstream, defeating stamp-touching. Run the deps build uninterrupted in one pass.

## Fork-Based Workflow Migration — COMPLETE ✅ (2026-07-18)

Replaced the patch-shuffle model (uncommitted edits + `.patch` files here) with **committed
source in three personal forks** under `github.com/llienofdoom`, all on branch `macos-houdini`:
`openmoonray` (superproject), `hdMoonray`, `moonray_dcc_plugins`. The other 17 submodules track
`OpenMoonRay/*@main`; `moonray` core is not forked. `.gitmodules` rewritten to absolute URLs;
`BUILD_QT_APPS=NO` (Houdini-only); docs folded into `openmoonray/docs/macos-houdini/{macos,general}/`;
a central `CLAUDE.md` + `.claude/skills/{build-houdini,render-test}` added (submodule forks carry
one-line pointer stubs). Reconciliation caught undocumented drift (the `hdMoonray` "sceneobject-ref"
feature) and separated hotl `*.hda.orig` noise (now git-ignored). Verified: clean
`--recurse-submodules -b macos-houdini` clone resolves all 19 submodules with zero 404s and no patch
step; forked-module content byte-identical to the build tree. **This repo is retained as the
research/history archive.** Full detail: `docs/research/fork-based-workflow.md`.

Full from-scratch deps build + compile of the fork: **done 2026-07-20** — see the
"From-Scratch Build Sign-Off" entry above (surfaced + fixed five committed-source defects).

## Houdini TAB Menu Consolidation — COMPLETE ✅ (2026-07-07)

Collapsed the four redundant Moonray VOP TAB-menu placements (`DW Moonray`,
`DreamWorks/All`, `DreamWorks/HIDDEN`, `Digital Assets`) into a single `Moonray`
menu with six suffix-classified subfolders (Materials, Maps, Normal Maps,
Displacement, Display Filters, Volumes) across all 126 shader HDAs. Root cause:
each `.hda` baked those four `<toolSubmenu>` entries into its `Tools.shelf`
section; `HIDDEN` was a 100% duplicate of `All`, and `DW Moonray` was missing 10
nodes. Tool `docs/patches/consolidate_moonray_menu.py` rewrites the section via a
`hotl` expand/collapse round-trip (idempotent, backs up `*.hda.orig`, 21 tests).
Applied to the source otls and the Houdini install otls; user-verified in Houdini
20.5 — single Moonray menu, DreamWorks/DW Moonray gone, nothing under Digital
Assets. Detail: `docs/research/houdini-node-menu-consolidation.md`; spec + plan in
`docs/superpowers/`.

## VdbVolume Houdini Node — COMPLETE ✅ (2026-07-03)

Exposed the `VdbVolume` shader as a first-class Solaris node, mirroring
`BaseVolume`/`CutoutVolume`: VOP HDA (`Vop::DW_MOONRAY::VdbVolume::1.hda`, cloned from
BaseVolume via `hotl`), LOP dialog (`moonray_VdbVolume.ds`), and `moonray_nodes.json`
entry. Also fixed the `python3.9libs`→`python3.11libs` CMake install drift. Verified
headlessly (hython node-load from the install `HOUDINI_PATH` + `bunny.vdb` render).
Full detail in `docs/todo.md` (Resolved) and `docs/research/vdbvolume-node/`; spec + plan
in `docs/superpowers/`.

## Upstream Sync — 2026-07-02

Synced the local clone (`/Applications/MoonRay/source/openmoonray`) from
`2efc058` → `489b926` (8 commits). **No code or submodule-pointer changes** — the
renderer we built is unaffected; no rebuild required. The 8 commits were a project
governance migration to the Academy Software Foundation, including a GitHub org move
from `dreamworksanimation` → `OpenMoonRay`. Actions taken:

- Updated the clone's `origin` remote URL to `https://github.com/OpenMoonRay/openmoonray.git`.
- Fast-forwarded `main`; all local macOS build-fix edits (CMake presets, `setupHoudini.sh`,
  `pxrTargets*.cmake`, `setup.sh`) preserved intact.
- Refreshed org URLs across our docs (`.claude/CLAUDE.md`, `macos-build.md`,
  `general-build.md`, `houdini21-upgrade-path.md`).
- One functional upstream change: `testdata/sphere.usd` canonicalized to
  `DwaBaseMaterial`/`inputs:albedo` (PR #253) — identical to our own Issue 6 fix, so
  fresh clones no longer need the manual edit. Annotated in `build-issues.md` Issue 6.

## Texture Loading Fix — COMPLETE ✅

Plain textures (JPEG, PNG, untiled/unmipped EXR) fail in both standalone and Houdini with
`unknown oiio sample failure` (repeated once per render sample). Root cause: MoonRay's OIIO
`TextureSystem` is initialised in strict mode (`accept_untiled=false`, `accept_unmipped=false`)
— it requires pre-tiled, pre-mipped TX files. See `build-issues.md` Issue 18 for full detail.

**Fix:** Convert textures to TX format before rendering:
```bash
source /Applications/MoonRay/installs/openmoonray-standalone/scripts/setup.sh
maketx input.jpg -o output.tx   # or .exr, .png
```
`maketx` is at `/Applications/MoonRay/installs/bin/maketx`. Verified working in both
standalone (`moonray_gui`) and Houdini Solaris (2026-05-06). ✅

## Project Setup

- [x] Created docs folder structure
- [x] Initialized git repository (main branch)
- [x] Created CLAUDE.md with project context

## Environment

- [x] Verified macOS 15.7.4 Sequoia
- [x] Switched to Xcode 16.4 (Build 16F6, SDK macos15.5)
- [x] Confirmed CMake 3.31.5, Git LFS 3.7.0, Clang 17.0.0 arm64
- [x] Freed disk space — 94GB available on /Applications
- [x] Documented Houdini 20.5.939 Python 3.11 preset fixes required

## Standalone Build — COMPLETE ✅

- [x] Created /Applications/MoonRay/{installs,build,build-deps,source}
- [x] Cloned openmoonray with --recurse-submodules (all 19 submodules)
- [x] Created symlinks (building → source/openmoonray/building, openmoonray → source/openmoonray)
- [x] Configured dep build (cmake ../building/macOS — Xcode 16.4 / AppleClang 17.0.0 confirmed)
- [x] cmake --build . -- -j8 — all 27 deps built and installed ✅
- [x] cmake --preset macos-release — MoonRay configured (AppleClang 17, all deps found, no errors)
- [x] cmake --build --preset macos-release — MoonRay compiled and installed ✅
- [x] source /Applications/MoonRay/installs/openmoonray-standalone/scripts/setup.sh — "Building shader descriptions... ...done"
- [x] Smoke test: moonray_gui launched (exit code 0)
- [x] Headless render confirmed: `moonray -in rectangle.rdla -out /tmp/rectangle.exr` produced output ✅

**Installed binaries include:** moonray, moonray_gui, moonray_gui_v2, hd_render, arras_render, denoise, rdl2_compare, rdl2_convert, rdl2_json_exporter, and more.

**Disk usage (post-build, as of 2026-05-05):**
| Directory | Size |
|---|---|
| /Applications/MoonRay/installs | 1.3 GB |
| /Applications/MoonRay/build-deps | 10 GB |
| /Applications/MoonRay/build | 2.8 GB |

**5 build issues encountered and resolved** — see `docs/research/build-issues.md`

## Houdini Build — COMPLETE ✅

- [x] Edited `CMakeMacOSPresets.json`: standalone preset installs to `openmoonray-standalone` (no rename needed); Houdini 20.5.939, libhboost_python311, install → openmoonray-houdini
- [x] Edited `scripts/macOS/setupHoudini.sh`: updated install dir and Houdini path to 20.5.939
- [x] Edited `building/macOS/pxr-houdini/pxrTargets.cmake`: Python 3.9 → 3.11 paths
- [x] cmake --preset macos-houdini-release — configured with Houdini Python 3.11.7 ✅
- [x] cmake --build --preset macos-houdini-release — compiled and installed to openmoonray-houdini/ ✅
- [x] source /Applications/MoonRay/installs/openmoonray-houdini/scripts/setup.sh — "Building shader descriptions... ...done" ✅

**No dep rebuild needed** — all deps reused from standalone build. Houdini's own USD used via PXR_LIB_PREFIX/PXR_INCLUDE_PREFIX.

**To run standalone:** `source /Applications/MoonRay/installs/openmoonray-standalone/scripts/setup.sh`
**To run Houdini variant:** `source /Applications/MoonRay/installs/openmoonray-houdini/scripts/macOS/setupHoudini.sh && houdini`

**Note:** Use `setupHoudini.sh` (in `scripts/macOS/`), NOT `scripts/setup.sh`, for Houdini. The setupHoudini.sh script strips the standalone USD Python 3.9 bindings from PYTHONPATH and adds `export PXR_PLUGINPATH_NAME` — both required for Houdini's Python 3.11 to work correctly.

## Houdini Rebuild (Issue 11) — COMPLETE ✅

After the initial Houdini build, `hd_moonray.dylib` was still linked against standalone USD 22.11
(`libusd_*.dylib`) rather than Houdini's USD 24.3 (`libpxr_*.dylib`). Two additional issues
were identified and resolved — see `build-issues.md` Issue 11 for full details.

**Fixes applied:**
- `building/macOS/pxr-houdini/pxrTargets.cmake` — removed `${_INCLUDE_PREFIX}` (toolkit/include)
  from all `INTERFACE_SYSTEM_INCLUDE_DIRECTORIES` entries (26 targets) so cmake doesn't classify
  toolkit/include as a system include for consuming targets
- `building/macOS/pxr-houdini/patch-toolkit-headers.sh` (new) — patches Houdini's
  `sdf/childrenProxy.h` to add a `_Set` stub, resolving a clang phase-1 compile error
- `docs/build-houdini.sh` (new) — build wrapper that temporarily renames `installs/include/pxr`
  so clang falls through to toolkit/include (USD 24.3) during compilation

**Build commands:**
```bash
cd /Applications/MoonRay/openmoonray
PYFW=/Applications/Houdini/Houdini20.5.939/Frameworks/Houdini.framework/Versions/Current/Resources/Frameworks/Python.framework/Versions/3.11
cmake --preset macos-houdini-release \
  -DPython_ROOT_DIR="$PYFW" \
  -DPython_EXECUTABLE="$PYFW/bin/python3.11" \
  -DPython_INCLUDE_DIR="$PYFW/include/python3.11" \
  -DPython_LIBRARY="$PYFW/lib/libpython3.11.dylib" \
  -DPYTHON_EXECUTABLE="$PYFW/bin/python3.11"

cd /Applications/MoonRay/docs
./build-houdini.sh -jobs 8

cmake --install /Applications/MoonRay/build --component hd_moonray
cmake --install /Applications/MoonRay/build --component hydramoonray
```

**Result:** `hd_moonray.dylib` links exclusively against `libpxr_*` (Houdini USD 24.3). Verified
with `otool -L` — no `libusd_*` present.

## Houdini Solaris Testing (Issues 12–16) — COMPLETE ✅

Post-build testing in Houdini's Solaris viewport uncovered and resolved five additional issues.
Full details in `build-issues.md` Issues 12–16 and the Known Warnings section.

**Issue 12 — `moonrayShaderDiscovery` / `moonrayShaderParser` linked against `libusd_*`:**
Same USD include-ordering problem as Issue 11. Both SDR plugin dylibs were built against
standalone USD 22.11 from cached `.o` files. Symptoms: "Invalid info:id DwaBaseMaterial"
errors in the Log Viewer; shader parameters have no effect.
Fix: touch source files to force recompile, rebuild with `build-houdini.sh`, reinstall.
```bash
find /Applications/MoonRay/source/openmoonray/moonray/hydra/moonray_sdr_plugins -name "*.cc" -o -name "*.cpp" -o -name "*.h" | xargs touch
./build-houdini.sh -target moonrayShaderDiscovery -jobs 8
./build-houdini.sh -target moonrayShaderParser -jobs 8
cmake --install /Applications/MoonRay/build --component moonrayShaderDiscovery
cmake --install /Applications/MoonRay/build --component moonrayShaderParser
```

**Issue 13 — `cannot convert long long to Int` for render settings:**
On macOS arm64, `long` and `long long` are distinct C++ types. Houdini sends integer values
as `long long`; the original `ValueConverter.cc` only handled `long` and `int`. Fixed by
adding `long long` branches to TYPE_BOOL, TYPE_INT, TYPE_LONG, and TYPE_FLOAT in
`ValueConverter.cc`. Rebuilt and installed `hydramoonray` component.

**Issue 14 — USD native `Sphere` primitive not supported:**
MoonRay's Hydra delegate only renders `mesh`, `basisCurves`, `points`, `volume`, and
`procedural` rprim types. USD implicit geometry (`Sphere`, `Cube`, etc.) is silently skipped.
Use SOP Create or SOP Import with polygon mesh geometry instead.

**Issue 15 — DwaBaseMaterial `diffuse_transmission = 1.0` default:**
The DwaBaseMaterial HDA defaults `diffuse_transmission` to `1.0`, transmitting all diffuse
light through the surface. Front-lit geometry appears black/transparent. Set
`diffuse_transmission = 0.0` in every new DwaBaseMaterial VOP.

**Issue 16 — `iridescence_interpolations: cannot convert TfToken to IntVector`:**
Houdini exports ramp interpolation settings as a single `TfToken` (e.g. `"hermite"`), but
MoonRay's `iridescence_interpolations` is a `TYPE_INT_VECTOR`. Added a `TfToken` silent-skip
in `ValueConverter.cc` `TYPE_INT_VECTOR` case — RDL2 default `[4,4,4,4,4,4,4]` (all-hermite)
is correct. Rebuild: `./build-houdini.sh -target hydramoonray -jobs 8` then install.

**Known harmless warnings** (appear in Log Viewer, no action required):

- `Import failed for module 'pxr.MoonrayShaderParser'` / `pxr.MoonrayShaderDiscovery'` — no Python bindings, C++ plugins work fine
- `SdrOslParserPlugin claims discovery type 'oso' but already claimed by HdNSIOsoParserPlugin` — MoonRay uses RDL2, not OSL
- `Default value type does not match for iridescence_colors` — parser bug for array-type SDR properties, render unaffected
- `Selected hydra renderer doesn't support prim type 'RenderSettings'` — MoonRay doesn't implement HdRenderSettings

**Result:** DwaBaseMaterial renders correctly in Houdini's Solaris viewport with MoonRay. ✅

## Dylib Portability Fix — COMPLETE ✅

8 autotools-based dep dylibs (OpenSSL, libcurl, log4cplus, microhttpd, libuuid, cppunit)
had `..` path segments baked into their install names at build time, e.g.:
`/Applications/MoonRay/source/openmoonray/building/macOS/../../../../installs/lib/libssl.3.dylib`

macOS `dyld` requires all intermediate directories to exist when traversing `..` — any
machine without the `source/` tree cannot load these dylibs.

**Root cause fix:** `building/macOS/CMakeLists.txt` patched — added
`get_filename_component(InstallRoot "${InstallRoot}" ABSOLUTE)` after the `set(InstallRoot ...)`
line so autotools `--prefix=` receives a canonical absolute path on future clean dep builds.

**Existing installation fix:** `docs/fix-dylib-install-names.sh` (new) — rewrites `-id` of
the 8 real dylibs and all `LC_LOAD_DYLIB` references in the ~860 binaries and dylibs in the
installs tree. Run after every dep build as a safety net. On our installation: 862 files fixed.

See `docs/research/build-issues.md` Issue 0 for full detail.

## Qt Platform Plugin Fix — COMPLETE ✅

`moonray_gui` crashed immediately with `Could not find the Qt platform plugin "cocoa" in ""`
on a machine where `installs/plugins/` was absent and `setup.sh` did not set Qt plugin paths.

**Root cause:** `setup.sh` did not set `QT_QPA_PLATFORM_PLUGIN_PATH` or `QT_PLUGIN_PATH`.
Qt's fallback search found nothing on a machine without a system Qt install.

**Fix:** Added to `source/openmoonray/scripts/setup.sh` (and all installed copies):
```bash
export QT_QPA_PLATFORM_PLUGIN_PATH=${install_root}/plugins/platforms
export QT_PLUGIN_PATH=${install_root}/plugins
```

**Distribution requirement:** When copying MoonRay to another machine, `installs/plugins/`
must be included alongside `installs/lib/` and the MoonRay install directory. `installs/bin/`
is NOT needed at runtime (contains dep build tools only).

See `docs/research/build-issues.md` Issue 17 and the "Distributing to Another Machine"
section in `docs/research/macos-build.md` for full details.

## Code Quality Improvements — COMPLETE ✅

Post-testing code improvements applied based on analysis of [OpenMoonRay PR #228](https://github.com/OpenMoonRay/openmoonray/pull/228).

**`ValueConverter.cc` — TYPE_INT integer extraction refactored:**

Added two helpers to replace the ad-hoc `IsHolding<long>() || IsHolding<long long>()`
chains in the TYPE_INT paths:

- `_extractIntegral64(val, &out)` — extracts `int`, `long`, or `long long` into
  `std::int64_t`; returns `false` if the value holds none of these types
- `_narrowIntChecked(sceneObj, attr, value, &out)` — narrows `int64_t` → `Int` with a
  bounds check; logs an error and returns `false` if the value is out of range

Also added `#include <cstdint>` and `#include <limits>`. TYPE_BOOL, TYPE_LONG, TYPE_FLOAT,
and TYPE_INT_VECTOR (Issue 16) are unchanged. Rebuilt and installed `hydramoonray`.

**`scripts/macOS/setupHoudini.sh` — path management improved (both source and installed):**

- Added `prepend_unique_path()` helper — prevents duplicate entries when the script is
  sourced more than once
- Now sets both `PXR_PLUGINPATH_NAME` and `PXR_PLUGIN_PATH` (Houdini uses different names
  across versions)
- `HOUDINI_PATH` is now conditional: prepends MoonRay dirs to an existing path set by
  `houdini_setup`, or builds from scratch using a hardcoded `houdini_resources` fallback
- Debug exports (`HOUDINI_DSO_ERROR`, `TF_DEBUG`) moved to commented-out lines

**Important for clean builds:** Source version (`source/openmoonray/scripts/macOS/setupHoudini.sh`)
is now the canonical version and matches the installed copy. The cmake install step
overwrites the installed script from source, so keep them in sync when patching.

Full notes in `docs/research/build-issues.md` (Issues 8 and 13) and
`docs/research/houdini21-upgrade-path.md`.

## husk vs viewport look parity (subd/SSS) — RESOLVED ✅ (2026-07-09)

**Symptom:** husk CLI renders of a catmullClark head (DwaSkinMaterial SSS + 8K displacement)
looked flatter/waxier than the Solaris viewport — SSS appeared to not contribute — despite both
using the same RenderSettings LOP. History: husk's *default* complexity OOM'd (mesh_resolution
256), so `--complexity 0` had been added as a workaround, which overshot.

**Root cause (verified by diffing RDL dumps from both paths):** scene translation, not render
settings. `--complexity 0` → refineLevel 0 → the delegate disables subdivision entirely
(`is_subd=false`, `smooth_normal=false`, `Mesh.cc:212-218`) → raw faceted cage, displacement at
cage vertices only. Additionally husk defaults meshes to **force single-sided** while the
viewport `.ds` defaults `doubleSided=1` → **force two-sided** (`GeometryMixin.cc:140-147`);
backlit ear translucency needs those backfaces.

**Fix (verified):** `HDMOONRAY_DOUBLESIDED=1` + `--complexity 1`. Filtered RDL geometry
sections then byte-identical to the viewport dump; render ~63s / 1.3GB peak; visual match
confirmed viewport vs MPlay vs EXR ("almost identical"). `~/bin/moonusd` updated accordingly.

**Method worth reusing:** dump the delegate's exact RDL2 scene from both paths
(`HDMOONRAY_RDLA_OUTPUT` for husk; the viewport "Rdl output" field for interactive — the env
var is overridden by the hip's saved `sceneviewrenderopts`), filter out bulk arrays, `diff -u`.

Full analysis: `docs/research/hdmoonray-viewport-vs-husk-scene-translation.md`.
Remaining upstream gaps tracked in `docs/todo.md` ("hdMoonray upstream gaps").
