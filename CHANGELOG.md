# Changelog

## 1.0.6

- **Close buttons work in combat:** the X on the main window, the alert list, the Bounty and Group windows and the What's new popup hid their window through the game's `HideUIPanel`, which is blocked for add-on windows in combat, so the X did nothing during a fight. They now hide their own window directly (`UI.CloseButton` / `UI.CloseOnClick`).
- **Stats: Hunting / Hunted toggle spacing:** buttons grow to fit their label, and "Hunting" is wider than the 64px the layout assumed, so the Hunted button overlapped it. Hunted now hangs off Hunting's real right edge (2px gap, like the level selector), and the pair is centred between the title and the level selector using their real widths.

## 1.0.5

- **Victims and Killed by counts are players:** the profile buttons now say how many different players ("Victims (3)", "Killed by (2)"), not total kills, and the "Name not readable" line is not counted as a player (in the button or in the list's hint line).
- **Stats: Hunted (deaths):** the Stats page has a **Hunting / Hunted** toggle next to the level selector (kept while the game runs). Hunted turns the three columns into **When you die** (deaths today / last 7 / last 30 days, or time out in the world and K/D for one level bracket; busiest day and hour from 20 deaths; deaths per hour from an hour out in the world), **Killed by level gap** (Skull, Higher, Even, Lower, Grey: the killer's level against yours, same tiers as kills, counts and share of deaths) and **Where you die** (top zones). The tiles stay the same. With no deaths yet the charts show as faded outlines ("Your first PvP death fills these in."). The death log now stores the killer's level and yours (`kl`, `ml`), and each level bracket keeps death totals (killer tiers, zones, weekdays, hours). Deaths logged before this version have no level of yours, so they are not added to the brackets.
- **Killed by:** a **Killed by** button on your own profile (next to Victims and Stats) opens a list of the enemies who killed you on this character: name (click for their profile), level, guild, times (right-aligned, most first by default), and when they last did, with the zone. Friends and your own alts are left out. Everything is sortable. Built from the hitlist's per-victim kill counts, the same data the nemesis uses.
- **Notoriety column (Hitlist):** each enemy's current notoriety, the same number as on their profile (what killing them is worth before your share and level adjustments), coloured by rank from grey (Nuisance) to red (Public Enemy), with a red ! while they are on a rampage, and a dash when there is nothing to collect. Sortable. It sits between Kills and Victims; The number columns (Lvl, Kills, Notoriety) are right-aligned, Kills is narrower, and Guild and Last seen are wider. Last seen shows only the main zone ("17h ago - Tanaris"); the row tooltip still has the full place with the subzone.

## 1.0.4

- **Battlegrounds never count:** PvP in a battleground (or arena) no longer counts for anything: no kills, deaths or K/D, Friends tab, profiles, victims lists, hitlist, attackers, notoriety, bounty completion, streaks or milestones, nemesis, weekly summary or Stats. The only thing it can produce is a Feed line ("... killed ... (battleground)", small grey tag) for a kill or a death, plus an alert for a friend's, and only when **Dungeons, raids, battlegrounds** is not off (show or wait until you're out, as before); with it off a battleground shows nothing at all. Your own battleground fights are not sent to friends. A friend on an older version still sends theirs: they are recognised by the zone name (Warsong Gulch, Arathi Basin, Alterac Valley, Eye of the Storm) and handled the same way, and caught-up ones are dropped. The old **Battlegrounds** switch under Where your own PvP is tracked is removed (the saved value is deleted); battlegrounds are controlled only by Dungeons, raids, battlegrounds. Hitlist entries added by it earlier age out as usual.

## 1.0.3

- **Time out in the world (Stats):** the time counter (it behind Average life and Kills per hour, and the row now called "Time out in the world") only runs while you could be ganked: it pauses while you are dead or a ghost, AFK, resting in an inn or city, on a flight, or in a dungeon, raid, battleground or arena. A check the game can't answer (or hides) doesn't pause anything. The counter is saved when any of those change.
- **Open-world PvP only (Stats):** kills and deaths inside a dungeon, raid, battleground or arena are no longer logged or counted in the Stats page (kill log, death log, brackets, best streak). The Feed, alerts, notoriety and streak toasts are unchanged.

## 1.0.2

- **Time played and lives (Stats page):** each character now counts the time it is logged in and alive (not dead or a ghost; it never asks the game for /played), from this version on. Your own live PvP deaths go in a death log (time, character, time played, killer, zone; the newest 1000, never PvE deaths or caught-up ones), and each logged kill remembers the time played. The Stats page gets a fourth tile, **Average life** (the average time played between PvP deaths, from 3 PvP deaths; line 2 shows your current life and its kills, e.g. "now 38m \u00b7 3 kills"; the tooltip names your longest life), and a **Kills per hour** row in "When you hunt" (kills logged since this version per hour played, from 1 hour played). Locked stats show a padlock and progress like "1/3 deaths" and "23/60 min". Nothing new is sent to friends.
- **Level brackets (Stats page):** a selector at the top of the page (All, <20, 20s, 30s, 40s, 50s, 60) shows the whole page for the time you were that level: tiles, charts, busiest day and hour, kills per hour, average life. A bracket shows Time played and K/D instead of Today / Last 7 / Last 30 days (those always count all levels). Brackets without anything yet are greyed out. The selection is kept only while the game runs. Each character keeps running totals per bracket (kills, deaths, time played, lives, levels, level-gap tiers, weekdays, hours, up to 50 zones) that are never trimmed, so All-time numbers survive the 1000-entry kill log. Kills from the 1.0.1 log that know your level are added to the brackets once; deaths, lives and time played can't be recovered for before 1.0.2.

## 1.0.1

- **Stats page:** a **Stats** button on your own profile (next to Victims) opens a one-page view in the tab, with Back: this character's name and level, three headline tiles (kills logged; best streak with the current run; average victim level with the average gap in words, "3 higher than you" / "2 lower than you" / "your level", from 5 kills with a known, non-skull level, until then a padlock and progress like "4/5 kills"), a "When you hunt" column (today, last 7 days, last 30 days, busiest weekday and hour from 20 logged kills), and two bar charts with counts and shares: kills by level gap (Skull to Grey, with the same grey-level and level tiers as notoriety) and your top 5 zones, with the full zone name. With nothing logged yet the charts show as faded outlines ("Your first kill fills these in."). It is built from a new kill log of your own live kills (time, character, victim, both levels, zone; the newest 1000, kept on this account; the page counts only the character you're on), counted from this version on; caught-up kills are never logged. Streaks are kills without dying (the existing streak); the best one is remembered from now on, per character. Nothing new is sent to friends.
- **Add by name:** the Hitlist tab has an **Add...** button (and `/fnf hitlist add <name>`) that puts any enemy player on your hitlist without a target. Names are letters (accents fine), up to two words like "Ru Mia", 2-24 characters; each word gets a capital; digits, symbols, you and your friends are refused with a chat message. A typed entry has no class, level or guild until you see them (the normal sighting fills them in), is never forgotten by itself (only you remove it), isn't passed on to friends until they've done something, and gets the nameplate skull and sighting alerts like the rest.
- **Bounty without a target:** Post bounty opens a small window (player, amount, days, message; your target's name is filled in), and `/fnf bounty [name] <amount> [days] [message]` takes a name, e.g. `/fnf bounty Ru Mia 10g 3d Caught me AFK`. The old `/fnf bounty 10g 3d` on your target still works. A bounty on a name puts them on your hitlist as a typed entry. The message goes out as a new last field `note` in BTY (older friends ignore it).
- **Bounty message:** an optional note of up to 60 characters, put through the language filter (the one for group names) before it's sent and again on arrival, with `|` and control characters removed. Shown when you hover its row on the Bounty board, in the bounty line's tooltip on the enemy's profile, and quoted in the "bounty posted" toast and chat line. If a message won't fit in one Battle.net message with very long names, it is trimmed first.
- **Bounty target spotted:** when you see (target, focus, mouseover, nameplate) a player with an open bounty on them, anyone's, you get a big raid-warning message in the middle of the screen (name, reward, zone), plus a bounty toast that stays twice as long, with the raid-warning sound and a red edge. Once per player per 5 minutes. When a friend sees them, you get the same louder toast without the big message. It follows the Bounty board alert setting (off: nothing; chat: just a chat line) and Where it works. Debug log: `BOUNTY-SPOTTED`.
- **Nemesis ties:** the enemy who killed you (or a friend) most is the nemesis; on a tie, the one who killed most recently (before, the name that sorts first, or on the weekly summary whichever came first). Used on profiles and in the weekly summary. Older data without times keeps the old order.

- **Levels in the Feed:** PvP lines in the Feed and in Recent PvP on profiles show the level each player was at the time, small and grey after the name ("Rogz Fang (35) killed Bob Gank (38) - Duskwood", "Bob Gank (Skull)" for a skull-level enemy). Nothing is shown when a level is unknown (older entries, older versions). Your friends' own level is the one already in every message; a skull-level enemy now travels as level 0. Replayed (catch-up) events carry your level from when they happened.
- **Resurrection Sickness:** killing an enemy who has Resurrection Sickness gives you no notoriety, unless they are a skull to you (level ?? or 10 or more above you), who give the normal amount. The kill still counts in your stats, and the Bounty board is unaffected. If the game won't show their buffs, they count as not sick. A skull-level enemy you've seen now also counts as "??" (x1.5) for the level factor.
- **Sighting text:** a sighting of an enemy who only attacked your group no longer says "0 kills on us": it says "attacked us N times" (or "attacked us once"); "1 kill on us" is singular; with nothing known the part is left out.

## 1.0.0

Friends & Foes is out of beta.

### What's new popup
- **Patch notes:** the first time you open the window after an update, a small popup lists what's new in this version, once (`FriendsAndFoesDB.seenVersion`, per account). Not shown in combat (it waits for the next open), not on a brand-new account (the tour covers that), and never together with the tour. `/fnf new` (or `whatsnew`, `changes`) shows it any time.

### Kills & credit
- **One toast per death:** when several friends (or you and a friend) kill the same enemy together, you get one toast and one Feed line naming them all ("Rogz Fang and Buddy Pal killed Bob Gank", "You and Buddy Pal killed Bob Gank"), not one each. If the enemy really dies again (the same friend reports them again, they got back up in between by Reincarnation, a soulstone or a resurrection, or it was more than a minute later), that is a new toast. Kill counts, victims lists, notoriety and bounties still count every killer.
- **Killing blows:** when the game reports that you (or your pet: hunter pet, warlock demon...) landed the killing blow on a player, your kill names them exactly (even from a DoT, out of range or without a target) and is marked "(killing blow)" or "(pet's killing blow)", for you and your friends. If the game doesn't report it, kills are named from what's on screen, as before. The debug log records what the game reports.
- **The killing blow gets the credit:** that player closes the bounty and is the one to be paid. When nobody's killing blow is reported (a guard's last hit, say), the credit goes to whoever attacked the victim most recently (spells, auto-attack or shot, or their pet). Only when nothing at all is known (an older version) does the first to report the kill close it.
- **Kills in long fights get their name:** an enemy you're fighting (your target, focus or a nameplate) stays "seen alive" while their health changes, so a long fight that ends in a kill is no longer left without a name (and without bounty or notoriety). This also covers enemies killed by a damage-over-time spell you never targeted, as long as their nameplate is on screen.
- **Healers count too:** a friend who heals or buffs you during a fight (without being in your party) shares the notoriety and any bounty when you get the kill. It is not a kill for them: no kill count, streak or victims list.

