local _, ns = ...
local L = ns.L

local Minimap_ = {}
ns.Minimap = Minimap_

local RADIUS = 80
local button

local function place()
  local angle = math.rad(ns.S().minimap.angle or 210)
  button:ClearAllPoints()
  button:SetPoint("CENTER", Minimap, "CENTER", math.cos(angle) * RADIUS, math.sin(angle) * RADIUS)
end

local function onDragUpdate()
  local mx, my = Minimap:GetCenter()
  local px, py = GetCursorPosition()
  local scale = Minimap:GetEffectiveScale()
  px, py = px / scale, py / scale
  ns.S().minimap.angle = math.deg(math.atan2(py - my, px - mx))
  place()
end

local function create()
  button = CreateFrame("Button", "FriendsAndFoesMinimapButton", Minimap)
  button:SetSize(31, 31)
  button:SetFrameStrata("MEDIUM")
  button:SetFrameLevel(8)
  button:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  button:RegisterForDrag("LeftButton")
  button:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

  local icon = button:CreateTexture(nil, "BACKGROUND")
  icon:SetTexture("Interface\\Icons\\Ability_DualWield")
  icon:SetSize(20, 20)
  icon:SetPoint("CENTER", 0, 1)

  local border = button:CreateTexture(nil, "OVERLAY")
  border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
  border:SetSize(53, 53)
  border:SetPoint("TOPLEFT")

  button:SetScript("OnClick", function(_, btn)
    if btn == "RightButton" then ns.UI.OpenSettings() else ns.UI.Toggle() end
  end)
  button:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", onDragUpdate) end)
  button:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
  button:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine(L.ADDON)
    GameTooltip:AddLine(L.MINIMAP_TIP, 1, 1, 1)
    GameTooltip:Show()
  end)
  button:SetScript("OnLeave", function() GameTooltip:Hide() end)
  place()
end

function Minimap_.Update()
  if not button then return end
  button:SetShown(not ns.S().minimap.hide)
end

-- the minimap's addon menu (modern clients): left-click opens the window, right-click options
function FriendsAndFoes_OnAddonCompartmentClick(_, button)
  if button == "RightButton" then ns.UI.OpenSettings() else ns.UI.Toggle() end
end

ns.OnReady(function()
  if not Minimap then return end
  -- where the addon menu exists, the separate button starts hidden (once; your choice sticks)
  local mm = ns.S().minimap
  if AddonCompartmentFrame and not mm.compartmentDefaulted then
    mm.hide = true
    mm.compartmentDefaulted = true
  end
  create()
  Minimap_.Update()
end)
