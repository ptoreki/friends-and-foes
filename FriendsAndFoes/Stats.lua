local _, ns = ...
local L = ns.L

-- Your own kill log, level brackets, and the numbers the Stats page (UIStats.lua) shows.
--  * FriendsAndFoesDB.killLog = { { t, c, p, n, vl, ml, z }, ... }, oldest first, at most LOG_MAX
--    (p: this character's time played at the kill, 1.0.2+): t time, c the character (ns.me; entries
--    without one are ignored), n victim's name (nil when unreadable), vl victim's level at the time
--    (nil unknown, -1 skull), ml your level at the time, z zone. Only your own live kills are
--    logged (never a friend's, never a caught-up or replayed one). Account-wide. Never sent.
--    Today / Last 7 days / Last 30 days are counted from this log.
--  * FriendsAndFoesCharDB.brackets[key] = running totals per level bracket (your level at the
--    moment of the event), never trimmed: the log is capped, these are not. All-time numbers are
--    the sum of the brackets. Kill-side totals of 1.0.1 log entries (those with `ml`) are seeded
--    once (FriendsAndFoesCharDB.bracketsSeeded); deaths, lives and time played can't be.
--  * FriendsAndFoesCharDB.bestStreak = this character's longest run of kills without dying (and,
--    per bracket, the best run counted while in it).
local Stats = {}
ns.Stats = Stats

Stats.LOG_MAX = 1000
Stats.TOP_ZONES = 5
Stats.ZONE_CAP = 50 -- zones kept per bracket (the smallest is dropped when full)
Stats.MIN_LEVELS = 5 -- kills with a known, non-skull level before the average level and gap show
Stats.MIN_BUSY = 20 -- logged kills before the busiest weekday and hour show
Stats.WEEK_DAYS, Stats.MONTH_DAYS = 7, 30 -- "Last 7 days" / "Last 30 days" = the last 7 / 30 days

-- level brackets: your level when it happened. 60 and above is one bracket.
Stats.BRACKETS = {
  { key = "u20", lo = 1, hi = 19 }, { key = "20", lo = 20, hi = 29 }, { key = "30", lo = 30, hi = 39 },
  { key = "40", lo = 40, hi = 49 }, { key = "50", lo = 50, hi = 59 }, { key = "60", lo = 60, hi = 999 },
}
function Stats.BracketOf(level)
  level = tonumber(level)
  if not level or level ~= level or level < 1 then return nil end
  for _, b in ipairs(Stats.BRACKETS) do
    if level >= b.lo and level <= b.hi then return b.key end
  end
  return nil
end

-- the level as the log keeps it: nil unknown, -1 skull, else a whole number
local function logLevel(raw)
  local n = tonumber(raw)
  if not n or n ~= n then return nil end
  if n == 0 or n < 0 then return -1 end -- (the wire sends a skull-level enemy as 0)
  return math.floor(n)
end

local function myLevel()
  local ok, lvl = pcall(UnitLevel, "player")
  lvl = ok and not ns.issecret(lvl) and tonumber(lvl) or nil
  return lvl and lvl > 0 and lvl or nil
end

function Stats.List()
  local db = FriendsAndFoesDB
  if type(db.killLog) ~= "table" then db.killLog = {} end
  return db.killLog
end

---------------------------------------------------------------------------
-- level brackets (running totals)
---------------------------------------------------------------------------
local function blank()
  return { kills = 0, deaths = 0, played = 0, lives = 0, lifeSum = 0, lifeMax = 0, bestStreak = 0,
    vlSum = 0, vlN = 0, gapSum = 0, gapN = 0, pkills = 0,
    tiers = { grey = 0, lower = 0, even = 0, higher = 0, skull = 0 }, wday = {}, hour = {}, zones = {} }
end

-- a bracket's totals (made on first use); nil for an unknown key
function Stats.Bracket(key)
  local c = FriendsAndFoesCharDB
  if not (c and key) then return nil end
  c.brackets = c.brackets or {}
  local b = c.brackets[key]
  if not b then b = blank(); c.brackets[key] = b end
  return b
