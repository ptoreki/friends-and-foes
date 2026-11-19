local _, ns = ...
local L = ns.L

-- Notoriety (0.9, called "bounties" until 1.0 - the code, saved data and messages keep that
-- name; players see "Notoriety"). Just for fun: points, not gold. Real gold promises are the
-- Bounty board (Contracts.lua).
-- Every enemy has an open bounty on their Wanted poster: what they've done to you and your
-- friends since someone last collected on them (per murder, per attack), plus a price
-- for every friend who has them as most wanted (paid out once per friend). Killing them collects it: everyone who got the
-- kill (each one's client reports it) shares it equally, and the open bounty starts again.
-- Each player's total is their own (account-wide), sent to friends with their profile like their
-- K/D, and shown on the Leaderboard and profiles.
local Bounty = {}
ns.Bounty = Bounty

Bounty.MURDER, Bounty.ATTACK, Bounty.WANTED, Bounty.MIN = 100, 25, 250, 10
local SHARE_WINDOW = 60 -- kills of the same enemy this close together share one bounty
local SETTLE = 15 -- seconds to wait for the other killers' reports before taking your share

local function mine()
  FriendsAndFoesDB.profile = FriendsAndFoesDB.profile or {}
  local p = FriendsAndFoesDB.profile
  p.bounty = p.bounty or { total = 0, count = 0 }
  return p.bounty
end

-- your bounties collected: total gold, how many, the biggest share { name, amount }
function Bounty.Mine()
  local b = mine()
  return ns.Count(b.total), ns.Count(b.count), b.best
end

-- the sum: murders and attacks (since the last collection), friends who want them
function Bounty.Price(murders, attacks, wantedBy)
  local b = Bounty.MURDER * (murders or 0) + Bounty.ATTACK * (attacks or 0) + Bounty.WANTED * (wantedBy or 0)
  return math.max(Bounty.MIN, b)
end

local function counts(name)
  local rec = ns.Data.FindPlayer(name)
  local hit = ns.Data.FindHit(name)
  local murders = ns.Count(rec and rec.k)
  local attacks = math.max(ns.Count(rec and rec.atk), ns.Count(hit and hit.attacks))
  return rec, murders, attacks
end

-- friends (and you) who want them and haven't had their most-wanted price paid out yet: each
-- one's price is paid once, so killing a most wanted again and again doesn't pay it again
local function unpaidWanters(rec, name)
  local paid, n = rec and rec.bwPaid, 0
  for _, who in ipairs(ns.Profile.WantedBy(name)) do
    if not (paid and paid[who]) then n = n + 1 end
  end
  return n
end

-- an enemy's open bounty right now
function Bounty.Open(name)
  if not name then return Bounty.MIN end
  local rec, murders, attacks = counts(name)
  local m = math.max(0, murders - ns.Count(rec and rec.bk0))
  local a = math.max(0, attacks - ns.Count(rec and rec.ba0))
  return Bounty.Price(m, a, unpaidWanters(rec, name))
end

-- someone collected: the open bounty starts again from here, and the most-wanted prices in it
-- are paid
local function reset(name)
  local rec, murders, attacks = counts(name)
  if not rec then return end
  rec.bk0, rec.ba0 = murders, attacks
  rec.bwPaid = rec.bwPaid or {}
  for _, who in ipairs(ns.Profile.WantedBy(name)) do rec.bwPaid[who] = true end
end

---------------------------------------------------------------------------
-- collecting: a kill by you or a friend (from Events: H.KILL)
---------------------------------------------------------------------------
local claims = {} -- enemy name -> { amount, killers = { name = true }, n, t, settled }

local function settle(name, claim)
  if claim.settled then return end
  claim.settled = true
  if not claim.killers[ns.me] then return end
  local share = math.floor(claim.amount / math.max(1, claim.n))
  local b = mine()
  b.total = ns.Count(b.total) + share
  b.count = ns.Count(b.count) + 1
  if not b.best or share > ns.Count(b.best.amount) then b.best = { name = name, amount = share } end
  local others = {}
  for k in pairs(claim.killers) do if k ~= ns.me then others[#others + 1] = ns.ClassColored(k) end end
  local enemy = ns.ClassColored(name, (ns.Data.FindPlayer(name) or {}).class)
  local line = #others == 0 and L.BOUNTY_COLLECTED:format(ns.Art.Points(share), enemy)
    or L.BOUNTY_COLLECTED_SHARED:format(ns.Art.Points(share), enemy, ns.JoinNames(others))
  ns.Toast.Chat(line)
  ns.Debug("BOUNTY", name, claim.amount, claim.n, share)
  ns.Profile.Changed() -- your new total goes to your friends
  if ns.Groups then ns.Groups.MyStatsChanged() end -- and through your groups
end

-- killer: who got the kill (you or a friend); victim: the enemy's name. Sim kills don't count.
function Bounty.OnKill(killer, victim)
  if not killer or not victim then return end
  local now = GetTime()
  local claim = claims[victim]
  if not claim or now - claim.t > SHARE_WINDOW then
    claim = { amount = Bounty.Open(victim), killers = {}, n = 0, t = now }
    claims[victim] = claim
    reset(victim)
  end
  if claim.killers[killer] then return end
  claim.killers[killer] = true
  claim.n = claim.n + 1
  if killer == ns.me and not claim.settled then
    C_Timer.After(SETTLE, function() ns.Try("bounty", settle, victim, claim) end)
  end
end

-- for tests: settle every open claim now
function Bounty.SettleAll()
  for name, claim in pairs(claims) do settle(name, claim) end
end
