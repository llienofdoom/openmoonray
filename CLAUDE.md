# Open MoonRay — macOS + Rocky 9 / Houdini fork (single source of truth)

This is a **personal fork** of Open MoonRay focused on building and extending the renderer
with a **Houdini** front-end (the hdMoonray Hydra delegate + Houdini DCC plugins) on **two
OSes from one shared branch**: **macOS** (Apple Silicon, dev/iteration) and **Rocky Linux 9**
(headless, CPU-only render servers). All accumulated build/dev/test knowledge lives **here**,
in this superproject — including notes about the two forked submodules. Do not split Claude
context across the submodule forks; they carry only a one-line pointer back here.

Active branch: **`macos-houdini`** — now the **shared cross-OS Houdini branch** (name kept to
avoid disrupting macOS iteration; an eventual rename to `houdini` is the clean end-state).
The build infra is OS-separated *within* this one branch (`CMakeMacOSPresets.json` vs
`CMakeLinuxPresets.json`, `building/macOS` vs `building/Rocky9`, `scripts/macOS` vs
`scripts/Rocky9`, `docs/macos-houdini` vs `docs/rocky9-houdini`); the delegate C++ and DCC
assets are genuinely shared. The user iterates on macOS; Linux follows. Upstream is the
ASWF-governed `OpenMoonRay` org (project moved from `dreamworksanimation` in 2026).

## Fork / submodule architecture

Open MoonRay is a superproject with 19 submodules. Only **two** are forked; the rest track
upstream. This repo (the superproject) owns their gitlink pointers — `moonray` core is NOT
forked.

| Repo | Source | Branch |
|---|---|---|
| `openmoonray` (this) | `github.com/llienofdoom/openmoonray` | `macos-houdini` |
| `moonray/hydra/hdMoonray` | `github.com/llienofdoom/hdMoonray` | `macos-houdini` |
| `moonray/moonray_dcc_plugins` | `github.com/llienofdoom/moonray_dcc_plugins` | `macos-houdini` |
| other 17 submodules | `github.com/OpenMoonRay/<name>` | `main` |

⚠️ **`.gitmodules` MUST use absolute URLs.** Upstream uses relative URLs (`../hdMoonray`),
which resolve against *this fork's* origin and would 404 for the 17 upstream repos. Never
revert to relative URLs. When bumping a forked submodule: commit in the submodule, push its
`macos-houdini` branch, then `git add <submodule-path>` here to record the new gitlink and
commit.

## Bootstrap from nothing

Source is one recursive clone; deps and Houdini are separate (not in git).

```bash
git lfs install
git clone --recurse-submodules -b macos-houdini \
    https://github.com/llienofdoom/openmoonray.git
```

That pulls the 2 forks from `llienofdoom` and the 17 from `OpenMoonRay` automatically — no
patch step. A full machine also needs, per `docs/macos-houdini/macos/macos-build.md`:

1. **Directory layout + symlinks** the presets expect (`${sourceParentDir}/installs`, etc.):
   clone into `/Applications/MoonRay/source/openmoonray`, then
   `ln -s source/openmoonray /Applications/MoonRay/openmoonray` and `ln -s source/openmoonray/building /Applications/MoonRay/building`.
2. **Dependencies** built from source into `installs/` — Houdini variant skips USD:
   `cd build-deps && cmake -DNO_USD=1 ../building/macOS && cmake --build . -- -j8` (multi-hour).
3. **Houdini 20.5.939** at `/Applications/Houdini/Houdini20.5.939`.

## Building (Houdini)

Use the **`build-houdini`** skill — it wraps the one non-obvious gotcha:

> The standalone deps ship USD 22.11 headers in `installs/include/pxr`; Houdini uses USD
> 24.3. Xcode's generator puts `-isystem installs/include` *before* the toolkit include, so
> 22.11 headers win and objects link against the wrong `libpxr_*` namespace. The build
> temporarily moves `installs/include/pxr` aside so clang falls through to Houdini's
> toolkit headers.

Configure once, then build via the wrapper (`docs/macos-houdini/macos/build-houdini.sh`):
```bash
cmake --preset macos-houdini-release      # BUILD_QT_APPS=NO (Houdini-only; no Qt5/GUI)
docs/macos-houdini/macos/build-houdini.sh -jobs 8
```
Targeted delegate rebuild avoids the flaky full `install` target — see the skill and
`docs/macos-houdini/macos/build-issues.md` (Issue 19). `BUILD_QT_APPS=NO` drops
`moonray_gui`/`arras_render`; the Arras *runtime* (`arras4_core`, `mcrt_*`, `execComp`) still
builds, so the delegate render path is intact.

## Building (Houdini) — Rocky 9 (headless, CPU-only render servers)

Rooted at **`/opt/MoonRay`** (not `/Applications/MoonRay`); Houdini at `/opt/hfs20.5.939`.
Full procedure in **`docs/rocky9-houdini/rocky9/rocky9-build.md`**; two Linux-specific issues
in `docs/rocky9-houdini/rocky9/build-issues.md`. Render-verified end-to-end (incl. OIDN on
CPU) on the `luma@` box, 2026-07-21. The one non-obvious gotcha (the Linux analogue of the
macOS pxr-header dance):

