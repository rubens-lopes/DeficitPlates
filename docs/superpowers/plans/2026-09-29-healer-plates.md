# Healer Plates Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A WoW Forever addon that restyles Blizzard's nameplates in Plater's default look for enemies and friends, and shows missing health (`-4.2K`, hidden at full health) on friendly plates.

**Architecture:** Four Lua files share one addon namespace (`local _, ns = ...`): `Colors.lua` (pure colour choice), `Health.lua` (value text from secret health values), `Style.lua` (one-time layout of a Blizzard plate), `Core.lua` (events, hooks, saved switch, slash commands). We never build our own plate. We call widget methods on Blizzard's `plate.UnitFrame` and keep our own state in weak-keyed tables.

**Tech Stack:** Lua 5.1 (WoW client), LuaJIT for tests, luacheck, BigWigs packager, GitHub Actions. Same toolchain as `~/DynamicDisplayNameplate`.

**Spec:** `docs/superpowers/specs/2026-09-28-healer-plates-design.md`

## Global Constraints

- TOC `## Interface: 16001`. Addon folder and name: `HealerPlates`. Title: `Healer Plates`.
- SavedVariables: `HealerPlatesDB`, one field `enabled` (default `true`).
- Slash commands use the `/hp-` prefix: `/hp-help`, `/hp-status`, `/hp-on`, `/hp-off`. Globals `SLASH_HPHELP1`, `SLASH_HPSTATUS1`, `SLASH_HPON1`, `SLASH_HPOFF1`.
- No other globals. The only new globals are `HealerPlatesDB` and the `SLASH_HP*` names.
- Hard rule 1: on Blizzard objects, only call widget methods (`SetFont`, `SetStatusBarTexture`, `SetStatusBarColor`, `SetPoint`, `ClearAllPoints`, `SetAlpha`, `SetTexture`, `SetVertexColor`, `SetTextColor`, `SetJustifyH`, `CreateTexture`, `CreateFontString`). Never write a field onto their tables and never iterate them.
- Hard rule 2: health values (`UnitHealthMissing`, `UnitHealthPercent`, `AbbreviateNumbers` results) only flow into widget calls. They are never compared, tested or used in arithmetic.
- Hard rule 3: never read aura data.
- Hard rule 4: look up every Blizzard child defensively. A missing child skips that step.
- Hard rule 5: skip plates where `plate:IsForbidden()` is true.
- Flat texture: `Interface\Buttons\WHITE8X8`. Font: `STANDARD_TEXT_FONT`, 10, `OUTLINE`.
- Chat prefix: `|cff33ccffHealer Plates:|r `. Warning format: `|cffff8800Healer Plates:|r couldn't <step> (<error>)`. It prints once per step per session.
- Git identity is already set in the repo (`Rubens Lopes` / `github@rubenslop.es`). Commit on `main`. Don't push until Task 8.
- Tests: `luajit tests/test_addon.lua`, run from the repo root. Lint: `luacheck .` If it's missing, install it with `brew install luacheck`.

## Review Focus

1. **Unit state is secret inside instances.** `UnitIsFriend`, `UnitReaction` or `UnitThreatSituation` may return secrets in dungeons. Expected: no Lua error, and the plate falls back to the base colour and the enemy text. Covered by a Task 4 test (`opts.secretUnitState`).
2. **Blizzard re-applies its own name look.** This happens after target changes, renames and level-ups. Expected: our font, colour and anchor come back each time. Covered by the Task 4 hook test, which checks the font, colour and anchor.
3. **A plate frame is reused from a friend to an enemy.** Expected: the text switches from `-X` to `%`, and the alpha goes back to 1, not the old curve alpha. Covered by tests in Task 2 and Task 4.
4. **Events for units without a styled plate.** This covers the player, units whose plate was removed, and forbidden plates. Expected: ignored silently. Covered by Task 4 tests.
5. **A plate missing children, or with locked children.** Expected: the remaining steps still apply, with no error. Covered by the Task 3 missing-children test.

---

## File Structure

| File | Responsibility |
|---|---|
| `HealerPlates.toc` | Metadata and load order: `Colors.lua`, `Health.lua`, `Style.lua`, `Core.lua` |
| `Colors.lua` | `ns.Colors.Info(unit)`, `ns.Colors.Bar(info)`, `ns.Colors.Name(info)` |
| `Health.lua` | `ns.Health.Update(text, unit, friend)`, `ns.Health.percentError` |
| `Style.lua` | `ns.Style.Create(uf)`, `ns.Style.Apply(uf, state)`, `ns.Style.Name(uf, r, g, b)`, `ns.Style.HideBarTexts(uf)` |
| `Core.lua` | Event frame, hooks, `Try`, saved setting, slash commands |
| `tests/harness.lua` | Stubbed client: secret values, read-only Blizzard widgets, fake plates, `Load()` |
| `tests/test_addon.lua` | All tests; the runner call stays at the bottom |
| `.luacheckrc`, `.pkgmeta`, `.gitignore`, `.github/workflows/ci.yml`, `.github/workflows/release.yml` | Tooling, copied from DDN's pattern |
| `README.md`, `CHANGELOG.md`, `LICENSE`, `docs/curseforge.md`, `media/make_logo.py`, `media/logo.png` | Docs and release assets |

The harness loads the files listed in `HealerPlates.toc`, in order. Each task adds its file to the TOC, so the TOC order is exercised by every test run.

---

### Task 1: Scaffolding, test harness and `Colors.lua`

