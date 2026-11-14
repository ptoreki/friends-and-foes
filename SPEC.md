# Friends & Foes — Spec (v0.3)

WoW Forever addon (interface 16001, `_forever_\Interface\AddOns\FriendsAndFoes`).
Tells you what your friends are doing (leveling, epic BoEs, new gear), alerts you to
world-PvP fights involving them, and keeps a hitlist and per-player K/D/A.

## Platform constraints
- Forever uses the modern (Midnight 12.x) addon API. **The combat log is unavailable**,
  and some combat values come back as *secret values*.
- So each client reports **only its own events** and sends them to friends.
  No client watches other players.
- Every value that might be secret is checked with `issecretvalue` before it is used.
  Every event handler is wrapped in `pcall`.
- If a signal turns out to be unreadable, that feature quietly degrades instead of erroring.
- Nothing has been tested on a live client. Friends are the testers.

## Friends and sync
- A "friend" is a Battle.net friend who is **online in WoW Forever** (same WoW project) and has the addon.
  Forever has no realms: `GetRealmName` returns an internal server name ("CAMWOW EU4 Realm 8 PvP")
  that differs between friends who play together, so it is ignored. Names are unique region-wide.
- **Picked friends** (`FriendsAndFoesDB.group`, keyed by BattleTag): if the set is empty, every
  friend above counts. Otherwise events are sent to, and accepted from, picked friends only. Toggle a
  friend by clicking them in the Friends tab, or with `/fnf group <name|BattleTag>`. `/fnf group all`
  clears the set. Unpicked online friends are still listed so you can pick them.
- Each event is sent **two ways**:
  - `BNSendGameData` to the friend's game account
  - an addon `WHISPER` to the friend's character (same faction only)
- The receiver drops duplicates using `sender:eventId`.
- Events are sent **live only**. Nothing is replayed at login.
  - Exception: a manual **Share hitlist** sends your 40 most recent entries. Receivers merge by
    taking the higher of each counter.
- Message format (protocol 3): `3\tKIND\tID\tsenderName\tclass\tlevel\taddonVersion\t<fields...>`,
  at most 255 bytes. If a message is too long, guild names are dropped first.
- The sender name in the header is accepted only if its first name matches what the route
  reports (Battle.net `characterName` or the whisper sender). The roster then switches to the
  full name, and whispers are addressed to "First Last".

## Names (WoW Forever)
- Every character has a first name and a surname. **Only the pair is unique** (region-wide).
  First names are shared. Neither part contains spaces or hyphens.
- `UnitName` returns `(first, surname)` where retail returns `(name, realm)`. The death recap and
  addon whispers use "First Last". "First-Last" also addresses a character.
- The key is always "First Last". A bare first name is resolved to a known full name only when
  exactly one matches. Otherwise it's kept as its own record, and folded in later once the full
  name appears and there's no ambiguity.
- At login, 0.2 records stored under a bare first name are merged into their unique full-name
  record.
- **Throttling:** each route has a token bucket of 8 that refills at 1 per second, with three
  priorities (PvP, then progress, then bulk). A client throttle result puts the message back
  in the queue.
- **Version check:** friends' versions appear in the Friends tab. You get a toast once per session
  when a friend runs a newer version or an incompatible protocol.
- **Simulation:** IDs that start with `S` are simulated. Every client stores them in
  `FriendsAndFoesDB.sim`, never in real data.

## Events
| Kind | Trigger (own character) | Fields |
|---|---|---|
| LVL | `PLAYER_LEVEL_UP` (every level) | level |
| LOOT | Looted or crafted item: **epic or better**, BoE or BoU | link, source (`loot`/`craft`) |
| GEAR | Newly equipped item: **blue or better**, never equipped on this character before. Changes within 4 seconds are bundled | link (best item), count |
| ATK | Hostile-faction player starts attacking you (one per encounter; repeated as more attackers join, 2 attackers per message) | enc, zone, attackers |
| DIE | You died in a world PvP context | zone, killer, conf (`c` confirmed / `s` suspected), assists (at most 3), ended (the kill streak this death ended) |
| KILL | Honorable-kill message | victim, vclass, vlevel, vguild, zone, streak (kills in a row, including this one) |
| HIT | Manual hitlist share | share id, packed entries |

Units are encoded as `name:CLASS:level:guild`, with the name as "First Last".

Rules:
- **Gear identity** is item ID plus random suffix; enchants are ignored. Shirt, tabard and ammo are excluded.
- **Seeding:** items already equipped when the addon first runs on a character are recorded silently.
- **Collapse:** a GEAR event isn't sent if the same item was shared as LOOT within the last 5 minutes.
- **World PvP context:** outside all instances (so no BGs, arenas, dungeons or raids), and not in an
  objective subzone (the EPL towers). Duels are excluded automatically, because attackers must be the
  opposite faction. Cities count.
