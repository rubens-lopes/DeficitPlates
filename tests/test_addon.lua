-- Healer Plates unit tests. Run from the repo root: luajit tests/test_addon.lua
package.path = "tests/?.lua;" .. package.path
local T = require("harness")
local Load, eq, rgb = T.Load, T.eq, T.rgb

local tests = {}
local function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end

local MAGE = "0.25,0.78,0.92"
local GREEN = "0.20,0.80,0.20"
local RED = "0.85,0.20,0.20"
local NEUTRAL = "0.90,0.80,0.20"
local GREY = "0.50,0.50,0.50"
local YELLOW = "1.00,0.90,0.00"
local ORANGE = "1.00,0.50,0.00"
local MAGENTA = "1.00,0.20,0.80"
local WHITE = "1.00,1.00,1.00"

-- Harness ---------------------------------------------------------------------

test("the fake client refuses math, comparison and tostring on health", function()
    local G = Load().globals
    local checks = {
        math = function() return G.UnitHealthMissing("nameplate1") + 1 end,
        compare = function() return G.UnitHealthMissing("nameplate1") > 0 end,
        tostring = function() return tostring(G.UnitHealthMissing("nameplate1")) end,
    }
    for what, fn in pairs(checks) do eq(pcall(fn), false, what) end
end)

test("the fake client refuses writes onto Blizzard's plate tables", function()
    local plate = T.Plate()
    eq(pcall(function() plate.UnitFrame.healthBar.mine = true end), false, "write")
end)

