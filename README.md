# CC-Programs-Repo

Libraries, programs, games and operating systems for **ComputerCraft** /
**CC:Tweaked**, built and tested against [CraftOS-PC](https://www.craftos-pc.cc/).

Everything here is MIT licensed and meant to be taken and used. Each project is
self-contained with its own README and install line — nothing depends on
anything else in this repo.

---

## Contents

### Libraries

| | What it does |
|---|---|
| **[gfxterm](libraries/gfxterm/)** | Draw ordinary CC text while the screen is in **graphics mode**. A drop-in `term` replacement that rasterises text into pixels with the real ComputerCraft font, so `window.create`, `print`, and every UI library you already have keep working on top of a pixel-rendered game. *A rewrite of [MCJack123's original](https://gist.github.com/MCJack123/f6819e41a60402b8a73403542bb23820) — see its [CREDITS](libraries/gfxterm/CREDITS.md).* |

### Operating systems

| | What it does |
|---|---|
| **[CraftFX-OS](os/craftfx-os/)** | The whole of CraftOS running in graphics mode. It does **not** reimplement the shell — it redirects `term` and calls `shell.run("shell")`, so every existing program renders as pixels unmodified, with a gradient wallpaper and live animation around it. The reference demo for `gfxterm`. |

### Programs

*Nothing here yet.*

### Games

*Nothing here yet.*

---

## Installing

Every project can be pulled straight onto a computer with `wget`. The exact
line is in each project's README; the shape is always:

```
wget https://raw.githubusercontent.com/Xylopia24/CC-Programs-Repo/main/libraries/gfxterm/gfxterm.lua
```

`http` must be enabled — it is by default in CraftOS-PC and on most servers.

---

## Requirements

Most of this targets **graphics mode**, which is not part of vanilla
CC:Tweaked. You need one of:

- **[CraftOS-PC](https://www.craftos-pc.cc/)** — the desktop emulator. Graphics
  mode is built in.
- **CC: Graphics** — the Minecraft mod that ports the same API in-game.

Anything that needs it says so, and checks at runtime rather than crashing.
Plain-text projects will say when they run anywhere CC:Tweaked runs.

---

## Repository layout

```
libraries/    reusable modules you require() from your own code
programs/     standalone utilities
games/        games
os/           full shells and operating systems
```

One folder per project, each with a `README.md`, and `examples/` or `tests/`
where they earn their place.

---

## Credits

**`gfxterm` was MCJack123's idea first.** The
[original](https://gist.github.com/MCJack123/f6819e41a60402b8a73403542bb23820)
dates from December 2020; the version here is a rewrite published with their
encouragement. See [libraries/gfxterm/CREDITS.md](libraries/gfxterm/CREDITS.md).

CraftOS-PC and its graphics mode API — which most of this repo depends on — are
also MCJack123's (JackMacWindows).

The ComputerCraft terminal font embedded in `gfxterm` comes from CC:Tweaked and
is not my work — see [libraries/gfxterm/FONT-NOTICE.md](libraries/gfxterm/FONT-NOTICE.md).

## Licence

[MIT](LICENSE), except where a file says otherwise.
