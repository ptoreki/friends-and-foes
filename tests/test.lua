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
check(lastFeed():find("killed", 1, true) and lastFeed():find("again (3rd)", 1, true)
  and lastFeed():find("th today", 1, true) and not lastFeed():find("/", 1, true), "repeat killer + deaths today: " .. lastFeed())
check(real.hitlist["Nem Esis"].kv["Buddy Pal"] == 3, "per-victim kill count kept on the hitlist entry")
for i = 4, 5 do
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("DIE", { zone = "Duskwood", killer = "Nem Esis:ROGUE:60:", conf = "c", assists = "" }, "fd" .. i), "WHISPER", 77)
end
check(lastFeed():find("has", 1, true) and lastFeed():find("number (5th)", 1, true), "5th death to the same killer: " .. lastFeed())
FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("ATK", { enc = "fa1", zone = "Duskwood", attackers = "Nem Esis:ROGUE:60:" }, "fa1"), "WHISPER", 77)
check(lastFeed():find("(killed them 5", 1, true) ~= nil, "attacker's history on this friend: " .. lastFeed())
for i = 1, 3 do
  ADVANCE(20)
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("KILL", { victim = "Vic Tim", vclass = "MAGE", vlevel = "60", vguild = "", zone = "Duskwood" }, "fk" .. i), "WHISPER", 77)
end
check(lastFeed():find("owns", 1, true) and lastFeed():find("(3rd)", 1, true) and not lastFeed():find("/", 1, true),
  "repeat kill: " .. lastFeed())
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
check(plain(lastFeed()) == "Buddy Pal killed Vic Tim · Duskwood", "compact kill: " .. plain(lastFeed()))
FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("DIE", { zone = "Duskwood", killer = "Nem Esis:ROGUE:60:", conf = "c", assists = "" }, "fc1"), "WHISPER", 77)
check(plain(lastFeed()) == "Buddy Pal killed by Nem Esis · Duskwood", "compact death: " .. plain(lastFeed()))
FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("ATK", { enc = "fc2", zone = "Duskwood", attackers = "Nem Esis:ROGUE:60:" }, "fc2"), "WHISPER", 77)
check(plain(lastFeed()) == "Buddy Pal attacked by Nem Esis · Duskwood", "compact attack: " .. plain(lastFeed()))
ADVANCE(20)
FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("KILL", { victim = "Nem Esis", vclass = "ROGUE", vlevel = "60", vguild = "", zone = "Duskwood" }, "fc3"), "WHISPER", 77)
check(plain(lastFeed()) == "Buddy Pal killed Nem Esis (revenge) · Duskwood", "compact revenge: " .. plain(lastFeed()))
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
check(ns.Flavor.Place("Hillsbrad Foothills (Tarren Mill)") == "Tarren Mill" and ns.Flavor.Place("Duskwood") == "Duskwood" and ns.Flavor.Place(nil) == "?", "place: subzone if any, else zone")
check(ns.errors == 0, "no errors in flavor (" .. tostring(ns.lastError) .. ")")

-- kill streaks: counted by the killer's own client, sent with KILL, ended by a PvP death
FriendsAndFoesCharDB.streak = 0
SENT = {}
for i = 1, 3 do
  ADVANCE(20)
  ns.Events.Emit("KILL", { victim = "Streak Victim" .. i, vclass = "MAGE", vlevel = "60", vguild = "", zone = "Duskwood" })
end
check(FriendsAndFoesCharDB.streak == 3, "own streak counts kills in a row: " .. tostring(FriendsAndFoesCharDB.streak))
RUN_TICKERS(4)
local lastKill
for _, s in ipairs(SENT) do if s.payload:find("	KILL	", 1, true) then lastKill = s.payload end end
check(lastKill and lastKill:sub(-2) == "	3", "KILL carries the streak: " .. tostring(lastKill))
ns.Events.Emit("DIE", { zone = "Duskwood", killer = "Ender Man:ROGUE:60:", conf = "c", assists = "" })
check(FriendsAndFoesCharDB.streak == 0, "a PvP death resets the streak")
check(lastFeed():find("ended a 3-kill streak", 1, true) ~= nil, "death notes the streak it ended: " .. lastFeed())
-- received
ns.S().show.kill = "chat"
FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("KILL", { victim = "Row Three", vclass = "MAGE", vlevel = "60", vguild = "", zone = "Duskwood", streak = "3" }, "ks3"), "WHISPER", 77)
check(lastFeed():find("3 in a row", 1, true) ~= nil, "received streak shown: " .. lastFeed())
local streakToast = toasted(function()
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("KILL", { victim = "Row Five", vclass = "MAGE", vlevel = "60", vguild = "", zone = "Duskwood", streak = "5" }, "ks5"), "WHISPER", 77)
end)
check(streakToast and lastFeed():find("5 in a row!", 1, true) ~= nil, "5 in a row is a milestone toast even with kills on chat")
ns.S().show.kill = "toast"
FIRE("BN_CHAT_MSG_ADDON", "FNF1", "3	KILL	old1	Buddy Pal	PRIEST	31	0.5.3	Old Client	MAGE	60		Duskwood", "WHISPER", 77)
check(lastFeed():find("Old Client", 1, true) and not lastFeed():find("in a row", 1, true), "message from an older client (no streak field) still works")
FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("DIE", { zone = "Duskwood", killer = "Ender Man:ROGUE:60:", conf = "c", assists = "", ended = "6" }, "kd6"), "WHISPER", 77)
check(lastFeed():find("ended a 6-kill streak", 1, true) ~= nil, "received death notes the ended streak: " .. lastFeed())
check(ns.errors == 0, "no errors in streaks (" .. tostring(ns.lastError) .. ")")

