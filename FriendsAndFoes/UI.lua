local _, ns = ...
local L = ns.L

-- The main window: a plain, native-looking reference you open now and then.
-- Tabs: Hitlist, Bounty board, Friends (with the ranking), Feed, Profile; settings live in the game's Options panel.
local UI = ns.UI -- (made in UIWidgets.lua, with the shared building blocks)
ns.UI = UI
local button, createWindow, createTab = UI.Button, UI.CreateWindow, UI.CreateTab

local WIDTH, HEIGHT = 700, 470
local ROWS, ROW_H = 15, 20
local MAX_COLS = 9

local win, rowsFrame, header, rows, detail, pageText, emptyText, friendsHint, prevPage, nextPage
local contractBar -- the Bounty board's bottom row
local groupBar -- Friends tab: board picker + group buttons
local pageRow -- bottom right: [<] 1-15 of 40 [>] (arrows only when there's more than a page)
-- Back (Profile page and Kill list): the places you came through, newest last
-- ({ tab, offset, boardView, profileName, killsOf })
local backButton
local history = {}
local HISTORY_MAX = 10
local profile -- the Profile tab's panel
local profileName -- whose profile it shows
local tabButtons = {}
local currentTab = "hitlist"
-- the tab button that's lit: the tab you picked. Someone's profile or kill list opens inside it
-- (with Back), so it stays lit; the Profile tab itself is always your own profile.
local homeTab = "hitlist"
local search = "" -- search box text (lowercase); filters the current list
local searchBox
local offset = 0
local data = {}
local selected

local function R() return ns.Data.ViewRealm() end

---------------------------------------------------------------------------
-- cell helpers
---------------------------------------------------------------------------
-- a friend (or you) is never shown as an enemy, even if old data marked them as one
local function isFriendRecord(name) -- on your side (a friend on the other faction is not)
  -- (exact names: an enemy known by a first name a friend also has stays an enemy)
  return ns.Data.OnOurSideName(name)
end

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

-- a level seen long ago is probably higher now: in grey (the hitlist tooltip says so)
local function lvl(e)
  local n = ns.Count(e.level)
  if n <= 0 then return "?" end
  if not e.friend and ns.Data.LevelIsOld(e) then return "|cff888888" .. n .. "|r" end
  return tostring(n)
end
local C = ns.Count

-- a number as shown: digits only - never a sign or a symbol in front, and zero is "0" (not "-0")
local function num(v)
  v = tonumber(v)
  if not v or v ~= v or v <= 0 then return "0" end
  if v == math.floor(v) then return string.format("%d", v) end
  return tostring(v)
end
UI.Num = num -- (for tests)
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

-- Clickable names in the Feed tab and the profile's Recent PvP: each player name becomes a custom
-- hyperlink "|Hfnfplayer:<name>|h...|h" (only in these UI lines, never in toasts or chat).
local LINK_KIND = "fnfplayer:"
local function wrapName(colour, name)
  return (colour or "") .. "|H" .. LINK_KIND .. name .. "|h" .. name .. "|h" .. (colour and "|r" or "")
end
-- link `name` wherever it stands alone in `seg` (a stretch of text with no links in it)
local function linkPlain(seg, name)
  local out, pos = {}, 1
  while true do
    local a, b = seg:find(name, pos, true)
    if not a then break end
    local before, after = seg:sub(a - 1, a - 1), seg:sub(b + 1, b + 1)
    if (a > 1 and before:match("%a")) or after:match("%a") then
      out[#out + 1] = seg:sub(pos, b)
    else
      out[#out + 1] = seg:sub(pos, a - 1) .. wrapName(nil, name)
    end
    pos = b + 1
  end
  out[#out + 1] = seg:sub(pos)
  return table.concat(out)
end
-- entry: the feed entry (its who / foes name the players in the text)
-- skip: a name to leave unlinked (the profile that's open: no link to the page you're on)
function UI.Linkify(text, entry, skip)
  if type(text) ~= "string" or text == "" or text:find("|H" .. LINK_KIND, 1, true) then return text end
  -- class-coloured names we know a profile for
  text = text:gsub("(|c%x%x%x%x%x%x%x%x)([^|]+)|r", function(colour, name)
    if name ~= skip and ns.Profile.KindOf(name) then return colour .. "|H" .. LINK_KIND .. name .. "|h" .. name .. "|h|r" end
  end)
  -- names without a colour (class not known): the entry's own players
  local names = {}
  if entry then
    if type(entry.who) == "string" and entry.who ~= "" and entry.who ~= skip then names[#names + 1] = entry.who end
    for _, f in ipairs(entry.foes or {}) do
      if type(f) == "string" and f ~= "" and f ~= skip then names[#names + 1] = f end
    end
  end
  table.sort(names, function(a, b) return #a > #b end) -- (longest first: "Rogz Fang" before "Rogz")
  for _, name in ipairs(names) do
    local out, pos = {}, 1
    while true do
      local a, b = text:find("|H.-|h.-|h", pos)
      out[#out + 1] = linkPlain(text:sub(pos, (a or #text + 1) - 1), name)
      if not a then break end
      out[#out + 1] = text:sub(a, b)
      pos = b + 1
    end
    text = table.concat(out)
  end
  return text
end

-- one player's name (already class-coloured or plain) as a link to their profile; left as it is
-- for `skip` (the open profile) and for names we know nothing about
function UI.LinkName(name, shown, skip)
  shown = shown or name
  if type(name) ~= "string" or name == "" or name == skip or not ns.Profile.KindOf(name) then return shown end
  return "|H" .. LINK_KIND .. name .. "|h" .. shown .. "|h"
end

-- a click on a name link: that player's profile (everything after the first ":" is the name)
function UI.OnPlayerLink(link)
  local name = type(link) == "string" and link:match("^" .. LINK_KIND .. "(.+)$")
  if name and name ~= "" then UI.ShowProfile(name) end
end

-- make `frame` (the one holding the text) answer clicks on the name links
function UI.EnableNameLinks(frame)
  if not frame.SetHyperlinksEnabled then return end
  frame:SetHyperlinksEnabled(true)
  frame:SetScript("OnHyperlinkClick", function(self, link)
    self.linkAt = GetTime and GetTime() or nil -- (a row's own OnClick can tell a link was just clicked)
    UI.OnPlayerLink(link)
  end)
  frame:SetScript("OnHyperlinkEnter", function(self, link)
    if type(link) ~= "string" or link:sub(1, #LINK_KIND) ~= LINK_KIND then return end
    GameTooltip:SetOwner(self, "ANCHOR_CURSOR")
    GameTooltip:AddLine(L.LINK_TIP, 1, 1, 1)
    GameTooltip:Show()
    if SetCursor then SetCursor("Interface\\CURSOR\\Point") end
  end)
  frame:SetScript("OnHyperlinkLeave", function()
    GameTooltip:Hide()
    if ResetCursor then ResetCursor() end
  end)
end

-- just the number (how many of them were best guesses is in the row tooltip)
local function hitKills(e)
  local s = tostring(C(e.kills))
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

-- Friends tab cells: just the number. Group boards: empty for an invite, or a member whose
-- numbers haven't reached you yet.
local function est(r, v)
  if r.invited or r.unknown then return "" end
  return type(v) == "string" and v or num(v)
end
-- K/D: kills per death with two decimals; no deaths = the kills. Never "-0.00".
local function kdText(k, d, kd)
  if (tonumber(d) or 0) <= 0 then return num(k) end
  kd = tonumber(kd) or 0
  if kd <= 0 then return "0.00" end
  return string.format("%.2f", kd)
end

local GREEN = "|cff33ff33"
local GREY = "|cff888888"
-- helpers the other window files share (UIProfile.lua)
UI.Util = { R = R, victimsText = victimsText, lastText = lastText, lvl = lvl, num = num, classIcon = classIcon,
  kdText = kdText, GREEN = GREEN, CLASS_ICONS = CLASS_ICONS }
local function boardNow(r)
  if r.me then return GREEN .. L.FRIEND_ONLINE .. "|r" end
  if r.invited then return GREY .. L.GROUP_ROW_INVITED .. "|r" end
  if r.onAlt then return GREEN .. L.FRIEND_ONLINE_ALT .. "|r" end
  local now = r.rec and r.rec.friend and ns.Profile.NowText(r.rec)
  if now then return GREEN .. now .. "|r" end
  -- a member you're not friends with: how old their numbers are, and who passed them on
  if r.via then return GREY .. L.GROUP_ROW_VIA:format(ns.Ago(r.at), r.via) .. "|r" end
  if r.unknown then return GREY .. L.GROUP_ROW_UNKNOWN .. "|r" end
  return GREY .. ns.Ago(r.lastSeen) .. "|r"
end

local boardView = "friends" -- Friends tab: "friends" or a shared group's id
local killsOf -- Kill list view: whose kills it shows

-- Kill list: who someone killed (an enemy: which of your friends), most first
local KILL_COLS = {
  -- the victim's name links to their profile (not the name of whose list this is)
  { L.COL_NAME, 220, function(e)
    return classIcon(e.class) .. UI.LinkName(e.name, ns.ClassColored(e.name, e.class), killsOf)
  end, byName },
  { L.COL_LEVEL, 30, lvl, byLevel },
  { L.COL_GUILD, 130, guild, byGuild },
  { L.COL_KILLS, 70, function(r) return tostring(C(r.n)) end, function(r) return C(r.n) end },
  { L.COL_LAST_KILL, 210, function(r)
    if not r.t then return "" end
    return ns.Ago(r.t) .. (r.zone and ("  |cff888888" .. r.zone .. "|r") or "")
  end, function(r) return r.t or 0 end },
}

-- the Friends tab: you and your friends ranked by kills (what was the Leaderboard), their
-- notoriety and Bounty board gold, and where they are. A shared group picked above the list shows
-- that group's board instead. Only friends who have sent you something from the add-on are listed.
-- (Your alert list is in Options: Friends & sharing -> Alert list.)
local function bountiesCell(r)
  if r.invited then return "" end
  local gold = ns.Contracts.EarnedBy(r.name)
  return gold > 0 and ns.Contracts.MoneyText(gold) or ""
end
local FRIEND_COLS = {
  { L.COL_RANK, 34, function(r) return ns.Art.RankText(r.rank) end, function(r) return -(r.rank or 999) end },
  { L.COL_NAME, 170, function(r)
    return nameCol(r) .. (r.me and ("  |cff888888" .. L.YOU .. "|r") or "") .. (r.leader and ("  |cffffd100" .. L.GROUP_LEADER_TAG .. "|r") or "")
  end, byName },
  { L.COL_LEVEL, 30, function(r) return lvl(r.rec or r) end, function(r) return tonumber((r.rec or r).level) or 0 end },
  { L.COL_KILLS, 55, function(r) return est(r, r.k) end, function(r) return r.k end },
  { L.COL_DEATHS, 55, function(r) return est(r, r.d) end, function(r) return r.d end },
  { L.COL_KD, 50, function(r) return est(r, kdText(r.k, r.d, r.kd)) end, function(r) return r.kd end },
  -- notoriety claimed (empty: invited, or a friend on a version before 0.9)
  { L.COL_BOUNTY, 75, function(r)
    if r.invited or r.bounty == nil then return "" end
    return ns.Art.Points(r.bounty)
  end, function(r) return r.bounty or -1 end },
  -- Bounty board gold they collected (paid bounties you know of)
  { L.COL_BOUNTIES, 90, bountiesCell, function(r) return ns.Contracts.EarnedBy(r.name) end },
  { L.COL_NOW, 113, boardNow, function(r) return r.me and math.huge or (r.lastSeen or 0) end },
}

local function fetchFriends()
  local g = boardView ~= "friends" and ns.Groups.Get(boardView)
  if g and ns.Groups.MyState(g) ~= "out" then return ns.Profile.Board(g.id) end
  boardView = "friends"
  local rows = ns.Profile.HideLowAlts(ns.Profile.Board())
  return rows
end

-- Bounty board: contracts you and your friends put on enemy players (Contracts.lua)
local STATE_ORDER = { open = 4, done = 3, paid = 2, expired = 1 }
local function contractStatus(r)
  if r.state == "open" then return "|cff33ff33" .. L.CONTRACT_OPEN:format(ns.Contracts.TimeLeft(r)) .. "|r" end
  if r.state == "done" then return "|cffffd100" .. L.CONTRACT_DONE .. "|r" end
  if r.state == "paid" and r.killer and r.killer == r.by then return GREY .. L.CONTRACT_SELF .. "|r" end
  if r.state == "paid" then return GREY .. L.CONTRACT_PAID .. "|r" end
  return GREY .. L.CONTRACT_EXPIRED .. "|r"
end
-- who got the kill (finished bounties stay on the board with it)
local function closedBy(r)
  if not r.killer or (r.state ~= "done" and r.state ~= "paid") then return "" end
  local names = ns.Contracts.Killers(r)
  local shown = {}
  for i = 1, math.min(#names, 2) do
    local n = names[i]
    shown[i] = n == ns.me and L.PROF_ME or (classIcon((ns.Data.FindPlayer(n) or {}).class) .. ns.ClassColored(n))
  end
  local text = table.concat(shown, ", ")
  if #names > #shown then text = text .. " " .. L.CONTRACT_MORE:format(#names - #shown) end
  return text
end
local CONTRACT_COLS = {
  { L.COL_TARGET, 150, nameCol, byName },
  { L.COL_REWARD, 110, function(r) return ns.Contracts.MoneyText(r.amount) end, function(r) return r.amount or 0 end },
  { L.COL_POSTED_BY, 120, function(r) return r.mine and L.PROF_ME or ns.ClassColored(r.by) end, function(r) return (r.by or ""):lower() end },
  { L.COL_CLOSED_BY, 120, closedBy, function(r) return (r.killer or ""):lower() end },
  { L.COL_STATUS, 115, contractStatus, function(r) return (STATE_ORDER[r.state] or 0) * 1e10 + (r.doneAt or r.t or 0) end },
  { L.COL_POSTED, 55, function(r) return GREY .. ns.Ago(r.t) .. "|r" end, function(r) return r.t or 0 end },
}

local TABS = {
  { key = "hitlist", label = L.TAB_HITLIST, columns = HITLIST_COLS,
    fetch = function() return sortedValues(R().hitlist, function(h) return not isFriendRecord(h.name) end) end },
  { key = "contracts", label = L.TAB_CONTRACTS, columns = CONTRACT_COLS, defaultSort = { col = 5, desc = true },
    fetch = function() return ns.Contracts.List() end },
  { key = "friends", label = L.TAB_FRIENDS, columns = FRIEND_COLS, defaultSort = { col = 4, desc = true }, fetch = fetchFriends },
  { key = "feed", label = L.TAB_FEED,
    columns = {
      { L.COL_TIME, 80, function(e) return ns.Ago(e.t) end },
      { L.COL_EVENT, 580, function(e) return UI.Linkify(e.text, e) end },
    },
    fetch = function()
      local feed, out = R().feed, {}
      for i = #feed, 1, -1 do out[#out + 1] = feed[i] end
      return out
    end },
  { key = "profile", label = L.TAB_PROFILE, columns = {}, fetch = function() return {} end },
  -- reached from a profile's Kill list button (no tab of its own)
  { key = "kills", label = L.TAB_KILLS, hidden = true, columns = KILL_COLS, defaultSort = { col = 4, desc = true },
    fetch = function() return killsOf and ns.Kills.List(killsOf) or {} end },
}

local function tabDef(key)
  if key == "board" or key == "leaderboard" then key = "friends" end -- (the Leaderboard is part of Friends)
  for _, t in ipairs(TABS) do if t.key == key then return t end end
  return TABS[1]
end

local function colsOf(def)
  if type(def.columns) == "function" then return def.columns() end
  return def.columns
end

local function friendsView() return currentTab == "friends" end

-- sorting: per tab, by column; newest first by default
local sortState = {}
local function viewKey() return currentTab end
local function sortOf(cols)
  local st = sortState[viewKey()]
  if not st then
    local default = tabDef(currentTab).defaultSort
    st = default and { col = default.col, desc = default.desc }
      or { col = #cols, desc = true } -- last column (last seen / time) newest first
    sortState[viewKey()] = st
  end
  return st
end

local function applySort(list, cols)
  local st = sortOf(cols)
  local key = cols[st.col] and cols[st.col][4]
  if not key then return end
  -- always last, whatever the column: faded hitlist entries (not seen for 30 days), and on a
  -- group board members who are only invited or whose numbers haven't reached you yet.
  -- Decided once, before sorting.
  local last = {}
  for _, e in ipairs(list) do
    if currentTab == "hitlist" then
      last[e] = ns.Data.IsStale(e)
    else
      last[e] = (e.invited or e.unknown) and true or false
    end
  end
  table.sort(list, function(a, b)
    if last[a] ~= last[b] then return last[b] end
    local ka, kb = key(a), key(b)
    if ka == kb then
      -- a tie on the Leaderboard: in rank order (rank 5 before rank 8), then by name
      if a.rank and b.rank and a.rank ~= b.rank then return a.rank < b.rank end
      return (a.name or "") < (b.name or "")
    end
    -- a missing value never comes first
    if ka == nil or kb == nil then return kb == nil end
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

-- tooltip for a hitlist row: record, who they killed (with counts), last seen
function UI.HitTooltip(owner, h)
  GameTooltip:SetOwner(owner, "ANCHOR_CURSOR")
  GameTooltip:AddLine(ns.ClassColored(h.name, h.class) .. (h.guild and ("  |cff888888<" .. h.guild .. ">|r") or ""))
  GameTooltip:AddLine(L.HIT_TIP_RECORD:format(ns.Count(h.kills)), 1, 1, 1)
  local likely = math.min(ns.Count(h.suspect), ns.Count(h.kills))
  if likely > 0 then GameTooltip:AddLine(L.HIT_TIP_LIKELY:format(likely), 0.7, 0.7, 0.7, true) end
  local p = ns.Data.ViewRealm().players[h.name]
  if ns.Count((p or h).level) > 0 and ns.Data.LevelIsOld(p or h) then GameTooltip:AddLine(L.HIT_TIP_LEVEL_OLD, 0.7, 0.7, 0.7, true) end
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
  GameTooltip:Show()
end

-- the rows currently listed (sorted), for tests
function UI.Rows() return data end

-- for tests: a tab's columns, and the width the list has for them
function UI.TabColumns(key) return colsOf(tabDef(key)) end

-- what a column's numbers mean, for its header's tooltip (nil: nothing to explain)
function UI.ColumnTip(tab, label)
  if tab == "board" or tab == "leaderboard" then tab = "friends" end
  local tips = L.COLUMN_TIPS[tab]
  return tips and label and tips[label]
end
UI.LIST_WIDTH = WIDTH - 28 -- the list area is inset 14 on each side
-- for tests: click row i of the list as the game would ("LeftButton" or "RightButton")
function UI.ClickRow(i, mouse)
  local row = rows and rows[i]
  local click = row and row:GetScript("OnClick")
  if click then click(row, mouse or "LeftButton") end
end

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


local function refreshDetail()
  contractBar:SetShown(currentTab == "contracts")
  if currentTab == "contracts" then
    contractBar.label:SetText(L.CONTRACT_HINT)
  end
  if currentTab ~= "hitlist" then
    detail:Hide()
    return
  end
  detail:Show()
  detail.clear:SetEnabled(next(R().hitlist) ~= nil)
  detail.label:SetText(L.HITLIST_HINT)
end


---------------------------------------------------------------------------
-- shared groups on the Friends tab
---------------------------------------------------------------------------
local function currentGroup()
  local g = boardView ~= "friends" and ns.Groups.Get(boardView)
  if g and ns.Groups.MyState(g) ~= "out" then return g end
end
UI.CurrentGroup = currentGroup -- (the group window, UIGroup.lua)

local function refreshGroupBar()
  local show = currentTab == "friends"
  groupBar:SetShown(show)
  if not show then return end
  if not currentGroup() then boardView = "friends" end
  groupBar.dropdown.refresh()
  local g = currentGroup()
  local st = g and ns.Groups.MyState(g)
  groupBar.new:SetShown(not g)
  groupBar.open:SetShown(g ~= nil)
  if g then UI.SetButtonText(groupBar.open, st == "invited" and L.BTN_GROUP_INVITATION or L.BTN_GROUP_OPEN) end
  groupBar.row:Layout()
end

-- the line under a group board: "Gank Squad: 4 members · 54 takedowns, 20 deaths (K/D 2.70)"
function UI.GroupTotals(g)
  local k, d, n, known = ns.Groups.Totals(g)
  -- "1 member" / "2 members": forms = { one, more }
  local function count(forms, x) return (x == 1 and forms[1] or forms[2]):format(x) end
  local line = L.GROUP_TOTALS:format(ns.Groups.Label(g), count(L.N_MEMBERS, n), count(L.N_KILLS, k),
    count(L.N_DEATHS, d), kdText(k, d, ns.Profile.KD(k, d)))
  if known < n then line = line .. " " .. count(L.GROUP_TOTALS_PARTIAL, n - known) end
  return line
end
local function groupHint(g)
  local leading = ns.Groups.Leader(g) == ns.Groups.MyKey()
  return UI.GroupTotals(g) .. "  " .. (leading and L.GROUP_HINT_LEADER or L.GROUP_HINT)
end
UI.GroupHint = groupHint -- (for tests)

local function say(text) print("|cff33ff99" .. L.ADDON .. "|r " .. text) end
local function why(reason) say(L[reason] or tostring(reason)) end

function UI.SetBoardView(v)
  boardView = v or "friends"
  offset = 0
  UI.Refresh()
end
function UI.BoardView() return boardView end
-- (slash commands: pick the board without redrawing)
function UI.UseBoardView(v) boardView = v or "friends" end


function UI.CreateGroup(name)
  local g, reason = ns.Groups.Create(name)
  if not g then return why(reason) end
  say(L.GROUP_CREATED:format(ns.Groups.Label(g)))
  UI.SetBoardView(g.id)
  return g
end

function UI.NewGroup() UI.Prompt(L.GROUP_NEW_PROMPT, UI.CreateGroup) end

function UI.InviteToGroup(name)
  local g = currentGroup()
  local who, reason = ns.Groups.Invite(g, name)
  if not who then return why(reason) end
  say(L.GROUP_INVITE_SENT:format(who, ns.Groups.Label(g)))
  UI.Refresh()
  return who
end

-- Invite: a menu of your friends who aren't in the group yet
function UI.GroupInviteMenu(owner)
  local g = currentGroup()
  if not g then return end
  local names = ns.Groups.Invitable(g)
  if #names == 0 then return say(L.GROUP_NOBODY_TO_INVITE) end
  if not (MenuUtil and MenuUtil.CreateContextMenu) then return say(L.GROUPS_USAGE) end
  MenuUtil.CreateContextMenu(owner, function(_, root)
    root:CreateTitle(L.GROUP_INVITE_TITLE:format(ns.Groups.Label(g)))
    for _, name in ipairs(names) do
      root:CreateButton(ns.ClassColored(name), function() UI.InviteToGroup(name) end)
    end
  end)
end

function UI.JoinGroup()
  local g = currentGroup()
  local ok, reason = ns.Groups.Join(g)
  if not ok then return why(reason) end
  say(L.GROUP_JOINED:format(ns.Groups.Label(g)))
  UI.Refresh()
end

-- leave a group, or decline an invite (no question asked for that)
function UI.LeaveGroup(decline)
  local g = currentGroup()
  if not g then return end
  local function go()
    local ok, reason = ns.Groups.Leave(g)
    if not ok then return why(reason) end
    say((decline and L.GROUP_DECLINED or L.GROUP_LEFT):format(ns.Groups.Label(g)))
    UI.SetBoardView("friends")
  end
  if decline then return go() end
  UI.Confirm(L.CONFIRM_LEAVE_GROUP:format(ns.Groups.Label(g)), go)
end

-- right-click a member on a group board: the leader removes them; on yourself, leave
function UI.RemoveFromGroup(key, name)
  local g = currentGroup()
  if not g then return end
  if key == ns.Groups.MyKey() then return UI.LeaveGroup() end
  if ns.Groups.Leader(g) ~= ns.Groups.MyKey() then return why("GROUP_NOT_LEADER") end
  UI.Confirm(L.CONFIRM_REMOVE_MEMBER:format(name or "?", ns.Groups.Label(g)), function()
    local ok, reason = ns.Groups.Remove(g, key)
    if not ok then return why(reason) end
    UI.Refresh()
  end)
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

-- what Back says it goes to: a tab ("Leaderboard"), a profile ("Bob Pal"), or a kill list
local function placeLabel(place)
  if place.tab == "profile" and place.profileName then return place.profileName end
  if place.tab == "kills" and place.killsOf then return L.KILLS_OF:format(place.killsOf) end
  return tabDef(place.tab).label
end

-- the line under a kill list: whose, how many, and where the numbers come from
local function killsHint()
  local name = killsOf or "?"
  local list = ns.Kills.List(name)
  local line = L.KILLS_HINT:format(ns.ClassColored(name), #list, ns.Kills.Total(list))
  local kind = ns.Profile.KindOf(name)
  local players = R().players
  local p = players[ns.Data.Resolve(players, name)]
  local source
  if kind == "enemy" then source = L.KILLS_SRC_ENEMY
  elseif name == ns.me then source = L.KILLS_SRC_ME
  elseif p and p.slainRepAt then source = L.KILLS_SRC_REPORT:format(ns.Ago(p.slainRepAt))
  elseif ns.Comm.everyone[name] then source = L.KILLS_SRC_ASKING
  else source = L.KILLS_SRC_LOCAL end
  return line .. "  |cff888888" .. source .. "|r"
end

function UI.Refresh()
  if not win or not win:IsShown() then return end
  local def = tabDef(currentTab)
  currentTab = def.key
  if currentTab ~= "profile" and currentTab ~= "kills" then homeTab = currentTab end
  for _, b in ipairs(tabButtons) do selectTabButton(b, b.key == homeTab) end
  refreshGroupBar()

  local isProfile = currentTab == "profile"
  if not isProfile then UI.ResetProfileCount() end -- (back to a profile later: count up again)
  rowsFrame:SetShown(not isProfile)
  profile:SetShown(isProfile)
  if currentTab == "friends" then UI.RefreshGroupWindow() else UI.HideGroupWindow() end
  searchBox:SetShown(not isProfile)
  -- Back: on the Profile page and the Kill list, if there's somewhere to go back to
  local backTo = (isProfile or currentTab == "kills") and history[#history]
  backButton:SetShown(backTo and true or false)
  if backTo then UI.SetButtonText(backButton, L.BTN_BACK:format(placeLabel(backTo))) end
  if isProfile then
    data = {}
    pageText:SetText("")
    prevPage:Hide()
    nextPage:Hide()
    detail:Hide()
    contractBar:Hide() -- (the Bounty board's row belongs to that tab alone)
    friendsHint:Hide()
    UI.RenderProfile()
    return
  end
  friendsHint:Show()

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
      local faded = currentTab == "hitlist" and ns.Data.IsStale(e) -- not seen for 30 days: grey
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
  pageRow:Layout()
  prevPage:SetEnabled(offset > 0)
  nextPage:SetEnabled(offset + ROWS < #data)
  refreshDetail()
  friendsHint:SetShown(friendsView() or currentTab == "kills")
  if currentTab == "kills" then
    friendsHint:SetText(killsHint())
  elseif friendsView() then
    local g = currentGroup()
    if g then
      friendsHint:SetText(groupHint(g))
    else
      friendsHint:SetText(L.BOARD_HINT .. " " .. L.REMOVE_HINT)
    end
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

-- going to the Profile page or a Kill list: remember where you are, for Back
local function rememberPlace(target, name)
  local same = currentTab == target
    and ((target == "profile" and profileName == name) or (target == "kills" and killsOf == name))
  if same then return end
  history[#history + 1] = { tab = currentTab, offset = offset, boardView = boardView,
    profileName = profileName, killsOf = killsOf }
  if #history > HISTORY_MAX then table.remove(history, 1) end
end

function UI.Back()
  local b = table.remove(history)
  if not b then return end
  currentTab, offset, boardView = b.tab, b.offset, b.boardView
  profileName, killsOf = b.profileName, b.killsOf
  UI.Refresh()
end

-- for tests
function UI.CurrentTab() return currentTab end
function UI.HomeTab() return homeTab end
function UI.BackLabel() return history[#history] and placeLabel(history[#history]) end
function UI.KillsOf() return killsOf end

function UI.SelectTab(key)
  -- older names: 0.6 had one Players tab; the Enemies tab is gone (enemies are on the Hitlist)
  if key == "players" or key == "enemies" then key = "hitlist" end
  key = tabDef(key).key
  wipe(history) -- picking a tab yourself starts over
  local changed = key ~= homeTab or key ~= currentTab
  if key == "profile" then profileName = ns.me end -- the Profile tab: always yours
  homeTab, currentTab = key, key
  offset = 0
  UI.Refresh()
  if changed then -- a page turn, and the new page fades in
    ns.Art.Sound("page")
    ns.Art.FadeIn(key == "profile" and profile or rowsFrame)
  end
end

-- 0.6 name: the Enemies/Friends dropdown (enemies are on the Hitlist now)
function UI.SetPlayerFilter(which) UI.SelectTab(which == "friends" and "friends" or "hitlist") end

function UI.OpenSettings() ns.Options.Open() end


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
  win:SetScript("OnShow", function()
    ns.Art.Sound("open")
    ns.Art.FadeIn(win)
    UI.Refresh()
  end)
  win:SetScript("OnHide", function() ns.Art.Sound("close") end)
  win:Hide()
  tinsert(UISpecialFrames, "FriendsAndFoesFrame")

  -- top row: search and Options (right)
  local options = button(win, 80, L.BTN_OPTIONS, function() UI.OpenSettings() end)
  local topRow = UI.Row(win, "TOPRIGHT", -14, -30)
  topRow:Add(options)

  -- search: filters the current list by name / guild (Feed: by text)
  local okBox, box = pcall(CreateFrame, "EditBox", "FriendsAndFoesSearchBox", win, "SearchBoxTemplate")
  if not (okBox and box) then box = CreateFrame("EditBox", "FriendsAndFoesSearchBox", win, "InputBoxTemplate") end
  box:SetSize(150, 20)
  topRow:Add(box, 12)
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

  -- Friends tab: which board (your friends or a shared group) and what you can do with it
  groupBar = CreateFrame("Frame", nil, win)
  groupBar:SetSize(420, 24)
  groupBar:SetPoint("TOPLEFT", 16, -30)
  groupBar.dropdown = UI.Dropdown(groupBar, 170, function()
    local items = { { "friends", L.BOARD_FRIENDS } }
    local mine, count = ns.Groups.Mine(), {}
    for _, g in ipairs(mine) do count[ns.Groups.Label(g):lower()] = (count[ns.Groups.Label(g):lower()] or 0) + 1 end
    for _, g in ipairs(mine) do
      local invited = ns.Groups.MyState(g) == "invited"
      -- two groups with the same name (different creators): say whose is whose
      local label = ns.Groups.Label(g) .. (count[ns.Groups.Label(g):lower()] > 1 and (" (" .. ns.FirstName(g.owner) .. ")") or "")
      items[#items + 1] = { g.id, label .. (invited and ("  " .. L.GROUP_INVITED_TAG) or "") }
    end
    return items
  end, function() return boardView end, function(v) UI.SetBoardView(v) end)
  groupBar.dropdown:SetPoint("LEFT", 0, 0)
  -- the buttons that apply line up after the dropdown (refreshGroupBar picks them, then Layout)
  groupBar.row = UI.Row(groupBar, "LEFT", 8, 0, groupBar.dropdown)
  groupBar.new = groupBar.row:Add(button(groupBar, 90, L.BTN_GROUP_NEW, function() UI.NewGroup() end))
  -- a group picked: its window (members, invites, join, leave) - "Invitation" while you're invited
  groupBar.open = groupBar.row:Add(button(groupBar, 80, L.BTN_GROUP_OPEN, function() UI.ToggleGroupWindow(win) end))
  groupBar:Hide()

  -- Profile page: back to where you were (same spot as the group bar, which is hidden there)
  backButton = button(win, 70, "<", function() UI.Back() end)
  backButton:SetPoint("TOPLEFT", 16, -30)
  backButton:Hide()


  local prev
  for i, t in ipairs(TABS) do
    if not t.hidden then -- (the Kill list has no tab: it opens from a profile)
      prev = createTab(win, t.key, t.label, prev, i)
      tabButtons[#tabButtons + 1] = prev
    end
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
    -- hover a column header: what its numbers mean (where that needs saying)
    b:SetScript("OnEnter", function(self)
      local tip = UI.ColumnTip(currentTab, self.text:GetText())
      if not tip then return end
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:AddLine(self.text:GetText(), 1, 0.82, 0)
      GameTooltip:AddLine(tip, 1, 1, 1, true)
      GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() GameTooltip:Hide() end)
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
      row.stripe = row:CreateTexture(nil, "BACKGROUND", nil, -1)
      row.stripe:SetAllPoints()
      row.stripe:SetColorTexture(1, 1, 1, 0.03)
    end
    UI.EnableNameLinks(row) -- (the Feed's player names are links to their profile)
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
        if e and currentTab == "hitlist" then
          UI.RemoveFromHitlist(e.name)
        elseif e and friendsView() and currentGroup() then
          UI.RemoveFromGroup(e.key, e.name)
        elseif e and not e.me and friendsView() then
          UI.RemovePlayer(e.name)
        elseif e and currentTab == "contracts" and e.mine then
          UI.ContractAction(e)
        end
        return
      end
      -- a click on a name opens their profile, on every tab (not twice when it was the name link)
      if self.linkAt and GetTime and GetTime() - self.linkAt < 0.2 then self.linkAt = nil; return end
      if currentTab ~= "feed" and e and e.name and ns.Profile.KindOf(e.name) then
        UI.ShowProfile(e.name) -- (a group member you've never heard from directly has no profile)
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
  pageRow = UI.Row(win, "BOTTOMRIGHT", -12, 4)
  nextPage = pageRow:Add(pageButton(1))
  pageText = pageRow:Add(win:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall"), 2)
  prevPage = pageRow:Add(pageButton(-1), 2)

  friendsHint = win:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  friendsHint:SetPoint("BOTTOMLEFT", 18, 40)
  friendsHint:SetPoint("BOTTOMRIGHT", -18, 40)
  friendsHint:SetJustifyH("LEFT")
  -- two lines at most, so it never reaches the list above it
  if friendsHint.SetMaxLines then friendsHint:SetMaxLines(2) end

  -- hitlist bottom row: a hint on the left, [Clear hitlist] on the right.
  -- (A player's note, kill list and the rest are on their profile: click them.)
  detail = CreateFrame("Frame", nil, win)
  -- above the page arrows (bottom right), so the two rows never touch
  detail:SetPoint("BOTTOMLEFT", 16, 30)
  detail:SetPoint("BOTTOMRIGHT", -16, 30)
  detail:SetHeight(46)
  local detailRow = UI.Row(detail, "BOTTOMRIGHT", 0, 0)
  detail.clear = detailRow:Add(button(detail, 100, L.BTN_CLEAR_HITLIST, function() UI.ClearHitlist() end))
  -- the hint stops before the buttons; two lines at most
  detail.label = detail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  detail.label:SetPoint("BOTTOMLEFT", 0, 4)
  detail.label:SetPoint("RIGHT", detail.clear, "LEFT", -16, 0)
  detail.label:SetJustifyH("LEFT")
  if detail.label.SetMaxLines then detail.label:SetMaxLines(2) end

  -- Bounty board bottom row: what it is on the left, [Post bounty] on the right
  contractBar = CreateFrame("Frame", nil, win)
  contractBar:SetPoint("BOTTOMLEFT", 16, 30)
  contractBar:SetPoint("BOTTOMRIGHT", -16, 30)
  contractBar:SetHeight(46)
  local contractRow = UI.Row(contractBar, "BOTTOMRIGHT", 0, 0)
  contractBar.post = contractRow:Add(button(contractBar, 120, L.BTN_POST_BOUNTY, function() UI.PostBounty() end))
  contractBar.label = contractBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  contractBar.label:SetPoint("BOTTOMLEFT", 0, 4)
  contractBar.label:SetPoint("RIGHT", contractBar.post, "LEFT", -16, 0)
  contractBar.label:SetJustifyH("LEFT")
  if contractBar.label.SetMaxLines then contractBar.label:SetMaxLines(3) end
  contractBar:Hide()

  profile = UI.BuildProfile(win)

end

---------------------------------------------------------------------------
-- the Bounty board: post a bounty, cancel yours, mark it paid
---------------------------------------------------------------------------
-- the enemy to put a bounty on: name (an enemy you know, e.g. from their profile), or your target
local function bountyTarget(name)
  if name then
    local e = ns.Data.FindPlayer(name) or ns.Data.FindHit(name) or { name = name }
    return { name = e.name, class = e.class, level = e.level, guild = e.guild }
  end
  local info = ns.PvP.ReadEnemy("target")
  if info and info.name then return info end
end

-- amountText: the amount already typed (/fnf bounty 10g); otherwise you're asked for it
function UI.PostBounty(name, amountText)
  local u = bountyTarget(name)
  if not u then
    why("CONTRACT_NEED_TARGET")
    return false
  end
  local function post(text)
    local amount, days = ns.Contracts.ParseOffer(text)
    if not amount then
      why(days)
      return
    end
    local c, reason = ns.Contracts.Post(u, amount, days)
    if not c then
      say((L[reason] or tostring(reason)):format(ns.Contracts.OPEN_MAX))
      return
    end
    say(L.CONTRACT_POSTED_YOU:format(ns.Contracts.MoneyText(c.amount), ns.ClassColored(c.target, c.class), ns.Contracts.DaysOf(c)))
    UI.Refresh()
  end
  if amountText and amountText ~= "" then
    post(amountText)
  else
    UI.Prompt(L.CONTRACT_PROMPT:format(ns.ClassColored(u.name, u.class)), post)
  end
  return true
end

-- right-click on your own bounty: cancel it (open), or mark it paid (done)
function UI.ContractAction(r)
  local money, target = ns.Contracts.MoneyText(r.amount), ns.ClassColored(r.name, r.class)
  if r.state == "open" then
    UI.Confirm(L.CONTRACT_CONFIRM_CANCEL:format(money, target), function()
      if ns.Contracts.Cancel(r.key) then say(L.CONTRACT_CANCELLED) end
      UI.Refresh()
    end)
  elseif r.state == "done" then
    local payees = ns.Contracts.Payees(r)
    local text
    if #payees > 1 then
      text = L.CONTRACT_CONFIRM_PAID_MANY:format(ns.Contracts.JoinNames(payees), ns.Contracts.MoneyText(ns.Contracts.ShareOf(r)), target)
    else
      text = L.CONTRACT_CONFIRM_PAID:format(ns.ClassColored(payees[1] or r.killer or "?"), ns.Contracts.MoneyText(ns.Contracts.ShareOf(r)), target)
    end
    UI.Confirm(text, function()
      ns.Contracts.MarkPaid(r.key)
      UI.Refresh()
    end)
  end
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


-- tab: "hitlist" | "contracts" | "friends" | "feed" | "profile" ("players" / "enemies" from older
-- versions open the Hitlist; "board", the old Leaderboard, opens Friends)
function UI.Show(tab)
  if not win then build() end
  if tab == "players" or tab == "enemies" then
    tab = "hitlist"
  elseif tab == "settings" then
    UI.OpenSettings()
    return
  end
  if tab then
    local key = tabDef(tab).key
    -- opening a tab starts over; the Profile tab is your own profile
    wipe(history)
    if key == "profile" then profileName = ns.me end
    if key ~= "kills" then homeTab = key end
    currentTab = key
    offset = 0
  end
  win:Show()
  -- (patch notes first: on a brand-new account they stay silent and the tour takes over)
  if ns.WhatsNew then ns.Try("whatsnew", ns.WhatsNew.MaybeShow) end
  if ns.Tour then ns.Tour.MaybeShow(win) end -- (first time on this account)
  UI.Refresh()
end

-- someone's profile or kill list: shown inside the tab you're on, with Back
local function openPage(key)
  if not win then build() end
  currentTab = key
  offset = 0
  win:Show()
  UI.Refresh()
end

function UI.Toggle()
  if win and win:IsShown() then win:Hide() else UI.Show() end
end

function UI.ShowProfile(name)
  -- "Rogz" -> "Rogz Fang" when that's the only one, so the page and its buttons use one key
  local key = ns.Data.Resolve(R().players, name)
  if not R().players[key] then key = ns.Data.Resolve(R().hitlist, name) end
  rememberPlace("profile", key)
  profileName = key
  openPage("profile")
end

-- someone's kill list (opened from their profile); a friend online is asked for their own list
function UI.ShowKills(name)
  if not name then return end
  rememberPlace("kills", name)
  killsOf = name
  if ns.Profile.KindOf(name) == "friend" then ns.Kills.Ask(name) end
  openPage("kills")
end

-- the profile tab's player (for tests)
function UI.ProfileName() return profileName end
function UI.SetProfileName(name) profileName = name end
function UI.ProfileModel() return profile and profile.model end -- (for tests)
function UI.Frames() return { profile = profile, rows = rowsFrame, contractBar = contractBar } end -- (for tests)

-- clicking a toast: that player's profile
function UI.ShowPlayer(name)
  if ns.Profile.KindOf(name) then return UI.ShowProfile(name) end
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
    UI.Show("hitlist")
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
ns.OnReady(function() ns.Events.WeeklyRoll() end) -- (Events.lua)

