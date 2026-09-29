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

Healer Plates gives World of Warcraft: Forever nameplates the clean look of Plater's defaults, and uses the same look on friendly plates. On friendly plates, the number on the bar is **missing health** (for example `-4.2K`), so you can see at a glance who needs healing. Someone at full health shows `-0`.

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
