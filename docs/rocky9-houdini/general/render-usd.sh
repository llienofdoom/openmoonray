#!/bin/bash
# render-usd (Rocky 9) — husk render a USD with MoonRay. Linux port of the macOS
# `moonusd` helper, kept in lock-step with it: same env vars and same husk args.
#
# The husk args matter for more than convenience — notably **--complexity 1**,
# which caps subdivision-surface tessellation. Without it husk uses the scene's
# authored complexity (Solaris often writes `veryhigh`), which explodes subdiv
# meshes into millions of polys and OOM-kills the MoonRay `mcrt` process during
# renderPrep (SIGKILL / "mcrt exited due to signal 9"). --make-output-path
# creates the output dir; --threads -1 uses all cores.
#
# Usage: render-usd <usd-file> [start-frame] [num-frames] [frame-inc]
#   render-usd head.usda             # frame 1
#   render-usd head.usda 1001 24 1   # 24 frames from 1001
#
# Output: <usd-dir>/img/<name>/<name>.<F4>.exr  (dir auto-created).
# Optional env:
#   HDMOONRAY_RDLA_OUTPUT=/tmp/dump.rdla   dump the translated RDL2 scene
#   HDMOONRAY_ENABLE_DENOISE=true          test OIDN-on-CPU denoise
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
    OMR="${OMR:-/opt/MoonRay/installs/openmoonray-houdini}"
fi
HFS="${HFS:-/opt/hfs20.5.939}"
HUSK="$HFS/bin/husk"

# Scrub Houdini's dsolib from LD_LIBRARY_PATH (the box's /etc/profile.d forces it
# on globally). husk and hd_moonray.so resolve their libs via RUNPATH; leaving it
# on makes the MoonRay mcrt process load Houdini's libtiff instead of the system
# one. See docs/rocky9-houdini/rocky9/build-env.sh for the full rationale.
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
