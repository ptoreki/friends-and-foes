local _, ns = ...
local L = ns.L

-- One pipeline for every event: own events are encoded/decoded exactly like
-- received ones, applied locally (feed + records), then broadcast if sharing is on.
local Events = {}
ns.Events = Events

local SHARE = { LVL = "level", LOOT = "loot", GEAR = "gear", ATK = "pvp", ENG = "pvp", DIE = "pvp", KILL = "pvp", AST = "pvp", SIGHT = "pvp" }
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

-- Kill streak (kills in a row without dying in world PvP) is counted by the player's own client,
-- which sees all of their kills and deaths, and sent along with KILL / DIE.
local function trackStreak(kind, fields)
  local c = FriendsAndFoesCharDB
  if kind == "KILL" then
    c.streak = (c.streak or 0) + 1
    ns.Stats.NoteStreak(c.streak)
    fields.streak = c.streak
  elseif kind == "DIE" then
    fields.ended = c.streak or 0
    c.streak = 0
  end
end

-- The PvP kinds that carry a zone, and so can come from a battleground
local BG_KINDS = { ATK = true, ENG = true, DIE = true, KILL = true, AST = true, SIGHT = true }

function Events.Emit(kind, fields)
  -- in a battleground: a Feed line for a kill or death at most (Events.Battleground), never counted
  -- (no streak), never sent to friends
  if BG_KINDS[kind] and ns.InstanceType() == "pvp" then
    local _, class = UnitClass("player")
    local msg = { kind = kind, id = ns.NewId(), class = class, level = UnitLevel("player"), f = fields, bg = true, from = ns.me }
    ns.Try("battleground", Events.Battleground, msg, true)
    return
  end
  trackStreak(kind, fields)
  -- may friends pass this on to their other friends? (Options: "Friends may pass on my events")
  fields.rl = ns.Comm.RelayAllowed() and "1" or ""
  local _, class = UnitClass("player")
  local msg = { kind = kind, id = ns.NewId(), class = class, level = UnitLevel("player"), f = fields }
  local wire = ns.Comm.Fit(msg)
  if not wire then return end
  local decoded = ns.Comm.Decode(wire)
  if not decoded then return end
  decoded.from = ns.me
  Events.Apply(decoded, true)
  if SHARE[kind] and ns.S().share[SHARE[kind]] then
    ns.Comm.Broadcast(msg)
    ns.Comm.Remember(kind, msg.id, fields) -- for friends who are offline now
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
  return ns.Data.Feed(kind, text, p and p.name, foes)
end

-- The Feed shows the level each player was at the time, small and grey after the name: tags =
-- { { shownName, level, isEnemy }, ... } (the name as it stands in the line, class colour included;
-- the level goes after its first appearance, outside any link). Toasts and chat keep the plain line.
local function leveled(line, tags)
  for _, t in ipairs(tags) do
    local tag = ns.LevelTag(t[2], t[3])
    if tag ~= "" and type(t[1]) == "string" and t[1] ~= "" then
      local _, b = line:find(t[1], 1, true)
      if b then line = line:sub(1, b) .. tag .. line:sub(b + 1) end
    end
  end
  return line
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

-- who an enemy has attacked or killed (a set of names with the time, the last HITWHO_MAX kept)
local HITWHO_MAX = 10
local function noteWho(h, name)
  if not (h and name) then return end
  h.hitWho = type(h.hitWho) == "table" and h.hitWho or {}
  h.hitWho[name] = ns.Now()
  local n = 0
  for _ in pairs(h.hitWho) do n = n + 1 end
  while n > HITWHO_MAX do
    local oldest, ot
    for k, t in pairs(h.hitWho) do
      if not ot or (tonumber(t) or 0) < ot then oldest, ot = k, tonumber(t) or 0 end
    end
    h.hitWho[oldest] = nil
    n = n - 1
  end
end
Events.NoteWho = noteWho

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
local PLACE_KINDS = { ATK = true, ENG = true, DIE = true, KILL = true, AST = true, SIGHT = true }

