# Changelog

## 0.4.0
Compatible with 0.3.x. Friends don't need to update at the same time.
- **Fewer pop-ups.** Only alerts you can act on are toasts: a friend being attacked or killed.
  Level-ups, loot, gear, kills, sightings and shares are now a single chat line in the
  guild-achievement colour, with clickable item links.
- **Milestones still toast:** a friend reaching level 60, looting an epic BoE, or getting a
  revenge kill.
- Each kind can be set to Toast, Chat or Off in Settings (click to cycle).
  `/fnf chat <tab number>` picks which chat tab gets the lines.
- **Hitlist marks:** a skull next to a hitlist player's nameplate, and a tooltip line with their
  kills and attacks on you and your friends, who they hit, and your note. Toggle it in Settings.
- The sighting sound is now the softer whisper ping, instead of the ready-check horn.
- Toasts you turned off in 0.3 stay off.

## 0.3.3
Compatible with 0.3.0 to 0.3.2.
- **Pick which friends you get alerts from.** Click a friend in the Friends tab, or use
  `/fnf group <name or BattleTag>`, to toggle them. Once you've picked anyone, you only exchange
  events with your picks, in both directions. Nobody picked means every friend with the addon
  (the old behaviour). `/fnf group` lists online friends, and `/fnf group all` clears the picks.
- Picks are stored by BattleTag, so they cover all of a friend's characters.

## 0.3.2
Compatible with 0.3.0 and 0.3.1.
- **Fixed sync between friends.** WoW Forever has no realms. The "realm" the game reports
  ("CAMWOW EU4 Realm 8 PvP") is an internal server name that differs between friends who play
  together, and 0.3.1 and earlier only talked to friends on the *same* one. Any Battle.net friend
  online in WoW Forever now counts. Friends playing another WoW version are excluded.
- Your data is now kept in a single store, instead of one per server name, so it can't look
  empty after a server change. Older stores are merged at login.

## 0.3.1
Compatible with 0.3.0.
- Friends whose realm name Battle.net spells differently are now matched by realm ID.
- The debug log lists every WoW Battle.net friend with the reason they were or weren't included
  (offline, other realm, ...), and each send now names who it went to.
- `/fnf status` shows your full name, your realm and the friends found.
- Feature status (`caps`) is saved, so reports show it.

## 0.3.0
**Not compatible with 0.2.** Everyone needs to update. An older friend now triggers a
"friend needs to update" toast instead of being silently ignored.

### WoW Forever names
On Forever every character has a first name and a surname. Only the full pair is unique, and
first names can be shared. 0.2 treated a first name as the identity and the surname as a realm,
which caused bugs.
- Players are now stored as "First Last". `UnitName`'s second value is read as the surname,
  not stripped as a realm.
- Fixed one enemy appearing twice ("Kragg" from the attack, "Kragg Bear" from the death recap).
  Existing duplicates are merged automatically at login.
- A bare first name (for example, from an honor-kill message) is matched to a known
  "First Last" only when exactly one exists. The addon never guesses between two characters
  who share a first name.
- Messages carry the sender's full name, so the Battle.net and whisper routes agree on who sent
  them. Whispers are addressed to "First Last", and a stranger who shares a friend's first name
  is rejected.
- If the death recap can't say whether the killer was a player, the addon no longer guesses
  from the name, because NPC names now look like player names. It falls back to the last
  attacker, marked as suspected.
- Wider name columns.
- More debug logging for dropped messages (`BN-DROP`, `WHISPER-DROP`, `SENDER-MISMATCH`, `ROSTER+`).

## 0.2.0
**Not compatible with 0.1.** The message format changed, so everyone needs to update.

### Fixes
- Outgoing messages are now rate-limited, with PvP messages sent before progress and before
  hitlist sharing. A burst of events can no longer flood the chat throttle.
- New gear equipped within a few seconds is bundled into one event ("equipped X and 2 more").
- Enemy names are stored without realm suffixes, so one player no longer shows up as two entries.
- The last 50 errors are always saved, even with debug logging off (`FriendsAndFoesDB.errorLog`).
- Messages that are too long drop guild names to fit, instead of being silently lost.

### New
- `/fnf sim <level|loot|gear|attacked|died|kill|sighting|all> [self]` runs fake events through
  the real pipeline:
  - Results go to a separate simulation store, shown with a "SIMULATION VIEW" banner.
    `/fnf sim clear` removes them.
  - With `self`, the event is sent to friends too, so you can test sync. They also file it as
    simulation data.
- **Do not disturb:** progress toasts wait while you're in combat. All toasts wait in
  dungeons and raids. PvP toasts older than 60 seconds are dropped.
- **Version check:** each message carries the sender's addon version. The Friends tab shows it,
  and you get a toast when a friend runs a newer version.
- **Enemy guilds** appear on the hitlist and Enemies tab.
- **Share hitlist** (button or `/fnf share`): sends your 40 most recent hitlist entries to
  online friends. Receivers merge by taking the higher of each counter. Notes stay private.
- **Revenge:** killing someone on the hitlist marks it ("R2" in the Kills column, "revenge!"
  in toasts).
- **Pruning:** enemies not seen for 90 days, who never hurt you or your friends and aren't on
  the hitlist, are removed at login.
- `npm test` runs the addon's Lua against a mocked WoW API (43 checks).
- `npm run package` builds `dist/FriendsAndFoes-<version>.zip`.

## 0.1.0
- First version: friend toasts (level, epic BoE, new gear), world PvP alerts, hitlist,
  K/D/A, the main window and settings.
- Defensive against Forever's unreadable combat values, with a fallback mode for each.
