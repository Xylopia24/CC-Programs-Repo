# Credits and prior art

## gfxterm was MCJack123's idea first

The original `gfxterm.lua` was written by **MCJack123** (JackMacWindows) in
December 2020:

<https://gist.github.com/MCJack123/f6819e41a60402b8a73403542bb23820>

The name, and the whole idea — a `term` object you redirect to that renders
ComputerCraft text into CraftOS-PC's graphics mode so existing text UI keeps
working — are theirs. That is not a small contribution to build on; it is the
entire concept.

MCJack123 also wrote **CraftOS-PC itself**, including the graphics mode API this
library depends on. Without either, none of this exists.

## What is different here

This version was rewritten while building a pixel-rendered RPG, where the
library had to survive daily use. The differences are substantial enough that
almost no original code remains, but it is a descendant, not an independent
invention:

| | MCJack123's original | This version |
|---|---|---|
| Font | BDF font files, loaded at runtime via a separate `readBDFFont` module | The real ComputerCraft terminal font, embedded, so text is pixel-identical to text mode and there are no external files |
| Rendering | Per character | Contiguous runs batched into one `drawPixels`, with a glyph cache keyed on (char, fg, bg) |
| Grid | Derived from the font metrics | Derived from `term.getSize()`; note `getSize(2)` reports cells, not pixels |
| Mode switching | Caller's responsibility | `GfxTerm.session` restores mode, palette and redirect on every exit path, including errors and terminate |
| Crashes | "render crashes are fatal and will crash the computer" | An error unwinds through `session` back to a working text terminal |
| Cursor | Blink handled with timer events | Caret backed by a shadow buffer, so moving it restores the covered cell exactly |
| Masking | — | `setMask` protects a rectangle from text, so a pixel viewport is not overpainted by window redraws |
| Palette | Delegated to native | CC colour values converted to mode-2 indices, so callers keep using `colours.*` |

## Licensing

The original gist carries no licence. This rewrite is published under MIT with
MCJack123's knowledge and encouragement, given directly in the ComputerCraft
Discord.

If you are MCJack123 and would like the attribution changed, the licensing
revisited, or this taken down, please open an issue — it will be honoured
without argument.

## Font

The embedded font is the ComputerCraft terminal font from CC:Tweaked. It is not
my work and no ownership is claimed — see [FONT-NOTICE.md](FONT-NOTICE.md).
