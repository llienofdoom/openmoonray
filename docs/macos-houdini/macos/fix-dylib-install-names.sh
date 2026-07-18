#!/bin/bash
# fix-dylib-install-names.sh — Rewrite dirty dylib install names in the MoonRay installs tree.
#
# PROBLEM
# =======
# Several autotools-based deps (OpenSSL, libcurl, log4cplus, microhttpd, libuuid, cppunit)
# embed their --prefix= string literally into their dylib install names. Because
# building/macOS/CMakeLists.txt derives InstallRoot as:
#
#   ${rootSrcDir}/../../../../installs
#
# the install name ends up as:
#
#   /Applications/MoonRay/source/openmoonray/building/macOS/../../../../installs/lib/libssl.3.dylib
#
# macOS dyld must traverse every intermediate directory in a path containing ..  — it does
# not resolve .. symbolically. On a machine where source/ was never installed this
# traversal fails and the dylib cannot be loaded.
#
# FIX
# ===
# This script rewrites:
#   1. The install name (-id) of each of the 8 affected real dylibs.
#   2. Every LC_LOAD_DYLIB entry (-change) that references a dirty path, across all
#      MoonRay binaries and dylibs in the installs tree.
#
# After this script runs, all references use clean absolute paths with no .. components.
#
# WHEN TO RUN
# ===========
# Run once after the dependency build completes (step: cmake --build . -- -j8 in build-deps/).
# The root cause is also fixed in building/macOS/CMakeLists.txt (get_filename_component
# ABSOLUTE normalisation), so clean builds using the patched CMakeLists.txt will not produce
# dirty paths. This script remains useful as a safety net and for fixing existing installs.
#
# USAGE
# =====
#   chmod +x fix-dylib-install-names.sh
#   ./fix-dylib-install-names.sh

set -euo pipefail

INSTALLS=/Applications/MoonRay/installs

DIRTY_PREFIX="/Applications/MoonRay/source/openmoonray/building/macOS/../../../../installs"
CLEAN_PREFIX="$INSTALLS"

# The 8 autotools dylibs whose install names contain ..
LIBS=(
    libcppunit-1.15.1.dylib
    libcrypto.3.dylib
    libcurl.4.dylib
    liblog4cplus-2.0.3.dylib
    liblog4cplusU-2.0.3.dylib
    libmicrohttpd.12.dylib
    libssl.3.dylib
    libuuid.1.dylib
)

# Build the -change argument list for install_name_tool
CHANGE_ARGS=()
for lib in "${LIBS[@]}"; do
    CHANGE_ARGS+=("-change" "${DIRTY_PREFIX}/lib/${lib}" "${CLEAN_PREFIX}/lib/${lib}")
done

echo "=== Step 1: Fix install names (-id) of the 8 affected dylibs ==="
for lib in "${LIBS[@]}"; do
    file="$INSTALLS/lib/$lib"
    if [[ ! -f "$file" ]]; then
        echo "  SKIP (not found): $file"
        continue
    fi
    current=$(otool -D "$file" 2>/dev/null | tail -1)
    if echo "$current" | grep -q '\.\.'; then
        install_name_tool -id "$CLEAN_PREFIX/lib/$lib" "$file"
        echo "  Fixed -id: $lib"
    else
        echo "  Already clean: $lib"
    fi
done

echo ""
echo "=== Step 2: Fix LC_LOAD_DYLIB references across all binaries and dylibs ==="
fixed=0
skipped=0

while IFS= read -r f; do
    if otool -L "$f" 2>/dev/null | grep -q '\.\.'; then
        if install_name_tool "${CHANGE_ARGS[@]}" "$f" 2>/dev/null; then
            echo "  Fixed refs: $f"
            ((fixed++)) || true
        else
            echo "  WARN: could not modify $f (codesign or permission issue)"
            ((skipped++)) || true
        fi
    fi
done < <(find "$INSTALLS" -type f \( -name "*.dylib" -o -perm +0111 \) 2>/dev/null)

echo ""
echo "Step 2 complete: $fixed files fixed, $skipped skipped."
echo ""
echo "=== Step 3: Fix dirty-path absolute symlinks ==="
# Some autotools deps create absolute symlinks using the same un-normalised prefix.
# Replace them with relative symlinks so they resolve on any machine.
fix_symlink() {
    local link="$1" rel_target="$2"
    local current
    current=$(readlink "$link" 2>/dev/null || true)
    if echo "${current:-}" | grep -q '\.\.'; then
        ln -sfn "$rel_target" "$link"
        echo "  Fixed symlink: $link -> $rel_target"
    else
        echo "  Already clean: $link"
    fi
}

fix_symlink "$INSTALLS/lib/libcurl.so.4"    "libcurl.4.dylib"
fix_symlink "$INSTALLS/include/uuid.h"      "_uuid/uuid.h"

echo ""
echo "=== Verification ==="
dirty_count=$(find "$INSTALLS" -type f \( -name "*.dylib" -o -perm +0111 \) \
    -exec sh -c 'otool -L "$1" 2>/dev/null | grep -q "\.\." && echo "$1"' _ {} \; 2>/dev/null | wc -l | tr -d ' ')
echo "Files still containing .. in load commands: $dirty_count"

dirty_links=$(find "$INSTALLS" -type l | while read -r f; do
    t=$(readlink "$f")
    if echo "$t" | grep -q '\.\.'; then echo "$f -> $t"; fi
done)
if [[ -n "$dirty_links" ]]; then
    echo "WARN: dirty-path symlinks still present:"
    echo "$dirty_links"
else
    echo "No dirty-path symlinks found."
fi

if [[ "$dirty_count" -eq 0 ]] && [[ -z "$dirty_links" ]]; then
    echo "All clear."
else
    echo "WARN: some files could not be fixed — see WARN lines above."
fi
