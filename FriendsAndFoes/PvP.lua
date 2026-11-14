local _, ns = ...
local issecret = ns.issecret

-- World PvP without the combat log:
--  * attackers  = opposite-faction players (target/focus/mouseover/nameplates) targeting you when you get hit
--  * killer     = death recap source if readable, else most recent attacker (suspected)
--  * kills      = honorable-kill system messages (counted as takedowns)

local PvP = {}
ns.PvP = PvP

local ENCOUNTER_GAP = 30
local ATTACKERS_PER_MSG = 2
local MAX_ASSISTS_PER_MSG = 3
local ZONE_MAX_LEN = 48
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
  local text = zone
  if sub and not issecret(sub) and sub ~= "" and sub ~= zone then
    text = zone .. " (" .. sub .. ")"
  end
  if #text > ZONE_MAX_LEN then text = text:sub(1, ZONE_MAX_LEN) end
  return text
end

-- Is a zone text from a friend's message ("Zone" or "Zone (Subzone)", maybe cut short) in the
-- zone I'm in right now? Unknown either side counts as "no".
function PvP.IsMyZone(text)
  if type(text) ~= "string" or text == "" or text == "?" then return false end
  local mine = GetRealZoneText()
  if issecret(mine) or type(mine) ~= "string" or mine == "" then return false end
  if text == mine then return true end
  if text:sub(1, #mine + 2) == mine .. " (" then return true end
  -- the sender cut the text at ZONE_MAX_LEN: a cut-off prefix of my zone still matches
  return #text >= ZONE_MAX_LEN and mine:sub(1, #text) == text
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
  -- Forever: UnitName returns (first, surname); the pair is the identity
  local name, surname = UnitName(unit)
  if issecret(name) then
    ns.SetCap("unitNames", "secret")
  elseif name and name ~= "" and name ~= UNKNOWNOBJECT then
    ns.SetCap("unitNames", "ok")
    if issecret(surname) then surname = nil end
    info.name = ns.CleanName(name, surname)
  end
  local _, class = UnitClass(unit)
  if not issecret(class) then info.class = class end
  local level = UnitLevel(unit)
  if not issecret(level) and level and level > 0 then info.level = level end
  if GetGuildInfo then
    local guild = GetGuildInfo(unit)
    if guild and not issecret(guild) and guild ~= "" then info.guild = guild end
  end
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

local seenCount = 0
local function remember(info)
  if not info.name then return end
  info.time = GetTime()
  if not seen[info.name] then seenCount = seenCount + 1 end
  seen[info.name] = info
  if seenCount > 300 then
    local now = GetTime()
    for name, i in pairs(seen) do
      if now - i.time > 600 then
        seen[name] = nil
        seenCount = seenCount - 1
      end
    end
    for name, t in pairs(threat) do
      if now - t.time > 60 then threat[name] = nil end
    end
  end
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
  -- small chunks keep each message under the 255-byte limit even with guild names
  local zone = PvP.ZoneText()
  for i = 1, #added, ATTACKERS_PER_MSG do
    local chunk = {}
    for j = i, math.min(i + ATTACKERS_PER_MSG - 1, #added) do chunk[#chunk + 1] = added[j] end
    ns.Events.Emit("ATK", { enc = enc.id, zone = zone, attackers = ns.EncodeUnits(chunk, ATTACKERS_PER_MSG) })
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
    local name = ns.CleanName(e.sourceName)
    if name and recapSourceIsPlayer(e) == true then
      result.players[name] = true
    end
  end
  best = best or events[1]
  local name = best and ns.CleanName(best.sourceName)
  if not name then
    ns.SetCap("deathRecap", "secret")
    return result
  end
  ns.SetCap("deathRecap", "ok")
  result.killer = { name = name, isPlayer = recapSourceIsPlayer(best) }
  return result
end

-- Look a name up in a name-keyed table. Exact match first; otherwise match on first name,
-- but only when exactly one entry shares it (Forever first names aren't unique).
local function findByName(tbl, name)
  if not (tbl and name) then return nil end
  if tbl[name] then return tbl[name] end
  local first, hit, n = ns.FirstName(name), nil, 0
  for k, v in pairs(tbl) do
    if k ~= "?" and ns.FirstName(k) == first and (k == first or name == first) then
      hit, n = v, n + 1
    end
  end
  if n == 1 then return hit end
  return nil
end
PvP.FindByName = findByName

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
    local recent = findByName(seen, rk.name)
    local known = (enc and findByName(enc.attackers, rk.name))
      or (recent and GetTime() - recent.time < 60 and recent)
    if known then
      killer, conf = known, "c"
      -- the recap may carry the surname our unit scan missed
      if rk.name:find(" ", 1, true) and not known.name:find(" ", 1, true) then known.name = rk.name end
    elseif rk.isPlayer == true then
      -- recap says it's a player: trust it even if we never saw them (names-unreadable fallback)
      killer, conf = { name = rk.name }, "c"
    end
    -- isPlayer == nil and not a known attacker: NPC names ("Twilight Acolyte") look just like
    -- Forever player names ("Kragg Bear"), so don't guess; fall through to the last attacker.
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
    addAssist(findByName(seen, name) or { name = name })
  end
  ns.Events.Emit("DIE", {
    zone = PvP.ZoneText(),
    killer = killer and ns.EncodeUnit(killer) or "",
    conf = conf or "",
    assists = ns.EncodeUnits(assists, MAX_ASSISTS_PER_MSG),
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
  victim = ns.CleanName(victim)
  if not victim then
    ns.Debug("HONOR-NOMATCH", msg)
    return
  end
  ns.SetCap("honor", "ok")
  local info = findByName(seen, victim)
  ns.Events.Emit("KILL", {
    victim = (info and info.name) or victim,
    vclass = info and info.class or "",
    vlevel = info and info.level or "",
    vguild = info and info.guild or "",
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
  local hit = ns.Data.FindHit(info.name)
  if not hit then return end
  local zone = PvP.ZoneText()
  ns.Data.Touch(hit, { class = info.class, level = info.level, guild = info.guild, zone = zone })
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
