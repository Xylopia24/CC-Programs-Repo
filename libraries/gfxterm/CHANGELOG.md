# Changelog

## 1.0.0

First public release of this rewrite, extracted from the ByteMons project where
it had been in daily use rendering a Pokemon-style RPG's world and UI together.

`gfxterm` originated with MCJack123 in December 2020; see CREDITS.md for what
this version changed and why.

Changes made while generalising it:

- **The grid is no longer hardcoded.** It was fixed at 80x25 / 480x225; it is
  now derived from `term.getSize()` at creation, so any terminal size works.
- **`GfxTerm.protect` / `GfxTerm.window`**, for the `term.redirect` leak that
  silently breaks `clear()` inside a window over a graphics-mode terminal.
- **`gfx.resize()`** - terminal resize support. The grid used to be captured at
  creation and never revisited, so resizing the window mid-session left writes
  clipped to the old bounds. The shadow buffer is carried across.
- **`setFont` takes metrics**: any glyph size, not just 6x9. The decoder used to
  hardcode nine rows of six bits, so "supply your own font" really meant "supply
  your own 6x9 typeface". Rows are now `ceil(w/8)` bytes, big-endian, with the
  glyph right-aligned - which is what the built-in 6x9 font already was, so it
  decodes unchanged.
- **A real cursor**, with the shadow buffer needed to erase it. A game never
  needs a caret; a shell is unusable without one. `blinkCursor()` and
  `refreshCursor()` are new, and moving the caret restores the cell underneath
  exactly.
- **`scroll()` keeps the shadow buffer in step**, so a scrolled terminal can
  still repaint any cell.
- **The font is embedded**, rather than required from a host project's tree, and
  can be replaced with `setFont`.
- `table.unpack` / `unpack` fallback, so it runs on both Lua flavours CC ships.
- Documentation rewritten for people who did not write it.
