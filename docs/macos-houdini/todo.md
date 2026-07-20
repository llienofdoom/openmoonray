# TODO

## Fork Migration — DONE (2026-07-18)

Work moved from the patch-shuffle model to committed source in `github.com/llienofdoom` forks
(`openmoonray`/`hdMoonray`/`moonray_dcc_plugins`, branch `macos-houdini`). See
`docs/research/fork-based-workflow.md` and the `done.md` entry. Existing items below are
preserved as historical record. Remaining verification:

- [x] Full from-scratch deps build + compile of the fork on a clean machine — **DONE 2026-07-20**
      (freshly relocated tree, empty installs/build/build-deps). Rendered end-to-end via husk.
      Surfaced + fixed five committed-source defects on the documented bootstrap path — see
      `done.md` "From-Scratch Build Sign-Off". This closes the final sign-off.

## Pre-Build Decisions (needs your input)

- [x] **Disk space:** 94GB free on /Applications — sufficient for full build. ✅
- [x] **Xcode:** Switched to Xcode 16.4 (Build 16F6, SDK macos15.5). Matches documented Sequoia config. ✅

## Pre-Build Fixes Required (Houdini variant only)

These edits must be made to the cloned source before running `cmake --preset macos-houdini-release`:

- [x] Edit `source/openmoonray/CMakeMacOSPresets.json`:
      - `HOUDINI_INSTALL_DIR` → `/Applications/Houdini/Houdini20.5.939`
      - `PXR_BOOST_PYTHON_LIB` → `libhboost_python311-mt-a64.dylib` (was `python39`)
      - `CMAKE_PREFIX_PATH` → `$env{PREFIX_PXR};$env{DEPS_ROOT}` (PREFIX_PXR first — Issue 9 fix)
- [x] Edit `source/openmoonray/scripts/macOS/setupHoudini.sh`:
      - `HOUDINI_PATH` → `/Applications/Houdini/Houdini20.5.939`
- [x] Edit `source/openmoonray/building/macOS/pxr-houdini/pxrTargets.cmake`:
      - `HPYTHONINC` → `.../toolkit/include/python3.11`
      - `HPYTHONLIB` → `.../Frameworks/Python.framework/Versions/3.11/lib/libpython3.11.dylib`
- [x] Edit `source/openmoonray/building/macOS/pxr-houdini/pxrTargets-release.cmake`:
      - `usdRiImaging` → `libpxr_usdRiPxrImaging.dylib` (Houdini 20.5 rename — Issue 9 fix)

## Build Steps

- [x] Create directory structure: `mkdir -p /Applications/MoonRay/{installs,build,build-deps,source}`
- [x] Clone with `--recurse-submodules` (Git LFS is ready)
- [x] Create symlinks (building → source/openmoonray/building, openmoonray → source/openmoonray)
- [x] Run dependency build — all 27 deps installed ✅
- [x] Build MoonRay with correct preset (`macos-release`) ✅
- [x] Source `setup.sh` and run smoke test ✅

## Standalone Build — DONE

The standalone (non-Houdini) build is complete as of 2026-05-05. All fixes documented in `docs/research/build-issues.md`.

For a clean fresh build incorporating all discovered fixes, see the "For a fresh build" notes in each build-issues.md entry.

## Optional Next Steps

- [x] Run headless render smoke test: `moonray -in /source/testdata/rectangle.rdla -out /tmp/rectangle.exr` ✅
- [x] Run USD render test: `hd_render -in testdata/sphere.usd -out /tmp/sphere.exr` ✅ (see Issues 6 & 7)
- [ ] Write a clean step-by-step build guide distilling research docs + all fixes
- [x] Houdini variant build — installed to installs/openmoonray-houdini/ ✅
- [ ] Document whether build-deps/ and build/ can be deleted post-install (~12.8 GB to reclaim)

## Future Work

- [ ] **Automatic TX texture conversion via USD asset resolver (`ArResolver`)**

  MoonRay requires all textures to be pre-tiled and pre-mipped TX files (see Issue 18).
  The ergonomic solution is a custom USD `ArResolver` subclass that intercepts texture
  file paths at render time and transparently redirects plain image files to their TX
  equivalents, auto-generating them if missing.

  How it would work:
  - Subclass `ArResolver` and override `Resolve()` / `_Resolve()`
  - If the resolved path ends in `.jpg`, `.png`, `.exr` (or similar), check for a
    corresponding `.tx` file in the same directory (or a configurable TX cache dir)
  - If the `.tx` exists, return it; if not, invoke `maketx` to generate it, then return it
  - Register the resolver via `AR_DEFAULT_RESOLVER` or `plugInfo.json` so it's picked up
    automatically by both `hd_render` and Houdini's Solaris MoonRay delegate

  Alternatives considered (less preferred):
  - **`#if 0` branch in `TextureSampler.cc`** — flipping the `#if 1` to `#if 0` enables
    OIIO's `automip`/`autotile` at render startup, but it's a compile-time change, adds
    latency, and was explicitly left as dead code by DreamWorks
  - **HDA shelf tool** — a "Prepare Textures" Python button that walks all `ImageMap`
    nodes and calls `maketx` via subprocess before rendering; practical for Houdini-only
    workflows but doesn't help with `moonray_gui` / `hd_render` directly
  - **Batch shell script** — simplest; scans USD or RDLA for texture references and bulk
    converts; no integration with the render pipeline

  `maketx` is already installed at `/Applications/MoonRay/installs/bin/maketx`.
  The resolver would need to be a separate Python or C++ USD plugin.

