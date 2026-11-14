local _, ns = ...
local L = ns.L

local Toast = {}
ns.Toast = Toast

-- Compact, quiet toasts: one line, a thin coloured edge, gone in a few seconds.
local MAX_VISIBLE = 2
local DURATION, DURATION_PVP = 3, 5
local FADE_IN, FADE = 0.2, 0.5
local HEIGHT, WIDTH, GAP = 26, 380, 4
local QUEUE_MAX = 30
local STALE_PVP = 60

local EDGE = {
  pvp = { 0.9, 0.2, 0.15 },       -- red
  progress = { 1.0, 0.8, 0.1 },   -- gold
  sighting = { 0.7, 0.3, 1.0 },   -- purple
}

-- soft, familiar game sounds
local SK = SOUNDKIT or {}
local SOUNDS = {
  pvp = SK.UI_RAID_BOSS_WHISPER_WARNING or 37666, -- short alert, quieter than the raid-warning horn
  progress = SK.UI_BNET_TOAST or 18019,          -- the Battle.net friend toast chime
  sighting = SK.TELL_MESSAGE or 3081,            -- the whisper ping
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
  anchor = CreateFrame("Frame", "FriendsAndFoesToastAnchor", UIParent)
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
  local bg = anchor:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0.1, 0.4, 0.1, 0.8)
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
  local text = (spec.text and spec.text ~= "") and ("  |cffbbbbbb" .. spec.text .. "|r") or ""
  f.label:SetText((spec.sim and "|cff999999[SIM]|r " or "") .. (spec.title or "") .. text)
  local c = EDGE[spec.category] or EDGE.progress
  f.edge:SetColorTexture(c[1], c[2], c[3], 0.9)
  f.duration = spec.category == "pvp" and DURATION_PVP or DURATION
  f.remaining = f.duration
  f:SetAlpha(0)
end

local function createToast()
  local f = CreateFrame("Button", nil, UIParent)
  f:SetSize(WIDTH, HEIGHT)
  f:SetFrameStrata("HIGH")
  f:RegisterForClicks("LeftButtonUp", "RightButtonUp")

  local bg = f:CreateTexture(nil, "BACKGROUND")
  bg:SetAllPoints()
  bg:SetColorTexture(0, 0, 0, 0.6)

  f.edge = f:CreateTexture(nil, "BORDER")
  f.edge:SetPoint("TOPLEFT")
  f.edge:SetPoint("BOTTOMLEFT")
  f.edge:SetWidth(3)

  f.icon = f:CreateTexture(nil, "ARTWORK")
  f.icon:SetSize(18, 18)
  f.icon:SetPoint("LEFT", 9, 0)
  f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

  f.label = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  f.label:SetPoint("LEFT", f.icon, "RIGHT", 7, 0)
  f.label:SetPoint("RIGHT", -8, 0)
  f.label:SetJustifyH("LEFT")
  f.label:SetWordWrap(false)

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
    local age = self.duration - self.remaining
    if self.remaining <= 0 then
      release(self)
    elseif self.remaining < FADE then
      self:SetAlpha(self.remaining / FADE)
    elseif age < FADE_IN then
      self:SetAlpha(age / FADE_IN)
    else
      self:SetAlpha(1)
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

-- Sound per kind (settings.sound[kind]); a milestone chimes even when its kind is silent.
local function playSound(spec)
  local s = ns.S().sound
  if not s.enabled then return end
  local id
  if spec.kind and s[spec.kind] then
    id = SOUNDS[spec.category] or SOUNDS.progress
  elseif spec.milestone then
    id = SOUNDS.progress
  end
  if id then ns.Try("sound", PlaySound, id, "Master") end
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
  playSound(spec)
  Toast.shown = (Toast.shown or 0) + 1
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

