#!/bin/bash
# render-usd — husk render a USD with MoonRay. One script for macOS + Rocky 9.
#
# Usage: render-usd <input.usd|.usda|.usdb> [husk args ...]
#   render-usd head.usda --frame 1 --output /tmp/head.0001.exr
#
# The input file is the first argument; everything after it is passed straight
# through to husk (so --frame, --output, --camera, ... work as-is). A handful of
# args are hard-coded below (renderer, complexity, frame-count/inc). If you do
# not pass --output, a default of <input-dir>/img/<name>/<name>.$F4.exr is used.
#
# --complexity 1 caps subdivision tessellation — without it heavy scenes explode
# and OOM-kill the MoonRay mcrt process during renderPrep.

# ---------------------------------------------------------------------------
# Per-OS install locations. Hard-coded defaults; override by exporting OMR/HFS.
# (Windows: fill in when a Windows build exists.)
# ---------------------------------------------------------------------------
case "$(uname -s)" in
    Darwin)                                    # macOS
        : "${OMR:=/Applications/MoonRay/installs/openmoonray-houdini}"
        : "${HFS:=/Applications/Houdini/Houdini20.5.939/Frameworks/Houdini.framework/Versions/20.5/Resources}"
        ;;
    Linux)                                     # Rocky 9 render server
        : "${OMR:=/opt/MoonRay/installs/openmoonray-houdini}"
        : "${HFS:=/opt/hfs20.5.939}"
        ;;
    *)                                         # Windows / other — TODO
        : "${OMR:=}"
        : "${HFS:=}"
        ;;
esac
HUSK="$HFS/bin/husk"

# ---------------------------------------------------------------------------
# Input file + derived default output.
# ---------------------------------------------------------------------------
input="$1"
if [ -z "$input" ]; then
    echo "Usage: render-usd <input.usd|.usda|.usdb> [husk args ...]" >&2
    exit 1
fi
shift

name="$(basename "$input")"; name="${name%.*}"     # strip .usd / .usda / .usdb
dir="$(dirname "$input")"

# Only supply the derived --output when the caller did not pass one.
default_output_arg=(--output "$dir/img/$name/$name.\$F4.exr")
for a in "$@"; do
    case "$a" in --output|--output=*|-o) default_output_arg=() ;; esac
done

# ---------------------------------------------------------------------------
# Linux only: scrub Houdini's dsolib from LD_LIBRARY_PATH. The Rocky 9 box's
# /etc/profile.d forces /opt/hfs*/dsolib on globally; it shadows the system
# libtiff in the MoonRay mcrt process. husk + hd_moonray.so find their libs via
# RUNPATH, so dropping it is safe. macOS is unaffected.
# ---------------------------------------------------------------------------
if [ "$(uname -s)" = "Linux" ]; then
    _lp=; _ifs=$IFS; IFS=:
    for _p in ${LD_LIBRARY_PATH:-}; do
        case "$_p" in *hfs*|*[Hh]oudini*|"") ;; *) _lp="${_lp:+$_lp:}$_p" ;; esac
    done
    IFS=$_ifs; export LD_LIBRARY_PATH="$_lp"
fi

# ---------------------------------------------------------------------------
# MoonRay + husk environment.
# ---------------------------------------------------------------------------
export PATH="$OMR/bin:$PATH"                   # execComp + arras bins (fixes "exec mcrt")
export PXR_PLUGINPATH_NAME="$OMR/plugin/pxr"   # load the HdMoonray delegate
export RDL2_DSO_PATH="$OMR/rdl2dso"
export MOONRAY_CLASS_PATH="$OMR/shader_json"
export REZ_MOONRAY_ROOT="$OMR"
export ARRAS_SESSION_PATH="$OMR/sessions"
export HOUDINI_PATH="$OMR/plugin/houdini;&"
export HDMOONRAY_INFO="${HDMOONRAY_INFO:-1}"
export HDMOONRAY_DOUBLESIDED="${HDMOONRAY_DOUBLESIDED:-1}"
export HDMOONRAY_ENABLE_DENOISE="${HDMOONRAY_ENABLE_DENOISE:-0}"

exec "$HUSK" "$input" \
    --renderer HdMoonrayRendererPlugin \
    --frame-count 1 \
    --frame-inc 1 \
    --complexity 1 \
    --make-output-path \
    --verbose a2 \
    "${default_output_arg[@]}" \
    "$@"
