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

local SCHEMA = {
  LVL  = { "level" },
  LOOT = { "link", "source" },
  GEAR = { "link", "count" },
  ATK  = { "enc", "zone", "attackers" },
  DIE  = { "zone", "killer", "conf", "assists", "ended" },        -- ended: kill streak this death ended
  KILL = { "victim", "vclass", "vlevel", "vguild", "zone", "streak" }, -- streak: kills in a row incl. this
  HIT  = { "share", "entries" },
  SIGHT = { "name", "class", "level", "guild", "zone" }, -- a hitlist player spotted by the sender
}
Comm.SCHEMA = SCHEMA

local PRIORITY_OF = { ATK = "high", DIE = "high", KILL = "high", SIGHT = "high", LVL = "normal", LOOT = "normal", GEAR = "normal", HIT = "bulk" }
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
  local msg = { kind = p[2], id = p[3], name = ns.CleanName(p[4]), class = p[5], level = tonumber(p[6]), version = p[7], f = {} }
  for i, field in ipairs(schema) do msg.f[field] = p[HEADER + i] or "" end
  return msg
end

-- Encodes, dropping guild names if needed to fit the 255-byte limit. nil if it still doesn't fit.
function Comm.Fit(msg)
  local payload = Comm.Encode(msg)
  if #payload > MAX_PAYLOAD then payload = Comm.Encode(msg, true) end
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
    if proj and WOW_PROJECT_ID and not issecret(proj) and proj ~= WOW_PROJECT_ID then
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
        if not g.isOnline then why = "offline"
        elseif not g.characterName then why = "no character name"
        elseif not same then why = notWhy
        elseif Comm.OtherFaction(g.factionName) then why = "other faction"
        end
        local name = not why and (fullByGid[g.gameAccountID] or ns.CleanName(g.characterName))
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
          if g.gameAccountID then tagByGid[g.gameAccountID] = tag or false end
          rememberTag(name, tag)
          if Comm.Allowed(tag) then roster[name] = entry else why = "not picked" end
        end
        if debugging then report[#report + 1] = table.concat({ tostring(g.characterName), tostring(g.realmName),
          tostring(g.realmID), tostring(g.wowProjectID), tostring(g.factionName), tag and "tag" or "no tag", why or "OK" }, "/") end
      end
    end
  end
  if not debugging then return end
  table.sort(report)
  local sig = table.concat(report, "; ")
  if sig ~= Comm.lastRosterReport then
    Comm.lastRosterReport = sig
    ns.Debug("ROSTER", "me=" .. tostring(ns.me) .. " server=" .. tostring(ns.realm) .. " project=" .. tostring(WOW_PROJECT_ID),
      "bnetFriends=" .. n, sig ~= "" and sig or "no WoW game accounts")
  end
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
function Comm.SendPayload(payload, prio)
  for name, r in pairs(roster) do
    if BNSendGameData and r.gid then
      enqueue("bn", prio, { target = r.gid, payload = payload })
    end
    if r.faction == ns.myFaction and C_ChatInfo and C_ChatInfo.SendAddonMessage then
      enqueue("whisper", prio, { target = name, payload = payload })
    end
  end
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
  ns.Events.Apply(msg, false)
  return sender
end

ns.On("BN_CHAT_MSG_ADDON", function(prefix, text, _, senderID)
  if issecret(prefix) or prefix ~= ns.PREFIX or issecret(senderID) then return end
  local g = C_BattleNet.GetGameAccountInfoByID(senderID)
  if not (g and g.characterName) then
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
  local name = ns.CleanName(g.characterName)
  if not name then return end
  if Comm.GroupActive() then
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
