local _, ns = ...
local L = ns.L

local Toast = {}
ns.Toast = Toast

-- Compact, quiet toasts: one line, a thin coloured edge, gone in a few seconds.
-- toasts on screen at once: Options -> Appearance (1-4)
local function maxVisible() return math.max(1, math.min(4, tonumber(ns.S().toastMax) or 2)) end
local PVP_EXTRA = 2 -- PvP toasts stay this much longer than the base (Core.lua: DEFAULT_TOAST_DURATION)
local FADE_IN, FADE = 0.2, 0.5
local HEIGHT, WIDTH, GAP = 26, 420, 4 -- HEIGHT is the one-line minimum; long text wraps
local MAX_LINES = 3
local QUEUE_MAX = 30
local STALE_PVP = 60

local EDGE = {
  pvp = { 0.9, 0.2, 0.15 },       -- red
  progress = { 1.0, 0.8, 0.1 },   -- gold
  sighting = { 0.7, 0.3, 1.0 },   -- purple
  bounty = { 0.95, 0.6, 0.15 },   -- old gold: the Bounty board
}

-- soft, familiar game sounds
local SK = SOUNDKIT or {}
local SOUNDS = {
  pvp = SK.UI_RAID_BOSS_WHISPER_WARNING or 37666, -- short alert, quieter than the raid-warning horn
  progress = SK.UI_BNET_TOAST or 18019,          -- the Battle.net friend toast chime
  sighting = SK.TELL_MESSAGE or 3081,            -- the whisper ping
  bounty = SK.LOOT_WINDOW_COIN_SOUND or 120,      -- coins
}

-- Sounds a player can pick per event (Options -> Sounds). Built-in game sounds only.
-- { key, label, sound id }
Toast.SOUND_CHOICES = {
  { "whisper", L.SND_WHISPER, SK.TELL_MESSAGE or 3081 },
  { "bnet", L.SND_BNET, SK.UI_BNET_TOAST or 18019 },
  { "bosswhisper", L.SND_BOSS_WHISPER, SK.UI_RAID_BOSS_WHISPER_WARNING or 37666 },
  { "raidwarning", L.SND_RAID_WARNING, SK.RAID_WARNING or 8959 },
  { "readycheck", L.SND_READY_CHECK, SK.READY_CHECK or 8960 },
  { "levelup", L.SND_LEVEL_UP, SK.LEVEL_UP or 888 },
  { "quest", L.SND_QUEST, SK.IG_QUEST_LIST_COMPLETE or 878 },
  { "invite", L.SND_INVITE, SK.IG_PLAYER_INVITE or 880 },
  { "mapping", L.SND_MAP_PING, SK.MAP_PING or 3175 },
  { "alarm", L.SND_ALARM, SK.ALARM_CLOCK_WARNING_3 or 12889 },
  { "coin", L.SND_COIN, SK.LOOT_WINDOW_COIN_SOUND or 120 },
}
local SOUND_BY_KEY = {}
for _, c in ipairs(Toast.SOUND_CHOICES) do SOUND_BY_KEY[c[1]] = c[3] end

-- the sound an alert plays: the pick for its kind of sound. Fights have two: a friend in trouble
-- (attacked, killed: urgent) and a friend's kill (good news), so the urgent ones never sound like
-- good news. On "Default", attacked, killed and a kill each keep their own built-in sound; the
-- other kinds play their category's.
local SOUND_OF_KIND = { attacked = "trouble", died = "trouble", engage = "trouble", kill = "victory" }
local KIND_SOUND = { attacked = "alarm", died = "raidwarning", kill = "levelup" }
function Toast.SoundFor(kind, category)
  local key = (kind and SOUND_OF_KIND[kind]) or category
  local pick = key and ns.S().soundPick and ns.S().soundPick[key]
  if (not pick or pick == "default") and kind then pick = KIND_SOUND[kind] end
  return (pick and SOUND_BY_KEY[pick]) or SOUNDS[category] or SOUNDS.progress
end
Toast.SOUND_OF_KIND = SOUND_OF_KIND

