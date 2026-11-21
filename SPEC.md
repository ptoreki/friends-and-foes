# Friends & Foes — Design notes (1.0)

How the add-on works and why, for whoever changes it next (API references: API-SOURCES.md). The README says what it does for
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
  outside servers or programs, BattleTags never leave your Battle.net friends, and text
  other players typed passes the language filter before it's shown.

## Friends and sync
- A **friend** is a Battle.net friend who is online in WoW Forever, on your faction, and has the
  add-on. Other-faction friends are left out: nothing is sent to them and their events are
  dropped. You are never your own friend.
- **Alert list** ("picks", `FriendsAndFoesDB.group`, by BattleTag). When it's empty, every friend
  counts. Otherwise alerts go to and come from picked friends only. Set in its own window
  (Options -> Friends & sharing -> Alert list, or `/fnf alerts`), one tick box per account. Groups, kill lists and
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
- **Test alerts:** `/fnf test` (and `/fnf sim`) shows sample toasts and a chat line, standalone:
  nothing is recorded or sent, and nothing else in the add-on checks for it. (Until 0.9.3 a
  simulation used IDs starting with `S`; messages with such IDs from older friends are dropped.)
- **Text from friends** is cleaned before use (`Events.Clean`, `ns.SafeLink`, `ns.CleanName`):
  zones and guilds become plain text, classes must be class tokens, names with escape codes are
  dropped, and an item link that isn't a plain item link is cut to its name.

