#!/usr/bin/env python3
"""Stitch the delay-style shots into one contact sheet.

Usage: python3 tools/delay-montage.py [out.png] shot1.png shot2.png ...

Each shot is cropped from its Cancel row down (detected by the blue Cancel
text), trimmed of trailing empty sheet background, scaled to 414 wide, and
tiled three across. Six inputs give a 3x2 sheet.
"""
import sys
from PIL import Image, ImageStat


def sheet_top(im):
    """First row of the sheet: the row holding the blue Cancel text."""
    w, h = im.size
    px = im.load()
    for y in range(int(h * 0.45), h):
        hits = 0
        for x in range(30, 180, 3):
            r, g, b = px[x, y]
            if b > 130 and b - r > 55 and b - g > 30:
                hits += 1
        if hits >= 6:
            return max(0, y - 140)
    return int(h * 0.5)


def trim_bottom(crop):
    """Drop trailing rows that are just the sheet background."""
    g = crop.convert("L")
    w, h = g.size
    bg = ImageStat.Stat(g.crop((0, h - 30, w, h - 10))).mean[0]
    for y in range(h - 1, 0, -4):
        st = ImageStat.Stat(g.crop((0, y - 2, w, y)))
        if st.stddev[0] > 2.0 or abs(st.mean[0] - bg) > 2.0:
            return crop.crop((0, 0, w, min(h, y + 6)))
    return crop


def main():
    args = sys.argv[1:]
    out = "contact-sheet.png"
    if args and args[0].endswith(".png") and not args[0].startswith("shot"):
        out, args = args[0], args[1:]
    if not args:
        print(__doc__)
        return 1

    cells, bgs = [], []
    for path in args:
        im = Image.open(path).convert("RGB")
        w, h = im.size
        crop = trim_bottom(im.crop((0, sheet_top(im), w, h)))
        crop = crop.resize((414, int(crop.height * 414 / w)), Image.LANCZOS)
        cells.append(crop)
        bgs.append(tuple(int(v) for v in ImageStat.Stat(crop.crop((5, crop.height - 8, 25, crop.height - 3))).mean))

    cols = 3 if len(cells) > 4 else len(cells)
    rows = (len(cells) + cols - 1) // cols
    height = max(c.height for c in cells)
    pad = 14
    sheet = Image.new("RGB", (cols * 414 + (cols + 1) * pad, rows * height + (rows + 1) * pad), (10, 10, 12))
    for i, cell in enumerate(cells):
        row, col = divmod(i, cols)
        tile = Image.new("RGB", (414, height), bgs[i])
        tile.paste(cell, (0, 0))
        sheet.paste(tile, (pad + col * (414 + pad), pad + row * (height + pad)))
    sheet.save(out)
    print(out, sheet.size)
    return 0


if __name__ == "__main__":
    sys.exit(main())
