local _, ns = ...
local L = ns.L

-- Kill lists: who each player has killed, and how often.
--  * You and your friends: counted from the kill alerts your client gets (a friend's kills while
--    you were offline arrive through the catch-up). Stored on the killer's record as
--    `slain` = { [victim] = { n, t, zone } }.
--  * A friend is the authority on their own kills: opening their list asks them for it (KLQ),
--    and their answer (KLA, their top victims) is kept as `slainRep` and merged in (highest
--    count wins, so nothing you saw gets lost).
--  * Enemies: the friends they killed, from the hitlist.
-- Kills whose victim couldn't be named (Forever's honor message has no name) are one line at the
-- end, "Name not readable", counted on the killer's record (kx).
local Kills = {}
ns.Kills = Kills

local SHARE_TOP = 60        -- victims sent when a friend asks for your list
local ASK_EVERY = 120       -- seconds before asking the same friend again
local ANSWER_EVERY = 60     -- seconds before answering the same friend again

-- count a kill on the killer's record (p) of victim (name), in zone, at time t (default: now)
function Kills.AddTo(p, victim, zone, t)
  if not (p and victim) then return end
  t = t or ns.Now()
  p.slain = p.slain or {}
  local v = p.slain[victim]
  if not v then
    v = { n = 0 }
    p.slain[victim] = v
  end
  v.n = v.n + 1
  if not v.t or t >= v.t then
    v.t = t
    if zone and zone ~= "" then v.zone = zone end
  end
end

function Kills.Add(p, victim, zone) Kills.AddTo(p, victim, zone) end

---------------------------------------------------------------------------
-- the list for one player: { { name, class, level, guild, n, t, zone }, ... }
---------------------------------------------------------------------------
local function enemyInfo(players, name, row)
  local e = players[ns.Data.Resolve(players, name)]
  if e then row.class, row.level, row.guild, row.lastSeen = e.class, e.level, e.guild, e.lastSeen end
  return row
end

