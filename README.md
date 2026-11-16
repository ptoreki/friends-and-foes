# Friends & Foes

A WoW Forever addon that keeps your friend group connected: see your Battle.net friends' level-ups,
epic loot and world PvP fights, and keep a shared hitlist of everyone who ganks your group.

> **Beta.** Being tested with real players. Report anything odd (see *Reporting a bug*).

## What it does
- **Friends' progress:** level-ups, epic loot and new gear. Big moments (level 60, epic BoE,
  revenge, kill streaks) always pop up.
- **World PvP alerts:** a friend is attacked, attacks someone, is killed, or gets a kill, with who
  and where.
- **Hitlist:** anyone who kills you or a friend.
  - Hover them to see who of your friends they killed and how often.
  - They get a skull on their nameplate.
  - You're alerted when you or a friend spots them.
  - Entries fade after 90 days unseen.
- **Leaderboard:** world PvP kills, deaths and K/D for you and your friends, all-time. Each player
  reports their own numbers.
- **Shared groups:** named groups whose stats you follow together, with group totals. Members
  pass each other's numbers along, so not everyone needs to be friends with everyone.
- **Kill lists:** who you and each friend have killed, and how often (sortable); for an enemy,
  which of your friends they killed. A friend's own list is fetched from them.
- **Profiles:** click a name for a friend's or enemy's page: K/D and rank, nemesis, most wanted,
  where a friend is right now, who an enemy has killed, and recent PvP. Set a most wanted enemy
  for your friends to see.
- **Tracking:** kills and deaths per player, and a weekly summary with your nemesis.
- **Messages:** with flavor (*"Rogz killed Bob again (3rd) · Tarren Mill"*) or short
  (*"Bob killed by Rogz · Duskwood"*).
- **Toasts** in four styles: Modern, Classic, Alliance and Horde. You can set their size, duration,
  position and stacking.

Everything is set up in **Options → AddOns → Friends & Foes**:
- each event: toast, chat line or off, with or without sound, and which sound
- how often level-ups show, and which gear quality counts
- what happens in dungeons, raids and battlegrounds
- what you share, and with which friends

## Install
- **CurseForge app** or **WowUp** (via Wago): search for *Friends & Foes*. Set the game to
  **WoW Forever**, and set the addon's release channel to **Beta** while it's in beta. Updates then
  install automatically.
- **WowUp from GitHub:** *Install from URL* → `https://github.com/ptoreki/friends-and-foes`.
- **By hand:** download the zip from [Releases](https://github.com/ptoreki/friends-and-foes/releases)
  and extract it into `World of Warcraft\_forever_\Interface\AddOns\`.

Then log in and type `/fnf`, or use the minimap's addon menu.

**Your friends need the addon too.** It works with Battle.net friends who are online in WoW Forever
on your faction. You don't need to group, share a server, or be in the same zone.

## Commands
| Command | What it does |
|---|---|
| `/fnf` | Open or close the window (Hitlist, Leaderboard, Enemies, Friends, Feed, Profile) |
| `/fnf board` | Open the Leaderboard |
| `/fnf groups [new\|invite\|join\|decline\|leave\|remove ...]` | List your shared groups, or manage one (see `/fnf groups`) |
| `/fnf profile [name]` | Open a profile (yours if no name) |
| `/fnf options` | Open the options |
| `/fnf alerts [name\|all]` | Your alert list: show it, add or remove a friend, or go back to everyone (`/fnf group` works too) |
| `/fnf unlock` / `/fnf lock` | Move the toasts |
| `/fnf size <70-150>` / `/fnf duration <2-10>` | Toast size and how long toasts stay |
| `/fnf chat <tab>` | Which chat tab gets the chat lines |
| `/fnf status` | Which friends were found and what works on your client |
| `/fnf share` | Send your hitlist to your friends |
| `/fnf sim all [self]` / `/fnf sim stop` / `/fnf sim clear` | Simulate every alert with fake data (`self` also sends it to friends) |
| `/fnf debug` / `/fnf debug clear` | Debug logging on/off, or clear the log |

## Reporting a bug
1. Turn on **Debug logging** (Options → Advanced, or `/fnf debug`).
2. Play until it happens, then type `/reload`.
3. Send `World of Warcraft\_forever_\WTF\Account\<account>\SavedVariables\FriendsAndFoes.lua`
   with a short description, or open an [issue](https://github.com/ptoreki/friends-and-foes/issues).

Debug logging turns itself off after 7 days.

## Good to know
- Everything runs inside the game, using the game's own addon messages. There are no accounts,
  websites or outside programs.
- Addons can't see who landed the killing blow in WoW Forever, so a *kill* means any honorable
  kill you got honor for.
- Alerts are live only, but you don't miss what friends did while you were offline: when you log
  in, and when a friend comes online later, they send what happened to them in the last 24 hours
  (up to 100 events). It goes into your Feed, hitlist and kill lists quietly, with one chat line,
  no toasts. Friends you're never online with still reach you: other friends pass their events
  on, if they allow it ("Friends may pass on my events" in the options).
- Options can't be opened during combat. That's a game rule.

## Development
- `npm install`, then `npm test`. That runs a Lua syntax check, then loads the whole addon in a Lua
  VM with a mocked WoW API (`tests/mock.lua`) and runs the tests (`tests/test.lua`).
- `npm run package` builds a local zip in `dist/`.
- Releases are automatic: push a `vX.Y.Z` or `vX.Y.Z-beta` tag. A GitHub Action then runs the tests
  and uploads the zip to CurseForge, Wago and GitHub Releases. See [PUBLISHING.md](PUBLISHING.md).
- Design notes are in [SPEC.md](SPEC.md), and version history is in [CHANGELOG.md](CHANGELOG.md).

## License
Copyright (C) 2026 ptoreki.

Friends & Foes is free software: you can redistribute it and/or modify it under the terms of the
[GNU General Public License](LICENSE) as published by the Free Software Foundation, either
version 3 of the License, or (at your option) any later version. It is distributed in the hope
that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the license for details.

The language filter is [ProfanityLib](https://github.com/Deathwing/ProfanityLib) by Deathwing
(GPLv3), bundled unchanged in `FriendsAndFoes/Libs/` (see `SOURCE.txt` there for the exact version).
