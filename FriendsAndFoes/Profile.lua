local _, ns = ...
local L = ns.L
local issecret = ns.issecret

-- Profiles and the PvP leaderboard.
-- Every client is the authority on its own player: it sends its own all-time kills/deaths,
-- most wanted enemy, zone and status (PRO message). Friends keep the latest one.
local Profile = {}
ns.Profile = Profile

local ZONE_MAX = 48
local SEND_DEBOUNCE = 5
local FIGHT_FRESH = 120 -- an "in a fight" status older than this is ignored (its "over" may be lost)
local RECENT_MAX = 10
local PVP_KINDS = { attacked = true, engage = true, died = true, kill = true, sighting = true }

---------------------------------------------------------------------------
-- your own profile (account-wide)
---------------------------------------------------------------------------
local function mine()
  FriendsAndFoesDB.profile = FriendsAndFoesDB.profile or {}
  return FriendsAndFoesDB.profile
end

-- bytes in the UTF-8 character starting with byte b
local function charLen(b) return (b >= 240 and 4) or (b >= 224 and 3) or (b >= 192 and 2) or 1 end

-- length in characters (what the player sees), not bytes: "Ærø" is 3
function Profile.Length(s)
  local n, i = 0, 1
  while i <= #s do
    n, i = n + 1, i + charLen(s:byte(i))
  end
  return n
end

-- the first `max` characters, never half of one
local function cut(s, max)
  local n, i = 0, 1
  while i <= #s do
    n = n + 1
    if n > max then return s:sub(1, i - 1) end
    i = i + charLen(s:byte(i))
  end
  return s
end

-- plain one-line text: no colour codes or links (a "|" starts one), no tabs or line breaks.
-- max: characters to keep (longer text is cut)
function Profile.CleanText(s, max)
  if type(s) ~= "string" or issecret(s) then return nil end
  s = s:gsub("|", ""):gsub("[%c]", " "):gsub("%s+", " ")
  s = strtrim(s)
  if s == "" then return nil end
  return max and cut(s, max) or s
end

---------------------------------------------------------------------------
-- language filter for text players type (group names). Blizzard's own filter isn't
-- available to add-ons, so this uses ProfanityLib and its word list (ProfanityLibData), bundled
-- in Libs/ (a separately installed newer copy takes over). Without the word list, ProfanityLib
-- would let everything through, so if either is ever missing, text from others isn't shown.
---------------------------------------------------------------------------
function Profile.FilterReady()
  return type(ProfanityLib) == "table" and type(ProfanityLib.IsProfane) == "function"
    and type(ProfanityLibData) == "table"
end

-- "ok" | "offensive" | "unchecked" (filter not installed, or it failed)
function Profile.Check(text)
  if type(text) ~= "string" or text == "" then return "ok" end
  if not Profile.FilterReady() then return "unchecked" end
  local ok, bad = pcall(ProfanityLib.IsProfane, ProfanityLib, text)
  if not ok then return "unchecked" end
  return bad and "offensive" or "ok"
end

-- text someone else wrote: only shown once the filter says it's fine. nil, why ("offensive" |
-- "unchecked") if not.
function Profile.Shown(text)
  local verdict = Profile.Check(text)
  if verdict == "ok" then return text end
  return nil, verdict
end

function Profile.Wanted() return mine().wanted end

-- name = nil clears it
function Profile.SetWanted(name)
  mine().wanted = ns.CleanName(name)
  Profile.Changed()
  return mine().wanted
end

local function myRecord()
  local players = ns.Data.RealRealm().players
  return players[ns.Data.Resolve(players, ns.me)]
end

function Profile.MyStatus()
  if UnitIsAFK then
    local afk = UnitIsAFK("player")
    if not issecret(afk) and afk then return "afk" end
  end
  if ns.PvP and ns.PvP.InFight and ns.PvP.InFight() then return "pvp" end
  return ""
end

-- when your kills/deaths last changed (your clock): the "as of" for your numbers everywhere
function Profile.MyStatsTime()
  local me = myRecord()
  local k, d = ns.Count(me and me.k), ns.Count(me and me.d)
  local p = mine()
  if p.statK ~= k or p.statD ~= d or not p.statT then
    p.statK, p.statD, p.statT = k, d, time()
  end
  return p.statT
end

-- a time from another player's clock: never later than now on yours
function Profile.ClampTime(t)
  t = tonumber(t)
  if not t then return nil end
  return math.min(t, time())
end

function Profile.Fields()
  local me = myRecord()
  local sharePvp = ns.S().share.pvp
  local shareWhere = ns.S().share.where ~= false -- Options: "Where I am"
  local zone = shareWhere and GetRealZoneText and GetRealZoneText()
  if issecret(zone) or type(zone) ~= "string" then zone = "" end
  return {
    k = sharePvp and ns.Count(me and me.k) or "",
    d = sharePvp and ns.Count(me and me.d) or "",
    wanted = mine().wanted or "",
    zone = cut(zone, ZONE_MAX),
    status = shareWhere and Profile.MyStatus() or "",
    t = sharePvp and Profile.MyStatsTime() or "",
  }
