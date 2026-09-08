-- The cursor and the shadow buffer behind it.
--
-- The thing that actually has to hold: moving the caret away must restore the
-- cell EXACTLY as it was. If the shadow buffer is wrong the shell leaves a
-- trail of underscores behind the prompt.
if not require then local mk = dofile("/rom/modules/main/cc/require.lua"); _G.require, _G.package = mk.make(_G, "/") end

local out, fails = {}, 0
local function P(...)
    local t = {}
    for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
    out[#out + 1] = table.concat(t, " ")
end
local function ok(c, m) if c then P("pass " .. m) else fails = fails + 1; P("FAIL " .. m) end end

-- Find gfxterm.lua and the mock wherever this suite has been dropped.
local function find(name, extra)
    local here = fs.getDir(shell and shell.getRunningProgram() or "")
    local tries = { fs.combine(here, name), fs.combine(here, "../" .. name),
                    fs.combine(here, "tests/" .. name), "/tests/" .. name, "/" .. name,
                    "/lib/" .. name, "/repocheck/" .. name, "/repocheck/tests/" .. name }
    if extra then for _, p in ipairs(extra) do tries[#tries + 1] = p end end
    for _, p in ipairs(tries) do if fs.exists(p) then return p end end
    error("could not find " .. name, 0)
end
local mockNative = dofile(find("mocknative.lua"))
local GfxTerm = dofile(find("gfxterm.lua", { "/repocheck/gfxterm.lua",
                                             "/libraries/gfxterm/gfxterm.lua" }))

local mock = mockNative()
local gfx = GfxTerm.new(mock)
GfxTerm.enter(mock)

-- snapshot the 6x9 pixels of one cell
local function cell(x, y)
    local px = {}
    for r = 0, 8 do
        for c = 0, 5 do px[#px + 1] = mock.screen[(y - 1) * 9 + r][(x - 1) * 6 + c] end
    end
    return table.concat(px, ",")
end

local prev = term.redirect(gfx)

term.setBackgroundColour(colours.black)
term.setTextColour(colours.white)
term.setCursorBlink(false)
term.clear()

-- write a known glyph and remember exactly what it looks like
term.setCursorPos(5, 5)
term.write("A")
local pristineA = cell(5, 5)

term.setCursorPos(6, 5)
term.write("B")
local pristineB = cell(6, 5)

-- park the caret over the 'A'
term.setCursorBlink(true)
term.setCursorPos(5, 5)
local withCaret = cell(5, 5)
ok(withCaret ~= pristineA, "caret is visible over a cell")

-- move it to the 'B' - the 'A' must come back byte for byte
term.setCursorPos(6, 5)
ok(cell(5, 5) == pristineA, "moving the caret away restores the cell exactly")
ok(cell(6, 5) ~= pristineB, "caret now visible on the next cell")

-- blink off restores it too
term.setCursorBlink(false)
ok(cell(6, 5) == pristineB, "turning blink off restores the cell exactly")

-- blinkCursor() toggles
term.setCursorBlink(true)
term.setCursorPos(5, 5)
local on1 = cell(5, 5)
gfx.blinkCursor()
local off1 = cell(5, 5)
gfx.blinkCursor()
local on2 = cell(5, 5)
ok(off1 == pristineA, "blinkCursor() off restores the cell")
ok(on2 == on1, "blinkCursor() on redraws the same caret")

-- writing while the caret is live must not leave a ghost
term.setCursorBlink(true)
term.setCursorPos(10, 7)
term.write("hello")
term.setCursorBlink(false)
local ghost = false
for x = 10, 14 do
    -- each of these cells should hold its own letter, not an underscore
    local expect
    term.setCursorBlink(false)
    term.setCursorPos(30, 20); term.write(("hello"):sub(x - 9, x - 9))
    expect = cell(30, 20)
    if cell(x, 7) ~= expect then ghost = true end
end
ok(not ghost, "no caret ghost left along a written run")

-- scrolling carries the shadow buffer with it
term.setCursorBlink(false)
term.clear()
term.setCursorPos(1, 3); term.write("ROW3")
local row3 = cell(1, 3)
term.scroll(1)
ok(cell(1, 2) == row3, "scroll(1) moved the row up in both pixels and shadow")

-- and the caret survives a scroll without ghosting
term.setCursorPos(1, 2)
term.setCursorBlink(true)
term.scroll(1)
term.setCursorBlink(false)
ok(cell(1, 1) == row3, "row intact after scrolling with the caret live")

term.redirect(prev)
GfxTerm.leave(mock)

P("")
P("failures: " .. fails)
P(fails == 0 and "ALL PASS" or "FAIL")
local h = fs.open(fs.combine(fs.getDir(shell and shell.getRunningProgram() or ""), "last.log"), "w") h.write(table.concat(out, "\n")) h.close()
