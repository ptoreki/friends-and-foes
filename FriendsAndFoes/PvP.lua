local _, ns = ...
local issecret = ns.issecret

-- World PvP without the combat log:
--  * attackers  = opposite-faction players (target/focus/mouseover/nameplates) targeting you when you get hit
--  * killer     = death recap source if readable, else most recent attacker (suspected)
--  * kills      = honorable-kill system messages (counted as takedowns)

local PvP = {}
ns.PvP = PvP

local ENCOUNTER_GAP = 30
local MAX_ATTACKERS_PER_MSG = 4
local SIGHTING_COOLDOWN = 300

-- world-PvP objective areas are excluded
local OBJECTIVE_SUBZONES = {
  ["Northpass Tower"] = true, ["Crown Guard Tower"] = true,
  ["Eastwall Tower"] = true, ["Plaguewood Tower"] = true,
}

local seen = {}     -- enemy name -> { info..., time }
local threat = {}   -- enemy name -> { info, time } (nameplate started targeting me)
local enc           -- current encounter where I'm the victim
local lastScan = 0
local recapMax = 0
local sightCooldown = {}

---------------------------------------------------------------------------
-- context
---------------------------------------------------------------------------
function PvP.InWorldPvPContext()
  local inInstance = IsInInstance()
  if issecret(inInstance) or inInstance then return false end
  local sub = GetSubZoneText()
  if sub and not issecret(sub) and OBJECTIVE_SUBZONES[sub] then return false end
  return true
end

function PvP.ZoneText()
  local zone, sub = GetRealZoneText(), GetSubZoneText()
  if issecret(zone) or not zone then zone = "?" end
  if sub and not issecret(sub) and sub ~= "" and sub ~= zone then
    return zone .. " (" .. sub .. ")"
  end
  return zone
end

---------------------------------------------------------------------------
-- reading enemy players (never branches on a secret value)
---------------------------------------------------------------------------
local function readEnemy(unit)
  local exists = UnitExists(unit)
  if issecret(exists) or not exists then return nil end
  local isPlayer = UnitIsPlayer(unit)
  if issecret(isPlayer) then
    ns.SetCap("enemyDetect", "secret")
    return nil
  end
  if not isPlayer then return nil end
  local faction = UnitFactionGroup(unit)
  if issecret(faction) then
    ns.SetCap("enemyDetect", "secret")
    return nil
  end
  if not faction or faction == ns.myFaction or faction == "Neutral" then return nil end
  ns.SetCap("enemyDetect", "ok")

  local info = { faction = faction }
  local name, realm = UnitName(unit)
  if issecret(name) then
    ns.SetCap("unitNames", "secret")
  elseif name and name ~= "" and name ~= UNKNOWNOBJECT then
    ns.SetCap("unitNames", "ok")
    info.name = name
    if realm and not issecret(realm) and realm ~= "" then info.name = name .. "-" .. realm end
  end
  local _, class = UnitClass(unit)
  if not issecret(class) then info.class = class end
  local level = UnitLevel(unit)
  if not issecret(level) and level and level > 0 then info.level = level end
  local targetsMe = UnitIsUnit(unit .. "target", "player")
  if issecret(targetsMe) then
    ns.SetCap("targeting", "secret")
    info.targetsMe = false
  else
    ns.SetCap("targeting", "ok")
    info.targetsMe = targetsMe and true or false
  end
  return info
end

function PvP.ReadEnemy(unit)
  local ok, info = pcall(readEnemy, unit)
  if ok then return info end
  ns.Debug("ERR:readEnemy", unit, info)
  return nil
end

local function remember(info)
  if not info.name then return end
  info.time = GetTime()
  seen[info.name] = info
end

