local _, ns = ...
local L = ns.L
local issecret = ns.issecret

-- Hitlist players are marked where you already look: a small skull on their nameplate and a
-- line in their tooltip. Quieter than a toast, and it's on the person in front of you.
local Marks = {}
ns.Marks = Marks

local SKULL = "Interface\\TargetingFrame\\UI-RaidTargetingIcon_8"
local plates = {} -- nameplate unit token -> plate frame (while shown)

local function safe(v) if issecret(v) then return nil end return v end

-- hitlist record for a unit, or nil
function Marks.HitFor(unit)
  if not unit or issecret(unit) then return nil end
  if not safe(UnitIsPlayer(unit)) then return nil end
  local first, surname = UnitName(unit)
  if not safe(first) then return nil end
  local name = ns.CleanName(first, safe(surname))
  return name and ns.Data.FindHit(name)
end

-- "Bob 3x, Alice 1x" - who they killed and how often (top 3)
local function victimsText(h)
  local list = {}
  for i, v in ipairs(ns.Data.KillsOn(h)) do
    if i > 3 then
      list[#list + 1] = "..."
      break
    end
    list[#list + 1] = v[2] and L.KILLS_ON_COUNT:format(v[1], v[2]) or v[1]
  end
  return table.concat(list, ", ")
end

local function markPlate(unit)
  if not (C_NamePlate and C_NamePlate.GetNamePlateForUnit) then return end
  local plate = C_NamePlate.GetNamePlateForUnit(unit)
  if not plate or (plate.IsForbidden and plate:IsForbidden()) then return end
  plates[unit] = plate
  local hit = ns.S().mark and Marks.HitFor(unit)
  if hit then
    if not plate.fnfMark then
      local uf = type(plate.UnitFrame) == "table" and plate.UnitFrame or nil
      local bar = uf and type(uf.healthBar) == "table" and uf.healthBar or nil
      local t = plate:CreateTexture(nil, "OVERLAY")
      t:SetSize(16, 16)
      t:SetTexture(SKULL)
      if bar then t:SetPoint("RIGHT", bar, "LEFT", -3, 0) else t:SetPoint("BOTTOM", plate, "TOP", 0, 2) end
      plate.fnfMark = t
    end
    plate.fnfMark:Show()
  elseif plate.fnfMark then
    plate.fnfMark:Hide()
  end
end

-- re-check visible plates (hitlist changed, or the setting was toggled)
function Marks.Refresh()
  for unit in pairs(plates) do ns.Try("mark", markPlate, unit) end
end

ns.On("NAME_PLATE_UNIT_ADDED", function(unit)
  if issecret(unit) then return end
  markPlate(unit)
end)

ns.On("NAME_PLATE_UNIT_REMOVED", function(unit)
  if issecret(unit) then return end
  local plate = plates[unit]
  if plate and plate.fnfMark then plate.fnfMark:Hide() end
  plates[unit] = nil
end)

local function onUnitTooltip(tt)
  if ns.S().markTooltip == false or not tt.GetUnit then return end
  local _, unit = tt:GetUnit()
  local h = Marks.HitFor(safe(unit))
  if not h then return end
  local line = L.TOOLTIP_HIT:format(ns.Count(h.kills))
  local victims = victimsText(h)
  if victims ~= "" then line = line .. " - " .. L.TOOLTIP_VICTIMS:format(victims) end
  tt:AddLine(ns.Art.Icon(SKULL) .. " " .. line, 1, 0.35, 0.3, true)
  if h.note then tt:AddLine(h.note, 1, 1, 1, true) end
end

ns.OnReady(function()
  if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
    TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tt)
      if tt == GameTooltip then ns.Try("tooltip-hit", onUnitTooltip, tt) end
    end)
  elseif GameTooltip and GameTooltip.HookScript then
    pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetUnit", function(tt) ns.Try("tooltip-hit", onUnitTooltip, tt) end)
  end
end)
