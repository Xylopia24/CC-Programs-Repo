# Changelog

## 1.0.0

First public release, extracted from the ByteMons project where it had been in
daily use rendering a Pokemon-style RPG's world and UI together.

Changes made while generalising it:

- **The grid is no longer hardcoded.** It was fixed at 80x25 / 480x225; it is
  now derived from `term.getSize()` at creation, so any terminal size works.
  Note that `getSize(2)` reports CELLS, not pixels, so the pixel surface is
  computed as `cols * 6` by `rows * 9`.
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
