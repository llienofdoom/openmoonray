# TODO (later work): relocatable build + macOS `.app` packaging

**Status:** parked investigation — no code/build changes made. Findings verified against the
CMake presets, the deps super-build, `setup.sh`, and `otool` on built dylibs (2026-07-20).

Two questions this doc answers, with a roadmap for when we pick it up:

1. Can it build somewhere other than `/Applications/MoonRay`?
2. Could the finished build be turned into a macOS `.app` package?

---

## Q1 — Build in a different location: **Yes, straightforward.**

The build is **location-relative by design**. `/Applications/MoonRay` is an *anchor created by
symlinks*, not a literal baked into the build graph.

- `CMakeMacOSPresets.json` derives every root from the CMake built-in `${sourceParentDir}`
  (`DEPS_ROOT`, `BUILD_DIR`, both `CMAKE_INSTALL_PREFIX`es, `PREFIX_PXR`). **No
  `/Applications/MoonRay` literal in any preset.** The anchor exists because the docs configure
  with `-S /Applications/MoonRay/openmoonray`, where `openmoonray` is a symlink to
  `source/openmoonray`, making `sourceParentDir` resolve to `/Applications/MoonRay`.
- `building/macOS/CMakeLists.txt:25` derives `InstallRoot` relative to the source tree
  (`${rootSrcDir}/../../../../installs`); it is a CACHE var, overridable with `-DInstallRoot=`.
- `scripts/setup.sh:6-14` computes `omr_root`/`install_root` from its own location via
  `realpath` — fully relocatable, needs no edits.

**To build elsewhere:** clone into a new parent, recreate the same `source/openmoonray` nesting
+ the two convenience symlinks (`<parent>/openmoonray`, `<parent>/building`), rebuild deps into
the new sibling `installs/`. Everything follows `sourceParentDir` automatically.

**The handful of files that hardcode `/Applications/MoonRay`** are *wrapper/runtime helper*
scripts, not the build graph — each needs its literal changed (or parameterized):

| File | Line | Literal |
|---|---|---|
| `docs/macos-houdini/macos/build-houdini.sh` | 27 | `MOONRAY_ROOT=/Applications/MoonRay` |
| `docs/macos-houdini/macos/fix-dylib-install-names.sh` | 43,45 | old/new install prefix |
| `scripts/macOS/setupHoudini.sh` | 1-3 | install dir + Houdini framework |
| `docs/macos-houdini/general/*.sh` | various | example `OMR=`/`HFS=` paths |

Unrelated absolute anchors (independent of the MoonRay path): `HOUDINI_INSTALL_DIR`
(`CMakeMacOSPresets.json:37`), Xcode Python 3.9 in the USD deps target
(`building/macOS/CMakeLists.txt:350-351`), and Homebrew leaf libs under `/opt/homebrew`.

**One caveat:** the autotools deps bake an **absolute** `InstallRoot` into their dylib
install-names, so wherever you build, the install tree is pinned to *that* absolute path until
a fixup pass runs. So you can build anywhere, but the tree isn't freely movable afterward
without rewriting install-names (this is exactly what Q2 solves).

---

## Q2 — Package as a macOS `.app`: **Feasible; it's a bundling project, not a toggle.**

### What already helps (≈70% relocatable)
- MoonRay's own dylibs already use `@rpath` install-ids and `@rpath` cross-references, with
  relative rpaths `@loader_path/` + `@loader_path/../lib` (`OMR_Platform.cmake:67`). Verified
  with `otool` on `libscene_rdl2.dylib`.
- CMake-built deps (boost, tbb, openvdb, embree, …) are already fully `@rpath`.
- `setup.sh` sets the runtime env relative to its own location, so the env layer moves with
  the tree.

### What blocks a self-contained bundle
1. `CMAKE_INSTALL_RPATH_USE_LINK_PATH TRUE` (in 14 CMakeLists) appends an **absolute**
   `/Applications/MoonRay/installs/lib` into every installed binary's `LC_RPATH`.
