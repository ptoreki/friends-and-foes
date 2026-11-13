local _, ns = ...
local L = ns.L

-- One pipeline for every event: own events are encoded/decoded exactly like
-- received ones, applied locally (feed + records), then broadcast if sharing is on.
local Events = {}
ns.Events = Events

local SHARE = { LVL = "level", LOOT = "loot", GEAR = "gear", ATK = "pvp", DIE = "pvp", KILL = "pvp" }

local ICON = {
  level = "Interface\\Icons\\Spell_Holy_SurgeOfLight",
  attacked = "Interface\\Icons\\Ability_Warrior_Challange",
  died = "Interface\\Icons\\Ability_Rogue_FeignDeath",
  kill = "Interface\\Icons\\Ability_DualWield",
  fallback = "Interface\\Icons\\INV_Misc_QuestionMark",
}
ns.ICON = ICON

function Events.Emit(kind, fields)
  local _, class = UnitClass("player")
  local msg = { kind = kind, id = ns.NewId(), class = class, level = UnitLevel("player"), f = fields }
  local wire = ns.Comm.Encode(msg)
  local decoded = ns.Comm.Decode(wire)
  if not decoded then return end
  decoded.from = ns.me
  Events.Apply(decoded, true)
  if ns.S().share[SHARE[kind]] then ns.Comm.Broadcast(msg) end
end

---------------------------------------------------------------------------
-- helpers
---------------------------------------------------------------------------
local function who(p) return ns.ClassColored(p.name, p.class) end

local function feed(p, kind, text)
  p.lastText = text
  ns.Data.Feed(kind, text)
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

local function enemyTouch(u, zone)
  local e = ns.Data.Player(u.name)
  e.enemy = true
  ns.Data.Touch(e, { class = u.class, level = u.level, zone = zone })
  return e
end

local function hitTouch(u, zone, victim)
  local h = ns.Data.Hit(u.name)
  ns.Data.Touch(h, { class = u.class, level = u.level, zone = zone })
  h.victims[victim] = true
  return h
end

---------------------------------------------------------------------------
-- handlers
---------------------------------------------------------------------------
local H = {}

function Events.Apply(msg, isSelf)
  local h = H[msg.kind]
  if not h then return end
  local p = ns.Data.Player(msg.from)
  p.friend = true
  if isSelf then p.self = true end
  ns.Data.Touch(p, { class = msg.class, level = msg.level })
  h(msg, isSelf, p, msg.f)
  if ns.UI and ns.UI.OnDataChanged then ns.UI.OnDataChanged() end
end

H.LVL = function(_, isSelf, p, f)
  local lvl = tonumber(f.level)
  if not lvl then return end
  p.level = lvl
  feed(p, "level", L.FEED_LEVEL:format(who(p), lvl))
  if isSelf then return end
  ns.Toast.Push({
    kind = "level", category = "progress", icon = ICON.level,
    subjects = { who(p) }, title = L.TOAST_LEVEL:format(who(p)), text = L.TOAST_LEVEL_TEXT:format(lvl),
    collapseKey = "level", merge = mergeSubjects(L.TOAST_LEVEL),
  })
end

H.LOOT = function(_, isSelf, p, f)
  if f.link == "" then return end
  local crafted = f.source == "craft"
  feed(p, "loot", (crafted and L.FEED_CRAFT or L.FEED_LOOT):format(who(p), f.link))
  if isSelf then return end
  ns.Toast.Push({
    kind = "loot", category = "progress", icon = itemIcon(f.link), link = f.link,
    title = L.TOAST_LOOT:format(who(p)), text = (crafted and L.TOAST_CRAFTED or L.TOAST_LOOTED):format(f.link),
  })
end

H.GEAR = function(_, isSelf, p, f)
  if f.link == "" then return end
  feed(p, "gear", L.FEED_GEAR:format(who(p), f.link))
  if isSelf then return end
  ns.Toast.Push({
    kind = "gear", category = "progress", icon = itemIcon(f.link), link = f.link, firstLink = f.link, count = 1,
    title = L.TOAST_GEAR:format(who(p)), text = f.link,
    collapseKey = "gear:" .. p.name,
    merge = function(old)
      old.count = old.count + 1
      old.text = L.TOAST_GEAR_MORE:format(old.firstLink, old.count - 1)
    end,
  })
end

local atkSeen = {}

H.ATK = function(msg, isSelf, p, f)
  local attackers = ns.DecodeUnits(f.attackers)
  local encKey = msg.from .. ":" .. f.enc
  local names = {}
  for _, u in ipairs(attackers) do
    if u.name then
      names[#names + 1] = ns.ClassColored(u.name, u.class)
      local k = encKey .. ":" .. u.name
      if not atkSeen[k] then
        atkSeen[k] = true
        enemyTouch(u, f.zone)
        local h = hitTouch(u, f.zone, msg.from)
        h.attacks = h.attacks + 1
      end
    end
  end
  if atkSeen[encKey] then return end
  atkSeen[encKey] = true

  local by = (#names > 0) and ns.JoinNames(names) or L.UNKNOWN_ENEMY
  feed(p, "attacked", L.FEED_ATTACKED:format(who(p), by, f.zone))
  if isSelf or suppressAttackToast(msg.from) then return end
  ns.Toast.Push({
    kind = "attacked", category = "pvp", icon = ICON.attacked,
    title = L.TOAST_ATTACKED:format(who(p)), text = L.TOAST_ATTACKED_TEXT:format(f.zone, by),
    player = attackers[1] and attackers[1].name,
  })
end

H.DIE = function(msg, isSelf, p, f)
  p.d = p.d + 1
  local killer = ns.DecodeUnit(f.killer)
  local suspect = f.conf == "s"
  local by
  if killer and killer.name then
    local e = enemyTouch(killer, f.zone)
    e.k = e.k + 1
    local h = hitTouch(killer, f.zone, msg.from)
    h.kills = h.kills + 1
    if suspect then h.suspect = h.suspect + 1 end
    by = ns.ClassColored(killer.name, killer.class) .. (suspect and "?" or "")
  end
  for _, u in ipairs(ns.DecodeUnits(f.assists)) do
    if u.name then
      local e = enemyTouch(u, f.zone)
      e.a = e.a + 1
      hitTouch(u, f.zone, msg.from) -- they attacked a friend: make sure they're on the hitlist
    end
  end

  if by then
    feed(p, "died", L.FEED_DIED:format(who(p), by, f.zone))
  else
    feed(p, "died", L.FEED_DIED_UNKNOWN:format(who(p), f.zone))
  end
  if isSelf then return end
  ns.Toast.Push({
    kind = "died", category = "pvp", icon = ICON.died,
    title = L.TOAST_DIED:format(who(p)),
    text = by and L.TOAST_DIED_TEXT:format(by, f.zone) or L.TOAST_DIED_UNKNOWN:format(f.zone),
    player = killer and killer.name,
  })
end

H.KILL = function(_, isSelf, p, f)
  if f.victim == "" then return end
  p.k = p.k + 1
  local victim = { name = f.victim, class = f.vclass ~= "" and f.vclass or nil, level = f.vlevel }
  enemyTouch(victim, f.zone)
  ns.Data.EnemyDied(f.victim)
  local v = ns.ClassColored(victim.name, victim.class)
  feed(p, "kill", L.FEED_KILL:format(who(p), v, f.zone))
  if isSelf then return end
  ns.Toast.Push({
    kind = "kill", category = "pvp", icon = ICON.kill,
    title = L.TOAST_KILL:format(who(p)), text = L.TOAST_KILL_TEXT:format(v, f.zone),
    player = f.victim,
  })
end
