local addonName, ns = ...

ns.VERSION = "0.1.0"
ns.PREFIX = "FNF1"

local issecret = issecretvalue or function() return false end
ns.issecret = issecret

---------------------------------------------------------------------------
-- defaults
---------------------------------------------------------------------------
local DEFAULTS = {
  share = { level = true, loot = true, gear = true, pvp = true },
  toast = { level = true, loot = true, gear = true, attacked = true, died = true, kill = true, sighting = true },
  sound = { enabled = true, pvp = true, progress = true, sighting = true },
  minimap = { hide = false, angle = 210 },
  anchor = { point = "TOP", x = 0, y = -140 },
  debug = false,
}

local function fillDefaults(dst, src)
  for k, v in pairs(src) do
    if type(v) == "table" then
      if type(dst[k]) ~= "table" then dst[k] = {} end
      fillDefaults(dst[k], v)
    elseif dst[k] == nil then
      dst[k] = v
    end
  end
end

function ns.S() return FriendsAndFoesDB.settings end

---------------------------------------------------------------------------
-- debug log + error containment
---------------------------------------------------------------------------
ns.errors = 0

local function str(v)
  if issecret(v) then return "<SECRET>" end
  return tostring(v)
end

function ns.Debug(tag, ...)
  local db = FriendsAndFoesDB
  if not (db and db.settings and db.settings.debug and db.debugLog) then return end
  local parts = {}
  for i = 1, select("#", ...) do parts[i] = str((select(i, ...))) end
  local log = db.debugLog
  log[#log + 1] = date("%Y-%m-%d %H:%M:%S") .. " [" .. tag .. "] " .. table.concat(parts, " | ")
  if #log > 5000 then table.remove(log, 1) end
end

function ns.Try(tag, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then
    ns.errors = ns.errors + 1
    ns.lastError = str(err)
    ns.Debug("ERR:" .. tag, err)
  end
  return ok
end

-- capability tracking: "untested" | "ok" | "secret" | "missing"
ns.caps = {
  bnet = "untested", whisper = "untested",
  enemyDetect = "untested", targeting = "untested", unitNames = "untested",
  deathRecap = "untested", honor = "untested",
}

function ns.SetCap(key, value)
  if ns.caps[key] == "ok" and value ~= "ok" then return end
  if ns.caps[key] ~= value then
    ns.caps[key] = value
    ns.Debug("CAP", key, value)
  end
end

---------------------------------------------------------------------------
-- event dispatch
---------------------------------------------------------------------------
local frame = CreateFrame("Frame")
local handlers = {}

function ns.On(event, fn)
  local list = handlers[event]
  if not list then
    list = {}
    handlers[event] = list
    if not pcall(frame.RegisterEvent, frame, event) then ns.Debug("REG-FAIL", event) end
  end
  list[#list + 1] = fn
end

frame:SetScript("OnEvent", function(_, event, ...)
  local list = handlers[event]
  if not list then return end
  for i = 1, #list do ns.Try(event, list[i], ...) end
end)

function ns.OnUnit(event, unit, fn)
  local f = CreateFrame("Frame")
  if not pcall(f.RegisterUnitEvent, f, event, unit) then
    ns.Debug("REG-FAIL", event, unit)
    return
  end
  f:SetScript("OnEvent", function(_, _, ...) ns.Try(event, fn, ...) end)
end

local readyCallbacks = {}
function ns.OnReady(fn) readyCallbacks[#readyCallbacks + 1] = fn end

ns.On("ADDON_LOADED", function(name)
  if name ~= addonName then return end
  FriendsAndFoesDB = FriendsAndFoesDB or {}
  local db = FriendsAndFoesDB
  db.settings = db.settings or {}
  fillDefaults(db.settings, DEFAULTS)
  db.realms = db.realms or {}
  db.debugLog = db.debugLog or {}
  FriendsAndFoesCharDB = FriendsAndFoesCharDB or {}
  FriendsAndFoesCharDB.equipped = FriendsAndFoesCharDB.equipped or {}
end)

ns.On("PLAYER_LOGIN", function()
  ns.me = UnitName("player")
  ns.myFaction = UnitFactionGroup("player")
  ns.realm = GetRealmName()
  ns.Debug("LOGIN", ns.VERSION, select(4, GetBuildInfo()), ns.realm, ns.me, ns.myFaction)
  for i = 1, #readyCallbacks do ns.Try("ready", readyCallbacks[i]) end
end)

---------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------
function ns.Split(s, sep)
  local out, start = {}, 1
  while true do
    local i = string.find(s, sep, start, true)
    if not i then
      out[#out + 1] = s:sub(start)
      return out
    end
    out[#out + 1] = s:sub(start, i - 1)
    start = i + #sep
  end
end

function ns.NormRealm(s)
  if not s or issecret(s) then return "" end
  return (s:gsub("[%s%-']", "")):lower()
end

function ns.StripRealm(name)
  if not name then return nil end
  return name:match("^([^%-]+)") or name
end

-- Turns a Blizzard format string ("You create: %s.") into an anchored Lua pattern.
function ns.ToPattern(fmt)
  if type(fmt) ~= "string" then return nil end
  local p = fmt:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")
  p = p:gsub("%%s", "(.+)")
  p = p:gsub("%%d", "(%%d+)")
  return "^" .. p
end

function ns.ClassColored(name, class)
  if not name then return "?" end
  local c = class and class ~= "" and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
  if c and c.colorStr then return "|c" .. c.colorStr .. name .. "|r" end
  return name
end

function ns.JoinNames(list)
  local n = #list
  if n == 0 then return "" end
  if n == 1 then return list[1] end
  if n == 2 then return list[1] .. " and " .. list[2] end
  if n == 3 then return list[1] .. ", " .. list[2] .. " and " .. list[3] end
  return list[1] .. ", " .. list[2] .. " and " .. (n - 2) .. " others"
end

function ns.Ago(t)
  if not t then return "never" end
  local d = time() - t
  if d < 60 then return "just now" end
  if d < 3600 then return math.floor(d / 60) .. "m ago" end
  if d < 86400 then return math.floor(d / 3600) .. "h ago" end
  return math.floor(d / 86400) .. "d ago"
end

local idCounter = 0
function ns.NewId()
  idCounter = idCounter + 1
  return string.format("%x%x", time() % 0x1000000, idCounter)
end

-- player-ish units travel as "name:CLASS:level", lists joined with ";"
function ns.EncodeUnit(u)
  if not u then return "" end
  return (u.name or "") .. ":" .. (u.class or "") .. ":" .. (u.level or "")
end

function ns.DecodeUnit(s)
  if not s or s == "" then return nil end
  local p = ns.Split(s, ":")
  return { name = (p[1] ~= "" and p[1]) or nil, class = (p[2] ~= "" and p[2]) or nil, level = tonumber(p[3]) }
end

function ns.EncodeUnits(list, max)
  local out = {}
  for i, u in ipairs(list) do
    if i > (max or 4) then break end
    out[#out + 1] = ns.EncodeUnit(u)
  end
  return table.concat(out, ";")
end

function ns.DecodeUnits(s)
  local out = {}
  if s and s ~= "" then
    for _, part in ipairs(ns.Split(s, ";")) do
      local u = ns.DecodeUnit(part)
      if u then out[#out + 1] = u end
    end
  end
  return out
end

function ns.PrintStatus()
  local n = 0
  for _ in pairs(ns.Comm.roster) do n = n + 1 end
  print("|cff33ff99" .. ns.L.ADDON .. "|r " .. ns.VERSION .. " - friends online on realm: " .. n)
  for k, v in pairs(ns.caps) do print("  " .. k .. ": " .. v) end
  print("  errors caught: " .. ns.errors .. (ns.lastError and (" (last: " .. ns.lastError .. ")") or ""))
end
