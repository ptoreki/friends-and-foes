local _, ns = ...
local L = ns.L

-- The main window: a plain, native-looking reference you open now and then.
-- Three tabs (Hitlist, Players, Feed); settings live in the game's Options panel.
local UI = {}
ns.UI = UI

local WIDTH, HEIGHT = 700, 470
local ROWS, ROW_H = 15, 20
local MAX_COLS = 7

local win, rowsFrame, header, rows, detail, pageText, emptyText, simBanner, friendsHint, filterBar
local tabButtons = {}
local currentTab = "hitlist"
local playerFilter = "enemies" -- Players tab: "enemies" | "friends"
local offset = 0
local data = {}
local selected

local function R() return ns.Data.ViewRealm() end
local onlineNow = {} -- friend record name -> true while they are in the roster (not saved)

---------------------------------------------------------------------------
-- cell helpers
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

-- small class icon, inline (|T path:h:w:x:y:texW:texH:l:r:t:b|t)
local CLASS_ICONS = "Interface\\TargetingFrame\\UI-Classes-Circles"
local function classIcon(class)
  local c = class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[class]
  if not c then return "" end
  local f = math.floor
  return ("|T%s:14:14:0:0:256:256:%d:%d:%d:%d|t "):format(CLASS_ICONS, f(c[1] * 256), f(c[2] * 256), f(c[3] * 256), f(c[4] * 256))
end
local function nameCol(e) return classIcon(e.class) .. ns.ClassColored(e.name, e.class) end

local function hitKills(e)
  local s = tostring(e.kills or 0)
  if (e.suspect or 0) > 0 then s = s .. "*" end
  if (e.revenge or 0) > 0 then s = s .. "  |cff33ff33" .. L.REVENGE_SHORT:format(e.revenge) .. "|r" end
  return s
end

---------------------------------------------------------------------------
-- tabs
---------------------------------------------------------------------------
local HITLIST_COLS = {
  { L.COL_NAME, 165, nameCol },
  { L.COL_LEVEL, 30, lvl },
  { L.COL_GUILD, 95, guild },
  { L.COL_ATTACKS, 50, function(e) return e.attacks or 0 end },
  { L.COL_KILLS, 70, hitKills },
  { L.COL_VICTIMS, 105, function(e) return victimsText(e.victims) end },
  { L.COL_LAST, 145, lastText },
}

local ENEMY_COLS = {
  { L.COL_NAME, 170, nameCol },
  { L.COL_LEVEL, 30, lvl },
  { L.COL_GUILD, 110, guild },
  { L.COL_KILLS_ON_US, 75, function(e) return e.k end },
  { L.COL_DEATHS_TO_US, 70, function(e) return e.d end },
  { L.COL_ASSISTS, 55, function(e) return e.a end },
  { L.COL_LAST, 150, lastText },
}

local FRIEND_COLS = {
  { L.COL_NAME, 165, nameCol },
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
  { L.COL_LAST_EVENT, 240, function(e)
    if e.pending then return "|cff33ff33" .. L.FRIEND_ONLINE .. "|r  |cff888888" .. L.FRIEND_NOT_HEARD .. "|r" end
    local online = onlineNow[e.name] and ("|cff33ff33" .. L.FRIEND_ONLINE .. "|r  ") or ""
    return online .. (e.lastText or "") .. "  |cff888888" .. ns.Ago(e.lastSeen) .. "|r"
  end },
}

-- friends we've heard from, plus online Battle.net friends in Forever the addon can see
-- but hasn't received anything from yet (so you can tell "not detected" from "silent")
local function fetchFriends()
  local list = sortedValues(R().players, function(p) return p.friend end)
  if ns.viewSim then return list end
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
  for _, row in ipairs(onlineRows) do table.insert(list, 1, row) end
  return list
end

