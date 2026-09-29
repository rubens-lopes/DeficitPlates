# Healer Plates

A World of Warcraft: Forever addon for healers. Friendly nameplates show **missing health** (for example `-118`, or `-0` at full health) in place of Blizzard's health number.

That's the only change. Enemy and friendly plates otherwise stay exactly as Blizzard draws them: colours, auras, cast bars, heal prediction and all.

## Commands

- `/hp-help` lists the commands.
- `/hp-status` shows what the addon found on this client. Include it in bug reports.
- `/hp-off` leaves Blizzard's nameplates alone after your next `/reload`. `/hp-on` turns missing health back on.

## Works with

[Dynamic Display Nameplate](https://github.com/rubens-lopes/DynamicDisplayNameplate) decides when plates show. Healer Plates adds missing health to friendly plates. Use both, or either one.

## Install

Get it from CurseForge, or copy this folder to `World of Warcraft/_classic_beta_/Interface/AddOns/HealerPlates` for the Forever beta.

## Development

```bash
luajit tests/test_addon.lua
luacheck .
```

Tagging `vX.Y.Z` runs the BigWigs packager in GitHub Actions and attaches `hp-<version>.zip` to a GitHub Release. Tags containing `beta` or `alpha` become pre-releases. Upload that zip to CurseForge by hand.
