local _, ns = ...
local L = ns.L

-- The Stats page: yours only, opened from your own profile's Stats button (UI.ShowStats), shown
-- inside the tab with Back. Top to bottom: the character, three headline tiles, then three columns
-- (When you hunt / Kills by level gap / Top zones), and a footnote. All the numbers come from
-- Stats.lua; nothing here is ever sent to anyone.
local UI = ns.UI

local page
local PAGE_W = 662
local PAGE_H = 380 -- (470 - 62 - 28)
local FOOT_H, FOOT_GAP = 12, 30 -- the footnote's line, and the space kept clear above it
local TILE_GAP, TILE_H, TILE_TOP = 10, 76, -48
local TILE_COLUMN_GAP = 16 -- tiles to the columns' headers
local COL_GAP = 16
local COL_W = math.floor((PAGE_W - 2 * COL_GAP) / 3)
local COL_TOP = TILE_TOP - TILE_H - TILE_COLUMN_GAP -- the columns' gold headers
local HEADER_GAP = 24 -- header top to the first row's top
local ROW_H, ROWS = 24, 5 -- (the bars)
-- the rows are spread so the last one ends FOOT_GAP above the footnote
local ROWS_TOP = COL_TOP - HEADER_GAP
local ROW_STEP = math.floor((-(-PAGE_H + FOOT_H + FOOT_GAP) + ROWS_TOP - ROW_H) / (ROWS - 1))
local DIM = "|cff888888"
local DASH = "-"
-- the level-gap ramp, mildest to most dangerous
local TIER_COLORS = {
  grey = { 0.50, 0.50, 0.50 }, lower = { 0.55, 0.55, 0.45 }, even = { 0.85, 0.70, 0.25 },
  higher = { 0.90, 0.45, 0.15 }, skull = { 0.80, 0.15, 0.10 },
}
local ZONE_COLOR = { 0.35, 0.50, 0.70 }
local FILL_ALPHA = 0.7
local GAP_ORDER = { "skull", "higher", "even", "lower", "grey" } -- (most dangerous first)

-- "4/5 kills" while a stat is still locked behind a minimum, else nil
local function progress(have, want) return have < want and L.STATS_PROGRESS:format(have, want) or nil end
local FADED = 0.4 -- the skeleton charts, and the value of a locked stat

local function percent(n, total) return total > 0 and math.floor(n * 100 / total + 0.5) or 0 end

