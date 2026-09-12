#!/usr/bin/env python3
import importlib.util
import tempfile
import unittest
from pathlib import Path

KIT = Path(__file__).resolve().parent.parent
MODULE_PATH = KIT / "lib" / "check-contrast.py"

spec = importlib.util.spec_from_file_location("check_contrast", MODULE_PATH)
check_contrast = importlib.util.module_from_spec(spec)
spec.loader.exec_module(check_contrast)


class ContrastMathTests(unittest.TestCase):
    def test_rel_luminance_extremes(self):
        self.assertAlmostEqual(check_contrast.rel_luminance((255, 255, 255)), 1.0, places=3)
        self.assertAlmostEqual(check_contrast.rel_luminance((0, 0, 0)), 0.0, places=3)

    def test_contrast_black_on_white_is_max(self):
        self.assertAlmostEqual(check_contrast.contrast((0, 0, 0), (255, 255, 255)), 21.0, places=1)

    def test_contrast_is_symmetric(self):
        a, b = (10, 20, 30), (200, 210, 220)
        self.assertAlmostEqual(check_contrast.contrast(a, b), check_contrast.contrast(b, a), places=6)


class ParseAndCheckTests(unittest.TestCase):
    def _write(self, tmp, name, content):
        p = Path(tmp) / name
        p.write_text(content)
        return p

    def test_parse_ignores_non_colors_groups(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = self._write(
                tmp, "sample.colors",
                "[General]\nName=X\n[Colors:Window]\nBackgroundNormal=10,20,30\n",
            )
            groups = check_contrast.parse(p)
            self.assertEqual(groups.get("[General]"), {})
            self.assertEqual(groups["[Colors:Window]"]["BackgroundNormal"], (10, 20, 30))

    def test_check_readable_scheme_passes(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = self._write(
                tmp, "good.colors",
                "[Colors:Window]\nBackgroundNormal=255,255,255\nForegroundNormal=0,0,0\n",
            )
            self.assertEqual(check_contrast.check(p), 0)

    def test_check_unreadable_scheme_fails(self):
        with tempfile.TemporaryDirectory() as tmp:
            p = self._write(
                tmp, "bad.colors",
                "[Colors:Window]\nBackgroundNormal=255,255,255\nForegroundNormal=250,250,250\n",
            )
            self.assertEqual(check_contrast.check(p), 1)

    def test_check_missing_file(self):
        self.assertEqual(check_contrast.check(Path("/nonexistent/path.colors")), 2)


if __name__ == "__main__":
    unittest.main()
