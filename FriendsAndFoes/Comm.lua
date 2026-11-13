local _, ns = ...
local issecret = ns.issecret

local Comm = {}
ns.Comm = Comm

local roster = {} -- characterName -> { gid = gameAccountID, faction = "Horde"|"Alliance" }
Comm.roster = roster

local SCHEMA = {
  LVL  = { "level" },
  LOOT = { "link", "source" },
  GEAR = { "link" },
  ATK  = { "enc", "zone", "attackers" },
  DIE  = { "zone", "killer", "conf", "assists" },
  KILL = { "victim", "vclass", "vlevel", "zone" },
}
Comm.SCHEMA = SCHEMA

---------------------------------------------------------------------------
-- wire format: 1 \t KIND \t ID \t class \t level \t fields...
---------------------------------------------------------------------------
local function clean(v)
  if v == nil then return "" end
  return (tostring(v):gsub("\t", " "))
end

function Comm.Encode(msg)
  local parts = { "1", msg.kind, msg.id, clean(msg.class), clean(msg.level) }
  for _, field in ipairs(SCHEMA[msg.kind]) do parts[#parts + 1] = clean(msg.f[field]) end
  return table.concat(parts, "\t")
end

function Comm.Decode(text)
  local p = ns.Split(text, "\t")
  if p[1] ~= "1" then return nil end
  local schema = SCHEMA[p[2]]
  if not schema or not p[3] or p[3] == "" then return nil end
  local msg = { kind = p[2], id = p[3], class = p[4], level = tonumber(p[5]), f = {} }
  for i, field in ipairs(schema) do msg.f[field] = p[5 + i] or "" end
  return msg
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
        and ns.NormRealm(g.realmName) == myRealm and g.characterName ~= ns.me then
        roster[ns.StripRealm(g.characterName)] = { gid = g.gameAccountID, faction = g.factionName }
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

local function isFriend(name)
  if roster[name] then return true end
  if GetTime() - lastRebuild > 10 then Comm.RebuildRoster() end
  return roster[name] ~= nil
end

---------------------------------------------------------------------------
-- send
---------------------------------------------------------------------------
function Comm.Broadcast(msg)
  local payload = Comm.Encode(msg)
  if #payload > 255 then
    ns.Debug("TOO-LONG", msg.kind, #payload)
    return
  end
  for name, r in pairs(roster) do
    if BNSendGameData and r.gid then
      ns.Try("bn-send", BNSendGameData, r.gid, ns.PREFIX, payload)
    end
    if r.faction == ns.myFaction and C_ChatInfo and C_ChatInfo.SendAddonMessage then
      ns.Try("whisper-send", C_ChatInfo.SendAddonMessage, ns.PREFIX, payload, "WHISPER", name)
    end
  end
  ns.Debug("SEND", msg.kind, msg.id)
end

---------------------------------------------------------------------------
-- receive (both routes, deduplicated)
---------------------------------------------------------------------------
local seen, seenCount = {}, 0

local function accept(text, sender, via)
  if issecret(text) or type(text) ~= "string" then return end
  local msg = Comm.Decode(text)
  if not msg then return end
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
  ns.Debug("RECV", via, sender, msg.kind, msg.id)
  ns.Events.Apply(msg, false)
end

ns.On("BN_CHAT_MSG_ADDON", function(prefix, text, _, senderID)
  if issecret(prefix) or prefix ~= ns.PREFIX or issecret(senderID) then return end
  local g = C_BattleNet.GetGameAccountInfoByID(senderID)
  if not (g and g.characterName and g.realmName) then return end
  if ns.NormRealm(g.realmName) ~= ns.NormRealm(ns.realm) then return end
  ns.SetCap("bnet", "ok")
  accept(text, ns.StripRealm(g.characterName), "bn")
end)

ns.On("CHAT_MSG_ADDON", function(prefix, text, channel, sender)
  if issecret(prefix) or prefix ~= ns.PREFIX then return end
  if issecret(channel) or channel ~= "WHISPER" or issecret(sender) or not sender then return end
  local name = ns.StripRealm(sender)
  if not isFriend(name) then return end
  ns.SetCap("whisper", "ok")
  accept(text, name, "whisper")
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
