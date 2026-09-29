-- Events and the saved on/off switch. Each update runs in Try(), so a client
-- change shows one chat line instead of a Lua error on every plate.

local ADDON_NAME, ns = ...
local Health = ns.Health
local TITLE = "Deficit Plates"
local TAG = "|cff33ccff" .. TITLE .. ":|r "

-- Our text per Blizzard UnitFrame. Weak keys: Blizzard owns the frames and
-- reuses them for other units.
local texts = setmetatable({}, { __mode = "k" })
-- Nameplate unit token -> UnitFrame, while that plate is shown.
local frames = {}
local warned = {}
local lastError
local running = false
-- Replaced by the saved table on ADDON_LOADED.
local settings = { enabled = true }

local function Try(step, fn, ...)
    local ok, err = pcall(fn, ...)
    if ok then return end
    lastError = ("couldn't %s (%s)"):format(step, tostring(err))
    if warned[step] then return end
    warned[step] = true
    print(("|cffff8800%s:|r %s"):format(TITLE, lastError))
end

local function Refresh(uf, unit)
    local bar = uf.healthBar
    if not bar then return end
    local friend = Health.IsFriend(unit)
    if friend and not texts[uf] then texts[uf] = Health.CreateText(bar) end
    Health.Update(bar, texts[uf], unit, friend)
end

local function OnPlateAdded(unit)
    local plate = C_NamePlate.GetNamePlateForUnit(unit)
    if not plate or plate:IsForbidden() then return end
    local uf = plate.UnitFrame
    if not uf then return end
    frames[unit] = uf
    Try("show missing health", Refresh, uf, unit)
end

local function OnUnit(unit)
    local uf = frames[unit]
    if uf then Try("show missing health", Refresh, uf, unit) end
end

local EVENTS = {
    NAME_PLATE_UNIT_ADDED = OnPlateAdded,
    NAME_PLATE_UNIT_REMOVED = function(unit) frames[unit] = nil end,
    UNIT_HEALTH = OnUnit,
    UNIT_MAXHEALTH = OnUnit,
    UNIT_FACTION = OnUnit,
}

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:SetScript("OnEvent", function(_, event, ...)
    if event == "ADDON_LOADED" then
        if (...) ~= ADDON_NAME then return end
        eventFrame:UnregisterEvent("ADDON_LOADED")
        DeficitPlatesDB = DeficitPlatesDB or {}
        settings = DeficitPlatesDB
        if settings.enabled == nil then settings.enabled = true end
        if settings.enabled then
            running = true
            for name in pairs(EVENTS) do eventFrame:RegisterEvent(name) end
        end
        return
    end
    EVENTS[event](...)
end)

local function Say(msg) print(TAG .. msg) end

local function Has(api) return api and "yes" or "no" end

-- "shown", "hidden" or "?" for a widget. Guarded, because this client can
-- hide values from addons.
local function Visible(region)
    local ok, shown = pcall(function() return region:IsShown() and region:GetAlpha() > 0 end)
    if not ok then return "?" end
    return shown and "shown" or "hidden"
end

local function BlizzardTexts(bar)
    if not bar then return "none" end
    local seen
    for _, key in ipairs({ "LeftText", "RightText", "TextString" }) do
        local state = bar[key] and Visible(bar[key])
        if state == "shown" or state == "?" then return state end
        if state then seen = state end
    end
    return seen or "none"
end

local function Help()
    Say("commands")
    print("  /dp-help - show this list")
    print("  /dp-status - show what the addon found on this client")
    print("  /dp-on - show missing health on friendly plates (after /reload)")
    print("  /dp-off - leave Blizzard's nameplates alone (after /reload)")
end

local function Status()
    Say(("%s (saved setting: %s)"):format(running and "running" or "not running",
        settings.enabled and "on" or "off"))
    local count = 0
    for _ in pairs(texts) do count = count + 1 end
    print(("  friendly plates with missing health: %d"):format(count))
    print(("  UnitHealthMissing: %s, AbbreviateNumbers: %s"):format(
        Has(UnitHealthMissing), Has(AbbreviateNumbers)))
    local units = {}
    for unit in pairs(frames) do units[#units + 1] = unit end
    table.sort(units)
    for _, unit in ipairs(units) do
        local uf = frames[unit]
        local text = texts[uf]
        print(("  %s: %s, ours %s, Blizzard's %s"):format(unit,
            Health.IsFriend(unit) and "friend" or "not friend",
            text and Visible(text) or "none", BlizzardTexts(uf.healthBar)))
    end
    print("  last error: " .. (lastError or "none"))
end

-- Changes take effect on reload, so both directions ask for one.
local function Switch(on)
    return function()
        settings.enabled = on
        Say(("turned %s. Type /reload to apply."):format(on and "on" or "off"))
    end
end

SLASH_DPHELP1 = "/dp-help"
SlashCmdList.DPHELP = Help
SLASH_DPSTATUS1 = "/dp-status"
SlashCmdList.DPSTATUS = Status
SLASH_DPON1 = "/dp-on"
SlashCmdList.DPON = Switch(true)
SLASH_DPOFF1 = "/dp-off"
SlashCmdList.DPOFF = Switch(false)
