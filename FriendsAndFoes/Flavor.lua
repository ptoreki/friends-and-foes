local _, ns = ...
local L = ns.L

-- Short PvP lines: who did what, then extras, then where - separated by " · ".
-- With flavor on, wording varies and calls out history the addon already keeps:
-- repeat killers, kill streaks, busy days, revenge on behalf of a friend.
-- Each builder returns title, text, line (the line goes to chat and the Feed).
local Flavor = {}
ns.Flavor = Flavor

local KEEP = 2 * 86400     -- event times kept per player (for "today")
local KEEP_MAX = 50
local SEP = " \194\183 "   -- " · "
Flavor.SEP = SEP

Flavor.random = math.random -- tests replace this

local function on() return ns.S().flavor ~= false end

local function pick(list)
  if type(list) ~= "table" then return list end
  if not on() then return list[1] end
  return list[Flavor.random(#list)]
end

function Flavor.Ordinal(n)
  local suffix = "th"
  local m100 = n % 100
  if m100 < 11 or m100 > 13 then
    local m = n % 10
    if m == 1 then suffix = "st" elseif m == 2 then suffix = "nd" elseif m == 3 then suffix = "rd" end
  end
  return n .. suffix
end

-- append now to a list of times, dropping old ones
local function stamp(list)
  list = type(list) == "table" and list or {}
  local now = time()
  list[#list + 1] = ns.Now()
  table.sort(list)
  while #list > 0 and (now - list[1] > KEEP or #list > KEEP_MAX) do table.remove(list, 1) end
  return list
end

local function since(list, t)
  local n = 0
  for _, x in ipairs(list or {}) do
    if x >= t then n = n + 1 end
  end
  return n
end

local function midnight()
  local t = date("*t")
  t.hour, t.min, t.sec = 0, 0, 0
  return time(t)
end

local function join(parts) return table.concat(parts, SEP) end

-- Where, as short as it stays clear: the subzone if the sender had one ("Tarren Mill"),
-- else the zone. Senders send "Zone (Subzone)"; the hitlist keeps the full text.
function Flavor.Place(zone)
  if type(zone) ~= "string" or zone == "" then return "?" end
  return zone:match("%((.+)%)$") or zone
end

-- "5th today" once there have been at least minToday today
local function today(list, minToday)
  local n = since(list, midnight())
  if n >= minToday then return L.TODAY:format(Flavor.Ordinal(n)) end
end

-- kill streaks: shown from 3 in a row; 5 and 10 are milestones (always a toast)
local STREAK_SHOW = 3
function Flavor.StreakMilestone(n)
  return on() and n ~= nil and (n == 5 or n == 10 or (n > 10 and n % 5 == 0)) or false
end

local function streakText(n)
  if not n or n < STREAK_SHOW then return nil end
  return (Flavor.StreakMilestone(n) and L.STREAK_BIG or L.STREAK):format(n)
end

-- title = who did what; text = extras and place; line (chat/Feed) = both
local function result(title, extra, zone)
  local parts = {}
  if extra then parts[#parts + 1] = extra end
  parts[#parts + 1] = Flavor.Place(zone)
  local text = join(parts)
  return title, text, title .. SEP .. text
end

-- flavor off: who did what, then where - one line, no extras
local function compact(title, zone)
  local line = title .. SEP .. Flavor.Place(zone)
  return line, nil, line
end

---------------------------------------------------------------------------
-- died: victim p (friend or you), who = coloured victim, by = coloured killer or nil,
-- h = killer's hitlist entry or nil
---------------------------------------------------------------------------
function Flavor.Died(p, who, by, h, zone, ended, helpers)
  p.deathTimes = stamp(p.deathTimes)
  local n
  if h then
    h.kv = h.kv or {}
    h.kv[p.name] = (h.kv[p.name] or 0) + 1
    n = h.kv[p.name]
    -- when they last killed this friend (the nemesis tie-break: Profile.NemesisBeats)
    h.kt = type(h.kt) == "table" and h.kt or {}
    h.kt[p.name] = math.max(tonumber(h.kt[p.name]) or 0, ns.Now())
  end
  -- enemies who helped: "(with Kragg Bear)"
  local with = (by and helpers and #helpers > 0) and (" " .. L.WITH_HELPERS:format(ns.JoinNames(helpers))) or ""
  if not on() then
    return compact((by and L.SHORT_DIED:format(who, by) .. with) or L.SHORT_DIED_UNKNOWN:format(who), zone)
  end

  local title
  if not by then
    title = pick(L.DIED_UNKNOWN):format(who)
  elseif n and n >= 10 then
    title = L.DIED_NEMESIS:format(who, by, Flavor.Ordinal(n))
  elseif n and n >= 5 then
    title = L.DIED_NUMBER:format(by, who, Flavor.Ordinal(n))
  elseif n and n >= 2 then
    title = L.DIED_AGAIN:format(by, who, Flavor.Ordinal(n))
  else
    title = pick(L.DIED):format(who, by)
  end
  title = title .. with
  local extra = (ended and ended >= STREAK_SHOW) and L.STREAK_ENDED:format(ended) or today(p.deathTimes, 3)
  return result(title, extra, zone)
end

---------------------------------------------------------------------------
-- kill: killer p, who = coloured killer, v = coloured victim, e = victim's player record,
-- hit = victim's hitlist entry (if revenge), revenge = boolean
---------------------------------------------------------------------------
function Flavor.Kill(p, who, v, e, hit, revenge, zone, streak)
  p.killTimes = stamp(p.killTimes)
  if not v then -- victim unknown
    local title = L.KILL_UNKNOWN:format(who)
    if not on() then return compact(title, zone) end
    return result(title, streakText(streak) or today(p.killTimes, 5), zone)
  end
  e.kb = e.kb or {}
  e.kb[p.name] = (e.kb[p.name] or 0) + 1
  local n = e.kb[p.name]
  if not on() then
    return compact((revenge and L.SHORT_REVENGE or L.SHORT_KILL):format(who, v), zone)
  end

  local title
  if revenge then
    local avenged = {}
    for victim in pairs(hit and hit.victims or {}) do
      if victim ~= p.name then
        local rec = ns.Data.FindPlayer(victim)
        avenged[#avenged + 1] = ns.ClassColored(victim, rec and rec.class)
      end
    end
    table.sort(avenged)
    if #avenged > 0 then
      title = L.KILL_AVENGED:format(who, ns.JoinNames(avenged), v)
    else
      title = L.KILL_REVENGE:format(who, v)
    end
  elseif n >= 3 then
    title = L.KILL_OWNS:format(who, v, Flavor.Ordinal(n))
  else
    title = pick(L.KILL):format(who, v)
  end
  return result(title, streakText(streak) or today(p.killTimes, 5), zone)
end

---------------------------------------------------------------------------
-- attacked: victim p, who = coloured victim, by = coloured attacker list,
-- attackers = decoded units (to look up past kills on this friend)
---------------------------------------------------------------------------
---------------------------------------------------------------------------
-- engage: friend p (who) started a fight with v; h = v's hitlist entry if they're on it
---------------------------------------------------------------------------
function Flavor.Engage(p, who, v, h, zone)
  if not on() then return compact(L.SHORT_ENGAGE:format(who, v), zone) end
  local title = h and L.ENGAGE_HITLIST:format(who, v) or pick(L.ENGAGE):format(who, v)
  return result(title, nil, zone)
end

function Flavor.Attacked(p, who, by, attackers, zone)
  if not on() then return compact(L.SHORT_ATTACKED:format(who, by), zone) end
  local title = pick(L.ATTACKED):format(who, by)
  for _, u in ipairs(attackers) do
    local h = u.name and ns.Data.FindHit(u.name)
    local n = h and h.kv and h.kv[p.name]
    if n and n >= 1 then
      title = title .. " " .. L.ATTACKER_HISTORY:format(n)
      break
    end
  end
  return result(title, nil, zone)
end