end

local function addZone(map, z)
  if map[z] then map[z] = map[z] + 1 return end
  local n = 0
  for _ in pairs(map) do n = n + 1 end
  if n >= Stats.ZONE_CAP then
    local minK, minV
    for k, v in pairs(map) do
      if not minV or v < minV or (v == minV and k < minK) then minK, minV = k, v end
    end
    map[minK] = nil
  end
  map[z] = 1
end

-- Tier of one kill by level gap, with Bounty.lua's rules (its grey level and level tiers):
-- "skull", "grey", "higher", "even", "lower"; nil when a level is unknown.
function Stats.Tier(e)
  local vl, ml = e.vl, e.ml
  if not vl then return nil end
  if vl < 0 then return "skull" end
  if not ml or ml <= 0 then return nil end
  if vl <= ns.Bounty.GreyLevel(ml) then return "grey" end
  local diff = vl - ml
  if diff >= ns.Bounty.LEVEL_TIERS[2][1] then return "higher" end -- (3+ above)
  if diff >= ns.Bounty.LEVEL_TIERS[3][1] then return "even" end -- (within 2 below)
  return "lower"
end
Stats.TIERS = { "grey", "lower", "even", "higher", "skull" }

-- one kill (a log entry) into a bracket's totals
local function addKill(b, e)
  b.kills = b.kills + 1
  if tonumber(e.p) then b.pkills = b.pkills + 1 end
  if e.vl and e.vl > 0 then
    b.vlSum, b.vlN = b.vlSum + e.vl, b.vlN + 1
    if e.ml and e.ml > 0 then b.gapSum, b.gapN = b.gapSum + (e.vl - e.ml), b.gapN + 1 end
  end
  local tier = Stats.Tier(e)
  if tier then b.tiers[tier] = b.tiers[tier] + 1 end
  local t = tonumber(e.t)
  local d = t and date("*t", t)
  if d then
    b.wday[d.wday] = (b.wday[d.wday] or 0) + 1
    b.hour[d.hour] = (b.hour[d.hour] or 0) + 1
  end
  if e.z then addZone(b.zones, e.z) end
end

-- Once: the kill side of the brackets from this character's 1.0.1 log entries (those that know
-- your level). force: start the kill side over from the log (tests).
function Stats.Seed(force)
  local c = FriendsAndFoesCharDB
  if not c or (c.bracketsSeeded and not force) then return end
  c.bracketsSeeded = true
  if force then
    for _, b in pairs(c.brackets or {}) do
      local fresh = blank()
      for _, k in ipairs({ "kills", "pkills", "vlSum", "vlN", "gapSum", "gapN", "tiers", "wday", "hour", "zones" }) do b[k] = fresh[k] end
    end
  end
  for _, e in ipairs(Stats.List()) do
    local key = e.c == ns.me and Stats.BracketOf(e.ml)
    if key then addKill(Stats.Bracket(key), e) end
  end
end

