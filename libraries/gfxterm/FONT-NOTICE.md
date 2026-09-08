# Font notice

`gfxterm.lua` embeds the **ComputerCraft terminal font** as a 256 × 9 byte
bitmap table.

It is included so that text drawn in graphics mode looks *identical* to text
drawn by the real terminal — which is the entire point of the library. Any
other font would make the illusion fail.

**This font is not my work and no ownership over it is claimed.** It is the
standard ComputerCraft terminal typeface, originating in
[CC:Tweaked](https://github.com/cc-tweaked/CC-Tweaked)'s asset
`assets/computercraft/textures/gui/term_font.png`, extracted to bitmasks. All
rights in it remain with its authors, and it is used here for interoperability
with the platform this library exists to extend.

If you would rather not ship it, `GfxTerm.setFont(data)` replaces it at runtime
with any 256 × 9 byte table in the same layout:

> glyph *g* occupies bytes `g*9+1 .. g*9+9`, one bitmask per row,
> bit 5 (32) = leftmost pixel of a 6-pixel-wide glyph.

The MIT licence at the repository root covers the library code, not this font.

If you are a CC:Tweaked maintainer and would prefer this removed, please open an
issue — it will be taken out without argument.