---------------------------------------------------------------------------
-- routing: each kind shows as "toast", "chat" or "off" (settings.show).
-- Milestones (level 60, a looted epic BoE, a revenge kill) always toast unless "off".
---------------------------------------------------------------------------
function Toast.Mode(spec)
  if spec.force or not spec.kind then return "toast" end
  local mode = ns.S().show[spec.kind] or "toast"
  if mode == "off" then return "off" end
  if spec.milestone then return "toast" end
  if spec.far and mode == "toast" then return "chat" end
  return mode
end

local function chatFrame()
  local n = tonumber(ns.S().chatFrame) or 1
  return _G["ChatFrame" .. n] or DEFAULT_CHAT_FRAME
end

-- one line in chat, in the colour of guild achievement announcements
function Toast.Chat(text, sim)
  local frame = chatFrame()
  if not (frame and text) then return end
  local info = ChatTypeInfo and ChatTypeInfo.GUILD_ACHIEVEMENT
  local r, g, b = 1, 1, 0
  if info and info.r then r, g, b = info.r, info.g, info.b end
  frame:AddMessage("|cff33ff99" .. L.CHAT_PREFIX .. "|r " .. (sim and "|cff999999[SIM]|r " or "") .. text, r, g, b)
end

function Toast.Push(spec)
  if not anchor then return end
  local mode = Toast.Mode(spec)
  if mode == "off" then return end
  spec.sim = spec.sim or ns.simulating or nil
  if mode == "chat" then
    if not spec.quiet then Toast.Chat(spec.chat or spec.title, spec.sim) end
    if not spec.quiet then playSound(spec) end
    return
  end
  if spec.milestone then spec.collapseKey = nil end -- a milestone gets its own toast
  -- flavor off: the toast is the same one short line as the chat/Feed line
  if ns.S().flavor == false and spec.chat and not spec.force then
    spec.title, spec.text, spec.collapseKey = spec.chat, nil, nil
  end
  spec.created = GetTime()
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
  local who = ns.ClassColored(name, class)
  Toast.Push({
    kind = "sighting", category = "sighting", icon = "Interface\\Icons\\Ability_Hunter_SniperShot",
    title = L.TOAST_SIGHTING:format(who),
    text = L.TOAST_SIGHTING_TEXT:format(zone or "?", hit.attacks or 0, hit.kills or 0),
    chat = ns.S().flavor == false and L.SHORT_SIGHTING:format(who, zone or "?")
      or L.CHAT_SIGHTING:format(who, zone or "?", hit.attacks or 0, hit.kills or 0),
    player = name,
  })
end

function Toast.Test()
  local friend = ns.ClassColored("Testfriend", "PALADIN")
  local enemy = ns.ClassColored("Testenemy", "ROGUE")
  local link = "|cffa335ee|Hitem:12584::::::::60:::::::|h[Grand Marshal's Longsword]|h|r"
  Toast.Push({ force = true, kind = "level", category = "progress", icon = ns.ICON.level, subjects = { friend },
    title = L.TOAST_LEVEL:format(friend), text = L.TOAST_LEVEL_TEXT:format(42) })
  Toast.Push({ force = true, kind = "loot", category = "progress", icon = ns.ICON.fallback, link = link,
    title = L.TOAST_LOOT:format(friend), text = L.TOAST_LOOTED:format(link) })
  Toast.Push({ force = true, kind = "attacked", category = "pvp", icon = ns.ICON.attacked,
    title = L.TOAST_ATTACKED:format(friend), text = L.TOAST_ATTACKED_TEXT:format("Hillsbrad Foothills (Tarren Mill)", enemy) })
  Toast.Push({ force = true, kind = "died", category = "pvp", icon = ns.ICON.died,
    title = L.TOAST_DIED:format(friend), text = L.TOAST_DIED_TEXT:format(enemy, "Hillsbrad Foothills") })
  Toast.Push({ force = true, kind = "kill", category = "pvp", icon = ns.ICON.kill,
    title = L.TOAST_KILL:format(friend), text = L.TOAST_KILL_TEXT:format(enemy, "Stranglethorn Vale") })
end

ns.OnReady(createAnchor)