**Files:**
- Create: `HealerPlates.toc`, `.luacheckrc`, `.pkgmeta`, `.gitignore`, `.github/workflows/ci.yml`, `.github/workflows/release.yml`
- Create: `tests/harness.lua`, `tests/test_addon.lua`
- Create: `Colors.lua`

**Interfaces:**
- Produces:
  - `ns.Colors.Info(unit) -> { friend: bool, player: bool, class: string|nil, reaction: number|nil, tapped: bool, threat: number|nil, tank: bool }`
  - `ns.Colors.Bar(info) -> r, g, b`
  - `ns.Colors.Name(info) -> r, g, b`
  - Harness module `T`, with:
    - `T.Load(opts) -> env`
    - `T.eq`, `T.rgb`, `T.run`
    - `T.Plate(without)`, `T.Widget(name, kind, children, blizzard)`
    - `T.fields(w)`, `T.value(uf)`, `T.point(w, n)`, `T.Label(v)`
    - `T.FONT`, `T.FLAT`
  - The `env` object has:
    - `env.ns`, `env.globals`, `env.frame`, `env.frames`
    - `env.printed`, `env.units`, `env.plates`, `env.hooked`, `env.curves`, `env.role`, `env.stubs`
    - `env.fire(event, ...)`, `env.slash(text)`, `env.show(unit, info, plate) -> UnitFrame`, `env.hide(unit)`

- [ ] **Step 1: Create the tooling files**

`HealerPlates.toc` (no file lines yet; Step 5 adds `Colors.lua`):

```
## Interface: 16001
## Title: Healer Plates
## Notes: Plater-style nameplates for enemies and friends. Friendly plates show missing health. /hp-help for commands.
## Author: Rubens Lopes
## Version: @project-version@
## Category: Combat
## IconTexture: Interface\Icons\Spell_Holy_FlashHeal
## SavedVariables: HealerPlatesDB

```

`.luacheckrc`:

```lua
std = "lua51"
max_line_length = false
exclude_files = { ".release" }

globals = {
    "HealerPlatesDB",
    "SLASH_HPHELP1",
    "SLASH_HPOFF1",
    "SLASH_HPON1",
    "SLASH_HPSTATUS1",
    "SlashCmdList",
}

read_globals = {
    "AbbreviateNumbers",
    "C_CurveUtil",
    "C_NamePlate",
    "CreateFrame",
    "CurveConstants",
    "hooksecurefunc",
    "RAID_CLASS_COLORS",
    "STANDARD_TEXT_FONT",
    "UnitClass",
    "UnitGroupRolesAssigned",
    "UnitHealthMissing",
    "UnitHealthPercent",
    "UnitIsFriend",
    "UnitIsPlayer",
    "UnitIsTapDenied",
    "UnitReaction",
    "UnitThreatSituation",
}
```

`.pkgmeta`:

```yaml
package-as: HealerPlates

manual-changelog:
  filename: CHANGELOG.md
  markup-type: markdown

ignore:
  - README.md
  - docs
  - media
  - tests
```

`.gitignore`:

```
.release/
```

`.github/workflows/ci.yml`:

```yaml
name: CI

on:
  push:
    branches: [main]
  pull_request:

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: nebularg/actions-luacheck@d4137dd840545b28521ed21931e06913d93c0bc1 # v1
        with:
          args: --no-color
      - name: Install LuaJIT
        run: sudo apt-get update && sudo apt-get install -y luajit
      - name: Unit tests
        run: luajit tests/test_addon.lua
```

`.github/workflows/release.yml`:

```yaml
name: Release

on:
  push:
    tags: ["v*"]

jobs:
  release:
    runs-on: ubuntu-latest
    permissions:
      contents: write
    env:
      CF_API_TOKEN: ${{ secrets.CF_API_TOKEN }}
      GITHUB_OAUTH: ${{ secrets.GITHUB_TOKEN }}
    steps:
      - uses: actions/checkout@v4
        with:
          fetch-depth: 0
      - name: Install LuaJIT
        run: sudo apt-get update && sudo apt-get install -y luajit
      - name: Unit tests
        run: luajit tests/test_addon.lua
      - uses: BigWigsMods/packager@e50a250f8705041e40f2fa1ddcb280a686d65aa0 # v2
        with:
          args: -n "hp-{project-version}"
```

- [ ] **Step 2: Write the complete test harness**

This file is written once, in full. Later tasks only add tests to `tests/test_addon.lua`.

`tests/harness.lua`:

```lua
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
    local w = { name = name, kind = kind, points = {}, alpha = 1, created = {} }
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
    return ("%s %s %s %d %d"):format(p[1], p[2].name, p[3], p[4], p[5])
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
    if opts.secretUnitState then
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
```

- [ ] **Step 3: Write the harness checks and the failing colour tests**

`tests/test_addon.lua`:

```lua
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

-- Runner (keep last) ------------------------------------------------------------

T.run(tests)
```

- [ ] **Step 4: Run the tests and confirm the colour tests fail**

Run: `luajit tests/test_addon.lua`
Expected: the 3 harness tests PASS. The 5 colour tests FAIL with `attempt to index local 'C' (a nil value)` or similar. The last line reads `3 passed, 5 failed`.

- [ ] **Step 5: Write `Colors.lua` and add it to the TOC**

`Colors.lua`:

```lua
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
```

Append this line to the end of `HealerPlates.toc`:

```
Colors.lua
```