> The box installs Houdini via `/etc/profile.d/houdini-20.5.*.sh`, which forces `/opt/hfs*/
> dsolib` onto every shell's `LD_LIBRARY_PATH`. Houdini's `dsolib` libcurl (dead CA path) and
> libtiff (unversioned symbols) shadow the system libs and break the build. **Source
> `docs/rocky9-houdini/rocky9/build-env.sh`** before every build/render step to scrub Houdini
> out of the shell — nothing MoonRay builds needs it there (deps are `NO_USD`; husk +
> delegate resolve their libs via RUNPATH).

```bash
source /opt/MoonRay/build-env.sh                                   # scrub Houdini from the shell
cmake --preset rocky9-houdini-release                             # BUILD_QT_APPS=NO, BUILD_TESTING=OFF, MOONRAY_USE_OPTIX=NO
cmake --build --preset rocky9-houdini-release -- -j $(nproc)
cmake --build --preset rocky9-houdini-release --target install -- -j $(nproc)
```

Unlike macOS, Rocky 9 gets most deps from `dnf` — but **OpenVDB is source-built into
`installs/`** (like macOS) specifically for the Houdini build, else Houdini's bundled OpenVDB
11 headers shadow dnf's 9.1 (Issue L2). `MOONRAY_USE_OPTIX=NO` ⇒ `HDMOONRAY_NO_OPTIX` ⇒ the
delegate auto-selects OIDN (CPU) and never hits the OptiX abort — the CPU-only payoff.

## Testing / debugging renders

Use the **`render-test`** skill (husk + optional RDL2 dump). Key facts:
- Render via husk against the `openmoonray-houdini` install. Do **not** `source
  .../scripts/setup.sh` for husk — it prepends the standalone USD 22.11 bindings and crashes
  husk. `$OMR/bin` must be on `PATH` so Arras finds `execComp` (else "failed to exec mcrt").
- `HDMOONRAY_RDLA_OUTPUT=/tmp/dump.rdla` dumps the exact RDL2 scene the delegate built —
  the primary tool for "what did the delegate translate?". Works for husk, **not** the
  Solaris viewport (the hip's saved `sceneviewrenderopts` override it; set the viewport
  "Rdl output" field manually in viewport-settings mode).
- User's local helpers: `moonusd` (husk wrapper, sets OCIO ACES 1.2 + MoonRay env) and
  `moonhou` (launches Houdini via `setupHoudini.sh`). Test scenes in `~/Desktop/moonray_tests/`.
- The user drives the Solaris viewport from the **RenderSettings LOP**, not viewport display
  options — don't assume viewport defaults apply.

## Where changes live (per area)

- **hdMoonray delegate** — `moonray/hydra/hdMoonray/lib/hydramoonray/` (translation:
  Light/Camera/Material/Volume/LightFilter, `ValueConverter`) and `plugin/hd_moonray/`
  (Arras client: `ArrasRenderer`, `ArrasSettings`). Pattern to know: `ValueConverter::
  setAttribute` takes a `RenderDelegate*` to resolve `TYPE_SCENE_OBJECT` attrs from prim paths.
- **Houdini DCC plugins** — `moonray/moonray_dcc_plugins/houdini/`: otls (`.hda`), soho param
  UIs (`.ds`), and `moonray_nodes.json` + `python3.11libs/pythonrc.py` (TAB menu). Editing
  otls with `hotl` leaves `*.hda.orig` backups + an `otls/backup/` dir — both git-ignored;
  never commit them. Node-authoring helper scripts are in `docs/macos-houdini/general/{mesh-light-node,vdbvolume-node}/`.

## Docs

`docs/macos-houdini/` — split into **`macos/`** (platform-specific: build log, dylib/toolkit
scripts, build-fix patches) and **`general/`** (cross-platform Houdini work: delegate fixes,
nodes, menu, shader mapping). The `patches/` folders are a **historical** development record;
the changes are already committed on the `macos-houdini` branches — you do not apply them to
build.

`docs/rocky9-houdini/` — the Linux sibling: **`rocky9/`** (platform-specific: `rocky9-build.md`
build log, `build-issues.md` for the two Houdini-env-shadowing issues, `build-env.sh` shell
scrub). Cross-platform delegate/node/shader work lives under `docs/macos-houdini/general/` and
is not duplicated here.

The **husk render helper is a single cross-OS script**, `scripts/render-usd.sh` — installed to
`$OMR/bin/render-usd` by the build (`scripts/CMakeLists.txt`). It picks `OMR`/`HFS` by
`uname` (macOS vs Rocky 9; Windows TBD), scrubs Houdini's `dsolib` on Linux, hard-codes the
renderer/complexity/frame args, and passes the first arg (input USD) + everything after it
(`--frame`, `--output`, `--camera`, …) through to husk. `--complexity 1` is deliberate — it
caps subdiv tessellation, without which heavy scenes OOM-kill the `mcrt` process in renderPrep.
The user's local macOS equivalent is `moonusd`.

## Conventions

- Factual, minimal prose; copy-pasteable commands. Cite sources (URLs, commit SHAs) in docs.
- Note Apple Silicon vs x86_64 differences explicitly where relevant.
- Some fixes are platform-independent (marked "Upstream-PR candidate" in the docs) and worth
  submitting to OpenMoonRay; macOS-specific guards (`__APPLE__`) are not.