-- one of your own live kills (victim: name or nil; vlevel: as sent in KILL; zone: text or nil)
function Stats.Log(victim, vlevel, zone)
  if Stats.InInstance() then return end -- (Stats are open-world PvP only: no battleground kills)
  Stats.Seed() -- (before this kill goes in the log, so it isn't counted twice)
  local log = Stats.List()
  local e = { t = ns.Now(), c = ns.me, p = math.floor(Stats.Played()), vl = logLevel(vlevel), ml = myLevel() }
  if type(victim) == "string" and victim ~= "" then e.n = victim end
  if type(zone) == "string" and zone ~= "" and not ns.issecret(zone) then e.z = zone end
  log[#log + 1] = e
  while #log > Stats.LOG_MAX do table.remove(log, 1) end
  local key = Stats.BracketOf(e.ml)
  if key then addKill(Stats.Bracket(key), e) end
end

-- the current run grew to n kills: remember the best one (overall, and in the bracket you're in)
function Stats.NoteStreak(n)
  if Stats.InInstance() then return end
  local c = FriendsAndFoesCharDB
  if n > ns.Count(c.bestStreak) then c.bestStreak = n end
  local key = Stats.BracketOf(myLevel())
  local b = key and Stats.Bracket(key)
  if b and n > b.bestStreak then b.bestStreak = n end
end

-- current run, best run
function Stats.Streaks()
  local cur = ns.Count(FriendsAndFoesCharDB and FriendsAndFoesCharDB.streak)
  return cur, math.max(cur, ns.Count(FriendsAndFoesCharDB and FriendsAndFoesCharDB.bestStreak))
end

---------------------------------------------------------------------------
-- time played (per character) and lives
---------------------------------------------------------------------------
-- FriendsAndFoesCharDB.played = seconds this character has been out in the world (logged in and alive,
-- not AFK, resting, on a flight or in an instance: see aliveNow), counted from
-- the first time 1.0.2 ran (never /played). Time is added from GetTime() deltas, on a 10 s ticker
-- and whenever the state changes (dead, alive, unghost, logout), so a crash loses at most 10 s.
-- Each delta also goes to the bracket of your level at that moment.
-- FriendsAndFoesCharDB.lifeStart = the counter at your last PvP death (nil: the first life, which
-- runs from the counter's start, 0). FriendsAndFoesDB.deathLog = { { t, c, p, k, z }, ... }: time,
-- character, played at the time, killer's name (nil unknown), zone; your own live PvP deaths only.
Stats.MIN_DEATHS = 3 -- PvP deaths before the average life shows
Stats.MIN_PLAYED = 3600 -- seconds played before kills per hour shows
Stats.FLUSH_EVERY = 10

local counting, lastTick = false, nil

-- true only when the game plainly says yes; a missing call, an error or a secret value is "no"
local function yes(fn, ...)
  if not fn then return false end
  local ok, r = pcall(fn, ...)
  return ok and not ns.issecret(r) and r == true
end

-- in a dungeon, raid, battleground or arena: Stats only count the open world
function Stats.InInstance()
  if not IsInInstance then return false end
  local ok, inside = pcall(IsInInstance)
  return ok and not ns.issecret(inside) and inside == true
end

-- Time out in the world: only while you could be ganked. Not counted when dead or a ghost, AFK,
-- resting (an inn or city), on a flight path, or in an instance. Each check is on its own: one that
-- can't be answered doesn't pause anything.
local function aliveNow()
  return not (yes(UnitIsDeadOrGhost, "player") or yes(UnitIsAFK, "player") or yes(IsResting)
    or yes(UnitOnTaxi, "player") or Stats.InInstance())
end

-- add the time since the last look (if we were counting), then start/stop counting by state
local function flush()
  local c = FriendsAndFoesCharDB
  if not c then return end
  local now = GetTime()
  if counting and lastTick then
    local delta = math.max(0, now - lastTick)
    c.played = (tonumber(c.played) or 0) + delta
    local key = Stats.BracketOf(myLevel())
    local b = key and Stats.Bracket(key)
    if b then b.played = b.played + delta end
  end
  counting = aliveNow()
  lastTick = counting and now or nil
end
Stats.Flush = flush

-- seconds not saved yet (counted since the last flush)
local function unflushed() return (counting and lastTick) and math.max(0, GetTime() - lastTick) or 0 end

-- seconds played, including the part not saved yet
function Stats.Played()
  local c = FriendsAndFoesCharDB
  if not c then return 0 end
  return (tonumber(c.played) or 0) + unflushed()
end

ns.OnReady(function()
  FriendsAndFoesCharDB.played = tonumber(FriendsAndFoesCharDB.played) or 0
  counting, lastTick = false, nil
  flush()
  C_Timer.NewTicker(Stats.FLUSH_EVERY, function() ns.Try("played", flush) end)
end)
-- (state changes: dead / alive, AFK, resting, entering an instance, a flight, logout)
for _, ev in ipairs({ "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST", "PLAYER_LOGOUT", "PLAYER_FLAGS_CHANGED",
  "PLAYER_UPDATE_RESTING", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA", "PLAYER_CONTROL_LOST", "PLAYER_CONTROL_GAINED" }) do
  ns.On(ev, function() ns.Try("played", flush) end)
end

-- "45m", "1h 52m", "2d 3h"
function Stats.Duration(sec)
  sec = math.max(0, math.floor(tonumber(sec) or 0))
  if sec >= 86400 then return L.STATS_DUR_DH:format(math.floor(sec / 86400), math.floor(sec % 86400 / 3600)) end
  if sec >= 3600 then return L.STATS_DUR_HM:format(math.floor(sec / 3600), math.floor(sec % 3600 / 60)) end
  return L.STATS_DUR_M:format(math.floor(sec / 60))
end

function Stats.DeathList()
  local db = FriendsAndFoesDB
  if type(db.deathLog) ~= "table" then db.deathLog = {} end
  return db.deathLog
end

-- one of your own live PvP deaths (killer: name or nil). The life that ends here goes into the
-- bracket of your level now.
function Stats.LogDeath(killer, zone)
  if Stats.InInstance() then return end
  flush()
  local c = FriendsAndFoesCharDB
  local played = math.floor(Stats.Played())
  local log = Stats.DeathList()
  local e = { t = ns.Now(), c = ns.me, p = played }
  if type(killer) == "string" and killer ~= "" then e.k = killer end
  if type(zone) == "string" and zone ~= "" and not ns.issecret(zone) then e.z = zone end
  log[#log + 1] = e
  while #log > Stats.LOG_MAX do table.remove(log, 1) end
  local len = math.max(0, played - (tonumber(c.lifeStart) or 0))
  local key = Stats.BracketOf(myLevel())
  local b = key and Stats.Bracket(key)
  if b then
    b.deaths, b.lives = b.deaths + 1, b.lives + 1
    b.lifeSum, b.lifeMax = b.lifeSum + len, math.max(b.lifeMax, len)
  end
  c.lifeStart = played
end

-- the life in progress: time played since your last PvP death (or the counter's start), and the
-- kills (with a played stamp) since then
function Stats.CurrentLife()
  local start = tonumber(FriendsAndFoesCharDB and FriendsAndFoesCharDB.lifeStart) or 0
  local r = { time = math.max(0, Stats.Played() - start), kills = 0 }
  for _, e in ipairs(Stats.List()) do
    if e.c == ns.me and tonumber(e.p) and e.p >= start then r.kills = r.kills + 1 end
  end
  return r
end

-- the bracket you are in now (nil when your level is unknown)
function Stats.CurrentBracket() return Stats.BracketOf(myLevel()) end

-- seconds played in a bracket (nil: everywhere), with the part not saved yet going to the one
-- you're in now
local function playedIn(key, sum)
  local cur = Stats.CurrentBracket()
  if key then return Stats.Bracket(key).played + (key == cur and unflushed() or 0) end
  return sum + unflushed()
end

-- does this bracket have anything to show?
function Stats.HasData(key)
  local b = Stats.Bracket(key)
  return b ~= nil and (b.kills > 0 or b.deaths > 0 or playedIn(key, 0) > 0)
end

---------------------------------------------------------------------------
-- the numbers
---------------------------------------------------------------------------
-- Everything the page shows, for one bracket (key) or everything (nil): the same shape either way.
-- The totals come from the brackets; today / week / month are counted from the log. now: for tests.
function Stats.Compute(key, now)
  Stats.Seed()
  now = now or time()
  local r = { key = key, tiers = { grey = 0, lower = 0, even = 0, higher = 0, skull = 0 }, tiered = 0,
    today = 0, week = 0, month = 0, zones = {}, n = 0, deaths = 0, lives = 0, lifeSum = 0, lifeMax = 0,
    bestStreak = 0, pkills = 0 }
  local vlSum, vlN, gapSum, gapN, played = 0, 0, 0, 0, 0
  local byDay, byHour, byZone = {}, {}, {}
  local c = FriendsAndFoesCharDB
  for _, def in ipairs(Stats.BRACKETS) do
    local b = (not key or key == def.key) and c and c.brackets and c.brackets[def.key]
    if b then
      r.n, r.deaths, r.lives = r.n + b.kills, r.deaths + b.deaths, r.lives + b.lives
      r.lifeSum, r.lifeMax = r.lifeSum + b.lifeSum, math.max(r.lifeMax, b.lifeMax)
      r.bestStreak, r.pkills, played = math.max(r.bestStreak, b.bestStreak), r.pkills + b.pkills, played + b.played
      vlSum, vlN, gapSum, gapN = vlSum + b.vlSum, vlN + b.vlN, gapSum + b.gapSum, gapN + b.gapN
      for tier, n in pairs(b.tiers) do r.tiers[tier] = r.tiers[tier] + n; r.tiered = r.tiered + n end
      for k, n in pairs(b.wday) do byDay[k] = (byDay[k] or 0) + n end
      for k, n in pairs(b.hour) do byHour[k] = (byHour[k] or 0) + n end
      for z, n in pairs(b.zones) do byZone[z] = (byZone[z] or 0) + n end
    end
  end
  if not key and c then r.bestStreak = math.max(r.bestStreak, ns.Count(c.bestStreak)) end
  r.played = playedIn(key, played)

  -- from the log: today, the last 7 and the last 30 days (all brackets)
  local dayStart = time({ year = tonumber(date("%Y", now)), month = tonumber(date("%m", now)), day = tonumber(date("%d", now)), hour = 0 })
  for _, e in ipairs(Stats.List()) do
    local t = e.c == ns.me and tonumber(e.t)
    if t then
      if t >= dayStart then r.today = r.today + 1 end
      if now - t < Stats.WEEK_DAYS * 86400 then r.week = r.week + 1 end
      if now - t < Stats.MONTH_DAYS * 86400 then r.month = r.month + 1 end
    end
  end

  r.levelN, r.gapN = vlN, gapN
  r.avgLevel = vlN >= Stats.MIN_LEVELS and (vlSum / vlN) or nil
  r.avgGap = gapN >= Stats.MIN_LEVELS and (gapSum / gapN) or nil
  local function best(counts, first, last)
    local at, most
    for k = first, last do
      if (counts[k] or 0) > (most or 0) then at, most = k, counts[k] end
    end
    return at
  end
  if r.n >= Stats.MIN_BUSY then r.busyDay, r.busyHour = best(byDay, 1, 7), best(byHour, 0, 23) end
  for z, n in pairs(byZone) do r.zones[#r.zones + 1] = { name = z, n = n } end
  table.sort(r.zones, function(a, b) if a.n ~= b.n then return a.n > b.n end return a.name < b.name end)
  while #r.zones > Stats.TOP_ZONES do r.zones[#r.zones] = nil end
  -- lives (completed ones) and the rate
  if r.deaths >= Stats.MIN_DEATHS and r.lives > 0 then r.avgLife = r.lifeSum / r.lives end
  r.longest = r.lives > 0 and r.lifeMax or nil
  if r.played >= Stats.MIN_PLAYED then r.perHour = r.pkills / (r.played / 3600) end
  return r
end

-- "3 higher" / "2 lower" / "even" for an average gap (nil: unknown)
function Stats.GapText(gap)
  if not gap then return nil end
  local n = math.floor(math.abs(gap) + 0.5)
  if n == 0 then return L.STATS_GAP_EVEN end
  return (gap > 0 and L.STATS_GAP_HIGHER or L.STATS_GAP_LOWER):format(n)
end
