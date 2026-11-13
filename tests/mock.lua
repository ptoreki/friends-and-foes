-- Minimal WoW API mock for running Friends & Foes logic outside the game.
FRAMES = {}
local now = 1000
function GetTime() return now end
function ADVANCE(s) now = now + s end
time = function() return os.time() end
date = os.date

local function newObj()
  local o = { _scripts = {}, _events = {}, _shown = false }
  FRAMES[#FRAMES + 1] = o
  return setmetatable(o, { __index = function(t, k)
    if type(k) ~= "string" or not k:find("^%u") then return nil end -- only methods are auto-provided
    if k == "SetScript" then return function(self, n, f) self._scripts[n] = f end end
    if k == "GetScript" then return function(self, n) return self._scripts[n] end end
    if k == "RegisterEvent" then return function(self, e) self._events[e] = true end end
    if k == "RegisterUnitEvent" then return function(self, e) self._events[e] = true end end
    if k == "Show" then return function(self) self._shown = true end end
    if k == "Hide" then return function(self) self._shown = false end end
    if k == "SetShown" then return function(self, v) self._shown = v and true or false end end
    if k == "IsShown" then return function(self) return self._shown end end
    if k == "SetText" then return function(self, v) self._text = v end end
    if k == "GetText" then return function(self) return self._text end end
    if k == "GetChecked" then return function(self) return self._checked end end
    if k == "SetChecked" then return function(self, v) self._checked = v end end
    if k:find("^Create") then return function() return newObj() end end
    return function() return nil end
  end })
end
function CreateFrame() return newObj() end
UIParent, Minimap, GameTooltip = newObj(), newObj(), newObj()
Minimap.GetCenter = function() return 0, 0 end

function FIRE(event, ...)
  for _, f in ipairs(FRAMES) do
    if f._events[event] and f._scripts.OnEvent then f._scripts.OnEvent(f, event, ...) end
  end
end

TIMERS = {}
C_Timer = {
  After = function(_, fn) TIMERS[#TIMERS + 1] = fn end,
  NewTicker = function(_, fn) TICKERS = TICKERS or {}; TICKERS[#TICKERS + 1] = fn; return {} end,
}
function RUN_TIMERS()
  for _ = 1, 10 do
    local t = TIMERS; TIMERS = {}
    if #t == 0 then return end
    for _, fn in ipairs(t) do fn() end
  end
end
function RUN_TICKERS(n) for _ = 1, n or 1 do ADVANCE(0.25); for _, fn in ipairs(TICKERS or {}) do fn() end end end

ME, MY_FACTION, MY_REALM = "Testme", "Horde", "Nightslayer"
function UnitName(u) if u == "player" then return ME end end
function UnitFactionGroup(u) if u == "player" then return MY_FACTION end end
function UnitClass(u) if u == "player" then return "Warrior", "WARRIOR" end end
function UnitLevel(u) if u == "player" then return 30 end return 0 end
function UnitExists() return false end
function UnitAffectingCombat() return IN_COMBAT or false end
function UnitInParty() return false end
function UnitInRaid() return nil end
function IsInInstance() return IN_INSTANCE or false, IN_INSTANCE and "party" or "none" end
function GetRealmName() return MY_REALM end
function GetBuildInfo() return "1.60.1", "70338", "", 16001 end
function GetRealZoneText() return "Hillsbrad Foothills" end
function GetSubZoneText() return "Tarren Mill" end
function GetInventoryItemLink() return nil end
function PlaySound(id) SOUNDS_PLAYED = (SOUNDS_PLAYED or 0) + 1 end
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
tinsert = table.insert
UISpecialFrames = {}
SlashCmdList = {}
PRINTED = {}
print = function(...) local t = {...}; for i = 1, #t do t[i] = tostring(t[i]) end; PRINTED[#PRINTED + 1] = table.concat(t, " ") end
RAID_CLASS_COLORS = setmetatable({}, { __index = function() return { colorStr = "ffffffff" } end })
SOUNDKIT = { RAID_WARNING = 8959, READY_CHECK = 8960 }
Enum = { SendAddonMessageResult = { Success = 0, AddonMessageThrottle = 3 } }
BNET_CLIENT_WOW = "WoW"
LOOT_ITEM_SELF = "You receive loot: %s."
LOOT_ITEM_SELF_MULTIPLE = "You receive loot: %sx%d."
LOOT_ITEM_PUSHED_SELF = "You receive item: %s."
LOOT_ITEM_PUSHED_SELF_MULTIPLE = "You receive item: %sx%d."
LOOT_ITEM_CREATED_SELF = "You create: %s."
LOOT_ITEM_CREATED_SELF_MULTIPLE = "You create: %sx%d."
COMBATLOG_HONORGAIN = "%s dies, honorable kill Rank: %s (Estimated Honor Points: %d)"
C_Item = { GetItemInfo = function(link)
  local q = link:find("a335ee") and 4 or 3
  return "Item", link, q, 60, 60, "Weapon", "Sword", 1, "INVTYPE_WEAPON", 135000, 0, 2, 7, 2
end }

-- sync mock: one same-realm Battle.net friend, every send recorded
SENT = {}
FRIENDS_ONLINE = 1
function BNGetNumFriends() return FRIENDS_ONLINE, FRIENDS_ONLINE end
C_BattleNet = {
  GetFriendNumGameAccounts = function() return 1 end,
  GetFriendGameAccountInfo = function() return { isOnline = true, clientProgram = "WoW", characterName = "Buddy", realmName = "Nightslayer", factionName = "Horde", gameAccountID = 77 } end,
  GetGameAccountInfoByID = function(id) return { characterName = "Buddy-Nightslayer", realmName = "Night Slayer" } end,
}
function BNSendGameData(gid, prefix, payload) SENT[#SENT + 1] = { route = "bn", payload = payload } end
C_ChatInfo = {
  RegisterAddonMessagePrefix = function() end,
  SendAddonMessage = function(prefix, payload, chan, target) SENT[#SENT + 1] = { route = "whisper", payload = payload }; return 0 end,
}
