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
-- the defaults a new player gets
do
  local s = ns.S()
  local okShow = s.show.level == "toast" and s.show.loot == "toast" and s.show.gear == "toast" and s.show.attacked == "toast"
    and s.show.engage == "toast" and s.show.died == "toast" and s.show.kill == "toast" and s.show.sighting == "toast" and s.show.share == "chat"
  local okSound = s.sound.enabled and not s.sound.level and s.sound.loot and s.sound.gear and s.sound.attacked and not s.sound.engage
    and s.sound.died and s.sound.kill and s.sound.sighting and not s.sound.share
  local okPick = s.soundPick.attacked == "alarm" and s.soundPick.died == "raidwarning" and s.soundPick.kill == "levelup"
    and s.soundPick.sighting == "mapping" and s.soundPick.engage == "default"
  check(okShow and okSound and okPick, "default alerts and sounds")
  check(s.nearbyOnly == false and s.dnd.combat == false and s.toastDuration == 5 and s.theme == "minimal" and s.toastScale == 1
    and s.flavor and s.weekly and s.mark and s.markTooltip and s.milestones and s.levelEvery == 1 and s.gearMin == 3
    and s.toastGrow == "down" and s.toastMax == 2 and s.share.pvp and s.share.where and s.chatFrame == 1, "default appearance, sharing and behaviour")
  -- the rest of these tests were written against the earlier, quieter defaults
  s.show.level, s.show.loot, s.show.gear, s.show.sighting = "chat", "chat", "chat", "chat"
  s.sound.kill, s.sound.gear = false, false
  for k in pairs(s.soundPick) do s.soundPick[k] = "default" end
  s.nearbyOnly, s.dnd.combat, s.toastDuration = true, true, 3
end
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
RUN_TICKERS(8) -- drain the profile greeting sent at login
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
RUN_TICKERS(8) -- drain the greeting from when he came back into the roster
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
RUN_TICKERS(8)
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
local killMsg = lastKill and ns.Comm.Decode(lastKill)
check(killMsg and killMsg.f.streak == "3" and killMsg.f.rl == "1", "KILL carries the streak (and may be passed on): " .. tostring(lastKill))
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
  check(dropdowns == 28, "9 alerts + level-ups + gear + 3 places + 9 sounds + style + stacking + message style + chat tab + forget (" .. dropdowns .. ")")
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

-- layout: every tab's columns fit inside the list (nothing runs past the window edge)
for _, key in ipairs({ "hitlist", "board", "enemies", "friends", "feed", "kills" }) do
  local total = 0
  for _, col in ipairs(ns.UI.TabColumns(key)) do total = total + col[2] end
  check(total > 0 and total <= ns.UI.LIST_WIDTH, "columns of the " .. key .. " tab fit: " .. total .. " of " .. ns.UI.LIST_WIDTH)
end
-- a button whose label changes is resized to fit the new label, never below its minimum
do
  local b = CreateFrame()
  b.minWidth = 60
  local fs = { GetStringWidth = function() return 140 end }
  b.GetFontString = function() return fs end
  local w
  b.SetSize = function(_, width) w = width end
  ns.UI.SetButtonText(b, "A much longer label")
  check(w == 164, "a longer label widens the button: " .. tostring(w))
  fs.GetStringWidth = function() return 10 end
  ns.UI.SetButtonText(b, "x")
  check(w == 60, "a short label keeps the minimum width")
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
ns.UI.SortBy(4) -- Kills
check(sortedBy(function(e) return e.kills or 0 end, true), "click Kills: most kills first")
ns.UI.SortBy(4)
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
  check(sightLine:find("Seen Guy spotted by Buddy Pal", 1, true) and sightLine:find("1 kills on us", 1, true) and not sightLine:find("attacks", 1, true)
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

-- hitlist hover: who a player killed, and how often
do
  local h = { name = "Count Me", kills = 4, attacks = 6, victims = { ["Bob One"] = true, ["Alice Two"] = true, ["Old Victim"] = true },
    kv = { ["Bob One"] = 3, ["Alice Two"] = 1 }, lastSeen = time() }
  local k = ns.Data.KillsOn(h)
  check(#k == 3 and k[1][1] == "Bob One" and k[1][2] == 3 and k[2][1] == "Alice Two" and k[2][2] == 1
    and k[3][1] == "Old Victim" and k[3][2] == nil, "KillsOn: most kills first, uncounted last")
  local lines = {}
  local oAdd, oDouble = GameTooltip.AddLine, GameTooltip.AddDoubleLine
  GameTooltip.AddLine = function(_, s) lines[#lines + 1] = ns.Plain(s or "") end
  GameTooltip.AddDoubleLine = function(_, l, r) lines[#lines + 1] = ns.Plain(l or "") .. " = " .. ns.Plain(r or "") end
  ns.UI.HitTooltip(CreateFrame(), h)
  local text = table.concat(lines, " | ")
  check(text:find("Bob One = 3x", 1, true) and text:find("Alice Two = 1x", 1, true) and text:find("Old Victim = before counting began", 1, true)
    and text:find("4 kills on your group", 1, true) and not text:find("attacks", 1, true), "hover tooltip: per-friend kill counts: " .. text)
  GameTooltip.AddLine, GameTooltip.AddDoubleLine = oAdd, oDouble
end

-- faction toast styles
for _, style in ipairs({ "alliance", "horde" }) do
  drainToasts()
  ns.S().theme = style
  ns.Toast.Push({ kind = "died", category = "pvp", title = "faction " .. style, text = "Tarren Mill", force = true })
  local ff
  for _, f in ipairs(FRAMES) do if f.spec and f.spec.title == "faction " .. style then ff = f end end
  check(ff and ff.theme == style and ff.header:GetText() == "Friend killed" and ff.title:GetText() == "faction " .. style
    and ff.sub:GetText() == "Tarren Mill", style .. " style: header, title, place")
end
drainToasts()
ns.S().theme = "minimal"
check(#ns.Toast.THEMES == 4, "four toast styles to choose from")
check(ns.errors == 0, "no errors in faction styles (" .. tostring(ns.lastError) .. ")")

-- class colours: given class, known class, or built from r/g/b
do
  local orig = RAID_CLASS_COLORS
  RAID_CLASS_COLORS = { ROGUE = { colorStr = "fffff468" }, MAGE = { r = 0.25, g = 0.78, b = 0.92 } }
  check(ns.ClassColored("Ro Gue", "ROGUE") == "|cfffff468Ro Gue|r", "class colour from the class")
  real.players["Known Mage"] = { name = "Known Mage", class = "MAGE", enemy = true, k = 0, d = 0, a = 0 }
  check(ns.ClassColored("Known Mage", nil) == "|cff3fc6eaKnown Mage|r", "missing class: looked up, colour built from r/g/b: " .. ns.ClassColored("Known Mage", nil))
  check(ns.ClassColored("Nobody Known", nil) == "Nobody Known", "unknown class: plain name")
  real.players["Known Mage"] = nil
  RAID_CLASS_COLORS = orig
end

-- old data: faded hitlist entries, old levels, gone friends, optional forgetting
do
  local day = 86400
  real.hitlist["Fresh Foe"] = { name = "Fresh Foe", kills = 1, attacks = 0, victims = {}, lastSeen = time() - 2 * day, level = 30 }
  real.hitlist["Old Foe"] = { name = "Old Foe", kills = 9, attacks = 0, victims = {}, lastSeen = time() - 100 * day, level = 20 }
  real.hitlist["Old Noted"] = { name = "Old Noted", kills = 1, attacks = 0, victims = {}, lastSeen = time() - 400 * day, note = "keep" }
  check(not ns.Data.IsStale(real.hitlist["Fresh Foe"]) and ns.Data.IsStale(real.hitlist["Old Foe"]), "stale after 90 days unseen")
  ns.UI.Show("hitlist")
  ns.UI.SortBy(4) -- kills, most first: Old Foe (9) would lead, but faded entries go last
  ns.UI.SortBy(4)
  ns.UI.SortBy(4)
  local rows = ns.UI.Rows()
  local posFresh, posOld
  for i, e in ipairs(rows) do
    if e.name == "Fresh Foe" then posFresh = i end
    if e.name == "Old Foe" then posOld = i end
  end
  check(posFresh and posOld and posOld > posFresh, "faded entries are listed after active ones")
  check(ns.Data.LevelIsOld(real.hitlist["Old Foe"]) and not ns.Data.LevelIsOld(real.hitlist["Fresh Foe"]), "old levels detected")
  -- forgetting (off by default)
  check(ns.Data.ForgetOld(FriendsAndFoesDB) == 0 and real.hitlist["Old Foe"], "forgetting is off by default")
  ns.S().forgetAfter = 90
  ns.Data.ForgetOld(FriendsAndFoesDB)
  check(real.hitlist["Old Foe"] == nil and real.hitlist["Fresh Foe"] and real.hitlist["Old Noted"], "forget after 90 days: removed, but fresh and noted entries kept")
  ns.S().forgetAfter = 0
  real.hitlist["Fresh Foe"], real.hitlist["Old Noted"] = nil, nil
  -- a friend not heard from in 6 months leaves the Friends list
  real.players["Gone Friend"] = { name = "Gone Friend", friend = true, k = 0, d = 0, a = 0, lastSeen = time() - 200 * day }
  ns.UI.Show("friends")
  local goneListed = false
  for _, e in ipairs(ns.UI.Rows()) do if e.name == "Gone Friend" then goneListed = true end end
  check(not goneListed and real.players["Gone Friend"], "friend gone 6 months: hidden, record kept")
  real.players["Gone Friend"] = nil
  check(ns.errors == 0, "no errors with old data (" .. tostring(ns.lastError) .. ")")
end

-- 0.6.2 options: level-up frequency, gear quality, milestones switch, stacking, skull/tooltip
do
  drainToasts()
  ns.S().show.level = "toast"
  ns.S().levelEvery = 5
  local before = ns.Toast.shown or 0
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("LVL", { level = 23 }, "le1"), "WHISPER", 77)
  check((ns.Toast.shown or 0) == before and lastFeed():find("23", 1, true), "every 5 levels: 23 skipped (still in the Feed)")
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("LVL", { level = 25 }, "le2"), "WHISPER", 77)
  check((ns.Toast.shown or 0) == before + 1, "every 5 levels: 25 shown")
  drainToasts()
  ns.S().levelEvery = 60
  before = ns.Toast.shown or 0
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("LVL", { level = 30 }, "le3"), "WHISPER", 77)
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("LVL", { level = 60 }, "le4"), "WHISPER", 77)
  check((ns.Toast.shown or 0) == before + 1, "only level 60")
  drainToasts()
  ns.S().levelEvery = 1
  ns.S().show.level = "chat"
  -- gear quality
  check(ns.ItemQuality("|cnIQ3:|Hitem:1|h[x]|h|r") == 3 and ns.ItemQuality("|cffa335ee|Hitem:2|h[y]|h|r") == 4 and ns.ItemQuality("plain") == nil, "item quality from links")
  ns.S().show.gear = "toast"
  ns.S().gearMin = 4
  before = ns.Toast.shown or 0
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("GEAR", { link = "|cff0070dd|Hitem:5|h[Blue Thing]|h|r", count = "1" }, "gq1"), "WHISPER", 77)
  check((ns.Toast.shown or 0) == before, "epic only: blue gear skipped")
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("GEAR", { link = "|cffa335ee|Hitem:6|h[Epic Thing]|h|r", count = "1" }, "gq2"), "WHISPER", 77)
  check((ns.Toast.shown or 0) == before + 1, "epic only: epic gear shown")
  drainToasts()
  ns.S().gearMin = 3
  ns.S().show.gear = "chat"
  -- milestones switch
  ns.S().milestones = false
  ns.S().show.level = "chat"
  CHAT = {}
  before = ns.Toast.shown or 0
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("LVL", { level = 60 }, "ms1"), "WHISPER", 77)
  check((ns.Toast.shown or 0) == before and #CHAT == 1, "milestones off: level 60 follows the chat setting")
  ns.S().milestones = true
  -- stacking direction and count
  ns.S().toastGrow = "up"
  ns.Toast.ApplyScale()
  ns.S().toastMax = 3
  before = ns.Toast.shown or 0
  for i = 1, 3 do ns.Toast.Push({ kind = "died", category = "pvp", title = "stack" .. i, force = true }) end
  check((ns.Toast.shown or 0) == before + 3, "three toasts on screen when set to 3")
  drainToasts()
  ns.S().toastGrow, ns.S().toastMax = "down", 2
  ns.Toast.ApplyScale()
  -- skull and tooltip separately
  ns.S().markTooltip = false
  check(ns.S().mark == true, "skull stays on when the tooltip line is off")
  ns.S().markTooltip = true
  check(ns.errors == 0, "no errors in 0.6.2 options (" .. tostring(ns.lastError) .. ")")
end

-- code review fixes
do
  -- #1 "Epic only" counts only the epics of a gear batch
  drainToasts()
  ns.S().show.gear, ns.S().gearMin = "toast", 4
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("GEAR", { link = "|cffa335ee|Hitem:7|h[Epic One]|h|r", count = "3", epics = "1" }, "rv1"), "WHISPER", 77)
  local gearToast
  for _, f in ipairs(FRAMES) do if f.spec and f.spec.kind == "gear" then gearToast = f.spec end end
  check(gearToast and not ns.Plain(gearToast.title):find("more", 1, true), "epic only: '+N more' counts epics only: " .. tostring(gearToast and ns.Plain(gearToast.title)))
  drainToasts()
  ns.S().show.gear, ns.S().gearMin = "chat", 3
  -- #2 white and grey items are recognised
  check(ns.ItemQuality("|cffffffff|Hitem:8|h[White]|h|r") == 1 and ns.ItemQuality("|cff9d9d9d|Hitem:9|h[Grey]|h|r") == 0, "white/grey quality")
  -- #3 forgetting asks first; "No" changes nothing
  real.hitlist["Ancient One"] = { name = "Ancient One", kills = 1, victims = {}, lastSeen = time() - 400 * 86400 }
  check(ns.Data.CountForget(FriendsAndFoesDB, 90) >= 1, "count what forgetting would remove")
  local saidNo = false
  ns.UI.Confirm("x", function() end, function() saidNo = true end) -- no pop-up available in tests: counts as No
  check(saidNo and real.hitlist["Ancient One"], "declined: nothing removed")
  real.hitlist["Ancient One"] = nil
  -- #4 the old "mark" choice carries over to the new tooltip switch
  ns.S().mark, ns.S().markTooltip, ns.S().markSplit = false, true, nil
  FIRE("ADDON_LOADED", "FriendsAndFoes")
  check(ns.S().markTooltip == false and ns.S().markSplit, "mark off before the split: tooltip stays off")
  ns.S().mark, ns.S().markTooltip = true, true
  -- #5 a fresh entry without "last seen" isn't shown as an old level
  check(not ns.Data.LevelIsOld({ firstSeen = time() }), "no lastSeen: firstSeen decides")
  -- #10 lowering "toasts on screen" closes the extra ones
  ns.S().toastMax = 3
  for i = 1, 3 do ns.Toast.Push({ kind = "died", category = "pvp", title = "trim" .. i, force = true }) end
  ns.S().toastMax = 1
  ns.Toast.ApplyMax()
  local onScreen = 0
  for _, f in ipairs(FRAMES) do if f.spec and f.spec.title and f.spec.title:find("^trim") then onScreen = onScreen + 1 end end
  check(onScreen == 1, "fewer toasts on screen applies at once (" .. onScreen .. ")")
  drainToasts()
  ns.S().toastMax = 2
  check(ns.errors == 0, "no errors in review fixes (" .. tostring(ns.lastError) .. ")")
