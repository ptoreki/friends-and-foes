local addonName, ns = ...

ns.VERSION = "0.9.1"
ns.PROTOCOL = 3
ns.PREFIX = "FNF1"
ns.MILESTONE_LEVEL = 60 -- reaching this level always toasts

local issecret = issecretvalue or function() return false end
ns.issecret = issecret

---------------------------------------------------------------------------
-- defaults
---------------------------------------------------------------------------
local DEFAULTS = {
  -- where: zone, AFK, in a fight; relay: friends may pass your events on to your other friends
  share = { level = true, loot = true, gear = true, pvp = true, where = true, relay = true },
  -- how each kind shows: "toast" | "chat" | "off"
  show = { level = "toast", loot = "toast", gear = "toast", attacked = "toast", engage = "toast", died = "toast", kill = "toast", sighting = "toast", share = "chat" },
  milestones = true, -- level 60, looted epic BoE, revenge and kill streaks always pop up as a toast
  levelEvery = 1,    -- show friends' level-ups: every level (1), every 5, every 10, or only 60
  gearMin = 3,       -- "new gear" alerts from this quality up: 3 = blue, 4 = epic
  toastGrow = "down", -- toasts stack "down" or "up" from their position
  toastMax = 2,      -- toasts on screen at once (1-4)
  chatFrame = 1,
  nearbyOnly = false, -- true: fights outside your zone become chat lines
  flavor = true, -- varied wording: repeat killers, sprees, streaks, revenge for a friend
  theme = "minimal", -- toast look: "minimal" | "achievement"
  toastScale = 1,    -- toast size (0.7 - 1.5)
  toastDuration = 5, -- seconds a toast stays (PvP toasts 2 longer)
  weekly = true,     -- weekly PvP summary in chat
  -- which sound each event plays ("default" = the built-in choice for that kind of event)
  soundPick = { attacked = "alarm", engage = "default", died = "raidwarning", kill = "levelup", sighting = "mapping",
    level = "default", loot = "default", gear = "default", share = "default" },
  mark = true,        -- skull next to hitlist players' nameplates
  markTooltip = true, -- hitlist record in hitlist players' tooltips
  forgetAfter = 0, -- days unseen before a hitlist entry (without a note) is removed; 0 = never
  -- sound per kind (played whenever that kind is shown, toast or chat). Milestones chime anyway.
  sound = { enabled = true, ui = true, level = false, loot = true, gear = true, attacked = true, engage = false, died = true, kill = true, sighting = true, share = false },
  dnd = { combat = false },
  -- alerts while you're in an instance: "show" | "hold" (until you're out) | "chat" | "off"
  where = { party = "hold", raid = "hold", pvp = "hold" },
  -- where your own PvP (attacks, deaths, kills, sightings) is tracked
  track = { world = true, pvp = false },
  minimap = { hide = false, angle = 210 }, -- hidden by default where the minimap addon menu exists
  anchor = { point = "TOP", x = 0, y = -140 },
  debug = false,
}
ns.DEFAULTS = DEFAULTS

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

-- an item link's quality (2 green, 3 blue, 4 epic...), or nil if it can't be told
local QUALITY_COLOR = { ["9d9d9d"] = 0, ["ffffff"] = 1, ["1eff00"] = 2, ["0070dd"] = 3, ["a335ee"] = 4,
  ["ff8000"] = 5, ["e6cc80"] = 6, ["00ccff"] = 7 }
function ns.ItemQuality(link)
  if type(link) ~= "string" then return nil end
  local q = link:match("|cnIQ(%d):")
  if q then return tonumber(q) end
  local color = link:match("|cff(%x%x%x%x%x%x)")
  return color and QUALITY_COLOR[color:lower()] or nil
end

-- a count for display: a whole number, never negative and never "-0"
function ns.Count(v)
  v = tonumber(v)
  if not v or v ~= v or v <= 0 then return 0 end -- also turns -0 (and NaN) into 0
  return math.floor(v)
end

-- text without colour codes, links or inline textures (for logs and searching)
function ns.Plain(s)
  if type(s) ~= "string" then return tostring(s) end
  return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", ""))
end

-- where you are: "world", "party" (dungeon or scenario), "raid", "pvp" (battleground),
-- or "unknown" if the game won't say. Forever has no arenas; one would count as a battleground.
function ns.InstanceType()
  local inInstance, kind = IsInInstance()
  if issecret(inInstance) or issecret(kind) then return "unknown" end
  if not inInstance then return "world" end
  if kind == "scenario" or kind == nil or kind == "none" then return "party" end
  if kind == "arena" then return "pvp" end
  return kind
end

---------------------------------------------------------------------------
-- debug log + error containment
---------------------------------------------------------------------------
ns.errors = 0
local ERROR_LOG_MAX = 50
-- The debug log is saved to disk, so its size costs load/logout time. Keep the newest
-- DEBUG_LOG_MAX lines, trimming in batches (shifting a full array per line is O(n)).
local DEBUG_LOG_MAX, DEBUG_LOG_SLACK = 2000, 250
local DEBUG_AUTO_OFF = 7 * 86400

