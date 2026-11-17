local _, ns = ...
local L = ns.L

-- A debug report you can copy (/fnf report, or the button in Options): everything a bug report
-- needs in one box - version, client, what works on this client, friends' versions, settings,
-- recent errors and the debug log. Select all and copy, then paste it wherever you report bugs.
-- No BattleTags or account details: only character names, which the report is about.
local Report = {}
ns.Report = Report

local LOG_LINES = 300 -- the newest debug log lines included
local ERROR_LINES = 50

local function onOff(v) return v and "on" or "off" end

function Report.Text()
  local out = {}
  local function add(s) out[#out + 1] = s end
  local db = FriendsAndFoesDB or {}
  local s = ns.S()
  local version, build, _, iface = "?", "?", nil, "?"
  if GetBuildInfo then version, build, _, iface = GetBuildInfo() end
  add("Friends & Foes " .. tostring(ns.VERSION) .. " report, " .. date("%Y-%m-%d %H:%M:%S"))
  add("client: " .. tostring(version) .. " (" .. tostring(build) .. "), interface " .. tostring(iface))
  add("you: " .. tostring(ns.me) .. ", " .. tostring(ns.myFaction))
  add("debug logging: " .. onOff(s.debug) .. ", errors this session: " .. tostring(ns.errors))

  add("")
  add("== works on this client ==")
  local caps = {}
  for k, v in pairs(ns.caps or {}) do caps[#caps + 1] = k .. "=" .. tostring(v) end
  table.sort(caps)
  add(table.concat(caps, ", "))
  add("language filter: " .. onOff(ns.Profile.FilterReady()))

  add("")
  add("== friends with the add-on ==")
  local rows = {}
  for _, p in pairs(ns.Data.RealRealm().players) do
    if p.friend and p.version then
      local note = ns.VersionNewer(ns.VERSION, p.version) and "  (older)" or ns.VersionNewer(p.version, ns.VERSION) and "  (newer)" or ""
      rows[#rows + 1] = p.name .. ": " .. p.version .. note .. ", last seen " .. ns.Ago(p.lastSeen)
    end
  end
  table.sort(rows)
  if #rows == 0 then add("(none heard from yet)") end
  for _, r in ipairs(rows) do add(r) end
  local online = ns.Comm.RosterNames and ns.Comm.RosterNames() or {}
  add("online now: " .. #online .. ", messages queued: " .. tostring(ns.Comm.QueuedCount and ns.Comm.QueuedCount() or "?"))
  add("alert list: " .. (ns.Comm.GroupActive() and "only picked friends" or "every friend"))

  add("")
  add("== settings ==")
  local share = {}
  for k, v in pairs(s.share or {}) do share[#share + 1] = k .. "=" .. onOff(v) end
  table.sort(share)
  add("sharing: " .. table.concat(share, ", "))
  add("sounds: " .. onOff(s.sound and s.sound.enabled) .. ", window sounds: " .. onOff(s.sound and s.sound.ui ~= false))

  add("")
  add("== errors (newest last) ==")
  local errs = db.errorLog or {}
  if #errs == 0 then add("(none)") end
  for i = math.max(1, #errs - ERROR_LINES + 1), #errs do add(errs[i]) end

  add("")
  add("== debug log (newest last) ==")
  local log = db.debugLog or {}
  if #log == 0 then add(s.debug and "(empty)" or "(debug logging is off: /fnf debug turns it on)") end
  for i = math.max(1, #log - LOG_LINES + 1), #log do add(log[i]) end
  -- (a "|" would start a colour code or link in the edit box)
  return (table.concat(out, "\n"):gsub("|", "/"))
end

---------------------------------------------------------------------------
-- the copy box
---------------------------------------------------------------------------
local box

local function build()
  local f = CreateFrame("Frame", "FriendsAndFoesReport", UIParent, "BackdropTemplate")
  f:SetSize(620, 440)
  f:SetPoint("CENTER")
  f:SetFrameStrata("FULLSCREEN_DIALOG")
  f:SetMovable(true)
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
  local title = f:CreateFontString(nil, "OVERLAY", "GameFontNormal")
  title:SetPoint("TOP", 0, -18)
  title:SetText(L.REPORT_TITLE)
  local hint = f:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  hint:SetPoint("TOP", title, "BOTTOM", 0, -6)
  hint:SetText(L.REPORT_HINT)

  local scroll = CreateFrame("ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", 22, -58)
  scroll:SetPoint("BOTTOMRIGHT", -40, 50)
  local edit = CreateFrame("EditBox", nil, scroll)
  edit:SetMultiLine(true)
  edit:SetAutoFocus(false)
  edit:SetFontObject("ChatFontSmall")
  edit:SetWidth(540)
  edit:SetScript("OnEscapePressed", function() f:Hide() end)
  -- read-only: typing puts the report back
  edit:SetScript("OnTextChanged", function(self, user)
    if user and f.text then self:SetText(f.text); self:HighlightText() end
  end)
  scroll:SetScrollChild(edit)
  f.edit = edit

  local close = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  close:SetSize(100, 22)
  close:SetPoint("BOTTOMRIGHT", -20, 18)
  close:SetText(CLOSE or "Close")
  close:SetScript("OnClick", function() f:Hide() end)
  local again = CreateFrame("Button", nil, f, "UIPanelButtonTemplate")
  again:SetSize(130, 22)
  again:SetPoint("RIGHT", close, "LEFT", -8, 0)
  again:SetText(L.REPORT_SELECT)
  again:SetScript("OnClick", function() edit:SetFocus(); edit:HighlightText() end)
  tinsert(UISpecialFrames, "FriendsAndFoesReport")
  return f
end

function Report.Show()
  box = box or build()
  box.text = Report.Text()
  box.edit:SetText(box.text)
  box:Show()
  box.edit:SetFocus()
  box.edit:HighlightText()
end
