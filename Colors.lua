-- Bar and name colours. Bar() and Name() take plain values only (never
-- health), so it's safe to branch on everything they see.

local _, ns = ...
local Colors = {}
ns.Colors = Colors

local FRIENDLY_NPC = { 0.2, 0.8, 0.2 }
local HOSTILE = { 0.85, 0.2, 0.2 }
local NEUTRAL = { 0.9, 0.8, 0.2 }
local TAPPED = { 0.5, 0.5, 0.5 }
local YELLOW = { 1.0, 0.9, 0.0 }
local ORANGE = { 1.0, 0.5, 0.0 }
local MAGENTA = { 1.0, 0.2, 0.8 }
local WHITE = { 1, 1, 1 }

-- UnitThreatSituation -> colour. A missing entry keeps the base colour.
local THREAT = {
    dps = { [1] = YELLOW, [2] = ORANGE, [3] = MAGENTA },
    tank = { [0] = ORANGE, [1] = YELLOW, [2] = YELLOW },
}

local function ClassColor(class)
    local c = class and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
    if c then return { c.r, c.g, c.b } end
end

-- Everything Bar() and Name() need. None of these APIs return health.
function Colors.Info(unit)
    local _, class = UnitClass(unit)
    return {
        friend = UnitIsFriend("player", unit) == true,
        player = UnitIsPlayer(unit) == true,
        class = class,
        reaction = UnitReaction(unit, "player"),
        tapped = UnitIsTapDenied(unit) == true,
        threat = UnitThreatSituation("player", unit),
        tank = UnitGroupRolesAssigned ~= nil and UnitGroupRolesAssigned("player") == "TANK",
    }
end

function Colors.Bar(info)
    if info.tapped then return unpack(TAPPED) end
    local base = info.player and ClassColor(info.class)
    if not base then
        if info.friend then
            base = FRIENDLY_NPC
        elseif info.reaction == 4 then
            base = NEUTRAL
        else
            base = HOSTILE
        end
    end
    if not info.friend and info.threat ~= nil then
        local override = THREAT[info.tank and "tank" or "dps"][info.threat]
        if override then return unpack(override) end
    end
    return unpack(base)
end

function Colors.Name(info)
    local c = info.friend and info.player and ClassColor(info.class)
    return unpack(c or WHITE)
end
