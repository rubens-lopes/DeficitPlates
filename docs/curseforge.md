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

Missing health on friendly nameplates, for healers. Everything else stays Blizzard's.

## Description

Healer Plates changes one thing on World of Warcraft: Forever nameplates: on friendly plates, the number on the bar is **missing health** (for example `-118`), so you can see at a glance who needs healing. Someone at full health shows `-0`.

Everything else stays exactly as Blizzard draws it, on friendly and enemy plates alike: colours, auras, cast bars and heal prediction.

**No setup**

Install it and it works. There's no settings panel. Chat commands:

- `/hp-help` lists the commands.
- `/hp-status` shows what the addon found on this client. Include it in bug reports.
- `/hp-off` leaves Blizzard's nameplates alone after your next `/reload`. `/hp-on` turns missing health back on.

**Good to know**

- Pairs well with Dynamic Display Nameplate, which decides *when* plates show.
- This is a beta. It hasn't been tested inside dungeons and raids yet.

**Compatibility**

- World of Warcraft: Forever (1.60.x)
- Addons that replace nameplates entirely (Plater, Kui, and so on) draw their own plates, so Healer Plates has nothing to change there.

**Source and issues**

The code is on [GitHub](https://github.com/rubens-lopes/HealerPlates). If something goes wrong, open an issue there and include the `/hp-status` output and any error text the addon printed in chat.
