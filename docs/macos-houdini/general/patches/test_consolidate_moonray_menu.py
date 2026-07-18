import glob
import os
import re
import shutil
import subprocess
import tempfile
import unittest
from unittest.mock import patch

import consolidate_moonray_menu as cm

SHELF_BEFORE = """<?xml version="1.0" encoding="UTF-8"?>
<shelfDocument>
  <tool name="$HDA_DEFAULT_TOOL" label="$HDA_LABEL" icon="$HDA_ICON">
    <toolMenuContext name="network">
      <contextOpType>$HDA_TABLE_AND_NAME</contextOpType>
    </toolMenuContext>
            <toolSubmenu>DW Moonray</toolSubmenu>
            <toolSubmenu>Digital Assets</toolSubmenu>
            <toolSubmenu>DreamWorks/All</toolSubmenu>
            <toolSubmenu>DreamWorks/HIDDEN</toolSubmenu>
    <script scriptType="python"><![CDATA[import voptoolutils]]></script>
  </tool>
</shelfDocument>
"""


class TestClassify(unittest.TestCase):
    def test_material(self):
        self.assertEqual(cm.classify_subfolder("DwaMetalMaterial"), "Materials")

    def test_normalmap_before_map(self):
        # NormalMap must win over the generic Map suffix
        self.assertEqual(cm.classify_subfolder("ImageNormalMap"), "Normal Maps")

    def test_plain_map(self):
        self.assertEqual(cm.classify_subfolder("OpMap"), "Maps")

    def test_displacement(self):
        self.assertEqual(cm.classify_subfolder("NormalDisplacement"), "Displacement")

    def test_display_filter(self):
        self.assertEqual(cm.classify_subfolder("BlendDisplayFilter"), "Display Filters")

    def test_volume(self):
        self.assertEqual(cm.classify_subfolder("VdbVolume"), "Volumes")

    def test_unclassifiable_raises(self):
        with self.assertRaises(ValueError):
            cm.classify_subfolder("SomethingElse")


class TestClassFromPath(unittest.TestCase):
    def test_versioned(self):
        p = "/x/otls/Vop::DW_MOONRAY::DwaMetalMaterial::1.hda"
        self.assertEqual(cm.class_from_hda_path(p), "DwaMetalMaterial")

    def test_multi_version(self):
        p = "Vop::DW_MOONRAY::NoiseWorleyMap::3.hda"
        self.assertEqual(cm.class_from_hda_path(p), "NoiseWorleyMap")


class TestRewriteToolsShelf(unittest.TestCase):
    def test_collapses_to_single(self):
        out = cm.rewrite_tools_shelf(SHELF_BEFORE, "Materials")
        self.assertEqual(out.count("<toolSubmenu>"), 1)
        self.assertIn("<toolSubmenu>Moonray/Materials</toolSubmenu>", out)
        self.assertNotIn("DW Moonray", out)
        self.assertNotIn("DreamWorks", out)
        self.assertNotIn("Digital Assets", out)

    def test_preserves_indentation(self):
        out = cm.rewrite_tools_shelf(SHELF_BEFORE, "Materials")
        self.assertIn("            <toolSubmenu>Moonray/Materials</toolSubmenu>", out)

    def test_idempotent(self):
        once = cm.rewrite_tools_shelf(SHELF_BEFORE, "Materials")
        twice = cm.rewrite_tools_shelf(once, "Materials")
        self.assertEqual(once, twice)

    def test_keeps_script_section(self):
        out = cm.rewrite_tools_shelf(SHELF_BEFORE, "Materials")
        self.assertIn("voptoolutils", out)


HOTL = os.environ.get("HOTL", cm.DEFAULT_HOTL)
OTLS = os.environ.get("OTLS_DIR", cm.DEFAULT_OTLS_DIR)
MATERIAL_HDA = os.path.join(OTLS, "Vop::DW_MOONRAY::DwaMetalMaterial::1.hda")
NORMALMAP_HDA = os.path.join(OTLS, "Vop::DW_MOONRAY::ImageNormalMap::1.hda")

_have_hotl = os.path.exists(HOTL)
_have_fixtures = os.path.exists(MATERIAL_HDA) and os.path.exists(NORMALMAP_HDA)

# The legacy (pre-consolidation) submenu set that migrate_hda is supposed to
# collapse down to a single Moonray/<folder> entry.
LEGACY_SUBMENUS = ["DW Moonray", "Digital Assets", "DreamWorks/All", "DreamWorks/HIDDEN"]