end

-- cloud review fixes
do
  -- 1) "Epic only": the Feed still records the whole batch
  drainToasts()
  ns.S().show.gear, ns.S().gearMin = "toast", 4
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("GEAR", { link = "|cffa335ee|Hitem:10|h[Epic Two]|h|r", count = "3", epics = "1" }, "cr1"), "WHISPER", 77)
  check(ns.Plain(lastFeed()):find("+2 more", 1, true) ~= nil, "Feed keeps the full gear batch: " .. ns.Plain(lastFeed()))
  drainToasts()
  ns.S().show.gear, ns.S().gearMin = "chat", 3
  -- 3) a share doesn't import entries "Forget" would remove anyway
  ns.S().forgetAfter = 90
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("HIT", { share = "s9", entries = "Very Old:ROGUE:30::0:2:0:2600;Quite New:MAGE:30::0:1:0:5" }, "cr3"), "WHISPER", 77)
  check(real.hitlist["Very Old"] == nil and real.hitlist["Quite New"] ~= nil, "share: entries older than the forget period aren't imported")
  ns.S().forgetAfter = 0
  real.hitlist["Quite New"] = nil
  -- 7) merging two records adds up the per-friend kill counts
  local dst = { name = "Kragg Bear", kills = 2, kv = { Bob = 2 } }
  ns.Data.MergeInto(dst, { name = "Kragg", kills = 2, kv = { Bob = 2, Alice = 1 } })
  check(dst.kills == 4 and dst.kv.Bob == 4 and dst.kv.Alice == 1, "merge: per-friend counts add up like the total")
  check(ns.errors == 0, "no errors in cloud review fixes (" .. tostring(ns.lastError) .. ")")
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

