local _, ns = ...
local issecret = ns.issecret

-- Level ups, epic BoE loot and never-before-equipped gear for *this* character.

local EXCLUDED_SLOTS = { [0] = true, [4] = true, [19] = true } -- ammo, shirt, tabard
local QUALITY_EPIC, QUALITY_RARE = 4, 3
local BIND_ON_EQUIP, BIND_ON_USE = 2, 3

local recentLootShared = {} -- itemID -> GetTime() of a shared LOOT event
local seeded = false

---------------------------------------------------------------------------
-- item helpers
---------------------------------------------------------------------------
function ns.ItemLinkFrom(msg)
  return msg:match("(|c[^|]*|Hitem:.-|h|r)") or msg:match("(|Hitem:.-|h.-|h)")
end

-- key = itemID:suffixID (random "of the Eagle" suffix counts, enchants don't)
function ns.ItemKey(link)
  local s = link and link:match("item:([^|]*)")
  if not s then return nil end
  local t = ns.Split(s, ":")
  local id = tonumber(t[1])
  if not id then return nil end
  return id .. ":" .. (tonumber(t[7]) or 0), id
end

-- cb(quality, bindType)
function ns.GetItemInfoAsync(link, cb)
  local get = (C_Item and C_Item.GetItemInfo) or GetItemInfo
  if not get then return end
  local function attempt()
    local name, _, quality, _, _, _, _, _, _, _, _, _, _, bindType = get(link)
    if name then
      cb(quality, bindType)
      return true
    end
    return false
  end
  if attempt() then return end
  if Item and Item.CreateFromItemLink then
    local item = Item:CreateFromItemLink(link)
    item:ContinueOnItemLoad(function() ns.Try("iteminfo", attempt) end)
  else
    C_Timer.After(1, function() ns.Try("iteminfo", attempt) end)
  end
end

---------------------------------------------------------------------------
-- level
---------------------------------------------------------------------------
ns.On("PLAYER_LEVEL_UP", function(level)
  if issecret(level) or not level then return end
  ns.Events.Emit("LVL", { level = level })
end)

---------------------------------------------------------------------------
-- epic BoE / BoU loot (looted or crafted)
---------------------------------------------------------------------------
local LOOT_PATTERNS, CRAFT_PATTERNS = {}, {}

ns.OnReady(function()
  for _, fmt in ipairs({ LOOT_ITEM_SELF_MULTIPLE, LOOT_ITEM_SELF, LOOT_ITEM_PUSHED_SELF_MULTIPLE, LOOT_ITEM_PUSHED_SELF }) do
    LOOT_PATTERNS[#LOOT_PATTERNS + 1] = ns.ToPattern(fmt)
  end
  for _, fmt in ipairs({ LOOT_ITEM_CREATED_SELF_MULTIPLE, LOOT_ITEM_CREATED_SELF }) do
    CRAFT_PATTERNS[#CRAFT_PATTERNS + 1] = ns.ToPattern(fmt)
  end
end)

local function matchAny(msg, patterns)
  for _, p in ipairs(patterns) do
    if msg:match(p) then return true end
  end
  return false
end

ns.On("CHAT_MSG_LOOT", function(msg)
  if issecret(msg) or type(msg) ~= "string" then return end
  local source
  if matchAny(msg, CRAFT_PATTERNS) then
    source = "craft"
  elseif matchAny(msg, LOOT_PATTERNS) then
    source = "loot"
  else
    return
  end
  local link = ns.ItemLinkFrom(msg)
  if not link then return end
  ns.GetItemInfoAsync(link, function(quality, bindType)
    if not quality or quality < QUALITY_EPIC then return end
    if bindType ~= BIND_ON_EQUIP and bindType ~= BIND_ON_USE then return end
    local _, id = ns.ItemKey(link)
    if id and ns.S().share.loot then recentLootShared[id] = GetTime() end
    ns.Events.Emit("LOOT", { link = link, source = source })
  end)
end)

---------------------------------------------------------------------------
-- new gear (bursts within GEAR_BUNDLE seconds become one event: best item + count)
---------------------------------------------------------------------------
local GEAR_BUNDLE = 4
local gearBuffer

local function queueGear(link, quality)
  if not gearBuffer then
    gearBuffer = { count = 0, epics = 0 }
    C_Timer.After(GEAR_BUNDLE, function()
      local b = gearBuffer
      gearBuffer = nil
      if b and b.best then
        ns.Try("gear-emit", ns.Events.Emit, "GEAR", { link = b.best, count = b.count, epics = b.epics })
      end
    end)
  end
  gearBuffer.count = gearBuffer.count + 1
  if quality and quality >= 4 then gearBuffer.epics = gearBuffer.epics + 1 end
  if not gearBuffer.bestQuality or quality > gearBuffer.bestQuality then
    gearBuffer.best, gearBuffer.bestQuality = link, quality
  end
end

local function seed()
  local known = FriendsAndFoesCharDB.equipped
  for slot = 0, 19 do
    local link = GetInventoryItemLink("player", slot)
    if link and not issecret(link) then
      local key = ns.ItemKey(link)
      if key then known[key] = true end
    end
  end
  FriendsAndFoesCharDB.seeded = true
  seeded = true
end

ns.On("PLAYER_ENTERING_WORLD", function()
  if seeded then return end
  C_Timer.After(3, function()
    ns.Try("seed", function()
      if FriendsAndFoesCharDB.seeded then seeded = true else seed() end
    end)
  end)
end)

ns.On("PLAYER_EQUIPMENT_CHANGED", function(slot)
  if not seeded or issecret(slot) or not slot or EXCLUDED_SLOTS[slot] then return end
  local link = GetInventoryItemLink("player", slot)
  if not link or issecret(link) then return end
  local key, id = ns.ItemKey(link)
  if not key then return end
  local known = FriendsAndFoesCharDB.equipped
  if known[key] then return end
  known[key] = true
  ns.GetItemInfoAsync(link, function(quality)
    if not quality or quality < QUALITY_RARE then return end
    local t = recentLootShared[id]
    if t and GetTime() - t < 300 then return end -- already announced as loot
    queueGear(link, quality)
  end)
end)
