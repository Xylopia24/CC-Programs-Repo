# gfxterm examples

Each example finds `gfxterm.lua` beside it, one directory up, or in `lib/`. If
you cloned the repository they already work; if you `wget` an example on its
own, fetch the library next to it.

| | Shows |
|---|---|
| `hello.lua` | The smallest useful program: ordinary `term.write` and `window.create` that have no idea they are in graphics mode, with pixel drawing beside them using palette indices text mode cannot reach. |
| `viewport.lua` | **The pattern the library exists for.** A pixel-rendered world in a `setMask`ed rectangle, with a text sidebar redrawing every frame beside it and never touching it. Comment out the `setMask` line to watch the flicker come back. |

Both need graphics mode — CraftOS-PC, or CC: Graphics in Minecraft — and say so
rather than crashing if it is missing.
