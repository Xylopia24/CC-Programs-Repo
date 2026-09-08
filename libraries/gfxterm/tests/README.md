# gfxterm tests

Headless CraftOS-PC **cannot really enter graphics mode** — the calls succeed,
nothing persists, and a full-screen `drawPixels` can segfault. So these run
against `mocknative.lua`, a stand-in for `term.native()` that enforces every
`drawPixels` contract (mode 2 only, 0-based integer origin, non-ragged string
rows, no overflow, palette index 0–255) and keeps a real framebuffer to assert
against.

| Suite | Covers |
|---|---|
| `test_shell_surface.lua` | That ordinary CC code — `print`, scrolling, `blit`, `window.create`, `textutils` — drives GfxTerm without knowing it exists. The feasibility gate for CraftFX-OS. |
| `test_redirect_leak.lua` | The `term.redirect` mutation that silently breaks `clear()` inside a window — it asserts the leak still exists in CC, and that `GfxTerm.protect` defeats it. This is the bug that made `worm` draw over the shell's scrollback. |
| `test_cursor.lua` | The caret and the shadow buffer behind it. The assertion that matters: moving the caret away restores the covered cell **exactly**, or a shell leaves a trail of underscores behind its prompt. |

## Running them

Put `gfxterm.lua`, `mocknative.lua` and a suite on a computer, then:

**Linux**

    ./CraftOS-PC.AppImage --headless --computers-dir ./Computers --id 6 \
      --exec "dofile('/tests/test_cursor.lua') os.shutdown()"

**Windows, from PowerShell**

    & "C:\Program Files\CraftOS-PC\CraftOS-PC_console.exe" --headless `
      --computers-dir .\Computers --id 6 `
      --exec "dofile('/tests/test_cursor.lua') os.shutdown()"

Then read `last.log` next to the suite. **Read the verdict from that file, not
from stdout** — the console echoes the terminal as it renders, so every line
repeats and is truncated at about 50 characters.

Each suite ends with `ALL PASS` or `FAIL`.