- [ ] **Step 6: Run the tests and lint**

Run: `luajit tests/test_addon.lua && luacheck .`
Expected: `8 passed, 0 failed`, and luacheck reports `0 warnings / 0 errors`. Fix any luacheck warning in the new files before committing. If luacheck doesn't know `newproxy`, add `-- luacheck: globals newproxy` at the top of `tests/harness.lua`.

- [ ] **Step 7: Commit**

```bash
git add HealerPlates.toc Colors.lua tests .luacheckrc .pkgmeta .gitignore .github
git commit -m "Add test harness, tooling and bar/name colours"
```

---

### Task 2: `Health.lua`, the value text

**Files:**
- Create: `Health.lua`
- Modify: `HealerPlates.toc` (append `Health.lua`)
- Test: `tests/test_addon.lua` (add a Health section above `-- Runner (keep last)`)

**Interfaces:**
- Consumes: the harness from Task 1 (`T.Widget`, `env.curves`, `opts.percentError`)
- Produces:
  - `ns.Health.Update(text, unit, friend)`, where `text` is a FontString and `friend` a boolean. It raises the error once, on the first enemy % failure, and is silent after that.
  - `ns.Health.percentError`: `nil`, or the error string from the first failure.

- [ ] **Step 1: Write the failing tests**

Add above `-- Runner (keep last)`:

```lua
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
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `luajit tests/test_addon.lua`
Expected: the 5 new tests FAIL with `attempt to index field 'Health' (a nil value)`. The last line reads `8 passed, 5 failed`.

- [ ] **Step 3: Write `Health.lua` and add it to the TOC**

`Health.lua`:

```lua
-- The value text on the bar. Health values are secret on this client: they
-- go straight into widget calls and are never compared or used in math.

local _, ns = ...
local Health = {}
ns.Health = Health

-- Set by the first failed enemy % call; enemy text stays hidden after that.
Health.percentError = nil

local fullHealthCurve

-- 1 below full health, 0 at full, so SetAlpha hides "-0" on healthy friends.
local function FullHealthCurve()
    if not fullHealthCurve then
        fullHealthCurve = C_CurveUtil.CreateCurve()
        fullHealthCurve:AddPoint(0, 1)
        fullHealthCurve:AddPoint(0.999, 1)
        fullHealthCurve:AddPoint(1, 0)
    end
    return fullHealthCurve
end

-- text: our FontString. friend: UnitIsFriend("player", unit).
function Health.Update(text, unit, friend)
    if friend then
        text:SetText("-" .. AbbreviateNumbers(UnitHealthMissing(unit)))
        text:SetAlpha(UnitHealthPercent(unit, false, FullHealthCurve()))
        return
    end
    if Health.percentError then
        text:SetAlpha(0)
        return
    end
    local ok, err = pcall(function()
        text:SetFormattedText("%d%%", UnitHealthPercent(unit, false, CurveConstants.ScaleTo100))
    end)
    if ok then
        text:SetAlpha(1)
        return
    end
    Health.percentError = tostring(err)
    text:SetAlpha(0)
    error(err, 0)
end
```

Append to `HealerPlates.toc`:

```
Health.lua
```

- [ ] **Step 4: Run the tests and lint**

Run: `luajit tests/test_addon.lua && luacheck .`
Expected: `13 passed, 0 failed`, and luacheck is clean.

- [ ] **Step 5: Commit**

```bash
git add Health.lua HealerPlates.toc tests/test_addon.lua
git commit -m "Show missing health on friends and percent on enemies"
```

---

### Task 3: `Style.lua`, the plate layout

**Files:**
- Create: `Style.lua`
- Modify: `HealerPlates.toc` (append `Style.lua`)
- Test: `tests/test_addon.lua` (add a Style section above `-- Runner (keep last)`)

**Interfaces:**
- Consumes: `T.Plate(without)`, `T.point`, `T.FONT`, `T.FLAT` from the harness
- Produces:
  - `ns.Style.Create(uf) -> state`. `state` is `{ value = FontString, border = { 4 Textures } }`, or `{}` when the plate has no `healthBar`. It creates only our own widgets, via `healthBar:CreateFontString` and `healthBar:CreateTexture`.
  - `ns.Style.Apply(uf, state)`: restyles Blizzard's children and sets `state.castBar` (boolean).
  - `ns.Style.Name(uf, r, g, b)`: name font, colour and anchor.
  - `ns.Style.HideBarTexts(uf)`: sets the alpha of `LeftText`, `RightText` and `TextString` to 0.

- [ ] **Step 1: Write the failing tests**

Add above `-- Runner (keep last)`:

```lua
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
```

Because every Blizzard widget in these tests is read-only, these tests also check hard rule 1: any field written onto Blizzard's tables raises an error.

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `luajit tests/test_addon.lua`
Expected: the 6 new tests FAIL with `attempt to index local 'S' (a nil value)`. The last line reads `13 passed, 6 failed`.

- [ ] **Step 3: Write `Style.lua` and add it to the TOC**

`Style.lua`:

```lua
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
```

Append to `HealerPlates.toc`:

```
Style.lua
```

- [ ] **Step 4: Run the tests and lint**

Run: `luajit tests/test_addon.lua && luacheck .`
Expected: `19 passed, 0 failed`, and luacheck is clean.

- [ ] **Step 5: Commit**

```bash
git add Style.lua HealerPlates.toc tests/test_addon.lua
git commit -m "Restyle Blizzard plates in a flat Plater-like layout"
```

---

### Task 4: `Core.lua`, events, hooks and saved switch

**Files:**
- Create: `Core.lua`
- Modify: `HealerPlates.toc` (append `Core.lua`)
- Test: `tests/test_addon.lua` (add a Core section above `-- Runner (keep last)`)

**Interfaces:**
- Consumes:
  - `ns.Colors.Info`, `ns.Colors.Bar`, `ns.Colors.Name`
  - `ns.Health.Update`, `ns.Health.percentError`
  - `ns.Style.Create`, `ns.Style.Apply`, `ns.Style.Name`, `ns.Style.HideBarTexts`
  - Harness: `env.show`, `env.hide`, `env.fire`, `env.hooked`, `T.value`, `T.fields`, `opts.secretUnitState`
- Produces (for Task 5, in the same file):
  - The locals `states` (weak UnitFrame → state), `installed` (hook name → true), `running` (boolean), `settings` (the saved table), `HOOKS` (a list of `{ name, fn }`) and `TITLE`.
  - `Try(step, fn, ...)`

- [ ] **Step 1: Write the failing tests**

Add above `-- Runner (keep last)`:

```lua
-- Core ------------------------------------------------------------------------

