---
name: render-test
description: Render a USD scene with MoonRay via husk on macOS and optionally dump the RDL2 the delegate produced. Use when asked to render a test scene, verify a delegate/otls change, or debug what hdMoonray translated.
---

# Render-test MoonRay via husk (macOS)

Renders a Houdini-exported USD with the MoonRay Hydra delegate using Houdini's `husk`, against
the `openmoonray-houdini` install. Use it to confirm a delegate or otls change end-to-end.

## Critical env facts (why a plain husk invocation fails)

- **Do NOT** `source .../scripts/setup.sh` — it prepends the standalone USD 22.11 bindings to
  `PYTHONPATH` and crashes husk (Houdini is USD 24.3).
- `$OMR/bin` **must** be on `PATH` or Arras can't find `execComp` → "failed to exec mcrt".
- Set only the vars husk needs (see the wrapper below).

## Render

Use the committed wrapper `scripts/render-usd.sh` — one cross-OS script (macOS + Rocky 9),
installed to `$OMR/bin/render-usd` by the build. It sets exactly the right env, hard-codes the
renderer/complexity/frame-count args, then execs husk; the input file is the first arg and
everything after it passes straight through to husk:

```bash
scripts/render-usd.sh scene.usda --frame 1 --output out.exr [--camera /cameras/render_cam]
# or, once $OMR/bin is on PATH:  render-usd scene.usda --frame 1 --output out.exr
```

The user's local macOS equivalent is the `moonusd` helper (adds OCIO ACES 1.2). Test scenes
live in `~/Desktop/moonray_tests/`. Launch Houdini itself with `moonhou`.

## Debugging: dump the RDL2 scene the delegate built

The single most useful tool for "what did the delegate translate?":

```bash
export HDMOONRAY_RDLA_OUTPUT=/tmp/dump.rdla
scripts/render-usd.sh scene.usda
# then inspect /tmp/dump.rdla — light classes, treatAsPoint, SceneObject refs, etc.
```

⚠️ `HDMOONRAY_RDLA_OUTPUT` works for **husk only**, NOT the Solaris viewport: a hip's saved
`sceneviewrenderopts` override it with an empty `rdlOutput`. In the viewport you must set the
"Rdl output" field manually, and it's only editable in viewport-settings mode. The user drives
the viewport from the **RenderSettings LOP**, not viewport display options.

## Reference

Viewport-vs-husk translation parity is documented in
`docs/macos-houdini/general/hdmoonray-viewport-vs-husk-scene-translation.md`.
