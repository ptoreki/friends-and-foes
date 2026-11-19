local _, ns = ...

local Data = {}
ns.Data = Data

local FEED_MAX = 500
local PRUNE_AFTER = 90 * 86400

local function ensure(r)
  r.players = r.players or {}
  r.hitlist = r.hitlist or {}
  r.feed = r.feed or {}
  return r
end

-- Storage key. Forever has no realms (GetRealmName is an internal server name that can differ
-- between friends and logins) and names are unique region-wide, so everything shares one store.
function Data.StoreKey()
  if ns.ForeverNames() then return "Forever" end
  return ns.realm or GetRealmName()
end

function Data.RealRealm()
  local realms = FriendsAndFoesDB.realms
  local key = Data.StoreKey()
  realms[key] = realms[key] or {}
  return ensure(realms[key])
end

-- (one store: what's written is what the window shows)
Data.Realm = Data.RealRealm
Data.ViewRealm = Data.RealRealm

---------------------------------------------------------------------------
-- name resolution (WoW Forever: "First Last" is the identity, first names are shared)
---------------------------------------------------------------------------
local COUNTERS = { k = true, d = true, a = true, attacks = true, kills = true, suspect = true, revenge = true }

-- counters add up, sets merge, newest timestamps win
local function mergeInto(dst, src)
  for k, v in pairs(src) do
    local cur = dst[k]
    if k == "name" then
      -- keep the key
    elseif COUNTERS[k] then
      dst[k] = ns.Count(cur) + ns.Count(v) -- never negative
    elseif k == "level" then
      dst[k] = math.max(tonumber(cur) or 0, tonumber(v) or 0)
    elseif k == "firstSeen" then
      dst[k] = cur and math.min(cur, v) or v
    elseif k == "lastSeen" or k == "lastRevenge" then
      if not cur or v > cur then
        dst[k] = v
        if k == "lastSeen" and src.lastZone then dst.lastZone = src.lastZone end
      end
    elseif k == "lastZone" then
      dst[k] = cur or v
    elseif type(v) == "boolean" then
      dst[k] = cur or v
    elseif k == "kv" and type(v) == "table" and type(cur) == "table" then
      for kk, vv in pairs(v) do cur[kk] = ns.Count(cur[kk]) + ns.Count(vv) end -- per-friend kills add up
    elseif (k == "slain" or k == "slainRep") and type(v) == "table" and type(cur) == "table" then
      -- kill lists: counts add up (their own report: the higher one), the later time wins
      for kk, vv in pairs(v) do
        local c = cur[kk]
        if type(c) ~= "table" then
          cur[kk] = vv
        elseif type(vv) == "table" then
          c.n = (k == "slain") and (ns.Count(c.n) + ns.Count(vv.n)) or math.max(ns.Count(c.n), ns.Count(vv.n))
          if vv.t and (not c.t or vv.t > c.t) then
            c.t = vv.t
            c.zone = vv.zone or c.zone
          end
        end
      end
    elseif type(v) == "table" and type(cur) == "table" then
      for kk, vv in pairs(v) do cur[kk] = cur[kk] or vv end
    elseif cur == nil then
      dst[k] = v
    end
  end
end
Data.MergeInto = mergeInto

-- full-name keys in `map` whose first name is `first`
local function fullKeysFor(map, first)
  local out = {}
  for k in pairs(map) do
    if type(k) == "string" and k:find(" ", 1, true) and ns.FirstName(k) == first then out[#out + 1] = k end
  end
  return out
end

-- A bare first name resolves to a full-name record only when exactly one exists.
-- Never guess between two characters sharing a first name.
local function resolve(map, name)
  if not name or map[name] then return name end
  if not name:find(" ", 1, true) then
    local keys = fullKeysFor(map, name)
    if #keys == 1 then return keys[1] end
  end
  return name
end
Data.Resolve = resolve

local function getOrCreate(map, name, new)
  local key = resolve(map, name)
  local rec = map[key]
  if rec then return rec end
  rec = new(key)
  map[key] = rec
  -- a bare-first-name record made earlier now has its full name: fold it in, if unambiguous
  local first = ns.FirstName(key)
  if key ~= first and map[first] and #fullKeysFor(map, first) == 1 then
    mergeInto(rec, map[first])
    map[first] = nil
  end
  return rec
end

-- K/D/A record for any player (friend, self or enemy)
function Data.Player(name)
  return getOrCreate(Data.Realm().players, name, function(key)
    return { name = key, k = 0, d = 0, a = 0 }
  end)
end

-- On your side: you, or a friend playing your faction. Such a player is never recorded or shown
-- as an enemy. A friend playing the OTHER faction can fight you, so they count as an enemy there
-- (and aren't listed with your friends). Unknown faction = your faction.
function Data.OnOurSide(p)
  if not p then return false end
  if p.self or p.name == ns.me then return true end
  if not p.friend then return false end
  local other = p.faction and ns.myFaction and p.faction ~= "Neutral" and p.faction ~= ns.myFaction
  return not other
end

-- Is this name on your side? A record that says so (above), or a Battle.net friend's character
-- the addon has seen online on your faction - even if they don't run the addon (their BattleTag
-- is remembered then, see Comm). Exact names only.
function Data.OnOurSideName(name)
  if not name then return false end
  if name == ns.me then return true end
  local p = Data.Realm().players[name]
  if p and Data.OnOurSide(p) then return true end
  local tags = FriendsAndFoesDB and FriendsAndFoesDB.friendTags
  if tags and tags[name] then
    -- unless we've since seen that character playing the other faction
    local other = p and p.faction and ns.myFaction and p.faction ~= "Neutral" and p.faction ~= ns.myFaction
    return not other
  end
  return false
end

function Data.FindPlayer(name)
  local map = Data.Realm().players
  return map[resolve(map, name)]
end

function Data.FindHit(name)
  local map = Data.Realm().hitlist
  return map[resolve(map, name)]
end

function Data.Touch(rec, u)
  if not u then return end
  local t = ns.Now()
  -- an event from while you were offline doesn't overwrite fresher info
  local newer = not rec.lastSeen or t >= rec.lastSeen
  if u.class and u.class ~= "" then rec.class = u.class end
  local lvl = tonumber(u.level)
  if lvl and lvl > 0 and (newer or lvl > (tonumber(rec.level) or 0)) then rec.level = lvl end
  if newer and u.guild and u.guild ~= "" then rec.guild = u.guild end
  if newer and u.zone and u.zone ~= "" then rec.lastZone = u.zone end
  if newer then rec.lastSeen = t end
end

function Data.Hit(name)
  return getOrCreate(Data.Realm().hitlist, name, function(key)
    return { name = key, attacks = 0, kills = 0, suspect = 0, revenge = 0, victims = {}, firstSeen = ns.Now() }
  end)
end

-- Who a hitlist player has killed, and how often: { { name, count }, ... }, most kills first.
-- count is nil for victims from before per-friend counting (0.5.1).
function Data.KillsOn(h)
  local out, seen = {}, {}
  for name, n in pairs(h and h.kv or {}) do
    out[#out + 1] = { name, ns.Count(n) }
    seen[name] = true
  end
  for name in pairs(h and h.victims or {}) do
    if not seen[name] then out[#out + 1] = { name, nil } end
  end
  table.sort(out, function(a, b)
    local ca, cb = a[2] or 0, b[2] or 0
    if ca ~= cb then return ca > cb end
    return a[1] < b[1]
  end)
  return out
end

-- who: the friend it's about; foes: enemy names in it (both optional, used by profiles)
function Data.Feed(kind, text, who, foes)
  local feed = Data.Realm().feed
  local entry = { t = ns.Now(), kind = kind, text = text, who = who }
  if foes and #foes > 0 then entry.foes = foes end
  -- kept in time order: something from while you were offline goes in at the time it happened
  local i = #feed + 1
  while i > 1 and (feed[i - 1].t or 0) > entry.t do i = i - 1 end
  table.insert(feed, i, entry)
  while #feed > FEED_MAX do table.remove(feed, 1) end
  return entry
end

-- several friends can get honor for the same death; count it once
local recentDeaths = {}
function Data.EnemyDied(name)
  local e = Data.Player(name)
  local now = GetTime()
  local key = e.name
  if recentDeaths[key] and now - recentDeaths[key] < 15 then return false end
  recentDeaths[key] = now
  e.d = e.d + 1
  return true
end

-- 0.2.0 stored attackers by bare first name ("Kragg", from UnitName) and recap killers by
-- full name ("Kragg Bear"). Fold each bare-first-name record into the one full-name record
-- with that first name. Ambiguous ones (two "Kragg X") are left alone and logged.
local function foldFirstNames(map)
  local moved, todo = 0, {}
  for name in pairs(map) do
    if type(name) == "string" and not name:find(" ", 1, true) then todo[#todo + 1] = name end
  end
  for _, first in ipairs(todo) do
    local keys = fullKeysFor(map, first)
    if #keys == 1 then
      mergeInto(map[keys[1]], map[first])
      map[first] = nil
      moved = moved + 1
    elseif #keys > 1 then
      ns.Debug("FOLD-AMBIGUOUS", first, #keys)
    end
  end
  return moved
end

function Data.FoldFirstNames(db)
  local moved = 0
  local function realm(r)
    ensure(r)
    moved = moved + foldFirstNames(r.players) + foldFirstNames(r.hitlist)
  end
  for _, r in pairs(db.realms or {}) do realm(r) end
  return moved
end

-- 0.2-0.3.1 stored data per "realm", which on Forever is an internal server name
-- ("CAMWOW EU4 Realm 8 PvP"). Fold every such store into the single "Forever" store.
function Data.MergeServerStores(db)
  if not ns.ForeverNames() then return 0 end
  db.realms = db.realms or {}
  local dst = db.realms.Forever or {}
  db.realms.Forever = ensure(dst)
  local merged, keys = 0, {}
  for key in pairs(db.realms) do
    if key ~= "Forever" then keys[#keys + 1] = key end
  end
  for _, key in ipairs(keys) do
    local src = ensure(db.realms[key])
    for _, field in ipairs({ "players", "hitlist" }) do
      for name, rec in pairs(src[field]) do
        if dst[field][name] then mergeInto(dst[field][name], rec) else dst[field][name] = rec end
      end
    end
    for _, e in ipairs(src.feed) do dst.feed[#dst.feed + 1] = e end
    db.realms[key] = nil
    merged = merged + 1
  end
  if merged > 0 then
    table.sort(dst.feed, function(a, b) return (a.t or 0) < (b.t or 0) end)
    while #dst.feed > FEED_MAX do table.remove(dst.feed, 1) end
  end
  return merged
end

-- 0.5.3 and earlier put anyone who attacked on the hitlist. Now only kills do: once, drop
-- entries with no kills (kept: anything with a note you wrote).
function Data.DropAttackOnly(db)
  if db.hitlistKillsOnly then return 0 end
  local dropped = 0
  local function store(r)
    ensure(r)
    local drop = {}
    for name, h in pairs(r.hitlist) do
      if (tonumber(h.kills) or 0) == 0 and not h.note then drop[#drop + 1] = name end
    end
    for _, name in ipairs(drop) do r.hitlist[name] = nil end
    dropped = dropped + #drop
  end
  for _, r in pairs(db.realms or {}) do store(r) end
  db.hitlistKillsOnly = true
  return dropped
end

ns.OnReady(function()
  ns.Try("servers", function() ns.Debug("MERGE-SERVERS", Data.MergeServerStores(FriendsAndFoesDB)) end)
  ns.Try("kills-only", function() ns.Debug("HITLIST-KILLS-ONLY", Data.DropAttackOnly(FriendsAndFoesDB)) end)
  ns.Try("fold", function() ns.Debug("FOLD", Data.FoldFirstNames(FriendsAndFoesDB)) end)
end)

---------------------------------------------------------------------------
-- old data
---------------------------------------------------------------------------
Data.STALE_DAYS = 30        -- hitlist entries fade (grey, listed last) after this long unseen
Data.OLD_LEVEL_DAYS = 30    -- a level seen longer ago than this is shown as "24+"
Data.FRIEND_HIDE_DAYS = 180 -- offline friends not heard from this long leave the Friends list
-- how long a hitlist entry stays without anybody seeing it: three options (days, 0 = forever),
-- one per kind of player; the defaults are set in Core.lua (they fill DEFAULTS)
Data.DEFAULT_FORGET_ATTACKERS = ns.DEFAULT_FORGET_ATTACKERS
Data.DEFAULT_FORGET_KILLED_ONCE = ns.DEFAULT_FORGET_KILLED_ONCE
Data.DEFAULT_FORGET_KILLED_MORE = ns.DEFAULT_FORGET_KILLED_MORE

local function daysSince(t) return t and (time() - t) / 86400 or math.huge end

-- which setting rules an entry (or { kills =, attacks = })
function Data.ForgetKey(rec)
  local kills = tonumber(rec and rec.kills) or 0
  return kills >= 2 and "forgetKilledMore" or kills == 1 and "forgetKilledOnce" or "forgetAttackers"
end

local FORGET_DEFAULT = {
  forgetAttackers = Data.DEFAULT_FORGET_ATTACKERS,
  forgetKilledOnce = Data.DEFAULT_FORGET_KILLED_ONCE,
  forgetKilledMore = Data.DEFAULT_FORGET_KILLED_MORE,
}

-- days an entry stays unseen before it is forgotten; nil = never. `pending` ({ key, days }) tries
-- another value for one setting (the Options confirmation counts with it).
function Data.ForgetDays(rec, pending)
  local key = Data.ForgetKey(rec)
  local days
  if pending and pending[1] == key then
    days = tonumber(pending[2])
  else
    local s = FriendsAndFoesDB and FriendsAndFoesDB.settings
    days = tonumber(s and s[key])
    if days == nil then days = FORGET_DEFAULT[key] end
  end
  if not days or days <= 0 then return nil end
  return days
end

local function shouldForget(name, h, pending)
  local days = Data.ForgetDays(h, pending)
  if not days or daysSince(h.lastSeen or h.firstSeen) <= days then return false end
  -- an open Bounty board contract keeps an enemy (checked last: only for entries already past due)
  local open = ns.Contracts and ns.Contracts.On and ns.Contracts.On(name)
  return not (open and #open > 0)
end

function Data.IsStale(rec)
  return rec ~= nil and daysSince(rec.lastSeen or rec.firstSeen) > Data.STALE_DAYS
end

function Data.LevelIsOld(rec)
  return rec ~= nil and daysSince(rec.lastSeen or rec.firstSeen) > Data.OLD_LEVEL_DAYS
end

function Data.FriendIsGone(rec)
  return rec ~= nil and daysSince(rec.lastSeen) > Data.FRIEND_HIDE_DAYS
end

-- how many entries ForgetOld would remove if setting `key` were `days` (for the confirmation)
function Data.CountForget(db, key, days)
  local n = 0
  local pending = key and { key, days } or nil
  for _, r in pairs(db.realms or {}) do
    for name, h in pairs(r.hitlist or {}) do
      if shouldForget(name, h, pending) then n = n + 1 end
    end
  end
  return n
end

function Data.ForgetOld(db)
  local removed, byKind = 0, {}
  for _, r in pairs(db.realms or {}) do
    ensure(r)
    local drop = {}
    for name, h in pairs(r.hitlist) do
      if shouldForget(name, h) then drop[#drop + 1] = name end
    end
    for _, name in ipairs(drop) do
      local key = Data.ForgetKey(r.hitlist[name])
      byKind[key] = (byKind[key] or 0) + 1
      r.hitlist[name] = nil
    end
    removed = removed + #drop
  end
  local parts = {}
  for key, n in pairs(byKind) do parts[#parts + 1] = key .. "=" .. n end
  table.sort(parts)
  ns.Debug("FORGET-OLD", removed, #parts > 0 and table.concat(parts, ", ") or "none")
  return removed
end

-- the login run: say so once if it removed anyone (the Options path asks first instead)
function Data.ForgetAtLogin()
  local n = Data.ForgetOld(FriendsAndFoesDB)
  if n > 0 and ns.Toast and ns.Toast.Chat then ns.Toast.Chat(ns.L.FORGOT_LINE:format(n)) end
  return n
end

ns.OnReady(function() ns.Try("forget-old", Data.ForgetAtLogin) end)

-- Drop enemies not seen for 90 days who never hurt us and aren't on the hitlist.
function Data.Prune()
  local cutoff = time() - PRUNE_AFTER
  local removed = 0
  for _, r in pairs(FriendsAndFoesDB.realms) do
    ensure(r)
    for name, p in pairs(r.players) do
      if p.enemy and not p.friend and (p.k or 0) == 0 and (p.a or 0) == 0
        and not r.hitlist[name] and (p.lastSeen or 0) < cutoff then
        r.players[name] = nil
        removed = removed + 1
      end
    end
  end
  ns.Debug("PRUNE", removed)
end

ns.OnReady(function() ns.Try("prune", Data.Prune) end)
