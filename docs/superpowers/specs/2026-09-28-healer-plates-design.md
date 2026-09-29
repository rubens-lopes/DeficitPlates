# Healer Plates: design

Date: 2026-09-28
Status: approved in chat, awaiting review of this document

## Goal

A World of Warcraft: Forever addon that gives nameplates Plater's default enemy look, applies that same look to friendly plates, and on friendly plates shows **missing health** (for example `-4.2K`, and `-0` at full health) in place of health percentage, because the author plays a healer. It replaces Plater, which has too many settings and is buggy on Forever. It is a sibling of Dynamic Display Nameplate (DDN) and published on CurseForge. It does not depend on DDN: DDN decides when plates show, and Healer Plates decides how they look.

## Target

- WoW Forever only: the retail 12.x engine, TOC `## Interface: 16001`. The local beta client is at `/Applications/World of Warcraft/_classic_beta_/`.
- CurseForge flavor: Forever. First release `v0.1.0-beta1` (release type: beta), uploaded by hand.
- Repo: `~/HealerPlates`, published under the personal GitHub account (`rubens-lopes`).

## What the client allows (probe results, 2026-09-28)

A throwaway `PlateProbe` addon measured these in the open world, in and out of combat. **Inside dungeons and raids is untested**; the beta release will cover it.

| Area | Finding |
|---|---|
| Health | `UnitHealth`, `UnitHealthMax`, `UnitHealthMissing`, `UnitHealthPercent`, incoming heals and absorbs are **secret values everywhere**, even out of combat in town. Math on them raises "attempt to perform arithmetic on a secret number value". |
| Using secret values | Concatenation, `string.format`, `AbbreviateNumbers`, `FontString:SetText`, `SetFormattedText`, `SetAlpha`, `StatusBar:SetMinMaxValues` and `SetValue` all accept them. The results are secret too, but they display correctly. |
| Hiding text at full health | A `C_CurveUtil.CreateCurve()` curve passed to `UnitHealthPercent(unit, false, curve)` gives an alpha that `SetAlpha` accepts. `C_StringUtil.TruncateWhenZero(UnitHealthMissing(unit))` also shows blank at 0 health missing. |
| Blizzard plate | `plate.UnitFrame` is not forbidden in the open world. Restyling it (`SetStatusBarTexture`, `SetFont`, `SetStatusBarColor` from a `hooksecurefunc` on `CompactUnitFrame_UpdateHealthColor`) raised **0 errors** over repeated fights. |
| Plate structure | `UnitFrame` has `healthBar` (inside `HealthBarsContainer`), `name`, `LevelFrame`, `ClassificationFrame`, `RaidTargetFrame`, `CastBarsContainer`, `AurasFrame`, `selectionHighlight`, `aggroHighlight`, and the heal-prediction textures `myHealPrediction`, `otherHealPrediction`, `totalAbsorb`, `totalAbsorbOverlay`, `myHealAbsorb`, `overAbsorbGlow`, `overHealAbsorbGlow`. `healthBar` has `LeftText`, `RightText`, `TextString`, `barTexture`, `bgTexture`. |
| Locked tables | Some Blizzard tables (for example `AurasFrame.debuffList`) can't be read by addons at all ("cannot be accessed while tainted"). |
| Auras | `C_UnitAuras.GetAuraDataByIndex` fails in combat on enemies with "Auras cannot be accessed when secret while tainted". Blizzard's `AurasFrame` still shows them. |
| Threat | `UnitThreatSituation("player", unit)` returns plain numbers. |
| Casts | No cast was active when probed. Blizzard's `CastBarsContainer` shows casts, which is enough for this design. |

## Approach

Restyle Blizzard's own plate (`plate.UnitFrame`). Don't build a second frame. The alternative, drawing our own plate on top, was rejected: restyling means less code, and Blizzard keeps handling secret values, auras and casts.

### Hard rules

1. **Only call widget methods on Blizzard objects** (`SetFont`, `SetStatusBarTexture`, `SetStatusBarColor`, `SetPoint`, `ClearAllPoints`, `SetAlpha`, `Hide`, `SetTexture`, `SetVertexColor`). **Never write fields onto Blizzard's tables** and never iterate them. Our per-plate state lives in our own weak-keyed tables.
2. **Health values only flow into widgets.** Never compare them, test them in a condition, or do arithmetic on them.
3. **Never read aura data.** Restyle and reposition `AurasFrame`, and let Blizzard choose which auras show.
4. Every Blizzard child is looked up defensively (`if uf.LevelFrame then ... end`), so a missing child skips that step and never raises an error.
5. Skip plates where `plate:IsForbidden()` is true.

