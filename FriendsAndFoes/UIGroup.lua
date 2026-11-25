local _, ns = ...
local L = ns.L

-- The group window: everything about the shared group picked on the Friends tab, in one place,
-- docked to the right of the main window (drag it anywhere; it hides with the main window).
--   the group's name, who leads it, its members (joined or invited), its totals, and the
--   buttons that apply to you: Invite / Leave as a member, Join / Decline when invited,
--   Remove beside each member when you lead.
-- Opened with the Group button on the Friends tab; the tab itself just shows the board.
-- Every action goes through the same UI functions as before (UI.lua), so nothing changes in
-- what they do: confirmations, messages, rules.
local UI = ns.UI
local W = 290
local ROW_H = 22
local MAX_ROWS = 10 -- (a group has at most 10 members, invites included)

local win -- this window
local rows = {}

local function nameOf(member)
  local p = ns.Data.FindPlayer(member.name)
  return ns.ClassColored(member.name, p and p.class)
end

local function build(main)
  local f = CreateFrame("Frame", "FriendsAndFoesGroup", main, "BackdropTemplate")
  f:SetSize(W, 120 + MAX_ROWS * ROW_H)
  f:SetPoint("TOPLEFT", main, "TOPRIGHT", 6, -10)
  f:SetFrameStrata("DIALOG")
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

  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  ns.Art.UseTitleFont(f.title, 20)
  f.title:SetWidth(W - 60)
  f.title:SetWordWrap(false)
  f.sub = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  f.sub:SetWidth(W - 40)
  f.sub:SetJustifyH("LEFT")
  f.sub:SetWordWrap(true)
  local col = UI.Column(f, "TOPLEFT", 20, -18)
  col:Add(f.title)
  col:Add(f.sub, 4)

  -- members, one per line: name (class colour), then leader / invited / you; Remove on the right
  for i = 1, MAX_ROWS do
    local r = CreateFrame("Frame", nil, f)
    r:SetSize(W - 36, ROW_H)
    r.name = r:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    r.name:SetPoint("LEFT", 0, 0)
    r.name:SetWidth(W - 110)
    r.name:SetJustifyH("LEFT")
    r.name:SetWordWrap(false)
    r.remove = UI.Button(r, 60, L.BTN_GROUP_REMOVE, function() UI.RemoveFromGroup(r.key, r.memberName) end)
    r.remove:SetPoint("RIGHT", 0, 0)
    col:Add(r, i == 1 and 12 or 0)
    rows[i] = r
  end

  f.totals = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.totals:SetWidth(W - 40)
  f.totals:SetJustifyH("LEFT")
  f.totals:SetWordWrap(true)
  col:Add(f.totals, 10)
  f.col = col

  -- what you can do, bottom right: the buttons that apply line up (UI.Row:Layout)
  f.buttons = UI.Row(f, "BOTTOMRIGHT", -18, 16)
  f.leave = f.buttons:Add(UI.Button(f, 70, L.BTN_GROUP_LEAVE, function() UI.LeaveGroup() end))
  f.invite = f.buttons:Add(UI.Button(f, 80, L.BTN_GROUP_INVITE, function(self) UI.GroupInviteMenu(self) end), 6)
  f.decline = f.buttons:Add(UI.Button(f, 70, L.BTN_GROUP_DECLINE, function() UI.LeaveGroup(true) end))
  f.join = f.buttons:Add(UI.Button(f, 70, L.BTN_GROUP_JOIN, function() UI.JoinGroup() end), 6)
  tinsert(UISpecialFrames, "FriendsAndFoesGroup")
  f:Hide()
  return f
end

-- fill it in for the group picked on the Friends tab (closes if there's none any more)
function UI.RefreshGroupWindow()
  if not win or not win:IsShown() then return end
  local g = UI.CurrentGroup()
  if not g then win:Hide(); return end
  local G = ns.Groups
  local me, leader = G.MyKey(), G.Leader(g)
  local state = G.MyState(g)
  local members = G.Members(g)
  win.title:SetText(G.Label(g))
  local leaderName
  for _, m in ipairs(members) do if m.key == leader then leaderName = m.name end end
  win.sub:SetText(state == "invited" and L.GROUPWIN_INVITED
    or (leader == me and L.GROUPWIN_YOU_LEAD) or (leaderName and L.GROUPWIN_LED_BY:format(nameOf({ name = leaderName }))) or "")
  -- joined members first (leader on top), then invites
  table.sort(members, function(a, b)
    if (a.state == "invited") ~= (b.state == "invited") then return b.state == "invited" end
    if a.leader ~= b.leader then return a.leader end
    return a.name < b.name
  end)
  for i, r in ipairs(rows) do
    local m = members[i]
    r:SetShown(m ~= nil)
    if m then
      local tags = {}
      if m.key == me then tags[#tags + 1] = L.YOU end
      if m.leader then tags[#tags + 1] = "|cffffd100" .. L.GROUP_LEADER_TAG .. "|r" end
      if m.state == "invited" then tags[#tags + 1] = "|cff888888" .. L.GROUP_INVITED_TAG .. "|r" end
      r.name:SetText(nameOf(m) .. (#tags > 0 and ("  |cff888888" .. table.concat(tags, " ") .. "|r") or ""))
      r.key, r.memberName = m.key, m.name
      -- the leader removes others; your own way out is Leave
      r.remove:SetShown(leader == me and m.key ~= me and state == "in")
    end
  end
  win.totals:SetText(UI.GroupTotals(g))
  win.col:Layout() -- (hidden member lines take no room)
  win:SetHeight(140 + math.min(#members, MAX_ROWS) * ROW_H)
  win.leave:SetShown(state == "in")
  win.invite:SetShown(state == "in")
  win.join:SetShown(state == "invited")
  win.decline:SetShown(state == "invited")
  win.buttons:Layout()
end

-- above the main window AND its buttons: as a child of the main window it would otherwise sit
-- just above the window's background, under its buttons wherever the two overlap (a window near
-- the screen's right edge pushes this one back over it). Same strata, so the game's yes/no
-- pop-ups still come out on top.
local ABOVE_MAIN = 50
local function raise(main)
  local base = main and main.GetFrameLevel and main:GetFrameLevel() or 1
  win:SetFrameLevel(base + ABOVE_MAIN)
  if win.SetToplevel then win:SetToplevel(true) end -- (a click brings it to the front)
end

function UI.ShowGroupWindow(main)
  win = win or build(main)
  raise(main)
  win:Show()
  UI.RefreshGroupWindow()
end

function UI.HideGroupWindow()
  if win then win:Hide() end
end

function UI.ToggleGroupWindow(main)
  if win and win:IsShown() then win:Hide() else UI.ShowGroupWindow(main) end
end

function UI.GroupWindow() return win end -- (for tests)
