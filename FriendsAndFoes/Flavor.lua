local _, ns = ...
local L = ns.L

-- Varied wording for PvP alerts, using history the addon already keeps:
-- repeat killers, death sprees, bad days, kill streaks, revenge on behalf of a friend.
-- Each builder returns title, text, line (the line goes to chat and the Feed).
local Flavor = {}
ns.Flavor = Flavor

local KEEP = 2 * 86400     -- event times kept per player (for "today" and sprees)
local KEEP_MAX = 50
local SPREE = 15 * 60      -- 3+ deaths within this = a spree
local STREAK = 10 * 60     -- 3+ kills within this = a streak (5+ = rampage)

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
  list[#list + 1] = now
  while #list > 0 and (now - list[1] > KEEP or #list > KEEP_MAX) do table.remove(list, 1) end
  return list
end

local function since(list, t)
  local n, first = 0, nil
  for _, x in ipairs(list or {}) do
    if x >= t then
      n = n + 1
      first = first or x
    end
  end
  return n, first
end

local function midnight()
  local t = date("*t")
  t.hour, t.min, t.sec = 0, 0, 0
  return time(t)
end

local function minutesSince(t) return math.max(1, math.floor((time() - t) / 60 + 0.5)) end

local function join(parts) return table.concat(parts, " - ") end

-- "a spree in the last 15 min" or "the Nth today", for deaths or kills
local function burst(list, window, minBurst, burstFmt, bigFmt, todayFmt, minToday)
  local n, first = since(list, time() - window)
  if n >= minBurst then
    return ((bigFmt and n >= 5) and bigFmt or burstFmt):format(n, minutesSince(first))
  end
  local today = since(list, midnight())
  if today >= minToday then return todayFmt:format(Flavor.Ordinal(today)) end
end

---------------------------------------------------------------------------
-- died: victim p (friend or you), who = coloured victim, by = coloured killer or nil,
-- h = killer's hitlist entry or nil
---------------------------------------------------------------------------
function Flavor.Died(p, who, by, h, zone)
  p.deathTimes = stamp(p.deathTimes)
  local n
  if h then
    h.kv = h.kv or {}
    h.kv[p.name] = (h.kv[p.name] or 0) + 1
    n = h.kv[p.name]
  end

  local title, detail
  if not by then
    title = pick(L.DIED_UNKNOWN):format(who)
  elseif on() and n and n >= 10 then
    title, detail = L.DIED_NEMESIS:format(who, by), L.NTH_TIME:format(Flavor.Ordinal(n))
  elseif on() and n and n >= 5 then
    title, detail = L.DIED_NUMBER:format(by, who), L.NTH_TIME:format(Flavor.Ordinal(n))
  elseif on() and n and n >= 2 then
    title, detail = L.DIED_AGAIN:format(by, who), L.NTH_TIME:format(Flavor.Ordinal(n))
  else
    title = pick(L.DIED):format(who, by)
  end

  local parts = {}
  if detail then parts[#parts + 1] = detail end
  local extra = on() and burst(p.deathTimes, SPREE, 3, L.SPREE_DEATHS, nil, L.DEATHS_TODAY, 3)
  if extra then parts[#parts + 1] = extra end
  parts[#parts + 1] = L.IN_ZONE:format(zone)
  local text = join(parts)
  return title, text, title .. " (" .. text .. ")"
end

---------------------------------------------------------------------------
-- kill: killer p, who = coloured killer, v = coloured victim, e = victim's player record,
-- hit = victim's hitlist entry (if revenge), revenge = boolean
---------------------------------------------------------------------------
function Flavor.Kill(p, who, v, e, hit, revenge, zone)
  p.killTimes = stamp(p.killTimes)
  e.kb = e.kb or {}
  e.kb[p.name] = (e.kb[p.name] or 0) + 1
  local n = e.kb[p.name]

  local title, detail
  if revenge then
    local avenged = {}
    for victim in pairs(hit and hit.victims or {}) do
      if victim ~= p.name then
        local rec = ns.Data.FindPlayer(victim)
        avenged[#avenged + 1] = ns.ClassColored(victim, rec and rec.class)
      end
    end
    table.sort(avenged)
    if on() and #avenged > 0 then
      title = L.KILL_AVENGED:format(who, ns.JoinNames(avenged), v)
    else
      title = L.KILL_REVENGE:format(who, v)
    end
  elseif on() and n >= 3 then
    title, detail = L.KILL_OWNS:format(who, v), L.NTH_KILL_ON:format(Flavor.Ordinal(n))
  else
    title = pick(L.KILL):format(who, v)
  end

  local parts = {}
  if detail then parts[#parts + 1] = detail end
  local extra = on() and burst(p.killTimes, STREAK, 3, L.STREAK, L.RAMPAGE, L.KILLS_TODAY, 5)
  if extra then parts[#parts + 1] = extra end
  parts[#parts + 1] = L.IN_ZONE:format(zone)
  local text = join(parts)
  return title, text, title .. " (" .. text .. ")"
end

---------------------------------------------------------------------------
-- attacked: victim p, who = coloured victim, by = coloured attacker list,
-- attackers = decoded units (to look up past kills on this friend)
---------------------------------------------------------------------------
function Flavor.Attacked(p, who, by, attackers, zone)
  local title = pick(L.ATTACKED):format(who)
  local parts = { L.ATTACKED_BY:format(by) }
  if on() then
    for _, u in ipairs(attackers) do
      local h = u.name and ns.Data.FindHit(u.name)
      local n = h and h.kv and h.kv[p.name]
      if n and n >= 1 then
        parts[#parts + 1] = L.ATTACKER_HISTORY:format(ns.ClassColored(u.name, u.class), n)
        break
      end
    end
  end
  parts[#parts + 1] = L.IN_ZONE:format(zone)
  local text = join(parts)
  return title, text, title .. " (" .. text .. ")"
end
