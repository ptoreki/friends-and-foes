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
  { "attacked", L.OPT_ATTACKED }, { "engage", L.OPT_ENGAGE }, { "died", L.OPT_DIED }, { "kill", L.OPT_KILL },
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
  check(p, x, y, L.OPT_DND_INSTANCE,
    function() return S().where.party == "hold" end,
    function(v) for k in pairs(S().where) do S().where[k] = v and "hold" or "show" end end)
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

  -- toast style: click to switch, Preview to see it
  y = y - 30
  text(p, "GameFontHighlightSmall", x, y - 4, L.OPT_THEME)
  local theme = CreateFrame("Button", nil, p, "UIPanelButtonTemplate")
  theme:SetSize(100, 22)
  theme:SetPoint("TOPLEFT", x + 74, y)
  theme.refresh = function() theme:SetText(L.THEME_NAMES[ns.Toast.Theme()] or ns.Toast.Theme()) end
  theme:SetScript("OnClick", function()
    local list, cur = ns.Toast.THEMES, ns.Toast.Theme()
    local nextTheme = list[1]
    for i, name in ipairs(list) do
      if name == cur then nextTheme = list[i % #list + 1] end
    end
    S().theme = nextTheme
    theme.refresh()
  end)
  cyclers[#cyclers + 1] = theme
  button(p, 80, L.BTN_PREVIEW, function() ns.Toast.Test() end):SetPoint("LEFT", theme, "RIGHT", 6, 0)

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

---------------------------------------------------------------------------
-- Native options (the game's own Settings panel): dropdowns with < > arrows, tooltips, search.
-- Four pages: Alerts (main), Appearance, Friends & sharing, Advanced.
-- The canvas panel above is only the fallback when this API isn't available.
---------------------------------------------------------------------------
local native -- main native category, once built

local EVENT_ROWS = {
  { "attacked", L.OPT_ATTACKED, L.TIP_ATTACKED }, { "engage", L.OPT_ENGAGE, L.TIP_ENGAGE },
  { "died", L.OPT_DIED, L.TIP_DIED },
  { "kill", L.OPT_KILL, L.TIP_KILL }, { "sighting", L.OPT_SIGHTING, L.TIP_SIGHTING },
  { "level", L.OPT_LEVEL, L.TIP_LEVEL }, { "loot", L.OPT_LOOT, L.TIP_LOOT },
  { "gear", L.OPT_GEAR, L.TIP_GEAR }, { "share", L.OPT_SHARE, L.TIP_SHARE },
}

-- one dropdown per event = show + sound together
local DISPLAY = {
  { "toast_sound", L.DISPLAY_TOAST_SOUND }, { "toast", L.DISPLAY_TOAST },
  { "chat_sound", L.DISPLAY_CHAT_SOUND }, { "chat", L.DISPLAY_CHAT }, { "off", L.DISPLAY_OFF },
}

function Options.DisplayValue(show, sound)
  if show == "off" then return "off" end
  return (show or "toast") .. (sound and "_sound" or "")
end

function Options.SetDisplay(kind, value)
  local s = S()
  if value == "off" then
    s.show[kind] = "off"
    return
  end
  local show, withSound = value:match("^(%a+)(.*)$")
  s.show[kind] = show == "chat" and "chat" or "toast"
  s.sound[kind] = withSound == "_sound"
end

local function nativeAvailable()
  return Settings and Settings.RegisterVerticalLayoutCategory and Settings.RegisterVerticalLayoutSubcategory
    and Settings.RegisterAddOnSetting and Settings.RegisterProxySetting and Settings.CreateCheckbox
    and Settings.CreateDropdown and Settings.CreateControlTextContainer and Settings.RegisterAddOnCategory
end

local function varType(kind)
  return (Settings.VarType and Settings.VarType[kind]) or kind:lower()
end

local function onChange(setting, fn)
  if setting.SetValueChangedCallback then
    setting:SetValueChangedCallback(function(_, value) ns.Try("option", fn, value) end)
  end
end

local function header(layout, text, tip)
  if CreateSettingsListSectionHeaderInitializer then
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer(text, tip))
  end
end

local function choices(list)
  return function()
    local c = Settings.CreateControlTextContainer()
    for _, o in ipairs(type(list) == "function" and list() or list) do c:Add(o[1], o[2], o[3]) end
    return c:GetData()
  end
end

local function checkbox(cat, key, tbl, field, name, default, tip, changed)
  local s = Settings.RegisterAddOnSetting(cat, "FNF_" .. key, field, tbl, varType("Boolean"), name, default)
  if changed then onChange(s, changed) end
  Settings.CreateCheckbox(cat, s, tip)
  return s
end

local function proxyDropdown(cat, key, kind, name, default, get, set, list, tip)
  local s = Settings.RegisterProxySetting(cat, "FNF_" .. key, varType(kind), name, default, get, set)
  Settings.CreateDropdown(cat, s, choices(list), tip)
  return s
end

local function button(layout, name, label, click, tip)
  if CreateSettingsButtonInitializer then
    layout:AddInitializer(CreateSettingsButtonInitializer(name, label, function() ns.Try("option", click) end, tip, true))
  end
end

local function chatTabs()
  local out = {}
  for i = 1, (NUM_CHAT_WINDOWS or 10) do
    local name = GetChatWindowInfo and GetChatWindowInfo(i)
    if name and name ~= "" and not ns.issecret(name) then out[#out + 1] = { i, i .. ". " .. name } end
  end
  if #out == 0 then out[1] = { 1, "1" } end
  return out
end

function Options.BuildNative()
  local D = ns.DEFAULTS
  local main, mainLayout = Settings.RegisterVerticalLayoutCategory(L.ADDON)

  -- Alerts (main page)
  header(mainLayout, L.ALERTS_HEADER, L.MILESTONE_NOTE)
  for _, row in ipairs(EVENT_ROWS) do
    local kind = row[1]
    proxyDropdown(main, "display_" .. kind, "String", row[2],
      Options.DisplayValue(D.show[kind], D.sound[kind]),
      function() return Options.DisplayValue(S().show[kind], S().sound[kind]) end,
      function(v) Options.SetDisplay(kind, v) end,
      DISPLAY, row[3] .. "\n\n" .. L.MILESTONE_NOTE)
  end
  checkbox(main, "nearbyOnly", S(), "nearbyOnly", L.OPT_NEARBY_ONLY, D.nearbyOnly, L.TIP_NEARBY_ONLY)
  header(mainLayout, L.DND_HEADER)
  checkbox(main, "dndCombat", S().dnd, "combat", L.OPT_DND_COMBAT, D.dnd.combat, L.TIP_DND_COMBAT)

  -- Where it works
  local where, whereLayout = Settings.RegisterVerticalLayoutSubcategory(main, L.PAGE_WHERE)
  header(whereLayout, L.WHERE_ALERTS_HEADER, L.TIP_WHERE_ALERTS)
  local rules = {
    { "show", L.WHERE_SHOW, L.TIP_WHERE_SHOW }, { "hold", L.WHERE_HOLD, L.TIP_WHERE_HOLD },
    { "chat", L.WHERE_CHAT, L.TIP_WHERE_CHAT }, { "off", L.WHERE_OFF, L.TIP_WHERE_OFF },
  }
  for _, w in ipairs({ { "party", L.WHERE_PARTY }, { "raid", L.WHERE_RAID }, { "pvp", L.WHERE_PVP } }) do
    local s = Settings.RegisterAddOnSetting(where, "FNF_where_" .. w[1], w[1], S().where, varType("String"), w[2], D.where[w[1]])
    Settings.CreateDropdown(where, s, choices(rules), L.TIP_WHERE_ALERTS)
  end
  header(whereLayout, L.TRACK_HEADER, L.TIP_TRACK)
  checkbox(where, "track_world", S().track, "world", L.TRACK_WORLD, D.track.world, L.TIP_TRACK_WORLD)
  checkbox(where, "track_pvp", S().track, "pvp", L.TRACK_PVP, D.track.pvp, L.TIP_TRACK_PVP)

  -- Sounds: which sound each event plays (picking one plays it)
  local snd, sndLayout = Settings.RegisterVerticalLayoutSubcategory(main, L.PAGE_SOUNDS)
  checkbox(snd, "sound", S().sound, "enabled", L.OPT_ALL_SOUNDS, D.sound.enabled, L.TIP_ALL_SOUNDS)
  header(sndLayout, L.SOUNDS_HEADER, L.TIP_SOUNDS_HEADER)
  local CATEGORY = { attacked = "pvp", engage = "pvp", died = "pvp", kill = "pvp", sighting = "sighting",
    level = "progress", loot = "progress", gear = "progress", share = "progress" }
  for _, row in ipairs(EVENT_ROWS) do
    local kind = row[1]
    local list = { { "default", L.SND_DEFAULT } }
    for _, c in ipairs(ns.Toast.SOUND_CHOICES) do list[#list + 1] = { c[1], c[2] } end
    proxyDropdown(snd, "soundPick_" .. kind, "String", row[2], "default",
      function() return S().soundPick[kind] or "default" end,
      function(v)
        S().soundPick[kind] = v
        ns.Toast.PlayChoice(v, CATEGORY[kind]) -- hear it straight away
      end, list, L.TIP_SOUND_PICK)
  end

  -- Appearance
  local look, lookLayout = Settings.RegisterVerticalLayoutSubcategory(main, L.PAGE_APPEARANCE)
  header(lookLayout, L.TOASTS_HEADER)
  local themes = {}
  for _, name in ipairs(ns.Toast.THEMES) do themes[#themes + 1] = { name, L.THEME_NAMES[name] or name, L.THEME_TIPS[name] } end
  proxyDropdown(look, "theme", "String", L.OPT_THEME, D.theme,
    function() return ns.Toast.Theme() end, function(v) S().theme = v end, themes, L.TIP_THEME)
  if Settings.CreateSlider and Settings.CreateSliderOptions then
    local function slider(key, name, default, get, set, min, max, step, fmt, tip)
      local s = Settings.RegisterProxySetting(look, "FNF_" .. key, varType("Number"), name, default, get, set)
      local o = Settings.CreateSliderOptions(min, max, step)
      if o.SetLabelFormatter and MinimalSliderWithSteppersMixin and MinimalSliderWithSteppersMixin.Label then
        o:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(v) return fmt:format(v) end)
      end
      Settings.CreateSlider(look, s, o, tip)
    end
    slider("toastScale", L.OPT_TOAST_SIZE, 100,
      function() return math.floor((tonumber(S().toastScale) or 1) * 100 + 0.5) end,
      function(v) S().toastScale = v / 100; ns.Toast.ApplyScale() end, 70, 150, 5, "%d%%", L.TIP_TOAST_SIZE)
    slider("toastDuration", L.OPT_TOAST_DURATION, D.toastDuration,
      function() return tonumber(S().toastDuration) or 3 end,
      function(v) S().toastDuration = v end, 2, 10, 1, "%d s", L.TIP_TOAST_DURATION)
  end
  button(lookLayout, L.OPT_PREVIEW, L.BTN_PREVIEW, function() ns.Toast.Test() end, L.TIP_PREVIEW)
  button(lookLayout, L.OPT_POSITION, L.BTN_UNLOCK, function() ns.Toast.ToggleUnlock() end, L.TIP_POSITION)
  header(lookLayout, L.MESSAGES_HEADER)
  proxyDropdown(look, "style", "String", L.OPT_STYLE, "flavor",
    function() return S().flavor == false and "short" or "flavor" end,
    function(v) S().flavor = (v ~= "short") end,
    { { "flavor", L.STYLE_FLAVOR, L.TIP_STYLE_FLAVOR }, { "short", L.STYLE_SHORT, L.TIP_STYLE_SHORT } }, L.TIP_STYLE)
  proxyDropdown(look, "chatTab", "Number", L.OPT_CHAT_TAB, D.chatFrame,
    function() return tonumber(S().chatFrame) or 1 end, function(v) S().chatFrame = v end, chatTabs, L.TIP_CHAT_TAB)
  checkbox(look, "weekly", S(), "weekly", L.OPT_WEEKLY, D.weekly, L.TIP_WEEKLY)

  -- Friends & sharing
  local friends, friendsLayout = Settings.RegisterVerticalLayoutSubcategory(main, L.PAGE_FRIENDS)
  header(friendsLayout, L.SHARE_HEADER, L.TIP_SHARE_HEADER)
  for _, o in ipairs({ { "level", L.OPT_LEVEL }, { "loot", L.OPT_LOOT }, { "gear", L.OPT_GEAR }, { "pvp", L.OPT_PVP } }) do
    checkbox(friends, "share_" .. o[1], S().share, o[1], o[2], D.share[o[1]], L.TIP_SHARE_KIND)
  end
  header(friendsLayout, L.PICK_HEADER)
  button(friendsLayout, L.OPT_PICK, L.BTN_PICK, function()
    if SettingsPanel and SettingsPanel.Hide then SettingsPanel:Hide() end
    ns.UI.Show("friends")
  end, L.TIP_PICK)
  header(friendsLayout, L.HITLIST_HEADER)
  checkbox(friends, "mark", S(), "mark", L.OPT_MARK, D.mark, L.TIP_MARK, function()
    if ns.Marks then ns.Marks.Refresh() end
  end)
  proxyDropdown(friends, "forgetAfter", "Number", L.OPT_FORGET, 0,
    function() return tonumber(S().forgetAfter) or 0 end,
    function(v)
      S().forgetAfter = v
      ns.Data.ForgetOld(FriendsAndFoesDB)
      if ns.UI then ns.UI.Refresh() end
    end,
    { { 0, L.FORGET_NEVER }, { 90, L.FORGET_3M }, { 180, L.FORGET_6M }, { 365, L.FORGET_1Y } }, L.TIP_FORGET)
  button(friendsLayout, L.OPT_SHARE_NOW, L.BTN_SHARE, function() ns.UI.ShareHitlist() end, L.TIP_SHARE_NOW)

  -- Advanced
  local adv, advLayout = Settings.RegisterVerticalLayoutSubcategory(main, L.PAGE_ADVANCED)
  local mm = Settings.RegisterProxySetting(adv, "FNF_minimap", varType("Boolean"), L.OPT_MINIMAP_SHOW, false,
    function() return not S().minimap.hide end,
    function(v)
      S().minimap.hide = not v
      if ns.Minimap then ns.Minimap.Update() end
    end)
  Settings.CreateCheckbox(adv, mm, L.TIP_MINIMAP)
  local dbg = Settings.RegisterProxySetting(adv, "FNF_debug", varType("Boolean"), L.OPT_DEBUG, false,
    function() return S().debug and true or false end, function(v) ns.SetDebug(v) end)
  Settings.CreateCheckbox(adv, dbg, L.TIP_DEBUG)
  header(advLayout, L.TOOLS_HEADER)
  button(advLayout, L.OPT_STATUS, L.BTN_STATUS, function() ns.PrintStatus() end, L.TIP_STATUS)
  button(advLayout, L.OPT_SIM, L.BTN_SIM, function() ns.Sim.RunAll(false) end, L.TIP_SIM)
  button(advLayout, L.OPT_SIM_STOP, L.BTN_SIM_STOP, function() ns.Sim.Stop() end, L.TIP_SIM_STOP)
  button(advLayout, L.OPT_SIM_CLEAR, L.BTN_SIM_CLEAR, function() ns.Sim.Clear() end, L.TIP_SIM_CLEAR)

  Settings.RegisterAddOnCategory(main)
  native = main
  return main
end

local function create()
  if nativeAvailable() then
    local ok, err = pcall(Options.BuildNative)
    if ok then return end
    ns.Debug("ERR:options-native", err) -- fall back to the canvas panel
  end
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
  if not panel then
    panel = CreateFrame("Frame")
    panel:Hide()
    build(panel)
  end
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

local function openCategory(cat)
  if not (cat and Settings and Settings.OpenToCategory) then return false end
  return pcall(Settings.OpenToCategory, cat.GetID and cat:GetID() or cat)
end

-- The game's settings window can't be opened by an addon during combat (protected UI),
-- so Options simply isn't available in combat.

local function inCombat()
  if not InCombatLockdown then return false end
  local ok, locked = pcall(InCombatLockdown)
  return ok and not ns.issecret(locked) and locked and true or false
end

function Options.Open()
  if inCombat() then
    print("|cff33ff99" .. L.ADDON .. "|r " .. L.OPTIONS_IN_COMBAT)
    return
  end
  if not (native or panel) then create() end
  if openCategory(native) or openCategory(category) then return end
  if panel and not category and InterfaceOptionsFrame_OpenToCategory then
    if pcall(InterfaceOptionsFrame_OpenToCategory, panel) then
      pcall(InterfaceOptionsFrame_OpenToCategory, panel) -- the old panel needs it twice
      return
    end
  end
  openStandalone()
end

-- set up the options at login; after combat if you logged in or reloaded mid-fight
local createAfterCombat = false
ns.OnReady(function()
  if native or panel then return end
  if inCombat() then createAfterCombat = true else create() end
end)
ns.On("PLAYER_REGEN_ENABLED", function()
  if createAfterCombat and not (native or panel) then
    createAfterCombat = false
    create()
  end
end)
