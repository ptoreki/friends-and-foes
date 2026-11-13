local _, ns = ...
local L = ns.L

local Toast = {}
ns.Toast = Toast

local MAX_VISIBLE = 3
local DURATION = 5
local FADE = 0.5
local HEIGHT, WIDTH, GAP = 58, 320, 6
local QUEUE_MAX = 30
local STALE_PVP = 60

local BORDER = {
  pvp = { 0.9, 0.2, 0.15 },
  progress = { 1.0, 0.8, 0.1 },
  sighting = { 0.7, 0.3, 1.0 },
}

local SOUNDS = {
  pvp = (SOUNDKIT and SOUNDKIT.RAID_WARNING) or 8959,
  progress = 888, -- level up fanfare
  sighting = (SOUNDKIT and SOUNDKIT.READY_CHECK) or 8960,
}

local BACKDROP = {
  bgFile = "Interface\\Tooltips\\UI-Tooltip-Background",
  edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
  tile = true, tileSize = 16, edgeSize = 16,
  insets = { left = 4, right = 4, top = 4, bottom = 4 },
}

local queue, active, pool = {}, {}, {}
local anchor

---------------------------------------------------------------------------
-- anchor (movable)
---------------------------------------------------------------------------
local function savePosition()
  local point, _, _, x, y = anchor:GetPoint(1)
  local a = ns.S().anchor
  a.point, a.x, a.y = point, x, y
end

local function createAnchor()
  anchor = CreateFrame("Frame", "FriendsAndFoesToastAnchor", UIParent, "BackdropTemplate")
  anchor:SetSize(WIDTH, 24)
  local a = ns.S().anchor
  anchor:SetPoint(a.point or "TOP", UIParent, a.point or "TOP", a.x or 0, a.y or -140)
  anchor:SetMovable(true)
  anchor:SetClampedToScreen(true)
  anchor:RegisterForDrag("LeftButton")
  anchor:SetScript("OnDragStart", anchor.StartMoving)
  anchor:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    savePosition()
  end)
  anchor:SetBackdrop(BACKDROP)
  anchor:SetBackdropColor(0.1, 0.4, 0.1, 0.8)
  anchor.label = anchor:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  anchor.label:SetPoint("CENTER")
  anchor.label:SetText(L.ANCHOR_LABEL)
  anchor:EnableMouse(false)
  anchor:SetAlpha(0)
end

function Toast.SetUnlocked(unlocked)
  if not anchor then return end
  anchor:EnableMouse(unlocked)
  anchor:SetAlpha(unlocked and 1 or 0)
  Toast.unlocked = unlocked
end

function Toast.ToggleUnlock() Toast.SetUnlocked(not Toast.unlocked) end

---------------------------------------------------------------------------
-- toast frames
---------------------------------------------------------------------------
local function itemString(link)
  return link and link:match("|H(item:[^|]+)|h") or link
end

local function release(f)
  for i, a in ipairs(active) do
    if a == f then
      table.remove(active, i)
      break
    end
  end
  f:Hide()
  f.spec = nil
  pool[#pool + 1] = f
  Toast.Layout()
  Toast.Pump()
end

local function render(f)
  local spec = f.spec
  f.icon:SetTexture(spec.icon or ns.ICON.fallback)
  f.title:SetText((spec.sim and "|cff999999[SIM]|r " or "") .. (spec.title or ""))
  f.text:SetText(spec.text or "")
  local c = BORDER[spec.category] or BORDER.progress
  f:SetBackdropBorderColor(c[1], c[2], c[3], 1)
  f.remaining = DURATION
  f:SetAlpha(1)
end

local function createToast()
  local f = CreateFrame("Button", nil, UIParent, "BackdropTemplate")
  f:SetSize(WIDTH, HEIGHT)
  f:SetFrameStrata("HIGH")
  f:SetBackdrop(BACKDROP)
  f:SetBackdropColor(0, 0, 0, 0.85)
  f:RegisterForClicks("LeftButtonUp", "RightButtonUp")

  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetSize(40, 40)
  f.icon:SetPoint("LEFT", 9, 0)

  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.title:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 8, -1)
  f.title:SetPoint("RIGHT", -10, 0)
  f.title:SetJustifyH("LEFT")
  f.title:SetWordWrap(false)

  f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.text:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -3)
  f.text:SetPoint("RIGHT", -10, 0)
  f.text:SetJustifyH("LEFT")
  f.text:SetJustifyV("TOP")
  f.text:SetHeight(26)

  f:SetScript("OnEnter", function(self)
    self.hover = true
    self:SetAlpha(1)
    local link = self.spec and self.spec.link
    if link then
      GameTooltip:SetOwner(self, "ANCHOR_BOTTOM")
      ns.Try("tooltip", GameTooltip.SetHyperlink, GameTooltip, itemString(link))
      GameTooltip:Show()
    end
  end)
  f:SetScript("OnLeave", function(self)
    self.hover = false
    GameTooltip:Hide()
  end)
  f:SetScript("OnClick", function(self, button)
    local spec = self.spec
    if button == "LeftButton" and spec and spec.player and ns.UI then
      ns.UI.ShowPlayer(spec.player)
    end
    GameTooltip:Hide()
    release(self)
  end)
  f:SetScript("OnUpdate", function(self, elapsed)
    if self.hover or not self.spec then return end
    self.remaining = self.remaining - elapsed
    if self.remaining <= 0 then
      release(self)
    elseif self.remaining < FADE then
      self:SetAlpha(self.remaining / FADE)
    end
  end)
  return f