### Notoriety
- **Reworked:** an enemy who never hurt you or a friend is worth 10. An enemy on your Hitlist is worth 100 per murder and 25 per attack since the last claim (at least 50), 1.5 times that on a rampage (3 kills on your group within an hour), and a little less for every quiet day since their last offence.
- **No camping:** killing the same enemy again within 30 minutes of the last time is worth less each time: the base value (10 for a random, the 50 minimum for a hitlist enemy) drops to half, a quarter, then nothing, and the chain keeps going as long as they are killed again within 30 minutes. Points they earned by killing or attacking you or a friend are never reduced, and doing so makes them worth full value again. Wanted posters show the reduced number. Kills still count in your stats.
- **Level matters:** your share is scaled by the victim's level against yours at the kill: a grey (trivial) player pays nothing, 6 or more levels below you x0.25, 3 to 5 below x0.5, within 2 x1, 3 to 5 above x1.25, 6 or more above (or "??") x1.5. Unknown levels count x1. Wanted posters still show the base value; kills still count in your stats.
- **Ranks and titles:** enemies get a rank on their Wanted poster (Nuisance, Menace, Wanted, Most Wanted, Public Enemy). You get a title from your notoriety (Tracker, Hunter, Bounty Hunter, Manhunter, Legend), with a toast when you earn a higher one.
- **Shared equally:** everyone who gets the kill (within a minute of the first) shares the notoriety equally; alone you get all of it. The killing blow doesn't change the split.
- **It fades:** you lose 10% of your notoriety for each full week without a claim. Your profile also shows everything you ever claimed, and what you claimed this week (the weekly summary mentions it too).
- **Takedowns:** a claim of 300 or more gives everyone who saw it a toast.

