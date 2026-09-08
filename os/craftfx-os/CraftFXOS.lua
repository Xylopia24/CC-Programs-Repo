--- CraftFX-OS - the whole of CraftOS, running in graphics mode.
--
-- This is a demonstration of the `gfxterm` library, and the demonstration is
-- deliberately unimpressive in one specific way: **nothing here reimplements
-- the shell.** It redirects `term` at a GfxTerm and calls `shell.run("shell")`.
-- Every program on the computer - edit, lua, paint, worm, anything you have
-- written yourself - then runs unmodified, rendered pixel by pixel.
--
-- What the pixels buy you is everything AROUND that shell: a wallpaper drawn
-- from a 16-step gradient using palette indices the text terminal cannot even
-- address, a title bar, and a live animation ticking away beside a fully
-- interactive prompt. None of that is reachable from text mode.
--
-- Run it:      CraftFXOS
-- Leave it:    type `exit` at the prompt, as you would in any shell.
--
-- MIT licensed. See the repository root.

-- Locate the library: beside this file, one level up, or in lib/. That way a
-- clone of the repository and a bare `wget` of two files both work.
local function loadGfxTerm()
    local dir = fs.getDir(shell.getRunningProgram())
    local tries = {
        fs.combine(dir, "gfxterm.lua"),
        fs.combine(dir, "../gfxterm.lua"),
        fs.combine(dir, "lib/gfxterm.lua"),
        fs.combine(dir, "../libraries/gfxterm/gfxterm.lua"),
        "gfxterm.lua",
    }
    for _, p in ipairs(tries) do
        if fs.exists(p) then return dofile(p) end
    end
    error("gfxterm.lua not found - put it beside this file", 0)
end
local GfxTerm = loadGfxTerm()

local NAME    = "CraftFX-OS"
local VERSION = "1.0.0"

-- Wallpaper gradient lives at palette indices 16..31. Indices 0-15 belong to
-- the CC colours the shell is drawing with, so anything above 15 is ours -
-- and is exactly what a text terminal has no way to reach.
local GRAD_BASE, GRAD_N = 16, 16

local function clamp(v) return v < 0 and 0 or (v > 1 and 1 or v) end

--- Paint the gradient into the palette. Two colours, blended across GRAD_N steps.
local function installGradient(native, from, to)
    for i = 0, GRAD_N - 1 do
        local t = i / (GRAD_N - 1)
        native.setPaletteColor(GRAD_BASE + i,
            clamp(from[1] + (to[1] - from[1]) * t),
            clamp(from[2] + (to[2] - from[2]) * t),
            clamp(from[3] + (to[3] - from[3]) * t))
    end
end

--- Fill the whole surface with a vertical gradient.
local function drawWallpaper(native, w, h)
    local band = math.ceil(h / GRAD_N)
    for i = 0, GRAD_N - 1 do
        local y = i * band
        local hh = math.min(band, h - y)
        if hh > 0 then native.drawPixels(0, y, GRAD_BASE + i, w, hh) end
    end
end

--- A scanning highlight in the title bar. Pure decoration, and the point:
--- it animates while a real shell prompt is live underneath it.
local function drawPulse(native, w, phase)
    local barH = 9                               -- one cell tall
    local cx = math.floor((math.sin(phase) * 0.5 + 0.5) * (w - 40))
    native.drawPixels(0, 0, GRAD_BASE + GRAD_N - 1, w, barH)
    for i = 0, 39 do
        local t = 1 - math.abs(i - 20) / 20
        local idx = GRAD_BASE + math.floor(t * (GRAD_N - 1))
        native.drawPixels(cx + i, 0, idx, 1, barH)
    end
end

local function main()
    if not GfxTerm.available() then
        print(NAME .. " needs graphics mode.")
        print("Run it under CraftOS-PC, or install CC: Graphics in Minecraft.")
        return
    end

    local ok, err, ran = GfxTerm.session(function(native, gfx)
        local W, H, cols, rows = GfxTerm.size(native)

        installGradient(native, { 0.05, 0.06, 0.12 }, { 0.16, 0.34, 0.52 })
        drawWallpaper(native, W, H)

        -- The shell lives in a window inset by one cell, so the wallpaper shows
        -- as a border. The window clears only its own region, which is why the
        -- gradient survives every `clear` the shell performs.
        local win = window.create(gfx, 2, 2, cols - 2, rows - 2, true)

        -- Keep text out of the border: without this, a stray full-width write
        -- would rasterise over the wallpaper.
        gfx.setMask(1, 1, cols, 1)

        local function chrome()
            local title = (" %s %s "):format(NAME, VERSION)
            local hint  = " type 'exit' to leave "
            gfx.setMask()                       -- allow text into row 1 briefly
            gfx.setCursorPos(2, 1)
            gfx.setTextColour(colours.white)
            gfx.setBackgroundColour(colours.blue)
            gfx.write(title)
            gfx.setCursorPos(cols - #hint, 1)
            gfx.setTextColour(colours.lightGrey)
            gfx.write(hint)
            gfx.setMask(1, 1, cols, 1)
        end

        local phase = 0
        local function decorate()
            drawPulse(native, W, phase)
            chrome()
        end
        decorate()

        local prev = term.redirect(win)

        -- The shell and the decoration run side by side. `parallel` resumes
        -- both on every event, so the shell still sees every keypress while the
        -- animation and the caret blink on their own timer.
        local shellDone = false
        parallel.waitForAny(
            function()
                shell.run("shell")
                shellDone = true
            end,
            function()
                local timer = os.startTimer(0.4)
                while not shellDone do
                    local ev, id = os.pullEvent()
                    if ev == "timer" and id == timer then
                        phase = phase + 0.25
                        native.setFrozen(true)
                        decorate()
                        gfx.blinkCursor()
                        native.setFrozen(false)
                        timer = os.startTimer(0.4)
                    end
                end
            end
        )

        term.redirect(prev)
    end)

    if not ran then
        print(NAME .. " could not start graphics mode: " .. tostring(err))
        return
    end
    if not ok then error(err, 0) end

    term.setBackgroundColour(colours.black)
    term.setTextColour(colours.white)
    term.clear()
    term.setCursorPos(1, 1)
    print(NAME .. " exited.")
end

main()
