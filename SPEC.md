# Friends & Foes — Design notes (1.0)

How the add-on works and why, for whoever changes it next. The README says what it does for
players, the CHANGELOG says what changed when, and the code comments say the details. When this
file and the code disagree, the code is right, so fix this file.

WoW Forever add-on (interface 16001, `_forever_\Interface\AddOns\FriendsAndFoes`).

## Platform constraints
- Forever runs the modern (Midnight 12.x) add-on API. **There is no combat log**, and some combat
  values come back as *secret values*.
- So each client reports **only its own events** and sends them to friends. No client watches
  other players' fights.
- Every value that might be secret is checked with `issecretvalue` before use, and every event
  handler runs through `ns.Try` (`pcall`). A signal that turns out unreadable degrades its feature
  (recorded in `ns.caps`), never errors.
- **Forever has no realms.** `GetRealmName` returns an internal server name that differs between
  friends who play together, so it's ignored. Everything lives in one store, `realms.Forever`.
- **Names:** every character is "First Last". Only the pair is unique (region-wide). First names
  are shared, and neither part has spaces or hyphens. `UnitName` returns `(first, surname)`. The
  key is always "First Last" (`ns.CleanName`). A bare first name resolves to a full one only when
  exactly one matches, and is folded in later when it can be.
- Blizzard's add-on policy, ToU and EULA are followed **by a margin**: low message traffic, no
  outside servers or programs, BattleTags and notes never leave your Battle.net friends, and text
  other players typed passes the language filter before it's shown.

## Friends and sync
- A **friend** is a Battle.net friend who is online in WoW Forever, on your faction, and has the
  add-on. Other-faction friends are left out: nothing is sent to them and their events are
  dropped. You are never your own friend.
- **Alert list** ("picks", `FriendsAndFoesDB.group`, by BattleTag). When it's empty, every friend
  counts. Otherwise alerts go to and come from picked friends only. Groups, kill lists and
  profiles still flow with everyone.
- **Route:** Battle.net game data (`BNSendGameData`) only. An addon whisper is used only if
  Battle.net messaging is missing, and whispers from older versions are still accepted. The
  receiver drops duplicates by `sender:id`.
- **Wire format (protocol 3):** `3\tKIND\tID\tsender\tclass\tlevel\tversion\t<fields...>`, at most
  255 bytes. If a message is too long, guild names are dropped, then helpers one at a time
  (`Comm.Fit`). The sender name in the header must match the first name the route reports.
- **Message rule:** new fields only go on the end, and kinds are never reused. Older clients
  ignore unknown kinds and extra fields. `Comm.SCHEMA`, `Comm.KINDS` and `Comm.FEATURES` are the
  reference.
- **Throttle:** one token bucket per route (8 tokens, 1 per second) with three priorities: PvP,
  then normal, then bulk. The queue holds at most 400; bulk is dropped first, PvP never.
- **Simulation:** IDs starting with `S` are simulated. They go to a separate store
  (`FriendsAndFoesDB.sim`), never to real data, notoriety or the Bounty board. Your own `/fnf sim` switches
  the window to it. A friend's simulated events don't; one chat line says they arrived.
- **Text from friends** is cleaned before use (`Events.Clean`, `ns.SafeLink`, `ns.CleanName`):
  zones and guilds become plain text, classes must be class tokens, names with escape codes are
  dropped, and an item link that isn't a plain item link is cut to its name.

## Message kinds
| Kind | When | Fields |
|---|---|---|
| LVL | you level up | level |
| LOOT | you loot or craft an epic+ BoE/BoU item | link, source (`loot`/`craft`) |
| GEAR | you equip a blue+ item new to this character (bundled over 4 s) | link, count, epics |
| ATK | an enemy player starts attacking you (one per encounter, 2 attackers per message) | enc, zone, attackers |
| ENG | you start a fight with an enemy player (once per enemy per 2 min) | zone, target |
| DIE | you die in a tracked PvP context | zone, killer, conf (`c`/`s`), assists (≤3), ended (streak) |
| KILL | you get an honorable kill | victim (may be empty), vclass, vlevel, vguild, zone, streak |
| SIGHT | you spot someone on your hitlist (once per player per 5 min) | name, class, level, guild, zone |
| HIT | Share hitlist (manual) | share, entries |
| REQ | catch-up request at login | window |
| PRO | your profile (on change, and to each friend who comes online) | k, d, wanted, zone, status, t, bt |
| GRP / GST | shared groups: membership / relayed stats | see Groups |
| KLQ / KLA | kill list request / answer | who / who, total, list |
| RLQ / RLY | relayed catch-up request / one relayed event | window, names / origin, …, data |
| BTY | one of your bounty board contracts (posted, changed, done; and to each friend who comes online) | cid, target, amount (copper), state, killer, age, updage, days |