### Bounty board
- **Shared bounties:** several players who got the kill (within a minute of the first) complete a bounty together, and the gold is shared equally; the poster pays each of them their share by trade and marks it paid once for everyone. A poster who was in on the kill doesn't pay themselves. The board's Closed by column lists everyone, and the Bounties column on the Friends tab counts each person's share.
- **Bounties travel further:** you also pass on your friends' open bounties (and ones done but not paid yet), up to 10 at a time, so a friend sees a bounty even when its poster is offline. Only the poster can change it, and a bounty is only ever passed on once.
- **Most wanted is gone**, and so are hitlist notes: the Bounty board does that job. The Make/Clear most wanted button, the Most wanted lines on profiles, `/fnf wanted` and the note box on enemy profiles are removed, and notoriety no longer adds anything for friends who wanted someone. Saved most-wanted picks and notes are cleared.

### Hitlist
- **How long players stay on the hitlist:** three options in Friends & sharing, one for each kind of player: "Forget attackers after" (attacked you or a friend, never killed anyone), "Forget one-time killers after" and "Forget repeat killers after". Each can be 1 week, 2 weeks, 1 month, 3 months, 6 months, 1 year or Forever. Attackers are forgotten after 2 weeks unseen by default; killers are kept forever. Someone with an open bounty is never forgotten, and seeing them again starts the time over. Entries grey out after 30 days unseen (was 90). Choosing a shorter time asks first if it would remove anyone right away, and a line in chat tells you when players were removed at login.
- **Victims:** kill lists are now called Victims.
- **Enemy profiles are shorter:** the Revenge taken, On your hitlist and Killed lines are gone (the Victims button shows who they killed). The Revenge toast stays; the green "R" next to Hitlist kill counts is gone.
- **No more Share hitlist button:** friends' fights already fill your hitlist live and when you log in, and bounties bring their targets. A share from a friend on an older version still arrives.

