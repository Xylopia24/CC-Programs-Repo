-- Regression: the window.clear() bypass that made `worm` draw over the shell's
-- scrollback in CraftFX-OS.
--
-- rom/apis/term.lua, term.redirect():
--     for _, method in ipairs { "setGraphicsMode", "getGraphicsMode", ... } do
--         if target[method] == nil then target[method] = native[method] end
--     end
--
-- A window has no getGraphicsMode, so redirecting into one COPIES the native
-- terminal's onto it. From then on the window reports the NATIVE graphics mode,
-- and window.lua:269 -
--     if term.getGraphicsMode and term.getGraphicsMode() then
--         return term.native().clear() end
-- - bails out of every window.clear() before blanking tLines or redrawing.
--
-- Headless never really enters mode 2, so the MODE cannot be observed here.
-- What can be observed, and is the whole mechanism, is whether the window ends
-- up holding native's function.
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

local nativeGGM = term.native().getGraphicsMode

-- 1. the leak itself, so the test fails loudly if CC ever changes behaviour
local plain = window.create(term.current(), 1, 1, 10, 5)
ok(plain.getGraphicsMode == nil, "a fresh window has no getGraphicsMode of its own")
local prev = term.redirect(plain)
term.redirect(prev)
ok(plain.getGraphicsMode == nativeGGM,
   "term.redirect COPIED native.getGraphicsMode onto the window (the leak)")

-- 2. GfxTerm.protect gets there first
local guarded = GfxTerm.protect(window.create(term.current(), 1, 1, 10, 5))
ok(type(guarded.getGraphicsMode) == "function", "protect() installed a getGraphicsMode")
ok(guarded.getGraphicsMode() == false, "protect()'s getGraphicsMode reports false")
local prev2 = term.redirect(guarded)
local afterRedirect = guarded.getGraphicsMode
local reported = guarded.getGraphicsMode()
term.redirect(prev2)
ok(afterRedirect ~= nativeGGM, "term.redirect did NOT overwrite it")
ok(reported == false, "still reports false after being redirected to")

-- 3. the convenience constructor does the same
local mock = mockNative()
GfxTerm.enter(mock)
local gfx = GfxTerm.new(mock)
local w = GfxTerm.window(gfx, 2, 2, 20, 8, true)
ok(w.getGraphicsMode() == false, "GfxTerm.window() is protected on creation")
local prev3 = term.redirect(w)
local rep3 = term.getGraphicsMode and term.getGraphicsMode()
term.redirect(prev3)
GfxTerm.leave(mock)
ok(rep3 == false,
   "term.getGraphicsMode() is false inside the window -> window.clear() takes the NORMAL path")

P("")
P("failures: " .. fails)
P(fails == 0 and "ALL PASS" or "FAIL")
local h = fs.open(fs.combine(fs.getDir(shell and shell.getRunningProgram() or ""), "last.log"), "w") h.write(table.concat(out, "\n")) h.close()
