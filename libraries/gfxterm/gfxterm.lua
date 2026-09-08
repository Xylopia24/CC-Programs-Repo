--- GfxTerm - draw normal ComputerCraft text while the screen is in graphics mode.
--
-- CraftOS-PC's graphics mode (and CC: Graphics in Minecraft) gives you a pixel
-- surface, but it hides the terminal's own text completely. The moment you call
-- `term.setGraphicsMode(2)`, every window, every `term.write`, every UI library
-- you already have stops appearing.
--
-- GfxTerm is a `term` object you can redirect to. It rasterises each write and
-- blit with the real ComputerCraft font and pushes it as pixels, so your
-- existing text UI keeps working *unchanged* on top of a pixel game.
--
--   local GfxTerm = require("gfxterm")
--
--   GfxTerm.session(function(native, gfx)
--       -- graphics mode is on and `term` points at `gfx`.
--       -- Ordinary text still works:
--       term.setCursorPos(2, 2)
--       term.setTextColour(colours.yellow)
--       term.write("Hello from graphics mode")
--
--       -- ...and so does window.create, and any library built on term.
--       -- Draw your own pixels straight to `native`:
--       native.drawPixels(0, 0, 32, 40, 30)
--
--       os.pullEvent("key")
--   end)
--   -- text mode, palette and the previous redirect are all restored HERE,
--   -- however the body ended - including on error or terminate.
--
-- Everything is documented in README.md next to this file.
--
-- Requires: CraftOS-PC, or CC: Graphics in Minecraft. `GfxTerm.available()`
-- tells you whether the current terminal can do any of this.
--
-- ---------------------------------------------------------------------------
-- Behaviour that is deliberate, and cost real debugging to learn. Please read
-- before "fixing" any of it:
--
--   * Every pixel call goes to `term.native()`. The shell's window wrapper
--     ignores `getSize(mode)` and raises a fake "Invalid colour" for palette
--     indices above 15, so a GfxTerm built on anything else misbehaves.
--   * In graphics mode the palette functions take a raw INDEX 0-255, not a CC
--     colour value - index 1 is orange, not white. GfxTerm converts, so callers
--     keep using `colours.*` as normal.
--   * `getGraphicsMode()` returns FALSE on purpose. CraftOS-PC's `window.lua`
--     sends `clear()` straight to `term.native()` whenever its parent claims a
--     graphics mode, which would bypass the window's own line buffer and erase
--     the whole screen instead of the window.
--   * The pixel surface is `cols * 6` by `rows * 9`. `getSize(2)` reports it
--     directly too (480x225 on an 80x25 terminal), but ONLY once really in
--     mode 2 - in text mode, and in headless CraftOS-PC which never truly
--     enters mode 2, it answers with the cell size instead. Deriving it is the
--     reliable route.
--   * `term.redirect` copies `native.getGraphicsMode` onto any target lacking
--     one, which breaks `window.clear()`. See `GfxTerm.protect`.
--   * Pixel coordinates are 0-based; cell (c, r) starts at ((c-1)*6, (r-1)*9).
--
-- ---------------------------------------------------------------------------
-- PRIOR ART
--
-- gfxterm was MCJack123's idea first. The original is at
--   https://gist.github.com/MCJack123/f6819e41a60402b8a73403542bb23820
-- (December 2020), and the name, and the whole concept of a redirectable term
-- that renders CC text into graphics mode, are theirs. MCJack123 also wrote
-- CraftOS-PC and the graphics mode API this depends on.
--
-- This is a rewrite - different font pipeline, batched rendering, a shadow
-- buffer and cursor, masking, and a session wrapper that cannot strand you on
-- a black screen - but it is a descendant, not an independent invention.
-- See CREDITS.md for a full comparison.
--
-- MIT licensed, published with MCJack123's encouragement. See LICENSE at the
-- repository root.
--
-- The embedded font is the ComputerCraft terminal font, from CC:Tweaked's
-- `term_font.png`. It is included so text looks identical to real text mode.
-- It is not my work and no ownership is claimed - see FONT-NOTICE.md. Call
-- `GfxTerm.setFont` if you would rather supply your own.

local GfxTerm = {}

GfxTerm._VERSION = "1.0.0"
GfxTerm._URL     = "https://github.com/Xylopia24/CC-Programs-Repo"