function Kills.List(name)
  local realm = ns.Data.ViewRealm()
  local players, hitlist = realm.players, realm.hitlist
  local kind = ns.Profile.KindOf(name)
  local rows = {}
  if kind == "enemy" then
    -- the friends this enemy killed (counts since 0.5.1; earlier ones without a count)
    local h = hitlist[ns.Data.Resolve(hitlist, name)]
    for _, v in ipairs(ns.Data.KillsOn(h)) do
      rows[#rows + 1] = enemyInfo(players, v[1], { name = v[1], n = v[2] or 1 })
    end
    return rows
  end
  local p = players[ns.Data.Resolve(players, name)]
  if not p then return rows end
  local merged = {}
  for victim, v in pairs(p.slain or {}) do
    merged[victim] = { name = victim, n = ns.Count(v.n), t = v.t, zone = v.zone }
  end
  -- their own report: the higher count wins, the later time wins
  for victim, v in pairs(p.slainRep or {}) do
    local m = merged[victim]
    if not m then
      merged[victim] = { name = victim, n = ns.Count(v.n), t = v.t }
    else
      m.n = math.max(m.n, ns.Count(v.n))
      if v.t and (not m.t or v.t > m.t) then m.t = v.t end
    end
  end
  for _, row in pairs(merged) do rows[#rows + 1] = enemyInfo(players, row.name, row) end
  -- kills whose victim couldn't be named: one line, so the list adds up to their kills
  if ns.Count(p.kx) > 0 then rows[#rows + 1] = { name = L.KILLS_UNKNOWN, n = ns.Count(p.kx), unknown = true } end
  return rows
end

-- how many different players are in a list (the "Name not readable" line is not a player)
function Kills.Unique(rows)
  local n = 0
  for _, r in ipairs(rows) do
    if not r.unknown then n = n + 1 end
  end
  return n
end

-- total kills in a list
function Kills.Total(rows)
  local n = 0
  for _, r in ipairs(rows) do n = n + ns.Count(r.n) end
  return n
end

---------------------------------------------------------------------------
-- sharing: ask a friend for their list; answer when asked
---------------------------------------------------------------------------
local asked, answered = {}, {}

local function msg(kind, fields)
  local _, class = UnitClass("player")
  return { kind = kind, id = ns.NewId(), class = class, level = UnitLevel("player"), f = fields }
end

-- ask an online friend for their own kill list (no-op if asked recently or they're offline)
function Kills.Ask(name)
  if not (name and ns.Comm.everyone[name]) then return false end
  if asked[name] and GetTime() - asked[name] < ASK_EVERY then return false end
  asked[name] = GetTime()
  ns.Comm.SendTo(name, msg("KLQ", { who = name }))
  return true
end

-- a friend asked for the list of `who`: answer only for the character you're playing
function Kills.Answer(requester, who)
  if ns.CleanName(who) ~= ns.me then return 0 end
  if answered[requester] and GetTime() - answered[requester] < ANSWER_EVERY then return 0 end
  answered[requester] = GetTime()
  if not ns.S().share.pvp then return 0 end -- you don't share your PvP
  local players = ns.Data.RealRealm().players
  local me = players[ns.Data.Resolve(players, ns.me)]
  local list = {}
  for victim, v in pairs(me and me.slain or {}) do list[#list + 1] = { victim, ns.Count(v.n), v.t or 0 } end
  table.sort(list, function(a, b)
    if a[2] ~= b[2] then return a[2] > b[2] end
    return a[1] < b[1]
  end)
  local items = {}
  for i = 1, math.min(#list, SHARE_TOP) do
    local e = list[i]
    items[#items + 1] = (e[1]:gsub("[:;\t|]", " ")) .. ":" .. e[2] .. ":" .. ns.Groups.B36(e[3])
  end
  -- as many per message as fit (the first message also says how many there are in all)
  local sent, batch = 0, {}
  local function build(b) return msg("KLA", { who = ns.me, total = #list, list = table.concat(b, ";") }) end
  local function flush()
    if #batch == 0 then return end
    ns.Comm.SendTo(requester, build(batch))
    sent = sent + 1
    batch = {}
  end
  for _, item in ipairs(items) do
    batch[#batch + 1] = item
    if #ns.Comm.Encode(build(batch)) > 250 then
      table.remove(batch)
      flush()
      batch[1] = item
    end
  end
  flush()
  if #items == 0 then ns.Comm.SendTo(requester, build({})) end -- "no kills yet" is an answer too
  return sent
end

-- a friend's answer about their own kills (sender = the character it's about)
function Kills.OnAnswer(sender, f)
  if ns.CleanName(f.who) ~= sender then return end -- only their own list counts
  local p = ns.Data.FindPlayer(sender)
  if not p then return end
  p.slainRep = p.slainRep or {}
  for _, part in ipairs(ns.Split(f.list or "", ";")) do
    local e = ns.Split(part, ":")
    local victim, n, t = ns.CleanName(e[1]), tonumber(e[2]), ns.Profile.ClampTime(ns.Groups.UnB36(e[3]))
    if victim and n and n > 0 and ns.Profile.Check(victim) ~= "offensive" then
      local cur = p.slainRep[victim]
      p.slainRep[victim] = { n = math.max(ns.Count(n), cur and cur.n or 0), t = math.max(t or 0, cur and cur.t or 0) }
    end
  end
  p.slainRepAt = time()
  p.slainRepTotal = tonumber(f.total) or p.slainRepTotal
end

---------------------------------------------------------------------------
-- one time: kills already in the Feed (0.7.0 started noting who and whom) go into the lists
---------------------------------------------------------------------------
function Kills.Backfill(db)
  if db.killsBackfilled then return 0 end
  local added = 0
  for _, store in pairs(db.realms or {}) do
    for _, e in ipairs(store.feed or {}) do
      local victim = e.kind == "kill" and e.who and e.foes and e.foes[1]
      local p = victim and store.players and store.players[e.who]
      if p then
        Kills.AddTo(p, victim, nil, e.t)
        added = added + 1
      end
    end
  end
  db.killsBackfilled = true
  return added
end

ns.OnReady(function() ns.Try("kills-backfill", function() ns.Debug("KILLS-BACKFILL", Kills.Backfill(FriendsAndFoesDB)) end) end)
