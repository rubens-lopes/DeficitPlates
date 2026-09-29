# Healer Plates: design

Date: 2026-09-28
Status: approved; revised 2026-09-29 after in-game testing (see "Revision")

## Goal

A World of Warcraft: Forever addon for healers: friendly nameplates show **missing health** (for example `-118`, and `-0` at full health) in place of Blizzard's health number. Nothing else on any plate changes. It replaces Plater, which has too many settings and is buggy on Forever. It is a sibling of Dynamic Display Nameplate (DDN) and published on CurseForge. It does not depend on DDN: DDN decides when plates show, and Healer Plates adds missing health to friendly ones.

## Revision (2026-09-29)

The first build restyled Blizzard's plates in Plater's default look (flat bars, border, threat colours, enemy amount and percent). After testing it in game, the user chose to drop the restyle: every issue found came from it (auras moved, colours needed keeping, Blizzard resets the layout and caches bar colours), while Blizzard's own compact plate already looks good. The addon now only adds missing health to friendly plates. Threat colours and the enemy percent were given up knowingly.

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

Leave Blizzard's plate (`plate.UnitFrame`) as it is. On friendly plates, add one FontString on `healthBar`, in the spot and font of Blizzard's health number, showing missing health, and hide Blizzard's health texts. On every other plate, show Blizzard's texts and hide ours.

### Hard rules

1. **Only call widget methods on Blizzard objects** (`SetAlpha`, `GetFont`, `CreateFontString`). **Never write fields onto Blizzard's tables** and never iterate them. Our per-plate state lives in our own weak-keyed table.
2. **Health values only flow into widgets.** Never compare them, test them in a condition, or do arithmetic on them.
3. **Never read aura data.**
4. Every Blizzard child is looked up defensively, so a missing child skips that step and never raises an error.
5. Skip plates where `plate:IsForbidden()` is true.
6. Unit state (`UnitIsFriend`) may be secret inside instances. A secret is treated as unknown (not a friend), via `issecretvalue`.

## Components

| File | Job |
|---|---|
| `Health.lua` | `IsFriend(unit)`, `CreateText(bar)` and `Update(bar, text, unit, friend)`. |
| `Core.lua` | Events, the saved on/off flag, slash commands. Owns the weak table of our texts and the unit-to-plate map. |

The TOC loads `Health.lua`, then `Core.lua`. They share one addon namespace table (`local _, ns = ...`).

### Events

- `ADDON_LOADED` (own name): load `HealerPlatesDB`, defaulting `enabled = true`. If disabled, register nothing else.
- `NAME_PLATE_UNIT_ADDED(unit)`: look up the plate, skip forbidden ones, remember it, and refresh it.
- `NAME_PLATE_UNIT_REMOVED(unit)`: forget the unit.
- `UNIT_HEALTH`, `UNIT_MAXHEALTH`, `UNIT_FACTION` (shown plates only): refresh.
- No hooks on Blizzard functions.

Refresh: if the unit is a friend and the plate has no text of ours yet, create it (once per `UnitFrame`, because Blizzard reuses plate frames). Then update it.

## Look

- **Text:** our FontString on `healthBar`, anchored `RIGHT` with a -3px inset, right-justified, using the font of Blizzard's `RightText` (or `TextString`), falling back to `STANDARD_TEXT_FONT` 10 `OUTLINE`.
- **Friends:** `SetText("-" .. AbbreviateNumbers(UnitHealthMissing(unit)))` at full alpha; Blizzard's `LeftText`, `RightText` and `TextString` at alpha 0 (alpha, because Blizzard calls `Show()` on them).
- **Everyone else:** our text at alpha 0; Blizzard's texts at alpha 1, so a reused plate gets its number back.
- Everything else (bar, colours, name, level, auras, cast bar, heal prediction, highlights) is Blizzard's.

## Settings and commands

- `## SavedVariables: HealerPlatesDB`, with one field: `enabled` (default `true`).
- `/hp-help` lists commands.
- `/hp-status` prints enabled state, how many friendly plates carry our text, and whether `UnitHealthMissing` and `AbbreviateNumbers` exist.
- `/hp-on` and `/hp-off` set `enabled`, then print "Type /reload to apply."

## Error handling

Each refresh runs in `pcall`. On failure, print one chat line per session: `Healer Plates: couldn't show missing health (<error>)`. Never let the error reach the frame.

## Testing

`luajit tests/test_addon.lua`, with no WoW client:

- **WoW stub:** event frame, widgets that record calls, `C_NamePlate.GetNamePlateForUnit`, fake `UnitFrame` objects with the child layout above.
- **Secret values:** health APIs return an object that raises on arithmetic, comparison and `tostring`; `issecretvalue` recognises it.
- **Blizzard tables are read-only:** writing a field onto a fake Blizzard widget raises.
- **Cases:** friendly text and hidden Blizzard texts; font and anchor; nothing else touched; enemies untouched; plate reuse both ways; events; faction change; forbidden plates; secret friendliness; missing children; one warning per failure; commands.
- **Lint:** luacheck with `std = "lua51"`.

**Manual in-game checklist before tagging:** friendly plates show `-X` (and `-0` at full health) where Blizzard's number was; enemy plates look exactly like Blizzard's; no Lua errors in a 5-minute session; `/hp-off` plus `/reload` gives back Blizzard's number.

## Release

The same pipeline as DDN: `.pkgmeta`, CI running tests and luacheck, and a tag `vX.Y.Z` that runs the BigWigs packager and attaches `hp-<version>.zip` to a GitHub Release (tags with `beta` or `alpha` become pre-releases). Upload that zip to CurseForge by hand. `docs/curseforge.md` holds the page text and `media/` the logo. `README.md` and `CHANGELOG.md` follow DDN's format.

## Out of scope for v1

A settings panel; any restyling; threat colours; enemy health text changes; aura changes; any change to when plates show (that's DDN's job).

## Open questions for the beta

- Do friendly plates stay unforbidden, and is `UnitIsFriend` plain, inside dungeons and raids?