local CANDIDATES = { "target", "focus", "mouseover" }
for i = 1, 40 do CANDIDATES[#CANDIDATES + 1] = "nameplate" .. i end

local function findAttackers()
  local found, unknown = {}, 0
  for _, unit in ipairs(CANDIDATES) do
    local info = PvP.ReadEnemy(unit)
    if info then
      if info.name then remember(info) end
      if info.targetsMe then
        if info.name then found[info.name] = info else unknown = unknown + 1 end
      end
    end
  end
  return found, unknown
end

---------------------------------------------------------------------------
-- being attacked
---------------------------------------------------------------------------
local function onHit()
  local now = GetTime()
  if now - lastScan < 0.5 then
    if enc and now - enc.last <= ENCOUNTER_GAP then enc.last = now end
    return
  end
  lastScan = now
  if not PvP.InWorldPvPContext() then return end

  local attackers, unknown = findAttackers()
  for name, t in pairs(threat) do
    if now - t.time < 3 then attackers[name] = attackers[name] or t.info end
  end
  if not next(attackers) and unknown > 0 then
    attackers["?"] = { unknown = true }
  end

  if not next(attackers) then
    if enc and now - enc.last <= ENCOUNTER_GAP then enc.last = now end
    return
  end

  if not enc or now - enc.last > ENCOUNTER_GAP then
    enc = { id = ns.NewId(), last = now, attackers = {}, lastHit = {} }
  end
  enc.last = now

  local added = {}
  for name, info in pairs(attackers) do
    enc.lastHit[name] = now
    if not enc.attackers[name] then
      enc.attackers[name] = info
      added[#added + 1] = info
    end
  end
  if #added > 0 then
    ns.Events.Emit("ATK", {
      enc = enc.id, zone = PvP.ZoneText(),
      attackers = ns.EncodeUnits(added, MAX_ATTACKERS_PER_MSG),
    })
  end
end

ns.OnUnit("UNIT_COMBAT", "player", function(_, action)
  if not issecret(action) and (action == "HEAL" or action == "ENERGIZE") then return end
  onHit()
end)

ns.On("UNIT_TARGET", function(unit)
  if issecret(unit) or type(unit) ~= "string" or not unit:find("^nameplate") then return end
  local info = PvP.ReadEnemy(unit)
  if info and info.name and info.targetsMe then
    remember(info)
    threat[info.name] = { info = info, time = GetTime() }
  end
end)

---------------------------------------------------------------------------
-- dying
---------------------------------------------------------------------------
local PLAYER_FLAG = 0x400 -- COMBATLOG_OBJECT_TYPE_PLAYER

-- true = definitely a player, false = definitely not, nil = can't tell
local function recapSourceIsPlayer(e)
  local guid = e.sourceGUID
  if guid and not issecret(guid) and type(guid) == "string" and guid ~= "" then
    return guid:find("^Player%-") ~= nil
  end
  local flags = e.sourceFlags
  if flags and not issecret(flags) and type(flags) == "number" and bit and bit.band then
    return bit.band(flags, PLAYER_FLAG) ~= 0
  end
  return nil
end

-- Returns { killer = { name, isPlayer }, players = { [name] = true } } or nil.
local function readRecap()
  if not (C_DeathRecap and C_DeathRecap.HasRecapEvents and C_DeathRecap.GetRecapEvents) then
    ns.SetCap("deathRecap", "missing")
    return nil
  end
  local newest
  for id = recapMax + 1, recapMax + 50 do
    local has = C_DeathRecap.HasRecapEvents(id)
    if issecret(has) then
      ns.SetCap("deathRecap", "secret")
      return nil
    end
    if has then newest = id end
  end
  if not newest then return nil end
  recapMax = newest
  local events = C_DeathRecap.GetRecapEvents(newest)
  if not events or issecret(events) then return nil end

  local result = { players = {} }
  local best, bestT
  for _, e in ipairs(events) do
    local t = e.timestamp
    if t and not issecret(t) and (not bestT or t > bestT) then best, bestT = e, t end
    local name = e.sourceName
    if name and not issecret(name) and name ~= "" and recapSourceIsPlayer(e) == true then
      result.players[name] = true
    end
  end
  best = best or events[1]
  local name = best and best.sourceName
  if not name or issecret(name) or name == "" then
    ns.SetCap("deathRecap", "secret")
    return result
  end
  ns.SetCap("deathRecap", "ok")
  result.killer = { name = name, isPlayer = recapSourceIsPlayer(best) }
  return result
end

local function looksLikePlayerName(name)
  return not name:find("[%s%d]")
end

local function resolveDeath(deathTime)
  local active = enc and (deathTime - enc.last) <= ENCOUNTER_GAP
  local okRecap, recap = pcall(readRecap)
  if not okRecap then
    ns.Debug("ERR:recap", recap)
    recap = nil
  end
  local rk = recap and recap.killer

  local killer, conf
  if rk then
    local known = (enc and enc.attackers[rk.name])
      or (seen[rk.name] and GetTime() - seen[rk.name].time < 60 and seen[rk.name])
    if known then
      killer, conf = known, "c"
    elseif rk.isPlayer == true then
      -- recap says it's a player: trust it even if we never saw them (names-unreadable fallback)
      killer, conf = { name = rk.name }, "c"
    elseif rk.isPlayer == nil and active and looksLikePlayerName(rk.name) then
      killer, conf = { name = rk.name }, "s"
    end
  end
  if not killer and active then
    local bestName, bestT
    for name, t in pairs(enc.lastHit) do
      if name ~= "?" and (not bestT or t > bestT) then bestName, bestT = name, t end
    end
    if bestName then killer, conf = enc.attackers[bestName], "s" end
  end
  if not killer and not active then return end -- not a PvP death

  local assists, added = {}, {}
  local function addAssist(info)
    if info.name and (not killer or info.name ~= killer.name) and not added[info.name] then
      added[info.name] = true
      assists[#assists + 1] = info
    end
  end
  if active then
    for _, info in pairs(enc.attackers) do addAssist(info) end
  end
  for name in pairs(recap and recap.players or {}) do
    addAssist(seen[name] or { name = name })
  end
  ns.Events.Emit("DIE", {
    zone = PvP.ZoneText(),
    killer = killer and ns.EncodeUnit(killer) or "",
    conf = conf or "",
    assists = ns.EncodeUnits(assists, MAX_ATTACKERS_PER_MSG),
  })
  enc = nil
end

ns.On("PLAYER_DEAD", function()
  if not PvP.InWorldPvPContext() then return end
  local t = GetTime()
  C_Timer.After(0.5, function() ns.Try("death", resolveDeath, t) end)
end)

---------------------------------------------------------------------------
-- kills (honorable kill messages)
---------------------------------------------------------------------------
local HONOR_PATTERNS = {}
ns.OnReady(function()
  for _, fmt in ipairs({ COMBATLOG_HONORGAIN, COMBATLOG_HONORGAIN_NO_RANK, COMBATLOG_HONORGAIN_EXHAUSTION1 }) do
    local p = ns.ToPattern(fmt)
    if p then HONOR_PATTERNS[#HONOR_PATTERNS + 1] = p end
  end
  HONOR_PATTERNS[#HONOR_PATTERNS + 1] = "^(.-) dies, honorable kill"
end)

ns.On("CHAT_MSG_COMBAT_HONOR_GAIN", function(msg)
  if issecret(msg) or type(msg) ~= "string" then
    ns.SetCap("honor", "secret")
    return
  end
  if not PvP.InWorldPvPContext() then return end
  local victim
  for _, p in ipairs(HONOR_PATTERNS) do
    victim = msg:match(p)
    if victim then break end
  end
  if not victim then
    ns.Debug("HONOR-NOMATCH", msg)
    return
  end
  ns.SetCap("honor", "ok")
  local info = seen[victim]
  ns.Events.Emit("KILL", {
    victim = victim,
    vclass = info and info.class or "",
    vlevel = info and info.level or "",
    zone = PvP.ZoneText(),
  })
end)

---------------------------------------------------------------------------
-- hitlist sightings
---------------------------------------------------------------------------
local function checkSighting(unit)
  if not PvP.InWorldPvPContext() then return end
  local info = PvP.ReadEnemy(unit)
  if not info or not info.name then return end
  remember(info)
  local hit = ns.Data.Realm().hitlist[info.name]
  if not hit then return end
  local zone = PvP.ZoneText()
  ns.Data.Touch(hit, { class = info.class, level = info.level, zone = zone })
  local now = GetTime()
  if sightCooldown[info.name] and now - sightCooldown[info.name] < SIGHTING_COOLDOWN then return end
  sightCooldown[info.name] = now
  ns.Toast.Sighting(info.name, info.class, zone, hit)
end

ns.On("NAME_PLATE_UNIT_ADDED", function(unit)
  if issecret(unit) then return end
  checkSighting(unit)
end)
ns.On("PLAYER_TARGET_CHANGED", function() checkSighting("target") end)
ns.On("UPDATE_MOUSEOVER_UNIT", function() checkSighting("mouseover") end)
