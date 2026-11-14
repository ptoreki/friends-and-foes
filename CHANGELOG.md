# Changelog

## 0.5.6
Compatible with 0.3.x to 0.5.5.
- **New Options page: Where it works.**
  - **Alerts while you're in:** a dropdown each for Dungeons, Raids and Battlegrounds.
    Choices: *Show*, *Wait until I'm out* (the default, same as before), *Chat line only*, or *Off*.
  - **Track my PvP in:** Open world (on) and Battlegrounds (off). If you turn on battlegrounds,
    your fights there count, and anyone who kills you there goes on the
    hitlist.
- **Debug log: every alert's outcome.** One `[TOAST]` line per alert: shown as a toast, a chat line,
  off, waiting (in combat or in a dungeon), merged, or dropped, always with the reason. Now a
  missing toast can be traced.
- The old "hold all toasts in dungeons/raids" checkbox is replaced by the dropdowns. If you had it
  off, they start on *Show*.

## 0.5.5
Compatible with 0.3.x to 0.5.4.
- **New options**, built into the game's own settings panel (Options → AddOns → Friends & Foes),
  so they look and work like Blizzard's menus. There are dropdowns with < > arrows, a tooltip on
  every option, and the options show up in the settings search. Four pages:
  - **Friends & Foes (Alerts):** one dropdown per event: *Toast + sound*, *Toast*,
    *Chat line + sound*, *Chat line* or *Off*. Below that: nearby-only, all sounds, do not disturb.
  - **Appearance:** toast style (dropdown), Preview, Move toasts, message style (*With flavor* or
    *Short*), and which chat tab gets the lines.
  - **Friends & sharing:** what you share, *Choose friends...*, hitlist marks, and Share hitlist.
  - **Advanced:** minimap button, debug logging, Print status, Simulate, and Clear simulated data.

  The old panel stays as a fallback if the game's settings system isn't available.
- **Toast styles renamed:** Modern (the slim strip, the default) and Classic (the achievement
  look).
- **Stop simulation:**
  - The simulation banner's button, **Advanced → Stop**, or `/fnf sim stop`.
  - Pending fake alerts are cancelled, fake toasts are dismissed, and the window shows your real
    data again.
- **Friends on the other faction are left out:** they don't appear in your Friends list, and
  alerts aren't exchanged with them. Their fights would otherwise put players from your own
  faction on your hitlist.
- **Fixed:** you no longer show up in your own Friends list.
- **Window:**
  - Click a column header to sort by it, and click again to flip the order. An arrow shows the
    current sort.
  - Page arrows (< 1-15 of 40 >) next to the count.
  - The Players tab has a **Show: Enemies / Friends** dropdown.

## 0.5.4
Compatible with 0.3.x to 0.5.3.
- **Toast styles:** choose in Options:
  - **Minimal** (the default): the compact one-line strip.
  - **Achievement**: WoW's own achievement pop-up look, with a small header ("Friend killed",
    "Revenge!", "Kill streak!", "Max level!") above the message. Red-tinted for PvP, purple for
    sightings.

  **Preview** shows one of each.
- **Fixed: friends' kills never showed.** WoW Forever's honor message is just "You have been
  awarded 7 Honor.", with no name, so earlier versions ignored it. Now it counts as a kill, and the
  victim is worked out from the screen: your dead target, or an enemy whose nameplate just
  disappeared because they died. If that's not possible you still get "Bob got a kill · Ashenvale".
- **Only kills add someone to the hitlist.** An attack on you or a friend still triggers an alert
  but no longer adds the attacker. Assists don't add anyone either.
- When a kill adds someone, the attacks they made before that are carried over, so the count
  stays right.
- **One-time cleanup:** hitlist entries with no kills are removed, unless you wrote a note on them.
- Hitlists shared from older versions no longer add anyone without kills.
- **A friend's kill is now a toast by default**, like attacks and deaths. It used to be a chat line,
  so it was easy to miss. If you had it on Chat, it switches to Toast once; you can change it back
  in Options.
