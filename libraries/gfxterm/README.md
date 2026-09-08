# gfxterm

**Draw normal ComputerCraft text while the screen is in graphics mode.**

CraftOS-PC's graphics mode gives you a pixel surface — and hides the terminal's
text completely. The moment you call `term.setGraphicsMode(2)`, every window,
every `term.write`, and every UI library you already have stops appearing.

`gfxterm` is a `term` object you redirect to. It rasterises each write and blit
with the **real ComputerCraft font** and pushes it as pixels, so your existing
text UI keeps working unchanged on top of a pixel-rendered game.

```
wget https://raw.githubusercontent.com/Xylopia24/CC-Programs-Repo/main/libraries/gfxterm/gfxterm.lua
```

One file, no dependencies. The font is embedded.

> **gfxterm was [MCJack123](https://gist.github.com/MCJack123/f6819e41a60402b8a73403542bb23820)'s
> idea first**, and so is CraftOS-PC and the graphics mode API underneath it.
> This is a rewrite of their December 2020 original, published with their
> encouragement — see [CREDITS.md](CREDITS.md) for what changed and why.

---

## Hello, pixels

```lua
local GfxTerm = require("gfxterm")

GfxTerm.session(function(native, gfx)
    -- Graphics mode is on and `term` points at `gfx`. Ordinary text works:
    term.setBackgroundColour(colours.black)
    term.clear()
    term.setCursorPos(2, 2)
    term.setTextColour(colours.yellow)
    term.write("Hello from graphics mode")

    -- And so do windows, and anything built on term:
    local w = window.create(term.current(), 4, 5, 24, 5)
    w.setBackgroundColour(colours.blue)
    w.clear()
    w.write("a real window")

    -- Meanwhile, draw pixels straight to the terminal. Palette indices above
    -- 15 are yours -- the text terminal cannot address them at all:
    native.setPaletteColor(16, 0.9, 0.3, 0.2)
    native.drawPixels(200, 40, 16, 60, 60)

    os.pullEvent("key")
end)
-- Text mode, the palette and the previous redirect are all restored HERE,
-- however the body ended - including on error or Ctrl+T.
```

See [`examples/`](examples/) for runnable versions.

---

## Why bother?

Because it means **you don't rewrite your UI to add pixels.** Build your menus,
inventories and dialogs with the text tools you already have; render the game
world with `drawPixels`; and let the two share a screen.

The reference case is [CraftFX-OS](../../os/craftfx-os/), which runs the entire
CraftOS shell in graphics mode without modifying a single program.

---

## API

### `GfxTerm.session(body) -> ok, err, ran`

The one you want. Enters graphics mode, redirects `term` to a new GfxTerm, runs
`body(native, gfx)`, and restores **everything** afterwards — mode, palette and
redirect — however the body ended.

An uncaught error in graphics mode otherwise strands the user on a black screen
with no shell, so prefer this over calling `enter`/`leave` yourself.

| Return | Meaning |
|---|---|
| `ran == false` | Setup failed; `err` says why. `body` never ran — fall back to a text path. |
| `ok == false` | `body` raised. `err` is its traceback; rethrow with `error(err, 0)` so `"Terminated"` keeps its prefix. |

### `GfxTerm.available([native]) -> boolean`

Whether this terminal can do graphics mode at all. False under vanilla
CC:Tweaked without CC: Graphics. **Check this and degrade gracefully** rather
than crashing on someone's server.

### `GfxTerm.new([native]) -> term object`

A `term` you can redirect to or pass around. The grid is fixed at creation from
the terminal's current size.

### `GfxTerm.enter([native])` / `GfxTerm.leave([native])`

Manual mode switching, if `session` doesn't fit. `enter` carries the current 16
colours across the switch, `leave` puts them back. Pair them, and make sure
`leave` runs on every exit path including errors.

### `GfxTerm.size([native]) -> pixelW, pixelH, cols, rows`

The pixel surface, derived as `cols * 6` by `rows * 9`.

> `getSize(2)` reports the same thing directly — but only once the terminal is
> genuinely in mode 2. Before the switch, and under headless CraftOS-PC (which
> never truly enters mode 2), it answers with the cell size instead. Deriving it
> is correct either way.

### `GfxTerm.protect(target) -> target`

**Call this on any window before redirecting into it.** See the trap below; a
window that skips it silently loses `clear()`.

### `GfxTerm.window(parent, x, y, w, h, visible) -> window`

`window.create` plus `protect`. Use it instead of `window.create` for any window
over a GfxTerm.

### `GfxTerm.setFont(data)` / `GfxTerm.getFont()`

Swap the embedded font. `data` is 256 × 9 bytes: glyph *g* occupies bytes
`g*9+1 .. g*9+9`, one bitmask per row, bit 5 (32) = leftmost pixel of a 6-wide
glyph.

> **You can change the typeface, not the metrics.** Cells are 6 × 9 throughout —
> that is what makes the output identical to a real CC terminal, and it is baked
> into the glyph decoder, not just into a pair of constants. Draw whatever
> glyphs you like inside that box; a font of a different size will not work.
> (MCJack123's original took BDF files at arbitrary sizes — that flexibility was
> traded away deliberately for exactness. See [CREDITS.md](CREDITS.md).)

### `GfxTerm.cellToPx(col, row) -> x, y`

Top-left pixel of a cell. Cells are 1-based, pixels are 0-based.

---

## Instance methods beyond the standard `term` API

### `gfx.setMask(x, y, w, h)` / `gfx.setMask()`

**Protect a rectangle, in cells, from text.** Nothing is ever rasterised inside
it, so a region you paint yourself with `drawPixels` — a game viewport, a chart,
a video — is never overwritten by an unrelated window redraw.

This exists because of a specific bug: a window that repaints its background
each frame paints *over* your pixels, and a frame presented between the two
writes shows a black band. Masking the viewport removes the problem at the
source. Call with no arguments to clear it.

### `gfx.blinkCursor()`

Toggle the caret once. Call it on a ~0.4 s timer for a blinking cursor. The
caret is drawn without this, so it is optional polish rather than a requirement.

### `gfx.refreshCursor()`

Redraw the caret — after you have painted your own pixels over where it sits.

Everything the underlying terminal offers that GfxTerm does not override
(`drawPixels`, `getPixels`, `setFrozen`, `showMouse`, …) passes straight
through, so code holding the redirect can still reach the pixel API.

---

## Things that will bite you

These are not opinions; each one cost real debugging.

- **Every pixel call must go to `term.native()`.** The shell's window wrapper
  ignores `getSize(mode)` and raises a fake `"Invalid colour"` for palette
  indices above 15.
- **In graphics mode the palette functions take a raw index 0–255**, not a CC
  colour value — index 1 is orange, not white. GfxTerm converts for you, so
  through the redirect you keep using `colours.*` normally. Talking to `native`
  directly, you are on your own.
- **Indices 0–15 reset to CC's defaults on entering mode 2**, not to your theme.
  `GfxTerm.enter` copies your palette back across; if you switch modes yourself,
  you must too.
- **`getGraphicsMode()` returns false on purpose.** CraftOS-PC's `window.lua`
  sends `clear()` straight to `term.native()` whenever its parent claims a
  graphics mode, which erases the whole screen instead of the window.
- **`term.redirect` mutates your redirect target.** It copies
  `native.getGraphicsMode` (and `drawPixels`, `setFrozen`, …) onto any target
  that lacks them. A `window` lacks `getGraphicsMode` — so the moment you
  redirect into one it starts reporting the **native** graphics mode, and
  `window.clear()` bails out to `term.native().clear()` without blanking its own
  lines or redrawing. `clear()` inside that window then does nothing: old text
  survives and the next program draws on top of it. Use `GfxTerm.window` (or
  call `GfxTerm.protect` before redirecting) and it cannot happen.
- **Mouse events arrive in PIXELS in graphics mode.** Divide by 6 and 9 to get
  cells.
- **Headless CraftOS-PC cannot really do graphics mode.** The calls succeed and
  nothing persists; a full-screen `drawPixels` can segfault. Test against a mock
  — [`tests/`](tests/) has one that enforces every `drawPixels` contract.
- **An uncaught error in graphics mode leaves a black screen and no shell.**
  Use `session`.

---

## Performance

Text is batched: a contiguous run of characters in the same colours becomes
**one** `drawPixels` call, and glyphs are cached per (char, fg, bg). A full
80×25 repaint is well within a tick.

`scroll()` is the expensive one — it reads back the surface with `getPixels` and
redraws it. Games rarely scroll; shells scroll constantly. If you are writing
something scroll-heavy and it feels slow, that is the place to look.

---

## Requirements

CraftOS-PC, or CC: Graphics in Minecraft. `GfxTerm.available()` tells you.

## Font

The embedded font is the ComputerCraft terminal font from CC:Tweaked, included
so text looks identical to real text mode. It is not my work and no ownership is
claimed — see [FONT-NOTICE.md](FONT-NOTICE.md). Use `setFont` to supply your own.

## Credits

`gfxterm` originated with **MCJack123**, who also wrote CraftOS-PC and its
graphics mode API. See [CREDITS.md](CREDITS.md).

## Licence

MIT — see the [repository root](../../LICENSE).
