# Houdini ↔ MoonRay light fixes

Consolidated write-up of the Solaris/Light-LOP fixes that made the standard Houdini
lights (point, sphere, disk, rectangle, cylinder, distant, env/dome) render correctly
through the MoonRay Hydra delegate. Mesh light and portal light are **not** covered here
(tracked separately as open work).

All three fixes were verified with `hython` (parm/attr authoring) and, for the delegate
change, with `husk` + `HDMOONRAY_RDLA_OUTPUT` (which dumps the exact RDL2 scene the
delegate builds — see `RenderPass.cc:145` → `writeSceneToFile`).

Files live in two trees; edit source **and** the live install:
- Source: `.../source/openmoonray/moonray/moonray_dcc_plugins/houdini/soho/parameters/`
  and `.../moonray/hydra/hdMoonray/lib/hydramoonray/`
- Install: `.../installs/openmoonray-houdini/plugin/houdini/soho/parameters/` and
  `.../installs/openmoonray-houdini/lib/libhydramoonray.dylib`

---

## 1. Light `moonray:class` mapping — point & env DSO errors (`.ds`, no rebuild)

**Symptoms (Light LOP):**
- Point → `Error: Couldn't find DSO for 'PointLight'`
- Env/Dome → `Error: Couldn't find DSO for 'None'`

**Cause.** The `class` parm default in `moonray_Light.ds` /
`HdMoonrayRendererPlugin_Light.ds` is a Python expression mapping Houdini's `lighttype`
menu label → `<label>Light`:
- "Point" → `moonray:class = "PointLight"` — no such RDL2 DSO (MoonRay represents a point
  as a `SphereLight`).
- Dome LOP has no `lighttype` parm and its prim type is `DomeLight_1` (not
  `UsdLuxDomeLight`), so the expression's `else` branch fell through → returned `None` →
  `moonray:class = "None"`.

**Fix (Option B).** Flip the `moonray:class` control-companion default `"set"` → `"none"`
in both generic `.ds` files, so `moonray:class` is no longer auto-authored. The delegate's
own type map then derives the class (`hydramoonray/Light.cc:41-46`):
`sphereLight→SphereLight`, `domeLight→EnvLight`, `distantLight→DistantLight`, etc. Per-type
`.ds` files never authored `class`, so they were already correct.

Patch: `docs/patches/light-class-normalize.patch`.

---

## 2. Distant light renders black by default (`.ds`, no rebuild)

**Symptom.** Distant light produced no error but rendered black; only fixed by manually
enabling Normalize. Not a class bug (`moonray:class` correctly resolved to `DistantLight`).

**Cause.** MoonRay's DistantLight needs `normalized = true` to be usable (tiny angular
extent otherwise → ~0 contribution). All MoonRay lights default `normalized=true` in-shader,
but Houdini's Light LOP authors `inputs:normalize = false` (UsdLux default), and the delegate
honors it: `Light.cc:234` reads `moonray:normalized` first, else falls back to
`inputs:normalize`.

**Fix (scoped to distant only).** A Python default expression does **not** evaluate on a
menu/`_control_` parm (verified — `eval()` returns `''`), so instead:
- Generic `.ds` (`moonray_Light.ds`, `HdMoonrayRendererPlugin_Light.ds`): set the
  `moonray:normalized` control default to static `"set"` **and narrow its `hidewhen` to
  `UsdLuxDistantLight` only** (both control + value parms). Distant now authors
  `moonray:normalized = true` by default; sphere/disk/rect/cylinder are untouched (their
  normalized control is hidden → not authored → unchanged render).
- Per-type `moonray_DistantLight.ds`: `inputs:normalize` control default `"none"` → `"set"`
  (covers the Edit-Properties authoring path).

Tradeoff: area lights lose the (redundant) `moonray:normalized` toggle in the Moonray render
folder; they keep Houdini's standard Normalize toggle. Patch:
`docs/patches/light-class-normalize.patch`.

---

## 3. Point light (`treatAsPoint`) → oversized sphere / spot (C++, rebuild)

**Symptom.** A point light behaved like a 0.5-radius sphere; with a cone, its spotlight
`lens_radius` was 0.5 → an oversized/soft spot.

