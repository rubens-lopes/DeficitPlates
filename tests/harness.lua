-- A stubbed WoW Forever client for Healer Plates tests.
-- Load() runs every file HealerPlates.toc lists, in order, against fake
-- APIs that behave like the 12.x engine: health values are secret (math,
-- comparison and tostring raise), and Blizzard's plate tables are
-- read-only (writing a field raises).

local M = {}
local ADDON_NAME = "HealerPlates"
M.FONT = "Fonts\\FRIZQT__.TTF"
M.FLAT = "Interface\\Buttons\\WHITE8X8"

-- Secret values -------------------------------------------------------------

local labels = setmetatable({}, { __mode = "k" })

-- What a test sees for a value that reached a widget: a secret's label, or
-- the plain value itself.
local function Label(v)
    if v ~= nil and labels[v] ~= nil then return labels[v] end
    return v
end
M.Label = Label

local function Secret(label)
    local proxy = newproxy(true)
    local mt = getmetatable(proxy)
    local function refuse() error("attempt to use a secret value (" .. label .. ")", 2) end
    for _, event in ipairs({ "__add", "__sub", "__mul", "__div", "__mod", "__pow", "__unm",
        "__lt", "__le", "__len", "__index", "__newindex", "__call", "__tostring" }) do
        mt[event] = refuse
    end
    -- The client lets a secret be joined to text; the result is secret too.
    mt.__concat = function(a, b)
        local function part(x)
            if labels[x] ~= nil then return labels[x] end
            if type(x) == "string" then return x end
            refuse()
        end
        return Secret(part(a) .. part(b))
    end
    labels[proxy] = label
    return proxy
end
M.Secret = Secret

-- Widgets -------------------------------------------------------------------

local fieldsOf = setmetatable({}, { __mode = "k" })