def force_legacy_shelf(hda_path, hotl):
    """Force `hda_path`'s Tools.shelf to the legacy 4-submenu layout.

    This makes integration tests hermetic against the live otls tree, which
    this very tool may have already migrated: it does the same
    `hotl -t` expand -> edit -> `hotl -l` collapse round-trip migrate_hda
    uses, but replaces whatever <toolSubmenu> line(s) are present with the
    four legacy lines (at the same indentation) instead of a single
    Moonray/<folder> line.
    """
    with tempfile.TemporaryDirectory() as td:
        expand_dir = os.path.join(td, "expanded")
        subprocess.run([hotl, "-t", expand_dir, hda_path],
                       check=True, capture_output=True)
        shelves = glob.glob(os.path.join(expand_dir, "**", "Tools.shelf"),
                            recursive=True)
        if len(shelves) != 1:
            raise RuntimeError("%s: expected 1 Tools.shelf, found %d"
                               % (hda_path, len(shelves)))
        shelf = shelves[0]
        with open(shelf) as fh:
            body = fh.read()
        out = []
        inserted = False
        for line in body.split("\n"):
            if cm.SUBMENU_LINE_RE.match(line):
                if not inserted:
                    indent = re.match(r"(\s*)", line).group(1)
                    for name in LEGACY_SUBMENUS:
                        out.append("%s<toolSubmenu>%s</toolSubmenu>" % (indent, name))
                    inserted = True
                # drop all other submenu lines
            else:
                out.append(line)
        if not inserted:
            raise RuntimeError("%s: no <toolSubmenu> line found to replace" % shelf)
        with open(shelf, "w") as fh:
            fh.write("\n".join(out))
        subprocess.run([hotl, "-l", expand_dir, hda_path],
                       check=True, capture_output=True)


@unittest.skipUnless(_have_hotl and _have_fixtures, "hotl or fixture HDAs missing")
class TestMigrateHda(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.mat = os.path.join(self.tmp, os.path.basename(MATERIAL_HDA))
        self.nrm = os.path.join(self.tmp, os.path.basename(NORMALMAP_HDA))
        shutil.copy2(MATERIAL_HDA, self.mat)
        shutil.copy2(NORMALMAP_HDA, self.nrm)
        # The live source otls may already be migrated by this tool (it's
        # meant to be run against them) -- force a known legacy starting
        # state so these tests are deterministic regardless of the live
        # tree's current migration state.
        force_legacy_shelf(self.mat, HOTL)
        force_legacy_shelf(self.nrm, HOTL)

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_material_migrates_to_single_moonray_submenu(self):
        folder = cm.migrate_hda(self.mat, HOTL)
        self.assertEqual(folder, "Materials")
        subs = cm.current_submenus(self.mat)
        self.assertEqual(subs, ["Moonray/Materials"])

    def test_normalmap_classified_correctly(self):
        folder = cm.migrate_hda(self.nrm, HOTL)
        self.assertEqual(folder, "Normal Maps")
        self.assertEqual(cm.current_submenus(self.nrm), ["Moonray/Normal Maps"])

    def test_backup_created(self):
        cm.migrate_hda(self.mat, HOTL)
        self.assertTrue(os.path.exists(self.mat + ".orig"))
        # backup retains the legacy submenus
        self.assertIn("DW Moonray", cm.current_submenus(self.mat + ".orig"))

    def test_idempotent_second_run_skips(self):
        cm.migrate_hda(self.mat, HOTL)
        result = cm.migrate_hda(self.mat, HOTL)
        self.assertIsNone(result)  # skipped
        self.assertEqual(cm.current_submenus(self.mat), ["Moonray/Materials"])

    def test_safety_stop_zero_shelves(self):
        # migrate_hda must refuse to guess when the expand doesn't yield
        # exactly one Tools.shelf -- here, zero.
        with patch.object(cm.glob, "glob", return_value=[]):
            with self.assertRaises(RuntimeError):
                cm.migrate_hda(self.mat, HOTL)

    def test_safety_stop_multiple_shelves(self):
        # ...and here, two (an ambiguous expand).
        with patch.object(cm.glob, "glob", return_value=["a/Tools.shelf", "b/Tools.shelf"]):
            with self.assertRaises(RuntimeError):
                cm.migrate_hda(self.nrm, HOTL)


@unittest.skipUnless(_have_fixtures, "fixture HDAs missing")
class TestMainDryRun(unittest.TestCase):
    """--dry-run must classify/report only and make no writes whatsoever."""

    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        self.dst = os.path.join(self.tmp, os.path.basename(MATERIAL_HDA))
        shutil.copy2(MATERIAL_HDA, self.dst)
        with open(self.dst, "rb") as fh:
            self.original_bytes = fh.read()

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def test_dry_run_makes_no_writes(self):
        rc = cm.main([self.tmp, "--dry-run", "--hotl", HOTL])
        self.assertEqual(rc, 0)
        self.assertFalse(os.path.exists(self.dst + ".orig"))
        with open(self.dst, "rb") as fh:
            self.assertEqual(fh.read(), self.original_bytes)


class TestMainNoHdas(unittest.TestCase):
    def test_empty_dir_returns_1(self):
        tmp = tempfile.mkdtemp()
        try:
            self.assertEqual(cm.main([tmp]), 1)
        finally:
            shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    unittest.main()