test("defines only its saved variable and slash commands as globals", function()
    local env = Load()
    local names = {}
    for k in pairs(env.globals) do
        if not env.stubs[k] and k ~= "HealerPlatesDB" and not k:match("^SLASH_HP") then
            names[#names + 1] = k
        end
    end
    table.sort(names)
    eq(table.concat(names, ","), "", "new globals")
end)

-- Colors ----------------------------------------------------------------------

test("bar colour: class for players, reaction for NPCs", function()
    local C = Load().ns.Colors
    eq(rgb(C.Bar({ friend = true, player = true, class = "MAGE" })), MAGE, "friendly player")
    eq(rgb(C.Bar({ friend = true })), GREEN, "friendly NPC")
    eq(rgb(C.Bar({ player = true, class = "MAGE", reaction = 2 })), MAGE, "enemy player")
    eq(rgb(C.Bar({ reaction = 2 })), RED, "hostile NPC")
    eq(rgb(C.Bar({ reaction = 4 })), NEUTRAL, "neutral NPC")
    eq(rgb(C.Bar({ friend = true, player = true, class = "NOPE" })), GREEN, "friendly player, unknown class")
end)

test("threat colours for a non-tank and a tank", function()
    local C = Load().ns.Colors
    local want = { dps = { RED, YELLOW, ORANGE, MAGENTA }, tank = { ORANGE, YELLOW, YELLOW, RED } }
    for role, colors in pairs(want) do
        for situation = 0, 3 do
            eq(rgb(C.Bar({ reaction = 2, threat = situation, tank = role == "tank" })),
                colors[situation + 1], role .. " situation " .. situation)
        end
    end
    eq(rgb(C.Bar({ reaction = 2 })), RED, "no threat keeps the base colour")
end)

test("tapped is grey whatever the threat; friends ignore threat", function()
    local C = Load().ns.Colors
    eq(rgb(C.Bar({ reaction = 2, tapped = true, threat = 3 })), GREY, "tapped")
    eq(rgb(C.Bar({ friend = true, threat = 3 })), GREEN, "friend with threat")
end)

test("name colour: class for friendly players, white otherwise", function()
    local C = Load().ns.Colors
    eq(rgb(C.Name({ friend = true, player = true, class = "MAGE" })), MAGE, "friendly player")
    eq(rgb(C.Name({ player = true, class = "MAGE", reaction = 2 })), WHITE, "enemy player")
    eq(rgb(C.Name({ friend = true })), WHITE, "friendly NPC")
    eq(rgb(C.Name({ friend = true, player = true, class = "NOPE" })), WHITE, "unknown class")
end)

test("Info reads plain unit state from the client", function()
    local env = Load({ role = "TANK" })
    env.units.nameplate1 = { player = true, class = "MAGE", reaction = 2, threat = 3 }
    local info = env.ns.Colors.Info("nameplate1")
    eq(info.friend, false, "friend")
    eq(info.player, true, "player")
    eq(info.class, "MAGE", "class")
    eq(info.reaction, 2, "reaction")
    eq(info.tapped, false, "tapped")
    eq(info.threat, 3, "threat")
    eq(info.tank, true, "tank")
    env.role = "HEALER"
    eq(env.ns.Colors.Info("nameplate1").tank, false, "healer is not a tank")
end)

-- Health ----------------------------------------------------------------------

test("friendly plates show missing health, hidden at full health", function()
    local env = Load()
    local text = T.Widget("value", "FontString")
    env.ns.Health.Update(text, "nameplate1", true)
    eq(text.text, "-abbr(missing:nameplate1)", "text")
    eq(text.alpha, "curve1:nameplate1", "alpha comes from the full-health curve")
    eq(table.concat(env.curves[1].points, " "), "0=1 0.999=1 1=0", "curve points")
end)

test("the full-health curve is built once", function()
    local env = Load()
    local text = T.Widget("value", "FontString")
    env.ns.Health.Update(text, "nameplate1", true)
    env.ns.Health.Update(text, "nameplate2", true)
    eq(#env.curves, 1, "curves built")
    eq(text.alpha, "curve1:nameplate2", "same curve, new unit")
end)

test("enemy plates show health percent at full alpha", function()
    local env = Load()
    local text = T.Widget("value", "FontString")
    env.ns.Health.Update(text, "nameplate2", false)
    eq(text.text, "%d%% <- percent:nameplate2", "text")
    eq(text.alpha, 1, "alpha")
end)

test("a text reused from a friend to an enemy gets full alpha back", function()
    local env = Load()
    local text = T.Widget("value", "FontString")
    env.ns.Health.Update(text, "nameplate1", true)
    env.ns.Health.Update(text, "nameplate1", false)
    eq(text.alpha, 1, "alpha")
    eq(text.text, "%d%% <- percent:nameplate1", "text")
end)

test("a failing enemy percent hides the text, raises once, then stays quiet", function()
    local env = Load({ percentError = "blocked" })
    local H = env.ns.Health
    local text = T.Widget("value", "FontString")
    local ok, err = pcall(H.Update, text, "nameplate1", false)
    eq(ok, false, "first call raises")
    eq(err, "blocked", "error")
    eq(text.alpha, 0, "hidden")
    eq(H.percentError, "blocked", "remembered")
    eq((pcall(H.Update, text, "nameplate2", false)), true, "second call is silent")
    eq(text.alpha, 0, "still hidden")
    H.Update(text, "nameplate3", true)
    eq(text.text, "-abbr(missing:nameplate3)", "friends still work")
end)

-- Style -----------------------------------------------------------------------

test("Create adds our value text and a 1px black border to the bar", function()
    local S = Load().ns.Style
    local uf = T.Plate().UnitFrame
    local state = S.Create(uf)
    eq(state.value.font, T.FONT .. ",10,OUTLINE", "value font")
    eq(T.point(state.value), "RIGHT healthBar RIGHT -3 0", "value anchor")
    eq(state.value.justify, "RIGHT", "value justify")
    eq(#state.border, 4, "border edges")
    for i, edge in ipairs(state.border) do
        eq(edge.colorTexture, "0.00,0.00,0.00,1.00", "edge " .. i .. " colour")
        eq(#edge.points, 2, "edge " .. i .. " anchors")
    end
    eq(T.point(state.border[1], 1), "TOPLEFT healthBar TOPLEFT -1 1", "top edge")
    eq(state.border[1].height, 1, "top edge height")
    eq(state.border[3].width, 1, "left edge width")
    eq(#uf.healthBar.created, 5, "widgets made on the bar")
end)

test("Apply flattens the bar, hides level and classification, moves auras", function()
    local S = Load().ns.Style
    local uf = T.Plate().UnitFrame
    local state = S.Create(uf)
    S.Apply(uf, state)
    eq(uf.healthBar.statusBarTexture, T.FLAT, "bar texture")
    eq(uf.healthBar.bgTexture.texture, T.FLAT, "background texture")
    eq(uf.healthBar.bgTexture.vertexColor, "0.00,0.00,0.00,0.60", "background colour")
    for _, key in ipairs({ "LevelFrame", "PlayerLevelDiffFrame", "ClassificationFrame" }) do
        eq(uf[key].alpha, 0, key)
    end
    eq(uf.RaidTargetFrame.alpha, 1, "raid marker kept")
    eq(uf.selectionHighlight.alpha, 1, "target highlight kept")
    eq(T.point(uf.AurasFrame), "BOTTOMLEFT UnitFrame.name TOPLEFT 0 2", "auras above the name")
    eq(#uf.AurasFrame.points, 1, "auras cleared first")
    eq(uf.CastBarsContainer.castBar.statusBarTexture, T.FLAT, "cast bar texture")
    eq(state.castBar, true, "cast bar found")
end)

test("heal prediction and absorbs are recoloured, the shimmer is kept", function()
    local S = Load().ns.Style
    local uf = T.Plate().UnitFrame
    S.Apply(uf, S.Create(uf))
    local want = {
        myHealPrediction = "0.00,0.90,0.40,0.80",
        otherHealPrediction = "0.00,0.60,0.30,0.80",
        totalAbsorb = "1.00,1.00,1.00,0.60",
        myHealAbsorb = "0.60,0.00,0.00,0.70",
    }
    for key, color in pairs(want) do
        eq(uf[key].texture, T.FLAT, key .. " texture")
        eq(uf[key].vertexColor, color, key .. " colour")
    end
    eq(uf.totalAbsorbOverlay.texture, nil, "shimmer untouched")
end)

test("Name sets font, colour and position above the bar", function()
    local S = Load().ns.Style
    local uf = T.Plate().UnitFrame
    S.Name(uf, 0.25, 0.78, 0.92)
    eq(uf.name.font, T.FONT .. ",10,OUTLINE", "font")
    eq(uf.name.textColor, MAGE, "colour")
    eq(uf.name.justify, "LEFT", "justify")
    eq(#uf.name.points, 1, "one anchor")
    eq(T.point(uf.name), "BOTTOMLEFT healthBar TOPLEFT 0 2", "anchor")
end)

test("HideBarTexts hides Blizzard's bar texts only", function()
    local S = Load().ns.Style
    local uf = T.Plate().UnitFrame
    S.HideBarTexts(uf)
    for _, key in ipairs({ "LeftText", "RightText", "TextString" }) do
        eq(uf.healthBar[key].alpha, 0, key)
    end
    eq(uf.healthBar.barTexture.alpha, 1, "bar texture kept")
end)

test("a plate missing children is styled without errors", function()
    local S = Load().ns.Style
    local bare = T.Plate({ "healthBar", "name", "LevelFrame", "PlayerLevelDiffFrame",
        "ClassificationFrame", "AurasFrame", "CastBarsContainer", "myHealPrediction",
        "otherHealPrediction", "totalAbsorb", "myHealAbsorb" }).UnitFrame
    local state = S.Create(bare)
    S.Apply(bare, state)
    S.Name(bare, 1, 1, 1)
    S.HideBarTexts(bare)
    eq(state.value, nil, "no value text without a bar")
    eq(state.castBar, false, "no cast bar")
    local noTexts = T.Plate({ "bgTexture", "LeftText", "RightText", "TextString" }).UnitFrame
    S.Apply(noTexts, S.Create(noTexts))
    S.HideBarTexts(noTexts)
    local noName = T.Plate({ "name" }).UnitFrame
    S.Apply(noName, S.Create(noName))
    eq(#noName.AurasFrame.points, 0, "auras left alone without a name to anchor to")
end)

-- Runner (keep last) ------------------------------------------------------------

T.run(tests)
