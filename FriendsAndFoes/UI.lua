local _, ns = ...
local L = ns.L

-- The main window: a plain, native-looking reference you open now and then.
-- Tabs: Hitlist, Leaderboard, Enemies, Friends, Feed, Profile; settings live in the game's Options panel.
local UI = {}
ns.UI = UI

local WIDTH, HEIGHT = 700, 470
local ROWS, ROW_H = 15, 20
local MAX_COLS = 7

local win, rowsFrame, header, rows, detail, pageText, emptyText, simBanner, friendsHint, prevPage, nextPage
local groupBar -- Leaderboard: board picker + group buttons
-- Back (Profile page and Kill list): the places you came through, newest last
-- ({ tab, offset, boardView, profileName, killsOf })
local backButton
local history = {}
local HISTORY_MAX = 10
local profile -- the Profile tab's panel
local profileName -- whose profile it shows
local tabButtons = {}
local currentTab = "hitlist"
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

-- a level seen long ago is probably higher now: "24+" in grey
local function lvl(e)
  local n = ns.Count(e.level)
  if n <= 0 then return "?" end
  if not e.pending and not e.friend and ns.Data.LevelIsOld(e) then return "|cff888888" .. n .. "+|r" end
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

-- a friend's kills and deaths: the same numbers as on the Leaderboard and their profile (their
-- own report, or counted from their alerts while they don't report yet)
local function friendKD(e)
  if e.sk then return e.sk, e.sd or 0 end
  return C(e.k), C(e.d)
end
local function kdCell(i)
  return function(e)
    if e.pending then return "" end
    return num((select(i, friendKD(e))))
  end, function(e)
    if e.pending then return -1 end
    return (select(i, friendKD(e)))
  end
end
local killsCell, killsSort = kdCell(1)
local deathsCell, deathsSort = kdCell(2)

