# Friends & Foes

**Summary (short description field):**
See your Battle.net friends' level-ups, epic loot and world PvP fights, and keep a hitlist of everyone who ganks your group.

**Longer summary (for an intro paragraph, Wago's description, or a forum post):**
Friends & Foes keeps your friend group connected in WoW Forever, even when you're not playing side by side. When a Battle.net friend with the addon levels up, loots an epic BoE or gears up, you see it as a short chat line. When they're attacked in your zone, killed, or score a kill in world PvP, you get an alert telling you who and where. Everyone who kills one of you goes on a shared hitlist, with a skull on their nameplate and their record in the tooltip, so you'll recognize them next time. Every alert can be set to a toast, a chat line or off, with sound on or off, and it stays quiet until something worth knowing happens.

---

## Friends & Foes

Leveling with friends in WoW Forever, but not always in the same group? Friends & Foes keeps your circle connected. You see your friends' big moments, you know when they're in a fight nearby, and you keep a shared grudge list of everyone who's ganked any of you.

It stays out of your way until something worth knowing happens.

> **Beta:** the addon is in active testing. Please report anything odd (see *Reporting bugs* below).

### What it does

**Friends' progress**
- Level-ups, epic BoE loot and new gear, shown as a short line in chat with clickable items.
- Milestones pop up as a small toast: reaching **level 60**, **looting an epic BoE**, **revenge kills**, and **kill streaks** (5 and 10 in a row).

**World PvP alerts**
- **Friend attacked:** a toast when a friend is attacked in **your zone**, so you can go help. Fights elsewhere get a chat line instead.
- **Friend killed:** shows who did it and where.
- **Friend got a kill:** with revenge called out when the victim was on your hitlist.

**The hitlist**
- Anyone who **kills** you or a friend goes on a shared list. It records their kills and attacks on your group, who they killed, their guild, where they were last seen, and your own notes. An attack alone only triggers an alert.
- Hitlist players get a **skull next to their nameplate** and a line in their **tooltip**, e.g. *"Hitlist: 3 kills, 5 attacks on us"*.
- You get a quiet alert when one of them shows up near you, or near a friend: *"Rogz Fang spotted by Bob · Astranaar"*.
- You can share your hitlist with friends in one click.

**K/D/A tracking**
- Kills, deaths and assists for every enemy player you meet, and takedowns and deaths for you and your friends.

**Messages with some personality**, or short and plain if you prefer:
- *"Rogz Fang killed Bob again (3rd) · 5th today · Tarren Mill"*
- *"Alice avenged Bob on Rogz Fang · Duskwood"*
- *"Bob owns Rogz Fang (3rd) · Duskwood"*
- *"Bob killed Kragg Bear · 5 in a row! · Southshore"*, and when it ends: *"Bob killed by Rogz Fang · ended a 5-kill streak · Southshore"*
- With flavor text off: *"Bob killed by Rogz Fang · Duskwood"*

### Your choice, per event
In **Options → AddOns → Friends & Foes**, every event gets its own choice:
- **Show:** Toast, Chat or Off
- **Sound:** on or off

Toasts come in two styles, and their size and duration can be adjusted: **Modern**, a slim one-line strip, or **Classic**, styled like WoW's own achievement pop-up. Use **Preview** to compare.

The defaults are quiet: toasts for your friends' fights (attacked nearby, killed, or scoring a kill) and for milestones, a chat line for everything else, and soft built-in game sounds.

You can also choose:
- **Which friends** you exchange alerts with: everyone, or only the friends you pick.
- **What you share:** levels, loot, gear and PvP, each separately.
- **Do not disturb:** hold progress toasts in combat.
- **Where it works:** for dungeons, raids and battlegrounds separately, choose whether alerts show, wait until you're out, become chat lines, or stay off. You also choose whether your own PvP is tracked in the open world and in battlegrounds.

### How it works
- Your friends need the addon too. Each player's addon reports only **their own** events (their level-ups, loot, and the fights they're in) and sends them to friends who have it.
- It works with your **Battle.net friends** who are online in WoW Forever **on your faction**. You don't need to be grouped, on the same server, or in the same zone.
- No external servers, websites or accounts are involved. Everything goes through the game's own addon messaging, and your data stays in your own SavedVariables.
- It uses only the standard addon API: no automation, no combat log, nothing outside the game.

### Commands
| Command | What it does |
|---|---|
| `/fnf` | Open the window (Hitlist, Players, Feed) |
| `/fnf options` | Open the options |
| `/fnf group` | List friends and pick who you exchange alerts with |
| `/fnf unlock` / `/fnf lock` | Move the toasts |
| `/fnf chat <tab>` | Choose the chat tab for alert lines |
| `/fnf status` | Show which friends were found and what works on your client |

The addon is also in the minimap's addon menu.

### Reporting bugs
1. Type `/fnf debug`, then play until the problem happens.
2. Type `/reload`.
3. Attach `WTF\Account\<YOUR ACCOUNT>\SavedVariables\FriendsAndFoes.lua` to a comment or issue.

Debug logging switches itself off after 7 days.

### Known limitations
- WoW Forever restricts some combat information for addons, so **killing blows can't be detected**. Friends' honorable kills count as *takedowns*.
- Alerts are live only. Events that happened while you were offline aren't replayed.
- English only for now.
