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
local PROFILE_LINES, RECENT_LINES = 10, 10
-- your own profile: your character above recent PvP, which then has room for fewer lines
local MODEL_TOP, MODEL_H, RECENT_LINES_ME = -40, 190, 5
-- an enemy's profile: their Wanted poster in the left column, their facts and recent PvP beside it
local POSTER_W = 290
local POSTER_RIGHT = 300 -- where the column beside the poster starts
local RECENT_LINES_POSTER = 7
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
    view.sub = L.PROF_LEVEL_CLASS:format(lvl(e), className(e.class)) .. (e.guild and ("  <" .. e.guild .. ">") or "")
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
    -- the poster: their name in plain ink, "Level 42 Orc Hunter", guild, and the bounty
    view.name, view.guild = e.name, e.guild
    local what = view.raceName and (view.raceName .. " " .. className(e.class)) or className(e.class)
    view.posterSub = L.PROF_LEVEL_CLASS:format(lvl(e), what)
    view.bounty = ns.Bounty.Open(e.name) -- (Bounty.lua: what collecting on them would pay now)
    return view
  end

  -- you or a friend
  local isMe = kind == "me" and name == ns.me
  local _, myClass = UnitClass("player")
  local p = rec or { name = name, class = isMe and myClass or nil, level = isMe and UnitLevel("player") or nil, k = 0, d = 0 }
  view.title = classIcon(p.class) .. ns.ClassColored(p.name, p.class) .. (isMe and ("  |cff888888" .. L.YOU .. "|r") or "")
  view.sub = (isMe and L.PROF_ME or L.PROF_FRIEND) .."  \194\183  " .. L.PROF_LEVEL_CLASS:format(lvl(p), className(p.class))

  local board, row = ns.Profile.Board(), nil
  for _, r in ipairs(board) do if r.name == p.name then row = r end end
  local k = row and row.k or (p.sk or C(p.k))
  local d = row and row.d or (p.sd or C(p.d))
  local estimated = row and row.estimated or (not isMe and p.sk == nil)
  line(L.PROF_KILLS, num(k))
  line(L.PROF_DEATHS, num(d))
  line(L.PROF_KD, kdText(k, d, ns.Profile.KD(k, d)))
  line(L.PROF_RANK, row and L.PROF_RANK_OF:format(row.rank, #board) or DASH)
  -- bounties collected: yours with how many; a friend's as they report it (0.9 and later)
  if isMe then
    local total, n = ns.Bounty.Mine()
    line(L.PROF_BOUNTIES, ns.Art.Gold(total) .. (n > 0 and ("  |cff888888" .. L.PROF_BOUNTIES_N:format(n) .. "|r") or ""))
  else
    line(L.PROF_BOUNTIES, p.sbt and ns.Art.Gold(p.sbt) or DASH)
  end
  local nem, times = ns.Profile.Nemesis(p.name)
  line(L.PROF_NEMESIS, nem and (isMe and L.PROF_NEMESIS_ME or L.PROF_NEMESIS_TEXT):format(ns.ClassColored(nem.name, nem.class), times) or DASH)
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
    profile.bounty:SetText(ns.Art.Gold(v.bounty or 0))
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
  if count and poster then ns.Art.CountUp(profile.bounty, v.bounty, ns.Art.Gold) end
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
  -- recent PvP: right-hand column; below your character on yours, below the facts beside a poster
  local recentX = poster and POSTER_RIGHT or 340
  local recentTop = (withModel and (MODEL_TOP - MODEL_H - 8)) or (poster and -(PROFILE_LINES * 19 + 12)) or PROFILE_TOP
  local recentLines = (withModel and RECENT_LINES_ME) or (poster and RECENT_LINES_POSTER) or RECENT_LINES
  profile.recentHeader:ClearAllPoints()
  profile.recentHeader:SetPoint("TOPLEFT", recentX, recentTop)
  for i = 1, RECENT_LINES do
    profile.recent[i]:ClearAllPoints()
    profile.recent[i]:SetPoint("TOPLEFT", recentX, recentTop - i * 19)
    profile.recent[i]:SetWidth(poster and 360 or 320)
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
  c.row:Layout()
  if editable and not c.edit:HasFocus() then c.edit:SetText(v.note or "") end
  -- Kill list (n): who they killed, how many in all
  UI.SetButtonText(c.kills, L.BTN_KILL_LIST_N:format(ns.Kills.Total(ns.Kills.List(profileName))))
  c.kills:Show()
  local action = c.action
  action:Show()
  action:Enable()
  if v.isMe then
    -- only there when you have a most wanted to clear (you set one on an enemy's profile)
    UI.SetButtonText(action, L.BTN_WANTED_CLEAR)
    action:SetShown(ns.Profile.Wanted() ~= nil)
  elseif v.kind == "enemy" then
    local isWanted = ns.Profile.Wanted() == profileName
    UI.SetButtonText(action, isWanted and L.BTN_WANTED_CLEAR or L.BTN_WANTED_SET)
  else
    local tag = ns.Comm.TagFor(profileName)
    UI.SetButtonText(action, ns.Comm.IsPicked(tag) and L.BTN_PICK_OFF or L.BTN_PICK_ON)
    action:SetEnabled(tag ~= nil and not ns.viewSim and profileName ~= ns.me)
  end
  c.row:Layout() -- (the action button may have come or gone)
end

function UI.ProfileAction()
  local profileName = UI.ProfileName()
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
  local profileName = UI.ProfileName()
  local kind = ns.Profile.KindOf(profileName)
  if kind == "enemy" then
    local h = R().hitlist[ns.Data.Resolve(R().hitlist, profileName)]
    if h then h.note = (text and text ~= "") and text or nil end
  end
  UI.Refresh()
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
  -- an enemy's Wanted poster: the left column of their profile page, above the note box. Light
  -- worn paper, all centred: WANTED / a framed portrait / DEAD OR ALIVE / their name / level,
  -- race, class, guild / their bounty. Their faction: a small crest in the corner (it's always
  -- the other one).
  local INK, SOFT, RED = ns.Art.INK, ns.Art.INK_SOFT, ns.Art.INK_RED
  local pw = CreateFrame("Frame", nil, profile)
  pw:SetPoint("TOPLEFT", -8, 8)
  pw:SetPoint("BOTTOMLEFT", -8, 32)
  pw:SetWidth(POSTER_W)
  ns.Art.Parchment(pw)
  -- top to bottom, each a set gap below the one before (UI.Column), centred on the poster
  local col = UI.Column(pw, "TOP", 0, 0)
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
  profile.bountyLabel = inked("GameFontNormalSmall", 13, SOFT, 12)
  profile.bountyLabel:SetText(L.PROF_BOUNTY)
  profile.bounty = inked("GameFontNormalLarge", 26, RED, 3)
  -- hover the bounty: how it's worked out
  local bountyTip = CreateFrame("Frame", nil, pw)
  bountyTip:SetPoint("TOPLEFT", profile.bountyLabel, "TOPLEFT")
  bountyTip:SetPoint("BOTTOMRIGHT", profile.bounty, "BOTTOMRIGHT")
  bountyTip:EnableMouse(true)
  bountyTip:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:AddLine(L.PROF_BOUNTY, 1, 0.82, 0)
    GameTooltip:AddLine(L.TIP_BOUNTY:format(ns.Bounty.MURDER, ns.Bounty.ATTACK, ns.Bounty.WANTED), 1, 1, 1, true)
    GameTooltip:Show()
  end)
  bountyTip:SetScript("OnLeave", function() GameTooltip:Hide() end)

  profile.factionIcon = pw:CreateTexture(nil, "ARTWORK")
  profile.factionIcon:SetSize(FACTION_CREST, FACTION_CREST)
  profile.factionIcon:SetPoint("TOPLEFT", 10, -10)
  profile.factionIcon:SetAlpha(0.75)

  function profile.ShowPoster(on) pw:SetShown(on) end
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
      GameTooltip:Show()
    end)
    hover:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  profile.recentHeader = text("GameFontNormalSmall")
  ns.Art.UseTitleFont(profile.recentHeader, 15)
  profile.recentHeader:SetPoint("TOPLEFT", 340, PROFILE_TOP)
  profile.recent = {}
  for i = 1, RECENT_LINES do
    local fs = text("GameFontHighlightSmall")
    fs:SetPoint("TOPLEFT", 340, PROFILE_TOP - i * 19)
    fs:SetWidth(320)
    fs:SetWordWrap(false)
    profile.recent[i] = fs
    -- a line cut short ("...") shows in full on hover
    local hover = CreateFrame("Frame", nil, profile)
    hover:SetAllPoints(fs)
    hover:EnableMouse(true)
    hover:SetScript("OnEnter", function(self)
      local full = fs:GetText()
      if not full or full == "" or not (fs.IsTruncated and fs:IsTruncated()) then return end
      GameTooltip:SetOwner(self, "ANCHOR_TOP")
      GameTooltip:AddLine(full, 1, 1, 1, true)
      GameTooltip:Show()
    end)
    hover:SetScript("OnLeave", function() GameTooltip:Hide() end)
  end
  -- your own profile: your character, top of the right column (recent PvP moves below it).
  -- Drag to turn it. Without model frames in this client, the page is the same as a friend's.
  local okModel, model = pcall(CreateFrame, "PlayerModel", nil, profile)
  if okModel and model then
    model:SetPoint("TOPLEFT", 340, MODEL_TOP)
    model:SetSize(320, MODEL_H)
    model:Hide()
    -- head-and-shoulders framing (0 = whole body, 1 = face only); set again once the model
    -- has loaded, since the client resets the camera when a unit's model finishes loading
    local function frame(self)
      pcall(self.SetPortraitZoom, self, 0.6)
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
  -- right to left: [action][Kill list], then the note box and Save (enemies on your hitlist)
  c.row = UI.Row(c, "BOTTOMRIGHT", 0, 0)
  c.action = c.row:Add(button(c, 130, L.BTN_WANTED_SET, function() UI.ProfileAction() end))
  c.kills = c.row:Add(button(c, 90, L.BTN_KILL_LIST, function() UI.ShowKills(UI.ProfileName()) end), 8)
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
    ns.Art.Sound("save")
    UI.ProfileSave(c.edit:GetText())
  end
  c.save = c.row:Add(button(c, 60, L.SAVE, saveEdit), 16)
  c.edit:SetPoint("RIGHT", c.save, "LEFT", -10, 0)
  c.edit:SetScript("OnEnterPressed", saveEdit)
  c.edit:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  profile.controls = c
  return profile
end
