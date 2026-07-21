#!/bin/bash
# render-denoise — denoise an image with MoonRay's denoiser. macOS + Rocky 9.
#
# Usage: render-denoise <input.exr> <output.exr> [extra denoise args ...]
#   render-denoise beauty.0001.exr denoised/beauty.0001.exr
#   render-denoise beauty.exr out.exr -albedo albedo.exr -normals normals.exr
#
# Thin wrapper over $OMR/bin/denoise with -mode oidn (OpenImageDenoise, the
# CPU-capable mode — the only one available on GPU-less render servers). The
# destination directory is created if missing. Anything after <output> passes
# straight through to `denoise` (e.g. -albedo, -normals, or a -mode override).

# --- per-OS install location (override by exporting OMR) ---------------------
case "$(uname -s)" in
    Darwin)   : "${OMR:=/Applications/MoonRay/installs/openmoonray-houdini}" ;;  # macOS
    Linux)    : "${OMR:=/opt/MoonRay/installs/openmoonray-houdini}" ;;           # Rocky 9
    *)        : "${OMR:=}" ;;                                                     # Windows — TODO
esac

input="$1"
output="$2"
if [ -z "$input" ] || [ -z "$output" ]; then
    echo "Usage: render-denoise <input.exr> <output.exr> [extra denoise args ...]" >&2
    exit 1
fi
shift 2

# --- Linux only: scrub Houdini's dsolib from LD_LIBRARY_PATH ------------------
# denoise links OIIO -> libtiff; the Rocky 9 box's /etc/profile.d forces
# /opt/hfs*/dsolib onto LD_LIBRARY_PATH globally, and Houdini's libtiff has
# unversioned symbols that break the load. denoise finds its own libs via
# RUNPATH, so dropping it is safe. macOS is unaffected.
if [ "$(uname -s)" = "Linux" ]; then
    _lp=; _ifs=$IFS; IFS=:
    for _p in ${LD_LIBRARY_PATH:-}; do
        case "$_p" in *hfs*|*[Hh]oudini*|"") ;; *) _lp="${_lp:+$_lp:}$_p" ;; esac
    done
    IFS=$_ifs; export LD_LIBRARY_PATH="$_lp"
fi

export PATH="$OMR/bin:$PATH"

mkdir -p "$(dirname "$output")"          # ensure the destination folder exists

exec "$OMR/bin/denoise" -in "$input" -mode oidn -out "$output" "$@"