end

local function message()
  local _, class = UnitClass("player")
  return { kind = "PRO", id = ns.NewId(), class = class, level = UnitLevel("player"), f = Profile.Fields() }
end

---------------------------------------------------------------------------
-- sending: to everyone when something changed, to a friend when they come online
---------------------------------------------------------------------------
local lastSig
local function signature(msg)
  local f = msg.f
  return table.concat({ tostring(f.k), tostring(f.d), f.wanted, f.zone, f.status, tostring(msg.level) }, "\t")
end

-- force: send even if nothing changed since the last time
function Profile.Broadcast(force)
  if not ns.me then return false end
  local msg = message()
  local sig = signature(msg)
  if not force and sig == lastSig then return false end
  local statsChanged = not lastSig or lastSig:match("^[^\t]*\t[^\t]*") ~= sig:match("^[^\t]*\t[^\t]*")
  lastSig = sig
  ns.Comm.Broadcast(msg)
  -- your groups: your account's numbers go to members (and through them to the rest)
  if statsChanged and ns.Groups then ns.Groups.MyStatsChanged() end
  return true
end

local pending = false
function Profile.Changed()
  if pending then return end
  pending = true
  C_Timer.After(SEND_DEBOUNCE, function()
    pending = false
    ns.Try("profile-send", Profile.Broadcast)
  end)
end

function Profile.Greet(names)
  local msg = message()
  for _, name in ipairs(names) do ns.Comm.SendTo(name, msg) end
end

ns.On("ZONE_CHANGED_NEW_AREA", function() Profile.Changed() end)
ns.On("PLAYER_FLAGS_CHANGED", function(unit)
  if unit == "player" then Profile.Changed() end -- AFK on/off
end)

---------------------------------------------------------------------------
-- receiving
---------------------------------------------------------------------------
-- p: the friend's record
function Profile.Apply(p, f)
  local k, d = tonumber(f.k), tonumber(f.d)
  if k and d then
    p.sk, p.sd = ns.Count(k), ns.Count(d)
  else
    p.sk, p.sd = nil, nil -- they stopped sharing PvP
  end
  p.wanted = ns.CleanName(f.wanted)
  -- where they are: an empty zone means they turned "Where I am" off - then nothing is kept
  local zone = Profile.CleanText(f.zone, ZONE_MAX)
  if zone then
    p.whereOff = nil
    Profile.SeenAt(p, zone, time())
  else
    p.whereOff, p.zone, p.zoneAt = true, nil, nil
  end
  p.status = (f.status == "afk" or f.status == "pvp") and f.status or nil
  p.statusAt = time()
  -- as of when (their clock, never in the future on yours); older clients don't say: now
  p.statAt = Profile.ClampTime(f.t) or time()
end

-- what a friend is doing now, if they're online: "Hillsbrad Foothills · in a fight"
-- A friend's last known place and when they were there (p.zone, p.zoneAt): the newest of
-- Battle.net (while they're online), their profile message, and their own PvP alerts (which say
-- where they happened). An older one arriving later never replaces a newer one.
function Profile.SeenAt(p, zone, t)
  if not p or p.whereOff or type(zone) ~= "string" or zone == "" or zone == "?" then return end
  t = t or time()
  if p.zoneAt and t < p.zoneAt then return end
  p.zone, p.zoneAt = zone, t
end

