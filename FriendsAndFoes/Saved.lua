local _, ns = ...

-- What the add-on saves, where, and how old saved data is brought up to date.
--
-- FriendsAndFoesDB (account-wide: every character on the account shares it)
--   settings      your options (Core.lua DEFAULTS fills in anything missing)
--   realms        the data: realms.Forever = { players, hitlist, feed } (Data.lua). Forever has
--                 no realms, so there is one store (an old `sim` store from before 0.9.4 is removed)
--   profile       your own profile: stats time, notoriety claimed (Profile, Bounty)
--   friendTags    friends' character names -> BattleTag, for picks (never sent anywhere)
--   group         your alert list (picked friends, by BattleTag)
--   groups, relay shared groups and members' relayed cards (Groups.lua); groupStat: your card
--   got, heard    catch-up: events already received / heard, for passing on (Comm.lua)
--   outbox        your recent events, all your characters (catch-up; each says which character)
--   digestAt      when each friend last got your hitlist digest (by BattleTag)
--   lastOnline    when you were last online (for catch-up)
--   weekly        this week's summary
--   repeats       enemy name -> recent claim times (last few, pruned after 30 min; Bounty.lua)
--   welcomed      the first-run tour was shown
--   caps          what works on this client (shown in Options and the debug report)
--   debugLog, errorLog   logs (capped)
--   dataVersion   which upgrade steps below have run
-- FriendsAndFoesCharDB (per character)
--   equipped, seeded     gear you had on, so only newly equipped gear is announced
--   outboxMoved          this character's old catch-up list was merged into the account one
--
-- Everything that grows has a limit: feed 500 events, catch-up a week / 250 events, debug
-- log, error log 50, kill lists (KILL_LIST_MAX victims each), enemy records (PLAYERS_MAX, and
-- harmless ones unseen for 90 days are dropped), hitlist (the "Forget ... after" options).
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
        if type(s.where) == "table" then
          for k in pairs(s.where) do s.where[k] = "show" end -- (step 10 turns these into one setting)
        else
          s.instances = "show"
        end
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
  -- 9 (0.9.4): most wanted and hitlist notes are gone (the Bounty board does that job now):
  -- their saved values are cleared
  function(db)
    if db.profile then db.profile.wanted = nil end
    for _, store in pairs(db.realms or {}) do
      for _, p in pairs(store.players or {}) do p.wanted, p.bwPaid = nil, nil end
      for _, h in pairs(store.hitlist or {}) do h.note = nil end
    end
  end,
  -- 10 (0.9.4): "Where it works" is one setting for dungeons, raids and battlegrounds (was one
  -- each, with a "chat line only" choice): the dungeon choice is kept ("chat line only" becomes
  -- "wait until I'm out"); the simulation and its separate store are gone
  function(db)
    local s = db.settings
    if type(s.where) == "table" then
      local v = s.where.party
      if v == "chat" then v = "hold" end
      if v == "show" or v == "hold" or v == "off" then s.instances = v end
      s.where = nil
    end
    db.sim = nil
  end,
  -- 11 (0.9.4): one sound per kind of alert (was one per alert): the old pick of the alert that
  -- stands for each kind is kept; "milestones always pop up" and the gear quality are fixed now
  function(db)
    local s = db.settings
    local old = type(s.soundPick) == "table" and s.soundPick or {}
    -- (a pick that was just the old default for that alert isn't a choice: it isn't carried over)
    local OLD_DEFAULT = { attacked = "alarm", died = "raidwarning", kill = "levelup", sighting = "mapping" }
    local function pick(k)
      local v = old[k]
      return (type(v) == "string" and v ~= "default" and v ~= OLD_DEFAULT[k]) and v or nil
    end
    s.soundPick = {
      trouble = pick("attacked") or pick("died") or "default",
      victory = pick("kill") or "default",
      sighting = old.sighting or "mapping",
      progress = old.progress or pick("loot") or pick("level") or "default",
      bounty = old.bounty or pick("contract") or "default",
    }
    s.milestones, s.gearMin = nil, nil
  end,
  -- 12 (0.9.4): alerts are set in four groups; each group takes its lead alert's setting (a
  -- friend attacked; epic loot) - except that attacking someone and plain level-ups stay quiet
  function(db)
    local s = db.settings
    if type(s.show) ~= "table" or type(s.sound) ~= "table" then return end
    local groups = { { "attacked", "engage", "died", "kill" }, { "loot", "gear", "level" } }
    local quiet = { engage = true, level = true }
    for _, g in ipairs(groups) do
      local show, sound = s.show[g[1]], s.sound[g[1]]
      for _, kind in ipairs(g) do
        s.show[kind] = show
        if not quiet[kind] then s.sound[kind] = sound end
      end
      s.sound.engage, s.sound.level = false, false
    end
  end,
  -- 13: "Forget hitlist players" is now normal / double / never (the time depends on what the
  -- player did). The old "never" (forgetAfter 0) was the default, so it can't be told apart from
  -- a choice: it becomes the new default, "normal", like 90/180/365 days do.
  function(db)
    local s = db.settings
    if s.forgetAfter ~= nil then
      s.forget = "normal"
      s.forgetAfter = nil
    end
  end,
  -- 14: the forget mode became three settings (days, 0 = forever): attackers / killed once / killed more
  function(db)
    local s = db.settings
    if s.forget == nil then return end
    if s.forget == "never" then
      s.forgetAttackers, s.forgetKilledOnce, s.forgetKilledMore = 0, 0, 0
    elseif s.forget == "double" then
      s.forgetAttackers, s.forgetKilledOnce, s.forgetKilledMore = 28, 0, 0
    else
      s.forgetAttackers = ns.DEFAULT_FORGET_ATTACKERS
      s.forgetKilledOnce = ns.DEFAULT_FORGET_KILLED_ONCE
      s.forgetKilledMore = ns.DEFAULT_FORGET_KILLED_MORE
    end
    s.forget = nil
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
