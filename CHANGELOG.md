# Changelog

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
