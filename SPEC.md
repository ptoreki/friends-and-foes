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
- A "friend" is a Battle.net friend who is **online on the same realm** and has the addon.
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
| DIE | You died in a world PvP context | zone, killer, conf (`c` confirmed / `s` suspected), assists (at most 3) |
| KILL | Honorable-kill message | victim, vclass, vlevel, vguild, zone |
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
  - the other encounter attackers, plus other players in the recap, count as assists and are
    added to the hitlist
- **Names-unreadable fallback:** a death the recap shows came from a player is recorded even
  when no encounter was detected. The hitlist then fills from deaths alone. The Settings tab
  shows which fallback mode is active.
- **Kill vs. assist:** killing blows can't be detected without the combat log, so a friend's honorable
  kills are counted as **takedowns**.

## Records (account-wide, per realm)
- **Players**: K/D/A per name.
  - Friends and you: takedowns and deaths.
  - Enemies: kills on us, deaths to us, and assists on our deaths.
- **Hitlist**: anyone who attacked or killed you or a friend.
  - Stores guild, attacks, kills (with a suspected count), revenge count, victims, last seen and
    zone, a note, and who shared it.
  - Entries never expire. They can be removed by hand.
- **Pruning** at login: enemies not seen for 90 days, with no kills or assists on us and not on
  the hitlist, are removed.
- **Feed**: the last 500 events.
- **Error log**: the last 50 errors, always kept (`FriendsAndFoesDB.errorLog`).
- **Per character**: the set of item keys already equipped.

## Toasts
- **Shown for:** friends' events, plus hitlist sightings (nameplate, target or mouseover,
  once per player every 5 minutes). Your own events go to the Feed only.
- **Layout:** movable anchor (`/fnf unlock`), 5 seconds each, at most 3 on screen, the rest queued
  (at most 30).
- **Do not disturb:** in combat only PvP and sighting toasts show. In instances all toasts wait.
  Queued PvP toasts older than 60 seconds are dropped.
- **Revenge:** a kill on a hitlist entry adds "revenge!" to the toast and "R<n>" to the Kills
  column.
- **Collapse:**
  - level-ups merge into one toast ("Bob, Alice and 2 others leveled up")
  - a burst of gear from one friend merges into one toast
- **Suppression:** "Friend attacked" toasts are suppressed when that friend is in your group
  and you're in combat.
- **Clicks:**
  - a PvP toast opens that enemy in the main window
  - hovering an item toast shows its tooltip
- **Chat:** none. Only slash-command replies print anything.
- **Sounds:** built-in. Separate sounds for PvP, progress and sighting toasts, with a global on/off
  and one per category.

## UI
- `/fnf` and a minimap button that can be hidden, both opening a tabbed window:
  - **Hitlist**: the hitlist, plus a note editor and a Remove button
  - **Enemies**: enemy K/D/A
  - **Friends**: friends' K/D/A and level
  - **Feed**: recent events
  - **Settings**:
    - share toggles per type (level, loot, gear, PvP)
    - toast toggles per type
    - sound toggles
    - minimap, debug, unlock toasts, test toasts
    - which features this client supports
- Slash commands: `/fnf`, `/fnf settings`, `/fnf unlock`, `/fnf lock`, `/fnf test`, `/fnf status`,
  `/fnf share`, `/fnf sim <kind|all> [self]`, `/fnf sim view`, `/fnf sim clear`, `/fnf debug`,
  `/fnf debug clear`, `/fnf minimap`.

## Tooling
- `npm test` runs a Lua 5.1 syntax check, then loads the whole addon in a JavaScript Lua VM
  (fengari, which is Lua 5.3) against a mocked WoW API (`tests/mock.lua`) and runs
  `tests/test.lua`.
- `npm run package` builds `dist/FriendsAndFoes-<version>.zip`.

## Debugging
`/fnf debug` logs to `FriendsAndFoesDB.debugLog` (at most 5000 lines). The log is saved on `/reload`
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
Localization, cross-realm friends, login replay, waypoints, public release.
