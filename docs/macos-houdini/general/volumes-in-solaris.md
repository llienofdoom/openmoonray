# Volumes in Solaris: authoring VdbGeometry grids for MoonRay

**Date:** 2026-07-06

How to get a VDB volume — density, emission/temperature, velocity — rendering in MoonRay
from Houdini/Solaris (USD). This trips everyone up the first time because emission is **not**
where you'd expect it, and the one attribute you need is easy to author in a form the
delegate silently ignores.

## The mental model: geometry holds the grids, the shader only tints

There are two layers, and they carry different responsibilities:

| Layer | RDL2 object | Responsibility |
|-------|-------------|----------------|
| **Geometry** | `VdbGeometry` | Which `.vdb` file (`model`) and which grids are density / emission / velocity (`density_grid`, `emission_grid`, `velocity_grid`) |
| **Shader** | `VdbVolume` | Tint/scale the baked result — `color_mult` (albedo), `incandescence_gain_mult` (emission), `opacity_gain_mult` (density), `anisotropy` |

**Emission comes from the geometry's `emission_grid`, not the shader.** The `VdbVolume`
shader's `incandescence_gain_mult` is only a multiplier on whatever the geometry emits. If
`emission_grid` is unset, there is nothing to multiply and the volume never glows — no matter
what you do on the shader. This is the #1 source of "my volume won't emit."

## How the delegate converts USD → RDL2 (and the gotcha)

The Hydra delegate (`hdMoonray/lib/hydramoonray/Volume.cc`) reads a USD `Volume` prim's
`field:*` relationships (each an `OpenVDBAsset` with a `fieldName` + `filePath`) and maps
them — but **only two field names are special-cased** (`Volume.cc:59`):

```cpp
if (desc.fieldName == densityToken || desc.fieldName == velocityToken) {
    geometry()->set(desc.fieldName.GetString() + "_grid", grid);  // density_grid / velocity_grid
    geometry()->set("model", filePath);
}
```

