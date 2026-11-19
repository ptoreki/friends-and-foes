local _, ns = ...
local issecret = ns.issecret

local Comm = {}
ns.Comm = Comm

-- name -> { gid = gameAccountID, faction = "Horde"|"Alliance" }
-- name is "First Last" once known (learned from their messages), else whatever Battle.net gives.
-- `roster` holds only the friends you exchange events with (your picks, or everyone if you picked
-- nobody). `everyone` holds every eligible online friend, so the UI can offer to pick them.
local roster = {}
Comm.roster = roster
local everyone = {}
Comm.everyone = everyone
local fullByGid = {} -- gameAccountID -> "First Last", learned from received headers
local tagByGid = {}  -- gameAccountID -> BattleTag

---------------------------------------------------------------------------
-- picked friends ("group"), keyed by BattleTag so alts are covered
---------------------------------------------------------------------------
local function group()
  FriendsAndFoesDB.group = FriendsAndFoesDB.group or {}
  return FriendsAndFoesDB.group
end

-- nobody picked = everyone counts (the default)
function Comm.GroupActive() return next(group()) ~= nil end

function Comm.Allowed(tag)
  if not Comm.GroupActive() then return true end
  return tag ~= nil and group()[tag] == true
end

function Comm.IsPicked(tag) return tag ~= nil and group()[tag] == true end

-- remembered name -> BattleTag, so offline friends in the Friends tab can still be toggled
local function rememberTag(name, tag)
  if not (name and tag) then return end
  FriendsAndFoesDB.friendTags = FriendsAndFoesDB.friendTags or {}
  FriendsAndFoesDB.friendTags[name] = tag
end

function Comm.TagFor(name)
  if not name then return nil end
  if everyone[name] then return everyone[name].tag end
  local tags = FriendsAndFoesDB.friendTags or {}
  return tags[name]
end

-- returns the new state (true = picked)
function Comm.TogglePick(tag)
  if not tag then return nil end
  local g = group()
  g[tag] = (not g[tag]) or nil
  Comm.RebuildRoster()
  return g[tag] == true
end

function Comm.ClearPicks()
  wipe(group())
  Comm.RebuildRoster()
end

-- find an online friend by "First Last", unique first name, BattleTag or BattleTag name (case-insensitive)
function Comm.FindCandidate(query)
  query = query and query:lower()
  if not query or query == "" then return nil end
  local hits = {}
  for name, e in pairs(everyone) do
    local tag = e.tag and e.tag:lower()
    if name:lower() == query or (tag and (tag == query or tag:match("^[^#]+") == query)) then
      return name, e.tag
    end
    if ns.FirstName(name):lower() == query then hits[#hits + 1] = name end
  end
  if #hits == 1 then return hits[1], everyone[hits[1]].tag end
  return nil, #hits > 1 and "ambiguous" or nil
end

local MAX_PAYLOAD = 255

-- "ago": seconds since it happened, set only when replaying events to a friend who was offline
-- (see catch-up below). Live messages leave it empty; older clients ignore it.
-- "rl" (0.7.1): "1" = the sender lets friends pass this event on to their other friends (relay,
-- below). Older clients don't send it (= not passed on) and ignore it.
local SCHEMA = {
  LVL  = { "level", "ago", "rl" },
  LOOT = { "link", "source", "ago", "rl" },
  GEAR = { "link", "count", "epics", "ago", "rl" }, -- epics: how many of the batch were epic or better
  ATK  = { "enc", "zone", "attackers", "ago", "rl" },
  DIE  = { "zone", "killer", "conf", "assists", "ended", "ago", "rl" },        -- ended: kill streak this death ended
  KILL = { "victim", "vclass", "vlevel", "vguild", "zone", "streak", "ago", "rl" }, -- streak: kills in a row incl. this
  HIT  = { "share", "entries" },
  SIGHT = { "name", "class", "level", "guild", "zone" }, -- a hitlist player spotted by the sender
  ENG  = { "zone", "target", "ago", "rl" }, -- the sender started a fight with an enemy player
  REQ  = { "window" }, -- "I just came online: what happened in the last <window> seconds?"
  -- the sender's profile (0.7): own all-time kills/deaths (empty if they don't share PvP),
  -- most wanted enemy, zone, status ("" | "afk" | "pvp"). Older clients ignore unknown kinds.
  -- t: when the K/D was last true, on the sender's clock (so relayed copies compare fairly)
  PRO  = { "k", "d", "wanted", "zone", "status", "t", "bt" }, -- bt (0.9): bounties collected, gold
  -- shared groups (0.7, Groups.lua): a group and some of its members ("First Last:a:j:r;...",
  -- times in base 36 after `base`), and relayed stats ("First Last:k:d:time;...")
  GRP  = { "gid", "name", "owner", "base", "members" },
  GST  = { "stats" },
  -- kill lists (0.7.1, Kills.lua): "send me the list of <who>" (your own character), and the
  -- answer: who it's about, how many victims in all, and the top ones ("Name:count:time;...")
  KLQ  = { "who" },
  KLA  = { "who", "total", "list" },
  -- relayed catch-up (0.7.1): "anything from these friends of mine in the last <window> seconds?"
  -- and the answer: one event someone else sent you, with who it's from (origin) and its own
  -- fields joined by "^" in `data`
  RLQ  = { "window", "names" },
  RLY  = { "origin", "oclass", "olevel", "okind", "oid", "ago", "data" },
  -- the bounty board (0.9.3, Contracts.lua): one of the sender's contracts. target is a unit,
  -- amount in copper, state open|done|paid|cancelled, killer who did it, age/updage: seconds
  -- since it was posted / last changed
  BTY  = { "cid", "target", "amount", "state", "killer", "age", "updage", "days" }, -- days: how long it's open
}
Comm.SCHEMA = SCHEMA

