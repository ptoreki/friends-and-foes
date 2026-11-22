local _, ns = ...
local L = ns.L

-- The Profile page: yours (with your character), a friend's, or an enemy's Wanted poster.
-- Built into the main window by UI.lua (UI.BuildProfile) and drawn by UI.RenderProfile.
-- Whose profile it shows is navigation, so UI.lua owns that: UI.ProfileName / SetProfileName.
local UI = ns.UI
local U = UI.Util -- shared helpers from UI.lua
local R, C = U.R, ns.Count
local victimsText, lastText, lvl, num, classIcon, kdText = U.victimsText, U.lastText, U.lvl, U.num, U.classIcon, U.kdText
local GREEN, CLASS_ICONS = U.GREEN, U.CLASS_ICONS
local button = UI.Button
local profile -- the page's frame

---------------------------------------------------------------------------
-- profile page
---------------------------------------------------------------------------
local PROFILE_LINES = 10
local RECENT_GATHER = 30 -- recent PvP entries gathered per profile (paged)
local RECENT_POOL = 12 -- most entries shown on one page (font strings built)
local RECENT_GAP = 4 -- between entries
local RECENT_LINE_H = 13 -- one wrapped line of an entry (small font), for the fallback estimate
local RECENT_MAX_LINES = 3 -- an entry wraps to at most this many lines
local RECENT_CHAR_W = 6 -- average glyph width, for the fallback estimate
-- your own / a friend's profile: two columns. Left: name, stats, recent PvP under them. Right: your
-- character, the full height of the page above the controls row.
local MODEL_X = 340 -- the right column (the page is 700 - 20 - 18 = 662 wide)
local PAGE_H = 380 -- the page: 470 - 62 - 28
local CONTROLS_H = 30 -- the controls row (24) + a gap: the model and recent PvP stay above it
local LEFT_W = 320 -- the left column's width
local LINE_H = 19 -- one stat / recent line
-- an enemy's profile: their Wanted poster in the left column, their facts and recent PvP beside it
local POSTER_W = 290
local POSTER_RIGHT = 300 -- where the column beside the poster starts
local POSTER_H = 360 -- (the slot under the Back button is 384 tall: 12 spare above and below)
local PORTRAIT_W, PORTRAIT_H = 170, 124
local FACE, SYMBOL = 112, 92 -- the painted face fills the portrait; a symbol sits smaller in it
local SEPIA = { 0.50, 0.38, 0.24, 1 } -- the portrait's print
local INK_PRINT = { 1, 0.84, 0.58 } -- the picture in it, tinted to match
local FACTION_CREST = 26 -- their faction (always the other one): small, in the corner
local countedFor -- whose profile numbers have counted up already (once per visit)
local PROFILE_TOP = -50 -- where the facts and recent PvP start, below the name lines
local DASH = "|cff888888-|r"

local function className(class)
  if not class then return "" end
  local names = LOCALIZED_CLASS_NAMES_MALE
  return (names and names[class]) or (class:sub(1, 1) .. class:sub(2):lower())
end

local function nameOr(name) return name and ns.ClassColored(name) or DASH end

-- "Level 35 Orc Mage"; an unknown level (lvl() gives "?") is left out: just "Orc Mage"
local function levelClass(level, what)
  if level == "?" then return what end
  return L.PROF_LEVEL_CLASS:format(level, what)
