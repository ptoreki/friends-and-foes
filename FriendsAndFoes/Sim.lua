local _, ns = ...
local L = ns.L

-- /fnf sim: inject fake events to test toasts, records and sync without real PvP.
-- Everything simulated is written to a separate scratch store (FriendsAndFoesDB.sim),
-- shown in the window as "simulation view", and wiped with /fnf sim clear.

local Sim = {}
ns.Sim = Sim

local FRIEND, FRIEND_CLASS, FRIEND_LEVEL = "Simfriend Tester", "PALADIN", 42
local ENEMIES = {
  { name = "Simganker Shade", class = "ROGUE", level = 60, guild = "Sim Gankers" },
  { name = "Simhelper Shade", class = "MAGE", level = 58 },
}
local EPIC_LINK = "|cffa335ee|Hitem:12584::::::::60:::::::|h[Grand Marshal's Longsword]|h|r"
local BLUE_LINK = "|cff0070dd|Hitem:13072::::::::60:::::::|h[Stonegrip Gauntlets]|h|r"
local ZONE_ATTACK = "Hillsbrad Foothills (Tarren Mill)"

local BUILDERS = {
  level = function()
    FRIEND_LEVEL = FRIEND_LEVEL + 1
    return "LVL", { level = FRIEND_LEVEL }
  end,
  loot = function() return "LOOT", { link = EPIC_LINK, source = "loot" } end,
  gear = function() return "GEAR", { link = BLUE_LINK, count = 3 } end,
  attacked = function()
    return "ATK", { enc = ns.NewId(true), zone = ZONE_ATTACK, attackers = ns.EncodeUnits(ENEMIES, 2) }
  end,
  engage = function()
    return "ENG", { zone = ZONE_ATTACK, target = ns.EncodeUnit(ENEMIES[1]) }
  end,
  died = function()
    return "DIE", { zone = ZONE_ATTACK, killer = ns.EncodeUnit(ENEMIES[1]), conf = "c", assists = ns.EncodeUnits({ ENEMIES[2] }, 3), ended = 4 }
  end,
  kill = function()
    local e = ENEMIES[1]
    return "KILL", { victim = e.name, vclass = e.class, vlevel = e.level, vguild = e.guild, zone = "Stranglethorn Vale", streak = 5 }
  end,
}
Sim.KINDS = { "level", "loot", "gear", "attacked", "engage", "died", "kill", "sighting" }

-- deliver as if Simfriend's client had sent it (local only)
local function deliverFromFriend(kind, fields)
  local msg = { kind = kind, id = ns.NewId(true), name = FRIEND, class = FRIEND_CLASS, level = FRIEND_LEVEL, f = fields }
  local decoded = ns.Comm.Decode(ns.Comm.Encode(msg))
  if not decoded then return end
  decoded.from = FRIEND
  decoded.localSim = true -- made up here: the window switches to the simulation
  ns.Events.Apply(decoded, false)
end

local function sighting()
  local e = ENEMIES[1]
  ns.simulating = true
  local ok, err = pcall(function()
    local h = ns.Data.Hit(e.name)
    ns.Data.Touch(h, { class = e.class, level = e.level, guild = e.guild, zone = "Arathi Highlands" })
    h.victims[FRIEND] = true
    ns.Toast.Sighting(e.name, e.class, "Arathi Highlands", h)
  end)
  ns.simulating = false
  ns.viewSim = true
  if not ok then error(err, 0) end
end

-- asSelf = emit as your own event: recorded in YOUR sim store and broadcast to friends,
-- who also file it under simulation. Use it to test sync with a friend.
function Sim.Run(kind, asSelf)
  if kind == "sighting" then
    sighting()
    return true
  end
  local build = BUILDERS[kind]
  if not build then return false end
  local k, fields = build()
  if asSelf then
    ns.Events.Emit(k, fields, true)
  else
    deliverFromFriend(k, fields)
  end
  return true
end

-- each run gets a number; Stop bumps it so pending steps of an older run don't fire
local generation = 0

function Sim.RunAll(asSelf)
  generation = generation + 1
  local gen = generation
  Sim.running = true
  for i, kind in ipairs(Sim.KINDS) do
    C_Timer.After((i - 1) * 0.6, function()
      if gen ~= generation then return end
      ns.Try("sim", Sim.Run, kind, asSelf)
      if i == #Sim.KINDS then Sim.running = false end
    end)
  end
end

-- stop a running simulation: no more fake alerts, fake toasts dismissed, real data shown
function Sim.Stop()
  generation = generation + 1
  Sim.running = false
  if ns.Toast and ns.Toast.DropSim then ns.Toast.DropSim() end
  ns.viewSim = false
  if ns.UI then ns.UI.Refresh() end
end

function Sim.Clear()
  ns.Data.ClearSim()
  if ns.UI then ns.UI.Refresh() end
end

function Sim.Command(args)
  local kind, rest = args:match("^(%S*)%s*(.*)$")
  local asSelf = rest == "self"
  local prefix = "|cff33ff99" .. L.ADDON .. "|r "
  if kind == "" or kind == "help" then
    print(prefix .. L.SIM_HELP)
  elseif kind == "stop" then
    Sim.Stop()
    print(prefix .. L.SIM_STOPPED)
  elseif kind == "clear" then
    Sim.Clear()
    print(prefix .. L.SIM_CLEARED)
  elseif kind == "view" then
    ns.viewSim = not ns.viewSim
    if ns.UI then ns.UI.Show() end
  elseif kind == "all" then
    Sim.RunAll(asSelf)
  elseif not Sim.Run(kind, asSelf) then
    print(prefix .. L.SIM_HELP)
  end
end
