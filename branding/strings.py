"""Rewrite the editor's UI text (Resources/StringTables.xml) for a Strike Pro OSS build.

StringTables.xml is a single-line UTF-16LE file with a BOM. Only user-visible text is changed:
  - product-name replacements (substring rules),
  - targeted rewrites of specific strings by their String ID (clearer, more honest messages),
  - the dead Save hotkey is rebound to Save As (the plain Save command has no handler in the app).
Device-matching strings live in the executable and are never touched.

Usage: python3 -I strings.py <StringTables.xml> [--product "Strike Pro OSS"] [--url https://...]
"""
import argparse
import re
import sys
import xml.etree.ElementTree as ET

parser = argparse.ArgumentParser()
parser.add_argument("path")
parser.add_argument("--product", default="Strike Pro OSS")
parser.add_argument("--url", default="https://github.com/nstankov-bg/strike-pro-oss#readme")
args = parser.parse_args()
P = args.product

# Substring rules, applied in order.
REPLACEMENTS = [
    ("About Strike Editor|About Alessis Strike Editor", f"About {P}|About {P}"),
    ("About Alesis Strike Preset Editor", f"About {P}"),
    (">Alesis Strike Editor<", f">{P}<"),
    ("Alesis Strike Instrument File", "Strike Instrument File"),
    ("Alesis Strike Kit File", "Strike Kit File"),
    ("Alesis Strike User Content File", "Strike User Content File"),
    ("Alesis Strike Factory Content Update File", "Strike Factory Content File"),
    ("Alesis Factory Content", "Factory Content"),
    ("Verify your Alesis Strike module is plugged into the USB port", "Verify your Strike module is plugged into the USB port"),
    # Typos in the original
    ("retreieving", "retrieving"), ("retreived", "retrieved"),
    ("Retrieve Sucessful", "Retrieve Successful"), ("sucessfully", "successfully"),
    ("Send Sucess", "Send Success"), ("vesion", "version"),
]

# Whole-value rewrites by String ID (each ID must exist exactly once).
BY_ID = {
    # Factory content: the most destructive action in the app; say what it does.
    "CONTEXT_MENU0.05.NID_IMPORT_DRIVE_CONTENT_REQ":
        "Restore Factory Content from .bin…|Erases and replaces the module's factory content from a .bin file. Back up the module drive first.",
    "IMPORT_DRIVE_CONTENT_DIALOG_TITLE": "Select Factory Content .bin File",
    "IMPORT_DRIVE_CONTENT_MESSAGE_BOX_CAPTION": "Restore Factory Content",
    "IMPORT_DRIVE_STATUS_TEXT": "Restoring factory content...",
    # Actionable errors.
    "HARDWARE_NOT_FOUND_ON_STARTUP_MESSAGEBOX_TEXT":
        "The Strike module was not found. Check that it is powered on and connected by USB, that the "
        "'Alesis Strike' MIDI port appears in Audio MIDI Setup, and that its drive is mounted under /Volumes. "
        "Run tools/strike-probe.swift for a detailed check.",
    "HARDWARE_NOT_FOUND_ON_STARTUP_MESSAGEBOX_CAPTION": "Module Not Found",
    "DEVICE_DISCONNECTED_MESSAGEBOX_TEXT":
        "The module was disconnected, so the file browsers are unavailable. Reconnect the module, or save your work to a backup location.",
    "LABEL_GET_PRESET_FAILED_FW_COMPATIBILITY_ERROR_MSGBOX_TEXT":
        "The firmware on your Strike module needs to be updated before this preset can be retrieved.",
    "LABEL_SEND_PRESET_FAILED_FW_COMPATIBILITY_ERROR_MSGBOX_TEXT":
        "The firmware on your Strike module is not compatible with this preset.",
    "LABEL_GET_PRESET_FAILED_MIDI_ERROR_MSGBOX_TEXT":
        "Error retrieving the preset from the module. Check the USB connection and try again.",
    # The original used one message for five different failures.
    "SETTINGS_FILE_LOAD_NEWER_MESSAGE": "This preset was saved by a newer editor and can't be opened here.",
    "SETTINGS_FILE_LOAD_OLDER_MESSAGE": "This preset was saved by an older editor and can't be converted.",
    "SETTINGS_FILE_LOAD_WRONG_DEVICE_MESSAGE": "This preset file is for a different device.",
    "SETTINGS_FILE_TRANSLATION_FAILURE_MESSAGE": "This preset file could not be converted to the current format.",
    "SETTINGS_FILE_LOAD_CORRUPT_MESSAGE": "This preset file is damaged or incomplete.",
    # The Alesis user guide page is gone.
    "URL_USER_GUIDE": args.url,
}

# Hotkey rebinding: the GHK entry for plain Save points at a command the app never registers.
RENAME_IDS = {"GHK.NID_MENU_FILE_SAVE_PRESET_TO_FILE": "GHK.NID_MENU_FILE_SAVEAS_PRESET_TO_FILE"}

raw = open(args.path, "rb").read()
if raw[:2] != b"\xff\xfe":
    sys.exit("expected a UTF-16LE StringTables.xml with BOM")
text = raw.decode("utf-16")

for old, new in REPLACEMENTS:
    print(f"{text.count(old):3d}x replace {old[:50]!r}")
    text = text.replace(old, new)

for sid, value in BY_ID.items():
    pattern = re.compile(r'(<String ID="' + re.escape(sid) + r'"><Locale LCID="0x0009">)(.*?)(</Locale>)', re.S)
    matches = pattern.findall(text)
    if len(matches) != 1:
        sys.exit(f"String ID {sid}: expected 1 match, found {len(matches)}")
    old = matches[0][1]
    for token in ("%s", "%d", "|"):
        if old.count(token) != value.count(token):
            sys.exit(f"String ID {sid}: '{token}' count changed ({old.count(token)} -> {value.count(token)})")
    text = pattern.sub(lambda m: m.group(1) + value + m.group(3), text)
    print(f"  1x set     {sid}")

for old_id, new_id in RENAME_IDS.items():
    if text.count(f'ID="{new_id}"') != 0 or text.count(f'ID="{old_id}"') != 1:
        sys.exit(f"hotkey rebinding {old_id}: unexpected state")
    text = text.replace(f'ID="{old_id}"', f'ID="{new_id}"')
    print(f"  1x rename  {old_id} -> {new_id}")

leftovers = re.findall(r"[^<>]{0,40}Ales+is[^<>]{0,40}", text)
allowed = [l for l in leftovers if "'Alesis Strike' MIDI port" in l]
if len(leftovers) != len(allowed):
    sys.exit(f"unexpected Alesis mentions left: {leftovers}")

ET.fromstring(text.encode("utf-8").replace(b'encoding="UTF-16"', b'encoding="UTF-8"', 1))  # must stay valid XML
open(args.path, "wb").write(b"\xff\xfe" + text.encode("utf-16-le"))
print("StringTables.xml OK")
