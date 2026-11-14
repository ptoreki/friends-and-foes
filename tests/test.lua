-- Expects: mock.lua already run; ADDON_FILES = { {name, src}, ... } in toc order.
local ns = {}
for _, f in ipairs(ADDON_FILES) do
  local chunk, err = load(f.src, "@" .. f.name)
  if not chunk then error(err) end
  chunk("FriendsAndFoes", ns)
end

local passed, failed = 0, 0
local function check(cond, msg)
  if cond then passed = passed + 1 else failed = failed + 1; RESULTS[#RESULTS + 1] = "FAIL: " .. msg end
end
local function count(t) local n = 0; for _ in pairs(t) do n = n + 1 end; return n end

-- boot
FIRE("ADDON_LOADED", "FriendsAndFoes")
FIRE("PLAYER_LOGIN")
FIRE("PLAYER_ENTERING_WORLD")
RUN_TIMERS()
ns.SetDebug(true) -- testers run with debug on
check(ns.Comm.roster.Buddy ~= nil, "roster contains same-realm friend Buddy (first name from Battle.net)")
check(ns.me == "Testme Tester", "own name is First Last: " .. tostring(ns.me))

-- helpers
check(("You create: |cff|Hitem:1|h[x]|h|r."):match(ns.ToPattern(LOOT_ITEM_CREATED_SELF)) ~= nil, "ToPattern craft")
check(ns.VersionNewer("0.10.0", "0.9.9") and not ns.VersionNewer("0.2.0", "0.2.0"), "VersionNewer")
check(ns.CleanName("Bob-Smith") == "Bob Smith" and ns.CleanName("  Bob ") == "Bob", "CleanName hyphen + trim")
check(ns.CleanName("Bob Smith-Nightslayer") == "Bob Smith" and ns.CleanName("Bob", "Smith") == "Bob Smith", "CleanName realm suffix + UnitName pair")
local u = ns.DecodeUnit(ns.EncodeUnit({ name = "Gank", class = "ROGUE", level = 60, guild = "Bad Guys" }))
check(u.name == "Gank" and u.class == "ROGUE" and u.level == 60 and u.guild == "Bad Guys", "unit roundtrip w/ guild")

-- simulated friend events: all kinds, isolated from real data
for _, kind in ipairs(ns.Sim.KINDS) do ns.Sim.Run(kind, false) end
local sim = FriendsAndFoesDB.sim
check(sim ~= nil, "sim store created")
local sf = sim.players["Simfriend Tester"]
check(sf and sf.k == 1 and sf.d == 1 and sf.level == 43,
  "Simfriend K/D/level in sim store: " .. tostring(sf and sf.k) .. "/" .. tostring(sf and sf.d) .. "/" .. tostring(sf and sf.level))
local sg = sim.hitlist["Simganker Shade"]
check(sg and sg.attacks == 1 and sg.kills == 1 and sg.revenge == 1 and sg.guild == "Sim Gankers", "Simganker hitlist: attacks/kills/revenge/guild")
check(sim.hitlist["Simhelper Shade"] == nil, "assist not added to hitlist (kills only)")
check(sim.players["Simhelper Shade"] and sim.players["Simhelper Shade"].a == 1, "assist counted")
check(sim.players["Simganker Shade"].d == 1 and sim.players["Simganker Shade"].k == 1, "enemy K and D")
check(#sim.feed >= 6, "sim feed entries: " .. #sim.feed)
local real = ns.Data.RealRealm()
check(real.players["Simfriend Tester"] == nil and real.hitlist["Simganker Shade"] == nil and #real.feed == 0, "real data untouched by sim")
check(ns.viewSim == true, "window switches to sim view")
check(ns.errors == 0, "no errors after sim (" .. tostring(ns.lastError) .. ")")

-- self sim broadcasts with S-id
SENT = {}
ns.Sim.Run("kill", true)
RUN_TICKERS(2)
check(#SENT == 2, "self sim sent on both routes: " .. #SENT)
check(SENT[1] and SENT[1].payload:find("^3\tKILL\tS") ~= nil, "payload protocol 3 + sim id")

-- clear sim
ns.Sim.Clear()
check(FriendsAndFoesDB.sim == nil and not ns.viewSim, "sim cleared")

-- receive real event over BN, then duplicate over whisper
local function payload(kind, fields, id, version)
  local msg = { kind = kind, id = id, name = "Buddy Pal", class = "PRIEST", level = 31, f = fields }
  local p = ns.Comm.Encode(msg)
  if version then p = p:gsub("\t" .. ns.VERSION .. "\t", "\t" .. version .. "\t", 1) end
  return p
end
local lv = payload("LVL", { level = 32 }, "abc1")
FIRE("BN_CHAT_MSG_ADDON", "FNF1", lv, "WHISPER", 77)
FIRE("CHAT_MSG_ADDON", "FNF1", lv, "WHISPER", "Buddy Pal")
local buddy = real.players["Buddy Pal"]
check(buddy and buddy.level == 32 and buddy.friend, "received LVL applied to Buddy")
check(#real.feed == 1, "duplicate (bn + whisper) applied once, feed=" .. #real.feed)
check(ns.caps.bnet == "ok" and ns.caps.whisper == "ok", "caps ok for both routes")
check(ns.Comm.roster["Buddy Pal"] ~= nil and ns.Comm.roster.Buddy == nil, "roster learned Buddy's surname from the header")
SENT = {}
ns.Comm.SendPayload("ping", "high")
RUN_TICKERS(2)
local wt
for _, s in ipairs(SENT) do if s.route == "whisper" then wt = s.target end end
check(wt == "Buddy Pal", "whispers address First Last: " .. tostring(wt))
ns.Comm.RebuildRoster()
check(ns.Comm.roster["Buddy Pal"] ~= nil, "learned surname survives roster rebuild")

-- Forever has no realms: a friend on another internal server still counts; another WoW version doesn't
local origInfo, origRealmID = C_BattleNet.GetFriendGameAccountInfo, GetRealmID
WOW_PROJECT_ID = 99
C_BattleNet.GetFriendGameAccountInfo = function() return { isOnline = true, clientProgram = "WoW", characterName = "Buddy", realmName = "CAMWOW EU5 Realm 2 PVP", wowProjectID = 99, factionName = "Horde", gameAccountID = 77 } end
ns.Comm.RebuildRoster()
check(ns.Comm.roster["Buddy Pal"] ~= nil, "friend on another Forever server is in the roster")
C_BattleNet.GetFriendGameAccountInfo = function() return { isOnline = true, clientProgram = "WoW", characterName = "Buddy", realmName = "Nightslayer", wowProjectID = 1, factionName = "Horde", gameAccountID = 77 } end
ns.Comm.RebuildRoster()
check(next(ns.Comm.roster) == nil, "friend on another WoW version excluded")
check(ns.Comm.lastRosterReport:find("other WoW version", 1, true) ~= nil, "roster report says why: " .. tostring(ns.Comm.lastRosterReport))
WOW_PROJECT_ID = nil
C_BattleNet.GetFriendGameAccountInfo, GetRealmID = origInfo, origRealmID
ns.Comm.RebuildRoster()
check(FriendsAndFoesDB.caps and FriendsAndFoesDB.caps.bnet == "ok", "caps saved for reports")

-- picked friends: nobody picked = everyone; once someone is picked, only picks send/receive
check(not ns.Comm.GroupActive() and ns.Comm.roster["Buddy Pal"] ~= nil, "no picks: every friend counts")
check(ns.Comm.TagFor("Buddy Pal") == "Buddy#1234", "BattleTag known for Buddy Pal")
check(select(2, ns.Comm.FindCandidate("buddy")) == "Buddy#1234" and ns.Comm.FindCandidate("BUDDY#1234") == "Buddy Pal"
  and ns.Comm.FindCandidate("buddy pal") == "Buddy Pal", "FindCandidate by first name, BattleTag, full name")
check(ns.Comm.FindCandidate("nobody") == nil, "FindCandidate miss")
FriendsAndFoesDB.group = { ["Someone#9"] = true }
ns.Comm.RebuildRoster()
check(ns.Comm.GroupActive() and next(ns.Comm.roster) == nil and ns.Comm.everyone["Buddy Pal"] ~= nil,
  "unpicked friend dropped from roster, still listed for picking")
check(ns.Comm.lastRosterReport:find("not picked", 1, true) ~= nil, "roster report says not picked")
local feedBefore = #real.feed
FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("LVL", { level = 40 }, "pick1"), "WHISPER", 77)
FIRE("CHAT_MSG_ADDON", "FNF1", payload("LVL", { level = 40 }, "pick2"), "WHISPER", "Buddy Pal")
check(#real.feed == feedBefore and real.players["Buddy Pal"].level == 32, "unpicked friend's events ignored on both routes")
SENT = {}
ns.Comm.SendPayload("ping", "high")
RUN_TICKERS(2)
check(#SENT == 0, "nothing sent to unpicked friend: " .. #SENT)
check(ns.Comm.TogglePick("Buddy#1234") == true and ns.Comm.roster["Buddy Pal"] ~= nil, "picking Buddy adds him back")
FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("LVL", { level = 32 }, "pick3"), "WHISPER", 77)
check(#real.feed == feedBefore + 1, "picked friend's events received")
check(ns.Comm.TogglePick("Buddy#1234") == false, "unpick")
ns.Comm.ClearPicks()
check(not ns.Comm.GroupActive() and ns.Comm.roster["Buddy Pal"] ~= nil, "clearing picks = everyone again")
check(ns.errors == 0, "no errors in picks (" .. tostring(ns.lastError) .. ")")
-- UI: Friends tab lists the friend, slash command toggles a pick
ns.UI.Show("friends")
SlashCmdList.FRIENDSANDFOES("group")
SlashCmdList.FRIENDSANDFOES("group buddy")
check(ns.Comm.IsPicked("Buddy#1234"), "/fnf group buddy picks him")
SlashCmdList.FRIENDSANDFOES("group all")
check(not ns.Comm.GroupActive(), "/fnf group all clears picks")
check(ns.errors == 0, "no errors in Friends tab / group command (" .. tostring(ns.lastError) .. ")")

-- a different "Buddy" (same first name, other surname) can't pose as our friend
FIRE("CHAT_MSG_ADDON", "FNF1", payload("LVL", { level = 50 }, "imp1"), "WHISPER", "Buddy Fake")
check(real.players["Buddy Fake"] == nil and buddy.level == 32, "same-first-name stranger rejected")

-- old (0.2, protocol 2) client: dropped, flagged, no error
FIRE("BN_CHAT_MSG_ADDON", "FNF1", "2\tLVL\tq\tPRIEST\t1\t0.2.0\t5", "WHISPER", 77)
check(ns.errors == 0, "old protocol handled without error (" .. tostring(ns.lastError) .. ")")

-- stranger whisper ignored
FIRE("CHAT_MSG_ADDON", "FNF1", payload("LVL", { level = 5 }, "zz1"), "WHISPER", "Stranger")
check(real.players.Stranger == nil, "non-friend whisper ignored")

-- newer version
FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("LVL", { level = 33 }, "abc2", "9.9.9"), "WHISPER", 77)
check(buddy.version == "9.9.9", "friend version recorded")
FIRE("BN_CHAT_MSG_ADDON", "FNF1", "4\tLVL\tq\tX\tX\t1\t9.9.9\t5", "WHISPER", 77)
check(ns.errors == 0, "newer protocol handled without error (" .. tostring(ns.lastError) .. ")")

-- received KILL on a hitlist enemy -> revenge; DIE builds hitlist
FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("DIE", { zone = "Duskwood", killer = "Rogz Fang:ROGUE:60:Gank Squad", conf = "s", assists = "" }, "d1"), "WHISPER", 77)
local rogz = real.hitlist["Rogz Fang"]
check(rogz and rogz.kills == 1 and rogz.suspect == 1, "DIE -> hitlist with suspect kill")
FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("KILL", { victim = "Rogz", vclass = "ROGUE", vlevel = 60, vguild = "", zone = "Duskwood" }, "k1"), "WHISPER", 77)
check(rogz.revenge == 1 and buddy.k == 1, "KILL by bare first name resolves to Rogz Fang -> revenge + takedown")
check(real.players.Rogz == nil, "no duplicate bare-name record for Rogz")

-- Forever names: "Kragg" (old unit scan) + "Kragg Bear" (death recap) are one player
local m1 = ns.Data.Hit("Kragg")
m1.attacks = 1
local m2 = ns.Data.Hit("Kragg Bear")
m2.kills = m2.kills + 1
check(real.hitlist.Kragg == nil and real.hitlist["Kragg Bear"].attacks == 1 and real.hitlist["Kragg Bear"].kills == 1,
  "bare first name folds into the full name when it shows up")
-- shared first names are never guessed
ns.Data.Hit("Ash Vale"); ns.Data.Hit("Ash Stone")
check(ns.Data.FindHit("Ash") == nil and ns.Data.FindHit("Ash Vale") ~= nil, "ambiguous first name not resolved")
-- migration of 0.2.0 saved data
local db = { realms = { R = {
  players = { Kragg = { name = "Kragg", enemy = true, k = 0, d = 0, a = 2, level = 24 },
              ["Kragg Bear"] = { name = "Kragg Bear", enemy = true, k = 1, d = 0, a = 0 } },
  hitlist = { Kragg = { name = "Kragg", attacks = 1, kills = 0, suspect = 0, revenge = 0, victims = { Testvictim = true }, lastSeen = 5 },
              ["Kragg Bear"] = { name = "Kragg Bear", attacks = 0, kills = 1, suspect = 0, revenge = 0, victims = { Testvictim = true }, lastSeen = 9 },
              Ash = { name = "Ash", attacks = 1, kills = 0, suspect = 0, revenge = 0, victims = {} },
              ["Ash Vale"] = { name = "Ash Vale", attacks = 1, kills = 0, suspect = 0, revenge = 0, victims = {} },
              ["Ash Stone"] = { name = "Ash Stone", attacks = 1, kills = 0, suspect = 0, revenge = 0, victims = {} } },
  feed = {} } } }
local moved = ns.Data.FoldFirstNames(db)
local mh, mp = db.realms.R.hitlist["Kragg Bear"], db.realms.R.players["Kragg Bear"]
check(moved == 2 and db.realms.R.hitlist.Kragg == nil and mh.attacks == 1 and mh.kills == 1 and mh.lastSeen == 9,
  "migration merges Kragg into Kragg Bear (moved " .. moved .. ")")
check(mp.k == 1 and mp.a == 2 and mp.level == 24, "migration merges K/D/A and keeps level")
check(db.realms.R.hitlist.Ash ~= nil, "migration leaves ambiguous bare names alone")
-- 0.3.1 data stored per internal server name is merged into one Forever store
local sdb = { realms = {
  ["CAMWOW EU4 Realm 8 PvP"] = { players = { ["Kragg Bear"] = { name = "Kragg Bear", k = 1, d = 0, a = 0 } },
    hitlist = { ["Kragg Bear"] = { name = "Kragg Bear", attacks = 1, kills = 1, suspect = 0, revenge = 0, victims = { A = true } } },
    feed = { { t = 2, text = "b" } } },
  ["CAMWOW EU5 Realm 2 PVP"] = { players = { ["Kragg Bear"] = { name = "Kragg Bear", k = 2, d = 1, a = 0 } },
    hitlist = { ["Kragg Bear"] = { name = "Kragg Bear", attacks = 2, kills = 0, suspect = 0, revenge = 0, victims = { B = true } } },
    feed = { { t = 1, text = "a" } } },
} }
check(ns.Data.MergeServerStores(sdb) == 2, "two server stores merged")
local fz = sdb.realms.Forever
check(fz and next(sdb.realms, next(sdb.realms)) == nil, "only the Forever store remains")
check(fz.players["Kragg Bear"].k == 3 and fz.hitlist["Kragg Bear"].attacks == 3 and fz.hitlist["Kragg Bear"].victims.A and fz.hitlist["Kragg Bear"].victims.B, "server merge adds counters, unions victims")
check(fz.feed[1].text == "a" and fz.feed[2].text == "b", "merged feed in time order")
-- unit lookups used by death resolution
local tbl = { ["Kragg Bear"] = 1, ["Ash Vale"] = 2, ["Ash Stone"] = 3, Solo = 4 }
check(ns.PvP.FindByName(tbl, "Kragg") == 1 and ns.PvP.FindByName(tbl, "Ash") == nil
  and ns.PvP.FindByName(tbl, "Solo Wolf") == 4 and ns.PvP.FindByName(tbl, "Kragg Fox") == nil, "FindByName rules")

-- own loot: epic BoE emits + queues broadcast
SENT = {}
FIRE("CHAT_MSG_LOOT", "You receive loot: |cffa335ee|Hitem:12584::::::::60:::::::|h[Sword]|h|r.")
RUN_TICKERS(2)
check(real.players["Testme Tester"] and real.players["Testme Tester"].lastText and real.players["Testme Tester"].lastText:find("looted") ~= nil, "own loot recorded")
check(#SENT == 2 and SENT[1].payload:find("^3\tLOOT\t%w+\tTestme Tester\t") ~= nil, "own loot broadcast")

-- throttle: 30 events -> at most bucket size sent per route at first
SENT = {}
for i = 1, 30 do ns.Comm.SendPayload("x" .. i, "normal") end
RUN_TICKERS(1)
local first = #SENT
check(first <= 16 and first >= 2, "throttle limits initial burst: " .. first)
RUN_TICKERS(200)
check(#SENT == 60, "all 60 sends eventually delivered: " .. #SENT)

-- priority: high goes before bulk
SENT = {}
for _, r in ipairs({ "a", "b", "c" }) do ns.Comm.SendPayload("bulk" .. r, "bulk") end
ns.Comm.SendPayload("HIGH", "high")
RUN_TICKERS(200)
check(SENT[1].payload == "HIGH", "high priority sent first")

-- 255-byte fit: long guilds stripped
local long = string.rep("G", 24)
local big = { kind = "DIE", id = "x1", class = "WARRIOR", level = 60, f = {
  zone = string.rep("Z", 48),
  killer = ns.EncodeUnit({ name = "Abcdefghijkl Abcdefghijkl", class = "WARLOCK", level = 60, guild = long }),
  conf = "c",
  assists = ns.EncodeUnits({
    { name = "Bcdefghijklm Bcdefghijklm", class = "WARLOCK", level = 60, guild = long },
    { name = "Cdefghijklmn Cdefghijklmn", class = "WARLOCK", level = 60, guild = long },
    { name = "Defghijklmno Defghijklmno", class = "WARLOCK", level = 60, guild = long },
  }, 3) } }
local fit = ns.Comm.Fit(big)
check(fit and #fit <= 255, "Fit strips guilds to stay <=255 (" .. (fit and #fit or "nil") .. ")")

-- hitlist share: packing + receiving merge
for i = 1, 45 do
  local h = ns.Data.Hit("Enemy" .. i .. " Foe")
  h.class, h.level, h.guild, h.attacks, h.kills, h.lastSeen = "MAGE", 60, "Some Long Guild Name", i, 1, time() - i * 60
end
SENT = {}
local shared = ns.Comm.ShareHitlist()
check(shared == 40, "share capped at 40: " .. shared)
RUN_TICKERS(400)
local maxLen, hitMsgs = 0, 0
for _, s in ipairs(SENT) do
  if s.payload:find("^3\tHIT\t") then
    hitMsgs = hitMsgs + 1
    if #s.payload > maxLen then maxLen = #s.payload end
  end
end
check(maxLen <= 255 and hitMsgs > 0, "share payloads <=255 (max " .. maxLen .. ", msgs " .. hitMsgs .. ")")
-- receive a share chunk from Buddy
local before = count(real.hitlist)
FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("HIT", { share = "s1", entries = "Newguy Hunt:HUNTER:59:Their Guild:3:2:0:5;Enemy1 Foe:MAGE:60::99:7:1:1;Peaceful Pete:MAGE:20::4:0:0:2" }, "h1"), "WHISPER", 77)
check(count(real.hitlist) == before + 1, "share adds new entry")
check(real.hitlist["Enemy1 Foe"].attacks == 99 and real.hitlist["Enemy1 Foe"].kills == 7, "share merges with max()")
check(real.hitlist["Newguy Hunt"].sharedBy == "Buddy Pal", "sharedBy recorded")
check(real.hitlist["Peaceful Pete"] == nil, "shared entry with no kills is not added")

-- do-not-disturb: progress held in combat, pvp shown
local function drainToasts()
  for _ = 1, 50 do
    for _, f in ipairs(FRAMES) do
      if f._scripts.OnUpdate and f.spec then f._scripts.OnUpdate(f, 10) end
    end
  end
end
drainToasts()
IN_COMBAT = true
local pvpBefore = SOUNDS_PLAYED or 0
ns.Toast.Push({ kind = "attacked", category = "pvp", title = "p", text = "q" })
check((SOUNDS_PLAYED or 0) == pvpBefore + 1, "pvp toast shown during combat")
drainToasts()
local beforeSounds = SOUNDS_PLAYED or 0
ns.Toast.Push({ kind = "level", category = "progress", title = "x", text = "y", milestone = true })
local heldSounds = SOUNDS_PLAYED or 0
IN_COMBAT = false
FIRE("PLAYER_REGEN_ENABLED")
check(heldSounds == beforeSounds and (SOUNDS_PLAYED or 0) > heldSounds, "progress toast held in combat, shown after")

-- routing: progress goes to chat, milestones toast, PvP toasts, "off" silences
drainToasts()
local function toasted(fn) local s = ns.Toast.shown or 0; CHAT = {}; fn(); drainToasts(); return (ns.Toast.shown or 0) > s end
local t1 = toasted(function() FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("LVL", { level = 45 }, "r1"), "WHISPER", 77) end)
check(not t1 and #CHAT == 1 and CHAT[1]:find("reached level 45", 1, true) ~= nil, "ordinary level-up goes to chat: " .. tostring(CHAT[1]))
local t2 = toasted(function() FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("LVL", { level = 60 }, "r2"), "WHISPER", 77) end)
check(t2 and #CHAT == 0, "level 60 is a toast")
local epic = "|cffa335ee|Hitem:12584::::::::60:::::::|h[Sword]|h|r"
local t3 = toasted(function() FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("LOOT", { link = epic, source = "loot" }, "r3"), "WHISPER", 77) end)
check(t3 and #CHAT == 0, "looted epic BoE is a toast")
local t4 = toasted(function() FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("LOOT", { link = epic, source = "craft" }, "r4"), "WHISPER", 77) end)
check(not t4 and #CHAT == 1, "crafted epic goes to chat")
local t5 = toasted(function() FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("ATK", { enc = "e9", zone = "Hillsbrad Foothills (Tarren Mill)", attackers = "Zed Q:ROGUE:60:" }, "r5"), "WHISPER", 77) end)
check(t5 and #CHAT == 0, "friend attacked in my zone is a toast")
local t5b = toasted(function() FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("ATK", { enc = "e10", zone = "Duskwood", attackers = "Zed Q:ROGUE:60:" }, "r5b"), "WHISPER", 77) end)
check(not t5b and #CHAT == 1 and CHAT[1]:find("Duskwood", 1, true) ~= nil, "friend attacked in another zone is a chat line")
ns.S().nearbyOnly = false
local t5c = toasted(function() FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("ATK", { enc = "e11", zone = "Duskwood", attackers = "Zed Q:ROGUE:60:" }, "r5c"), "WHISPER", 77) end)
check(t5c, "nearby-only off: far fights toast again")
ns.S().nearbyOnly = true
check(ns.PvP.IsMyZone("Hillsbrad Foothills") and ns.PvP.IsMyZone("Hillsbrad Foothills (Southshore)")
  and not ns.PvP.IsMyZone("Hillsbrad") and not ns.PvP.IsMyZone("?") and not ns.PvP.IsMyZone(nil), "IsMyZone matching")
ns.S().show.level = "off"
local t6 = toasted(function() FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("LVL", { level = 60 }, "r6"), "WHISPER", 77) end)
check(not t6 and #CHAT == 0, "off silences even milestones")
ns.S().show.level = "chat"
check(real.hitlist["Zed Q"] == nil and real.players["Zed Q"].atk == 3 and #real.feed > 0,
  "attacks alone: toasts/feed and enemy record, but not on the hitlist")
FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("DIE", { zone = "Duskwood", killer = "Zed Q:ROGUE:60:", conf = "c", assists = "Ass Ist:MAGE:60:" }, "zk1"), "WHISPER", 77)
check(real.hitlist["Zed Q"] and real.hitlist["Zed Q"].kills == 1 and real.hitlist["Zed Q"].attacks == 3,
  "a kill adds them, carrying over earlier attacks")
check(real.hitlist["Ass Ist"] == nil and real.players["Ass Ist"].a == 1, "assist counted, but not added to the hitlist")

-- hitlist marks: nameplate skull + tooltip line
local plate = CreateFrame()
C_NamePlate = { GetNamePlateForUnit = function(u) if u == "nameplate1" then return plate end end }
local origUnitName, origIsPlayer = UnitName, UnitIsPlayer
UnitName = function(u) if u == "nameplate1" or u == "mouseover" then return "Zed", "Q" end return origUnitName(u) end
UnitIsPlayer = function(u) return u == "nameplate1" or u == "mouseover" end
FIRE("NAME_PLATE_UNIT_ADDED", "nameplate1")
check(plate.fnfMark ~= nil and plate.fnfMark:IsShown(), "hitlist player gets a nameplate skull")
ns.S().mark = false; ns.Marks.Refresh()
check(not plate.fnfMark:IsShown(), "skull hidden when marking is off")
ns.S().mark = true; ns.Marks.Refresh()
check(ns.Marks.HitFor("mouseover") == real.hitlist["Zed Q"], "tooltip lookup finds the hitlist entry")
FIRE("NAME_PLATE_UNIT_REMOVED", "nameplate1")
check(not plate.fnfMark:IsShown(), "skull hidden when plate removed")
UnitName, UnitIsPlayer, C_NamePlate = origUnitName, origIsPlayer, nil
check(ns.errors == 0, "no errors in routing/marks (" .. tostring(ns.lastError) .. ")")

-- a friend's kill defaults to a toast; an old saved "chat" switches once
check(ns.S().show.kill == "toast", "friend's kill defaults to toast")
ns.S().show.kill, ns.S().killToast = "chat", nil
FIRE("ADDON_LOADED", "FriendsAndFoes")
check(ns.S().show.kill == "toast" and ns.S().killToast, "old 'chat' default switched to toast once")
ns.S().show.kill = "chat"
FIRE("ADDON_LOADED", "FriendsAndFoes")
check(ns.S().show.kill == "chat", "a later choice of chat is kept")
ns.S().show.kill = "toast"

-- once: attack-only hitlist entries (no kills, no note) are dropped
local mdb = { realms = { Forever = { players = {}, feed = {}, hitlist = {
  A = { name = "A", attacks = 2, kills = 0 }, B = { name = "B", attacks = 1, kills = 1 }, C = { name = "C", attacks = 1, kills = 0, note = "watch" } } } } }
local dropped = ns.Data.DropAttackOnly(mdb)
local mh = mdb.realms.Forever.hitlist
check(dropped == 1 and mh.A == nil and mh.B and mh.C and mdb.hitlistKillsOnly, "attack-only entries dropped, kills and notes kept")
mh.D = { name = "D", attacks = 1, kills = 0 }
check(ns.Data.DropAttackOnly(mdb) == 0 and mh.D, "cleanup runs only once")

-- prune
local old = ns.Data.Player("Oldie")
old.enemy, old.lastSeen = true, time() - 100 * 86400
ns.Data.Prune()
check(real.players.Oldie == nil and real.hitlist["Enemy1 Foe"] ~= nil, "prune removes stale harmless enemies only")

-- UI + slash commands exercise
SlashCmdList.FRIENDSANDFOES("")
for _, tab in ipairs({ "hitlist", "players", "feed" }) do ns.UI.SelectTab(tab) end
ns.UI.SetPlayerFilter("friends")
ns.UI.SetPlayerFilter("enemies")
SlashCmdList.FRIENDSANDFOES("options")
ns.SetDebug(false); ns.Options.Refresh(); ns.SetDebug(true); ns.Options.Refresh()
FriendsAndFoes_OnAddonCompartmentClick(nil, "LeftButton")
FriendsAndFoes_OnAddonCompartmentClick(nil, "RightButton")
check(ns.errors == 0, "window tabs, options panel, addon menu: no errors (" .. tostring(ns.lastError) .. ")")
ns.UI.ShowPlayer("Rogz Fang")
SlashCmdList.FRIENDSANDFOES("sim all")
RUN_TIMERS()
SlashCmdList.FRIENDSANDFOES("sim clear")
SlashCmdList.FRIENDSANDFOES("status")
SlashCmdList.FRIENDSANDFOES("share")
SlashCmdList.FRIENDSANDFOES("test")
SlashCmdList.FRIENDSANDFOES("bogus")
check(ns.errors == 0, "no errors after UI/slash exercise (" .. tostring(ns.lastError) .. ")")
check(#FriendsAndFoesDB.errorLog == 0, "error log empty")

-- error log always on: force an error in a handler
-- flavor: varied PvP wording from history (deterministic picks in tests)
ns.Flavor.random = function() return 1 end
local O = ns.Flavor.Ordinal
check(O(1) == "1st" and O(2) == "2nd" and O(3) == "3rd" and O(4) == "4th" and O(11) == "11th" and O(12) == "12th"
  and O(13) == "13th" and O(21) == "21st" and O(22) == "22nd" and O(111) == "111th", "ordinals")
local function lastFeed() return real.feed[#real.feed].text end
for i = 1, 3 do
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("DIE", { zone = "Duskwood", killer = "Nem Esis:ROGUE:60:", conf = "c", assists = "" }, "fd" .. i), "WHISPER", 77)
end
check(lastFeed():find("killed", 1, true) and lastFeed():find("again", 1, true) and lastFeed():find("3rd time", 1, true)
  and lastFeed():find("deaths in 1 min", 1, true), "repeat killer + death spree: " .. lastFeed())
check(real.hitlist["Nem Esis"].kv["Buddy Pal"] == 3, "per-victim kill count kept on the hitlist entry")
for i = 4, 5 do
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("DIE", { zone = "Duskwood", killer = "Nem Esis:ROGUE:60:", conf = "c", assists = "" }, "fd" .. i), "WHISPER", 77)
end
check(lastFeed():find("has", 1, true) and lastFeed():find("number", 1, true) and lastFeed():find("5th time", 1, true), "5th death to the same killer: " .. lastFeed())
FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("ATK", { enc = "fa1", zone = "Duskwood", attackers = "Nem Esis:ROGUE:60:" }, "fa1"), "WHISPER", 77)
check(lastFeed():find("has killed them 5 times before", 1, true) ~= nil, "attacker's history on this friend: " .. lastFeed())
for i = 1, 3 do
  ADVANCE(20)
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("KILL", { victim = "Vic Tim", vclass = "MAGE", vlevel = "60", vguild = "", zone = "Duskwood" }, "fk" .. i), "WHISPER", 77)
end
check(lastFeed():find("owns", 1, true) and lastFeed():find("3rd kill on them", 1, true) and lastFeed():find("kills in", 1, true),
  "repeat kill + streak: " .. lastFeed())
-- revenge on behalf of another friend
local nem = real.hitlist["Nem Esis"]
nem.victims["Alice Ally"] = true
ADVANCE(20)
FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("KILL", { victim = "Nem Esis", vclass = "ROGUE", vlevel = "60", vguild = "", zone = "Duskwood" }, "fk9"), "WHISPER", 77)
check(lastFeed():find("avenged", 1, true) and lastFeed():find("Alice Ally", 1, true) and nem.revenge >= 1, "revenge names the avenged friend: " .. lastFeed())
ns.S().flavor = false
ADVANCE(20)
FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("KILL", { victim = "Vic Tim", vclass = "MAGE", vlevel = "60", vguild = "", zone = "Duskwood" }, "fk10"), "WHISPER", 77)
check(lastFeed():find("killed", 1, true) and not lastFeed():find("owns", 1, true), "flavor off: plain wording: " .. lastFeed())
local function plain(s) return (s:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", "")) end
check(plain(lastFeed()) == "Buddy Pal killed Vic Tim - Duskwood", "compact kill: " .. plain(lastFeed()))
FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("DIE", { zone = "Duskwood", killer = "Nem Esis:ROGUE:60:", conf = "c", assists = "" }, "fc1"), "WHISPER", 77)
check(plain(lastFeed()) == "Buddy Pal killed by Nem Esis - Duskwood", "compact death: " .. plain(lastFeed()))
FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("ATK", { enc = "fc2", zone = "Duskwood", attackers = "Nem Esis:ROGUE:60:" }, "fc2"), "WHISPER", 77)
check(plain(lastFeed()) == "Buddy Pal attacked by Nem Esis - Duskwood", "compact attack: " .. plain(lastFeed()))
ADVANCE(20)
FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("KILL", { victim = "Nem Esis", vclass = "ROGUE", vlevel = "60", vguild = "", zone = "Duskwood" }, "fc3"), "WHISPER", 77)
check(plain(lastFeed()) == "Buddy Pal killed Nem Esis (revenge) - Duskwood", "compact revenge: " .. plain(lastFeed()))
-- the toast is the same single line
drainToasts()
local shownToast
for _, f in ipairs(FRAMES) do if f.spec and f.spec.kind == "kill" then shownToast = f.spec end end
check(shownToast == nil or (shownToast.text == nil and plain(shownToast.title) == plain(lastFeed())), "compact toast = one line")
ns.Toast.Push({ kind = "kill", category = "pvp", title = "T", text = "X", chat = "line", milestone = true })
local top
for _, f in ipairs(FRAMES) do if f.spec and f.spec.chat == "line" then top = f.spec end end
check(top and top.title == "line" and top.text == nil, "compact toast uses the chat line as its only text")
ns.S().flavor = true
check(ns.errors == 0, "no errors in flavor (" .. tostring(ns.lastError) .. ")")

