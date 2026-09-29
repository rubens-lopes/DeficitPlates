-- Missing health on friendly plates, in place of Blizzard's health number.
-- Everything else on the plate stays Blizzard's. Health values are secret on
-- this client: they go straight into widget calls and are never compared or
-- used in math. Only widget methods are called on Blizzard's objects.

local _, ns = ...
local Health = {}
ns.Health = Health

local BLIZZARD_TEXTS = { "LeftText", "RightText", "TextString" }

-- Unit state can be secret too (inside instances, for example). Comparing a
-- secret raises, so treat it as unknown.
local function Plain(v)
    if issecretvalue and issecretvalue(v) then return nil end
    return v
end

function Health.IsFriend(unit)
    return Plain(UnitIsFriend("player", unit)) == true
end

-- Our text, in the spot and font of Blizzard's health number.
function Health.CreateText(bar)
    local text = bar:CreateFontString(nil, "OVERLAY")
    local source = bar.RightText or bar.TextString
    local font, size, flags
    if source then font, size, flags = source:GetFont() end
    text:SetFont(font or STANDARD_TEXT_FONT, size or 10, flags or "OUTLINE")
    text:SetPoint("RIGHT", bar, "RIGHT", -3, 0)
    text:SetJustifyH("RIGHT")
    return text
end

-- Friends: Blizzard's health number hidden, ours shows missing health.
-- Everyone else: Blizzard's number back, ours hidden. Alpha, not Hide(),
-- because Blizzard calls Show() on its texts.
function Health.Update(bar, text, unit, friend)
    for _, key in ipairs(BLIZZARD_TEXTS) do
        if bar[key] then bar[key]:SetAlpha(friend and 0 or 1) end
    end
    if not text then return end
    if not friend then
        text:SetAlpha(0)
        return
    end
    text:SetText("-" .. AbbreviateNumbers(UnitHealthMissing(unit)))
    text:SetAlpha(1)
end