-- catch-up: friends send you what you missed while you were offline
do
  local rr = ns.Data.RealRealm()
  -- own events are kept for friends who are offline now
  local before = #ns.Comm.Outbox()
  ns.Events.Emit("DIE", { zone = "Duskwood", killer = "Out Box:ROGUE:60:", conf = "c", assists = "" })
  local box = ns.Comm.Outbox()
  check(#box == before + 1 and box[#box].kind == "DIE" and box[#box].f.killer == "Out Box:ROGUE:60:", "own event kept for catch-up")
  -- asking: only after being away a while
  RUN_TICKERS(60)
  SENT = {}
  check(not ns.Comm.AskCatchUp(time() - 30), "no catch-up after a reload")
  check(ns.Comm.AskCatchUp(time() - 7200), "catch-up asked after 2 hours away")
  RUN_TICKERS(4)
  local req
  for _, s in ipairs(SENT) do if s.payload:find("\tREQ\t", 1, true) then req = s.payload end end
  check(req and req:find("\t7200$") ~= nil, "REQ carries the window: " .. tostring(req))
  -- answering: a friend asks, we send them our own recent events
  RUN_TICKERS(60)
  SENT = {}
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("REQ", { window = 3600 }, "q1"), "WHISPER", 77)
  RUN_TICKERS(60)
  local die
  for _, s in ipairs(SENT) do if s.payload:find("Out Box", 1, true) then die = s.payload end end
  check(die and die:find("\tDIE\t", 1, true) and die:match("\t(%d+)$") ~= nil, "answer replays our DIE with its age: " .. tostring(die))
  -- receiving: past events go to the Feed and hitlist, no toast and no chat line per event
  local t0 = toasted(function()
    FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("DIE", { zone = "Duskwood", killer = "Past Ganker:ROGUE:60:", conf = "c", assists = "", ago = 3600 }, "past1"), "WHISPER", 77)
  end)
  check(not t0 and #CHAT == 0, "past event: no toast or chat line")
  local ph = rr.hitlist["Past Ganker"]
  check(ph and ph.kills == 1, "past death puts the killer on the hitlist")
  local entry, idx
  for i, e in ipairs(rr.feed) do if e.text:find("Past Ganker", 1, true) then entry, idx = e, i end end
  check(entry and math.abs(entry.t - (time() - 3600)) <= 5, "past event in the Feed at the time it happened")
  check(entry and (idx == #rr.feed or rr.feed[idx + 1].t >= entry.t), "Feed stays in time order")
  check(ph and ph.lastSeen and ph.lastSeen <= time() - 3500, "hitlist last seen = when it happened")
  RUN_TIMERS()
  check(#CHAT == 1 and CHAT[1]:find("While you were away", 1, true) ~= nil, "one summary chat line after a catch-up: " .. tostring(CHAT[1]))
  -- something already seen live isn't applied twice
  FriendsAndFoesDB.got["Buddy Pal:old1"] = time() - 600
  local n = #rr.feed
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("DIE", { zone = "Duskwood", killer = "Old News:ROGUE:60:", conf = "c", assists = "", ago = 600 }, "old1"), "WHISPER", 77)
  check(#rr.feed == n and rr.hitlist["Old News"] == nil, "replay of an event seen live is ignored")
end

-- 0.7: you start a fight, the enemy hits back: friends get "you attacked X", not also "X attacked you"
do
  local errs = ns.errors
  local o = { UnitExists = UnitExists, UnitIsPlayer = UnitIsPlayer, UnitFactionGroup = UnitFactionGroup, UnitName = UnitName, UnitIsUnit = UnitIsUnit }
  local who = { "Duel", "Starter" }
  UnitExists = function(u) if u == "target" then return true end return o.UnitExists(u) end
  UnitIsPlayer = function(u) if u == "target" then return true end return o.UnitIsPlayer and o.UnitIsPlayer(u) end
  UnitFactionGroup = function(u) if u == "target" then return "Alliance" end return o.UnitFactionGroup(u) end
  UnitName = function(u) if u == "target" then return who[1], who[2] end return o.UnitName(u) end
  UnitIsUnit = function(a) return a == "targettarget" end -- the enemy targets you
  ADVANCE(60)
  local function kinds()
    local out = {}
    for _, e in ipairs(real.feed) do out[#out + 1] = e.kind end
    return table.concat(out, ",")
  end
  local before = #real.feed
  FIRE("PLAYER_ENTER_COMBAT")
  check(#real.feed == before + 1 and real.feed[#real.feed].kind == "engage", "you start a fight: one engage")
  check(ns.PvP.InFight() and ns.Profile.MyStatus() == "pvp", "in a fight now")
  ADVANCE(1)
  FIRE("UNIT_COMBAT", "player", "WOUND")
  check(#real.feed == before + 1, "they hit back: no 'attacked' on top (" .. kinds() .. ")")
  -- someone else joins in: that is news
  who = { "Third", "Party" }
  ADVANCE(1)
  FIRE("UNIT_COMBAT", "player", "WOUND")
  check(#real.feed == before + 2 and real.feed[#real.feed].kind == "attacked", "a new attacker is still reported")
  for k, v in pairs(o) do _G[k] = v end
  ADVANCE(40)
  check(not ns.PvP.InFight() and ns.Profile.MyStatus() == "", "the fight is over 30 seconds later")
  RUN_TIMERS()
  RUN_TICKERS(8)
  check(ns.errors == errs, "no errors in engage/attack dedupe (" .. tostring(ns.lastError) .. ")")
end

-- 0.7: profiles, the leaderboard and their messages
do
  local errs = ns.errors
  local rr = ns.Data.RealRealm()
  ns.viewSim = false
  ns.Comm.ClearPicks()
  ns.Comm.RebuildRoster()
  -- your own message: your own all-time K/D from your record
  local me = rr.players[ns.me]
  me.k, me.d = 12, 4
  local f = ns.Profile.Fields()
  check(f.k == 12 and f.d == 4 and f.zone == "Hillsbrad Foothills" and f.status == "", "own profile fields: " .. tostring(f.k) .. "/" .. tostring(f.d))
  ns.S().share.pvp = false
  f = ns.Profile.Fields()
  check(f.k == "" and f.d == "", "not sharing PvP: no K/D in the profile")
  ns.S().share.where = false
  f = ns.Profile.Fields()
  check(f.zone == "" and f.status == "", "'Where I am' off: no zone or status in the profile")
  ns.S().share.where = true
  check(ns.Profile.Fields().zone == "Hillsbrad Foothills", "'Where I am' on: zone shared")
  check(#ns.Options.SHARE == 6 and ns.Options.SHARE[5][1] == "where" and ns.Options.SHARE[6][1] == "relay", "Options list the 'Where I am' and 'pass on' switches")
  ns.S().share.pvp = true

  -- typed text: one plain line, counted and cut in characters, never half of one
  local P = ns.Profile
  check(P.CleanText("  |cffff0000Red|r\tline  ") == "cffff0000Redr line", "text loses colour codes and tabs")
  check(P.Length("\195\134r\195\184") == 3, "length counts characters, not bytes")
  check(P.CleanText(string.rep("a", 23) .. "\195\169\195\169", 24) == string.rep("a", 23) .. "\195\169", "cut at 24 characters, whole characters only")
  check(P.CleanText("   ") == nil, "blank text is nothing")

  -- changes are sent once, after a short wait; unchanged = not sent again
  RUN_TIMERS(); RUN_TICKERS(8); SENT = {}
  ns.Profile.SetWanted("Rogz Fang")
  RUN_TIMERS()
  RUN_TICKERS(8)
  local pro = {}
  for _, s in ipairs(SENT) do if s.payload:find("\tPRO\t", 1, true) then pro[#pro + 1] = s.payload end end
  check(#pro == 2, "one profile update (both routes): " .. #pro)
  local decoded = pro[1] and ns.Comm.Decode(pro[1])
  check(decoded and decoded.f.k == "12" and decoded.f.d == "4" and decoded.f.wanted == "Rogz Fang" and decoded.f.motto == nil,
    "profile message carries K/D and most wanted (no free text)")
  check(pro[1] and #pro[1] <= 255, "profile fits one message")
  SENT = {}
  ns.Profile.Changed()
  RUN_TIMERS(); RUN_TICKERS(8)
  check(#SENT == 0, "nothing changed: nothing sent")

  -- a friend coming online gets your profile right away
  FRIENDS_ONLINE = 0
  ns.Comm.RebuildRoster()
  FRIENDS_ONLINE = 1
  ns.Comm.RebuildRoster()
  ns.Comm.RebuildRoster() -- no second greeting
  RUN_TICKERS(8)
  local greet = 0
  for _, s in ipairs(SENT) do if s.payload:find("\tPRO\t", 1, true) then greet = greet + 1 end end
  check(greet == 2, "friend back online: greeted once on both routes: " .. greet)

  -- receiving a friend's profile
  local buddy = rr.players["Buddy Pal"]
  buddy.k, buddy.d, buddy.sk, buddy.sd = 1, 1, nil, nil
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("PRO", { k = 20, d = 5, wanted = "Rogz-Fang", zone = "Duskwood", status = "pvp" }, "pro1"), "WHISPER", 77)
  check(buddy.sk == 20 and buddy.sd == 5, "friend's own K/D stored")
  check(buddy.wanted == "Rogz Fang" and buddy.zone == "Duskwood" and buddy.status == "pvp", "friend's most wanted, zone, status")
  check(ns.Profile.NowText(buddy) == "online \194\183 Duskwood \194\183 in a fight", "now: " .. tostring(ns.Profile.NowText(buddy)))
  buddy.statusAt = time() - 600
  check(ns.Profile.NowText(buddy) == "online \194\183 Duskwood", "an old 'in a fight' is dropped")
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("PRO", { k = "", d = "", wanted = "", zone = "", status = "weird" }, "pro2"), "WHISPER", 77)
  check(buddy.sk == nil and buddy.wanted == nil and buddy.status == nil, "friend stopped sharing: their numbers fall back")
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("PRO", { k = 20, d = 5, wanted = "Rogz Fang", zone = "", status = "" }, "pro3"), "WHISPER", 77)

  -- leaderboard: you + friends, most kills first, reported numbers win
  local quiet = { name = "Quiet Friend", friend = true, k = 3, d = 0, a = 0, lastSeen = time(), class = "MAGE" }
  rr.players["Quiet Friend"] = quiet
  rr.players["Old Friend"] = { name = "Old Friend", friend = true, k = 50, d = 1, a = 0, lastSeen = time() - 400 * 86400 }
  local board = ns.Profile.Board()
  local names = {}
  for _, r in ipairs(board) do names[#names + 1] = r.name .. "=" .. r.k .. "/" .. r.d .. "#" .. r.rank end
  check(table.concat(names, ",") == "Buddy Pal=20/5#1,Testme Tester=12/4#2,Quiet Friend=3/0#3", "board order: " .. table.concat(names, ","))
  check(board[3].estimated and not board[1].estimated and board[2].me, "friend without a report is marked estimated")
  check(ns.Profile.KD(3, 0) == 3 and ns.Profile.KD(20, 5) == 4 and ns.Profile.KD(10, 3) == 3.33, "K/D: no deaths = kills, else 2 decimals")
  quiet.k, quiet.d = 12, 4
  board = ns.Profile.Board()
  check(board[2].rank == 2 and board[3].rank == 2, "same K and D: same rank")
  FriendsAndFoesDB.group = { ["Someone#9"] = true }
  board = ns.Profile.Board()
  check(#board == 1 and board[1].me, "picks active: only picked friends (and you) on the board")
  ns.Comm.ClearPicks()

  -- the feed knows who each PvP line is about
  local nFeed = #rr.feed
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("DIE", { zone = "Duskwood", killer = "Rogz Fang:ROGUE:60:Gank Squad", conf = "c", assists = "Helper Guy:MAGE:60:" }, "pd1"), "WHISPER", 77)
  local e = rr.feed[#rr.feed]
  check(#rr.feed == nFeed + 1 and e.who == "Buddy Pal" and e.foes[1] == "Rogz Fang" and e.foes[2] == "Helper Guy", "feed entry has who and foes")
  local recent = ns.Profile.Recent("Buddy Pal")
  check(#recent >= 1 and recent[1] == e, "friend's recent PvP, newest first")
  check(ns.Profile.Recent("Helper Guy", true)[1] == e, "enemy's recent PvP")
  local nem, times = ns.Profile.Nemesis("Buddy Pal")
  local most, mostName = 0, nil
  for _, h in pairs(rr.hitlist) do
    local n = h.kv and h.kv["Buddy Pal"] or 0
    if n > most or (n == most and mostName and h.name < mostName) then most, mostName = n, h.name end
  end
  check(nem and nem.name == mostName and times == most, "nemesis = the enemy with most kills on them: " .. tostring(nem and nem.name))
  local by = ns.Profile.WantedBy("Rogz Fang")
  check(#by == 2 and by[1] == "Buddy Pal" and by[2] == ns.me, "most wanted by you and Buddy")

  -- Enemies and Friends are their own tabs; the 0.6 names still work
  ns.UI.Show("enemies")
  local allEnemies = true
  for _, row in ipairs(ns.UI.Rows()) do if not row.enemy then allEnemies = false end end
  check(#ns.UI.Rows() > 0 and allEnemies, "Enemies tab lists enemies")
  ns.UI.Show("friends")
  local hasBuddy = false
  for _, row in ipairs(ns.UI.Rows()) do if row.name == "Buddy Pal" then hasBuddy = true end end
  check(hasBuddy, "Friends tab lists friends")
  ns.UI.Show("players")
  check(#ns.UI.Rows() > 0 and ns.UI.Rows()[1].enemy, "old 'players' name opens Enemies")
  ns.UI.SetPlayerFilter("friends")
  ns.UI.SetPlayerFilter("enemies")

  -- the window: Leaderboard tab, profiles for you, a friend and an enemy
  ns.UI.Show("board")
  check(#ns.UI.Rows() == 3 and ns.UI.Rows()[1].name == "Buddy Pal", "Leaderboard tab lists the board, most kills first")
  check(ns.Profile.KindOf(ns.me) == "me" and ns.Profile.KindOf("Buddy Pal") == "friend" and ns.Profile.KindOf("Rogz") == "enemy"
    and ns.Profile.KindOf("Nobody Atall") == nil, "profile kinds")
  local v = ns.UI.ProfileView("Buddy Pal")
  local function lineOf(view, label)
    for _, l in ipairs(view.lines) do if l[1] == label then return ns.Plain(tostring(l[2])) end end
  end
  check(v and lineOf(v, "Kills") == "20" and lineOf(v, "Rank") == "#1 of 3" and lineOf(v, "Most wanted") == "Rogz Fang"
    and lineOf(v, "Nemesis"):find(nem.name, 1, true) ~= nil, "friend profile: kills, rank, most wanted, nemesis")
  buddy.version = "0.6.3"
  check(ns.UI.ProfileView("Buddy Pal") and lineOf(ns.UI.ProfileView("Buddy Pal"), "Addon"):find("older", 1, true) ~= nil, "outdated addon hinted")
  v = ns.UI.ProfileView("Quiet Friend")
  check(v.estimated and lineOf(v, "Kills") == "~12", "estimated numbers marked ~")
  v = ns.UI.ProfileView(ns.me)
  check(v and v.isMe and lineOf(v, "Kills") == "12", "your own profile")
  v = ns.UI.ProfileView("Rogz Fang")
  check(v and v.kind == "enemy" and v.onHitlist and lineOf(v, "Most wanted by"):find("Buddy Pal", 1, true) ~= nil, "enemy profile")

  ns.UI.ShowProfile("Rogz")
  check(ns.UI.ProfileName() == "Rogz Fang", "bare first name opens the full name's profile")
  ns.UI.ProfileSave("camps the flight path")
  check(rr.hitlist["Rogz Fang"].note == "camps the flight path", "note saved from the enemy profile")
  ns.Profile.SetWanted(nil)
  ns.UI.ProfileAction()
  check(ns.Profile.Wanted() == "Rogz Fang", "enemy profile button makes them most wanted")
  ns.UI.ProfileAction()
  check(ns.Profile.Wanted() == nil, "and clears it again")
  ns.UI.ShowProfile(ns.me)
  ns.UI.ProfileSave("anything")
  check(FriendsAndFoesDB.profile.motto == nil, "your own profile has no free text to save")
  ns.UI.ShowProfile("Buddy Pal")
  ns.UI.ProfileAction()
  check(ns.Comm.IsPicked("Buddy#1234"), "friend profile button picks them")
  ns.UI.ProfileAction()
  ns.Comm.ClearPicks()
  ns.UI.ShowPlayer("Rogz Fang")
  check(ns.UI.ProfileName() == "Rogz Fang", "clicking a toast opens the profile")
  ns.UI.SelectTab("profile")

  -- slash commands
  SlashCmdList.FRIENDSANDFOES("wanted Rogz")
  check(ns.Profile.Wanted() == "Rogz Fang", "/fnf wanted resolves a first name")
  SlashCmdList.FRIENDSANDFOES("wanted clear")
  check(ns.Profile.Wanted() == nil, "/fnf wanted clear")
  local printed = #PRINTED
  SlashCmdList.FRIENDSANDFOES("motto Hello")
  check(PRINTED[#PRINTED] and PRINTED[#PRINTED]:find("/fnf", 1, true) and #PRINTED > printed, "/fnf motto is gone: just the help line")
  SlashCmdList.FRIENDSANDFOES("profile buddy pal")
  SlashCmdList.FRIENDSANDFOES("profile")
  check(ns.UI.ProfileName() == ns.me, "/fnf profile = your own")
  SlashCmdList.FRIENDSANDFOES("board")
  -- simulation view: the board shows the simulated friend, no errors
  ns.Sim.Run("kill", false)
  ns.UI.Show("board")
  ns.Sim.Clear()
  rr.players["Quiet Friend"], rr.players["Old Friend"] = nil, nil
  RUN_TIMERS(); RUN_TICKERS(8)
  check(ns.errors == errs, "no errors in profiles / leaderboard (" .. tostring(ns.lastError) .. ")")
end

-- 0.7: shared groups with relaying. Members are Battle.net accounts. You're friends with Buddy and
-- Alice; Carol is only Alice's friend, so her numbers reach you (and Buddy) through Alice and you.
do
  local errs = ns.errors
  local G = ns.Groups
  local F = { { gid = 77, name = "Buddy", tag = "Buddy#1234" }, { gid = 78, name = "Alice Wonder", tag = "Alice#5678" } }
  local o = { num = BNGetNumFriends, info = C_BattleNet.GetFriendGameAccountInfo, acct = C_BattleNet.GetFriendAccountInfo,
    byId = C_BattleNet.GetGameAccountInfoByID, bninfo = BNGetInfo }
  BNGetNumFriends = function() return #F, #F end
  C_BattleNet.GetFriendGameAccountInfo = function(i)
    local f = F[i]
    return f and { isOnline = true, clientProgram = "WoW", characterName = f.name, realmName = "X", factionName = "Horde", gameAccountID = f.gid }
  end
  C_BattleNet.GetFriendAccountInfo = function(i) return { battleTag = F[i] and F[i].tag } end
  C_BattleNet.GetGameAccountInfoByID = function(id)
    for _, f in ipairs(F) do
      if f.gid == id then return { characterName = f.name, realmName = "X", factionName = "Horde", gameAccountID = id } end
    end
  end
  check(G.MyKey() == nil and select(2, G.Create("No Tag")) == "GROUP_NO_TAG", "no BattleTag from Battle.net: no groups (and no error)")
  BNGetInfo = function() return 1, "Testme#1111" end
  local KME, KB, KA, KC = G.MyKey(), G.KeyOf("Buddy#1234"), G.KeyOf("Alice#5678"), G.KeyOf("Carol#4242")
  check(KME and KB and KA and KC and KB ~= KA and G.KeyOf("BUDDY#1234") == KB and not KB:find("buddy", 1, true),
    "account keys: stable, case-insensitive, not the BattleTag itself")

  local function from(name, gid, kind, fields)
    local p = ns.Comm.Encode({ kind = kind, id = ns.NewId(), name = name, class = "PRIEST", level = 40, f = fields })
    FIRE("BN_CHAT_MSG_ADDON", "FNF1", p, "WHISPER", gid)
  end
  local function sentTo(gid, kind)
    local out = {}
    for _, s in ipairs(SENT) do
      if s.route == "bn" and s.target == gid then
        local m = ns.Comm.Decode(s.payload)
        if m and m.kind == kind then out[#out + 1] = m end
      end
    end
    return out
  end
  local function drain() RUN_TIMERS(); RUN_TICKERS(60) end
  local function copy(g)
    local c = { id = g.id, name = g.name, owner = g.owner, members = {} }
    for k, m in pairs(g.members) do c.members[k] = { a = m.a, j = m.j, r = m.r, name = m.name } end
    return c
  end
  -- a member's copy of a group, sent to you by them
  local function sendGroup(c, name, gid)
    for _, m in ipairs(G.GroupMessages(c, KME)) do from(name, gid, "GRP", m.f) end
  end
  local function st(g, key) return G.StateOf(g, key) end

  ns.Comm.ClearPicks()
  ns.Comm.RebuildRoster()
  check(ns.Comm.everyone["Alice Wonder"] ~= nil and ns.Comm.everyone["Buddy Pal"] ~= nil, "two friends online")
  check(G.FriendKey("Buddy Pal") == KB, "a friend's account key from their character")
  drain(); SENT = {}

  check(G.UnB36(G.B36(1763290000)) == 1763290000 and G.B36(0) == "0", "base 36 round trip")
  check(select(2, G.Create("  ")) == "GROUP_BAD_NAME", "a group needs a name")
  local g = G.Create("Gank Squad")
  check(g and g.owner == ns.me and G.MyState(g) == "in" and G.Leader(g) == KME, "create: you're in it and lead it")
  check(select(2, G.Create("gank squad")) == "GROUP_EXISTS", "no two groups with the same name")
  check(select(2, G.Invite(g, "Nobody Known")) == "GROUP_NOT_FRIEND", "only your friends can be invited")

  -- friends on 0.6 can't be invited; then Buddy (on 0.7) is
  local buddyRec = ns.Data.RealRealm().players["Buddy Pal"]
  buddyRec.version = "0.6.3"
  check(select(2, G.Invite(g, "Buddy Pal")) == "GROUP_OLD_VERSION" and not table.concat(G.Invitable(g), ","):find("Buddy", 1, true),
    "friends on 0.6 can't be invited (they'd never see it)")
  buddyRec.version = ns.VERSION
  check(G.Invite(g, "Buddy Pal") == "Buddy Pal" and st(g, KB) == "invited" and g.members[KB].name == "Buddy Pal", "Buddy invited (by account)")
  drain()
  local toBuddy = sentTo(77, "GRP")
  check(#toBuddy >= 1 and toBuddy[1].f.members:find("^" .. KB .. ":") ~= nil and toBuddy[1].f.name == "Gank Squad", "invite sent to Buddy, his entry first")
  check(toBuddy[1] and not toBuddy[1].f.members:find("#", 1, true), "no BattleTags in group messages")
  check(#sentTo(78, "GRP") == 0, "non-members hear nothing")
  check(select(2, G.Invite(g, "Buddy Pal")) == "GROUP_ALREADY", "can't invite twice")

  -- Buddy joins on his side
  local bc = copy(g)
  bc.members[KB].j = bc.members[KB].a
  sendGroup(bc, "Buddy Pal", 77)
  check(st(g, KB) == "in", "Buddy's join reaches you")

  -- invite Alice; she joins; you pass her join on to Buddy (not back to her)
  G.Invite(g, "Alice Wonder")
  drain(); SENT = {}
  local ac = copy(g)
  ac.members[KA].j = ac.members[KA].a
  sendGroup(ac, "Alice Wonder", 78)
  drain()
  check(st(g, KA) == "in", "Alice joined")
  check(#sentTo(77, "GRP") >= 1 and #sentTo(78, "GRP") == 0, "her join is passed on to Buddy only")

  -- your own numbers: all your characters added up, sent to the members
  local rr = ns.Data.RealRealm()
  rr.players["Testme Alt"] = { name = "Testme Alt", self = true, friend = true, k = 5, d = 1, a = 0 }
  local myRec = rr.players[ns.me]
  local tot = G.MyTotals()
  check(tot.k == ns.Count(myRec.k) + 5 and tot.d == ns.Count(myRec.d) + 1, "your group numbers count every character on the account")
  SENT = {}
  G.MyStatsChanged()
  drain()
  local mine1 = sentTo(77, "GST")
  check(#mine1 >= 1 and mine1[1].f.stats:find("^" .. KME .. ":" .. tot.k .. ":" .. tot.d .. ":") ~= nil, "your totals go to Buddy")
  local whispered = false
  for _, s in ipairs(SENT) do
    if s.route == "whisper" and (s.payload:find("\tGST\t", 1, true) or s.payload:find("\tGRP\t", 1, true)) then whispered = true end
  end
  check(not whispered, "group messages go over Battle.net only (no duplicate whisper)")

  -- Buddy's numbers (from Buddy himself) are relayed to Alice, who isn't his friend
  SENT = {}
  local T = time() - 30
  from("Buddy Pal", 77, "GST", { stats = KB .. ":21:5:" .. G.B36(T) .. ":Buddy Pal" })
  drain()
  local gst = sentTo(78, "GST")
  check(G.StatsOf(KB).k == 21 and G.StatsOf(KB).direct and not G.StatsOf(KB).via, "Buddy's own numbers: direct")
  check(#gst >= 1 and gst[1].f.stats:find(KB .. ":21:5:", 1, true) ~= nil, "relayed to Alice")
  check(#sentTo(77, "GST") == 0, "not echoed back to Buddy")
  -- the same numbers coming back via Alice don't replace his own word
  from("Alice Wonder", 78, "GST", { stats = KB .. ":21:5:" .. G.B36(T) .. ":Buddy Pal" })
  check(G.StatsOf(KB).direct, "same age: the member's own word wins over a relayed copy")

  -- Alice invites her friend Carol, Carol joins; Carol's numbers come via Alice and go on to Buddy
  ac = copy(g)
  ac.members[KC] = { a = time(), name = "Carol Far" }
  sendGroup(ac, "Alice Wonder", 78)
  check(st(g, KC) == "invited" and g.members[KC].name == "Carol Far", "a member's invite of their own friend is merged")
  ac.members[KC].j = time()
  sendGroup(ac, "Alice Wonder", 78)
  check(st(g, KC) == "in", "Carol joined (through Alice)")
  drain(); SENT = {}
  local t = time() - 60
  from("Alice Wonder", 78, "GST", { stats = KC .. ":7:2:" .. G.B36(t) .. ":Carol Far" })
  drain()
  local carol = G.StatsOf(KC)
  check(carol and carol.k == 7 and carol.d == 2 and carol.via == "Alice Wonder" and carol.name == "Carol Far", "Carol's stats stored, via Alice")
  local toB = sentTo(77, "GST")
  check(#toB >= 1 and toB[1].f.stats:find(KC .. ":7:2:", 1, true) ~= nil, "and passed on to Buddy")
  SENT = {}
  from("Buddy Pal", 77, "GST", { stats = KC .. ":5:2:" .. G.B36(t - 100) .. ":Carol Far;" .. G.KeyOf("Random#1") .. ":9:9:" .. G.B36(t) .. ":Random Guy" })
  drain()
  check(G.StatsOf(KC).k == 7 and G.Relayed()[G.KeyOf("Random#1")] == nil, "older and non-member stats ignored")
  check(#SENT == 0, "nothing new: nothing passed on")
  -- a member whose clock runs fast: taken as "now", so later news still wins
  from("Alice Wonder", 78, "GST", { stats = KC .. ":8:2:" .. G.B36(time() + 10000) .. ":Carol Far" })
  check(G.StatsOf(KC).k == 8 and G.StatsOf(KC).t <= time(), "fast clock: accepted, stamped now")
  local later, realTime = time() + 1, time
  time = function(x) if x then return realTime(x) end return later end
  from("Alice Wonder", 78, "GST", { stats = KC .. ":9:2:" .. G.B36(later) .. ":Carol Far" })
  check(G.StatsOf(KC).k == 9, "the next real update replaces it")
  time = realTime
  drain(); SENT = {}

  -- the group board: one row per account
  local rows = ns.Profile.Board(g.id)
  local byName = {}
  for _, r in ipairs(rows) do byName[r.name] = r end
  check(#rows == 4 and byName[ns.me] and byName[ns.me].leader and byName[ns.me].k == tot.k and byName["Buddy Pal"].k == 21
    and byName["Carol Far"].k == 9 and byName["Carol Far"].via == "Alice Wonder", "group board: you (leader, all characters), Buddy, Alice, Carol (via Alice)")
  local _, _, n = G.Totals(g)
  check(n == 4, "totals count 4 members")

  -- someone invites you to their group; you join; then leave; an old copy can't pull you back in
  local shown = ns.Toast.shown or 0
  local nw = { id = "nightw1", name = "Night Watch", owner = "Buddy Pal", members = {
    [KB] = { a = time() - 50, j = time() - 50, name = "Buddy Pal" }, [KME] = { a = time() - 10, name = ns.me } } }
  sendGroup(nw, "Buddy Pal", 77)
  drainToasts()
  local mine = G.Get("nightw1")
  check(mine and G.MyState(mine) == "invited" and (ns.Toast.shown or 0) > shown, "invite received, with a toast")
  check(G.Leader(mine) == KB, "Buddy leads his group")
  SENT = {}
  check(G.Join(mine), "join")
  drain()
  local back = sentTo(77, "GRP")
  check(G.MyState(mine) == "in" and #back >= 1 and back[1].f.members:find("^" .. KB .. ":") ~= nil, "your join goes back to Buddy")
  check(select(2, G.Remove(mine, KB)) == "GROUP_NOT_LEADER", "only the leader removes")
  -- the leader leaves: whoever has been in longest after them leads now
  local ld = copy(mine)
  ld.members[KB].r = time()
  sendGroup(ld, "Buddy Pal", 77)
  check(st(mine, KB) == "out" and G.Leader(mine) == KME, "leader left: the next-oldest member leads")
  check(G.Leave(mine) and G.MyState(mine) == "out", "leave")
  sendGroup(nw, "Buddy Pal", 77)
  check(G.MyState(mine) == "out", "an old copy of the group doesn't bring you back")
  local count = #G.Mine()
  sendGroup({ id = "other1", name = "Not Mine", owner = "Buddy Pal", members = { [KB] = { a = time(), j = time(), name = "Buddy Pal" } } }, "Buddy Pal", 77)
  check(G.Get("other1") == nil and #G.Mine() == count, "groups you're not in aren't kept")

  -- leadership is by join time, so it's the same on every client: the second-oldest takes over
  local lg = { id = "leadtest", name = "Lead Test", owner = "Someone", members = {
    a1 = { a = 100, j = 100 }, a2 = { a = 150, j = 200 }, a3 = { a = 120, j = 300 } } }
  check(G.Leader(lg) == "a1", "the creator leads")
  lg.members.a1.r = 400
  check(G.Leader(lg) == "a2", "creator gone: the member who joined next leads")

  -- the 10-member cap holds even when invites made offline collide
  local cap = { id = "captest", name = "Cap Test", owner = "x", members = {} }
  for i = 1, 8 do cap.members["m" .. i] = { a = 100 + i, j = 200 + i } end
  cap.members.late = { a = 500, j = 600 } -- joined last
  cap.members.inv1 = { a = 300 }            -- invited, earlier
  cap.members.inv2 = { a = 400 }            -- invited, later: the 11th
  local states = G.States(cap)
  local n2 = 0
  for _ in pairs(states) do n2 = n2 + 1 end
  check(n2 == 10 and states.late == "in" and states.inv1 == "invited" and states.inv2 == nil, "over 10: the latest invite doesn't count; joined members keep their place")
  cap.members.inv1.j = 700
  cap.members.inv2.j = 800
  states = G.States(cap)
  check(states.inv2 == nil and states.inv1 == "in", "both join: the later joiner past 10 is out")

  -- group messages still flow with friends you didn't pick for alerts
  FriendsAndFoesDB.group = { ["Alice#5678"] = true }
  ns.Comm.RebuildRoster()
  local KQ = G.KeyOf("Quiet#7")
  bc = copy(g)
  bc.members[KQ] = { a = time(), name = "Quiet Member" }
  sendGroup(bc, "Buddy Pal", 77)
  check(st(g, KQ) == "invited", "unpicked friend's group update accepted")
  ns.Comm.ClearPicks()

  -- the leader removes someone
  check(G.Remove(g, KQ) and st(g, KQ) == "out", "leader removes a member")
  check(G.MemberByName(g, "carol") == KC and G.MemberByName(g, "Carol Far") == KC, "members found by name")

  -- full at 10 (invites count)
  local g2 = G.Create("Big Crew")
  for i = 1, 9 do g2.members["fill" .. i] = { a = time(), name = "Filler" .. i .. " X" } end
  check(select(2, G.Invite(g2, "Alice Wonder")) == "GROUP_FULL", "10 members max")
  G.Leave(g2)

  -- every message fits, and a big group decodes back to the same entries
  local fits = true
  for _, s in ipairs(SENT) do if #s.payload > 255 then fits = false end end
  local big = { id = "bigone", name = string.rep("N", 24), owner = "Longfirstname Longsurname", members = {} }
  for i = 1, 12 do
    big.members[G.KeyOf("Long" .. i .. "#12345")] = { a = time() - i * 1000, j = time() - i * 500, r = 0, name = "Longfirstname" .. i .. " Longsurname" }
  end
  local parts = G.GroupMessages(big, "x")
  for _, m in ipairs(parts) do if #ns.Comm.Encode(m) > 255 then fits = false end end
  check(fits and #parts >= 3, "group messages are split to fit 255 bytes: " .. #parts)
  local back2 = { id = "bigone", members = {} }
  for _, m in ipairs(parts) do
    local entries = {}
    for _, part in ipairs(ns.Split(m.f.members, ";")) do
      local p = ns.Split(part, ":")
      local function abs(v) local x = G.UnB36(v); return x and (m.f.base + x - 1) or 0 end
      entries[p[1]] = { a = abs(p[2]), j = abs(p[3]), r = abs(p[4]), name = p[5] }
    end
    G.Merge(back2, entries)
  end
  local same = true
  for k, mm in pairs(big.members) do
    local b = back2.members[k]
    if not b or b.a ~= mm.a or b.j ~= mm.j or b.name ~= mm.name then same = false end
  end
  check(same, "members survive encoding")

  -- the window: group board, buttons, slash commands
  ns.UI.Show("board")
  ns.UI.SetBoardView(g.id)
  check(ns.UI.BoardView() == g.id and #ns.UI.Rows() == 4, "Leaderboard shows the group")
  ns.UI.SetBoardView("friends")
  SlashCmdList.FRIENDSANDFOES("groups")
  SlashCmdList.FRIENDSANDFOES("groups new Test Crew")
  local tc = G.FindByName("Test Crew")
  check(tc and ns.UI.BoardView() == tc.id, "/fnf groups new")
  SlashCmdList.FRIENDSANDFOES("groups invite Test Crew Buddy Pal")
  check(st(tc, KB) == "invited", "/fnf groups invite <group> <friend>")
  SlashCmdList.FRIENDSANDFOES("groups remove Test Crew Buddy")
  check(st(tc, KB) == "out", "/fnf groups remove (first name works)")
  SlashCmdList.FRIENDSANDFOES("groups leave Test Crew")
  check(G.MyState(tc) == "out", "/fnf groups leave")
  ns.UI.SetBoardView(tc.id)
  check(ns.UI.BoardView() == "friends", "a group you left falls back to your friends")

  -- Back on the Profile page: to the tab you came from, as you left it
  ns.UI.Show("board")
  ns.UI.SetBoardView(g.id)
  ns.UI.ShowProfile("Buddy Pal")
  check(ns.UI.CurrentTab() == "profile" and ns.UI.BackLabel() == ns.L.TAB_BOARD, "profile from the Leaderboard: Back says Leaderboard")
  ns.UI.Back()
  check(ns.UI.CurrentTab() == "board" and ns.UI.BoardView() == g.id, "Back: the Leaderboard, still showing the group")
  check(ns.UI.BackLabel() == nil, "after going back there's nothing more to go back to")
  ns.UI.Back() -- does nothing
  check(ns.UI.CurrentTab() == "board", "Back with nowhere to go does nothing")
  ns.UI.Show("hitlist")
  ns.UI.ShowPlayer("Rogz Fang") -- like clicking a toast
  ns.UI.Back()
  check(ns.UI.CurrentTab() == "hitlist", "profile from a toast: Back to the tab you had open")
  ns.UI.SelectTab("feed")
  ns.UI.SelectTab("profile")
  check(ns.UI.BackLabel() == ns.L.TAB_FEED, "Profile tab clicked directly: Back to where you were")
  ns.UI.Back()
  ns.UI.SetBoardView("friends")

  -- you leave while every other member is offline: they hear it when they come back
  local g3 = G.Create("Late Crew")
  g3.members[KB] = { a = time() - 100, j = time() - 90, name = "Buddy Pal" }
  F = { F[2] } -- Buddy logs off
  ns.Comm.RebuildRoster()
  drain(); SENT = {}
  G.Leave(g3)
  drain()
  check(#sentTo(77, "GRP") == 0, "nobody online to tell")
  F = { { gid = 77, name = "Buddy", tag = "Buddy#1234" }, F[1] } -- Buddy back
  ns.Comm.RebuildRoster()
  drain()
  local told = false
  for _, m in ipairs(sentTo(77, "GRP")) do
    if m.f.gid == g3.id and m.f.members:find(KME .. ":[^:;]*:[^:;]*:%w+") then told = true end
  end
  check(told, "you left while they were offline: told when they log in")

  -- removed while offline for days: their stale copy gets an answer, so they find out
  G.Remove(g, KA)
  local am = g.members[KA]
  am.r, am.a, am.j = time() - 3 * 86400, time() - 5 * 86400, time() - 4 * 86400
  local stale = copy(g)
  stale.members[KA].r = nil
  drain(); SENT = {}
  sendGroup(stale, "Alice Wonder", 78)
  drain()
  check(st(g, KA) == "out" and #sentTo(78, "GRP") >= 1, "stale copy from a removed member: still out, and told")
  SENT = {}
  sendGroup(copy(g), "Alice Wonder", 78)
  drain()
  check(#sentTo(78, "GRP") == 0, "a copy that already knows gets no answer")

  -- cleanup never forgets removals, so an ancient copy can't bring anyone back
  G.Tidy()
  check(g.members[KQ] and st(g, KQ) == "out", "removal record kept after cleanup")
  local ancient = copy(g)
  ancient.members[KQ] = { a = g.members[KQ].a, name = "Quiet Member" }
  sendGroup(ancient, "Buddy Pal", 77)
  check(st(g, KQ) == "out", "an ancient copy doesn't bring them back")

  -- upkeep: relayed stats about accounts in none of your groups are dropped
  G.Relayed()["gone_1"] = { k = 1, d = 1, t = time() }
  G.Tidy()
  check(G.Relayed()["gone_1"] == nil and G.Relayed()[KC] ~= nil, "tidy drops stats you no longer need")

  -- language filter (ProfanityLib + its word list). Without them, others' words stay hidden.
  local P, L = ns.Profile, ns.L
  -- the bundled filter is there from the start, with the real word list
  local realLib, realData = ProfanityLib, ProfanityLibData
  check(P.FilterReady() and realLib.VERSION == 4 and realData.VERSION == 4, "bundled ProfanityLib and its word list are loaded")
  check(P.Check("Gank Squad") == "ok" and P.Check("Night Watch") == "ok" and P.Check("Tarren Mill Defenders") == "ok",
    "ordinary group names pass the real word list")
  check(P.Check("Hitler Fans") == "offensive" and P.Check("H1tl3r") == "offensive", "the real word list catches hate terms, also in l33t")
  check(select(2, G.Create("Hitler Fans")) == "TEXT_OFFENSIVE", "such a name can't be used for a group")
  -- if it were ever missing (or a broken copy), others' words stay hidden
  ProfanityLib, ProfanityLibData = nil, nil
  check(not P.FilterReady() and P.Check("Hello there") == "unchecked", "no filter installed: nothing from others counts as checked")
  local foreign = G.Create("Temp Crew")
  check(G.Label(foreign) == "Temp Crew", "your own group names always show")
  local nwg = G.Get("nightw1")
  check(G.Label(nwg) == L.GROUP_UNNAMED, "no filter: someone else's group name is hidden")
  -- a stand-in ProfanityLib that flags one made-up word
  ProfanityLib = { IsProfane = function(_, s)
    local f = s:lower():gsub("[^a-z]", "")
    if f:find("zzbad", 1, true) then return true, "zzbad" end
    return false, nil
  end }
  check(not P.FilterReady(), "the matcher without its word list doesn't count")
  ProfanityLibData = { VERSION = 4 }
  check(P.FilterReady() and P.Check("Hello there") == "ok" and P.Check("zz-BAD!") == "offensive", "filter installed: checks text")
  check(select(2, G.Create("zzbad crew")) == "TEXT_OFFENSIVE", "an offensive group name can't be created")
  check(G.Label(nwg) == "Night Watch", "a clean group name from someone else shows once checked")
  nwg.name = "Zzbad Watch"
  check(G.Label(nwg) == L.GROUP_UNNAMED and G.FindByName("Zzbad Watch") == nil, "an offensive group name is hidden and can't be typed to reach it")
  g.members[KC].name = "Zzbad Person"
  check(G.DisplayName(g, KC) == "?", "an offensive member name is hidden")
  ProfanityLib.IsProfane = function() error("broken") end
  check(P.Check("anything") == "unchecked", "a broken filter counts as not checked (hidden), not as clean")
  ProfanityLib, ProfanityLibData = realLib, realData -- back to the bundled filter
  nwg.name, g.members[KC].name = "Night Watch", "Carol Far"
  G.Leave(foreign)

  -- group names: 2-24 characters, like guild names; too long is refused, not cut
  check(select(2, G.Create("X")) == "GROUP_BAD_NAME", "one character is too short")
  check(select(2, G.Create(string.rep("a", 25))) == "GROUP_NAME_TOO_LONG", "25 characters is too long")
  local accented = string.rep("\195\134", 24) -- 24 x "Æ": 48 bytes, 24 characters
  local okName = G.Create(accented)
  check(okName and okName.name == accented, "24 accented characters fit (counted as characters, not bytes)")
  G.Leave(okName)
  check(G.CleanName(string.rep("b", 40)) == string.rep("b", 24), "a longer name from someone else is cut to 24")
  check(G.CleanName("Gank:Squad;x") == "Gank Squad x", "separators can't sneak into a name")

  rr.players["Testme Alt"] = nil
  BNGetNumFriends, C_BattleNet.GetFriendGameAccountInfo, C_BattleNet.GetFriendAccountInfo, C_BattleNet.GetGameAccountInfoByID, BNGetInfo =
    o.num, o.info, o.acct, o.byId, o.bninfo
  ns.Comm.RebuildRoster()
  drain()
  check(ns.errors == errs, "no errors in shared groups (" .. tostring(ns.lastError) .. ")")
end

-- 0.7.1: kill lists (who each player killed), shared on request; Back through the views;
-- catch-up from friends who come online after you, 24 hours / 100 events
do
  local errs = ns.errors
  local K, G = ns.Kills, ns.Groups
  local rr = ns.Data.RealRealm()
  ns.viewSim = false
  ns.Comm.ClearPicks()
  ns.Comm.RebuildRoster()
  RUN_TIMERS(); RUN_TICKERS(60); SENT = {}
  local function sentKinds(kind)
    local out = {}
    for _, s in ipairs(SENT) do
      local m = ns.Comm.Decode(s.payload)
      if m and m.kind == kind and s.route == "bn" then out[#out + 1] = m end
    end
    return out
  end

  -- a friend's kills are counted per victim
  local buddy = rr.players["Buddy Pal"]
  buddy.slain, buddy.slainRep, buddy.slainRepAt = nil, nil, nil
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("KILL", { victim = "Vex Morrow", vclass = "MAGE", vlevel = 40, vguild = "", zone = "Duskwood" }, "kl1"), "WHISPER", 77)
  ADVANCE(20)
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("KILL", { victim = "Vex Morrow", vclass = "MAGE", vlevel = 40, vguild = "", zone = "Hillsbrad Foothills" }, "kl2"), "WHISPER", 77)
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("KILL", { victim = "Grim Shade", vclass = "ROGUE", vlevel = 41, vguild = "", zone = "Duskwood" }, "kl3"), "WHISPER", 77)
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("KILL", { victim = "", vclass = "", vlevel = "", vguild = "", zone = "Duskwood" }, "kl4"), "WHISPER", 77)
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("KILL", { victim = "Vex Morrow", vclass = "MAGE", vlevel = 40, vguild = "", zone = "Duskwood" }, "kl1"), "WHISPER", 77) -- same message again
  drainToasts()
  check(buddy.slain["Vex Morrow"].n == 2 and buddy.slain["Grim Shade"].n == 1, "kills counted per victim (repeats ignored)")
  check(buddy.slain["Vex Morrow"].zone == "Hillsbrad Foothills", "last kill's zone kept")
  local list = K.List("Buddy Pal")
  check(#list == 2 and K.Total(list) == 3, "a nameless kill isn't listed: 2 players, 3 kills")
  local vex
  for _, r in ipairs(list) do if r.name == "Vex Morrow" then vex = r end end
  check(vex and vex.class == "MAGE" and vex.level == 40, "victim's class and level come from what you know of them")

  -- their own list (asked for) merges in: the higher count wins, nothing you saw is lost
  local T = time() - 100
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("KLA", { who = "Buddy Pal", total = 3,
    list = "Vex Morrow:5:" .. G.B36(T) .. ";Old Foe:4:" .. G.B36(T) .. ";Grim Shade:1:" .. G.B36(T) }, "ka1"), "WHISPER", 77)
  list = K.List("Buddy Pal")
  local byName = {}
  for _, r in ipairs(list) do byName[r.name] = r end
  check(byName["Vex Morrow"].n == 5 and byName["Old Foe"].n == 4 and byName["Grim Shade"].n == 1 and #list == 3,
    "their own report merged: higher counts win, kills you never saw are added")
  check(buddy.slainRepAt and buddy.slainRepTotal == 3, "when it came and how many in all are noted")
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("KLA", { who = "Someone Else", total = 1, list = "Vex Morrow:99:" .. G.B36(T) }, "ka2"), "WHISPER", 77)
  check(byName["Vex Morrow"].n == 5 and K.List("Buddy Pal")[1].n ~= 99, "a list about someone else is ignored")

  -- you answer a friend's request with your own list (only for the character you're playing)
  local me = rr.players[ns.me]
  me.slain = { ["Vex Morrow"] = { n = 3, t = time() - 50 }, ["Nem Esis"] = { n = 1, t = time() - 10 } }
  SENT = {}
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("KLQ", { who = ns.me }, "kq1"), "WHISPER", 77)
  RUN_TICKERS(20)
  local ans = sentKinds("KLA")
  check(#ans == 1 and ans[1].f.who == ns.me and ans[1].f.total == "2" and ans[1].f.list:find("^Vex Morrow:3:") ~= nil,
    "asked for your list: you send it, most kills first")
  SENT = {}
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("KLQ", { who = ns.me }, "kq2"), "WHISPER", 77)
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("KLQ", { who = "Testme Alt" }, "kq3"), "WHISPER", 77)
  RUN_TICKERS(20)
  check(#sentKinds("KLA") == 0, "not again within a minute, and not for a character you're not on")
  ADVANCE(61)
  ns.S().share.pvp = false
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("KLQ", { who = ns.me }, "kq4"), "WHISPER", 77)
  RUN_TICKERS(20)
  check(#sentKinds("KLA") == 0, "not sharing PvP: your list isn't sent")
  ns.S().share.pvp = true
  -- a long list is split over messages that each fit
  ADVANCE(61)
  me.slain = {}
  for i = 1, 80 do me.slain["Victimname" .. i .. " Longsurname"] = { n = i, t = time() } end
  SENT = {}
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("KLQ", { who = ns.me }, "kq5"), "WHISPER", 77)
  RUN_TICKERS(80)
  local parts, entries, fits = sentKinds("KLA"), 0, true
  for _, m in ipairs(parts) do
    entries = entries + #ns.Split(m.f.list, ";")
    if #ns.Comm.Encode(m) > 255 then fits = false end
  end
  check(#parts >= 3 and entries == 60 and fits, "top 60 of 80 victims, split over messages that fit: " .. #parts .. " / " .. entries)
  me.slain = nil

  -- opening a friend's kill list asks them (once every 2 minutes)
  SENT = {}
  ns.UI.Show("board")
  ns.UI.ShowProfile("Buddy Pal")
  ns.UI.ShowKills("Buddy Pal")
  RUN_TICKERS(10)
  check(#sentKinds("KLQ") == 1 and sentKinds("KLQ")[1].f.who == "Buddy Pal", "opening their kill list asks them for it")
  check(ns.UI.CurrentTab() == "kills" and ns.UI.KillsOf() == "Buddy Pal" and #ns.UI.Rows() == 3, "the kill list view shows their victims")
  check(ns.UI.Rows()[1].name == "Vex Morrow", "most kills first")
  SENT = {}
  ns.UI.ShowKills("Buddy Pal")
  RUN_TICKERS(10)
  check(#sentKinds("KLQ") == 0, "not asked again right away")

  -- Back goes back through the way you came: kill list -> profile -> Leaderboard
  check(ns.UI.BackLabel() == "Buddy Pal", "from the kill list, Back says whose profile")
  ns.UI.ShowProfile("Vex Morrow") -- clicking a victim
  check(ns.UI.BackLabel() == ns.L.KILLS_OF:format("Buddy Pal"), "from a victim's profile, Back goes to the kill list")
  ns.UI.Back()
  check(ns.UI.CurrentTab() == "kills" and ns.UI.KillsOf() == "Buddy Pal", "Back: the kill list again")
  ns.UI.Back()
  check(ns.UI.CurrentTab() == "profile" and ns.UI.ProfileName() == "Buddy Pal", "Back: their profile")
  ns.UI.Back()
  check(ns.UI.CurrentTab() == "board" and ns.UI.BackLabel() == nil, "Back: the Leaderboard, and that's the start")
  ns.UI.ShowKills("Buddy Pal")
  ns.UI.SelectTab("feed")
  check(ns.UI.BackLabel() == nil, "picking a tab yourself starts over")

  -- an enemy's kill list: the friends they killed
  local rows = K.List("Rogz Fang")
  local hasBuddy = false
  for _, r in ipairs(rows) do if r.name == "Buddy Pal" then hasBuddy = true end end
  check(#rows >= 1 and hasBuddy, "an enemy's kill list shows the friends they killed")

  -- merging two records of the same player adds their kill lists up
  local a = { name = "X", slain = { Foo = { n = 2, t = 10 } } }
  ns.Data.MergeInto(a, { slain = { Foo = { n = 3, t = 20, zone = "Z" }, Bar = { n = 1, t = 5 } } })
  check(a.slain.Foo.n == 5 and a.slain.Foo.t == 20 and a.slain.Foo.zone == "Z" and a.slain.Bar.n == 1, "kill lists add up when records merge")

  -- one time: kills already in the Feed (since 0.7.0) fill the lists
  local db = { realms = { Forever = { players = { ["Kil Ler"] = { name = "Kil Ler", k = 2, d = 0 } }, hitlist = {}, feed = {
    { t = 100, kind = "kill", text = "x", who = "Kil Ler", foes = { "Poor Soul" } },
    { t = 200, kind = "kill", text = "y", who = "Kil Ler", foes = { "Poor Soul" } },
    { t = 300, kind = "died", text = "z", who = "Kil Ler", foes = { "Poor Soul" } } } } } }
  check(K.Backfill(db) == 2 and db.realms.Forever.players["Kil Ler"].slain["Poor Soul"].n == 2, "backfill from the Feed: kills only")
  check(K.Backfill(db) == 0, "backfill runs once")

  -- catch-up: a friend who comes online after you is asked too; 24 hours; 100 events
  ns.Comm.SetAwayFrom(time() - 7200)
  FRIENDS_ONLINE = 0
  ns.Comm.RebuildRoster()
  RUN_TICKERS(20); SENT = {}
  FRIENDS_ONLINE = 1
  ns.Comm.RebuildRoster()
  RUN_TICKERS(20)
  local req = sentKinds("REQ")
  check(#req == 1 and math.abs(tonumber(req[1].f.window) - 7200) <= 5, "a friend coming online later is asked what you missed")
  FRIENDS_ONLINE = 0
  ns.Comm.RebuildRoster()
  FRIENDS_ONLINE = 1
  SENT = {}
  ns.Comm.RebuildRoster()
  RUN_TICKERS(20)
  check(#sentKinds("REQ") == 0, "once per session per friend")
  ns.Comm.SetAwayFrom(time() - 3 * 86400)
  FRIENDS_ONLINE = 0
  ns.Comm.RebuildRoster()
  FRIENDS_ONLINE = 1
  SENT = {}
  ns.Comm.RebuildRoster()
  RUN_TICKERS(20)
  req = sentKinds("REQ")
  check(#req == 1 and tonumber(req[1].f.window) == 86400, "away for days: asks for the last 24 hours")
  check(ns.Comm.CATCHUP_WINDOW == 86400, "catch-up window is 24 hours")
  local box = ns.Comm.Outbox()
  local keep = {}
  for i, e in ipairs(box) do keep[i] = e end
  for i = 1, 130 do ns.Comm.Remember("LVL", "ob" .. i, { level = i }) end
  check(#ns.Comm.Outbox() == 100, "up to 100 of your own events kept for friends: " .. #ns.Comm.Outbox())
  wipe(box)
  for i, e in ipairs(keep) do box[i] = e end

  RUN_TIMERS(); RUN_TICKERS(60)
  check(ns.errors == errs, "no errors in kill lists / catch-up (" .. tostring(ns.lastError) .. ")")
end

-- 0.7.1: relayed catch-up. You're friends with Buddy and Alice. Events Alice allows to be passed
-- on reach Buddy through you (only if Buddy names her), and Alice's events reach you through Buddy.
do
  local errs = ns.errors
  local F = { { gid = 77, name = "Buddy", tag = "Buddy#1234" }, { gid = 78, name = "Alice Wonder", tag = "Alice#5678" } }
  local o = { num = BNGetNumFriends, info = C_BattleNet.GetFriendGameAccountInfo, acct = C_BattleNet.GetFriendAccountInfo,
    byId = C_BattleNet.GetGameAccountInfoByID }
  BNGetNumFriends = function() return #F, #F end
  C_BattleNet.GetFriendGameAccountInfo = function(i)
    local f = F[i]
    return f and { isOnline = true, clientProgram = "WoW", characterName = f.name, realmName = "X", factionName = "Horde", gameAccountID = f.gid }
  end
  C_BattleNet.GetFriendAccountInfo = function(i) return { battleTag = F[i] and F[i].tag } end
  C_BattleNet.GetGameAccountInfoByID = function(id)
    for _, f in ipairs(F) do
      if f.gid == id then return { characterName = f.name, realmName = "X", factionName = "Horde", gameAccountID = id } end
    end
  end
  local function from(name, gid, kind, fields, id)
    local p = ns.Comm.Encode({ kind = kind, id = id or ns.NewId(), name = name, class = "PRIEST", level = 40, f = fields })
    FIRE("BN_CHAT_MSG_ADDON", "FNF1", p, "WHISPER", gid)
  end
  local function sent(gid, kind)
    local out = {}
    for _, s in ipairs(SENT) do
      if s.route == "bn" and s.target == gid then
        local m = ns.Comm.Decode(s.payload)
        if m and m.kind == kind then out[#out + 1] = m end
      end
    end
    return out
  end
  local function drain() RUN_TIMERS(); RUN_TICKERS(60) end
  ns.Comm.ClearPicks()
  ns.Comm.RebuildRoster()
  drain(); SENT = {}
  local rr = ns.Data.RealRealm()
  local box = ns.Comm.HeardBox()
  wipe(box)

  -- what you keep to pass on: only events marked "may be passed on"
  from("Alice Wonder", 78, "KILL", { victim = "Relay Victim", vclass = "MAGE", vlevel = 50, vguild = "", zone = "Duskwood", rl = "1" }, "ak1")
  from("Alice Wonder", 78, "LVL", { level = 51, rl = "" }, "al1")
  from("Alice Wonder", 78, "DIE", { zone = "Duskwood", killer = "Relay Killer:ROGUE:60:A Very Long Guild Name Here",
    conf = "c", assists = "Helper One:MAGE:60:Another Long Guild Name;Helper Two:PRIEST:60:Yet Another Guild Name", rl = "1" }, "ad1")
  drainToasts()
  check(#box == 2 and box[1].o == "Alice Wonder" and box[1].k == "KILL", "kept to pass on: the events Alice allows (not the one she doesn't)")

  -- Buddy asks for Alice: he gets her events, passed on by you
  SENT = {}
  from("Buddy Pal", 77, "RLQ", { window = 3600, names = "Alice Wonder;Not Asked" }, "rq1")
  drain()
  local rly = sent(77, "RLY")
  local ids = {}
  for _, m in ipairs(rly) do if m.f.origin == "Alice Wonder" then ids[m.f.oid] = m.f.okind end end
  check(#rly == 2 and ids.ak1 == "KILL" and ids.ad1 == "DIE", "Buddy asked for Alice: her events go to him (newest first)")
  local fits = true
  for _, s in ipairs(SENT) do if #s.payload > 255 then fits = false end end
  check(fits, "a big event passed on still fits in one message")
  SENT = {}
  from("Buddy Pal", 77, "RLQ", { window = 3600, names = "Alice Wonder" }, "rq2")
  drain()
  check(#sent(77, "RLY") == 0, "asked again soon: not sent twice")
  SENT = {}
  from("Buddy Pal", 77, "RLQ", { window = 3600, names = "Someone Else" }, "rq3")
  drain()
  check(#sent(77, "RLY") == 0, "only friends he names: nothing about anyone else")
  -- his own events never go back to him
  from("Buddy Pal", 77, "LVL", { level = 44, rl = "1" }, "bl1")
  SENT = {}
  from("Buddy Pal", 77, "RLQ", { window = 3600, names = "Buddy Pal" }, "rq4")
  drain()
  check(#sent(77, "RLY") == 0, "his own events aren't sent back to him")

  -- you receive Alice's events passed on by Buddy: applied quietly as from Alice
  local alice = rr.players["Alice Wonder"]
  alice.slain = nil
  local shown = ns.Toast.shown or 0
  CHAT = {}
  local feedBefore = #rr.feed
  local data = table.concat({ "Far Victim", "ROGUE", "52", "", "Stranglethorn Vale", "2" }, "^")
  from("Buddy Pal", 77, "RLY", { origin = "Alice Wonder", oclass = "MAGE", olevel = 52, okind = "KILL", oid = "ak9", ago = 5400, data = data }, "ry1")
  drainToasts(); RUN_TIMERS()
  local e
  for _, x in ipairs(rr.feed) do if x.foes and x.foes[1] == "Far Victim" then e = x end end -- (in time order)
  check(#rr.feed == feedBefore + 1 and e and e.who == "Alice Wonder" and math.abs(e.t - (time() - 5400)) <= 5,
    "passed-on event lands in your Feed as Alice's, at the time it happened")
  check(alice.slain and alice.slain["Far Victim"].n == 1, "and in her kill list")
  check((ns.Toast.shown or 0) == shown, "no toast for it")
  check(#CHAT == 1 and CHAT[1]:find("Alice Wonder", 1, true) ~= nil, "one quiet chat line names Alice")
  from("Buddy Pal", 77, "RLY", { origin = "Alice Wonder", oclass = "MAGE", olevel = 52, okind = "KILL", oid = "ak9", ago = 5400, data = data }, "ry2")
  check(#rr.feed == feedBefore + 1, "the same event passed on again (or by another friend) is applied once")
  local kept = #box
  check(kept == #ns.Comm.HeardBox(), "a passed-on event is never passed on again (one hop)")
  -- not your friend, yourself, the relayer itself, too old, or not picked: ignored
  from("Buddy Pal", 77, "RLY", { origin = "Total Stranger", oclass = "", olevel = "", okind = "LVL", oid = "x1", ago = 60, data = "20" }, "ry3")
  from("Buddy Pal", 77, "RLY", { origin = ns.me, oclass = "", olevel = "", okind = "LVL", oid = "x2", ago = 60, data = "20" }, "ry4")
  from("Buddy Pal", 77, "RLY", { origin = "Alice Wonder", oclass = "", olevel = "", okind = "LVL", oid = "x3", ago = 3 * 86400, data = "20" }, "ry5")
  from("Buddy Pal", 77, "RLY", { origin = "Alice Wonder", oclass = "", olevel = "", okind = "HIT", oid = "x4", ago = 60, data = "" }, "ry6")
  check(rr.players["Total Stranger"] == nil and #rr.feed == feedBefore + 1, "strangers, yourself, too old and other kinds are ignored")
  FriendsAndFoesDB.group = { ["Buddy#1234"] = true } -- you only want alerts from Buddy
  ns.Comm.RebuildRoster()
  from("Buddy Pal", 77, "RLY", { origin = "Alice Wonder", oclass = "", olevel = "", okind = "LVL", oid = "x5", ago = 60, data = "53" }, "ry7")
  check(#rr.feed == feedBefore + 1, "your picks still count: Alice not picked, her events not taken")
  ns.Comm.ClearPicks()

  -- your own events: may be passed on unless you said no, or only share with picks
  check(ns.Comm.RelayAllowed(), "by default friends may pass on your events")
  ns.S().share.relay = false
  check(not ns.Comm.RelayAllowed(), "'Friends may pass on my events' off: not allowed")
  ns.S().share.relay = true
  FriendsAndFoesDB.group = { ["Buddy#1234"] = true }
  check(not ns.Comm.RelayAllowed(), "alerts limited to picked friends: never passed on")
  FriendsAndFoesDB.group = {}

  -- asking: online friends are asked for your offline friends' events
  F = { F[1] } -- Alice goes offline
  ns.Comm.RebuildRoster()
  drain(); SENT = {}
  check(ns.Comm.AskRelay(3600) == 1, "one ask")
  drain()
  local rlq = sent(77, "RLQ")
  check(#rlq == 1 and rlq[1].f.names:find("Alice Wonder", 1, true) ~= nil and not rlq[1].f.names:find("Buddy", 1, true)
    and tonumber(rlq[1].f.window) == 3600, "Buddy is asked about Alice (offline), not about himself")

  BNGetNumFriends, C_BattleNet.GetFriendGameAccountInfo, C_BattleNet.GetFriendAccountInfo, C_BattleNet.GetGameAccountInfoByID = o.num, o.info, o.acct, o.byId
  ns.Comm.RebuildRoster()
  drain()
  check(ns.errors == errs, "no errors in relayed catch-up (" .. tostring(ns.lastError) .. ")")
end

RESULTS[#RESULTS + 1] = string.format("%d passed, %d failed", passed, failed)
