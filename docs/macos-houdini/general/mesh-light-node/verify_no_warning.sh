#!/bin/bash
# Fails if the carrier mesh light emits the class-mismatch warning.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
OMR=/Applications/MoonRay/installs/openmoonray-houdini
export HOUDINI_PATH="$OMR/plugin/houdini;&" PXR_PLUGINPATH_NAME="$OMR/plugin/pxr"
export RDL2_DSO_PATH="$OMR/rdl2dso" REZ_MOONRAY_ROOT="$OMR" MOONRAY_CLASS_PATH="$OMR/shader_json" ARRAS_SESSION_PATH="$OMR/sessions"
export PATH="$OMR/bin:$PATH"
HB=/Applications/Houdini/Houdini20.5.939/Frameworks/Houdini.framework/Versions/20.5/Resources/bin
OUT=$(timeout 240 "$HB/husk" -R HdMoonrayRendererPlugin -o "$HERE/nw.exr" -f 1 --camera /world/cam "$HERE/fixture.usda" 2>&1)
if echo "$OUT" | grep -q "may not be compatible with USD light type"; then
  echo "FAIL: class-mismatch warning present"; exit 1
else
  echo "PASS: no class-mismatch warning"; exit 0
fi
