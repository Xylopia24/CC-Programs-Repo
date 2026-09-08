-- headless stand-in for term.native() with graphics mode 2
local function mockNative()
    local m = { calls = {}, mode = false, pal = {}, frozen = false, screen = {} }
    for k=0,15 do m.pal[k] = {k/15,k/15,k/15} end
    for y=0,224 do local r={} for x=0,479 do r[x]=15 end m.screen[y]=r end
    local function rec(name, ...) m.calls[#m.calls+1] = { name, ... } end
    function m.setGraphicsMode(mode) rec("setGraphicsMode", mode); if mode == 0 then m.mode = false else m.mode = mode end end
    function m.getGraphicsMode() return m.mode end
    function m.getSize(mode) if mode == 2 or mode == 1 then return 480, 225 end return 80, 25 end
    function m.setPaletteColor(i, r, g, b)
        assert(m.mode == 2, "setPaletteColor while not in mode 2 must use CC colour values")
        assert(type(i)=="number" and i>=0 and i<=255 and i==math.floor(i), "bad palette index "..tostring(i))
        m.pal[i] = {r,g,b}
    end
    m.setPaletteColour = m.setPaletteColor
    function m.getPaletteColor(i)
        if m.mode ~= 2 then -- CC colour value expected
            local k = math.log(i)/math.log(2); assert(math.abs(k-math.floor(k+0.5))<1e-9, "bad colour "..tostring(i))
            i = math.floor(k+0.5)
        end
        local c = m.pal[i] or {0,0,0}; return c[1],c[2],c[3]
    end
    m.getPaletteColour = m.getPaletteColor
    function m.setFrozen(b) m.frozen = b end
    function m.getFrozen() return m.frozen end
    function m.drawPixels(x, y, a, w, h)
        assert(m.mode == 2, "drawPixels outside mode 2")
        assert(x == math.floor(x) and y == math.floor(y) and x >= 0 and y >= 0, "bad origin "..x..","..y)
        if type(a) == "number" then
            assert(w and h and w>0 and h>0, "fill needs w,h")
            assert(x+w <= 480 and y+h <= 225, ("fill overflow %d,%d %dx%d"):format(x,y,w,h))
            rec("fill", x, y, a, w, h)
            for yy=y,y+h-1 do for xx=x,x+w-1 do m.screen[yy][xx]=a end end
        else
            assert(type(a)=="table" and #a>0, "rows must be a non-empty table")
            local len = #a[1]
            for r=1,#a do
                assert(type(a[r])=="string", "row "..r.." not a string")
                assert(#a[r]==len, "ragged rows")
            end
            assert(x+len <= 480, ("blit overflow x=%d len=%d"):format(x,len))
            assert(y+#a <= 225, ("blit overflow y=%d rows=%d"):format(y,#a))
            rec("blit", x, y, len, #a)
            for r=1,#a do local row=m.screen[y+r-1] for i=1,len do row[x+i-1]=a[r]:byte(i) end end
        end
    end
    function m.getPixels(x, y, w, h)
        local t={} for r=0,h-1 do local row={} for c=0,w-1 do local v=m.screen[y+r] and m.screen[y+r][x+c]; row[c+1]= v==nil and -1 or v end t[r+1]=row end return t
    end
    function m.clear() rec("nativeclear") end
    function m.write() rec("nativewrite") end
    function m.setCursorPos() end
    function m.showMouse() end
    return m
end

if not require then local mk = dofile("/rom/modules/main/cc/require.lua"); _G.require, _G.package = mk.make(_G, "/") end
return mockNative