-- key: a sound choice; group: which sound it's for (its "Default" is the built-in one)
local GROUP_DEFAULT = { trouble = "alarm", victory = "levelup" }
function Toast.PlayChoice(key, group)
  local id = SOUND_BY_KEY[key] or SOUND_BY_KEY[GROUP_DEFAULT[group] or ""] or SOUNDS[group] or SOUNDS.progress
  ns.Try("sound", PlaySound, id, "Master")
end

local queue, active = {}, {}
local pools = {} -- theme -> spare frames
local anchor, holder

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
  -- toasts hang from a holder under the anchor, so their size can be scaled as a group
  holder = CreateFrame("Frame", nil, UIParent)
  holder:SetSize(WIDTH, 1)
  holder:SetFrameStrata("HIGH")
  Toast.ApplyScale()
end

-- Options -> Appearance: toast size
function Toast.ApplyScale()
  if not holder then return end
  local s = tonumber(ns.S().toastScale) or 1
  holder:SetScale(math.max(0.7, math.min(1.5, s)))
  -- Options -> Appearance: stack down from the position, or up from it
  holder:ClearAllPoints()
  if ns.S().toastGrow == "up" then
    holder:SetPoint("BOTTOM", anchor, "TOP", 0, 0)
  else
    holder:SetPoint("TOP", anchor, "BOTTOM", 0, 0)
  end
  if Toast.Layout then Toast.Layout() end
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
  pools[f.theme] = pools[f.theme] or {}
  table.insert(pools[f.theme], f)
  Toast.Layout()
  Toast.Pump()
end

---------------------------------------------------------------------------
-- themes: how a toast looks. Each builds its parts once and fills them per toast.
---------------------------------------------------------------------------
local THEMES = {}
Toast.THEMES = { "minimal", "achievement", "alliance", "horde" } -- order in Options

-- Minimal (default): one compact line on a dark strip with a thin coloured edge.
THEMES.minimal = {
  build = function(f)
    f:SetSize(WIDTH, HEIGHT)
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
    f.label:SetWordWrap(true)
    f.label:SetJustifyV("MIDDLE")
    if f.label.SetMaxLines then f.label:SetMaxLines(MAX_LINES) end
  end,
  render = function(f, spec)
    f.icon:SetTexture(spec.icon or ns.ICON.fallback)
    local text = (spec.text and spec.text ~= "") and ("  |cffbbbbbb" .. spec.text .. "|r") or ""
    f.label:SetText((spec.title or "") .. text)
    -- grow to fit wrapped text (up to MAX_LINES) instead of cutting it off
    local textH = tonumber(f.label:GetStringHeight()) or 0
    f:SetHeight(math.max(HEIGHT, math.ceil(textH) + 12))
    local c = EDGE[spec.category] or EDGE.progress
    f.edge:SetColorTexture(c[1], c[2], c[3], 0.9)
  end,
}

-- Achievement: WoW's own achievement-alert artwork. A small header says what kind of news it
-- is, then who did what, then the details. Tinted red for PvP and purple for sightings.
local ACH_W, ACH_H = 300, 80
local ACH_TINT = { pvp = { 1, 0.62, 0.55 }, progress = { 1, 1, 1 }, sighting = { 0.85, 0.7, 1 }, bounty = { 1, 0.85, 0.55 } }

local function artOrFallback(tex, file, l, r, top, b, fallback)
  -- SetTexture returns false when the file doesn't exist in this client
  local ok = tex:SetTexture(file)
  if ok == false then
    tex:SetColorTexture(fallback[1], fallback[2], fallback[3], fallback[4])
    return false
  end
  tex:SetTexCoord(l, r, top, b)
  return true
end

