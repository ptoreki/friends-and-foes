local _, ns = ...

-- What the add-on saves, where, and how old saved data is brought up to date.
--
-- FriendsAndFoesDB (account-wide: every character on the account shares it)
--   settings      your options (Core.lua DEFAULTS fills in anything missing)
--   realms        the data: realms.Forever = { players, hitlist, feed } (Data.lua). Forever has
--                 no realms, so there's one store; `sim` is a separate scratch one for /fnf sim
--   profile       your own profile: most wanted, stats time, bounties collected (Profile, Bounty)
--   friendTags    friends' character names -> BattleTag, for picks (never sent anywhere)
--   group         your alert list (picked friends, by BattleTag)
--   groups, relay shared groups and members' relayed cards (Groups.lua); groupStat: your card
--   got, heard    catch-up: events already received / heard, for passing on (Comm.lua)
--   lastOnline    when you were last online (for catch-up)
--   weekly        this week's summary
--   welcomed      the first-run tour was shown
--   caps          what works on this client (shown in Options and the debug report)
--   debugLog, errorLog   logs (capped)
--   dataVersion   which upgrade steps below have run
-- FriendsAndFoesCharDB (per character)
--   equipped, seeded     gear you had on, so only newly equipped gear is announced
--
-- Everything that grows has a limit: feed 500 events, catch-up 24 hours / 300 events, debug
-- log, error log 50, kill lists (KILL_LIST_MAX victims each), enemy records (PLAYERS_MAX, and
-- harmless ones unseen for 90 days are dropped), hitlist ("Forget after" option).
local Saved = {}
ns.Saved = Saved

local KILL_LIST_MAX = 250
local PLAYERS_MAX = 3000

-- Upgrade steps, in order. Each runs once (dataVersion remembers), and each is safe to run on
-- data that never needed it. New steps go on the end with the next number.
local STEPS = {
  -- 1 (0.3.3 and earlier): toast = { kind = bool }. Keep "off" choices, drop the rest.
  function(db)
    local s = db.settings
    if type(s.toast) == "table" then
      for k, v in pairs(s.toast) do
        if v == false and s.show[k] then s.show[k] = "off" end
      end
      s.toast = nil
    end
  end,
  -- 2 (0.5.5 and earlier): one "hold toasts in instances" switch; off meant show everywhere
  function(db)
    local s = db.settings
    if s.dnd.instance ~= nil then
      if s.dnd.instance == false then
        for k in pairs(s.where) do s.where[k] = "show" end
      end
      s.dnd.instance = nil
    end
  end,
  -- 3 (0.6.1 and earlier): one switch for skull + tooltip; the tooltip switch keeps that choice
  function(db)
    local s = db.settings
    if not s.markSplit then
      s.markTooltip = s.mark ~= false
      s.markSplit = true
    end
  end,
  -- 4 (0.5.3 and earlier) defaulted a friend's kill to chat; it's a toast now
  function(db)
    local s = db.settings
    if not s.killToast then
      if s.show.kill == "chat" then s.show.kill = "toast" end
      s.killToast = true
    end
  end,
  -- 5 (0.4.2 and earlier): sound per category (pvp, progress). Keep "off" choices per kind.
  function(db)
    local snd = db.settings.sound
    for old, kinds in pairs({ pvp = { "attacked", "died", "kill" }, progress = { "level", "loot", "gear", "share" } }) do
      if snd[old] == false then for _, k in ipairs(kinds) do snd[k] = false end end
      snd[old] = nil
    end
  end,
  -- 6 (0.9): kill lists and enemy records get their limits right away
  function() Saved.Trim() end,
  -- 7 (1.0): kills whose victim couldn't be named get their own count (kx), for the kill list's
  -- "Name not readable" line; earlier ones are counted from the Feed (it names the killer since 0.7)
  function(db)
    for _, store in pairs(db.realms or {}) do
      for _, e in ipairs(store.feed or {}) do
        local p = e.kind == "kill" and e.who and not (e.foes and e.foes[1]) and store.players and store.players[e.who]
        if p then p.kx = ns.Count(p.kx) + 1 end
      end
    end
  end,
  -- 8 (1.0): the minimap button is on by default; 0.6-0.9 hid it once where the minimap's addon
  -- menu exists, so that automatic hiding is undone (a button you hid yourself before that stays
  -- hidden only if it was never auto-hidden)
  function(db)
    local mm = db.settings and db.settings.minimap
    if mm and mm.compartmentDefaulted then
      mm.hide = false
      mm.compartmentDefaulted = nil
    end
  end,
}
Saved.STEPS = STEPS

-- bring saved data up to date (from ADDON_LOADED, after the defaults are filled in)
function Saved.Upgrade(db)
  local from = tonumber(db.dataVersion) or 0
  for i = from + 1, #STEPS do
    local ok, err = pcall(STEPS[i], db)
    if not ok then ns.Debug("ERR:upgrade", i, err) end
    db.dataVersion = i
  end
  if from < #STEPS then ns.Debug("UPGRADE", from, #STEPS) end
end

---------------------------------------------------------------------------
-- limits
---------------------------------------------------------------------------
-- a kill list over the limit keeps the victims killed most (then most recently)
local function trimKills(list)
  if type(list) ~= "table" then return 0 end
  local all = {}
  for victim, v in pairs(list) do all[#all + 1] = { victim, ns.Count(v.n), v.t or 0 } end
  if #all <= KILL_LIST_MAX then return 0 end
  table.sort(all, function(a, b)
    if a[2] ~= b[2] then return a[2] > b[2] end
    return a[3] > b[3]
  end)
  for i = KILL_LIST_MAX + 1, #all do list[all[i][1]] = nil end
  return #all - KILL_LIST_MAX
end

-- enemy records over the limit: the ones seen longest ago go first, but never anyone on your
-- hitlist, anyone who killed one of you, a friend, or you
local function trimPlayers(r)
  local n, candidates = 0, {}
  for name, p in pairs(r.players) do
    n = n + 1
    if p.enemy and not p.friend and not p.self and ns.Count(p.k) == 0 and not r.hitlist[name] then
      candidates[#candidates + 1] = { name, p.lastSeen or 0 }
    end
  end
  if n <= PLAYERS_MAX then return 0 end
  table.sort(candidates, function(a, b) return a[2] < b[2] end)
  local drop = math.min(n - PLAYERS_MAX, #candidates)
  for i = 1, drop do r.players[candidates[i][1]] = nil end
  return drop
end

function Saved.Trim()
  local db = FriendsAndFoesDB
  local kills, players = 0, 0
  for _, r in pairs(db.realms or {}) do
    for _, p in pairs(r.players or {}) do
      kills = kills + trimKills(p.slain) + trimKills(p.slainRep)
    end
    if r.players then players = players + trimPlayers(r) end
  end
  if kills + players > 0 then ns.Debug("TRIM", "kill-list entries", kills, "enemy records", players) end
  return kills, players
end

Saved.KILL_LIST_MAX, Saved.PLAYERS_MAX = KILL_LIST_MAX, PLAYERS_MAX

-- once per session, a little after login (it's cheap, but there's no hurry)
ns.OnReady(function() C_Timer.After(20, function() ns.Try("trim", Saved.Trim) end) end)
