"""Runs the Swift test files through the interpreter (no compiled binaries)."""
import os
import subprocess
import unittest

from helpers import ROOT

SUITES = {
    "branding/logos.swift": "tests/swift/test_logos.swift",
    "tools/strike-probe.swift": "tests/swift/test_probe.swift",
}


def run_swift_suite(script, test_file):
    source = ""
    for rel in (script, "tests/swift/harness.swift", test_file):
        with open(os.path.join(ROOT, rel)) as f:
            source += f.read() + "\n"
    return subprocess.run(["swift", "-"], input=source, capture_output=True, text=True,
                          env=dict(os.environ, STRIKE_TEST="1"), timeout=600)


class SwiftTest(unittest.TestCase):
    def check(self, script):
        r = run_swift_suite(script, SUITES[script])
        self.assertEqual(r.returncode, 0, f"{script}\n{r.stdout}\n{r.stderr}")
        self.assertIn("\nOK", "\n" + r.stdout)

    def test_logos_swift(self):
        self.check("branding/logos.swift")

    def test_strike_probe_swift(self):
        self.check("tools/strike-probe.swift")
