# Friends & Foes

**Summary (short description field):**
See your Battle.net friends' level-ups, epic loot and world PvP fights, and keep a hitlist of everyone who ganks your group.

**Longer summary (for an intro paragraph, Wago's description, or a forum post):**
Friends & Foes keeps your friend group connected in WoW Forever, even when you're not playing side by side. When a friend levels up, loots an epic or gets new gear, you see a short line in chat. When they're attacked near you, killed, or score a kill in world PvP, you get an alert with who and where. Everyone who kills one of you goes on a shared hitlist. They get a skull on their nameplate, and you're told when you or a friend spots them again. Every alert can be a toast, a chat line or off, and it stays quiet until something worth knowing happens.

---

## Friends & Foes

**Leveling with friends, but not always side by side?** Friends & Foes keeps your group connected. You'll know when a friend dings, loots something great, or gets jumped in world PvP. And nobody who ganks your group gets forgotten.

It stays out of your way until something happens that's worth knowing.

> **Beta:** still being tested with real players. If something looks wrong, see *Something not working?* below.

---

### What you'll see

**Your friends' progress**
- Level-ups, epic loot and new gear, as a short line in chat. Click the item to see it.
- Big moments pop up as a toast: **reaching level 60**, **looting an epic BoE**, **revenge**, and **kill streaks**.

**World PvP**
- **A friend is attacked:** a toast if they're in your zone, so you can go help. Fights elsewhere are a chat line.
- **A friend is killed:** who did it, and where.
- **A friend gets a kill:** including revenge on someone from your hitlist and kills in a row.

**The hitlist**
- Anyone who **kills** you or a friend lands on your hitlist. It shows:
  - their kills and attacks on your group
  - who they killed
  - their guild
  - where they were last seen
  - your own note
- Hitlist players get a **skull next to their nameplate**, and their record shows in their **tooltip**.
- You're told when one of them turns up, whether you see them or a friend does: *"Rogz Fang spotted by Bob · Astranaar"*
- Share your hitlist with your friends in one click.

**Kill and death tracking**
- **Enemies:** how often each one killed one of you, died to you, or helped in a kill.
- **You and your friends:** takedowns and deaths.
- Once a week you get a short summary of your PvP week, including your **nemesis**.

**Messages with a bit of personality**
- *"Rogz Fang killed Bob again (3rd) · Tarren Mill"*
- *"Alice avenged Bob on Rogz Fang · Duskwood"*
- *"Bob killed Kragg Bear · 5 in a row! · Southshore"*
- *"Bob killed by Rogz Fang · ended a 5-kill streak · Southshore"*

Prefer it plain? Switch to **Short** messages and you get just who did what, and where: *"Bob killed by Rogz Fang · Duskwood"*.

---

### Getting started
1. Install it, and have your friends install it too. It only works between people who have the addon.
2. Log in. That's it: anyone on your **Battle.net friends list** who's playing WoW Forever on **your faction** is picked up automatically.
3. Type **/fnf** to open the window, or find it in the **minimap's addon menu**.

You don't need to be in a group, on the same server, or in the same zone.

---

### The window (/fnf)
- **Hitlist:** everyone on your hitlist. Click someone to add a note.
- **Players:** switch between **Enemies** and **Friends**. Friends shows who's online, where they are, and their version of the addon.
- **Feed:** everything that happened recently.

Click any column header to sort, and use the **search box** to find someone quickly. **Right-click** a player to remove them, or use **Clear hitlist** to start over. You'll always be asked to confirm first.

---

### Make it yours
Everything is in **Options → AddOns → Friends & Foes**. Hover any option for an explanation.

**Alerts:** for each kind of event, choose:
- *Toast + sound*
- *Toast*
- *Chat line + sound*
- *Chat line*
- *Off*

**Where it works:**
- For **dungeons**, **raids** and **battlegrounds** separately, choose whether alerts show, wait until you're out, become chat lines, or stay off.
- Choose whether your own fights count in battlegrounds too.

**Appearance:**
- Pick a toast style: **Modern** (a slim strip) or **Classic** (like WoW's achievement pop-up).
- Adjust the toast **size** and how **long** toasts stay.
- Move toasts anywhere on screen.
- Choose **flavor** or **short** messages, and which chat tab gets the lines.

**Friends & sharing:**
- Choose what you share about yourself.
- Pick **specific friends** to exchange alerts with, instead of everyone.
- Turn the nameplate skulls on or off.

The defaults are quiet. Toasts come only for your friends' fights and for big moments; everything else is a chat line.

---

### Good to know
- **It's safe and simple.** Everything happens inside the game. There are no websites, accounts or outside programs, and it doesn't play for you.
- **Friends only see what you choose to share.** If you've picked specific friends, only they get your updates.
- **Kills count as "takedowns".** The game doesn't tell addons who landed the killing blow, so any honorable kill you took part in counts.
- **Alerts are live.** Things that happened while you were offline aren't shown afterwards.
- **Options can't be opened during combat.** That's a game rule, so wait until the fight is over.
- **English only**, for now.

---

### Something not working?
1. Open **Options → AddOns → Friends & Foes → Advanced** and turn on **Debug logging**.
2. Play until the problem happens, then type **/reload**.
3. Send the file `World of Warcraft\_forever_\WTF\Account\<your account>\SavedVariables\FriendsAndFoes.lua` along with a short description.

Debug logging turns itself off after a week, so you won't forget it.

---

### Commands
| Command | What it does |
|---|---|
| `/fnf` | Open or close the window |
| `/fnf options` | Open the options |
| `/fnf group` | See your friends and choose who you exchange alerts with |
| `/fnf unlock` / `/fnf lock` | Move the toasts |
| `/fnf status` | Check which friends were found |
