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

-- Simulated events (/fnf sim) write to a separate scratch store, never to real data.
function Data.SimRealm()
  local db = FriendsAndFoesDB
  db.sim = db.sim or {}
  return ensure(db.sim)
end

function Data.RealRealm()
  local realms = FriendsAndFoesDB.realms
  local key = ns.realm or GetRealmName()
  realms[key] = realms[key] or {}
  return ensure(realms[key])
end

-- where writes go right now
function Data.Realm()
  if ns.simulating then return Data.SimRealm() end
  return Data.RealRealm()
end

-- what the window shows
function Data.ViewRealm()
  if ns.viewSim then return Data.SimRealm() end
  return Data.RealRealm()
end

function Data.ClearSim()
  FriendsAndFoesDB.sim = nil
  ns.viewSim = false
end

-- K/D/A record for any player (friend, self or enemy)
function Data.Player(name)
  local players = Data.Realm().players
  local p = players[name]
  if not p then
    p = { name = name, k = 0, d = 0, a = 0 }
    players[name] = p
  end
  return p
end

function Data.Touch(rec, u)
  if not u then return end
  if u.class and u.class ~= "" then rec.class = u.class end
  local lvl = tonumber(u.level)
  if lvl and lvl > 0 then rec.level = lvl end
  if u.guild and u.guild ~= "" then rec.guild = u.guild end
  if u.zone and u.zone ~= "" then rec.lastZone = u.zone end
  rec.lastSeen = time()
end

function Data.Hit(name)
  local list = Data.Realm().hitlist
  local h = list[name]
  if not h then
    h = { name = name, attacks = 0, kills = 0, suspect = 0, revenge = 0, victims = {}, firstSeen = time() }
    list[name] = h
  end
  return h
end

function Data.Feed(kind, text)
  local feed = Data.Realm().feed
  local entry = { t = time(), kind = kind, text = text }
  feed[#feed + 1] = entry
  while #feed > FEED_MAX do table.remove(feed, 1) end
  return entry
end

-- several friends can get honor for the same death; count it once
local recentDeaths = {}
function Data.EnemyDied(name)
  local now = GetTime()
  if recentDeaths[name] and now - recentDeaths[name] < 15 then return false end
  recentDeaths[name] = now
  local e = Data.Player(name)
  e.d = e.d + 1
  return true
end

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
