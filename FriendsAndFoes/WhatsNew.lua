local _, ns = ...
local L = ns.L

-- "What's new": a small popup with the patch notes, shown once over the main window the first time
-- it's opened after an update (FriendsAndFoesDB.seenVersion, per account), and any time with
-- /fnf new. Newest version first. Every release needs an entry here (a test checks).
local WhatsNew = {}
ns.WhatsNew = WhatsNew

WhatsNew.NOTES = {
  {
    version = "1.0.5",
    lines = { L.NEW_105_1, L.NEW_105_2, L.NEW_105_3, L.NEW_105_4 },
  },
  {
    version = "1.0.4",
    lines = { L.NEW_104_1, L.NEW_104_2, L.NEW_104_3 },
  },
  {
    version = "1.0.3",
    lines = { L.NEW_103_1, L.NEW_103_2, L.NEW_103_3 },
  },
  {
    version = "1.0.2",
    lines = { L.NEW_102_1, L.NEW_102_2, L.NEW_102_3, L.NEW_102_4 },
  },
  {
    version = "1.0.1",
    lines = {
      L.NEW_101_1, L.NEW_101_2, L.NEW_101_3, L.NEW_101_4,
      L.NEW_101_5, L.NEW_101_6, L.NEW_101_7,
    },
  },
  {
    version = "1.0.0",
    lines = {
      L.NEW_100_1, L.NEW_100_2, L.NEW_100_3, L.NEW_100_4,
      L.NEW_100_5, L.NEW_100_6, L.NEW_100_7, L.NEW_100_8,
    },
  },
}

local W, MAX_H = 420, 520
local frame

-- the notes for this version (nil when there are none); skipped versions' notes aren't shown
function WhatsNew.Entry()
  for _, e in ipairs(WhatsNew.NOTES) do
    if e.version == ns.VERSION then return e end
  end
end

local function bodyText(entries)
  local parts = {}
  for i, e in ipairs(entries) do
    parts[#parts + 1] = (i > 1 and "\n" or "") .. "|cffffd100" .. e.version .. "|r"
    for _, line in ipairs(e.lines) do parts[#parts + 1] = "|cffffd100\226\128\162|r " .. line end
  end
  return table.concat(parts, "\n")
end

local function build()
  local f = CreateFrame("Frame", "FriendsAndFoesWhatsNew", UIParent, "BackdropTemplate")
  f:SetSize(W, 200)
  f:SetPoint("CENTER", 0, 20)
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
  ns.UI.SolidBackground(f)
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -4, -4)
  tinsert(UISpecialFrames, "FriendsAndFoesWhatsNew")

  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  f.title:SetPoint("TOPLEFT", 20, -18)
  f.title:SetPoint("RIGHT", f, "RIGHT", -40, 0)
  f.title:SetJustifyH("LEFT")

  -- the notes sit in a scroll frame, so a long list never outgrows the screen
  f.scroll = CreateFrame("ScrollFrame", "FriendsAndFoesWhatsNewScroll", f, "UIPanelScrollFrameTemplate")
  f.scroll:SetPoint("TOPLEFT", 20, -50)
  f.child = CreateFrame("Frame", nil, f.scroll)
  f.child:SetSize(W - 70, 10)
  f.scroll:SetScrollChild(f.child)
  f.body = f.child:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  f.body:SetPoint("TOPLEFT", 0, 0)
  f.body:SetWidth(W - 70)
  f.body:SetJustifyH("LEFT")
  f.body:SetJustifyV("TOP")
  f.body:SetWordWrap(true)
  f.body:SetSpacing(3)

  f.ok = ns.UI.Button(f, 90, L.WHATSNEW_OK, function() f:Hide() end)
  f.ok:SetPoint("BOTTOMRIGHT", -20, 16)
  f:Hide()
  return f
end

-- entries: a list of { version, lines }
function WhatsNew.Show(entries)
  if not entries or #entries == 0 then return end
  frame = frame or build()
  local text = bodyText(entries)
  frame.title:SetText(L.WHATSNEW_TITLE:format(ns.VERSION))
  frame.body:SetText(text)
  local h = frame.body.GetStringHeight and frame.body:GetStringHeight()
  if type(h) ~= "number" or h <= 0 then -- (estimate: ~55 characters a line, 16 pixels each)
    local lines = 0
    for part in (text .. "\n"):gmatch("(.-)\n") do lines = lines + math.max(1, math.ceil(#part / 55)) end
    h = lines * 16
  end
  h = math.ceil(h) + 4
  local chrome = 50 + 56 -- title above, buttons below
  local shown = math.min(h, MAX_H - chrome)
  frame.child:SetSize(W - 70, h)
  frame.scroll:SetSize(W - 70, shown)
  frame:SetSize(W, shown + chrome)
  frame.shownHeight = shown + chrome -- (for tests)
  frame:Show()
  if frame.Raise then frame:Raise() end
end

function WhatsNew.IsShown() return frame ~= nil and frame:IsShown() end
function WhatsNew.Frame() return frame end
function WhatsNew.Text() return frame and frame.body and frame.body:GetText() end

local function inCombat()
  if not InCombatLockdown then return false end
  local ok, locked = pcall(InCombatLockdown)
  return ok and locked and true or false
end

-- called whenever the main window opens
function WhatsNew.MaybeShow()
  local db = FriendsAndFoesDB
  if db.seenVersion == ns.VERSION then return end
  -- a brand-new account: the tour is its welcome, no patch notes
  if not db.toured then db.seenVersion = ns.VERSION; return end
  if inCombat() or (ns.Tour and ns.Tour.IsShown()) then return end -- next time
  local e = WhatsNew.Entry()
  db.seenVersion = ns.VERSION
  if e then WhatsNew.Show({ e }) end
end

-- /fnf new: this version's notes, any time
function WhatsNew.ShowCurrent()
  WhatsNew.Show({ WhatsNew.Entry() or WhatsNew.NOTES[1] })
end
