#!/bin/bash
# Verifies a carrier mesh light renders with geometry attached, via husk + RDL dump.
# Usage: verify_delegate.sh [houdini|standalone]
set -uo pipefail
VARIANT="${1:-houdini}"
HERE="$(cd "$(dirname "$0")" && pwd)"
DUMP="$HERE/verify_${VARIANT}.rdla"
LOG="$HERE/verify_${VARIANT}.log"
rm -f "$DUMP" "$LOG"

if [ "$VARIANT" = "houdini" ]; then
  OMR=/Applications/MoonRay/installs/openmoonray-houdini
  export HOUDINI_PATH="$OMR/plugin/houdini;&" PXR_PLUGINPATH_NAME="$OMR/plugin/pxr"
  export RDL2_DSO_PATH="$OMR/rdl2dso" REZ_MOONRAY_ROOT="$OMR" MOONRAY_CLASS_PATH="$OMR/shader_json" ARRAS_SESSION_PATH="$OMR/sessions"
  export PATH="$OMR/bin:$PATH"
  export HDMOONRAY_RDLA_OUTPUT="$DUMP"
  HB=/Applications/Houdini/Houdini20.5.939/Frameworks/Houdini.framework/Versions/20.5/Resources/bin
  timeout 240 "$HB/husk" -R HdMoonrayRendererPlugin -o "$HERE/verify_${VARIANT}.exr" -f 1 \
    --camera /world/cam "$HERE/fixture.usda" > "$LOG" 2>&1
else
  OMR=/Applications/MoonRay/installs/openmoonray-standalone
  # shellcheck disable=SC1091
  source "$OMR/scripts/setup.sh" >/dev/null 2>&1
  export HDMOONRAY_RDLA_OUTPUT="$DUMP"
  timeout 240 hd_render -in "$HERE/fixture.usda" -out "$HERE/verify_${VARIANT}.exr" > "$LOG" 2>&1
fi

if [ ! -f "$DUMP" ]; then echo "FAIL: no RDL dump produced"; exit 1; fi
if ! grep -q 'MeshLight("/world/meshlight")' "$DUMP"; then echo "FAIL: no MeshLight prim"; exit 1; fi
if ! grep -A15 'MeshLight("/world/meshlight")' "$DUMP" | grep -q '"geometry"'; then
  echo "FAIL: MeshLight has no geometry attached"; exit 1
fi
# The geometry attr being set is not enough — MoonRay rejects an emitter that is in the
# render layer. Assert the MeshLight actually LOADED (no load-failure warnings in the log).
if grep -qiE "did not load|cannot be referenced|MeshLight contains no faces" "$LOG"; then
  echo "FAIL: MeshLight did not load —"; grep -iE "did not load|cannot be referenced|no faces" "$LOG" | head -3; exit 1
fi
echo "PASS: MeshLight has geometry attached and loaded (no layer/faces warnings)"; exit 0
