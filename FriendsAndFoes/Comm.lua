local _, ns = ...
local issecret = ns.issecret

local Comm = {}
ns.Comm = Comm

-- name -> { gid = gameAccountID, faction = "Horde"|"Alliance" }
-- name is "First Last" once known (learned from their messages), else whatever Battle.net gives.
local roster = {}
Comm.roster = roster
local fullByGid = {} -- gameAccountID -> "First Last", learned from received headers

local MAX_PAYLOAD = 255

local SCHEMA = {
  LVL  = { "level" },
  LOOT = { "link", "source" },
  GEAR = { "link", "count" },
  ATK  = { "enc", "zone", "attackers" },
  DIE  = { "zone", "killer", "conf", "assists" },
  KILL = { "victim", "vclass", "vlevel", "vguild", "zone" },
  HIT  = { "share", "entries" },
}
Comm.SCHEMA = SCHEMA

local PRIORITY_OF = { ATK = "high", DIE = "high", KILL = "high", LVL = "normal", LOOT = "normal", GEAR = "normal", HIT = "bulk" }
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

function Comm.RebuildRoster()
  lastRebuild = GetTime()
  wipe(roster)
  if not (BNGetNumFriends and C_BattleNet and C_BattleNet.GetFriendNumGameAccounts and C_BattleNet.GetFriendGameAccountInfo) then
    ns.SetCap("bnet", "missing")
    return
  end
  local myRealm = ns.NormRealm(ns.realm)
  local wowClient = BNET_CLIENT_WOW or "WoW"
  local n = BNGetNumFriends() or 0
  for i = 1, n do
    for j = 1, (C_BattleNet.GetFriendNumGameAccounts(i) or 0) do
      local g = C_BattleNet.GetFriendGameAccountInfo(i, j)
      if g and g.isOnline and g.clientProgram == wowClient and g.characterName and g.realmName
        and ns.NormRealm(g.realmName) == myRealm then
        local name = fullByGid[g.gameAccountID] or ns.CleanName(g.characterName)
        if name and name ~= ns.me then
          roster[name] = { gid = g.gameAccountID, faction = g.factionName }
          ns.Debug("ROSTER+", name, g.characterName)
        end
      end
    end
  end
  ns.Debug("ROSTER", "rebuilt")
end

local pending = false
function Comm.QueueRoster()
  if pending then return end
  pending = true
  C_Timer.After(2, function()
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
  if key and key ~= full and roster[key] then
    roster[full] = roster[key]
    roster[key] = nil
  end
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

local function enqueue(routeName, prio, item)
  local route = routes[routeName]
  local q = route.q[prio]
  q[#q + 1] = item
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

ns.OnReady(function()
  C_Timer.NewTicker(0.25, function() ns.Try("pump", pump) end)
end)

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
  ns.Debug("SEND", msg.kind, msg.id)
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
  if not (g and g.characterName and g.realmName) then
    ns.Debug("BN-DROP", "no game info", senderID)
    return
  end
  if ns.NormRealm(g.realmName) ~= ns.NormRealm(ns.realm) then
    ns.Debug("BN-DROP", "realm", g.realmName, ns.realm)
    return
  end
  local name = ns.CleanName(g.characterName)
  if not name then return end
  ns.SetCap("bnet", "ok")
  local sender = accept(text, name, "bn")
  if sender then learnFull(rosterFind(name), sender, g.gameAccountID) end
end)

ns.On("CHAT_MSG_ADDON", function(prefix, text, channel, sender)
  if issecret(prefix) or prefix ~= ns.PREFIX then return end
  if issecret(channel) or channel ~= "WHISPER" then return end
  local name = ns.CleanName(sender)
  local key = findFriend(name)
  if not key then
    ns.Debug("WHISPER-DROP", "not a friend", sender)
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
