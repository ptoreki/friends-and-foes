local _, ns = ...
local L = ns.L

-- The bounty board (1.0): contracts.
-- You put a price on an enemy player, in gold, silver and copper. It's a promise to your
-- friends, nothing more: the add-on never moves gold. When you or a friend kills them, the
-- contract is done, and you pay the one who did it yourself, by trade in the game. Then you mark
-- it paid.
--  * Posting puts the target on your hitlist, and on your friends' when it reaches them.
--  * Only the one who posted a contract can change it (raise or lower it, cancel it, mark it
--    paid). Every client marks a contract done when it hears of the kill, so it shows done even
--    if the poster is offline; the poster's own client confirms it to everyone.
--  * Contracts go to every friend with the add-on (not only your alert list), when posted or
--    changed, and when a friend comes online.
--  * Enemy players only: never someone on your side. Never in the simulation.
-- Saved account-wide in FriendsAndFoesDB.contracts, keyed "poster/id".
local Contracts = {}
ns.Contracts = Contracts

local OPEN_MAX = 5                 -- open contracts you can have at once
Contracts.OPEN_MAX = OPEN_MAX
local AMOUNT_MAX = 10000 * 10000   -- 10,000 gold, in copper
Contracts.AMOUNT_MAX = AMOUNT_MAX
-- how long a contract stays open: the poster picks 1-30 days (7 if they don't say)
local DAYS_MIN, DAYS_MAX, DAYS_DEFAULT = 1, 30, 7
Contracts.DAYS_MIN, Contracts.DAYS_MAX, Contracts.DAYS_DEFAULT = DAYS_MIN, DAYS_MAX, DAYS_DEFAULT
local GONE_DAYS = 14               -- cancelled and run-out ones leave the board after this
local DONE_MAX = 200               -- finished ones (someone got the kill) stay; at most this many
local DAY = 86400

local RANK = { open = 1, done = 2, paid = 3, cancelled = 3, expired = 3 } -- (known states)
-- which state changes a message may make: forward only. Cancelling never undoes a kill (the
-- poster may not have heard of it yet), and "expired" is each client's own reckoning, so the
-- poster's word (done, paid, or open again after posting it again) wins over it.
local NEXT = {
  open = { done = true, paid = true, cancelled = true, expired = true },
  expired = { open = true, done = true, paid = true, cancelled = true },
  done = { paid = true },
  paid = {}, cancelled = {},
}
local FRESH = 3600 -- a friend's news older than this goes on the board without a toast

local function finite(n) return type(n) == "number" and n == n and n > -math.huge and n < math.huge end

local function store()
  FriendsAndFoesDB.contracts = FriendsAndFoesDB.contracts or {}
  return FriendsAndFoesDB.contracts
end
Contracts.Store = store

---------------------------------------------------------------------------
-- money: copper <-> "12g 50s 3c"
---------------------------------------------------------------------------
-- "12g 50s", "12 g", "50s 3c", "12" (= gold), "1.5g" -> copper; nil if it isn't money
function Contracts.ParseMoney(text)
  if type(text) ~= "string" then return nil end
  local s = text:lower():gsub("[,%s]+", " ")
  if s:find("%d%s*d") then return nil end -- (days: Contracts.ParseOffer)
  s = strtrim and strtrim(s) or s:match("^%s*(.-)%s*$")
  if s == "" then return nil end
  local plain = tonumber(s)
  if plain then
    if not finite(plain) or plain <= 0 then return nil end -- ("inf", "nan")
    return math.floor(plain * 10000 + 0.5)
  end
  local total, seen = 0, false
  local rest = s:gsub("(%d+%.?%d*)%s*([gsc])", function(n, unit)
    local v = tonumber(n) or 0
    total = total + v * (unit == "g" and 10000 or unit == "s" and 100 or 1)
    seen = true
    return ""
  end)
  if not seen or rest:match("%S") then return nil end
  total = math.floor(total + 0.5)
  return total > 0 and total or nil
end

-- what you type when posting: an amount, and how many days it stays open:
-- "10g 50s 3d", "10g 3 days", "10g for 3 days", "10g" (7 days).
-- Returns copper, days; or nil and why ("CONTRACT_BAD_AMOUNT" / "CONTRACT_BAD_DAYS").
function Contracts.ParseOffer(text)
  if type(text) ~= "string" then return nil, "CONTRACT_BAD_AMOUNT" end
  local s = " " .. text:lower() .. " "
  local days
  s = s:gsub("%s+for%s+", " ")
  s = s:gsub("(%d+)%s*days?%f[^%a]", function(n) days = tonumber(n); return " " end, 1)
  if not days then s = s:gsub("(%d+)%s*d%f[^%a]", function(n) days = tonumber(n); return " " end, 1) end
  local amount = Contracts.ParseMoney(s)
  if not amount then return nil, "CONTRACT_BAD_AMOUNT" end
  days = days or DAYS_DEFAULT
  if days < DAYS_MIN or days > DAYS_MAX then return nil, "CONTRACT_BAD_DAYS" end
  return amount, days
end

local function daysOf(c)
  local d = tonumber(c.days)
  if not (finite(d) and d >= DAYS_MIN and d <= DAYS_MAX) then return DAYS_DEFAULT end
  return math.floor(d)
end
Contracts.DaysOf = daysOf

local COINS = {
  { 10000, "Interface\\MoneyFrame\\UI-GoldIcon" },
  { 100, "Interface\\MoneyFrame\\UI-SilverIcon" },
  { 1, "Interface\\MoneyFrame\\UI-CopperIcon" },
}

-- copper -> "12 [g] 50 [s]" with coin icons (parts that are 0 are left out)
function Contracts.MoneyText(copper)
  copper = ns.Count(copper)
  local parts = {}
  for _, c in ipairs(COINS) do
    local n = math.floor(copper / c[1])
    copper = copper - n * c[1]
    if n > 0 then parts[#parts + 1] = n .. " " .. ns.Art.Icon(c[2]) end
  end
  if #parts == 0 then return "0 " .. ns.Art.Icon(COINS[3][2]) end
  return table.concat(parts, " ")
end

---------------------------------------------------------------------------
-- the board
---------------------------------------------------------------------------
local function key(by, id) return by .. "/" .. id end

-- Open contracts that ran out become "expired". Cancelled and expired ones leave after a while;
-- finished ones (done, paid: someone got the kill) stay on the board with who closed them -
-- only the oldest go once there are more than DONE_MAX.
function Contracts.Tidy()
  local now, list = time(), store()
  local finished = {}
  for k, c in pairs(list) do
    if c.state == "open" and now - (c.t or 0) > daysOf(c) * DAY then
      c.state, c.upd = "expired", now
    end
    if c.state == "cancelled" or c.state == "expired" then
      if now - (c.upd or c.t or 0) > GONE_DAYS * DAY then list[k] = nil end
    elseif c.state ~= "open" then
      finished[#finished + 1] = { k, c.doneAt or c.upd or 0 }
    end
  end
  table.sort(finished, function(a, b) return a[2] < b[2] end)
  for i = 1, #finished - DONE_MAX do list[finished[i][1]] = nil end
end

-- rows for the Bounty board: open ones first (newest first), then done and not paid yet, then
-- the rest. Each: the contract plus name/class/level/guild of the target, mine, key.
function Contracts.List()
  Contracts.Tidy()
  local rows = {}
  for k, c in pairs(store()) do
    if c.state ~= "cancelled" then
      local e = ns.Data.FindPlayer(c.target) or {}
      rows[#rows + 1] = setmetatable({ key = k, name = c.target, class = c.class or e.class, level = c.level or e.level,
        guild = c.guild or e.guild, mine = c.by == ns.me, lastSeen = e.lastSeen }, { __index = c })
    end
  end
  local order = { open = 1, done = 2, paid = 3, expired = 4 }
  table.sort(rows, function(a, b)
    local oa, ob = order[a.state] or 5, order[b.state] or 5
    if oa ~= ob then return oa < ob end
    return (a.t or 0) > (b.t or 0)
  end)
  return rows
end

-- open contracts on one enemy: { contract, ... }
function Contracts.On(name)
  local out = {}
  for _, c in pairs(store()) do
    if c.target == name and c.state == "open" then out[#out + 1] = c end
  end
  table.sort(out, function(a, b) return (a.amount or 0) > (b.amount or 0) end)
  return out
end

-- your open contracts
function Contracts.MineOpen()
  local n = 0
  for _, c in pairs(store()) do
    if c.by == ns.me and c.state == "open" then n = n + 1 end
  end
  return n
end

---------------------------------------------------------------------------
-- sending
---------------------------------------------------------------------------
local function message(c)
  local _, class = UnitClass("player")
  local now = time()
  return { kind = "BTY", id = ns.NewId(), class = class, level = UnitLevel("player"), f = {
    cid = c.id,
    target = ns.EncodeUnit({ name = c.target, class = c.class, level = c.level, guild = c.guild }),
    amount = c.amount,
    state = c.state,
    killer = c.killer or "",
    age = math.max(0, now - (c.t or now)),
    updage = math.max(0, now - (c.upd or now)),
    days = daysOf(c),
  } }
end

-- one contract of yours to every friend with the add-on (or just to `names`)
local function send(c, names)
  if c.by ~= ns.me then return end
  local msg = message(c)
  if names then
    for _, name in ipairs(names) do ns.Comm.SendTo(name, msg) end
  else
    for _, name in ipairs(ns.Comm.EveryoneNames()) do ns.Comm.SendTo(name, msg) end
  end
end

-- a friend came online: your contracts they should know about - open ones, done ones you
-- haven't paid yet, and ones finished in the last GONE_DAYS (older finished ones they already
-- have; sending all of them every time would be a lot of messages)
function Contracts.Greet(names)
  Contracts.Tidy()
  local now = time()
  for _, c in pairs(store()) do
    local recent = now - (c.upd or c.t or 0) <= GONE_DAYS * DAY
    if c.by == ns.me and (c.state == "open" or c.state == "done" or (c.state == "paid" and recent)) then
      send(c, names)
    end
  end
end

---------------------------------------------------------------------------
-- the target on your hitlist (yours, or a friend's contract that reached you)
---------------------------------------------------------------------------
local function onHitlist(c)
  if ns.PvP.IsFriendly(c.target) then return end
  local realm = ns.Data.RealRealm()
  local e = realm.players[c.target]
  if not e then
    e = { name = c.target, k = 0, d = 0, a = 0 }
    realm.players[c.target] = e
  end
  e.enemy = true
  e.class = e.class or c.class
  e.level = e.level or c.level
  e.guild = e.guild or c.guild
  local h = realm.hitlist[c.target]
  if not h then
    h = { name = c.target, attacks = 0, kills = 0, suspect = 0, revenge = 0, victims = {}, firstSeen = time() }
    realm.hitlist[c.target] = h
    if c.by ~= ns.me then h.sharedBy = c.by end
  end
  h.class = h.class or c.class
  h.level = h.level or c.level
  h.guild = h.guild or c.guild
  if ns.Marks then ns.Marks.Refresh() end
end

local function say(text) ns.Toast.Chat(text) end
local function changed() if ns.UI and ns.UI.OnDataChanged then ns.UI.OnDataChanged() end end

---------------------------------------------------------------------------
-- your contracts: post, cancel, mark paid
---------------------------------------------------------------------------
-- u: { name, class, level, guild } of an enemy player; amount in copper; days it stays open
-- (1-30, default 7). Posting again on the same enemy changes your open contract.
-- Returns the contract, or nil and why ("CONTRACT_...").
function Contracts.Post(u, amount, days)
  if not ns.me then return nil, "CONTRACT_NOT_READY" end
  local name = u and ns.CleanName(u.name)
  if not name then return nil, "CONTRACT_NEED_TARGET" end
  if name == ns.me or ns.PvP.IsFriendly(name) then return nil, "CONTRACT_NOT_ENEMY" end
  amount = tonumber(amount)
  if not (finite(amount) and amount >= 1 and amount <= AMOUNT_MAX) then return nil, "CONTRACT_BAD_AMOUNT" end
  amount = math.floor(amount)
  days = tonumber(days) or DAYS_DEFAULT
  if not (finite(days) and days >= DAYS_MIN and days <= DAYS_MAX) then return nil, "CONTRACT_BAD_DAYS" end
  days = math.floor(days)
  local list, now = store(), time()
  for _, c in pairs(list) do
    if c.by == ns.me and c.target == name and c.state == "open" then
      -- posting again: the new amount, open for the new number of days from now
      c.amount, c.days, c.t, c.upd = amount, days, now, now
      send(c)
      changed()
      return c
    end
  end
  if Contracts.MineOpen() >= OPEN_MAX then return nil, "CONTRACT_TOO_MANY" end
  local c = { id = ns.NewId(), by = ns.me, target = name, class = u.class, level = ns.Count(u.level) > 0 and ns.Count(u.level) or nil,
    guild = u.guild, amount = amount, days = days, state = "open", t = now, upd = now }
  list[key(c.by, c.id)] = c
  onHitlist(c)
  ns.Data.Feed("contract", L.CONTRACT_FEED_POSTED:format(ns.ClassColored(ns.me), Contracts.MoneyText(amount),
    ns.ClassColored(name, c.class)), ns.me, { name })
  send(c)
  changed()
  return c
end

local function ownContract(k)
  local c = store()[k]
  if c and c.by == ns.me then return c end
end

function Contracts.Cancel(k)
  local c = ownContract(k)
  if not c or c.state ~= "open" then return false end
  c.state, c.upd = "cancelled", time()
  send(c)
  changed()
  return true
end

function Contracts.MarkPaid(k)
  local c = ownContract(k)
  if not c or c.state ~= "done" then return false end
  c.state, c.upd = "paid", time()
  send(c)
  changed()
  return true
end

---------------------------------------------------------------------------
-- a kill (from Events: H.KILL): open contracts on that enemy are done
---------------------------------------------------------------------------
-- Kills count at the time they happened: one caught up on at login may be from before the bounty
-- was posted (then it doesn't count), or from before it ran out (then it does). A bounty on a
-- bare first name (the surname couldn't be read) matches that player's full name, and takes it.
local function sameTarget(c, victim)
  if c.target == victim then return true end
  return not c.target:find(" ", 1, true) and ns.FirstName(victim) == c.target
end

function Contracts.OnKill(killer, victim)
  if not killer or not victim then return 0 end
  local now, when, n = time(), ns.Now(), 0
  for _, c in pairs(store()) do
    if (c.state == "open" or c.state == "expired") and sameTarget(c, victim)
      and when >= (c.t or 0) and when - (c.t or 0) <= daysOf(c) * DAY then
      n = n + 1
      c.target = victim
      c.killer, c.doneAt, c.upd = killer, when, now
      -- the poster got them: nothing to pay
      c.state = killer == c.by and "paid" or "done"
      if killer ~= c.by then Contracts.ToastDone(c) end
      local money, target = Contracts.MoneyText(c.amount), ns.ClassColored(victim, c.class)
      if killer ~= c.by then
        ns.Data.Feed("contract", L.CONTRACT_FEED_DONE:format(ns.ClassColored(killer), ns.ClassColored(c.by), target, money),
          killer, { victim })
      end
      send(c) -- (yours only: the poster confirms it to everyone)
    end
  end
  if n > 0 then changed() end
  return n
end

---------------------------------------------------------------------------
-- receiving a friend's contract (BTY)
---------------------------------------------------------------------------
-- from: the friend who sent it (always the poster: a contract is keyed by its sender, so no one
-- can change someone else's)
function Contracts.OnMessage(from, f)
  if not from or from == ns.me then return end
  local id = f.cid and f.cid:match("^%w+$")
  if not id or #id > 16 then return end
  local u = ns.DecodeUnit(f.target)
  local name = u and u.name
  if not name or name == ns.me or ns.PvP.IsFriendly(name) then return end
  local amount = ns.Count(tonumber(f.amount))
  if amount < 1 or amount > AMOUNT_MAX then return end
  local state = RANK[f.state] and f.state or nil
  if not state then return end
  local now = time()
  local updAge = math.min(ns.Count(tonumber(f.updage)), 60 * DAY)
  local t = now - math.min(ns.Count(tonumber(f.age)), 60 * DAY)
  local upd = now - updAge
  local killer = ns.CleanName(f.killer)
  local days = tonumber(f.days)
  if not (finite(days) and days >= DAYS_MIN and days <= DAYS_MAX) then days = nil end

  local list, k = store(), key(from, id)
  local c = list[k]
  local isNew = c == nil
  if isNew then
    if state == "cancelled" or state == "expired" then return end
    c = { id = id, by = from, target = name, t = t }
    list[k] = c
  end
  local before = c.state
  -- the poster's word on the amount, days and details (when it's newer than what you have)
  local newer = not c.upd or upd >= c.upd - 5
  if newer then
    c.amount, c.t = amount, t -- (posting again starts it again)
    if days then c.days = math.floor(days) end
    c.class, c.level, c.guild = u.class or c.class, (u.level and u.level > 0) and u.level or c.level, u.guild or c.guild
  end
  if not before then
    c.state = state
  elseif state ~= before and NEXT[before] and NEXT[before][state] then
    -- open again after it ran out here: only if the poster's days say it's still open
    if not (state == "open" and now - (c.t or 0) > daysOf(c) * DAY) then c.state = state end
  end
  -- who got the kill: the poster's word wins (two friends can get honor for the same death)
  if killer and (c.state == "done" or c.state == "paid") and (state == "done" or state == "paid") then
    c.killer = killer
    c.doneAt = c.doneAt or upd
  end
  c.upd = math.max(c.upd or 0, upd)

  local money, target, poster = Contracts.MoneyText(c.amount), ns.ClassColored(name, c.class), ns.ClassColored(from)
  -- toasts only for news (a friend who comes online sends all their bounties again)
  local fresh = updAge <= FRESH
  if isNew and c.state == "open" then
    onHitlist(c)
    if fresh then Contracts.ToastPosted(c) end
    ns.Data.Feed("contract", L.CONTRACT_FEED_POSTED:format(poster, money, target), from, { name })
  elseif fresh and before ~= "done" and before ~= "paid" and c.state == "done" and c.killer and c.killer ~= c.by then
    Contracts.ToastDone(c) -- (a kill you hadn't heard of: the poster confirms it)
  elseif before ~= c.state and c.state == "paid" and c.killer == ns.me then
    say(L.CONTRACT_PAID_YOU:format(poster, money, target))
  end
  Contracts.Tidy()
  changed()
end

ns.OnReady(function() ns.Try("contracts-tidy", Contracts.Tidy) end)

-- "6d" / "5h": how long an open contract has left
function Contracts.TimeLeft(c)
  local left = daysOf(c) * DAY - (time() - (c.t or time()))
  if left >= DAY then return math.floor(left / DAY) .. "d" end
  return math.max(1, math.floor(left / 3600)) .. "h"
end

---------------------------------------------------------------------------
-- toasts: a friend's bounty goes up, a bounty is done (kind "contract", Options -> Alerts)
---------------------------------------------------------------------------
local ICON_POSTED = "Interface\\Icons\\INV_Scroll_03"
local ICON_DONE = "Interface\\Icons\\INV_Misc_Coin_01"

function Contracts.ToastPosted(c)
  local poster, target = ns.ClassColored(c.by), ns.ClassColored(c.target, c.class)
  local title = L.CONTRACT_POSTED:format(poster, Contracts.MoneyText(c.amount), target)
  local text = L.CONTRACT_TOAST_DAYS:format(daysOf(c))
  ns.Toast.Push({ kind = "contract", category = "bounty", icon = ICON_POSTED, header = L.HEADER_CONTRACT_POSTED,
    title = title, text = text, chat = title .. ns.Flavor.SEP .. text, player = c.target })
end

-- your bounty: pay them; theirs and you got it: they pay you; anyone else's: who got it
function Contracts.ToastDone(c)
  local target, money = ns.ClassColored(c.target, c.class), Contracts.MoneyText(c.amount)
  local killer, poster = ns.ClassColored(c.killer or "?"), ns.ClassColored(c.by)
  local title, text
  if c.by == ns.me then
    title, text = L.CONTRACT_YOURS_DONE_TITLE:format(target, killer), L.CONTRACT_YOURS_DONE_TEXT:format(money)
  elseif c.killer == ns.me then
    title, text = L.CONTRACT_YOU_DID_TITLE:format(poster, target), L.CONTRACT_YOU_DID_TEXT:format(money)
  else
    title, text = L.CONTRACT_DONE_TITLE:format(killer, poster, target), money
  end
  ns.Toast.Push({ kind = "contract", category = "bounty", icon = ICON_DONE, header = L.HEADER_CONTRACT_DONE,
    title = title, text = text, chat = title .. ns.Flavor.SEP .. text, player = c.target })
end
