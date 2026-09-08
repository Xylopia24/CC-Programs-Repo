--- setMask: a pixel viewport and a text UI sharing one screen.
--
-- This is the pattern the library was actually built for. A game renders its
-- world with drawPixels into a rectangle, while the panels, stats and menus
-- around it are drawn with the ordinary text tools you already have.
--
-- The problem it solves: a window that repaints its own background every frame
-- paints straight over your pixels, and a frame presented between the two
-- writes shows a black band across the viewport. setMask tells GfxTerm that a
-- rectangle belongs to you, and text is never rasterised into it again.
--
-- Comment out the setMask line below to watch the flicker come back.
--
-- Put gfxterm.lua beside this file and run it. Arrow keys move; Q quits.

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

-- Viewport in CELLS. Cells are the unit the text side thinks in, so the two
-- halves of the layout can be reasoned about together.
local VP = { x = 2, y = 3, w = 46, h = 18 }

local ok, err, ran = GfxTerm.session(function(native, gfx)
    local _, _, cols, rows = GfxTerm.size(native)

    -- pixel bounds of the viewport
    local px, py = GfxTerm.cellToPx(VP.x, VP.y)
    local pw, ph = VP.w * GfxTerm.CELL_W, VP.h * GfxTerm.CELL_H

    -- 24 shades for the world, well clear of the 16 the text UI is using
    for i = 0, 23 do
        native.setPaletteColor(32 + i, 0.05 + i * 0.02, 0.20 + i * 0.03, 0.12 + i * 0.01)
    end

    -- THE LINE. Without it, every sidebar redraw paints over the viewport.
    gfx.setMask(VP.x, VP.y, VP.w, VP.h)

    local sidebar = window.create(term.current(), VP.x + VP.w + 1, VP.y, cols - VP.w - VP.x, VP.h)

    local camX, camY = 0, 0

    local function drawWorld()
        -- Stand-in for a real renderer: a scrolling pattern, one drawPixels
        -- per row band, which is how you would push a tile band too.
        local rows_ = {}
        for r = 1, ph do
            local line = {}
            for c = 1, pw do
                -- floor division: CC is Lua 5.1/5.2, there is no // operator
                local v = (math.floor((c + camX) / 16) + math.floor((r + camY) / 16)) % 24
                line[c] = string.char(32 + v)
            end
            rows_[r] = table.concat(line)
        end
        native.drawPixels(px, py, rows_)
    end

    local function drawChrome()
        term.setBackgroundColour(colours.black)
        term.setTextColour(colours.white)
        term.clear()                      -- clears AROUND the viewport only

        term.setCursorPos(2, 1)
        term.setTextColour(colours.yellow)
        term.write("gfxterm - viewport + text UI")

        term.setCursorPos(2, rows)
        term.setTextColour(colours.grey)
        term.write("arrows: move   Q: quit")

        sidebar.setBackgroundColour(colours.grey)
        sidebar.setTextColour(colours.white)
        sidebar.clear()
        sidebar.setCursorPos(2, 2); sidebar.write("SIDEBAR")
        sidebar.setCursorPos(2, 4); sidebar.write(("cam %d,%d"):format(camX, camY))
        sidebar.setCursorPos(2, 6); sidebar.setTextColour(colours.lightGrey)
        sidebar.write("Ordinary")
        sidebar.setCursorPos(2, 7); sidebar.write("text, drawn")
        sidebar.setCursorPos(2, 8); sidebar.write("every frame,")
        sidebar.setCursorPos(2, 9); sidebar.write("never touching")
        sidebar.setCursorPos(2, 10); sidebar.write("the viewport.")
    end

    while true do
        -- setFrozen batches the frame so the world and the chrome are
        -- presented together instead of tearing.
        native.setFrozen(true)
        drawChrome()
        drawWorld()
        native.setFrozen(false)

        local _, key = os.pullEvent("key")
        if key == keys.q then break
        elseif key == keys.left  then camX = camX - 8
        elseif key == keys.right then camX = camX + 8
        elseif key == keys.up    then camY = camY - 8
        elseif key == keys.down  then camY = camY + 8 end
    end
end)

if not ran then
    print("Could not start graphics mode: " .. tostring(err))
    return
end
if not ok then error(err, 0) end
print("Done.")
