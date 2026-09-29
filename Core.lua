-- Events and the saved on/off switch. Each update runs in Try(), so a client
-- change shows one chat line instead of a Lua error on every plate.

local ADDON_NAME, ns = ...
local Health = ns.Health
local TITLE = "Healer Plates"
local TAG = "|cff33ccff" .. TITLE .. ":|r "

-- Our text per Blizzard UnitFrame. Weak keys: Blizzard owns the frames and
-- reuses them for other units.
local texts = setmetatable({}, { __mode = "k" })
-- Nameplate unit token -> UnitFrame, while that plate is shown.
local frames = {}
local warned = {}
local running = false
-- Replaced by the saved table on ADDON_LOADED.
local settings = { enabled = true }

local function Try(step, fn, ...)
    local ok, err = pcall(fn, ...)
    if ok or warned[step] then return end
    warned[step] = true
    print(("|cffff8800%s:|r couldn't %s (%s)"):format(TITLE, step, tostring(err)))
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
        HealerPlatesDB = HealerPlatesDB or {}
        settings = HealerPlatesDB
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

local function Help()
    Say("commands")
    print("  /hp-help - show this list")
    print("  /hp-status - show what the addon found on this client")
    print("  /hp-on - show missing health on friendly plates (after /reload)")
    print("  /hp-off - leave Blizzard's nameplates alone (after /reload)")
end

local function Status()
    Say(("%s (saved setting: %s)"):format(running and "running" or "not running",
        settings.enabled and "on" or "off"))
    local count = 0
    for _ in pairs(texts) do count = count + 1 end
    print(("  friendly plates with missing health: %d"):format(count))
    print(("  UnitHealthMissing: %s, AbbreviateNumbers: %s"):format(
        Has(UnitHealthMissing), Has(AbbreviateNumbers)))
end

-- Changes take effect on reload, so both directions ask for one.
local function Switch(on)
    return function()
        settings.enabled = on
        Say(("turned %s. Type /reload to apply."):format(on and "on" or "off"))
    end
end

SLASH_HPHELP1 = "/hp-help"
SlashCmdList.HPHELP = Help
SLASH_HPSTATUS1 = "/hp-status"
SlashCmdList.HPSTATUS = Status
SLASH_HPON1 = "/hp-on"
SlashCmdList.HPON = Switch(true)
SLASH_HPOFF1 = "/hp-off"
SlashCmdList.HPOFF = Switch(false)