local TABS = {
  { key = "hitlist", label = L.TAB_HITLIST, columns = HITLIST_COLS,
    fetch = function() return sortedValues(R().hitlist) end },
  { key = "players", label = L.TAB_PLAYERS,
    columns = function() return playerFilter == "friends" and FRIEND_COLS or ENEMY_COLS end,
    fetch = function()
      if playerFilter == "friends" then return fetchFriends() end
      return sortedValues(R().players, function(p) return p.enemy end)
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
}

local function tabDef(key)
  for _, t in ipairs(TABS) do if t.key == key then return t end end
  return TABS[1]
end

local function colsOf(def)
  if type(def.columns) == "function" then return def.columns() end
  return def.columns
end

local function friendsView() return currentTab == "players" and playerFilter == "friends" end

---------------------------------------------------------------------------
-- list rendering
---------------------------------------------------------------------------
local function layoutColumns(cols)
  local x = 0
  for c = 1, MAX_COLS do
    local col = cols[c]
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

local function selectTabButton(b, on)
  if PanelTemplates_SelectTab and b.isPanelTab then
    pcall(on and PanelTemplates_SelectTab or PanelTemplates_DeselectTab, b)
  elseif on then
    b:LockHighlight()
  else
    b:UnlockHighlight()
  end
end

function UI.Refresh()
  if not win or not win:IsShown() then return end
  local def = tabDef(currentTab)
  currentTab = def.key
  for _, b in ipairs(tabButtons) do selectTabButton(b, b.key == currentTab) end
  simBanner:SetShown(ns.viewSim and true or false)
  filterBar:SetShown(currentTab == "players")
  filterBar.enemies:SetEnabled(playerFilter ~= "enemies")
  filterBar.friends:SetEnabled(playerFilter ~= "friends")

  local cols = colsOf(def)
  data = def.fetch()
  local maxOffset = math.max(0, #data - ROWS)
  if offset > maxOffset then offset = maxOffset end
  layoutColumns(cols)

  for i, row in ipairs(rows) do
    local e = data[offset + i]
    row.entry = e
    if e then
      for c, col in ipairs(cols) do
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
  friendsHint:SetShown(friendsView() and not ns.viewSim)
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
  currentTab = tabDef(key).key
  offset = 0
  UI.Refresh()
end

function UI.SetPlayerFilter(which)
  playerFilter = which == "friends" and "friends" or "enemies"
  offset = 0
  UI.Refresh()
end

function UI.OpenSettings() ns.Options.Open() end
UI.RefreshSettings = function() if ns.Options then ns.Options.Refresh() end end

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

local FALLBACK_BACKDROP = {
  bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
  edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
  tile = true, tileSize = 32, edgeSize = 32,
  insets = { left = 11, right = 12, top = 12, bottom = 11 },
}

-- Blizzard's plain window frame if available, else a dialog box
local function createWindow()
  local ok, f = pcall(CreateFrame, "Frame", "FriendsAndFoesFrame", UIParent, "BasicFrameTemplateWithInset")
  local templated = ok and f and type(f.TitleBg) == "table"
  if not templated then
    if not (ok and f) then f = CreateFrame("Frame", "FriendsAndFoesFrame", UIParent, "BackdropTemplate") end
    if f.SetBackdrop then f:SetBackdrop(FALLBACK_BACKDROP) end
    local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
    close:SetPoint("TOPRIGHT", -4, -4)
  end
  local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  if templated then title:SetPoint("CENTER", f.TitleBg, "CENTER", 0, 0) else title:SetPoint("TOP", 0, -14) end
  title:SetText(L.ADDON)
  return f
end

-- tabs hang below the window, like the Character or Social window
local function createTab(parent, key, label, prev, index)
  local ok, b = pcall(CreateFrame, "Button", "FriendsAndFoesFrameTab" .. index, parent, "PanelTabButtonTemplate")
  local isPanelTab = ok and b and PanelTemplates_TabResize ~= nil
  if not isPanelTab then
    b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    b:SetSize(90, 22)
  end
  b:SetText(label)
  b.isPanelTab = isPanelTab
  if isPanelTab then pcall(PanelTemplates_TabResize, b, 0) end
  b:SetScript("OnClick", function() UI.SelectTab(key) end)
  if prev then
    b:SetPoint("LEFT", prev, "RIGHT", isPanelTab and -14 or 4, 0)
  else
    b:SetPoint("TOPLEFT", parent, "BOTTOMLEFT", 12, isPanelTab and 2 or -2)
  end
  b.key = key
  return b
end

local function build()
  win = createWindow()
  win:SetSize(WIDTH, HEIGHT)
  win:SetPoint("CENTER")
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

  -- top row: Players filter (left), Options (right)
  local options = button(win, 80, L.BTN_OPTIONS, function() UI.OpenSettings() end)
  options:SetPoint("TOPRIGHT", -14, -30)

  filterBar = CreateFrame("Frame", nil, win)
  filterBar:SetSize(200, 22)
  filterBar:SetPoint("TOPLEFT", 14, -30)
  filterBar.enemies = button(filterBar, 80, L.FILTER_ENEMIES, function() UI.SetPlayerFilter("enemies") end)
  filterBar.enemies:SetPoint("LEFT")
  filterBar.friends = button(filterBar, 80, L.FILTER_FRIENDS, function() UI.SetPlayerFilter("friends") end)
  filterBar.friends:SetPoint("LEFT", filterBar.enemies, "RIGHT", 4, 0)

  -- simulation banner
  simBanner = CreateFrame("Frame", nil, win)
  simBanner:SetSize(260, 22)
  simBanner:SetPoint("TOP", 0, -30)
  local simText = simBanner:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  simText:SetPoint("LEFT")
  simText:SetText("|cffff9933" .. L.SIM_BANNER .. "|r")
  local simExit = button(simBanner, 80, L.SIM_EXIT, function()
    ns.viewSim = false
    UI.Refresh()
  end)
  simExit:SetPoint("LEFT", simText, "RIGHT", 6, 0)
  simBanner:Hide()

  local prev
  for i, t in ipairs(TABS) do
    prev = createTab(win, t.key, t.label, prev, i)
    tabButtons[#tabButtons + 1] = prev
  end

  -- list area
  rowsFrame = CreateFrame("Frame", nil, win)
  rowsFrame:SetPoint("TOPLEFT", 14, -58)
  rowsFrame:SetPoint("BOTTOMRIGHT", -14, 76)
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
    -- cells are cut to their column; hovering a row shows any cut-off text in full
    row:SetScript("OnEnter", function(self)
      local cut = {}
      for c, cell in ipairs(self.cells) do
        if cell:IsShown() and cell.IsTruncated and cell:IsTruncated() then
          cut[#cut + 1] = { header.cells[c]:GetText(), cell:GetText() }
        end
      end
      if #cut == 0 then return end
      GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
      for _, pair in ipairs(cut) do
        if #cut == 1 then
          GameTooltip:AddLine(pair[2], 1, 1, 1, true)
        else
          GameTooltip:AddDoubleLine(pair[1] or "", pair[2], 1, 0.82, 0, 1, 1, 1)
        end
      end
      GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() GameTooltip:Hide() end)
    row:SetScript("OnClick", function(self)
      if currentTab == "hitlist" and self.entry then
        selected = self.entry.name
        UI.Refresh()
      elseif friendsView() and self.entry and not ns.viewSim then
        UI.TogglePick(self.entry.name)
      end
    end)
    rows[i] = row
  end

  emptyText = rowsFrame:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  emptyText:SetPoint("CENTER")
  emptyText:SetText(L.EMPTY)

  pageText = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  pageText:SetPoint("BOTTOMRIGHT", -18, 10)

  friendsHint = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  friendsHint:SetPoint("BOTTOMLEFT", 18, 40)
  friendsHint:SetPoint("BOTTOMRIGHT", -18, 40)
  friendsHint:SetJustifyH("LEFT")

  -- hitlist detail (note / remove / share)
  detail = CreateFrame("Frame", nil, win)
  detail:SetPoint("BOTTOMLEFT", 16, 24)
  detail:SetPoint("BOTTOMRIGHT", -16, 24)
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
    if ns.Marks then ns.Marks.Refresh() end
    selected = nil
    UI.Refresh()
  end)
  detail.remove:SetPoint("LEFT", detail.save, "RIGHT", 6, 0)
  detail.share = button(detail, 110, L.BTN_SHARE, function() UI.ShareHitlist() end)
  detail.share:SetPoint("BOTTOMRIGHT", 0, 0)
  detail.shareStatus = detail:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  detail.shareStatus:SetPoint("BOTTOMRIGHT", detail.share, "TOPRIGHT", 0, 4)

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

-- tab: "hitlist" | "players" | "feed"; the old names "enemies"/"friends" pick the Players filter
function UI.Show(tab)
  if not win then build() end
  if tab == "enemies" or tab == "friends" then
    playerFilter = tab
    tab = "players"
  elseif tab == "settings" then
    UI.OpenSettings()
    return
  end
  if tab then
    currentTab = tabDef(tab).key
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
  elseif msg == "settings" or msg == "config" or msg == "options" then
    UI.OpenSettings()
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
    ns.SetDebug(not ns.S().debug)
    print(prefix .. "debug: " .. (ns.S().debug and "on" or "off"))
    UI.RefreshSettings()
  elseif msg == "debug clear" then
    wipe(FriendsAndFoesDB.debugLog)
    wipe(FriendsAndFoesDB.errorLog)
    print(prefix .. "debug + error logs cleared")
  elseif msg == "minimap" then
    ns.S().minimap.hide = not ns.S().minimap.hide
    if ns.Minimap then ns.Minimap.Update() end
  elseif msg == "chat" or msg:find("^chat ") then
    local n = tonumber(strtrim(msg:sub(5)))
    if n and n >= 1 and n <= 10 and math.floor(n) == n then
      ns.S().chatFrame = n
      print(prefix .. L.CHAT_TAB_SET:format(n))
      ns.Toast.Chat(L.CHAT_TAB_SET:format(n))
    else
      print(prefix .. L.CHAT_TAB_USAGE:format(ns.S().chatFrame or 1))
    end
  elseif msg == "group" or msg:find("^group ") then
    groupCommand(strtrim(msg:sub(6)))
  elseif msg == "sim" or msg:find("^sim ") then
    ns.Sim.Command(strtrim(msg:sub(4)))
  else
    print(prefix .. L.HELP)
  end
end
