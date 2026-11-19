local _, ns = ...
local L = ns.L

-- One pipeline for every event: own events are encoded/decoded exactly like
-- received ones, applied locally (feed + records), then broadcast if sharing is on.
local Events = {}
ns.Events = Events

local SHARE = { LVL = "level", LOOT = "loot", GEAR = "gear", ATK = "pvp", ENG = "pvp", DIE = "pvp", KILL = "pvp", SIGHT = "pvp" }
Events.SHARE = SHARE

local ICON = {
  level = "Interface\\Icons\\Spell_Holy_SurgeOfLight",
  attacked = "Interface\\Icons\\Ability_Warrior_Challange",
  engage = "Interface\\Icons\\Ability_Warrior_Charge",
  died = "Interface\\Icons\\Ability_Rogue_FeignDeath",
  kill = "Interface\\Icons\\Ability_DualWield",
  share = "Interface\\Icons\\INV_Letter_15",
  version = "Interface\\Icons\\INV_Misc_Note_01",
  fallback = "Interface\\Icons\\INV_Misc_QuestionMark",
}
ns.ICON = ICON

-- sim = true marks the event as simulated: it goes to the scratch store on every client.
-- Kill streak (kills in a row without dying in world PvP) is counted by the player's own client,
-- which sees all of their kills and deaths, and sent along with KILL / DIE.
local function trackStreak(kind, fields, sim)
  if sim then return end -- simulated events never touch the real streak
  local c = FriendsAndFoesCharDB
  if kind == "KILL" then
    c.streak = (c.streak or 0) + 1
    fields.streak = c.streak
  elseif kind == "DIE" then
    fields.ended = c.streak or 0
    c.streak = 0
  end
end

function Events.Emit(kind, fields, sim)
  trackStreak(kind, fields, sim)
  -- may friends pass this on to their other friends? (Options: "Friends may pass on my events")
  fields.rl = ns.Comm.RelayAllowed() and "1" or ""
  local _, class = UnitClass("player")
  local msg = { kind = kind, id = ns.NewId(sim), class = class, level = UnitLevel("player"), f = fields }
  local wire = ns.Comm.Fit(msg)
  if not wire then return end
  local decoded = ns.Comm.Decode(wire)
  if not decoded then return end
  decoded.from = ns.me
  Events.Apply(decoded, true)
  if SHARE[kind] and ns.S().share[SHARE[kind]] then
    ns.Comm.Broadcast(msg)
    if not sim then ns.Comm.Remember(kind, msg.id, fields) end -- for friends who are offline now
  end
end

---------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------
local function who(p) return ns.ClassColored(p.name, p.class) end