local function trimLog(log, max)
  local n = #log
  if n <= max then return end
  local drop = n - max
  for i = 1, max do log[i] = log[i + drop] end
  for i = max + 1, n do log[i] = nil end
end

-- turn debug logging on/off; remembers when it was turned on so it can switch itself off
function ns.SetDebug(on)
  local s = FriendsAndFoesDB.settings
  s.debug = on and true or false
  s.debugSince = on and time() or nil
end

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
  if #log > DEBUG_LOG_MAX + DEBUG_LOG_SLACK then trimLog(log, DEBUG_LOG_MAX) end
end

-- Errors are always kept (last 50), even with debug logging off.
local function recordError(tag, err)
  ns.errors = ns.errors + 1
  ns.lastError = str(err)
  local db = FriendsAndFoesDB
  if db and db.errorLog then
    local log = db.errorLog
    log[#log + 1] = date("%Y-%m-%d %H:%M:%S") .. " [" .. tag .. "] " .. ns.lastError
    while #log > ERROR_LOG_MAX do table.remove(log, 1) end
  end
  ns.Debug("ERR:" .. tag, err)
end

function ns.Try(tag, fn, ...)
  local ok, err = pcall(fn, ...)
  if not ok then recordError(tag, err) end
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
    if FriendsAndFoesDB then FriendsAndFoesDB.caps = ns.caps end -- saved, so reports show it
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

-- with debug logging on, any handler that takes longer than SLOW_MS is logged as [SLOW], so a
-- stall (e.g. during a loading screen) can be traced to us or ruled out
local SLOW_MS = 20
local function debugging()
  local db = FriendsAndFoesDB
  return db and db.settings and db.settings.debug
end

frame:SetScript("OnEvent", function(_, event, ...)
  local list = handlers[event]
  if not list then return end
  local clock = debugging() and debugprofilestop
  for i = 1, #list do
    local t0 = clock and clock()
    ns.Try(event, list[i], ...)
    if t0 then
      local ms = clock() - t0
      if ms > SLOW_MS then ns.Debug("SLOW", event, i, string.format("%.0f ms", ms)) end
    end
  end
end)

function ns.OnUnit(event, unit, fn)
  local f = CreateFrame("Frame")
  if not pcall(f.RegisterUnitEvent, f, event, unit) then
    ns.Debug("REG-FAIL", event, unit)
    return
  end
  f:SetScript("OnEvent", function(_, _, ...) ns.Try(event, fn, ...) end)
end

-- loading screens in the debug log, to line up with anything odd that happens around them
ns.On("LOADING_SCREEN_ENABLED", function() if debugging() then ns.Debug("LOADING", "start") end end)
ns.On("LOADING_SCREEN_DISABLED", function() if debugging() then ns.Debug("LOADING", "end") end end)

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
  db.errorLog = db.errorLog or {}
  FriendsAndFoesCharDB = FriendsAndFoesCharDB or {}
  FriendsAndFoesCharDB.equipped = FriendsAndFoesCharDB.equipped or {}
  -- older saved data brought up to date, step by step (Saved.lua)
  ns.Saved.Upgrade(db)
end)

