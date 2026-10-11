# OlympusWatch

Someone spotted a PvP opponent nearby. Find the report, check with the player who saw them, and ask for help.

OlympusWatch is a World of Warcraft Forever addon for Alliance and Horde. It automatically discovers guild names containing **Olympus** and shares recent sightings of their visible, PvP-flagged opponents with other addon users.

## Features

- **Nearby:** your current outdoor zone's reports from the last 15 minutes, with approximate locations, age, guilds and reporter details.
- **Quick coordination:** map waypoint, whisper reporter, request help or request a party invite. The reporter chooses whether to invite you.
- **Readable crowds:** sightings are grouped into encounter areas instead of displaying thousands of player names.
- **Your guild list:** separate faction, visibility and source columns. Hide false matches or choose to show a globally excluded guild personally.
- **Separate rulesets:** PvP, PvE, RP and Hardcore lists and sharing channels stay separate.
- **One window:** Nearby, Guilds and Settings tabs, plus a draggable minimap button.

## Install

Download **OlympusWatch-0.8.0.zip** from [GitHub Releases](https://github.com/RelevantJesse/OlympusWatch/releases). Extract it so `Interface/AddOns/OlympusWatch/OlympusWatch.toc` exists in your Forever client, then reload WoW. Open it with `/ow` or the minimap button. No companion app or addon dependency is required for players.

Built for Forever **Interface 16001**. Other WoW clients are not supported by this release.

## Understanding reports

Locations approximate the observer's position. Reports can be up to 15 minutes old, enemies may have moved, and layers are unconfirmed. Counts describe observations, not the current population. Grouping does not guarantee a layer transfer. Sightings and help requests are disabled in cities and instances; guild discovery can still occur there.

In-game sharing requires reachable online users on the same faction and ruleset. The addon does not contact an external database directly. Personal visibility choices survive synchronization.

## Documentation and source

See the [addon guide](Forever/OlympusWatch/README.md) for commands, limits and synchronization details. `tools/` contains the owner companion and authority source for inspection; their credentials and database are deliberately absent. Regular users do not need to run these tools.

Report bugs through [GitHub Issues](https://github.com/RelevantJesse/OlympusWatch/issues), including version, ruleset and reproduction steps. Please remove private account information from screenshots or logs.

Original code and artwork: Samrin / RelevantJesse. All rights reserved. The bundled `pure_lua_SHA` code retains its [MIT license](Forever/OlympusWatch/THIRD_PARTY_LICENSES.txt).
