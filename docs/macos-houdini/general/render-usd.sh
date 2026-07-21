#!/bin/bash
# render-usd (macOS) — husk render a USD with MoonRay. The repo counterpart of
# the user's personal `moonusd` helper, kept in lock-step with the Rocky 9
# `docs/rocky9-houdini/general/render-usd.sh`: same env vars and same husk args,
# only the macOS paths differ (and there is no Houdini dsolib/LD_LIBRARY_PATH
# poisoning to scrub on macOS — Houdini env is sourced deliberately here).
#
# The husk args matter for more than convenience — notably **--complexity 1**,
# which caps subdivision-surface tessellation. Without it husk uses the scene's
# authored complexity (Solaris often writes `veryhigh`), which explodes subdiv
# meshes into millions of polys and OOM-kills the MoonRay `mcrt` process during
# renderPrep. --make-output-path creates the output dir; --threads -1 uses all
# cores. Do NOT `source .../scripts/setup.sh` for husk — its PYTHONPATH prepends
# the standalone USD bindings and crashes husk.
#
# Usage: render-usd <usd-file> [start-frame] [num-frames] [frame-inc]
#   render-usd head.usda             # frame 1
#   render-usd head.usda 1001 24 1   # 24 frames from 1001
#
# Output: <usd-dir>/img/<name>/<name>.<F4>.exr  (dir auto-created).
# Optional env:
#   HDMOONRAY_RDLA_OUTPUT=/tmp/dump.rdla   dump the translated RDL2 scene
#   HDMOONRAY_ENABLE_DENOISE=true          enable OIDN denoise
#   OCIO=/path/to/aces/config.ocio         ACES color (unset = MoonRay default)
#   OMR=... / HFS=...                      override install / Houdini locations

args=$@
if [[ -z "${args[@]}" ]]; then
    echo "Usage: render-usd <usd-file> [start-frame] [num-frames] [frame-inc]"
    exit 1
fi

usdfile=$1
name=$(basename "$usdfile" .usda)
folder=$(dirname "$usdfile")
frame=${2:-1}
end=${3:-1}
inc=${4:-1}

# Resolve the MoonRay-Houdini install. When this script lives in $OMR/bin (the
# recommended home), derive $OMR from its own location so it is relocatable;
# otherwise honor $OMR from the env or fall back to the standard install path.
selfdir="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
if [ -d "$selfdir/../rdl2dso" ] && [ -d "$selfdir/../plugin/pxr" ]; then
    OMR="$(cd "$selfdir/.." && pwd)"
else
    OMR="${OMR:-/Applications/MoonRay/installs/openmoonray-houdini}"
fi
HFS="${HFS:-/Applications/Houdini/Houdini20.5.939/Frameworks/Houdini.framework/Versions/20.5/Resources}"
HUSK="$HFS/bin/husk"

export PATH="$OMR/bin:$PATH"                  # execComp + arras bins (fixes "exec mcrt")
export PXR_PLUGINPATH_NAME="$OMR/plugin/pxr"  # load the HdMoonray delegate
export RDL2_DSO_PATH="$OMR/rdl2dso"
export MOONRAY_CLASS_PATH="$OMR/shader_json"
export REZ_MOONRAY_ROOT="$OMR"
export ARRAS_SESSION_PATH="$OMR/sessions"
export HOUDINI_PATH="$OMR/plugin/houdini;&"
export HDMOONRAY_INFO="${HDMOONRAY_INFO:-1}"
export HDMOONRAY_DOUBLESIDED="${HDMOONRAY_DOUBLESIDED:-1}"
export HDMOONRAY_ENABLE_DENOISE="${HDMOONRAY_ENABLE_DENOISE:-0}"

echo "husk -> $folder/img/$name/$name.<F4>.exr  (frame $frame, count $end, complexity 1)"
exec "$HUSK" "$usdfile" \
    --frame "$frame" \
    --frame-count "$end" \
    --frame-inc "$inc" \
    --verbose a2 \
    --renderer HdMoonrayRendererPlugin \
    --make-output-path \
    --complexity 1 \
    --threads -1 \
    --output "$folder/img/$name/$name.\$F4.exr"
