# hdMoonray: why husk renders don't match the Solaris viewport (scene translation)

Date: 2026-07-09. Test scene: `~/Desktop/moonray_tests/usd/head_v02.usda` (catmullClark head,
DwaSkinMaterial SSS, 8K displacement, fog volume box, 3 RectLights). Symptom: husk output had
flatter/weaker subsurface than the interactive viewport, "waxy" denoised skin, despite both
using the same RenderSettings prim (viewport set to take settings from the node).

## TL;DR

Render settings were **not** the problem. The Hydra **scene translation** differed: with the
`--complexity 0` workaround (added earlier to avoid the subd-tessellation OOM), husk sends the
head to MoonRay as a **raw un-subdivided polygon cage, force single-sided, no smooth normals**.
The viewport sends a **catClark subd surface (default `mesh_resolution=2`), force two-sided**.
SSS through thin geometry (ears lit by the rim light) needs the backfaces and the smooth limit
surface; single-sided + faceted cage kills it, and OIDN then smears what's left.

Parity recipe (verified identical geometry translation, renders in ~63 s / 1.3 GB peak):

```bash
HDMOONRAY_DOUBLESIDED=1 husk head_v02.usda ... --complexity 1 ...
```

## Method: dump the delegate's RDL from both paths and diff

The delegate can write the exact RDL2 scene it builds (`RenderPass.cc:140-150`):

- **husk:** `HDMOONRAY_RDLA_OUTPUT=/path/husk_dump.rdla husk <file.usda> ...`
  (env var is the default of the `rdlOutput` render setting, `RenderSettings.cc:50`).
- **Viewport:** the env var does NOT work — Houdini restores the viewport display options
  saved in the hip (`sceneviewrenderopts` block), which contain `rdlOutput=""` and override
  the env default. Set the **"Rdl output"** field in the viewport's Moonray render settings
  panel instead (only editable when the viewport uses viewport settings, not the node; this
  does not affect geometry translation, which comes from displayStyle, not render settings).

Filter both dumps to scalar attributes (strip `vertex_list*`, `vertices_by_index`, uv/normal
lists, index arrays) and `diff -u`. Note the rdla writer skips default-valued attributes, so
an *absent* attribute means "RDL default".

## Findings (head_v02, 2026-07-09)

Per-mesh geometry attrs on every RdlMeshGeometry:

| RDL attr          | husk `--complexity 0`     | viewport                  | RDL default |
|-------------------|---------------------------|---------------------------|-------------|
| `is_subd`         | `false` (raw cage)        | absent → **true**         | true        |
| `mesh_resolution` | `1`                       | absent → **2**            | 2.0         |
| `smooth_normal`   | `false`                   | absent → **true**         | true        |
| `side_type`       | `"force single-sided"`    | absent → default (2-sided)| —           |

Mechanism (all in `moonray/hydra/hdMoonray`):

- `Mesh.cc:205-229` (`syncSubdivScheme`): `mesh_resolution = 1 << refineLevel`;
  refineLevel = Hydra displayStyle complexity (husk `--complexity N`, N = refine level).
  husk's *default* refineLevel is high → `mesh_resolution 256` → subd tessellation OOM
  (see todo entry from 2026-07-08).
- `Mesh.cc:212-218`: **refineLevel < 1 disables subd entirely** (`is_subd=false`) and
  `Mesh.cc:237-241` then also forces `smooth_normal=false`. So `--complexity 0` is not
  "coarse subd", it is *no subd at all*.
- `GeometryMixin.cc:140-147`: `side_type = force single-sided` unless the `doubleSided`
  render setting or the prim's USD `doubleSided` attr is true. The Houdini viewport `.ds`
  defaults `doubleSided` to **1** (`HdMoonrayRendererPlugin_Viewport.ds:380-388`); husk's
  default comes from `HDMOONRAY_DOUBLESIDED` (unset → false). Hence viewport two-sided,
  husk single-sided.