LVL, LOOT, GEAR, ATK, ENG, DIE and KILL also end with `ago` (seconds since it happened, when
replayed) and `rl` ("1" = may be passed on). Units travel as `name:CLASS:level:guild`.

## Catch-up (alerts are live only)
- Each character keeps its own events from the last **24 hours** (at most 100, only the kinds you
  share).
- **At login:** 15 seconds in, if you were away at least 2 minutes (`lastOnline`, saved every
  minute), you ask online friends (REQ). A friend who comes online later is asked once per
  session.
- Replayed events go to the Feed, records and hitlist **at the time they happened**, with no
  toasts, chat lines or sounds; one chat line sums them up. They never overwrite fresher info.
  Received IDs are kept 25 hours (`got`) so a replay of something you saw live is ignored.
- **Relayed catch-up:** you name your offline friends (RLQ), and online friends pass on events
  those friends sent them (RLY). Rules:
  - one hop only
  - only events marked `rl` (the sender's "Friends may pass on my events" is on and their alert
    list is empty)
  - at most **30 per answer**, from a "heard" box of 300 events / 24 hours
  - the origin must be your own friend, and your picks still apply

## PvP detection
- **Where:** the open world (cities count; the EPL tower subzones don't). Battlegrounds only if
  turned on. Never dungeons or raids. Duels are excluded because attackers must be the other
  faction.
- **Attacked (ATK):** you take a hit while an enemy player (target, focus, mouseover or nameplate)
  targets you. The encounter ends after **30 s** without hits. Enemies you attacked first count
  as an ENG, not an ATK.
- **Killer (DIE):**
  - the death recap's newest non-friendly source, if it's a known attacker or flagged as a
    player (confirmed)
  - otherwise the encounter's last attacker (suspected; shown with "(likely)")
  - other attackers and recap players are assists
  - someone on your side (you, Battle.net friends, party/raid) is never a killer or helper
- **Kills (KILL):** Forever's honor message names no one ("You have been awarded 7 Honor."), so
  the victim is worked out from the screen, in this order:
  1. a dead enemy target, mouseover or focus
  2. a visible dead enemy nameplate
  3. an enemy whose nameplate went away dead in the last 5 s

  The victim must have been **seen alive in the last 60 s** (an old corpse isn't your kill), and
  is credited once per 15 s. Otherwise the KILL goes out with an empty victim, which counts
  towards K/D and is the kill list's "Name not readable" line (`kx`). Killing blows can't be
  seen, so a kill is any honorable kill.
- **Kill streak:** kills in a row without a PvP death, counted by the player's own client (per
  character) and sent with KILL and DIE.

## Records (account-wide, `realms.Forever`)
- **Players:** K/D/A per name, plus each player's kill list (`slain`; a friend's own report merges
  in as `slainRep`, highest count wins).
- **Hitlist:** anyone who **killed** you or a friend, or **attacked one of you first** (ATK). It
  keeps guild, attacks, kills (and how many were suspected), revenge, who they killed (`kv`),
  last seen and zone, your note, and who shared it.
  - Assists and enemies you attacked first are recorded on their player record only.
  - Entries fade after 90 days unseen. "Forget hitlist players" (off, or 90/180/365 days)
    removes old entries, never ones with a note.
  - **Share hitlist** sends your 40 most recent entries. Receivers take the higher of each
    counter and add entries that have a kill or an attack.
- **Feed:** the last 500 events, in the order they happened.
- **Limits** (`Saved.lua`): players 3,000 (harmless enemies unseen for 90 days are dropped), kill
  lists 250 victims each, debug log 2,000 lines (it switches off after 7 days), error log 50.
- **Upgrades:** `Saved.STEPS` run once each, in order (`dataVersion`).

## Profiles, Leaderboard, notoriety
- **PRO:** each client is the authority on its own numbers. It sends the current character's
  all-time kills and deaths (if it shares PvP), most wanted, zone and status (if it shares
  "where I am"), and notoriety claimed. Friends keep the latest one.
- **Leaderboard:** you and your friends (your picks, if any), one row per character, ranked by
  kills, then fewer deaths.
- **Notoriety (just for fun, points not gold; called "bounty" in the code, saved data and
  messages):** an enemy's notoriety is 100 per murder + 25 per attack since the
  last collection, + 250 for each friend who has them as most wanted (paid once per friend), at
  least 10. Any kill of them by you or a friend collects it. Kills within 60 s share it equally;
  your share is settled after 15 s. Each client counts on its own, so the split is best-effort.
  Totals are account-wide and self-reported, like K/D.