**Cause.** Houdini's "Point" light authors a `UsdLuxSphereLight` with `treatAsPoint = true`
and no radius (schema fallback 0.5). The delegate ignored `treatAsPoint` entirely, and both
`radius` (SphereLight) and `lens_radius` (SpotLight) map to `HdLightTokens->radius`
(`Light.cc:246,252`), so the point inherited 0.5.

**Fix (`lib/hydramoonray/Light.cc`).** Added a `treatAsPoint()` helper
(`GetLightParamValue("treatAsPoint")` — confirmed forwarded by Hydra at runtime) and, in the
attribute loop, when treatAsPoint is set:
- `radius`/`lens_radius` → `sTreatAsPointRadius` (**0.01**, tunable). **Not 0** — MoonRay
  bakes the sphere radius into the light's transform (`SphereLight.cc:112-123`,
  `mRcpRadius = 1/radius`) and rejects a zero radius as a singular transform
  (`pbr/light/Light.cc:251` "Invalid transform on light - setting to off"), disabling the
  light. Verified: radius 0 turned the light off; 0.01 keeps it on.
- `normalized` → forced `true`. Required because `normalized=false` does not divide radiance
  by area (`SphereLight.cc:132-141`), so a near-point emitting area would drive energy toward
  zero. With `normalized=true`, intensity = power (size-independent) — the standard
  point-light convention.

Both overrides sit after the `moonray:`-prefixed check (`Light.cc:234`), so an explicit
`moonray:radius` / `moonray:normalized` still wins.

**Brightness note.** A point light's power is now `intensity` (was `intensity × ~π` at
radius 0.5, `normalized=false`), so existing point lights render ~3× dimmer and may need
intensity re-tuning. This is the correct point-light behavior; point size / spot sharpness is
tunable via `sTreatAsPointRadius`.

**Rebuild + reinstall** (only `Light.cc` changed → recompile + relink the shared lib):
```bash
cd docs
./build-houdini.sh -target hydramoonray -jobs 8
cmake --install /Applications/MoonRay/build --component hydramoonray
./fix-dylib-install-names.sh
```
Houdini must be restarted to load the rebuilt `libhydramoonray.dylib`.

**Verified** via husk + `HDMOONRAY_RDLA_OUTPUT`: a `treatAsPoint` SphereLight comes through
as `radius = 0.01`, no "invalid transform" warning (light on), `normalized` omitted from the
dump because it equals the shader default `true`; a normal Sphere light is unchanged
(`radius = 0.5`, `normalized = false`). Patch:
`docs/patches/light-treataspoint-delegate.patch` (the `treatAsPoint` hunks; the file's
`renderDelegate` hunks belong to the earlier SceneObject fix).

---

## Reproducing the RDL2 dump verification

```bash
source .../installs/openmoonray-houdini/scripts/setup.sh   # OR set the vars below manually
# NOTE: setup.sh's PYTHONPATH (standalone USD 22.11) crashes husk; when driving husk,
# set only these instead of sourcing setup.sh:
OMR=.../installs/openmoonray-houdini
export HOUDINI_PATH="$OMR/plugin/houdini;&" PXR_PLUGINPATH_NAME="$OMR/plugin/pxr"
export RDL2_DSO_PATH="$OMR/rdl2dso" REZ_MOONRAY_ROOT="$OMR" MOONRAY_CLASS_PATH="$OMR/shader_json"
export HDMOONRAY_RDLA_OUTPUT=/tmp/dump.rdla
husk -R HdMoonrayRendererPlugin -o /tmp/out.exr -f 1 --camera /world/cam scene.usda
# inspect /tmp/dump.rdla for each light's radius / normalized
```

## Sources
- Delegate light mapping: `moonray/hydra/hdMoonray/lib/hydramoonray/Light.cc`
- Light `.ds`: `moonray/moonray_dcc_plugins/houdini/soho/parameters/{moonray_Light,HdMoonrayRendererPlugin_Light,moonray_DistantLight}.ds`
- MoonRay light transform/area: `moonray/moonray/lib/rendering/pbr/light/{Light,SphereLight,SpotLight}.cc`
- RDL dump hook: `hydramoonray/RenderSettings.cc:50` (`HDMOONRAY_RDLA_OUTPUT`), `RenderPass.cc:145`
- Patches: `docs/patches/light-class-normalize.patch`, `docs/patches/light-treataspoint-delegate.patch`
