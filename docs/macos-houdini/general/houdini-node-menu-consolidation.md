# Houdini Node Menu Consolidation

Consolidates the Moonray VOP shader nodes in Houdini's matnet/VOP TAB menu into
a single `Moonray` menu with type-based subfolders, replacing four redundant
legacy placements.

Spec: `docs/superpowers/specs/2026-07-07-houdini-node-menu-consolidation-design.md`
Plan: `docs/superpowers/plans/2026-07-07-houdini-node-menu-consolidation.md`

## Problem

In the matnet/VOP shader builder, the Moonray shader nodes appeared under
**four** separate TAB-menu placements — redundant and cluttered:

- `DW Moonray`
- `Digital Assets` (Houdini's default catch-all for any HDA)
- `DreamWorks/All`
- `DreamWorks/HIDDEN`

## Findings (root cause)

Every Moonray shader node is a Houdini Digital Asset (`.hda`) under
`moonray/moonray_dcc_plugins/houdini/otls/` — **126** of them, all VOP-context
(`Vop::DW_MOONRAY::<Class>::<ver>.hda`), each a single-operator library. Each
`.hda` embeds a `Tools.shelf` XML section whose `<toolSubmenu>` entries decide
where the node appears in the TAB menu.

Tallied across all 126 HDAs:

| Menu placement      | # nodes | Notes                                  |
|---------------------|--------:|----------------------------------------|
| `DreamWorks/All`    | 126     | the complete set                       |
| `DreamWorks/HIDDEN` | 126     | **identical** to All — a 100% duplicate |
| `DW Moonray`        | 116     | missing 10 nodes                       |
| `Digital Assets`    | 126     | Houdini default catch-all              |

Two concrete conclusions:

1. **`HIDDEN` is not a "hidden extras" folder.** It holds the exact same 126
   nodes as `All`; nothing lives under HIDDEN that is not in the main menu. It
   is a legacy DreamWorks-internal convention shipped with the assets.
2. **`DW Moonray` was the *incomplete* menu** — it omitted 10 nodes that only
   the DreamWorks menu exposed: `BaseMaterial`, `ColorCorrectNukeMap`,
   `GlitterFlakeMaterial`, `LayerMap`, `MacroFlakeMaterial`, `NoiseMap`,
   `NoiseWorleyMap` (×2), `OpSqrtMap`, `TwoSidedMap`. The consolidation includes
   them automatically (every asset is rewritten uniformly).

## Solution

`docs/patches/consolidate_moonray_menu.py` rewrites each asset's `Tools.shelf`
to a single `Moonray/<Subfolder>` entry via a Houdini `hotl` round-trip
(`hotl -t` expand → rewrite the XML section → `hotl -l` collapse). Classification
is purely by class-name suffix — every one of the 126 names ends in exactly one
type suffix, giving 100% coverage with no fallback bucket:

| Suffix            | Subfolder                | Count |
|-------------------|--------------------------|------:|
| `*Material`       | `Moonray/Materials`      | 25    |
| `*NormalMap`      | `Moonray/Normal Maps`    | 11    |
| `*Map` (non-normal)| `Moonray/Maps`          | 65    |
| `*Displacement`   | `Moonray/Displacement`   | 4     |
| `*DisplayFilter`  | `Moonray/Display Filters`| 18    |
| `*Volume`         | `Moonray/Volumes`        | 3     |

`NormalMap` is tested before the generic `Map` suffix so normal maps are not
misclassified. The tool:

- backs up each asset to `<path>.orig` once (never overwrites an existing backup);
- is **idempotent** — an asset whose only submenu is a single `Moonray/...`
  entry is skipped;
- errors out (safety stop) if an expand ever yields other than exactly one
  `Tools.shelf`, so a multi-operator file can never be misclassified.

`hotl` (not on `PATH`):
`/Applications/Houdini/Houdini20.5.939/Frameworks/Houdini.framework/Versions/Current/Resources/bin/hotl`

The core (classifier + rewriter) and the migrator/CLI have unit + integration
tests in `docs/patches/test_consolidate_moonray_menu.py` (21 tests; the
integration tests run the real `hotl` against copies of real HDAs, forcing a
deterministic legacy-submenu precondition first so they're hermetic against
whatever migration state the live otls tree happens to be in). Built TDD
via `docs/superpowers/` spec → plan → subagent-driven execution.

## How to run

```bash
cd docs/patches
python3 consolidate_moonray_menu.py --dry-run          # verify tally = 126, no writes
python3 consolidate_moonray_menu.py                     # migrate the source otls (backs up *.hda.orig)
python3 consolidate_moonray_menu.py <other_otls_dir>    # e.g. an install tree
```

The tool is idempotent; a second run reports `migrated=0 skipped=N`.

## What was migrated (2026-07-07)

- **Source tree** `moonray/moonray_dcc_plugins/houdini/otls/` — all 126 assets:
  single `Moonray/*` submenu, 0 legacy menus, 126 `.orig` backups. Idempotent
  re-run: `migrated=0 skipped=126`.
- **Houdini install tree**
  `/Applications/MoonRay/installs/openmoonray-houdini/plugin/houdini/otls/`
  (the GUI `HOUDINI_PATH` target) — migrated directly with the same tool
  (`migrated=99 skipped=27`; the 27 already carried a correct `Moonray/*` menu
  from the earlier VdbVolume-era work). Cross-check confirmed all 126 install
  assets match their correct expected subfolder, 0 legacy, 0 mismatches.
- The `openmoonray-standalone` install tree was deliberately **not** migrated —
  it is CLI-only and has no matnet menu.

Note: the install tree was updated with the tool directly (fast, backed up,
idempotent) rather than a full `build-houdini.sh` reinstall. Because the source
tree is also migrated, a future full reinstall stays consistent.

## Verification (in Houdini, 2026-07-07)

Confirmed in Houdini 20.5.939 (matnet TAB menu), user-verified:

- ✅ A single top-level **Moonray** menu with the six subfolders (Materials,
  Maps, Normal Maps, Displacement, Display Filters, Volumes) shows correctly.
- ✅ The `DW Moonray` and `DreamWorks` (All/HIDDEN) menus are **gone**.
- ✅ **Outcome (a)** — the nodes no longer appear under Houdini's built-in
  **Digital Assets** catch-all. Removing the explicit `Digital Assets`
  `<toolSubmenu>` was sufficient; no per-HDA suppression fallback was needed.

Goal fully met.

## Sources

- otls (source): `/Applications/MoonRay/source/openmoonray/moonray/moonray_dcc_plugins/houdini/otls`
- otls (Houdini install): `/Applications/MoonRay/installs/openmoonray-houdini/plugin/houdini/otls`
- hotl: Houdini 20.5.939 `Resources/bin/hotl`
- Tool + tests: `docs/patches/consolidate_moonray_menu.py`, `docs/patches/test_consolidate_moonray_menu.py`