## Bounty board (`Contracts.lua`)
- A contract is a player's own promise: a price in gold, silver and copper on an enemy player.
  The add-on never moves gold; the poster pays by trade in the game and marks it paid. In-game
  gold only, between Battle.net friends.
- Enemy players only (never anyone on your side). Posting puts the target on your hitlist, and on
  each friend's when it reaches them (shared by the poster).
- Up to 5 open per player, at most 10,000 gold each, open for the days the poster picks (1-30,
  default 7). Finished ones (someone got the kill) stay on the board with who closed them (the
  oldest go past 200); cancelled and run-out ones leave after 14 days.
- Toasts (alert kind "contract", Options -> Alerts): a friend posts one; one is done (yours:
  pay them; theirs and you got it: they pay you; otherwise who got it).
- Sent to every friend with the add-on (not only the alert list), like groups and kill lists.
  Keyed by poster and id, so only the poster can change one. States only move forward: open,
  done, paid (or cancelled). Every client marks a contract done when it hears of a kill on the
  target by you or a friend; the poster's client confirms it to everyone. A kill by the poster
  closes it with nothing to pay.

## Shared groups (`Groups.lua`)
- Named groups whose stats members follow together. Members are Battle.net **accounts** (keyed by
  a hash of the BattleTag), and their stats add up all their characters.
- No server: every member keeps a copy. Membership entries carry three times: invited, joined,
  removed. Copies merge by taking the newest of each, so every client works out the same result.
- Limits: 10 members (joined first, then invites, oldest first), 5 groups, names 2–24 characters
  through the language filter. The leader is the longest-joined member.
- Members pass stats along (GST) because not everyone is friends with everyone. Only stats are
  relayed, never live alerts.

## Alerts
- **Show:** each kind is Toast, Chat or Off, with or without sound (`settings.show`,
  `settings.sound`, `settings.soundPick`). Defaults are in `Core.lua` `DEFAULTS`.
- **Milestones** always toast unless that kind is off: level 60, a looted epic BoE, a revenge
  kill, kill streaks of 5, 10, then every 5.
- **Nearby only:** fights outside your zone become chat lines.
- **Instances** (`settings.where`): show, hold until you're out (default), chat, or off. In combat,
  only PvP and sighting toasts show if "Do not disturb in combat" is on.
- **Toasts:** at most 1–4 on screen (default 2), queue 30, queued PvP toasts older than 60 s are
  dropped. Similar toasts merge (level-ups, a burst of gear), milestones never. Four styles:
  Modern, Classic, Alliance, Horde. Clicking a PvP toast opens that enemy's profile.
- **Wording:** with flavor on, messages vary using local history (repeat killers, "Nth today",
  streaks, revenge naming whom it avenged). Off: one short line, who did what, then where.
- Your own events go to the Feed only. Records are kept whatever the display setting.
- **Hitlist marks:** a skull on hitlist players' nameplates and their record in the tooltip.

## Window
- Tabs: **Hitlist**, **Bounty board**, **Leaderboard**, **Friends**, **Feed**, **Profile** (always yours). Clicking
  any name opens their profile inside the current tab, with Back. A friend's profile has their
  numbers, nemesis, where they are now and recent PvP. An enemy's is their Wanted poster with
  bounty, note and most wanted. Kill lists open from a profile.
- The old tab names `players` and `enemies` open the Hitlist.
- **Group window:** members, invites, Join/Leave, opened from the Leaderboard.
- **Minimap button:** on by default, on the rim of the minimap (sized to it, square minimaps
  too). Drag it round; Shift-drag it anywhere; `/fnf minimap reset` puts it back.
- **Options:** the game's Settings panel (Alerts, Where, Sounds, Appearance, Friends & sharing,
  Advanced), with a fallback panel if that API is missing.
- Slash commands: see the README.

## Tooling
- `npm test`: a Lua 5.1 syntax check, a check that every string the code uses is defined
  (`tests/locale.js`), then the whole add-on loaded in a Lua VM (fengari) against a mocked WoW API
  (`tests/mock.lua`), running `tests/test.lua`.
- `npm run package` builds `dist/FriendsAndFoes-<version>.zip`. Releases go through a tag and the
  GitHub Action (PUBLISHING.md).
- **Debugging:** `/fnf debug` logs to `FriendsAndFoesDB.debugLog`, and `/fnf report` gives a
  copyable report. The log has the capability results, errors, messages sent and received, and
  each alert's outcome with its reason.

## Known risks (live testing)
1. The honor-kill victim guess (screen-based) on busy fights.
2. Group joins from the invitee's side, kill-list fetches and relayed events with a non-mutual
   friend pair.
3. Whether Battle.net always gives a character name (it sometimes doesn't; the name learned from
   the friend's messages is used then).
