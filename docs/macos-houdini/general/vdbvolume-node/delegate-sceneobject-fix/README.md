# hdMoonray delegate fix — SceneObject / SceneObjectVector references from USD

**Date:** 2026-07-06
**Status:** Implemented + compiles/links; runtime verification pending (interactive Houdini)

## Problem

The hdMoonray delegate could not set any RDL2 shader/camera/light attribute of type
`SceneObject` or `SceneObjectVector` from USD. `ValueConverter::setAttribute` had:

```cpp
case TYPE_SCENE_OBJECT:          // not supported yet
case TYPE_SCENE_OBJECT_VECTOR:   // not supported yet
```

so any authored value fell through to
`"<obj>.<attr>: cannot convert VtArray<string> to SceneObjectVector"`.

This is **pervasive** — it affects every attribute that references another scene object:
- `OpenVdbMap` / `OpenVdbMap_v2` `openvdb_geometry` (read a grid from a VdbGeometry — e.g.
  temperature for emission)
- every camera: `medium_geometry`, `medium_material`; `BakeCamera.geometry`;
  `ProjectCameraMap*.projector`
- potentially lights/light-filters referencing geometry/projectors

## Fix

Central change in `ValueConverter` (one place, all callers benefit):

1. `setAttribute` gains a `RenderDelegate* renderDelegate = nullptr` parameter.
2. `TYPE_SCENE_OBJECT`: resolve a single authored prim path (`std::string` / `SdfPath` /
   `TfToken`) → `renderDelegate->getSceneObject(path)` and set it. Empty path clears the ref.
3. `TYPE_SCENE_OBJECT_VECTOR`: resolve an array of paths
   (`VtArray<string>` / `SdfPathVector` / `VtArray<SdfPath|TfToken>`, or a single path) →
   build a `SceneObjectVector` and set it.
4. Unresolved paths log a `Logger::warn` and are skipped (the referenced prim may not exist
   or not be synced yet — the known geometry-ordering fragility).
5. The 5 call sites that handle object attributes pass their delegate:
   `Material.cc`, `Camera.cc`, `Light.cc` (×2), `LightFilter.cc`.

Files touched (see `hdMoonray-sceneobject-ref.patch`): `ValueConverter.{h,cc}`,
`Material.cc`, `Camera.cc`, `Light.cc`, `LightFilter.cc` (all in
`moonray/hydra/hdMoonray/lib/hydramoonray/`, which is its own git submodule).

## Build / install

**Rebuild with `docs/build-houdini.sh`, NOT a plain `cmake --build`.** A plain
`cmake --build --target hydramoonray` compiles against the standalone USD 22.11 headers in
`installs/include/pxr` (they win the include race — see build-issues.md Issues 10–12), so
recompiled objects get the `pxrInternal_v0_22` namespace while the delegate expects Houdini's
`pxrInternal_v0_24`. The result is a **mixed-USD `hydramoonray`** whose e.g.
`RenderSettings::getRenderSetting(v0_22 TfToken)` no longer matches the delegate's
`(v0_24 TfToken)` import — Houdini then silently fails to load the release delegate and it
**disappears from the viewport renderer menu** (debug delegate, if not rebuilt, may linger).
`build-houdini.sh` temporarily renames `installs/include/pxr` away so Houdini USD 24.3 wins,
and patches the toolkit `childrenProxy.h`. A **clean** rebuild is required (incremental won't
recompile the already-contaminated `.o`):

```bash
cd /Users/llien/Dropbox/Projects/dev/moonray/docs
./build-houdini.sh -target hydramoonray clean build   # v0_24 only
./build-houdini.sh -target hd_moonray  build           # relink
# sanity: nm .../Release/libhydramoonray.dylib | grep -oE 'pxrInternal_v0_[0-9]+' | sort -u
#         -> must be pxrInternal_v0_24 ONLY (no v0_22)
```

**Install via cmake (rewrites rpaths to the self-contained layout) — NOT a raw `cp`.** The build-tree
dylibs carry absolute build-tree `LC_RPATH`s; the install step rewrites them to the
self-contained layout (`@loader_path/../lib`, `/installs/lib`) and installs `hydramoonray`
into `.../lib`. A raw `cp` of the build-tree `hd_moonray.dylib` into the install ships
build-tree rpaths, so Houdini fails to load it and **the release "Moonray" delegate silently
disappears from the viewport renderer menu** (the untouched debug delegate remains). Correct:

```bash
cmake -DCMAKE_INSTALL_CONFIG_NAME=Release -P \
  /Applications/MoonRay/build/moonray/hydra/hdMoonray/lib/hydramoonray/cmake_install.cmake
cmake -DCMAKE_INSTALL_CONFIG_NAME=Release -P \
  /Applications/MoonRay/build/moonray/hydra/hdMoonray/plugin/hd_moonray/cmake_install.cmake
```

Verify the installed delegate's rpaths match the debug delegate (no `/MoonRay/build` paths):
`otool -l .../installs/openmoonray-houdini/plugin/hd_moonray.dylib | grep -A2 LC_RPATH`.
Also do NOT `install_name_tool` the installed dylibs to chase headless `@rpath/Python` — it
does not fix the deeper linkage defect and only risks the install.

## Verification status

- ✅ Compiles and links cleanly (both targets BUILD SUCCEEDED 2026-07-06).
- ✅ Installed to the live Houdini delegate.
- ⚠️ **Headless render verification blocked** by a *separate, pre-existing* defect: the
  Houdini-variant delegate cannot be loaded by any headless CLI (`husk`, `hython`
  usdrender, `openmoonray-houdini/bin/hd_render`) because of the broken `@rpath/Python`
  linkage (rpath carries a stray `/lib`, so `@rpath/Python` misses Houdini's framework
  binary at `Python.framework/Versions/3.11/Python`). Every headless attempt fails at
  plugin load with `Unable to load render plugin: HdMoonrayRendererPlugin`. This is the
  same linkage defect logged as the `openmoonray-houdini/bin/hd_render` todo — out of scope
  for this fix. **Interactive Houdini Solaris loads the delegate correctly** (Houdini sets
  up the runtime env), so that is the verification path.

To verify interactively: author `OpenVdbMap_v2` with `vdb source = "from OpenVdbGeometry"`,
`openvdb_geometry` referencing the VdbGeometry prim, `grid_name = "temperature"`, bound into
a `VdbVolume` input — it should now resolve and render instead of erroring. Likewise a
camera `medium_geometry`/`medium_material` node reference should work.

## Upstream candidate

Platform-independent, self-contained, fixes a real gap. Good OpenMoonRay PR candidate.
