local _, ns = ...
local L = ns.L

-- Settings live in the game's own Settings panel: Options -> AddOns -> Friends & Foes. Four pages:
--   Alerts (main)      Test alerts; four groups of alerts, each Toast / Chat / Off (with or
--                      without sound) with its own sound; when alerts wait (instances, combat)
--   Appearance         toasts, messages, the minimap button
--   Friends & sharing  what you share, where your own PvP is tracked, your alert list, the hitlist
--   Advanced           debug logging and the debug report
-- The game's controls read and write the settings directly, so there's nothing to refresh.
local Options = {}
ns.Options = Options

local function S() return ns.S() end

-- what you share with friends: { key in settings.share, label, tooltip }
Options.SHARE = {
  { "level", L.OPT_LEVEL, L.TIP_SHARE_KIND }, { "loot", L.OPT_LOOT, L.TIP_SHARE_KIND },
  { "gear", L.OPT_GEAR, L.TIP_SHARE_KIND }, { "pvp", L.OPT_PVP, L.TIP_SHARE_PVP },
  { "where", L.OPT_SHARE_WHERE, L.TIP_SHARE_WHERE },
  { "relay", L.OPT_SHARE_RELAY, L.TIP_SHARE_RELAY },
}

-- the alerts, four groups with one setting each: { key, label, tooltip, alerts in it }. The
-- setting is still kept per alert (settings.show / settings.sound), all of a group set together.
Options.ALERT_GROUPS = {
  { "fights", L.ALERT_FIGHTS, L.TIP_ALERT_FIGHTS, { "attacked", "engage", "died", "kill" } },
  { "sighting", L.ALERT_SIGHTINGS, L.TIP_SIGHTING, { "sighting" } },
  { "progress", L.ALERT_PROGRESS, L.TIP_ALERT_PROGRESS, { "loot", "gear", "level" } }, -- (loot leads: level-ups are quiet)
  { "bounty", L.OPT_CONTRACT, L.TIP_CONTRACT, { "contract" } },
}
-- alerts that never make a sound of their own: you attacking someone (it happens a lot), and a
-- plain level-up (milestones like level 60 still chime)
Options.QUIET = { engage = true, level = true }
-- one sound for each kind of alert: { key in settings.soundPick, label }
local SOUND_GROUPS = {
  { "trouble", L.SOUND_TROUBLE, L.TIP_SOUND_TROUBLE }, { "victory", L.SOUND_VICTORY, L.TIP_SOUND_VICTORY }, { "sighting", L.SOUND_SIGHTING }, { "progress", L.SOUND_PROGRESS }, { "bounty", L.SOUND_BOUNTY },
}

-- one dropdown per alert = show + sound together
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
  s.sound[kind] = withSound == "_sound" and not Options.QUIET[kind]
end

-- a group: what its first alert shows; setting it sets every alert in it
function Options.GroupValue(group)
  local first = group[4][1]
  return Options.DisplayValue(S().show[first], S().sound[first])
end
function Options.SetGroup(group, value)
  for _, kind in ipairs(group[4]) do Options.SetDisplay(kind, value) end
end

---------------------------------------------------------------------------
-- building blocks
---------------------------------------------------------------------------
local function available()
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

---------------------------------------------------------------------------
-- the pages
---------------------------------------------------------------------------
local native -- the main category, once built