2. 8 autotools deps (ssl, crypto, curl, log4cplus(+U), microhttpd, uuid, cppunit) carry
   **absolute install-names**; `fix-dylib-install-names.sh` currently rewrites them to a *new
   absolute* prefix, not `@rpath`.
3. **Split install:** MoonRay lands in `installs/openmoonray-houdini`, its deps in the sibling
   `installs/lib` — reached only via the absolute rpath. Must be consolidated into one bundle
   dir so a single relative rpath reaches everything.
4. Runtime library discovery is **purely rpath** — `setup.sh` sets no `DYLD_*` fallback — so
   every absolute path must be rewritten or nothing loads.
5. No existing `.app`/`Info.plist`/`CPack`/bundle-codesign infrastructure anywhere.

### Houdini vs standalone — the important distinction
- **Standalone variant** (`openmoonray-standalone`) → can become a genuine **self-contained,
  double-clickable `.app`**.
- **Houdini variant** (`openmoonray-houdini`, what this fork builds) → the delegate links
  against **Houdini's own** USD 24.3 framework + `libhboost_python311` and is loaded *by*
  Houdini/husk via env-var layering (`PXR_PLUGINPATH_NAME`, `HOUDINI_PATH`). A Houdini-variant
  bundle will **always require a host Houdini install present** — it cannot be fully
  self-contained. For the Houdini side, the natural "package" is a **relocatable Houdini
  package** (`packages/*.json` + a relocatable install dir), which today does not exist (wiring
  is all `setupHoudini.sh` env layering).

### Recommended roadmap (if pursued later)
A **post-install bundling script** — most of the work is `install_name_tool`, not a build
rework:

1. **Standalone `.app`** (cleanest first target):
   - Build the `openmoonray-standalone` preset.
   - Consolidate both prefixes into `MoonRay.app/Contents/{MacOS,Frameworks,Resources}`.
   - `install_name_tool` pass: rewrite the 8 absolute dep ids + all absolute `LC_LOAD_DYLIB`
     to `@rpath`; strip the absolute `/installs/lib` `LC_RPATH` entries (extend
     `fix-dylib-install-names.sh` to emit `@rpath` instead of a new absolute prefix).
   - Bundle the 4 Homebrew leaf libs (`brotli gnutls libidn2 libnghttp2`).
   - Add `Info.plist` + a launcher that sources the (location-relative) `setup.sh`.
   - Optional: ad-hoc codesign the bundle.
2. **Houdini variant**: instead of an `.app`, produce a relocatable Houdini package
   (`packages/moonray.json`) that layers `plugin/pxr` + `plugin/houdini` onto Houdini and
   still depends on the host Houdini — plus the same `install_name_tool` relocatability pass so
   the package dir can live anywhere.
3. **Build-side improvements** to reduce post-processing (optional, deeper): drop
   `CMAKE_INSTALL_RPATH_USE_LINK_PATH`, unify the install prefix, set the autotools deps to
   `@rpath` install-names at build time.

---

## Verification (when/if implemented)
- Build fully in a non-`/Applications/MoonRay` location; confirm `cmake --preset` + deps +
  delegate build with only symlink/wrapper-path changes.
- `otool -L` / `otool -l` across the bundled tree → **zero** absolute paths, all `@rpath`/
  `@loader_path`; run the `dirty_count` check already in `fix-dylib-install-names.sh`.
- Standalone: launch the `.app` on a machine where the build tree was never present.
- Houdini: `render-test` skill (husk render) against the relocated package to confirm the
  delegate still loads and translates a scene.

## Cross-references
- `docs/macos-houdini/macos/fix-dylib-install-names.sh` — existing dylib install-name fixup
  (extend to emit `@rpath` for the bundle).
- `docs/macos-houdini/macos/macos-build.md` — "Distributing to Another Machine" section is the
  closest thing to a current packaging spec (copy `installs/lib`, `installs/plugins`, the
  MoonRay prefix, run the fixup first).
- `cmake_modules/cmake/OMR_Platform.cmake:67` — the `@loader_path` RPATH policy.
- `scripts/setup.sh` / `scripts/macOS/setupHoudini.sh` — the runtime env layer.