## Message kinds
| Kind | When | Fields |
|---|---|---|
| LVL | you level up | level |
| LOOT | you loot or craft an epic+ BoE/BoU item | link, source (`loot`/`craft`) |
| GEAR | you equip an epic+ item new to this character (bundled over 4 s; blue+ until 0.9.3) | link, count, epics |
| ATK | an enemy player starts attacking you (one per encounter, 2 attackers per message) | enc, zone, attackers |
| ENG | you start a fight with an enemy player (once per enemy per 2 min) | zone, target |
| DIE | you die in a tracked PvP context | zone, killer, conf (`c`/`s`), assists (≤3), ended (streak) |
| KILL | you get an honorable kill | victim (may be empty), vclass, vlevel, vguild, zone, streak, ago, rl, blow ("1" own blow, "pet" their pet's), last (seconds since their last attack on the victim, 0-120, empty = unknown) |
| AST | you supported (healed, buffed) a friend within 30 s of their live KILL, without honor of your own | victim, vclass, vlevel, zone, helped (the friend). Live only: not kept for catch-up, not passed on; not a kill for the sender |
| SIGHT | you spot someone on your hitlist (once per player per 5 min) | name, class, level, guild, zone |
| HIT | hitlist chunk: manual share (sending removed in 0.9.4, still received) and the automatic digest | share, entries (`name:class:level:guild:attacks:kills:revenge:hours:who;...`, who = up to 3 comma-separated victims, digest only), auto ("1" = digest: merged with no toast or Feed line) |
| REQ | catch-up request at login | window |
| PRO | your profile (on change, and to each friend who comes online) | k, d, wanted, zone, status, t, bt (current notoriety), btw (claimed this week), bwk (that week's start, in days; older than 7 days = 0), rl ("1" = friends may pass the numbers on) |
| PRL | a friend's numbers passed on (0.9.4; to a friend who comes online, for friends who are offline) | origin, k, d, t, bt, btw, bwk (no zone or status) |
| GRP / GST | shared groups: membership / relayed stats | gid, name, owner, base, members / stats (see Shared groups) |
| KLQ / KLA | kill list request / answer | who / who, total, list |
| RLQ / RLY | relayed catch-up request / one relayed event | window, names / origin, oclass, olevel, okind, oid, ago, data, alt ("1" = origin is the sender's own other character) |
| BTY | one of your bounty board contracts (posted, changed, done; and to each friend who comes online) | cid, target, amount (copper), state, killer, age, updage, days, blow ("1" or "pet"), last (seconds since the killer's last attack on the target), poster (empty = the sender posted it; else the sender passes on that friend's contract), killers (everyone who got the kill, comma-separated, at most 5, the lead = `killer` first; older clients read only `killer`), note (1.0.1: the poster's message, up to 60 characters, filtered; older clients ignore it) |

LVL, LOOT, GEAR, ATK, ENG, DIE and KILL also end with `ago` (seconds since it happened, when
replayed) and `rl` ("1" = may be passed on). Units travel as `name:CLASS:level:guild`.
No new message fields for the Feed levels (1.0.1): the friend's own level is the header `level` (your
level when it happened, also for replayed events: the outbox keeps it as `l`), the enemy's level is
the unit's / `vlevel` / SIGHT `level`. A skull-level enemy (game level -1) travels as level `0`
(older clients ignore a 0); the Feed shows it as "(Skull)" (`L.LEVEL_SKULL`). The Feed text of
PvP events (ATK, ENG, DIE, KILL incl. merged killers, AST, SIGHT) is built with " (35)" in grey
after each name (`ns.LevelTag`); toasts and chat stay without levels; older entries and unknown
levels show nothing.

## Catch-up (alerts are live only)
- Your account keeps its events from the last **week**: at most **250 in all** (not per
  character), each saying which character it is from (`FriendsAndFoesDB.outbox`; until 0.9.4 each
  character had its own list in `FriendsAndFoesCharDB.outbox`, merged in once at login). Only
  the kinds you share.
- **At login:** 15 seconds in, if you were away at least 2 minutes (`lastOnline`, saved every
  minute), you ask online friends (REQ). A friend who comes online later is asked once per
  session. Both asks are in the background (bulk).
- **Your other characters:** events of the character you play go out as before; events of your
  other characters go out as RLY with `origin` = that character and `alt` = "1", to friends whose
  add-on has `altCatchup` (0.9.4). Only your own share settings apply (not `rl`). The receiver
  takes the origin as a friend (its record gets `friend`), remembers the sender's BattleTag for
  it (`friendTags`, so alert-list picks cover it) and applies its own picks. It ignores the
  claim if the origin is on its hitlist, or already tied to another BattleTag. Dedupe stays
  `origin:oid`.
- **Gaps while both are online (0.9.4):** the time of the newest event received from each friend
  is kept for the session. A friend who comes back after 2 minutes or more (a disconnect, a
  relog) is asked again (REQ) for the time since that event (+5 s); with no event from them yet
  it stays as before. Once an hour, an online friend (with an event time) who sent nothing at
  all for an hour is asked the same way (at most 20 per round). A friend who missed nothing
  answers with nothing; the 60 s answer limit still applies.
- Replayed events go to the Feed, records and hitlist **at the time they happened**, with no
  toasts, chat lines or sounds; one chat line sums them up. They never overwrite fresher info.
  Received IDs are kept 25 hours (`got`) so a replay of something you saw live is ignored.
- **Relayed catch-up:** you name your offline friends (RLQ), and online friends pass on events
  those friends sent them (RLY). Rules:
  - one hop only
  - only events marked `rl` (the sender's "Friends may pass on my events" is on and their alert
    list is empty)
  - at most **30 per answer**, from a "heard" box of 300 events / a week
  - the origin must be your own friend (except `alt`, above), and your picks still apply
- **Hitlist digest (0.9.4):** when you first meet a friend this session (roster friends whose
  add-on has `digest`; if their version isn't known yet, when a message shows it), you send
  your 40 most recent hitlist entries that have a kill or an attack (HIT with `auto` = "1",
  packed into as few messages as fit, bulk priority), at most once per 7 days per BattleTag
  (`FriendsAndFoesDB.digestAt`). Not sent if you don't share PvP. The receiver merges as it
  does a share (max of counters, new entries need a kill or an attack) but shows no toast and
  adds no Feed line. Each entry carries up to 3 names of people the enemy killed or attacked
  (you first, then kills, then attacks; entries with none are not sent). The receiver keeps an
  entry only if one of those names is the sender, the receiver, or a friend on the receiver's
  side; entries without the 9th field are dropped. Enemies track who they attacked in
  `hitlist[name].hitWho` (name -> time, last 10).

## PvP detection
- **Where:** the open world (cities count; the EPL tower subzones don't). Never dungeons or raids.
  **Battlegrounds** (and arenas) are only watched, never counted (`PvP.InBattleground`, unless
  `settings.instances` is off): `Events.Emit` marks such a PvP event `bg`, applies only
  `Events.Battleground` (a Feed line for a KILL or DIE, tagged "(battleground)", on nobody's
  profile; no streak, nothing sent or remembered for catch-up) and returns. A received event whose
  zone text names a known battleground (`ns.IsBattlegroundZone`; older friends carry no flag) takes
  the same path with the receiver's own `instances` setting: off = nothing, otherwise a Feed line
  and an alert; caught-up ones are dropped. No wire change. (The old "Battlegrounds" tracking switch, `track.pvp`, is gone; upgrade step 15 deletes the saved value.) Duels are excluded because attackers must be the other
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
- **Kills (KILL):** a kill is the honor award (`CHAT_MSG_COMBAT_HONOR_GAIN`). Forever's message
  names no one ("You have been awarded 7 Honor."), so the victim comes from, in this order:
  1. **Your killing blow:** `PARTY_KILL` (attacker = your GUID, or your pet's, target a
     `Player-` GUID) within 3 s before the honor names the victim exactly (by GUID, from units
     seen earlier or `GetPlayerInfoByGUID`) and sets `blow` ("1", or "pet"). A blow reported
     after the honor is only logged. Secret values degrade it (`ns.caps.partyKill`).
  2. **The screen:** a dead enemy target, mouseover or focus; a visible dead enemy nameplate; an
     enemy whose nameplate went away dead in the last 5 s.

  A screen victim must have been **seen alive in the last 60 s** (an old corpse isn't your
  kill), and is credited once per 15 s. "Seen alive" is noted whenever a unit is read and
  `UnitIsDeadOrGhost` says no, and refreshed by `UNIT_HEALTH` on target, focus and nameplates
  (at most once a second per unit), so a long fight keeps its victim fresh. Otherwise the KILL
  goes out with an empty victim, which counts towards K/D and is the victims list's "Name not
  readable" line (`kx`). A kill without a killing blow is any honorable kill.
- **Last attack (`last`):** the time of your latest attack on each enemy (you or your pet:
  auto-attack or auto-shot state from `PLAYER_ENTER_COMBAT` and `START_AUTOREPEAT_SPELL`, your
  pet's target, and spells cast at them, `UNIT_SPELLCAST_SENT`). Sent with KILL as seconds (0-120)
  so that, with no killing blow, the most recent attacker gets the credit.
- **Kill streak:** kills in a row without a PvP death, counted by the player's own client (per
  character) and sent with KILL and DIE.
- **Assists by support (AST):** honor only goes to players who damaged the victim and their party,
  so a friend who just heals or buffs you gets none. When a friend's live KILL arrives and you cast
  something at that friend in the last 30 s (and did not report the kill yourself, once per victim
  per 60 s), you send AST: you join the notoriety claim and the bounty's killers like a killer, but
  it is never a kill for you (no K/D, streak, weekly count, kill list or hitlist change, no toast).

## Records (account-wide, `realms.Forever`)
- **Players:** K/D/A per name, plus each player's kill list (`slain`; a friend's own report merges
  in as `slainRep`, highest count wins).
- **Hitlist:** anyone who **killed** you or a friend, or **attacked one of you first** (ATK). It
  keeps guild, attacks, kills (and how many were suspected), revenge (counted for the Revenge
  toast; not shown), who they killed (`kv`),
  last seen and zone, and who shared it.
  - Assists and enemies you attacked first are recorded on their player record only.
  - **Manual entries (1.0.1):** `Data.AddManual` (the Hitlist's Add... button, `/fnf hitlist add`,
    and a bounty on a typed name) makes an entry with `manual = true`: no class, level or guild
    until `PvP.checkSighting` sees them (it `Touch`es the entry). `Data.ParseName`: letters (any
    non-ASCII byte counts), apostrophes, one space or hyphen, at most two words, 2-24 characters,
    trimmed, each word capitalised (ASCII words get the rest lower-cased); anything else is
    `NAME_BAD`; you and anyone on your side are `NAME_FRIEND` (`Data.ManualTarget`). A manual
    entry is never forgotten (`shouldForget`), and, having no kills or attacks, isn't in the
    digest (`Comm.DigestList` needs a deed and someone they hurt). It's a hitlist record only
    (no `players` record), so the entry in the window and the profile read from it.
  - `kt[friend]` = when they last killed that friend (set in `Flavor.Died`; merged as the later
    time). **Nemesis rule** (`Profile.NemesisBeats`, used by `Profile.Nemesis` and the weekly
    summary, which keeps `weekly.killedAt`): most kills; on a tie the most recent killer; with no
    times known, the name that sorts first.
  - Entries are greyed out after 30 days unseen. Unseen entries are forgotten per kind of player
    (days, 0 = forever): `settings.forgetAttackers` (attacked one of you, no kills; default 14),
    `forgetKilledOnce` (default 0) and `forgetKilledMore` (2 or more kills; default 0); choices are
    7, 14, 30, 90, 180, 365 or 0. An open Bounty board contract on them keeps them, and seeing them
    again restarts the clock. The defaults live at the top of `Core.lua`.
  - Friends' events fill your hitlist live and through catch-up, and bounties bring their
    targets, so there's no manual sharing any more. A share from a friend on an older version
    still merges in (the higher of each counter; new entries need a kill or an attack).
- **Feed:** the last 500 events, in the order they happened.
- **Kill log** (`FriendsAndFoesDB.killLog`, `Stats.lua`; 1.0.1): your own live kills only, oldest first, newest 1000 kept: `{ t, c, n, vl, ml, z }` = time, character (`ns.me`; entries without one are ignored and the page counts only the current character's), victim name (nil when unreadable), victim level at the time (nil unknown, -1 skull), your level then, zone. Caught-up and friends' kills are never logged; it is never sent. `FriendsAndFoesCharDB.bestStreak` (per character, next to `streak`) is the longest run of kills without dying. The Stats page (own profile, Stats button; lines the profile already has are not repeated) is computed from these: level-gap tiers reuse `Bounty.GreyLevel` and `Bounty.LEVEL_TIERS`; average level/gap need 5 kills with a known non-skull level and busiest weekday/hour 20 logged kills (`Stats.MIN_LEVELS`, `Stats.MIN_BUSY`); today = since local midnight, "Last 7 days" and "Last 30 days" are rolling windows.
- **Time played and lives** (1.0.2, `Stats.lua`): `FriendsAndFoesCharDB.played` = seconds out in the world: logged in and not dead/ghost, AFK (`UnitIsAFK`), resting (`IsResting`), on a taxi (`UnitOnTaxi`) or in an instance (`IsInInstance`); each check is pcall/secret-guarded and a failed one pauses nothing. Added from `GetTime()` deltas on a 10 s ticker and on PLAYER_DEAD / ALIVE / UNGHOST / LOGOUT / FLAGS_CHANGED / UPDATE_RESTING / ENTERING_WORLD / ZONE_CHANGED_NEW_AREA / CONTROL_LOST / CONTROL_GAINED (time is added only if the state during that interval was counting); no /played. Stats.Log, LogDeath and NoteStreak do nothing while `IsInInstance()` (open-world PvP only; the Feed, alerts and notoriety are unaffected). Kill log entries get `p` = played at the kill. `FriendsAndFoesDB.deathLog` = `{ t, c, p, k, z }` (time, character, played, killer name or nil, zone), newest 1000, written only for your own live PvP deaths (the DIE handler; never PvE, never caught-up). `FriendsAndFoesCharDB.lifeStart` = played at your last PvP death (nil: the first life starts at 0, when the counter began). A life = played time between consecutive PvP deaths; the average needs `Stats.MIN_DEATHS` (3) of them; kills per hour = kills with a `p` / hours played, from `Stats.MIN_PLAYED` (1 hour). Entries from 1.0.1 without `p` are left out of the rate and of current-life kills.
- **Level brackets** (1.0.2, `Stats.lua`): `FriendsAndFoesCharDB.brackets[key]` for key in u20 (1-19), 20, 30, 40, 50, 60 (60 and above), by YOUR level at the event: `{ kills, deaths, played, lives, lifeSum, lifeMax, bestStreak, vlSum, vlN, gapSum, gapN, pkills, tiers, wday, hour, zones }`, never trimmed (zones capped at `Stats.ZONE_CAP` = 50 per bracket, smallest dropped). Updated on each own logged kill, each own PvP death (the ended life goes to the bracket you died in), each played-time flush (the delta goes to the current level's bracket) and each streak step. An unknown level skips the bracket update. `bracketsSeeded` marks the one-time seed of kill-side totals from this character's 1.0.1 log entries that have `ml`. `Stats.Compute(key or nil)` returns one shape for a bracket and for All (the sum); Today / Last 7 / Last 30 days stay log-based. The selected bracket is session-only (not saved).
- **Limits** (`Saved.lua`): players 3,000 (harmless enemies unseen for 90 days are dropped), kill
  lists 250 victims each, debug log 2,000 lines (it switches off after 7 days), error log 50.
- **Upgrades:** `Saved.STEPS` run once each, in order (`dataVersion`).

## Profiles, Friends ranking, notoriety
- **PRO:** each client is the authority on its own numbers. It sends the current character's
  all-time kills and deaths (if it shares PvP), zone and status (if it shares
  "where I am"), and notoriety claimed. Friends keep the latest one.
- **Profiles passed on (0.9.4):** PRO carries `rl` ("1" = friends may pass the numbers on, the
  same switch as for events). When you greet a friend whose add-on has `profileRelay`, you also
  send up to 10 PRL (bulk) for other friends: only ones who are offline now, whose last PRO you got
  directly with `rl` = "1" and `t` set (numbers not older than 30 days, freshest first), and
  never the friend you're greeting. PRL has only the stats (no zone or status). The receiver
  applies it only for a friend of its own who is offline, only if `t` is newer than what it has,
  and never passes it on (one hop: a PRL-applied profile isn't passable until their own next PRO). Its `wanted` field (most
  wanted, until 0.9.3) is always sent empty and ignored.
- **Friends tab ranking** (was the Leaderboard): you and every friend who has run the add-on
  (a record with `friend`; Battle.net friends without it aren't listed, and there are no "online,
  not heard from yet" rows; the alert list doesn't hide anyone here), one row per character,
  ranked by kills, then fewer deaths. Columns: rank, name, level, kills, deaths, K/D, notoriety,
  Bounty board gold collected (`Contracts.EarnedBy`) and where they are now. Friends not seen
  for a long while drop off (`Data.FriendIsGone`). A shared group picked above the list shows
  that group's board instead.
  - **Low-level filter:** with `settings.hideLowAlts` (default on; Options -> Friends & sharing),
    a friend's characters below level 15 are left out (never yours, never one with an unknown
    level) and ranks are redone. A friend who is online on a hidden alt gets their account's best
    shown character marked "online (on an alt)". Their alerts still come through.
- **Notoriety (just for fun, points not gold; called "bounty" in the code, saved data and
  messages):** all numbers are constants at the top of `Bounty.lua`. A "random" (never killed or
  attacked you or a friend) is worth 10. A hitlist enemy is worth 100 per murder + 25 per attack since the
  last collection, x1.5 on a rampage (3 kills on your group within an hour, `h.killTimes`), x0.9
  per full day since their last offence (`h.lastOffence`), at least 50, rounded down.
  Diminishing returns: when nothing was earned since the last claim, only the free part is paid
  (10 for a random, the 50 floor for a hitlist enemy), times `REPEAT_FACTORS` = 1, 0.5, 0.25, then
  0 by how many claims of that enemy are in the current chain (`FriendsAndFoesDB.repeats[name]`,
  claim times, one per claim however many killers report it; a claim within `REPEAT_WINDOW` = 30
  min of the last extends the chain, a longer gap resets it; caught-up kills aren't recorded).
  Earned points are never reduced; a claim with earned points pays them in full and resets the
  chain to 0 (not counted). A claim worth 0 pays and toasts nothing. `Bounty.Open` is the one
  function for posters, profiles and claims. Their rank
  (Nuisance < 100, Menace, Wanted 300, Most Wanted 600, Public Enemy 1000) shows on the poster and
  profile; randoms have none. Any kill of them by you or a friend collects it. A claim of 300 or
  more (a takedown) gets one toast on every client that saw it (each settles 15 s after the first
  report; only your own share is added to you). Credit by priority: whoever landed the killing
  blow (the game said so; a pet's blow counts for its owner), else whoever attacked the victim
  most recently (the KILL field `last`, seconds since the sender's last attack), closes the bounty
  board contract (Contracts.lua). Notoriety ignores credit: everyone who got the kill (reports
  within 60 s) shares it equally, rounded down; alone you get all of it;
  your share is settled after 15 s. Your share (only yours) is then multiplied by a level factor
  from victim level - your level at the kill (`Bounty.LEVEL_TIERS`, `Bounty.GreyLevel` = the Classic
  grey rule): grey x0 (pays and says nothing); diff <= -6 x0.25; -5..-3 x0.5; -2..+2 x1; +3..+5
  x1.25; >= +6 or "??" (-1) x1.5; unknown victim or killer level x1; floored. Posters, profiles and
  takedown toasts show the base value. Resurrection Sickness (spell 15007, read in `PvP.lua` from
  the victim's auras wherever an enemy is read; in memory only, `PvP.IsSick`; secret or missing aura
  data = not sick): a victim who was sick when you got the kill is worth x0 to you (quiet), unless a
  skull to you (seen at level -1, or >= your level + 10), who keep the normal level factor (a skull
  seen with no known level counts as -1 = x1.5). Sightings: "N kills on us", else "attacked us N
  times", else just the place. Each client counts on its own, so the split is best-effort.
  Totals are account-wide and self-reported, like K/D. Your own notoriety fades: it loses 10% for
  each full week since your last claim (applied lazily, `b.clock` = last claim or last fade, so a
  week is never taken twice); `b.allTime` keeps everything ever claimed. Your title (Tracker,
  Hunter 500, Bounty Hunter 2000, Manhunter 5000, Legend 10000) comes from the current total: a
  new higher title toasts, losing one is quiet, and reaching a title again after a drop toasts
  again. This week's claimed points (`weekly.bt`, unaffected by fading) are in the weekly summary.

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
  Keyed by poster and id, so only the poster can change one. Who closed it: the best credit
  (a killing blow, a pet's counting for its owner; else the most recent attacker, by `last`;
  of equals the first report stays). A better credit for the same death reported up to 60 s
  later takes it over; the poster's word wins unless you know of a better credit. With nothing
  known, the first to report the kill. States only move forward: open,
  done, paid (or cancelled; "expired" is each client's own reckoning when the days run out, and
  the poster's word wins over it). Every client marks a contract done when it hears of a kill on the
  target by you or a friend; the poster's client confirms it to everyone. A kill by the poster
  closes it with nothing to pay.
- **Shared (1.0):** everyone who got the kill within `SHARE_WINDOW` = 60 s of the first one is in
  `c.killers` (at most `KILLERS_MAX` = 5): kills of yours and friends' reports, and the poster's
  BTY `killers`, merged as a union with the poster's names first, never shrinking; only while the
  contract is done (a paid one doesn't change). `c.killer` stays the lead (best credit, as above)
  for older clients and sorting. Each killer's share = floor(amount / #killers) copper
  (`Contracts.ShareOf`); the poster pays each by trade and marks it paid once. A poster among the
  killers owes themselves nothing (alone: closed, state paid). `EarnedBy` counts each killer's
  share of paid contracts (not the poster's own); contracts without `killers` count `killer` with
  the full amount. A late killer: the poster gets a chat line, the killer a toast.
- **By name and a note (1.0.1):** `Contracts.Post(u, amount, days, note)`; `u.manual` means the
  name was typed (checked with `Data.ManualTarget`; the target goes on your hitlist as manual) and
  the BTY `target` then has an empty class and level (`Name:::`). `note` (BTY `note`, the last
  field): at most 60 characters (`Profile.NOTE_MAX`), no `|` or control characters, through
  `Profile.Check` (ProfanityLib, the group-name filter) before sending (`TEXT_OFFENSIVE`) and again
  on receipt (`Profile.ShownNote`: dropped unless the filter says ok; a copy passed on by an older
  add-on doesn't wipe a note you have). `Comm.Fit` trims the note first (a character at a time),
  then guild names, then helper lists. Shown in the row's tooltip, the profile bounty line's
  tooltip, and the "bounty posted" toast and chat line (quoted after the amount).
  `/fnf bounty [name] <amount> [days] [message]` is split by `Contracts.ParseCommand` (the name is
  the words before the first one that starts with a digit).
- **Bounty target spotted (1.0.1):** `PvP.checkSighting` (target, focus... mouseover, nameplates) also
  fires for someone with an open bounty (`Contracts.OpenOn`: open, not past its days) who isn't on
  your hitlist; the normal once-per-5-minutes limit (`PvP.SightingDue`) applies. `Toast.Sighting`
  hands those to `Contracts.Spotted`: a "contract"/bounty toast with `alert` (red 7px edge),
  `longer` (twice the duration) and `alertSound` (the raid-warning sound unless a bounty sound is
  picked), and, for your own sighting in "toast" mode only, `Toast.Centre` (RaidNotice_AddMessage
  on RaidWarningFrame, else UIErrorsFrame). Alert setting off: nothing; chat: the chat line only;
  Where it works: off: nothing, hold: no centre message and the toast waits. A friend's SIGHT of
  a bounty target gets the same toast (no centre message). Debug log: `BOUNTY-SPOTTED`.
- **Passed on (0.9.4):** BTY has `poster`: empty when the sender posted it, otherwise the sender
  passes on that friend's contract. A friend who comes online (and has `contractRelay`) also
  gets up to 10 contracts you received **directly** from their posters (`c.direct`), open or done
  and not paid, newest news first, bulk priority, never the poster's own to the poster. The
  receiver keeps a passed-on contract under the poster ("poster/id") only if the poster is its
  own friend (and not itself) and the state is open or done; it follows the same forward-only
  rules, so it can never roll back newer news, and it is never passed on again (not direct).

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
- **Show:** set in four groups (fights: attacked, attacking, killed, a kill; sightings;
  progress: loot, gear, level-ups; bounty board), each Toast, Chat or Off, with or without
  sound. Stored per alert (`settings.show`,
  `settings.sound`, and `settings.soundPick`: trouble (attacked, killed), victory (a kill), sighting,
  progress, bounty; on "Default" attacked, killed and a kill keep their own sounds).
  Attacking someone and plain level-ups never make a sound of their own. Defaults are in `Core.lua` `DEFAULTS`.
- **Milestones** always toast (no switch) unless that kind is off: level 60, a looted epic BoE, a revenge
  kill, kill streaks of 5, 10, then every 5.
- **One toast per death:** several killers of the same victim (you and friends, or friends
  only) fold into one Feed line and one toast naming everyone ("A and B killed X", "You and B
  killed X"; `deaths` table in `Events.lua`, merged on `collapseKey`, `mergeOnly`/`keepKey` on the
  toast; log lines `KILL-MERGE` / `KILL-NEWDEATH`). A report is a **new death** when the same
  killer reports the victim again, the victim was seen alive since the first report
  (`PvP.SeenAliveSince`: Reincarnation, a soulstone, a resurrection), or it is more than 60 s
  after the first. A streak or revenge keeps its own toast. Kill counts, victims lists,
  notoriety and bounties still count every killer. Caught-up kills never merge.
- **Nearby only:** fights outside your zone become chat lines.
- **Instances** (`settings.instances`, one for dungeons, raids and battlegrounds): show, hold
  until you're out (default), or off. In combat,
  only PvP and sighting toasts show if "Do not disturb in combat" is on.
- **Toasts:** at most 1–4 on screen (default 2), queue 30, queued PvP toasts older than 60 s are
  dropped. Similar toasts merge (level-ups, a burst of gear), milestones never. Four styles:
  Modern, Classic, Alliance, Horde. Clicking a PvP toast opens that enemy's profile.
- **Wording:** with flavor on, messages vary using local history (repeat killers, "Nth today",
  streaks, revenge naming whom it avenged). Off: one short line, who did what, then where.
- Your own events go to the Feed only. Records are kept whatever the display setting.
- **Hitlist marks:** a skull on hitlist players' nameplates and their record in the tooltip.

## Window
- Tabs: **Hitlist**, **Bounty board**, **Friends**, **Feed**, **Profile** (always yours). Clicking
  any name opens their profile inside the current tab, with Back. A friend's profile has their
  numbers, nemesis, where they are now and recent PvP. An enemy's is their Wanted poster with
  notoriety and the bounties on them (Post bounty). Victims (kill lists) open from a profile.
- The old tab names `players` and `enemies` open the Hitlist.
- **Group window:** members, invites, Join/Leave, opened from the Friends tab.
- **Minimap button:** on by default, on the rim of the minimap (sized to it, square minimaps
  too). Drag it round; Shift-drag it anywhere; `/fnf minimap reset` puts it back.
- **Options:** the game's Settings panel only, four pages: Alerts (Test alerts first; the four
  alert groups; the five sounds; level-up frequency; nearby only; when alerts wait: instances and
  combat), Appearance (toasts, messages, chat tab, weekly summary, minimap button), Friends &
  sharing (what you share, where your own PvP is tracked, low-level filter, alert list button,
  hitlist skull and tooltip, the three "forget" settings), Advanced (debug logging and report).
- Slash commands: see the README.
- What's new (`WhatsNew.lua`): `WhatsNew.NOTES` holds `{ version, lines }` (strings `L.NEW_<ver>_n`);
  a test fails if the current version has none. Account-wide `FriendsAndFoesDB.seenVersion`: when the
  window opens and it differs from `ns.VERSION`, the current version's notes (only that version, skipped
  versions are ignored) show once and it is set at once. Brand-new account (tour not yet seen): set
  silently, no popup. In combat or while the tour is up: skipped, tried again on the next open.
  `/fnf new` shows it any time.

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
1. The honor-kill victim guess (screen-based) on busy fights, and whether `PARTY_KILL` fires
   with readable values for your own blows in world PvP (see `[PARTY-KILL]` in the debug log).
2. Group joins from the invitee's side, kill-list fetches and relayed events with a non-mutual
   friend pair.
3. Whether Battle.net always gives a character name (it sometimes doesn't; the name learned from
   the friend's messages is used then).