THEMES.achievement = {
  build = function(f)
    f:SetSize(ACH_W, ACH_H)
    f.bg = f:CreateTexture(nil, "BACKGROUND")
    f.bg:SetAllPoints()
    f.hasArt = artOrFallback(f.bg, "Interface\\AchievementFrame\\UI-Achievement-Alert-Background",
      0, 0.605, 0, 0.703, { 0.08, 0.06, 0.03, 0.92 })

    f.icon = f:CreateTexture(nil, "ARTWORK")
    f.icon:SetSize(40, 40)
    f.icon:SetPoint("LEFT", 22, -1)
    f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
    f.iconFrame = f:CreateTexture(nil, "OVERLAY")
    f.iconFrame:SetSize(58, 58)
    f.iconFrame:SetPoint("CENTER", f.icon, "CENTER", 0, 0)
    artOrFallback(f.iconFrame, "Interface\\AchievementFrame\\UI-Achievement-IconFrame",
      0, 0.5625, 0, 0.5625, { 0, 0, 0, 0 })

    f.header = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    f.header:SetPoint("TOP", 26, -13)
    f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    f.title:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 14, -6)
    f.title:SetPoint("RIGHT", -18, 0)
    f.title:SetJustifyH("CENTER")
    f.title:SetWordWrap(true)
    if f.title.SetMaxLines then f.title:SetMaxLines(2) end
    f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -2)
    f.sub:SetPoint("TOPRIGHT", f.title, "BOTTOMRIGHT", 0, -2)
    f.sub:SetJustifyH("CENTER")
    f.sub:SetWordWrap(false)
    f.sub:SetTextColor(0.75, 0.75, 0.75)
  end,
  render = function(f, spec)
    f.icon:SetTexture(spec.icon or ns.ICON.fallback)
    f.header:SetText(Toast.HeaderFor(spec))
    f.title:SetText(spec.title or "")
    f.sub:SetText(spec.text or "")
    local c = ACH_TINT[spec.category] or ACH_TINT.progress
    if f.hasArt then f.bg:SetVertexColor(c[1], c[2], c[3]) end
    f:SetHeight(ACH_H)
  end,
}

-- the small header above the message (Classic and faction styles)
function Toast.HeaderFor(spec)
  local header = spec.header
    or (spec.milestone and L.HEADER_MILESTONE[spec.kind])
    or (spec.kind and L.HEADER[spec.kind]) or L.ADDON
  return header
end

-- Alliance / Horde: a dark faction-coloured panel with metal trim, a faded faction crest behind
-- the text, and a thin stripe on the left in the event's colour.
local FACTION_W, FACTION_H = 320, 64
local FACTION_STYLE = {
  alliance = { bg = { 0.04, 0.09, 0.24, 0.93 }, trim = { 0.85, 0.7, 0.3 }, header = { 1, 0.82, 0.25 },
    crest = "Interface\\TargetingFrame\\UI-PVP-Alliance" },
  horde = { bg = { 0.22, 0.03, 0.02, 0.93 }, trim = { 0.72, 0.5, 0.25 }, header = { 1, 0.62, 0.2 },
    crest = "Interface\\TargetingFrame\\UI-PVP-Horde" },
}

