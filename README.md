# Friends & Foes

A WoW Forever addon that keeps your friend group connected: see your Battle.net friends' level-ups,
epic loot and world PvP fights, and put a bounty on everyone who ganks your group.

## What it does
- **Friends' progress:** level-ups, epic loot and new epic gear. Big moments (level 60, epic BoE,
  revenge, kill streaks) always pop up.
- **World PvP alerts:** a friend is attacked, attacks someone, is killed, or gets a kill, with who
  and where. When several of you kill the same enemy, there is one toast and one Feed line
  naming everyone ("Rogz Fang and Buddy Pal killed Bob Gank"); a second one only for a new death
  (they got back up and died again).
- **Hitlist:** anyone who kills you or a friend, or attacks one of you first.
  - Hover them to see who of your friends they killed and how often.
  - They get a skull on their nameplate.
  - You're alerted when you or a friend spots them.
  - **Add by name:** the Hitlist tab's **Add...** button (or `/fnf hitlist add <name>`) puts any
    enemy player on it, no target needed (names are letters, up to two words like "Ru Mia", 2-24
    characters; not you or your friends). Their class, level and guild fill in when you first see
    them. A name you typed is never forgotten by itself (only you remove it), and it isn't passed
    to friends until they've done something.
  - Entries grey out after 30 days unseen. Three options (attackers, one-time killers, repeat
    killers) set how long each kind stays: 1 week to 1 year, or forever. By default attackers
    are forgotten after 2 weeks and killers are kept forever; an open bounty keeps anyone.
- **Wanted posters & notoriety:** an enemy's profile is a Wanted poster: their face (once you've
  seen them), what they've done to your group, and their notoriety (points, just for fun). It
  grows with every murder and attack (and cools when they go quiet); whoever kills them claims
  it, shared equally with the friends who get the kill too (a friend who just heals or buffs you
  during the fight counts, without getting a kill). Killing the same player again within 30
  minutes is worth less each time, so camping doesn't pay. Level counts: grey players give nothing,
  higher-level players give more. Ganking someone who has Resurrection Sickness gives nothing,
  unless they are far above your level. Enemies get ranks (Nuisance to Public
  Enemy), you earn titles (Tracker to Legend), and your own notoriety fades 10% for each idle week.
