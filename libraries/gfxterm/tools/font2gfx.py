#!/usr/bin/env python3
"""Convert an OpenType/TrueType font into a gfxterm bitmap font.

    font2gfx.py MyFont.otf --size 12x18 --out myfont.lua
    font2gfx.py MyFont.otf --size 12x18 --preview sheet.png --ascii 65

Then in ComputerCraft:

    local GfxTerm = require("gfxterm")
    local f = dofile("myfont.lua")
    GfxTerm.setFont(f.data, f.w, f.h)     -- BEFORE creating any terminal

--------------------------------------------------------------------------
LICENSING - READ THIS

Converting a font produces a derivative of it. Many font licences forbid
exactly that, and many more forbid redistributing the result. This script
never ships a converted font, and neither should you unless the licence
clearly allows it - OFL and CC0 fonts do, most commercial and "personal use"
fonts do not, even when they happily permit "embedding a rasterized
representation" (a Lua table of bitmaps is editable text, not a locked-down
document).

Convert fonts you have the right to convert. The output is yours to keep;
whether it is yours to publish is between you and the font's licence.

--------------------------------------------------------------------------
WHAT THIS HAS TO GET RIGHT

ComputerCraft's 256 slots are not ASCII, and two ranges must NOT come from
the font:

  0-31     CP437 pictographs - smileys, card suits, arrows. Mapped through to
           their Unicode equivalents where the font has them.
  9,10,13  tab / newline / carriage return. BLANK in CC's own font, because
           they are real control characters. Always blanked here too.
  32-126   ASCII, straight through.
  128-159  THE SEXTANT BLOCKS. A 2x3 grid of filled quadrant blocks - this is
           what pixelbox and every piece of sub-cell art in CC is built on.
           No text font contains them. They are SYNTHESISED, at whatever cell
           size you asked for. Taking these from a font would silently break
           every pixelbox program on the system.
  160-255  Latin-1, straight through.

Requires Pillow:  python -m pip install pillow
"""
import argparse
import pathlib
import sys

try:
    from PIL import Image, ImageDraw, ImageFont
except ImportError:
    sys.exit("this needs Pillow:  python -m pip install pillow")

# ── the ComputerCraft charset ───────────────────────────────────────────────
# slot -> unicode codepoint. Anything absent is left blank.
CONTROL = {
    1: 0x263A, 2: 0x263B, 3: 0x2665, 4: 0x2666, 5: 0x2663, 6: 0x2660,
    7: 0x2022, 8: 0x25D8, 11: 0x2642, 12: 0x2640, 14: 0x266B, 15: 0x263C,
    16: 0x25BA, 17: 0x25C4, 18: 0x2195, 19: 0x203C, 20: 0x00B6, 21: 0x00A7,
    22: 0x25AC, 23: 0x21A8, 24: 0x2191, 25: 0x2193, 26: 0x2192, 27: 0x2190,
    28: 0x221F, 29: 0x2194, 30: 0x25B2, 31: 0x25BC, 127: 0x2302,
}
# CC blanks these: they are used as real control characters.
ALWAYS_BLANK = {0, 9, 10, 13}
BLOCK_LO, BLOCK_HI = 128, 159        # synthesised, never taken from the font

# Caps, descenders, ascenders and digits - enough to bound the real ink.
FIT_SAMPLE = "AXHMNWbdfghjpqy0123456789"


def slot_codepoint(slot):
    """Unicode codepoint a slot should be rendered from, or None."""
    if slot in ALWAYS_BLANK or BLOCK_LO <= slot <= BLOCK_HI:
        return None
    if slot in CONTROL:
        return CONTROL[slot]
    if 32 <= slot <= 126:
        return slot
    if 160 <= slot <= 255:
        return slot                  # Latin-1 is codepoint-identical
    return None