local function factionTheme(style)
  local c = FACTION_STYLE[style]
  return {
    build = function(f)
      f:SetSize(FACTION_W, FACTION_H)
      local bg = f:CreateTexture(nil, "BACKGROUND")
      bg:SetAllPoints()
      bg:SetColorTexture(c.bg[1], c.bg[2], c.bg[3], c.bg[4])
      -- trim: thin lines top and bottom
      for _, edge in ipairs({ "TOP", "BOTTOM" }) do
        local line = f:CreateTexture(nil, "BORDER")
        line:SetPoint(edge .. "LEFT")
        line:SetPoint(edge .. "RIGHT")
        line:SetHeight(1)
        line:SetColorTexture(c.trim[1], c.trim[2], c.trim[3], 0.9)
      end
      -- faded crest on the right, behind the text
      local crest = f:CreateTexture(nil, "BORDER")
      crest:SetSize(70, 70)
      crest:SetPoint("RIGHT", 8, -6)
      crest:SetTexture(c.crest)
      crest:SetTexCoord(0, 0.62, 0, 0.62)
      crest:SetAlpha(0.22)
      -- event colour stripe on the left
      f.edge = f:CreateTexture(nil, "ARTWORK")
      f.edge:SetPoint("TOPLEFT", 0, -1)
      f.edge:SetPoint("BOTTOMLEFT", 0, 1)
      f.edge:SetWidth(3)

      f.icon = f:CreateTexture(nil, "ARTWORK")
      f.icon:SetSize(38, 38)
      f.icon:SetPoint("LEFT", 12, 0)
      f.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
      local iconBorder = f:CreateTexture(nil, "BORDER")
      iconBorder:SetPoint("TOPLEFT", f.icon, "TOPLEFT", -1, 1)
      iconBorder:SetPoint("BOTTOMRIGHT", f.icon, "BOTTOMRIGHT", 1, -1)
      iconBorder:SetColorTexture(c.trim[1], c.trim[2], c.trim[3], 0.9)

      f.header = f:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
      f.header:SetPoint("TOPLEFT", f.icon, "TOPRIGHT", 10, 1)
      f.header:SetPoint("RIGHT", -12, 0)
      f.header:SetJustifyH("LEFT")
      f.header:SetTextColor(c.header[1], c.header[2], c.header[3])
      f.title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
      f.title:SetPoint("TOPLEFT", f.header, "BOTTOMLEFT", 0, -2)
      f.title:SetPoint("RIGHT", -12, 0)
      f.title:SetJustifyH("LEFT")
      f.title:SetWordWrap(true)
      if f.title.SetMaxLines then f.title:SetMaxLines(2) end
      f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      f.sub:SetPoint("TOPLEFT", f.title, "BOTTOMLEFT", 0, -2)
      f.sub:SetPoint("RIGHT", -12, 0)
      f.sub:SetJustifyH("LEFT")
      f.sub:SetWordWrap(false)
      f.sub:SetTextColor(0.75, 0.75, 0.75)
    end,
    render = function(f, spec)
      f.icon:SetTexture(spec.icon or ns.ICON.fallback)
      f.header:SetText(Toast.HeaderFor(spec))
      f.title:SetText(spec.title or "")
      f.sub:SetText(spec.text or "")
      local e = EDGE[spec.category] or EDGE.progress
      f.edge:SetColorTexture(e[1], e[2], e[3], 1)
      -- grow if the title wraps to two lines
      local h = (tonumber(f.title:GetStringHeight()) or 0) + (tonumber(f.sub:GetStringHeight()) or 0) + 30
      f:SetHeight(math.max(FACTION_H, math.ceil(h)))
    end,
  }
end
THEMES.alliance = factionTheme("alliance")
THEMES.horde = factionTheme("horde")

function Toast.Theme()
  local th = ns.S().theme
  return THEMES[th] and th or "minimal"
end

local function render(f)
  THEMES[f.theme].render(f, f.spec)
  -- Options -> Appearance: how long toasts stay; PvP ones 2 seconds longer
  local d = math.max(2, math.min(10, tonumber(ns.S().toastDuration) or ns.DEFAULT_TOAST_DURATION))
  f.duration = f.spec.category == "pvp" and d + PVP_EXTRA or d
  f.remaining = f.duration
  f:SetAlpha(0)
end

local function createToast(theme)
  local f = CreateFrame("Button", nil, holder or UIParent)
  f.theme = theme
  f:SetFrameStrata("HIGH")
  f:RegisterForClicks("LeftButtonUp", "RightButtonUp")
  THEMES[theme].build(f)

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

-- Options: fewer toasts on screen - close the oldest extra ones now
function Toast.ApplyMax()
  while #active > maxVisible() do release(active[1]) end
  Toast.Pump()
end

function Toast.Layout()
  local y = 0
  local up = ns.S().toastGrow == "up"
  for _, f in ipairs(active) do
    f:ClearAllPoints()
    if up then
      f:SetPoint("BOTTOM", holder or anchor, holder and "BOTTOM" or "TOP", 0, y)
    else
      f:SetPoint("TOP", holder or anchor, holder and "TOP" or "BOTTOM", 0, -y)
    end
    y = y + (tonumber(f:GetHeight()) or HEIGHT) + GAP
  end
end

-- Sound per kind (settings.sound[kind]); a milestone chimes even when its kind is silent.
local function playSound(spec)
  local s = ns.S().sound
  if not s.enabled then return end
  local id
  if spec.kind and s[spec.kind] then
    id = Toast.SoundFor(spec.kind, spec.category)
  elseif spec.milestone then
    -- a milestone chimes even when its alert is silent
    id = Toast.SoundFor(spec.kind, spec.category)
  end
  if id then ns.Try("sound", PlaySound, id, "Master") end
end