- **Encounter:** starts when you take a hit while a hostile player is targeting you. It ends after
  **30 seconds** without hits.
- **Killer:**
  - the death recap's source, if readable and either a known enemy or flagged as a player
    by its GUID or flags (confirmed)
  - the recap's name isn't used to guess "player" from its shape, since Forever player names
    ("Kragg Bear") look like NPC names
  - otherwise the most recent attacker in the encounter (suspected)
  - the other encounter attackers, plus other players in the recap, count as assists. Assists
    are not added to the hitlist.
- **Names-unreadable fallback:** a death the recap shows came from a player is recorded even
  when no encounter was detected. The Settings tab shows which fallback mode is active.
- **Kill vs. assist:** killing blows can't be detected without the combat log, so a friend's honorable
  kills are counted as **takedowns**.

## Records (account-wide, one store: `realms.Forever`; older per-server stores are merged at login)
- **Players**: K/D/A per name.
  - Friends and you: takedowns and deaths.
  - Enemies: kills on us, deaths to us, and assists on our deaths.
- **Hitlist**: anyone who **killed** you or a friend. Only a kill adds someone; an attack alone
  only alerts.
  - An enemy's attacks are counted on their player record (`atk`) and carried over when a kill
    adds them. Attacks keep being counted while they're on the list.
  - Stores guild, attacks, kills (with a suspected count), revenge count, victims (who they
    killed), last seen and zone, a note, and who shared it.
  - A shared entry with no kills (from an older client) isn't added.
  - From 0.5.4, a one-time cleanup removes entries with no kills, unless they have a note.
  - Entries never expire. They can be removed by hand.
- **Pruning** at login: enemies not seen for 90 days, with no kills or assists on us and not on
  the hitlist, are removed.
- **Feed**: the last 500 events.
- **Error log**: the last 50 errors, always kept (`FriendsAndFoesDB.errorLog`).
- **Per character**: the set of item keys already equipped.

## Alerts (toast, chat or off)
- **Rule:** if you can act on it in the next 30 seconds, it's a toast. Everything else is a chat line.
  Each kind can be set to Toast, Chat or Off in Settings (`settings.show`). Defaults:
  - **Toast:** friend attacked, friend killed, friend's kill
  - **Chat:** level up, loot/craft, new gear, hitlist sighting, hitlist share
- **Nearby only** (`settings.nearbyOnly`, default on): "friend attacked" is shown as a toast only when the
  friend's zone (from the message) is your current zone. Otherwise it's a chat line.
- **Milestones always toast** (unless that kind is Off): reaching level 60 (`ns.MILESTONE_LEVEL`),
  a **looted** epic BoE (crafted ones follow the setting), and a revenge kill.
- Your own events go to the Feed only. Records are kept whatever the display setting.
- **Chat lines:** "F&F: <feed text>" in the guild-achievement colour, with clickable item links.
  They go to chat tab 1, or the tab picked with `/fnf chat <n>`.
- **Sound per event** (`settings.sound[kind]`): plays whenever that event is shown, as a toast or a
  chat line. Defaults: on for friend attacked, friend killed, sighting and loot; off for the rest.
  Milestones play a soft chime even when their event's sound is off. There's also a global
  "Sounds on". Sounds:
  - PvP: a short boss-whisper alert
  - progress and milestones: the Battle.net toast chime
  - sightings: the whisper ping
- **Hitlist marks** (`settings.mark`, default on):
  - a skull next to a hitlist player's nameplate
  - a tooltip line: kills, attacks, who they killed, and your note
  - Sightings (nameplate, target or mouseover, once per player every 5 minutes, world PvP only)
    still produce a chat line or toast.
- **Toast layout:** one compact line (icon, title, details; long text wraps to at most 3 lines) on a dark strip with a thin coloured
  edge: red for PvP, gold for progress, purple for sightings. It fades in and out. PvP toasts stay
  5 seconds, others 3. At most 2 are on screen and the rest are queued (at most 30). The anchor is
  movable (`/fnf unlock`).
- **Do not disturb:** in combat only PvP and sighting toasts show. In instances all toasts wait.
  Queued PvP toasts older than 60 seconds are dropped.
- **Message shape:** short. Who did what, then extras, then the place, separated by " · ", e.g.
  "Rogz killed Bob again (3rd) · 5th today · Tarren Mill". The place is the subzone if the
  sender had one, else the zone (`Flavor.Place`); the hitlist still stores the full zone.