-- What the page shows:
--   sub     the character (class-coloured name, level)
--   tiles   { { big, label, tip, dim, tipTitle, extra, locked }, ... } three headline tiles (locked: the
--           progress text "4/5 kills" while it waits for enough kills; the extra line shows it)
--   hunt    { { label, value, dim, locked, tip }, ... } "When you hunt" (locked as above)
--   gap     { { label, n, color, countText, tip }, ... } Skull to Grey
--   zones   { { name, n, color, countText }, ... } up to 5
--   empty   nothing logged for this character yet (the charts show as faded skeletons)
function UI.StatsView()
  local s = ns.Stats.Compute()
  local v = { empty = s.n == 0 }
  local _, class = UnitClass("player")
  v.sub = ns.ClassColored(ns.me, class) .. "  " .. DIM .. L.STATS_LEVEL_OF:format(UnitLevel("player") or 0) .. "|r"

  local cur, best = ns.Stats.Streaks()
  local lvlLock = progress(s.levelN, ns.Stats.MIN_LEVELS)
  -- { big text, label (line 1), hover text, dim (not enough kills yet), hover title, extra (line 2) }
  v.tiles = {
    { tostring(s.n), L.STATS_KILLS, L.STATS_TIP_KILLS, false, L.STATS_KILLS, "" },
    { tostring(best), L.STATS_BEST_STREAK, L.STATS_TIP_STREAK, false, L.STATS_BEST_STREAK, L.STATS_NOW:format(cur) },
    { s.avgLevel and L.STATS_LEVEL_FMT:format(s.avgLevel) or DASH,
      L.STATS_AVG_LEVEL, L.STATS_TIP_AVG .. (lvlLock and (" " .. L.STATS_LOCK_AVG:format(ns.Stats.MIN_LEVELS)) or ""),
      s.avgLevel == nil, L.STATS_AVG_LEVEL, s.avgLevel and ns.Stats.GapText(s.avgGap) or lvlLock or "", lvlLock },
  }

  local busyLock = progress(s.n, ns.Stats.MIN_BUSY)
  local busyTip = busyLock and L.STATS_LOCK_BUSY:format(ns.Stats.MIN_BUSY) or nil
  v.hunt = {
    { L.STATS_TODAY, tostring(s.today) },
    { L.STATS_WEEK, tostring(s.week) },
    { L.STATS_MONTH, tostring(s.month) },
    { L.STATS_BUSY_DAY, s.busyDay and L.STATS_DAYS[s.busyDay] or busyLock or DASH, s.busyDay == nil, busyLock, busyTip },
    { L.STATS_BUSY_HOUR, s.busyHour and L.STATS_HOUR:format(s.busyHour, (s.busyHour + 1) % 24) or busyLock or DASH, s.busyHour == nil, busyLock, busyTip },
  }

  v.gap = {}
  for _, tier in ipairs(GAP_ORDER) do
    local n = s.tiers[tier]
    v.gap[#v.gap + 1] = { L["STATS_TIER_" .. tier:upper()], n, TIER_COLORS[tier],
      n == 0 and "0" or L.STATS_COUNT:format(n, percent(n, s.n)), L.STATS_TIER_TIPS[tier] }
  end
  v.zones = {}
  for _, z in ipairs(s.zones) do
    v.zones[#v.zones + 1] = { z.name, z.n, ZONE_COLOR, L.STATS_COUNT:format(z.n, percent(z.n, s.n)) }
  end
  v.stats = s
  return v
end

local function tooltip(owner, title, tip)
  if not tip then return end
  GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
  GameTooltip:AddLine(title, 1, 0.82, 0)
  GameTooltip:AddLine(tip, 1, 1, 1, true)
  GameTooltip:Show()
end

local function hoverable(f, getTitleTip)
  f:EnableMouse(true)
  f:SetScript("OnEnter", function(self) tooltip(self, getTitleTip()) end)
  f:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

-- a column: gold header, then ROWS rows (x: its left edge)
local function newColumn(x)
  local col = { rows = {} }
  col.header = page:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
  col.header:SetPoint("TOPLEFT", x, COL_TOP)
  col.header:SetJustifyH("LEFT")
  col.x = x
  return col
end

-- label left, value right (the "When you hunt" rows)
local function addTextRows(col)
  for i = 1, ROWS do
    local y = ROWS_TOP - (i - 1) * ROW_STEP
    local row = {}
    row.label = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.label:SetPoint("TOPLEFT", col.x, y)
    row.label:SetJustifyH("LEFT")
    row.value = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.value:SetPoint("TOPRIGHT", col.x + COL_W, y)
    row.x, row.y = col.x, y
    row.lock = page:CreateTexture(nil, "OVERLAY")
    row.lock:SetSize(14, 14)
    row.lock:SetPoint("TOPRIGHT", col.x + COL_W, y + 1)
    row.lock:Hide()
    row.hover = CreateFrame("Frame", nil, page)
    row.hover:SetPoint("TOPLEFT", col.x, y)
    row.hover:SetSize(COL_W, ROW_H)
    hoverable(row.hover, function() return row.tipTitle, row.tip end)
    row.value:SetJustifyH("RIGHT")
    row.label:SetPoint("RIGHT", row.value, "LEFT", -6, 0)
    row.label:SetWordWrap(false)
    row.value:SetWordWrap(false)
    col.rows[i] = row
  end
end

-- bar rows: a faint track, the fill on it, the label on the bar, the count at the right
local function addBarRows(col)
  for i = 1, ROWS do
    local y = ROWS_TOP - (i - 1) * ROW_STEP
    local row = CreateFrame("Frame", nil, page)
    row:SetPoint("TOPLEFT", col.x, y)
    row:SetSize(COL_W, ROW_H)
    row.track = row:CreateTexture(nil, "BACKGROUND")
    row.track:SetAllPoints(row)
    row.track:SetColorTexture(1, 1, 1, 0.06)
    row.fill = row:CreateTexture(nil, "ARTWORK")
    row.fill:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
    row.fill:SetSize(1, ROW_H)
    row.count = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.count:SetPoint("RIGHT", row, "RIGHT", -4, 0)
    row.count:SetJustifyH("RIGHT")
    row.count:SetWordWrap(false)
    row.label = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
    row.label:SetPoint("LEFT", row, "LEFT", 4, 0)
    row.label:SetPoint("RIGHT", row.count, "LEFT", -6, 0) -- (too long: cut off with "...")
    row.label:SetJustifyH("LEFT")
    row.label:SetWordWrap(false)
    hoverable(row, function() return row.tipTitle, row.tip end)
    col.rows[i] = row
  end
end

local function fillBars(col, header, items, tipOf)
  col.header:SetText(header)
  local max = 0
  for _, it in ipairs(items) do max = math.max(max, it[2]) end
  for i, row in ipairs(col.rows) do
    local it = items[i]
    row:SetShown(it ~= nil)
    if it then
      row.label:SetText(it[1])
      row.count:SetText(it[4])
      local w = max > 0 and math.floor(COL_W * it[2] / max) or 0
      row.fill:SetShown(w > 0)
      if w > 0 then
        row.fill:SetWidth(math.max(2, w))
        row.fill:SetColorTexture(it[3][1], it[3][2], it[3][3], FILL_ALPHA)
      end
      row.tipTitle, row.tip = it[1], tipOf(it)
    end
  end
end

function UI.BuildStats(win)
  page = CreateFrame("Frame", nil, win)
  page:SetPoint("TOPLEFT", 20, -62) -- (where the Profile page is)
  page:SetPoint("BOTTOMRIGHT", -18, 28)
  page:Hide()
  page.title = page:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
  page.title:SetJustifyH("LEFT")
  ns.Art.UseTitleFont(page.title, 20)
  page.title:SetPoint("TOPLEFT", 0, 0)
  page.title:SetText(L.STATS_TITLE)
  page.sub = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  page.sub:SetJustifyH("LEFT")
  page.sub:SetPoint("TOPLEFT", page.title, "BOTTOMLEFT", 0, -4)

  -- headline tiles
  local tileW = math.floor((PAGE_W - 2 * TILE_GAP) / 3)
  page.tiles = {}
  for i = 1, 3 do
    local tile = CreateFrame("Frame", nil, page)
    tile:SetPoint("TOPLEFT", (i - 1) * (tileW + TILE_GAP), TILE_TOP)
    tile:SetSize(tileW, TILE_H)
    tile.bg = tile:CreateTexture(nil, "BACKGROUND")
    tile.bg:SetAllPoints(tile)
    tile.bg:SetColorTexture(1, 1, 1, 0.06)
    tile.big = tile:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
    tile.big:SetPoint("TOP", 0, -12)
    -- two lines under the number: the label (grey), then the extra (lighter)
    tile.caption = tile:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
    tile.caption:SetPoint("BOTTOM", 0, 24)
    tile.caption:SetWidth(tileW - 12)
    tile.caption:SetWordWrap(false)
    tile.extra = tile:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    tile.extra:SetPoint("BOTTOM", 0, 8)
    tile.extra:SetWidth(tileW - 12)
    tile.extra:SetWordWrap(false)
    tile.lock = tile:CreateTexture(nil, "OVERLAY")
    tile.lock:SetSize(16, 16)
    tile.lock:SetPoint("LEFT", tile.big, "RIGHT", 6, 0)
    tile.lock:Hide()
    hoverable(tile, function() return tile.tipTitle, tile.tip end)
    page.tiles[i] = tile
  end

  -- columns
  page.hunt = newColumn(0)
  addTextRows(page.hunt)
  page.gap = newColumn(COL_W + COL_GAP)
  addBarRows(page.gap)
  page.zones = newColumn(2 * (COL_W + COL_GAP))
  addBarRows(page.zones)
  page.empty = page:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
  page.empty:SetPoint("TOPLEFT", COL_W + COL_GAP, ROWS_TOP - 2 * ROW_STEP)
  page.empty:SetWidth(2 * COL_W + COL_GAP)
  page.empty:SetJustifyH("CENTER")
  page.empty:SetWordWrap(true)
  page.empty:SetText(L.STATS_EMPTY)

  page.footnote = page:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
  page.footnote:SetPoint("BOTTOMLEFT", 0, 0)
  page.footnote:SetWidth(PAGE_W)
  page.footnote:SetJustifyH("LEFT")
  page.footnote:SetWordWrap(false)
  page.footnote:SetText(L.STATS_FOOTNOTE)
  return page
end

function UI.RenderStats()
  if not page then return end
  local v = UI.StatsView()
  page.sub:SetText(v.sub)
  for i, tile in ipairs(page.tiles) do
    local t = v.tiles[i]
    tile.big:SetText((t[4] and DIM or "") .. t[1] .. (t[4] and "|r" or ""))
    tile.big:SetAlpha(t[7] and FADED or 1)
    tile.caption:SetText(t[2])
    tile.extra:SetText(t[6] or "")
    tile.tipTitle, tile.tip = t[5], t[3]
    tile.lock:SetShown(t[7] ~= nil and ns.Art.SetLockIcon(tile.lock))
  end
  local hunt = page.hunt
  hunt.header:SetText(L.STATS_HUNT)
  for i, row in ipairs(hunt.rows) do
    local h = v.hunt[i]
    row.label:SetText(h[1])
    row.value:SetText((h[3] and DIM or "") .. h[2] .. (h[3] and "|r" or ""))
    row.value:SetAlpha(h[4] and FADED or 1)
    local lock = h[4] ~= nil and ns.Art.SetLockIcon(row.lock)
    row.lock:SetShown(lock)
    row.value:ClearAllPoints()
    row.value:SetPoint("TOPRIGHT", row.x + COL_W - (lock and 18 or 0), row.y)
    row.tipTitle, row.tip = h[1], h[5]
  end
  fillBars(page.gap, L.STATS_CHART_GAP, v.gap, function(it) return it[5] end)
  if v.empty then
    -- nothing logged yet: the level rows with their zeros, five bare zone rows, all faded
    fillBars(page.zones, L.STATS_CHART_ZONES, {}, nil)
    for _, row in ipairs(page.zones.rows) do
      row:Show()
      row.label:SetText("")
      row.count:SetText("")
      row.fill:Hide()
      row.tipTitle, row.tip = nil, nil
    end
  else
    fillBars(page.zones, L.STATS_CHART_ZONES, v.zones, function(it) return L.STATS_ZONE_TIP:format(it[1], it[2]) end)
  end
  local alpha = v.empty and FADED or 1
  for _, col in ipairs({ page.gap, page.zones }) do
    col.header:SetAlpha(alpha)
    col.alpha = alpha
    for _, row in ipairs(col.rows) do row:SetAlpha(alpha) end
  end
  page.empty:SetShown(v.empty)
end
