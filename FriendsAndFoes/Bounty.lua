local _, ns = ...
local L = ns.L

-- Notoriety (0.9, called "bounties" until 1.0 - the code, saved data and messages keep that
-- name; players see "Notoriety"). Just for fun: points, not gold. Real gold promises are the
-- Bounty board (Contracts.lua).
-- Every enemy has an open notoriety on their Wanted poster: a "random" (never hurt any of you) is
-- worth a little; a hitlist enemy what they've done to you and your friends since
-- someone last claimed it, more while on a rampage, cooling off while they lie low. Killing the
-- same enemy again and again within 30 minutes is worth less each time (no camping). Killing them
-- claims it: alone you get all of it; with several killers, everyone who got the kill shares it equally.
-- Your own notoriety fades a little each idle week.
-- Each player's total is their own (account-wide), sent to friends with their profile like their
-- K/D, and shown on the Friends tab and profiles.
local Bounty = {}
ns.Bounty = Bounty

-- All the numbers in one place, to tune:
Bounty.MURDER, Bounty.ATTACK = 100, 25 -- hitlist enemy: points per kill / per attack since the last claim
Bounty.RANDOM = 10 -- an enemy who never hurt you or a friend ("a random") is worth this
Bounty.HITLIST_MIN = 50 -- a hitlist enemy is always worth at least this
-- Diminishing returns, so camping doesn't pay: the "free" part of what an enemy is worth (the
-- RANDOM value, or the HITLIST_MIN floor) is scaled by how many times they were claimed in a chain:
-- each kill within REPEAT_WINDOW seconds of the last kill of them extends the chain; that long
-- without a kill resets it. 1st kill x1, 2nd x0.5, 3rd x0.25, later ones (past the list) x0.
-- Points they earned (kills/attacks on you or a friend) are never reduced, and fighting back resets the chain.
Bounty.REPEAT_WINDOW = 1800
Bounty.REPEAT_FACTORS = { 1, 0.5, 0.25 }
Bounty.RAMPAGE_KILLS, Bounty.RAMPAGE_WINDOW, Bounty.RAMPAGE_FACTOR = 3, 3600, 1.5 -- 3 kills on your group in an hour: x1.5
Bounty.COOL_RATE = 0.9 -- x this for every full day since they last killed or attacked one of you
Bounty.PLAYER_DECAY, Bounty.PLAYER_DECAY_EVERY = 0.1, 7 * 86400 -- your notoriety loses 10% for every full week since your last claim
Bounty.TAKEDOWN_MIN = 300 -- a claim this big is a takedown: everyone who saw it gets a toast
-- an enemy's rank by what they're worth now (highest first), your title by your notoriety now
Bounty.RANKS = { { 1000, L.RANK_PUBLIC_ENEMY }, { 600, L.RANK_MOST_WANTED }, { 300, L.RANK_WANTED },
  { 100, L.RANK_MENACE }, { 0, L.RANK_NUISANCE } }
Bounty.TITLES = { { 10000, L.TITLE_LEGEND }, { 5000, L.TITLE_MANHUNTER }, { 2000, L.TITLE_BOUNTY_HUNTER },
  { 500, L.TITLE_HUNTER }, { 0, L.TITLE_TRACKER } }
