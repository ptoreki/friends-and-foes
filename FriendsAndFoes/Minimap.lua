local _, ns = ...
local L = ns.L

local Minimap_ = {}
ns.Minimap = Minimap_

local button

-- the button sits on the minimap's rim, at an angle (drag it round), sized to the minimap the
-- game actually has (the modern one is bigger than the old 140 pixels). On a square minimap it
-- follows the edge instead of a circle. Shift-drag puts it anywhere on screen; a plain drag puts
-- it back on the rim.
local EDGE = 5 -- how far past the rim its centre sits

local function atan2(y, x)
  if math.atan2 then return math.atan2(y, x) end
  return math.atan(y, x)
end

local function rim(angle)
  local w = (tonumber(Minimap:GetWidth()) or 140) / 2 + EDGE
  local h = (tonumber(Minimap:GetHeight()) or 140) / 2 + EDGE
  local x, y = math.cos(angle), math.sin(angle)
  local shape = GetMinimapShape and GetMinimapShape()
  if shape == "SQUARE" then
    -- the edge of the square: the longer of x and y reaches the side
    local m = math.max(math.abs(x), math.abs(y))
    return x / m * w, y / m * h
  end
  return x * w, y * h
end

local function place()
  local mm = ns.S().minimap
  button:ClearAllPoints()
  if mm.free and mm.x and mm.y then
    button:SetPoint("CENTER", UIParent, "BOTTOMLEFT", mm.x, mm.y)
    return
  end
  local x, y = rim(math.rad(mm.angle or 210))
  button:SetPoint("CENTER", Minimap, "CENTER", x, y)
end
Minimap_.Place = function() if button then place() end end

local function onDragUpdate()
  local mm = ns.S().minimap
  local px, py = GetCursorPosition()
  if mm.free then
    local scale = button:GetEffectiveScale() -- (offsets are in the button's own scale)
    mm.x, mm.y = math.floor(px / scale + 0.5), math.floor(py / scale + 0.5)
  else
    local mx, my = Minimap:GetCenter()
    local scale = Minimap:GetEffectiveScale()
    mm.angle = math.deg(atan2(py / scale - my, px / scale - mx))
  end
  place()
end

local function create()
  button = CreateFrame("Button", "FriendsAndFoesMinimapButton", Minimap)
  button:SetSize(31, 31)
  button:SetFrameStrata("MEDIUM")
  button:SetFrameLevel(8)
  button:SetClampedToScreen(true)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:RegisterForDrag("LeftButton")
  button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  -- the usual minimap-button layout: a dark disc with the icon in its middle, and the gold ring
  -- over both (the ring's circle is in the top-left part of its texture, so it's anchored there)
  local back = button:CreateTexture(nil, "BACKGROUND")
  back:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
  back:SetSize(24, 24)
  back:SetPoint("CENTER")

  local icon = button:CreateTexture(nil, "ARTWORK")
  icon:SetTexture("Interface\\Icons\\Ability_DualWield")
  icon:SetSize(18, 18)
  icon:SetPoint("CENTER")
  icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) -- (trims the icon's own frame)

  local border = button:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(50, 50)
  border:SetPoint("TOPLEFT")

  button:SetScript("OnClick", function(_, btn)
    if btn == "RightButton" then ns.UI.OpenSettings() else ns.UI.Toggle() end
  end)
  -- drag: round the rim; Shift-drag: anywhere on screen
  button:SetScript("OnDragStart", function(self)
    ns.S().minimap.free = (IsShiftKeyDown and IsShiftKeyDown()) and true or false
    GameTooltip:Hide()
    self:SetScript("OnUpdate", onDragUpdate)
  end)
  button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  button:SetScript("OnEnter", function(self) Minimap_.ShowTooltip(self) end)
  button:SetScript("OnLeave", function() GameTooltip:Hide() end)
  place()
end

function Minimap_.Update()
  if not button then return end
  button:SetShown(not ns.S().minimap.hide)
end

-- hover summary: friends online, hitlist size, last fight
function Minimap_.Summary()
  local friends = 0
  for _ in pairs(ns.Comm.roster) do friends = friends + 1 end
  local hits = 0
  for _ in pairs(ns.Data.RealRealm().hitlist) do hits = hits + 1 end
  local lastFight
  local feed = ns.Data.RealRealm().feed
  for i = #feed, 1, -1 do
    local k = feed[i].kind
    if k == "attacked" or k == "died" or k == "kill" then
      lastFight = feed[i]
      break
    end
  end
  return friends, hits, lastFight
end

function Minimap_.ShowTooltip(owner)
  local friends, hits, lastFight = Minimap_.Summary()
  GameTooltip:SetOwner(owner, "ANCHOR_LEFT")
  GameTooltip:AddLine(L.ADDON)
  GameTooltip:AddLine(L.TIP_FRIENDS_ONLINE:format(friends), 1, 1, 1)
  GameTooltip:AddLine(L.TIP_HITLIST_SIZE:format(hits), 1, 1, 1)
  if lastFight then
    GameTooltip:AddLine(L.TIP_LAST_FIGHT:format(ns.Ago(lastFight.t)), 1, 1, 1)
    GameTooltip:AddLine(lastFight.text, 0.8, 0.8, 0.8, true)
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine(L.MINIMAP_TIP, 0.6, 0.6, 0.6)
  GameTooltip:Show()
end

-- the minimap's addon menu (modern clients): left-click opens the window, right-click options
function FriendsAndFoes_OnAddonCompartmentEnter(_, frame)
  ns.Try("compartment-tip", Minimap_.ShowTooltip, frame)
end
function FriendsAndFoes_OnAddonCompartmentLeave() GameTooltip:Hide() end

function FriendsAndFoes_OnAddonCompartmentClick(_, button)
  if button == "RightButton" then ns.UI.OpenSettings() else ns.UI.Toggle() end
end

ns.OnReady(function()
  if not Minimap then return end
  create()
  Minimap_.Update()
end)
