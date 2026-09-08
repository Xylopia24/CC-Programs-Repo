# CraftFX-OS

**The whole of CraftOS, running in graphics mode.**

CraftFX-OS is the reference demonstration for [gfxterm](../../libraries/gfxterm/),
and it is deliberately unimpressive in one specific way:

> **It does not reimplement the shell.**

It redirects `term` at a GfxTerm and calls `shell.run("shell")`. That's it. The
real CraftOS shell, `edit`, `lua`, `paint`, `worm`, and every program you have
ever written then run **completely unmodified**, rendered pixel by pixel.

That is the entire point. A pixel-mode OS you can't run your existing programs
on isn't worth much; this one runs all of them, because underneath it is still
just `term`.

## What the pixels buy you

Everything *around* the shell — none of which text mode can do:

- a **wallpaper** drawn from a 16-step gradient, using palette indices 16–31
  that the text terminal cannot address at all
- a **title bar** with a live scanning animation, ticking away while a fully
  interactive prompt runs underneath it
- a **border** that survives every `clear` the shell performs, because the shell
  lives in an inset `window` and `setMask` keeps text out of the frame

## Install

Two files:

```
mkdir craftfx
cd craftfx
wget https://raw.githubusercontent.com/Xylopia24/CC-Programs-Repo/main/os/craftfx-os/CraftFXOS.lua
wget https://raw.githubusercontent.com/Xylopia24/CC-Programs-Repo/main/libraries/gfxterm/gfxterm.lua
```

`CraftFXOS.lua` finds `gfxterm.lua` beside it, one directory up, or in `lib/`.

## Run

```
CraftFXOS
```

Type `exit` at the prompt to leave, exactly as you would in any shell. The
terminal, the palette and the previous redirect are all restored on the way
out — including if something crashes or you press Ctrl+T.

## Requirements

Graphics mode: **CraftOS-PC**, or **CC: Graphics** in Minecraft. CraftFX-OS
checks at startup and prints a friendly message instead of crashing if it isn't
available.

An 80×25 terminal is assumed for the layout to look right, but nothing is
hardcoded — the grid comes from `term.getSize()`, so other sizes work.

## Booting straight into it

Drop this in `startup/`:

```lua
shell.run("/craftfx/CraftFXOS")
```

If a bad build ever leaves you unable to reach the shell, the files live on your
real filesystem under `Computers/<id>/` — rename the startup script from outside
and the computer boots normally again.

## How it works

The interesting part is about fifteen lines:

```lua
GfxTerm.session(function(native, gfx)
    drawWallpaper(native, W, H)                       -- pixels
    local win = window.create(gfx, 2, 2, cols - 2, rows - 2, true)
    gfx.setMask(1, 1, cols, 1)                        -- protect the title bar
    term.redirect(win)

    parallel.waitForAny(
        function() shell.run("shell") end,            -- the real shell
        function() --[[ animate + blink the caret on a timer ]] end
    )
end)
```

`parallel` resumes both coroutines on every event, so the shell still receives
every keypress while the decoration animates on its own timer.

## Licence

MIT — see the [repository root](../../LICENSE).
