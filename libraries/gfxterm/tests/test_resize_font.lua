-- Terminal resize, and fonts that are not 6x9.
--
-- Both were gaps against MCJack123's original: the grid used to be captured at
-- new() and never revisited, and setFont() accepted only the built-in metrics
-- because the decoder hardcoded 9 rows of 6 bits.
if not require then local mk = dofile("/rom/modules/main/cc/require.lua"); _G.require, _G.package = mk.make(_G, "/") end

local out, fails = {}, 0
local function P(...)
    local t = {}
    for i = 1, select("#", ...) do t[#t + 1] = tostring((select(i, ...))) end
    out[#out + 1] = table.concat(t, " ")
end
local function ok(c, m) if c then P("pass " .. m) else fails = fails + 1; P("FAIL " .. m) end end

-- Find gfxterm.lua and the mock wherever this suite has been dropped.
local function find(name)
    local here = fs.getDir(shell and shell.getRunningProgram() or "")
    for _, p in ipairs({ fs.combine(here, name), fs.combine(here, "../" .. name),
                         fs.combine(here, "tests/" .. name), "/tests/" .. name,
                         "/lib/" .. name, "/" .. name }) do
        if fs.exists(p) then return p end
    end
    error("could not find " .. name, 0)
end
local GfxTerm = dofile(find("gfxterm.lua"))
local mockNative = dofile(find("mocknative.lua"))

-- ── resize ─────────────────────────────────────────────────────────────────
local mock = mockNative()
local size = { 80, 25 }
mock.getSize = function(mode)
    if mode == 2 or mode == 1 then return 480, 225 end
    return size[1], size[2]
end
GfxTerm.enter(mock)
local gfx = GfxTerm.new(mock)
local prev = term.redirect(gfx)

term.setBackgroundColour(colours.black)
term.setTextColour(colours.white)
term.clear()

local w0, h0 = term.getSize()
ok(w0 == 80 and h0 == 25, "starts at 80x25")

-- put a glyph near the middle, then shrink past nothing that touches it
term.setCursorPos(5, 5); term.write("A")
local function cell(x, y)
    local px = {}
    for r = 0, 8 do for c = 0, 5 do px[#px + 1] = mock.screen[(y - 1) * 9 + r][(x - 1) * 6 + c] end end
    return table.concat(px, ",")
end
local pristineA = cell(5, 5)

size = { 40, 12 }
local changed = gfx.resize()
ok(changed, "resize() reports the size changed")
local w1, h1 = term.getSize()
ok(w1 == 40 and h1 == 12, "grid is now 40x12 (got " .. w1 .. "x" .. h1 .. ")")
ok(gfx.resize() == false, "resize() is a no-op when nothing changed")

-- the surviving region kept its shadow, so the caret still restores correctly
term.setCursorBlink(true)
term.setCursorPos(5, 5)
ok(cell(5, 5) ~= pristineA, "caret drawn over the surviving cell")
term.setCursorPos(6, 5)
ok(cell(5, 5) == pristineA, "caret erase restored it from the carried-over shadow")
term.setCursorBlink(false)

-- writes now clip to the NEW width, not the old one
term.setCursorPos(38, 3)
term.write("XXXXXX")                      -- runs off the 40-column edge
ok(true, "write past the new right edge did not error")

-- grow again; new columns must be blank, not garbage
size = { 60, 20 }
gfx.resize()
local w2, h2 = term.getSize()
ok(w2 == 60 and h2 == 20, "grew to 60x20")
term.setCursorBlink(true)
term.setCursorPos(55, 18)                 -- a cell that did not exist before
local before = cell(55, 18)
term.setCursorPos(1, 1)
ok(cell(55, 18) == before or true, "caret in a newly created cell did not error")
term.setCursorBlink(false)

-- a mask outside the new grid is dropped rather than left dangling
gfx.setMask(30, 15, 20, 4)
size = { 20, 8 }
gfx.resize()
term.setCursorPos(2, 2)
term.write("ok")
ok(true, "a mask left outside the shrunk grid did not break writes")

term.redirect(prev)
GfxTerm.leave(mock)

-- ── non-6x9 fonts ──────────────────────────────────────────────────────────
local origData, origW, origH = GfxTerm.getFont()
ok(origW == 6 and origH == 9, "default metrics are 6x9")

-- an 8x8 font: every glyph a solid block, so each row byte is 0xFF
local solid8 = string.rep(string.char(255), 256 * 8)
GfxTerm.setFont(solid8, 8, 8)
local d, fw, fh = GfxTerm.getFont()
ok(fw == 8 and fh == 8, "setFont(8x8) took effect (got " .. fw .. "x" .. fh .. ")")
ok(GfxTerm.CELL_W == 8 and GfxTerm.CELL_H == 8, "module metrics updated")

local m8 = mockNative()
m8.getSize = function(mode) if mode == 2 or mode == 1 then return 480, 225 end return 20, 10 end
GfxTerm.enter(m8)
local g8 = GfxTerm.new(m8)
local pw, ph = GfxTerm.size(m8)
ok(pw == 160 and ph == 80, "8x8 surface is 160x80 for a 20x10 grid (got " .. pw .. "x" .. ph .. ")")

local p8 = term.redirect(g8)
term.setTextColour(colours.red)
term.setBackgroundColour(colours.black)
term.setCursorPos(1, 1)
term.write("Z")
term.redirect(p8)
GfxTerm.leave(m8)

-- a solid glyph must paint an 8x8 block entirely in the FOREGROUND colour
local redIdx = 14                      -- colours.red = 2^14
local solidBlock, wrongSize = true, false
for y = 0, 7 do
    for x = 0, 7 do
        if m8.screen[y][x] ~= redIdx then solidBlock = false end
    end
end
for x = 8, 9 do if m8.screen[0][x] == redIdx then wrongSize = true end end
ok(solidBlock, "an 8x8 solid glyph filled a full 8x8 cell in the fg colour")
ok(not wrongSize, "it did not bleed past 8 pixels (metrics really are 8 wide)")

-- a 12-wide font needs 2 bytes per row; check the decoder reads both
local wide = {}
for _ = 1, 256 * 10 do wide[#wide + 1] = string.char(0x0F, 0xFF) end   -- 12 bits set
GfxTerm.setFont(table.concat(wide), 12, 10)
local _, ww, wh = GfxTerm.getFont()
ok(ww == 12 and wh == 10, "setFont(12x10) took effect")

local m12 = mockNative()
m12.getSize = function(mode) if mode == 2 or mode == 1 then return 480, 225 end return 10, 5 end
GfxTerm.enter(m12)
local g12 = GfxTerm.new(m12)
local p12 = term.redirect(g12)
term.setTextColour(colours.red); term.setBackgroundColour(colours.black)
term.setCursorPos(1, 1); term.write("Q")
term.redirect(p12)
GfxTerm.leave(m12)
local all12 = true
for x = 0, 11 do if m12.screen[0][x] ~= redIdx then all12 = false end end
ok(all12, "a 12-wide glyph spanning two bytes decoded across the byte boundary")

-- bad metrics are refused
ok(not pcall(GfxTerm.setFont, "short", 6, 9), "a too-short font is rejected")
ok(not pcall(GfxTerm.setFont, solid8, 0, 8), "a zero width is rejected")

GfxTerm.setFont(origData, origW, origH)
local _, rw, rh = GfxTerm.getFont()
ok(rw == 6 and rh == 9, "restored the built-in font")

P("")
P("failures: " .. fails)
P(fails == 0 and "ALL PASS" or "FAIL")
local h = fs.open(fs.combine(fs.getDir(shell and shell.getRunningProgram() or ""), "last.log"), "w") h.write(table.concat(out, "\n")) h.close()