-- WoW Forever's honor message has no name: "You have been awarded 7 Honor."
-- the victim comes from a dead enemy on screen, else the kill is sent without a name
do
  local enemyUnits = {} -- unit -> { first, surname, dead }
  local o = { UnitExists = UnitExists, UnitIsPlayer = UnitIsPlayer, UnitFactionGroup = UnitFactionGroup, UnitName = UnitName,
    UnitClass = UnitClass, UnitLevel = UnitLevel, UnitIsDeadOrGhost = UnitIsDeadOrGhost, UnitIsUnit = UnitIsUnit }
  UnitExists = function(u) return enemyUnits[u] ~= nil or o.UnitExists(u) end
  UnitIsPlayer = function(u) if enemyUnits[u] then return true end return o.UnitIsPlayer and o.UnitIsPlayer(u) end
  UnitFactionGroup = function(u) if enemyUnits[u] then return "Alliance" end return o.UnitFactionGroup(u) end
  UnitName = function(u) local e = enemyUnits[u]; if e then return e[1], e[2] end return o.UnitName(u) end
  UnitClass = function(u) if enemyUnits[u] then return "Rogue", "ROGUE" end return o.UnitClass(u) end
  UnitLevel = function(u) if enemyUnits[u] then return 24 end return o.UnitLevel(u) end
  UnitIsDeadOrGhost = function(u) local e = enemyUnits[u]; return e and e[3] or false end
  UnitIsUnit = function() return false end
  local HONOR = "You have been awarded 7 Honor."
  FriendsAndFoesCharDB.streak = 0
  -- 1) dead enemy target
  enemyUnits.target = { "Corpse", "Target", true }
  ADVANCE(30)
  FIRE("CHAT_MSG_COMBAT_HONOR_GAIN", HONOR)
  check(lastFeed():find("Corpse Target", 1, true) ~= nil and ns.caps.honor == "ok", "nameless honor: victim = dead enemy target: " .. lastFeed())
  -- the same corpse isn't credited twice
  ADVANCE(1)
  FIRE("CHAT_MSG_COMBAT_HONOR_GAIN", HONOR)
  check(lastFeed():find("got a kill", 1, true) ~= nil, "same corpse not credited twice -> kill without a name: " .. lastFeed())
  enemyUnits.target = nil
  -- 2) nameplate removed because the enemy died
  enemyUnits.nameplate3 = { "Plate", "Faller", false }
  FIRE("NAME_PLATE_UNIT_ADDED", "nameplate3")
  enemyUnits.nameplate3[3] = true
  FIRE("NAME_PLATE_UNIT_REMOVED", "nameplate3")
  enemyUnits.nameplate3 = nil
  ADVANCE(1)
  FIRE("CHAT_MSG_COMBAT_HONOR_GAIN", HONOR)
  check(lastFeed():find("Plate Faller", 1, true) ~= nil, "nameless honor: victim = enemy whose nameplate vanished dead: " .. lastFeed())
  -- 3) nothing on screen -> kill without a name, still sent and counted
  ADVANCE(30)
  SENT = {}
  FIRE("CHAT_MSG_COMBAT_HONOR_GAIN", HONOR)
  check(lastFeed():find("got a kill", 1, true) ~= nil and FriendsAndFoesCharDB.streak == 4, "unknown victim: still a kill, streak counts: " .. lastFeed())
  RUN_TICKERS(4)
  check(#SENT > 0, "unknown-victim kill is still sent to friends")
  -- received from a friend
  ns.S().show.kill = "toast"
  local anonToast = toasted(function()
    FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("KILL", { victim = "", vclass = "", vlevel = "", vguild = "", zone = "Ashenvale", streak = "2" }, "anon1"), "WHISPER", 77)
  end)
  check(anonToast and lastFeed():find("Buddy Pal", 1, true) and lastFeed():find("got a kill", 1, true), "friend's nameless kill shows as a toast: " .. lastFeed())
  for k, v in pairs(o) do _G[k] = v end
  FriendsAndFoesCharDB.streak = 0
  check(ns.errors == 0, "no errors in nameless honor (" .. tostring(ns.lastError) .. ")")
end

