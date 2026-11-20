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
-- a Wanted poster's paper: light and worn, for dark ink. A warm base (always), the game's
-- parchment on top, edges darkened like old paper, and a thin ink border. If the parchment
-- file is missing, the base alone still looks right.
---------------------------------------------------------------------------
local PARCHMENT = "Interface\\AchievementFrame\\UI-Achievement-Parchment-Horizontal"
local BASE = { 0.78, 0.68, 0.49, 1 }
local PAPER_TINT = { 1, 0.95, 0.84, 1 }
local EDGE = { 0.32, 0.2, 0.09, 0.9 }
local WORN = { 0.38, 0.25, 0.11 } -- the darkened edges: bands that fade towards the middle
local WORN_BANDS = { { 3, 0.35 }, { 8, 0.18 }, { 16, 0.08 } } -- { width, alpha }

-- ink colours for text on the paper
-- (dark enough to read on the light paper; the game fonts' drop shadow is taken off poster text)
Art.INK = { 0.16, 0.08, 0.03 }
Art.INK_SOFT = { 0.22, 0.12, 0.05 }
Art.INK_RED = { 0.55, 0.06, 0.03 } -- the bounty, in red like a real wanted poster

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
  local function edge(p1, p2, horizontal, size, color, layer, sub)
    local t = owner:CreateTexture(nil, layer or "BORDER", nil, sub)
    t:SetColorTexture(color[1], color[2], color[3], color[4])
    t:SetPoint(p1, area)
    t:SetPoint(p2, area)
    if horizontal then t:SetHeight(size) else t:SetWidth(size) end
    layers[#layers + 1] = t
  end
  local function allSides(size, color, layer, sub)
    edge("TOPLEFT", "TOPRIGHT", true, size, color, layer, sub)
    edge("BOTTOMLEFT", "BOTTOMRIGHT", true, size, color, layer, sub)
    edge("TOPLEFT", "BOTTOMLEFT", false, size, color, layer, sub)
    edge("TOPRIGHT", "BOTTOMRIGHT", false, size, color, layer, sub)
  end
  for i, band in ipairs(WORN_BANDS) do
    allSides(band[1], { WORN[1], WORN[2], WORN[3], band[2] }, "BACKGROUND", -7 + i)
  end
  allSides(1, EDGE)
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

---------------------------------------------------------------------------
-- symbols for a Wanted poster: race and faction (class uses the class crest, in UI.lua)
---------------------------------------------------------------------------
local function atlasExists(name)
  if not (C_Texture and C_Texture.GetAtlasInfo) then return false end
  local ok, info = pcall(C_Texture.GetAtlasInfo, name)
  return ok and info ~= nil
end

-- A small padlock for things that unlock later (the Stats page). One place for the choice: the
-- game's lock atlas when this client has it (checked at runtime), else the LFG lock file
-- (Interface\\LFGFrame\\UI-LFG-ICON-LOCK, in the classic client's files). Neither can be confirmed
-- from here, so a failed load just returns false and the caller hides the icon.
local LOCK_ATLAS, LOCK_FILE = "AdventureMapIcon-Lock", "Interface\\LFGFrame\\UI-LFG-ICON-LOCK"
function Art.SetLockIcon(tex)
  if atlasExists(LOCK_ATLAS) and tex.SetAtlas and pcall(tex.SetAtlas, tex, LOCK_ATLAS) then return true end
  local ok, loaded = pcall(tex.SetTexture, tex, LOCK_FILE)
  if not ok or loaded == false then return false end
  tex:SetTexCoord(0, 1, 0, 1)
  return true
end

local RACE_FILE = "Interface\\Glues\\CharacterCreate\\UI-CharacterCreate-Races"

-- the game's painted face for a race and sex: the portraits unit frames show when a 3D face
-- can't be drawn ("TemporaryPortrait-Male-Orc"). Referenced from the game's files, not copied.
-- race: the game's race file name ("Orc", "NightElf", "Scourge"); sex: 2 male, 3 female.
-- true if the texture now shows their face.
local PORTRAIT_FILE = "Interface\\CharacterFrame\\TemporaryPortrait-%s-%s"
function Art.SetRacePortrait(tex, race, sex)
  if type(race) ~= "string" or not race:match("^%a+$") then return false end
  local file = PORTRAIT_FILE:format(sex == 3 and "Female" or "Male", race)
  local ok, loaded = pcall(tex.SetTexture, tex, file)
  if not ok or loaded == false then return false end
  tex:SetTexCoord(0, 1, 0, 1)
  return true
end

-- race: the game's race file name ("Orc", "NightElf", "Scourge"); sex: 2 male, 3 female.
-- true if the texture now shows their race symbol.
function Art.SetRaceIcon(tex, race, sex)
  if type(race) ~= "string" or race == "" then return false end
  local s = sex == 3 and "female" or "male"
  local lower = race:lower()
  local names = { lower }
  if lower == "scourge" then names[2] = "undead" end
  for _, n in ipairs(names) do
    local atlas = "raceicon-" .. n .. "-" .. s
    if atlasExists(atlas) and tex.SetAtlas and pcall(tex.SetAtlas, tex, atlas) then return true end
  end
  local c = RACE_ICON_TCOORDS and RACE_ICON_TCOORDS[race:upper() .. "_" .. s:upper()]
  if type(c) == "table" and c[4] then
    tex:SetTexture(RACE_FILE)
    tex:SetTexCoord(c[1], c[2], c[3], c[4])
    return true
  end
  return false
end

local FACTION_FILE = { Horde = "Interface\\TargetingFrame\\UI-PVP-Horde", Alliance = "Interface\\TargetingFrame\\UI-PVP-Alliance" }

-- faction: "Horde" | "Alliance". true if the texture now shows its crest.
function Art.SetFactionIcon(tex, faction)
  local file = FACTION_FILE[faction]
  if not file then return false end
  tex:SetTexture(file)
  tex:SetTexCoord(0, 0.62, 0, 0.62) -- (the crest sits in the top-left of the file)
  return true
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

-- fmt (optional): turns a number into the text shown (default: the plain number)
function Art.CountUp(fs, target, fmt)
  target = tonumber(target)
  if not fs or not target or target < 2 or target ~= math.floor(target) then return end
  counting[fs] = { target = target, start = GetTime(), fmt = fmt or tostring }
  if not counter then
    counter = CreateFrame("Frame")
    counter:SetScript("OnUpdate", function(self)
      local now, left = GetTime(), false
      for f, c in pairs(counting) do
        local p = (now - c.start) / COUNT_TIME
        if p >= 1 or not f:IsVisible() then
          f:SetText(c.fmt(c.target))
          counting[f] = nil
        else
          f:SetText(c.fmt(math.floor(c.target * (1 - (1 - p) * (1 - p)))))
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

-- an icon inside a line of text. Height 0 = the font height, so the icon is as tall as the
-- line and sits level with the numbers whatever the font size. ICON_Y nudges every icon up (+)
-- or down (-) by the same amount if the game draws them off-centre.
Art.ICON_Y = 0
function Art.Icon(path)
  return "|T" .. path .. ":0:0:0:" .. Art.ICON_Y .. "|t"
end

-- 12500 -> "12,500" (never negative): notoriety points
function Art.Points(n)
  local s = tostring(ns.Count(n))
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  if out:sub(1, 1) == "," then out = out:sub(2) end
  return out
end

-- 12500 -> "12,500" with a gold coin after it (never negative)
function Art.Gold(n)
  local s = tostring(ns.Count(n))
  local out = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
  if out:sub(1, 1) == "," then out = out:sub(2) end
  return out .. " " .. Art.Icon("Interface\\MoneyFrame\\UI-GoldIcon")
end

---------------------------------------------------------------------------
-- window sounds: the game's own, like its Character window and spellbook.
-- Options: "Window sounds" (on by default), and the main "Sounds on".
---------------------------------------------------------------------------
local SOUNDS = {
  open = "IG_CHARACTER_INFO_OPEN",
  close = "IG_CHARACTER_INFO_CLOSE",
  page = "IG_ABILITY_PAGE_TURN", -- tab switch
}

-- window sounds are always on, like the game's own windows (the game's sound settings still
-- apply); only alert sounds have an on/off switch (Options -> Sounds)
function Art.Sound(what)
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
  return m[1] .. rank .. "|r " .. Art.Icon(m[2])
end
