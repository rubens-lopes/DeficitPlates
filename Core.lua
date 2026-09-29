-- Events, hooks and the saved on/off switch. Every per-plate step runs in
-- Try(), so a client change shows one chat line instead of a Lua error on
-- every plate.

local ADDON_NAME, ns = ...
local Colors, Health, Style = ns.Colors, ns.Health, ns.Style
local TITLE = "Healer Plates"

-- Our state per Blizzard UnitFrame (value text, border). Weak keys: Blizzard
-- owns the frames and reuses them for other units.
local states = setmetatable({}, { __mode = "k" })
-- Nameplate unit token -> UnitFrame, while that plate is shown.
local frames = {}
-- Hook name -> true once installed.
local installed = {} -- luacheck: ignore 241
local warned = {}
local running = false -- luacheck: ignore 231
-- Replaced by the saved table on ADDON_LOADED.
local settings = { enabled = true }

local function Try(step, fn, ...)
    local ok, err = pcall(fn, ...)
    if ok or warned[step] then return end
    warned[step] = true
    print(("|cffff8800%s:|r couldn't %s (%s)"):format(TITLE, step, tostring(err)))
end

local function Rename(uf, unit)
    Style.Name(uf, Colors.Name(Colors.Info(unit)))
end

local function Recolor(uf, unit)
    if uf.healthBar then uf.healthBar:SetStatusBarColor(Colors.Bar(Colors.Info(unit))) end
end

local function ShowHealth(uf, unit)
    local value = states[uf].value
    if not value then return end
    Style.HideBarTexts(uf)
    Health.Update(value, unit, UnitIsFriend("player", unit) == true)
end

local function Setup(uf)
    local state = Style.Create(uf)
    states[uf] = state
    Style.Apply(uf, state)
end

local function OnPlateAdded(unit)
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if not plate or plate:IsForbidden() then return end
    local uf = plate.UnitFrame
    if not uf then return end
    if not states[uf] then Try("style a plate", Setup, uf) end
    if not states[uf] then return end
    frames[unit] = uf
    Try("style a name", Rename, uf, unit)
    Try("show health", ShowHealth, uf, unit)
    Try("color a bar", Recolor, uf, unit)
end

local function OnHealth(unit)
    local uf = frames[unit]
    if uf then Try("show health", ShowHealth, uf, unit) end
end

local function RecolorAll()
    for unit, uf in pairs(frames) do Try("color a bar", Recolor, uf, unit) end
end

local EVENTS = {
    NAME_PLATE_UNIT_ADDED = OnPlateAdded,
    NAME_PLATE_UNIT_REMOVED = function(unit) frames[unit] = nil end,
    UNIT_HEALTH = OnHealth,
    UNIT_MAXHEALTH = OnHealth,
    UNIT_THREAT_LIST_UPDATE = function(unit)
        local uf = frames[unit]
        if uf then Try("color a bar", Recolor, uf, unit) else RecolorAll() end
    end,
    UNIT_THREAT_SITUATION_UPDATE = RecolorAll,
    PLAYER_ROLES_ASSIGNED = RecolorAll,
}

-- Blizzard recolours and renames plates on its own schedule; these put our
-- look back on top. Frames we never styled (raid frames) are skipped.
local HOOKS = {
    { name = "CompactUnitFrame_UpdateHealthColor", fn = function(frame)
        if states[frame] and frame.unit then Try("color a bar", Recolor, frame, frame.unit) end
    end },
    { name = "CompactUnitFrame_UpdateName", fn = function(frame)
        if states[frame] and frame.unit then Try("style a name", Rename, frame, frame.unit) end
    end },
}

local eventFrame = CreateFrame("Frame")

local function Start()
    running = true
    for event in pairs(EVENTS) do eventFrame:RegisterEvent(event) end
    for _, hook in ipairs(HOOKS) do
        if type(_G[hook.name]) == "function" then
            hooksecurefunc(hook.name, hook.fn)
            installed[hook.name] = true
        end
    end
end

eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if (...) ~= ADDON_NAME then return end
        eventFrame:UnregisterEvent("ADDON_LOADED")
        HealerPlatesDB = HealerPlatesDB or {}
        settings = HealerPlatesDB
        if settings.enabled == nil then settings.enabled = true end
        if settings.enabled then Start() end
        return
    end
    EVENTS[event](...)
end)
