local _, ns = ...
local L = ns.L

-- The "Post a bounty" window: a small dialog with four boxes (player, amount, days, message), for
-- when there's no single line that says it all. Opened by the Bounty board's Post bounty button
-- (the player filled in from your target), by a profile's Post bounty button, and by /fnf bounty
-- with no amount. What happens on Post is UI.PostBountyNow (UI.lua), the same as /fnf bounty.
local UI = ns.UI
local W = 340

local win
local fields = {}

local function close() if win then win:Hide() end end

local function submit()
  if not win then return end
  local days = strtrim(fields.days:GetText() or "")
  local amount = strtrim(fields.amount:GetText() or "")
  if days ~= "" then amount = amount .. " " .. days .. "d" end
  if UI.PostBountyNow(fields.name:GetText(), amount, fields.note:GetText()) then close() end
end

local function labelled(parent, text, maxLetters, width)
  local label = parent:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  label:SetText(text)
  label:SetJustifyH("LEFT")
  local box = CreateFrame("EditBox", nil, parent, "InputBoxTemplate")
  box:SetSize(width or (W - 56), 20)
  box:SetAutoFocus(false)
  box:SetMaxLetters(maxLetters)
  box:SetScript("OnEscapePressed", function() close() end)
  box:SetScript("OnEnterPressed", submit)
  return label, box
end

local function build()
  local f = CreateFrame("Frame", "FriendsAndFoesBountyDialog", UIParent, "BackdropTemplate")
  f:SetSize(W, 300)
  f:SetPoint("CENTER", 0, 60)
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
  if UISpecialFrames then tinsert(UISpecialFrames, "FriendsAndFoesBountyDialog") end
  local x = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  x:SetPoint("TOPRIGHT", -4, -4)

  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  title:SetText(L.BOUNTY_DLG_TITLE)
  title:SetPoint("TOP", 0, -18)

  local col = UI.Column(f, "TOPLEFT", 28, -50)
  local specs = {
    { "name", L.BOUNTY_DLG_NAME, ns.Data.NAME_MAX },
    { "amount", L.BOUNTY_DLG_AMOUNT, 24 },
    { "days", L.BOUNTY_DLG_DAYS, 2, 60 },
    { "note", L.BOUNTY_DLG_NOTE, ns.Profile.NOTE_MAX },
  }
  for i, s in ipairs(specs) do
    local label, box = labelled(f, s[2], s[3], s[4])
    col:Add(label, i == 1 and 0 or 10)
    col:Add(box, 2, 6) -- (an edit box sits a little in from its left edge)
    fields[s[1]] = box
  end

  local row = UI.Row(f, "BOTTOMRIGHT", -24, 18)
  row:Add(UI.Button(f, 80, CANCEL or "Cancel", close))
  row:Add(UI.Button(f, 80, L.BTN_POST, submit), 6)
  return f
end

-- name: the player to fill in (nil: empty, you type it)
function UI.BountyDialog(name)
  if not win then win = build() end
  fields.name:SetText(name or "")
  fields.amount:SetText("")
  fields.days:SetText("")
  fields.note:SetText("")
  win:Show()
  local box = (name and name ~= "") and fields.amount or fields.name
  if box.SetFocus then box:SetFocus() end
end

function UI.Frames_Bounty() return win, fields end -- (for tests)
