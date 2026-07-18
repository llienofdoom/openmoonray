#!/usr/bin/env python3
# Copyright 2026. SPDX-License-Identifier: Apache-2.0
"""Consolidate Moonray Houdini VOP shader HDAs into a single `Moonray` TAB
menu with type-based subfolders, replacing the legacy DW Moonray / DreamWorks
/ HIDDEN / Digital Assets placements.

See docs/research/houdini-node-menu-consolidation.md for background.
"""
import argparse
import glob
import os
import re
import shutil
import subprocess
import sys
import tempfile

# (suffix, subfolder) — order matters: NormalMap before the generic Map.
SUFFIX_MAP = [
    ("NormalMap", "Normal Maps"),
    ("Map", "Maps"),
    ("Material", "Materials"),
    ("Displacement", "Displacement"),
    ("DisplayFilter", "Display Filters"),
    ("Volume", "Volumes"),
]

SUBMENU_LINE_RE = re.compile(r"\s*<toolSubmenu>.*</toolSubmenu>\s*$")
SUBMENU_TAG_RE = re.compile(r"<toolSubmenu>([^<]*)</toolSubmenu>")


def classify_subfolder(class_name):
    """Map a node class name to its Moonray subfolder label."""
    for suffix, folder in SUFFIX_MAP:
        if class_name.endswith(suffix):
            return folder
    raise ValueError("unclassifiable class name: %r" % class_name)


def class_from_hda_path(path):
    """Extract the class token from an .hda filename.

    e.g. 'Vop::DW_MOONRAY::DwaMetalMaterial::1.hda' -> 'DwaMetalMaterial'
    """
    name = os.path.basename(path)
    if name.endswith(".hda"):
        name = name[:-4]
    parts = name.split("::")
    return parts[-2]


def rewrite_tools_shelf(text, folder):
    """Collapse every <toolSubmenu> line to a single Moonray/<folder> entry."""
    target = "Moonray/%s" % folder
    out = []
    inserted = False
    for line in text.split("\n"):
        if SUBMENU_LINE_RE.match(line):
            if not inserted:
                indent = re.match(r"(\s*)", line).group(1)
                out.append("%s<toolSubmenu>%s</toolSubmenu>" % (indent, target))
                inserted = True
            # drop all other submenu lines
        else:
            out.append(line)
    return "\n".join(out)


def current_submenus(hda_path):
    """Return submenu strings present in the raw .hda (Tools.shelf is stored
    as uncompressed text, so a raw read is reliable)."""
    with open(hda_path, "rb") as fh:
        data = fh.read().decode("latin-1")
    return SUBMENU_TAG_RE.findall(data)


DEFAULT_HOTL = ("/Applications/Houdini/Houdini20.5.939/Frameworks/"
                "Houdini.framework/Versions/Current/Resources/bin/hotl")
DEFAULT_OTLS_DIR = ("/Applications/MoonRay/source/openmoonray/moonray/"
                    "moonray_dcc_plugins/houdini/otls")


def is_migrated(hda_path):
    """True if the asset already has exactly one Moonray/... submenu."""
    subs = current_submenus(hda_path)
    return bool(subs) and len(set(subs)) == 1 and subs[0].startswith("Moonray/")


def migrate_hda(hda_path, hotl, backup_suffix=".orig"):
    """Rewrite the asset's Tools.shelf to a single Moonray subfolder.

    Returns the subfolder label applied, or None if the asset was already
    migrated and therefore skipped.
    """
    if is_migrated(hda_path):
        return None

    folder = classify_subfolder(class_from_hda_path(hda_path))

    backup = hda_path + backup_suffix
    if not os.path.exists(backup):
        shutil.copy2(hda_path, backup)

    with tempfile.TemporaryDirectory() as td:
        expand_dir = os.path.join(td, "expanded")
        subprocess.run([hotl, "-t", expand_dir, hda_path],
                       check=True, capture_output=True)
        shelves = glob.glob(os.path.join(expand_dir, "**", "Tools.shelf"),
                            recursive=True)
        if len(shelves) != 1:
            raise RuntimeError("%s: expected 1 Tools.shelf, found %d"
                               % (hda_path, len(shelves)))
        for shelf in shelves:
            with open(shelf) as fh:
                body = fh.read()
            with open(shelf, "w") as fh:
                fh.write(rewrite_tools_shelf(body, folder))
        subprocess.run([hotl, "-l", expand_dir, hda_path],
                       check=True, capture_output=True)
    return folder


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("otls_dir", nargs="?", default=DEFAULT_OTLS_DIR,
                        help="directory of .hda files (default: %(default)s)")
    parser.add_argument("--hotl", default=DEFAULT_HOTL,
                        help="path to Houdini hotl binary")
    parser.add_argument("--dry-run", action="store_true",
                        help="classify and report only; do not modify files")
    args = parser.parse_args(argv)

    hdas = sorted(glob.glob(os.path.join(args.otls_dir, "*.hda")))
    if not hdas:
        print("no .hda files found in %s" % args.otls_dir, file=sys.stderr)
        return 1

    tally = {}
    migrated = skipped = 0
    for hda in hdas:
        cls = class_from_hda_path(hda)
        folder = classify_subfolder(cls)
        tally[folder] = tally.get(folder, 0) + 1
        if args.dry_run:
            print("  %-28s -> Moonray/%s" % (cls, folder))
            continue
        result = migrate_hda(hda, args.hotl)
        if result is None:
            skipped += 1
            print("  skip (already migrated): %s" % os.path.basename(hda))
        else:
            migrated += 1
            print("  %-28s -> Moonray/%s" % (cls, result))

    print("\nTally (%d assets):" % len(hdas))
    for folder in sorted(tally):
        print("  %-16s %d" % (folder, tally[folder]))
    if not args.dry_run:
        print("migrated=%d skipped=%d" % (migrated, skipped))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