## Components

| File | Job |
|---|---|
| `Core.lua` | Events, hooks, saved on/off flag, slash commands. Owns the weak tables. |
| `Style.lua` | One-time layout of a plate: textures, border, fonts, positions, hiding the level and classification. |
| `Health.lua` | The value text on the bar: enemy %, friendly missing health and its full-health alpha. |
| `Colors.lua` | Bar colour from reaction, class, tapped state, threat and role. Pure functions, taking plain values (no secrets). |

The TOC loads `Colors.lua`, `Health.lua`, `Style.lua`, `Core.lua` in that order. The files share one addon namespace table (`local _, ns = ...`).

### Events and hooks

- `ADDON_LOADED` (own name): load `HealerPlatesDB`, defaulting `enabled = true`. If disabled, register nothing else.
- `NAME_PLATE_UNIT_ADDED(unit)`: look up the plate. Apply `Style` once per `UnitFrame` (tracked in a weak table, because Blizzard reuses plate frames), then update the value text and colour for this unit.
- `NAME_PLATE_UNIT_REMOVED(unit)`: drop the unit from our unit-to-plate map.
- `UNIT_HEALTH`, `UNIT_MAXHEALTH` (nameplate units only): update the value text.
- `UNIT_THREAT_LIST_UPDATE`, `UNIT_THREAT_SITUATION_UPDATE`, `PLAYER_ROLES_ASSIGNED`: recolour affected plates.
- `hooksecurefunc("CompactUnitFrame_UpdateHealthColor", fn)`: when the frame's unit is a nameplate unit, re-apply our colour. Blizzard sets its colour first, and ours wins.
- `hooksecurefunc("CompactUnitFrame_UpdateName", fn)`: re-apply our name font, colour and position.
- If a hooked global doesn't exist, skip that hook. Style still applies on plate add.

## Look

```
  [aura][aura]                 AurasFrame, above the name
  Name                         left-aligned above the bar
  ████████████▒▒░░░░░░  64%    flat bar, value right-aligned inside
  [ic] Spell name ▓▓▓░░        Blizzard cast bar, directly under the bar
```

- **Bar:** `Interface\Buttons\WHITE8X8` texture, `bgTexture` set to black at 60% alpha, and a 1px black border made from four textures we create on `healthBar`.
- **Name:** `STANDARD_TEXT_FONT`, 10pt, `OUTLINE`, anchored `BOTTOMLEFT` to the bar's `TOPLEFT` with a 2px gap. White, except friendly players, who use their class colour.
- **Value text:** our own FontString on `healthBar`, `STANDARD_TEXT_FONT` 10pt `OUTLINE`, anchored `RIGHT` with a -3px inset. Blizzard's bar texts (`LeftText`, `RightText`, `TextString`) are hidden by setting their alpha to 0 every time we update, so a Blizzard `Show()` can't bring them back.
- **Hidden:** `LevelFrame`, `PlayerLevelDiffFrame`, `ClassificationFrame` (alpha 0).
- **Kept as is:** `RaidTargetFrame`, `selectionHighlight` (target), `aggroHighlight`, `CastBarsContainer`. The cast bar gets our flat texture only.
- **Auras:** `AurasFrame` re-anchored with `BOTTOMLEFT` to the name's `TOPLEFT`, 2px gap. Blizzard decides the contents: on enemies it shows your debuffs, and on friends it shows your buffs and HoTs.

### Value text

- **Enemies:** `SetFormattedText("%d%%", UnitHealthPercent(unit, false, CurveConstants.ScaleTo100))`. If that call fails, which we check with `pcall` once per session, fall back to hiding the value text.
- **Friends:** `SetText("-" .. AbbreviateNumbers(UnitHealthMissing(unit)))`, at full alpha. The text always shows, `-0` at full health included (the user asked to drop the full-health fade after trying it on 2026-09-29).
- **Friendliness** comes from `UnitIsFriend("player", unit)`, which is a plain boolean, re-checked on every update.

### Heal prediction and absorbs

Blizzard already draws these on friendly plates. We only recolour them, with `SetTexture(WHITE8X8)` plus `SetVertexColor`:

| Texture | Colour |
|---|---|
| `myHealPrediction` | `0.0, 0.9, 0.4` at 0.8 alpha |
| `otherHealPrediction` | `0.0, 0.6, 0.3` at 0.8 alpha |
| `totalAbsorb` | `1, 1, 1` at 0.6 alpha (Blizzard's `totalAbsorbOverlay` shimmer is kept) |
| `myHealAbsorb` | `0.6, 0.0, 0.0` at 0.7 alpha |

### Colours

Base colour (from `Colors.lua`):

| Unit | Colour |
|---|---|
| Friendly player | class colour (`RAID_CLASS_COLORS`) |
| Friendly NPC | `0.2, 0.8, 0.2` |
| Enemy player | class colour |
| Enemy NPC, hostile (`UnitReaction` ≤ 3) | `0.85, 0.2, 0.2` |
| Enemy NPC, neutral (`UnitReaction` = 4) | `0.9, 0.8, 0.2` |
| Tapped by others (`UnitIsTapDenied`) | `0.5, 0.5, 0.5` |

**Threat** overrides the base colour for enemy units only, when `UnitThreatSituation("player", unit)` isn't nil. Role comes from `UnitGroupRolesAssigned("player")`: `"TANK"` means tank, and anything else (including `"NONE"` or a missing API) means non-tank.

| Situation | Non-tank | Tank |
|---|---|---|
| 0 | base colour | orange `1.0, 0.5, 0.0` |
| 1 | yellow `1.0, 0.9, 0.0` | yellow |
| 2 | orange | yellow |
| 3 | magenta `1.0, 0.2, 0.8` | base colour |

A tapped-by-others unit is always grey, whatever the threat.

## Settings and commands

- `## SavedVariables: HealerPlatesDB`, with one field: `enabled` (default `true`).
- `/hp-help` lists commands.
- `/hp-status` prints enabled state, how many plates are styled, whether each hook was installed, whether the value APIs (`UnitHealthPercent`, `UnitHealthMissing`) exist, and whether the enemy % fallback kicked in.
- `/hp-on` and `/hp-off` set `enabled`, then print "Type /reload to apply." The addon doesn't undo a restyle live.

## Error handling

- Rules 1 to 5 above keep us out of the client's taint and secret-value errors.
- Each per-plate step (style, value, colour) runs in its own `pcall`. On failure, print one chat line per step per session: `Healer Plates: couldn't <step> (<error>)`. Never let the error reach the frame.

## Testing

`luajit tests/test_addon.lua`, with no WoW client, in the same style as DDN:

- **WoW stub:** `CreateFrame`, widgets that record calls (`SetText`, `SetFormattedText`, `SetAlpha`, `SetStatusBarColor`, `SetPoint`, `SetFont`), `hooksecurefunc`, a fake `C_NamePlate.GetNamePlateForUnit`, and fake `UnitFrame` objects with the child layout recorded above.
- **Secret values:** health APIs return a userdata-like object whose metatable raises an error on arithmetic, comparison, `tostring` and concatenation with a non-string. `AbbreviateNumbers` and `UnitHealthPercent` stubs accept it and return tagged values, so tests can assert what reached `SetText`. Any code that touches a health value fails the test.
- **Blizzard tables are read-only:** fake `UnitFrame` and child tables have a `__newindex` that raises an error. Writing a field onto them fails the test.
- **Cases:** friendly vs enemy value text; friendly text is always visible; each plate is styled once when reused for another unit; the threat × role table; tapped beats threat; class vs reaction colours; missing children are skipped without error; disabled registers nothing; `/hp-on`, `/hp-off` and `/hp-status` output.
- **Lint:** luacheck with `std = "lua51"`, the same as DDN.

**Manual in-game checklist before tagging:** enemy and friendly plates look right in the open world; friendly missing health shows `-0` at full health; heal prediction shows while you cast a heal; threat colours change during a pull; no Lua errors in a 5-minute session; `/hp-off` plus `/reload` gives back Blizzard's look.

## Release

The same pipeline as DDN: `.pkgmeta`, CI running tests and luacheck, and a tag `vX.Y.Z` that runs the BigWigs packager and attaches `hp-<version>.zip` to a GitHub Release (tags with `beta` or `alpha` become pre-releases). Upload that zip to CurseForge by hand. `docs/curseforge.md` holds the page text and `media/` the logo. `README.md` and `CHANGELOG.md` follow DDN's format.

Once Healer Plates is installed, delete the `PlateProbe` folder from the beta AddOns directory.

## Out of scope for v1

A settings panel; our own aura filtering (the client blocks it in combat); dispel highlights; an aggro warning on friends; any change to when plates show (that's DDN's job).

## Open questions for the beta

- Do friendly plates stay unforbidden, and do the hooks behave, inside dungeons and raids?
- Is cast data secret? (Only matters if we later restyle beyond Blizzard's cast bar.)