function Options.BuildNative()
  local D = ns.DEFAULTS
  local main, mainLayout = Settings.RegisterVerticalLayoutCategory(L.ADDON)

  -- Alerts (main page): try them first, then one row per group of alerts
  button(mainLayout, L.OPT_SIM, L.BTN_TEST, function() ns.Toast.Test() end, L.TIP_SIM)
  header(mainLayout, L.ALERTS_HEADER, L.MILESTONE_NOTE)
  for _, group in ipairs(Options.ALERT_GROUPS) do
    local first = group[4][1]
    proxyDropdown(main, "display_" .. group[1], "String", group[2],
      Options.DisplayValue(D.show[first], D.sound[first]),
      function() return Options.GroupValue(group) end,
      function(v) Options.SetGroup(group, v) end,
      DISPLAY, group[3] .. "\n\n" .. L.MILESTONE_NOTE)
  end
  proxyDropdown(main, "levelEvery", "Number", L.OPT_LEVEL_EVERY, D.levelEvery,
    function() return tonumber(S().levelEvery) or 1 end, function(v) S().levelEvery = v end,
    { { 1, L.LEVEL_EVERY_1 }, { 5, L.LEVEL_EVERY_5 }, { 10, L.LEVEL_EVERY_10 }, { 60, L.LEVEL_EVERY_MAX } }, L.TIP_LEVEL_EVERY)
  checkbox(main, "nearbyOnly", S(), "nearbyOnly", L.OPT_NEARBY_ONLY, D.nearbyOnly, L.TIP_NEARBY_ONLY)
  -- sounds: on or off for all alerts, and one sound for each kind (picking one plays it)
  header(mainLayout, L.SOUNDS_HEADER, L.TIP_SOUNDS_HEADER)
  checkbox(main, "sound", S().sound, "enabled", L.OPT_ALL_SOUNDS, D.sound.enabled, L.TIP_ALL_SOUNDS)
  local sounds = { { "default", L.SND_DEFAULT } }
  for _, c in ipairs(ns.Toast.SOUND_CHOICES) do sounds[#sounds + 1] = { c[1], c[2] } end
  for _, g in ipairs(SOUND_GROUPS) do
    local key = g[1]
    proxyDropdown(main, "soundPick_" .. key, "String", g[2], D.soundPick[key] or "default",
      function() return S().soundPick[key] or "default" end,
      function(v)
        S().soundPick[key] = v
        ns.Toast.PlayChoice(v, key) -- hear it straight away
      end, sounds, g[3] or L.TIP_SOUND_PICK)
  end
  -- when alerts wait: in dungeons, raids and battlegrounds (one setting for all), and in combat
  header(mainLayout, L.HOLD_HEADER)
  local inst = Settings.RegisterAddOnSetting(main, "FNF_instances", "instances", S(), varType("String"), L.WHERE_INSTANCES, D.instances)
  Settings.CreateDropdown(main, inst, choices({
    { "show", L.WHERE_SHOW, L.TIP_WHERE_SHOW }, { "hold", L.WHERE_HOLD, L.TIP_WHERE_HOLD },
    { "off", L.WHERE_OFF, L.TIP_WHERE_OFF },
  }), L.TIP_WHERE_ALERTS)
  checkbox(main, "dndCombat", S().dnd, "combat", L.OPT_DND_COMBAT, D.dnd.combat, L.TIP_DND_COMBAT)


  -- Appearance: toasts, messages, the minimap button
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
      function() return tonumber(S().toastDuration) or ns.DEFAULT_TOAST_DURATION end,
      function(v) S().toastDuration = v end, 2, 10, 1, "%d s", L.TIP_TOAST_DURATION)
    slider("toastMax", L.OPT_TOAST_MAX, D.toastMax,
      function() return tonumber(S().toastMax) or 2 end,
      function(v) S().toastMax = v; ns.Toast.ApplyMax() end, 1, 4, 1, "%d", L.TIP_TOAST_MAX)
  end
  proxyDropdown(look, "toastGrow", "String", L.OPT_TOAST_GROW, D.toastGrow,
    function() return S().toastGrow == "up" and "up" or "down" end,
    function(v) S().toastGrow = v; ns.Toast.ApplyScale() end,
    { { "down", L.GROW_DOWN }, { "up", L.GROW_UP } }, L.TIP_TOAST_GROW)
  button(lookLayout, L.OPT_POSITION, L.BTN_UNLOCK, function() ns.Toast.ToggleUnlock() end, L.TIP_POSITION)
  header(lookLayout, L.MESSAGES_HEADER)
  proxyDropdown(look, "style", "String", L.OPT_STYLE, "flavor",
    function() return S().flavor == false and "short" or "flavor" end,
    function(v) S().flavor = (v ~= "short") end,
    { { "flavor", L.STYLE_FLAVOR, L.TIP_STYLE_FLAVOR }, { "short", L.STYLE_SHORT, L.TIP_STYLE_SHORT } }, L.TIP_STYLE)
  proxyDropdown(look, "chatTab", "Number", L.OPT_CHAT_TAB, D.chatFrame,
    function() return tonumber(S().chatFrame) or 1 end, function(v) S().chatFrame = v end, chatTabs, L.TIP_CHAT_TAB)
  checkbox(look, "weekly", S(), "weekly", L.OPT_WEEKLY, D.weekly, L.TIP_WEEKLY)
  header(lookLayout, L.MINIMAP_HEADER)
  local mm = Settings.RegisterProxySetting(look, "FNF_minimap", varType("Boolean"), L.OPT_MINIMAP_SHOW, true,
    function() return not S().minimap.hide end,
    function(v)
      S().minimap.hide = not v
      if ns.Minimap then ns.Minimap.Update() end
    end)
  Settings.CreateCheckbox(look, mm, L.TIP_MINIMAP)

  -- Friends & sharing: what you share, where your own PvP is tracked, alert list, hitlist
  local friends, friendsLayout = Settings.RegisterVerticalLayoutSubcategory(main, L.PAGE_FRIENDS)
  header(friendsLayout, L.SHARE_HEADER, L.TIP_SHARE_HEADER)
  for _, o in ipairs(Options.SHARE) do
    -- your profile goes out again right away, so friends see the change
    checkbox(friends, "share_" .. o[1], S().share, o[1], o[2], D.share[o[1]], o[3], function() ns.Profile.Changed() end)
  end
  header(friendsLayout, L.TRACK_HEADER, L.TIP_TRACK)
  checkbox(friends, "track_world", S().track, "world", L.TRACK_WORLD, D.track.world, L.TIP_TRACK_WORLD)
  checkbox(friends, "hideLowAlts", S(), "hideLowAlts", L.OPT_HIDE_LOW_ALTS, D.hideLowAlts, L.TIP_HIDE_LOW_ALTS, function()
    if ns.UI and ns.UI.Refresh then ns.UI.Refresh() end
  end)
  header(friendsLayout, L.PICK_HEADER)
  button(friendsLayout, L.OPT_PICK, L.BTN_PICK, function() ns.UI.ShowAlertList() end, L.TIP_PICK)
  header(friendsLayout, L.HITLIST_HEADER)
  checkbox(friends, "mark", S(), "mark", L.OPT_MARK, D.mark, L.TIP_MARK, function()
    if ns.Marks then ns.Marks.Refresh() end
  end)
  checkbox(friends, "markTooltip", S(), "markTooltip", L.OPT_MARK_TOOLTIP, D.markTooltip, L.TIP_MARK_TOOLTIP)
  -- forgetting deletes entries: if any would go now, ask first; "No" puts the setting back
  local FORGET_CHOICES = {
    { 7, L.FORGET_1W }, { 14, L.FORGET_2W }, { 30, L.FORGET_1M }, { 90, L.FORGET_3M },
    { 180, L.FORGET_6M }, { 365, L.FORGET_1Y }, { 0, L.FORGET_FOREVER },
  }
  local function forgetDropdown(key, name, default, tip)
    local dd
    dd = proxyDropdown(friends, key, "Number", name, default,
      function()
        local v = tonumber(S()[key])
        if v == nil then v = default end
        return v
      end,
      function(v)
        local old = tonumber(S()[key])
        if old == nil then old = default end
        if v == old then return end
        local n = ns.Data.CountForget(FriendsAndFoesDB, key, v)
        if n == 0 then
          S()[key] = v
          return
        end
        S()[key] = old -- until confirmed
        ns.UI.Confirm(L.CONFIRM_FORGET:format(n), function()
          S()[key] = v
          ns.Data.ForgetOld(FriendsAndFoesDB)
          if ns.UI then ns.UI.Refresh() end
        end, function()
          if dd and dd.SetValue then dd:SetValue(old) end
        end)
      end, FORGET_CHOICES, tip)
  end
  forgetDropdown("forgetAttackers", L.OPT_FORGET_ATTACKERS, D.forgetAttackers, L.TIP_FORGET_ATTACKERS)
  forgetDropdown("forgetKilledOnce", L.OPT_FORGET_KILLED_ONCE, D.forgetKilledOnce, L.TIP_FORGET_KILLED_ONCE)
  forgetDropdown("forgetKilledMore", L.OPT_FORGET_KILLED_MORE, D.forgetKilledMore, L.TIP_FORGET_KILLED_MORE)

  -- Advanced: debugging only
  local adv, advLayout = Settings.RegisterVerticalLayoutSubcategory(main, L.PAGE_ADVANCED)
  local dbg = Settings.RegisterProxySetting(adv, "FNF_debug", varType("Boolean"), L.OPT_DEBUG, false,
    function() return S().debug and true or false end, function(v) ns.SetDebug(v) end)
  Settings.CreateCheckbox(adv, dbg, L.TIP_DEBUG)
  button(advLayout, L.OPT_REPORT, L.BTN_REPORT, function() ns.Report.Show() end, L.TIP_REPORT)

  Settings.RegisterAddOnCategory(main)
  native = main
  return main
