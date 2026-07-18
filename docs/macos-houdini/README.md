# MoonRay on macOS — Houdini build notes

Documentation for building and extending Open MoonRay on macOS with a focus on the
**Houdini** integration (hdMoonray delegate + DCC plugins). These notes previously lived
in a standalone "managing" repo that carried source edits as `.patch` files; that work is
now **committed directly** on the `macos-houdini` branch of this fork and its two forked
submodules:

| Repo | Fork | Branch |
|---|---|---|
| superproject | `github.com/llienofdoom/openmoonray` | `macos-houdini` |
| Hydra delegate | `github.com/llienofdoom/hdMoonray` | `macos-houdini` |
| Houdini DCC plugins | `github.com/llienofdoom/moonray_dcc_plugins` | `macos-houdini` |

The other 17 submodules track `OpenMoonRay/*@main` (see `../../.gitmodules`).

## Layout

- **`macos/`** — platform-specific to the macOS build: environment setup, the macOS
  build-troubleshooting log, dylib/toolkit-header scripts, and the two macOS build-fix
  patches. Not expected to carry over to a Linux build.
- **`general/`** — cross-platform Houdini work that should mostly apply to a future Linux
  build too: the Hydra delegate light/volume/scene-object fixes, the mesh-light and
  vdbvolume nodes, the TAB-menu consolidation, denoise wiring, and shader mapping notes.

`todo.md` / `done.md` track outstanding vs completed work across both.

## About the `patches/` folders

The `.patch` files are kept as a **historical development record** — how each feature was
built. They are **already applied and committed** on the `macos-houdini` branches; you do
**not** apply them to build. A clean `git clone --recurse-submodules -b macos-houdini
https://github.com/llienofdoom/openmoonray` yields a buildable tree with no patch step.

Cross-reference: the macOS build log (`macos/build-issues.md`) still contains some
platform-agnostic delegate analysis (e.g. Issue 19 denoise, Issue 9 delegate discovery);
the distilled cross-platform conclusions live in the topic docs under `general/`.
