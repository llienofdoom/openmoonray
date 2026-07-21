#!/bin/bash
# Package the compiled MoonRay-for-Houdini install into a dated, deployable zip.
#
# Usage: package-installs.sh <destination-dir>
#
# Auto-detects the OS, zips the local MoonRay `installs/` tree (preserving
# symlinks), names it  moonray-houdini-<os>-<YYYY-MM-DD>.zip,  stages it on local
# disk, then moves it to <destination-dir>. The archive unpacks to
#   MoonRay/installs/...
# so on a target machine you unzip it and place the resulting MoonRay/ folder at
# /opt (Linux) or /Applications (macOS).
#
# The destination is a REQUIRED argument on purpose — it is never hard-coded here,
# because deploy locations are personal / site-specific.
set -euo pipefail

dest="${1:-}"
if [ -z "$dest" ]; then
    echo "Usage: package-installs.sh <destination-dir>" >&2
    echo "  (destination is required — intentionally not hard-coded)" >&2
    exit 1
fi

case "$(uname -s)" in
    Darwin) os=macos; parent=/Applications ;;
    Linux)  os=linux; parent=/opt ;;
    *) echo "Unsupported OS: $(uname -s)" >&2; exit 1 ;;
esac

src="$parent/MoonRay/installs"
[ -d "$src" ] || { echo "Not found: $src (build MoonRay first)" >&2; exit 1; }
command -v zip >/dev/null || { echo "'zip' not found — install it (Linux: sudo dnf install -y zip)" >&2; exit 1; }

zipname="moonray-houdini-${os}-$(date +%Y-%m-%d).zip"

# Stage on local disk (a few GB of scratch), then move to the destination.
stage="$(mktemp -d "${TMPDIR:-/var/tmp}/moonray-pkg.XXXXXX")"
trap 'rm -rf "$stage"' EXIT

echo "Packaging $src"
echo "  -> $zipname (preserving symlinks; this can take a minute)..."
# zip from the parent so the archive root is MoonRay/installs/...
( cd "$parent" && zip -r -y -q "$stage/$zipname" MoonRay/installs )

mkdir -p "$dest"
mv -f "$stage/$zipname" "$dest/$zipname"

size="$(du -h "$dest/$zipname" | cut -f1)"
echo "Done: $dest/$zipname ($size)"
echo "Deploy: unzip on the target -> MoonRay/installs/... ; place MoonRay/ at $parent/"
