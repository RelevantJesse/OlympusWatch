# OlympusWatch 0.8.0 — Forever

Track recent sightings of visible, PvP-flagged opponents belonging to watched guilds. Works for Alliance and Horde; Interface 16001, no addon dependencies.

## Nearby encounters

`/ow` or a left click on the minimap button opens your current zone's encounters from the last 15 minutes, newest first. Under two minutes is marked Recent; older reports are history, not a live enemy location. Select a row to highlight it and show location, guild, reporter and actions in the same window. Map sets a waypoint; contact and help actions enable only for suitable selections. `/ow nearby` and minimap right click open the encounter panel directly. `/ow operations` and `/ow battles` are compatibility aliases for Nearby.

Cities are excluded from sighting collection, encounter displays, help alerts, and invite requests. Known capital city UI map IDs and their child maps are checked explicitly. Outdoor inns remain eligible even when resting. Guild discovery still works in cities, including friendly and unflagged members.

Reports use approximate observer locations grouped into 10% coordinate cells. Player identities are sampled, not listed in the main interface. Each area retains at most 256 sampled players, 16 peer guild summaries, and three displayed guild names; + indicates additional observations. The cache holds at most 64 areas, individual diagnostics at most 100 sightings, and each zone map at most 16 markers. Counts describe reports across the history window, not current crowd size or a server census. Adjacent cells and different layers may overlap.

The inline encounter details offer:

- Map: place a waypoint at the approximate reported location.
- Request help: broadcast a five-minute call for assistance based on your own sighting from the last two minutes. Ordinary users can do this. Refresh after spotting opponents again; requests have a one-minute cooldown.
- Whisper reporter: open an editable whisper asking if the encounter is still active.
- Request invite: send an addon whisper to the reporter (or current help requester). They see a request and choose Invite or Dismiss. Requests expire after two minutes; outgoing requests have a 30-second cooldown. Nothing automatically accepts a request or invites players.

Layers remain unconfirmed. Party invitations can be attempted through the normal game API, subject to leadership, capacity and game restrictions; grouping does not guarantee a layer transfer. Invite requests require both players to use this version and remain in the same outdoor zone. Peer reports and help requests are advisory claims, not verified server telemetry.

Scheduled operations and their companion tab have been retired. Old signed operation records remain compatible with history replay but are not displayed or announced.

## Guilds and shared control

Guilds > Reset my visibility choices (or `/ow reset-personal`) clears personal hides and Show anyway overrides for your current ruleset, retains the verified global list and discoveries, and requests peer updates. Other rulesets and scanning/sharing settings are preserved. No companion or reload is needed. New global changes still require a reachable online peer carrying them.

Seeing any readable guild containing `olympus` adds it automatically, with a local chat notice. The Guilds tab has separate Guild, Faction, Visibility and Source columns. Visibility distinguishes Visible, Hidden by you, Excluded globally and Shown by you. Hide affects only you and survives peer sync. Show excluded lets you Restore a personal hide. Auto-discovery and peer messages cannot restore personal hides or change signed global exclusions. Show excluded offers Show anyway for global exclusions: this saved, ruleset-specific personal override makes the guild visible only to you. Hide clears the override.

The owner companion manages the Oracle guild database, privileged users and audited global changes. Only the owner can grant/revoke access. Owner or granted users can change the global guild list; global exclusions have no hourly cooldown. Signed history supports rollback. No private credential or signing key is included in the addon.

PvP, PvE, RP and Hardcore have separate saved lists, channels, signed histories and Oracle databases. Unknown rulesets do not exchange network data. Old unclassified guilds remain legacy data rather than being assigned to a ruleset without evidence.

## Sharing and Oracle

Addon sharing uses your party/raid, guild and the temporary `OlympusWatch<ruleset><faction>` channel. Reach depends on the game's channel routing and online peers. Peer catalogue/history requests run every 30 seconds, with bounded replies; sync is gradual. Live encounters are shared only from local observations and are not relayed across peers or factions.

The owner companion automatically uploads newly saved guild discoveries for its selected ruleset on startup, refresh, ruleset change and every 15 seconds while open. WoW writes discoveries to disk on `/reload` or logout. Click Update installed addon in the companion, then `/reload`, to load Oracle's public catalogue and signed changes into your addon for peer distribution. Individual addons do not read Oracle directly. Addon upgrades preserve the installed public snapshot.

Settings and guilds persist in account SavedVariables. Encounters are session-only; online reporters can supply their still-recent observations again. Enable enemy nameplates with V. Detection pauses in instances or when scanning is off, and cannot read data restricted by the client.

Scanning, sharing, network and alert controls live in Settings. Only one Nearby tab exists. Pagination is hidden for a single page; invite requests expand below the panel only when pending.

## Commands and installation

Extract the ZIP into the Forever client's Interface/AddOns directory. Reload WoW after updating.

- `/ow show|hide`, `/ow nearby`: open/close the main or encounter panel.
- `/ow add <guild>`, `/ow remove <guild>`: restore/watch or hide a guild personally.
- `/ow on|off`, `/ow sharing on|off`, `/ow network on|off`, `/ow alerts on|off`: settings.
- `/ow clear`: clear session encounters and requests, retaining guild choices.
- `/ow minimap`: toggle minimap icon. Drag it to reposition.
- `/ow debug`: detection and network diagnostics.

Map-background right click still zooms out. Addon pins have independent click handling for Leatrix Maps interoperability. In-game checks are needed for actual channel delivery, visual layout and invitations.

Hash.lua includes the MIT-licensed pure_lua_SHA implementation; see THIRD_PARTY_LICENSES.txt. Icon art is original; matching CurseForge artwork lives outside the addon package in Forever/branding.
