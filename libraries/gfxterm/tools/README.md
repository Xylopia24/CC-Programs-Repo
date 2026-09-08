# font2gfx

Convert an OpenType/TrueType font into a gfxterm bitmap font.

```
python font2gfx.py MyFont.otf --size 8x12 --out myfont.lua --preview sheet.png
```

```lua
local GfxTerm = require("gfxterm")
local f = dofile("myfont.lua")
GfxTerm.setFont(f.data, f.w, f.h)     -- BEFORE creating any terminal
```

Needs Pillow: `python -m pip install pillow`

---

## Licensing — read this before you convert anything

**Converting a font produces a derivative of it.** Plenty of licences forbid
exactly that, and more forbid redistributing the result.

This repository ships **no converted fonts** and you probably shouldn't either.
Watch for a licence that permits "embedding a rasterized representation" but only
"in a secure format that permits only the viewing and printing but not the
editing of the text" — a Lua table of bitmaps is *editable text*, so that clause
does **not** cover it.

Safe to publish: **OFL** and **CC0** fonts, which explicitly permit modification
and redistribution. Good pixel-grid choices are Departure Mono, Pixel Operator,
Cozette and GNU Unifont.

Convert fonts you have the right to convert. The output is yours to keep;
whether it's yours to publish is between you and the font's licence.

---

## Picking a size

The single biggest factor in whether the result is readable.

| Cell | Terminal at 480x225 | Verdict |
|---|---|---|
| 6x9 | 80x25 | CC's own metrics. Most vector faces turn to mush; needs threshold tuning, and some fonts simply can't do it. |
| 8x12 | 60x18 | The sweet spot for most pixel fonts. |
| 12x18 | 40x12 | Roomy and crisp, including for scripts 6x9 can't express — but half the terminal. |

You are trading screen space for legibility, and there is no way around it: a
6x9 cell holds about 5x7 usable pixels.

## Tuning

**`--threshold`** is the knob that matters. Rendering is greyscale and has to be
cut to 1-bit somewhere; too high and thin stems vanish, too low and everything
blobs together. Real example, the same font at 6x9:

```
--threshold 128 (default)     --threshold 80
    ......                        ......
    #.....                        ###...
    #.....                        #..#..
    #.#...                        ####..
    #.....                        #.##..
    #.....                        #..#..
```

Same glyph. One is unusable, the other is an 'A'. **Always look at
`--preview` or `--ascii` before you commit to a font.**

Other knobs:

- `--pt N` — force a point size instead of fitting one.
- `--offset X,Y` — nudge the baseline when a font sits high or low.
- `--tight` — use the whole cell. By default a 1px gutter is left on each axis,
  matching CC's own font (6x9 cells with a 5x7 glyph), so adjacent characters
  don't touch.
- `--index N` — pick a face out of a collection.
- `--ascii N` — dump one slot as ASCII art. Repeatable.

## What it does with the charset

CC's 256 slots are not ASCII, and getting this wrong breaks things silently:

| Slots | Handling |
|---|---|
| 0–31 | CP437 pictographs (smileys, card suits, arrows), mapped to their Unicode equivalents. Left blank where the font has none. |
| 9, 10, 13 | Always blank — tab, newline and carriage return are real control characters, and CC blanks them too. |
| 32–126 | ASCII, straight through. |
| **128–159** | **The sextant blocks — SYNTHESISED, never taken from the font.** |
| 160–255 | Latin-1, straight through. |

Those 32 block glyphs are a 2×3 grid of filled sub-cells, and they are what
`pixelbox` and every piece of sub-cell art in ComputerCraft is built on. **No
text font contains them.** A converter that took them from the font would
silently break every pixelbox program on the system, so they're regenerated at
whatever cell size you asked for.

They're verified against the real thing: generated at 6x9, all 32 match CC's
own font byte for byte. (Only five sub-cells are ever set — the sixth bit is an
inversion flag CC applies at the colour level, not something in the glyph.)

`--no-blocks` exists to disable this. Don't use it.

## Output

A Lua module:

```lua
return {
    name = "Some Font Regular",
    w = 8, h = 12,
    data = "\0\0\0...",      -- 256 * h * ceil(w/8) bytes
}
```

Each glyph row is a big-endian integer in `ceil(w/8)` bytes with the glyph
right-aligned; pixel *x* is bit `(w-1-x)`. That's the same layout the built-in
6x9 font uses — see the library README.