- **Varied wording** (`Flavor.lua`, `settings.flavor`, default on): built from history kept locally.
  - Hitlist `kv[victim]` counts that enemy's kills on each friend:
    - 2 or more: "Y killed X again (Nth)"
    - 5 or more: "Y has X's number (Nth)"
    - 10 or more: "X's nemesis Y strikes (Nth)"
  - Each player's `deathTimes` and `killTimes` keep the last 2 days, at most 50 each:
    - 3 or more deaths today, or 5 or more kills today: "Nth today"
  - **Kill streak:** kills in a row without a world PvP death. Each client counts its own
    (`FriendsAndFoesCharDB.streak`, per character; simulated events don't count) and sends it with
    KILL. A DIE sends the streak it ended, then resets it. Fields added at the end are ignored by
    older clients, and missing ones read as empty.
    - from 3: "N in a row" (it takes the place of "Nth today")
    - 5, 10, then every 5 more: "N in a row!", a milestone that always toasts (flavor on only)
    - a death that ended 3 or more: "ended a N-kill streak"
  - Enemy `kb[friend]` counts kills on that enemy by each friend: 3 or more gives "X owns Y (Nth)".
  - Revenge names the friends that enemy had killed ("X avenged A on Y").
  - An attack mentions the attacker's past kills on that friend ("(killed them N×)").
  - Otherwise one plain wording is picked at random.
- **Flavor off:** every message is one short line, who did what, then where. PvP:
  "X killed by Y · Place", "X killed Y [(revenge)] · Place", "X attacked by Y · Place", and
  "Hitlist: Y nearby · Place". Progress uses the Feed line. The toast shows that line only, with
  no second part and no merging.
  The same line goes to the toast, the chat line and the Feed. Counts are per client, since each
  client builds them from the events it received.
- **Revenge:** a kill on a hitlist entry adds "revenge!" and "R<n>" to the Kills column.
- **Collapse:** level-up toasts merge ("Bob, Alice and 2 others leveled up"), and so does a burst
  of gear toasts from one friend. Milestones are never merged.
- **Suppression:** "Friend attacked" is suppressed when that friend is in your group and you're
  in combat.
- **Clicks:** a PvP toast opens that enemy in the main window. Hovering an item toast shows its
  tooltip.
- **Older settings:** a 0.3 toast that was turned off becomes Off. A 0.4 sound category that was
  off turns that category's events silent.

## UI
- **Window** (`/fnf`, the minimap addon menu, or the optional minimap button): Blizzard's plain
  window frame, with tabs below it like the Character window.
  - **Hitlist**: the hitlist, plus a note editor, Remove and Share
  - **Players**: an Enemies / Friends filter
    - Enemies shows K/D/A.
    - Friends shows level, version, takedowns, deaths and alerts. Click a friend to pick them.
  - **Feed**: recent events
  - Rows show class icons. An **Options** button opens the settings.
- **Options** live in the game's Options → AddOns panel. If that panel can't be opened, the addon
  opens its own window instead.
  - Alerts: for each event, Show (Toast / Chat / Off, click to cycle) and Sound (on / off),
    plus "nearby only" and "Sounds on"
  - Share with friends, per type
  - Do not disturb
  - Other: hitlist marks, minimap button, debug logging, move toasts
  - **Beta tools** (only while debug is on): test toasts, simulate, and which features this client
    supports
- **Minimap:** Friends & Foes is in the minimap's addon menu where the client has one
  (`AddonCompartmentFunc`). The separate minimap button then starts hidden, once; your later
  choice sticks.
- Slash commands: `/fnf`, `/fnf options` (also `settings`), `/fnf unlock`, `/fnf lock`, `/fnf test`, `/fnf status`,
  `/fnf share`, `/fnf group [name|BattleTag|all]`, `/fnf chat <tab>`, `/fnf sim <kind|all> [self]`, `/fnf sim view`, `/fnf sim clear`, `/fnf debug`,
  `/fnf debug clear`, `/fnf minimap`.

## Tooling
- `npm test` runs a Lua 5.1 syntax check, then loads the whole addon in a JavaScript Lua VM
  (fengari, which is Lua 5.3) against a mocked WoW API (`tests/mock.lua`) and runs
  `tests/test.lua`.
- `npm run package` builds `dist/FriendsAndFoes-<version>.zip`.

## Debugging
`/fnf debug` logs to `FriendsAndFoesDB.debugLog` (newest 2000 lines; switches itself off after 7 days). The log is saved on `/reload`
or logout, to `WTF\Account\<ACCOUNT>\SavedVariables\FriendsAndFoes.lua`. It records:
- secret or readable results for each capability (bnet, whisper, unitNames, deathRecap, honor)
- caught errors
- messages sent and received

## Known risks to check in beta
1. Whether attacker names are readable (`unitNames` capability). If not, no ATK events fire and
   the hitlist stays empty.
2. Whether death recap IDs and fields work as assumed.
3. Whether honor-kill message wording matches the English patterns.
4. Whether the Battle.net and whisper sync routes deliver.

## Out of scope for 0.1
Localization, login replay, waypoints, public release.
