"""build.sh, exercised against a fake source bundle so the vendor's app is never needed."""
import os
import re
import subprocess

from helpers import TempDirTestCase, load_module, make_fake_editor, run_zsh

SCRIPT = "build.sh"
strings = load_module("branding/strings.py", "strings_for_build_test")


class BuildTest(TempDirTestCase):
    def setUp(self):
        super().setUp()
        self.source = make_fake_editor(self.tmp, strings)
        self.home = self.path("home")
        self.defaults_log = self.path("defaults.calls")
        stub = self.write("defaults", f'#!/bin/sh\necho "$@" >> "{self.defaults_log}"\n')
        os.chmod(stub, 0o755)
        self.env = {"STRIKE_OUT_DIR": self.path("out"), "STRIKE_INSTALL_DIR": self.path("Applications"),
                    "STRIKE_DEFAULTS": stub, "STRIKE_BUNDLE_ID": "test.strike-pro-oss", "HOME": self.home}
        self.app = self.path("out", "Strike Pro OSS.app")

    def zsh(self, code):
        return run_zsh(SCRIPT, code, self.env)

    def plist(self, app, key):
        return subprocess.run(["/usr/libexec/PlistBuddy", "-c", f"Print :{key}", os.path.join(app, "Contents", "Info.plist")],
                              capture_output=True, text=True).stdout.strip()

    def test_usage(self):
        out = self.zsh("usage").stdout
        self.assertIn("--install", out)
        self.assertIn("--theme", out)

    def test_parse_args(self):
        r = self.zsh('parse_args --install --theme graphite --source /x/y.app; print "$INSTALL|$THEME|$SOURCE"')
        self.assertEqual(r.stdout.strip(), "1|graphite|/x/y.app")
        self.assertEqual(self.zsh("parse_args --nope").returncode, 2)
        self.assertEqual(self.zsh("parse_args --help >/dev/null").returncode, 3)

    def test_check_source(self):
        self.assertEqual(self.zsh(f'check_source "{self.path("missing.app")}"').returncode, 1)
        r = self.zsh(f'check_source "{self.source}"')
        self.assertEqual(r.returncode, 0)
        self.assertIn("not signed by the original vendor", r.stderr)
        self.assertNotIn("tested with", r.stderr)

    def test_inputs_hash(self):
        a = self.zsh(f'inputs_hash "{self.source}" ""').stdout.strip()
        self.assertRegex(a, r"^[0-9a-f]{64}$")
        self.assertEqual(a, self.zsh(f'inputs_hash "{self.source}" ""').stdout.strip())
        self.assertNotEqual(a, self.zsh(f'inputs_hash "{self.source}" graphite').stdout.strip())
        with open(os.path.join(self.source, "Contents", "Resources", "Skins.xml"), "a") as f:
            f.write("<!-- changed -->")
        self.assertNotEqual(a, self.zsh(f'inputs_hash "{self.source}" ""').stdout.strip())

    def test_build_app(self):
        r = self.zsh(f'build_app "{self.source}" graphite')
        self.assertEqual(r.returncode, 0, r.stdout + r.stderr)
        self.assertEqual(self.plist(self.app, "CFBundleName"), "Strike Pro OSS")
        self.assertEqual(self.plist(self.app, "CFBundleIdentifier"), "test.strike-pro-oss")
        self.assertEqual(self.plist(self.app, "CFBundleShortVersionString"), "1.1.6-oss1")
        self.assertEqual(self.plist(self.app, "NSHighResolutionCapable"), "true")
        res = os.path.join(self.app, "Contents", "Resources")
        self.assertIn(">Strike Pro OSS<", strings.load(os.path.join(res, "StringTables.xml")))
        with open(os.path.join(res, "Skins.xml")) as f:
            self.assertIn("0xFFFAAF41", f.read())
        for name in ("Strike.icns", "productlogos.png", "alesis_strike_logo.png"):
            self.assertTrue(os.path.isfile(os.path.join(res, name)), name)
        self.assertEqual(subprocess.run(["codesign", "--verify", "--deep", "--strict", self.app]).returncode, 0)
        # The source bundle is never modified.
        self.assertEqual(self.plist(self.source, "CFBundleName"), "Fake Editor")

    def test_cdhash(self):
        self.zsh(f'build_app "{self.source}" ""')
        self.assertRegex(self.zsh(f'cdhash "{self.app}"').stdout.strip(), r"^[0-9a-f]{40}$")

    def test_migrate_settings(self):
        old = self.write("home/Library/Application Support/Alesis Strike Preset Editor/UserSettings.ini", "CurrentSkinIndex=1\n")
        new = os.path.join(self.home, "Library", "Application Support", "Strike Pro OSS", "UserSettings.ini")
        self.assertIn("migrated", self.zsh("migrate_settings").stdout)
        with open(new) as f:
            self.assertEqual(f.read(), "CurrentSkinIndex=1\n")
        # Never overwrites settings the new app already has.
        with open(old, "w") as f:
            f.write("CurrentSkinIndex=2\n")
        self.assertNotIn("migrated", self.zsh("migrate_settings").stdout)
        with open(new) as f:
            self.assertEqual(f.read(), "CurrentSkinIndex=1\n")

    def test_install_app(self):
        self.zsh(f'build_app "{self.source}" ""')
        r = self.zsh("install_app")
        self.assertEqual(r.returncode, 0, r.stderr)
        installed = self.path("Applications", "Strike Pro OSS.app")
        self.assertEqual(self.plist(installed, "CFBundleName"), "Strike Pro OSS")
        with open(self.defaults_log) as f:
            self.assertEqual(f.read().strip(), "write test.strike-pro-oss NSAppSleepDisabled -bool YES")

    def test_main(self):
        first = self.zsh(f'main --source "{self.source}"')
        self.assertEqual(first.returncode, 0, first.stdout + first.stderr)
        hash1 = re.search(r"arm64 CDHash: ([0-9a-f]{40})", first.stdout)
        assert hash1 is not None, first.stdout
        second = self.zsh(f'main --source "{self.source}" --install')
        self.assertIn("inputs unchanged, keeping existing build", second.stdout)
        self.assertIn(hash1.group(1), second.stdout)
        self.assertTrue(os.path.isdir(self.path("Applications", "Strike Pro OSS.app")))
        self.assertEqual(self.zsh("main --bogus").returncode, 2)
        self.assertEqual(self.zsh("main --help").returncode, 0)