function Profile.NowText(p)
  local online = ns.Comm.everyone[p.name]
  if not online then return nil end
  -- Battle.net's zone is live, straight from the game; theirs may be a message behind
  local zone = online.zone or p.zone
  local status
  if p.status == "afk" then status = L.STATUS_AFK
  elseif p.status == "pvp" and p.statusAt and time() - p.statusAt < FIGHT_FRESH then status = L.STATUS_FIGHT end
  local parts = { L.FRIEND_ONLINE }
  if zone then parts[#parts + 1] = zone end
  if status then parts[#parts + 1] = status end
  return table.concat(parts, " \194\183 ")
end

---------------------------------------------------------------------------
-- leaderboard
---------------------------------------------------------------------------
function Profile.KD(k, d)
  if d <= 0 then return k end
  return math.floor(k / d * 100 + 0.5) / 100
end

-- friends shown on the board: the same friends as the Friends list, limited to your picks
local function onBoard(p, view)
  if not p.friend or p.self or p.name == ns.me then return false end
  if p.faction and ns.myFaction and p.faction ~= ns.myFaction then return false end
  if not view.sim then
    if not ns.Comm.everyone[p.name] and ns.Data.FriendIsGone(p) then return false end
    if ns.Comm.GroupActive() and not ns.Comm.IsPicked(ns.Comm.TagFor(p.name)) then return false end
  end
  return true
end

local function rank(rows)
  for i, r in ipairs(rows) do
    local prev = rows[i - 1]
    if r.unknown or r.invited then
      r.rank = nil
    else
      r.rank = (prev and prev.rank and prev.k == r.k and prev.d == r.d) and prev.rank or i
    end
  end
end

-- a shared group's board: one row per member account (you included), named after the character
-- they last played, with the freshest numbers known (all their characters added up).
-- Extra row fields: key, leader, invited, unknown (no numbers yet), via (relayed by), at (how old).
local function groupBoard(g)
  local players = ns.Data.RealRealm().players
  local myKey = ns.Groups.MyKey()
  local rows = {}
  for _, m in ipairs(ns.Groups.Members(g)) do
    local isMe = m.key == myKey
    local s = ns.Groups.StatsOf(m.key)
    local name = isMe and ns.me or (s and s.name) or m.name
    local p = players[ns.Data.Resolve(players, name)]
    local row = { key = m.key, name = name, class = p and p.class, level = p and p.level, me = isMe, rec = p,
      lastSeen = p and p.lastSeen, invited = m.state == "invited", leader = m.leader }
    if isMe then
      local _, class = UnitClass("player")
      row.class = row.class or class
    end
    if s then
      row.k, row.d, row.via, row.at = s.k, s.d, s.via, (not s.self) and s.t or nil
    else
      row.k, row.d, row.unknown = 0, 0, true
    end
    row.kd = Profile.KD(row.k, row.d)
    rows[#rows + 1] = row
  end
  table.sort(rows, function(a, b)
    local wa, wb = (a.invited or a.unknown) and 1 or 0, (b.invited or b.unknown) and 1 or 0
    if wa ~= wb then return wa < wb end
    if a.k ~= b.k then return a.k > b.k end
    if a.d ~= b.d then return a.d < b.d end
    return a.name < b.name
  end)
  rank(rows)
  return rows
end

-- rows: { name, class, level, k, d, kd, rank, estimated, me, rec }, best first.
-- estimated: counted by you from their events (they're on a version that doesn't report).
-- groupId: a shared group's board instead of your friends'.
function Profile.Board(groupId)
  local g = groupId and ns.Groups.Get(groupId)
  if g then return groupBoard(g) end
  local realm = ns.Data.ViewRealm()
  local view = { sim = ns.viewSim }
  local rows = {}
  local function add(p, isMe)
    local reported = isMe or p.sk ~= nil
    local k = (not isMe and p.sk) or ns.Count(p.k)
    local d = (not isMe and p.sd) or ns.Count(p.d)
    rows[#rows + 1] = { name = p.name, class = p.class, level = p.level, k = k, d = d, kd = Profile.KD(k, d),
      estimated = not reported, me = isMe, rec = p, lastSeen = p.lastSeen }
  end
  local me = realm.players[ns.Data.Resolve(realm.players, ns.me)]
  local _, class = UnitClass("player")
  add(me or { name = ns.me, class = class, level = UnitLevel("player"), k = 0, d = 0 }, true)
  for _, p in pairs(realm.players) do
    if onBoard(p, view) then add(p, false) end
  end
  table.sort(rows, function(a, b)
    if a.k ~= b.k then return a.k > b.k end
    if a.d ~= b.d then return a.d < b.d end
    return a.name < b.name
  end)
  rank(rows)
  return rows
end

---------------------------------------------------------------------------
-- profile page data
---------------------------------------------------------------------------
-- the enemy who killed this friend most (from the hitlist's per-friend counts)
function Profile.Nemesis(name)
  local best, most
  for _, h in pairs(ns.Data.ViewRealm().hitlist) do
    local n = ns.Count(h.kv and h.kv[name])
    if n > 0 and (not most or n > most or (n == most and h.name < best.name)) then best, most = h, n end
  end
  return best, most
end

-- friends (and you) who have this enemy as their most wanted
function Profile.WantedBy(enemy)
  local out = {}
  if mine().wanted == enemy then out[#out + 1] = ns.me end
  for _, p in pairs(ns.Data.ViewRealm().players) do
    if p.friend and not p.self and p.name ~= ns.me and p.wanted == enemy then out[#out + 1] = p.name end
  end
  table.sort(out)
  return out
end

-- newest first: Feed lines about this friend (who) or this enemy (foes)
function Profile.Recent(name, asEnemy, max)
  local feed, out = ns.Data.ViewRealm().feed, {}
  for i = #feed, 1, -1 do
    local e = feed[i]
    if PVP_KINDS[e.kind] then
      local hit = false
      if asEnemy then
        for _, f in ipairs(e.foes or {}) do if f == name then hit = true end end
      else
        hit = e.who == name
      end
      if hit then
        out[#out + 1] = e
        if #out >= (max or RECENT_MAX) then break end
      end
    end
  end
  return out
end

-- "friend" | "me" | "enemy" | nil (unknown)
function Profile.KindOf(name)
  if not name then return nil end
  if name == ns.me then return "me" end
  local realm = ns.Data.ViewRealm()
  local p = realm.players[ns.Data.Resolve(realm.players, name)]
  if p and p.friend then return "friend" end -- (your alts too)
  if p or realm.hitlist[ns.Data.Resolve(realm.hitlist, name)] then return "enemy" end
  return nil
end
-- Logging in (or /reload) needs no broadcast: every friend in the roster is new then, and
-- Comm.GreetNew sends them this profile.