-- Do-not-disturb: in combat only PvP/sighting toasts get through; in instances everything waits.
-- Debug log: one [TOAST] line per alert outcome, so "I didn't see it" can be traced.
-- kind | what it was about | outcome
local function plain(s)
  if type(s) ~= "string" then return tostring(s) end
  return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|H.-|h(.-)|h", "%1"):gsub("|T.-|t", ""))
end
function Toast.Log(spec, outcome)
  if not ns.S().debug then return end
  ns.Debug("TOAST", spec.kind or "notice", plain(spec.chat or spec.title or ""), outcome)
end

-- why a queued toast has to wait, or nil if it can show now
local function heldBecause(spec)
  if not spec.force and ns.InInstance() and ns.S().instances == "hold" then
    return "waiting: in " .. ns.InstanceType() .. " (Where it works)"
  end
  if ns.S().dnd.combat and spec.category ~= "pvp" and spec.category ~= "sighting" then
    local inCombat = UnitAffectingCombat("player")
    if not ns.issecret(inCombat) and inCombat then return "waiting: in combat (Do not disturb)" end
  end
  return nil
end

local function show(spec)
  local theme = Toast.Theme()
  local f = table.remove(pools[theme] or {}) or createToast(theme)
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
  while #active < maxVisible() and i <= #queue do
    local spec = queue[i]
    local held = heldBecause(spec)
    if spec.category == "pvp" and GetTime() - spec.created > STALE_PVP then
      table.remove(queue, i) -- a fight from minutes ago is no longer actionable
      Toast.Log(spec, "dropped: fight over a minute old by the time it could show")
    elseif held then
      if spec.heldLogged ~= held then
        spec.heldLogged = held
        Toast.Log(spec, held)
      end
      i = i + 1
    else
      table.remove(queue, i)
      show(spec)
      Toast.Log(spec, "shown as toast (" .. Toast.Theme() .. ")")
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
-- returns mode, reason
function Toast.Mode(spec)
  if spec.force or not spec.kind then return "toast", "always shown" end
  local mode = ns.S().show[spec.kind] or "toast"
  if mode == "off" then return "off", "your alert setting" end
  -- inside a dungeon, raid or battleground: Options -> Where it works
  if ns.InInstance() and ns.S().instances == "off" then return "off", "in " .. ns.InstanceType() .. " (Where it works)" end
  if spec.milestone then return "toast", "milestone" end
  if spec.far and mode == "toast" then return "chat", "friend is in another zone" end
  return mode, "your alert setting"
end

local function chatFrame()
  local n = tonumber(ns.S().chatFrame) or 1
  return _G["ChatFrame" .. n] or DEFAULT_CHAT_FRAME
end

-- one line in chat, in the colour of guild achievement announcements
function Toast.Chat(text)
  local frame = chatFrame()
  if not (frame and text) then return end
  local info = ChatTypeInfo and ChatTypeInfo.GUILD_ACHIEVEMENT
  local r, g, b = 1, 1, 0
  if info and info.r then r, g, b = info.r, info.g, info.b end
  frame:AddMessage("|cff33ff99" .. L.CHAT_PREFIX .. "|r " .. text, r, g, b)
end

