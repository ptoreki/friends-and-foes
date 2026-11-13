local _, ns = ...

local Data = {}
ns.Data = Data

local FEED_MAX = 500

function Data.Realm()
  local realms = FriendsAndFoesDB.realms
  local key = ns.realm or GetRealmName()
  local r = realms[key]
  if not r then
    r = {}
    realms[key] = r
  end
  r.players = r.players or {}
  r.hitlist = r.hitlist or {}
  r.feed = r.feed or {}
  return r
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
  if u.zone and u.zone ~= "" then rec.lastZone = u.zone end
  rec.lastSeen = time()
end

function Data.Hit(name)
  local list = Data.Realm().hitlist
  local h = list[name]
  if not h then
    h = { name = name, attacks = 0, kills = 0, suspect = 0, victims = {}, firstSeen = time() }
    list[name] = h
  end
  return h
end

function Data.Feed(kind, text)
  local feed = Data.Realm().feed
  feed[#feed + 1] = { t = time(), kind = kind, text = text }
  while #feed > FEED_MAX do table.remove(feed, 1) end
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