-- The ComputerCraft terminal font: 256 glyphs, 9 rows each, one byte per row,
-- bit 5 (32) = leftmost pixel of a 6-wide glyph. See FONT-NOTICE.md.
local FONT = "\0\0\0\0\0\0\0\0\0\28\34\54\34\42\34\28\0\0\28\62\42\62\34\54\28\0\0\0\20\62\62\62\28\8\0\0\0\8\28\62\28\8\0\0\0\8\28\8\62\62\8\28\0\0\0\8\28\62\62\8\28\0\0\0\0\12\30\30\12\0\0\0\63\63\51\33\33\51\63\63\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\14\6\26\36\36\24\0\0\28\34\34\34\28\8\28\8\0\0\0\0\0\0\0\0\0\0\0\30\18\30\16\48\48\0\0\0\31\17\31\17\51\51\0\0\0\32\56\62\56\32\0\0\0\0\2\14\62\14\2\0\0\0\8\28\62\8\8\62\28\8\0\18\18\18\18\18\0\18\0\0\30\42\42\26\10\10\10\0\0\30\48\44\34\26\6\60\0\0\0\0\0\0\0\30\30\0\0\8\28\62\8\62\28\8\62\0\8\28\62\8\8\8\8\0\0\8\8\8\8\62\28\8\0\0\0\8\12\62\12\8\0\0\0\0\8\24\62\24\8\0\0\0\0\0\0\0\32\32\62\0\0\0\0\18\63\18\0\0\0\0\0\8\8\28\28\62\0\0\0\0\62\28\28\8\8\0\0\0\0\0\0\0\0\0\0\0\0\8\8\8\8\8\0\8\0\0\10\10\20\0\0\0\0\0\0\20\20\62\20\62\20\20\0\0\8\30\32\28\2\60\8\0\0\34\36\4\8\16\18\34\0\0\8\20\8\26\44\36\26\0\0\4\4\8\0\0\0\0\0\0\6\8\16\16\16\8\6\0\0\24\4\2\2\2\4\24\0\0\0\0\18\12\18\0\0\0\0\0\8\8\62\8\8\0\0\0\0\0\0\0\0\8\8\8\0\0\0\0\62\0\0\0\0\0\0\0\0\0\0\8\8\0\0\2\4\4\8\16\16\32\0\0\28\34\38\42\50\34\28\0\0\8\24\8\8\8\8\62\0\0\28\34\2\12\16\34\62\0\0\28\34\2\12\2\34\28\0\0\6\10\18\34\62\2\2\0\0\62\32\60\2\2\34\28\0\0\12\16\32\60\34\34\28\0\0\62\34\2\4\8\8\8\0\0\28\34\34\28\34\34\28\0\0\28\34\34\30\2\4\24\0\0\0\8\8\0\0\8\8\0\0\0\8\8\0\0\8\8\8\0\2\4\8\16\8\4\2\0\0\0\0\62\0\0\62\0\0\0\16\8\4\2\4\8\16\0\0\28\34\2\4\8\0\8\0\0\30\33\45\45\47\32\30\0\0\28\34\62\34\34\34\34\0\0\60\34\60\34\34\34\60\0\0\28\34\32\32\32\34\28\0\0\60\34\34\34\34\34\60\0\0\62\32\56\32\32\32\62\0\0\62\32\56\32\32\32\32\0\0\30\32\38\34\34\34\28\0\0\34\34\62\34\34\34\34\0\0\28\8\8\8\8\8\28\0\0\2\2\2\2\2\34\28\0\0\34\36\56\36\34\34\34\0\0\32\32\32\32\32\32\62\0\0\34\54\42\34\34\34\34\0\0\34\50\42\38\34\34\34\0\0\28\34\34\34\34\34\28\0\0\60\34\60\32\32\32\32\0\0\28\34\34\34\34\36\26\0\0\60\34\60\34\34\34\34\0\0\30\32\28\2\2\34\28\0\0\62\8\8\8\8\8\8\0\0\34\34\34\34\34\34\28\0\0\34\34\34\34\20\20\8\0\0\34\34\34\34\42\54\34\0\0\34\20\8\20\34\34\34\0\0\34\20\8\8\8\8\8\0\0\62\2\4\8\16\32\62\0\0\28\16\16\16\16\16\28\0\0\32\16\16\8\4\4\2\0\0\28\4\4\4\4\4\28\0\0\8\20\34\0\0\0\0\0\0\0\0\0\0\0\0\0\62\0\8\8\4\0\0\0\0\0\0\0\0\28\2\30\34\30\0\0\32\32\44\50\34\34\60\0\0\0\0\28\34\32\34\28\0\0\2\2\26\38\34\34\30\0\0\0\0\28\34\62\32\30\0\0\6\8\30\8\8\8\8\0\0\0\0\30\34\34\30\2\60\0\32\32\44\50\34\34\34\0\0\8\0\8\8\8\8\8\0\0\2\0\2\2\2\34\34\28\0\16\16\18\20\24\20\18\0\0\8\8\8\8\8\8\4\0\0\0\0\52\42\42\34\34\0\0\0\0\60\34\34\34\34\0\0\0\0\28\34\34\34\28\0\0\0\0\44\50\34\60\32\32\0\0\0\26\38\34\30\2\2\0\0\0\44\50\32\32\32\0\0\0\0\30\32\28\2\60\0\0\8\8\28\8\8\8\4\0\0\0\0\34\34\34\34\30\0\0\0\0\34\34\34\20\8\0\0\0\0\34\34\42\42\30\0\0\0\0\34\20\8\20\34\0\0\0\0\34\34\34\30\2\60\0\0\0\62\4\8\16\62\0\0\6\8\8\16\8\8\6\0\0\8\8\8\8\8\8\8\0\0\24\4\4\2\4\4\24\0\0\25\38\0\0\0\0\0\0\0\18\36\9\18\36\9\18\36\9\0\0\0\0\0\0\0\0\0\56\56\56\0\0\0\0\0\0\7\7\7\0\0\0\0\0\0\63\63\63\0\0\0\0\0\0\0\0\0\56\56\56\0\0\0\56\56\56\56\56\56\0\0\0\7\7\7\56\56\56\0\0\0\63\63\63\56\56\56\0\0\0\0\0\0\7\7\7\0\0\0\56\56\56\7\7\7\0\0\0\7\7\7\7\7\7\0\0\0\63\63\63\7\7\7\0\0\0\0\0\0\63\63\63\0\0\0\56\56\56\63\63\63\0\0\0\7\7\7\63\63\63\0\0\0\63\63\63\63\63\63\0\0\0\0\0\0\0\0\0\56\56\56\56\56\56\0\0\0\56\56\56\7\7\7\0\0\0\56\56\56\63\63\63\0\0\0\56\56\56\0\0\0\56\56\56\56\56\56\56\56\56\56\56\56\56\56\56\7\7\7\56\56\56\56\56\56\63\63\63\56\56\56\56\56\56\0\0\0\7\7\7\56\56\56\56\56\56\7\7\7\56\56\56\7\7\7\7\7\7\56\56\56\63\63\63\7\7\7\56\56\56\0\0\0\63\63\63\56\56\56\56\56\56\63\63\63\56\56\56\7\7\7\63\63\63\56\56\56\63\63\63\63\63\63\56\56\56\0\0\0\0\0\0\0\0\0\8\0\8\8\8\8\8\0\0\0\8\28\34\32\34\28\8\0\12\18\16\60\16\16\62\0\0\0\34\28\34\34\34\28\34\0\34\20\62\8\62\8\8\0\0\8\8\8\0\8\8\8\0\0\30\48\44\34\26\6\60\0\0\20\0\0\0\0\0\0\0\0\0\30\37\41\41\37\30\0\0\24\4\28\36\28\0\0\0\0\0\0\10\20\40\20\10\0\0\0\0\0\62\2\2\0\0\0\0\0\0\62\0\0\0\0\0\0\30\45\45\43\33\30\0\0\62\0\0\0\0\0\0\0\0\24\36\36\24\0\0\0\0\0\0\8\8\62\8\8\0\62\0\32\16\48\32\48\0\0\0\0\48\16\48\16\48\0\0\0\0\16\32\0\0\0\0\0\0\0\0\0\34\34\34\34\61\32\32\30\42\42\26\10\10\10\0\0\0\0\0\12\12\0\0\0\0\0\0\0\0\0\0\4\8\0\16\48\16\16\56\0\0\0\0\0\28\34\34\34\28\0\0\0\0\0\40\20\10\20\40\0\0\34\36\4\8\22\22\34\0\0\34\36\4\8\18\20\38\0\0\50\20\52\8\22\22\34\0\0\8\0\8\16\32\34\28\0\0\48\0\28\34\62\34\34\0\0\6\0\28\34\62\34\34\0\0\28\34\28\34\62\34\34\0\0\20\40\28\34\62\34\34\0\0\20\0\28\34\62\34\34\0\0\8\0\28\34\62\34\34\0\0\30\40\40\60\40\40\46\0\0\28\34\32\32\34\28\4\8\0\48\0\62\32\60\32\62\0\0\6\0\62\32\60\32\62\0\0\28\34\62\32\60\32\62\0\0\20\0\62\32\60\32\62\0\0\24\0\28\8\8\8\28\0\0\12\0\28\8\8\8\28\0\0\8\20\28\8\8\8\28\0\0\20\0\28\8\8\8\28\0\0\60\34\34\50\34\34\60\0\0\10\20\34\50\42\38\34\0\0\48\28\34\34\34\34\28\0\0\6\28\34\34\34\34\28\0\0\28\34\28\34\34\34\28\0\0\20\40\28\34\34\34\28\0\0\20\28\34\34\34\34\28\0\0\0\34\20\8\20\34\0\0\0\28\34\38\42\50\34\28\0\0\48\0\34\34\34\34\28\0\0\6\0\34\34\34\34\28\0\0\8\20\0\34\34\34\28\0\0\20\0\34\34\34\34\28\0\0\6\0\34\20\8\8\8\0\0\28\8\12\10\12\8\28\0\0\60\34\44\34\34\34\44\32\0\48\0\28\2\30\34\30\0\0\6\0\28\2\30\34\30\0\0\28\34\28\2\30\34\30\0\0\20\40\28\2\30\34\30\0\0\20\0\28\2\30\34\30\0\0\8\0\28\2\30\34\30\0\0\0\0\22\41\62\40\23\0\0\0\28\34\32\34\28\4\8\0\48\0\28\34\62\32\30\0\0\6\0\28\34\62\32\30\0\0\28\34\28\34\62\32\30\0\0\20\0\28\34\62\32\30\0\0\24\0\8\8\8\8\8\0\0\12\0\8\8\8\8\8\0\0\8\20\8\8\8\8\8\0\0\20\0\8\8\8\8\8\0\0\8\4\30\34\34\34\28\0\0\20\40\60\34\34\34\34\0\0\48\0\28\34\34\34\28\0\0\6\0\28\34\34\34\28\0\0\28\34\28\34\34\34\28\0\0\20\40\28\34\34\34\28\0\0\20\0\28\34\34\34\28\0\0\0\8\0\62\0\8\0\0\0\0\0\28\38\42\50\28\0\0\48\0\34\34\34\34\30\0\0\6\0\34\34\34\34\30\0\0\8\20\0\34\34\34\30\0\0\20\0\34\34\34\34\30\0\0\6\0\34\34\34\30\2\60\0\24\8\12\10\12\8\28\0\0\20\0\34\34\34\30\2\60\0"

