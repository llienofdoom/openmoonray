# Fork-Based Workflow Migration (2026-07-18)

Replaced the **patch-shuffle model** (uncommitted edits in the build tree
`/Applications/MoonRay/source/openmoonray` + regenerated `.patch` files in this repo) with
**committed source in personal GitHub forks**. This repo is retained as the research/history
archive; the live source of truth is now the forks.

## Why

The patch-shuffle model was fragile: real edits lived only as working-tree modifications
mirrored by patch files. It had already drifted — several `hdMoonray` edits
(`Camera/LightFilter/Material.cc`, `ValueConverter.h`; the "sceneobject-ref" feature) were
captured only in `docs/research/vdbvolume-node/delegate-sceneobject-fix/`, not in
`docs/patches/`. A stray `git reset` would have lost them.

## What was done

### Three forks under `github.com/llienofdoom`, branch `macos-houdini`

| Fork | Path in tree | Contents |
|---|---|---|
| `openmoonray` (superproject) | root | macOS build config, `BUILD_QT_APPS=NO`, absolute-URL `.gitmodules`, folded docs, central `CLAUDE.md` + skills |
| `hdMoonray` | `moonray/hydra/hdMoonray` | delegate: build-fixes, sceneobject-ref, lights (treatAsPoint + mesh-light), denoise-issue19 |
| `moonray_dcc_plugins` | `moonray/moonray_dcc_plugins` | TAB-menu consolidation (125 otls), mesh-light + vdbvolume nodes, light/denoise `.ds` |

`moonray` core is **not** forked — `hdMoonray` and `moonray_dcc_plugins` are direct submodules
of the superproject, which owns their gitlink pointers. The other 17 submodules track
`OpenMoonRay/*@main`.

### Commit groupings (each fork, on `macos-houdini`)

- **hdMoonray** (4): build-fixes · sceneobject-ref (`ValueConverter::setAttribute` gains a
  `RenderDelegate*` to resolve `TYPE_SCENE_OBJECT` attrs from prim paths) · lights · denoise-issue19.
- **moonray_dcc_plugins** (6): `.gitignore` (hotl `*.hda.orig` + `otls/backup/`) · menu
  consolidation · mesh-light node · vdbvolume node · light-class-normalize `.ds` · denoise `.ds`.
- **openmoonray** (4): macOS build + `BUILD_QT_APPS=NO` · `.gitmodules` absolute URLs +
  gitlink bumps · folded docs · central `CLAUDE.md` + skills.

### Key mechanics

- **`.gitmodules` MUST use absolute URLs.** Upstream uses relative (`../hdMoonray`), which
  would resolve against the fork and 404 for the 17 upstream repos. The 2 forks →
  `llienofdoom/*@macos-houdini`; the other 17 → `OpenMoonRay/*@main`.
- **`BUILD_QT_APPS=NO`** on the `macos-houdini-release` preset drops `moonray_gui`/`arras_render`
  + Qt5. The Arras *runtime* (`arras4_core`, `mcrt_*`, `execComp`) still builds, so the
  hdMoonray delegate render path is intact.
- **Noise excluded** via `.gitignore`: `*.hda.orig` + `otls/backup/` (hotl), and `.DS_Store` +
  `testdata/*.exr` in the superproject.

### Docs folded into the superproject fork

`openmoonray/docs/macos-houdini/` split into `macos/` (platform-specific: build log, dylib/
toolkit scripts, build-fix patches) and `general/` (cross-platform Houdini work — reusable for
a future Linux build). Patches retained as historical record; they are already committed.

### Claude context centralized

Single `CLAUDE.md` at the superproject root + `.claude/skills/{build-houdini,render-test}`.
The two submodule forks carry only a one-line pointer stub. Rationale: submodules live inside
the openmoonray tree, so the root `CLAUDE.md` auto-loads even when working deep in a submodule.

## Bootstrap from a fresh machine

```bash
git lfs install
git clone --recurse-submodules -b macos-houdini \
    https://github.com/llienofdoom/openmoonray.git
```
Pulls the 2 forks from `llienofdoom` and the 17 from `OpenMoonRay`, no patch step. Deps build
and Houdini install are separate (not in git) — see `macos-build.md`.

## Verification

- Clean `--recurse-submodules -b macos-houdini` clone resolves all 19 submodules with **zero
  404s and no patch step**; checked-out SHAs match the pushed commits.
- Forked-module content is **byte-identical** to the built/verified build tree — nothing
  dropped or altered in migration.
- `BUILD_QT_APPS=NO` present in the cloned preset.
- **Not yet run:** a full from-scratch deps build + compile of the fork (multi-hour; committed
  bytes are identical to the already-built-and-render-verified tree, so confidence is high).

## Sources

- Forks: `github.com/llienofdoom/{openmoonray,hdMoonray,moonray_dcc_plugins}` (branch `macos-houdini`)
- Superproject commits: `42f5b6d`, `1e2d5cb`, `43555dc`, `ef8a1c2`
- hdMoonray base `6366b99`; moonray_dcc_plugins base `eda4e57`; superproject base `489b926`
