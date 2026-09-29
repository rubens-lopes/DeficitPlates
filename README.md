# Healer Plates

A World of Warcraft: Forever addon that gives nameplates Plater's default look, for enemies and friends alike, with one change for healers: friendly plates show **missing health** (`-4.2K`) in place of a percentage (`-0` at full health).

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