- **Shorter messages, same information.** Who did what, then the details, then the place:
  "Rogz killed Bob again (3rd) · 5th today · Tarren Mill" instead of "Rogz killed Bob again (3rd
  time - 4 deaths in 12 min - in Hillsbrad Foothills (Tarren Mill))". The place is the subzone
  when there is one. Level-up, loot and gear toasts are one line ("Bob reached level 30").
- Dropped the "N deaths/kills in M minutes" and "rampage" notes; "5th today" stays.
- **Kill streaks:** kills in a row without dying in world PvP. "Bob killed Rogz · 3 in a row · Duskwood";
  5 and 10 in a row always pop up as a toast. A death that ends a streak of 3 or more says so:
  "Bob killed by Rogz · ended a 6-kill streak". Each player's own addon keeps their count, so it's
  right even if you were offline for part of it. Streaks show once the killer has 0.5.4.
- **Long messages are no longer cut off.** Toasts are a bit wider and wrap onto up to 3 lines. In
  the window, hovering a row shows any cut-off text (e.g. a long Feed entry) in full.

## 0.5.2
Compatible with 0.3.x to 0.5.1.
- **Flavor text can be turned off for short, plain messages:** who did what, then where. With it
  off, every toast is a single line, the same as the chat line:
  - "Bob killed by Rogz Fang - Duskwood"
  - "Bob killed Rogz Fang (revenge) - Duskwood"
  - "Bob attacked by Rogz Fang - Duskwood"
  - "Hitlist: Rogz Fang spotted - Arathi Highlands"
  - "Bob reached level 60", "Bob looted [item]"
- The option is "Flavor text" in Options (it replaces "Varied PvP messages").

## 0.5.1
Compatible with 0.3.x to 0.5.0.
- **Varied PvP messages.** Deaths, kills and attacks now use different wordings and call out
  history:
  - a repeat killer: "Rogz killed Bob again (3rd time)", "Rogz has Bob's number",
    "Bob's nemesis strikes again"
  - a death spree or a bad day: "4 deaths in 12 min", "5th death today"
  - kill streaks: "Bob owns Rogz (3rd kill on them)", "3 kills in 8 min", "rampage!",
    "6th kill today"
  - revenge for a friend: "Bob avenged Alice - Rogz is down"
  - an attacker's record: "... Rogz has killed them 4 times before"
- You can turn this off with "Varied PvP messages" in Options.

## 0.5.0
Compatible with 0.3.x and 0.4.x.
- **Choose per event:** Show (Toast / Chat / Off) and Sound (on / off) for each event. The
  defaults are quiet: toasts and sound for fights, chat lines for everything else, and a soft
  chime for milestones.
- **Smaller toasts:** one compact line with a thin coloured edge. They fade in and out, 3 seconds
  (5 for PvP), and at most 2 on screen.
- **Softer sounds:** a short alert for PvP, the Battle.net chime for milestones, and the whisper
  ping for sightings. The raid-warning horn and the level-up fanfare are gone.
- **Settings moved** to the game's Options → AddOns panel. Open them with the Options button,
  right-click on the minimap icon, or `/fnf options`.
- **Simpler window:** Blizzard's window frame with tabs below it. Three tabs: Hitlist, Players
  (Enemies / Friends filter) and Feed. Rows have class icons.
- **Minimap:** Friends & Foes is now in the minimap's addon menu, so the separate minimap button
  starts hidden. Turn it back on in Options.
- Beta tools (test toasts, simulate, feature status) show only while debug logging is on.

## 0.4.2
Compatible with 0.3.x and 0.4.x.
- **"Friend attacked" only pops up when you could help.** If they're in your zone, it's a
  toast. If they're anywhere else, it's a chat line. You can switch this off with "Fights
  outside my zone: chat only" in Settings.

## 0.4.1
Compatible with 0.3.x and 0.4.0.
- **Faster login, logout and /reload with debug on.** The debug log keeps the newest 2,000
  lines (it was 5,000), trims in batches instead of on every line, and switches itself off
  after 7 days.
- **Less work on Battle.net friend updates.** The friend list is rebuilt at most every
  5 seconds. BattleTags are looked up only for friends who are in WoW Forever, and the
  diagnostic report is built only while debug is on.
- **The send queue sleeps when there's nothing to send.** It used to check 4 times a second
  forever.

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
