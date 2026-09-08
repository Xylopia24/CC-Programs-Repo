--- The smallest useful gfxterm program.
--
-- Shows the two halves of the idea: ordinary text drawing that has no idea it
-- is in graphics mode, and pixel drawing next to it.
--
-- Put gfxterm.lua beside this file and run it.

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

if not GfxTerm.available() then
    print("This needs graphics mode - run it under CraftOS-PC,")
    print("or install CC: Graphics in Minecraft.")
    return
end

local ok, err, ran = GfxTerm.session(function(native, gfx)
    local W = GfxTerm.size(native)

    -- ── Ordinary text. Nothing here knows about pixels. ────────────────────
    term.setBackgroundColour(colours.black)
    term.clear()
    term.setCursorPos(3, 2)
    term.setTextColour(colours.yellow)
    term.write("Hello from graphics mode")

    term.setCursorPos(3, 4)
    term.setTextColour(colours.lightGrey)
    term.write("This is term.write, unchanged.")

    -- window.create works too - it is built on term like everything else.
    local w = window.create(term.current(), 3, 6, 30, 5)
    w.setBackgroundColour(colours.blue)
    w.setTextColour(colours.white)
    w.clear()
    w.setCursorPos(2, 2)
    w.write("...and so does a window.")
    w.setCursorPos(2, 3)
    w.write("No changes required.")

    -- ── Pixels, in the same frame. ─────────────────────────────────────────
    -- Palette indices above 15 are yours: the text terminal cannot address
    -- them at all. Here are eight shades text mode could never show.
    for i = 0, 7 do
        native.setPaletteColor(16 + i, 0.1 + i * 0.11, 0.15, 0.5 - i * 0.05)
    end
    for i = 0, 7 do
        native.drawPixels(W - 140 + i * 16, 40, 16 + i, 14, 100)
    end

    local _, _, _, rows = GfxTerm.size(native)
    term.setCursorPos(3, rows - 1)
    term.setTextColour(colours.grey)
    term.write("press any key")
    os.pullEvent("key")
end)

if not ran then
    print("Could not start graphics mode: " .. tostring(err))
    return
end
if not ok then error(err, 0) end
print("Back in text mode, palette restored.")
