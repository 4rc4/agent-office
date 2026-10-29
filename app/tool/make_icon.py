#!/usr/bin/env python3
"""Draws Claude's beanie head (rows copied from lib/scene/sprites.dart) at
2x into a 32x32 icon and writes it as assets/icons/tray_icon.ico (the tray,
loaded as a Flutter asset) and windows/runner/resources/app_icon.ico (the
executable and window icon). Run from app/: python3 tool/make_icon.py
(needs Pillow). Regenerate only when the sprite's head changes."""
from pathlib import Path

from PIL import Image

HEAD = [
    "..OOOOOOOO..", ".OHHHhhhhhO.", "OHHHhhhhhhhO", "OHHhhhhhhhhO",
    "OHhhhhhhhhhO", "OhdddsddddhO", "khLssssssShk", "kLssssssssSk",
    "kLssssssssSk", "ksssssssssSk", "kssssmmssSSk", ".kssssssSSk.",
    "..kkkkkkkk..",
]
BEANIE = [
    ".qbbbbbbbbq.", "qBBBbbbbbbbq", "qBBBbbbbbbbq", "qBBbbbbbbbbq",
    "qDbDbDbDbDbq", "qDDDDDDDDDDq",
]
EARS = ["..q......q..", ".qnq....qnq.", "qbnnq..qnnbq"]
BRIM = "qb........bq"
EYES = {(7, 9): "E", (7, 10): "e", (7, 13): "E", (7, 14): "e",
        (8, 9): "e", (8, 10): "e", (8, 13): "e", (8, 14): "e"}
COLORS = {
    "O": 0x2E1810, "H": 0x8A5A3C, "h": 0x6B3F2A, "d": 0x4A2A1C,
    "k": 0x8E5C3E, "L": 0xFFE8CC, "s": 0xF7D2A8, "S": 0xDBA878,
    "q": 0x7E3E18, "B": 0xF7AA60, "b": 0xE8873A, "D": 0xBB612A,
    "e": 0x2B2127, "E": 0xFFF9E8, "m": 0x8E5C3E, "n": 0xF2A9A2,
}


def rows():
    out = [list(r) for r in EARS]
    for i, head in enumerate(HEAD):
        row = list(head)
        if i < len(BEANIE):
            row = list(BEANIE[i])
        if i == 6:
            row = [b if b != "." else h for b, h in zip(BRIM, row)]
        out.append(row)
    for (r, c), ch in EYES.items():
        out[r + len(EARS)][c - 6] = ch
    return out


def main():
    grid = rows()
    image = Image.new("RGBA", (32, 32), (0, 0, 0, 0))
    for y, row in enumerate(grid):
        for x, ch in enumerate(row):
            rgb = COLORS.get(ch)
            if rgb is None:
                continue
            color = (rgb >> 16 & 0xFF, rgb >> 8 & 0xFF, rgb & 0xFF, 255)
            for dy in range(2):
                for dx in range(2):
                    image.putpixel((4 + x * 2 + dx, y * 2 + dy), color)
    root = Path(__file__).resolve().parent.parent
    for target in [root / "assets/icons/tray_icon.ico",
                   root / "windows/runner/resources/app_icon.ico"]:
        target.parent.mkdir(parents=True, exist_ok=True)
        image.save(target, format="ICO", sizes=[(32, 32)])
        print("wrote", target)


if __name__ == "__main__":
    main()