- Per-mesh primvar overrides beat all of this: `moonray:mesh_resolution`,
  `moonray:adaptive_error`, `moonray:smooth_normal` (`Mesh.cc:222-235`),
  `moonray:side_type` (`GeometryMixin.cc:24,141`). `adaptive_error > 0` gives
  camera-adaptive tessellation *capped* by `mesh_resolution` — the right tool for heavy
  displacement without OOM.

Non-geometry diffs seen in the dumps (expected/benign):

- SceneVariables differ when the viewport is in viewport-settings mode (that's the settings
  panel, not translation): `pixel_samples 3`, `max_diffuse/glossy/mirror/volume_depth
  1/5/5/5`, `enable_presence_shadows true` vs the node's `pixel_samples 2` + defaults.
  Worth knowing the viewport-settings defaults differ from renderer defaults.
- `film_width_aperture` differs per output aspect (`aspectRatioConformPolicy
  adjustApertureWidth`): same vertical FOV, wider horizontal in a wide viewport pane.
- Viewport adds extra RenderOutputs (depth, primId, instanceId AOVs) and a
  `__HoudiniFreeCamera__`.

## Delegate bug found on the way

`RenderSettings.cc:53`: the `decodeNormals` descriptor default reads
`HDMOONRAY_DOUBLESIDED` (copy-paste; should be its own env var). Setting
`HDMOONRAY_DOUBLESIDED=1` silently defaults decodeNormals on. Harmless for scenes using
Moonray-native shading nodes (decodeNormals only rewrites `UsdUVTexture` normal inputs,
`Material.cc:363-369`), but a landmine for USD-Preview-Surface scenes. Upstream-worthy.

## Verified result

With `--complexity 1` + `HDMOONRAY_DOUBLESIDED=1`, the filtered RDL geometry sections of the
husk dump and viewport dump are **byte-identical**. Render: ~63 s, 1.3 GB peak (vs OOM at
default complexity; vs flat-SSS cage at complexity 0). Visual: translucency in ears/nose
restored, denoiser artifacts on the jaw gone.

## Recommendations

- In `~/bin/moonusd`: change `--complexity 0` → `--complexity 1` and add
  `export HDMOONRAY_DOUBLESIDED=1`.
- For higher displacement fidelity than the viewport (final frames): keep `--complexity 1`
  and author per-mesh primvars on heavy geo, e.g. `moonray:mesh_resolution = 8..16` (+
  optionally `moonray:adaptive_error = 1.0`), instead of raising complexity globally.
- Alternative to the env var: author USD `doubleSided = true` on the meshes that need it
  (delegate honors the prim attr) — renderer-agnostic and works identically in both paths.

## Sources

- hdMoonray source: `/Applications/MoonRay/source/openmoonray/moonray/hydra/hdMoonray`
  - `lib/hydramoonray/Mesh.cc` (syncSubdivScheme, lines 196-241)
  - `lib/hydramoonray/GeometryMixin.cc` (side_type, lines 139-148)
  - `lib/hydramoonray/RenderSettings.cc` (descriptors/env defaults, lines 46-64; apply, 99-126)
  - `lib/hydramoonray/RenderPass.cc` (rdla write, lines 140-150)
  - `plugin/houdini/soho/parameters/HdMoonrayRendererPlugin_Viewport.ds` (doubleSided default, ~line 380)
- RDL defaults: `scene_rdl2/lib/scene/rdl2/CommonAttributes.h:39-76` (mesh_resolution 2.0,
  adaptive_error 0, smooth_normal true), `moonray/dso/geometry/RdlMesh/attributes.cc:153`
  (is_subd true), `SceneVariables.cc:348-441` (pixel_samples 8, depths 2/2/3/1, etc.)
- Dumps/renders: `~/Desktop/moonray_tests/usd/{husk_dump,viewport_dump,husk_parity_dump}.rdla`,
  `~/Desktop/moonray_tests/usd/img/head_v02_parity/head_v02_parity.0001.exr` (2026-07-09)
