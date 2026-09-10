# Changelog

## 1.1.0

Merges back the features the library's own fork inside ByteMons grew while it
was being used to ship a game. Everything here is additive - 1.0.0 code keeps
working unchanged.

- **Sessions nest.** `GfxTerm.session` is reference counted, so opening one
  inside another reuses the terminal already up instead of entering graphics
  mode a second time. Without this, an inner `leave()` drops the outer session
  to mode 0 while it still expects pixels. It means a screen can open its own
  session and still work when the whole program already runs inside one.
  `GfxTerm.inSession()` and `GfxTerm.sessionTerms()` expose the running pair.
- **`GfxTerm.frame(body)`** - run a body with the display frozen so it presents
  at once. `window.lua` walks its buffer line by line, and in graphics mode each
  line is its own `drawPixels`, so an unfrozen redraw is visibly painted from the
  top down. Depth counted, and it always unfreezes, including when the body
  throws - a terminal left frozen is indistinguishable from a hang.
- **Mouse folding.** In graphics mode CraftOS-PC reports mouse events in PIXELS,
  which silently breaks every hit test written against the text terminal.
  `GfxTerm.session` now folds them back to cells at the event source;
  `GfxTerm.foldMouse` controls it directly.
- **`GfxTerm.onRepaint(fn)`** - a hook run after every window redraw, inside the
  freeze. A redraw wipes anything drawn *over* the window (pixel widgets, sprite
  overlays), and this is the one correct moment to put them back. Returns an
  unregister function.
- **`GfxTerm.refreshFont()`** - `new()` snapshots the font and caches rasterised
  glyphs, so `setFont` alone changes nothing on a terminal that already exists,
  and a program building its terminal once at startup sees no change at all.
  This re-snapshots every live terminal through a weak-keyed registry.
- **`GfxTerm.clearMask()`** - drops the running session's text mask. A mask set
  by one screen otherwise outlives it, leaving the protected rect burned on
  screen and every later screen forbidden from drawing text there.
- **`GfxTerm.modeSettled()`** - `setGraphicsMode(2)`'s readback LAGS, answering
  false until events have been pumped. Verifying the switch immediately is what
  makes a good terminal look like a failed one, so this is the honest check to
  use later rather than at startup.

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
