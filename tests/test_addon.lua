-- Healer Plates unit tests. Run from the repo root: luajit tests/test_addon.lua
package.path = "tests/?.lua;" .. package.path
local T = require("harness")
local Load, eq = T.Load, T.eq

local tests = {}
local function test(name, fn) tests[#tests + 1] = { name = name, fn = fn } end

local FRIEND = { friend = true, player = true, class = "MAGE", reaction = 5 }
local ENEMY = { reaction = 2 }
local BLIZZARD_TEXTS = { "LeftText", "RightText", "TextString" }

local function ourText(uf) return T.value(uf) end

local function blizzardTextAlphas(uf)
    local out = {}
    for _, key in ipairs(BLIZZARD_TEXTS) do out[#out + 1] = tostring(uf.healthBar[key].alpha) end
    return table.concat(out, ",")
end

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

-- Friendly plates -------------------------------------------------------------

test("a friendly plate shows missing health in place of Blizzard's number", function()
    local env = Load()
    local uf = env.show("nameplate1", FRIEND)
    local text = ourText(uf)
    eq(text.text, "-abbr(missing:nameplate1)", "text")
    eq(text.alpha, 1, "visible, -0 at full health included")
    eq(blizzardTextAlphas(uf), "0,0,0", "Blizzard's health texts hidden")
end)

test("the missing-health text uses Blizzard's font and sits right inside the bar", function()
    local env = Load()
    local uf = env.show("nameplate1", FRIEND)
    local text = ourText(uf)
    eq(text.font, "Fonts\\BLIZZ.TTF,9,OUTLINE", "Blizzard's health text font")
    eq(T.point(text), "RIGHT healthBar RIGHT -3 0", "anchor")
    eq(text.justify, "RIGHT", "justify")
end)

test("nothing else on the plate is touched", function()
    local env = Load()
    local uf = env.show("nameplate1", FRIEND)
    eq(uf.healthBar.statusBarTexture, nil, "bar texture")
    eq(uf.healthBar.color, nil, "bar colour")
    eq(uf.name.font, nil, "name font")
    eq(uf.name.textColor, nil, "name colour")
    eq(#uf.name.points, 0, "name position")
    eq(#uf.AurasFrame.points, 0, "auras position")
    eq(uf.LevelFrame.alpha, 1, "level")
    eq(uf.myHealPrediction.vertexColor, nil, "heal prediction")
    eq(uf.CastBarsContainer.castBar.statusBarTexture, nil, "cast bar")
    eq(#uf.healthBar.created, 1, "only our one text is created")
end)

-- Enemy plates ----------------------------------------------------------------

test("enemy plates are left fully to Blizzard", function()
    local env = Load()
    local uf = env.show("nameplate1", ENEMY)
    eq(#uf.healthBar.created, 0, "nothing created")
    eq(blizzardTextAlphas(uf), "1,1,1", "Blizzard's health texts shown")
    eq(uf.healthBar.color, nil, "bar colour")
    eq(uf.name.font, nil, "name font")
end)

test("a plate reused from a friend to an enemy gives Blizzard its number back", function()
    local env = Load()
    local plate = T.Plate()
    env.show("nameplate1", FRIEND, plate)
    env.hide("nameplate1")
    local uf = env.show("nameplate2", ENEMY, plate)
    eq(ourText(uf).alpha, 0, "our text hidden")
    eq(blizzardTextAlphas(uf), "1,1,1", "Blizzard's texts back")
end)

test("a plate reused from an enemy to a friend makes its text once", function()
    local env = Load()
    local plate = T.Plate()
    env.show("nameplate1", ENEMY, plate)
    env.hide("nameplate1")
    env.show("nameplate2", FRIEND, plate)
    env.hide("nameplate2")
    local uf = env.show("nameplate3", FRIEND, plate)
    eq(#uf.healthBar.created, 1, "one text")
    eq(ourText(uf).text, "-abbr(missing:nameplate3)", "text follows the new unit")
end)

-- Events ----------------------------------------------------------------------

test("registers only the events it needs when enabled (the default)", function()
    local env = Load()
    local want = { "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_FACTION" }
    local n = 0
    for _ in pairs(env.frame.events) do n = n + 1 end
    for _, event in ipairs(want) do eq(env.frame.events[event], true, event) end
    eq(n, #want, "events registered")
    eq(next(env.hooked), nil, "no hooks")
    eq(env.globals.HealerPlatesDB.enabled, true, "saved default")
end)

test("a saved off setting registers nothing", function()
    local env = Load({ saved = { enabled = false } })
    eq(env.frame.events.NAME_PLATE_UNIT_ADDED, nil, "plate events")
    local uf = env.show("nameplate1", FRIEND)
    eq(#uf.healthBar.created, 0, "plate left alone")
end)

test("health events update shown friendly plates and ignore everything else", function()
    local env = Load()
    local uf = env.show("nameplate1", FRIEND)
    local text = ourText(uf)
    text.text = nil
    env.fire("UNIT_HEALTH", "nameplate1")
    eq(text.text, "-abbr(missing:nameplate1)", "UNIT_HEALTH")
    text.text = nil
    env.fire("UNIT_MAXHEALTH", "nameplate1")
    eq(text.text, "-abbr(missing:nameplate1)", "UNIT_MAXHEALTH")
    env.hide("nameplate1")
    text.text = nil
    env.fire("UNIT_HEALTH", "nameplate1")
    eq(text.text, nil, "removed plate ignored")
    env.fire("UNIT_HEALTH", "player")
    eq(#env.printed, 0, "no warnings")
end)

test("a unit that turns hostile gives Blizzard its number back", function()
    local env = Load()
    local uf = env.show("nameplate1", FRIEND)
    env.units.nameplate1.friend = false
    env.fire("UNIT_FACTION", "nameplate1")
    eq(ourText(uf).alpha, 0, "our text hidden")
    eq(blizzardTextAlphas(uf), "1,1,1", "Blizzard's texts back")
end)

test("forbidden plates are left alone", function()
    local env = Load()
    local plate = T.Plate()
    T.fields(plate).forbidden = true
    local uf = env.show("nameplate1", FRIEND, plate)
    eq(#uf.healthBar.created, 0, "nothing created")
    env.fire("UNIT_HEALTH", "nameplate1")
    eq(#env.printed, 0, "no warnings")
end)

test("secret friendliness is treated as an enemy (untested inside instances)", function()
    local env = Load({ secretUnitState = true })
    local uf = env.show("nameplate1", FRIEND)
    eq(#uf.healthBar.created, 0, "left to Blizzard")
    eq(#env.printed, 0, "no warnings")
end)

test("a plate missing its bar or texts is handled without errors", function()
    local env = Load()
    env.show("nameplate1", FRIEND, T.Plate({ "healthBar" }))
    local uf = env.show("nameplate2", FRIEND, T.Plate({ "LeftText", "RightText", "TextString" }))
    eq(ourText(uf).font, T.FONT .. ",10,OUTLINE", "falls back to the standard font")
    eq(#env.printed, 0, "no warnings")
end)

test("a failing update prints one line and never raises", function()
    local env = Load({ remove = { "UnitHealthMissing" } })
    env.show("nameplate1", FRIEND)
    env.show("nameplate2", FRIEND)
    env.fire("UNIT_HEALTH", "nameplate1")
    eq(#env.printed, 1, "warnings printed")
    assert(env.printed[1]:find("Healer Plates:", 1, true), env.printed[1])
    assert(env.printed[1]:find("couldn't show missing health", 1, true), env.printed[1])
end)

test("normal play prints nothing", function()
    local env = Load()
    env.show("nameplate1", FRIEND)
    env.show("nameplate2", ENEMY)
    env.fire("UNIT_HEALTH", "nameplate1")
    env.hide("nameplate2")
    eq(#env.printed, 0, "messages printed")
end)

-- Commands --------------------------------------------------------------------

test("every slash command uses the /hp- prefix", function()
    local env = Load()
    local n = 0
    for k, v in pairs(env.globals) do
        if type(k) == "string" and k:match("^SLASH_") then
            n = n + 1
            assert(v:match("^/hp%-%l+$"), k .. " = " .. v)
        end
    end
    eq(n, 4, "slash commands")
end)

test("/hp-off and /hp-on save the setting and ask for a reload", function()
    local env = Load()
    env.slash("/hp-off")
    eq(env.globals.HealerPlatesDB.enabled, false, "off")
    assert(env.printed[#env.printed]:find("Type /reload to apply.", 1, true), env.printed[#env.printed])
    env.slash("/hp-on")
    eq(env.globals.HealerPlatesDB.enabled, true, "on")
    assert(env.printed[#env.printed]:find("turned on", 1, true), env.printed[#env.printed])
end)

test("/hp-status reports what the addon found on this client", function()
    local env = Load({ remove = { "AbbreviateNumbers" } })
    env.show("nameplate1", FRIEND)
    env.show("nameplate2", ENEMY)
    env.printed = {}
    env.slash("/hp-status")
    local out = table.concat(env.printed, "\n")
    for _, want in ipairs({
        "running (saved setting: on)",
        "friendly plates with missing health: 1",
        "UnitHealthMissing: yes, AbbreviateNumbers: no",
    }) do
        assert(out:find(want, 1, true), "missing '" .. want .. "' in:\n" .. out)
    end
end)

test("/hp-status when turned off", function()
    local env = Load({ saved = { enabled = false } })
    env.slash("/hp-status")
    local out = table.concat(env.printed, "\n")
    assert(out:find("not running (saved setting: off)", 1, true), out)
    assert(out:find("friendly plates with missing health: 0", 1, true), out)
end)

test("/hp-help lists every command", function()
    local env = Load()
    env.slash("/hp-help")
    local out = table.concat(env.printed, "\n")
    for k, v in pairs(env.globals) do
        if type(k) == "string" and k:match("^SLASH_") then
            assert(out:find(v, 1, true), "help mentions " .. v)
        end
    end
end)

-- Runner (keep last) ------------------------------------------------------------

T.run(tests)