-- The writable fields behind a Blizzard widget, so tests can set state the
-- addon itself must not touch (a plate's unit, the forbidden flag).
function M.fields(w) return fieldsOf[w] or w end

local function Color(r, g, b, a)
    local s = ("%.2f,%.2f,%.2f"):format(r, g, b)
    if a ~= nil then s = s .. (",%.2f"):format(a) end
    return s
end

function M.rgb(r, g, b) return Color(r, g, b) end

-- A widget that records what the addon does to it. blizzard = true makes it
-- read-only, like the client's own frames.
local function Widget(name, kind, children, blizzard)
    local w = { id = name, kind = kind, points = {}, alpha = 1, created = {} }
    for k, v in pairs(children or {}) do w[k] = v end
    local function Make(childKind, layer)
        local child = Widget(name .. ":" .. childKind, childKind)
        child.layer = layer
        w.created[#w.created + 1] = child
        return child
    end
    function w.SetText(_, v) w.text = Label(v) end
    function w.SetFormattedText(_, fmt, ...)
        local parts = { fmt }
        for i = 1, select("#", ...) do parts[#parts + 1] = Label((select(i, ...))) end
        w.text = table.concat(parts, " <- ")
    end
    function w.SetAlpha(_, a) w.alpha = Label(a) end
    function w.SetFont(_, font, size, flags) w.font = ("%s,%d,%s"):format(font, size, flags or "") end
    function w.SetJustifyH(_, justify) w.justify = justify end
    function w.SetTextColor(_, r, g, b) w.textColor = Color(r, g, b) end
    function w.SetStatusBarTexture(_, texture) w.statusBarTexture = texture end
    function w.SetStatusBarColor(_, r, g, b) w.color = Color(r, g, b) end
    function w.SetTexture(_, texture) w.texture = texture end
    function w.SetColorTexture(_, r, g, b, a) w.colorTexture = Color(r, g, b, a) end
    function w.SetVertexColor(_, r, g, b, a) w.vertexColor = Color(r, g, b, a) end
    function w.SetHeight(_, height) w.height = height end
    function w.SetWidth(_, width) w.width = width end
    function w.ClearAllPoints() w.points = {} end
    function w.SetPoint(_, point, relativeTo, relativePoint, x, y)
        w.points[#w.points + 1] = { point, relativeTo, relativePoint, x or 0, y or 0 }
    end
    function w.IsForbidden() return w.forbidden == true end
    function w.CreateTexture(...) return Make("Texture", select(3, ...)) end
    function w.CreateFontString(...) return Make("FontString", select(3, ...)) end
    if not blizzard then return w end
    local proxy = setmetatable({}, {
        __index = w,
        __newindex = function(_, key)
            error(("wrote field %s onto Blizzard's %s"):format(tostring(key), name), 2)
        end,
    })
    fieldsOf[proxy] = w
    return proxy
end
M.Widget = Widget

local UNIT_FRAME_CHILDREN = { "name", "LevelFrame", "PlayerLevelDiffFrame", "ClassificationFrame",
    "RaidTargetFrame", "AurasFrame", "selectionHighlight", "aggroHighlight", "myHealPrediction",
    "otherHealPrediction", "totalAbsorb", "totalAbsorbOverlay", "myHealAbsorb", "overAbsorbGlow",
    "overHealAbsorbGlow" }
local BAR_CHILDREN = { "LeftText", "RightText", "TextString", "barTexture", "bgTexture" }

-- A Blizzard nameplate with the child layout the probe found. without:
-- children to leave out, e.g. { "healthBar", "bgTexture", "CastBarsContainer" }.
function M.Plate(without)
    local skip = {}
    for _, key in ipairs(without or {}) do skip[key] = true end
    local function Children(keys, prefix)
        local t = {}
        for _, key in ipairs(keys) do
            if not skip[key] then t[key] = Widget(prefix .. key, "Region", nil, true) end
        end
        return t
    end
    local children = Children(UNIT_FRAME_CHILDREN, "UnitFrame.")
    if not skip.healthBar then
        children.healthBar = Widget("healthBar", "StatusBar", Children(BAR_CHILDREN, "healthBar."), true)
    end
    if not skip.CastBarsContainer then
        children.CastBarsContainer = Widget("CastBarsContainer", "Frame",
            { castBar = Widget("castBar", "StatusBar", nil, true) }, true)
    end
    return Widget("plate", "Frame", { UnitFrame = Widget("UnitFrame", "Frame", children, true) }, true)
end

-- Our value FontString on a plate: the only FontString we create on the bar.
function M.value(uf)
    for _, w in ipairs(uf.healthBar.created) do
        if w.kind == "FontString" then return w end
    end
end

-- "POINT relativeTo RELPOINT x y" for a widget's nth anchor (default 1st).
function M.point(w, n)
    local p = w.points[n or 1]
    return ("%s %s %s %d %d"):format(p[1], p[2].id, p[3], p[4], p[5])
end

-- The client --------------------------------------------------------------

local function EventFrame()
    local f = { events = {}, scripts = {} }
    function f:RegisterEvent(event) self.events[event] = true end
    function f:UnregisterEvent(event) self.events[event] = nil end
    function f:SetScript(name, fn) self.scripts[name] = fn end
    return f
end

-- opts.saved            HealerPlatesDB as left by a previous session
-- opts.role             UnitGroupRolesAssigned("player") (default "NONE"); env.role changes it later
-- opts.remove           globals this client lacks, e.g. { "C_CurveUtil" }
-- opts.percentError     UnitHealthPercent(unit, false, ScaleTo100) raises this
-- opts.secretUnitState  UnitIsFriend, UnitReaction and UnitThreatSituation return secrets
function M.Load(opts)
    opts = opts or {}
    local env = { printed = {}, units = {}, plates = {}, hooked = {}, curves = {}, frames = {},
        role = opts.role or "NONE" }

    local G = setmetatable({}, { __index = _G })
    G._G = G
    G.print = function(...) env.printed[#env.printed + 1] = table.concat({ ... }, " ") end
    G.CreateFrame = function()
        local f = EventFrame()
        env.frames[#env.frames + 1] = f
        return f
    end
    G.SlashCmdList = {}
    G.HealerPlatesDB = opts.saved
    G.STANDARD_TEXT_FONT = M.FONT
    G.RAID_CLASS_COLORS = { MAGE = { r = 0.25, g = 0.78, b = 0.92 }, PRIEST = { r = 1, g = 1, b = 1 } }
    G.C_NamePlate = { GetNamePlateForUnit = function(unit) return env.plates[unit] end }

    local function Info(unit) return env.units[unit] or {} end
    G.UnitIsFriend = function(_, unit) return Info(unit).friend == true end
    G.UnitIsPlayer = function(unit) return Info(unit).player == true end
    G.UnitClass = function(unit)
        local class = Info(unit).class
        return class and class:lower(), class
    end
    G.UnitReaction = function(unit) return Info(unit).reaction end
    G.UnitIsTapDenied = function(unit) return Info(unit).tapped == true end
    G.UnitThreatSituation = function(_, unit) return Info(unit).threat end
    G.UnitGroupRolesAssigned = function() return env.role end
    -- The client's check for secret values; code uses it to fall back safely.
    G.issecretvalue = function(v) return v ~= nil and labels[v] ~= nil end
    if opts.secretUnitState then
        G.UnitGroupRolesAssigned = function() return Secret("role") end
        G.UnitIsFriend = function(_, unit) return Secret("friend:" .. unit) end
        G.UnitReaction = function(unit) return Secret("reaction:" .. unit) end
        G.UnitThreatSituation = function(_, unit) return Secret("threat:" .. unit) end
    end

    G.UnitHealth = function(unit) return Secret("health:" .. unit) end
    G.UnitHealthMax = function(unit) return Secret("max:" .. unit) end
    G.UnitHealthMissing = function(unit) return Secret("missing:" .. unit) end
    G.AbbreviateNumbers = function(v) return Secret("abbr(" .. Label(v) .. ")") end
    local scaleTo100 = { "ScaleTo100" }
    G.CurveConstants = { ScaleTo100 = scaleTo100 }
    G.C_CurveUtil = { CreateCurve = function()
        local curve = { points = {} }
        function curve:AddPoint(x, y) self.points[#self.points + 1] = x .. "=" .. y end
        env.curves[#env.curves + 1] = curve
        return curve
    end }
    G.UnitHealthPercent = function(unit, _, curve)
        if curve == scaleTo100 then
            if opts.percentError then error(opts.percentError, 0) end
            return Secret("percent:" .. unit)
        end
        for i, c in ipairs(env.curves) do
            if c == curve then return Secret("curve" .. i .. ":" .. unit) end
        end
        error("UnitHealthPercent: not a curve", 2)
    end

    -- Blizzard's own updates, which the addon hooks. Each applies Blizzard's
    -- look first, the way the client does.
    G.CompactUnitFrame_UpdateHealthColor = function(frame) frame.healthBar:SetStatusBarColor(0, 1, 0) end
    G.CompactUnitFrame_UpdateName = function(frame)
        frame.name:SetFont("blizzard", 12, "")
        frame.name:SetTextColor(1, 1, 0)
        frame.name:ClearAllPoints()
        frame.name:SetPoint("CENTER", frame, "CENTER", 0, 0)
    end
    G.hooksecurefunc = function(name, fn)
        local original = G[name]
        env.hooked[name] = true
        G[name] = function(...)
            original(...)
            fn(...)
        end
    end

    for _, name in ipairs(opts.remove or {}) do G[name] = nil end
    env.stubs = {}
    for k in pairs(G) do env.stubs[k] = true end

    local ns = {}
    for line in io.lines("HealerPlates.toc") do
        local file = line:match("^([^#%s].-)%s*$")
        if file then
            local chunk = assert(loadfile(file))
            setfenv(chunk, G)
            chunk(ADDON_NAME, ns)
        end
    end
    env.ns, env.globals, env.frame = ns, G, env.frames[1]

    function env.fire(event, ...)
        local f = env.frame
        if f and f.events[event] then f.scripts.OnEvent(f, event, ...) end
    end
    -- Runs a slash command the way the chat box does: look up SLASH_<KEY>n.
    function env.slash(text)
        local cmd, rest = text:match("^(%S+)%s*(.-)$")
        for key, fn in pairs(G.SlashCmdList) do
            local i = 1
            while rawget(G, "SLASH_" .. key .. i) do
                if rawget(G, "SLASH_" .. key .. i) == cmd then return fn(rest) end
                i = i + 1
            end
        end
        error("unknown slash command " .. cmd, 2)
    end
    -- Shows a plate for unit the way the client does: assign it, then fire.
    -- info: friend, player, class, reaction, tapped, threat (copied).
    function env.show(unit, info, plate)
        plate = plate or M.Plate()
        local copy = {}
        for k, v in pairs(info or {}) do copy[k] = v end
        env.units[unit] = copy
        env.plates[unit] = plate
        M.fields(plate.UnitFrame).unit = unit
        env.fire("NAME_PLATE_UNIT_ADDED", unit)
        return plate.UnitFrame
    end
    function env.hide(unit)
        env.fire("NAME_PLATE_UNIT_REMOVED", unit)
        env.plates[unit] = nil
    end

    env.fire("ADDON_LOADED", "SomeOtherAddon")
    env.fire("ADDON_LOADED", ADDON_NAME)
    return env
end

function M.eq(actual, expected, what)
    if actual ~= expected then
        error(("%s: expected %s, got %s"):format(what, tostring(Label(expected)), tostring(Label(actual))), 2)
    end
end

function M.run(tests)
    local failed = 0
    for _, t in ipairs(tests) do
        local ok, err = pcall(t.fn)
        if ok then
            print("PASS  " .. t.name)
        else
            failed = failed + 1
            print("FAIL  " .. t.name .. "\n      " .. tostring(err))
        end
    end
    print(("%d passed, %d failed"):format(#tests - failed, failed))
    os.exit(failed == 0 and 0 or 1)
end

return M
