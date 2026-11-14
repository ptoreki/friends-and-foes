local _, ns = ...
local L = ns.L

-- The main window: a plain, native-looking reference you open now and then.
-- Three tabs (Hitlist, Players, Feed); settings live in the game's Options panel.
local UI = {}
ns.UI = UI

local WIDTH, HEIGHT = 700, 470
local ROWS, ROW_H = 15, 20
local MAX_COLS = 7

local win, rowsFrame, header, rows, detail, pageText, emptyText, simBanner, friendsHint, filterBar, prevPage, nextPage
local tabButtons = {}
local currentTab = "hitlist"
local playerFilter = "enemies" -- Players tab: "enemies" | "friends"
local search = "" -- search box text (lowercase); filters the current list
local searchBox
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

-- who a hitlist player killed, most first, with counts: "Bob 3x, Alice 1x"
local function victimsText(h)
  local list = {}
  for _, v in ipairs(ns.Data.KillsOn(h)) do
    local name = ns.ClassColored(v[1])
    list[#list + 1] = v[2] and L.KILLS_ON_COUNT:format(name, v[2]) or name
  end
  return table.concat(list, ", ")
end

local function lastText(e)
  return ns.Ago(e.lastSeen) .. (e.lastZone and (" - " .. e.lastZone) or "")
end

-- a level seen long ago is probably higher now: "24+" in grey
local function lvl(e)
  local n = ns.Count(e.level)
  if n <= 0 then return "?" end
  if not e.pending and not e.friend and ns.Data.LevelIsOld(e) then return "|cff888888" .. n .. "+|r" end
  return tostring(n)
end
local C = ns.Count
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
  local s = tostring(C(e.kills))
  if C(e.suspect) > 0 then s = s .. "*" end
  if C(e.revenge) > 0 then s = s .. "  |cff33ff33" .. L.REVENGE_SHORT:format(C(e.revenge)) .. "|r" end
  return s
end

---------------------------------------------------------------------------
-- tabs
---------------------------------------------------------------------------
-- column: { header, width, cell text, sort key (click the header to sort) }
local function byName(e) return (e.name or ""):lower() end
local function byLevel(e) return tonumber(e.level) or 0 end
local function byGuild(e) return (e.guild or ""):lower() end
local function byLast(e) return e.lastSeen or 0 end
local function count(t) local n = 0; for _ in pairs(t or {}) do n = n + 1 end; return n end

local HITLIST_COLS = {
  { L.COL_NAME, 165, nameCol, byName },
  { L.COL_LEVEL, 30, lvl, byLevel },
  { L.COL_GUILD, 95, guild, byGuild },
  { L.COL_KILLS, 70, hitKills, function(e) return e.kills or 0 end },
  { L.COL_VICTIMS, 155, function(e) return victimsText(e) end, function(e) return count(e.victims) end },
  { L.COL_LAST, 145, lastText, byLast },
}

local ENEMY_COLS = {
  { L.COL_NAME, 170, nameCol, byName },
  { L.COL_LEVEL, 30, lvl, byLevel },
  { L.COL_GUILD, 110, guild, byGuild },
  { L.COL_KILLS_ON_US, 75, function(e) return C(e.k) end, function(e) return C(e.k) end },
  { L.COL_DEATHS_TO_US, 70, function(e) return C(e.d) end, function(e) return C(e.d) end },
  { L.COL_ASSISTS, 55, function(e) return C(e.a) end, function(e) return C(e.a) end },
  { L.COL_LAST, 150, lastText, byLast },
}

local FRIEND_COLS = {
  { L.COL_NAME, 165, nameCol, byName },
  { L.COL_LEVEL, 30, lvl, byLevel },
  { L.COL_VERSION, 50, function(e)
    if not e.version then return "" end
    if ns.VersionNewer(e.version, ns.VERSION) then return "|cffffd100" .. e.version .. "|r" end
    return e.version
  end, function(e) return e.version or "" end },
  { L.COL_TAKEDOWNS, 70, function(e) return e.pending and "" or C(e.k) end, function(e) return e.pending and -1 or C(e.k) end },
  { L.COL_DEATHS, 55, function(e) return e.pending and "" or C(e.d) end, function(e) return e.pending and -1 or C(e.d) end },
  { L.COL_ALERTS, 50, function(e)
    local tag = ns.Comm.TagFor(e.name)
    if ns.Comm.IsPicked(tag) then return "|cff33ff33" .. L.ALERTS_ON .. "|r" end
    if ns.Comm.GroupActive() then return "|cff888888" .. L.ALERTS_OFF .. "|r" end
    return "|cff888888" .. L.ALERTS_ALL .. "|r"
  end, function(e) return ns.Comm.IsPicked(ns.Comm.TagFor(e.name)) and 1 or 0 end },
  { L.COL_LAST_EVENT, 240, function(e)
    -- "online · Ashenvale": the zone comes from Battle.net
    local function onlineText(zone)
      return "|cff33ff33" .. L.FRIEND_ONLINE .. (zone and (" \194\183 " .. zone) or "") .. "|r  "
    end
    if e.pending then return onlineText(e.zone) .. "|cff888888" .. L.FRIEND_NOT_HEARD .. "|r" end
    local online = onlineNow[e.name] and onlineText(type(onlineNow[e.name]) == "string" and onlineNow[e.name] or nil) or ""
    return online .. (e.lastText or "") .. "  |cff888888" .. ns.Ago(e.lastSeen) .. "|r"
  end, function(e) return e.pending and math.huge or (e.lastSeen or 0) end },
}

-- friends we've heard from, plus online Battle.net friends in Forever the addon can see
-- but hasn't received anything from yet (so you can tell "not detected" from "silent")
local function fetchFriends()
  -- you are not your own friend; friends on the other faction aren't shown
  -- friends you haven't heard from in 6 months leave the list (unless they're online now)
  -- one pass over who's online: known friends get "online", the rest a placeholder row
  wipe(onlineNow)
  local onlineRows = {}
  if not ns.viewSim then
    for _, name in ipairs(ns.Comm.EveryoneNames()) do
      local rec = R().players[ns.Data.Resolve(R().players, name)]
      if rec and rec.friend then
        onlineNow[rec.name] = ns.Comm.ZoneOf(name) or true
      else
        onlineRows[#onlineRows + 1] = { name = name, pending = true, zone = ns.Comm.ZoneOf(name) }
      end
    end
  end
  local list = sortedValues(R().players, function(p)
    return p.friend and not p.self and p.name ~= ns.me
      and not (p.faction and ns.myFaction and p.faction ~= ns.myFaction)
      and (onlineNow[p.name] or ns.viewSim or not ns.Data.FriendIsGone(p))
  end)
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

-- sorting: per view, by column; newest first by default
local sortState = {}
local function viewKey() return currentTab == "players" and ("players_" .. playerFilter) or currentTab end
local function sortOf(cols)
  local st = sortState[viewKey()]
  if not st then
    st = { col = #cols, desc = true } -- last column (last seen / time) newest first
    sortState[viewKey()] = st
  end
  return st
end

local function applySort(list, cols)
  local st = sortOf(cols)
  local key = cols[st.col] and cols[st.col][4]
  if not key then return end
  -- faded hitlist entries (not seen for 90 days) always go last; decided once, before sorting
  local stale
  if currentTab == "hitlist" then
    stale = {}
    for _, e in ipairs(list) do stale[e] = ns.Data.IsStale(e) end
  end
  table.sort(list, function(a, b)
    if stale and stale[a] ~= stale[b] then return stale[b] end
    local ka, kb = key(a), key(b)
    if ka == kb then return (a.name or "") < (b.name or "") end
    if type(ka) ~= type(kb) then ka, kb = tostring(ka), tostring(kb) end
    if st.desc then return ka > kb end
    return ka < kb
  end)
end

-- click a column header: sort by it; click again to flip the order
function UI.SetSearch(text)
  search = strtrim(text or ""):lower()
  offset = 0
  UI.Refresh()
end

-- tooltip for a hitlist row: record, who they killed (with counts), last seen, note
function UI.HitTooltip(owner, h)
  GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")
  GameTooltip:AddLine(ns.ClassColored(h.name, h.class) .. (h.guild and ("  |cff888888<" .. h.guild .. ">|r") or ""))
  GameTooltip:AddLine(L.HIT_TIP_RECORD:format(ns.Count(h.kills)), 1, 1, 1)
  local kills = ns.Data.KillsOn(h)
  if #kills > 0 then
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine(L.HIT_TIP_KILLED, 1, 0.82, 0)
    for _, v in ipairs(kills) do
      local right = v[2] and L.HIT_TIP_TIMES:format(v[2]) or L.HIT_TIP_EARLIER
      GameTooltip:AddDoubleLine(ns.ClassColored(v[1]), right, 1, 1, 1, 1, 1, 1)
    end
  end
  GameTooltip:AddLine(" ")
  GameTooltip:AddLine(L.HIT_TIP_LAST:format(lastText(h)), 0.7, 0.7, 0.7)
  if h.note then GameTooltip:AddLine(h.note, 1, 1, 1, true) end
  GameTooltip:Show()
end

-- the rows currently listed (sorted), for tests
function UI.Rows() return data end

function UI.SortBy(col)
  local st = sortState[viewKey()] or {}
  if st.col == col then
    st.desc = not st.desc
  else
    st.col, st.desc = col, (col ~= 1) -- names A-Z first, numbers highest first
  end
  sortState[viewKey()] = st
  offset = 0
  UI.Refresh()
end

---------------------------------------------------------------------------
-- list rendering
---------------------------------------------------------------------------
local function layoutColumns(cols)
  local x = 0
  local st = sortOf(cols)
  for c = 1, MAX_COLS do
    local col = cols[c]
    local h = header.buttons[c]
    if col then
      h:ClearAllPoints()
      h:SetPoint("LEFT", header, "LEFT", x, 0)
      h:SetSize(col[2] - 2, ROW_H)
      h.text:SetText(col[1])
      h:EnableMouse(col[4] ~= nil)
      local sorted = col[4] ~= nil and st.col == c
      if sorted then h.text:SetTextColor(1, 1, 1) else h.text:SetTextColor(1, 0.82, 0) end
      h.arrow:SetShown(sorted)
      if sorted then
        if st.desc then h.arrow:SetTexCoord(0, 0.5625, 0, 1) else h.arrow:SetTexCoord(0, 0.5625, 1, 0) end
      end
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
  if detail.clear then detail.clear:SetEnabled(next(R().hitlist) ~= nil) end
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
  filterBar.dropdown.refresh()

  local cols = colsOf(def)
  data = def.fetch()
  -- search box: keep rows whose name or guild (or Feed text) contains the search
  if search ~= "" then
    local kept = {}
    for _, e in ipairs(data) do
      local hay = ((e.name or "") .. " " .. (e.guild or "") .. " " .. ns.Plain(e.text or "")):lower()
      if hay:find(search, 1, true) then kept[#kept + 1] = e end
    end
    data = kept
  end
  applySort(data, cols)
  local maxOffset = math.max(0, #data - ROWS)
  if offset > maxOffset then offset = maxOffset end
  layoutColumns(cols)

  for i, row in ipairs(rows) do
    local e = data[offset + i]
    row.entry = e
    if e then
      local faded = currentTab == "hitlist" and ns.Data.IsStale(e) -- not seen for 90 days: grey
      for c, col in ipairs(cols) do
        local ok, val = pcall(col[3], e)
        local text = ok and tostring(val) or "?"
        if faded then text = "|cff777777" .. ns.Plain(text) .. "|r" end
        row.cells[c]:SetText(text)
      end
      row.sel:SetShown(currentTab == "hitlist" and e.name ~= nil and e.name == selected)
      row:Show()
    else
      row:Hide()
    end
  end
  emptyText:SetShown(#data == 0)
  emptyText:SetText(search ~= "" and L.SEARCH_NONE or L.EMPTY)
  local paged = #data > ROWS
  if paged then
    pageText:SetText(string.format("%d-%d of %d", offset + 1, math.min(offset + ROWS, #data), #data))
  else
    pageText:SetText(#data > 0 and tostring(#data) or "")
  end
  prevPage:SetShown(paged)
  nextPage:SetShown(paged)
  prevPage:SetEnabled(offset > 0)
  nextPage:SetEnabled(offset + ROWS < #data)
  refreshDetail()
  friendsHint:SetShown(currentTab == "players")
  if friendsView() and not ns.viewSim then
    friendsHint:SetText((ns.Comm.GroupActive() and L.PICK_HINT_ACTIVE or L.PICK_HINT_ALL) .. "  " .. L.REMOVE_HINT)
  else
    friendsHint:SetText(L.REMOVE_HINT)
  end
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

-- Yes/No confirmation (the game's standard pop-up) before anything is deleted.
local CONFIRM = "FRIENDSANDFOES_CONFIRM"
function UI.Confirm(text, onYes, onNo)
  if not (StaticPopupDialogs and StaticPopup_Show) then -- no way to ask: do nothing
    if onNo then ns.Try("confirm-no", onNo) end
    return
  end
  StaticPopupDialogs[CONFIRM] = StaticPopupDialogs[CONFIRM] or {
    text = "%s", button1 = YES or "Yes", button2 = NO or "No",
    OnAccept = function(self, data)
      local d = data or (self and self.data)
      if d and d.fn then ns.Try("confirm", d.fn) end
    end,
    OnCancel = function(self, data)
      local d = data or (self and self.data)
      if d and d.no then ns.Try("confirm-no", d.no) end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
  }
  StaticPopup_Show(CONFIRM, text, nil, { fn = onYes, no = onNo })
end

local function afterRemove()
  if ns.Marks then ns.Marks.Refresh() end
  UI.Refresh()
end

function UI.RemoveFromHitlist(name)
  if not (name and R().hitlist[name]) then return end
  UI.Confirm(L.CONFIRM_REMOVE_HIT:format(name), function()
    R().hitlist[name] = nil
    if selected == name then selected = nil end
    afterRemove()
  end)
end

function UI.RemovePlayer(name)
  if not (name and R().players[name]) then return end
  UI.Confirm(L.CONFIRM_REMOVE_PLAYER:format(name), function()
    R().players[name] = nil
    afterRemove()
  end)
end

function UI.ClearHitlist()
  local n = 0
  for _ in pairs(R().hitlist) do n = n + 1 end
  if n == 0 then return end
  UI.Confirm(L.CONFIRM_CLEAR_HITLIST:format(n), function()
    wipe(R().hitlist)
    selected = nil
    afterRemove()
  end)
end

-- A dropdown: the game's modern dropdown when available, else a  < value >  stepper.
-- items = { { value, label }, ... }
function UI.Dropdown(parent, width, items, get, set)
  local ok, dd = pcall(CreateFrame, "DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
  if ok and dd and dd.SetupMenu then
    dd:SetWidth(width)
    dd:SetupMenu(function(_, root)
      for _, it in ipairs(items) do
        root:CreateRadio(it[2], function() return get() == it[1] end, function() set(it[1]) end, it[1])
      end
    end)
    dd.refresh = function() if dd.GenerateMenu then dd:GenerateMenu() end end
    return dd
  end
  local f = CreateFrame("Frame", nil, parent)
  f:SetSize(width, 24)
  local label = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  label:SetPoint("CENTER")
  local function step(d)
    local idx = 1
    for i, it in ipairs(items) do if it[1] == get() then idx = i end end
    set(items[(idx - 1 + d) % #items + 1][1])
  end
  for _, d in ipairs({ -1, 1 }) do
    local b = CreateFrame("Button", nil, f)
    b:SetSize(22, 22)
    local name = d < 0 and "Prev" or "Next"
    b:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. name .. "Page-Up")
    b:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. name .. "Page-Down")
    b:SetPoint(d < 0 and "LEFT" or "RIGHT")
    b:SetScript("OnClick", function() step(d) end)
  end
  f.refresh = function()
    for _, it in ipairs(items) do if it[1] == get() then label:SetText(it[2]) end end
  end
  return f
end
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
  -- equal widths (at least 90), with a small gap between tabs like the game's own windows
  if isPanelTab then pcall(PanelTemplates_TabResize, b, 0, nil, 90) end
  b:SetScript("OnClick", function() UI.SelectTab(key) end)
  if prev then
    b:SetPoint("LEFT", prev, "RIGHT", 3, 0)
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

  -- search: filters the current list by name / guild (Feed: by text)
  local okBox, box = pcall(CreateFrame, "EditBox", "FriendsAndFoesSearchBox", win, "SearchBoxTemplate")
  if not (okBox and box) then box = CreateFrame("EditBox", "FriendsAndFoesSearchBox", win, "InputBoxTemplate") end
  box:SetSize(150, 20)
  box:SetPoint("RIGHT", options, "LEFT", -12, 0)
  box:SetAutoFocus(false)
  local placeholder = box:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  placeholder:SetPoint("LEFT", 18, 0)
  placeholder:SetText(L.SEARCH)
  box:HookScript("OnTextChanged", function(self)
    local text = self:GetText() or ""
    placeholder:SetShown(text == "" and not (self.Instructions and self.Instructions:IsShown()))
    UI.SetSearch(text)
  end)
  box:SetScript("OnEscapePressed", function(self)
    self:SetText("")
    self:ClearFocus()
  end)
  box:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
  searchBox = box

  filterBar = CreateFrame("Frame", nil, win)
  filterBar:SetSize(220, 24)
  filterBar:SetPoint("TOPLEFT", 16, -30)
  local showLabel = filterBar:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  showLabel:SetPoint("LEFT")
  showLabel:SetText(L.FILTER_SHOW)
  filterBar.dropdown = UI.Dropdown(filterBar, 140,
    { { "enemies", L.FILTER_ENEMIES }, { "friends", L.FILTER_FRIENDS } },
    function() return playerFilter end, function(v) UI.SetPlayerFilter(v) end)
  filterBar.dropdown:SetPoint("LEFT", showLabel, "RIGHT", 8, 0)

  -- simulation banner
  simBanner = CreateFrame("Frame", nil, win)
  simBanner:SetSize(260, 22)
  simBanner:SetPoint("BOTTOMLEFT", 16, 2)
  local simText = simBanner:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  simText:SetPoint("LEFT")
  simText:SetText("|cffff9933" .. L.SIM_BANNER .. "|r")
  local simExit = button(simBanner, 110, L.SIM_EXIT, function() ns.Sim.Stop() end)
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
  header.cells, header.buttons = {}, {}
  for c = 1, MAX_COLS do
    -- click a column header to sort by it; again to flip the order
    local b = CreateFrame("Button", nil, header)
    b:SetHeight(ROW_H)
    local hl = b:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetColorTexture(1, 1, 1, 0.06)
    b.text = b:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    b.text:SetPoint("LEFT", 4, 0)
    b.text:SetJustifyH("LEFT")
    b.text:SetWordWrap(false)
    b.arrow = b:CreateTexture(nil, "OVERLAY")
    b.arrow:SetTexture("Interface\\Buttons\\UI-SortArrow")
    b.arrow:SetSize(9, 8)
    b.arrow:SetPoint("LEFT", b.text, "RIGHT", 3, -1)
    b.arrow:Hide()
    b:SetScript("OnClick", function() UI.SortBy(c) end)
    header.buttons[c] = b
    header.cells[c] = b.text
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
      -- hitlist: who this player killed in your group, and how often
      if currentTab == "hitlist" and self.entry and self.entry.name then
        UI.HitTooltip(self, self.entry)
        return
      end
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
    row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
    row:SetScript("OnClick", function(self, mouse)
      local e = self.entry
      if mouse == "RightButton" then
        if e and not e.pending and currentTab == "hitlist" then
          UI.RemoveFromHitlist(e.name)
        elseif e and not e.pending and currentTab == "players" then
          UI.RemovePlayer(e.name)
        end
        return
      end
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

  -- paging: < 1-15 of 40 >  (the mouse wheel scrolls too)
  local function pageButton(dir)
    local b = CreateFrame("Button", nil, win)
    b:SetSize(24, 24)
    local name = dir < 0 and "Prev" or "Next"
    b:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. name .. "Page-Up")
    b:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. name .. "Page-Down")
    b:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. name .. "Page-Disabled")
    b:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
    b:SetScript("OnClick", function()
      offset = math.max(0, math.min(offset + dir * ROWS, math.max(0, #data - ROWS)))
      UI.Refresh()
    end)
    b:Hide()
    return b
  end
  nextPage = pageButton(1)
  nextPage:SetPoint("BOTTOMRIGHT", -12, 4)
  pageText = win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  pageText:SetPoint("RIGHT", nextPage, "LEFT", -2, 0)
  prevPage = pageButton(-1)
  prevPage:SetPoint("RIGHT", pageText, "LEFT", -2, 0)

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
  detail.remove = button(detail, 70, L.REMOVE, function() UI.RemoveFromHitlist(selected) end)
  detail.remove:SetPoint("LEFT", detail.save, "RIGHT", 6, 0)
  detail.share = button(detail, 110, L.BTN_SHARE, function() UI.ShareHitlist() end)
  detail.share:SetPoint("BOTTOMRIGHT", 0, 0)
  detail.clear = button(detail, 100, L.BTN_CLEAR_HITLIST, function() UI.ClearHitlist() end)
  detail.clear:SetPoint("RIGHT", detail.share, "LEFT", -6, 0)
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
-- first time on this account: a short hello in chat
ns.OnReady(function()
  if FriendsAndFoesDB.welcomed then return end
  FriendsAndFoesDB.welcomed = true
  C_Timer.After(6, function()
    local prefix = "|cff33ff99" .. L.ADDON .. "|r "
    print(prefix .. L.WELCOME_1)
    print(prefix .. L.WELCOME_2)
  end)
end)

-- once a week at login: your PvP week in one line
ns.OnReady(function()
  local db = FriendsAndFoesDB
  local now = time()
  local w = db.weekly
  if not w then
    db.weekly = { start = now, k = 0, d = 0, killers = {} }
    return
  end
  if now - (w.start or now) < 7 * 86400 then return end
  db.weekly = { start = now, k = 0, d = 0, killers = {} }
  if ns.S().weekly == false or ((w.k or 0) + (w.d or 0)) == 0 then return end
  local line = L.WEEKLY:format(ns.Count(w.k), ns.Count(w.d))
  local nemesis, most = nil, 0
  for name, n in pairs(w.killers or {}) do
    if n > most then nemesis, most = name, n end
  end
  if nemesis and most >= 2 then line = line .. " " .. L.WEEKLY_NEMESIS:format(nemesis, most) end
  C_Timer.After(8, function() ns.Toast.Chat(line) end)
end)

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
  elseif msg:find("^size") then
    local n = tonumber(msg:match("%d+"))
    if n and n >= 70 and n <= 150 then
      ns.S().toastScale = n / 100
      ns.Toast.ApplyScale()
      ns.Toast.Test()
    else
      print(prefix .. L.SIZE_USAGE:format(math.floor((tonumber(ns.S().toastScale) or 1) * 100 + 0.5)))
    end
  elseif msg:find("^duration") then
    local n = tonumber(msg:match("%d+"))
    if n and n >= 2 and n <= 10 then
      ns.S().toastDuration = n
      print(prefix .. L.DURATION_SET:format(n))
    else
      print(prefix .. L.DURATION_USAGE:format(tonumber(ns.S().toastDuration) or 3))
    end
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