-- What each message kind is: the version it first appeared in, and whether friends may pass it
-- on to their other friends (relay, catch-up). One place to check before changing a message:
-- new fields only ever go on the end (older clients ignore them), kinds are never reused.
Comm.KINDS = {
  LVL = { since = "0.1.0", relay = true }, LOOT = { since = "0.1.0", relay = true },
  GEAR = { since = "0.1.0", relay = true }, ATK = { since = "0.1.0", relay = true },
  DIE = { since = "0.1.0", relay = true }, KILL = { since = "0.1.0", relay = true },
  HIT = { since = "0.2.0" }, SIGHT = { since = "0.6.0" }, ENG = { since = "0.6.1", relay = true },
  REQ = { since = "0.6.3" }, PRO = { since = "0.7.0" }, GRP = { since = "0.7.0" }, GST = { since = "0.7.0" },
  KLQ = { since = "0.7.1" }, KLA = { since = "0.7.1" }, RLQ = { since = "0.7.1" }, RLY = { since = "0.7.1" },
  BTY = { since = "0.9.3" },
}

-- Features and the first version that has them, for "does this friend's add-on do X?"
Comm.FEATURES = {
  profiles = "0.7.0", groups = "0.7.0", killLists = "0.7.1", relay = "0.7.1", bounties = "0.9.0", contracts = "0.9.3",
}

-- true if this version of the add-on has the feature (nil version: unknown, so no)
function Comm.VersionSupports(version, feature)
  local since = Comm.FEATURES[feature]
  if not since or type(version) ~= "string" then return false end
  return not ns.VersionNewer(since, version)
end

-- does this friend's add-on (the version they last sent) have the feature?
function Comm.Supports(name, feature)
  local p = name and ns.Data.FindPlayer(name)
  return Comm.VersionSupports(p and p.version, feature)
end
-- asked for, not broadcast: group traffic and kill lists also flow with friends you didn't
-- pick for alerts, and only over Battle.net (no whisper copy)
local GROUP_KINDS = { GRP = true, GST = true, KLQ = true, KLA = true, BTY = true }

local PRIORITY_OF = { BTY = "normal", RLQ = "normal", RLY = "bulk", KLQ = "normal", KLA = "bulk", GRP = "normal", GST = "normal", PRO = "normal", REQ = "normal", ATK = "high", ENG = "high", DIE = "high", KILL = "high", SIGHT = "high", LVL = "normal", LOOT = "normal", GEAR = "normal", HIT = "bulk" }
local UNIT_FIELDS = { attackers = true, killer = true, assists = true }

---------------------------------------------------------------------------
-- wire format: PROTOCOL \t KIND \t ID \t senderName \t class \t level \t addonVersion \t fields...
-- senderName is the full "First Last": on Forever, Battle.net may only give us the first name,
-- and first names are shared.
---------------------------------------------------------------------------
local HEADER = 7
local function clean(v)
  if v == nil then return "" end
  return (tostring(v):gsub("\t", " "))
end

