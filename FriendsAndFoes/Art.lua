local _, ns = ...

-- The window's look: title font, aged parchment, soft fades, page sounds, medals.
-- Only what the game already has (its fonts, textures and sounds): nothing is bundled.
-- Everything here fails quietly: a missing font, texture or sound leaves the plain look.
local Art = {}
ns.Art = Art

---------------------------------------------------------------------------
-- title font: the game's quest-title font (Morpheus)
---------------------------------------------------------------------------
local TITLE_FONT = "Fonts\\MORPHEUS.TTF"
local fonts = {}

-- a font object at this size, or nil if the client doesn't have the font (keep the default then)
function Art.TitleFont(size)
  if fonts[size] ~= nil then return fonts[size] or nil end
  local ok, f = pcall(CreateFont, "FriendsAndFoesTitle" .. size)
  local okSet = ok and f and pcall(f.SetFont, f, TITLE_FONT, size, "")
  local path = okSet and f.GetFont and f:GetFont()
  fonts[size] = (type(path) == "string" and path ~= "") and f or false
  return fonts[size] or nil
end

-- give a font string the title font (keeps its own font if that fails)
function Art.UseTitleFont(fs, size)
  local f = Art.TitleFont(size)
  if f and fs and fs.SetFontObject then pcall(fs.SetFontObject, fs, f) end
end

---------------------------------------------------------------------------
-- aged parchment: a dark warm base (always), the game's parchment on top (dimmed so white
-- and gold text stay readable), and a thin gold edge. If the parchment file is missing, the
-- base alone still looks right.
---------------------------------------------------------------------------
local PARCHMENT = "Interface\\AchievementFrame\\UI-Achievement-Parchment-Horizontal"
local BASE = { 0.13, 0.09, 0.05, 0.92 }
local PAPER_TINT = { 0.42, 0.34, 0.24, 0.55 }
local EDGE = { 0.65, 0.52, 0.25, 0.55 }

-- owner: the frame it's drawn on (behind that frame's own text); area: the part it covers
-- (default: all of owner). Returns a handle with :SetShown(bool).
function Art.Parchment(owner, area)
  area = area or owner
  local layers = {}
  local base = owner:CreateTexture(nil, "BACKGROUND", nil, -8)
  base:SetAllPoints(area)
  base:SetColorTexture(BASE[1], BASE[2], BASE[3], BASE[4])
  layers[#layers + 1] = base
  local paper = owner:CreateTexture(nil, "BACKGROUND", nil, -7)
  paper:SetAllPoints(area)
  if pcall(paper.SetTexture, paper, PARCHMENT) then
    pcall(paper.SetVertexColor, paper, PAPER_TINT[1], PAPER_TINT[2], PAPER_TINT[3], PAPER_TINT[4])
    layers[#layers + 1] = paper
  else
    paper:Hide()
  end
  local function edge(p1, p2, horizontal)
    local t = owner:CreateTexture(nil, "BORDER")
    t:SetColorTexture(EDGE[1], EDGE[2], EDGE[3], EDGE[4])
    t:SetPoint(p1, area)
    t:SetPoint(p2, area)
    if horizontal then t:SetHeight(1) else t:SetWidth(1) end
    layers[#layers + 1] = t
  end
  edge("TOPLEFT", "TOPRIGHT", true)
  edge("BOTTOMLEFT", "BOTTOMRIGHT", true)
  edge("TOPLEFT", "BOTTOMLEFT", false)
  edge("TOPRIGHT", "BOTTOMRIGHT", false)
  local handle = { shown = true }
  function handle:SetShown(on)
    on = on and true or false
    if self.shown == on then return end
    self.shown = on
    for _, t in ipairs(layers) do t:SetShown(on) end
  end
  function handle:IsShown() return self.shown end
  return handle
end

-- a faint ruled line (ledger rows), in the parchment's ink colour
function Art.RuledLine(frame)
  local t = frame:CreateTexture(nil, "BACKGROUND", nil, -1)
  t:SetColorTexture(EDGE[1], EDGE[2], EDGE[3], 0.22)
  t:SetPoint("BOTTOMLEFT")
  t:SetPoint("BOTTOMRIGHT")
  t:SetHeight(1)
  return t
end

---------------------------------------------------------------------------
-- soft fade in (window open, tab switch)
---------------------------------------------------------------------------
local FADE = 0.15

function Art.FadeIn(frame)
  if not frame or not frame.CreateAnimationGroup then return end
  if not frame.fnfFade then
    local ok, group = pcall(frame.CreateAnimationGroup, frame)
    if not (ok and group) then return end
    local okA, a = pcall(group.CreateAnimation, group, "Alpha")
    if not (okA and a) then return end
    pcall(a.SetFromAlpha, a, 0)
    pcall(a.SetToAlpha, a, 1)
    pcall(a.SetDuration, a, FADE)
    pcall(a.SetSmoothing, a, "OUT")
    frame.fnfFade = group
  end
  pcall(frame.fnfFade.Stop, frame.fnfFade)
  pcall(frame.fnfFade.Play, frame.fnfFade)
end

-- numbers counting up to their value, once when a profile opens.
-- fs: the font string; target: the whole number it ends on; the text already shows it.
local COUNT_TIME = 0.4
local counting = {}
local counter

function Art.CountUp(fs, target)
  target = tonumber(target)
  if not fs or not target or target < 2 or target ~= math.floor(target) then return end
  counting[fs] = { target = target, start = GetTime() }
  if not counter then
    counter = CreateFrame("Frame")
    counter:SetScript("OnUpdate", function(self)
      local now, left = GetTime(), false
      for f, c in pairs(counting) do
        local p = (now - c.start) / COUNT_TIME
        if p >= 1 or not f:IsVisible() then
          f:SetText(tostring(c.target))
          counting[f] = nil
        else
          f:SetText(tostring(math.floor(c.target * (1 - (1 - p) * (1 - p)))))
          left = true
        end
      end
      if not left then self:Hide() end
    end)
  end
  counter:Show()
end

-- stop counting (the text is about to be replaced)
function Art.StopCount(fs) counting[fs] = nil end

---------------------------------------------------------------------------
-- window sounds: the game's own, like its Character window and spellbook.
-- Options: "Window sounds" (on by default), and the main "Sounds on".
---------------------------------------------------------------------------
local SOUNDS = {
  open = "IG_CHARACTER_INFO_OPEN",
  close = "IG_CHARACTER_INFO_CLOSE",
  page = "IG_ABILITY_PAGE_TURN", -- tab switch
  save = "IG_QUEST_LIST_SELECT", -- a note written
}

function Art.Sound(what)
  local s = ns.S and ns.S().sound
  if not s or s.enabled == false or s.ui == false then return end
  local id = SOUNDKIT and SOUNDKIT[SOUNDS[what] or ""]
  if id and PlaySound then pcall(PlaySound, id) end
end

---------------------------------------------------------------------------
-- medals for the top 3 (the game's gold, silver and copper coin icons)
---------------------------------------------------------------------------
local MEDALS = {
  { "|cffffd100", "Interface\\MoneyFrame\\UI-GoldIcon" },
  { "|cffd8d8e0", "Interface\\MoneyFrame\\UI-SilverIcon" },
  { "|cffd9884a", "Interface\\MoneyFrame\\UI-CopperIcon" },
}

-- "1" in gold with a gold coin after it; 4 and up plain
function Art.RankText(rank)
  if not rank then return "" end
  local m = MEDALS[rank]
  if not m then return tostring(rank) end
  return m[1] .. rank .. "|r |T" .. m[2] .. ":12:12|t"
end