- **Bounty board:** put a bounty on an enemy player yourself, in gold, silver and copper, open
  for as many days as you pick (1-30). It goes on your hitlist and your friends' Bounty board,
  with a toast. It's a promise between friends: when one of you kills them, everyone gets a
  toast, you pay whoever did it by trade in the game, then mark it paid. If several of you got
  the kill (within a minute), the gold is split equally. Whoever landed the killing blow gets the
  credit when the game says who it was. Finished bounties stay on the board with who closed
  them. The add-on never moves gold, and it's only ever in-game gold. Up to 5 open at a time.
  - **By name:** Post bounty needs no target: it opens a small window for the player's name, the
    amount, the days and an optional message (it fills in your target's name). A bounty on a name
    puts them on your hitlist as a typed entry.
  - **A message:** up to 60 characters, put through the language filter before it's sent and again
    when it arrives; shown when you hover the row on the Bounty board, in the profile's bounty
    line tooltip and in the "bounty posted" toast.
  - **Bounty target spotted:** when you see someone with an open bounty (anyone's) on them, you
    get a big raid-warning message in the middle of the screen with their name, the reward and
    the zone, plus a longer toast with a louder sound and a red edge (once per player per 5
    minutes). When a friend sees them, you get the same louder toast, without the big message.
    It follows the Bounty board alert setting: off shows nothing, chat only a chat line.
- **Friends:** you and your friends who run the add-on, ranked by world PvP kills, with deaths,
  K/D and notoriety, all-time, Bounty board gold collected, and where they are now. Each player
  reports their own numbers. Friends' characters below level 15 (bank alts) are hidden by
  default (an option).
- **Shared groups:** named groups whose stats you follow together on the Friends tab, with group totals. Members
  pass each other's numbers along, so not everyone needs to be friends with everyone.
- **Victims:** who you and each friend have killed, and how often (sortable); for an enemy,
  which of your friends they killed. Opens from a profile. A friend's own list is fetched from
  them.
- **Stats:** a **Stats** button on your own profile opens a one-page view of this character's kill log (what your profile doesn't show): four headline tiles (kills logged, best streak with your current run, average life between PvP deaths with your current life (from 3 deaths), average victim level with how far above or below you that is, from 5 kills with a known level), a "When you hunt" column (today, last 7 days, last 30 days, busiest day and hour from 20 kills, kills per hour played from 1 hour played) and two bar charts, kills by level gap (Skull, Higher, Even, Lower, Grey, with each share) and your top zones. Times, zones and levels are counted from version 1.0.1 on. A selector at the top (All, <20, 20s ... 60) shows it for the time you were that level; each character keeps running totals per bracket. Only you see it; nothing is sent to friends.
- **Profiles:** click a name for a friend's or enemy's page: K/D and rank, nemesis, where a
  friend is right now, who an enemy has killed, the bounties on them, and recent PvP.
- **Tracking:** kills and deaths per player, and a weekly summary with your nemesis (the enemy who
  killed you most; on a tie, the one who killed you most recently).
- **Messages:** with flavor (*"Rogz killed Bob again (3rd) · Tarren Mill"*) or short
  (*"Bob killed by Rogz · Duskwood"*).
- **Toasts** in four styles: Modern, Classic, Alliance and Horde. You can set their size, duration,
  position and stacking.

Everything is set up in **Options → AddOns → Friends & Foes** (start with **Test alerts** to see them):
Four pages:
- **Alerts:** Test alerts; four groups of alerts (friends' fights, hitlist sightings, friends'
  progress, the Bounty board), each a toast, chat line or off, with or without sound; five
  sounds to pick (a friend in trouble, a friend's kill, sightings, progress, bounties); how often
  level-ups show; what happens in dungeons, raids and battlegrounds (one setting for all three);
  and combat.
- **Appearance:** toast style, size, duration, position and stacking; message style; chat tab;
  weekly summary; the minimap button.
- **Friends & sharing:** what you share, where your own PvP is tracked, your alert list (which
  friends you exchange alerts with), hiding low-level characters on the Friends tab, the
  hitlist skull and tooltip, and how long attackers, one-time killers and repeat killers stay
  on your hitlist.
- **Advanced:** debug logging and the debug report.

## Install
- **CurseForge app** or **WowUp** (via Wago): search for *Friends & Foes*. Set the game to
  **WoW Forever**. Updates then install automatically.
- **WowUp from GitHub:** *Install from URL* → `https://github.com/ptoreki/friends-and-foes`.
- **By hand:** download the zip from [Releases](https://github.com/ptoreki/friends-and-foes/releases)
  and extract it into `World of Warcraft\_forever_\Interface\AddOns\`.

Then log in and type `/fnf`, or click the minimap button (drag it round the minimap, or
Shift-drag it anywhere).

**Your friends need the addon too.** It works with Battle.net friends who are online in WoW Forever
on your faction. You don't need to group, share a server, or be in the same zone.

## Commands
| Command | What it does |
|---|---|
| `/fnf` | Open or close the window (Hitlist, Bounty board, Friends, Feed, Profile) |
| `/fnf bounty [name] <amount> [days] [message]` | Put a bounty on your target, like `/fnf bounty 10g 50s 3d` (7 days if you leave it out), or on a name with no target: `/fnf bounty Ru Mia 10g 3d Caught me AFK` (message up to 60 characters). With no amount it opens the Post bounty window |
| `/fnf hitlist add <name>` | Put a player on your hitlist by name, like `/fnf hitlist add Ru Mia` |
| `/fnf minimap` | Show or hide the minimap button |
| `/fnf minimap reset` | Put the minimap button back on the minimap |
| `/fnf board` | Open the Friends tab (the ranking) |
| `/fnf groups [new\|invite\|join\|decline\|leave\|remove ...]` | List your shared groups, or manage one (see `/fnf groups`) |
| `/fnf profile [name]` | Open a profile (yours if no name) |
| `/fnf options` | Open the options |
| `/fnf alerts [name\|all]` | Your alert list (also in Options): open it, add or remove a friend, or go back to everyone (`/fnf group` works too) |
| `/fnf unlock` / `/fnf lock` | Move the toasts |
| `/fnf size <70-150>` / `/fnf duration <2-10>` | Toast size and how long toasts stay |
| `/fnf chat <tab>` | Which chat tab gets the chat lines |
| `/fnf status` | Which friends were found and what works on your client |
| `/fnf test` (or `/fnf sim`) | Show one sample of each alert and a chat line. Nothing is recorded or sent |
| `/fnf debug` / `/fnf debug clear` | Debug logging on/off, or clear the log |
| `/fnf report` | A debug report to copy and paste into a bug report |
| `/fnf tour` | The short tour from the first time you opened the window |
| `/fnf new` (or `whatsnew`, `changes`) | The patch notes for this version (also shown once after an update) |

## Reporting a bug
1. Turn on **Debug logging** (Options → Advanced, or `/fnf debug`).
2. Play until it happens, then type `/fnf report`.
3. Copy the box (it's all selected: Ctrl+C) and paste it into an
   [issue](https://github.com/ptoreki/friends-and-foes/issues) with a short description.

Debug logging turns itself off after 7 days.

## Good to know
- Everything runs inside the game, using the game's own addon messages. There are no accounts,
  websites or outside programs.
- WoW Forever doesn't say who died when you get honor, so a *kill* means any honorable kill
  you got honor for, and the victim is worked out from what's on your screen (it can end up
  unnamed). When the game reports your own killing blow (or your pet's), the victim is named
  exactly and the kill is marked "(killing blow)".
- Alerts are live only, but you don't miss what friends did while you were offline: when you log
  in, and when a friend comes online later, they send what happened to them in the last week
  (their latest 250 events, including what their other characters did). It goes into your Feed,
  hitlist and victims lists quietly, with one chat line, no toasts. If a friend drops off and
  comes back, or goes quiet for an hour, you ask them for what you missed. Friends you're never
  online with still reach you: other friends pass their events and numbers on, if they allow it
  ("Friends may pass on my events" in the options). When you meet a friend you also swap a
  short hitlist hello (at most once a week), added quietly.
- Options can't be opened during combat. That's a game rule.

## Development
- `npm install`, then `npm test`. That runs a Lua syntax check, checks every string the code uses
  is defined (`tests/locale.js`), then loads the whole addon in a Lua VM with a mocked WoW API
  (`tests/mock.lua`) and runs the tests (`tests/test.lua`).
- Where things are: messages and their versions in `Comm.lua` (`Comm.SCHEMA`, `Comm.KINDS`),
  saved data and its upgrade steps in `Saved.lua`, the window in `UI.lua` (lists, tabs),
  `UIProfile.lua` (profiles, Wanted posters), `UIAlerts.lua` (the alert list window),
  `UIWidgets.lua` (buttons, layout) and `UISlash.lua` (commands). Translating: see the top of `Locale.lua`.
- `npm run package` builds a local zip in `dist/`.
- Releases are automatic: push a `vX.Y.Z` or `vX.Y.Z-beta` tag. A GitHub Action then runs the tests
  and uploads the zip to CurseForge, Wago and GitHub Releases. See [PUBLISHING.md](PUBLISHING.md).
- Design notes are in [SPEC.md](SPEC.md), and version history is in [CHANGELOG.md](CHANGELOG.md). Where to look up the add-on API (and what WoW Forever restricts) is in [API-SOURCES.md](API-SOURCES.md).

## License
Copyright (C) 2026 ptoreki.

Friends & Foes is free software: you can redistribute it and/or modify it under the terms of the
[GNU General Public License](LICENSE) as published by the Free Software Foundation, either
version 3 of the License, or (at your option) any later version. It is distributed in the hope
that it will be useful, but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the license for details.

The language filter is [ProfanityLib](https://github.com/Deathwing/ProfanityLib) by Deathwing
(GPLv3), bundled unchanged in `FriendsAndFoes/Libs/` (see `SOURCE.txt` there for the exact version).