-- Text from friends' messages is shown in chat and the window: only plain text, a class token,
-- or a real item link gets through (a modified client can't slip in textures or other links)
local TEXT_FIELDS = { zone = true, guild = true, vguild = true }
local CLASS_FIELDS = { class = true, vclass = true }
-- numbers that get shown: whole and never negative
local NUMBER_FIELDS = { level = true, vlevel = true, streak = true, ended = true, count = true, epics = true,
  k = true, d = true, bt = true, btw = true, bwk = true, added = true, last = true }

-- Who gets the credit for a kill: a credit is { blow = "1"|"pet"|nil, last = seconds|nil }.
-- A killing blow beats none (the first of two stays); with no blow the more recent attacker (the
-- smaller `last`) wins, a known `last` beating an unknown one; nothing known: the first stays.
-- Returns true when `a` outranks `b`.
function Events.BetterCredit(a, b)
  a, b = a or {}, b or {}
  if a.blow or b.blow then return a.blow ~= nil and b.blow == nil end
  if a.last and b.last then return a.last < b.last end
  return a.last ~= nil and b.last == nil
end

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

-- A kill or death in a battleground: never counted anywhere (no kills, deaths, K/D, kill list,
-- hitlist, notoriety, bounty, streak, stats), never passed on. At most a Feed line and an alert,
-- and only when "Dungeons, raids, battlegrounds" is not off. Your own show in the Feed only, like
-- your other kills; a friend's also alert. Anything caught up from before is dropped.
function Events.Battleground(msg, isSelf)
  if ns.S().instances == "off" or msg.ago then return end
  if msg.kind ~= "KILL" and msg.kind ~= "DIE" then return end
  local f = msg.f or {}
  local from = isSelf and ns.me or msg.from
  local subject = ns.ClassColored(from, msg.class)
  local line, kind
  if msg.kind == "KILL" then
    local victim = ns.CleanName(f.victim)
    local class = type(f.vclass) == "string" and f.vclass:match("^%u+$") or nil
    line, kind = L.BG_KILL:format(subject, victim and ns.ClassColored(victim, class) or L.BG_SOMEONE), "kill"
  else
    local killer = ns.DecodeUnit(f.killer)
    line, kind = L.BG_DIE:format(subject, killer and killer.name and ns.ClassColored(killer.name, killer.class) or L.BG_SOMEONE), "died"
  end
  line = line .. " |cff888888(" .. L.BG_TAG .. ")|r"
  ns.Data.Feed(kind, line) -- (no who / foes: it isn't on anyone's profile)
  if isSelf then return end
  ns.Toast.Push({ kind = kind, category = "pvp", icon = ICON[kind], chat = line, title = line })
end

function Events.Apply(msg, isSelf)
  local h = H[msg.kind]
  if not h then return end
  -- (ids starting with "S": a friend on 0.9.3 or older testing with /fnf sim - never real data)
  if msg.id:sub(1, 1) == "S" then return end
  if not isSelf then Events.Clean(msg) end
  -- from a battleground (flagged, or by its zone name from an older friend): see Events.Battleground
  if BG_KINDS[msg.kind] and (msg.bg or ns.IsBattlegroundZone(msg.f and msg.f.zone)) then
    ns.Try("battleground", Events.Battleground, msg, isSelf)
    return
  end
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
  ns.past, ns.eventTime = nil, nil
  if ok and msg.ago then Events.CaughtUp(msg.from) end
  if not ok then error(err, 0) end

  if not isSelf and ns.VersionNewer(msg.version, ns.VERSION) then
    Events.NewerVersion(msg.from, msg.version)
  elseif not isSelf and msg.version and ns.VersionNewer(ns.VERSION, msg.version) then
    Events.OlderVersion(msg.from, msg.version)
  end
  if ns.Marks then ns.Marks.Refresh() end -- a new hitlist entry may be on screen
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
  -- epic gear only: the toast counts just the epics of a batch (friends on 0.9.3 or older also
  -- send blue gear; senders before 0.6.2 don't say how many were epic)
  local epics = tonumber(f.epics)
  if epics and epics >= 1 and epics ~= count then
    count = epics
    text = (count > 1) and L.TOAST_GEAR_MORE:format(f.link, count - 1) or f.link
    line = L.FEED_GEAR:format(who(p), text)
  end
  local q = ns.ItemQuality(f.link)
  if q and q < 4 then
    ns.Debug("TOAST", "gear", ns.Plain(line), "skipped: not epic")
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
        h.lastOffence = math.max(tonumber(h.lastOffence) or 0, ns.Now())
        noteWho(h, isSelf and ns.me or p.name)
      end
    end
  end
  if atkSeen[encKey] then return end
  atkSeen[encKey] = true
  atkSeenCount = atkSeenCount + 1

  local by = (#names > 0) and ns.JoinNames(names) or L.UNKNOWN_ENEMY
  local title, text, line = ns.Flavor.Attacked(p, who(p), by, attackers, f.zone)
  local tags = { { who(p), msg.level } }
  for _, u in ipairs(attackers) do
    if u.name then tags[#tags + 1] = { ns.ClassColored(u.name, u.class), u.level, true } end
  end
  feed(p, "attacked", leveled(line, tags), namesOf(attackers))
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
  feed(p, "engage", leveled(line, { { who(p), msg.level }, { ns.ClassColored(u.name, u.class), u.level, true } }), { u.name })
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
  if isSelf then
    Events.WeeklyAdd("d", killer and killer.name)
    if not ns.past then ns.Stats.LogDeath(killer and killer.name, f.zone) end -- (your PvP death log, Stats.lua)
    ns.Profile.Changed() -- friends' leaderboards
  end
  local suspect = f.conf == "s"
  local by, h
  if killer and killer.name then
    local e = enemyTouch(killer, f.zone)
    e.k = e.k + 1
    h = hitTouch(killer, f.zone, msg.from)
    h.kills = h.kills + 1
    noteWho(h, msg.from)
    -- when they killed (for a rampage: the last 10) and their last offence (for cooling)
    h.killTimes = h.killTimes or {}
    h.killTimes[#h.killTimes + 1] = ns.Now()
    while #h.killTimes > 10 do table.remove(h.killTimes, 1) end
    h.lastOffence = math.max(tonumber(h.lastOffence) or 0, ns.Now())
    if suspect then h.suspect = h.suspect + 1 end
    by = ns.ClassColored(killer.name, killer.class) .. (suspect and L.SUSPECT_TAG or "")
  end
  local helpers, foes = {}, { killer and killer.name }
  local tags = { { who(p), msg.level } }
  if killer and killer.name then tags[2] = { ns.ClassColored(killer.name, killer.class), killer.level, true } end
  for _, u in ipairs(ns.DecodeUnits(f.assists)) do
    if u.name and not onYourSide(u.name) then
      foes[#foes + 1] = u.name
      helpers[#helpers + 1] = ns.ClassColored(u.name, u.class)
      tags[#tags + 1] = { helpers[#helpers], u.level, true }
      local e = enemyTouch(u, f.zone)
      e.a = e.a + 1
      hitUpdate(u, f.zone) -- assists don't add anyone; only the killer goes on the hitlist
    end
  end

  local title, text, line = ns.Flavor.Died(p, who(p), by, h, f.zone, tonumber(f.ended), helpers)
  feed(p, "died", leveled(line, tags), foes)
  if isSelf then return end
  ns.Toast.Push({
    chat = line, kind = "died", category = "pvp", icon = ICON.died,
    title = title, text = text,
    player = killer and killer.name,
  })
end

-- enemy name -> GetTime() you reported their death yourself, or sent an AST for it: not again
-- within ASSIST_ONCE seconds (you'd already be one of the killers)
local assisted, ASSIST_ONCE = {}, 60

-- One death, one toast and one Feed line, however many friends report the kill: a second killer's
-- report of the same victim within SAME_DEATH seconds, with the victim not seen alive in between,
-- folds into the first (a new death - Reincarnation, a soulstone, a resurrection - is its own).
local SAME_DEATH = 60
local deaths = {} -- victim -> { t = first report (GetTime), killers = set, names = {...}, entry = Feed entry, zone }
local function mergeDeath(old, new)
  old.title, old.text, old.chat = new.title, new.text, new.chat
end

H.KILL = function(msg, isSelf, p, f)
  if isSelf then
    Events.WeeklyAdd("k")
    ns.Profile.Changed()
  end
  local name = ns.CleanName(f.victim)
  ns.Debug("KILL", isSelf and "you" or p.name, "victim " .. tostring(name or "(unnamed)"), "blow " .. tostring(f.blow ~= "" and f.blow or "-"), "last " .. tostring(f.last ~= "" and f.last or "?"), ns.past and "caught up" or "live")
  -- someone on your side is never a victim (it can only be a misread): a kill without a name
  if name and ns.PvP.IsFriendly(name) then name = nil end
  -- your own live kill goes in your kill log (Stats.lua); a caught-up one never does
  if isSelf and not ns.past then ns.Stats.Log(name, f.vlevel, f.zone) end
  p.k = p.k + 1
  local streak = tonumber(f.streak)
  if not name then
    -- the killer's client couldn't tell who died (Forever's honor message has no name): counted
    -- on its own so the kill list can show them as one "name not readable" line
    p.kx = ns.Count(p.kx) + 1
    local title, text, line = ns.Flavor.Kill(p, who(p), nil, nil, nil, false, f.zone, streak)
    if f.blow == "1" then title, line = title .. L.KILLING_BLOW_TAG, line .. L.KILLING_BLOW_TAG end
    if f.blow == "pet" then title, line = title .. L.PET_BLOW_TAG, line .. L.PET_BLOW_TAG end
    feed(p, "kill", leveled(line, { { who(p), msg.level } }))
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
  -- their bounty: collected by everyone who got the kill
  if e.enemy then
    -- who gets the credit: the killing blow, when the game says whose it was; else everyone who got
    -- the kill (notoriety) / the first to report it (a bounty)
    local credit = { blow = (f.blow == "1" or f.blow == "pet") and f.blow or nil, last = tonumber(f.last) }
    ns.Bounty.OnKill(isSelf and ns.me or p.name, e.name, credit)
    ns.Contracts.OnKill(isSelf and ns.me or p.name, e.name, credit) -- the bounty board: contracts on them are done
    -- you healed or buffed this friend a moment ago, outside their party (so no honor, no KILL of
    -- your own): you were in on it, and your friends are told (once per victim)
    local at = GetTime()
    if isSelf then
      assisted[e.name] = at
    elseif ns.past then
      ns.Debug("AST-SKIP", e.name, "a caught-up kill")
    elseif not ns.PvP.SupportedRecently(p.name, ns.PvP.SUPPORT_WINDOW) then
      ns.Debug("AST-SKIP", e.name, "you did not support " .. p.name .. " in the last " .. ns.PvP.SUPPORT_WINDOW .. " s")
    elseif assisted[e.name] and at - assisted[e.name] <= ASSIST_ONCE then
      ns.Debug("AST-SKIP", e.name, "already reported or assisted in the last " .. ASSIST_ONCE .. " s")
    else
      assisted[e.name] = at
      ns.Debug("AST-SEND", e.name, "helped " .. p.name)
      Events.Emit("AST", { victim = e.name, vclass = f.vclass or "", vlevel = f.vlevel or "", zone = f.zone or "", helped = p.name })
    end
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
  -- their own killing blow (0.9.4, when the game says so): marked, and counted on their record
  if f.blow == "1" then
    title, line = title .. L.KILLING_BLOW_TAG, line .. L.KILLING_BLOW_TAG
    p.blows = ns.Count(p.blows) + 1
  elseif f.blow == "pet" then
    title, line = title .. L.PET_BLOW_TAG, line .. L.PET_BLOW_TAG
  end
  local milestone = revenge or ns.Flavor.StreakMilestone(streak)
  local key = isSelf and ns.me or p.name
  local now = GetTime()
  local d = (not ns.past) and deaths[name] or nil
  if d then
    local why
    if d.killers[key] then why = "the same killer again"
    elseif now - d.t > SAME_DEATH then why = "more than " .. SAME_DEATH .. " s after the first report"
    elseif ns.PvP.SeenAliveSince(name, d.t) then why = "seen alive since the first report" end
    if why then
      ns.Debug("KILL-NEWDEATH", name, why)
      d = nil
    end
  end
  if d then
    -- the same death, reported by another killer: one Feed line and one toast naming everyone
    d.killers[key] = true
    local shown = isSelf and L.KILL_YOU_NAME or who(p)
    local shownL = shown .. ns.LevelTag(msg.level)
    if isSelf then
      table.insert(d.names, 1, shown)
      table.insert(d.namesL, 1, shownL)
    else
      d.names[#d.names + 1] = shown
      d.namesL[#d.namesL + 1] = shownL
    end
    local together = L.KILL_TOGETHER:format(ns.JoinNames(d.names), v)
    local place = ns.Flavor.Place(d.zone)
    local both = together .. ns.Flavor.SEP .. place
    -- the Feed line keeps each killer's level (and the victim's)
    local bothL = L.KILL_TOGETHER:format(ns.JoinNames(d.namesL), v .. ns.LevelTag(f.vlevel, true)) .. ns.Flavor.SEP .. place
    ns.Debug("KILL-MERGE", name, ns.Plain(ns.JoinNames(d.names)))
    if d.entry then d.entry.text = bothL end
    if not p.lastTextAt or ns.Now() >= p.lastTextAt then p.lastText, p.lastTextAt = bothL, ns.Now() end
    if isSelf then return end
    if milestone then
      -- a streak or revenge is about this killer: it still gets its own toast (and no plain one)
      ns.Toast.Push({
        header = (revenge and L.HEADER_REVENGE) or L.HEADER_STREAK,
        chat = line, milestone = true, kind = "kill", category = "pvp", icon = ICON.kill,
        title = title, text = text, player = name,
      })
    else
      ns.Toast.Push({
        chat = both, kind = "kill", category = "pvp", icon = ICON.kill, mergeOnly = true, keepKey = true,
        title = together, text = ns.S().flavor ~= false and place or nil, player = name,
        collapseKey = "death:" .. name .. ":" .. d.t, merge = mergeDeath,
      })
    end
    return
  end
  local entry = feed(p, "kill", leveled(line, { { who(p), msg.level }, { v, f.vlevel, true } }), { name })
  if not ns.past then
    for k, o in pairs(deaths) do if now - o.t > SAME_DEATH * 2 then deaths[k] = nil end end
    local first = isSelf and L.KILL_YOU_NAME or who(p)
    deaths[name] = { t = now, killers = { [key] = true }, names = { first }, namesL = { first .. ns.LevelTag(msg.level) },
      entry = entry, zone = f.zone }
  end
  if isSelf then return end
  ns.Toast.Push({
    header = (revenge and L.HEADER_REVENGE) or (ns.Flavor.StreakMilestone(streak) and L.HEADER_STREAK) or nil,
    chat = line, milestone = milestone, kind = "kill", category = "pvp", icon = ICON.kill,
    title = title, text = text,
    player = name,
    collapseKey = "death:" .. name .. ":" .. now, merge = mergeDeath, keepKey = true,
  })
end

-- someone supported (healed, buffed) a friend's kill without honor of their own: they share the
-- notoriety and any bounty, but it's no kill for them (no count, kill list or hitlist change, no toast)
H.AST = function(msg, isSelf, p, f)
  local name = ns.CleanName(f.victim)
  if ns.past then ns.Debug("AST-SKIP", p.name, "a caught-up message") return end
  if not name or ns.PvP.IsFriendly(name) then ns.Debug("AST-SKIP", p.name, "no usable enemy name: " .. tostring(name)) return end
  ns.Debug("AST-GOT", isSelf and "you" or p.name, "helped " .. tostring(f.helped), "victim " .. name)
  ns.Bounty.OnKill(p.name, name, nil)
  ns.Contracts.OnKill(p.name, name, nil)
  if isSelf then return end
  local helped = ns.CleanName(f.helped)
  local victim = ns.ClassColored(name, f.vclass ~= "" and f.vclass or nil)
  local line
  if helped == ns.me then
    line = L.FEED_ASSIST_YOU:format(who(p), victim)
  else
    line = L.FEED_ASSIST:format(who(p), helped and ns.ClassColored(helped) or "?", victim)
  end
  feed(p, "kill", leveled(line, { { who(p), msg.level }, { victim, f.vlevel, true } }), { name })
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
  feed(p, "sighting", leveled(line, { { who(p), msg.level }, { ns.ClassColored(name, u.class), f.level, true } }), { name })
end

-- a friend's profile: their own all-time K/D, zone and status
H.PRO = function(_, isSelf, p, f)
  if isSelf then return end
  ns.Profile.Apply(p, f)
end

-- a friend's numbers passed on by another friend (only for friends who are offline)
H.PRL = function(msg, isSelf, _, f)
  if isSelf then return end
  ns.Profile.OnRelayed(msg.from, f)
end

-- shared groups: membership, and stats passed along by members
-- a friend's contract on the bounty board (Contracts.lua)
H.BTY = function(msg, isSelf, _, f)
  if isSelf then return end
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

-- A week is over (at login, or when you claim notoriety after it): start the next one and say how
-- the last one went in one chat line.
function Events.WeeklyRoll()
  local db = FriendsAndFoesDB
  local now = time()
  local w = db.weekly
  if not w then
    db.weekly = { start = now, k = 0, d = 0, killers = {}, bt = 0 }
    return
  end
  if now - (w.start or now) < 7 * 86400 then return end
  db.weekly = { start = now, k = 0, d = 0, killers = {}, bt = 0 }
  if ns.S().weekly == false or ((w.k or 0) + (w.d or 0) + ns.Count(w.bt)) == 0 then return end
  local line = L.WEEKLY:format(ns.Count(w.k), ns.Count(w.d))
  if ns.Count(w.bt) > 0 then line = line:gsub("%.$", "") .. L.WEEKLY_NOTORIETY:format(ns.Art.Points(ns.Count(w.bt))) end
  local nemesis, most, bestT = nil, 0, nil
  for name, n in pairs(w.killers or {}) do
    local t = type(w.killedAt) == "table" and w.killedAt[name] or nil
    if ns.Profile.NemesisBeats(n, t, name, nemesis and most or nil, bestT, nemesis) then nemesis, most, bestT = name, n, t end
  end
  if nemesis and most >= 2 then line = line .. " " .. L.WEEKLY_NEMESIS:format(nemesis, most) end
  C_Timer.After(8, function() ns.Toast.Chat(line) end)
end

-- weekly summary: your own takedowns and deaths, and who killed you most
-- (kind "bt": points of notoriety you claimed; killer is then the number)
function Events.WeeklyAdd(kind, killer)
  local w = FriendsAndFoesDB.weekly
  if not w then return end
  if kind == "bt" then
    -- a week over while you were playing: start the next one (with its summary) first
    if time() - (w.start or time()) >= 7 * 86400 then Events.WeeklyRoll(); w = FriendsAndFoesDB.weekly end
    w.bt = ns.Count(w.bt) + ns.Count(killer)
    return
  end
  if kind == "k" then w.k = (w.k or 0) + 1 end
  if kind == "d" then
    w.d = (w.d or 0) + 1
    if killer then
      w.killers = w.killers or {}
      w.killers[killer] = (w.killers[killer] or 0) + 1
      w.killedAt = type(w.killedAt) == "table" and w.killedAt or {}
      w.killedAt[killer] = time() -- (the tie-break: the most recent killer is the nemesis)
    end
  end
end

H.HIT = function(msg, isSelf, p, f)
  if isSelf then return end
  local added, total, dropped = 0, 0, {}
  local auto = f.auto == "1"
  for _, raw in ipairs(ns.Split(f.entries or "", ";")) do
    local e = ns.Split(raw, ":")
    local name = ns.CleanName(e[1])
    -- an automatic digest only brings enemies who hurt the sender, you, or a friend you share: the
    -- 9th field names up to 3 of their victims; none of them on your side = not for you
    local who9 = {}
    if auto then
      for _, n in ipairs(ns.Split(e[9] or "", ",")) do
        n = ns.CleanName(n)
        if n and (n == msg.from or ns.Data.OnOurSideName(n)) then who9[#who9 + 1] = n end
      end
    end
    local isNew = name and ns.Data.FindHit(name) == nil
    -- don't add someone your "Forget ... after" settings would remove at the next login
    local hours = tonumber(e[8])
    local forget = ns.Data.ForgetDays({ kills = e[6], attacks = e[5] })
    local tooOld = isNew and forget and hours and hours / 24 > forget
    total = total + 1
    local why = (not name and "no name") or (tooOld and "older than your Forget setting") or ((auto and #who9 == 0) and "no victim on your side")
      or (ns.PvP.IsFriendly(name) and "on your side") or ((isNew and (tonumber(e[6]) or 0) <= 0 and (tonumber(e[5]) or 0) <= 0) and "no kill or attack") or nil
    if why then dropped[why] = (dropped[why] or 0) + 1 end
    -- a new entry needs a kill or an attack on one of you (an empty one is never added)
    -- (never someone on your side, even if they are on the sharer's list)
    if name and not tooOld and (not auto or #who9 > 0) and not ns.PvP.IsFriendly(name) and (not isNew or (tonumber(e[6]) or 0) > 0 or (tonumber(e[5]) or 0) > 0) then
      local h = ns.Data.Hit(name)
      for _, n in ipairs(who9) do noteWho(h, n) end
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

  -- the automatic digest a friend sends when you meet: merged quietly (no toast, no Feed line)
  if auto then
    local parts = {}
    for why, n in pairs(dropped) do parts[#parts + 1] = n .. " " .. why end
    table.sort(parts)
    ns.Debug("DIGEST-GOT", msg.from, "entries " .. total, "new " .. added, "dropped: " .. (#parts > 0 and table.concat(parts, "; ") or "none"))
    return
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
  -- an old version's manual share: one chat line, never a toast or a sound (the chunks of one
  -- share fold into that one line)
  if s.first then ns.Toast.Chat(L.CHAT_SHARE:format(who(p))) end
end