function Comm.Encode(msg, dropGuilds)
  local parts = { tostring(ns.PROTOCOL), msg.kind, msg.id, clean(msg.name or ns.me), clean(msg.class), clean(msg.level), ns.VERSION }
  for _, field in ipairs(SCHEMA[msg.kind]) do
    local v = clean(msg.f[field])
    if dropGuilds and UNIT_FIELDS[field] then
      v = v:gsub("([^:;]*:[^:;]*:[^:;]*):[^;]*", "%1:")
    end
    parts[#parts + 1] = v
  end
  return table.concat(parts, "\t")
end

function Comm.Decode(text)
  local p = ns.Split(text, "\t")
  local proto = tonumber(p[1])
  if not proto then return nil end
  if proto ~= ns.PROTOCOL then return nil, proto end
  local schema = SCHEMA[p[2]]
  if not schema or not p[3] or p[3] == "" then return nil end
  local msg = { kind = p[2], id = p[3], name = ns.CleanName(p[4]), class = p[5] and p[5]:match("^%u+$"), level = tonumber(p[6]),
    version = p[7] and p[7]:match("^[%d%.]+$"), f = {} }
  for i, field in ipairs(schema) do msg.f[field] = p[HEADER + i] or "" end
  return msg
end

-- Encodes, dropping guild names if needed to fit the 255-byte limit. nil if it still doesn't fit.
-- Still too long (long names, a long zone): helpers are dropped one at a time, last first - the
-- killer and the rest of the message always go (a death with 3 helpers could otherwise be lost).
local TRIM_LISTS = { "assists" }
function Comm.Fit(msg)
  local payload = Comm.Encode(msg)
  if #payload > MAX_PAYLOAD then payload = Comm.Encode(msg, true) end
  if #payload > MAX_PAYLOAD then
    -- trim a copy: your own copy of the event keeps everyone
    local sent = setmetatable({ f = setmetatable({}, { __index = msg.f }) }, { __index = msg })
    for _, field in ipairs(TRIM_LISTS) do
      local list = msg.f[field]
      while #payload > MAX_PAYLOAD and type(list) == "string" and list ~= "" do
        list = list:match("^(.*);[^;]*$") or "" -- drop the last one
        sent.f[field] = list
        payload = Comm.Encode(sent, true)
      end
    end
  end
  if #payload > MAX_PAYLOAD then
    ns.Debug("TOO-LONG", msg.kind, #payload)
    return nil
  end
  return payload
end

---------------------------------------------------------------------------
-- roster: online Battle.net friends on this realm
---------------------------------------------------------------------------
local lastRebuild = 0

-- Can we exchange events with this Battle.net game account?
-- WoW Forever has no realms: GetRealmName returns an internal server name ("CAMWOW EU4 Realm 8 PvP")
-- that differs between friends who play together. Names are unique region-wide, so any friend in
-- the Forever game (same WoW project) counts. Elsewhere, fall back to same-realm.
-- Returns ok, reasonIfNot.
function Comm.SameWorld(g)
  if ns.ForeverNames() then
    local proj = g.wowProjectID
    -- 0 (or nothing) means Battle.net didn't say: not a different game
    if proj and proj ~= 0 and WOW_PROJECT_ID and not issecret(proj) and proj ~= WOW_PROJECT_ID then
      return false, "other WoW version"
    end
    return true
  end
  local myRealmID = GetRealmID and GetRealmID()
  if issecret(myRealmID) then myRealmID = nil end
  if g.realmName and ns.NormRealm(g.realmName) == ns.NormRealm(ns.realm) then return true end
  if myRealmID and g.realmID and not issecret(g.realmID) and g.realmID == myRealmID then return true end
  return false, "other realm"
end

-- Friends on the other faction are left out: you can't group or help each other in world PvP,
-- and their fights would put your own faction's players on your hitlist.
function Comm.OtherFaction(faction)
  if not faction or issecret(faction) or faction == "" or faction == "Neutral" then return false end
  if not ns.myFaction or ns.myFaction == "Neutral" then return false end
  return faction ~= ns.myFaction
end

function Comm.RebuildRoster()
  lastRebuild = GetTime()
  wipe(roster)
  wipe(everyone)
  if not (BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendNumGameAccounts and C_BattleNet.GetFriendGameAccountInfo) then
    ns.SetCap("bnet", "missing")
    return
  end
  local wowClient = BNET_CLIENT_WOW or "WoW"
  local n = BNGetNumFriends() or 0
  local report = {} -- one line per WoW game account, so a report shows why someone is missing
  local debugging = ns.S().debug
  for i = 1, n do
    local tag, tagRead
    for j = 1, (C_BattleNet.GetFriendNumGameAccounts(i) or 0) do
      local g = C_BattleNet.GetFriendGameAccountInfo(i, j)
      if g and g.clientProgram == wowClient then
        local why
        local same, notWhy = Comm.SameWorld(g)
        -- Battle.net sometimes gives a friend's game account without a character name; the name
        -- learned from their own messages still works
        local known = fullByGid[g.gameAccountID] or ns.CleanName(g.characterName)
        if not g.isOnline then why = "offline"
        elseif not known then why = "no character name"
        elseif not same then why = notWhy
        elseif Comm.OtherFaction(g.factionName) then why = "other faction"
        end
        local name = not why and known
        if not why and (not name or name == ns.me) then why = "self" end
        if not why and not tagRead then
          -- BattleTag only for friends who are actually eligible (saves a table per friend)
          tagRead = true
          if C_BattleNet.GetFriendAccountInfo then
            local ok, acct = pcall(C_BattleNet.GetFriendAccountInfo, i)
            if ok and acct and type(acct.battleTag) == "string" and not issecret(acct.battleTag) then tag = acct.battleTag end
          end
        end
        if not why then
          local zone = g.areaName
          if issecret(zone) or zone == "" then zone = nil end
          local entry = { gid = g.gameAccountID, faction = g.factionName, tag = tag, zone = zone }
          everyone[name] = entry
          -- Battle.net's zone is live: it's their last known place (shown once they log off)
          local rec = zone and ns.Profile and ns.Data.FindPlayer(name)
          if rec and rec.friend then ns.Profile.SeenAt(rec, zone, time()) end
          if g.gameAccountID then tagByGid[g.gameAccountID] = tag or false end
          rememberTag(name, tag)
          if Comm.Allowed(tag) then roster[name] = entry else why = "not picked" end
        end
        if debugging then report[#report + 1] = table.concat({ tostring(g.characterName), tostring(g.realmName),
          tostring(g.realmID), tostring(g.wowProjectID), tostring(g.factionName), tag and "tag" or "no tag", why or "OK" }, "/") end
      end
    end
  end
  Comm.GreetNew()
  if not debugging then return end
  table.sort(report)
  local sig = table.concat(report, "; ")
  if sig ~= Comm.lastRosterReport then
    Comm.lastRosterReport = sig
    ns.Debug("ROSTER", "me=" .. tostring(ns.me) .. " server=" .. tostring(ns.realm) .. " project=" .. tostring(WOW_PROJECT_ID),
      "bnetFriends=" .. n, sig ~= "" and sig or "no WoW game accounts")
  end
end

-- Friends who just came online (or you just logged in) get your profile once, if they're in the
-- roster, and the groups you share with them, even if you didn't pick them. Keyed by game
-- account, so a friend re-keyed from "First" to "First Last" isn't greeted twice.
local greeted = {} -- gameAccountID -> "roster" | "everyone"
function Comm.GreetNew()
  local profile, groups, present = {}, {}, {}
  for name, e in pairs(everyone) do
    if e.gid then
      present[e.gid] = true
      local level = roster[name] and "roster" or "everyone"
      if not greeted[e.gid] then groups[#groups + 1] = name end
      if level == "roster" and greeted[e.gid] ~= "roster" then profile[#profile + 1] = name end
      greeted[e.gid] = level
    end
  end
  for gid in pairs(greeted) do
    if not present[gid] then greeted[gid] = nil end -- offline: greet again when back
  end
  if not ns.me then return end
  if #profile > 0 and ns.Profile then ns.Profile.Greet(profile) end
  for _, name in ipairs(profile) do Comm.AskCatchUpFrom(name) end -- what they did while you were away
  if #groups > 0 and ns.Groups then ns.Groups.Greet(groups) end
  if #groups > 0 and ns.Contracts then ns.Contracts.Greet(groups) end -- your bounty board contracts
end

function Comm.RosterNames()
  local names = {}
  for name in pairs(roster) do names[#names + 1] = name end
  table.sort(names)
  return names
end

-- BN_FRIEND_INFO_CHANGED fires for every status/zone change of every Battle.net friend (any
-- game), so rebuilds are batched. Explicit callers (status, group, unknown sender) rebuild directly.
local ROSTER_DEBOUNCE = 5
local pending = false
function Comm.QueueRoster()
  if pending then return end
  pending = true
  C_Timer.After(ROSTER_DEBOUNCE, function()
    pending = false
    ns.Try("roster", Comm.RebuildRoster)
  end)
end

-- roster entry for a name in any form ("First Last", "First"); first-name matches only when unique
local function rosterFind(name)
  if not name then return nil end
  if roster[name] then return name end
  local first, hit, n = ns.FirstName(name), nil, 0
  for k in pairs(roster) do
    if ns.FirstName(k) == first and (k == first or name == first) then hit, n = k, n + 1 end
  end
  if n == 1 then return hit end
  return nil
end

local function findFriend(name)
  local key = rosterFind(name)
  if key then return key end
  if GetTime() - lastRebuild > 10 then Comm.RebuildRoster() end
  return rosterFind(name)
end
Comm.FindFriend = findFriend

-- learned a friend's full name: re-key their roster entry so whispers address "First Last"
local function learnFull(key, full, gid)
  if gid then fullByGid[gid] = full end
  if key and key ~= full then
    for _, map in ipairs({ roster, everyone }) do
      if map[key] then
        map[full] = map[key]
        map[key] = nil
      end
    end
  end
  rememberTag(full, gid and tagByGid[gid] or (everyone[full] and everyone[full].tag))
end

-- the zone Battle.net says an online friend is in (nil if unknown)
function Comm.ZoneOf(name)
  local e = name and everyone[name]
  return e and e.zone
end

function Comm.EveryoneNames()
  local names = {}
  for name in pairs(everyone) do names[#names + 1] = name end
  table.sort(names)
  return names
end

---------------------------------------------------------------------------
-- throttled send queues (token bucket per route, 3 priorities)
---------------------------------------------------------------------------
local BUCKET_MAX, REFILL_PER_SEC, QUEUE_MAX = 8, 1, 400
local PRIORITIES = { "high", "normal", "bulk" }

local routes = {}
for _, r in ipairs({ "bn", "whisper" }) do
  routes[r] = { tokens = BUCKET_MAX, q = { high = {}, normal = {}, bulk = {} } }
end

function Comm.QueuedCount(prio)
  local n = 0
  for _, route in pairs(routes) do
    for _, p in ipairs(PRIORITIES) do
      if not prio or prio == p then n = n + #route.q[p] end
    end
  end
  return n
end

local startPump -- defined with the pump below

local function enqueue(routeName, prio, item)
  local route = routes[routeName]
  local q = route.q[prio]
  q[#q + 1] = item
  startPump()
  -- overflow: drop oldest bulk, then oldest normal; never drop high
  local total = #route.q.high + #route.q.normal + #route.q.bulk
  while total > QUEUE_MAX do
    if #route.q.bulk > 0 then table.remove(route.q.bulk, 1)
    elseif #route.q.normal > 0 then table.remove(route.q.normal, 1)
    else break end
    total = total - 1
  end
end

local function sendItem(routeName, item)
  if routeName == "bn" then
    BNSendGameData(item.target, ns.PREFIX, item.payload)
    return true
  end
  local res = C_ChatInfo.SendAddonMessage(ns.PREFIX, item.payload, "WHISPER", item.target)
  local E = Enum and Enum.SendAddonMessageResult
  if type(res) == "number" and E and E.AddonMessageThrottle and res == E.AddonMessageThrottle then
    return false -- throttled by the client: retry later
  end
  if res ~= nil and res ~= 0 and res ~= true and not issecret(res) then
    ns.Debug("WHISPER-RESULT", item.target, tostring(res))
  end
  return true
end

local lastPump = GetTime()
local function pump()
  local now = GetTime()
  local elapsed = now - lastPump
  lastPump = now
  for routeName, route in pairs(routes) do
    route.tokens = math.min(BUCKET_MAX, route.tokens + elapsed * REFILL_PER_SEC)
    while route.tokens >= 1 do
      local item, q
      for _, p in ipairs(PRIORITIES) do
        if #route.q[p] > 0 then
          q = route.q[p]
          item = q[1]
          break
        end
      end
      if not item then break end
      local ok, sent = pcall(sendItem, routeName, item)
      if ok and sent == false then
        route.tokens = 0
        break
      end
      table.remove(q, 1)
      route.tokens = route.tokens - 1
      if not ok then ns.Debug("ERR:send-" .. routeName, sent) end
    end
  end
end

-- the pump only ticks while something is queued
local ticker
function startPump()
  if ticker then return end
  ticker = C_Timer.NewTicker(0.25, function()
    ns.Try("pump", pump)
    if ticker and Comm.QueuedCount() == 0 then
      ticker:Cancel()
      ticker = nil
    end
  end)
end
Comm.PumpRunning = function() return ticker ~= nil end

---------------------------------------------------------------------------
-- broadcast
---------------------------------------------------------------------------
-- Broadcasts go to the roster; group messages may go to any eligible friend.
-- Everything goes over Battle.net only (0.7.3). An addon whisper is sent only if Battle.net
-- messaging isn't available at all - every friend in the roster comes from your Battle.net list,
-- so Battle.net can always reach them. Whispers from older versions are still accepted.
local function sendTo(name, payload, prio)
  local r = roster[name] or everyone[name]
  if not r then return end
  if BNSendGameData and r.gid then
    enqueue("bn", prio, { target = r.gid, payload = payload })
  elseif r.faction == ns.myFaction and C_ChatInfo and C_ChatInfo.SendAddonMessage then
    enqueue("whisper", prio, { target = name, payload = payload })
  end
end

function Comm.SendPayload(payload, prio)
  for name in pairs(roster) do sendTo(name, payload, prio) end
end

-- one message to one friend
function Comm.SendTo(name, msg)
  local payload = Comm.Fit(msg)
  if not payload then return end
  sendTo(name, payload, PRIORITY_OF[msg.kind] or "normal")
  ns.Debug("SEND", msg.kind, msg.id, "to " .. tostring(name))
end

function Comm.Broadcast(msg)
  local payload = Comm.Fit(msg)
  if not payload then return end
  Comm.SendPayload(payload, PRIORITY_OF[msg.kind] or "normal")
  local to = Comm.RosterNames()
  ns.Debug("SEND", msg.kind, msg.id, #to == 0 and "to nobody (no friends found)" or ("to " .. table.concat(to, ", ")))
end

---------------------------------------------------------------------------
-- hitlist sharing (one-time, manual)
---------------------------------------------------------------------------
local SHARE_MAX_ENTRIES = 40

local function encodeEntry(h)
  local hours = h.lastSeen and math.floor((time() - h.lastSeen) / 3600) or ""
  return table.concat({
    (tostring(h.name):gsub("[:;\t]", " ")), h.class or "", h.level or "",
    ((h.guild or ""):gsub("[:;\t]", " ")), h.attacks or 0, h.kills or 0, h.revenge or 0, hours,
  }, ":")
end

-- returns number of entries queued
function Comm.ShareHitlist()
  local list = {}
  for _, h in pairs(ns.Data.RealRealm().hitlist) do list[#list + 1] = h end
  table.sort(list, function(a, b) return (a.lastSeen or 0) > (b.lastSeen or 0) end)

  local _, class = UnitClass("player")
  local shareId = ns.NewId()
  local batch = {}
  local count = 0

  local function flush()
    if #batch == 0 then return end
    local msg = { kind = "HIT", id = ns.NewId(), class = class, level = UnitLevel("player"),
      f = { share = shareId, entries = table.concat(batch, ";") } }
    Comm.SendPayload(Comm.Encode(msg), "bulk")
    wipe(batch)
  end

  for i = 1, math.min(#list, SHARE_MAX_ENTRIES) do
    local e = encodeEntry(list[i])
    batch[#batch + 1] = e
    local probe = Comm.Encode({ kind = "HIT", id = "x", class = class, level = 60,
      f = { share = shareId, entries = table.concat(batch, ";") } })
    if #probe > MAX_PAYLOAD - 8 then
      table.remove(batch)
      flush()
      batch[1] = e
    end
    count = count + 1
  end
  flush()
  return count
end

---------------------------------------------------------------------------
-- catch-up: when you log in, friends who are online send you their own events from while you
-- were away (up to 12 hours). They land in your Feed and hitlist without alerts.
---------------------------------------------------------------------------
local CATCHUP_WINDOW = 24 * 3600
local CATCHUP_MIN_AWAY = 120 -- a /reload or a quick relog doesn't ask
local OUTBOX_MAX = 100
local CATCHUP_KINDS = { LVL = true, LOOT = true, GEAR = true, ATK = true, ENG = true, DIE = true, KILL = true }
Comm.CATCHUP_WINDOW = CATCHUP_WINDOW

-- your own recent events, per character
local function outbox()
  local c = FriendsAndFoesCharDB
  c.outbox = c.outbox or {}
  local box, now = c.outbox, time()
  while #box > 0 and (now - (box[1].t or 0) > CATCHUP_WINDOW or #box > OUTBOX_MAX) do table.remove(box, 1) end
  return box
end
Comm.Outbox = outbox

function Comm.Remember(kind, id, fields)
  if not CATCHUP_KINDS[kind] then return end
  local f = {}
  for _, k in ipairs(SCHEMA[kind]) do
    local v = fields[k]
    if k ~= "ago" and (type(v) == "string" or type(v) == "number") then f[k] = v end
  end
  local box = outbox()
  box[#box + 1] = { t = time(), kind = kind, id = id, f = f }
  outbox()
end

-- what we received, kept a day and an hour so a replay of something you already saw is ignored
local function got()
  FriendsAndFoesDB.got = FriendsAndFoesDB.got or {}
  return FriendsAndFoesDB.got
end

local function pruneGot()
  local g, cutoff = got(), time() - CATCHUP_WINDOW - 3600
  for k, t in pairs(g) do
    if t < cutoff then g[k] = nil end
  end
end

local awayFrom          -- when you went offline before this session (nil until login is done)
local loginAsked = false -- the login-time ask has happened (or wasn't needed)
local askedThisSession = {} -- friend -> true once asked, at login or when they came online

local function reqMessage(window)
  local _, class = UnitClass("player")
  return { kind = "REQ", id = ns.NewId(), class = class, level = UnitLevel("player"), f = { window = window } }
end

-- just logged in: ask online friends what you missed since lastOnline
function Comm.AskCatchUp(lastOnline)
  local away = lastOnline and (time() - lastOnline) or CATCHUP_WINDOW
  if away < CATCHUP_MIN_AWAY then return false end
  local names = Comm.RosterNames()
  if #names == 0 then return false end
  for _, name in ipairs(names) do askedThisSession[name] = true end
  local window = math.floor(math.min(away, CATCHUP_WINDOW))
  Comm.SendPayload(Comm.Encode(reqMessage(window)), PRIORITY_OF.REQ)
  Comm.AskRelay(window) -- and what your other friends did, through them
  ns.Debug("CATCHUP-ASK", window, table.concat(names, ", "))
  return true
end

-- a friend came online after you did: they may have played while you were offline, so ask them
-- too (once per session; events you already got live are skipped by the receiving side)
function Comm.AskCatchUpFrom(name)
  if not (loginAsked and awayFrom) or askedThisSession[name] then return false end
  askedThisSession[name] = true
  local away = time() - awayFrom
  if away < CATCHUP_MIN_AWAY then return false end
  local window = math.floor(math.min(away, CATCHUP_WINDOW))
  sendTo(name, Comm.Encode(reqMessage(window)), PRIORITY_OF.REQ)
  Comm.AskRelay(window, name)
  ns.Debug("CATCHUP-ASK-LATE", name, window)
  return true
end

-- for tests: pretend you went offline at `t` and the login ask is done
function Comm.SetAwayFrom(t)
  awayFrom, loginAsked = t, true
  wipe(askedThisSession)
end

-- a friend just logged in: send them our own events from the window they missed
local answered = {}
function Comm.AnswerCatchUp(name, window)
  window = math.min(tonumber(window) or 0, CATCHUP_WINDOW)
  if window <= 0 then return 0 end
  if answered[name] and GetTime() - answered[name] < 60 then return 0 end
  answered[name] = GetTime()
  local key = rosterFind(name)
  if not key then
    Comm.RebuildRoster()
    key = rosterFind(name)
  end
  if not key then return 0 end
  local now, n = time(), 0
  local _, class = UnitClass("player")
  local share = ns.S().share
  for _, e in ipairs(outbox()) do
    local ago = now - e.t
    local cat = ns.Events.SHARE[e.kind]
    if ago <= window and cat and share[cat] then
      local f = {}
      for k, v in pairs(e.f) do f[k] = v end
      f.ago = math.max(1, ago)
      local payload = Comm.Fit({ kind = e.kind, id = e.id, class = class, level = UnitLevel("player"), f = f })
      if payload then
        sendTo(key, payload, "bulk")
        n = n + 1
      end
    end
  end
  ns.Debug("CATCHUP-ANSWER", key, window, n)
  return n
end

---------------------------------------------------------------------------
-- relayed catch-up: friends pass on what your OTHER friends did while you were offline, so you
-- also get the events of a friend you're never online with. Rules:
--  * the asker names which of their friends they want (those offline now); nothing else is sent
--  * only events the original sender marked "rl" (their "may be passed on" switch is on and they
--    haven't limited their alerts to picked friends)
--  * one hop: an event that came to you passed on is never passed on again
--  * same as catch-up: last 24 hours, no toasts, and your own picks still filter what you accept
---------------------------------------------------------------------------
local HEARD_MAX = 300        -- other friends' events kept to pass on
local RELAY_NAMES_MAX = 40   -- friends named in one ask
local SEP = "^"              -- joins an event's own fields inside RLY
-- events passed on per ask: every online friend who heard them answers, so the asker gets
-- copies from each; kept low so a login among several friends stays light
local RELAY_ANSWER_MAX = 30

-- may friends pass on your events? (sent with each event, as "rl")
function Comm.RelayAllowed()
  return ns.S().share.relay ~= false and not Comm.GroupActive()
end

-- events friends sent you that may be passed on, oldest first
local function heard()
  local db = FriendsAndFoesDB
  db.heard = db.heard or {}
  local box, cutoff = db.heard, time() - CATCHUP_WINDOW
  while #box > 0 and ((box[1].t or 0) < cutoff or #box > HEARD_MAX) do table.remove(box, 1) end
  return box
end
Comm.HeardBox = heard

function Comm.Hear(origin, msg)
  local f = {}
  for _, k in ipairs(SCHEMA[msg.kind]) do
    if k ~= "ago" and k ~= "rl" then f[k] = msg.f[k] end
  end
  local box = heard()
  local t = time() - (msg.ago or 0)
  local i = #box + 1 -- keep time order (a caught-up event can be older than the newest)
  while i > 1 and (box[i - 1].t or 0) > t do i = i - 1 end
  table.insert(box, i, { t = t, o = origin, c = msg.class, l = msg.level, k = msg.kind, id = msg.id, f = f })
  heard()
end

-- your friends who aren't online now: their events can only reach you through others
local function offlineFriends()
  local out = {}
  for _, p in pairs(ns.Data.RealRealm().players) do
    if p.friend and not p.self and p.name ~= ns.me and not everyone[p.name]
      and not ns.Data.FriendIsGone(p) and not Comm.OtherFaction(p.faction) then
      out[#out + 1] = p.name
    end
  end
  table.sort(out)
  while #out > RELAY_NAMES_MAX do table.remove(out) end
  return out
end

-- ask online friends (or one) for what those offline friends did in the last `window` seconds
function Comm.AskRelay(window, onlyName)
  local names = offlineFriends()
  if #names == 0 then return 0 end
  local _, class = UnitClass("player")
  local function build(batch)
    return { kind = "RLQ", id = ns.NewId(), class = class, level = UnitLevel("player"),
      f = { window = window, names = table.concat(batch, ";") } }
  end
  local msgs, batch = {}, {}
  for _, name in ipairs(names) do
    batch[#batch + 1] = name
    if #Comm.Encode(build(batch)) > 250 then
      table.remove(batch)
      msgs[#msgs + 1] = build(batch)
      batch = { name }
    end
  end
  msgs[#msgs + 1] = build(batch)
  for _, m in ipairs(msgs) do
    local payload = Comm.Encode(m)
    if onlyName then sendTo(onlyName, payload, PRIORITY_OF.RLQ) else Comm.SendPayload(payload, PRIORITY_OF.RLQ) end
  end
  ns.Debug("RELAY-ASK", onlyName or "all", window, #names)
  return #msgs
end

-- one event passed on, as an RLY payload (guild names dropped if it doesn't fit; nil if still not)
local function relayPayload(e, ago, dropGuilds)
  local parts = {}
  for _, k in ipairs(SCHEMA[e.k]) do
    if k ~= "ago" and k ~= "rl" then
      local v = tostring(e.f[k] or ""):gsub("%^", " ")
      if dropGuilds and UNIT_FIELDS[k] then v = v:gsub("([^:;]*:[^:;]*:[^:;]*):[^;]*", "%1:") end
      parts[#parts + 1] = v
    end
  end
  local _, class = UnitClass("player")
  local payload = Comm.Encode({ kind = "RLY", id = ns.NewId(), class = class, level = UnitLevel("player"),
    f = { origin = e.o, oclass = e.c or "", olevel = e.l or "", okind = e.k, oid = e.id,
      ago = math.max(1, ago), data = table.concat(parts, SEP) } })
  if #payload <= MAX_PAYLOAD then return payload end
  if dropGuilds then return nil end
  return relayPayload(e, ago, true)
end

-- a friend asked: pass on what the friends they named did (not their own events: they know those)
local relayedTo = {} -- asker>origin:id -> GetTime(), so a repeat ask doesn't resend
function Comm.AnswerRelay(asker, f)
  local window = math.min(tonumber(f.window) or 0, CATCHUP_WINDOW)
  if window <= 0 then return 0 end
  local key = rosterFind(asker) or (everyone[asker] and asker)
  if not key then return 0 end
  local want = {}
  for _, n in ipairs(ns.Split(f.names or "", ";")) do
    local name = ns.CleanName(n)
    if name and name ~= asker then want[name] = true end
  end
  local now, sent, box = time(), 0, heard()
  -- newest first, at most RELAY_ANSWER_MAX: other online friends may be sending the same ones
  for i = #box, 1, -1 do
    if sent >= RELAY_ANSWER_MAX then break end
    local e = box[i]
    local ago = now - e.t
    local mark = asker .. ">" .. e.o .. ":" .. e.id
    if want[e.o] and ago <= window and not (relayedTo[mark] and GetTime() - relayedTo[mark] < 600) then
      local payload = relayPayload(e, ago)
      if payload then
        relayedTo[mark] = GetTime()
        sendTo(key, payload, "bulk")
        sent = sent + 1
      end
    end
  end
  ns.Debug("RELAY-ANSWER", asker, window, sent)
  return sent
end

-- an event passed on to you by `relayer`: applied like a catch-up event from its origin
function Comm.OnRelay(relayer, f)
  local origin = ns.CleanName(f.origin)
  local kind, oid = f.okind, f.oid
  if not (origin and CATCHUP_KINDS[kind] and type(oid) == "string" and oid ~= "" and not oid:find("^S")) then return end
  if origin == ns.me or origin == relayer then return end
  -- only your own friends' events, and your picks still count
  local rec = ns.Data.FindPlayer(origin)
  if not ((rec and rec.friend and not rec.self) or everyone[origin]) then return end
  if Comm.GroupActive() and not Comm.Allowed(Comm.TagFor(origin)) then return end
  local ago = tonumber(f.ago)
  if not ago or ago < 1 or ago > CATCHUP_WINDOW then return end
  local key = origin .. ":" .. oid
  if got()[key] then return end -- already have it (live, from them, or from another friend)
  got()[key] = time()
  local fields, vals, i = {}, ns.Split(f.data or "", SEP), 0
  for _, k in ipairs(SCHEMA[kind]) do
    if k ~= "ago" and k ~= "rl" then
      i = i + 1
      fields[k] = vals[i] or ""
    end
  end
  fields.ago = tostring(ago)
  ns.Debug("RELAY-GOT", relayer, origin, kind, oid)
  ns.Events.Apply({ kind = kind, id = oid, name = origin, class = f.oclass and f.oclass:match("^%u+$") or nil,
    level = tonumber(f.olevel), f = fields, from = origin, ago = ago }, false)
end

-- when you were last online (account-wide): saved every minute and at logout
ns.OnReady(function()
  local db = FriendsAndFoesDB
  local last = db.lastOnline
  db.lastOnline = time()
  awayFrom = last or (time() - CATCHUP_WINDOW)
  pruneGot()
  C_Timer.NewTicker(60, function() FriendsAndFoesDB.lastOnline = time() end)
  -- the roster is built a few seconds after login
  C_Timer.After(15, function()
    ns.Try("catchup", Comm.AskCatchUp, last)
    loginAsked = true -- from now on, friends coming online are asked one by one
  end)
end)
ns.On("PLAYER_LOGOUT", function() FriendsAndFoesDB.lastOnline = time() end)

---------------------------------------------------------------------------
-- receive (both routes, deduplicated)
---------------------------------------------------------------------------
local seen, seenCount = {}, 0
local warnedProtocol = false

-- routeName: who the route says sent it (Battle.net characterName or whisper sender), maybe
-- first name only. The header carries the full name; accept it only if the first names agree.
-- Returns the canonical sender name, or nil to drop.
local function senderOf(msg, routeName)
  local header = msg.name
  if header and ns.FirstName(header) == ns.FirstName(routeName) then
    -- same character: keep whichever form carries the surname
    if #header >= #routeName then return header end
    return routeName
  end
  if header then
    ns.Debug("SENDER-MISMATCH", routeName, header)
    return nil
  end
  return routeName
end

-- returns the canonical sender name if accepted
local function accept(text, routeName, via)
  if issecret(text) or type(text) ~= "string" then return end
  local msg, otherProto = Comm.Decode(text)
  if not msg then
    if otherProto and otherProto ~= ns.PROTOCOL and not warnedProtocol then
      warnedProtocol = true
      ns.Events.ProtocolMismatch(routeName, otherProto > ns.PROTOCOL)
    end
    return
  end
  local sender = senderOf(msg, routeName)
  if not sender then return end
  local key = sender .. ":" .. msg.id
  if seen[key] then return end
  seen[key] = GetTime()
  seenCount = seenCount + 1
  if seenCount > 400 then
    local now = GetTime()
    for k, t in pairs(seen) do
      if now - t > 600 then
        seen[k] = nil
        seenCount = seenCount - 1
      end
    end
  end
  msg.from = sender
  ns.Debug("RECV", via, routeName, sender, msg.kind, msg.id)
  if msg.kind == "REQ" then
    Comm.AnswerCatchUp(sender, msg.f.window)
    return sender
  end
  if msg.kind == "RLQ" then
    Comm.AnswerRelay(sender, msg.f)
    return sender
  end
  if msg.kind == "RLY" then
    Comm.OnRelay(sender, msg.f)
    return sender
  end
  if CATCHUP_KINDS[msg.kind] then
    local ago = tonumber(msg.f.ago)
    if ago and ago > 0 then
      if got()[key] then return sender end -- already seen live
      msg.ago = math.min(ago, CATCHUP_WINDOW)
    end
    got()[key] = time()
    -- kept to pass on to your other friends later, if the sender allows it
    if msg.f.rl == "1" and not msg.id:find("^S") then Comm.Hear(sender, msg) end
  end
  ns.Events.Apply(msg, false)
  return sender
end

ns.On("BN_CHAT_MSG_ADDON", function(prefix, text, _, senderID)
  if issecret(prefix) or prefix ~= ns.PREFIX or issecret(senderID) then return end
  local g = C_BattleNet.GetGameAccountInfoByID(senderID)
  if not g then
    ns.Debug("BN-DROP", "no game info", senderID)
    return
  end
  local same, why = Comm.SameWorld(g)
  if not same then
    ns.Debug("BN-DROP", why, g.realmName, ns.realm, tostring(g.wowProjectID))
    return
  end
  if Comm.OtherFaction(g.factionName) then
    ns.Debug("BN-DROP", "other faction", g.characterName, g.factionName)
    return
  end
  -- the character, as Battle.net names it; if it doesn't (it sometimes leaves the name out), the
  -- name we learned from them before, else the one in the message (it comes from this friend's
  -- own game account, so it's theirs)
  local name = ns.CleanName(g.characterName) or fullByGid[g.gameAccountID]
  if not name and type(text) == "string" and not issecret(text) then
    name = ns.CleanName(text:match("^%d+\t%u+\t[^\t]*\t([^\t]*)\t"))
  end
  if not name then
    ns.Debug("BN-DROP", "no character name", senderID)
    return
  end
  local kind = type(text) == "string" and not issecret(text) and text:match("^%d+\t(%u+)\t")
  if Comm.GroupActive() and not GROUP_KINDS[kind] then
    if tagByGid[g.gameAccountID] == nil then Comm.RebuildRoster() end
    if not Comm.Allowed(tagByGid[g.gameAccountID]) then
      ns.Debug("BN-DROP", "not picked", name)
      return
    end
  end
  ns.SetCap("bnet", "ok")
  local sender = accept(text, name, "bn")
  if sender then
    learnFull(rosterFind(name), sender, g.gameAccountID)
    local rec = ns.Data.FindPlayer(sender)
    if rec and g.factionName and not issecret(g.factionName) then rec.faction = g.factionName end
  end
end)

ns.On("CHAT_MSG_ADDON", function(prefix, text, channel, sender)
  if issecret(prefix) or prefix ~= ns.PREFIX then return end
  if issecret(channel) or channel ~= "WHISPER" then return end
  local name = ns.CleanName(sender)
  local key = findFriend(name)
  if not key then
    ns.Debug("WHISPER-DROP", "not a (picked) friend", sender)
    return
  end
  ns.SetCap("whisper", "ok")
  local from = accept(text, name, "whisper")
  if from then learnFull(key, from, roster[key] and roster[key].gid) end
end)

for _, ev in ipairs({ "BN_FRIEND_INFO_CHANGED", "BN_FRIEND_ACCOUNT_ONLINE", "BN_FRIEND_ACCOUNT_OFFLINE", "BN_CONNECTED", "PLAYER_ENTERING_WORLD" }) do
  ns.On(ev, Comm.QueueRoster)
end

ns.OnReady(function()
  if C_ChatInfo and C_ChatInfo.RegisterAddonMessagePrefix then
    C_ChatInfo.RegisterAddonMessagePrefix(ns.PREFIX)
  end
  Comm.QueueRoster()
end)