-- toast themes: minimal (default) and achievement; each theme has its own frames
check(ns.Toast.Theme() == "minimal", "default toast theme is minimal")
drainToasts()
ns.S().theme = "achievement"
ns.Toast.Push({ kind = "kill", category = "pvp", title = "Bob killed Rogz", text = "Duskwood", header = "Revenge!", force = true })
local achFrame
for _, f in ipairs(FRAMES) do if f.spec and f.spec.title == "Bob killed Rogz" then achFrame = f end end
check(achFrame and achFrame.theme == "achievement" and achFrame.header and achFrame.header:GetText() == "Revenge!"
  and achFrame.title:GetText() == "Bob killed Rogz", "achievement theme: header, title")
drainToasts()
ns.Toast.Push({ kind = "died", category = "pvp", title = "Bob killed by Rogz", force = true })
local reused
for _, f in ipairs(FRAMES) do if f.spec and f.spec.title == "Bob killed by Rogz" then reused = f end end
check(reused == achFrame and reused.header:GetText() == "Friend killed", "achievement frames are reused; header from the event kind")
ns.S().theme = "bogus"
check(ns.Toast.Theme() == "minimal", "unknown theme falls back to minimal")
ns.S().theme = "minimal"
drainToasts()
ns.Toast.Push({ kind = "died", category = "pvp", title = "Back to minimal", force = true })
local minFrame
for _, f in ipairs(FRAMES) do if f.spec and f.spec.title == "Back to minimal" then minFrame = f end end
check(minFrame and minFrame.theme == "minimal" and minFrame.label ~= nil, "switching back uses minimal frames")
drainToasts()
check(ns.errors == 0, "no errors in themes (" .. tostring(ns.lastError) .. ")")