-- Font metrics. The embedded font is 6x9; a replacement may be any size.
local CELL_W, CELL_H = 6, 9
local FONT_BPR = 1                       -- bytes per glyph row = ceil(w / 8)
local FONT_MASK = {}                     -- pixel x -> bit within the row value
GfxTerm.CELL_W, GfxTerm.CELL_H = CELL_W, CELL_H

local function buildMask(w)
    local m = {}
    for x = 0, w - 1 do m[x] = 2 ^ (w - 1 - x) end
    return m
end
FONT_MASK = buildMask(CELL_W)

--- Replace the font, and optionally its metrics.
--
-- Each glyph row is a big-endian integer in `ceil(w / 8)` bytes, and pixel x is
-- bit `(w - 1 - x)` of it - so the glyph sits right-aligned in its bytes. Glyph
-- *g* starts at byte `g * h * ceil(w / 8) + 1`. At the default 6x9 that reduces
-- to one byte per row with bit 5 as the leftmost pixel.
--
-- Set the font BEFORE creating terminals: `new()` captures the metrics, so a
-- terminal already running is never disturbed by a later change.
--
-- @param data string of at least 256 * h * ceil(w / 8) bytes
-- @param w    glyph width in pixels  (default 6)
-- @param h    glyph height in pixels (default 9)
function GfxTerm.setFont(data, w, h)
    w, h = w or 6, h or 9
    if type(data) ~= "string" then error("setFont: data must be a string", 2) end
    if type(w) ~= "number" or w < 1 or w > 32 or w % 1 ~= 0 then
        error("setFont: width must be an integer 1-32 (got " .. tostring(w) .. ")", 2)
    end
    if type(h) ~= "number" or h < 1 or h % 1 ~= 0 then
        error("setFont: height must be a positive integer (got " .. tostring(h) .. ")", 2)
    end
    local bpr = math.ceil(w / 8)
    local need = 256 * h * bpr
    if #data < need then
        error("setFont: expected at least " .. need .. " bytes for a " .. w .. "x" .. h
              .. " font, got " .. #data, 2)
    end
    FONT, CELL_W, CELL_H, FONT_BPR = data, w, h, bpr
    FONT_MASK = buildMask(w)
    GfxTerm.CELL_W, GfxTerm.CELL_H = w, h
end

--- The font currently in use.
-- @return data, width, height
function GfxTerm.getFont() return FONT, CELL_W, CELL_H end

-- CC colour value <-> palette index, and blit's hex digits <-> index.
local IDX = {}
for k = 0, 15 do IDX[2 ^ k] = k end
local HEX = "0123456789abcdef"
local HEXIDX = {}
for k = 0, 15 do HEXIDX[HEX:sub(k + 1, k + 1)] = k end
local unpack_ = table.unpack or unpack     -- CC ships both Lua 5.1 and 5.2 flavours

--- Pixel coordinate of the top-left of a cell. Cells are 1-based, pixels 0-based.
function GfxTerm.cellToPx(col, row) return (col - 1) * CELL_W, (row - 1) * CELL_H end

--- The pixel size of the surface for a terminal, derived from its cell size.
--
-- Derived rather than read from `getSize(2)` because that only answers in
-- pixels once the terminal is genuinely in mode 2; before the switch, and under
-- headless CraftOS-PC, it returns the cell size instead. `cols * 6` by
-- `rows * 9` is correct either way.
-- @return pixelWidth, pixelHeight, cols, rows
function GfxTerm.size(native)
    native = native or term.native()
    local cols, rows = native.getSize()
    return cols * CELL_W, rows * CELL_H, cols, rows
end

--- Make a redirect target safe to hand to `term.redirect` while in graphics
--- mode. Returns the same object.
--
-- `term.redirect` COPIES `native.getGraphicsMode` onto any target that does not
-- have one of its own. A `window` does not have one - so the moment you
-- redirect into a window, that window starts reporting the NATIVE graphics
-- mode. `window.clear()` checks exactly that, and when it is truthy it bails
-- out to `term.native().clear()` WITHOUT blanking its own lines or redrawing.
--
-- The visible result is that `clear()` inside the window does nothing: old text
-- survives and whatever runs next draws on top of it. Every program that clears
-- the screen is affected.
--
-- Call this on a window (or any redirect target) BEFORE redirecting to it.
-- `term.redirect` only fills in methods that are nil, so getting there first
-- wins.
function GfxTerm.protect(target)
    if target.getGraphicsMode == nil then
        target.getGraphicsMode = function() return false end
    end
    return target
end

--- `window.create` plus `GfxTerm.protect`. Use this instead of `window.create`
--- for any window living over a GfxTerm.
function GfxTerm.window(parent, x, y, w, h, visible)
    return GfxTerm.protect(window.create(parent, x, y, w, h, visible))
end

--- Can this terminal do graphics mode at all?
-- False under vanilla CC:Tweaked without CC: Graphics, and in CraftOS-PC's
-- headless mode (where the calls exist but nothing is drawn).
function GfxTerm.available(native)
    native = native or term.native()
    return type(native.setGraphicsMode) == "function"
       and type(native.drawPixels) == "function"
       and type(native.setFrozen) == "function"
end

-- Palette captured across the mode switch so leave() can put it back.
local _saved

--- Switch the terminal into graphics mode, carrying the current 16 colours
--- across so a themed UI keeps its palette.
function GfxTerm.enter(native)
    native = native or term.native()
    _saved = {}
    for k = 0, 15 do _saved[k] = { native.getPaletteColor(2 ^ k) } end
    native.setGraphicsMode(2)
    -- After the switch the palette functions address raw indices, and indices
    -- 0-15 start at CC's DEFAULTS rather than whatever the caller had set.
    for k = 0, 15 do
        local c = _saved[k]
        native.setPaletteColor(k, c[1], c[2], c[3])
    end
end

--- Back to text mode, restoring the palette. Safe to call twice.
function GfxTerm.leave(native)
    native = native or term.native()
    if native.setFrozen then pcall(native.setFrozen, false) end
    native.setGraphicsMode(0)
    if _saved then
        for k = 0, 15 do
            local c = _saved[k]
            pcall(native.setPaletteColor, 2 ^ k, c[1], c[2], c[3])
        end
        _saved = nil
    end
end

--- Run `body(native, gfx)` in graphics mode with `term` redirected to a
--- GfxTerm, then restore EVERYTHING - mode, palette and redirect - no matter
--- how the body ends.
--
-- An uncaught error in graphics mode otherwise strands the user on a black
-- screen with no shell, so prefer this over calling enter/leave yourself.
--
-- @return ok, err, ran
--   ran == false : setup failed (err says why); `body` never ran, and the
--                  caller should fall back to a text-mode path.
--   ok  == false : `body` raised; `err` is its traceback, ready to rethrow
--                  with `error(err, 0)` so "Terminated" keeps its prefix.
function GfxTerm.session(body)
    local native = term.native()
    local gfx, prev
    local okSetup, errSetup = pcall(function()
        gfx = GfxTerm.new(native)
        GfxTerm.enter(native)
        prev = term.redirect(gfx)
    end)
    if not okSetup then
        if prev then pcall(term.redirect, prev) end
        pcall(GfxTerm.leave, native)
        return false, tostring(errSetup), false
    end
    local ok, err = xpcall(body, debug.traceback, native, gfx)
    pcall(term.redirect, prev)
    pcall(GfxTerm.leave, native)
    return ok, err, true
end

--- Create a term object that rasterises text onto `native`'s pixel surface.
-- The grid is fixed at creation from the terminal's current size.
function GfxTerm.new(native)
    native = native or term.native()

    -- Metrics are captured here, so GfxTerm.setFont later cannot corrupt a
    -- terminal that is already drawing.
    local CW, CH, BPR, MASK = CELL_W, CELL_H, FONT_BPR, FONT_MASK
    local FDATA = FONT

    local cols0, rows0 = native.getSize()
    local COLS, ROWS = cols0, rows0
    local SCREEN_W, SCREEN_H = COLS * CW, ROWS * CH

    local t = {}
    local cx, cy = 1, 1
    local fg, bg = 0, 15              -- palette indices: white on black
    local blink = false

    -- Shadow buffer of what is on screen, one entry per cell. A caret cannot
    -- be erased without knowing what it covered, so a terminal that shows a
    -- cursor has to remember its own contents. Kept as three flat arrays
    -- rather than a table per cell - 2000 small tables is a lot of garbage.
    local shCh, shFg, shBg = {}, {}, {}
    local function blankRow(a, b, c, from, to, f, bgi)
        for x = from, to do a[x], b[x], c[x] = 32, f or 0, bgi or 15 end
    end
    for y = 1, ROWS do
        local a, b, c = {}, {}, {}
        blankRow(a, b, c, 1, COLS)
        shCh[y], shFg[y], shBg[y] = a, b, c
    end

    local function colourIndex(c)
        local i = IDX[c]
        if i == nil then error("Invalid color (got " .. tostring(c) .. ")", 3) end
        return i
    end

    -- glyph cache: (byte, fg, bg) -> CH row strings of CW bytes each
    local cache = {}
    local function glyph(byte, f, b)
        local key = byte * 256 + f * 16 + b
        local g = cache[key]
        if g then return g end
        g = {}
        local fc, bc = string.char(f), string.char(b)
        local base = byte * CH * BPR
        for r = 1, CH do
            -- the row is a big-endian integer across BPR bytes
            local bits, off = 0, base + (r - 1) * BPR
            for k = 1, BPR do bits = bits * 256 + (FDATA:byte(off + k) or 0) end
            local s = {}
            for x = 0, CW - 1 do
                s[x + 1] = bit32.band(bits, MASK[x]) ~= 0 and fc or bc
            end
            g[r] = table.concat(s)
        end
        cache[key] = g
        return g
    end

    --- Protect a rectangle (in CELLS) from text.
    -- Nothing is ever rasterised inside it, so a region you paint yourself with
    -- drawPixels - a game viewport, a chart, a video - is not overwritten when
    -- an unrelated window redraws. Without it, a window that repaints its
    -- background each frame flashes a band over your pixels.
    -- Call with no arguments to clear the mask.
    local mask
    function t.setMask(x, y, w, h)
        mask = x and { x0 = x, x1 = x + w - 1, y0 = y, y1 = y + h - 1 } or nil
    end

    -- Rasterise chars i0..i1 of `text` (run starting at cell x0) as one blit.
    local function emit(text, fgs, bgs, x0, i0, i1)
        local rows = {}
        for r = 1, CH do rows[r] = {} end
        local j = 0
        local rowCh, rowFg, rowBg = shCh[cy], shFg[cy], shBg[cy]
        for i = i0, i1 do
            j = j + 1
            local ch = text:byte(i)
            local f, b = fgs and fgs[i] or fg, bgs and bgs[i] or bg
            local g = glyph(ch, f, b)
            for r = 1, CH do rows[r][j] = g[r] end
            local col = x0 + i - 1
            if rowCh and col >= 1 and col <= COLS then
                rowCh[col], rowFg[col], rowBg[col] = ch, f, b
            end
        end
        for r = 1, CH do rows[r] = table.concat(rows[r]) end
        native.drawPixels((x0 + i0 - 2) * CW, (cy - 1) * CH, rows)
    end

    -- ── Cursor ─────────────────────────────────────────────────────────────
    -- CC renders the caret as an underscore in the current text colour. It is
    -- painted straight to the surface (never through put()) and erased by
    -- repainting the covered cell out of the shadow buffer.
    local curOn, curX, curY = false, 1, 1

    local function inGrid(x, y) return x >= 1 and x <= COLS and y >= 1 and y <= ROWS end

    local function paintCell(x, y)
        if not inGrid(x, y) then return end
        local g = glyph(shCh[y][x], shFg[y][x], shBg[y][x])
        native.drawPixels((x - 1) * CW, (y - 1) * CH, g)
    end

    local function eraseCursor()
        if not curOn then return end
        curOn = false
        paintCell(curX, curY)
    end

    local function drawCursor()
        if not blink or not inGrid(cx, cy) then return end
        if mask and cx >= mask.x0 and cx <= mask.x1 and cy >= mask.y0 and cy <= mask.y1 then
            return          -- never scribble into a protected region
        end
        local g = glyph(95, fg, shBg[cy][cx])          -- 95 = '_'
        native.drawPixels((cx - 1) * CW, (cy - 1) * CH, g)
        curOn, curX, curY = true, cx, cy
    end

    --- Toggle the caret once. Call on a timer (~0.4 s) for a blinking cursor;
    --- the caret is already drawn without it, so this is optional polish.
    function t.blinkCursor()
        if not blink then eraseCursor(); return end
        if curOn then eraseCursor() else drawCursor() end
    end

    --- Force the caret to be redrawn - after you have painted your own pixels
    --- over the area it occupies, for instance.
    function t.refreshCursor() eraseCursor(); drawCursor() end

    --- Adopt a new terminal size.
    --
    -- The grid is fixed when the terminal is created, so a GfxTerm does not
    -- notice the window being resized on its own. Call this when you see a
    -- `term_resize` event:
    --
    --     if ev == "term_resize" then gfx.resize() end
    --
    -- The shadow buffer is carried across, keeping whatever still fits, so the
    -- caret can still erase itself correctly afterwards. The SCREEN is not
    -- repainted - only the model is corrected - because only the caller knows
    -- what should be on it. Redraw after calling this.
    --
    -- @param cols,rows optional explicit size; read from the terminal if absent
    -- @return true if the size actually changed
    function t.resize(cols, rows)
        if not cols or not rows then cols, rows = native.getSize() end
        cols, rows = math.floor(cols), math.floor(rows)
        if cols < 1 or rows < 1 then return false end
        if cols == COLS and rows == ROWS then return false end

        eraseCursor()

        for y = 1, rows do
            local a, b, c = shCh[y], shFg[y], shBg[y]
            if a then
                if cols > COLS then                  -- widened: blank the new columns
                    blankRow(a, b, c, COLS + 1, cols)
                elseif cols < COLS then              -- narrowed: drop the tail
                    for x = cols + 1, COLS do a[x], b[x], c[x] = nil, nil, nil end
                end
            else                                     -- a brand new row
                a, b, c = {}, {}, {}
                blankRow(a, b, c, 1, cols)
                shCh[y], shFg[y], shBg[y] = a, b, c
            end
        end
        for y = rows + 1, ROWS do                    -- shortened: drop the rows
            shCh[y], shFg[y], shBg[y] = nil, nil, nil
        end

        COLS, ROWS = cols, rows
        SCREEN_W, SCREEN_H = COLS * CW, ROWS * CH

        if mask then                                 -- keep the mask inside the grid
            mask.x0, mask.y0 = math.max(1, mask.x0), math.max(1, mask.y0)
            mask.x1, mask.y1 = math.min(COLS, mask.x1), math.min(ROWS, mask.y1)
            if mask.x1 < mask.x0 or mask.y1 < mask.y0 then mask = nil end
        end
        if cx > COLS + 1 then cx = COLS + 1 end
        if cy > ROWS then cy = ROWS end

        drawCursor()
        return true
    end

    -- Rasterise `text` at the cursor. fgs/bgs are per-char index arrays, or nil
    -- for the current uniform colours. Clips to the grid and around the mask.
    local function put(text, fgs, bgs)
        local n = #text
        if n == 0 then return end
        local x0 = cx
        cx = cx + n
        if cy < 1 or cy > ROWS then return end
        local first, last = 1, n
        if x0 < 1 then first = 2 - x0 end
        if x0 + n - 1 > COLS then last = COLS - x0 + 1 end
        if first > last then return end
        if mask and cy >= mask.y0 and cy <= mask.y1 then
            local m0, m1 = mask.x0 - x0 + 1, mask.x1 - x0 + 1    -- as char indices
            if first < m0 then emit(text, fgs, bgs, x0, first, math.min(last, m0 - 1)) end
            if last > m1 then emit(text, fgs, bgs, x0, math.max(first, m1 + 1), last) end
            return
        end
        emit(text, fgs, bgs, x0, first, last)
    end

    function t.write(text)
        eraseCursor()
        put(tostring(text))
        drawCursor()
    end

    function t.blit(text, tfg, tbg)
        if type(text) ~= "string" or type(tfg) ~= "string" or type(tbg) ~= "string" then
            error("Expected string, string, string", 2)
        end
        if #tfg ~= #text or #tbg ~= #text then error("Arguments must be the same length", 2) end
        local fgs, bgs = {}, {}
        for i = 1, #text do
            fgs[i] = HEXIDX[tfg:sub(i, i)] or fg
            bgs[i] = HEXIDX[tbg:sub(i, i)] or bg
        end
        eraseCursor()
        put(text, fgs, bgs)
        drawCursor()
    end

    -- Record a background fill over a cell range in the shadow buffer.
    local function shadowFill(x0, x1, y0, y1)
        for y = math.max(1, y0), math.min(ROWS, y1) do
            local a, b, c = shCh[y], shFg[y], shBg[y]
            for x = math.max(1, x0), math.min(COLS, x1) do
                a[x], b[x], c[x] = 32, fg, bg
            end
        end
    end

    -- Fill cell rows y0..y1 with the background colour, leaving the mask alone.
    local function fillRows(y0, y1)
        local py, ph = (y0 - 1) * CH, (y1 - y0 + 1) * CH
        if not mask or y1 < mask.y0 or y0 > mask.y1 then
            shadowFill(1, COLS, y0, y1)
            native.drawPixels(0, py, bg, SCREEN_W, ph); return
        end
        shadowFill(1, mask.x0 - 1, y0, y1); shadowFill(mask.x1 + 1, COLS, y0, y1)
        shadowFill(1, COLS, y0, mask.y0 - 1); shadowFill(1, COLS, mask.y1 + 1, y1)
        if y0 < mask.y0 then native.drawPixels(0, py, bg, SCREEN_W, (mask.y0 - y0) * CH) end
        if y1 > mask.y1 then native.drawPixels(0, mask.y1 * CH, bg, SCREEN_W, (y1 - mask.y1) * CH) end
        local my0, my1 = math.max(y0, mask.y0), math.min(y1, mask.y1)
        local mpy, mph = (my0 - 1) * CH, (my1 - my0 + 1) * CH
        if mask.x0 > 1 then native.drawPixels(0, mpy, bg, (mask.x0 - 1) * CW, mph) end
        if mask.x1 < COLS then native.drawPixels(mask.x1 * CW, mpy, bg, (COLS - mask.x1) * CW, mph) end
    end

    function t.clear() eraseCursor(); fillRows(1, ROWS); drawCursor() end

    function t.clearLine()
        eraseCursor()
        if cy >= 1 and cy <= ROWS then fillRows(cy, cy) end
        drawCursor()
    end

    function t.getCursorPos() return cx, cy end
    function t.setCursorPos(x, y)
        eraseCursor()
        cx, cy = math.floor(x), math.floor(y)
        drawCursor()
    end
    function t.setCursorBlink(b)
        eraseCursor()
        blink = b and true or false
        drawCursor()
    end
    function t.getCursorBlink() return blink end
    function t.getSize() return COLS, ROWS end
    function t.isColor() return true end
    t.isColour = t.isColor

    function t.setTextColor(c) fg = colourIndex(c) end
    function t.setBackgroundColor(c) bg = colourIndex(c) end
    function t.getTextColor() return 2 ^ fg end
    function t.getBackgroundColor() return 2 ^ bg end
    t.setTextColour, t.setBackgroundColour = t.setTextColor, t.setBackgroundColor
    t.getTextColour, t.getBackgroundColour = t.getTextColor, t.getBackgroundColor

    -- Implemented honestly via a pixel read-back. Most UI code never scrolls,
    -- but `window.lua` and `print` do.
    function t.scroll(n)
        n = math.floor(n or 0)
        if n == 0 then return end
        eraseCursor()

        -- shift the shadow buffer by the same amount, blanking the new rows
        local blankCh, blankFg, blankBg
        for _ = 1, math.min(math.abs(n), ROWS) do
            if n > 0 then
                blankCh, blankFg, blankBg = table.remove(shCh, 1), table.remove(shFg, 1), table.remove(shBg, 1)
                shCh[#shCh + 1], shFg[#shFg + 1], shBg[#shBg + 1] = blankCh, blankFg, blankBg
            else
                blankCh, blankFg, blankBg = table.remove(shCh), table.remove(shFg), table.remove(shBg)
                table.insert(shCh, 1, blankCh); table.insert(shFg, 1, blankFg); table.insert(shBg, 1, blankBg)
            end
            for x = 1, COLS do blankCh[x], blankFg[x], blankBg[x] = 32, fg, bg end
        end

        local dy = math.abs(n) * CH
        if dy >= SCREEN_H then t.clear(); return end
        local srcY = n > 0 and dy or 0
        local dstY = n > 0 and 0 or dy
        local px = native.getPixels(0, srcY, SCREEN_W, SCREEN_H - dy)
        local rows = {}
        for r = 1, #px do
            local row = px[r]
            for i = 1, #row do if row[i] < 0 then row[i] = bg end end
            rows[r] = string.char(unpack_(row))
        end
        native.drawPixels(0, dstY, rows)
        local gapY = n > 0 and (SCREEN_H - dy) or 0
        native.drawPixels(0, gapY, bg, SCREEN_W, dy)
        drawCursor()
    end

    -- Callers speak CC colour values (or a packed RGB hex); the terminal in
    -- graphics mode wants indices.
    function t.setPaletteColor(c, r, g, b)
        local i = colourIndex(c)
        if type(r) == "number" and g == nil and b == nil then
            r, g, b = colours.unpackRGB(r)
        end
        native.setPaletteColor(i, r, g, b)
    end
    function t.getPaletteColor(c)
        return native.getPaletteColor(colourIndex(c))
    end
    t.setPaletteColour, t.getPaletteColour = t.setPaletteColor, t.getPaletteColor

    -- Present as a plain text terminal. See the header for why this must lie.
    -- Mode switching belongs to GfxTerm.enter/leave, never to a redirect user.
    function t.getGraphicsMode() return false end
    function t.setGraphicsMode() end

    -- Anything else the terminal offers - setFrozen, drawPixels, getPixels,
    -- showMouse - passes straight through, so code holding the redirect can
    -- still reach the pixel API.
    for k, v in pairs(native) do
        if t[k] == nil and type(v) == "function" then t[k] = v end
    end
    return t
end

return GfxTerm
