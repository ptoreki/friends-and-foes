local _, ns = ...
local L = ns.L

local UI = {}
ns.UI = UI

local WIDTH, HEIGHT = 700, 480
local ROWS, ROW_H = 15, 20
local MAX_COLS = 7

local win, rowsFrame, header, rows, detail, settings, pageText, emptyText, simBanner, friendsHint
local tabButtons = {}
local currentTab = "hitlist"
local offset = 0
local data = {}
local selected

local BACKDROP = {
  bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
  edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
  tile = true, tileSize = 32, edgeSize = 32,
  insets = { left = 11, right = 12, top = 12, bottom = 11 },
}

local function R() return ns.Data.ViewRealm() end
local onlineNow = {} -- friend record name -> true while they are in the roster (not saved)

---------------------------------------------------------------------------
-- data per tab
---------------------------------------------------------------------------
local function sortedValues(tbl, filter)
  local out = {}
  for _, v in pairs(tbl) do
    if not filter or filter(v) then out[#out + 1] = v end
  end
  table.sort(out, function(a, b) return (a.lastSeen or 0) > (b.lastSeen or 0) end)
  return out
end

local function victimsText(victims)
  local list = {}
  for name in pairs(victims or {}) do
    local p = R().players[name]
    list[#list + 1] = ns.ClassColored(name, p and p.class)
  end
  table.sort(list)
  return ns.JoinNames(list)
end

local function lastText(e)
  return ns.Ago(e.lastSeen) .. (e.lastZone and (" - " .. e.lastZone) or "")
end

local function lvl(e) return e.level and tostring(e.level) or "?" end
local function guild(e) return e.guild and ("<" .. e.guild .. ">") or "" end
local function nameCol(e) return ns.ClassColored(e.name, e.class) end

local function hitKills(e)
  local s = tostring(e.kills or 0)
  if (e.suspect or 0) > 0 then s = s .. "*" end
  if (e.revenge or 0) > 0 then s = s .. "  |cff33ff33" .. L.REVENGE_SHORT:format(e.revenge) .. "|r" end
  return s
end

local TABS = {
  { key = "hitlist", label = L.TAB_HITLIST,
    columns = {
      { L.COL_NAME, 150, nameCol },
      { L.COL_LEVEL, 30, lvl },
      { L.COL_GUILD, 95, guild },
      { L.COL_ATTACKS, 50, function(e) return e.attacks or 0 end },
      { L.COL_KILLS, 75, hitKills },
      { L.COL_VICTIMS, 105, function(e) return victimsText(e.victims) end },
      { L.COL_LAST, 150, lastText },
    },
    fetch = function() return sortedValues(R().hitlist) end },
  { key = "enemies", label = L.TAB_ENEMIES,
    columns = {
      { L.COL_NAME, 155, nameCol },
      { L.COL_LEVEL, 30, lvl },
      { L.COL_GUILD, 110, guild },
      { L.COL_KILLS_ON_US, 75, function(e) return e.k end },
      { L.COL_DEATHS_TO_US, 70, function(e) return e.d end },
      { L.COL_ASSISTS, 55, function(e) return e.a end },
      { L.COL_LAST, 165, lastText },
    },
    fetch = function() return sortedValues(R().players, function(p) return p.enemy end) end },
  { key = "friends", label = L.TAB_FRIENDS,
    columns = {
      { L.COL_NAME, 150, nameCol },
      { L.COL_LEVEL, 30, lvl },
      { L.COL_VERSION, 50, function(e)
        if not e.version then return "" end
        if ns.VersionNewer(e.version, ns.VERSION) then return "|cffffd100" .. e.version .. "|r" end
        return e.version
      end },
      { L.COL_TAKEDOWNS, 70, function(e) return e.pending and "" or e.k end },
      { L.COL_DEATHS, 55, function(e) return e.pending and "" or e.d end },
      { L.COL_ALERTS, 50, function(e)
        local tag = ns.Comm.TagFor(e.name)
        if ns.Comm.IsPicked(tag) then return "|cff33ff33" .. L.ALERTS_ON .. "|r" end
        if ns.Comm.GroupActive() then return "|cff888888" .. L.ALERTS_OFF .. "|r" end
        return "|cff888888" .. L.ALERTS_ALL .. "|r"
      end },
      { L.COL_LAST_EVENT, 255, function(e)
        if e.pending then return "|cff33ff33" .. L.FRIEND_ONLINE .. "|r  |cff888888" .. L.FRIEND_NOT_HEARD .. "|r" end
        local online = onlineNow[e.name] and ("|cff33ff33" .. L.FRIEND_ONLINE .. "|r  ") or ""
        return online .. (e.lastText or "") .. "  |cff888888" .. ns.Ago(e.lastSeen) .. "|r"
      end },
    },
    -- friends we've heard from, plus online Battle.net friends in Forever the addon can see
    -- but hasn't received anything from yet (so you can tell "not detected" from "silent")
    fetch = function()
      local rows = sortedValues(R().players, function(p) return p.friend end)
      if ns.viewSim then return rows end
      wipe(onlineNow)
      local onlineRows = {}
      for _, name in ipairs(ns.Comm.EveryoneNames()) do
        local p = ns.Data.Resolve(R().players, name)
        local rec = R().players[p]
        if rec and rec.friend then
          onlineNow[rec.name] = true
        else
          onlineRows[#onlineRows + 1] = { name = name, pending = true }
        end
      end
      for _, row in ipairs(onlineRows) do table.insert(rows, 1, row) end
      return rows
    end },
  { key = "feed", label = L.TAB_FEED,
    columns = {
      { L.COL_TIME, 80, function(e) return ns.Ago(e.t) end },
      { L.COL_EVENT, 580, function(e) return e.text end },
    },
    fetch = function()
      local feed, out = R().feed, {}
      for i = #feed, 1, -1 do out[#out + 1] = feed[i] end
      return out
    end },
  { key = "settings", label = L.TAB_SETTINGS },
}

local function tabDef(key)
  for _, t in ipairs(TABS) do if t.key == key then return t end end
end

---------------------------------------------------------------------------
-- list rendering
---------------------------------------------------------------------------
local function layoutColumns(def)
  local x = 0
  for c = 1, MAX_COLS do
    local col = def.columns[c]
    local h = header.cells[c]
    if col then
      h:ClearAllPoints()
      h:SetPoint("LEFT", header, "LEFT", x + 4, 0)
      h:SetWidth(col[2] - 6)
      h:SetText(col[1])
      h:Show()
      for _, row in ipairs(rows) do
        local cell = row.cells[c]
        cell:ClearAllPoints()
        cell:SetPoint("LEFT", row, "LEFT", x + 4, 0)
        cell:SetWidth(col[2] - 6)
        cell:Show()
      end
      x = x + col[2]
    else
      h:Hide()
      for _, row in ipairs(rows) do row.cells[c]:Hide() end
    end
  end
end

local function refreshShareStatus()
  local queued = ns.Comm.QueuedCount("bulk")
  detail.shareStatus:SetText(queued > 0 and L.SHARE_QUEUED:format(queued) or "")
  if ns.viewSim then detail.share:Disable() else detail.share:Enable() end
end

local function refreshDetail()
  if currentTab ~= "hitlist" then
    detail:Hide()
    return
  end
  detail:Show()
  refreshShareStatus()
  local h = selected and R().hitlist[selected]
  if h then
    local extra = h.sharedBy and ("  |cff888888" .. L.SHARED_BY:format(h.sharedBy) .. "|r") or ""
    detail.label:SetText(ns.ClassColored(h.name, h.class) .. extra .. "  |cff888888" .. L.SUSPECT_HINT .. "|r")
    detail.note:SetText(h.note or "")
    detail.note:Enable()
    detail.save:Enable()
    detail.remove:Enable()
  else
    detail.label:SetText(L.NONE_SELECTED)
    detail.note:SetText("")
    detail.note:Disable()
    detail.save:Disable()
    detail.remove:Disable()
  end
end

function UI.Refresh()
  if not win or not win:IsShown() then return end
  local def = tabDef(currentTab)
  for _, b in ipairs(tabButtons) do
    if b.key == currentTab then b:LockHighlight() else b:UnlockHighlight() end
  end
  simBanner:SetShown(ns.viewSim and true or false)

  if currentTab == "settings" then
    rowsFrame:Hide()
    detail:Hide()
    pageText:SetText("")
    settings:Show()
    friendsHint:Hide()
    UI.RefreshSettings()
    return
  end
  settings:Hide()
  rowsFrame:Show()

  data = def.fetch()
  local maxOffset = math.max(0, #data - ROWS)
  if offset > maxOffset then offset = maxOffset end
  layoutColumns(def)

  for i, row in ipairs(rows) do
    local e = data[offset + i]
    row.entry = e
    if e then
      for c, col in ipairs(def.columns) do
        local ok, val = pcall(col[3], e)
        row.cells[c]:SetText(ok and tostring(val) or "?")
      end
      row.sel:SetShown(currentTab == "hitlist" and e.name ~= nil and e.name == selected)
      row:Show()
    else
      row:Hide()
    end
  end
  emptyText:SetShown(#data == 0)
  if #data > ROWS then
    pageText:SetText(string.format("%d-%d of %d", offset + 1, math.min(offset + ROWS, #data), #data))
  else
    pageText:SetText(#data > 0 and tostring(#data) or "")
  end
  refreshDetail()
  friendsHint:SetShown(currentTab == "friends" and not ns.viewSim)
  friendsHint:SetText(ns.Comm.GroupActive() and L.PICK_HINT_ACTIVE or L.PICK_HINT_ALL)
end

local refreshPending = false
function UI.OnDataChanged()
  if not win or not win:IsShown() or refreshPending then return end
  refreshPending = true
  C_Timer.After(0.2, function()
    refreshPending = false
    ns.Try("refresh", UI.Refresh)
  end)
end

function UI.SelectTab(key)
  currentTab = key
  offset = 0
  UI.Refresh()
end

---------------------------------------------------------------------------
-- settings tab
---------------------------------------------------------------------------
local checks = {}
local capsText, modeText

local function check(parent, x, y, label, get, set)
  local cb = CreateFrame("CheckButton", nil, parent, "UICheckButtonTemplate")
  cb:SetSize(22, 22)
  cb:SetPoint("TOPLEFT", x, y)
  local fs = cb:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  fs:SetPoint("LEFT", cb, "RIGHT", 2, 0)
  fs:SetText(label)
  cb:SetScript("OnClick", function(self) set(self:GetChecked() and true or false) end)
  cb.get = get
  checks[#checks + 1] = cb
  return cb
end

local function heading(parent, x, y, text)
  local fs = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  fs:SetPoint("TOPLEFT", x, y)
  fs:SetText(text)
end

local function buildSettings(parent)
  local S = ns.S
  local function toggle(tbl, key)
    return function() return S()[tbl][key] end, function(v) S()[tbl][key] = v end
  end
  local STEP = 21

  local x1, x2, x3 = 10, 230, 450
  heading(parent, x1, -5, L.SHARE_HEADER)
  local y = -24
  for _, o in ipairs({ { "level", L.OPT_LEVEL }, { "loot", L.OPT_LOOT }, { "gear", L.OPT_GEAR }, { "pvp", L.OPT_PVP } }) do
    check(parent, x1, y, o[2], toggle("share", o[1]))
    y = y - STEP
  end

  y = y - 8
  heading(parent, x1, y, L.DND_HEADER)
  y = y - 19
  check(parent, x1, y, L.OPT_DND_COMBAT, toggle("dnd", "combat"))
  y = y - STEP
  check(parent, x1, y, L.OPT_DND_INSTANCE, toggle("dnd", "instance"))

  heading(parent, x2, -5, L.TOAST_HEADER)
  y = -24
  for _, o in ipairs({
    { "level", L.OPT_LEVEL }, { "loot", L.OPT_LOOT }, { "gear", L.OPT_GEAR },
    { "attacked", L.OPT_ATTACKED }, { "died", L.OPT_DIED }, { "kill", L.OPT_KILL },
    { "sighting", L.OPT_SIGHTING }, { "share", L.OPT_SHARE },
  }) do
    check(parent, x2, y, o[2], toggle("toast", o[1]))
    y = y - STEP
  end

  heading(parent, x3, -5, L.SOUND_HEADER)
  y = -24
  for _, o in ipairs({
    { "enabled", L.OPT_SOUND }, { "pvp", L.OPT_SOUND_PVP }, { "progress", L.OPT_SOUND_PROGRESS }, { "sighting", L.OPT_SOUND_SIGHTING },
  }) do
    check(parent, x3, y, o[2], toggle("sound", o[1]))
    y = y - STEP
  end

  y = y - 8
  heading(parent, x3, y, L.MISC_HEADER)
  y = y - 19
  check(parent, x3, y, L.OPT_MINIMAP,
    function() return not S().minimap.hide end,
    function(v)
      S().minimap.hide = not v
      if ns.Minimap then ns.Minimap.Update() end
    end)
  y = y - STEP
  check(parent, x3, y, L.OPT_DEBUG,
    function() return S().debug end,
    function(v) S().debug = v end)

  local unlock = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  unlock:SetSize(110, 22)
  unlock:SetPoint("TOPLEFT", x1, -205)
  unlock:SetText(L.BTN_UNLOCK)
  unlock:SetScript("OnClick", function() ns.Toast.ToggleUnlock() end)

  local test = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  test:SetSize(110, 22)
  test:SetPoint("LEFT", unlock, "RIGHT", 8, 0)
  test:SetText(L.BTN_TEST)
  test:SetScript("OnClick", function() ns.Toast.Test() end)

  local sim = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  sim:SetSize(110, 22)
  sim:SetPoint("LEFT", test, "RIGHT", 8, 0)
  sim:SetText(L.BTN_SIM)
  sim:SetScript("OnClick", function() ns.Sim.RunAll(false) end)

  heading(parent, x1, -238, L.CAPS_HEADER)
  capsText = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  capsText:SetPoint("TOPLEFT", x1, -256)
  capsText:SetJustifyH("LEFT")
  capsText:SetWidth(210)

  heading(parent, x2, -238, L.MODE_HEADER)
  modeText = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  modeText:SetPoint("TOPLEFT", x2, -256)
  modeText:SetJustifyH("LEFT")
  modeText:SetJustifyV("TOP")
  modeText:SetWidth(420)
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

function UI.RefreshSettings()
  for _, cb in ipairs(checks) do cb:SetChecked(cb.get() and true or false) end
  local lines = {}
  for _, c in ipairs(CAP_LABELS) do
    local v = ns.caps[c[1]] or "untested"
    lines[#lines + 1] = c[2] .. ": " .. (CAP_COLORS[v] or "") .. v .. "|r"
  end
  lines[#lines + 1] = L.ERRORS_LINE:format(ns.errors)
  capsText:SetText(table.concat(lines, "\n"))
  modeText:SetText(modeNotes())
end

---------------------------------------------------------------------------
-- window
---------------------------------------------------------------------------
local function button(parent, w, text, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b:SetSize(w, 22)
  b:SetText(text)
  b:SetScript("OnClick", onClick)
  return b
end

local function build()
  win = CreateFrame("Frame", "FriendsAndFoesFrame", UIParent, "BackdropTemplate")
  win:SetSize(WIDTH, HEIGHT)
  win:SetPoint("CENTER")
  win:SetBackdrop(BACKDROP)
  win:SetFrameStrata("DIALOG")
  win:SetMovable(true)
  win:SetClampedToScreen(true)
  win:EnableMouse(true)
  win:RegisterForDrag("LeftButton")
  win:SetScript("OnDragStart", win.StartMoving)
  win:SetScript("OnDragStop", win.StopMovingOrSizing)
  win:SetScript("OnShow", function() UI.Refresh() end)
  win:Hide()
  tinsert(UISpecialFrames, "FriendsAndFoesFrame")

  local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetPoint("TOP", 0, -18)
  title:SetText(L.ADDON)

  local close = CreateFrame("Button", nil, win, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -6, -6)

  -- simulation banner
  simBanner = CreateFrame("Frame", nil, win)
  simBanner:SetSize(260, 22)
  simBanner:SetPoint("TOPLEFT", 18, -14)
  local simText = simBanner:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  simText:SetPoint("LEFT")
  simText:SetText("|cffff9933" .. L.SIM_BANNER .. "|r")
  local simExit = button(simBanner, 80, L.SIM_EXIT, function()
    ns.viewSim = false
    UI.Refresh()
  end)
  simExit:SetPoint("LEFT", simText, "RIGHT", 6, 0)
  simBanner:Hide()

  -- tabs
  local prev
  for _, t in ipairs(TABS) do
    local b = button(win, 100, t.label, function() UI.SelectTab(t.key) end)
    if prev then b:SetPoint("LEFT", prev, "RIGHT", 4, 0) else b:SetPoint("TOPLEFT", 20, -44) end
    b.key = t.key
    tabButtons[#tabButtons + 1] = b
    prev = b
  end

  -- list area
  rowsFrame = CreateFrame("Frame", nil, win)
  rowsFrame:SetPoint("TOPLEFT", 20, -74)
  rowsFrame:SetPoint("BOTTOMRIGHT", -20, 80)
  rowsFrame:EnableMouseWheel(true)
  rowsFrame:SetScript("OnMouseWheel", function(_, delta)
    offset = math.max(0, math.min(offset - delta * 3, math.max(0, #data - ROWS)))
    UI.Refresh()
  end)

  header = CreateFrame("Frame", nil, rowsFrame)
  header:SetPoint("TOPLEFT")
  header:SetPoint("TOPRIGHT")
  header:SetHeight(ROW_H)
  header.cells = {}
  for c = 1, MAX_COLS do
    local fs = header:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(false)
    header.cells[c] = fs
  end

  rows = {}
  for i = 1, ROWS do
    local row = CreateFrame("Button", nil, rowsFrame)
    row:SetHeight(ROW_H)
    row:SetPoint("TOPLEFT", header, "BOTTOMLEFT", 0, -((i - 1) * ROW_H))
    row:SetPoint("TOPRIGHT", header, "BOTTOMRIGHT", 0, -((i - 1) * ROW_H))
    local hl = row:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.08)
    row.sel = row:CreateTexture(nil, "BACKGROUND")
    row.sel:SetAllPoints()
    row.sel:SetColorTexture(1, 0.8, 0.1, 0.15)
    row.sel:Hide()
    if i % 2 == 0 then
      local bg = row:CreateTexture(nil, "BACKGROUND", nil, -1)
      bg:SetAllPoints()
      bg:SetColorTexture(1, 1, 1, 0.03)
    end
    row.cells = {}
    for c = 1, MAX_COLS do
      local fs = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
      fs:SetJustifyH("LEFT")
      fs:SetWordWrap(false)
      row.cells[c] = fs
    end
    row:SetScript("OnClick", function(self)
      if currentTab == "hitlist" and self.entry then
        selected = self.entry.name
        UI.Refresh()
      elseif currentTab == "friends" and self.entry and not ns.viewSim then
        UI.TogglePick(self.entry.name)
      end
    end)
    rows[i] = row
  end

  emptyText = rowsFrame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  emptyText:SetPoint("CENTER")
  emptyText:SetText(L.EMPTY)

  pageText = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  pageText:SetPoint("BOTTOMRIGHT", -24, 18)

  friendsHint = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  friendsHint:SetPoint("BOTTOMLEFT", 24, 40)
  friendsHint:SetPoint("BOTTOMRIGHT", -24, 40)
  friendsHint:SetJustifyH("LEFT")

  -- hitlist detail (note / remove / share)
  detail = CreateFrame("Frame", nil, win)
  detail:SetPoint("BOTTOMLEFT", 20, 30)
  detail:SetPoint("BOTTOMRIGHT", -20, 30)
  detail:SetHeight(46)
  detail.label = detail:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  detail.label:SetPoint("TOPLEFT")
  local noteLabel = detail:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  noteLabel:SetPoint("BOTTOMLEFT", 0, 4)
  noteLabel:SetText(L.NOTE)
  detail.note = CreateFrame("EditBox", nil, detail, "InputBoxTemplate")
  detail.note:SetSize(300, 20)
  detail.note:SetPoint("LEFT", noteLabel, "RIGHT", 10, 0)
  detail.note:SetAutoFocus(false)
  detail.note:SetMaxLetters(200)
  local function saveNote()
    local h = selected and R().hitlist[selected]
    if h then
      local t = detail.note:GetText()
      h.note = (t and t ~= "") and t or nil
    end
    detail.note:ClearFocus()
  end
  detail.save = button(detail, 60, L.SAVE, saveNote)
  detail.save:SetPoint("LEFT", detail.note, "RIGHT", 8, 0)
  detail.note:SetScript("OnEnterPressed", saveNote)
  detail.note:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  detail.remove = button(detail, 70, L.REMOVE, function()
    if selected then R().hitlist[selected] = nil end
    selected = nil
    UI.Refresh()
  end)
  detail.remove:SetPoint("LEFT", detail.save, "RIGHT", 6, 0)
  detail.share = button(detail, 110, L.BTN_SHARE, function() UI.ShareHitlist() end)
  detail.share:SetPoint("BOTTOMRIGHT", 0, 0)
  detail.shareStatus = detail:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  detail.shareStatus:SetPoint("BOTTOMRIGHT", detail.share, "TOPRIGHT", 0, 4)

  -- settings
  settings = CreateFrame("Frame", nil, win)
  settings:SetPoint("TOPLEFT", 20, -76)
  settings:SetPoint("BOTTOMRIGHT", -20, 20)
  buildSettings(settings)
  settings:Hide()

  -- keep the share queue counter live while the window is open
  C_Timer.NewTicker(1, function()
    if win:IsShown() and currentTab == "hitlist" then ns.Try("share-status", refreshShareStatus) end
  end)
end

function UI.ShareHitlist()
  local n = 0
  for _ in pairs(ns.Comm.roster) do n = n + 1 end
  local prefix = "|cff33ff99" .. L.ADDON .. "|r "
  if n == 0 then
    print(prefix .. L.SHARE_NO_FRIENDS)
    return
  end
  local count = ns.Comm.ShareHitlist()
  print(prefix .. L.SHARE_STARTED:format(count, n))
  UI.Refresh()
end

-- pick/unpick a friend (by character name; the pick is stored by BattleTag)
function UI.TogglePick(name)
  local prefix = "|cff33ff99" .. L.ADDON .. "|r "
  local tag = ns.Comm.TagFor(name)
  if not tag then
    print(prefix .. L.PICK_NO_TAG:format(name))
    return
  end
  local on = ns.Comm.TogglePick(tag)
  print(prefix .. (on and L.PICK_ON or L.PICK_OFF):format(name, tag))
  if not ns.Comm.GroupActive() then print(prefix .. L.PICK_NOW_ALL) end
  UI.Refresh()
end

local function groupCommand(arg)
  local prefix = "|cff33ff99" .. L.ADDON .. "|r "
  if arg == "all" or arg == "clear" then
    ns.Comm.ClearPicks()
    print(prefix .. L.PICK_NOW_ALL)
  elseif arg ~= "" then
    ns.Comm.RebuildRoster()
    local name, tagOrWhy = ns.Comm.FindCandidate(arg)
    if not name then
      print(prefix .. (tagOrWhy == "ambiguous" and L.PICK_AMBIGUOUS or L.PICK_NOT_FOUND):format(arg))
      return
    end
    UI.TogglePick(name)
    return
  end
  ns.Comm.RebuildRoster()
  print(prefix .. (ns.Comm.GroupActive() and L.PICK_HINT_ACTIVE or L.PICK_HINT_ALL))
  local names = ns.Comm.EveryoneNames()
  if #names == 0 then print("  " .. L.SHARE_NO_FRIENDS) end
  for _, name in ipairs(names) do
    local tag = ns.Comm.TagFor(name)
    local mark = ns.Comm.Allowed(tag) and "|cff33ff33[x]|r " or "[ ] "
    print("  " .. mark .. name .. " (" .. tostring(tag or "?") .. ")")
  end
  print("  " .. L.PICK_USAGE)
end

function UI.Show(tab)
  if not win then build() end
  if tab then
    currentTab = tab
    offset = 0
  end
  win:Show()
  UI.Refresh()
end

function UI.Toggle()
  if win and win:IsShown() then win:Hide() else UI.Show() end
end

function UI.ShowPlayer(name)
  local r = R()
  if r.hitlist[name] then
    selected = name
    UI.Show("hitlist")
    for i, e in ipairs(data) do
      if e.name == name then
        offset = math.max(0, i - 1)
        break
      end
    end
    UI.Refresh()
  elseif r.players[name] and r.players[name].friend then
    UI.Show("friends")
  else
    UI.Show("enemies")
  end
end

---------------------------------------------------------------------------
-- slash
---------------------------------------------------------------------------
SLASH_FRIENDSANDFOES1 = "/fnf"
SlashCmdList.FRIENDSANDFOES = function(msg)
  msg = strtrim((msg or ""):lower())
  local prefix = "|cff33ff99" .. L.ADDON .. "|r "
  if msg == "" then
    UI.Toggle()
  elseif msg == "settings" or msg == "config" then
    UI.Show("settings")
  elseif msg == "unlock" then
    ns.Toast.SetUnlocked(true)
  elseif msg == "lock" then
    ns.Toast.SetUnlocked(false)
  elseif msg == "test" then
    ns.Toast.Test()
  elseif msg == "status" then
    ns.PrintStatus()
  elseif msg == "share" then
    UI.ShareHitlist()
  elseif msg == "debug" then
    ns.S().debug = not ns.S().debug
    print(prefix .. "debug: " .. (ns.S().debug and "on" or "off"))
  elseif msg == "debug clear" then
    wipe(FriendsAndFoesDB.debugLog)
    wipe(FriendsAndFoesDB.errorLog)
    print(prefix .. "debug + error logs cleared")
  elseif msg == "minimap" then
    ns.S().minimap.hide = not ns.S().minimap.hide
    if ns.Minimap then ns.Minimap.Update() end
  elseif msg == "group" or msg:find("^group ") then
    groupCommand(strtrim(msg:sub(6)))
  elseif msg == "sim" or msg:find("^sim ") then
    ns.Sim.Command(strtrim(msg:sub(4)))
  else
    print(prefix .. L.HELP)
  end
end
