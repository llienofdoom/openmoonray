#!/bin/bash
# render-usd.sh — render a Houdini-exported USD with MoonRay via husk.
#
# Usage:  render-usd.sh <scene.usd[a]> [out.exr] [camera_prim_path] [frame]
#   render-usd.sh scene.usda
#   render-usd.sh scene.usda out.exr /cameras/render_cam 1
#
# Notes:
#  - Uses the openmoonray-houdini install + Houdini's husk (Houdini USD 24.3).
#  - Sets ONLY the vars husk needs. Do NOT `source .../scripts/setup.sh` for husk —
#    its PYTHONPATH prepends the standalone USD 22.11 bindings and crashes husk.
#  - $OMR/bin MUST be on PATH so Arras finds `execComp` (the host that runs the
#    `mcrt` render computation); otherwise you get "failed to exec mcrt".
#  - Set HDMOONRAY_RDLA_OUTPUT=/tmp/dump.rdla before running to dump the RDL2 scene
#    MoonRay builds (handy for debugging what the delegate produced).
set -uo pipefail

SCENE="${1:?usage: render-usd.sh <scene.usd> [out.exr] [camera] [frame]}"
OUT="${2:-${SCENE%.*}.exr}"
CAM="${3:-}"
FRAME="${4:-1}"

OMR=/Applications/MoonRay/installs/openmoonray-houdini
HFS=/Applications/Houdini/Houdini20.5.939/Frameworks/Houdini.framework/Versions/20.5/Resources
HUSK="$HFS/bin/husk"

export PATH="$OMR/bin:$PATH"                  # execComp + arras bins (fixes "exec mcrt")
export PXR_PLUGINPATH_NAME="$OMR/plugin/pxr"  # load the HdMoonray delegate
export RDL2_DSO_PATH="$OMR/rdl2dso"
export MOONRAY_CLASS_PATH="$OMR/shader_json"
export REZ_MOONRAY_ROOT="$OMR"
export ARRAS_SESSION_PATH="$OMR/sessions"
export HOUDINI_PATH="$OMR/plugin/houdini;&"

CAM_ARG=()
[ -n "$CAM" ] && CAM_ARG=(--camera "$CAM")

echo "husk -> $OUT  (frame $FRAME${CAM:+, camera $CAM})"
# ${CAM_ARG[@]+...} guards the empty-array expansion: under `set -u`, macOS's default
# bash 3.2 treats "${CAM_ARG[@]}" on an empty array as an unbound variable and aborts.
exec "$HUSK" -R HdMoonrayRendererPlugin -o "$OUT" -f "$FRAME" ${CAM_ARG[@]+"${CAM_ARG[@]}"} "$SCENE"