- [ ] **Suppress `pxr.MoonrayShaderParser/Discovery` Python warnings** — Houdini logs
  `ModuleNotFoundError: No module named 'pxr.MoonrayShaderParser'` (and Discovery) on startup.
  The source tree has stub `__init__.py` files for both plugins whose sole purpose is to
  suppress this warning, but they were never added to the cmake install step.
  Because Houdini's `pxr` is a regular package (not a namespace package), the stubs must be
  installed directly into Houdini's pxr directory — no env-var-only fix is possible:
  ```bash
  PXR=/Applications/Houdini/Houdini20.5.939/Frameworks/Python.framework/Versions/3.11/lib/python3.11/site-packages/pxr
  mkdir -p "$PXR/MoonrayShaderParser" "$PXR/MoonrayShaderDiscovery"
  cp .../moonrayShaderParser/__init__.py "$PXR/MoonrayShaderParser/"
  cp .../moonrayShaderDiscovery/__init__.py "$PXR/MoonrayShaderDiscovery/"
  ```
  The warnings are harmless — C++ plugins load and render correctly regardless.

- [x] **Expose `VdbVolume` shader as a first-class Houdini node — DONE 2026-07-03**
  (Path B implemented in full — see the "VdbVolume Houdini node" Resolved entry below and
  `docs/research/vdbvolume-node/` for the generators, HDA sections, and rebuild steps. The
  original analysis is kept below as the historical record of how it was scoped.)

  The `VdbVolume` shader is required for non-trivial VDB volume rendering (reads VDB grids
  directly for density/temperature/color), but it isn't exposed in the Houdini Solaris UI
  the way `BaseVolume` and `CutoutVolume` are. Authoring a USD `Volume` + `OpenVDBAsset`
  alone produces the `Material.cc:514` error `"<geom>.material: <materialId> has no
  moonray or fallback shaders"` because no shader with an `outputs:moonray:volume`
  terminal is bound.

  **Discovery status:** `shader_json/VdbVolume.json` is installed, so the shader IS already
  registered with USD's Sdr registry via the `moonrayShaderDiscovery` plugin
  (`moonray/hydra/moonray_sdr_plugins/moonrayShaderDiscovery/discoveryPlugin.cpp`). That
  means `info:id = "VdbVolume"` works in hand-authored USD today — the gap is purely a
  Houdini UI integration gap.

  **What BaseVolume/CutoutVolume have that VdbVolume lacks** (compare to confirm scope):
  - `moonray/moonray_dcc_plugins/houdini/otls/Vop::DW_MOONRAY::BaseVolume::1.hda`
    — VOP node for the TAB menu inside a Material Builder. Must be authored in Houdini
    (it's a binary HDA, not editable as text).
  - `moonray/moonray_dcc_plugins/houdini/soho/parameters/moonray_BaseVolume.ds`
    — ~650-line dialog script defining parameter UI. Loaded via the
    `loputils.addDialogScriptFolder()` call in `python3.9libs/pythonrc.py`. *Note: that
    pythonrc.py is in `python3.9libs/` only — Houdini 20.5 uses Python 3.11, so it does
    not currently run for this build (separate issue worth checking).*
  - Entry in `moonray/moonray_dcc_plugins/houdini/moonray_nodes.json` — a comprehensive
    metadata mirror (moonray↔houdini name/label, defaults, help, menus). **No open-source
    consumer reads this file** (only referenced by the CMake install rule); it appears to
    be consumed by an external/DreamWorks-internal tool. Editing it alone will NOT expose
    the node in Houdini.

  **Two implementation paths:**
  - **Path A (quick, no source edits):** Use the existing Sdr discovery. In Solaris,
    author a Shader prim with `info:id = "VdbVolume"` either via `Configure Primitive` /
    `Edit Properties` LOPs, or pick it from the `Material Library` LOP's USD shader picker.
    Wire its `outputs:volume` to the Material's `outputs:moonray:volume`, then bind the
    Material to the USD `Volume` prim. This works today.
  - **Path B (full integration):** Author `Vop::DW_MOONRAY::VdbVolume::1.hda` in Houdini,
    write `moonray_VdbVolume.ds` (mirror `moonray_BaseVolume.ds` structure, ~600 LOC),
    add the corresponding `VdbVolume` entry to `moonray_nodes.json` for completeness, and
    update `moonray_dcc_plugins/houdini/CMakeLists.txt` if needed. Multi-hour task; only
    worthwhile if interactive shader authoring inside Houdini's Material Builder is
    required regularly.

  Source/install reference paths:
  - shader runtime: `installs/openmoonray-houdini/rdl2dso/VdbVolume.so`
  - shader desc:    `installs/openmoonray-houdini/shader_json/VdbVolume.json`
  - canonical USD example: `moonray/hydra/hdMoonray/testSuite/geometry/volume/volume.usda`
  - canonical RDLA:        `moonray/hydra/hdMoonray/hats/geometry/geometry_volume.canonical.rdla`

- [ ] **Audit & close Moonray-shader → Houdini exposure gaps**

  A diff between `installs/openmoonray-houdini/shader_json/*.json` (175 shaders, the
  authoritative catalog registered with USD's Sdr by `moonrayShaderDiscovery`) and the
  three Houdini exposure layers — `moonray_nodes.json` metadata, `otls/Vop::DW_MOONRAY::*.hda`
  VOP nodes, `soho/parameters/moonray_*.ds` parameter UIs — surfaces three categorical
  gaps and one isolated case. All gap shaders are real, discoverable via Sdr, and usable
  via direct USD authoring (`info:id = "<ShaderName>"`); they're just not first-class
  Houdini nodes.

  **Gap 1 — Light Filters missing HDAs (9 shaders, uniform pattern):**
  `BarnDoorLightFilter`, `ColorRampLightFilter`, `CombineLightFilter`, `CookieLightFilter`,
  `CookieLightFilter_v2`, `DecayLightFilter`, `IntensityLightFilter`, `RodLightFilter`,
  `VdbLightFilter`. Each has `shader_json` + a `moonray_nodes.json` entry (type
  `LightFilter`) + a `.ds` parameter file in `soho/parameters/`. The missing piece is the
  HDA at `moonray_dcc_plugins/houdini/otls/Vop::DW_MOONRAY::<Name>::1.hda`. Highest-leverage
  fix after VdbVolume — common workflow, uniform gap. Each HDA must be authored inside
  Houdini (binary file, not text-editable).

  **Gap 2 — Display Filters missing `.ds` (18 shaders, uniform pattern):**
  `BlendDisplayFilter`, `ClampDisplayFilter`, `ColorCorrectDisplayFilter`,
  `ConstantDisplayFilter`, `ConvolutionDisplayFilter`, `DiscretizeDisplayFilter`,
  `DofDisplayFilter`, `HalftoneDisplayFilter`, `ImageDisplayFilter`, `OpDisplayFilter`,
  `OverDisplayFilter`, `RampDisplayFilter`, `RemapDisplayFilter`, `RgbToFloatDisplayFilter`,
  `RgbToHsvDisplayFilter`, `ShadowDisplayFilter`, `TangentSpaceDisplayFilter`,
  `ToonDisplayFilter`. Each has `shader_json` + `moonray_nodes.json` + HDA, but no
  `moonray_<Name>.ds`. DisplayFilters are post-process AOV operations (not bound to
  geometry), so the HDA likely carries parameter UI internally and the missing `.ds`
  may be intentional. Lower priority — verify by trying to attach one to an AOV in
  Solaris and seeing whether parameters are reachable.

  **Gap 3 — `VdbVolume` missing all three pieces:** ✅ RESOLVED 2026-07-03 — all three
  pieces (HDA, `.ds`, `moonray_nodes.json` entry) now shipped. See the "VdbVolume Houdini
  node" Resolved entry below.

  **Intentional non-gaps (do not attempt to fill):**
  - `UsdPreviewSurface`, `UsdPrimvarReader_{float,float2,float3,int,normal,point,vector}`,
    `UsdTransform2d`, `UsdUVTexture` — Moonray ships these as compatibility shims; Houdini
    already exposes them natively via the standard USD shader registry.
  - `_v2` / `_v3` versioned shaders — the HDA filename's version digit maps to the `_vN`
    suffix (e.g. `Vop::DW_MOONRAY::NoiseMap::2.hda` ↔ shader `NoiseMap_v2`). Coverage
    already exists; not a gap.

  **Reproduce the audit:** the python diff script used to produce these lists walks
  `shader_json/` (175 entries), parses `moonray_nodes.json` top-level keys, regex-matches
  HDA filenames `Vop::DW_MOONRAY::(.+?)::(\d+)\.hda` (version 1 → bare name, version N>1 →
  `Name_vN`), regex-matches `.ds` filenames `^moonray_(.+)\.ds$`, then filters by
  `moonray_type ∈ {Map, NormalMap, Material, Displacement, Volume, DisplayFilter,
  LightFilter, DwaBaseLayerable, DwaBaseHairLayerable}` to ignore non-shader RDL types
  (cameras, lights, geometries, sets, SceneVariables, etc.). Re-run this after any
  Moonray version bump to catch regressions or newly-added shaders.

  **Verification of the discovery mechanism** (so future readers don't re-derive it):
  Nothing in the open-source codebase reads `moonray_nodes.json` at runtime — confirmed
  by `grep -rln "moonray_nodes" /Applications/MoonRay/source/openmoonray/` returning only
  `moonray_dcc_plugins/houdini/CMakeLists.txt:9` (the install rule). Actual shader
  discovery happens via `moonray/hydra/moonray_sdr_plugins/moonrayShaderDiscovery/`
  walking `*.json` files in the Sdr search path. `moonray_nodes.json` is a metadata
  mirror consumed by an external (presumably DreamWorks-internal) tool.

- [ ] **hdMoonray upstream gaps: subd tessellation defaults & controls** (workflow side RESOLVED
  2026-07-09, see `docs/done.md` "husk vs viewport look parity" and
  `docs/research/hdmoonray-viewport-vs-husk-scene-translation.md`; these delegate-side gaps remain
  and are upstream-worthy):
  - The default `mesh_resolution` (256 from husk's default refineLevel) is **pathological for
    subd** — the delegate should cap/adapt it for catmullClark so batch renders don't OOM by
    default (`Mesh.cc:228`).
  - There is **no RenderSettings-level subd/tessellation control** in the Moonray RenderSettings
    tab (`HdMoonrayRendererPlugin_Global.ds` has an adaptive-tessellation *camera* + adaptive
    *sampling*, but no mesh-resolution/refine control). Users are stuck between the global husk
    `--complexity` and per-mesh `moonray:mesh_resolution`. A scene-level knob would help.
  - `decodeNormals` descriptor default reads `HDMOONRAY_DOUBLESIDED` (copy-paste bug,
    `RenderSettings.cc:53`) — setting that env var silently defaults decodeNormals on. Only
    affects `UsdUVTexture`-based materials (`Material.cc:363-369`).
  - (Separate, also seen: MoonRay hard-crashes with a `std::vector` out-of-range — libc++ "vector" —
    when a mesh has an **empty constant primvar** like `displayColor`/`displayOpacity`; it should
    warn+skip instead of crashing the whole render. Data-side fixable in the export.)

- [ ] **Moonray mesh lights, light filters & procedurals in Houdini — root cause + tiered plan**

  **CORRECTION (2026-07-07):** the earlier premise here ("MeshLight works today via direct
  USD authoring, just needs an authoring LOP") is **wrong for the Houdini build.** Verified
  (husk + interactive Solaris + RDL dump): a `MoonrayMeshLight` prim — and a standard
  `UsdLuxGeometryLight` — is **silently dropped**; MoonRay never receives it as a light and
  the emitter mesh becomes plain render geometry.

  **Root cause (confirmed):** the `hdMoonrayAdapters` plugin (`MoonrayMeshLightAdapter`,
  `MoonrayLightFilterAdapter`, `ProceduralAdapter`) is **linked against the standalone MoonRay
  USD 22.11 (`libusd_*`), not Houdini's USD 24.3 (`libpxr_*`)** — `otool -L` shows 26 `libusd_`
  / 0 `libpxr_` vs the working `hd_moonray.dylib`'s 24 `libpxr_` / 0 `libusd_`. Houdini's
  UsdImaging can't load it, so those custom prim types are never imaged. The plugin is
  **intentionally excluded** from the Houdini build (`plugin/CMakeLists.txt`:
  `if (NOT MOONRAY_USE_HOUDINI) add_subdirectory(adapters)`) because it **fails to compile**
  against USD 24.3 — the `light*Adapter.h` include chain hits `SdfChildrenProxy::_Set`
  (documented as an Issue in `research/build-issues.md`). The installed copy is a
  standalone-built leftover.

  **Tiered plan:**
  - **Tier A — mesh lights (IN PROGRESS, 2026-07-07).** Delegate-side workaround, no adapter
    needed. Author a *carrier* light prim UsdImaging recognizes (e.g. `SphereLight`, tiny
    radius) + `uniform token moonray:class = "MeshLight"` + `string moonray:geometry` +
    MeshLight params; the delegate reads `moonray:class` first (`Light.cc:73`) → builds a
    `MeshLight`, and a new `moonray:geometry` **string fallback** in the geometry handler
    (`Light.cc:205`) attaches the emitter geometry (reusing `Mesh::geometryForMeshLight` +
    the SceneObject-path resolution added by the delegate-sceneobject-fix). Plus a Python LOP
    HDA to author it and suppress the cosmetic "class may not be compatible" warning. Build
    into BOTH the Houdini and standalone `hydramoonray` variants so it renders in the Solaris
    viewport, husk, standalone `hd_render` (farm), and RDL export → `moonray`. Spec:
    `docs/superpowers/specs/2026-07-07-moonray-mesh-light-authoring-design.md`; plan:
    `docs/superpowers/plans/2026-07-07-moonray-mesh-light-authoring.md`.

    **Tier A status (2026-07-08) — WORKING in the Houdini viewport, pending more testing.**
    Delegate fix (Houdini variant) + the "Moonray Mesh Light" LOP HDA are done and
    user-verified emitting in the Solaris viewport. Full write-up:
    `docs/research/mesh-light-node/README.md`; delegate patch:
    `docs/patches/mesh-light-delegate.patch`. Done:
    - Delegate: `moonray:geometry` string fallback + suppressed class warning (Houdini
      `hydramoonray` rebuilt/installed). **CRITICAL learning:** the emitter MUST be
      invisible (out of the render layer) or MoonRay rejects it ("cannot be referenced …
      in Layer" → "MeshLight did not load"). The node always hides it.
    - HDA `Lop::moonray_mesh_light::1.0`: full MeshLight `.ds` param UI (Properties/Map/…,
      same layout as other Moonray lights, generic control-companion authoring), USD
      prim-path picker for the emitter, always-hide emitter, working **On** (drives the
      carrier prim's visibility — the delegate ignores `moonray:on`, `Light.cc:224`),
      color/intensity/exposure/visible_in_camera default to Set-or-Create,
      `visible_in_camera` defaults "force off", node under the **Lights** TAB menu.
    - Generators/tests in `docs/research/mesh-light-node/` (`gen_hda.py`, `verify_hda.py`,
      `verify_delegate.sh {houdini,standalone}`, `fixture.usda`).

    **Tier A OPEN items (pinned for later):**
    - **Standalone/farm build (deferred):** the delegate source fix is committed but the
      **standalone `hydramoonray` variant is not yet built** with it, so farm `hd_render`
      / RDL export don't have it. Blocked on: `macos-release` and `macos-houdini-release`
      share one `$env{BUILD_DIR}` (mutually exclusive configs) — building standalone
      reconfigures/clobbers the Houdini build tree config (not the install). Do it in the
      next standalone rebuild.
    - **Interactive emitter-change re-sync (FOLLOW-UP):** moving the emitter (or toggling
      its visibility live) does NOT update the running render — the delegate never marks
      the referencing MeshLight dirty when its emitter geometry changes. Fix: a mesh→light
      reverse map registered at geometry resolution (`Mesh::geometryForMeshLight` /
      `Light` geometry handler) + `MarkSprimDirty` on the referencing lights in
      `Mesh::Sync`. `RenderDelegate` already holds `mRenderIndex` + `mLights`. Non-trivial;
      may need iteration to trigger MoonRay's MeshLight rebuild. (Same root cause as the
      live-visibility-toggle breakage — one fix covers both.)
    - **GL viewport preview lights (FOLLOW-UP, low priority):** the carrier is a
      MoonRay-only construct, so Houdini's GL/Storm viewport shows no light. Could author a
      hidden Storm-only preview light later.
    - **Final whole-branch review** (SDD) not yet run — do it when this work is wrapped.

  - **Tier A-style — light filters (LATER, 9 shaders).** Same piggyback, no adapter port
    needed: the delegate already reads `moonray:class` for filters (`LightFilter.cc:214`
    `createSceneObject(classToken)`) and natively supports the `lightFilter` Sprim
    (`RenderDelegate.cc` `lightFilterToken`), and **stock** UsdImaging images a base
    `UsdLuxLightFilter` prim (Houdini ships `usdImaging/lightFilterAdapter.h`). So: author a
    stock `UsdLuxLightFilter` + `moonray:class="BarnDoorLightFilter"` (etc.), wire to a light
    via the filter relationship. Parameter-only filters (BarnDoor, ColorRamp, Decay,
    Intensity, Rod) are trivial; reference-carrying ones (Cookie, Vdb, Combine) reuse the
    same string→SceneObject fallback as mesh geometry. Do after mesh lights land.

  - **Tier B/C — port `hdMoonrayAdapters` to Houdini USD (LATER, larger).** Required ONLY for
    **procedurals** (`ProceduralAdapter : UsdImagingGprimAdapter` — custom geometry, no native
    carrier to piggyback, so no delegate-side workaround exists) and for the cosmetic "native
    `MoonrayMeshLight` prim, no carrier, no warning" cleanliness. Means fixing the USD 24.3
    compile break (`SdfChildrenProxy::_Set` in the `light*Adapter.h` chain — forward-declare /
    trim the include, or port the adapters to the 24.3 UsdImaging/scene-index API), then
    enabling + linking the adapters against Houdini `libpxr_*` in the Houdini build. Same class
    of work as the broader "unify on Houdini USD / retire the dual-USD split" idea (would also
    fix the dual-linked houdini `hd_render`). Not a prerequisite for A or the filters.

  Reference infra (unchanged): `rdl2dso/MeshLight.so`, `shader_json/MeshLight.json`,
  `soho/parameters/moonray_MeshLight.ds` (42 parms), canonical (standalone-only) example
  `moonray/hydra/hdMoonray/testSuite/light/mesh_basic/scene.usd`.

- [ ] **`openmoonray-houdini/bin/hd_render` crashes — dual USD/Python linkage** (found
  2026-07-03 during VdbVolume verification). The Houdini-variant `hd_render` CLI aborts
  (dyld exit 134 → `TF_DEBUG_ENVIRONMENT_SYMBOL multiple debug symbol definitions`): the
  binary directly links BOTH the standalone build's USD (Python 3.9 via `libboost_python39`)
  and Houdini's bundled USD (Python 3.11), so two USD copies load in one process and
  double-register `Tf` debug symbols. Its compiled `LC_RPATH`s also don't resolve
  (`@rpath/Python`, `@rpath/Python3.framework/.../3.9/Python3`). Deeper than Issue 8 (that was
  a Python *module* dlopen; this is the executable's own link deps). **Workaround:** use
  `openmoonray-standalone/bin/hd_render` for headless USD renders (works fine). Not a
  VdbVolume problem — the shader/node render correctly. Fix would relink the houdini
  `hd_render` against a single consistent USD/Python.

## Still Unknown

- [ ] Actual total build time (multi-session, not measured precisely)
- [ ] Whether `-exec_mode xpu` Metal GPU path renders correctly (GUI launched but render not confirmed)
- [ ] Whether Xcode 26.1.1 + macOS 26 SDK causes issues (not tested; Xcode 16.4 used throughout)
- [ ] Houdini MoonRay render delegate working in Solaris (plugin built + installed; test pending)


## Resolved

> Consolidated write-up of the three light fixes below (class mapping, distant normalize,
> `treatAsPoint`): `docs/research/houdini-light-fixes.md`.

- [x] **Point light (`treatAsPoint`) → near-point in the delegate** (2026-07-07). Houdini's
  "Point" light authors a `UsdLuxSphereLight` with `treatAsPoint = true` and **no** radius, so
  the radius fell back to the UsdLux schema default (0.5). The hdMoonray delegate ignored
  `treatAsPoint` entirely (`grep treatAsPoint Light.cc` → 0 hits), so a point light became a
  0.5-radius sphere — indistinguishable from a Sphere light — and, with a cone, a spotlight
  whose `lens_radius` (mapped from the same `HdLightTokens->radius`, `Light.cc:252`) was 0.5,
  i.e. an oversized/soft spot. **Fix** (`lib/hydramoonray/Light.cc`, see
  `docs/patches/light-treataspoint-delegate.patch` — the treatAsPoint hunks; the file's
  `renderDelegate` hunks are the earlier SceneObject fix): added a `treatAsPoint()` helper
  (`GetLightParamValue("treatAsPoint")` — confirmed forwarded by Hydra at runtime) and, in the
  attribute loop, when treatAsPoint is set:
  - `radius`/`lens_radius` → `sTreatAsPointRadius` (0.01, a tunable constant). **Not 0** —
    MoonRay bakes the sphere radius into the light transform (`SphereLight.cc:112-123`,
    `mRcpRadius = 1/radius`) and rejects a zero radius as a singular transform
    (`pbr/light/Light.cc:251` "Invalid transform on light - setting to off"), which would
    disable the light. Verified: radius 0 turned the point light off; radius 0.01 keeps it on.
  - `normalized` → forced `true`. Required because `normalized=false` (Houdini's default) does
    **not** divide radiance by area (`SphereLight.cc:132-141`), so a near-point emitting area
    would drive the energy toward zero. With `normalized=true` the intensity is the power
    (size-independent), which is the standard point-light convention.

  Both overrides sit in the schema-fallback path (after the `moonray:`-prefixed check at
  `Light.cc:234`), so an explicit `moonray:radius`/`moonray:normalized` still wins. Rebuilt +
  reinstalled `hydramoonray` (`docs/build-houdini.sh -target hydramoonray`). **Verified via
  husk + `HDMOONRAY_RDLA_OUTPUT`** (dumps the exact RDL2 the delegate builds): a `treatAsPoint`
  SphereLight comes through as `radius = 0.01`, no "invalid transform" warning (light on),
  `normalized` omitted from the dump because it now equals the shader default `true`; a normal
  Sphere light is unchanged (`radius = 0.5`, `normalized = false`). **Brightness note for the
  user:** a point light's power is now `intensity` (was `intensity × ~π` at radius 0.5,
  `normalized=false`), so existing point lights render ~3× dimmer and may need intensity
  re-tuning — this is the correct point-light behavior. Spot sharpness / point size is tunable
  via `sTreatAsPointRadius`. Interactive Solaris confirmation still worthwhile.

- [x] **Houdini light class-mapping + distant-normalize defaults** (2026-07-07). Creating
  Moonray lights via the Solaris **Light LOP** produced two DSO-not-found errors and one
  render-blank case:
  - **Point light** → `Error: Couldn't find DSO for 'PointLight'`. Root cause: the `class`
    parm default in `moonray_Light.ds` / `HdMoonrayRendererPlugin_Light.ds` is a Python
    expression mapping Houdini's `lighttype` menu label → `<label>Light`, so "Point" became
    `moonray:class = "PointLight"` (no such RDL2 DSO — Moonray represents a point light as a
    `SphereLight`). Houdini authors a Point as a `UsdLuxSphereLight` prim (radius 0), so only
    the class *name* was wrong.
  - **Env/Dome light** → `Error: Couldn't find DSO for 'None'`. Same expression: the dome LOP
    has no `lighttype` parm and its prim type is `DomeLight_1` (not `UsdLuxDomeLight`), so the
    expression's `else` branch fell through and returned `None` → `moonray:class = "None"`.
  - **Distant light** → no error but rendered black; fixed only by manually enabling Normalize.
    Not a class bug (`moonray:class` correctly resolved to `DistantLight`). Cause: MoonRay's
    DistantLight needs `normalized = true` to be usable (tiny angular extent otherwise → ~0
    contribution), but Houdini's Light LOP authors `inputs:normalize = false` (UsdLux default),
    which the delegate honors over the shader's own `normalized=true` default (`Light.cc:234`
    reads `moonray:normalized` first, else falls back to `inputs:normalize`).

  **Fix (`.ds`-only, no rebuild)** — see `docs/patches/light-class-normalize.patch`:
  1. **Class (Option B):** flipped the `moonray:class` control-companion default `"set"` →
    `"none"` in both generic files, so `moonray:class` is no longer auto-authored. The
    delegate's own type map (`Light.cc:41-46`: `sphereLight→SphereLight`, `domeLight→EnvLight`,
    `distantLight→DistantLight`, …) then derives the correct class. Per-type `.ds` files never
    authored `class`, so they were already fine.
  2. **Distant normalize (scoped to distant only):** a Python default expression does **not**
    evaluate on a menu/`_control_` parm (verified — returns `''`), so instead set the
    `moonray:normalized` control default to static `"set"` and **narrowed its `hidewhen` to
    `UsdLuxDistantLight` only** (both control + value parms) in the two generic files. Distant
    lights now author `moonray:normalized = true` by default; sphere/disk/rect/cylinder are
    untouched (their normalized control is hidden → not authored → same render as before). Also
    set the per-type `moonray_DistantLight.ds` `inputs:normalize` control default → `"set"` for
    the Edit-Properties authoring path.

  Applied to source (`moonray_dcc_plugins/houdini/soho/parameters/`) **and** the live install
  (`installs/openmoonray-houdini/plugin/houdini/soho/parameters/`). **Verified headlessly with
  hython** (cook a Light LOP → inspect authored USD attrs): Point/Sphere→`SphereLight` prim
  with no `moonray:class`; Distant→`DistantLight` prim, no `moonray:class`, `moonray:normalized=
  True`; Disk/Rect/Cylinder→correct prim types, no class, no normalized; Dome→`class_control`
  evaluates `none`, `moonray:class` not authored. **Interactive Solaris re-verify still worth
  doing**, especially that the newer `DomeLight_1` schema actually renders as `EnvLight` (if the
  delegate doesn't recognize that Hydra token, use the older `domelight::2.0` = `UsdLuxDomeLight`
  — separate delegate concern, not this fix). Tradeoff: area lights lose the (redundant)
  `moonray:normalized` toggle in the Moonray render folder; they retain Houdini's standard
  Normalize toggle.

- [x] **Houdini TAB menu consolidation — single `Moonray` menu** (2026-07-07). The
  matnet/VOP TAB menu listed the Moonray shader nodes under four redundant
  placements (`DW Moonray`, `Digital Assets`, `DreamWorks/All`, `DreamWorks/HIDDEN`),
  all baked into each `.hda`'s `Tools.shelf` `<toolSubmenu>` entries. Investigation:
  `HIDDEN` == `All` (identical 126-node duplicate); `DW Moonray` was the incomplete
  one (missing 10 nodes: BaseMaterial, ColorCorrectNukeMap, GlitterFlakeMaterial,
  LayerMap, MacroFlakeMaterial, NoiseMap, NoiseWorleyMap×2, OpSqrtMap, TwoSidedMap).
  **Fix:** `docs/patches/consolidate_moonray_menu.py` rewrites each `Tools.shelf` to a
  single `Moonray/<Subfolder>` entry via a `hotl -t`/`hotl -l` round-trip. Suffix-based
  classification, 100% coverage: Materials 25, Normal Maps 11, Maps 65, Displacement 4,
  Display Filters 18, Volumes 3 (= 126). Idempotent, backs up `*.hda.orig`, 21 tests
  (unit + hotl integration, hermetic against the live otls tree's migration state).
  Applied to the source otls and the `openmoonray-houdini`
  install otls (standalone tree left alone — CLI-only, no matnet menu). User-verified in
  Houdini 20.5: single Moonray menu with 6 subfolders, DreamWorks/DW Moonray gone,
  nothing under Digital Assets. Full write-up:
  `docs/research/houdini-node-menu-consolidation.md`; spec + plan in `docs/superpowers/`.

- [~] **hdMoonray: SceneObject / SceneObjectVector references from USD** (2026-07-06) —
  IMPLEMENTED, interactive verification pending. The delegate's `ValueConverter::setAttribute`
  marked `TYPE_SCENE_OBJECT` / `TYPE_SCENE_OBJECT_VECTOR` "not supported yet", so any
  attribute referencing another scene object errored with `cannot convert VtArray<string> to
  SceneObjectVector`. Pervasive: `OpenVdbMap(_v2).openvdb_geometry` (read a grid — e.g.
  temperature — from a VdbGeometry), every camera's `medium_geometry`/`medium_material`,
  `BakeCamera.geometry`, `ProjectCameraMap*.projector`. **Fix:** central — `setAttribute`
  gains a `RenderDelegate*` and resolves authored prim path(s) → `getSceneObject()` for both
  types; the 5 object-handling call sites (Material/Camera/Light×2/LightFilter) pass their
  delegate. Compiles + links (`hydramoonray` + `hd_moonray` BUILD SUCCEEDED), installed.
  ⚠️ Headless render verification blocked by the pre-existing `@rpath/Python` defect (same as
  the houdini `hd_render` item below) — verify in interactive Solaris. Full write-up + patch:
  `docs/research/vdbvolume-node/delegate-sceneobject-fix/`.
  - **anisotropy slider range fixed** (2026-07-06): VdbVolume node's `anisotropy` was
    `range { 0 10 }` (inherited from BaseVolume); the shader defines [-1, 1], default 0.
    Corrected to `range { -1 1 }` in `gen_ds.py`, `moonray_VdbVolume.ds`, and the HDA
    DialogScript; `.hda`/`.ds` rebuilt + reinstalled.
  - **surface_opacity_threshold is NOT broken** (clarification): it only feeds the volume
    "surface" T-distance computation (`PathIntegratorVolume.cc:1531`) used for depth/Z,
    surface-position (P), and deep output — it has no effect on the beauty/scattering RGB, so
    changing it correctly shows no change in a normal render.

- [x] **VdbVolume Houdini node — first-class Solaris exposure** (2026-07-03). The
  `VdbVolume` shader is now exposed the same way `BaseVolume`/`CutoutVolume` are. Three
  pieces added, mirroring BaseVolume (spec + plan under `docs/superpowers/`):
  1. **VOP HDA** `otls/Vop::DW_MOONRAY::VdbVolume::1.hda` — cloned from BaseVolume's HDA by
     editing `hotl -X` text sections and re-collapsing (`hotl -C`), headless, no GUI. 9 attrs
     from `VdbVolume.json`. hython gate confirmed: type `Vop::DW_MOONRAY::VdbVolume::1` =
     "Moonray VdbVolume", 9/9 params, volume output.
  2. **LOP dialog** `soho/parameters/moonray_VdbVolume.ds` — generated (`gen_ds.py`) with the
     `hou.text.encode`d `xn__inputs…` names + Set/Block/Do-Nothing control companions,
     byte-for-byte matching BaseVolume conventions (incl. real-tab help indentation).
  3. **Metadata** `moonray_nodes.json` `VdbVolume` entry — generated (`gen_nodes_json.py`),
     full BaseVolume-shape parity (5 top-level keys incl. `folders_sorted`/`folders_with_parms`,
     per-parm `aliases`/`bindable`). Parity-only; no open-source runtime consumer.
  Also fixed the **`python3.9libs`→`python3.11libs` CMake install drift** so a clean rebuild
  ships the `.ds` loader for Houdini 20.5's Python 3.11 (`moonray_dcc_plugins/houdini/
  CMakeLists.txt` + new `python3.11libs/pythonrc.py`; the installed tree already had a
  `python3.11libs`→`python3.9libs` symlink, which is why existing volume nodes loaded).
  Installed to the live tree and verified headlessly: the node loads via the install
  `HOUDINI_PATH`, and a `bunny.vdb` scene renders (Max 0.42, no `Material.cc:514`) via the
  standalone `hd_render` (the houdini `hd_render` CLI is separately broken — see the
  dual-USD-linkage item under the task list). All generators, HDA sections, preserved
  deliverables, and the `vdb_test.usda` scene live in `docs/research/vdbvolume-node/`.
  Reference: `moonray/hydra/hdMoonray/testSuite/geometry/volume/volume.usda`.

- [x] **Houdini denoiser "Optix mode not supported in this build"** — CONFIRMED WORKING
  2026-07-02. Standalone denoising was always fine; Houdini errored. Three fixes, all in
  `hdMoonray`:
  1. `ArrasSettings::applySettings()` never called `setDenoiseEngine()` → the OIDN toggle
     was dead and the engine stayed at its `OPTIX` default.
  2. `setDenoiseEngine()` had no macOS guard → added `#if defined(__APPLE__)` forcing OIDN
     (OptiX is compiled out on macOS).
  3. **The decisive one:** `ArrasRenderer::connect()` set the denoise *mode* on each freshly
     created `ClientReceiverFb` but not the *engine*, so the receiver kept its OPTIX default
     and the correct engine value never reached it. Added the engine push in `connect()`.
  Fixes #1/#2 are necessary but not sufficient without #3. Rebuilt/reinstalled `hd_moonray`.
  Full write-up: `research/build-issues.md` Issue 19. Upstream-PR candidate (#1 and #3 are
  platform-independent).

- [~] **Per-output denoise control on the RenderSettings node** — bare-named parms did NOT
  route (confirmed: RenderSettings toggles had no effect on the render), because husk only
  forwards `moonray:`-namespaced RenderSettings-prim attributes. Full fix implemented:
  - `_Global.ds`: renamed the 4 denoise parms to the Houdini-encoded namespaced names
    (`xn__moonrayenableDenoise_o8a` = `moonray:enableDenoise`, etc. — encodings computed with
    `hou.text.encode()` via hython, verified against known `moonray:sceneVariable:*` mappings).
  - `ArrasSettings.cc`: added the 4 `moonray:*` tokens and a `denoiseFlag` helper in
    `applySettings()` that coalesces the bare (viewport) and namespaced (RenderSettings-prim)
    keys, presence-checking the namespaced one via `getRenderSetting().IsEmpty()` (get<bool>()
    on a missing key would error).
  - Rebuilt/reinstalled `hd_moonray` + both `.ds` files 2026-07-02.
  - **Namespacing alone still didn't author** (toggles set but render unchanged). Missing piece
    (spotted by the user): the RenderSettings-node settings need a **control companion parm**
    (the "Set or Create / Block / Do Nothing" menu) — that's what tells Houdini's Render
    Settings LOP to actually author the attribute onto the USD prim. Every other MoonRay
    setting has one; ours didn't. Added a `_control_` companion per denoise toggle, named
    `encode(attr + "_control")` (e.g. `xn__moonrayenableDenoise_control_pmb` =
    `moonray:enableDenoise_control`, via `hou.text.decode` of the fps control to confirm the
    convention), default `"set"` so denoise authors on by default. Also changed the delegate
    `denoiseFlag` from OR to **override** semantics (a RenderSettings prim value now wins over
    the viewport value, so per-output denoise can also be turned OFF). Rebuilt/reinstalled
    2026-07-02.
  - **CONFIRMED WORKING 2026-07-03** — RenderSettings-node denoise drives the render, with
    per-output override. Control parms default to `"set"` (Set or Create) so the node authors
    denoise ON by default, independent of the viewport (a `"none"`/Do-Nothing default was
    tried but rejected: Do-Nothing means "inherit", which in Solaris = the viewport, and the
    user wanted the node itself to drive the default). Disable per-output by unchecking the
    value (authors off) or setting the control to Do Nothing/Block. All 4 toggles default ON;
    Denoising tab sits after Sampling.
  - Note: the denoise control menus omit "Add if Exists"/"Multiply if Exists" — correct for
    booleans (matches MoonRay's other bool settings, e.g. Two Stage Output); those ops are
    numeric-only.

- [x] **RenderSettings-node UX tweaks** (2026-07-02): moved the Denoising tab to sit right
  after Sampling; defaulted all 4 denoise toggles ON in both `_Viewport.ds` and `_Global.ds`.

- [x] **RenderSettings-node layout cleanup** (`HdMoonrayRendererPlugin_Global.ds`, source in
  `moonray_dcc_plugins/houdini/soho/parameters/`) — MoonRay's generator emitted a batch of
  SceneVariables as top-level parms *outside* any `group{}`, so they rendered loose beneath
  the tab switcher. Moved them into their proper tabs: Fps→Frame; Sampling Mode, Min/Max/
  Target Adaptive Samples, Light Sampling Mode/Quality, Crypto Uv→Sampling; Batch/Progressive/
  Checkpoint Tile Order + Two Stage Output→Driver. Also relocated the new Denoising folder to
  sit among the groups (was appended after the loose parms, so it never joined the tab bar).
  `.ds`-only, reinstalled 2026-07-02. Braces verified balanced, no loose parms remain.