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

COLORIZER = re.compile(r'(<Colorizer\b[^>]*\bColor=")(0x[0-9A-Fa-f]{8})(")')


def normalize(color):
    """'0xff0093d0' / '0XFF0093D0' -> '0xFF0093D0'."""
    return "0x" + color[2:].upper()


def apply_theme(text, theme):
    """Returns (new text, {original colour: replacements made})."""
    mapping = {normalize(k): v for k, v in theme.items()}
    counts = dict.fromkeys(mapping, 0)

    def recolor(m):
        color = normalize(m.group(2))
        if color in mapping:
            counts[color] += 1
            return m.group(1) + mapping[color] + m.group(3)
        return m.group(0)

    return COLORIZER.sub(recolor, text), counts


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("path")
    parser.add_argument("--theme", required=True, choices=sorted(THEMES))
    args = parser.parse_args(argv)

    theme = THEMES[args.theme]
    with open(args.path, encoding="utf-8") as f:
        text, counts = apply_theme(f.read(), theme)
    targets = {normalize(k): v for k, v in theme.items()}
    for color, n in counts.items():
        print(f"{n:3d}x {color} -> {targets[color]}")
    if not any(counts.values()):
        print("theme matched no colours", file=sys.stderr)
        return 1
    ET.fromstring(text.encode("utf-8"))
    with open(args.path, "w", encoding="utf-8") as f:
        f.write(text)
    print(f"Skins.xml themed: {args.theme}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
