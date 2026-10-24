import contextlib
import io

from helpers import SKINS_XML, TempDirTestCase, load_module

skin = load_module("branding/skin.py", "skin_under_test")


class SkinTest(TempDirTestCase):
    def test_normalize(self):
        self.assertEqual(skin.normalize("0xff0093d0"), "0xFF0093D0")
        self.assertEqual(skin.normalize("0XFF0093D0"), "0xFF0093D0")

    def test_apply_theme(self):
        text, counts = skin.apply_theme(SKINS_XML, skin.THEMES["graphite"])
        self.assertEqual(counts, {"0xFF0093D0": 1, "0xFFECE9D8": 1})
        self.assertIn('Color="0xFFFAAF41"', text)
        self.assertIn('Color="0xFF1A212A"', text)  # matched case-insensitively ("0xffece9d8" in the fixture)
        self.assertIn('Color="0xFFFFFFFF"', text)  # unmapped colours untouched
        self.assertNotIn("0093D0", text)

    def test_main(self):
        p = self.write("Skins.xml", SKINS_XML)
        with contextlib.redirect_stdout(io.StringIO()) as out:
            self.assertEqual(skin.main([p, "--theme", "graphite"]), 0)
        self.assertIn("1x 0xFF0093D0 -> 0xFFFAAF41", out.getvalue())
        with open(p) as f:
            self.assertIn("0xFFFAAF41", f.read())
        # A second pass has nothing left to recolour.
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()) as err:
            self.assertEqual(skin.main([p, "--theme", "graphite"]), 1)
        self.assertIn("matched no colours", err.getvalue())
