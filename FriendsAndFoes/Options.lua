local _, ns = ...
local L = ns.L

-- Settings live in the game's own Options -> AddOns panel, not in the main window.
-- Every event gets its own Show (Toast / Chat / Off) and Sound (on/off) choice.
local Options = {}
ns.Options = Options

local panel, category, standalone
local checks, cyclers = {}, {}
local beta, capsText, modeText

local EVENTS = {
  { "attacked", L.OPT_ATTACKED }, { "died", L.OPT_DIED }, { "kill", L.OPT_KILL },
  { "sighting", L.OPT_SIGHTING }, { "level", L.OPT_LEVEL }, { "loot", L.OPT_LOOT },
  { "gear", L.OPT_GEAR }, { "share", L.OPT_SHARE },
}

local function S() return ns.S() end

local function text(parent, font, x, y, s, width)
  local fs = parent:CreateFontString(nil, "OVERLAY", font)
  fs:SetPoint("TOPLEFT", x, y)
  fs:SetJustifyH("LEFT")
  if width then fs:SetWidth(width) end
  fs:SetText(s)
  return fs
end

local function check(parent, x, y, label, get, set)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetSize(22, 22)
  cb:SetPoint("TOPLEFT", x, y)
  if label then
    local fs = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
    fs:SetText(label)
  end
  cb:SetScript("OnClick", function(self)
    set(self:GetChecked() and true or false)
    Options.Refresh()
  end)
  cb.get = get
  checks[#checks + 1] = cb
  return cb
end

local function toggle(tbl, key)
  return function() return S()[tbl][key] end, function(v) S()[tbl][key] = v end
end

-- a small button that cycles an event through toast -> chat -> off
local SHOW_NEXT = { toast = "chat", chat = "off", off = "toast" }
local SHOW_LABEL = {
  toast = "|cffffd100" .. L.SHOW_TOAST .. "|r",
  chat = "|cff33ff99" .. L.SHOW_CHAT .. "|r",
  off = "|cff888888" .. L.SHOW_OFF .. "|r",
}
local function cycler(parent, x, y, kind)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(56, 20)
  b:SetPoint("TOPLEFT", x, y)
  b.refresh = function() b:SetText(SHOW_LABEL[S().show[kind]] or SHOW_LABEL.toast) end
  b:SetScript("OnClick", function()
    local show = S().show
    show[kind] = SHOW_NEXT[show[kind]] or "toast"
    b.refresh()
  end)
  cyclers[#cyclers + 1] = b
  return b
end

local function button(parent, w, label, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w, 22)
  b:SetText(label)
  b:SetScript("OnClick", onClick)
  return b
end

local function build(p)
  text(p, "GameFontNormalLarge", 16, -16, L.ADDON)

  -- alerts: one row per event
  local x = 16
  text(p, "GameFontNormal", x, -50, L.ALERTS_HEADER)
  text(p, "GameFontDisableSmall", x + 150, -70, L.COL_SHOW)
  text(p, "GameFontDisableSmall", x + 214, -70, L.COL_SOUND)
  local y = -86
  for _, e in ipairs(EVENTS) do
    text(p, "GameFontHighlightSmall", x, y - 4, e[2])
    cycler(p, x + 150, y, e[1])
    check(p, x + 214, y + 1, nil, toggle("sound", e[1]))
    y = y - 24
  end
  text(p, "GameFontDisableSmall", x, y - 4, L.MILESTONE_NOTE, 280)
  y = y - 40
  check(p, x, y, L.OPT_NEARBY_ONLY, function() return S().nearbyOnly end, function(v) S().nearbyOnly = v end)
  y = y - 22
  check(p, x, y, L.OPT_ALL_SOUNDS, toggle("sound", "enabled"))
  y = y - 22
  check(p, x, y, L.OPT_FLAVOR, function() return S().flavor end, function(v) S().flavor = v end)

  -- right column
  x = 340
  y = -50
  text(p, "GameFontNormal", x, y, L.SHARE_HEADER)
  y = y - 20
  for _, o in ipairs({ { "level", L.OPT_LEVEL }, { "loot", L.OPT_LOOT }, { "gear", L.OPT_GEAR }, { "pvp", L.OPT_PVP } }) do
    check(p, x, y, o[2], toggle("share", o[1]))
    y = y - 21
  end
  y = y - 10
  text(p, "GameFontNormal", x, y, L.DND_HEADER)
  y = y - 20
  check(p, x, y, L.OPT_DND_COMBAT, toggle("dnd", "combat"))
  y = y - 21
  check(p, x, y, L.OPT_DND_INSTANCE, toggle("dnd", "instance"))
  y = y - 31
  text(p, "GameFontNormal", x, y, L.MISC_HEADER)
  y = y - 20
  check(p, x, y, L.OPT_MARK, function() return S().mark end, function(v)
    S().mark = v
    if ns.Marks then ns.Marks.Refresh() end
  end)
  y = y - 21
  check(p, x, y, L.OPT_MINIMAP, function() return not S().minimap.hide end, function(v)
    S().minimap.hide = not v
    if ns.Minimap then ns.Minimap.Update() end
  end)
  y = y - 21
  check(p, x, y, L.OPT_DEBUG, function() return S().debug end, function(v) ns.SetDebug(v) end)
  y = y - 30
  button(p, 120, L.BTN_UNLOCK, function() ns.Toast.ToggleUnlock() end):SetPoint("TOPLEFT", x, y)

  -- beta tools: only while debug logging is on
  beta = CreateFrame("Frame", nil, p)
  beta:SetPoint("TOPLEFT", 16, -400)
  beta:SetSize(600, 200)
  text(beta, "GameFontNormal", 0, 0, L.BETA_HEADER)
  local test = button(beta, 110, L.BTN_TEST, function() ns.Toast.Test() end)
  test:SetPoint("TOPLEFT", 0, -20)
  local sim = button(beta, 110, L.BTN_SIM, function() ns.Sim.RunAll(false) end)
  sim:SetPoint("LEFT", test, "RIGHT", 8, 0)
  text(beta, "GameFontNormalSmall", 0, -52, L.CAPS_HEADER)
  capsText = text(beta, "GameFontHighlightSmall", 0, -68, "", 200)
  text(beta, "GameFontNormalSmall", 230, -52, L.MODE_HEADER)
  modeText = text(beta, "GameFontHighlightSmall", 230, -68, "", 370)
end

local CAP_LABELS = {
  { "bnet", L.CAP_BNET }, { "whisper", L.CAP_WHISPER },
  { "enemyDetect", L.CAP_ENEMY_DETECT }, { "targeting", L.CAP_TARGETING }, { "unitNames", L.CAP_NAMES },
  { "deathRecap", L.CAP_RECAP }, { "honor", L.CAP_HONOR },
}
local CAP_COLORS = { ok = "|cff33ff33", secret = "|cffff5555", missing = "|cffff5555", untested = "|cffaaaaaa" }

local function modeNotes()
  local c, notes = ns.caps, {}
  local function bad(k) return c[k] == "secret" or c[k] == "missing" end
  if bad("enemyDetect") or bad("targeting") then
    notes[#notes + 1] = L.MODE_NO_DETECT
  elseif bad("unitNames") then
    notes[#notes + 1] = L.MODE_NO_NAMES
  end
  if bad("deathRecap") then notes[#notes + 1] = L.MODE_NO_RECAP end
  if bad("honor") then notes[#notes + 1] = L.MODE_NO_HONOR end
  if c.bnet ~= "ok" and c.whisper ~= "ok" then notes[#notes + 1] = L.MODE_SYNC_UNTESTED end
  if #notes == 0 then notes[1] = L.MODE_FULL end
  return table.concat(notes, "\n\n")
end

function Options.Refresh()
  if not panel then return end
  for _, cb in ipairs(checks) do cb:SetChecked(cb.get() and true or false) end
  for _, b in ipairs(cyclers) do b.refresh() end
  beta:SetShown(S().debug and true or false)
  if S().debug then
    local lines = {}
    for _, c in ipairs(CAP_LABELS) do
      local v = ns.caps[c[1]] or "untested"
      lines[#lines + 1] = c[2] .. ": " .. (CAP_COLORS[v] or "") .. v .. "|r"
    end
    lines[#lines + 1] = L.ERRORS_LINE:format(ns.errors)
    capsText:SetText(table.concat(lines, "\n"))
    modeText:SetText(modeNotes())
  end
end

local function create()
  panel = CreateFrame("Frame")
  panel.name = L.ADDON
  panel:Hide()
  build(panel)
  panel:SetScript("OnShow", function() ns.Try("options", Options.Refresh) end)
  if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
    local ok, cat = pcall(Settings.RegisterCanvasLayoutCategory, panel, L.ADDON)
    if ok and cat then
      category = cat
      pcall(Settings.RegisterAddOnCategory, cat)
    end
  elseif InterfaceOptions_AddCategory then
    pcall(InterfaceOptions_AddCategory, panel)
  end
end

-- own window, if the game's options panel can't be opened
local function openStandalone()
  if not standalone then
    local ok, f = pcall(CreateFrame, "Frame", "FriendsAndFoesOptions", UIParent, "BasicFrameTemplateWithInset")
    if not ok or not f then f = CreateFrame("Frame", "FriendsAndFoesOptions", UIParent) end
    f:SetSize(660, 620)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    tinsert(UISpecialFrames, "FriendsAndFoesOptions")
    panel:SetParent(f)
    panel:ClearAllPoints()
    panel:SetPoint("TOPLEFT", 4, -24)
    panel:SetPoint("BOTTOMRIGHT", -4, 4)
    standalone = f
  end
  standalone:Show()
  panel:Show()
  Options.Refresh()
end

function Options.Open()
  if not panel then create() end
  if category and Settings and Settings.OpenToCategory then
    local ok = pcall(Settings.OpenToCategory, category.GetID and category:GetID() or category)
    if ok then return end
  elseif InterfaceOptionsFrame_OpenToCategory and not category then
    if pcall(InterfaceOptionsFrame_OpenToCategory, panel) then
      pcall(InterfaceOptionsFrame_OpenToCategory, panel) -- the old panel needs it twice
      return
    end
  end
  openStandalone()
end

ns.OnReady(function() if not panel then create() end end)