-- native options (the game's Settings API), with a minimal mock of that API
do
  local settings, controls, pages, opened = {}, {}, {}, nil
  local function category(name)
    local cat = { name = name, GetID = function() return name end }
    local layout = { items = {} }
    function layout:AddInitializer(i) self.items[#self.items + 1] = i end
    pages[#pages + 1] = { cat = cat, layout = layout }
    return cat, layout
  end
  local function newSetting(var, get, set)
    local s = { var = var }
    function s:GetValue() return get() end
    function s:SetValue(v) set(v); if self.cb then self.cb(self, v) end end
    function s:SetValueChangedCallback(cb) self.cb = cb end
    settings[var] = s
    return s
  end
  Settings = {
    VarType = { Boolean = "boolean", Number = "number", String = "string" },
    RegisterVerticalLayoutCategory = function(name) return category(name) end,
    RegisterVerticalLayoutSubcategory = function(_, name) return category(name) end,
    RegisterAddOnSetting = function(_, var, key, tbl) return newSetting(var, function() return tbl[key] end, function(v) tbl[key] = v end) end,
    RegisterProxySetting = function(_, var, _, _, _, get, set) return newSetting(var, get, set) end,
    CreateCheckbox = function(_, s) controls[#controls + 1] = { kind = "checkbox", s = s } end,
    CreateDropdown = function(_, s, opts) controls[#controls + 1] = { kind = "dropdown", s = s, opts = opts } end,
    CreateControlTextContainer = function()
      local d = {}
      return { Add = function(_, v, l) d[#d + 1] = { value = v, label = l } end, GetData = function() return d end }
    end,
    RegisterAddOnCategory = function() end,
    OpenToCategory = function(id) opened = id end,
  }
  CreateSettingsListSectionHeaderInitializer = function(text) return { header = text } end
  CreateSettingsButtonInitializer = function(name, label, click) return { button = label, click = click } end
  local ok, err = pcall(ns.Options.BuildNative)
  check(ok, "native options build: " .. tostring(err))
  check(#pages == 6, "six pages: Alerts, Where it works, Sounds, Appearance, Friends & sharing, Advanced (" .. #pages .. ")")
  local dropdowns = 0
  for _, c in ipairs(controls) do
    if c.kind == "dropdown" then
      dropdowns = dropdowns + 1
      check(#c.opts() > 0, "dropdown " .. c.s.var .. " has choices")
    end
  end
  check(dropdowns == 24, "9 alerts + 3 places + 9 sounds + style + message style + chat tab (" .. dropdowns .. ")")
  -- one dropdown per event = show + sound
  local kill = settings.FNF_display_kill
  check(kill:GetValue() == "toast", "kill shows as 'Toast' (sound off by default): " .. tostring(kill:GetValue()))
  kill:SetValue("chat_sound")
  check(ns.S().show.kill == "chat" and ns.S().sound.kill == true, "'Chat line + sound' sets show + sound")
  kill:SetValue("off")
  check(ns.S().show.kill == "off" and kill:GetValue() == "off", "'Off'")
  kill:SetValue("toast")
  check(ns.S().show.kill == "toast" and ns.S().sound.kill == false, "back to 'Toast'")
  settings.FNF_theme:SetValue("achievement")
  check(ns.Toast.Theme() == "achievement", "style dropdown sets the toast theme")
  settings.FNF_theme:SetValue("minimal")
  settings.FNF_style:SetValue("short")
  check(ns.S().flavor == false and settings.FNF_style:GetValue() == "short", "message style: short = flavor off")
  settings.FNF_style:SetValue("flavor")
  check(ns.S().flavor == true, "message style: with flavor")
  settings.FNF_where_pvp:SetValue("chat")
  check(ns.S().where.pvp == "chat", "battleground alerts dropdown")
  settings.FNF_where_pvp:SetValue("hold")
  settings.FNF_track_pvp:SetValue(true)
  check(ns.S().track.pvp == true, "track PvP in battlegrounds checkbox")
  settings.FNF_track_pvp:SetValue(false)
  local played = SOUNDS_PLAYED or 0
  settings.FNF_soundPick_kill:SetValue("raidwarning")
  check(ns.S().soundPick.kill == "raidwarning" and (SOUNDS_PLAYED or 0) == played + 1, "picking a sound sets it and plays it")
  settings.FNF_soundPick_kill:SetValue("default")
  settings.FNF_mark:SetValue(false)
  check(ns.S().mark == false, "hitlist marks checkbox")
  settings.FNF_mark:SetValue(true)
  settings.FNF_debug:SetValue(true)
  check(ns.S().debug and ns.S().debugSince, "debug checkbox goes through SetDebug")
  -- every button runs without error
  for _, pg in ipairs(pages) do
    for _, item in ipairs(pg.layout.items) do
      if item.click and item.button ~= "Choose friends..." then item.click() end
    end
  end
  ns.Options.Open()
  check(opened == "Friends & Foes", "Options opens the native category")
  Settings, CreateSettingsListSectionHeaderInitializer, CreateSettingsButtonInitializer = nil, nil, nil
  check(ns.errors == 0, "no errors in native options (" .. tostring(ns.lastError) .. ")")
end

-- window: click-to-sort columns, page arrows, Players dropdown
ns.UI.Show("hitlist")
local r = ns.UI.Rows()
check(#r > 1, "hitlist has rows: " .. #r)
local function sortedBy(key, desc)
  local rows = ns.UI.Rows()
  for i = 2, #rows do
    local a, b = key(rows[i - 1]), key(rows[i])
    if (desc and a < b) or (not desc and a > b) then return false end
  end
  return true
end
check(sortedBy(function(e) return e.lastSeen or 0 end, true), "default: newest first")
ns.UI.SortBy(5) -- Kills
check(sortedBy(function(e) return e.kills or 0 end, true), "click Kills: most kills first")
ns.UI.SortBy(5)
check(sortedBy(function(e) return e.kills or 0 end, false), "click Kills again: fewest first")
ns.UI.SortBy(1)
check(sortedBy(function(e) return (e.name or ""):lower() end, false), "click Name: A-Z")
ns.UI.Show("friends")
ns.UI.SortBy(2)
ns.UI.Show("enemies")
check(sortedBy(function(e) return e.lastSeen or 0 end, true), "each view keeps its own sort")
ns.UI.Show("friends")
ns.UI.Show("feed")
check(ns.errors == 0, "no errors in window sort/paging (" .. tostring(ns.lastError) .. ")")

-- you are not in your own Friends list
ns.UI.Show("friends")
local meListed = false
for _, e in ipairs(ns.UI.Rows()) do if e.name == ns.me then meListed = true end end
check(real.players[ns.me] and real.players[ns.me].friend and not meListed, "you don't show up under Friends")

-- friends on the other faction: left out of the roster, their events dropped, not shown
do
  local origInfo, origById = C_BattleNet.GetFriendGameAccountInfo, C_BattleNet.GetGameAccountInfoByID
  C_BattleNet.GetFriendGameAccountInfo = function() return { isOnline = true, clientProgram = "WoW", characterName = "Buddy", realmName = "X", factionName = "Alliance", gameAccountID = 77 } end
  C_BattleNet.GetGameAccountInfoByID = function() return { characterName = "Buddy", realmName = "X", factionName = "Alliance", gameAccountID = 77 } end
  ns.Comm.RebuildRoster()
  check(next(ns.Comm.roster) == nil and next(ns.Comm.everyone) == nil, "other-faction friend not in the roster")
  check(ns.Comm.lastRosterReport:find("other faction", 1, true) ~= nil, "roster report says other faction")
  local before = #real.feed
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("LVL", { level = 50 }, "fac1"), "WHISPER", 77)
  check(#real.feed == before, "other-faction friend's events ignored")
  C_BattleNet.GetFriendGameAccountInfo, C_BattleNet.GetGameAccountInfoByID = origInfo, origById
  ns.Comm.RebuildRoster()
  check(ns.Comm.roster["Buddy Pal"] ~= nil, "same-faction friend back in the roster")
  local hordeOnly = { name = "Ally Friend", friend = true, faction = "Alliance", k = 0, d = 0, a = 0, lastSeen = time() }
  real.players["Ally Friend"] = hordeOnly
  ns.UI.Show("friends")
  local allyListed = false
  for _, e in ipairs(ns.UI.Rows()) do if e.name == "Ally Friend" then allyListed = true end end
  check(not allyListed, "a known friend now on the other faction isn't listed")
  real.players["Ally Friend"] = nil
end

-- stop simulation: pending fake alerts don't fire, fake toasts dismissed, real data shown
do
  local simFeed = #(ns.Data.SimRealm().feed)
  ns.Sim.RunAll(false)
  check(ns.Sim.running, "simulation running")
  ns.Toast.Push({ kind = "died", category = "pvp", title = "fake", sim = true, force = true })
  ns.Sim.Stop()
  RUN_TIMERS()
  check(#(ns.Data.SimRealm().feed) == simFeed and not ns.Sim.running and not ns.viewSim, "stopped: no more simulated events, real view")
  local simShown = false
  for _, f in ipairs(FRAMES) do if f.spec and f.spec.sim then simShown = true end end
  check(not simShown, "simulated toasts dismissed")
  SlashCmdList.FRIENDSANDFOES("sim stop")
  check(ns.errors == 0, "no errors stopping simulation (" .. tostring(ns.lastError) .. ")")
end

-- where it works: alerts per instance type, and where your own PvP is tracked
do
  local origII = IsInInstance
  local here = "none"
  IsInInstance = function() return here ~= "none", here end
  drainToasts()
  local function shownIn(kind)
    here = kind
    local s = ns.Toast.shown or 0
    CHAT = {}
    ns.Toast.Push({ kind = "died", category = "pvp", title = "x", chat = "line" })
    drainToasts()
    here = "none"
    ns.Toast.Pump()
    drainToasts()
    return (ns.Toast.shown or 0) > s, #CHAT
  end
  -- default: wait until you're out
  here = "party"
  local s0 = ns.Toast.shown or 0
  ns.Toast.Push({ kind = "died", category = "pvp", title = "held", chat = "line" })
  check((ns.Toast.shown or 0) == s0, "in a dungeon, toasts wait by default")
  here = "none"
  ns.Toast.Pump()
  check((ns.Toast.shown or 0) == s0 + 1, "...and show once you're out")
  drainToasts()
  ns.S().where.party = "chat"
  local toasted1, chats1 = shownIn("party")
  check(not toasted1 and chats1 == 1, "dungeon: chat line only")
  ns.S().where.party = "off"
  local toasted2, chats2 = shownIn("party")
  check(not toasted2 and chats2 == 0, "dungeon: off")
  ns.S().where.party = "show"
  local toasted3 = shownIn("party")
  check(toasted3, "dungeon: show")
  ns.S().where.party = "hold"
  -- tracking your own PvP
  here = "pvp"
  check(not ns.PvP.InWorldPvPContext(), "battlegrounds not tracked by default")
  ns.S().track.pvp = true
  check(ns.PvP.InWorldPvPContext(), "battlegrounds tracked when turned on")
  ns.S().track.pvp = false
  here = "arena"
  check(ns.InstanceType() == "pvp" and not ns.PvP.InWorldPvPContext(), "an arena (if ever) counts as a battleground")
  here = "none"
  check(ns.PvP.InWorldPvPContext(), "open world tracked")
  ns.S().track.world = false
  check(not ns.PvP.InWorldPvPContext(), "open world can be turned off")
  ns.S().track.world = true
  -- old "hold in instances" switch turned off = show everywhere
  ns.S().dnd.instance = false
  FIRE("ADDON_LOADED", "FriendsAndFoes")
  check(ns.S().dnd.instance == nil and ns.S().where.party == "show" and ns.S().where.pvp == "show", "old instance switch migrated")
  for k in pairs(ns.S().where) do ns.S().where[k] = "hold" end
  IsInInstance = origII
  check(ns.errors == 0, "no errors in where-it-works (" .. tostring(ns.lastError) .. ")")
end

-- debug log: every alert's outcome is logged as a [TOAST] line
do
  ns.SetDebug(true)
  local log = FriendsAndFoesDB.debugLog
  local function lastToastLine()
    for i = #log, 1, -1 do if log[i]:find("[TOAST]", 1, true) then return log[i] end end
    return ""
  end
  drainToasts()
  ns.S().show.level = "chat"
  ns.Toast.Push({ kind = "level", category = "progress", title = "x", chat = "|cff00ff00Bob|r reached level 30" })
  check(lastToastLine():find("level | Bob reached level 30 | chat line: your alert setting", 1, true) ~= nil, "log: chat line + why: " .. lastToastLine())
  ns.S().show.level = "off"
  ns.Toast.Push({ kind = "level", category = "progress", title = "x", chat = "Bob reached level 31" })
  check(lastToastLine():find("off: your alert setting", 1, true) ~= nil, "log: off + why")
  ns.S().show.level = "chat"
  ns.Toast.Push({ kind = "died", category = "pvp", title = "x", chat = "Bob killed by Rogz" })
  check(lastToastLine():find("shown as toast", 1, true) ~= nil, "log: shown")
  drainToasts()
  IN_COMBAT = true
  ns.Toast.Push({ kind = "loot", category = "progress", title = "x", chat = "Bob looted [Sword]", milestone = true })
  check(lastToastLine():find("waiting: in combat", 1, true) ~= nil, "log: held, and why: " .. lastToastLine())
  IN_COMBAT = false
  FIRE("PLAYER_REGEN_ENABLED")
  check(lastToastLine():find("Bob looted [Sword] | shown as toast", 1, true) ~= nil, "log: shown after the wait: " .. lastToastLine())
  drainToasts()
  check(ns.errors == 0, "no errors in toast logging (" .. tostring(ns.lastError) .. ")")
end

-- options in combat: not allowed (the game blocks it), nothing queued
do
  local lockdown = true
  InCombatLockdown = function() return lockdown end
  PRINTED = {}
  ns.Options.Open()
  ns.Options.Open()
  local said = 0
  for _, line in ipairs(PRINTED) do if line:find("during combat", 1, true) then said = said + 1 end end
  check(said == 2, "in combat: refused with a message each time (" .. said .. ")")
  lockdown = false
  FIRE("PLAYER_REGEN_ENABLED")
  InCombatLockdown = nil
  check(ns.errors == 0, "no errors refusing options in combat (" .. tostring(ns.lastError) .. ")")
end

-- removing players / clearing the hitlist asks for confirmation first
do
  local popup
  StaticPopupDialogs = {}
  StaticPopup_Show = function(which, text, _, data) popup = { which = which, text = text, data = data } end
  local function yes() StaticPopupDialogs[popup.which].OnAccept(nil, popup.data); popup = nil end
  real.hitlist["Gone Soon"] = { name = "Gone Soon", attacks = 1, kills = 1, victims = {} }
  real.players["Gone Soon"] = { name = "Gone Soon", enemy = true, k = 1, d = 0, a = 0 }
  ns.UI.Show("hitlist")
  ns.UI.RemoveFromHitlist("Gone Soon")
  check(popup and popup.text:find("Gone Soon", 1, true) and real.hitlist["Gone Soon"], "remove asks first; nothing removed yet")
  popup = nil -- said No / closed it
  check(real.hitlist["Gone Soon"] ~= nil, "No keeps them")
  ns.UI.RemoveFromHitlist("Gone Soon")
  yes()
  check(real.hitlist["Gone Soon"] == nil and real.players["Gone Soon"] ~= nil, "Yes removes them from the hitlist (their K/D stays)")
  ns.UI.RemovePlayer("Gone Soon")
  check(popup and real.players["Gone Soon"] ~= nil, "removing a player asks first")
  yes()
  check(real.players["Gone Soon"] == nil, "Yes removes the player record")
  local saved = {}
  for k, v in pairs(real.hitlist) do saved[k] = v end
  ns.UI.ClearHitlist()
  check(popup and popup.text:find("Clear your whole hitlist", 1, true) and next(real.hitlist) ~= nil, "clear asks first")
  yes()
  check(next(real.hitlist) == nil, "Yes clears the hitlist")
  for k, v in pairs(saved) do real.hitlist[k] = v end
  StaticPopupDialogs, StaticPopup_Show = nil, nil
  check(ns.errors == 0, "no errors removing/clearing (" .. tostring(ns.lastError) .. ")")
end

-- 0.6: shared sightings, toast size/duration, search, friend zones, weekly summary, welcome
do
  check(FriendsAndFoesDB.welcomed == true, "welcome shown once (flag set)")
  -- shared sighting: a friend spots a hitlist player
  real.hitlist["Seen Guy"] = { name = "Seen Guy", attacks = 2, kills = 1, victims = {} }
  drainToasts()
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("SIGHT", { name = "Seen Guy", class = "ROGUE", level = "30", guild = "", zone = "Ashenvale (Astranaar)" }, "sg1"), "WHISPER", 77)
  local sightLine = ns.Plain(lastFeed())
  check(sightLine:find("Seen Guy spotted by Buddy Pal", 1, true) and sightLine:find("1 kills, 2 attacks", 1, true)
    and sightLine:find("Astranaar", 1, true), "friend's sighting: who, by whom, record, where: " .. sightLine)
  local feedN = #real.feed
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("SIGHT", { name = "Seen Guy", class = "ROGUE", level = "30", guild = "", zone = "Ashenvale" }, "sg2"), "WHISPER", 77)
  check(#real.feed == feedN, "same player again within 5 min: no second alert")
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("SIGHT", { name = "Not Mine", class = "MAGE", level = "30", guild = "", zone = "Duskwood" }, "sg3"), "WHISPER", 77)
  check(ns.Plain(lastFeed()):find("Not Mine spotted by", 1, true) and not lastFeed():find("kills", 1, true), "someone not on your hitlist: shown without a record")
  SENT = {}
  ns.Events.Emit("SIGHT", { name = "Seen Guy", class = "ROGUE", level = 30, guild = "", zone = "Ashenvale" })
  RUN_TICKERS(3)
  local sentSight = false
  for _, s in ipairs(SENT) do if s.payload:find("	SIGHT	", 1, true) then sentSight = true end end
  check(sentSight, "your own sightings are sent to friends")
  real.hitlist["Seen Guy"] = nil
  -- toast duration
  ns.S().toastDuration = 6
  drainToasts()
  ns.Toast.Push({ kind = "level", category = "progress", title = "dur", force = true })
  local df
  for _, f in ipairs(FRAMES) do if f.spec and f.spec.title == "dur" then df = f end end
  check(df and df.duration == 6, "toast duration setting")
  drainToasts()
  ns.Toast.Push({ kind = "died", category = "pvp", title = "durpvp", force = true })
  for _, f in ipairs(FRAMES) do if f.spec and f.spec.title == "durpvp" then df = f end end
  check(df and df.duration == 8, "PvP toasts stay 2 seconds longer")
  drainToasts()
  ns.S().toastDuration = 3
  ns.S().toastScale = 1.2
  ns.Toast.ApplyScale()
  ns.S().toastScale = 1
  ns.Toast.ApplyScale()
  -- search
  ns.UI.Show("hitlist")
  ns.UI.SetSearch("ROGZ")
  local rows = ns.UI.Rows()
  check(#rows >= 1 and rows[1].name:find("Rogz", 1, true), "search filters by name (case-insensitive)")
  ns.UI.SetSearch("zzzz-nobody")
  check(#ns.UI.Rows() == 0, "search with no matches: empty")
  ns.UI.SetSearch("")
  ns.UI.Show("feed")
  ns.UI.SetSearch("spotted")
  check(#ns.UI.Rows() >= 1, "search works on the Feed text")
  ns.UI.SetSearch("")
  -- friend's zone from Battle.net
  local origInfo = C_BattleNet.GetFriendGameAccountInfo
  C_BattleNet.GetFriendGameAccountInfo = function() return { isOnline = true, clientProgram = "WoW", characterName = "Buddy", realmName = "X", factionName = "Horde", gameAccountID = 77, areaName = "Ashenvale" } end
  ns.Comm.RebuildRoster()
  check(ns.Comm.ZoneOf("Buddy Pal") == "Ashenvale", "friend's zone known")
  C_BattleNet.GetFriendGameAccountInfo = origInfo
  ns.Comm.RebuildRoster()
  -- weekly summary
  local w = FriendsAndFoesDB.weekly
  check(w and w.start, "weekly tracking started")
  local k0 = w.k or 0
  FriendsAndFoesCharDB.streak = 0
  ns.Events.Emit("KILL", { victim = "Week Victim", vclass = "MAGE", vlevel = "60", vguild = "", zone = "Duskwood" })
  check(FriendsAndFoesDB.weekly.k == k0 + 1, "your takedowns count toward the week")
  FriendsAndFoesDB.weekly = { start = time() - 8 * 86400, k = 3, d = 2, killers = { ["Rogz Fang"] = 2 } }
  CHAT = {}
  FIRE("PLAYER_LOGIN")
  RUN_TIMERS()
  local weekly
  for _, line in ipairs(CHAT) do if line:find("Your PvP week", 1, true) then weekly = line end end
  check(weekly and weekly:find("3 takedowns, 2 deaths", 1, true) and weekly:find("Nemesis: Rogz Fang (2", 1, true), "weekly summary after a week: " .. tostring(weekly))
  check(FriendsAndFoesDB.weekly.k == 0 and time() - FriendsAndFoesDB.weekly.start < 60, "new week started")
  FriendsAndFoesCharDB.streak = 0
  -- minimap / addon-menu tooltip
  local fr, hl = ns.Minimap.Summary()
  check(type(fr) == "number" and type(hl) == "number", "tooltip summary numbers")
  FriendsAndFoes_OnAddonCompartmentEnter("FriendsAndFoes", CreateFrame())
  FriendsAndFoes_OnAddonCompartmentLeave()
  ADVANCE(15) -- let the send queue's allowance refill for later tests
  RUN_TICKERS(2)
  check(ns.errors == 0, "no errors in 0.6 features (" .. tostring(ns.lastError) .. ")")
end

-- counts are never shown as -0 or negative
check(ns.Count(-0) == 0 and tostring(ns.Count(-0)) == "0" and ns.Count(-3) == 0 and ns.Count(nil) == 0 and ns.Count("5") == 5 and ns.Count(2.7) == 2, "ns.Count")
real.players["Neg Zero"] = { name = "Neg Zero", enemy = true, k = -0.0, d = -1, a = 0, lastSeen = time() }
ns.UI.Show("enemies")
ns.UI.SetSearch("neg zero")
local nz = ns.UI.Rows()[1]
check(nz and nz.name == "Neg Zero", "test player listed")
ns.UI.SetSearch("")
real.players["Neg Zero"] = nil
-- picked sounds play instead of the default
do
  local lastId
  local origPS = PlaySound
  PlaySound = function(id) lastId = id; SOUNDS_PLAYED = (SOUNDS_PLAYED or 0) + 1 end
  ns.S().soundPick.died = "coin"
  ns.S().sound.died = true
  drainToasts()
  ns.Toast.Push({ kind = "died", category = "pvp", title = "snd" })
  local coinId
  for _, c in ipairs(ns.Toast.SOUND_CHOICES) do if c[1] == "coin" then coinId = c[3] end end
  check(lastId == coinId, "picked sound plays for that event")
  ns.S().soundPick.died = "default"
  drainToasts()
  ns.Toast.Push({ kind = "died", category = "pvp", title = "snd2" })
  check(lastId ~= coinId, "default plays the built-in sound")
  drainToasts()
  PlaySound = origPS
end

-- a friend attacks someone (starts the fight)
do
  -- received
  drainToasts()
  local shown = toasted(function()
    FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("ENG", { zone = "Hillsbrad Foothills (Tarren Mill)", target = "Gank Target:MAGE:30:" }, "eg1"), "WHISPER", 77)
  end)
  check(shown and ns.Plain(lastFeed()):find("Buddy Pal", 1, true) and lastFeed():find("Gank Target", 1, true)
    and lastFeed():find("Tarren Mill", 1, true), "friend attacks someone in my zone: toast + feed: " .. ns.Plain(lastFeed()))
  check(real.hitlist["Gank Target"] == nil and real.players["Gank Target"].enemy, "attacking someone doesn't put them on the hitlist")
  local far = toasted(function()
    FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("ENG", { zone = "Duskwood", target = "Far Target:MAGE:30:" }, "eg2"), "WHISPER", 77)
  end)
  check(not far and #CHAT == 1, "in another zone: a chat line")
  -- detected on your own client
  local enemyTarget = true
  local o = { UnitExists = UnitExists, UnitIsPlayer = UnitIsPlayer, UnitFactionGroup = UnitFactionGroup, UnitName = UnitName, UnitIsUnit = UnitIsUnit }
  UnitExists = function(u) if u == "target" and enemyTarget then return true end return o.UnitExists(u) end
  UnitIsPlayer = function(u) if u == "target" then return enemyTarget end return o.UnitIsPlayer and o.UnitIsPlayer(u) end
  UnitFactionGroup = function(u) if u == "target" then return "Alliance" end return o.UnitFactionGroup(u) end
  UnitName = function(u) if u == "target" then return "Prey", "Person" end return o.UnitName(u) end
  UnitIsUnit = function() return false end
  SENT = {}
  FIRE("PLAYER_ENTER_COMBAT")
  check(lastFeed():find("Prey Person", 1, true) ~= nil, "starting auto-attack on an enemy player is an attack: " .. ns.Plain(lastFeed()))
  RUN_TICKERS(3)
  local sentEng = false
  for _, s in ipairs(SENT) do if s.payload:find("	ENG	", 1, true) then sentEng = true end end
  check(sentEng, "sent to friends")
  local n = #real.feed
  FIRE("START_AUTOREPEAT_SPELL")
  check(#real.feed == n, "same enemy again within 2 minutes: not repeated")
  enemyTarget = false
  for k, v in pairs(o) do _G[k] = v end
  ADVANCE(15)
  RUN_TICKERS(2)
  check(ns.errors == 0, "no errors in friend-attacks alerts (" .. tostring(ns.lastError) .. ")")
end

-- every kill gets its own toast (they stack); enemy assists show on deaths
do
  drainToasts()
  ns.S().show.kill = "toast"
  FriendsAndFoesCharDB.streak = 0
  local before = ns.Toast.shown or 0
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("KILL", { victim = "First Vic", vclass = "MAGE", vlevel = "30", vguild = "", zone = "Duskwood", streak = "1" }, "mk1"), "WHISPER", 77)
  ADVANCE(5)
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("KILL", { victim = "Second Vic", vclass = "MAGE", vlevel = "30", vguild = "", zone = "Duskwood", streak = "2" }, "mk2"), "WHISPER", 77)
  check((ns.Toast.shown or 0) == before + 2, "two kills close together: two toasts, stacked")
  drainToasts()
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("DIE", { zone = "Duskwood", killer = "Main Killer:ROGUE:60:", conf = "c", assists = "Side Kick:MAGE:60:" }, "wd1"), "WHISPER", 77)
  check(ns.Plain(lastFeed()):find("(with Side Kick)", 1, true) ~= nil, "death names enemy helpers: " .. ns.Plain(lastFeed()))
  ns.S().flavor = false
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("DIE", { zone = "Duskwood", killer = "Main Killer:ROGUE:60:", conf = "c", assists = "Side Kick:MAGE:60:" }, "wd2"), "WHISPER", 77)
  check(ns.Plain(lastFeed()) == "Buddy Pal killed by Main Killer (with Side Kick)" .. ns.Flavor.SEP .. "Duskwood", "short style too: " .. ns.Plain(lastFeed()))
  ns.S().flavor = true
  drainToasts()
  check(ns.errors == 0, "no errors in kill merging (" .. tostring(ns.lastError) .. ")")
end

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
