# MaterialX / DwaBase / OSL Feature Mapping

Research into whether translations between DreamWorks DwaBaseMaterial, MaterialX
`standard_surface`, and OSL shaders are feasible — and what would be lost.

---

## How MaterialX actually works in Moonray today

Moonray has **zero native MaterialX code**. No `ND_*` DSOs exist in `rdl2dso/`.

When you use `MtlxStandard` in Houdini Solaris + MoonRay delegate, USD 24.3
automatically translates the `ND_standard_surface_surfaceshader` network to a
`UsdPreviewSurface` material before it reaches Moonray. The `UsdPreviewSurface.so`
DSO is what actually renders.

### UsdPreviewSurface → Moonray BSDF mapping

| Input | Moonray implementation | Works? |
|---|---|---|
| `diffuseColor` | LambertianBRDF | ✅ |
| `roughness` | GGX microfacet (isotropic) | ✅ |
| `metallic` | conductor / dielectric blend | ✅ |
| `opacity` | transmission weight | ✅ |
| `opacityThreshold` | presence cutout | ✅ |
| `emissiveColor` | additive emission | ✅ |
| `clearcoat` + `clearcoatRoughness` | additive dielectric lobe | ✅ |
| `ior` | Fresnel for dielectric/transmission | ✅ |
| `normal` | tangent-space normal | ✅ |
| `displacement` | attribute declared, **never evaluated** | ❌ dead code |
| `occlusion` | JSON: "Ignored by Moonray" | ❌ |
| `specularColor` / `specularWorkflow` | code: "can't support until Schlick implemented" | ❌ stubbed |

### What gets silently dropped by the USD translation

MaterialX `standard_surface` inputs with no `UsdPreviewSurface` equivalent:
- Subsurface scattering (subsurface, subsurface_color, subsurface_radius)
- Sheen (sheen, sheen_color, sheen_roughness)
- Thin film (thin_film_thickness, thin_film_ior)
- Anisotropy (specular_anisotropy, specular_rotation, tangent)
- Complex MaterialX math node networks beyond basic texture→surface connections

### Native USD shaders with first-class Moonray DSOs

These work regardless of MaterialX translation:

| DSO | Notes |
|---|---|
| `UsdUVTexture` | file, st, wrapS/T, scale, bias, sourceColorSpace, UDIM via `<UDIM>`. **TX format required.** |
| `UsdPrimvarReader_float/float2/float3/int/normal/point/vector` | all variants |
| `UsdTransform2d` | UV transforms |

---

## DwaBase feature inventory

`DwaBaseMaterial` is composed from modular JSON files. Full feature list:

**Core PBR:** albedo, diffuse_roughness (0=Lambertian, >0=Oren-Nayar), metallic, specular,
roughness, anisotropy, shading_tangent (Vec2f), refractive_index (IOR)

**Subsurface scattering:** bssrdf (normalized diffusion / dipole / random walk),
scattering_color, scattering_radius, crease_attenuation, sss_trace_set,
enable_sss_input_normal, resolve_self_intersections

**Clearcoat:** clearcoat, clearcoat_model (Beckmann/GGX), clearcoat_refractive_index,
clearcoat_roughness, clearcoat_thickness (Beer-Lambert absorption),
clearcoat_attenuation_color, clearcoat_bending (ray bending through coat),
use_independent_clearcoat_normal, clearcoat_normal_dial

**Iridescence:** iridescence, iridescence_apply_to (specular or clearcoat),
iridescence_color_control (hue-wheel or color ramp), iridescence_primary/secondary_color,
iridescence_positions/colors/interpolations, iridescence_thickness, iridescence_exponent,
iridescence_at_0/90_incidence

**Fuzz:** fuzz, fuzz_roughness, fuzz_albedo, use_absorbing_fuzz_fibers,
fuzz_normal, fuzz_normal_dial

**Transmission (refractive solid):** transmission, transmission_color,
use_independent_transmission_refractive_index, use_independent_transmission_roughness,
use_dispersion, dispersion_abbe_number

**Diffuse transmission:** diffuse_transmission, diffuse_transmission_color,
diffuse_transmission_blending_behavior

**Fabric (woven):** warp_color, warp_roughness, weft_color, weft_roughness,
use_independent_weft_attributes, warp_thread_direction, warp_thread_coverage,
warp_thread_elevation

**Glitter:** glitter, glitter_seed, glitter_space, glitter_density, glitter_randomness,
glitter_layering_mode (physical / additive), style A+B (size, roughness, color, texture)

**Hair (HairMaterial_v3):** hair_color, refractive_index, cuticle_layer_thickness,
primary specular (offset, roughness, tint), secondary specular (offset, independent
roughness, tint), glint (roughness, eccentricity, min/max_twists, saturation),
transmission lobe (offset, roughness, azimuthal roughness, tint), multiple scattering

**Render-engine concepts (not portable):** diffuse_lightset, specular_lightset,
sss_trace_set

---

## Core feature alignment

All three are built on the same physical BSDFs. These map near 1:1 with different
parameterization but equivalent physics:

