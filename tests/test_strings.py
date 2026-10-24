import contextlib
import io

from helpers import TempDirTestCase, load_module, string_tables_xml

strings = load_module("branding/strings.py", "strings_under_test")
quiet = lambda *_: None


class StringsTest(TempDirTestCase):
    def table(self):
        return string_tables_xml(strings)

    def test_replacements(self):
        rules = strings.replacements("My Product")
        self.assertIn((">Alesis Strike Editor<", ">My Product<"), rules)
        self.assertIn(("vesion", "version"), rules)
        self.assertTrue(all(old != new for old, new in rules))

    def test_by_id(self):
        ids = strings.by_id("https://example.test/guide")
        self.assertEqual(ids["URL_USER_GUIDE"], "https://example.test/guide")
        self.assertEqual(len(set(v for k, v in ids.items() if k.startswith("SETTINGS_FILE_"))), 5,
                         "the five preset-load errors must get distinct messages")
        self.assertIn("Back up", ids["CONTEXT_MENU0.05.NID_IMPORT_DRIVE_CONTENT_REQ"])

    def test_load(self):
        p = self.write("t.xml", b"\xff\xfe" + "<a>é</a>".encode("utf-16-le"))
        self.assertEqual(strings.load(p), "<a>é</a>")
        bad = self.write("bad.xml", b"<a/>")
        with self.assertRaises(strings.StringsError):
            strings.load(bad)

    def test_save(self):
        p = self.path("out.xml")
        strings.save(p, "<a>ü</a>")
        with open(p, "rb") as f:
            raw = f.read()
        self.assertEqual(raw[:2], b"\xff\xfe")
        self.assertEqual(raw[2:].decode("utf-16-le"), "<a>ü</a>")

    def test_apply_replacements(self):
        logged = []
        out = strings.apply_replacements("a vesion and a vesion", [("vesion", "version"), ("zzz", "y")], logged.append)
        self.assertEqual(out, "a version and a version")
        self.assertTrue(logged[0].strip().startswith("2x"))
        self.assertTrue(logged[1].strip().startswith("0x"))

    def test_set_by_id(self):
        text = '<String ID="X"><Locale LCID="0x0009">Old|tip %s</Locale></String>'
        self.assertIn(">New|tip %s<", strings.set_by_id(text, "X", "New|tip %s"))
        with self.assertRaisesRegex(strings.StringsError, "'%s' count changed"):
            strings.set_by_id(text, "X", "New|tip")
        with self.assertRaisesRegex(strings.StringsError, "expected 1 match, found 0"):
            strings.set_by_id(text, "MISSING", "v")
        with self.assertRaisesRegex(strings.StringsError, "found 2"):
            strings.set_by_id(text + text, "X", "New|tip %s")

    def test_rename_id(self):
        text = '<String ID="GHK.A">k</String>'
        self.assertEqual(strings.rename_id(text, "GHK.A", "GHK.B"), '<String ID="GHK.B">k</String>')
        with self.assertRaises(strings.StringsError):
            strings.rename_id(text, "GHK.MISSING", "GHK.B")
        with self.assertRaises(strings.StringsError):
            strings.rename_id(text + '<String ID="GHK.B">k</String>', "GHK.A", "GHK.B")

    def test_check_leftovers(self):
        strings.check_leftovers("<a>check the 'Alesis Strike' MIDI port</a>")
        for bad in ("<a>Alesis Strike Editor</a>", "<a>About Alessis</a>"):
            with self.assertRaises(strings.StringsError):
                strings.check_leftovers(bad)

    def test_check_xml(self):
        strings.check_xml('<?xml version="1.0" encoding="UTF-16"?><a><b/></a>')
        with self.assertRaises(Exception):
            strings.check_xml("<a><b></a>")

    def test_rebrand(self):
        out = strings.rebrand(self.table(), "Strike Pro OSS", "https://example.test", quiet)
        self.assertIn(">Strike Pro OSS<", out)
        self.assertIn("this version was successfully saved", out)
        self.assertIn('ID="GHK.NID_MENU_FILE_SAVEAS_PRESET_TO_FILE"', out)
        self.assertNotIn('ID="GHK.NID_MENU_FILE_SAVE_PRESET_TO_FILE"', out)
        self.assertIn(">https://example.test<", out)
        with self.assertRaises(strings.StringsError):
            strings.rebrand(self.table().replace('ID="URL_USER_GUIDE"', 'ID="GONE"'), log=quiet)

    def test_main(self):
        p = self.path("StringTables.xml")
        strings.save(p, self.table())
        with contextlib.redirect_stdout(io.StringIO()) as out:
            self.assertEqual(strings.main([p, "--product", "Test Pro"]), 0)
        self.assertIn("StringTables.xml OK", out.getvalue())
        self.assertIn(">Test Pro<", strings.load(p))
        # Running again fails cleanly: the IDs it rewrites by value are still there, but the hotkey is already renamed.
        with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(io.StringIO()) as err:
            self.assertEqual(strings.main([p]), 1)
        self.assertIn("hotkey rebinding", err.getvalue())
