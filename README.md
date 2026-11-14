# Friends & Foes

A WoW Forever addon that:
- pops up a toast when a friend is attacked or killed in world PvP, reaches level 60, loots an
  epic BoE, or gets revenge
- adds a quiet chat line for everything else (level-ups, gear, kills), with clickable items
- keeps a hitlist and marks those players with a skull on their nameplate and a tooltip line
- tracks per-player K/D/A

For each event you choose Toast, Chat or Off, and sound on or off, in Options (the Options button
in the window, or `/fnf options`).

## Install (for friends)
1. Download `FriendsAndFoes-<version>.zip`.
2. Extract it into `World of Warcraft\_forever_\Interface\AddOns\`. You should end up with
   `AddOns\FriendsAndFoes\FriendsAndFoes.toc`.
3. Log in. Type `/fnf`, or open it from the minimap's addon menu.

Only Battle.net friends who are **online in WoW Forever** and **also have the addon** can see your events. (Forever has no realms, so the server name the game shows doesn't matter.)

To get alerts only from certain friends, click them in **Players → Friends** (or `/fnf group <name>`).
Once anyone is picked, you only exchange events with your picks. `/fnf group all` goes back to everyone.

## Beta testing
- `/fnf sim all` shows every toast type, using fake data that never mixes with real records.
  `/fnf sim clear` removes it.
- `/fnf sim all self` also sends the fake events to your friends, to test that sync works.
- With `/fnf debug` on, Options also shows beta tools and which features work on your client.
- To report a bug:
  1. Turn on `/fnf debug` and play until it happens.
  2. `/reload`.
  3. Send `WTF\Account\<ACCOUNT>\SavedVariables\FriendsAndFoes.lua`.

## Commands
`/fnf` · `/fnf options` · `/fnf group [name|all]` · `/fnf chat <tab>` · `/fnf unlock` / `lock` ·
`/fnf test` · `/fnf status` · `/fnf share` · `/fnf sim …` · `/fnf debug` · `/fnf debug clear` · `/fnf minimap`

## Development
- `npm install`, then `npm test` to run the syntax check and the logic tests in a mocked WoW API.
- `npm run package` builds the release zip in `dist/`.
- Design and decisions are in [SPEC.md](SPEC.md). Version history is in [CHANGELOG.md](CHANGELOG.md).
