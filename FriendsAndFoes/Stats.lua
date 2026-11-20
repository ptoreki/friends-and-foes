local _, ns = ...
local L = ns.L

-- Your own kill log, and the numbers the Stats page (UIStats.lua) shows from it.
--  * FriendsAndFoesDB.killLog = { { t, c, n, vl, ml, z }, ... }, oldest first, at most LOG_MAX:
--    t time, c the character (ns.me; entries without one are ignored, and the page only counts this character's), n victim's name (nil when it couldn't be read), vl victim's level at the time
--    (nil unknown, -1 skull), ml your level at the time, z zone. Only your own live kills are
--    logged here (never a friend's, never a caught-up or replayed one). Account-wide, like your
--    own kill counts. Nothing in it is ever sent to anyone.
--  * FriendsAndFoesCharDB.bestStreak = this character's longest run of kills without dying.
--    The current run is the one Events.lua already counts (FriendsAndFoesCharDB.streak).
local Stats = {}
ns.Stats = Stats

Stats.LOG_MAX = 1000
Stats.TOP_ZONES = 5
Stats.MIN_LEVELS = 5 -- kills with a known, non-skull level before the average level and gap show
Stats.MIN_BUSY = 20 -- logged kills before the busiest weekday and hour show
Stats.WEEK_DAYS, Stats.MONTH_DAYS = 7, 30 -- "Last 7 days" / "Last 30 days" = the last 7 / 30 days

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

-- one of your own live kills (victim: name or nil; vlevel: as sent in KILL; zone: text or nil)
function Stats.Log(victim, vlevel, zone)
  local log = Stats.List()
  local e = { t = ns.Now(), c = ns.me, vl = logLevel(vlevel), ml = myLevel() }
  if type(victim) == "string" and victim ~= "" then e.n = victim end
  if type(zone) == "string" and zone ~= "" and not ns.issecret(zone) then e.z = zone end
  log[#log + 1] = e
  while #log > Stats.LOG_MAX do table.remove(log, 1) end
end

-- the current run grew to n kills: remember the best one
function Stats.NoteStreak(n)
  local c = FriendsAndFoesCharDB
  if n > ns.Count(c.bestStreak) then c.bestStreak = n end
end

-- current run, best run
function Stats.Streaks()
  local cur = ns.Count(FriendsAndFoesCharDB and FriendsAndFoesCharDB.streak)
  return cur, math.max(cur, ns.Count(FriendsAndFoesCharDB and FriendsAndFoesCharDB.bestStreak))
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

-- everything the page shows from the log. now: for tests (default: the time of day now).
function Stats.Compute(now)
  now = now or time()
  local log = Stats.List()
  local r = { n = 0, tiers = { grey = 0, lower = 0, even = 0, higher = 0, skull = 0 }, tiered = 0,
    today = 0, week = 0, month = 0, zones = {} }
  local dayStart = time({ year = tonumber(date("%Y", now)), month = tonumber(date("%m", now)), day = tonumber(date("%d", now)), hour = 0 })
  local lvSum, lvN, gapSum, gapN = 0, 0, 0, 0
  local byDay, byHour, byZone = {}, {}, {}
  r.n = 0
  for _, e in ipairs(log) do if e.c == ns.me then
    r.n = r.n + 1
    local t = tonumber(e.t)
    if t then
      if t >= dayStart then r.today = r.today + 1 end
      if now - t < Stats.WEEK_DAYS * 86400 then r.week = r.week + 1 end
      if now - t < Stats.MONTH_DAYS * 86400 then r.month = r.month + 1 end
      local d = date("*t", t)
      if d then
        byDay[d.wday] = (byDay[d.wday] or 0) + 1
        byHour[d.hour] = (byHour[d.hour] or 0) + 1
      end
    end
    if e.vl and e.vl > 0 then
      lvSum, lvN = lvSum + e.vl, lvN + 1
      if e.ml and e.ml > 0 then gapSum, gapN = gapSum + (e.vl - e.ml), gapN + 1 end
    end
    local tier = Stats.Tier(e)
    if tier then r.tiers[tier] = r.tiers[tier] + 1; r.tiered = r.tiered + 1 end
    if e.z then byZone[e.z] = (byZone[e.z] or 0) + 1 end
  end end
  r.levelN, r.gapN = lvN, gapN
  r.avgLevel = lvN >= Stats.MIN_LEVELS and (lvSum / lvN) or nil
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
  return r
end

-- "3 higher" / "2 lower" / "even" for an average gap (nil: unknown)
function Stats.GapText(gap)
  if not gap then return nil end
  local n = math.floor(math.abs(gap) + 0.5)
  if n == 0 then return L.STATS_GAP_EVEN end
  return (gap > 0 and L.STATS_GAP_HIGHER or L.STATS_GAP_LOWER):format(n)
end
