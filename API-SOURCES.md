# Add-on API sources (WoW Forever)

Where to look up what the add-on API can do, newest and most reliable first. Collected
2026-11-19; check the dates, because Forever's API follows retail's and keeps changing.

## What WoW Forever runs

- Forever runs the **modern client and its add-on API**, matching retail one for one, with the
  Midnight (12.x) restrictions: secret values, a restricted combat log, protected combat data.
  Restriction changes on retail reach Forever about a patch later.
  ([Kami-Labs, 2026-09-16](https://kami-labs.fr/en/wow-classic/wow-forever-addons-restreints-comme-sur-midnight/),
  based on a [Warcraft Tavern interview with Ion Hazzikostas and Holly Longdale, 2026-09-14](https://www.warcrafttavern.com/forever/news/ion-holly-interview-blizzcon-2026/))
- `## Interface: 16001`; the client reports `WOW_PROJECT_MAINLINE` (the retail codebase), but
  most Classic globals are missing. A retail version check like `>= 100000` gets it wrong.
  ([forever-addon-kit](https://github.com/Thunderz96/forever-addon-kit))
- Blizzard's own explanation of the restrictions:
  [Combat Philosophy and Addon Disarmament in Midnight (2025-11-13)](https://news.blizzard.com/en-us/article/24246290/combat-philosophy-and-addon-disarmament-in-midnight),
  and the later loosening ([Icy Veins, 2025-12](https://www.icy-veins.com/wow/news/blizzard-relaxing-more-addon-limitations-in-midnight/)).

## Sources

1. **In the game: `/api`** (Blizzard's built-in documentation, the only official reference).
   Search it in chat: `/api search PARTY_KILL`, `/api system C_BattleNet`. Since 12.0.5 it has a
   **Predicates** table saying when each function's or event's values are secret or blocked.
   Note: the 12.0.7 notes say some secret-value fields are left out of the *Classic* API docs,
   so check what Forever's own `/api` shows.
2. **[Warcraft Wiki: World of Warcraft API](https://warcraft.wiki.gg/wiki/World_of_Warcraft_API)**
   and [Events](https://warcraft.wiki.gg/wiki/Events): the community reference. Each patch has an
   API changes page:
   - [12.0.0](https://warcraft.wiki.gg/wiki/Patch_12.0.0/API_changes) (Midnight: the restrictions start)
   - [12.0.5](https://warcraft.wiki.gg/wiki/Patch_12.0.5/API_changes) ([notes](https://warcraft.wiki.gg/wiki/Patch_12.0.5/API_changes/notes): the Predicates table)
   - [12.0.7](https://warcraft.wiki.gg/wiki/Patch_12.0.7/API_changes) ([notes](https://warcraft.wiki.gg/wiki/Patch_12.0.7/API_changes/notes))
   - [12.1.0](https://warcraft.wiki.gg/wiki/Patch_12.1.0/API_changes)
   - [12.1.5](https://warcraft.wiki.gg/wiki/Patch_12.1.5/API_changes) (test realm, 2026-08)
3. **[Blizzard's UI source (Gethe/wow-ui-source)](https://github.com/Gethe/wow-ui-source)**: a
   mirror of Blizzard's own interface code, to see how something really works (for example the
   Settings panel the Options are built with).
4. **Forever-specific community work** (measured on the Forever client, not official):
   - [Thunderz96/forever-addon-kit](https://github.com/Thunderz96/forever-addon-kit) (MIT):
     findings from the Forever beta (build 1.60.1.69893, later rechecked in part), a captured API
     list (`data/forever_api.json`: about 6,000 global functions, 269 namespaces), porting
     tools and a few small add-ons.
   - [Atraeau/WoW-Addons](https://github.com/Atraeau/WoW-Addons): an add-on workspace with a
     generated API reference for the modern (12.0) client.
5. **[wow-api-lib](https://www.curseforge.com/wow/addons/wow-api-lib)** (CurseForge): an in-game
   add-on to browse and export the `/api` docs, restriction flags included.
6. **Blizzard forum posts** on the Forever beta:
   [development notes (2026-09-24)](https://us.forums.blizzard.com/en/wow/t/wow-forever-beta-development-notes-%E2%80%93-updated-september-24/2360696),
   [known issues (2026-09-17)](https://us.forums.blizzard.com/en/wow/t/wow-forever-beta-known-issues-september-17/2352687),
   and the community bug tracker [ClassicWoWCommunity/forever-bugs](https://github.com/ClassicWoWCommunity/forever-bugs).

Not usable from an add-on: the Battle.net **web** APIs (Profile, Game Data). They're for websites,
need OAuth and the internet, and add-ons have no network access.

## What matters for Friends & Foes

From the sources above (beta-era findings; recheck on the live client):

- **Registering an event the client doesn't know raises an error.** `ns.On` / `ns.OnUnit`
  register inside `pcall` and log `REG-FAIL`, so an event that's missing (for example
  `PARTY_KILL`, if Forever drops it) can't break loading.
- **The combat log is restricted and creature health is secret in combat.** We never use the
  combat log; `UNIT_HEALTH` is only used as a "they're still alive" signal, and the health value
  is never read.
- **Range checks on hostile targets give plain values in open-world combat**, but melee range
  isn't reliable. We don't use range.
- **Rulesets:** `C_GameRules.IsGameRuleActive` is in forever-addon-kit's captured API list. The names
  of the `Enum.GameRule` fields (`HardcoreRuleset`, `RPRuleset`, `PvPRuleset`) are unverified, so
  `ns.Ruleset()` returns nil if any is missing and the add-on falls back to one store.
- **After 100 Lua errors the client stops reporting them.** Every handler runs through `ns.Try`,
  which keeps its own error log (`/fnf report`).
- **Beta bug: saved variables were written but not loaded back.** Our live saved data loads
  fine, so it was fixed or didn't affect live.
- **Risk to watch:** spell-cast events are predicted to move into a protected nameplate
  container in a later patch (Kami-Labs). We only use your own casts (`UNIT_SPELLCAST_SENT` and `_SUCCEEDED`: who you last attacked or healed, and your first strike), but we do read enemy
  **nameplates** (enemy detection, kill naming; their GUIDs name a killing blow from `PARTY_KILL`). If nameplates get locked down, those are what
  break first.
- **From [DoesItDie](https://github.com/swirllyman/DoesItDie)** (a Forever add-on that reads your
  DoT damage on hostile targets): **never register `COMBAT_LOG_EVENT_UNFILTERED`** - Forever
  forbids it and shows a "blocked" popup. What stays readable: your own casts
  (`UNIT_SPELLCAST_SENT` gives the target's name and a cast ID, `UNIT_SPELLCAST_SUCCEEDED`),
  damage taken by a unit you can see (`UNIT_COMBAT` on target / nameplates, with the amount), unit
  GUIDs in the open world (secret in instances, where a nameplate token can stand in), and after
  combat the built-in damage meter's per-spell totals (`C_DamageMeter`). Health is secret in
  combat; it compares health against damage with a status bar, which accepts secret values.
- **To check in the Forever client** before relying on them: `/api search PARTY_KILL`,
  `/api search GetPlayerInfoByGUID`, `/api search CHAT_MSG_COMBAT_HONOR_GAIN`,
  `/api search UnitGUID`, `/api system C_BattleNet`.