-- foes: enemy names the line is about (for their profile's recent PvP)
local function feed(p, kind, text, foes)
  -- their latest event, and when it happened (an older one caught up later doesn't replace it)
  local t = ns.Now()
  if p and (not p.lastTextAt or t >= p.lastTextAt) then p.lastText, p.lastTextAt = text, t end
  ns.Data.Feed(kind, text, p and p.name, foes)
end

-- names of decoded units, for feed()
local function namesOf(units)
  local out = {}
  for _, u in ipairs(units) do if u and u.name then out[#out + 1] = u.name end end
  return out
end

local function itemIcon(link)
  local getInstant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
  if getInstant then
    local ok, _, _, _, _, icon = pcall(getInstant, link)
    if ok and icon then return icon end
  end
  return ICON.fallback
end

local function mergeSubjects(titleFmt)
  return function(old, new)
    for _, s in ipairs(new.subjects) do
      local dup = false
      for _, o in ipairs(old.subjects) do if o == s then dup = true end end
      if not dup then old.subjects[#old.subjects + 1] = s end
    end
    old.title = titleFmt:format(ns.JoinNames(old.subjects))
    old.text = (#old.subjects == 1) and new.text or ""
  end
end

local function suppressAttackToast(name)
  local issecret = ns.issecret
  local inParty = UnitInParty and UnitInParty(name)
  if issecret(inParty) then return false end
  local inRaid = UnitInRaid and UnitInRaid(name)
  if issecret(inRaid) then return false end
  if not (inParty or inRaid) then return false end
  local inCombat = UnitAffectingCombat("player")
  if issecret(inCombat) then return false end
  return inCombat and true or false
end

-- Someone on your side (you, or a friend playing your faction) is never recorded as an enemy:
-- whatever a message says, they get a throwaway record that isn't saved anywhere.
local function scratch(name)
  return { name = name, k = 0, d = 0, a = 0, atk = 0, attacks = 0, kills = 0, suspect = 0, revenge = 0, victims = {}, scratch = true }
end

local function enemyTouch(u, zone)
  if ns.PvP.IsFriendly(u.name) then return scratch(u.name) end
  local e = ns.Data.Player(u.name)
  e.enemy = true
  ns.Data.Touch(e, { class = u.class, level = u.level, guild = u.guild, zone = zone })
  ns.PvP.NoteRace(e)
  return e
end

-- A kill puts someone on the hitlist, and so does attacking one of you first (an ATK: they
-- started it). Attacks counted on their enemy record (e.atk) are carried over when they're added.
-- victim: who they killed (nil for an attack).
local function hitTouch(u, zone, victim)
  if ns.PvP.IsFriendly(u.name) then return scratch(u.name) end
  local isNew = ns.Data.FindHit(u.name) == nil
  local h = ns.Data.Hit(u.name)
  ns.Data.Touch(h, { class = u.class, level = u.level, guild = u.guild, zone = zone })
  ns.PvP.NoteRace(h)
  if victim then h.victims[victim] = true end
  if isNew then
    local e = ns.Data.FindPlayer(u.name)
    if e and e.atk then h.attacks = math.max(h.attacks or 0, e.atk) end
  end
  return h
end

-- update someone already on the hitlist; never adds them
local function hitUpdate(u, zone)
  local h = ns.Data.FindHit(u.name)
  if h then ns.Data.Touch(h, { class = u.class, level = u.level, guild = u.guild, zone = zone }) end
  return h
end

---------------------------------------------------------------------------
-- version notices (once per session per friend)
---------------------------------------------------------------------------
local versionNotified = {}

function Events.NewerVersion(sender, version)
  if versionNotified[sender] then return end
  versionNotified[sender] = true
  ns.Toast.Push({
    category = "progress", icon = ICON.version,
    title = L.TOAST_NEWER_VERSION,
    text = version and L.TOAST_NEWER_VERSION_TEXT:format(sender, version, ns.VERSION)
      or L.TOAST_NEWER_PROTOCOL_TEXT:format(sender),
  })
end

-- friends on an older version: one quiet chat line per session naming them (gathered for a
-- while after you log in, so everyone online is in the one line), and again for anyone new
local OLDER_GATHER = 30
local olderSeen, olderTold, olderPending = {}, {}, false
function Events.OlderVersion(sender, version)
  if not sender or olderTold[sender] then return end
  olderSeen[sender] = version
  if olderPending then return end
  olderPending = true
  C_Timer.After(OLDER_GATHER, function()
    olderPending = false
    local names = {}
    for name, v in pairs(olderSeen) do
      names[#names + 1] = ns.ClassColored(name) .. " (" .. v .. ")"
      olderTold[name] = true
    end
    wipe(olderSeen)
    if #names == 0 then return end
    table.sort(names)
    ns.Toast.Chat(L.CHAT_OLDER_VERSIONS:format(ns.JoinNames(names), ns.VERSION))
    ns.Debug("OLDER", table.concat(names, ", "))
  end)
end

-- a friend's client speaks another protocol: neither side can read the other
function Events.ProtocolMismatch(sender, theirsIsNewer)
  if theirsIsNewer then return Events.NewerVersion(sender, nil) end
  if versionNotified[sender] then return end
  versionNotified[sender] = true
  ns.Toast.Push({
    category = "progress", icon = ICON.version,
    title = L.TOAST_OLDER_VERSION,
    text = L.TOAST_OLDER_PROTOCOL_TEXT:format(sender),
  })
end

---------------------------------------------------------------------------
-- apply
---------------------------------------------------------------------------
local H = {}

-- events whose zone is where the sender was (their own fights and sightings)
local PLACE_KINDS = { ATK = true, ENG = true, DIE = true, KILL = true, SIGHT = true }

-- Text from friends' messages is shown in chat and the window: only plain text, a class token,
-- or a real item link gets through (a modified client can't slip in textures or other links)
local TEXT_FIELDS = { zone = true, guild = true, vguild = true }
local CLASS_FIELDS = { class = true, vclass = true }
-- numbers that get shown: whole and never negative
local NUMBER_FIELDS = { level = true, vlevel = true, streak = true, ended = true, count = true, epics = true,
  k = true, d = true, bt = true, added = true }

function Events.Clean(msg)
  if msg.level then msg.level = ns.Count(msg.level) end
  local f = msg.f
  for k, v in pairs(f) do
    if type(v) == "string" and v ~= "" then
      if TEXT_FIELDS[k] then f[k] = ns.Profile.CleanText(v, 64) or ""
      elseif CLASS_FIELDS[k] then f[k] = v:match("^%u+$") or ""
      elseif NUMBER_FIELDS[k] and tonumber(v) then f[k] = tostring(ns.Count(v))
      elseif k == "link" then f[k] = ns.SafeLink(v) or "" end
    end
  end
end

local simTold = {} -- friends whose test alerts you were told about (once per session)

function Events.Apply(msg, isSelf)
  local h = H[msg.kind]
  if not h then return end
  if not isSelf then Events.Clean(msg) end
  local sim = msg.id:sub(1, 1) == "S"
  ns.simulating = sim
  local ok, err = pcall(function()
    local p = ns.Data.Player(msg.from)
    p.friend = true
    if isSelf then p.self = true end
    if msg.version and msg.version ~= "" then p.version = msg.version end
    -- msg.ago: a friend's event from while you were offline (caught up, or passed on by another
    -- friend). Feed and records only, no alerts - and it counts at the time it HAPPENED, so an
    -- old event doesn't make them look "seen just now".
    if msg.ago then
      ns.past, ns.eventTime = true, time() - msg.ago
    end
    ns.Data.Touch(p, { class = msg.class, level = msg.level })
    -- their PvP alerts say where they were
    if not isSelf and PLACE_KINDS[msg.kind] then ns.Profile.SeenAt(p, msg.f.zone, ns.Now()) end
    h(msg, isSelf, p, msg.f)
  end)
  ns.simulating, ns.past, ns.eventTime = false, nil, nil
  if ok and msg.ago then Events.CaughtUp(msg.from) end
  if not ok then error(err, 0) end

  if not isSelf and not sim and ns.VersionNewer(msg.version, ns.VERSION) then
    Events.NewerVersion(msg.from, msg.version)
  elseif not isSelf and not sim and msg.version and ns.VersionNewer(ns.VERSION, msg.version) then
    Events.OlderVersion(msg.from, msg.version)
  end
  -- your own simulation switches the window to it; a friend's test alerts don't take your window
  -- over (one chat line says they're there)
  if sim and (isSelf or msg.localSim) then
    ns.viewSim = true
  elseif sim and not simTold[msg.from] then
    simTold[msg.from] = true
    ns.Toast.Chat(L.SIM_FROM_FRIEND:format(ns.ClassColored(msg.from)))
  end
  if not sim and ns.Marks then ns.Marks.Refresh() end -- a new hitlist entry may be on screen
  if ns.UI and ns.UI.OnDataChanged then ns.UI.OnDataChanged() end
end

H.LVL = function(_, isSelf, p, f)
  local lvl = tonumber(f.level)
  if not lvl or lvl < 1 then return end -- (a broken level - 0, or negative before cleaning - is dropped)
  p.level = ns.past and math.max(tonumber(p.level) or 0, lvl) or lvl
  local line = L.FEED_LEVEL:format(who(p), lvl)
  feed(p, "level", line)
  if isSelf then return end
  local milestone = lvl >= ns.MILESTONE_LEVEL
  -- Options: every level, every 5, every 10, or only max level (still in the Feed)
  local every = tonumber(ns.S().levelEvery) or 1
  if not milestone and every > 1 and lvl % every ~= 0 then
    ns.Debug("TOAST", "level", ns.Plain(line), "skipped: only every " .. every .. " levels (your setting)")
    return
  end
  ns.Toast.Push({
    kind = "level", category = "progress", icon = ICON.level, chat = line, milestone = milestone,
    subjects = { who(p) }, title = milestone and L.TOAST_LEVEL_MAX:format(who(p), lvl) or line,
    collapseKey = "level", merge = mergeSubjects(L.TOAST_LEVEL),
  })
end

H.LOOT = function(_, isSelf, p, f)
  if f.link == "" then return end
  local crafted = f.source == "craft"
  local line = (crafted and L.FEED_CRAFT or L.FEED_LOOT):format(who(p), f.link)
  feed(p, "loot", line)
  if isSelf then return end
  ns.Toast.Push({
    kind = "loot", category = "progress", icon = itemIcon(f.link), link = f.link,
    chat = line, milestone = not crafted, -- a looted epic BoE always toasts
    title = line,
  })
end

H.GEAR = function(_, isSelf, p, f)
  if f.link == "" then return end
  local count = tonumber(f.count) or 1
  local text = (count > 1) and L.TOAST_GEAR_MORE:format(f.link, count - 1) or f.link
  local line = L.FEED_GEAR:format(who(p), text) -- the Feed keeps the whole batch
  feed(p, "gear", line)
  if isSelf then return end
  -- "Epic only": the toast counts just the epics of the batch (senders before 0.6.2 don't say)
  local epics = tonumber(f.epics)
  if epics and (tonumber(ns.S().gearMin) or 3) >= 4 and epics >= 1 and epics ~= count then
    count = epics
    text = (count > 1) and L.TOAST_GEAR_MORE:format(f.link, count - 1) or f.link
    line = L.FEED_GEAR:format(who(p), text)
  end
  -- Options: blue or better, or epic only (still in the Feed)
  local q = ns.ItemQuality(f.link)
  local min = tonumber(ns.S().gearMin) or 3
  if q and q < min then
    ns.Debug("TOAST", "gear", ns.Plain(line), "skipped: below the gear quality you chose")
    return
  end
  ns.Toast.Push({
    chat = line, kind = "gear", category = "progress", icon = itemIcon(f.link), link = f.link, firstLink = f.link, count = count,
    title = line, who = who(p),
    collapseKey = "gear:" .. p.name,
    merge = function(old, new)
      old.count = old.count + new.count
      old.title = L.FEED_GEAR:format(old.who, L.TOAST_GEAR_MORE:format(old.firstLink, old.count - 1))
    end,
  })
end

local atkSeen = {}
local atkSeenCount = 0

H.ATK = function(msg, isSelf, p, f)
  if atkSeenCount > 2000 then wipe(atkSeen); atkSeenCount = 0 end
  local attackers = ns.DecodeUnits(f.attackers)
  local encKey = msg.from .. ":" .. f.enc
  local names = {}
  for _, u in ipairs(attackers) do
    if u.name then
      names[#names + 1] = ns.ClassColored(u.name, u.class)
      local k = encKey .. ":" .. u.name
      if not atkSeen[k] then
        atkSeen[k] = true
        atkSeenCount = atkSeenCount + 1
        local e = enemyTouch(u, f.zone)
        e.atk = (e.atk or 0) + 1
        -- they attacked first (a fight you started is an ENG, not an ATK): on the hitlist
        local isNew = ns.Data.FindHit(u.name) == nil
        local h = hitTouch(u, f.zone) -- (a new entry starts with their attacks so far, this one included)
        if not isNew then h.attacks = (h.attacks or 0) + 1 end
      end
    end
  end
  if atkSeen[encKey] then return end
  atkSeen[encKey] = true
  atkSeenCount = atkSeenCount + 1

  local by = (#names > 0) and ns.JoinNames(names) or L.UNKNOWN_ENEMY
  local title, text, line = ns.Flavor.Attacked(p, who(p), by, attackers, f.zone)
  feed(p, "attacked", line, namesOf(attackers))
  if isSelf then return end
  if suppressAttackToast(msg.from) then
    ns.Debug("TOAST", "attacked", msg.from, "skipped: they're in your group and you're in combat")
    return
  end
  ns.Toast.Push({
    chat = line, kind = "attacked",
    -- you can only help if you're in the same zone: elsewhere it's a chat line
    far = ns.S().nearbyOnly and not ns.PvP.IsMyZone(f.zone), category = "pvp", icon = ICON.attacked,
    title = title, text = text,
    player = attackers[1] and attackers[1].name,
  })
end

-- a friend started a fight with an enemy player
H.ENG = function(msg, isSelf, p, f)
  local u = ns.DecodeUnit(f.target)
  if not (u and u.name) then return end
  enemyTouch(u, f.zone)
  local h = hitUpdate(u, f.zone) -- doesn't add them to the hitlist
  local title, text, line = ns.Flavor.Engage(p, who(p), ns.ClassColored(u.name, u.class), h, f.zone)
  feed(p, "engage", line, { u.name })
  if isSelf then return end
  ns.Toast.Push({
    chat = line, kind = "engage", category = "pvp", icon = ICON.engage,
    title = title, text = text, player = u.name,
    far = ns.S().nearbyOnly and not ns.PvP.IsMyZone(f.zone), -- far away: a chat line
  })
end

H.DIE = function(msg, isSelf, p, f)
  p.d = p.d + 1
  -- nobody on your side is ever a killer or helper (older clients could name a friend who was in
  -- the death recap): such names are dropped here too
  local function onYourSide(name) return name == msg.from or ns.PvP.IsFriendly(name) end
  local killer = ns.DecodeUnit(f.killer)
  if killer and killer.name and onYourSide(killer.name) then killer = nil end
  if isSelf and not msg.id:find("^S") then
    Events.WeeklyAdd("d", killer and killer.name)
    ns.Profile.Changed() -- friends' leaderboards
  end
  local suspect = f.conf == "s"
  local by, h
  if killer and killer.name then
    local e = enemyTouch(killer, f.zone)
    e.k = e.k + 1
    h = hitTouch(killer, f.zone, msg.from)
    h.kills = h.kills + 1
    if suspect then h.suspect = h.suspect + 1 end
    by = ns.ClassColored(killer.name, killer.class) .. (suspect and L.SUSPECT_TAG or "")
  end
  local helpers, foes = {}, { killer and killer.name }
  for _, u in ipairs(ns.DecodeUnits(f.assists)) do
    if u.name and not onYourSide(u.name) then
      foes[#foes + 1] = u.name
      helpers[#helpers + 1] = ns.ClassColored(u.name, u.class)
      local e = enemyTouch(u, f.zone)
      e.a = e.a + 1
      hitUpdate(u, f.zone) -- assists don't add anyone; only the killer goes on the hitlist
    end
  end

  local title, text, line = ns.Flavor.Died(p, who(p), by, h, f.zone, tonumber(f.ended), helpers)
  feed(p, "died", line, foes)
  if isSelf then return end
  ns.Toast.Push({
    chat = line, kind = "died", category = "pvp", icon = ICON.died,
    title = title, text = text,
    player = killer and killer.name,
  })
end

H.KILL = function(msg, isSelf, p, f)
  if isSelf and not msg.id:find("^S") then
    Events.WeeklyAdd("k")
    ns.Profile.Changed()
  end
  local name = ns.CleanName(f.victim)
  -- someone on your side is never a victim (it can only be a misread): a kill without a name
  if name and ns.PvP.IsFriendly(name) then name = nil end
  p.k = p.k + 1
  local streak = tonumber(f.streak)
  if not name then
    -- the killer's client couldn't tell who died (Forever's honor message has no name): counted
    -- on its own so the kill list can show them as one "name not readable" line
    p.kx = ns.Count(p.kx) + 1
    local title, text, line = ns.Flavor.Kill(p, who(p), nil, nil, nil, false, f.zone, streak)
    feed(p, "kill", line)
    if isSelf then return end
    ns.Toast.Push({
      chat = line, milestone = ns.Flavor.StreakMilestone(streak), kind = "kill", category = "pvp", icon = ICON.kill,
      title = title, text = text, header = ns.Flavor.StreakMilestone(streak) and L.HEADER_STREAK or nil,
    })
    return
  end
  local victim = { name = name, class = f.vclass ~= "" and f.vclass or nil, level = f.vlevel, guild = f.vguild ~= "" and f.vguild or nil }
  local e = enemyTouch(victim, f.zone)
  local counted = ns.Data.EnemyDied(name)
  ns.Kills.Add(p, e.name, f.zone) -- the killer's kill list
  -- their bounty: collected by everyone who got the kill (never in the simulation)
  if not msg.id:find("^S") and e.enemy then
    ns.Bounty.OnKill(isSelf and ns.me or p.name, e.name)
    ns.Contracts.OnKill(isSelf and ns.me or p.name, e.name) -- the bounty board: contracts on them are done
  end

  local hit = ns.Data.FindHit(name)
  local revenge = false
  if hit and counted then
    hit.revenge = (hit.revenge or 0) + 1
    hit.lastRevenge = ns.Now()
    revenge = true
  end

  local v = ns.ClassColored(name, victim.class)
  local title, text, line = ns.Flavor.Kill(p, who(p), v, e, hit, revenge, f.zone, streak)
  feed(p, "kill", line, { name })
  if isSelf then return end
  ns.Toast.Push({
    header = (revenge and L.HEADER_REVENGE) or (ns.Flavor.StreakMilestone(streak) and L.HEADER_STREAK) or nil,
    chat = line, milestone = revenge or ns.Flavor.StreakMilestone(streak), kind = "kill", category = "pvp", icon = ICON.kill,
    title = title, text = text,
    player = name,
  })
end

-- after a catch-up: one quiet chat line saying what came in, no toasts
local caught, caughtFrom, caughtPending = 0, {}, false
function Events.CaughtUp(from)
  caught = caught + 1
  caughtFrom[from] = true
  if caughtPending then return end
  caughtPending = true
  C_Timer.After(8, function()
    caughtPending = false
    local names = {}
    for name in pairs(caughtFrom) do names[#names + 1] = ns.ClassColored(name) end
    table.sort(names)
    if caught > 0 then
      ns.Toast.Chat(L.CHAT_CAUGHT_UP:format(caught, ns.JoinNames(names)))
      ns.Debug("CATCHUP-GOT", caught)
    end
    caught = 0
    wipe(caughtFrom)
  end)
end

-- shared hitlist chunk: merge by taking the max of each counter, never overwrite notes
local shareSeen = {}

-- a friend spotted someone from their hitlist
H.SIGHT = function(msg, isSelf, p, f)
  if isSelf then return end
  local name = ns.CleanName(f.name)
  if not name or ns.PvP.IsFriendly(name) then return end -- (never a friend on your side)
  local u = { name = name, class = f.class ~= "" and f.class or nil, level = f.level, guild = f.guild ~= "" and f.guild or nil }
  enemyTouch(u, f.zone)
  local h = hitUpdate(u, f.zone)
  if not ns.PvP.SightingDue(name) then
    ns.Debug("TOAST", "sighting", name, "skipped: already alerted about them in the last 5 minutes")
    return
  end
  local line = ns.Toast.Sighting(name, u.class, f.zone, h, who(p))
  feed(p, "sighting", line, { name })
end

-- a friend's profile: their own all-time K/D, most wanted, zone and status
H.PRO = function(_, isSelf, p, f)
  if isSelf then return end
  ns.Profile.Apply(p, f)
end

-- shared groups: membership, and stats passed along by members
-- a friend's contract on the bounty board (Contracts.lua)
H.BTY = function(msg, isSelf, _, f)
  if isSelf or msg.id:find("^S") then return end
  ns.Contracts.OnMessage(msg.from, f)
end

H.GRP = function(msg, isSelf, _, f)
  if isSelf then return end
  ns.Groups.OnGroup(msg.from, f)
end

H.GST = function(msg, isSelf, _, f)
  if isSelf then return end
  ns.Groups.OnStats(msg.from, f)
end

-- kill lists: a friend asks for yours, or answers with theirs
H.KLQ = function(msg, isSelf, _, f)
  if isSelf then return end
  ns.Kills.Answer(msg.from, f.who)
end

H.KLA = function(msg, isSelf, _, f)
  if isSelf then return end
  ns.Kills.OnAnswer(msg.from, f)
end

-- weekly summary: your own takedowns and deaths, and who killed you most
function Events.WeeklyAdd(kind, killer)
  local w = FriendsAndFoesDB.weekly
  if not w then return end
  if kind == "k" then w.k = (w.k or 0) + 1 end
  if kind == "d" then
    w.d = (w.d or 0) + 1
    if killer then
      w.killers = w.killers or {}
      w.killers[killer] = (w.killers[killer] or 0) + 1
    end
  end
end

H.HIT = function(msg, isSelf, p, f)
  if isSelf then return end
  local added = 0
  for _, raw in ipairs(ns.Split(f.entries or "", ";")) do
    local e = ns.Split(raw, ":")
    local name = ns.CleanName(e[1])
    local isNew = name and ns.Data.FindHit(name) == nil
    -- don't add someone your "Forget hitlist players" setting would remove at the next login
    local hours = tonumber(e[8])
    local forget = tonumber(ns.S().forgetAfter) or 0
    local tooOld = isNew and forget > 0 and hours and hours / 24 > forget
    -- a new entry needs a kill or an attack on one of you (an empty one is never added)
    -- (never someone on your side, even if they are on the sharer's list)
    if name and not tooOld and not ns.PvP.IsFriendly(name) and (not isNew or (tonumber(e[6]) or 0) > 0 or (tonumber(e[5]) or 0) > 0) then
      local h = ns.Data.Hit(name)
      local cls = e[2] and e[2]:match("^%u+$")
      if cls then h.class = h.class or cls end
      local lvl = tonumber(e[3])
      if lvl and lvl > 0 then h.level = math.max(h.level or 0, lvl) end
      local g = ns.Profile.CleanText(e[4], 64)
      if g then h.guild = h.guild or g end
      h.attacks = math.max(h.attacks or 0, tonumber(e[5]) or 0)
      h.kills = math.max(h.kills or 0, tonumber(e[6]) or 0)
      h.revenge = math.max(h.revenge or 0, tonumber(e[7]) or 0)
      if hours then
        local seenAt = time() - hours * 3600
        if not h.lastSeen or seenAt > h.lastSeen then h.lastSeen = seenAt end
      end
      h.sharedBy = h.sharedBy or msg.from
      local en = ns.Data.Player(name)
      en.enemy = true
      en.class = en.class or h.class
      if isNew then added = added + 1 end
    end
  end

  local key = msg.from .. ":" .. f.share
  local s = shareSeen[key]
  if not s then
    s = { added = 0 }
    shareSeen[key] = s
  end
  s.added = s.added + added
  local text = L.FEED_SHARE:format(who(p), s.added)
  s.first = s.entry == nil
  if s.entry then s.entry.text = text else s.entry = ns.Data.Feed("share", text) end
  ns.Toast.Push({
    kind = "share", category = "progress", icon = ICON.share, chat = L.CHAT_SHARE:format(who(p)), quiet = not s.first,
    title = L.TOAST_SHARE:format(who(p)), text = L.TOAST_SHARE_TEXT:format(s.added),
    collapseKey = "share:" .. key,
    merge = function(old) old.text = L.TOAST_SHARE_TEXT:format(s.added) end,
  })
end