### Friends tab
- **The Leaderboard is part of the Friends tab now:** one list of you and your friends, ranked by kills, with deaths, K/D, notoriety, Bounty board gold collected and where they are. Shared groups are picked above it, as before. `/fnf board` opens it. The add-on version column is gone (it's on each profile).
- **Only friends with the add-on:** Battle.net friends who don't run Friends & Foes are no longer listed ("nothing received from them yet" rows are gone).
- **Fewer alts:** friends' characters below level 15 (bank alts, fresh alts) are hidden by default. Turn it off with "Hide characters below level 15" in Friends & sharing. Your own characters always show, their alerts still come through, and they appear once they reach 15. When a friend is online on a hidden alt, their other character shows "online (on an alt)".
- **Bounties column:** the Bounty board gold each person has collected (bounties paid to them, the ones you know of).

### Syncing
- **Catch-up covers a week:** when you log in, friends send what happened in the last week (was 24 hours), up to their latest 250 events each (was 100).
- **Alts count:** when a friend logs in, they also hear what your other characters did while they were away (only what you share). Those characters show up in their Feed as your friends, and your alert list covers them too. Both of you need this version.
- **A hitlist hello:** when you meet a friend, you send them your 40 most active hitlist entries, once a week at most. They are added quietly: no toast and no Feed line. Only enemies who killed or attacked the friend, you, or a friend you have in common come along.
- **Profiles travel further:** you pass on up to 10 numbers (kills, deaths, notoriety) of friends who are offline, when they let friends pass on their events, so your Friends tab stays up to date. Only the numbers, and only once.
- **No gaps while you are both online:** if a friend drops off and comes back, or goes quiet for an hour, you ask them for what you may have missed since their last event.

### Alerts & options
- **Four alert settings instead of nine:** Friends' fights (attacked, attacking someone, killed, a kill), Hitlist sightings, Friends' progress (epic loot, new epic gear, level-ups) and the Bounty board, each a toast, chat line or off, with or without sound. Attacking someone and plain level-ups stay quiet.
- **Five sounds instead of nine:** Friend in trouble (attacked, killed), Friend's kill, Hitlist sightings, Friends' progress and the Bounty board. Urgent news never sounds like good news, and on "Default" attacked and killed still sound different from each other. The sounds are on the Alerts page now. Your old picks carry over where they can.
- **Milestones always pop up** (level 60, a looted epic BoE, revenge, kill streaks of 5, 10, 15...): the switch is gone.
- **New gear means epic gear:** blue items are no longer announced or sent, and the "New gear to show" choice is gone.
- **One setting for instances:** one choice for dungeons, raids and battlegrounds together: show, wait until I'm out, or off. Your dungeon choice is kept ("chat line only" becomes "wait until I'm out").
- **Alert list in Options:** Options -> Friends & sharing -> Alert list (or `/fnf alerts`) opens a small window with a tick box for each friend. The Friends tab no longer has an Alerts column, and clicking a friend who doesn't have the add-on yet no longer changes your list.
- **Four option pages instead of six:** Test alerts is the first thing on the Alerts page. The instances setting is on the Alerts page under "When alerts wait", and tracking your own PvP is in Friends & sharing. The minimap button setting is under Appearance, and Advanced only has debugging. The "Hitlist shared" alert and the Status button are gone (`/fnf status` still works).
- **Window sounds** (opening the window, turning a page) are always on, like the game's own windows; "Alert sounds" only switches the alerts' sounds.
- **Simpler test:** `/fnf test` (also `/fnf sim`, and Test alerts in the options) shows one sample of each alert and a chat line. Nothing is recorded or sent. The old simulation is gone, and its saved data is removed.

## 0.9.3
- **New: the Bounty board.** Put your own bounty on an enemy player, in gold, silver and copper,
  open for as many days as you pick (1-30): target them and click **Post bounty** on the new
  Bounty board tab, use the button on their profile, or type `/fnf bounty 10g 50s 3d`. It goes
  on your hitlist and on your friends' Bounty board and hitlist, with a toast. When you or a
  friend kills them, it's done, with a toast: whoever posted it pays the killer by trade in the
  game, then right-clicks it to mark it paid. Finished bounties stay on the board with who
  closed them. It's a promise between friends; the add-on never moves gold. Up to 5 open
  bounties each, up to 10,000 gold. The toasts are a new alert in Options (Bounty board).
  Friends need this version to see them.
- **"Bounties" are now "Notoriety":** the just-for-fun number on Wanted posters, the
  Leaderboard and profiles is points, not gold, so it isn't mixed up with real bounties. Nothing
  else about it changed, and your total carries over.
- **Minimap button:** on by default again (it was hidden where the minimap has an add-on menu),
  sits on the edge of the minimap at any size or shape instead of inside it, and the icon is
  centred in its ring. Drag it round the minimap, Shift-drag it anywhere, and
  `/fnf minimap reset` puts it back.
- **No number is ever shown with a minus sign.** A bounty could show as "-,250", and a level or
  streak from a friend's message could come through negative. Every number from friends is now
  checked, and a test fills the add-on with broken numbers and checks every tab, profile, kill
  list, tooltip, toast and chat line.
- **Icons next to numbers sit level with them:** the bounty coin, the Leaderboard medals and the
  tooltip skull are now as tall as the text around them.
- **No more "*" or "+" stuck to numbers:** a Hitlist kill count is just the number, and the row's
  tooltip says how many were likely rather than certain. An old level stays grey without the
  "+", and the tooltip says it's probably higher now.
- **Your profile's character model** is framed a little wider, so the top of the head isn't cut
  off.

## 0.9.2
- **Your profile shows your character from the chest up** (head and shoulders) instead of the
  whole body with the top of the head cut off.
- **The Hitlist now also has anyone who attacks you or a friend first**, not only killers. Their
  kills start at 0 and count up if they kill one of you. Shared hitlists bring attackers along
  too.
- **No more Enemies tab:** enemies are on the Hitlist. `/fnf` and old links to "Enemies" open
  the Hitlist.
- **Fixes:**
  - A friend's test alerts (`/fnf sim all self`) no longer switch your window to the
    simulation, and no longer stop your real kills from collecting bounties. One chat line says
    they arrived.
  - A most wanted's bounty price (250 per friend who wants them) is paid out once, not on every
    kill of them.
  - A kill is only credited to an enemy you saw alive in the last minute, so an old corpse you
    target or ride past isn't counted as your kill.
- **Profile page:**
  - Your own profile says "You", and your nemesis "killed you".
  - Kills whose victim couldn't be named are a "Name not readable" line in the kill list, so the
    kill list adds up to your kills.
  - A likely killer (the last attacker, when the death recap couldn't tell) is shown as
    "(likely)" instead of a bare "?".
  - "Clear most wanted" is only there when you have one.
  - A recent PvP line that's cut short shows in full on hover.
- **Safer text from friends:** zones, guilds and classes in friends' messages are plain text, and
  anything that isn't a real item link is shown as plain text.
- **Lighter catch-up:** a friend passes on at most 30 of your other friends' events when you log
  in (was 100); every online friend answers, so this was mostly duplicates.
- **SPEC.md rewritten** to match how the add-on works now.

## 0.9.1
- **The Wanted poster is back inside the enemy's profile**, not a separate window: the poster on
  the left, their facts and recent PvP beside it. No window popping up, nothing to close.
- **Easier to read poster:** darker ink, no drop shadow on the light paper, the level and guild
  lines a size bigger, and the bounty in red ink (gold on parchment was hard to see).
- **Fix: the main window's buttons showed through the group window** where the two overlapped
  (main window near the right edge of the screen). It now sits above the main window and its
  buttons, and comes to the front when clicked.
- **The poster's portrait looks printed on it:** a sepia print, darker towards its edges, in a
  double ink frame with a soft shadow; the face or symbol in it is in the same sepia ink instead
  of a bright icon on a flat dark box.

## 0.9.0
- **Bounties.** Every enemy's Wanted poster shows their open bounty in gold (just for fun, not
  real gold): 100 for every murder and 25 for every attack on you and your friends since someone
  last collected it, plus 250 for every friend who has them as most wanted. **Kill them to
  collect it:** everyone who gets the kill within a minute shares it equally, and their bounty
  starts again from the minimum. A chat line tells you what you collected.
- **Bounties collected** is your all-time total (account-wide), sent to friends with your profile
  like your K/D: a new **Bounties** column on the Leaderboard, and a line on profiles (yours also
  says how many you've collected). Friends on older versions show an empty cell until they update.
- Profiles have room for one more line.
- **Bounties pass through groups:** a group member's bounties reach you even if you aren't
  Battle.net friends, on the same relayed card as their kills and deaths.
- **The Wanted poster has its own window**, tall like a real poster, docked beside the main
  window: a bigger face, bigger WANTED and bounty. The enemy's profile page keeps their facts and
  recent PvP at full width. Close the poster and it stays closed for that enemy; the *Wanted
  poster* button on their profile brings it back. Drag it anywhere; it goes when you leave the
  profile.
- **The group window:** the Leaderboard's *Group* button (*Invitation* while you're invited) opens
  everything about the group in one place, beside the main window: its name and leader, the
  members (joined or invited), its totals, and the buttons that apply to you - Invite and Leave,
  Join and Decline, and Remove beside each member when you lead. The Leaderboard just shows the
  board now.
- **First-run tour:** three short pages the first time you open the window (everyone sees it once
  after updating). `/fnf tour` shows it again.
- **Hover to explain:** column headers and profile labels explain their numbers (K/D, rank,
  bounties, the * on the Hitlist, murders, revenge...).
- **Debug report:** `/fnf report` (or *Copy debug report* in Options) puts everything a bug report
  needs in one box to copy and paste: version, what works on your client, friends' versions,
  errors and the debug log. No more digging in the WTF folder.
- **Friends on older versions:** one chat line per session names them, so you know why some
  things don't sync with them.
- **Fix: a death could go unreported.** With long names, a long zone name and three helpers, the
  death message was over the game's 255-byte limit and was never sent. Helpers are now dropped
  from the end until it fits (your own record keeps them all).
- Under the hood, for a dependable 1.0:
  - The window is split into parts with one job each (lists and tabs, profiles and posters,
    building blocks, commands), with a small layout helper instead of hand-counted positions:
    every row of buttons (top bar, Leaderboard group buttons, page arrows, Hitlist and profile
    buttons, the Wanted poster) lines itself up, and buttons that hide leave no gap.
  - Every message type is listed with the version it came in; tests check each one reads back
    the same and fits the 255-byte limit at its longest.
  - Saved data has a version and numbered upgrade steps, and everything that grows has a limit
    (kill lists 250 victims each, 3000 enemy records; the oldest harmless ones go first).
  - A test checks every text the add-on shows exists, and translations can be added as one file
    per language.

### Also in 0.9.0 (from the unreleased 0.8.1)
- **A real Wanted poster.** An enemy's profile is now a poster-shaped sheet of light, worn paper,
  everything centred: big **WANTED**, a framed portrait, **DEAD OR ALIVE**, their name, level,
  race and class, guild, and their **bounty** in gold (just for fun: 100 per murder, 25 per
  attack, 250 per friend who has them as most wanted; hover it to see). Their facts ("Murders",
  "Died to us", ...) and recent PvP sit in the column beside it. Their faction is a small crest
  in the corner (it's always the other one).
- **The portrait:** the game's own painted face for their race and sex, with their class crest
  on its corner (their race symbol if the face isn't there; their class crest alone if you
  haven't seen their race). Race is only known once you've seen them yourself (target,
  mouseover, nameplate); it isn't sent between friends.
- **Parchment only on Wanted posters.** The Hitlist is back to its plain striped rows.
- **The Profile tab is always your own profile.** Clicking someone's name opens their profile
  inside the tab you're on (that tab stays lit), with a Back button. The same goes for kill lists.
- **Fix: Leaderboard ranks out of order.** Sorted by kills, players with the same kills could
  show in the wrong order (rank 8 above rank 5). Ties now follow the rank.

## 0.8.0
A look pass: the window feels more like part of the game. Everything uses only the game's own
fonts, art and sounds, and falls back to the plain look if any of it is missing.
- **Enemy profiles are Wanted posters:** aged parchment, "WANTED" above their name, their class
  crest in the corner.
- **Title font:** names on profiles and the Recent PvP heading use the game's quest-title font.
- **Medals on the Leaderboard:** the top 3 get a gold, silver or copper coin and colour.
- **The Hitlist is a ledger:** parchment with ruled lines.
- **Soft motion:** the window and each tab fade in; profile numbers count up when you open one.
- **Window sounds:** the game's own sounds when you open or close the window, turn to another
  tab, or save a note. New option "Window sounds" (on by default; also follows "Sounds on").

## 0.7.3
- **Your character on your own profile:** the Profile tab shows your character model above
  your recent PvP (drag it to turn it). Friends' and enemies' profiles are unchanged.
- **No more addon whispers:** everything goes over Battle.net only, so half as many messages
  (less load on the realm). Whispers are only used if Battle.net messaging isn't available at all.
  Whispers from friends on older versions are still accepted.
- **Fix: a friend could be ignored completely.** For some friends Battle.net reports their game
  without a character name and with game version 0. The add-on took that as "a different WoW
  game" and dropped everything they sent (a group invite answer, alerts, everything), and never
  sent them anything. Version 0 now means "not said", and their name comes from their own
  messages. Seen in a live debug log.
- **A friend fighting next to you is never named as your killer or a helper.** The death recap
  lists everyone in it without saying whose side they're on, so a friend could show up as "killed
  by Enemy (with Bob)" and even be counted as an enemy. Now:
  - the dying player's client takes the newest *enemy* in the recap as the killer, and leaves out
    friends, party and raid members, and themselves;
  - every client also drops its own friends from a death's killer and helpers (this fixes
    messages from friends who haven't updated yet);
  - a friend wrongly marked as an enemy by older data no longer shows on the Enemies tab or the
    Hitlist.
- **Friends and enemies never mix:** a friend playing your faction is never recorded or listed as
  an enemy (attacker, killer, helper, victim, sighting, shared hitlist), and an enemy is never on
  the Friends tab. The one exception: a friend playing the *other* faction can fight you, so
  their character can be on the Enemies tab and Hitlist (and stays off the Friends tab).
  "Friend" includes Battle.net friends who don't run the addon, once the addon has seen them
  online on your faction (a friend like that was showing up on the Enemies list).
- **Numbers are just numbers:** no symbol in front of any number anywhere (the "~" that marked
  numbers counted from a friend's alerts could look like a minus sign, "-0"). Zero always shows
  as 0, K/D as 0.00 (the game saves zeros as -0, which used to show up as "-0"). Members of a group who are only invited, or whose numbers haven't reached
  you yet, show empty cells instead of "-" or "?". Their profile still says, in words, when
  numbers were counted from their alerts.

## 0.7.2
Compatible with 0.3.x to 0.7.1.
Fixes from the first live tests, and clearer wording and clicks:
- **Friends tab, Last event:** shows when that event happened, not when you last heard from them
  (it could say "reached level 9 · 17m ago" for a friend now level 16). An older event that
  arrives later through catch-up no longer replaces a newer one.
- **Friends tab, Kills and Deaths:** the same numbers as the Leaderboard and their profile (their
  own report; ~ when counted from their alerts). Before, it could show 0 deaths where the
  Leaderboard showed 2. The column is called Kills now, like everywhere else.
- **Friends tab, Ver:** an older add-on version is flagged too (orange), as on their profile.
- **Group board:** members who are only invited (or whose numbers haven't reached you yet) stay
  at the bottom whatever you sort by; before, an invite could sit above members.
- **Group totals** read "1 member, 1 kill, 6 deaths" (was "1 members, 1 takedowns").
- **Friends' locations were sometimes wrong** ("seen" somewhere they weren't):
  - An event that arrived late (caught up, or passed on by another friend) made them look "seen
    just now"; it now counts at the time it happened.
  - Online: the zone comes from Battle.net (live) first, not from a message that may be behind.
  - Offline profiles show "Last seen" (when you last heard from them) and "Last place" (where,
    with its own time) separately, from the newest of Battle.net, their profile and their own
    PvP alerts. Friends with "Where I am" off: no place is kept.
- **One click opens a profile on every tab**, the Hitlist too (it used to need a double-click).
  A player's note is on their profile; the Hitlist's bottom row is just Share and Clear.
- **The Profile tab shows your own profile** when you open it without choosing anyone.
- **"Alert list"** instead of "picks": "Add to alert list" / "Remove from alert list" on a
  friend's profile, and `/fnf alerts` (`/fnf group` still works).
- **"Kills" everywhere** instead of "takedowns" (weekly summary, help texts).
- Confirmed live: creating a group and inviting work, including reading your BattleTag.

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