end


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
    view.title = ns.ClassColored(e.name, e.class) -- (their class crest is on the poster)
    view.class = e.class
    -- for the poster's symbols: race only once you've seen them yourself; their faction is the
    -- other one (enemies always are)
    local seenRec = (rec and rec.race) and rec or h
    view.race, view.raceName, view.sex = seenRec and seenRec.race, seenRec and seenRec.raceName, seenRec and seenRec.sex
    view.faction = (rec and rec.faction) or (ns.myFaction == "Horde" and "Alliance" or ns.myFaction == "Alliance" and "Horde" or nil)
    view.sub = levelClass(lvl(e), className(e.class)) .. (e.guild and ("  <" .. e.guild .. ">") or "")
    line(L.PROF_KILLS_ON_US, C(rec and rec.k))
    line(L.PROF_DIED_TO_US, C(rec and rec.d))
    line(L.PROF_ATTACKS, math.max(C(rec and rec.atk), C(h and h.attacks)))
    -- (who they killed: the Victims button; their hitlist row says it too)
    if h and h.sharedBy then
      local shared = {}
      for who in tostring(h.sharedBy):gmatch("[^,]+") do
        who = who:match("^%s*(.-)%s*$")
        if who ~= "" then shared[#shared + 1] = UI.LinkName(who, ns.ClassColored(who), e.name) end
      end
      line(L.PROF_SHARED_BY, #shared > 0 and table.concat(shared, ", ") or ns.ClassColored(h.sharedBy))
    end
    -- the bounty board: open contracts on them (only when there are any)
    local posted = {}
    for _, ct in ipairs(ns.Contracts.On(e.name)) do
      posted[#posted + 1] = L.CONTRACT_BY:format(ns.Contracts.MoneyText(ct.amount), ct.by == ns.me and L.PROF_ME or UI.LinkName(ct.by, ns.ClassColored(ct.by), e.name))
    end
    if #posted > 0 then line(L.PROF_CONTRACTS, table.concat(posted, ", ")) end
    local rank = ns.Bounty.Rank(e.name)
    view.rank = rank and (rank .. (ns.Bounty.OnRampage(e.name) and ("  -  " .. L.RAMPAGE_TAG) or "")) or nil
    if view.rank then line(L.PROF_STANDING, view.rank) end
    line(L.PROF_LAST_SEEN, lastText(e))
    view.onHitlist = h ~= nil
    view.recent = ns.Profile.Recent(e.name, true, RECENT_GATHER)
    -- the poster: their name in plain ink, "Level 42 Orc Hunter", guild, and the bounty
    view.name, view.guild = e.name, e.guild
    local what = view.raceName and (view.raceName .. " " .. className(e.class)) or className(e.class)
    view.posterSub = levelClass(lvl(e), what)
    view.bounty = ns.Bounty.Open(e.name) -- (Bounty.lua: what collecting on them would pay now)
    return view
  end

  -- you or a friend
  local isMe = kind == "me" and name == ns.me
  local _, myClass = UnitClass("player")
  local p = rec or { name = name, class = isMe and myClass or nil, level = isMe and UnitLevel("player") or nil, k = 0, d = 0 }
  view.title = classIcon(p.class) .. ns.ClassColored(p.name, p.class) .. (isMe and ("  |cff888888" .. L.YOU .. "|r") or "")
  view.sub = (isMe and L.PROF_ME or L.PROF_FRIEND) .."  \194\183  " .. levelClass(lvl(p), className(p.class))

  local board, row = ns.Profile.Board(), nil
  for _, r in ipairs(board) do if r.name == p.name then row = r end end
  local k = row and row.k or (p.sk or C(p.k))
  local d = row and row.d or (p.sd or C(p.d))
  local estimated = row and row.estimated or (not isMe and p.sk == nil)
  line(L.PROF_KILLS, num(k))
  line(L.PROF_DEATHS, num(d))
  line(L.PROF_KD, kdText(k, d, ns.Profile.KD(k, d)))
  -- the rank is the Friends tab's: same filtered list (low alts left out), so same position and total
  local shownBoard, shownRow = ns.Profile.HideLowAlts(board), nil
  for _, r in ipairs(shownBoard) do if r.name == p.name then shownRow = r end end
  line(L.PROF_RANK, shownRow and L.PROF_RANK_OF:format(shownRow.rank, #shownBoard) or DASH)
  -- bounties collected: yours with how many; a friend's as they report it (0.9 and later)
  -- (notoriety now, with the title it earns; yours with everything you ever claimed in grey)
  if isMe then
    local total, n = ns.Bounty.Mine()
    local all = ns.Bounty.AllTime()
    line(L.PROF_BOUNTIES, ns.Art.Points(total) .. "  \194\183  " .. ns.Bounty.Title(total)
      .. (all > 0 and ("  |cff888888" .. L.PROF_BOUNTIES_ALL:format(ns.Art.Points(all)) .. "|r") or ""))
    line(L.PROF_BOUNTIES_WEEK, ns.Art.Points(ns.Bounty.Week()))
  else
    line(L.PROF_BOUNTIES, p.sbt and (ns.Art.Points(p.sbt) .. "  \194\183  " .. ns.Bounty.Title(p.sbt)) or DASH)
    local wk = ns.Bounty.FriendWeek(p)
    line(L.PROF_BOUNTIES_WEEK, wk and ns.Art.Points(wk) or DASH)
  end
  local nem, times = ns.Profile.Nemesis(p.name)
  line(L.PROF_NEMESIS, nem and (isMe and L.PROF_NEMESIS_ME or L.PROF_NEMESIS_TEXT):format(UI.LinkName(nem.name, ns.ClassColored(nem.name, nem.class), p.name), times) or DASH)
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
  view.recent = ns.Profile.Recent(p.name, false, RECENT_GATHER)
  return view
end

local recentFor, recentPage -- whose recent PvP is paged, and which page

-- one Recent PvP entry: the time stays at the start
local function recentText(e)
  return "|cff888888" .. ns.Ago(e.t) .. "|r  " .. UI.Linkify(e.text, e, UI.ProfileName())
end

-- how tall an entry is when wrapped to `width`: measured on the hidden measuring string, or
-- (no GetStringHeight) estimated from the text length
local function entryHeight(text, width)
  local m = profile.recentMeasure
  m:SetWidth(width)
  m:SetText(text)
  local h = tonumber(m:GetStringHeight())
  if h and h > 0 then return h end
  local plain = ns.Plain(text)
  local lines = math.ceil(#plain / math.max(1, math.floor(width / RECENT_CHAR_W)))
  return math.min(RECENT_MAX_LINES, math.max(1, lines)) * RECENT_LINE_H
end

-- split the entries into pages: walk them, adding heights; a new page starts when the next entry
-- wouldn't fit in `avail` (or the page already holds the whole pool). { {first, last}, ... }
local function paginate(entries, width, avail)
  local pages, cur, used = {}, nil, 0
  for i, e in ipairs(entries) do
    local h = math.min(entryHeight(recentText(e), width), math.max(avail, RECENT_LINE_H))
    local need = used + (cur and RECENT_GAP or 0) + h
    if not cur or need > avail or (cur.last - cur.first + 1) >= RECENT_POOL then
      cur = { first = i, last = i }
      pages[#pages + 1] = cur
      used = h
    else
      cur.last = i
      used = need
    end
  end
  return pages
end

function UI.RenderProfile()
  -- the Profile tab opened directly, with nobody chosen yet: your own
  if not UI.ProfileName() then UI.SetProfileName(ns.me) end
  local profileName = UI.ProfileName()
  local v = UI.ProfileView(profileName)
  profile.empty:SetShown(v == nil)

  -- an enemy: their Wanted poster on the left; their facts and recent PvP in the column beside it
  local enemy = v ~= nil and v.kind == "enemy"
  local poster = enemy
  profile.ShowPoster(poster)
  -- the facts: under the name, or beside the poster at the top of the right-hand column (the
  -- name is on the poster then)
  local factsX = poster and POSTER_RIGHT or 0
  local factsTop = poster and 0 or PROFILE_TOP
  profile.title:SetShown(not poster)
  profile.sub:SetShown(not poster)
  for i = 1, PROFILE_LINES do
    local y = factsTop - (i - 1) * 19
    profile.labels[i]:ClearAllPoints()
    profile.labels[i]:SetPoint("TOPLEFT", factsX, y)
    profile.values[i]:ClearAllPoints()
    profile.values[i]:SetPoint("TOPLEFT", factsX + 104, y)
    profile.values[i]:SetWidth(poster and 250 or 220)
  end
  if poster then
    profile.factionIcon:SetShown(ns.Art.SetFactionIcon(profile.factionIcon, v.faction))
    profile.posterName:SetText(v.name or "")
    profile.posterSub:SetText(v.posterSub or "")
    profile.posterGuild:SetText(v.guild and ("<" .. v.guild .. ">") or "")
    -- the portrait: the game's painted face for their race and sex, else their race symbol,
    -- else their class crest; the class crest also sits on the portrait's corner when it
    -- isn't the portrait itself
    local icon = profile.portraitIcon
    local face = ns.Art.SetRacePortrait(icon, v.race, v.sex)
    local raceShown = face or ns.Art.SetRaceIcon(icon, v.race, v.sex)
    local side = face and FACE or SYMBOL
    icon:SetSize(side, side)
    local c = v.class and CLASS_ICON_TCOORDS and CLASS_ICON_TCOORDS[v.class]
    local classAsPortrait = not raceShown and c ~= nil
    if classAsPortrait then
      icon:SetTexture(CLASS_ICONS)
      icon:SetTexCoord(c[1], c[2], c[3], c[4])
    end
    icon:SetShown(raceShown or classAsPortrait)
    -- printed in the poster's sepia ink, not a bright game icon pasted on
    if icon.SetDesaturated then pcall(icon.SetDesaturated, icon, true) end
    icon:SetVertexColor(INK_PRINT[1], INK_PRINT[2], INK_PRINT[3])
    profile.badge:SetShown(c ~= nil and not classAsPortrait)
    if c then
      profile.badgeIcon:SetTexture(CLASS_ICONS)
      profile.badgeIcon:SetTexCoord(c[1], c[2], c[3], c[4])
    end
    ns.Art.StopCount(profile.bounty)
    profile.bounty:SetText(ns.Art.Points(v.bounty or 0))
    profile.rankLine:SetText(v.rank or "")
    profile.CenterPoster()
  end

  profile.title:SetText(v and v.title or "")
  profile.sub:SetText(v and v.sub or "")
  -- numbers count up once each time you open someone's profile
  local count = v ~= nil and countedFor ~= profileName
  if count then countedFor = profileName end
  for i = 1, PROFILE_LINES do
    local l = v and v.lines[i]
    local value = l and tostring(l[2]) or ""
    profile.labels[i]:SetText(l and l[1] or "")
    ns.Art.StopCount(profile.values[i])
    profile.values[i]:SetText(value)
    if count and value:match("^%d+$") then ns.Art.CountUp(profile.values[i], tonumber(value)) end
  end
  if count and poster then ns.Art.CountUp(profile.bounty, v.bounty, ns.Art.Points) end
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
  -- recent PvP: beside the poster, under the facts (right column); otherwise in the left column
  -- straight under the stats (and under the "estimated" footnote when there is one)
  local recentX, recentTop, recentW
  if poster then
    profile.footnote:ClearAllPoints()
    profile.footnote:SetPoint("TOPLEFT", 0, PROFILE_TOP - PROFILE_LINES * 19 - 6) -- (as built)
    recentX, recentTop, recentW = POSTER_RIGHT, -(PROFILE_LINES * 19 + 12), 360
  elseif not withModel then
    -- a friend (no model): recent PvP takes the right column, from the top (level with the header)
    local statsEnd = PROFILE_TOP - (v and #v.lines or PROFILE_LINES) * LINE_H
    profile.footnote:ClearAllPoints()
    profile.footnote:SetPoint("TOPLEFT", 0, statsEnd - 6)
    recentX, recentTop, recentW = MODEL_X, 0, 322
  else
    local used = v and #v.lines or PROFILE_LINES
    local statsEnd = PROFILE_TOP - used * LINE_H
    profile.footnote:ClearAllPoints()
    profile.footnote:SetPoint("TOPLEFT", 0, statsEnd - 6)
    recentX, recentW = 0, LEFT_W
    recentTop = statsEnd - 8 - ((v and v.estimated) and 26 or 0) -- (the footnote: up to 2 small lines)
  end
  profile.recentHeader:ClearAllPoints()
  profile.recentHeader:SetPoint("TOPLEFT", recentX, recentTop)
  profile.recentHeader:SetText(v and L.PROF_RECENT or "")

  -- the entries: wrapped in full, filled page by page into the room between the heading and the
  -- controls row (its top is -(PAGE_H - CONTROLS_H); the entries start 22 under the heading)
  if recentFor ~= profileName then recentFor, recentPage = profileName, 1 end
  local recent = v and v.recent or {}
  local entryTop = recentTop - 22
  local avail = PAGE_H - CONTROLS_H + entryTop
  local pages = {}
  if #recent > 0 then pages = paginate(recent, recentW, avail) end
  recentPage = math.max(1, math.min(recentPage, math.max(1, #pages)))
  local pg = pages[recentPage]
  local prev
  for i = 1, RECENT_POOL do
    local fs = profile.recent[i]
    local e = pg and recent[pg.first + i - 1]
    fs:ClearAllPoints()
    fs:SetWidth(recentW)
    if e and pg.first + i - 1 <= pg.last then
      if prev then fs:SetPoint("TOPLEFT", prev, "BOTTOMLEFT", 0, -RECENT_GAP)
      else fs:SetPoint("TOPLEFT", recentX, entryTop) end
      fs:SetText(recentText(e))
      fs:Show()
      prev = fs
    elseif i == 1 and v and #recent == 0 then
      fs:SetPoint("TOPLEFT", recentX, entryTop)
      fs:SetText("|cff888888" .. L.PROF_RECENT_NONE .. "|r")
      fs:Show()
    else
      fs:SetText("")
      fs:Hide()
    end
  end
  -- page arrows and "1/3", right end of the heading's row (level with the heading, so clear of
  -- the controls row in all three layouts); hidden with a single page
  local pager = profile.recentPager
  local multi = #pages > 1
  pager.page, pager.pages = recentPage, #pages
  pager.prev:ClearAllPoints()
  pager.prev:SetPoint("TOPLEFT", recentX + recentW - 46, recentTop + 2)
  pager.next:ClearAllPoints()
  pager.next:SetPoint("LEFT", pager.prev, "RIGHT", 2, 0)
  pager.label:SetText(multi and L.PROF_PAGE:format(recentPage, #pages) or "")
  pager.label:SetShown(multi)
  pager.prev:SetShown(multi)
  pager.next:SetShown(multi)
  pager.prev:SetEnabled(recentPage > 1)
  pager.next:SetEnabled(recentPage < #pages)
  profile.footnote:SetText(v and v.estimated and ("|cff888888" .. L.PROF_ESTIMATED .. "|r") or "")

  -- controls: Victims; a friend: pick for alerts; an enemy: post a bounty
  local c = profile.controls
  c:SetShown(v ~= nil)
  if not v then return end
  -- Victims (n): who they killed, how many in all
  UI.SetButtonText(c.kills, L.BTN_KILL_LIST_N:format(ns.Kills.Unique(ns.Kills.List(profileName))))
  c.kills:Show()
  c.stats:SetShown(v.isMe == true)
  c.killedby:SetShown(v.isMe == true)
  if v.isMe == true then UI.SetButtonText(c.killedby, L.BTN_KILLEDBY_N:format(#UI.KilledByList())) end
  c.post:SetShown(v.kind == "enemy")
  -- a friend: add to or take off your alert list
  local action = c.action
  local isFriend = v.kind == "friend"
  action:SetShown(isFriend)
  if isFriend then
    local tag = ns.Comm.TagFor(profileName)
    UI.SetButtonText(action, ns.Comm.IsPicked(tag) and L.BTN_PICK_OFF or L.BTN_PICK_ON)
    action:SetEnabled(tag ~= nil)
  end
  c.row:Layout() -- (the buttons that apply, side by side)
end

-- the profile's action button: a friend on or off your alert list
function UI.ProfileAction()
  local profileName = UI.ProfileName()
  if ns.Profile.KindOf(profileName) == "friend" then UI.TogglePick(profileName) end
end

-- leaving the Profile page: the numbers count up again next time
function UI.ResetProfileCount() countedFor = nil end

function UI.BuildProfile(win)
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
  -- an enemy's Wanted poster: the left column of their profile page. Light
  -- worn paper, all centred: WANTED / a framed portrait / DEAD OR ALIVE / their name / level,
  -- race, class, guild / their bounty. Their faction: a small crest in the corner (it's always
  -- the other one).
  local INK, SOFT, RED = ns.Art.INK, ns.Art.INK_SOFT, ns.Art.INK_RED
  -- the space for it: from just under the Back button (win TOPLEFT 16,-30, 22 tall -> bottom at
  -- -52; +6 gap = -58 = profile top (-62) + 4) down to the page's bottom edge (the controls row's
  -- bottom; its buttons are on the right, so this column may use the full height); the poster
  -- sits centred in it. Slot = 470 - 58 - 28 = 384 tall; POSTER_H 360 leaves 12 above and below.
  local slot = CreateFrame("Frame", nil, profile)
  slot:SetPoint("TOPLEFT", -8, 4)
  slot:SetPoint("BOTTOMLEFT", -8, 0)
  slot:SetWidth(POSTER_W)
  local pw = CreateFrame("Frame", nil, profile)
  pw:SetPoint("LEFT", slot, "LEFT", 0, 0) -- (vertical centre of the slot)
  pw:SetSize(POSTER_W, POSTER_H)
  ns.Art.Parchment(pw)
  -- top to bottom, each a set gap below the one before (UI.Column), centred on the poster; a
  -- spacer on top is sized when it's rendered so the whole block sits in the middle
  local col = UI.Column(pw, "TOP", 0, 0)
  local pad = CreateFrame("Frame", nil, pw)
  pad:SetSize(1, 1)
  col:Add(pad, 0)
  local function inked(font, size, color, gap)
    local fs = pw:CreateFontString(nil, "OVERLAY", font)
    if size then ns.Art.UseTitleFont(fs, size) end
    fs:SetTextColor(color[1], color[2], color[3])
    if fs.SetShadowColor then fs:SetShadowColor(0, 0, 0, 0) end -- (a shadow smudges on light paper)
    col:Add(fs, gap)
    fs:SetWidth(POSTER_W - 20)
    fs:SetJustifyH("CENTER")
    fs:SetWordWrap(false)
    return fs
  end
  profile.wanted = inked("GameFontNormalLarge", 34, INK, 10)
  profile.wanted:SetText(L.PROF_WANTED_POSTER)

  -- the portrait, printed on the poster: back to front, a soft shadow, a thick ink frame, a
  -- strip of paper, a fine ink line, then the picture - an old sepia print, darker towards its
  -- edges. In it: the game's painted face for their race, in the same sepia (or their race
  -- symbol, or their class crest if you haven't seen their race).
  local portrait = CreateFrame("Frame", nil, pw)
  portrait:SetSize(PORTRAIT_W, PORTRAIT_H)
  col:Add(portrait, 12)
  profile.portrait = portrait
  -- a rectangle centred on the picture, `grow` px bigger on each side (dx, dy: shifted)
  local function box(sub, grow, color, dx, dy)
    local t = pw:CreateTexture(nil, "BORDER", nil, sub)
    t:SetColorTexture(color[1], color[2], color[3], color[4] or 1)
    t:SetPoint("CENTER", portrait, "CENTER", dx or 0, dy or 0)
    t:SetSize(PORTRAIT_W + 2 * grow, PORTRAIT_H + 2 * grow)
    return t
  end
  box(0, 7, { 0.12, 0.07, 0.02, 0.35 }, 3, -4) -- shadow on the paper
  box(1, 7, { INK[1], INK[2], INK[3], 0.95 }) -- thick frame
  box(2, 4, { 0.80, 0.69, 0.48, 1 }) -- paper between the lines
  box(3, 1, { INK[1], INK[2], INK[3], 0.9 }) -- fine line
  box(4, 0, SEPIA) -- the print
  -- darker towards the print's edges (bands, strongest at the edge)
  for i, band in ipairs({ { 4, 0.30 }, { 10, 0.16 }, { 20, 0.08 } }) do
    for _, side in ipairs({ { "TOPLEFT", "TOPRIGHT", true }, { "BOTTOMLEFT", "BOTTOMRIGHT", true },
      { "TOPLEFT", "BOTTOMLEFT", false }, { "TOPRIGHT", "BOTTOMRIGHT", false } }) do
      local e = pw:CreateTexture(nil, "BORDER", nil, 4 + i)
      e:SetColorTexture(0.18, 0.10, 0.04, band[2])
      e:SetPoint(side[1], portrait, side[1])
      e:SetPoint(side[2], portrait, side[2])
      if side[3] then e:SetHeight(band[1]) else e:SetWidth(band[1]) end
    end
  end
  profile.portraitIcon = pw:CreateTexture(nil, "ARTWORK")
  profile.portraitIcon:SetPoint("CENTER", portrait, "CENTER")
  -- their class crest, pinned to the portrait's corner
  local badge = CreateFrame("Frame", nil, portrait)
  badge:SetSize(30, 30)
  badge:SetPoint("BOTTOMRIGHT", portrait, "BOTTOMRIGHT", 8, -8)
  badge:SetFrameLevel((portrait:GetFrameLevel() or 1) + 5)
  profile.badgeIcon = badge:CreateTexture(nil, "ARTWORK")
  profile.badgeIcon:SetAllPoints()
  profile.badge = badge

  profile.deadOrAlive = inked("GameFontNormal", 15, INK, 16) -- (clear of the frame and its shadow)
  profile.deadOrAlive:SetText(L.PROF_DEAD_OR_ALIVE)
  profile.posterName = inked("GameFontNormalLarge", 22, INK, 7)
  profile.posterSub = inked("GameFontHighlight", nil, SOFT, 6)
  profile.posterGuild = inked("GameFontHighlight", nil, SOFT, 3)
  profile.bountyLabel = inked("GameFontNormal", 15, INK, 10)
  profile.bountyLabel:SetText(L.PROF_BOUNTY)
  profile.bounty = inked("GameFontNormalLarge", 26, RED, 2)
  profile.rankLine = inked("GameFontNormalLarge", 18, { 0.36, 0.03, 0.02 }, 0) -- their rank (and "on a rampage")
  -- hover the bounty: how it's worked out
  local bountyTip = CreateFrame("Frame", nil, pw)
  bountyTip:SetPoint("TOPLEFT", profile.bountyLabel, "TOPLEFT")
  bountyTip:SetPoint("BOTTOMRIGHT", profile.bounty, "BOTTOMRIGHT")
  bountyTip:EnableMouse(true)
  bountyTip:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(L.PROF_BOUNTY, 1, 0.82, 0)
    GameTooltip:AddLine(L.TIP_BOUNTY:format(ns.Bounty.MURDER, ns.Bounty.ATTACK), 1, 1, 1, true)
    GameTooltip:Show()
  end)
  bountyTip:SetScript("OnLeave", function() GameTooltip:Hide() end)

  profile.factionIcon = pw:CreateTexture(nil, "ARTWORK")
  profile.factionIcon:SetSize(FACTION_CREST, FACTION_CREST)
  profile.factionIcon:SetPoint("TOPLEFT", 10, -10)
  profile.factionIcon:SetAlpha(0.75)

  function profile.ShowPoster(on) pw:SetShown(on) end
  -- Centre the stacked lines vertically on the parchment: equal empty paper above WANTED and
  -- below the last line. Optional lines (guild, rank) are hidden when empty, so they take no room.
  -- Heights come from the text itself (estimates when the client can't say).
  local ESTIMATE = { wanted = 34, deadOrAlive = 15, posterName = 22, posterSub = 13, posterGuild = 13,
    bountyLabel = 15, bounty = 26, rankLine = 18 }
  local STACK = { { "wanted", 10 }, { "portrait", 12 }, { "deadOrAlive", 16 }, { "posterName", 7 },
    { "posterSub", 6 }, { "posterGuild", 3 }, { "bountyLabel", 10 }, { "bounty", 2 }, { "rankLine", 0 } }
  function profile.CenterPoster()
    profile.posterGuild:SetShown((profile.posterGuild:GetText() or "") ~= "")
    profile.rankLine:SetShown((profile.rankLine:GetText() or "") ~= "")
    col:Layout()
    local total, first = 0, nil
    for _, item in ipairs(STACK) do
      local r = profile[item[1]]
      if not r.IsShown or r:IsShown() then
        local h = (item[1] == "portrait") and PORTRAIT_H or (r.GetStringHeight and r:GetStringHeight()) or 0
        if not h or h <= 0 then h = ESTIMATE[item[1]] or 0 end
        if first then total = total + item[2] else first = item[2] end
        total = total + h
      end
    end
    pad:SetHeight(math.max(1, math.floor((POSTER_H - total) / 2 - (first or 0))))
  end
  profile.poster = pw
  pw:Hide()

  profile.title = text("GameFontNormalLarge")
  ns.Art.UseTitleFont(profile.title, 20)
  profile.title:SetPoint("TOPLEFT", 0, 0)
  profile.title:SetWidth(640)
  profile.sub = text("GameFontHighlightSmall")
  profile.sub:SetPoint("TOPLEFT", profile.title, "BOTTOMLEFT", 0, -4)
  profile.sub:SetWidth(640)
  profile.labels, profile.values = {}, {}
  for i = 1, PROFILE_LINES do
    local label = text("GameFontNormalSmall")
    label:SetWidth(100)
    label:SetPoint("TOPLEFT", 0, PROFILE_TOP - (i - 1) * 19)
    local value = text("GameFontHighlightSmall")
    value:SetWidth(220)
    value:SetPoint("TOPLEFT", 104, PROFILE_TOP - (i - 1) * 19)
    profile.labels[i], profile.values[i] = label, value
    -- hover a label: what the number means (L.PROFILE_TIPS)
    local hover = CreateFrame("Frame", nil, profile)
    hover:SetAllPoints(label)
    hover:EnableMouse(true)
    hover:SetScript("OnEnter", function(self)
      local tip = L.PROFILE_TIPS[label:GetText() or ""]
      if not tip then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      GameTooltip:AddLine(label:GetText(), 1, 0.82, 0)
      GameTooltip:AddLine(tip, 1, 1, 1, true)
      -- the bounties on them: each one's note, if it has one
      if label:GetText() == L.PROF_CONTRACTS then
        for _, ct in ipairs(ns.Contracts.On(UI.ProfileName() or "")) do
          if ct.note then
            GameTooltip:AddLine(L.CONTRACT_BY:format(ns.Contracts.MoneyText(ct.amount), ct.by == ns.me and L.PROF_ME or ct.by)
              .. ": " .. L.CONTRACT_QUOTE:format(ct.note), 0.9, 0.9, 0.9, true)
          end
        end
      end
      GameTooltip:Show()
    end)
    hover:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  profile.recentHeader = text("GameFontNormalSmall")
  ns.Art.UseTitleFont(profile.recentHeader, 15)
  profile.recentHeader:SetPoint("TOPLEFT", 0, PROFILE_TOP)
  profile.recent = {}
  -- entries wrap in full (up to RECENT_MAX_LINES lines), stacked under each other (placed in RenderProfile)
  local function wrapped(fs)
    fs:SetWordWrap(true)
    fs:SetJustifyH("LEFT")
    if fs.SetMaxLines then fs:SetMaxLines(RECENT_MAX_LINES) end
    return fs
  end
  for i = 1, RECENT_POOL do
    local fs = wrapped(text("GameFontHighlightSmall"))
    fs:SetPoint("TOPLEFT", 340, PROFILE_TOP - i * 19)
    fs:SetWidth(320)
    profile.recent[i] = fs
  end
  UI.EnableNameLinks(profile) -- (names in Recent PvP are links to their profile)
  profile.recentMeasure = wrapped(text("GameFontHighlightSmall")) -- (never shown: measures entries)
  profile.recentMeasure:Hide()
  -- page arrows (the spellbook's) and "1/3" at the right end of the heading
  local pager = {}
  pager.label = text("GameFontDisableSmall")
  pager.label:SetJustifyH("RIGHT")
  local function arrow(dir)
    local b = CreateFrame("Button", nil, profile)
    b:SetSize(20, 20)
    local n = dir < 0 and "Prev" or "Next"
    b:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. n .. "Page-Up")
    b:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. n .. "Page-Down")
    b:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. n .. "Page-Disabled")
    b:SetScript("OnClick", function()
      recentPage = math.max(1, (recentPage or 1) + dir)
      UI.RenderProfile()
    end)
    return b
  end
  pager.prev, pager.next = arrow(-1), arrow(1)
  pager.label:SetPoint("RIGHT", pager.prev, "LEFT", -2, 0)
  pager.label:SetWidth(40)
  profile.recentPager = pager
  -- your own profile: your character, top of the right column (recent PvP moves below it).
  -- Drag to turn it. Without model frames in this client, the page is the same as a friend's.
  local okModel, model = pcall(CreateFrame, "PlayerModel", nil, profile)
  if okModel and model then
    -- the right column, top to just above the controls row
    model:SetPoint("TOPLEFT", MODEL_X, 0)
    model:SetPoint("BOTTOMRIGHT", 0, CONTROLS_H)
    model:Hide()
    -- whole body, head to feet: zoom 0 = whole body, camera pulled in close so the character fills
    -- its frame (0.9; ~0.8 is the closest that still fits the head for tall races - tune in game),
    -- no offset. Set again once the model has loaded and on every show, since the client resets
    -- the camera when a unit's model finishes loading
    local function frame(self)
      pcall(self.SetPortraitZoom, self, 0)
      pcall(self.SetCamDistanceScale, self, 0.9)
      pcall(self.SetPosition, self, 0, 0, 0)
    end
    local function dress(self)
      pcall(self.SetUnit, self, "player")
      pcall(self.SetFacing, self, 0)
      frame(self)
    end
    model.dress = dress
    model:SetScript("OnShow", dress) -- (the window reopened: a hidden model can lose its unit)
    pcall(model.SetScript, model, "OnModelLoaded", frame)
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
  -- right to left: [action (a friend: alert list)][Victims][Stats (you)][Post bounty (an enemy)]
  c.row = UI.Row(c, "BOTTOMRIGHT", 0, 0)
  c.action = c.row:Add(button(c, 130, L.BTN_PICK_ON, function() UI.ProfileAction() end))
  c.kills = c.row:Add(button(c, 90, L.BTN_KILL_LIST, function() UI.ShowKills(UI.ProfileName()) end), 8)
  -- your own profile: your stats (UIStats.lua)
  c.stats = c.row:Add(button(c, 70, L.BTN_STATS, function() UI.ShowStats() end), 8)
  c.killedby = c.row:Add(button(c, 90, L.BTN_KILLEDBY, function() UI.ShowKilledBy() end), 8)
  -- an enemy: put a bounty on them (the Bounty board)
  c.post = c.row:Add(button(c, 100, L.BTN_POST_BOUNTY, function() UI.PostBounty(UI.ProfileName()) end), 8)
  profile.controls = c
  return profile
end
