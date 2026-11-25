local _, ns = ...
local L = ns.L

-- The window's building blocks: buttons that fit their label, dropdowns, the game's pop-ups
-- (prompt, yes/no), the window frame and its tabs, and a small layout helper. Shared by every
-- page of the window (UI.lua, UIProfile.lua) and the Options panel.
local UI = ns.UI or {}
ns.UI = UI

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
function UI.Button(parent, w, text, onClick)
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

-- The dark dialog art is partly see-through; put a solid fill under it so
-- nothing behind the window shows through.
function UI.SolidBackground(f)
  if not f.CreateTexture then return end
  local t = f:CreateTexture(nil, "BACKGROUND", nil, -8)
  t:SetPoint("TOPLEFT", 11, -12)
  t:SetPoint("BOTTOMRIGHT", -12, 11)
  t:SetColorTexture(0.05, 0.05, 0.05, 0.97)
  f.solidBg = t
  return t
end

-- The game's close (X) button closes through HideUIPanel, which the game blocks in combat for
-- add-on windows. Ours just hide their own window, which always works.
function UI.CloseOnClick(btn, frame)
  if btn and btn.SetScript then btn:SetScript("OnClick", function() frame:Hide() end) end
  return btn
end
function UI.CloseButton(frame)
  local close = CreateFrame("Button", nil, frame, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", -4, -4)
  return UI.CloseOnClick(close, frame)
end

-- Blizzard's plain window frame if available, else a dialog box
function UI.CreateWindow()
  local ok, f = pcall(CreateFrame, "Frame", "FriendsAndFoesFrame", UIParent, "BasicFrameTemplateWithInset")
  local templated = ok and f and type(f.TitleBg) == "table"
  if not templated then
    if not (ok and f) then f = CreateFrame("Frame", "FriendsAndFoesFrame", UIParent, "BackdropTemplate") end
    if f.SetBackdrop then f:SetBackdrop(FALLBACK_BACKDROP) end
    UI.CloseButton(f)
  else
    UI.CloseOnClick(f.CloseButton, f) -- (the template's own X)
  end
  local title = f:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
  if templated then title:SetPoint("CENTER", f.TitleBg, "CENTER", 0, 0) else title:SetPoint("TOP", 0, -14) end
  title:SetText(L.ADDON)
  return f
end

-- tabs hang below the window, like the Character or Social window
function UI.CreateTab(parent, key, label, prev, index)
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


---------------------------------------------------------------------------
-- layout: put things one under another (a column) or side by side (a row), each placed where
-- the previous one ends, instead of hand-counted offsets that break when a label or font
-- changes. Text sizes itself, so a column of text needs no heights at all.
--   local col = UI.Column(parent, "TOP", 0, -10)    -- first item's anchor on the parent
--   col:Add(title); col:Add(subtitle, 4)            -- gap above, in pixels
--   local row = UI.Row(parent, "BOTTOMRIGHT", 0, 0) -- right to left from the corner
--   row:Add(okButton); row:Add(cancelButton, 6)     -- gap before it
-- Items that show and hide: call :Layout() after changing which are shown. Hidden ones take no
-- room, and the next shown one moves up (or along) into their place.
-- `start`: what the first item hangs from (default: the parent, at `point`); a row can start
-- next to another frame, e.g. UI.Row(bar, "LEFT", 8, 0, dropdown) starts right of the dropdown.
---------------------------------------------------------------------------
local BELOW = { TOP = "BOTTOM", TOPLEFT = "BOTTOMLEFT", TOPRIGHT = "BOTTOMRIGHT" }

local function line(parent, point, x, y, start, place)
  local l = { items = {}, gaps = {}, shifts = {} }
  local function shown(r) return not r.IsShown or r:IsShown() end
  function l:Layout()
    local last
    for i, r in ipairs(self.items) do
      if shown(r) then
        r:ClearAllPoints()
        place(r, last, self.gaps[i] or 0, self.shifts[i] or 0)
        last = r
      end
    end
  end
  function l:Add(region, gap, shift)
    self.items[#self.items + 1] = region
    self.gaps[#self.items], self.shifts[#self.items] = gap, shift
    self:Layout()
    return region
  end
  return l
end

function UI.Column(parent, point, x, y, start)
  point = point or "TOPLEFT"
  return line(parent, point, x, y, start, function(r, last, gap, dx)
    if last then
      r:SetPoint(point, last, BELOW[point] or "BOTTOMLEFT", dx, -gap)
    elseif start then
      r:SetPoint(point, start, BELOW[point] or "BOTTOMLEFT", (x or 0) + dx, (y or 0) - gap)
    else
      r:SetPoint(point, parent, point, (x or 0) + dx, (y or 0) - gap)
    end
  end)
end

-- point: the corner the row starts from; it grows away from it (from a right corner: leftwards)
function UI.Row(parent, point, x, y, start)
  point = point or "LEFT"
  local leftwards = point:find("RIGHT") ~= nil
  return line(parent, point, x, y, start, function(r, last, gap)
    if last then
      if leftwards then r:SetPoint("RIGHT", last, "LEFT", -gap, 0) else r:SetPoint("LEFT", last, "RIGHT", gap, 0) end
    elseif start then
      -- x: how far from `start` (away from it)
      if leftwards then
        r:SetPoint("RIGHT", start, "LEFT", -((x or 0) + gap), y or 0)
      else
        r:SetPoint("LEFT", start, "RIGHT", (x or 0) + gap, y or 0)
      end
    else
      r:SetPoint(point, parent, point, x or 0, y or 0)
    end
  end)
end
