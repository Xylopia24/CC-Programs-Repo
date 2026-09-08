-- Feasibility gate for CraftFX-OS: can ORDINARY CC code - the kind the shell
-- and every shipped program runs - drive GfxTerm without knowing about it?
--
-- Headless CraftOS-PC cannot really enter graphics mode, so everything runs
-- against tests/mocknative.lua, which enforces every drawPixels contract and
-- keeps a real framebuffer to assert on.
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

-- size is derived from the terminal, not hardcoded
local pw, ph, cols, rows = GfxTerm.size(mock)
ok(cols == 80 and rows == 25, ("grid from getSize(): %dx%d cells"):format(cols, rows))
ok(pw == 480 and ph == 225, ("pixel surface derived: %dx%d"):format(pw, ph))

local gfx = GfxTerm.new(mock)
GfxTerm.enter(mock)
ok(mock.mode == 2, "entered graphics mode")

local prev = term.redirect(gfx)
local body = function()
    -- 1. plain writes
    term.setBackgroundColour(colours.black)
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColour(colours.yellow)
    term.write("CraftFX")

    -- 2. print(), which is what almost every program actually uses, and which
    --    scrolls once it runs off the bottom
    for i = 1, 40 do print("line " .. i) end

    -- 3. blit
    term.setCursorPos(1, 1)
    term.blit("abc", "123", "456")

    -- 4. window.create on top of the redirect - the buffered path
    local w = window.create(term.current(), 4, 4, 20, 5)
    w.setBackgroundColour(colours.blue)
    w.clear()
    w.setCursorPos(1, 1)
    w.write("in a window")
    w.setVisible(true)

    -- 5. textutils, which uses scroll + cursor queries
    textutils.pagedPrint("paged output line")
end

local okRun, err = pcall(body)
term.redirect(prev)
GfxTerm.leave(mock)

ok(okRun, "ordinary CC code ran without error" .. (okRun and "" or (": " .. tostring(err))))
ok(mock.mode == false, "left graphics mode")

-- something was actually drawn
local blits, fills = 0, 0
for _, c in ipairs(mock.calls) do
    if c[1] == "blit" then blits = blits + 1 elseif c[1] == "fill" then fills = fills + 1 end
end
ok(blits > 0, "text was rasterised (" .. blits .. " pixel blits)")
ok(fills > 0, "backgrounds were filled (" .. fills .. " fills)")

-- the framebuffer is not uniform: real glyph pixels landed
local seen = {}
for y = 0, 224 do for x = 0, 479 do seen[mock.screen[y][x]] = true end end
local n = 0
for _ in pairs(seen) do n = n + 1 end
ok(n > 1, "framebuffer holds more than one colour (" .. n .. " distinct)")

-- THE CURSOR GAP: a shell needs a visible caret. Recorded as a known gap so
-- the suite documents it rather than pretending it works.
P("")
P("cursor blink honoured: " .. tostring(gfx.getCursorBlink and "api present" or "MISSING"))

P("")
P("failures: " .. fails)
P(fails == 0 and "ALL PASS" or "FAIL")
local h = fs.open(fs.combine(fs.getDir(shell and shell.getRunningProgram() or ""), "last.log"), "w") h.write(table.concat(out, "\n")) h.close()