function Toast.Push(spec)
  if ns.past then
    Toast.Log(spec, "not shown: happened while you were offline (it's in the Feed)")
    return
  end
  if not anchor then
    Toast.Log(spec, "not shown: toasts not ready yet (still loading)")
    return
  end
  local mode, why = Toast.Mode(spec)
  if mode == "off" then
    Toast.Log(spec, "off: " .. why)
    return
  end
  if mode == "chat" then
    if spec.mergeOnly then return end -- (only ever folds into a toast: no second chat line)
    if not spec.quiet then
      Toast.Chat(spec.chat or spec.title)
      playSound(spec)
      Toast.Log(spec, "chat line: " .. why)
    end
    return
  end
  if spec.milestone then spec.collapseKey = nil end -- a milestone gets its own toast
  -- flavor off: the toast is the same one short line as the chat/Feed line
  if ns.S().flavor == false and spec.chat and not spec.force then
    spec.title, spec.text = spec.chat, nil
    if not spec.keepKey then spec.collapseKey = nil end
  end
  spec.created = GetTime()
  if spec.collapseKey and spec.merge then
    for _, f in ipairs(active) do
      if f.spec.collapseKey == spec.collapseKey then
        f.spec.merge(f.spec, spec)
        render(f)
        Toast.Layout() -- merged text may need more lines
        Toast.Log(spec, "merged into a toast already on screen")
        return
      end
    end
    for _, q in ipairs(queue) do
      if q.collapseKey == spec.collapseKey then
        q.merge(q, spec)
        Toast.Log(spec, "merged into a waiting toast")
        return
      end
    end
  end
  if spec.mergeOnly then
    Toast.Log(spec, "not shown: the first toast for this death is gone already")
    return
  end
  queue[#queue + 1] = spec
  while #queue > QUEUE_MAX do
    Toast.Log(table.remove(queue, 1), "dropped: more than " .. QUEUE_MAX .. " toasts waiting")
  end
  if #active >= maxVisible() then Toast.Log(spec, "queued: " .. maxVisible() .. " toasts already on screen") end
  Toast.Pump()
end

---------------------------------------------------------------------------
-- sightings + test
---------------------------------------------------------------------------
-- by = the friend who spotted them (coloured), or nil if you did. hit may be nil when they're on
-- your friend's hitlist but not yours. Returns the line (for the Feed).
function Toast.Sighting(name, class, zone, hit, by)
  local who = ns.ClassColored(name, class)
  local title = by and L.SIGHTING_BY:format(who, by) or L.SIGHTING:format(who)
  local place = ns.Flavor.Place(zone)
  -- flavor off: who and where only; on: their record too
  local text = place
  if ns.S().flavor ~= false and hit then
    text = L.SIGHTING_RECORD:format(ns.Count(hit.kills)) .. ns.Flavor.SEP .. place
  end
  local line = title .. ns.Flavor.SEP .. text
  Toast.Push({
    kind = "sighting", category = "sighting", icon = "Interface\\Icons\\Ability_Hunter_SniperShot",
    title = title, text = text, chat = line, player = name,
    header = by and L.HEADER_SIGHT_FRIEND or nil,
  })
  return line
end

-- /fnf test (and /fnf sim): a quick look at the alerts, worded like the real thing. Standalone:
-- nothing is recorded, nothing is sent, nothing else in the add-on knows it happened.
function Toast.Test()
  local friend = ns.ClassColored("Testfriend", "PALADIN")
  local enemy = ns.ClassColored("Testenemy", "ROGUE")
  local link = "|cffa335ee|Hitem:12584::::::::60:::::::|h[Grand Marshal's Longsword]|h|r"
  local SEP = ns.Flavor.SEP
  Toast.Push({ force = true, kind = "level", category = "progress", icon = ns.ICON.level,
    title = L.TOAST_LEVEL_MAX:format(friend, 60) })
  Toast.Push({ force = true, kind = "loot", category = "progress", icon = ns.ICON.fallback, link = link,
    title = L.FEED_LOOT:format(friend, link) })
  Toast.Push({ force = true, kind = "attacked", category = "pvp", icon = ns.ICON.attacked,
    title = L.SHORT_ATTACKED:format(friend, enemy), text = "Tarren Mill" })
  Toast.Push({ force = true, kind = "died", category = "pvp", icon = ns.ICON.died,
    title = L.SHORT_DIED:format(friend, enemy), text = "Southshore" })
  Toast.Push({ force = true, kind = "kill", category = "pvp", icon = ns.ICON.kill,
    title = L.KILL_OWNS:format(friend, enemy, "3rd"), text = L.TODAY:format("5th") .. SEP .. "Stranglethorn Vale" })
  Toast.Push({ force = true, kind = "sighting", category = "sighting", icon = "Interface\\Icons\\Ability_Hunter_SniperShot",
    title = L.SIGHTING_BY:format(enemy, friend), text = "Arathi Highlands" })
  Toast.Push({ force = true, kind = "contract", category = "bounty", icon = "Interface\\Icons\\INV_Scroll_03",
    header = L.HEADER_CONTRACT_POSTED, title = L.CONTRACT_POSTED:format(friend, "10 " .. ns.Art.Icon("Interface\\MoneyFrame\\UI-GoldIcon"), enemy),
    text = L.CONTRACT_TOAST_DAYS:format(3) })
  Toast.Chat(L.TEST_CHAT)
end

ns.OnReady(createAnchor)
