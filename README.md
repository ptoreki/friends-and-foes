# Friends & Foes

A WoW Forever addon that:
- shows a toast when your Battle.net friends level up, loot an epic BoE, or equip new gear
- warns you when friends are attacked, killed, or get kills in world PvP
- keeps a hitlist and per-player K/D/A

## Install (for friends)
1. Download `FriendsAndFoes-<version>.zip`.
2. Extract it into `World of Warcraft\_forever_\Interface\AddOns\`. You should end up with
   `AddOns\FriendsAndFoes\FriendsAndFoes.toc`.
3. Log in. Type `/fnf` or click the crossed-swords minimap button.

Only Battle.net friends who are **online in WoW Forever** and **also have the addon** can see your events. (Forever has no realms, so the server name the game shows doesn't matter.)

## Beta testing
- `/fnf sim all` shows every toast type, using fake data that never mixes with real records.
  `/fnf sim clear` removes it.
- `/fnf sim all self` also sends the fake events to your friends, to test that sync works.
- The Settings tab shows which features work on your client and what that means.
- To report a bug:
  1. Turn on `/fnf debug` and play until it happens.
  2. `/reload`.
  3. Send `WTF\Account\<ACCOUNT>\SavedVariables\FriendsAndFoes.lua`.

## Commands
`/fnf` · `/fnf settings` · `/fnf unlock` / `lock` · `/fnf test` · `/fnf status` · `/fnf share` ·
`/fnf sim …` · `/fnf debug` · `/fnf debug clear` · `/fnf minimap`

## Development
- `npm install`, then `npm test` to run the syntax check and the logic tests in a mocked WoW API.
- `npm run package` builds the release zip in `dist/`.
- Design and decisions are in [SPEC.md](SPEC.md). Version history is in [CHANGELOG.md](CHANGELOG.md).