local FRIEND_COLS = {
  { L.COL_NAME, 165, nameCol, byName },
  { L.COL_LEVEL, 30, lvl, byLevel },
  { L.COL_VERSION, 50, function(e)
    if not e.version then return "" end
    -- newer than yours: time to update; older: tell them to (same colours as on their profile)
    if ns.VersionNewer(e.version, ns.VERSION) then return "|cffffd100" .. e.version .. "|r" end
    if ns.VersionNewer(ns.VERSION, e.version) then return "|cffff7f3f" .. e.version .. "|r" end
    return e.version
  end, function(e) return e.version or "" end },
  { L.COL_KILLS, 70, killsCell, killsSort },
  { L.COL_DEATHS, 55, deathsCell, deathsSort },
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
    -- the time of that event itself (older saves don't have it: then when we last heard of them)
    return online .. (e.lastText or "") .. "  |cff888888" .. ns.Ago(e.lastTextAt or e.lastSeen) .. "|r"
  end, function(e) return e.pending and math.huge or (e.lastTextAt or e.lastSeen or 0) end },
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

-- Leaderboard cells: just the number. Group boards: empty for an invite, or a member whose
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
local function boardNow(r)
  if r.me then return GREEN .. L.FRIEND_ONLINE .. "|r" end
  if r.invited then return GREY .. L.GROUP_ROW_INVITED .. "|r" end
  local now = r.rec and r.rec.friend and ns.Profile.NowText(r.rec)
  if now then return GREEN .. now .. "|r" end
  -- a member you're not friends with: how old their numbers are, and who passed them on
  if r.via then return GREY .. L.GROUP_ROW_VIA:format(ns.Ago(r.at), r.via) .. "|r" end
  if r.unknown then return GREY .. L.GROUP_ROW_UNKNOWN .. "|r" end
  return GREY .. ns.Ago(r.lastSeen) .. "|r"
end

local boardView = "friends" -- Leaderboard: "friends" or a shared group's id
local killsOf -- Kill list view: whose kills it shows

-- Kill list: who someone killed (an enemy: which of your friends), most first
local KILL_COLS = {
  { L.COL_NAME, 220, nameCol, byName },
  { L.COL_LEVEL, 30, lvl, byLevel },
  { L.COL_GUILD, 130, guild, byGuild },
  { L.COL_KILLS, 70, function(r) return tostring(C(r.n)) end, function(r) return C(r.n) end },
  { L.COL_LAST_KILL, 210, function(r)
    if not r.t then return "" end
    return ns.Ago(r.t) .. (r.zone and ("  |cff888888" .. r.zone .. "|r") or "")
  end, function(r) return r.t or 0 end },
}

local BOARD_COLS = {
  { L.COL_RANK, 34, function(r) return r.rank and tostring(r.rank) or "" end, function(r) return -(r.rank or 999) end },
  { L.COL_NAME, 200, function(r)
    return nameCol(r) .. (r.me and ("  |cff888888" .. L.YOU .. "|r") or "") .. (r.leader and ("  |cffffd100" .. L.GROUP_LEADER_TAG .. "|r") or "")
  end, byName },
  { L.COL_KILLS, 70, function(r) return est(r, r.k) end, function(r) return r.k end },
  { L.COL_DEATHS, 70, function(r) return est(r, r.d) end, function(r) return r.d end },
  { L.COL_KD, 60, function(r) return est(r, kdText(r.k, r.d, r.kd)) end, function(r) return r.kd end },
  { L.COL_NOW, 236, boardNow, function(r) return r.me and math.huge or (r.lastSeen or 0) end },
}

local TABS = {
  { key = "hitlist", label = L.TAB_HITLIST, columns = HITLIST_COLS,
    fetch = function() return sortedValues(R().hitlist, function(h) return not isFriendRecord(h.name) end) end },
  { key = "board", label = L.TAB_BOARD, columns = BOARD_COLS, defaultSort = { col = 3, desc = true },
    fetch = function()
      local g = boardView ~= "friends" and ns.Groups.Get(boardView)
      if not g or ns.Groups.MyState(g) == "out" or ns.viewSim then
        boardView = "friends"
        return ns.Profile.Board()
      end
      return ns.Profile.Board(g.id)
    end },
  { key = "enemies", label = L.TAB_ENEMIES, columns = ENEMY_COLS,
    fetch = function() return sortedValues(R().players, function(p) return p.enemy and not isFriendRecord(p.name) end) end },
  { key = "friends", label = L.TAB_FRIENDS, columns = FRIEND_COLS, fetch = fetchFriends },
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
  { key = "profile", label = L.TAB_PROFILE, columns = {}, fetch = function() return {} end },
  -- reached from a profile's Kill list button (no tab of its own)
  { key = "kills", label = L.TAB_KILLS, hidden = true, columns = KILL_COLS, defaultSort = { col = 4, desc = true },
    fetch = function() return killsOf and ns.Kills.List(killsOf) or {} end },
}

local function tabDef(key)
  for _, t in ipairs(TABS) do if t.key == key then return t end end
  return TABS[1]
end

local function colsOf(def)
  if type(def.columns) == "function" then return def.columns() end
  return def.columns
end

local function friendsView() return currentTab == "friends" end
local function playersView() return currentTab == "enemies" or currentTab == "friends" end

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
  -- always last, whatever the column: faded hitlist entries (not seen for 90 days), and on a
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
    if ka == kb then return (a.name or "") < (b.name or "") end
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

-- for tests: a tab's columns, and the width the list has for them
function UI.TabColumns(key) return colsOf(tabDef(key)) end
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
  detail.label:SetText(L.HITLIST_HINT .. "  |cff888888" .. L.SUSPECT_HINT .. "|r")
end

---------------------------------------------------------------------------
-- profile page
---------------------------------------------------------------------------
local PROFILE_LINES, RECENT_LINES = 9, 10
-- your own profile: your character above recent PvP, which then has room for fewer lines
local MODEL_TOP, MODEL_H, RECENT_LINES_ME = -40, 190, 5
local PROFILE_TOP = -50 -- where the facts and recent PvP start, below the name lines
local DASH = "|cff888888-|r"

local function className(class)
  if not class then return "" end
  local names = LOCALIZED_CLASS_NAMES_MALE
  return (names and names[class]) or (class:sub(1, 1) .. class:sub(2):lower())
end

local function nameOr(name) return name and ns.ClassColored(name) or DASH end

-- What the Profile tab shows for a name: { kind, title, sub, lines = { {label, value} },
-- recent = { feed entries } }, or nil if we know nothing about them.
function UI.ProfileView(name)
  local kind = ns.Profile.KindOf(name)
  if not kind then return nil end
  local players, hitlist = R().players, R().hitlist
  local rec = players[ns.Data.Resolve(players, name)]
  local view = { kind = kind, lines = {} }
  local function line(label, value) view.lines[#view.lines + 1] = { label, value } end

  if kind == "enemy" then
    local h = hitlist[ns.Data.Resolve(hitlist, name)]
    local e = rec or h
    view.title = classIcon(e.class) .. ns.ClassColored(e.name, e.class)
    view.sub = L.PROF_ENEMY .. "  \194\183  " .. L.PROF_LEVEL_CLASS:format(lvl(e), className(e.class)) .. (e.guild and ("  <" .. e.guild .. ">") or "")
    line(L.PROF_KILLS_ON_US, C(rec and rec.k))
    line(L.PROF_DIED_TO_US, C(rec and rec.d))
    line(L.PROF_ATTACKS, math.max(C(rec and rec.atk), C(h and h.attacks)))
    local victims = h and victimsText(h) or ""
    line(L.PROF_KILLED, victims ~= "" and victims or DASH)
    line(L.PROF_REVENGE, C(h and h.revenge))
    line(L.PROF_HITLIST, h and L.PROF_ON_HITLIST or L.PROF_NOT_ON_HITLIST)
    if h and h.sharedBy then line(L.PROF_SHARED_BY, ns.ClassColored(h.sharedBy)) end
    local by = {}
    for _, n in ipairs(ns.Profile.WantedBy(e.name)) do by[#by + 1] = ns.ClassColored(n) end
    line(L.PROF_WANTED_BY, #by > 0 and ns.JoinNames(by) or DASH)
    line(L.PROF_LAST_SEEN, lastText(e))
    view.note = h and h.note
    view.onHitlist = h ~= nil
    view.recent = ns.Profile.Recent(e.name, true, RECENT_LINES)
    return view
  end

  -- you or a friend
  local isMe = kind == "me" and name == ns.me
  local _, myClass = UnitClass("player")
  local p = rec or { name = name, class = isMe and myClass or nil, level = isMe and UnitLevel("player") or nil, k = 0, d = 0 }
  view.title = classIcon(p.class) .. ns.ClassColored(p.name, p.class) .. (isMe and ("  |cff888888" .. L.YOU .. "|r") or "")
  view.sub = L.PROF_FRIEND .. "  \194\183  " .. L.PROF_LEVEL_CLASS:format(lvl(p), className(p.class))

  local board, row = ns.Profile.Board(), nil
  for _, r in ipairs(board) do if r.name == p.name then row = r end end
  local k = row and row.k or (p.sk or C(p.k))
  local d = row and row.d or (p.sd or C(p.d))
  local estimated = row and row.estimated or (not isMe and p.sk == nil)
  line(L.PROF_KILLS, num(k))
  line(L.PROF_DEATHS, num(d))
  line(L.PROF_KD, kdText(k, d, ns.Profile.KD(k, d)))
  line(L.PROF_RANK, row and L.PROF_RANK_OF:format(row.rank, #board) or DASH)
  local nem, times = ns.Profile.Nemesis(p.name)
  line(L.PROF_NEMESIS, nem and L.PROF_NEMESIS_TEXT:format(ns.ClassColored(nem.name, nem.class), times) or DASH)
  line(L.PROF_WANTED, nameOr(isMe and ns.Profile.Wanted() or p.wanted))
  if isMe then
    local zone = GetRealZoneText and GetRealZoneText()
    if ns.issecret(zone) then zone = nil end
    local parts = { L.FRIEND_ONLINE, zone }
    local status = ns.Profile.MyStatus()
    if status == "afk" then parts[#parts + 1] = L.STATUS_AFK elseif status == "pvp" then parts[#parts + 1] = L.STATUS_FIGHT end
    line(L.PROF_NOW, GREEN .. table.concat(parts, " \194\183 ") .. "|r")
    line(L.PROF_ADDON, ns.VERSION)
  else
    local now = ns.Profile.NowText(p)
    if now then
      line(L.PROF_NOW, GREEN .. now .. "|r")
    else
      -- when you last heard from them, and separately where they were last known to be (with
      -- its own time: the two can differ)
      line(L.PROF_LAST_SEEN, ns.Ago(p.lastSeen))
      if p.zone and not p.whereOff then
        line(L.PROF_LAST_PLACE, p.zone .. (p.zoneAt and ("  |cff888888" .. ns.Ago(p.zoneAt) .. "|r") or ""))
      end
    end
    local v = p.version
    if not v then line(L.PROF_ADDON, DASH)
    elseif ns.VersionNewer(v, ns.VERSION) then line(L.PROF_ADDON, "|cffffd100" .. L.PROF_NEWER:format(v) .. "|r")
    elseif ns.VersionNewer(ns.VERSION, v) then line(L.PROF_ADDON, "|cffff7f3f" .. L.PROF_OUTDATED:format(v) .. "|r")
    else line(L.PROF_ADDON, v) end
  end
  view.estimated = estimated
  view.isMe = isMe
  view.recent = ns.Profile.Recent(p.name, false, RECENT_LINES)
  return view
end

local function renderProfile()
  -- the Profile tab opened directly, with nobody chosen yet: your own
  if not profileName then profileName = ns.me end
  local v = UI.ProfileView(profileName)
  profile.empty:SetShown(v == nil)
  profile.title:SetText(v and v.title or "")
  profile.sub:SetText(v and v.sub or "")
  for i = 1, PROFILE_LINES do
    local l = v and v.lines[i]
    profile.labels[i]:SetText(l and l[1] or "")
    profile.values[i]:SetText(l and tostring(l[2]) or "")
  end
  -- your character, on your own profile
  local model = profile.model
  local withModel = model ~= nil and v ~= nil and v.isMe
  if model then
    if withModel and not model:IsShown() then
      model:Show()
      model.dress(model)
    elseif not withModel then
      model:Hide()
    end
  end
  local recentTop = withModel and (MODEL_TOP - MODEL_H - 8) or PROFILE_TOP
  local recentLines = withModel and RECENT_LINES_ME or RECENT_LINES
  profile.recentHeader:ClearAllPoints()
  profile.recentHeader:SetPoint("TOPLEFT", 340, recentTop)
  for i = 1, RECENT_LINES do
    profile.recent[i]:ClearAllPoints()
    profile.recent[i]:SetPoint("TOPLEFT", 340, recentTop - i * 19)
  end

  profile.recentHeader:SetText(v and L.PROF_RECENT or "")
  local recent = v and v.recent or {}
  for i = 1, RECENT_LINES do
    local e = i <= recentLines and recent[i]
    profile.recent[i]:SetText(e and ("|cff888888" .. ns.Ago(e.t) .. "|r  " .. e.text) or "")
  end
  if v and #recent == 0 then profile.recent[1]:SetText("|cff888888" .. L.PROF_RECENT_NONE .. "|r") end
  profile.footnote:SetText(v and v.estimated and ("|cff888888" .. L.PROF_ESTIMATED .. "|r") or "")

  -- controls: you = clear most wanted; friend = pick; enemy = note (on your hitlist) + most wanted
  local c = profile.controls
  c:SetShown(v ~= nil)
  if not v then return end
  local editable = v.kind == "enemy" and v.onHitlist
  c.editLabel:SetShown(editable)
  c.edit:SetShown(editable)
  c.save:SetShown(editable)
  if editable and not c.edit:HasFocus() then c.edit:SetText(v.note or "") end
  -- Kill list (n): who they killed, how many in all
  UI.SetButtonText(c.kills, L.BTN_KILL_LIST_N:format(ns.Kills.Total(ns.Kills.List(profileName))))
  c.kills:Show()
  local action = c.action
  action:Show()
  action:Enable()
  if v.isMe then
    UI.SetButtonText(action, L.BTN_WANTED_CLEAR)
    action:SetEnabled(ns.Profile.Wanted() ~= nil)
  elseif v.kind == "enemy" then
    local isWanted = ns.Profile.Wanted() == profileName
    UI.SetButtonText(action, isWanted and L.BTN_WANTED_CLEAR or L.BTN_WANTED_SET)
  else
    local tag = ns.Comm.TagFor(profileName)
    UI.SetButtonText(action, ns.Comm.IsPicked(tag) and L.BTN_PICK_OFF or L.BTN_PICK_ON)
    action:SetEnabled(tag ~= nil and not ns.viewSim and profileName ~= ns.me)
  end
end

function UI.ProfileAction()
  local kind = ns.Profile.KindOf(profileName)
  if not kind then return end
  local prefix = "|cff33ff99" .. L.ADDON .. "|r "
  if kind == "me" or (kind == "enemy" and ns.Profile.Wanted() == profileName) then
    ns.Profile.SetWanted(nil)
    print(prefix .. L.WANTED_CLEARED)
  elseif kind == "enemy" then
    print(prefix .. L.WANTED_SET:format(ns.Profile.SetWanted(profileName)))
  else
    UI.TogglePick(profileName)
    return
  end
  UI.Refresh()
end

-- Save on the profile page: the note on an enemy on your hitlist (it never leaves your computer)
function UI.ProfileSave(text)
  local kind = ns.Profile.KindOf(profileName)
  if kind == "enemy" then
    local h = R().hitlist[ns.Data.Resolve(R().hitlist, profileName)]
    if h then h.note = (text and text ~= "") and text or nil end
  end
  UI.Refresh()
end

---------------------------------------------------------------------------
-- shared groups on the Leaderboard
---------------------------------------------------------------------------
local function currentGroup()
  local g = boardView ~= "friends" and ns.Groups.Get(boardView)
  if g and ns.Groups.MyState(g) ~= "out" then return g end
end

local function refreshGroupBar()
  local show = currentTab == "board" and not ns.viewSim
  groupBar:SetShown(show)
  if not show then return end
  if not currentGroup() then boardView = "friends" end
  groupBar.dropdown.refresh()
  local g = currentGroup()
  local st = g and ns.Groups.MyState(g)
  groupBar.new:SetShown(not g)
  groupBar.invite:SetShown(st == "in")
  groupBar.leave:SetShown(st == "in")
  groupBar.join:SetShown(st == "invited")
  groupBar.decline:SetShown(st == "invited")
end

-- the line under a group board: "Gank Squad: 4 members · 54 takedowns, 20 deaths (K/D 2.70)"
local function groupHint(g)
  local k, d, n, known = ns.Groups.Totals(g)
  -- "1 member" / "2 members": forms = { one, more }
  local function count(forms, x) return (x == 1 and forms[1] or forms[2]):format(x) end
  local line = L.GROUP_TOTALS:format(ns.Groups.Label(g), count(L.N_MEMBERS, n), count(L.N_KILLS, k),
    count(L.N_DEATHS, d), kdText(k, d, ns.Profile.KD(k, d)))
  if known < n then line = line .. " " .. count(L.GROUP_TOTALS_PARTIAL, n - known) end
  local leading = ns.Groups.Leader(g) == ns.Groups.MyKey()
  return line .. "  " .. (leading and L.GROUP_HINT_LEADER or L.GROUP_HINT)
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

-- a one-line text prompt (the game's pop-up with an edit box); nothing happens without one
local PROMPT = "FRIENDSANDFOES_PROMPT"
function UI.Prompt(text, onAccept)
  if not (StaticPopupDialogs and StaticPopup_Show) then return end
  StaticPopupDialogs[PROMPT] = StaticPopupDialogs[PROMPT] or {
    text = "%s", button1 = ACCEPT or "Accept", button2 = CANCEL or "Cancel",
    hasEditBox = true, maxLetters = 24, enterClicksFirstButton = true,
    OnAccept = function(self, data)
      local eb = self.editBox or self.EditBox or (self.GetEditBox and self:GetEditBox())
      local d = data or self.data
      if eb and d and d.fn then ns.Try("prompt", d.fn, eb:GetText()) end
    end,
    EditBoxOnEnterPressed = function(self)
      local parent = self:GetParent()
      local d = parent and parent.data
      if d and d.fn then ns.Try("prompt", d.fn, self:GetText()) end
      if parent then parent:Hide() end
    end,
    timeout = 0, whileDead = true, hideOnEscape = true, preferredIndex = 3,
  }
  StaticPopup_Show(PROMPT, text, nil, { fn = onAccept })
end

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
  for _, b in ipairs(tabButtons) do selectTabButton(b, b.key == currentTab) end
  simBanner:SetShown(ns.viewSim and true or false)
  refreshGroupBar()

  local isProfile = currentTab == "profile"
  rowsFrame:SetShown(not isProfile)
  profile:SetShown(isProfile)
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
    friendsHint:Hide()
    renderProfile()
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
  friendsHint:SetShown(playersView() or currentTab == "board" or currentTab == "kills")
  if currentTab == "kills" then
    friendsHint:SetText(killsHint())
  elseif currentTab == "board" then
    local g = currentGroup()
    friendsHint:SetText(g and groupHint(g) or L.BOARD_HINT)
  elseif friendsView() and not ns.viewSim then
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
function UI.BackLabel() return history[#history] and placeLabel(history[#history]) end
function UI.KillsOf() return killsOf end

function UI.SelectTab(key)
  if key == "players" then key = "enemies" end -- 0.6 had one Players tab
  key = tabDef(key).key
  if key == "profile" then
    rememberPlace("profile", profileName)
  else
    wipe(history) -- picking a tab yourself starts over
  end
  currentTab = key
  offset = 0
  UI.Refresh()
end

-- 0.6 name: the Enemies/Friends dropdown is two tabs now
function UI.SetPlayerFilter(which) UI.SelectTab(which == "friends" and "friends" or "enemies") end

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
function UI.Dropdown(parent, width, itemsOrFn, get, set)
  -- itemsOrFn: the list, or a function returning it (for lists that change)
  local function list() return type(itemsOrFn) == "function" and itemsOrFn() or itemsOrFn end
  local ok, dd = pcall(CreateFrame, "DropdownButton", nil, parent, "WowStyle1DropdownTemplate")
  if ok and dd and dd.SetupMenu then
    dd:SetWidth(width)
    dd:SetupMenu(function(_, root)
      for _, it in ipairs(list()) do
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
    local items = list()
    if #items == 0 then return end
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
    for _, it in ipairs(list()) do if it[1] == get() then label:SetText(it[2]) end end
  end
  return f
end
UI.RefreshSettings = function() if ns.Options then ns.Options.Refresh() end end

---------------------------------------------------------------------------
-- window
---------------------------------------------------------------------------
-- a button's label, with the button resized to fit it (never below its minimum width).
-- Use this, not SetText, whenever a button's label changes after it was made.
function UI.SetButtonText(b, text)
  b:SetText(text)
  local w = b.minWidth or 0
  local fs = b.GetFontString and b:GetFontString()
  local tw = fs and fs.GetStringWidth and fs:GetStringWidth()
  if type(tw) == "number" then w = math.max(w, math.ceil(tw) + 24) end
  b:SetSize(w, 22)
end

-- w is the minimum width: a button always grows to fit its label
local function button(parent, w, text, onClick)
  local b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
  b.minWidth = w
  UI.SetButtonText(b, text)
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

  -- top row: search and Options (right)
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

  -- Leaderboard: which board (your friends or a shared group) and what you can do with it
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
  groupBar.new = button(groupBar, 90, L.BTN_GROUP_NEW, function() UI.NewGroup() end)
  groupBar.new:SetPoint("LEFT", groupBar.dropdown, "RIGHT", 8, 0)
  groupBar.invite = button(groupBar, 80, L.BTN_GROUP_INVITE, function(self) UI.GroupInviteMenu(self) end)
  groupBar.invite:SetPoint("LEFT", groupBar.dropdown, "RIGHT", 8, 0)
  groupBar.leave = button(groupBar, 70, L.BTN_GROUP_LEAVE, function() UI.LeaveGroup() end)
  groupBar.leave:SetPoint("LEFT", groupBar.invite, "RIGHT", 4, 0)
  groupBar.join = button(groupBar, 70, L.BTN_GROUP_JOIN, function() UI.JoinGroup() end)
  groupBar.join:SetPoint("LEFT", groupBar.dropdown, "RIGHT", 8, 0)
  groupBar.decline = button(groupBar, 70, L.BTN_GROUP_DECLINE, function() UI.LeaveGroup(true) end)
  groupBar.decline:SetPoint("LEFT", groupBar.join, "RIGHT", 4, 0)
  groupBar:Hide()

  -- Profile page: back to where you were (same spot as the group bar, which is hidden there)
  backButton = button(win, 70, "<", function() UI.Back() end)
  backButton:SetPoint("TOPLEFT", 16, -30)
  backButton:Hide()

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
        elseif e and not e.pending and playersView() then
          UI.RemovePlayer(e.name)
        elseif e and currentTab == "board" and currentGroup() then
          UI.RemoveFromGroup(e.key, e.name)
        end
        return
      end
      -- a click on a name opens their profile, on every tab
      if friendsView() and e and e.pending and not ns.viewSim then
        UI.TogglePick(e.name) -- online but never heard from: no profile yet, but you can add them
      elseif currentTab ~= "feed" and e and e.name and ns.Profile.KindOf(e.name) then
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
  -- two lines at most, so it never reaches the list above it
  if friendsHint.SetMaxLines then friendsHint:SetMaxLines(2) end

  -- hitlist bottom row: a hint on the left, [Clear hitlist][Share hitlist] on the right.
  -- (A player's note, kill list and the rest are on their profile: click them.)
  detail = CreateFrame("Frame", nil, win)
  -- above the page arrows (bottom right), so the two rows never touch
  detail:SetPoint("BOTTOMLEFT", 16, 30)
  detail:SetPoint("BOTTOMRIGHT", -16, 30)
  detail:SetHeight(46)
  detail.share = button(detail, 110, L.BTN_SHARE, function() UI.ShareHitlist() end)
  detail.share:SetPoint("BOTTOMRIGHT", 0, 0)
  detail.clear = button(detail, 100, L.BTN_CLEAR_HITLIST, function() UI.ClearHitlist() end)
  detail.clear:SetPoint("RIGHT", detail.share, "LEFT", -6, 0)
  detail.shareStatus = detail:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  detail.shareStatus:SetPoint("BOTTOMRIGHT", detail.share, "TOPRIGHT", 0, 4)
  -- the hint stops before the buttons; two lines at most
  detail.label = detail:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  detail.label:SetPoint("BOTTOMLEFT", 0, 4)
  detail.label:SetPoint("RIGHT", detail.clear, "LEFT", -16, 0)
  detail.label:SetJustifyH("LEFT")
  if detail.label.SetMaxLines then detail.label:SetMaxLines(2) end

  -- Profile tab: name on top, facts on the left, recent PvP on the right, controls below
  profile = CreateFrame("Frame", nil, win)
  profile:SetPoint("TOPLEFT", 20, -62) -- below the top row (search, Options)
  profile:SetPoint("BOTTOMRIGHT", -18, 28)
  profile:Hide()
  local function text(font, wrap)
    local fs = profile:CreateFontString(nil, "OVERLAY", font)
    fs:SetJustifyH("LEFT")
    fs:SetWordWrap(wrap and true or false)
    return fs
  end
  profile.title = text("GameFontNormalLarge")
  profile.title:SetPoint("TOPLEFT", 0, 0)
  profile.title:SetWidth(640)
  profile.sub = text("GameFontHighlightSmall")
  profile.sub:SetPoint("TOPLEFT", profile.title, "BOTTOMLEFT", 0, -4)
  profile.sub:SetWidth(640)
  profile.labels, profile.values = {}, {}
  for i = 1, PROFILE_LINES do
    local y = PROFILE_TOP - (i - 1) * 19
    local label = text("GameFontNormalSmall")
    label:SetPoint("TOPLEFT", 0, y)
    label:SetWidth(100)
    local value = text("GameFontHighlightSmall")
    value:SetPoint("TOPLEFT", 104, y)
    value:SetWidth(220)
    profile.labels[i], profile.values[i] = label, value
  end
  profile.recentHeader = text("GameFontNormalSmall")
  profile.recentHeader:SetPoint("TOPLEFT", 340, PROFILE_TOP)
  profile.recent = {}
  for i = 1, RECENT_LINES do
    local fs = text("GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", 340, PROFILE_TOP - i * 19)
    fs:SetWidth(320)
    profile.recent[i] = fs
  end
  -- your own profile: your character, top of the right column (recent PvP moves below it).
  -- Drag to turn it. Without model frames in this client, the page is the same as a friend's.
  local okModel, model = pcall(CreateFrame, "PlayerModel", nil, profile)
  if okModel and model then
    model:SetPoint("TOPLEFT", 340, MODEL_TOP)
    model:SetSize(320, MODEL_H)
    model:Hide()
    local function dress(self)
      pcall(self.SetUnit, self, "player")
      pcall(self.SetFacing, self, 0)
    end
    model.dress = dress
    model:SetScript("OnShow", dress) -- (the window reopened: a hidden model can lose its unit)
    model:EnableMouse(true)
    model:SetScript("OnMouseDown", function(self, mouse)
      if mouse == "LeftButton" then self.dragX = GetCursorPosition() end
    end)
    model:SetScript("OnMouseUp", function(self) self.dragX = nil end)
    model:SetScript("OnHide", function(self) self.dragX = nil end)
    model:SetScript("OnUpdate", function(self)
      if not self.dragX then return end
      local x = GetCursorPosition()
      local ok, facing = pcall(self.GetFacing, self)
      if ok and type(facing) == "number" then pcall(self.SetFacing, self, facing + (x - self.dragX) / 80) end
      self.dragX = x
    end)
    profile.model = model
    -- new gear or a new look (shapeshift, mount): show it
    local function changed()
      if model:IsVisible() then dress(model) end
    end
    ns.On("PLAYER_EQUIPMENT_CHANGED", changed)
    ns.OnUnit("UNIT_MODEL_CHANGED", "player", changed)
  end
  profile.footnote = text("GameFontDisableSmall")
  profile.footnote:SetPoint("TOPLEFT", 0, PROFILE_TOP - PROFILE_LINES * 19 - 6)
  profile.footnote:SetWidth(320)
  profile.footnote:SetWordWrap(true)
  profile.empty = profile:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  profile.empty:SetPoint("CENTER")
  profile.empty:SetWidth(500)
  profile.empty:SetText(L.PROFILE_EMPTY)

  local c = CreateFrame("Frame", nil, profile)
  c:SetPoint("BOTTOMLEFT", 0, 0)
  c:SetPoint("BOTTOMRIGHT", 0, 0)
  c:SetHeight(24)
  -- right to left: [action][Kill list], then the note box and Save (enemies on your hitlist)
  c.action = button(c, 130, L.BTN_WANTED_SET, function() UI.ProfileAction() end)
  c.action:SetPoint("BOTTOMRIGHT", 0, 0)
  c.kills = button(c, 90, L.BTN_KILL_LIST, function() UI.ShowKills(profileName) end)
  c.kills:SetPoint("RIGHT", c.action, "LEFT", -8, 0)
  c.editLabel = c:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  c.editLabel:SetPoint("BOTTOMLEFT", 0, 4)
  c.editLabel:SetText(L.NOTE)
  c.edit = CreateFrame("EditBox", nil, c, "InputBoxTemplate")
  c.edit:SetHeight(20)
  c.edit:SetPoint("LEFT", c.editLabel, "RIGHT", 10, 0)
  c.edit:SetAutoFocus(false)
  c.edit:SetMaxLetters(200)
  local function saveEdit()
    c.edit:ClearFocus()
    UI.ProfileSave(c.edit:GetText())
  end
  c.save = button(c, 60, L.SAVE, saveEdit)
  c.save:SetPoint("RIGHT", c.kills, "LEFT", -16, 0)
  c.edit:SetPoint("RIGHT", c.save, "LEFT", -10, 0)
  c.edit:SetScript("OnEnterPressed", saveEdit)
  c.edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  profile.controls = c

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

-- tab: "hitlist" | "board" | "enemies" | "friends" | "feed" | "profile" ("players" = enemies, as in 0.6)
function UI.Show(tab)
  if not win then build() end
  if tab == "players" then
    tab = "enemies"
  elseif tab == "settings" then
    UI.OpenSettings()
    return
  end
  if tab then
    local key = tabDef(tab).key
    -- (ShowProfile / ShowKills remember the way back themselves; opening a tab starts over)
    if key ~= "profile" and key ~= "kills" then wipe(history) end
    currentTab = key
    offset = 0
  end
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
  UI.Show("profile")
end

-- someone's kill list (opened from their profile); a friend online is asked for their own list
function UI.ShowKills(name)
  if not name then return end
  rememberPlace("kills", name)
  killsOf = name
  if ns.Profile.KindOf(name) == "friend" then ns.Kills.Ask(name) end
  UI.Show("kills")
end

-- the profile tab's player (for tests)
function UI.ProfileName() return profileName end
function UI.ProfileModel() return profile and profile.model end -- (for tests)

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
-- /fnf wanted [name | clear]: no name = your current target
local function wantedCommand(arg)
  local prefix = "|cff33ff99" .. L.ADDON .. "|r "
  if arg:lower() == "clear" then
    ns.Profile.SetWanted(nil)
    print(prefix .. L.WANTED_CLEARED)
    return
  end
  local name = ns.CleanName(arg)
  if not name then
    local info = ns.PvP.ReadEnemy("target")
    name = info and info.name
  end
  if not name then
    print(prefix .. L.WANTED_USAGE)
    return
  end
  -- a bare first name means the one enemy you know by it, if there's exactly one
  local players = ns.Data.RealRealm().players
  name = ns.Data.Resolve(players, name)
  print(prefix .. L.WANTED_SET:format(ns.Profile.SetWanted(name)))
  UI.Refresh()
end

-- "<group name> <rest>": the longest group name the text starts with
local function splitGroup(text)
  local best, rest
  for _, g in ipairs(ns.Groups.Mine()) do
    local n = ns.Groups.Label(g):lower()
    local t = text:lower()
    if (t == n or t:sub(1, #n + 1) == n .. " ") and (not best or #n > #best.name) then
      best, rest = g, strtrim(text:sub(#n + 1))
    end
  end
  return best, rest
end

-- /fnf groups [new <name> | invite <group> <friend> | join <group> | leave <group> | remove <group> <member>]
local function groupsCommand(arg)
  local sub, rest = arg:match("^(%S+)%s*(.*)$")
  sub = sub and sub:lower()
  if sub == "new" then
    return UI.CreateGroup(rest)
  end
  if sub == "invite" or sub == "join" or sub == "leave" or sub == "decline" or sub == "remove" then
    local g, more = splitGroup(rest)
    if not g then return say(L.GROUP_UNKNOWN:format(rest)) end
    boardView = g.id
    if sub == "invite" then return UI.InviteToGroup(more) end
    if sub == "join" then return UI.JoinGroup() end
    if sub == "decline" then return UI.LeaveGroup(true) end
    if sub == "leave" then
      local ok, reason = ns.Groups.Leave(g)
      if not ok then return why(reason) end
      boardView = "friends"
      return say(L.GROUP_LEFT:format(ns.Groups.Label(g)))
    end
    local key = ns.Groups.MemberByName(g, ns.CleanName(more) or more)
    if not key then return why("GROUP_NOT_MEMBER") end
    local ok, reason = ns.Groups.Remove(g, key)
    if not ok then return why(reason) end
    return say(L.GROUP_MEMBER_REMOVED:format(more, ns.Groups.Label(g)))
  end
  if not ns.Groups.MyKey() then return why("GROUP_NO_TAG") end
  local mine = ns.Groups.Mine()
  if #mine == 0 then say(L.GROUPS_NONE) end
  for _, g in ipairs(mine) do
    local names = {}
    for _, m in ipairs(ns.Groups.Members(g)) do
      names[#names + 1] = m.name .. (m.leader and (" " .. L.GROUP_LEADER_TAG) or "")
        .. (m.state == "invited" and (" " .. L.GROUP_INVITED_TAG) or "")
    end
    local tag = ns.Groups.MyState(g) == "invited" and ("  " .. L.GROUP_INVITED_TAG) or ""
    print("  " .. ns.Groups.Label(g) .. tag .. ": " .. table.concat(names, ", "))
  end
  print("  " .. L.GROUPS_USAGE)
end

SlashCmdList.FRIENDSANDFOES = function(msg)
  local raw = strtrim(msg or "") -- names keep their capitals
  msg = raw:lower()
  local prefix = "|cff33ff99" .. L.ADDON .. "|r "
  if msg == "" then
    UI.Toggle()
  elseif msg == "board" or msg == "leaderboard" then
    UI.Show("board")
  elseif msg == "groups" or msg:find("^groups ") then
    groupsCommand(strtrim(raw:sub(7)))
    UI.Refresh()
  elseif msg == "profile" or msg:find("^profile ") then
    local who = strtrim(raw:sub(8))
    UI.ShowProfile(who ~= "" and (ns.CleanName(who) or who) or ns.me)
  elseif msg == "wanted" or msg:find("^wanted ") then
    wantedCommand(strtrim(raw:sub(7)))
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
  elseif msg == "alerts" or msg:find("^alerts ") then
    groupCommand(strtrim(msg:sub(7))) -- your alert list
  elseif msg == "group" or msg:find("^group ") then
    groupCommand(strtrim(msg:sub(6))) -- (the old name of /fnf alerts)
  elseif msg == "sim" or msg:find("^sim ") then
    ns.Sim.Command(strtrim(msg:sub(4)))
  else
    print(prefix .. L.HELP)
  end
end
