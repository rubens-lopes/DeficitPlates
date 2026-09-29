-- Plater-like layout for a Blizzard plate. Only widget methods are called
-- on Blizzard's objects; nothing is written into their tables, and every
-- child is looked up defensively because the client can change them.

local _, ns = ...
local Style = {}
ns.Style = Style

local FLAT = "Interface\\Buttons\\WHITE8X8"
local FONT_SIZE = 10
local GAP = 2

local HIDDEN = { "LevelFrame", "PlayerLevelDiffFrame", "ClassificationFrame" }
local BAR_TEXTS = { "LeftText", "RightText", "TextString" }
local PREDICTION = {
    myHealPrediction = { 0.0, 0.9, 0.4, 0.8 },
    otherHealPrediction = { 0.0, 0.6, 0.3, 0.8 },
    totalAbsorb = { 1, 1, 1, 0.6 },
    myHealAbsorb = { 0.6, 0.0, 0.0, 0.7 },
}

-- Our own widgets on a plate: the value text and a 1px border. Returns the
-- state table Core keeps for this UnitFrame.
function Style.Create(uf)
    local bar = uf.healthBar
    if not bar then return {} end
    local value = bar:CreateFontString(nil, "OVERLAY")
    value:SetFont(STANDARD_TEXT_FONT, FONT_SIZE, "OUTLINE")
    value:SetPoint("RIGHT", bar, "RIGHT", -3, 0)
    value:SetJustifyH("RIGHT")
    local function Edge(point1, x1, y1, point2, x2, y2)
        local edge = bar:CreateTexture(nil, "OVERLAY")
        edge:SetColorTexture(0, 0, 0, 1)
        edge:SetPoint(point1, bar, point1, x1, y1)
        edge:SetPoint(point2, bar, point2, x2, y2)
        return edge
    end
    local top = Edge("TOPLEFT", -1, 1, "TOPRIGHT", 1, 1)
    top:SetHeight(1)
    local bottom = Edge("BOTTOMLEFT", -1, -1, "BOTTOMRIGHT", 1, -1)
    bottom:SetHeight(1)
    local left = Edge("TOPLEFT", -1, 1, "BOTTOMLEFT", -1, -1)
    left:SetWidth(1)
    local right = Edge("TOPRIGHT", 1, 1, "BOTTOMRIGHT", 1, -1)
    right:SetWidth(1)
    return { value = value, border = { top, bottom, left, right } }
end

-- One-time restyle of Blizzard's children.
function Style.Apply(uf, state)
    local bar = uf.healthBar
    if bar then
        bar:SetStatusBarTexture(FLAT)
        if bar.bgTexture then
            bar.bgTexture:SetTexture(FLAT)
            bar.bgTexture:SetVertexColor(0, 0, 0, 0.6)
        end
    end
    for _, key in ipairs(HIDDEN) do
        if uf[key] then uf[key]:SetAlpha(0) end
    end
    for key, c in pairs(PREDICTION) do
        local texture = uf[key]
        if texture then
            texture:SetTexture(FLAT)
            texture:SetVertexColor(c[1], c[2], c[3], c[4])
        end
    end
    if uf.AurasFrame and uf.name then
        uf.AurasFrame:ClearAllPoints()
        uf.AurasFrame:SetPoint("BOTTOMLEFT", uf.name, "TOPLEFT", 0, GAP)
    end
    local castBar = uf.castBar or (uf.CastBarsContainer and uf.CastBarsContainer.castBar)
    if castBar then castBar:SetStatusBarTexture(FLAT) end
    state.castBar = castBar ~= nil
end

-- Name font, colour and position. Runs on every plate update and after
-- Blizzard's own name update, which resets them.
function Style.Name(uf, r, g, b)
    local name, bar = uf.name, uf.healthBar
    if not name then return end
    name:SetFont(STANDARD_TEXT_FONT, FONT_SIZE, "OUTLINE")
    name:SetTextColor(r, g, b)
    name:SetJustifyH("LEFT")
    if bar then
        name:ClearAllPoints()
        name:SetPoint("BOTTOMLEFT", bar, "TOPLEFT", 0, GAP)
    end
end

-- Blizzard's bar texts stay invisible. Alpha, not Hide(): Blizzard calls Show().
function Style.HideBarTexts(uf)
    local bar = uf.healthBar
    if not bar then return end
    for _, key in ipairs(BAR_TEXTS) do
        if bar[key] then bar[key]:SetAlpha(0) end
    end
end