local FRIEND = { friend = true, player = true, class = "MAGE", reaction = 5 }
local ENEMY = { reaction = 2 }

test("registers its events and hooks when enabled (the default)", function()
    local env = Load()
    for _, event in ipairs({ "NAME_PLATE_UNIT_ADDED", "NAME_PLATE_UNIT_REMOVED", "UNIT_HEALTH",
        "UNIT_MAXHEALTH", "UNIT_THREAT_LIST_UPDATE", "UNIT_THREAT_SITUATION_UPDATE",
        "PLAYER_ROLES_ASSIGNED" }) do
        eq(env.frame.events[event], true, event)
    end
    eq(env.frame.events.ADDON_LOADED, nil, "ADDON_LOADED unregistered")
    eq(env.hooked.CompactUnitFrame_UpdateHealthColor, true, "colour hook")
    eq(env.hooked.CompactUnitFrame_UpdateName, true, "name hook")
    eq(env.globals.HealerPlatesDB.enabled, true, "saved default")
end)

test("a saved off setting registers nothing and hooks nothing", function()
    local env = Load({ saved = { enabled = false } })
    eq(env.frame.events.NAME_PLATE_UNIT_ADDED, nil, "plate events")
    eq(next(env.hooked), nil, "hooks")
    local uf = env.show("nameplate1", ENEMY)
    eq(#uf.healthBar.created, 0, "plate left alone")
end)

test("a friendly plate shows missing health in its class colour", function()
    local env = Load()
    local uf = env.show("nameplate1", FRIEND)
    eq(T.value(uf).text, "-abbr(missing:nameplate1)", "text")
    eq(T.value(uf).alpha, "curve1:nameplate1", "hidden at full health")
    eq(uf.healthBar.color, MAGE, "bar colour")
    eq(uf.name.textColor, MAGE, "name colour")
    eq(uf.healthBar.LeftText.alpha, 0, "Blizzard's text hidden")
    eq(uf.healthBar.statusBarTexture, T.FLAT, "styled")
end)

test("an enemy plate shows health percent and a white name", function()
    local env = Load()
    local uf = env.show("nameplate2", ENEMY)
    eq(T.value(uf).text, "%d%% <- percent:nameplate2", "text")
    eq(T.value(uf).alpha, 1, "alpha")
    eq(uf.healthBar.color, RED, "bar colour")
    eq(uf.name.textColor, WHITE, "name colour")
end)

test("a reused plate is styled once and follows its new unit", function()
    local env = Load()
    local plate = T.Plate()
    env.show("nameplate1", FRIEND, plate)
    env.hide("nameplate1")
    local uf = env.show("nameplate2", ENEMY, plate)
    eq(#uf.healthBar.created, 5, "no second set of widgets")
    eq(T.value(uf).text, "%d%% <- percent:nameplate2", "text")
    eq(T.value(uf).alpha, 1, "alpha back to full")
    eq(uf.healthBar.color, RED, "colour")
end)

test("health events update shown plates and ignore everything else", function()
    local env = Load()
    local uf = env.show("nameplate1", FRIEND)
    local value = T.value(uf)
    value.text = nil
    env.fire("UNIT_HEALTH", "nameplate1")
    eq(value.text, "-abbr(missing:nameplate1)", "UNIT_HEALTH")
    value.text = nil
    env.fire("UNIT_MAXHEALTH", "nameplate1")
    eq(value.text, "-abbr(missing:nameplate1)", "UNIT_MAXHEALTH")
    env.hide("nameplate1")
    value.text = nil
    env.fire("UNIT_HEALTH", "nameplate1")
    eq(value.text, nil, "removed plate ignored")
    env.fire("UNIT_HEALTH", "player")
    eq(#env.printed, 0, "no warnings")
end)

test("threat and role events recolour enemy plates", function()
    local env = Load()
    local uf = env.show("nameplate1", ENEMY)
    env.units.nameplate1.threat = 3
    env.fire("UNIT_THREAT_LIST_UPDATE", "nameplate1")
    eq(uf.healthBar.color, MAGENTA, "list update")
    env.units.nameplate1.threat = 1
    env.fire("UNIT_THREAT_SITUATION_UPDATE", "player")
    eq(uf.healthBar.color, YELLOW, "situation update")
    env.role = "TANK"
    env.units.nameplate1.threat = 0
    env.fire("PLAYER_ROLES_ASSIGNED")
    eq(uf.healthBar.color, ORANGE, "role change")
    env.units.nameplate1.threat = 3
    env.fire("UNIT_THREAT_LIST_UPDATE", "target")
    eq(uf.healthBar.color, RED, "unknown unit recolours all plates")
end)

test("Blizzard's colour and name updates are overridden on our plates only", function()
    local env = Load()
    local uf = env.show("nameplate1", ENEMY)
    env.globals.CompactUnitFrame_UpdateHealthColor(uf)
    eq(uf.healthBar.color, RED, "our bar colour wins")
    env.globals.CompactUnitFrame_UpdateName(uf)
    eq(uf.name.font, T.FONT .. ",10,OUTLINE", "our name font wins")
    eq(uf.name.textColor, WHITE, "our name colour wins")
    eq(T.point(uf.name), "BOTTOMLEFT healthBar TOPLEFT 0 2", "our name anchor wins")
    local other = T.Plate().UnitFrame
    env.globals.CompactUnitFrame_UpdateHealthColor(other)
    eq(other.healthBar.color, "0.00,1.00,0.00", "unstyled frame keeps Blizzard's colour")
end)

test("a client without the hooked functions still styles plates", function()
    local env = Load({ remove = { "CompactUnitFrame_UpdateHealthColor", "CompactUnitFrame_UpdateName" } })
    eq(next(env.hooked), nil, "no hooks")
    local uf = env.show("nameplate1", ENEMY)
    eq(uf.healthBar.color, RED, "colour")
    eq(#env.printed, 0, "no warnings")
end)

test("forbidden plates are left alone", function()
    local env = Load()
    local plate = T.Plate()
    T.fields(plate).forbidden = true
    local uf = env.show("nameplate1", ENEMY, plate)
    eq(#uf.healthBar.created, 0, "nothing created")
    eq(uf.healthBar.statusBarTexture, nil, "not restyled")
    env.fire("UNIT_HEALTH", "nameplate1")
    eq(#env.printed, 0, "no warnings")
end)

test("secret unit state never raises (untested inside instances)", function()
    local env = Load({ secretUnitState = true })
    local uf = env.show("nameplate1", ENEMY)
    env.fire("UNIT_THREAT_LIST_UPDATE", "nameplate1")
    eq(uf.healthBar.color, RED, "falls back to hostile")
    eq(T.value(uf).text, "%d%% <- percent:nameplate1", "enemy text")
end)

test("a failing step prints one line and never raises", function()
    local env = Load({ percentError = "blocked" })
    local uf = env.show("nameplate1", ENEMY)
    env.show("nameplate2", ENEMY)
    env.fire("UNIT_HEALTH", "nameplate1")
    eq(#env.printed, 1, "warnings printed")
    assert(env.printed[1]:find("Healer Plates:", 1, true), env.printed[1])
    assert(env.printed[1]:find("couldn't show health (blocked)", 1, true), env.printed[1])
    eq(T.value(uf).alpha, 0, "text hidden")
    eq(uf.healthBar.color, RED, "later steps still ran")
end)

test("normal play prints nothing", function()
    local env = Load()
    env.show("nameplate1", FRIEND)
    env.show("nameplate2", ENEMY)
    env.fire("UNIT_HEALTH", "nameplate1")
    env.fire("UNIT_THREAT_SITUATION_UPDATE", "player")
    env.hide("nameplate2")
    eq(#env.printed, 0, "messages printed")
end)
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `luajit tests/test_addon.lua`
Expected: the 13 new Core tests FAIL, mostly with `attempt to index field 'frame' (a nil value)` or `attempt to index a nil value`, because no event frame exists yet. The last line reads `19 passed, 13 failed`.

- [ ] **Step 3: Write `Core.lua` and add it to the TOC**

`Core.lua`:

```lua
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
local installed = {}
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
```

Append to `HealerPlates.toc`:

```
Core.lua
```

- [ ] **Step 4: Run the tests and lint**

Run: `luajit tests/test_addon.lua && luacheck .`
Expected: `32 passed, 0 failed`. Luacheck may flag `running` as set but never accessed. Task 5 reads it. If luacheck flags it now, add `-- luacheck: ignore 231` to the end of that `local` line for this commit, then remove it in Task 5.

- [ ] **Step 5: Commit**

```bash
git add Core.lua HealerPlates.toc tests/test_addon.lua
git commit -m "Style plates on show and keep them updated through events and hooks"
```

---

### Task 5: Slash commands

**Files:**
- Modify: `Core.lua`. Add the commands at the end of the file and a `TAG` local under `TITLE`. Remove any `luacheck: ignore` comment added in Task 4.
- Test: `tests/test_addon.lua` (add a Commands section above `-- Runner (keep last)`)

**Interfaces:**
- Consumes:
  - From Task 4: `states`, `installed`, `running`, `settings`, `HOOKS`, `TITLE`
  - `ns.Health.percentError`
- Produces:
  - `SLASH_HPHELP1`, `SLASH_HPSTATUS1`, `SLASH_HPON1`, `SLASH_HPOFF1`
  - `SlashCmdList.HPHELP`, `.HPSTATUS`, `.HPON`, `.HPOFF`

- [ ] **Step 1: Write the failing tests**

Add above `-- Runner (keep last)`:

```lua
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
    local env = Load({ remove = { "CompactUnitFrame_UpdateName", "C_CurveUtil" }, percentError = "blocked" })
    env.show("nameplate1", ENEMY)
    env.printed = {}
    env.slash("/hp-status")
    local out = table.concat(env.printed, "\n")
    for _, want in ipairs({
        "running (saved setting: on)",
        "plates styled: 1 (cast bar found on 1)",
        "hook CompactUnitFrame_UpdateHealthColor: installed",
        "hook CompactUnitFrame_UpdateName: missing",
        "UnitHealthPercent: yes, UnitHealthMissing: yes, C_CurveUtil: no",
        "enemy health %: hidden, it failed: blocked",
    }) do
        assert(out:find(want, 1, true), "missing '" .. want .. "' in:\n" .. out)
    end
end)

test("/hp-status when turned off, and when enemy percent works", function()
    local env = Load({ saved = { enabled = false } })
    env.slash("/hp-status")
    local out = table.concat(env.printed, "\n")
    assert(out:find("not running (saved setting: off)", 1, true), out)
    assert(out:find("plates styled: 0", 1, true), out)
    assert(out:find("enemy health %: shown", 1, true), out)
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
```

- [ ] **Step 2: Run the tests and confirm they fail**

Run: `luajit tests/test_addon.lua`
Expected: the 5 new tests FAIL. The prefix test reports `slash commands: expected 4, got 0`, and the others report `unknown slash command /hp-...`. The last line reads `32 passed, 5 failed`.

- [ ] **Step 3: Add the commands to `Core.lua`**

Directly under `local TITLE = "Healer Plates"`, add:

```lua
local TAG = "|cff33ccff" .. TITLE .. ":|r "
```

At the end of `Core.lua`, add:

```lua
local function Say(msg) print(TAG .. msg) end

local function Has(api) return api and "yes" or "no" end

local function Help()
    Say("commands")
    print("  /hp-help - show this list")
    print("  /hp-status - show what the addon found on this client")
    print("  /hp-on - restyle nameplates (after /reload)")
    print("  /hp-off - leave Blizzard's nameplates alone (after /reload)")
end

local function Status()
    Say(("%s (saved setting: %s)"):format(running and "running" or "not running",
        settings.enabled and "on" or "off"))
    local styled, castBars = 0, 0
    for _, state in pairs(states) do
        styled = styled + 1
        if state.castBar then castBars = castBars + 1 end
    end
    print(("  plates styled: %d (cast bar found on %d)"):format(styled, castBars))
    for _, hook in ipairs(HOOKS) do
        print(("  hook %s: %s"):format(hook.name, installed[hook.name] and "installed" or "missing"))
    end
    print(("  UnitHealthPercent: %s, UnitHealthMissing: %s, C_CurveUtil: %s"):format(
        Has(UnitHealthPercent), Has(UnitHealthMissing), Has(C_CurveUtil)))
    print("  enemy health %: " .. (Health.percentError and ("hidden, it failed: " .. Health.percentError) or "shown"))
end

-- The restyle can't be undone live, so both directions need a reload.
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
```

- [ ] **Step 4: Run the tests and lint**

Run: `luajit tests/test_addon.lua && luacheck .`
Expected: `37 passed, 0 failed`, and luacheck is clean with no `ignore` comments left.

- [ ] **Step 5: Commit**

```bash
git add Core.lua tests/test_addon.lua
git commit -m "Add /hp-help, /hp-status, /hp-on and /hp-off"
```

---

### Task 6: Docs, licence and logo

**Files:**
- Create: `README.md`, `CHANGELOG.md`, `LICENSE`, `docs/curseforge.md`, `media/make_logo.py`, `media/logo.png` (generated)

**Interfaces:**
- Consumes: the command names and behaviour from Tasks 4–5
- Produces: the release assets that Task 8 uses

- [ ] **Step 1: Write `README.md`**

````markdown
# Healer Plates

A World of Warcraft: Forever addon that gives nameplates Plater's default look, for enemies and friends alike, with one change for healers: friendly plates show **missing health** (`-4.2K`) in place of a percentage, and nothing at full health.

- Flat bars with a thin black border, the name above the bar, and the value inside the bar on the right.
- Enemies: health %, your debuffs, cast bar, and threat colours (yellow when threat is building, orange when you're about to pull aggro, magenta when you have it; tanks get the reverse).
- Friends: missing health, class colours, your HoTs and buffs, and incoming heals and absorbs on the bar.

It restyles Blizzard's own nameplates, so Blizzard still decides which auras and casts show. It has no settings panel.

## Commands

- `/hp-help` lists the commands.
- `/hp-status` shows what the addon found on this client. Include it in bug reports.
- `/hp-off` leaves Blizzard's nameplates alone after your next `/reload`. `/hp-on` turns the restyle back on.

## Works with

[Dynamic Display Nameplate](https://github.com/rubens-lopes/DynamicDisplayNameplate) decides when plates show. Healer Plates decides how they look. Use both, or either one.

## Install

Get it from CurseForge, or copy this folder to `World of Warcraft/_classic_beta_/Interface/AddOns/HealerPlates` for the Forever beta.

## Development

```bash
luajit tests/test_addon.lua
luacheck .
```

Tagging `vX.Y.Z` runs the BigWigs packager in GitHub Actions and attaches `hp-<version>.zip` to a GitHub Release. Tags containing `beta` or `alpha` become pre-releases. Upload that zip to CurseForge by hand.
````

- [ ] **Step 2: Write `CHANGELOG.md`**

```markdown
# Changelog

## v0.1.0-beta1

- First beta for World of Warcraft: Forever. Plater-style nameplates for enemies and friends.
- Friendly plates show missing health (hidden at full health), class colours, and incoming heals and absorbs.
- Enemy plates show health %, threat colours, your debuffs and the cast bar.
- Commands: `/hp-help`, `/hp-status`, `/hp-on`, `/hp-off`.
- Not yet tested inside dungeons and raids. Please report what you see there with `/hp-status`.
```

- [ ] **Step 3: Write `LICENSE`**

Copy `~/DynamicDisplayNameplate/LICENSE` unchanged if it's MIT with `Copyright (c) 2026 Rubens Lopes`. Otherwise, write the standard MIT License text with that copyright line.

- [ ] **Step 4: Write `docs/curseforge.md`**

```markdown
# CurseForge project page

Paste these into the project form at https://authors.curseforge.com/#/projects/create

- **Game:** World of Warcraft
- **Project type:** Addons
- **Name:** Healer Plates
- **Primary category:** Unit Frames
- **Additional category:** Healer (use Combat if CurseForge has no Healer category)
- **License:** MIT License
- **Logo:** `media/logo.png`
- **Source:** https://github.com/rubens-lopes/HealerPlates
- **Issues:** https://github.com/rubens-lopes/HealerPlates/issues

## Summary

Plater-style nameplates for enemies and friends, with missing health on friendly plates for healers.

## Description

Healer Plates gives World of Warcraft: Forever nameplates the clean look of Plater's defaults, and uses the same look on friendly plates. On friendly plates, the number on the bar is **missing health** (for example `-4.2K`), so you can see at a glance who needs healing. It shows nothing when someone is at full health.

**What you get**

- Flat bars with a thin border, the name above the bar, and the value inside the bar.
- Enemies: health %, your debuffs, cast bar, and threat colours.
- Friends: missing health, class colours, your HoTs and buffs, and incoming heals and absorbs.

**No setup**

Install it and it works. There's no settings panel. Chat commands:

- `/hp-help` lists the commands.
- `/hp-status` shows what the addon found on this client. Include it in bug reports.
- `/hp-off` leaves Blizzard's nameplates alone after your next `/reload`. `/hp-on` turns the restyle back on.

**Good to know**

- It restyles Blizzard's own nameplates, so Blizzard still decides which auras and casts are shown.
- Pairs well with Dynamic Display Nameplate, which decides *when* plates show.
- This is a beta. It hasn't been tested inside dungeons and raids yet.

**Compatibility**

- World of Warcraft: Forever (1.60.x)
- Don't run it alongside another addon that restyles nameplates (Plater, Kui, and so on).

**Source and issues**

The code is on [GitHub](https://github.com/rubens-lopes/HealerPlates). If something goes wrong, open an issue there and include the `/hp-status` output and any error text the addon printed in chat.
```

- [ ] **Step 5: Write and run the logo script**

`media/make_logo.py`:

```python
# Draws media/logo.png (400x400): a green healing cross over a nameplate bar
# that is partly empty. Standard library only. Run from the repo root.
import struct
import zlib

SIZE = 400
BG = (24, 26, 30)
GREEN = (40, 200, 90)
EMPTY = (70, 74, 82)
BLACK = (0, 0, 0)


def pixel(x, y):
    c = SIZE // 2
    cy = 170
    if (abs(x - c) < 40 and abs(y - cy) < 120) or (abs(y - cy) < 40 and abs(x - c) < 120):
        return GREEN
    if 306 <= y < 344 and 56 <= x < 344:
        if y < 310 or y >= 340 or x < 60 or x >= 340:
            return BLACK
        return GREEN if x < 250 else EMPTY
    return BG


def chunk(tag, data):
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)


rows = b"".join(
    b"\x00" + bytes(v for x in range(SIZE) for v in pixel(x, y)) for y in range(SIZE)
)
png = (
    b"\x89PNG\r\n\x1a\n"
    + chunk(b"IHDR", struct.pack(">IIBBBBB", SIZE, SIZE, 8, 2, 0, 0, 0))
    + chunk(b"IDAT", zlib.compress(rows, 9))
    + chunk(b"IEND", b"")
)
with open("media/logo.png", "wb") as f:
    f.write(png)
```

Run: `python3 media/make_logo.py && file media/logo.png`
Expected: `media/logo.png: PNG image data, 400 x 400, 8-bit/color RGB, non-interlaced`. Open it with the Read tool to check it shows a green cross above a bar that's about two-thirds full.

- [ ] **Step 6: Check that tests still pass, then commit**

Run: `luajit tests/test_addon.lua && luacheck .`
Expected: `37 passed, 0 failed`, and luacheck is clean. `.pkgmeta` already excludes `docs`, `media` and `README.md` from the zip.

```bash
git add README.md CHANGELOG.md LICENSE docs/curseforge.md media
git commit -m "Add README, changelog, licence, CurseForge page and logo"
```

---

### Task 7: Install on the beta client and check in game

**Files:**
- No repo changes, unless the check finds bugs. Fix bugs TDD-style: write a failing test in `tests/test_addon.lua` that reproduces the bug, then fix it, then commit.

**Interfaces:**
- Consumes: the whole addon
- Produces: the user's go-ahead for the release

- [ ] **Step 1: Link the repo into the beta AddOns folder**

```bash
ls "/Applications/World of Warcraft/_classic_beta_/Interface/AddOns/"
ln -s ~/HealerPlates "/Applications/World of Warcraft/_classic_beta_/Interface/AddOns/HealerPlates"
```

Expected: the listing shows `PlateProbe` and no existing `HealerPlates`. If `HealerPlates` already exists, stop and ask the user.

- [ ] **Step 2: Remove the throwaway probe**

Look at the folder first, then delete it. It holds only `PlateProbe.toc` and `PlateProbe.lua`, both from the brainstorming session:

```bash
ls "/Applications/World of Warcraft/_classic_beta_/Interface/AddOns/PlateProbe"
rm -r "/Applications/World of Warcraft/_classic_beta_/Interface/AddOns/PlateProbe"
```

If the listing shows anything other than those two files, stop and ask the user.

- [ ] **Step 3: Ask the user to run the in-game checklist**

Send the user this list and wait for results. Screenshots help.

1. Out of combat in the open world: enemy and friendly plates have flat bars, a thin black border, the name above the bar, and no level text.
2. Friendly players at full health show no number. Once hurt, they show `-X` (for example `-4.2K`).
3. Enemy plates show a whole-number `%`.
4. While you cast a heal on a hurt friend, the incoming heal shows as green on their bar. A shield shows as white.
5. Threat colours change during a pull: yellow, then orange, then magenta.
6. Your debuffs show above enemy names, and your HoTs show above friendly names.
7. Enemy casts show under the bar.
8. The target highlight and raid markers still show.
9. No Lua errors over about 5 minutes of play. `/hp-status` shows both hooks `installed` and `cast bar found on N` with N above 0.
10. `/hp-off`, then `/reload`, gives back Blizzard's look. `/hp-on`, then `/reload`, brings the restyle back.

If an item fails, fix it under this task using the TDD rule above, then ask the user to recheck that item. Put any layout tweaks the user asks for, such as sizes or offsets, in `Style.lua` constants, and update their tests.

- [ ] **Step 4: Update the spec's probe notes if the check taught us something**

If a check finds that a child name differs from what the spec's plate-structure row says (for example, the cast bar isn't under `CastBarsContainer.castBar`), update that row in `docs/superpowers/specs/2026-09-28-healer-plates-design.md` and commit:

```bash
git add docs/superpowers/specs/2026-09-28-healer-plates-design.md
git commit -m "Record in-game findings in the design spec"
```

---

### Task 8: Publish v0.1.0-beta1

**Files:**
- No code changes

**Interfaces:**
- Consumes: the user's go-ahead from Task 7, and the Task 6 docs
- Produces: a GitHub repo, a tagged pre-release with `hp-v0.1.0-beta1.zip`, and CurseForge upload steps for the user

These steps are outward-facing. **Ask the user before each of Steps 1, 3 and 4.**

- [ ] **Step 1: Create the GitHub repo under `rubens-lopes`**

```bash
gh auth switch -u rubens-lopes
gh repo create rubens-lopes/HealerPlates --public --description "Plater-style nameplates for WoW Forever, with missing health on friendly plates for healers."
gh auth switch -u rubens-sindel
```

- [ ] **Step 2: Add a repo-local credential helper, so pushes use `rubens-lopes` without switching accounts**

```bash
git config --local credential.https://github.com.helper ''
git config --local --add credential.https://github.com.helper '!f() { test "$1" = get && echo username=rubens-lopes && echo "password=$(/opt/homebrew/bin/gh auth token -u rubens-lopes)"; }; f'
git remote add origin https://github.com/rubens-lopes/HealerPlates.git
```

- [ ] **Step 3: Push `main` and check CI**

```bash
git push -u origin main
gh run watch -R rubens-lopes/HealerPlates $(gh run list -R rubens-lopes/HealerPlates --limit 1 --json databaseId -q '.[0].databaseId')
```

Expected: the CI run succeeds, with luacheck and unit tests both passing.

- [ ] **Step 4: Tag the release and check the packaged zip**

```bash
git tag v0.1.0-beta1
git push origin v0.1.0-beta1
gh run watch -R rubens-lopes/HealerPlates $(gh run list -R rubens-lopes/HealerPlates --workflow Release --limit 1 --json databaseId -q '.[0].databaseId')
gh release view v0.1.0-beta1 -R rubens-lopes/HealerPlates
```

Expected: the release is marked pre-release and has `hp-v0.1.0-beta1.zip` attached. Download it into the session scratchpad with `gh release download v0.1.0-beta1 -R rubens-lopes/HealerPlates -D <scratchpad>`. Run `unzip -l` on it and confirm it contains only these files under `HealerPlates/`: `HealerPlates.toc`, `Colors.lua`, `Health.lua`, `Style.lua`, `Core.lua`, `CHANGELOG.md`, `LICENSE`. There should be no `tests`, `docs` or `media`.

- [ ] **Step 5: Hand over the CurseForge upload steps**

Tell the user:
1. Create the project with the fields and text in `docs/curseforge.md`, and use `media/logo.png` as the logo.
2. Upload `hp-v0.1.0-beta1.zip`. Set the release type to **Beta** and the game version to **Forever 1.60.x**. Paste the `v0.1.0-beta1` section of `CHANGELOG.md` as the changelog.
3. Send me the project ID. The next release adds `## X-Curse-Project-ID: <id>` to `HealerPlates.toc`.
4. Try a dungeon with the beta, and send `/hp-status` output plus screenshots.