ns.On("PLAYER_LOGIN", function()
  ns.me = ns.CleanName(UnitName("player")) or "?"
  ns.myFaction = UnitFactionGroup("player")
  ns.realm = GetRealmName()
  FriendsAndFoesDB.caps = ns.caps
  local s = FriendsAndFoesDB.settings
  if s.debug then
    s.debugSince = s.debugSince or time()
    if time() - s.debugSince > DEBUG_AUTO_OFF then
      ns.SetDebug(false)
      print("|cff33ff99" .. ns.L.ADDON .. "|r " .. ns.L.DEBUG_AUTO_OFF)
    end
  end
  trimLog(FriendsAndFoesDB.debugLog, DEBUG_LOG_MAX)
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

-- WoW Forever: every character has a first name and a surname, and only the PAIR is unique
-- (region-wide). First names are shared. UnitName returns (first, surname) where retail returns
-- (name, realm); addon whispers arrive from "First Last"; the death recap says "First Last";
-- "First-Last" also addresses a character. Neither part may contain spaces or hyphens.
-- So the canonical player key is "First Last". A bare "First" (e.g. from an older client) is
-- kept as-is and resolved against known full names by Data.
function ns.ForeverNames()
  if RegionalUniqueNamesEnabled then
    local ok, v = pcall(RegionalUniqueNamesEnabled)
    if ok and not issecret(v) and v ~= nil then return v and true or false end
  end
  return true -- this addon only targets Forever (interface 16001)
end

-- CleanName(name [, second]) -> "First Last" / "First" / nil.
-- `second` is UnitName's second return: the surname on Forever, the realm elsewhere.
-- Accepts "First Last", "First-Last", "First Last-Realm"; trailing parts beyond the surname are dropped.
function ns.CleanName(name, second)
  if not name or issecret(name) or type(name) ~= "string" then return nil end
  local forever = ns.ForeverNames()
  local words = {}
  for w in name:gmatch("[^%s%-]+") do words[#words + 1] = w end
  if #words == 0 then return nil end
  if not forever then return words[1] end -- retail: the rest is a realm
  if not words[2] and second and not issecret(second) and type(second) == "string" then
    words[2] = second:match("^[%s]*([^%s%-]+)")
  end
  if words[2] then return words[1] .. " " .. words[2] end
  return words[1]
end

function ns.FirstName(name)
  return name and name:match("^(%S+)")
end

-- Turns a Blizzard format string ("You create: %s.") into an anchored Lua pattern.
function ns.ToPattern(fmt)
  if type(fmt) ~= "string" then return nil end
  local p = fmt:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")
  p = p:gsub("%%s", "(.+)")
  p = p:gsub("%%d", "(%%d+)")
  return "^" .. p
end

-- a name in its class colour. If the class isn't given, use what we know about that player.
function ns.ClassColored(name, class)
  if not name then return "?" end
  if (not class or class == "") and ns.Data and FriendsAndFoesDB and FriendsAndFoesDB.realms then
    local ok, view = pcall(ns.Data.ViewRealm) -- the data on screen (real or simulation)
    local rec = ok and view and view.players[name]
    if rec and rec.class then class = rec.class end
  end
  local c = class and class ~= "" and RAID_CLASS_COLORS and RAID_CLASS_COLORS[class]
  if not c then return name end
  if c.colorStr then return "|c" .. c.colorStr .. name .. "|r" end
  if c.r and c.g and c.b then
    return ("|cff%02x%02x%02x%s|r"):format(math.floor(c.r * 255), math.floor(c.g * 255), math.floor(c.b * 255), name)
  end
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

-- the time an event happened: now, or earlier for a friend's event replayed after you were offline
function ns.Now() return ns.eventTime or time() end

function ns.Ago(t)
  if not t then return "never" end
  local d = time() - t
  if d < 60 then return "just now" end
  if d < 3600 then return math.floor(d / 60) .. "m ago" end
  if d < 86400 then return math.floor(d / 3600) .. "h ago" end
  return math.floor(d / 86400) .. "d ago"
end

local idCounter = 0
function ns.NewId(sim)
  idCounter = idCounter + 1
  return (sim and "S" or "") .. string.format("%x%x", time() % 0x1000000, idCounter)
end

-- "1.2.10" > "1.2.9"
function ns.VersionNewer(a, b)
  if not a or not b then return false end
  local pa, pb = ns.Split(a, "."), ns.Split(b, ".")
  for i = 1, math.max(#pa, #pb) do
    local x, y = tonumber(pa[i]) or 0, tonumber(pb[i]) or 0
    if x ~= y then return x > y end
  end
  return false
end

-- player-ish units travel as "name:CLASS:level:guild", lists joined with ";"
local function field(v)
  if v == nil then return "" end
  return (tostring(v):gsub("[:;\t]", " "))
end

function ns.EncodeUnit(u)
  if not u then return "" end
  return field(u.name) .. ":" .. field(u.class) .. ":" .. field(u.level) .. ":" .. field(u.guild)
end

function ns.DecodeUnit(s)
  if not s or s == "" then return nil end
  local p = ns.Split(s, ":")
  return {
    name = ns.CleanName(p[1]),
    class = (p[2] and p[2] ~= "") and p[2] or nil,
    level = tonumber(p[3]),
    guild = (p[4] and p[4] ~= "") and p[4] or nil,
  }
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
  ns.Comm.RebuildRoster()
  local names = ns.Comm.RosterNames()
  print("|cff33ff99" .. ns.L.ADDON .. "|r " .. ns.VERSION .. " - you: " .. tostring(ns.me) .. " (server " .. tostring(ns.realm) .. ")")
  print("  friends online: " .. #names .. (#names > 0 and (" (" .. table.concat(names, ", ") .. ")") or "")
    .. ", messages queued: " .. ns.Comm.QueuedCount())
  print("  alerts: " .. (ns.Comm.GroupActive() and "your alert list only (/fnf alerts)" or "every friend (/fnf alerts to limit)"))
  for k, v in pairs(ns.caps) do print("  " .. k .. ": " .. v) end
  print("  " .. (ns.Profile.FilterReady() and ns.L.FILTER_STATUS_ON or ns.L.FILTER_STATUS_OFF))
  print("  errors caught: " .. ns.errors .. (ns.lastError and (" (last: " .. ns.lastError .. ")") or ""))
end
