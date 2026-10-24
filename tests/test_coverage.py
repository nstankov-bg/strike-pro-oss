"""Enforces the project rule: every function has a test.

For each script, every top-level function `name` must have a `test_<name>` in that script's test file
(`def test_<name>(` for Python and zsh tests, `func test_<name>(` for Swift tests).
New scripts must be added to TEST_FILES, otherwise this test fails.
"""
import ast
import glob
import os
import re
import unittest

from helpers import ROOT

TEST_FILES = {
    "branding/strings.py": "tests/test_strings.py",
    "branding/skin.py": "tests/test_skin.py",
    "tools/strike-check.py": "tests/test_strike_check.py",
    "branding/logos.swift": "tests/swift/test_logos.swift",
    "tools/strike-probe.swift": "tests/swift/test_probe.swift",
    "build.sh": "tests/test_build.py",
    "tools/strike-backup.sh": "tests/test_backup.py",
    "tools/install-backup-agent.sh": "tests/test_install_agent.py",
}


def read(rel):
    with open(os.path.join(ROOT, rel)) as f:
        return f.read()


def functions(rel):
    """Top-level function names defined in a script."""
    text = read(rel)
    if rel.endswith(".py"):
        return [n.name for n in ast.parse(text).body if isinstance(n, ast.FunctionDef)]
    if rel.endswith(".swift"):
        return re.findall(r"^func (\w+)", text, re.M)
    return re.findall(r"^(\w+)\(\) \{", text, re.M)


def tested(test_rel):
    pattern = r"^\s*func test_(\w+)\(" if test_rel.endswith(".swift") else r"^\s*def test_(\w+)\("
    return set(re.findall(pattern, read(test_rel), re.M))


# Scripts with no functions of their own (a one-line exec of the test runner).
EXEMPT = {"run-tests.sh"}


def scripts():
    found = []
    for pattern in ("*.sh", "branding/*", "tools/*"):
        found += [os.path.relpath(p, ROOT) for p in glob.glob(os.path.join(ROOT, pattern))
                  if p.endswith((".py", ".swift", ".sh"))]
    return sorted(set(found) - EXEMPT)


class CoverageTest(unittest.TestCase):
    def test_every_script_has_a_test_file(self):
        self.assertEqual(sorted(TEST_FILES), scripts(), "map new scripts to a test file in TEST_FILES")

    def test_every_function_has_a_test(self):
        missing = []
        for script, test_file in TEST_FILES.items():
            names = functions(script)
            self.assertTrue(names, f"no functions found in {script}")
            have = tested(test_file)
            missing += [f"{script}: {name}" for name in names if name not in have]
        self.assertEqual(missing, [], "functions without a test_<name> in their test file")

    def test_functions(self):
        self.assertIn("rebrand", functions("branding/strings.py"))
        self.assertIn("matchDecision", functions("tools/strike-probe.swift"))
        self.assertIn("take_snapshot", functions("tools/strike-backup.sh"))

    def test_tested(self):
        self.assertIn("rebrand", tested("tests/test_strings.py"))
        self.assertIn("matchDecision", tested("tests/swift/test_probe.swift"))

    def test_scripts(self):
        self.assertIn("build.sh", scripts())
        self.assertIn("tools/strike-check.py", scripts())