-- Level difference (victim level - the KILLER's own level) scales each killer's share. The first row
-- whose minimum difference is met wins. A victim who is grey to the killer pays nothing (x0); a "??"
-- victim (level -1, skull) counts as far above. Unknown levels (either side) never change the share.
Bounty.LEVEL_TIERS = { { 6, 1.5 }, { 3, 1.25 }, { -2, 1 }, { -5, 0.5 }, { -999, 0.25 } }
Bounty.LEVEL_UNKNOWN_FACTOR = 1.5 -- a victim shown as "??"

-- The level at or below which a victim is grey (worth no honor/XP) to someone of this level: the
-- Classic grey-level rule. Pure function (UnitQuestTrivialLevelRange only knows the player).
function Bounty.GreyLevel(level)
  level = tonumber(level) or 0
  if level <= 5 then return 0 end
  if level <= 39 then return level - 5 - math.floor(level / 10) end
  if level <= 59 then return level - 1 - math.floor(level / 5) end
  return level - 9
end

-- factor, short text for the debug log
function Bounty.LevelFactor(killerLevel, victimLevel)
  killerLevel, victimLevel = tonumber(killerLevel), tonumber(victimLevel)
  if not killerLevel or killerLevel <= 0 then return 1, "lvl unknown (x1)" end
  if not victimLevel or victimLevel == 0 then return 1, "lvl ? vs " .. killerLevel .. " (x1)" end
  if victimLevel < 0 then
    return Bounty.LEVEL_UNKNOWN_FACTOR, "lvl ?? vs " .. killerLevel .. " (x" .. Bounty.LEVEL_UNKNOWN_FACTOR .. ")"
  end
  if victimLevel <= Bounty.GreyLevel(killerLevel) then return 0, "grey (x0)" end
  local diff = victimLevel - killerLevel
  for _, t in ipairs(Bounty.LEVEL_TIERS) do
    if diff >= t[1] then
      return t[2], "lvl " .. killerLevel .. " vs " .. victimLevel .. " (x" .. t[2] .. ")"
    end
  end
  return 1, "lvl " .. killerLevel .. " vs " .. victimLevel .. " (x1)"
end

local SHARE_WINDOW = 60 -- kills of the same enemy this close together share one bounty
local SETTLE = 15 -- seconds to wait for the other killers' reports before taking your share
local WEEK = 7 * 86400
local KILL_ICON = "Interface\\Icons\\Ability_DualWield"

-- Your notoriety fades: b.total is what you have NOW; b.allTime is everything you ever claimed.
-- b.clock is the last claim, or the last full week already taken off (so a week is never applied twice).
local function mine()
  FriendsAndFoesDB.profile = FriendsAndFoesDB.profile or {}
  local p = FriendsAndFoesDB.profile
  p.bounty = p.bounty or { total = 0, count = 0 }
  local b = p.bounty
  b.total = ns.Count(b.total)
  b.allTime = b.allTime and ns.Count(b.allTime) or b.total -- (from before the fading: all you had)
  if not b.clock then b.clock = time() end
  local weeks = math.floor((time() - b.clock) / Bounty.PLAYER_DECAY_EVERY)
  if weeks > 0 then
    if b.total > 0 then b.total = math.floor(b.total * (1 - Bounty.PLAYER_DECAY) ^ weeks + 1e-6) end
    b.clock = b.clock + weeks * Bounty.PLAYER_DECAY_EVERY
  end
  return b
end

-- your notoriety now (faded), how many claims, the biggest share { name, amount }
function Bounty.Mine()
  local b = mine()
  return b.total, ns.Count(b.count), b.best
end

-- everything you ever claimed, fading or not
function Bounty.AllTime() return mine().allTime end

-- this week's claimed points (0 once the week is over), and the week's id (its start, in days)
-- for friends to tell a stale number from a fresh one
function Bounty.Week()
  local w = FriendsAndFoesDB.weekly
  if not w or not w.start or time() - w.start >= WEEK then return 0 end
  return ns.Count(w.bt)
end

function Bounty.WeekId()
  local w = FriendsAndFoesDB.weekly
  return w and w.start and math.floor(w.start / 86400) or 0
end

-- a friend's points this week as they reported it: nil when unknown, 0 when it's an old week
function Bounty.FriendWeek(p)
  if not p or not p.sbtw then return nil end
  if not p.sbwk or math.floor(time() / 86400) - p.sbwk > 7 then return 0 end
  return p.sbtw
end

local function labelFor(list, points)
  points = tonumber(points) or 0
  for _, r in ipairs(list) do
    if points >= r[1] then return r[2], r[1] end
  end
  return list[#list][2], list[#list][1]
end

-- an enemy's rank for what they're worth, your title for your total
function Bounty.RankFor(points) return (labelFor(Bounty.RANKS, points)) end
function Bounty.Title(total) return (labelFor(Bounty.TITLES, total)) end
-- how far up the titles: 1 = the first
local function titleLevel(total)
  local _, floor = labelFor(Bounty.TITLES, total)
  for i = #Bounty.TITLES, 1, -1 do if Bounty.TITLES[i][1] == floor then return #Bounty.TITLES - i + 1 end end
  return 1
end

-- the sum: murders and attacks (since the last collection)
function Bounty.Price(murders, attacks)
  return Bounty.MURDER * (murders or 0) + Bounty.ATTACK * (attacks or 0)
end

local function counts(name)
  local rec = ns.Data.FindPlayer(name)
  local hit = ns.Data.FindHit(name)
  local murders = ns.Count(rec and rec.k)
  local attacks = math.max(ns.Count(rec and rec.atk), ns.Count(hit and hit.attacks))
  return rec, murders, attacks, hit
end

-- never killed or attacked you or a friend
local function isRandom(rec, murders, attacks, hit)
  return murders == 0 and attacks == 0 and ns.Count(hit and hit.kills) == 0
end

-- 3 or more kills on your group within the hour
function Bounty.OnRampage(name)
  local hit = name and ns.Data.FindHit(name)
  if not hit or type(hit.killTimes) ~= "table" then return false end
  local now, n = ns.Now(), 0
  for _, t in ipairs(hit.killTimes) do
    if type(t) == "number" and now - t <= Bounty.RAMPAGE_WINDOW then n = n + 1 end
  end
  return n >= Bounty.RAMPAGE_KILLS
end

-- Claim times per enemy (FriendsAndFoesDB.repeats[name] = { t, t, ... }, oldest first), for the
-- repeat chain. Every client records one time per claim (a kill reported by several friends is one
-- claim), so they all count the same.
local function repeatList(name)
  local all = FriendsAndFoesDB.repeats
  return type(all) == "table" and type(all[name]) == "table" and all[name] or nil
end

-- how many claims are in the enemy's current chain (0 = none, or the last one is over 30 min old)
local function chainLength(list, now)
  local n, prev = 0, now
  if not list then return 0 end
  for i = #list, 1, -1 do
    local t = tonumber(list[i])
    if not t or prev - t > Bounty.REPEAT_WINDOW then break end
    n = n + 1
    prev = t
  end
  return n
end

function Bounty.Repeats(name) return chainLength(repeatList(name), ns.Now()) end

-- points earned since the last claim: kills and attacks on you or your friends
local function earnedCounts(rec, murders, attacks)
  return math.max(0, murders - ns.Count(rec and rec.bk0)), math.max(0, attacks - ns.Count(rec and rec.ba0))
end

-- a claim of this enemy is happening (once per claim, not per killer): remember the time. Fighting
-- back (earned > 0) resets the chain to 0 (that claim isn't counted); old chains and old enemies are dropped.
local function noteClaim(name, fought)
  local now = ns.Now()
  FriendsAndFoesDB.repeats = type(FriendsAndFoesDB.repeats) == "table" and FriendsAndFoesDB.repeats or {}
  local all = FriendsAndFoesDB.repeats
  local list = repeatList(name)
  if fought then
    all[name] = nil -- (that claim paid in full and starts the count from 0)
  else
    local keep = {}
    if list then
      for i = #list - chainLength(list, now) + 1, #list do keep[#keep + 1] = list[i] end
    end
    keep[#keep + 1] = now
    while #keep > #Bounty.REPEAT_FACTORS + 1 do table.remove(keep, 1) end
    all[name] = keep
  end
  for other, l in pairs(all) do
    if other ~= name and (type(l) ~= "table" or chainLength(l, now) == 0) then all[other] = nil end
  end
end

-- an enemy's open bounty right now
function Bounty.Open(name)
  if not name then return 0 end
  local rec, murders, attacks, hit = counts(name)
  local m, a = earnedCounts(rec, murders, attacks)
  if m + a == 0 then
    -- nothing earned since the last claim: only the free part, shrinking with each repeat kill
    local free = isRandom(rec, murders, attacks, hit) and Bounty.RANDOM or Bounty.HITLIST_MIN
    local factor = Bounty.REPEAT_FACTORS[Bounty.Repeats(name) + 1] or 0
    return math.floor(free * factor + 1e-6)
  end
  local points = Bounty.Price(m, a)
  if Bounty.OnRampage(name) then points = points * Bounty.RAMPAGE_FACTOR end
  local last = hit and tonumber(hit.lastOffence)
  if last then
    local days = math.floor(math.max(0, ns.Now() - last) / 86400)
    if days > 0 then points = points * Bounty.COOL_RATE ^ days end
  end
  return math.max(Bounty.HITLIST_MIN, math.floor(points + 1e-6))
end

-- a hitlist enemy's rank by what they're worth now; randoms have none
function Bounty.Rank(name)
  if not name then return nil end
  local rec, murders, attacks, hit = counts(name)
  if isRandom(rec, murders, attacks, hit) then return nil end
  return Bounty.RankFor(Bounty.Open(name))
end

-- someone collected: the open bounty starts again from here
local function reset(name)
  local rec, murders, attacks = counts(name)
  if not rec then return end
  rec.bk0, rec.ba0 = murders, attacks
end

---------------------------------------------------------------------------
-- collecting: a kill by you or a friend (from Events: H.KILL)
---------------------------------------------------------------------------
local claims = {} -- enemy name -> { amount, rank, killers = { name = true }, n, t, settled }

-- your share is in: it counts now and this week, and a higher title gets a toast (a lower one,
-- after the fading, is lost quietly - and reaching the same one again later toasts again)
local function pay(name, claim, winner, share)
  local b = mine()
  local before = titleLevel(b.total)
  b.total = b.total + share
  b.allTime = b.allTime + share
  b.clock = time() -- a claim starts the fading again
  b.count = ns.Count(b.count) + 1
  if not b.best or share > ns.Count(b.best.amount) then b.best = { name = name, amount = share } end
  if ns.Events and ns.Events.WeeklyAdd then ns.Events.WeeklyAdd("bt", share) end
  local others = {}
  for k in pairs(claim.killers) do if k ~= ns.me then others[#others + 1] = ns.ClassColored(k) end end
  local enemy = ns.ClassColored(name, (ns.Data.FindPlayer(name) or {}).class)
  local line = #others == 0 and L.BOUNTY_COLLECTED:format(ns.Art.Points(share), enemy)
    or L.BOUNTY_COLLECTED_SHARED:format(ns.Art.Points(share), enemy, ns.JoinNames(others))
  ns.Toast.Chat(line)
  ns.Debug("BOUNTY-PAID", name, claim.amount, claim.n, share)
  if titleLevel(b.total) > before then
    local text = L.TITLE_NEW:format(Bounty.Title(b.total))
    ns.Debug("TITLE", Bounty.Title(b.total), "total " .. b.total)
    ns.Toast.Push({ kind = "kill", category = "pvp", icon = KILL_ICON, header = L.HEADER_TITLE,
      milestone = true, chat = text, title = text })
  end
  ns.Profile.Changed() -- your new total goes to your friends
  if ns.Groups then ns.Groups.MyStatsChanged() end -- and through your groups
end

-- a big claim: everyone who saw it gets one toast, naming the killers
local function takedown(name, claim)
  local enemy = ns.ClassColored(name, (ns.Data.FindPlayer(name) or {}).class)
  local rank = Bounty.RankFor(claim.amount)
  local names = {}
  for k in pairs(claim.killers) do names[#names + 1] = k end
  table.sort(names)
  for i, k in ipairs(names) do names[i] = ns.ClassColored(k) end
  local line = (#names == 1 and L.TAKEDOWN or L.TAKEDOWN_SHARED):format(ns.JoinNames(names), enemy, rank,
    ns.Art.Points(claim.amount))
  ns.Debug("TAKEDOWN", name, rank, claim.amount .. " points", "killers: " .. table.concat(names, ", "))
  ns.Toast.Push({ kind = "kill", category = "pvp", icon = KILL_ICON, header = L.HEADER_TAKEDOWN,
    milestone = true, chat = line, title = line, player = name })
end

-- Who gets it: everyone who got the kill (killers reporting within SHARE_WINDOW) shares it equally,
-- rounded down; alone you get all of it. Who landed the killing blow doesn't matter here (that
-- decides the Bounty board, Contracts.lua). Every client settles (15 s after the first report), but
-- only your own share is ever added to you.
local function settle(name, claim)
  if claim.settled then return end
  claim.settled = true
  if claim.amount <= 0 then
    ns.Debug("BOUNTY-SETTLE", name, "worth 0, nothing to share", "killers " .. claim.n)
    return
  end
  -- your share: an equal part, times your own level factor (your level when you got the kill)
  local factor, lvlText = Bounty.LevelFactor(claim.myLevel, claim.vlevel)
  local share = math.floor(claim.amount / math.max(1, claim.n) * factor + 1e-6)
  ns.Debug("BOUNTY-SETTLE", name, claim.amount .. " points", "killers " .. claim.n, claim.killers[ns.me] and ("your share " .. share .. ", " .. lvlText) or "you were not one of them")
  if claim.killers[ns.me] then
    if share > 0 then pay(name, claim, nil, share) end -- (grey: quiet, like a worth-0 repeat)
  end
  if claim.amount >= Bounty.TAKEDOWN_MIN and not claim.past and claim.n > 0 then
    takedown(name, claim)
  end
end

-- why a claim is worth what it is, for the debug log
local function whyWorth(name)
  local rec, murders, attacks, hit = counts(name)
  local m, a = earnedCounts(rec, murders, attacks)
  local why = isRandom(rec, murders, attacks, hit) and "random" or "hitlist"
  if m + a == 0 then
    local n = Bounty.Repeats(name)
    return why .. ", repeat " .. n .. " (x" .. (Bounty.REPEAT_FACTORS[n + 1] or 0) .. ")"
  end
  why = "hitlist"
  if Bounty.OnRampage(name) then why = why .. "+rampage" end
  local last = hit and tonumber(hit.lastOffence)
  if last and math.floor(math.max(0, ns.Now() - last) / 86400) > 0 then why = why .. "+cooling" end
  return why .. ", earned, chain reset"
end

-- A repeat report of an enemy whose claim just ended (within REPEAT_GUARD) opens nothing new: the
-- same death reported late would otherwise pay again (a hitlist enemy is always worth something).
local REPEAT_GUARD = 100

-- killer: who got the kill (you or a friend); victim: the enemy's name; credit: { blow, last } as
-- in Events.BetterCredit (true counts as a plain killing blow).
function Bounty.OnKill(killer, victim, credit)
  if not killer or not victim then return end
  if credit == true then credit = { blow = "1" } elseif type(credit) ~= "table" then credit = {} end
  local now = GetTime()
  local claim = claims[victim]
  if ns.past then
    -- something from before (caught up, passed on): never pays; it only restarts the enemy's
    -- open bounty (someone collected it then) when nothing newer is open
    if not claim or now - claim.t > SHARE_WINDOW then reset(victim) end
    ns.Debug("BOUNTY-PAST", killer, victim, "no claim (an old kill)")
    return
  end
  if claim and now - claim.t > SHARE_WINDOW and now - claim.t <= REPEAT_GUARD then
    ns.Debug("BOUNTY-LATE", killer, victim, "ignored: their claim ended " .. math.floor(now - claim.t) .. " s ago")
    return
  end
  if not claim or now - claim.t > SHARE_WINDOW then
    local vrec = ns.Data.FindPlayer(victim)
    claim = { amount = Bounty.Open(victim), killers = {}, n = 0, t = now, vlevel = vrec and tonumber(vrec.level) }
    claims[victim] = claim
    ns.Debug("BOUNTY-CLAIM", victim, claim.amount .. " points", whyWorth(victim),
      "first: " .. killer, (select(2, Bounty.LevelFactor(UnitLevel("player"), claim.vlevel))))
    -- one more repeat of this enemy (a worth-0 kill too: it keeps the chain going)
    local rec, murders, attacks = counts(victim)
    local m, a = earnedCounts(rec, murders, attacks)
    noteClaim(victim, m + a > 0)
    reset(victim)
    C_Timer.After(SETTLE, function() ns.Try("bounty", settle, victim, claim) end)
  end
  if (credit.blow or credit.last) and (not claim.winner or ns.Events.BetterCredit(credit, claim.best)) then
    claim.winner, claim.best = killer, credit
  end
  if claim.killers[killer] then
    ns.Debug("BOUNTY-JOIN", killer, victim, "already in the claim")
    return
  end
  claim.killers[killer] = true
  if killer == ns.me then claim.myLevel = UnitLevel("player") end -- (at the kill, not when it settles)
  claim.n = claim.n + 1
  if claim.n > 1 then ns.Debug("BOUNTY-JOIN", killer, victim, "killers now " .. claim.n) end
end

-- for tests: settle every open claim now
function Bounty.SettleAll()
  for name, claim in pairs(claims) do settle(name, claim) end
end
