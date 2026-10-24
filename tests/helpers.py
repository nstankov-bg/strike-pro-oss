"""Shared fixtures for the test suite. Nothing here needs the vendor's app or a connected module."""
import importlib.util
import os
import shutil
import struct
import subprocess
import tempfile
import unittest

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))


def load_module(relpath, name):
    """Imports a repo script (even one with a hyphen in its name) as a module."""
    spec = importlib.util.spec_from_file_location(name, os.path.join(ROOT, relpath))
    assert spec is not None and spec.loader is not None, relpath
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def wav_bytes(rate=44100, bits=16, channels=1, frames=100, tag=1, data=None):
    """A minimal RIFF/WAVE file. `data` overrides the sample bytes."""
    block = channels * bits // 8
    if data is None:
        data = bytes((i * 7) % 256 for i in range(frames * block))
    fmt = struct.pack("<HHIIHH", tag, channels, rate, rate * block, block, bits)
    body = b"WAVE" + b"fmt " + struct.pack("<I", len(fmt)) + fmt + b"data" + struct.pack("<I", len(data)) + data
    return b"RIFF" + struct.pack("<I", len(body)) + body


def string_tables_xml(strings_module, extra=""):
    """A synthetic StringTables.xml containing every String ID the rebrand script expects."""
    entries = []
    for sid, value in strings_module.by_id(strings_module.DEFAULT_URL).items():
        old = "Old|value" if "|" in value else "Old value"
        entries.append(f'<String ID="{sid}"><Locale LCID="0x0009">{old}</Locale></String>')
    for old_id in strings_module.RENAME_IDS:
        entries.append(f'<String ID="{old_id}"><Locale LCID="0x0009">Ctrl+VKEY_S</Locale></String>')
    entries.append('<String ID="CAPTION"><Locale LCID="0x0009">Alesis Strike Editor</Locale></String>')
    entries.append('<String ID="TYPO"><Locale LCID="0x0009">this vesion was sucessfully saved</Locale></String>')
    return ('<?xml version="1.0" encoding="UTF-16" standalone="yes"?><M-Audio_StringTable_Definitions>'
            '<Application Name="PresetEditor"><StringTable ID="|PresetEditor">'
            + "".join(entries) + extra + "</StringTable></Application></M-Audio_StringTable_Definitions>")


SKINS_XML = ('<?xml version="1.0" encoding="utf-8"?><Skins><Colorizers>'
             '<Colorizer Name="AlesisBlue" ColorType="SolidFill" Color="0xFF0093D0" />'
             '<Colorizer Name="Control" ColorType="SolidFill" Color="0xffece9d8" />'
             '<Colorizer Name="White" ColorType="SolidFill" Color="0xFFFFFFFF" />'
             '</Colorizers></Skins>')


def make_fake_editor(parent, strings_module):
    """A stand-in for the vendor's 1.1.6 bundle with the same layout (no vendor content)."""
    app = os.path.join(parent, "Fake Strike Editor.app")
    os.makedirs(os.path.join(app, "Contents", "MacOS"))
    os.makedirs(os.path.join(app, "Contents", "Resources"))
    plist = os.path.join(app, "Contents", "Info.plist")
    subprocess.run(["plutil", "-create", "xml1", plist], check=True)
    for key, value in [("CFBundleExecutable", "Panel"), ("CFBundleIdentifier", "test.fake.editor"),
                       ("CFBundleName", "Fake Editor"), ("CFBundleShortVersionString", "1.1.6"),
                       ("CFBundlePackageType", "APPL"), ("NSHumanReadableCopyright", "fake")]:
        subprocess.run(["plutil", "-insert", key, "-string", value, plist], check=True)
    panel = os.path.join(app, "Contents", "MacOS", "Panel")
    with open(panel, "w") as f:
        f.write("#!/bin/sh\nexit 0\n")
    os.chmod(panel, 0o755)
    res = os.path.join(app, "Contents", "Resources")
    with open(os.path.join(res, "StringTables.xml"), "wb") as f:
        f.write(b"\xff\xfe" + string_tables_xml(strings_module).encode("utf-16-le"))
    with open(os.path.join(res, "Skins.xml"), "w") as f:
        f.write(SKINS_XML)
    return app


def run_zsh(script, code, env=None, cwd=None):
    """Sources `script` (its main() is guarded, so it doesn't run) and evaluates `code`."""
    full_env = dict(os.environ, **(env or {}))
    return subprocess.run(["/bin/zsh", "-c", 'source "$1" && eval "$2"', "zsh", os.path.join(ROOT, script), code],
                          capture_output=True, text=True, env=full_env, cwd=cwd)


class TempDirTestCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="strike-test-")
        self.addCleanup(shutil.rmtree, self.tmp, True)

    def path(self, *parts):
        return os.path.join(self.tmp, *parts)

    def write(self, relpath, data):
        p = self.path(relpath)
        os.makedirs(os.path.dirname(p), exist_ok=True)
        with open(p, "wb" if isinstance(data, bytes) else "w") as f:
            f.write(data)
        return p