-- per-event sound, whatever the display; milestones chime even when their kind is silent
local snd = ns.S().sound
snd.level = true
local s0 = SOUNDS_PLAYED or 0
ns.Toast.Push({ kind = "level", category = "progress", title = "x", chat = "x" })
check((SOUNDS_PLAYED or 0) == s0 + 1, "chat line plays its event's sound when on")
snd.level = false
s0 = SOUNDS_PLAYED or 0
ns.Toast.Push({ kind = "level", category = "progress", title = "x", chat = "x" })
check((SOUNDS_PLAYED or 0) == s0, "silent when that event's sound is off")
drainToasts()
s0 = SOUNDS_PLAYED or 0
ns.Toast.Push({ kind = "level", category = "progress", title = "x", milestone = true })
check((SOUNDS_PLAYED or 0) == s0 + 1, "milestone chimes even with its sound off")
-- 0.4.2 sound settings (per category) migrate to per event
snd.pvp, snd.progress = false, true
FIRE("ADDON_LOADED", "FriendsAndFoes")
check(snd.pvp == nil and snd.progress == nil and snd.attacked == false and snd.died == false and snd.kill == false and snd.loot == true,
  "old per-category sound settings migrated")
snd.attacked, snd.died = true, true

-- performance: send pump idles when nothing is queued
RUN_TICKERS(50)
check(ns.Comm.QueuedCount() == 0 and not ns.Comm.PumpRunning(), "send pump stops when the queue is empty")
SENT = {}
ns.Comm.SendPayload("ping", "high")
check(ns.Comm.PumpRunning(), "send pump starts when something is queued")
RUN_TICKERS(2)
check(#SENT == 2 and not ns.Comm.PumpRunning(), "queued message sent, pump idle again: " .. #SENT)
-- performance: debug log trimmed in batches, capped at 2000
local dlog = FriendsAndFoesDB.debugLog
for i = 1, 2300 do ns.Debug("FILL", i) end
check(#dlog <= 2250 and #dlog >= 2000 and dlog[#dlog]:find("[FILL] 2300", 1, true) ~= nil, "debug log capped, newest kept: " .. #dlog)
-- performance: debug switches itself off after 7 days
ns.S().debugSince = time() - 8 * 86400
FIRE("PLAYER_LOGIN")
check(not ns.S().debug and #dlog <= 2000, "debug auto-off after 7 days, log trimmed at login")
-- roster report only built while debugging
ns.Comm.lastRosterReport = nil
ns.Comm.RebuildRoster()
check(ns.Comm.lastRosterReport == nil and ns.Comm.roster["Buddy Pal"] ~= nil, "no roster report with debug off, roster still built")
ns.S().debug = false
ns.Try("forced", function() error("boom") end)
check(#FriendsAndFoesDB.errorLog == 1, "errors recorded even with debug off")

RESULTS[#RESULTS + 1] = string.format("%d passed, %d failed", passed, failed)