end

function Toast.Layout()
  for i, f in ipairs(active) do
    f:ClearAllPoints()
    f:SetPoint("TOP", anchor, "BOTTOM", 0, -((i - 1) * (HEIGHT + GAP)))
  end
end

local function playSound(category)
  local s = ns.S().sound
  if not s.enabled or not s[category] then return end
  ns.Try("sound", PlaySound, SOUNDS[category], "Master")
end

-- Do-not-disturb: in combat only PvP/sighting toasts get through; in instances everything waits.
local function isHeld(spec)
  local dnd = ns.S().dnd
  if dnd.instance then
    local inInstance = IsInInstance()
    if not ns.issecret(inInstance) and inInstance then return true end
  end
  if dnd.combat and spec.category ~= "pvp" and spec.category ~= "sighting" then
    local inCombat = UnitAffectingCombat("player")
    if not ns.issecret(inCombat) and inCombat then return true end
  end
  return false
end

local function show(spec)
  local f = table.remove(pool) or createToast()
  f.spec = spec
  render(f)
  active[#active + 1] = f
  Toast.Layout()
  f:Show()
  playSound(spec.category)
end

function Toast.Pump()
  local i = 1
  while #active < MAX_VISIBLE and i <= #queue do
    local spec = queue[i]
    if spec.category == "pvp" and GetTime() - spec.created > STALE_PVP then
      table.remove(queue, i) -- a fight from minutes ago is no longer actionable
    elseif isHeld(spec) then
      i = i + 1
    else
      table.remove(queue, i)
      show(spec)
    end
  end
end

for _, ev in ipairs({ "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "ZONE_CHANGED_NEW_AREA" }) do
  ns.On(ev, function() if anchor then Toast.Pump() end end)
end

function Toast.Push(spec)
  if not anchor then return end
  if spec.kind and ns.S().toast[spec.kind] == false then return end
  spec.created = GetTime()
  spec.sim = spec.sim or ns.simulating or nil
  if spec.collapseKey and spec.merge then
    for _, f in ipairs(active) do
      if f.spec.collapseKey == spec.collapseKey then
        f.spec.merge(f.spec, spec)
        render(f)
        return
      end
    end
    for _, q in ipairs(queue) do
      if q.collapseKey == spec.collapseKey then
        q.merge(q, spec)
        return
      end
    end
  end
  queue[#queue + 1] = spec
  while #queue > QUEUE_MAX do table.remove(queue, 1) end
  Toast.Pump()
end

---------------------------------------------------------------------------
-- sightings + test
---------------------------------------------------------------------------
function Toast.Sighting(name, class, zone, hit)
  Toast.Push({
    kind = "sighting", category = "sighting", icon = "Interface\\Icons\\Ability_Hunter_SniperShot",
    title = L.TOAST_SIGHTING:format(ns.ClassColored(name, class)),
    text = L.TOAST_SIGHTING_TEXT:format(zone or "?", hit.attacks or 0, hit.kills or 0),
    player = name,
  })
end

function Toast.Test()
  local friend = ns.ClassColored("Testfriend", "PALADIN")
  local enemy = ns.ClassColored("Testenemy", "ROGUE")
  local link = "|cffa335ee|Hitem:12584::::::::60:::::::|h[Grand Marshal's Longsword]|h|r"
  Toast.Push({ kind = "level", category = "progress", icon = ns.ICON.level, subjects = { friend },
    title = L.TOAST_LEVEL:format(friend), text = L.TOAST_LEVEL_TEXT:format(42) })
  Toast.Push({ kind = "loot", category = "progress", icon = ns.ICON.fallback, link = link,
    title = L.TOAST_LOOT:format(friend), text = L.TOAST_LOOTED:format(link) })
  Toast.Push({ kind = "attacked", category = "pvp", icon = ns.ICON.attacked,
    title = L.TOAST_ATTACKED:format(friend), text = L.TOAST_ATTACKED_TEXT:format("Hillsbrad Foothills (Tarren Mill)", enemy) })
  Toast.Push({ kind = "died", category = "pvp", icon = ns.ICON.died,
    title = L.TOAST_DIED:format(friend), text = L.TOAST_DIED_TEXT:format(enemy, "Hillsbrad Foothills") })
  Toast.Push({ kind = "kill", category = "pvp", icon = ns.ICON.kill,
    title = L.TOAST_KILL:format(friend), text = L.TOAST_KILL_TEXT:format(enemy, "Stranglethorn Vale") })
end

ns.OnReady(createAnchor)