| DwaBase | MtlX standard_surface | OSL closure |
|---|---|---|
| `albedo` | `base_color` | `diffuse()` / `oren_nayar_diffuse()` |
| `diffuse_roughness` | `diffuse_roughness` | Oren-Nayar parameter |
| `metallic` | `metalness` | `conductor_bsdf()` |
| `specular` + `roughness` | `specular` + `specular_roughness` | `dielectric_bsdf()` |
| `refractive_index` | `specular_IOR` | Fresnel IOR |
| `anisotropy` | `specular_anisotropy` | anisotropic GGX |
| `shading_tangent` | `tangent` | tangent input |
| `transmission` + `transmission_color` | `transmission` + `transmission_color` | `dielectric_bsdf()` with transmission |
| `dispersion_abbe_number` | `transmission_dispersion` | Abbe number |
| `clearcoat` + `clearcoat_roughness` + `clearcoat_refractive_index` | `coat` + `coat_roughness` + `coat_IOR` | `layer()` + `dielectric_bsdf()` |
| `bssrdf` (3 model choices) | `subsurface` + `subsurface_color` + `subsurface_radius` | `subsurface_bssrdf()` |
| `emission` | `emission` + `emission_color` | `emission()` |
| `normal` | `normal` | tangent-space normal |

---

## Approximate mappings (lossy)

Same concept, incompatible parameterization — visual match possible but no clean
parameter-level conversion.

**Iridescence vs thin-film:**
- DwaBase: artistic hue-wheel / color ramp model, thickness = spectrum-spread knob
- MtlX: physical thin-film interference, thickness in nanometers, IOR-derived colors
- Cannot round-trip. Needs manual rebake.

**Fuzz vs sheen:**
- DwaBase fuzz: independent normal, absorbing/transmitting fiber mode
- MtlX sheen: simpler Zeltner 2022 microfiber BRDF, no independent normal
- Fuzz → sheen loses absorbing fiber behavior and the independent normal.

**Clearcoat thickness absorption vs coat_affect_color:**
- DwaBase: `clearcoat_thickness` + `clearcoat_attenuation_color` → Beer-Lambert depth absorption
- MtlX: `coat_affect_color` + `coat_affect_roughness` → artistic darkening/blurring knobs
- Related intent, incompatible parameterization.

---

## DwaBase features with no MtlX standard_surface equivalent

These are the translation blockers for DwaBase → MtlX:

**Diffuse transmission** (`diffuse_transmission`): backlit diffuse transmission —
scattered light through a thin surface (leaves, skin from behind). MtlX `transmission`
is glass-only. No standard MtlX node for diffuse-mode transmission; would need a custom
`ND_*` node or a separate back-face material.

**Fabric** (warp/weft woven simulation): DWA's two-thread-direction procedural anisotropic
BRDF. MaterialX 1.39 has no woven fabric BSDF. No translation path.

**Glitter**: Worley-noise metallic flake simulation with two styles, per-flake
randomization, physics-based or additive layering. No MtlX standard equivalent.

**Hair glint detail**: `glint_eccentricity` (elliptical cross-section), `glint_min/max_twists`
(procedural twist-count randomization). MtlX 1.39 has `ND_hair_chiang_bsdf` (Chiang 2016)
but it's a different model — twist parameterization doesn't map.

**Per-lobe lightsets**, **SSS trace sets**: render-engine concepts, not portable.

**Iridescence apply-to control**: choosing whether iridescence modulates the specular
lobe or the clearcoat lobe — no MtlX concept.

---

## MtlX standard_surface features with no DwaBase equivalent

**Volumetric transmission scatter** (`transmission_scatter`, `transmission_scatter_anisotropy`):
participating media inside a refractive solid (fog in glass). DwaBase transmission is a
pure Fresnel BSDF with no internal scattering.

**Transmission depth** (`transmission_depth`): physical Beer-Lambert absorption with
explicit depth scaling. DwaBase `transmission_color` is a tint, not depth-parameterized.

**`thin_walled`**: explicit flag for infinitely thin double-sided surfaces. No exposed
DwaBase parameter.

**`coat_affect_roughness`**: how much the clearcoat layer blurs the base specular.
DwaBase `clearcoat_bending` models refraction behavior but not this artistic effect.

---

## OSL angle

OSL closures are the underlying algebra that MaterialX compiles to. The
`ND_standard_surface` → OSL compilation via MaterialX's compiler is reference quality —
this is how RenderMan and other OSL renderers implement it.

OSL closure equivalents: `diffuse()`, `oren_nayar_diffuse()`, `conductor_bsdf()`,
`dielectric_bsdf()`, `burley_diffuse_bsdf()`, `subsurface_bssrdf()`, `sheen_bsdf()`,
`layer()`, `emission()`, `hair_chiang_bsdf()`

Moonray uses ISPC, not OSL — there is no OSL execution path. DwaBase → OSL would
mean writing a new OSL shader that reimplements the DwaBase BSDF stack, not automated
translation. Feasible for the core features; novel OSL code needed for glitter, fabric,
and hair glint.

---

## Translation feasibility summary

| Direction | Fidelity | Hard blockers |
|---|---|---|
| MtlX standard_surface → DwaBaseMaterial | ~85% lossless | volumetric transmission scatter, thin_walled, coat_affect_roughness |
| DwaBaseMaterial → MtlX standard_surface | ~65% lossless | fabric, glitter, diffuse_transmission, hair glint detail |
| MtlX → OSL | ~98% | this is just compilation; near-lossless |
| DwaBase → OSL | Medium | doable for core; proprietary lobes need new OSL |
| Round-trip (MtlX → Dwa → MtlX) | ~60% | DWA-specific additions don't survive return trip |

The core PBR look (plastic, metal, glass, skin, coated surfaces) translates well.
Studio-specific appearance (woven fabric, glitter, hair glint detail) is where DWA
shaders are intentionally ahead of the standard — that gap is irreducible without
implementing those features in MaterialX as custom nodes.
