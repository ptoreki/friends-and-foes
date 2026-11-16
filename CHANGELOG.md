# Changelog

## 0.7.1
Compatible with 0.3.x to 0.7.0. Sharing kill lists and passing on events need 0.7.1 on both sides.
- **Back button** on the Profile page and kill lists ("< Leaderboard", "< Bob Pal", ...): goes back
  the way you came, as you left it: same scroll position, and on the Leaderboard the same group
  view. Leaderboard, a profile, their kill list, a victim's profile, then Back, Back, Back.
  Picking a tab yourself starts over.
- **Kill lists:** who you and each friend have killed, and how often. Open them with the
  **Kill list (n)** button on any profile: a sortable list of victims with kills, last kill and
  zone; click a name for their profile. For an enemy, it lists which of your friends they killed.
  - Opening a friend's list asks them for their own (top 60 victims) and merges it in, so it
    includes kills you missed. Counting starts with 0.7.0 (kills in your Feed are added once).
  - Kills where the victim couldn't be named aren't listed (WoW Forever's honor message has no name).
- **Catch-up after being offline is better:** friends who come online after you are asked too,
  and the window is 24 hours and up to 100 events (was 12 hours and 40).
- **Friends pass on each other's events:** if Bob played while you were offline and you're never
  online at the same time, a friend who got Bob's events passes them on when you log in.
  - Only friends you name: your client asks about your own friends who are offline.
  - Only if Bob allows it: new switch "Friends may pass on my events" (Options → Friends &
    sharing, on by default), and never while Bob only exchanges alerts with picked friends.
  - One hop only, last 24 hours, no toasts, and your picks still decide whose events you take.
    Events passed on show up in the Feed, hitlist and kill lists as Bob's.
  - Friends on 0.7.0 or older don't mark their events, so theirs aren't passed on.
- The license is in the add-on folder once instead of twice.
- Release workflow updated to the current GitHub Actions (Node 24).

## 0.7.0
Compatible with 0.3.x to 0.6.3. Friends on older versions just don't send profiles yet.
- **Leaderboard tab:** world PvP kills, deaths and K/D for you and your friends, all-time, most
  kills first. Click a column to sort.
  - Each player reports their own numbers, so everyone sees the same board. Your count starts
    from what the addon has already recorded for you.
  - A friend on an older version shows what you counted from their alerts, marked with ~.
  - Only your picked friends are listed if you picked any.
- **Shared groups:** named groups whose PvP stats you follow together, shown on the Leaderboard
  (pick the group at the top left) with the group's total takedowns, deaths and K/D.
  - Not everyone in a group has to be Battle.net friends with everyone else. Members pass each
    other's numbers along, so you see everyone. A member you're not friends with shows how old
    their numbers are and who passed them on ("as of 2h ago, via Alice").
  - Members are Battle.net accounts, not characters: your alts are in too, and your numbers in a
    group are all your characters added up. Each row shows the character the member last played.
    BattleTags are never sent; members are known by a scrambled code made from them.
  - Group names are 2 to 24 characters, like guild names.
  - Any member can invite their own friends (New group, Invite). An invite has to be accepted
    (Join / Decline) before someone counts. Anyone can leave.
  - The leader is the member who has been in the group longest: the creator, and if they leave,
    the next-oldest member. The leader can remove members (right-click).
  - Up to 10 members per group (invites count), and up to 5 groups. If invites made at the same
    time push a group past 10, the latest ones don't count; members who already joined keep
    their place.
  - Everyone in a group needs 0.7 or newer; friends on older versions can't be invited.
  - Only stats are passed along. Live alerts still come only from your own friends.
  - Group messages flow even with friends you didn't pick for alerts.
  - Also `/fnf groups` (list), `/fnf groups new <name>`, `invite <group> <friend>`,
    `join <group>`, `decline <group>`, `leave <group>`, `remove <group> <member>`.
- **Language filter:** group names go through a word filter (ProfanityLib by Deathwing, bundled
  in the add-on; nothing extra to install). An offensive name can't be used, and from others
  it's shown as "Unnamed group". Blizzard's own filter isn't available to add-ons.
  `/fnf status` shows whether the filter is on.
- **New option "Where I am"** (Options → Friends & sharing): turn off sharing your zone and
  AFK / in-a-fight status. Your kill/death numbers on leaderboards and in groups follow the
  existing "World PvP" switch.
- **Enemies and Friends are tabs now**, not a dropdown on a Players tab.
- **Profiles:** click a name on the Leaderboard, Enemies or Friends tab (double-click on the
  Hitlist), or click a toast, to open a Profile tab.
  - Friends: kills, deaths, K/D, rank, nemesis (the enemy who killed them most), most wanted,
    where they are now ("online · Duskwood · in a fight" or AFK), addon version (flagged when
    out of date) and their recent PvP.
  - Enemies: kills on your group, deaths to your group, who of your friends they killed,
    revenge taken, who has them as most wanted, last seen, recent PvP and your note.
- **Most wanted:** make an enemy your most wanted from their profile; friends see it on yours.
  Also `/fnf wanted <name>` (or target them and type `/fnf wanted`).
- **Picking friends** moved into their profile (Pick for alerts / Unpick). Friends the addon sees
  but hasn't heard from yet can still be picked with a click in the Friends list, and
  `/fnf group` works as before.
- **Fix:** when a friend started a fight, you got "Bob attacked Rogz" and then, a few seconds
  later, "Bob attacked by Rogz" for the same fight. Now only the first one comes. A second enemy
  joining in is still reported.
- **Layout fixes:** buttons whose label changes (Pick / Unpick, Make / Clear most wanted) now
  resize to fit. The Profile page starts below the search bar. The hint line under lists is
  capped at two lines so it can't reach the list. In the fallback Options panel (used only when
  the game's settings screen isn't available), the milestone note no longer overlaps the
  options below it, and its buttons fit their labels.