def sextant(slot, w, h):
    """One of CC's 32 block glyphs, drawn to fit a w x h cell.

    The cell is a 2x3 grid of blocks; the low bits of (slot - 128) select which
    are filled. Regenerating these at the target size is why a converted font
    does not break pixelbox art."""
    n = slot - BLOCK_LO
    grid = [[False] * 2 for _ in range(3)]
    # Only FIVE sub-cells. CC's 128-159 range uses bits 0-4 for top-left,
    # top-right, mid-left, mid-right and bottom-left; the bottom-right is never
    # set in the glyph - the sixth bit is an inversion flag CC applies at the
    # colour level. Verified against the bundled 6x9 font: filling it makes
    # slot 159 wrong, and nothing else.
    for i in range(5):
        if n & (1 << i):
            grid[i // 2][i % 2] = True

    xs = [0, w // 2, w]
    ys = [0, h // 3, (2 * h) // 3, h]
    rows = [[0] * w for _ in range(h)]
    for gy in range(3):
        for gx in range(2):
            if not grid[gy][gx]:
                continue
            for y in range(ys[gy], ys[gy + 1]):
                for x in range(xs[gx], xs[gx + 1]):
                    rows[y][x] = 1
    return rows


def ink_box(face, chars):
    """Union ink box of `chars`, relative to the left-baseline origin."""
    x0 = y0 = 10 ** 6
    x1 = y1 = -10 ** 6
    for ch in chars:
        try:
            bb = face.getbbox(ch, anchor="ls")
        except Exception:
            continue
        if not bb or bb[2] <= bb[0] or bb[3] <= bb[1]:
            continue
        x0, y0 = min(x0, bb[0]), min(y0, bb[1])
        x1, y1 = max(x1, bb[2]), max(y1, bb[3])
    if x1 <= x0 or y1 <= y0:
        return None
    return x0, y0, x1, y1


def pick_pt(path, w, h, index, tight=False):
    """Largest point size whose INK fits the cell.

    Fitting ascent+descent instead wastes the cell on any font with a generous
    line gap - it scaled the FireRed font's 'A' down to 3x3 pixels of a 6x9
    cell. Leaves a 1px gutter on each axis unless --tight, matching CC's own
    font (6x9 cells with the glyph occupying 5x7)."""
    fit_w = w if tight or w < 3 else w - 1
    fit_h = h if tight or h < 3 else h - 1
    best = None
    for pt in range(1, 8 * h + 8):
        try:
            f = ImageFont.truetype(str(path), pt, index=index)
        except Exception:
            break
        box = ink_box(f, FIT_SAMPLE)
        if box is None:
            continue
        if box[2] - box[0] <= fit_w and box[3] - box[1] <= fit_h:
            best = (pt, f, box)
        elif best is not None:
            break
    if best is None:
        sys.exit("no point size fits %dx%d - the cell is too small for this font" % (w, h))
    return best


def render(face, cp, w, h, baseline, dx, threshold):
    """Rasterise one codepoint into a w x h bitmap of 0/1, or None if absent."""
    if cp != 32 and face.getmask(chr(cp)).getbbox() is None:
        return None                                  # font has no ink for it
    img = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(img)
    try:
        d.text((dx, baseline), chr(cp), font=face, fill=255, anchor="ls")
    except Exception:
        return None
    px = img.load()
    return [[1 if px[x, y] >= threshold else 0 for x in range(w)] for y in range(h)]


def pack(rows, w, h):
    """Rows of 0/1 -> bytes, big-endian per row, glyph right-aligned."""
    bpr = (w + 7) // 8
    out = bytearray()
    for y in range(h):
        v = 0
        for x in range(w):
            v = (v << 1) | rows[y][x]
        for k in range(bpr - 1, -1, -1):
            out.append((v >> (8 * k)) & 0xFF)
    return bytes(out)


def lua_escape(data):
    return "".join("\\%d" % b for b in data)


def lua_string(s):
    return '"' + s.replace("\\", "\\\\").replace('"', '\\"') + '"'


def ascii_art(rows):
    return "\n".join("".join("#" if v else "." for v in r) for r in rows)


def main():
    ap = argparse.ArgumentParser(
        description="Convert an OTF/TTF font to a gfxterm bitmap font.",
        epilog="Only convert fonts whose licence permits it. See the header.")
    ap.add_argument("font", type=pathlib.Path)
    ap.add_argument("--size", default="6x9",
                    help="cell size WxH (default 6x9, CC's own metrics). Vector "
                         "faces are usually mush below about 10x14.")
    ap.add_argument("--out", type=pathlib.Path, help="write a Lua module here")
    ap.add_argument("--pt", type=int, help="force a point size instead of fitting one")
    ap.add_argument("--threshold", type=int, default=128,
                    help="0-255; ink below this is dropped (default 128). The knob "
                         "that decides whether thin stems survive.")
    ap.add_argument("--offset", default="0,0", help="nudge X,Y in pixels")
    ap.add_argument("--index", type=int, default=0, help="face index in a collection")
    ap.add_argument("--preview", type=pathlib.Path, help="write a 16x16 sheet PNG")
    ap.add_argument("--scale", type=int, default=4, help="preview magnification")
    ap.add_argument("--ascii", type=int, action="append", default=[],
                    help="dump one slot as ASCII art (repeatable)")
    ap.add_argument("--tight", action="store_true",
                    help="fill the whole cell; by default a 1px gutter is left on "
                         "each axis, as CC's own 6x9 font does")
    ap.add_argument("--no-blocks", action="store_true",
                    help="do NOT synthesise 128-159. Breaks pixelbox. Don't.")
    a = ap.parse_args()

    try:
        w, h = (int(v) for v in a.size.lower().split("x"))
    except ValueError:
        sys.exit("--size must look like 12x18")
    if not (1 <= w <= 32):
        sys.exit("width must be 1-32 (gfxterm packs a row into at most 4 bytes)")
    try:
        ox, oy = (int(v) for v in a.offset.split(","))
    except ValueError:
        sys.exit("--offset must look like 0,-1")

    if a.pt:
        face = ImageFont.truetype(str(a.font), a.pt, index=a.index)
        pt = a.pt
        box = ink_box(face, FIT_SAMPLE) or (0, -h, w, 0)
    else:
        pt, face, box = pick_pt(a.font, w, h, a.index, a.tight)

    # Centre the ink box in the cell. Its y is relative to the baseline and
    # negative above it, so the baseline lands at (top padding - box top).
    ix0, iy0, ix1, iy1 = box
    iw, ih = ix1 - ix0, iy1 - iy0
    baseline = (h - ih) // 2 - iy0 + oy
    dx = (w - iw) // 2 - ix0 + ox

    try:
        name = " ".join(str(n) for n in face.getname())
    except Exception:
        name = a.font.stem

    glyphs, have, missing, synth = [], 0, [], 0
    for slot in range(256):
        rows = None
        if BLOCK_LO <= slot <= BLOCK_HI and not a.no_blocks:
            rows = sextant(slot, w, h)
            synth += 1
        else:
            cp = slot_codepoint(slot)
            if cp is not None:
                rows = render(face, cp, w, h, baseline, dx, a.threshold)
                if rows is None:
                    missing.append(slot)
                else:
                    have += 1
        glyphs.append(rows or [[0] * w for _ in range(h)])

    print("font:        %s" % name)
    print("cell:        %dx%d   point size %d   baseline row %d" % (w, h, pt, baseline))
    print("ink:         %dx%d of the cell%s"
          % (iw, ih, "" if a.tight else "   (1px gutter reserved)"))
    print("rendered:    %d glyphs from the font" % have)
    print("synthesised: %d block glyphs (128-159)" % synth)
    if missing:
        show = ", ".join(str(s) for s in missing[:24])
        print("blank:       %d slots the font had no glyph for: %s%s"
              % (len(missing), show, " ..." if len(missing) > 24 else ""))

    for slot in a.ascii:
        print("\n-- slot %d --" % slot)
        print(ascii_art(glyphs[slot]))

    if a.preview:
        s = a.scale
        sheet = Image.new("RGB", (16 * (w * s + 2) + 2, 16 * (h * s + 2) + 2), (24, 24, 28))
        p = sheet.load()
        for slot in range(256):
            bx = 2 + (slot % 16) * (w * s + 2)
            by = 2 + (slot // 16) * (h * s + 2)
            for y in range(h):
                for x in range(w):
                    c = (235, 235, 235) if glyphs[slot][y][x] else (44, 44, 52)
                    for sy in range(s):
                        for sx in range(s):
                            p[bx + x * s + sx, by + y * s + sy] = c
        sheet.save(a.preview)
        print("preview:     %s" % a.preview)

    if a.out:
        data = b"".join(pack(g, w, h) for g in glyphs)
        assert len(data) == 256 * h * ((w + 7) // 8)
        a.out.write_text(
            "-- gfxterm bitmap font, generated by tools/font2gfx.py\n"
            "-- source: %s\n"
            "-- cell: %dx%d\n"
            "--\n"
            "-- NOT redistributable unless the source font's licence says so.\n"
            "--\n"
            "--   local f = dofile(\"%s\")\n"
            "--   GfxTerm.setFont(f.data, f.w, f.h)\n"
            "return {\n"
            "    name = %s,\n"
            "    w = %d, h = %d,\n"
            "    data = \"%s\",\n"
            "}\n" % (name, w, h, a.out.name, lua_string(name), w, h, lua_escape(data)),
            encoding="utf-8", newline="\n")
        print("wrote:       %s  (%d bytes of glyph data)" % (a.out, len(data)))


if __name__ == "__main__":
    main()
