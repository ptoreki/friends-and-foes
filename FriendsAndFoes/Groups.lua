local _, ns = ...
local L = ns.L
local issecret = ns.issecret

-- Shared groups: named groups of players whose PvP stats you follow together.
-- A member is a Battle.net ACCOUNT (all its characters count), known by a scrambled code made
-- from its BattleTag: friends-of-friends need some ID for you, but never see the BattleTag.
-- No server: every member keeps a copy, and members pass along what they know, because not
-- everyone in a group is Battle.net friends with everyone else ("relaying").
--  * Membership: one entry per account with three times: a = invited, j = joined, r = removed/left.
--    Copies merge by taking the newest of each time, so changes made while people were offline
--    fit together in any order. Any member invites their own friends; anyone can leave; the
--    leader removes people. An invite must be accepted (Join) before someone counts.
--  * Every client works out the same thing from the same entries, so nobody has to agree:
--    - at most 10: joined members first (earliest join first), then invites (earliest first);
--      anyone past 10 doesn't count (their invite is void)
--    - the leader is the member who has been in longest (the creator, until they leave)
--  * Stats: each account's kills/deaths over all its characters, with the time they were true.
--    The newest copy wins. Only stats travel this way; live alerts stay between direct friends.
-- Messages: GRP (a group and some of its member entries), GST (stats for some accounts).
-- Removals and left groups are never forgotten (they're tiny): a very old copy of a group turning
-- up later must not bring anyone back in.
local Groups = {}
ns.Groups = Groups

local MAX_MEMBERS = 10     -- invited + joined
local MAX_GROUPS = 5       -- groups you're in or invited to
local NAME_MIN, NAME_MAX = 2, 24 -- group name length in characters, like guild names
local FORWARD_DELAY = 5    -- batch relaying for a few seconds
local OUT_NOTIFY = 86400   -- someone removed less than a day ago still hears about it
local LEFT_TELL = 30 * 86400 -- after you leave, members you meet still hear it for this long
local MIN_VERSION = "0.7.0" -- groups need this on both sides

---------------------------------------------------------------------------
-- storage (account-wide)
---------------------------------------------------------------------------
local function store()
  FriendsAndFoesDB.groups = FriendsAndFoesDB.groups or {}
  return FriendsAndFoesDB.groups
end

-- stats you heard about: account key -> { k, d, t, name, via, direct }
local function relayed()
  local world = ns.Data.Realm()
  world.relay = world.relay or {}
  return world.relay
end
Groups.Relayed = relayed

function Groups.Get(id) return id and store()[id] end

---------------------------------------------------------------------------
-- base 36, account keys, ids
---------------------------------------------------------------------------
local B36 = "0123456789abcdefghijklmnopqrstuvwxyz"
local function b36(n)
  n = math.floor(tonumber(n) or 0)
  if n <= 0 then return n == 0 and "0" or "" end
  local s = ""
  while n > 0 do
    local d = n % 36
    s = B36:sub(d + 1, d + 1) .. s
    n = (n - d) / 36
  end
  return s
end
local function unb36(s) return s and s ~= "" and tonumber(s, 36) or nil end
Groups.B36, Groups.UnB36 = b36, unb36

-- the same BattleTag gives the same key on every client (two plain 32-bit string hashes)
function Groups.KeyOf(tag)
  if type(tag) ~= "string" or issecret(tag) or tag == "" then return nil end
  tag = tag:lower()
  local h1, h2 = 5381, 7
  for i = 1, #tag do
    local c = tag:byte(i)
    h1 = (h1 * 33 + c) % 4294967296
    h2 = (h2 * 131 + c) % 4294967291
  end
  return b36(h1) .. "_" .. b36(h2)
end

local function validKey(s) return type(s) == "string" and #s <= 16 and s:match("^[%w_]+$") ~= nil end

-- your own BattleTag (nil if Battle.net won't say)
function Groups.MyTag()
  if BNGetInfo then
    local ok, _, tag = pcall(BNGetInfo)
    if ok and type(tag) == "string" and not issecret(tag) and tag ~= "" then return tag end
  end
  if C_BattleNet and C_BattleNet.GetAccountInfoByGUID and UnitGUID then
    local ok, info = pcall(C_BattleNet.GetAccountInfoByGUID, UnitGUID("player"))
    local tag = ok and info and info.battleTag
    if type(tag) == "string" and not issecret(tag) and tag ~= "" then return tag end
  end
end
function Groups.MyKey() return Groups.KeyOf(Groups.MyTag()) end

-- a friend's account key, from their character name (works offline: BattleTags are remembered)
function Groups.FriendKey(name) return Groups.KeyOf(ns.Comm.TagFor(name)) end

-- online friends with the addon: account key -> character name
local function onlineByKey()
  local out = {}
  for name, e in pairs(ns.Comm.everyone) do
    local k = Groups.KeyOf(e.tag)
    if k then out[k] = name end
  end
  return out
end

local function cleanId(s)
  if type(s) ~= "string" then return nil end
  s = s:gsub("[^%w]", "")
  if s == "" or #s > 16 then return nil end
  return s
end

-- group names: plain text, no separators, at most 24 characters (like guild names). A name that
-- arrives longer (an older or modified client) is cut.
function Groups.CleanName(s)
  local t = ns.Profile.CleanText(s and (s:gsub("[:;]", " ")), NAME_MAX)
  return t
end

-- a name you type for a new group: 2-24 characters, like a guild name. Returns the name, or
-- nil + reason. Too long is refused, not cut, so you see what others will see.
function Groups.CheckName(s)
  local t = ns.Profile.CleanText(s and (s:gsub("[:;]", " ")))
  if not t or ns.Profile.Length(t) < NAME_MIN then return nil, "GROUP_BAD_NAME" end
  if ns.Profile.Length(t) > NAME_MAX then return nil, "GROUP_NAME_TOO_LONG" end
  if ns.Profile.Check(t) == "offensive" then return nil, "TEXT_OFFENSIVE" end
  return t
end

local function newId() return b36(time()) .. b36(math.random(0, 36 ^ 4 - 1)) end

-- the name to show for a group: your own groups as you named them; anyone else's only once the
-- language filter has passed it
function Groups.Label(g)
  if not g then return "?" end
  if g.mine then return g.name end
  return ns.Profile.Shown(g.name) or L.GROUP_UNNAMED
end

---------------------------------------------------------------------------
-- membership
---------------------------------------------------------------------------
-- one entry on its own: "in" | "invited" | "out"
local function rawState(m)
  if not m then return "out" end
  local a, j, r = m.a or 0, m.j or 0, m.r or 0
  if a == 0 or r >= a then return "out" end
  if j > r and j >= a then return "in" end
  return "invited"
end
Groups.RawState = rawState

-- every account's state with the 10-member cap applied: key -> "in" | "invited"
function Groups.States(g)
  local list = {}
  if not g then return {} end
  for key, m in pairs(g.members) do
    local s = rawState(m)
    if s ~= "out" then list[#list + 1] = { key = key, s = s, t = (s == "in") and (m.j or 0) or (m.a or 0) } end
  end
  table.sort(list, function(x, y)
    if x.s ~= y.s then return x.s == "in" end
    if x.t ~= y.t then return x.t < y.t end
    return x.key < y.key
  end)
  local out = {}
  for i = 1, math.min(#list, MAX_MEMBERS) do out[list[i].key] = list[i].s end
  return out
end

function Groups.StateOf(g, key) return (key and Groups.States(g)[key]) or "out" end
function Groups.MyState(g) return Groups.StateOf(g, Groups.MyKey()) end

-- the member who has been in longest
function Groups.Leader(g)
  local best, bt
  for key, s in pairs(Groups.States(g)) do
    local j = g.members[key].j or 0
    if s == "in" and (not bt or j < bt or (j == bt and key < best)) then best, bt = key, j end
  end
  return best
end

-- a member's character name. Normally one Blizzard already approved, but it arrives through
-- other players, so it goes through the language filter too.
local function displayName(g, key)
  local m = g.members[key]
  local r = relayed()[key]
  local name = (m and m.name) or (r and r.name)
  if not name or ns.Profile.Check(name) == "offensive" then return "?" end
  return name
end
Groups.DisplayName = displayName

-- members that count: { { key, name, state, leader }, ... } sorted by name
function Groups.Members(g)
  local out, leader = {}, Groups.Leader(g)
  for key, s in pairs(Groups.States(g)) do
    out[#out + 1] = { key = key, name = displayName(g, key), state = s, leader = key == leader }
  end
  table.sort(out, function(x, y) return x.name < y.name end)
  return out
end

-- a member by name ("First Last", or a first name only one member has)
function Groups.MemberByName(g, text)
  text = text and text:lower()
  if not text or text == "" then return nil end
  local hit, n = nil, 0
  for _, m in ipairs(Groups.Members(g)) do
    local name = m.name:lower()
    if name == text then return m.key end
    if (ns.FirstName(name) or "") == text then hit, n = m.key, n + 1 end
  end
  return n == 1 and hit or nil
end

-- your groups (joined or invited), by name
function Groups.Mine()
  local out = {}
  if not Groups.MyKey() then return out end
  for _, g in pairs(store()) do
    if Groups.MyState(g) ~= "out" then out[#out + 1] = g end
  end
  table.sort(out, function(x, y)
    if x.name:lower() ~= y.name:lower() then return x.name:lower() < y.name:lower() end
    return x.id < y.id
  end)
  return out
end

-- by the name you see (so a hidden name can't be typed to reach it)
function Groups.FindByName(text)
  text = text and text:lower()
  for _, g in ipairs(Groups.Mine()) do
    if Groups.Label(g):lower() == text then return g end
  end
end

-- you're in (or invited to) a group with this account, and with `other` too if given
local function shareGroup(key, other)
  if not key then return false end
  for _, g in pairs(store()) do
    local st = Groups.States(g)
    local mine = Groups.MyKey()
    if mine and st[mine] and st[key] and (not other or st[other]) then return true end
  end
  return false
end
Groups.ShareGroup = shareGroup

---------------------------------------------------------------------------
-- stats
---------------------------------------------------------------------------
-- your kills/deaths over all your characters, and when they last changed
function Groups.MyTotals()
  local k, d = 0, 0
  for _, p in pairs(ns.Data.RealRealm().players) do
    if p.self then k, d = k + ns.Count(p.k), d + ns.Count(p.d) end
  end
  -- bounties collected (0.9) ride along: a new total is newer news too
  local bt = ns.Bounty and (ns.Bounty.Mine()) or 0
  local s = ns.Data.Realm().groupStat
  if not s or s.k ~= k or s.d ~= d or s.bt ~= bt then
    s = { k = k, d = d, bt = bt, t = time() }
    ns.Data.Realm().groupStat = s
  end
  return s
end

-- best known card for an account: { k, d, bt, t, name, via, direct, self } or nil.
-- One card per member account, newest wins, passed on by members to members (GST). bt: bounties
-- collected (nil from a member on a version before 0.9). New stats go on the end of the card.
function Groups.StatsOf(key)
  if key and key == Groups.MyKey() then
    if not ns.S().share.pvp then return nil end
    local s = Groups.MyTotals()
    return { k = s.k, d = s.d, bt = s.bt, t = s.t, name = ns.me, self = true }
  end
  local r = key and relayed()[key]
  if not r then return nil end
  return { k = r.k, d = r.d, bt = r.bt, t = r.t or 0, name = r.name, via = r.via, direct = r.direct }
end

---------------------------------------------------------------------------
-- wire format
---------------------------------------------------------------------------
local function plainName(name) return ((name or ""):gsub("[:;\t|]", " ")) end

-- entries relative to `base` so the times stay short: "key:a:j:r:Character Name"
local function encodeEntry(key, m, base)
  local function rel(t) return (t and t > 0) and b36(t - base + 1) or "" end
  return key .. ":" .. rel(m.a) .. ":" .. rel(m.j) .. ":" .. rel(m.r) .. ":" .. plainName(m.name)
end

local function decodeEntries(s, base)
  local out = {}
  base = tonumber(base)
  if not base or not s or s == "" then return out end
  for _, part in ipairs(ns.Split(s, ";")) do
    local p = ns.Split(part, ":")
    if validKey(p[1]) then
      local function abs(v) local n = unb36(v); return n and (base + n - 1) or 0 end
      out[p[1]] = { a = abs(p[2]), j = abs(p[3]), r = abs(p[4]), name = ns.CleanName(p[5]) }
    end
  end
  return out
end

local function msg(kind, fields)
  local _, class = UnitClass("player")
  return { kind = kind, id = ns.NewId(), class = class, level = UnitLevel("player"), f = fields }
end

-- fill messages with list items until each is as full as fits; first item goes first
local function chunked(list, build)
  local out, batch = {}, {}
  local function fits(items) return #ns.Comm.Encode(build(items)) <= 250 end
  for _, item in ipairs(list) do
    batch[#batch + 1] = item
    if not fits(batch) then
      table.remove(batch)
      if #batch > 0 then out[#out + 1] = build(batch) end
      batch = { item }
    end
  end
  if #batch > 0 then out[#out + 1] = build(batch) end
  return out
end

-- GRP messages for one account: their own entry first, so the first one that arrives tells
-- them whether the group is about them at all
function Groups.GroupMessages(g, recipientKey)
  local keys = {}
  for key in pairs(g.members) do if key ~= recipientKey then keys[#keys + 1] = key end end
  table.sort(keys)
  if g.members[recipientKey] then table.insert(keys, 1, recipientKey) end
  local base = math.huge
  for _, m in pairs(g.members) do
    for _, t in ipairs({ m.a or 0, m.j or 0, m.r or 0 }) do
      if t > 0 and t < base then base = t end
    end
  end
  if base == math.huge then base = time() end
  return chunked(keys, function(batch)
    local parts = {}
    for _, key in ipairs(batch) do parts[#parts + 1] = encodeEntry(key, g.members[key], base) end
    return msg("GRP", { gid = g.id, name = g.name, owner = plainName(g.owner), base = base, members = table.concat(parts, ";") })
  end)
end

-- GST messages with the cards of these accounts (the ones we know): "key:k:d:time:Name:bt".
-- Fields only ever go on the end: older versions read the first five and ignore the rest.
function Groups.StatsMessages(keys)
  local items = {}
  for _, key in ipairs(keys) do
    local s = Groups.StatsOf(key)
    if s then
      items[#items + 1] = key .. ":" .. s.k .. ":" .. s.d .. ":" .. b36(s.t) .. ":" .. plainName(s.name)
        .. ":" .. (s.bt and b36(s.bt) or "")
    end
  end
  return chunked(items, function(batch) return msg("GST", { stats = table.concat(batch, ";") }) end)
end

---------------------------------------------------------------------------
-- sending
---------------------------------------------------------------------------
-- someone who should hear about changes to this group: in it, invited, or removed recently
local function audience(g, key)
  if not key or key == Groups.MyKey() then return false end
  local m = g.members[key]
  if not m then return false end
  if Groups.StateOf(g, key) ~= "out" then return true end
  return (m.r or 0) > time() - OUT_NOTIFY
end

local function sendGroup(g, key, name)
  for _, m in ipairs(Groups.GroupMessages(g, key)) do ns.Comm.SendTo(name, m) end
end

-- tell every online member about this group (except whoever we just heard it from)
function Groups.Push(g, exceptKey)
  for key, name in pairs(onlineByKey()) do
    if key ~= exceptKey and audience(g, key) then sendGroup(g, key, name) end
  end
end

-- you left (or declined) recently: members you meet still need to hear it, even if nobody
-- else was online to pass it on when you left
local function leftRecently(g)
  local me = g.members[Groups.MyKey() or ""]
  return me and Groups.MyState(g) == "out" and (me.r or 0) > time() - LEFT_TELL
end

-- friends came online: the groups you share and the stats of their members
function Groups.Greet(names)
  if not Groups.MyKey() then return end
  for _, friend in ipairs(names) do
    local fkey = Groups.FriendKey(friend)
    if fkey then
      local others, seen = {}, {}
      for _, g in pairs(store()) do
        if leftRecently(g) and Groups.StateOf(g, fkey) ~= "out" then
          sendGroup(g, fkey, friend)
        elseif Groups.MyState(g) ~= "out" and audience(g, fkey) then
          sendGroup(g, fkey, friend)
          for key in pairs(Groups.States(g)) do
            if key ~= fkey and not seen[key] then
              seen[key] = true
              others[#others + 1] = key
            end
          end
        end
      end
      table.sort(others)
      for _, m in ipairs(Groups.StatsMessages(others)) do ns.Comm.SendTo(friend, m) end
    end
  end
end

-- newer stats about an account (from `sourceKey`): pass them on to online friends in a group with it
local dirty, dirtyFrom, flushPending = {}, {}, false
function Groups.StatsChanged(key, sourceKey)
  if not shareGroup(key) then return end
  dirty[key] = true
  dirtyFrom[key] = sourceKey
  if flushPending then return end
  flushPending = true
  C_Timer.After(FORWARD_DELAY, function()
    flushPending = false
    ns.Try("groups-forward", Groups.Flush)
  end)
end

function Groups.Flush()
  local keys = {}
  for key in pairs(dirty) do keys[#keys + 1] = key end
  table.sort(keys)
  local from = dirtyFrom
  dirty, dirtyFrom = {}, {}
  for fkey, friend in pairs(onlineByKey()) do
    local send = {}
    for _, key in ipairs(keys) do
      if key ~= fkey and from[key] ~= fkey and shareGroup(fkey, key) then send[#send + 1] = key end
    end
    for _, m in ipairs(Groups.StatsMessages(send)) do ns.Comm.SendTo(friend, m) end
  end
end

-- your own numbers changed (a kill or death on any of your characters)
function Groups.MyStatsChanged()
  local key = Groups.MyKey()
  if key then Groups.StatsChanged(key) end
end

---------------------------------------------------------------------------
-- your actions. Each returns a result, or nil + reason (a Locale key).
---------------------------------------------------------------------------
local function changed(g)
  Groups.Push(g)
  if ns.UI and ns.UI.OnDataChanged then ns.UI.OnDataChanged() end
end

function Groups.Create(name)
  local me = Groups.MyKey()
  if not me then return nil, "GROUP_NO_TAG" end
  local why
  name, why = Groups.CheckName(name)
  if not name then return nil, why end
  if #Groups.Mine() >= MAX_GROUPS then return nil, "GROUP_TOO_MANY" end
  if Groups.FindByName(name) then return nil, "GROUP_EXISTS" end
  local now = time()
  local g = { id = newId(), name = name, owner = ns.me, mine = true, members = { [me] = { a = now, j = now, name = ns.me } } }
  store()[g.id] = g
  changed(g)
  return g
end

local function tooOld(p) return p and p.version and ns.VersionNewer(MIN_VERSION, p.version) end
local function otherFaction(p) return p and p.faction and ns.myFaction and p.faction ~= ns.myFaction end

-- friends you could invite (character names): online friends, and friends you've heard from
function Groups.Invitable(g)
  local players = ns.Data.RealRealm().players
  local out, seen = {}, {}
  local function add(name)
    local p = players[ns.Data.Resolve(players, name)]
    local key = Groups.FriendKey(name)
    if key and not seen[key] and key ~= Groups.MyKey() and Groups.StateOf(g, key) == "out"
      and not tooOld(p) and not otherFaction(p) then
      seen[key] = true
      out[#out + 1] = name
    end
  end
  for name in pairs(ns.Comm.everyone) do add(name) end
  local names = {}
  for _, p in pairs(players) do
    if p.friend and not p.self and not ns.Data.FriendIsGone(p) then names[#names + 1] = p.name end
  end
  table.sort(names)
  for _, name in ipairs(names) do add(name) end
  table.sort(out)
  return out
end

-- invite a friend (by character name); returns their name
function Groups.Invite(g, name)
  if not g or Groups.MyState(g) ~= "in" then return nil, "GROUP_NOT_IN" end
  local players = ns.Data.RealRealm().players
  name = ns.CleanName(name)
  local resolved = name and ns.Data.Resolve(players, name)
  local p = resolved and players[resolved]
  if not (resolved and (ns.Comm.everyone[resolved] or (p and p.friend))) or otherFaction(p) then
    return nil, "GROUP_NOT_FRIEND"
  end
  local key = Groups.FriendKey(resolved)
  if not key then return nil, "GROUP_NO_FRIEND_TAG" end
  if key == Groups.MyKey() then return nil, "GROUP_ALREADY" end
  -- an older addon ignores group messages: the invite would hang there unanswered
  if tooOld(p) then return nil, "GROUP_OLD_VERSION" end
  if Groups.StateOf(g, key) ~= "out" then return nil, "GROUP_ALREADY" end
  local count = 0
  for _ in pairs(Groups.States(g)) do count = count + 1 end
  if count >= MAX_MEMBERS then return nil, "GROUP_FULL" end
  local m = g.members[key] or {}
  m.a = math.max(time(), (m.r or 0) + 1, (m.j or 0) + 1)
  m.name = resolved
  g.members[key] = m
  changed(g)
  return resolved
end

function Groups.Join(g)
  if not g or Groups.MyState(g) ~= "invited" then return nil, "GROUP_NOT_INVITED" end
  local m = g.members[Groups.MyKey()]
  m.j = math.max(time(), m.a or 0)
  m.name = ns.me
  changed(g)
  -- members you're not friends with learn your numbers through the others
  Groups.MyStatsChanged()
  return true
end

-- leave, or decline an invite
function Groups.Leave(g)
  if not g or Groups.MyState(g) == "out" then return nil, "GROUP_NOT_IN" end
  local m = g.members[Groups.MyKey()]
  m.r = math.max(time(), m.a or 0, m.j or 0)
  changed(g)
  return true
end

-- the leader removes a member (removing yourself = leaving)
function Groups.Remove(g, key)
  if not g then return nil, "GROUP_NOT_IN" end
  if key and key == Groups.MyKey() then return Groups.Leave(g) end
  if Groups.Leader(g) ~= Groups.MyKey() then return nil, "GROUP_NOT_LEADER" end
  if Groups.StateOf(g, key) == "out" then return nil, "GROUP_NOT_MEMBER" end
  local m = g.members[key]
  m.r = math.max(time(), m.a or 0, m.j or 0)
  changed(g)
  return true
end

---------------------------------------------------------------------------
-- receiving
---------------------------------------------------------------------------
-- newest of each time wins (and the name that came with the newest); true if anything changed
local function merge(g, entries)
  local any = false
  for key, e in pairs(entries) do
    local m = g.members[key]
    if not m then
      m = {}
      g.members[key] = m
    end
    local newest = math.max(e.a or 0, e.j or 0)
    if e.name and (not m.name or newest > math.max(m.a or 0, m.j or 0)) then m.name = e.name end
    for _, k in ipairs({ "a", "j", "r" }) do
      if (e[k] or 0) > (m[k] or 0) then
        m[k] = e[k]
        any = true
      end
    end
  end
  return any
end
Groups.Merge = merge

function Groups.OnGroup(sender, f)
  local me = Groups.MyKey()
  local id = cleanId(f.gid)
  if not (me and id) then return end
  local entries = decodeEntries(f.members, f.base)
  local g = store()[id]
  if not g then
    -- only groups you're in or invited to are kept
    if rawState(entries[me]) == "out" then return end
    local name, owner = Groups.CleanName(f.name), ns.CleanName(f.owner)
    if not (name and owner) then return end
    if #Groups.Mine() >= MAX_GROUPS then
      ns.Debug("GROUP-DROP", "too many groups", name)
      return
    end
    g = { id = id, name = name, owner = owner, members = {} }
    store()[id] = g
  end
  local senderKey = Groups.FriendKey(sender)
  local before = Groups.MyState(g)
  local changedNow = merge(g, entries)
  -- the sender was removed or left, but their copy doesn't know it yet (they were offline):
  -- send them ours so they find out (they won't pass it on once they're out)
  if before ~= "out" and senderKey and Groups.StateOf(g, senderKey) == "out"
    and entries[senderKey] and rawState(entries[senderKey]) ~= "out" then
    sendGroup(g, senderKey, sender)
  end
  if not changedNow then return end
  local after = Groups.MyState(g)
  ns.Debug("GROUP", g.name, sender, before .. "->" .. after)
  if after == "invited" and before ~= "invited" and not ns.past then
    local line = L.GROUP_INVITED:format(ns.ClassColored(sender), Groups.Label(g))
    ns.Toast.Push({ category = "progress", icon = ns.ICON.share, title = line, text = L.GROUP_INVITED_TEXT,
      chat = line .. " " .. L.GROUP_INVITED_TEXT })
  elseif after == "out" and before ~= "out" then
    ns.Toast.Chat(L.GROUP_REMOVED:format(Groups.Label(g)))
  end
  -- pass it on, unless you're out (then it was just news for you)
  if after ~= "out" then Groups.Push(g, senderKey) end
  if after == "in" then
    -- members who just joined need everyone's numbers: send what we know
    for key, e in pairs(entries) do
      if key ~= me and rawState(e) == "in" then Groups.StatsChanged(key, senderKey) end
    end
    if before ~= "in" then Groups.MyStatsChanged() end
  end
end

function Groups.OnStats(sender, f)
  local me = Groups.MyKey()
  if not me then return end
  local senderKey = Groups.FriendKey(sender)
  for _, part in ipairs(ns.Split(f.stats or "", ";")) do
    local p = ns.Split(part, ":")
    -- a sender's clock may run fast: never later than now
    local key, k, d, t = p[1], tonumber(p[2]), tonumber(p[3]), ns.Profile.ClampTime(unb36(p[4]))
    if validKey(key) and key ~= me and k and d and t and shareGroup(key) then
      local cur = relayed()[key]
      local direct = senderKey == key
      -- newer wins; same age: the member's own word wins over a relayed copy
      if not cur or t > (cur.t or 0) or (t == cur.t and direct and not cur.direct) then
        local name = ns.CleanName(p[5]) or (cur and cur.name)
        local bt = p[6] and p[6] ~= "" and unb36(p[6]) or nil -- (none from before 0.9)
        relayed()[key] = { k = ns.Count(k), d = ns.Count(d), bt = bt and ns.Count(bt) or nil, t = t, name = name,
          via = (not direct) and sender or nil, direct = direct or nil }
        Groups.StatsChanged(key, senderKey)
      end
    end
  end
end

---------------------------------------------------------------------------
-- totals and upkeep
---------------------------------------------------------------------------
-- members' kills and deaths added up (members whose numbers we know)
function Groups.Totals(g)
  local k, d, n, known = 0, 0, 0, 0
  for key, s in pairs(Groups.States(g)) do
    if s == "in" then
      n = n + 1
      local st = Groups.StatsOf(key)
      if st then k, d, known = k + st.k, d + st.d, known + 1 end
    end
  end
  return k, d, n, known
end

-- stats about accounts in none of your groups (membership records are kept: see the top)
function Groups.Tidy()
  if not Groups.MyKey() then return end -- can't tell who's in your groups without it
  for key in pairs(relayed()) do
    if not shareGroup(key) then relayed()[key] = nil end
  end
end

ns.OnReady(function() C_Timer.After(10, function() ns.Try("groups-tidy", Groups.Tidy) end) end)

Groups.MAX_MEMBERS, Groups.MAX_GROUPS = MAX_MEMBERS, MAX_GROUPS
