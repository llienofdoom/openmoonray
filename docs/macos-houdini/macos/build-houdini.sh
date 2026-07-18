#!/bin/bash
# build-houdini.sh — Build OpenMoonRay with Houdini USD 24.3
#
# BACKGROUND
# ==========
# installs/include/pxr/ contains USD 22.11 headers. Houdini's libpxr_* uses
# USD 24.3 (namespace pxrInternal_v0_24). cmake's Xcode generator places
# SYSTEM_HEADER_SEARCH_PATHS (-isystem installs/include) BEFORE OTHER_CPLUSPLUSFLAGS
# (-isystem toolkit/include) in the clang compile command, so USD 22.11 headers
# win and compiled objects use the wrong namespace — causing undefined symbol
# link errors against libpxr_*.
#
# FIX: temporarily rename installs/include/pxr/ during the build so clang
# cannot find USD 22.11 pxr headers there and falls through to toolkit/include.
#
# USAGE
# =====
#   ./build-houdini.sh [xcodebuild options...]
#
# Examples:
#   ./build-houdini.sh                          # build all targets
#   ./build-houdini.sh -target hd_moonray       # build only hd_moonray
#   ./build-houdini.sh -jobs 8                  # parallel build

set -euo pipefail

MOONRAY_ROOT=/Applications/MoonRay
BUILD_DIR="$MOONRAY_ROOT/build"
XCODEPROJ="$BUILD_DIR/openmoonray.xcodeproj"
PXR_INCLUDE="$MOONRAY_ROOT/installs/include/pxr"
PXR_INCLUDE_DISABLED="$MOONRAY_ROOT/installs/include/pxr_standalone_disabled"
PATCH_SCRIPT="$MOONRAY_ROOT/source/openmoonray/building/macOS/pxr-houdini/patch-toolkit-headers.sh"

# Ensure toolkit headers are patched (idempotent)
if [[ -x "$PATCH_SCRIPT" ]]; then
    "$PATCH_SCRIPT"
fi

# Verify project exists
if [[ ! -d "$XCODEPROJ" ]]; then
    echo "ERROR: Xcode project not found: $XCODEPROJ"
    echo "Run cmake configure first:"
    echo "  PYFRAME=/Applications/Houdini/Houdini20.5.939/Frameworks/Python.framework"
    echo "  cmake -S /Applications/MoonRay/openmoonray --preset macos-houdini-release \\"
    echo "    -DPython_ROOT_DIR=\"\$PYFRAME/Versions/3.11\" \\"
    echo "    -DPython_EXECUTABLE=\"\$PYFRAME/Versions/3.11/bin/python3.11\" \\"
    echo "    -DPython_INCLUDE_DIR=\"\$PYFRAME/Versions/3.11/include/python3.11\" \\"
    echo "    -DPython_LIBRARY=\"\$PYFRAME/Versions/3.11/lib/libpython3.11.dylib\" \\"
    echo "    -DPYTHON_EXECUTABLE=\"\$PYFRAME/Versions/3.11/bin/python3.11\""
    exit 1
fi

# Ensure standalone pxr headers are present before we disable them
if [[ ! -d "$PXR_INCLUDE" && ! -d "$PXR_INCLUDE_DISABLED" ]]; then
    echo "ERROR: Neither $PXR_INCLUDE nor $PXR_INCLUDE_DISABLED found"
    exit 1
fi

# Restore function — always re-enable standalone pxr headers on exit
restore_pxr() {
    if [[ -d "$PXR_INCLUDE_DISABLED" && ! -d "$PXR_INCLUDE" ]]; then
        echo "Restoring installs/include/pxr..."
        mv "$PXR_INCLUDE_DISABLED" "$PXR_INCLUDE"
        echo "Restored."
    fi
}
trap restore_pxr EXIT

# Disable standalone USD 22.11 pxr headers
if [[ -d "$PXR_INCLUDE" ]]; then
    echo "Disabling installs/include/pxr (USD 22.11) to force use of Houdini toolkit (USD 24.3)..."
    mv "$PXR_INCLUDE" "$PXR_INCLUDE_DISABLED"
fi

# Build
echo "Building with Xcode project: $XCODEPROJ"
xcodebuild \
    -project "$XCODEPROJ" \
    -configuration Release \
    "$@"

echo "Build complete."
