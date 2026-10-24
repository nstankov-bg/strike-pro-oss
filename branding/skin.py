"""Optional colour theme for the editor's Skins.xml (only <Colorizer Color="..."> values change).

Themes map the original ARGB colours to new ones. PNG skin art is not recoloured, so check the
result visually and adjust the map; this is meant for iterating, not a one-shot.

Usage: python3 -I skin.py <Skins.xml> --theme graphite
"""
import argparse
import re
import sys
import xml.etree.ElementTree as ET

THEMES = {
    "graphite": {
        "0xFF0093D0": "0xFFFAAF41",  # Alesis blue -> amber
        "0xFFECE9D8": "0xFF1A212A",  # XP beige    -> graphite
    },
}

parser = argparse.ArgumentParser()
parser.add_argument("path")
parser.add_argument("--theme", required=True, choices=sorted(THEMES))
args = parser.parse_args()

text = open(args.path, encoding="utf-8").read()
mapping = {"0x" + k[2:].upper(): v for k, v in THEMES[args.theme].items()}
counts = dict.fromkeys(mapping, 0)


def recolor(m):
    color = "0x" + m.group(2)[2:].upper()
    if color in mapping:
        counts[color] += 1
        return m.group(1) + mapping[color] + m.group(3)
    return m.group(0)


text = re.sub(r'(<Colorizer\b[^>]*\bColor=")(0x[0-9A-Fa-f]{8})(")', recolor, text)
for color, n in counts.items():
    print(f"{n:3d}x {color} -> {mapping[color]}")
if not any(counts.values()):
    sys.exit("theme matched no colours")
ET.fromstring(text.encode("utf-8"))
open(args.path, "w", encoding="utf-8").write(text)
print(f"Skins.xml themed: {args.theme}")