- **License:** Friends & Foes is now free software under the GNU GPL v3 or later (LICENSE in the
  repo, LICENSE.txt in the add-on folder). GPLv3 because it includes ProfanityLib, which is GPLv3.
- New commands: `/fnf board`, `/fnf groups`, `/fnf profile [name]`, `/fnf wanted`.

## 0.6.3
Compatible with 0.3.x to 0.6.2.
- **Catch-up after being offline:** when you log in, friends who are online send what happened to
  them in the last 12 hours (attacks, deaths, kills, level-ups, loot).
  - It goes into your Feed, at the time it happened, and killers go on your hitlist. No toasts or
    sounds, just one chat line: "While you were away: 5 events from Bob."
  - Only friends who are online when you log in can send it.
- **Hitlist window:** the buttons at the bottom can no longer overlap. They're laid out from the
  right, every button is at least as wide as its label, and the note box takes the space that's
  left. The row also sits above the page arrows now.
- **Debug log:** with debug logging on, anything the addon does that takes over 20 ms is logged as
  [SLOW], and loading screens are marked as [LOADING]. This helps track down a reported window
  minimize/restore on loading screens.

## 0.6.2
Compatible with 0.3.x to 0.6.1.
- **Who killed whom:** hover a player on the Hitlist to see their kills on your group, then who
  of your friends they killed and how often ("Bob 3x, Alice 1x"), when they were
  last seen, and your note.
  - Kills from before 0.5.1, when per-friend counting started, are listed as "before counting
    began".
- The tooltip on a hitlist player's nameplate shows the counts too: "killed Bob 3x, Alice 1x".
- **Two new toast styles: Alliance and Horde.**
  - Alliance: deep blue with gold trim. Horde: deep red with bronze trim.
  - Each has its faction crest faded behind the text, a header saying what happened, and a thin
    stripe in the event's colour.
  - Choose in Options → Appearance → Toast style.
- **More names in class colours:** if a message doesn't say a player's class, the addon uses the
  class it already knows for them (e.g. a killer named by the death recap), so fewer names show
  up white.
- **New options:**
  - **Toasts stack** downward or upward, and **Toasts on screen** 1-4 (Appearance).
  - **Level-ups to show:** every level, every 5, every 10, or only 60 (Alerts).
  - **New gear to show:** blue or better, or epic only (Alerts).
  - **Milestones always pop up:** on/off (Alerts).
  - **Skull on hitlist players** and **Hitlist info in tooltips** are now separate switches.
- **New defaults** for new installs (the Defaults button resets to these):
  - Toasts for everything except Hitlist shared (chat line).
  - Sound for all of those except Friend attacks someone and Level ups.
  - Sounds: Alarm for attacked, Raid warning for killed, Level-up fanfare for a kill, Map ping
    for sightings.
  - Toasts stay 5 seconds. Fights in other zones and in combat aren't held back.

  Your own settings don't change.
- **Fixes from a code review:**
  - Choosing a "Forget hitlist players" period now asks first if it would remove anything right
    away. No keeps the old setting.
  - If you had turned off "Mark hitlist players", the new tooltip switch starts off too.
  - The Victims column shows who a player killed, most first, with counts ("Bob 3x, Alice 1x").
  - "Epic only" counts only the epics in a batch of new gear.
  - Lowering "Toasts on screen" takes effect right away.
  - A just-shared hitlist entry no longer shows an old level.
  - Every item quality colour is recognised, including white and grey.
  - Class colours are looked up faster, and use simulation data while in simulation view.
  - Combining two records for the same enemy now adds up their per-friend kill counts too, so
    "Bob 4x" matches the total.
  - A shared hitlist no longer imports players your "Forget" setting would remove at the next
    login.
  - With "Epic only", the Feed still records the whole gear batch.
  - The fallback options panel has the tooltip and milestone switches too.
