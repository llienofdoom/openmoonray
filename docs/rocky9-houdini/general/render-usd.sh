#!/bin/bash
# render-usd.sh (Rocky 9) — render a Houdini-exported USD with MoonRay via husk.
#
# Usage:  render-usd.sh <scene.usd[a]> [out.exr] [camera_prim_path] [frame]
#   render-usd.sh scene.usda
#   render-usd.sh scene.usda out.exr /cameras/render_cam 1
#
# Notes:
#  - Uses the openmoonray-houdini install + Houdini's husk (Houdini USD 24.3).
#  - Sets ONLY the vars husk needs. Do NOT `source .../scripts/setup.sh` for husk —
#    its PYTHONPATH prepends the standalone Python bindings and crashes husk.
#  - $OMR/bin MUST be on PATH so Arras finds `execComp` (the host that runs the
#    `mcrt` render computation); otherwise you get "failed to exec mcrt".
#  - Set HDMOONRAY_RDLA_OUTPUT=/tmp/dump.rdla before running to dump the RDL2 scene
#    MoonRay builds (handy for debugging what the delegate produced).
#  - Headless CPU-only servers: the delegate auto-selects OIDN (built with
#    -DMOONRAY_USE_OPTIX=NO); enable denoise on the RenderSettings prim as usual.
#    To force-test denoise: export HDMOONRAY_ENABLE_DENOISE=true before running.
set -uo pipefail

SCENE="${1:?usage: render-usd.sh <scene.usd> [out.exr] [camera] [frame]}"
OUT="${2:-${SCENE%.*}.exr}"
CAM="${3:-}"
FRAME="${4:-1}"

OMR=/opt/MoonRay/installs/openmoonray-houdini
HFS=/opt/hfs20.5.939
HUSK="$HFS/bin/husk"

# Scrub Houdini's dsolib from LD_LIBRARY_PATH (the box's /etc/profile.d puts it
# there globally). husk finds its own libs via RUNPATH ($ORIGIN/../dsolib), and
# hd_moonray.so carries $HFS/dsolib in its OWN RUNPATH for USD/pxr — so nothing
# here needs it on LD_LIBRARY_PATH. Leaving it on would make the MoonRay mcrt
# process (execComp) load Houdini's libtiff (unversioned symbols) instead of the
# system one. See docs/rocky9-houdini/rocky9/build-env.sh for the full rationale.
_lp=; _IFS_SAVE=$IFS; IFS=:
for _p in ${LD_LIBRARY_PATH:-}; do
    case "$_p" in *hfs*|*[Hh]oudini*|"") ;; *) _lp="${_lp:+$_lp:}$_p" ;; esac
done
IFS=$_IFS_SAVE; export LD_LIBRARY_PATH="$_lp"

export PATH="$OMR/bin:$PATH"                  # execComp + arras bins (fixes "exec mcrt")
export PXR_PLUGINPATH_NAME="$OMR/plugin/pxr"  # load the HdMoonray delegate
export RDL2_DSO_PATH="$OMR/rdl2dso"
export MOONRAY_CLASS_PATH="$OMR/shader_json"
export REZ_MOONRAY_ROOT="$OMR"
export ARRAS_SESSION_PATH="$OMR/sessions"
export HOUDINI_PATH="$OMR/houdini:$OMR/plugin/houdini:&"

CAM_ARG=()
[ -n "$CAM" ] && CAM_ARG=(--camera "$CAM")

echo "husk -> $OUT  (frame $FRAME${CAM:+, camera $CAM})"
exec "$HUSK" -R HdMoonrayRendererPlugin -o "$OUT" -f "$FRAME" ${CAM_ARG[@]+"${CAM_ARG[@]}"} "$SCENE"