So:
- `field:density`  → sets `density_grid` **and** `model` (the `.vdb` path). **Automatic.**
- `field:velocity` → sets `velocity_grid`. Automatic **only if the field is literally named
  `velocity`** — a field named `v` (Houdini's default) is **not** matched.
- `field:temperature`, `field:temperature_rgb`, anything else → **ignored.** There is no
  branch that sets `emission_grid` from a field.

Everything else on the `VdbGeometry` — `emission_grid`, `velocity_grid` (for a non-"velocity"
field), `velocity_scale`, `emission_sample_rate`, a `density_grid` override — must be set
through the **generic primvar override** in `Primvars.cc:183`:

```cpp
// primvars starting with 'moonray:' act to override an RDL object attribute of the same name
if (not strncmp(name.GetText(), "moonray:", 8))
    ... mGeometry->getSceneClass().getAttribute(<name after moonray:>) ... ValueConverter::setAttribute(...)
```

### The gotcha — it MUST be a primvar, in the `primvars:` namespace

Only these three are read; the distinction is subtle and unforgiving:

| USD authoring | Read by MoonRay? |
|---------------|------------------|
| `string primvars:moonray:emission_grid = "temperature_rgb"` | ✅ **yes** — a primvar; `Primvars.cc` strips `moonray:` → sets `emission_grid` |
| `custom string moonray:emission_grid = "temperature_rgb"` | ❌ no — a plain attribute, not in `primvars:` |
| `customData = { dictionary moonray = { string emission_grid = "..." } }` | ❌ no — metadata, invisible to Hydra |

The `custom` keyword is irrelevant either way (primvars are custom by nature). What matters is
the `primvars:` prefix — that's what makes it a *primvar* rather than a plain attribute. Use
`interpolation = "constant"` (it's one value for the whole volume).

## The recipe

For a typical fire/smoke sim (density + temperature emission + velocity):

| What | Where | How |
|------|-------|-----|
| density grid + file | geometry | `field:density` → auto (`density_grid` + `model`) |
| emission grid | geometry | `primvars:moonray:emission_grid = "temperature_rgb"` (constant) |
| velocity grid (motion blur) | geometry | `primvars:moonray:velocity_grid = "v"` (constant) — `field:v` alone won't do it |
| emission tint / brightness | shader | `VdbVolume.incandescence_gain_mult` |
| density boost | shader | `VdbVolume.opacity_gain_mult` |

## Authoring in Houdini/Solaris

**Simplest — a Wrangle** (confirmed working). Set the primvar directly by name in VEX:

```c
s@primvars:moonray:emission_grid = "temperature_rgb";
// and, for motion blur:
s@primvars:moonray:velocity_grid = "v";
```

**Python LOP** (explicit namespace/interpolation control):

```python
from pxr import UsdGeom, Sdf
stage = hou.pwd().editableStage()
prim = stage.GetPrimAtPath("/flame/volume_0")
pv = UsdGeom.PrimvarsAPI(prim).CreatePrimvar(
        "moonray:emission_grid", Sdf.ValueTypeNames.String, UsdGeom.Tokens.constant)
pv.Set("temperature_rgb")
```

**Edit Properties / Configure Primitive LOP:** add a custom property
`primvars:moonray:emission_grid`, type string, interpolation constant, value `temperature_rgb`.

Verify in the Scene Graph Details panel that it appears as `primvars:moonray:emission_grid`
— **not** under customData or as a bare `moonray:` attribute.

## Minimal working USD

```usda
#usda 1.0
def Xform "flame"
{
    def Volume "volume_0" (prepend apiSchemas = ["MaterialBindingAPI"])
    {
        rel field:density = </flame/volume_0/density>
        rel material:binding = </materials/flame>
        # emission_grid has no field branch -> set it as a moonray primvar:
        string primvars:moonray:emission_grid = "temperature_rgb" ( interpolation = "constant" )
        # optional motion blur (field is named "v", not "velocity"):
        # string primvars:moonray:velocity_grid = "v" ( interpolation = "constant" )

        def OpenVDBAsset "density"
        {
            token fieldName = "density"
            asset filePath = @.../torch_rgb_emission.vdb@
        }
    }
}
def Scope "materials"
{
    def Material "flame"
    {
        token outputs:moonray:volume.connect = </materials/flame/vol.outputs:out>
        def Shader "vol"
        {
            uniform token info:id = "VdbVolume"
            color3f inputs:incandescence_gain_mult = (0.2, 0.2, 0.2)   # tint/scale the emission
            token outputs:out
        }
    }
}
```

(Only `field:density` is strictly required — it hands MoonRay both the `.vdb` file and the
density grid. The other `field:*` rels Houdini writes are harmless but unused: MoonRay reads
the emission/velocity grids by name straight from the same file.)

## When to use OpenVdbMap instead

`emission_grid` is the right tool for "this grid IS the volume's emission." Use `OpenVdbMap`
only when you want to **sample a grid into a shading parameter** (e.g. drive `color_mult` or
another input from an arbitrary grid). Two ways to point it at the vdb:
- `vdb_source = "from texture"` + `texture = "<path>.vdb"` + `grid_name` — works today, no
  geometry reference.
- `vdb_source = "from OpenVdbGeometry"` + `openvdb_geometry` (a `SceneObjectVector`
  referencing the VdbGeometry) — requires the delegate SceneObject-reference fix (see
  `delegate-sceneobject-fix/README.md`); before that fix it errors with
  `cannot convert VtArray<string> to SceneObjectVector`.

## Sources

- `moonray/hydra/hdMoonray/lib/hydramoonray/Volume.cc` — field→grid mapping (density/velocity
  only) + `model`.
- `moonray/hydra/hdMoonray/lib/hydramoonray/Primvars.cc:183` — generic
  `primvars:moonray:<attr>` → RDL2 geometry attribute override.
- `shader_json/VdbGeometry.json` — `model`, `density_grid`, `emission_grid`, `velocity_grid`,
  `velocity_scale`, `emission_sample_rate`, …
- `shader_json/VdbVolume.json` — `incandescence_gain_mult`, `color_mult`, `opacity_gain_mult`,
  `anisotropy`.
- Canonical native example: `rats/tests/moonray/volume/emission_vdb/scene.rdla`
  (`VdbGeometry{ emission_grid = "temperature_rgb" }` + `VdbVolume{ incandescence_gain_mult }`).