end

local function create()
  if not available() then
    ns.Debug("OPTIONS", "the game's Settings panel isn't available")
    return
  end
  local ok, err = pcall(Options.BuildNative)
  if not ok then ns.Debug("ERR:options", err) end
end

---------------------------------------------------------------------------
-- opening
---------------------------------------------------------------------------
-- The game's settings window can't be opened by an addon during combat (protected UI),
-- so Options simply isn't available in combat.
local function inCombat()
  if not InCombatLockdown then return false end
  local ok, locked = pcall(InCombatLockdown)
  return ok and not ns.issecret(locked) and locked and true or false
end

function Options.Open()
  local prefix = "|cff33ff99" .. L.ADDON .. "|r "
  if inCombat() then
    print(prefix .. L.OPTIONS_IN_COMBAT)
    return
  end
  if not native then create() end
  local cat = native
  if cat and Settings and Settings.OpenToCategory
    and pcall(Settings.OpenToCategory, cat.GetID and cat:GetID() or cat) then
    return
  end
  print(prefix .. L.OPTIONS_WHERE) -- (no Settings panel to open: say where they are)
end

-- set up the options at login; after combat if you logged in or reloaded mid-fight
local createAfterCombat = false
ns.OnReady(function()
  if native then return end
  if inCombat() then createAfterCombat = true else create() end
end)
ns.On("PLAYER_REGEN_ENABLED", function()
  if createAfterCombat and not native then
    createAfterCombat = false
    create()
  end
end)
