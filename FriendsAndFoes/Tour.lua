local _, ns = ...
local L = ns.L

-- A three-page tour, shown over the window the first time it's opened on an account
-- (FriendsAndFoesDB.toured), and again with /fnf tour. Back / Next / Done; Escape closes it.
local Tour = {}
ns.Tour = Tour

local PAGES = {
  { L.TOUR_1_TITLE, L.TOUR_1_TEXT },
  { L.TOUR_2_TITLE, L.TOUR_2_TEXT },
  { L.TOUR_3_TITLE, L.TOUR_3_TEXT },
}
local W, H = 420, 210
local frame, page = nil, 1

local function render()
  frame.title:SetText(PAGES[page][1])
  frame.text:SetText(PAGES[page][2])
  frame.step:SetText(L.TOUR_STEP:format(page, #PAGES))
  frame.back:SetShown(page > 1)
  ns.UI.SetButtonText(frame.next, page < #PAGES and L.TOUR_NEXT or L.TOUR_DONE)
end

local function build(parent)
  local f = CreateFrame("Frame", "FriendsAndFoesTour", parent or UIParent, "BackdropTemplate")
  f:SetSize(W, H)
  f:SetPoint("CENTER", parent or UIParent, "CENTER", 0, 10)
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:EnableMouse(true) -- (clicks don't fall through to the window below)
  if f.SetBackdrop then
    f:SetBackdrop({
      bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background-Dark",
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = true, tileSize = 32, edgeSize = 32, insets = { left = 11, right = 12, top = 12, bottom = 11 },
    })
  end
  f.title = f:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  ns.Art.UseTitleFont(f.title, 22)
  f.text = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  f.text:SetWidth(W - 56)
  f.text:SetJustifyH("LEFT")
  f.text:SetSpacing(3)
  local col = ns.UI.Column(f, "TOP", 0, -22)
  col:Add(f.title)
  col:Add(f.text, 12)

  f.step = f:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  f.step:SetPoint("BOTTOMLEFT", 24, 24)
  local row = ns.UI.Row(f, "BOTTOMRIGHT", -20, 18)
  f.next = row:Add(ns.UI.Button(f, 90, L.TOUR_NEXT, function()
    if page < #PAGES then page = page + 1; render() else f:Hide() end
  end))
  f.back = row:Add(ns.UI.Button(f, 80, L.TOUR_BACK, function() page = math.max(1, page - 1); render() end), 6)
  f:SetScript("OnKeyDown", function(self, key)
    if key == "ESCAPE" then self:Hide() end
    if self.SetPropagateKeyboardInput then self:SetPropagateKeyboardInput(key ~= "ESCAPE") end
  end)
  if f.EnableKeyboard then f:EnableKeyboard(true) end
  f:Hide()
  return f
end

-- parent: the window to show it over
function Tour.Show(parent)
  frame = frame or build(parent)
  page = 1
  render()
  frame:Show()
end

function Tour.IsShown() return frame ~= nil and frame:IsShown() end
function Tour.Page() return page end
function Tour.Next() if frame then frame.next:GetScript("OnClick")() end end

-- the first time the window opens on this account
function Tour.MaybeShow(parent)
  if FriendsAndFoesDB.toured then return end
  FriendsAndFoesDB.toured = true
  Tour.Show(parent)
end
