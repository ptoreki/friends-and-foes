local _, ns = ...
local L = ns.L

-- The alert list window: who you exchange alerts with. Opened from Options (Friends & sharing ->
-- Alert list...) and with /fnf alerts. One tick box per friend account (by BattleTag; a friend's
-- characters are listed together). Nothing ticked: alerts from and to every friend with the
-- add-on. Anything ticked: only them. The list is stored by BattleTag (Comm.lua).
local UI = ns.UI
local W, ROW_H, ROWS = 330, 22, 12

local win
local rows = {}
local page = 0
local entries = {}

-- friend accounts the add-on knows: { tag, names = { ... }, online }
local function accounts()
  local byTag = {}
  local tags = FriendsAndFoesDB.friendTags or {}
  local function add(name, tag, online)
    if not (name and tag) or name == ns.me then return end
    local a = byTag[tag]
    if not a then
      a = { tag = tag, names = {}, seen = {} }
      byTag[tag] = a
    end
    if not a.seen[name] then
      a.seen[name] = true
      a.names[#a.names + 1] = name
    end
    if online then a.online = true end
  end
  for _, name in ipairs(ns.Comm.EveryoneNames()) do add(name, ns.Comm.TagFor(name), true) end
  local players = ns.Data.RealRealm().players
  for name, tag in pairs(tags) do
    local p = players[name]
    -- friends you've heard from (with the add-on), on your side
    if p and p.friend and ns.Data.OnOurSide(p) then add(name, tag, false) end
  end
  local list = {}
  for _, a in pairs(byTag) do
    table.sort(a.names)
    list[#list + 1] = a
  end
  table.sort(list, function(a, b)
    if (a.online or false) ~= (b.online or false) then return a.online == true end
    return a.names[1] < b.names[1]
  end)
  return list
end
UI.AlertAccounts = accounts -- (for tests)

local function refresh()
  if not (win and win:IsShown()) then return end
  entries = accounts()
  local pages = math.max(1, math.ceil(#entries / ROWS))
  if page >= pages then page = pages - 1 end
  local active = ns.Comm.GroupActive()
  win.sub:SetText(active and L.ALERTLIST_ACTIVE or L.ALERTLIST_ALL)
  for i, r in ipairs(rows) do
    local a = entries[page * ROWS + i]
    r.account = a
    if a then
      local names = {}
      for _, n in ipairs(a.names) do names[#names + 1] = ns.ClassColored(n) end
      r.label:SetText(table.concat(names, ", "))
      r.check:SetChecked(ns.Comm.IsPicked(a.tag))
      r:Show()
    else
      r:Hide()
    end
  end
  win.empty:SetShown(#entries == 0)
  win.everyone:SetEnabled(active)
  win.prev:SetShown(pages > 1)
  win.next:SetShown(pages > 1)
  win.prev:SetEnabled(page > 0)
  win.next:SetEnabled(page < pages - 1)
end
UI.RefreshAlertList = refresh

local function build()
  local f = CreateFrame("Frame", "FriendsAndFoesAlertList", UIParent, "BackdropTemplate")
  -- top: title + the explanation (up to 3 lines) = 96; bottom: the buttons = 50
  f:SetSize(W, 146 + ROWS * ROW_H)
  f:SetPoint("CENTER")
  f:SetFrameStrata("DIALOG")
  f:SetToplevel(true)
  f:SetMovable(true)
  f:SetClampedToScreen(true)
  f:EnableMouse(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", f.StartMoving)
  f:SetScript("OnDragStop", f.StopMovingOrSizing)
  if f.SetBackdrop then
    f:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
  end
  UI.SolidBackground(f)
  UI.CloseButton(f)
  tinsert(UISpecialFrames, "FriendsAndFoesAlertList")

  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  f.title:SetText(L.ALERTLIST_TITLE)
  f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.sub:SetWidth(W - 40)
  f.sub:SetJustifyH("LEFT")
  f.sub:SetWordWrap(true)
  local col = UI.Column(f, "TOPLEFT", 20, -18)
  col:Add(f.title)
  col:Add(f.sub, 6)

  for i = 1, ROWS do
    local r = CreateFrame("Frame", nil, f)
    r:SetSize(W - 40, ROW_H)
    -- the first row hangs below the explanation, however many lines it wraps to; the rest follow
    if i == 1 then
      r:SetPoint("TOPLEFT", f.sub, "BOTTOMLEFT", -4, -8)
    else
      r:SetPoint("TOPLEFT", rows[i - 1], "BOTTOMLEFT", 0, 0)
    end
    r.check = CreateFrame("CheckButton", nil, r, "UICheckButtonTemplate")
    r.check:SetSize(22, 22)
    r.check:SetPoint("LEFT", 0, 0)
    r.label = r:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    r.label:SetPoint("LEFT", r.check, "RIGHT", 4, 0)
    r.label:SetPoint("RIGHT", r, "RIGHT", 0, 0)
    r.label:SetJustifyH("LEFT")
    r.label:SetWordWrap(false)
    r.check:SetScript("OnClick", function()
      if r.account then
        ns.Comm.TogglePick(r.account.tag)
        if ns.UI.Refresh then ns.UI.Refresh() end
      end
      refresh()
    end)
    rows[i] = r
  end

  f.rows = rows -- (for tests)
  f.empty = f:CreateFontString(nil, "OVERLAY", "GameFontDisable")
  f.empty:SetPoint("TOPLEFT", f.sub, "BOTTOMLEFT", 0, -14)
  f.empty:SetWidth(W - 40)
  f.empty:SetJustifyH("LEFT")
  f.empty:SetText(L.ALERTLIST_EMPTY)

  -- bottom: [Everyone] on the left, page arrows on the right
  f.everyone = UI.Button(f, 110, L.ALERTLIST_EVERYONE, function()
    ns.Comm.ClearPicks()
    if ns.UI.Refresh then ns.UI.Refresh() end
    refresh()
  end)
  f.everyone:SetPoint("BOTTOMLEFT", 18, 16)
  local function arrow(dir)
    local b = CreateFrame("Button", nil, f)
    b:SetSize(24, 24)
    local n = dir < 0 and "Prev" or "Next"
    b:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. n .. "Page-Up")
    b:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. n .. "Page-Down")
    b:SetDisabledTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. n .. "Page-Disabled")
    b:SetScript("OnClick", function()
      page = math.max(0, page + dir)
      refresh()
    end)
    return b
  end
  f.next = arrow(1)
  f.next:SetPoint("BOTTOMRIGHT", -16, 16)
  f.prev = arrow(-1)
  f.prev:SetPoint("RIGHT", f.next, "LEFT", -4, 0)
  f:SetScript("OnShow", function() ns.Try("alert-list", refresh) end)
  f:Hide()
  return f
end

-- open (or close) the alert list window
function UI.ShowAlertList()
  if not win then win = build() end
  page = 0
  ns.Comm.RebuildRoster()
  win:Show()
  win:Raise()
  refresh()
end
function UI.AlertListWindow() return win end -- (for tests)