- **Old data fades instead of piling up:**
  - **Hitlist players nobody has seen for 90 days** are greyed out and listed at the bottom. As
    soon as you or a friend sees them again, they're back to normal.
  - **Optional forgetting:** Options → Friends & sharing → "Forget hitlist players not seen for":
    Never (the default), 3 months, 6 months or 1 year. Entries you wrote a note on are always
    kept.
  - **Old levels** (seen over 30 days ago) show as "24+" in grey, since they've probably levelled
    since.
  - **Friends you haven't heard from in 6 months** leave the Friends list while they're offline.
    Their record is kept, and they're back as soon as they come online.
- **Attacks are no longer shown** on the hitlist: not in the hover, the Attacks column (removed),
  the nameplate tooltip, or sighting messages. Kills are what count. Attacks are still counted
  in the background.

## 0.6.1
Compatible with 0.3.x to 0.6.0. Friends need 0.6.1 to send these alerts.
- **New alert: a friend attacks someone.** When a friend starts a fight with an enemy player
  (auto-attack, auto-shot or a harmful spell on them), you get "Bob attacked Rogz Fang · Tarren Mill".
  If Rogz is on your hitlist, it says "Bob is going after Rogz Fang (hitlist)".
  - It's a toast in your zone and a chat line elsewhere, like "Friend attacked".
  - It doesn't fire if the enemy was already attacking them. That's the "Friend attacked" alert.
  - Once per enemy every 2 minutes. Attacking someone doesn't add them to the hitlist.
  - Set it under "Friend attacks someone" in Options, with its own sound on the Sounds page.
- **Deaths name the enemies who helped:** "Bob killed by Rogz Fang (with Kragg Bear) · Tarren Mill".
- About assists: the game doesn't tell addons who landed the killing blow. A friend who helped
  gets the same honor message as the one who finished, so assists already show as kills, each
  with its own toast.

## 0.6.0
Compatible with 0.3.x to 0.5.5. Friends need 0.6.0 to send or receive sightings.
- **Shared hitlist sightings:** when a friend spots someone from their hitlist, you get
  "Rogz Fang spotted by Bob · 2 kills, 3 attacks · Astranaar". You're alerted once per player
  every 5 minutes, whoever spots them. This uses the Hitlist sighting alert setting and the
  World PvP share setting.
- **Choose the sound for each event:** a new Options → Sounds page with one dropdown per event.
  There are 11 built-in game sounds to pick from, plus Default. Picking one plays it so you can
  hear it. Whether an event makes a sound at all is still set on the main page.
- **Toast size and duration:** sliders in Options → Appearance (70-150%, 2-10 seconds; PvP toasts
  stay 2 seconds longer). Also `/fnf size 120` and `/fnf duration 5`.
- **Search box** in the window. It filters the Hitlist and Players lists by name or guild, and
  the Feed by text.
- **Friend's zone** in the Friends list ("online · Ashenvale"), from Battle.net.
- **Weekly summary:** once a week at login, a chat line with your takedowns, deaths and nemesis.
  It can be turned off in Options → Appearance.
- **Minimap and addon-menu tooltip** shows friends online, hitlist size and your last fight.
- **Welcome message** the first time the addon runs.
- The simulation banner moved to the bottom of the window.
- The tabs under the window (Hitlist, Players, Feed) are now evenly spaced and the same width;
  they used to overlap.
- Counts in the window, tooltips and messages are never shown as "-0" or below zero.
- **New Options page: Where it works.**
  - **Alerts while you're in:** a dropdown each for Dungeons, Raids and Battlegrounds.
    Choices: *Show*, *Wait until I'm out* (the default, same as before), *Chat line only*, or *Off*.
  - **Track my PvP in:** Open world (on) and Battlegrounds (off). If you turn on battlegrounds,
    your fights there count, and anyone who kills you there goes on the
    hitlist.
- **Debug log: every alert's outcome.** One `[TOAST]` line per alert: shown as a toast, a chat line,
  off, waiting (in combat or in a dungeon), merged, or dropped, always with the reason. Now a
  missing toast can be traced.
- **Remove players and clear the hitlist, with confirmation:**
  - Right-click anyone in the Hitlist or Players lists to remove them.
  - The Hitlist tab has a **Clear hitlist** button.
  - Every removal asks Yes/No first, including the existing Remove button.
  - Removing someone from the hitlist keeps their kill/death record. Removing them under Players
    deletes that record.
- **Fixed:** opening Options in combat caused a Lua error. The game doesn't let addons open its
  settings window in combat, so Options now says so and doesn't open.
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
