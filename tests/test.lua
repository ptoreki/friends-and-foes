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
    and s.show.engage == "toast" and s.show.died == "toast" and s.show.kill == "toast" and s.show.sighting == "toast" and s.show.share == nil
  local okSound = s.sound.enabled and not s.sound.level and s.sound.loot and s.sound.gear and s.sound.attacked and not s.sound.engage
    and s.sound.died and s.sound.kill and s.sound.sighting and s.sound.share == nil
  local okPick = s.soundPick.trouble == "default" and s.soundPick.victory == "default" and s.soundPick.sighting == "mapping"
    and s.soundPick.progress == "default" and s.soundPick.bounty == "default" and s.soundPick.kill == nil
  check(okShow and okSound and okPick, "default alerts and sounds")
  check(s.nearbyOnly == false and s.dnd.combat == false and s.toastDuration == 5 and s.theme == "minimal" and s.toastScale == 1
    and s.flavor and s.weekly and s.mark and s.markTooltip and s.milestones == nil and s.levelEvery == 1 and s.gearMin == nil
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

-- test alerts (/fnf test, /fnf sim): sample toasts and a chat line - nothing recorded or sent
local real = ns.Data.RealRealm()
RUN_TICKERS(8) -- drain the profile greeting sent at login
SENT, CHAT = {}, {}
ns.Toast.Test()
RUN_TICKERS(4)
check(#real.feed == 0 and next(real.hitlist) == nil and #SENT == 0 and FriendsAndFoesDB.sim == nil and ns.Sim == nil,
  "test alerts: nothing recorded, nothing sent, no simulation store")
check(#CHAT == 1, "test alerts: a sample chat line")
check(ns.errors == 0, "no errors in test alerts (" .. tostring(ns.lastError) .. ")")

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
local wt, routes = nil, {}
for _, s in ipairs(SENT) do routes[s.route] = (routes[s.route] or 0) + 1 end
check(routes.bn == 1 and not routes.whisper, "sent over Battle.net only, no whisper")
-- only if Battle.net messaging isn't there at all: a whisper, addressed "First Last"
local realBN = BNSendGameData
BNSendGameData = nil
SENT = {}
ns.Comm.SendPayload("ping", "high")
RUN_TICKERS(2)
for _, s in ipairs(SENT) do if s.route == "whisper" then wt = s.target end end
BNSendGameData = realBN
check(wt == "Buddy Pal", "fallback whisper (no Battle.net messaging) addresses First Last: " .. tostring(wt))
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
check(#SENT == 1 and SENT[1].route == "bn" and SENT[1].payload:find("^3\tLOOT\t%w+\tTestme Tester\t") ~= nil, "own loot broadcast")

-- throttle: 30 events -> at most bucket size sent per route at first
SENT = {}
for i = 1, 30 do ns.Comm.SendPayload("x" .. i, "normal") end
RUN_TICKERS(1)
local first = #SENT
check(first <= 8 and first >= 2, "throttle limits initial burst: " .. first)
RUN_TICKERS(200)
check(#SENT == 30, "all 30 sends eventually delivered: " .. #SENT)

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
-- sharing your hitlist is gone (0.9.4); a share from a friend on an older version still merges in
check(ns.Comm.ShareHitlist == nil and ns.UI.ShareHitlist == nil, "no Share hitlist")
-- receive a share chunk from Buddy
local before = count(real.hitlist)
FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("HIT", { share = "s1", entries = "Newguy Hunt:HUNTER:59:Their Guild:3:2:0:5;Enemy1 Foe:MAGE:60::99:7:1:1;Peaceful Pete:MAGE:20::4:0:0:2;Empty Ed:MAGE:20::0:0:0:2" }, "h1"), "WHISPER", 77)
check(count(real.hitlist) == before + 2, "share adds new entries")
check(real.hitlist["Enemy1 Foe"].attacks == 99 and real.hitlist["Enemy1 Foe"].kills == 7, "share merges with max()")
check(real.hitlist["Newguy Hunt"].sharedBy == "Buddy Pal", "sharedBy recorded")
check(real.hitlist["Peaceful Pete"] ~= nil and real.hitlist["Empty Ed"] == nil, "a shared attacker is added; an entry with no kills or attacks is not")

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
check(real.hitlist["Zed Q"] and real.hitlist["Zed Q"].attacks == 3 and real.hitlist["Zed Q"].kills == 0
  and real.players["Zed Q"].atk == 3 and #real.feed > 0, "attacked first: on the hitlist with their attacks, no kills")
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
FriendsAndFoesDB.dataVersion = nil -- (saved data from before the upgrade steps)
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
ns.SetDebug(false); ns.SetDebug(true)
FriendsAndFoes_OnAddonCompartmentClick(nil, "LeftButton")
FriendsAndFoes_OnAddonCompartmentClick(nil, "RightButton")
check(ns.errors == 0, "window tabs, options panel, addon menu: no errors (" .. tostring(ns.lastError) .. ")")
ns.UI.ShowPlayer("Rogz Fang")
SlashCmdList.FRIENDSANDFOES("sim") -- (the same quick test as /fnf test)
RUN_TIMERS()
SlashCmdList.FRIENDSANDFOES("status")
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
local function nolv(s) return (ns.Plain(s):gsub(" %(%d+%)", "")) end -- (Feed lines carry levels: tested separately)
check(nolv(lastFeed()) == "Buddy Pal killed Vic Tim · Duskwood", "compact kill: " .. plain(lastFeed()))
FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("DIE", { zone = "Duskwood", killer = "Nem Esis:ROGUE:60:", conf = "c", assists = "" }, "fc1"), "WHISPER", 77)
check(nolv(lastFeed()) == "Buddy Pal killed by Nem Esis · Duskwood", "compact death: " .. plain(lastFeed()))
FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("ATK", { enc = "fc2", zone = "Duskwood", attackers = "Nem Esis:ROGUE:60:" }, "fc2"), "WHISPER", 77)
check(nolv(lastFeed()) == "Buddy Pal attacked by Nem Esis · Duskwood", "compact attack: " .. plain(lastFeed()))
ADVANCE(20)
FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("KILL", { victim = "Nem Esis", vclass = "ROGUE", vlevel = "60", vguild = "", zone = "Duskwood" }, "fc3"), "WHISPER", 77)
check(nolv(lastFeed()) == "Buddy Pal killed Nem Esis (revenge) · Duskwood", "compact revenge: " .. plain(lastFeed()))
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
  -- 1) dead enemy target (seen alive during the fight, then dead)
  enemyUnits.target = { "Corpse", "Target", false }
  ns.PvP.ReadEnemy("target")
  ADVANCE(30)
  enemyUnits.target[3] = true
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
  -- 4) an old corpse you never saw alive isn't your kill
  enemyUnits.target = { "Old", "Corpse", true }
  ADVANCE(30)
  FIRE("CHAT_MSG_COMBAT_HONOR_GAIN", HONOR)
  check(lastFeed():find("Old Corpse", 1, true) == nil and lastFeed():find("got a kill", 1, true) ~= nil, "an old corpse isn't credited: " .. lastFeed())
  enemyUnits.target = nil
  -- 5) a long fight: targeted 90 s before the kill, never hit you - their health changing during
  -- the fight keeps them "seen alive", so the kill is theirs
  enemyUnits.target = { "Long", "Fight", false }
  ns.PvP.ReadEnemy("target")
  for _ = 1, 9 do
    ADVANCE(10)
    FIRE("UNIT_HEALTH", "target")
  end
  enemyUnits.target[3] = true
  FIRE("CHAT_MSG_COMBAT_HONOR_GAIN", HONOR)
  check(lastFeed():find("Long Fight", 1, true) ~= nil, "a fight over a minute long: the kill still names the target: " .. lastFeed())
  enemyUnits.target = nil
  -- 6) not targeted, killed by a damage-over-time spell: their nameplate (seen alive while the
  -- dot ticks) shows them dead when the honor comes
  enemyUnits.nameplate5 = { "Dot", "Victim", false }
  FIRE("NAME_PLATE_UNIT_ADDED", "nameplate5")
  for _ = 1, 8 do
    ADVANCE(10)
    FIRE("UNIT_HEALTH", "nameplate5")
  end
  enemyUnits.nameplate5[3] = true
  FIRE("CHAT_MSG_COMBAT_HONOR_GAIN", HONOR)
  check(lastFeed():find("Dot Victim", 1, true) ~= nil, "killed by a dot, never targeted: named from their nameplate: " .. lastFeed())
  -- 7) ...but with no nameplate, target or mouseover there's nobody to name: a kill without a name
  enemyUnits.nameplate5 = nil
  FIRE("NAME_PLATE_UNIT_REMOVED", "nameplate5")
  ADVANCE(30)
  FIRE("CHAT_MSG_COMBAT_HONOR_GAIN", HONOR)
  check(lastFeed():find("got a kill", 1, true) ~= nil, "nothing on screen: a kill without a name: " .. lastFeed())
  -- 8) killing blows (PARTY_KILL): your blow names the victim exactly, even with nothing on screen
  local oGuid = UnitGUID
  UnitGUID = function(u)
    if u == "player" then return "Player-1-00000001" end
    if enemyUnits[u] then return "Player-1-" .. enemyUnits[u][1] end
  end
  enemyUnits.target = { "Blow", "Taker", false }
  ns.PvP.ReadEnemy("target") -- (seen once: their GUID is known)
  enemyUnits.target = nil -- (then out of sight: a DoT finishes them)
  ADVANCE(40)
  FIRE("PARTY_KILL", "Player-1-00000001", "Player-1-Blow")
  FIRE("CHAT_MSG_COMBAT_HONOR_GAIN", HONOR)
  check(lastFeed():find("Blow Taker", 1, true) and lastFeed():find(ns.L.KILLING_BLOW_TAG, 1, true) and ns.caps.partyKill == "ok",
    "your killing blow: the victim named exactly, marked as a killing blow: " .. lastFeed())
  -- a party member's blow, or one coming after the honor, doesn't name your kill
  ADVANCE(30)
  FIRE("PARTY_KILL", "Player-1-00000099", "Player-1-Blow")
  FIRE("CHAT_MSG_COMBAT_HONOR_GAIN", HONOR)
  check(not lastFeed():find(ns.L.KILLING_BLOW_TAG, 1, true), "a party member's killing blow isn't yours: " .. lastFeed())
  ADVANCE(30)
  FIRE("CHAT_MSG_COMBAT_HONOR_GAIN", HONOR)
  FIRE("PARTY_KILL", "Player-1-00000001", "Player-1-Blow")
  ADVANCE(30)
  FIRE("CHAT_MSG_COMBAT_HONOR_GAIN", HONOR)
  check(not lastFeed():find(ns.L.KILLING_BLOW_TAG, 1, true), "a killing blow after the honor is only logged, never used for the next kill: " .. lastFeed())
  -- a blow on a creature isn't a player kill
  FIRE("PARTY_KILL", "Player-1-00000001", "Creature-0-1-2-3-4-5")
  FIRE("CHAT_MSG_COMBAT_HONOR_GAIN", HONOR)
  check(not lastFeed():find(ns.L.KILLING_BLOW_TAG, 1, true), "a killing blow on a creature doesn't count")
  -- a friend's kill, then your own killing blow and honor for the same victim 3 s later: one line
  do
    ADVANCE(10)
    drainToasts()
    ns.Events.Apply({ kind = "KILL", id = ns.NewId(), from = "Buddy Pal", class = "PRIEST", level = 40,
      f = { victim = "Latey Comer", vclass = "MAGE", vlevel = "30", vguild = "", zone = "Duskwood" } }, false)
    local function kills() local n, last = 0; for _, e in ipairs(real.feed) do if e.kind == "kill" then n, last = n + 1, e.text end end return n, last end
    local n0 = kills()
    enemyUnits.target = { "Latey", "Comer", false }
    ns.PvP.ReadEnemy("target")
    enemyUnits.target = nil
    ADVANCE(3)
    FIRE("PARTY_KILL", "Player-1-00000001", "Player-1-Latey")
    FIRE("CHAT_MSG_COMBAT_HONOR_GAIN", HONOR)
    local n1, line = kills()
    check(n1 == n0 and nolv(line):find("You and Buddy Pal killed Latey Comer", 1, true) ~= nil,
      "a friend's kill, then your own blow for the same death: one merged line (" .. n0 .. " -> " .. n1 .. "): " .. ns.Plain(line))
  end
  -- a friend's kill marked as their killing blow
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("KILL", { victim = "Their Blow", vclass = "MAGE", vlevel = 30, vguild = "", zone = "Duskwood", blow = "1" }, "kb1"), "WHISPER", 77)
  check(lastFeed():find("Their Blow", 1, true) and lastFeed():find(ns.L.KILLING_BLOW_TAG, 1, true), "a friend's killing blow is marked too: " .. lastFeed())
  UnitGUID = oGuid
  RUN_TICKERS(80) -- (send what these kills queued)
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
  check(#pages == 4, "four pages: Alerts (with sounds), Appearance, Friends & sharing, Advanced (" .. #pages .. ")")
  local dropdowns = 0
  for _, c in ipairs(controls) do
    if c.kind == "dropdown" then
      dropdowns = dropdowns + 1
      check(#c.opts() > 0, "dropdown " .. c.s.var .. " has choices")
    end
  end
  check(dropdowns == 18, "4 alert groups + level-ups + one for instances + 5 sounds + style + stacking + message style + chat tab + 3 forget (" .. dropdowns .. ")")
  -- the "Hitlist shared" alert is gone; one Test alerts button; Advanced is debugging only
  local tests, advItems = 0, 0
  for _, pg in ipairs(pages) do
    for _, item in ipairs(pg.layout.items) do if item.button == ns.L.BTN_TEST then tests = tests + 1 end end
  end
  check(settings.FNF_display_share == nil and settings.FNF_soundPick_share == nil and settings.FNF_where_party == nil,
    "no Hitlist shared alert, no per-place instance settings")
  check(tests == 1 and settings.FNF_minimap ~= nil and settings.FNF_instances ~= nil, "one Test alerts button; minimap and instances settings there")
  -- one dropdown per group of alerts = show + sound for every alert in it
  local saveShow, saveSound = {}, {}
  for k, v in pairs(ns.S().show) do saveShow[k] = v end
  for k, v in pairs(ns.S().sound) do saveSound[k] = v end
  local fights = settings.FNF_display_fights
  check(settings.FNF_display_kill == nil and fights and settings.FNF_display_progress and settings.FNF_display_sighting and settings.FNF_display_bounty,
    "four alert groups: fights, sightings, progress, bounty board")
  fights:SetValue("chat_sound")
  local sh, so = ns.S().show, ns.S().sound
  check(sh.attacked == "chat" and sh.engage == "chat" and sh.died == "chat" and sh.kill == "chat" and so.kill and so.attacked and not so.engage,
    "'Chat line + sound' sets the whole group (attacking someone stays quiet)")
  fights:SetValue("off")
  check(sh.kill == "off" and sh.engage == "off" and fights:GetValue() == "off", "'Off' for the whole group")
  settings.FNF_display_progress:SetValue("toast_sound")
  check(sh.level == "toast" and sh.loot == "toast" and sh.gear == "toast" and so.loot and not so.level, "progress: a plain level-up stays quiet")
  for k, v in pairs(saveShow) do ns.S().show[k] = v end
  for k, v in pairs(saveSound) do ns.S().sound[k] = v end
  settings.FNF_theme:SetValue("achievement")
  check(ns.Toast.Theme() == "achievement", "style dropdown sets the toast theme")
  settings.FNF_theme:SetValue("minimal")
  settings.FNF_style:SetValue("short")
  check(ns.S().flavor == false and settings.FNF_style:GetValue() == "short", "message style: short = flavor off")
  settings.FNF_style:SetValue("flavor")
  check(ns.S().flavor == true, "message style: with flavor")
  settings.FNF_instances:SetValue("off")
  check(ns.S().instances == "off", "one instances dropdown for dungeons, raids and battlegrounds")
  settings.FNF_instances:SetValue("hold")
  settings.FNF_track_pvp:SetValue(true)
  check(ns.S().track.pvp == true, "track PvP in battlegrounds checkbox")
  settings.FNF_track_pvp:SetValue(false)
  local played = SOUNDS_PLAYED or 0
  settings.FNF_soundPick_trouble:SetValue("raidwarning")
  check(ns.S().soundPick.trouble == "raidwarning" and (SOUNDS_PLAYED or 0) == played + 1, "picking a sound sets it and plays it")
  settings.FNF_soundPick_trouble:SetValue("default")
  check(settings.FNF_soundPick_victory ~= nil and settings.FNF_soundPick_pvp == nil, "two fight sounds: a friend in trouble, a friend's kill")
  check(settings.FNF_soundPick_kill == nil and settings.FNF_milestones == nil and settings.FNF_gearMin == nil,
    "one sound per kind of alert; no milestones switch; no gear quality choice")
  settings.FNF_mark:SetValue(false)
  check(ns.S().mark == false, "hitlist marks checkbox")
  settings.FNF_mark:SetValue(true)
  local hideWas = ns.S().hideLowAlts
  check(settings.FNF_hideLowAlts ~= nil, "Friends & sharing: a 'Hide characters below level 15' checkbox")
  settings.FNF_hideLowAlts:SetValue(false)
  check(ns.S().hideLowAlts == false, "the low alt checkbox turns the filter off")
  settings.FNF_hideLowAlts:SetValue(true)
  check(ns.S().hideLowAlts == true, "... and on")
  ns.S().hideLowAlts = hideWas
  settings.FNF_debug:SetValue(true)
  check(ns.S().debug and ns.S().debugSince, "debug checkbox goes through SetDebug")
  -- "Forget ... after": three dropdowns of days; asks first when entries would go right away
  do
    local keys = { "forgetAttackers", "forgetKilledOnce", "forgetKilledMore" }
    local want = { forgetAttackers = 14, forgetKilledOnce = 0, forgetKilledMore = 0 }
    for _, k in ipairs(keys) do
      check(settings["FNF_" .. k] ~= nil and settings["FNF_" .. k]:GetValue() == want[k], "forget dropdown " .. k .. " defaults to " .. want[k])
    end
    local ctl
    for _, c in ipairs(controls) do if c.s == settings.FNF_forgetAttackers then ctl = c end end
    local vals = {}
    for _, o in ipairs(ctl and ctl.opts() or {}) do vals[#vals + 1] = o.value end
    check(table.concat(vals, ",") == "7,14,30,90,180,365,0", "forget dropdown choices: 1w 2w 1m 3m 6m 1y forever (" .. table.concat(vals, ",") .. ")")
    real.hitlist["Dusty Attacker"] = { name = "Dusty Attacker", kills = 0, attacks = 3, victims = {}, lastSeen = time() - 20 * 86400 }
    settings.FNF_forgetAttackers:SetValue(30) -- longer: nothing goes
    check(ns.S().forgetAttackers == 30 and real.hitlist["Dusty Attacker"], "forget dropdown: a longer time is stored")
    settings.FNF_forgetAttackers:SetValue(7) -- would remove Dusty Attacker: asks; no pop-up in tests counts as No
    check(ns.S().forgetAttackers == 30 and real.hitlist["Dusty Attacker"], "forget dropdown: asks before removing, declined keeps the old setting")
    real.hitlist["Dusty Attacker"] = nil
    settings.FNF_forgetAttackers:SetValue(7)
    check(ns.S().forgetAttackers == 7, "forget dropdown: 1 week is stored as 7")
    settings.FNF_forgetKilledOnce:SetValue(365)
    settings.FNF_forgetKilledMore:SetValue(0)
    check(ns.S().forgetKilledOnce == 365 and ns.S().forgetKilledMore == 0, "forget dropdowns: killer settings are stored")
    ns.S().forgetAttackers, ns.S().forgetKilledOnce, ns.S().forgetKilledMore = 14, 0, 0
  end
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
ns.UI.Show("hitlist")
check(sortedBy(function(e) return (e.name or ""):lower() end, false), "each view keeps its own sort")
ns.UI.Show("friends")
ns.UI.Show("feed")
check(ns.errors == 0, "no errors in window sort/paging (" .. tostring(ns.lastError) .. ")")

-- you are in the Friends ranking once, as yourself (never as one of your friends)
ns.UI.Show("friends")
local meRows, meIsMe = 0, false
for _, e in ipairs(ns.UI.Rows()) do if e.name == ns.me then meRows = meRows + 1; meIsMe = e.me end end
check(meRows == 1 and meIsMe, "you show up once in the Friends ranking, as you")

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
  ns.S().instances = "off"
  local toasted2, chats2 = shownIn("party")
  local toasted2b = shownIn("raid")
  check(not toasted2 and chats2 == 0 and not toasted2b, "instances off: nothing in a dungeon or a raid")
  ns.S().instances = "show"
  local toasted3 = shownIn("party")
  check(toasted3, "instances: show")
  ns.S().instances = "hold"
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
  FriendsAndFoesDB.dataVersion = nil -- (saved data from before the upgrade steps)
FIRE("ADDON_LOADED", "FriendsAndFoes")
  check(ns.S().dnd.instance == nil and ns.S().instances == "show", "old instance switch migrated")
  ns.S().instances = "hold"
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
  local sightLine = nolv(lastFeed())
  check(sightLine:find("Seen Guy spotted by Buddy Pal", 1, true) and sightLine:find("1 kill on us", 1, true) and not sightLine:find("attacks", 1, true)
    and sightLine:find("Astranaar", 1, true), "friend's sighting: who, by whom, record, where: " .. sightLine)
  local feedN = #real.feed
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("SIGHT", { name = "Seen Guy", class = "ROGUE", level = "30", guild = "", zone = "Ashenvale" }, "sg2"), "WHISPER", 77)
  check(#real.feed == feedN, "same player again within 5 min: no second alert")
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("SIGHT", { name = "Not Mine", class = "MAGE", level = "30", guild = "", zone = "Duskwood" }, "sg3"), "WHISPER", 77)
  check(nolv(lastFeed()):find("Not Mine spotted by", 1, true) and not lastFeed():find("kills", 1, true), "someone not on your hitlist: shown without a record")
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
  -- unset: one default everywhere (5)
  ns.S().toastDuration = nil
  PRINTED = {}
  SlashCmdList.FRIENDSANDFOES("duration")
  check(PRINTED[#PRINTED] and PRINTED[#PRINTED]:find("now 5", 1, true), "/fnf duration with nothing set says now 5: " .. tostring(PRINTED[#PRINTED]))
  ns.Toast.Push({ kind = "level", category = "progress", title = "durdef", force = true })
  for _, f in ipairs(FRAMES) do if f.spec and f.spec.title == "durdef" then df = f end end
  check(df and df.duration == ns.DEFAULT_TOAST_DURATION and df.duration == 5, "an unset toast duration is the default, 5")
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
  check(weekly and weekly:find("3 kills, 2 deaths", 1, true) and weekly:find("Nemesis: Rogz Fang (2", 1, true), "weekly summary after a week: " .. tostring(weekly))
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
real.hitlist["Neg Zero"] = { name = "Neg Zero", kills = -0.0, attacks = -1, suspect = 0, revenge = 0, victims = {}, lastSeen = time() }
ns.UI.Show("hitlist")
ns.UI.SetSearch("neg zero")
local nz = ns.UI.Rows()[1]
check(nz and nz.name == "Neg Zero", "test player listed")
ns.UI.SetSearch("")
real.hitlist["Neg Zero"] = nil
-- picked sounds play instead of the default
do
  local lastId
  local origPS = PlaySound
  PlaySound = function(id) lastId = id; SOUNDS_PLAYED = (SOUNDS_PLAYED or 0) + 1 end
  ns.S().soundPick.trouble = "coin"
  ns.S().sound.died = true
  drainToasts()
  ns.Toast.Push({ kind = "died", category = "pvp", title = "snd" })
  local coinId
  for _, c in ipairs(ns.Toast.SOUND_CHOICES) do if c[1] == "coin" then coinId = c[3] end end
  check(lastId == coinId, "the trouble sound plays for a friend killed")
  ns.S().soundPick.trouble = "default"
  -- on "Default", attacked / killed / a kill each keep their own sound
  local idOf = {}
  for _, c in ipairs(ns.Toast.SOUND_CHOICES) do idOf[c[1]] = c[3] end
  check(ns.Toast.SoundFor("attacked", "pvp") == idOf.alarm and ns.Toast.SoundFor("died", "pvp") == idOf.raidwarning
    and ns.Toast.SoundFor("kill", "pvp") == idOf.levelup, "fights on Default: attacked, killed and a kill sound different")
  ns.S().soundPick.trouble = "coin"
  check(ns.Toast.SoundFor("attacked", "pvp") == idOf.coin and ns.Toast.SoundFor("died", "pvp") == idOf.coin
    and ns.Toast.SoundFor("kill", "pvp") == idOf.levelup, "a trouble sound plays for attacked and killed; a kill keeps its own")
  ns.S().soundPick.victory = "whisper"
  check(ns.Toast.SoundFor("kill", "pvp") == idOf.whisper and ns.Toast.SoundFor("attacked", "pvp") == idOf.coin, "and the kill sound is its own pick")
  ns.S().soundPick.trouble, ns.S().soundPick.victory = "default", "default"
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
  check(nolv(lastFeed()):find("(with Side Kick)", 1, true) ~= nil, "death names enemy helpers: " .. ns.Plain(lastFeed()))
  ns.S().flavor = false
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("DIE", { zone = "Duskwood", killer = "Main Killer:ROGUE:60:", conf = "c", assists = "Side Kick:MAGE:60:" }, "wd2"), "WHISPER", 77)
  check(nolv(lastFeed()) == "Buddy Pal killed by Main Killer (with Side Kick)" .. ns.Flavor.SEP .. "Duskwood", "short style too: " .. ns.Plain(lastFeed()))
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
  real.hitlist["Old Foe"] = { name = "Old Foe", kills = 9, attacks = 0, victims = {}, lastSeen = time() - 400 * day, level = 20 }
  real.hitlist["Old Noted"] = { name = "Old Noted", kills = 1, attacks = 0, victims = {}, lastSeen = time() - 400 * day, note = "keep" }
  check(not ns.Data.IsStale(real.hitlist["Fresh Foe"]) and ns.Data.IsStale(real.hitlist["Old Foe"]), "stale after 30 days unseen")
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
  -- forgetting
  ns.S().forgetKilledOnce, ns.S().forgetKilledMore = 0, 0
  check(ns.Data.ForgetOld(FriendsAndFoesDB) == 0 and real.hitlist["Old Foe"], "killers are kept forever by default")
  ns.S().forgetKilledOnce, ns.S().forgetKilledMore = 365, 365
  ns.Data.ForgetOld(FriendsAndFoesDB)
  check(real.hitlist["Old Foe"] == nil and real.hitlist["Fresh Foe"] and real.hitlist["Old Noted"] == nil, "forget: old entries removed (a note no longer keeps one), fresh ones kept")
  real.hitlist["Fresh Foe"], real.hitlist["Old Noted"] = nil, nil
  ns.S().forgetKilledOnce, ns.S().forgetKilledMore = 0, 0
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
  before = ns.Toast.shown or 0
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("GEAR", { link = "|cff0070dd|Hitem:5|h[Blue Thing]|h|r", count = "1" }, "gq1"), "WHISPER", 77)
  check((ns.Toast.shown or 0) == before, "epic only: blue gear skipped")
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("GEAR", { link = "|cffa335ee|Hitem:6|h[Epic Thing]|h|r", count = "1" }, "gq2"), "WHISPER", 77)
  check((ns.Toast.shown or 0) == before + 1, "epic only: epic gear shown")
  drainToasts()
  ns.S().show.gear = "chat"
  -- milestones always pop up (no switch any more)
  ns.S().show.level = "chat"
  CHAT = {}
  before = ns.Toast.shown or 0
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("LVL", { level = 60 }, "ms1"), "WHISPER", 77)
  check((ns.Toast.shown or 0) == before + 1, "level 60 always pops up, even with level-ups on chat")
  drainToasts()
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
  ns.S().show.gear = "toast"
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("GEAR", { link = "|cffa335ee|Hitem:7|h[Epic One]|h|r", count = "3", epics = "1" }, "rv1"), "WHISPER", 77)
  local gearToast
  for _, f in ipairs(FRAMES) do if f.spec and f.spec.kind == "gear" then gearToast = f.spec end end
  check(gearToast and not ns.Plain(gearToast.title):find("more", 1, true), "epic only: '+N more' counts epics only: " .. tostring(gearToast and ns.Plain(gearToast.title)))
  drainToasts()
  ns.S().show.gear = "chat"
  -- #2 white and grey items are recognised
  check(ns.ItemQuality("|cffffffff|Hitem:8|h[White]|h|r") == 1 and ns.ItemQuality("|cff9d9d9d|Hitem:9|h[Grey]|h|r") == 0, "white/grey quality")
  -- #3 forgetting asks first; "No" changes nothing
  real.hitlist["Ancient One"] = { name = "Ancient One", kills = 1, victims = {}, lastSeen = time() - 400 * 86400 }
  check(ns.Data.CountForget(FriendsAndFoesDB, "forgetKilledOnce", 365) >= 1, "count what forgetting would remove")
  local saidNo = false
  ns.UI.Confirm("x", function() end, function() saidNo = true end) -- no pop-up available in tests: counts as No
  check(saidNo and real.hitlist["Ancient One"], "declined: nothing removed")
  real.hitlist["Ancient One"] = nil
  -- #4 the old "mark" choice carries over to the new tooltip switch
  ns.S().mark, ns.S().markTooltip, ns.S().markSplit = false, true, nil
  FriendsAndFoesDB.dataVersion = nil -- (saved data from before the upgrade steps)
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
  ns.S().show.gear = "toast"
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("GEAR", { link = "|cffa335ee|Hitem:10|h[Epic Two]|h|r", count = "3", epics = "1" }, "cr1"), "WHISPER", 77)
  check(ns.Plain(lastFeed()):find("+2 more", 1, true) ~= nil, "Feed keeps the full gear batch: " .. ns.Plain(lastFeed()))
  drainToasts()
  ns.S().show.gear = "chat"
  -- 3) a share doesn't import entries "Forget" would remove anyway
  ns.S().forgetKilledOnce = 90
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("HIT", { share = "s9", entries = "Very Old:ROGUE:30::0:1:0:2600;Quite New:MAGE:30::0:1:0:5" }, "cr3"), "WHISPER", 77)
  check(real.hitlist["Very Old"] == nil and real.hitlist["Quite New"] ~= nil, "share: entries older than the forget period aren't imported")
  real.hitlist["Quite New"] = nil
  ns.S().forgetKilledOnce = 0
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
FriendsAndFoesDB.dataVersion = nil -- (saved data from before the upgrade steps)
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
check(#SENT == 1 and not ns.Comm.PumpRunning(), "queued message sent, pump idle again: " .. #SENT)
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
  FriendsAndFoesDB.profile.bounty = FriendsAndFoesDB.profile.bounty or { total = 0, count = 0 }
  FriendsAndFoesDB.profile.bounty.total = ns.Count(FriendsAndFoesDB.profile.bounty.total) + 1 -- (something changed)
  ns.Profile.Changed()
  RUN_TIMERS()
  RUN_TICKERS(8)
  local pro = {}
  for _, s in ipairs(SENT) do if s.payload:find("\tPRO\t", 1, true) then pro[#pro + 1] = s.payload end end
  check(#pro == 1, "one profile update (Battle.net only): " .. #pro)
  local decoded = pro[1] and ns.Comm.Decode(pro[1])
  check(decoded and decoded.f.k == "12" and decoded.f.d == "4" and decoded.f.wanted == "" and decoded.f.motto == nil,
    "profile message carries K/D; the old most-wanted field is there but empty (no free text)")
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
  check(greet == 1, "friend back online: greeted once: " .. greet)

  -- receiving a friend's profile
  local buddy = rr.players["Buddy Pal"]
  buddy.k, buddy.d, buddy.sk, buddy.sd = 1, 1, nil, nil
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("PRO", { k = 20, d = 5, wanted = "Rogz-Fang", zone = "Duskwood", status = "pvp" }, "pro1"), "WHISPER", 77)
  check(buddy.sk == 20 and buddy.sd == 5, "friend's own K/D stored")
  check(buddy.wanted == nil and buddy.zone == "Duskwood" and buddy.status == "pvp", "friend's zone and status (a most wanted from an older version is ignored)")
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
  check(#board == 3, "your alert list only picks whose alerts you get: every friend is still ranked")
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

  -- enemies are on the Hitlist (no Enemies tab); the old names open it
  ns.UI.Show("enemies")
  check(ns.UI.CurrentTab() == "hitlist", "the old Enemies tab name opens the Hitlist")
  ns.UI.Show("friends")
  local hasBuddy = false
  for _, row in ipairs(ns.UI.Rows()) do if row.name == "Buddy Pal" then hasBuddy = true end end
  check(hasBuddy, "Friends tab lists friends")
  ns.UI.Show("players")
  check(ns.UI.CurrentTab() == "hitlist", "old 'players' name opens the Hitlist")
  ns.UI.SetPlayerFilter("friends")
  ns.UI.SetPlayerFilter("enemies")

  -- the window: Leaderboard tab, profiles for you, a friend and an enemy
  ns.UI.Show("board")
  local buddyRank
  for _, r in ipairs(ns.UI.Rows()) do if r.name == "Buddy Pal" then buddyRank = r.rank end end
  check(ns.UI.CurrentTab() == "friends" and buddyRank == 1,
    "the old Leaderboard name opens Friends, ranked by kills, most first")
  check(ns.Profile.KindOf(ns.me) == "me" and ns.Profile.KindOf("Buddy Pal") == "friend" and ns.Profile.KindOf("Rogz") == "enemy"
    and ns.Profile.KindOf("Nobody Atall") == nil, "profile kinds")
  local v = ns.UI.ProfileView("Buddy Pal")
  local function lineOf(view, label)
    for _, l in ipairs(view.lines) do if l[1] == label then return ns.Plain(tostring(l[2])) end end
  end
  check(v and lineOf(v, "Kills") == "20" and lineOf(v, "Rank") == "#1 of 3" and lineOf(v, "Most wanted") == nil
    and lineOf(v, "Nemesis"):find(nem.name, 1, true) ~= nil, "friend profile: kills, rank, nemesis (no most wanted)")
  buddy.version = "0.6.3"
  check(ns.UI.ProfileView("Buddy Pal") and lineOf(ns.UI.ProfileView("Buddy Pal"), "Addon"):find("older", 1, true) ~= nil, "outdated addon hinted")
  v = ns.UI.ProfileView("Quiet Friend")
  check(v.estimated and lineOf(v, "Kills") == "12", "counted numbers are shown as plain numbers (the footnote explains)")
  v = ns.UI.ProfileView(ns.me)
  check(v and v.isMe and lineOf(v, "Kills") == "12", "your own profile")
  v = ns.UI.ProfileView("Rogz Fang")
  check(v and v.kind == "enemy" and v.onHitlist and lineOf(v, "Most wanted by") == nil and v.note == nil, "enemy profile (no most wanted by, no note)")

  ns.UI.ShowProfile("Rogz")
  check(ns.UI.ProfileName() == "Rogz Fang", "bare first name opens the full name's profile")
  local ctl = ns.UI.Frames().profile.controls
  check(not ctl.action:IsShown() and ctl.post:IsShown() and ctl.edit == nil and ns.UI.ProfileSave == nil and ns.Profile.SetWanted == nil,
    "an enemy's profile: Post bounty, no most wanted button, no note box")
  ns.UI.ProfileAction() -- (does nothing on an enemy)
  ns.UI.ShowProfile(ns.me)
  check(not ctl.action:IsShown() and not ctl.post:IsShown(), "your own profile: no action button")
  ns.UI.ShowProfile("Buddy Pal")
  ns.UI.ProfileAction()
  check(ns.Comm.IsPicked("Buddy#1234"), "friend profile button picks them")
  ns.UI.ProfileAction()
  ns.Comm.ClearPicks()
  ns.UI.ShowPlayer("Rogz Fang")
  check(ns.UI.ProfileName() == "Rogz Fang", "clicking a toast opens the profile")
  ns.UI.SelectTab("profile")

  -- slash commands
  local printed = #PRINTED
  SlashCmdList.FRIENDSANDFOES("wanted Rogz")
  check(#PRINTED > printed and PRINTED[#PRINTED]:find("/fnf", 1, true) and not PRINTED[#PRINTED]:find("wanted", 1, true),
    "/fnf wanted is gone: just the help line, which no longer lists it")
  printed = #PRINTED
  SlashCmdList.FRIENDSANDFOES("motto Hello")
  check(PRINTED[#PRINTED] and PRINTED[#PRINTED]:find("/fnf", 1, true) and #PRINTED > printed, "/fnf motto is gone: just the help line")
  SlashCmdList.FRIENDSANDFOES("profile buddy pal")
  SlashCmdList.FRIENDSANDFOES("profile")
  check(ns.UI.ProfileName() == ns.me, "/fnf profile = your own")
  SlashCmdList.FRIENDSANDFOES("board")
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
  check(carol.bt == nil, "a card from before 0.9: no bounty total (unknown, not 0)")
  -- 0.9: the card carries bounties collected too, on the end (older versions read the first five)
  SENT = {}
  from("Alice Wonder", 78, "GST", { stats = KC .. ":7:2:" .. G.B36(t + 1) .. ":Carol Far:" .. G.B36(1300) })
  drain()
  check(G.StatsOf(KC).bt == 1300, "Carol's bounties arrive on her card")
  toB = sentTo(77, "GST")
  check(#toB >= 1 and toB[1].f.stats:find(":Carol Far:" .. G.B36(1300), 1, true) ~= nil, "and are passed on with it")
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
  check(ns.UI.CurrentTab() == "profile" and ns.UI.BackLabel() == ns.L.TAB_FRIENDS, "profile from Friends: Back says Friends")
  ns.UI.Back()
  check(ns.UI.CurrentTab() == "friends" and ns.UI.BoardView() == g.id, "Back: Friends, still showing the group")
  check(ns.UI.BackLabel() == nil, "after going back there's nothing more to go back to")
  ns.UI.Back() -- does nothing
  check(ns.UI.CurrentTab() == "friends", "Back with nowhere to go does nothing")
  ns.UI.Show("hitlist")
  ns.UI.ShowPlayer("Rogz Fang") -- like clicking a toast
  ns.UI.Back()
  check(ns.UI.CurrentTab() == "hitlist", "profile from a toast: Back to the tab you had open")
  -- the Profile tab is always your own profile; someone else's opens inside the tab you're on
  ns.UI.SelectTab("feed")
  ns.UI.ShowProfile("Buddy Pal")
  check(ns.UI.HomeTab() == "feed" and ns.UI.CurrentTab() == "profile", "a friend's profile opens inside the Feed tab (Feed stays lit)")
  check(ns.UI.BackLabel() == ns.L.TAB_FEED, "with Back to the Feed")
  ns.UI.SelectTab("profile")
  check(ns.UI.ProfileName() == ns.me and ns.UI.HomeTab() == "profile", "the Profile tab: your own profile, even right after someone else's")
  check(ns.UI.BackLabel() == nil, "your profile from its tab: no Back")
  ns.UI.ShowProfile("Rogz Fang")
  check(ns.UI.HomeTab() == "profile" and ns.UI.BackLabel() == ns.me, "someone's profile from yours: Back to you")
  ns.UI.Back()
  check(ns.UI.ProfileName() == ns.me, "Back: your profile again")
  ns.UI.Show("hitlist")
  ns.UI.ShowProfile("Rogz Fang")
  ns.UI.ShowKills("Rogz Fang")
  check(ns.UI.HomeTab() == "hitlist" and ns.UI.CurrentTab() == "kills", "a kill list opens inside the tab too")
  ns.UI.Back()
  ns.UI.Back()
  check(ns.UI.CurrentTab() == "hitlist", "Back, Back: the Hitlist")
  SlashCmdList.FRIENDSANDFOES("profile")
  check(ns.UI.ProfileName() == ns.me, "/fnf profile: your own")
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
-- catch-up from friends who come online after you, a week / 250 events
do
  local errs = ns.errors
  local K, G = ns.Kills, ns.Groups
  local rr = ns.Data.RealRealm()
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
  buddy.slain, buddy.slainRep, buddy.slainRepAt, buddy.kx = nil, nil, nil, nil
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
  local unknownRow = list[#list]
  check(#list == 3 and K.Total(list) == 4 and unknownRow.unknown and unknownRow.n == 1,
    "a nameless kill is one 'name not readable' line: 2 players + 1, 4 kills")
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
  check(byName["Vex Morrow"].n == 5 and byName["Old Foe"].n == 4 and byName["Grim Shade"].n == 1 and #list == 4,
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
  check(ns.UI.CurrentTab() == "kills" and ns.UI.KillsOf() == "Buddy Pal" and #ns.UI.Rows() == 4, "the kill list view shows their victims")
  check(ns.UI.Rows()[1].name == "Vex Morrow", "most kills first")
  do
    local vrow
    for _, o in ipairs(FRAMES) do
      if o.cells and o._shown and o.entry and o.entry.name == "Vex Morrow" then vrow = o end
    end
    check(vrow and vrow.cells[1]._text and vrow.cells[1]._text:find("|Hfnfplayer:Vex Morrow|h", 1, true),
      "kill list: the victim's name is a link")
    check(vrow and vrow._scripts.OnHyperlinkClick, "kill list rows answer link clicks")
    ns.UI.SortBy(1)
    local names = {}
    for i, r in ipairs(ns.UI.Rows()) do
      if i <= 3 then names[#names + 1] = r.name:lower() end -- (the 4th is a placeholder entry)
    end
    check(#names >= 3, "kill list: names to sort")
    local sorted = true
    for i = 2, #names do if names[i - 1] > names[i] then sorted = false end end
    local sortedDesc = true
    for i = 2, #names do if names[i - 1] < names[i] then sortedDesc = false end end
    check(sorted or sortedDesc, "kill list: sorting by name uses the plain names " .. table.concat(names, ","))
    ns.UI.SortBy(4)
  end
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
  check(ns.UI.CurrentTab() == "friends" and ns.UI.BackLabel() == nil, "Back: Friends, and that's the start")
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

  -- catch-up: a friend who comes online after you is asked too; a week; 250 events
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
  check(#req == 1 and tonumber(req[1].f.window) == 3 * 86400, "away for 3 days: asks for those 3 days")
  check(ns.Comm.CATCHUP_WINDOW == 7 * 86400, "catch-up window is a week")
  local box = ns.Comm.Outbox()
  local keep = {}
  for i, e in ipairs(box) do keep[i] = e end
  for i = 1, 300 do ns.Comm.Remember("LVL", "ob" .. i, { level = i }) end
  check(#ns.Comm.Outbox() == 250, "up to 250 of your own events kept for friends: " .. #ns.Comm.Outbox())
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
  from("Buddy Pal", 77, "RLY", { origin = "Alice Wonder", oclass = "", olevel = "", okind = "LVL", oid = "x3", ago = 8 * 86400, data = "20" }, "ry5")
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

-- 0.7.2: Friends tab fixes from live screenshots
do
  local errs = ns.errors
  local rr = ns.Data.RealRealm()
  local cols = ns.UI.TabColumns("friends")
  local function cell(c, e) return ns.Plain(tostring(cols[c][3](e))) end

  -- kills/deaths: the friend's own report, or counted from their alerts when they don't report
  rr.players["Report Er"] = { name = "Report Er", friend = true, k = 4, d = 0, sk = 4, sd = 2, lastSeen = time() }
  rr.players["Esti Mate"] = { name = "Esti Mate", friend = true, k = 3, d = 1, lastSeen = time() }
  local rep, est
  for _, r in ipairs(ns.Profile.Board()) do
    if r.name == "Report Er" then rep = r elseif r.name == "Esti Mate" then est = r end
  end
  check(cols[4][1] == ns.L.COL_KILLS and cell(4, rep) == "4" and cell(5, rep) == "2", "Friends tab: their own numbers")
  check(cell(4, est) == "3" and cell(5, est) == "1", "Friends tab: counted numbers shown as plain numbers")
  check(cols[5][4](rep) == 2, "Friends tab: sorts by the numbers shown")
  rr.players["Report Er"], rr.players["Esti Mate"] = nil, nil

  -- last event: an older event caught up later doesn't replace a newer one, and the time shown
  -- is that event's own time
  local buddy = rr.players["Buddy Pal"]
  buddy.lastText, buddy.lastTextAt = nil, nil
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("LVL", { level = 16 }, "lt1"), "WHISPER", 77)
  check(buddy.lastText:find("16", 1, true) and math.abs(buddy.lastTextAt - time()) <= 2, "last event: the level-up just now")
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("LVL", { level = 9, ago = 7200 }, "lt2"), "WHISPER", 77)
  RUN_TIMERS()
  check(buddy.lastText:find("16", 1, true) ~= nil, "an older event caught up later doesn't replace it")
  buddy.lastSeen = time() -- (heard from them just now)

  check(ns.errors == errs, "no errors in Friends tab fixes (" .. tostring(ns.lastError) .. ")")
end

-- 0.7.2: group board fixes from the live screenshot
do
  local errs = ns.errors
  local G = ns.Groups
  local oldInfo = BNGetInfo
  BNGetInfo = function() return 1, "Testme#1111" end
  local g = G.Create("Sort Test")
  local me = G.MyKey()
  local rr = ns.Data.RealRealm()
  local mine = rr.players[ns.me]
  -- you: some kills; an invited friend: nothing yet
  local savedK, savedD = mine.k, mine.d
  FriendsAndFoesDB.groupStat = nil
  g.members[G.KeyOf("Invitee#42")] = { a = time(), name = "Invited Pal" }
  ns.UI.Show("board")
  ns.UI.SetBoardView(g.id)
  local function lastRow() local rows = ns.UI.Rows(); return rows[#rows] end
  ns.UI.SortBy(3) -- Kills
  check(lastRow().invited, "invited member at the bottom (sorted by kills)")
  ns.UI.SortBy(3) -- other way round
  check(lastRow().invited, "and still at the bottom sorted the other way")
  ns.UI.SortBy(2) -- Name
  check(lastRow().invited, "and when sorted by name")
  -- totals: "1 member", "1 kill"
  mine.k, mine.d = 1, 6
  for _, p in pairs(rr.players) do if p.self and p ~= mine then p.k, p.d = 0, 0 end end
  FriendsAndFoesDB.groupStat = nil
  local hint = ns.Plain(ns.UI.GroupHint(g))
  check(hint:find("1 member, 1 kill, 6 deaths", 1, true) ~= nil, "totals in the singular: " .. hint)
  mine.k = 3
  FriendsAndFoesDB.groupStat = nil
  hint = ns.Plain(ns.UI.GroupHint(g))
  check(hint:find("3 kills", 1, true) ~= nil and not hint:find("takedown", 1, true), "plural, and 'kills' like the column: " .. hint)
  mine.k, mine.d = savedK, savedD
  FriendsAndFoesDB.groupStat = nil
  G.Leave(g)
  ns.UI.SetBoardView("friends")
  BNGetInfo = oldInfo
  check(ns.errors == errs, "no errors in group board fixes (" .. tostring(ns.lastError) .. ")")
end

-- 0.7.2: friends' locations (live report: "says I saw them somewhere they weren't")
do
  local errs = ns.errors
  local rr = ns.Data.RealRealm()
  local buddy = rr.players["Buddy Pal"]
  buddy.zone, buddy.zoneAt, buddy.whereOff = nil, nil, nil

  -- an old event (caught up / passed on) counts at the time it happened, not when it arrived
  buddy.lastSeen = time() - 86400
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("LVL", { level = 30, ago = 7200 }, "pl1"), "WHISPER", 77)
  RUN_TIMERS()
  check(math.abs(buddy.lastSeen - (time() - 7200)) <= 5, "an event from 2h ago: last seen 2h ago, not 'just now'")

  -- their PvP alerts say where they were; an older one arriving later doesn't move them back
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("ATK", { enc = "pe1", zone = "Wetlands", attackers = "Some Foe:ROGUE:30:" }, "pl2"), "WHISPER", 77)
  drainToasts()
  check(buddy.zone == "Wetlands" and math.abs(buddy.zoneAt - time()) <= 2, "last place from their alert, with its time")
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("KILL", { victim = "Old Foe", vclass = "", vlevel = "", vguild = "", zone = "Ashenvale", ago = 3600 }, "pl3"), "WHISPER", 77)
  RUN_TIMERS()
  check(buddy.zone == "Wetlands", "an older event from elsewhere doesn't overwrite a newer place")

  -- online: Battle.net's live zone first (their profile message may be a step behind)
  buddy.zone = "Ashenvale"
  local origInfo = C_BattleNet.GetFriendGameAccountInfo
  C_BattleNet.GetFriendGameAccountInfo = function() return { isOnline = true, clientProgram = "WoW", characterName = "Buddy", realmName = "X", factionName = "Horde", gameAccountID = 77, areaName = "Duskwood" } end
  ns.Comm.RebuildRoster()
  check(ns.Profile.NowText(buddy):find("Duskwood", 1, true) ~= nil, "online: Battle.net's zone, not an older one")
  check(buddy.zone == "Duskwood", "and it becomes their last place")
  C_BattleNet.GetFriendGameAccountInfo = origInfo

  -- offline profile: when you last heard from them, and separately where they last were
  FRIENDS_ONLINE = 0
  ns.Comm.RebuildRoster()
  buddy.lastSeen, buddy.zone, buddy.zoneAt = time() - 60, "Wetlands", time() - 3 * 3600
  local v = ns.UI.ProfileView("Buddy Pal")
  local function lineOf(label) for _, l in ipairs(v.lines) do if l[1] == label then return ns.Plain(tostring(l[2])) end end end
  check(lineOf(ns.L.PROF_LAST_SEEN) == "1m ago" and lineOf(ns.L.PROF_LAST_PLACE):find("Wetlands  3h ago", 1, true),
    "offline: 'Last seen 1m ago' and 'Last place Wetlands, 3h ago' - each with its own time")
  check(#v.lines <= 10, "the profile still fits: " .. #v.lines .. " lines")
  FRIENDS_ONLINE = 1
  ns.Comm.RebuildRoster()

  -- "Where I am" off on their side: no place is kept or shown
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("PRO", { k = 1, d = 1, wanted = "", zone = "", status = "" }, "pl4"), "WHISPER", 77)
  check(buddy.whereOff and buddy.zone == nil, "they share no location: nothing kept")
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("ENG", { zone = "Duskwood", target = "Some Foe:ROGUE:30:" }, "pl5"), "WHISPER", 77)
  drainToasts()
  check(buddy.zone == nil, "not even from their alerts")
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("PRO", { k = 1, d = 1, wanted = "", zone = "Arathi Highlands", status = "" }, "pl6"), "WHISPER", 77)
  check(not buddy.whereOff and buddy.zone == "Arathi Highlands", "sharing again: their place is kept again")

  check(ns.errors == errs, "no errors in friend locations (" .. tostring(ns.lastError) .. ")")
end

-- 0.7.2: one click opens a profile on every tab; the Profile tab shows yours by default;
-- "alert list" and "kills" wording
do
  local errs = ns.errors
  ns.UI.Show("hitlist")
  local first = ns.UI.Rows()[1]
  ns.UI.ClickRow(1)
  check(first and ns.UI.CurrentTab() == "profile" and ns.UI.ProfileName() == first.name, "Hitlist: one click opens the profile")
  ns.UI.Back()
  check(ns.UI.CurrentTab() == "hitlist", "and Back returns to the Hitlist")
  ns.UI.Show("enemies")
  local e1 = ns.UI.Rows()[1]
  ns.UI.ClickRow(1)
  check(e1 and ns.UI.ProfileName() == e1.name, "Enemies: one click opens the profile too")
  ns.UI.Show("feed")
  ns.UI.ClickRow(1)
  check(ns.UI.CurrentTab() == "feed", "Feed lines don't open anything")

  -- the Profile tab with nobody chosen: your own profile
  ns.UI.ShowProfile(nil)
  check(ns.UI.ProfileName() == ns.me, "Profile tab with nobody chosen shows your own profile")

  -- an enemy shared to you: who shared them is on their profile
  local h = ns.Data.RealRealm().hitlist["Rogz Fang"]
  h.sharedBy = "Buddy Pal"
  local v = ns.UI.ProfileView("Rogz Fang")
  local shared
  for _, l in ipairs(v.lines) do if l[1] == ns.L.PROF_SHARED_BY then shared = ns.Plain(l[2]) end end
  check(shared == "Buddy Pal" and #v.lines <= 9, "enemy profile says who shared them, and still fits")
  local sharedRaw
  for _, l in ipairs(v.lines) do if l[1] == ns.L.PROF_SHARED_BY then sharedRaw = l[2] end end
  check(sharedRaw and sharedRaw:find("|Hfnfplayer:Buddy Pal|h", 1, true), "Shared by: the name is a link")
  h.sharedBy = nil

  -- wording: alert list, /fnf alerts, kills
  check(ns.L.BTN_PICK_ON == "Add to alert list" and ns.L.BTN_PICK_OFF == "Remove from alert list", "buttons say alert list")
  SlashCmdList.FRIENDSANDFOES("alerts buddy")
  check(ns.Comm.IsPicked("Buddy#1234"), "/fnf alerts <friend> adds them to your alert list")
  SlashCmdList.FRIENDSANDFOES("alerts all")
  check(not ns.Comm.GroupActive(), "/fnf alerts all empties it")
  SlashCmdList.FRIENDSANDFOES("group buddy")
  check(ns.Comm.IsPicked("Buddy#1234"), "the old /fnf group still works")
  ns.Comm.ClearPicks()
  local texts = table.concat({ ns.L.WEEKLY, ns.L.TIP_WEEKLY, ns.L.TIP_PICK, ns.L.ALERTLIST_ALL, ns.L.ALERTLIST_ACTIVE }, " ")
  check(not texts:lower():find("takedown", 1, true) and not texts:lower():find("pick", 1, true), "no 'takedowns' or 'pick' left in those texts")

  check(ns.errors == errs, "no errors in click / wording changes (" .. tostring(ns.lastError) .. ")")
end

-- 0.7.3: numbers are just numbers - never a symbol in front, never "-0"
do
  local errs = ns.errors
  local N = ns.UI.Num
  check(N(0) == "0" and N(-0.0) == "0" and N(-3) == "0" and N(nil) == "0" and N(0 / 0) == "0", "zero, -0, negatives and junk all show as 0")
  check(N(12) == "12" and N(12.0) == "12", "whole numbers without decimals")

  -- every cell of every list: no "~", "-", "?" or "+" in front of a number, and no "-0"
  -- (with a friend on an old version in the lists: their numbers used to get a "~")
  ns.Data.RealRealm().players["Old Version"] = { name = "Old Version", friend = true, k = 2, d = 1, lastSeen = time(), version = "0.5.4" }
  local bad = {}
  for _, key in ipairs({ "hitlist", "board", "enemies", "friends", "feed" }) do
    ns.UI.Show(key)
    for _, row in ipairs(ns.UI.Rows()) do
      for c, col in ipairs(ns.UI.TabColumns(key)) do
        if key ~= "feed" or c == 1 then
          local ok, val = pcall(col[3], row)
          local t = ok and ns.Plain(tostring(val)) or ""
          if t:match("^%s*[~%-%?%+]%s*%d") or t:find("%-0[%.%s]") or t:match("%-0$") then bad[#bad + 1] = key .. ":" .. t end
        end
      end
    end
  end
  check(#bad == 0, "no symbol in front of any number on any tab: " .. table.concat(bad, ", "))
  ns.UI.Show("board")
  local seen = false
  for _, r in ipairs(ns.UI.Rows()) do if r.name == "Old Version" and r.estimated then seen = true end end
  check(seen, "(the sweep did include a friend with counted numbers)")
  ns.Data.RealRealm().players["Old Version"] = nil

  -- K/D with no kills and some deaths: 0.00, not -0.00
  local rr = ns.Data.RealRealm()
  rr.players["Zero Kills"] = { name = "Zero Kills", friend = true, k = 0, d = 0, sk = 0, sd = 3, lastSeen = time() }
  ns.UI.Show("board")
  local row
  for _, r in ipairs(ns.UI.Rows()) do if r.name == "Zero Kills" then row = r end end
  local kdCol = ns.UI.TabColumns("friends")[6]
  check(row and ns.Plain(kdCol[3](row)) == "0.00", "0 kills, 3 deaths: K/D 0.00")
  row.kd = -0.0
  check(ns.Plain(kdCol[3](row)) == "0.00", "a negative-zero K/D still shows 0.00")
  rr.players["Zero Kills"] = nil

  -- group board: an invite or a member without numbers shows empty cells, no placeholder symbol
  local killsCol = ns.UI.TabColumns("friends")[4]
  check(ns.Plain(killsCol[3]({ invited = true, k = 0, d = 0 })) == "" and ns.Plain(killsCol[3]({ unknown = true, k = 0, d = 0 })) == "",
    "invited / not-yet-known members: empty cells")

  check(ns.errors == errs, "no errors in number display (" .. tostring(ns.lastError) .. ")")
end

-- 0.7.3: a friend fighting next to you is never named as your killer or a helper
do
  local errs = ns.errors
  local rr = ns.Data.RealRealm()
  rr.players["Side Kick"] = { name = "Side Kick", friend = true, k = 5, d = 0, a = 0, lastSeen = time() }
  local P = ns.PvP

  -- who counts as on your side
  check(P.IsFriendly(ns.me) and P.IsFriendly("Side Kick") and P.IsFriendly("Buddy Pal"), "you and your friends are on your side")
  check(not P.IsFriendly("Rogz Fang") and not P.IsFriendly("Total Stranger"), "enemies and strangers aren't")
  local oldParty = UnitInParty
  UnitInParty = function(n) return n == "Party Member" end
  check(P.IsFriendly("Party Member"), "someone in your party is on your side")
  UnitInParty = oldParty

  -- a death message naming a friend as helper (from an older client): the friend is dropped
  local nFeed = #rr.feed
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("DIE", { zone = "Duskwood", killer = "Real Foe:ROGUE:40:",
    conf = "c", assists = "Side Kick:PRIEST:40:;Other Foe:MAGE:40:" }, "sd1"), "WHISPER", 77)
  drainToasts()
  local e = rr.feed[#rr.feed]
  check(#rr.feed == nFeed + 1 and e.foes[1] == "Real Foe" and e.foes[2] == "Other Foe" and #e.foes == 2,
    "the friend isn't listed with the enemies")
  check(not ns.Plain(e.text):find("Side Kick", 1, true), "and isn't in the Feed line")
  local sk = rr.players["Side Kick"]
  check(not sk.enemy and sk.a == 0 and sk.k == 5, "the friend isn't marked as an enemy, their numbers untouched")
  check(rr.players["Other Foe"] and rr.players["Other Foe"].a == 1, "the real enemy helper still counts")

  -- a death message naming a friend (or the dying friend) as the killer: no killer, nobody on the hitlist
  nFeed = #rr.feed
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("DIE", { zone = "Duskwood", killer = "Side Kick:PRIEST:40:", conf = "c", assists = "" }, "sd2"), "WHISPER", 77)
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("DIE", { zone = "Duskwood", killer = "Buddy Pal:PRIEST:40:", conf = "c", assists = "" }, "sd3"), "WHISPER", 77)
  drainToasts()
  check(rr.hitlist["Side Kick"] == nil and rr.hitlist["Buddy Pal"] == nil and sk.k == 5, "a friend named as killer isn't put on the hitlist")
  check(#rr.feed == nFeed + 2, "the deaths are still in the Feed")

  -- old data: a friend wrongly marked as an enemy doesn't show on the Enemies tab or the Hitlist
  sk.enemy = true
  rr.hitlist["Side Kick"] = { name = "Side Kick", kills = 1, attacks = 0, suspect = 0, revenge = 0, victims = {} }
  local function listed(tab)
    ns.UI.Show(tab)
    for _, r in ipairs(ns.UI.Rows()) do if r.name == "Side Kick" then return true end end
    return false
  end
  check(not listed("enemies") and not listed("hitlist"), "a friend is never listed as an enemy")
  check(listed("friends"), "they're still on the Friends tab")

  rr.players["Side Kick"], rr.hitlist["Side Kick"] = nil, nil
  check(ns.errors == errs, "no errors in friend/foe sides (" .. tostring(ns.lastError) .. ")")
end

-- 0.7.3: your own death recap with a friend in it
do
  local errs = ns.errors
  local rr = ns.Data.RealRealm()
  rr.players["Side Kick"] = { name = "Side Kick", friend = true, k = 0, d = 0, a = 0, lastSeen = time() }
  local recapId = 1
  local events
  C_DeathRecap = {
    HasRecapEvents = function(id) return id == recapId end,
    GetRecapEvents = function() return events end,
  }
  local function die()
    local n = #rr.feed
    FIRE("PLAYER_DEAD")
    RUN_TIMERS()
    drainToasts()
    return #rr.feed > n and rr.feed[#rr.feed] or nil
  end

  -- the friend's event is the newest in the recap: the enemy is still the killer, the friend not a helper
  events = {
    { sourceName = "Real Killer", sourceGUID = "Player-1-0000AAAA", timestamp = 100 },
    { sourceName = "Enemy Helper", sourceGUID = "Player-1-0000BBBB", timestamp = 99 },
    { sourceName = "Side Kick", sourceGUID = "Player-1-0000CCCC", timestamp = 101 },
  }
  local e = die()
  check(e and e.kind == "died" and e.foes[1] == "Real Killer", "killer: the newest enemy, not the friend's later event")
  local named = {}
  for _, f in ipairs(e and e.foes or {}) do named[f] = true end
  check(named["Enemy Helper"] and not named["Side Kick"], "helpers: the enemy, never the friend")
  check(not rr.players["Side Kick"].enemy and rr.hitlist["Side Kick"] == nil, "the friend isn't marked as an enemy anywhere")

  -- only friends in the recap: no PvP death is invented
  recapId = 2
  events = { { sourceName = "Side Kick", sourceGUID = "Player-1-0000CCCC", timestamp = 200 } }
  check(die() == nil, "a recap with only a friend in it isn't a PvP death")

  C_DeathRecap = nil
  rr.players["Side Kick"] = nil
  check(ns.errors == errs, "no errors in your own death recap (" .. tostring(ns.lastError) .. ")")
end

-- 0.7.3: friends and enemies never mix - except a friend playing the other faction
do
  local errs = ns.errors
  local rr = ns.Data.RealRealm()
  local D = ns.Data
  local ours = { name = "Our Side", friend = true, faction = ns.myFaction, k = 3, d = 1, a = 0, lastSeen = time() }
  local other = { name = "Other Side", friend = true, faction = "Alliance", k = 0, d = 0, a = 0, lastSeen = time() }
  local foe = { name = "Plain Foe", enemy = true, k = 1, d = 0, a = 0, lastSeen = time() }
  rr.players["Our Side"], rr.players["Other Side"], rr.players["Plain Foe"] = ours, other, foe
  check(ns.myFaction == "Horde", "(test setup: you're Horde)")

  check(D.OnOurSide(ours) and not D.OnOurSide(other) and not D.OnOurSide(foe), "on your side: friends on your faction only")
  check(ns.PvP.IsFriendly("Our Side") and not ns.PvP.IsFriendly("Other Side"), "a friend on the other faction can fight you")

  -- a friend on your faction can't be made an enemy by any message
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("ATK", { enc = "os1", zone = "Duskwood", attackers = "Our Side:ROGUE:40:" }, "os1"), "WHISPER", 77)
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("DIE", { zone = "Duskwood", killer = "Our Side:ROGUE:40:", conf = "c", assists = "" }, "os2"), "WHISPER", 77)
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("KILL", { victim = "Our Side", vclass = "", vlevel = "", vguild = "", zone = "Duskwood" }, "os3"), "WHISPER", 77)
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("SIGHT", { name = "Our Side", class = "", level = "", guild = "", zone = "Duskwood" }, "os4"), "WHISPER", 77)
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("HIT", { share = "os5", entries = "Our Side:ROGUE:40::0:3:0:1" }, "os5"), "WHISPER", 77)
  drainToasts(); RUN_TIMERS()
  local buddy = rr.players["Buddy Pal"]
  check(not ours.enemy and ours.a == 0 and ours.k == 3 and ours.d == 1 and (ours.atk or 0) == 0,
    "attacker, killer, victim, sighting, shared hitlist: a friend on your faction is never recorded as an enemy")
  check(rr.hitlist["Our Side"] == nil, "and never put on the hitlist")
  check(not (buddy.slain and buddy.slain["Our Side"]), "and never in a kill list as a victim")

  -- a friend on the other faction CAN be an enemy
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("DIE", { zone = "Duskwood", killer = "Other Side:WARRIOR:40:", conf = "c", assists = "" }, "os6"), "WHISPER", 77)
  drainToasts()
  check(other.enemy and other.k == 1 and rr.hitlist["Other Side"] ~= nil, "a friend on the other faction who kills a friend: enemy and hitlist")
  check(ns.Profile.KindOf("Other Side") == "enemy" and ns.Profile.KindOf("Our Side") == "friend", "profiles: the other-faction friend you fought opens as an enemy")

  -- the lists
  local function listed(tab, name)
    ns.UI.Show(tab)
    for _, r in ipairs(ns.UI.Rows()) do if r.name == name then return true end end
    return false
  end
  ours.enemy = true -- (as if old data had marked them)
  check(listed("friends", "Our Side") and not listed("enemies", "Our Side") and not listed("hitlist", "Our Side"),
    "a friend on your faction: Friends tab only, never Enemies or Hitlist (even if old data marked them)")
  check(listed("enemies", "Other Side") and listed("hitlist", "Other Side") and not listed("friends", "Other Side"),
    "a friend on the other faction: Enemies and Hitlist, not the Friends tab")
  check(not listed("friends", "Plain Foe"), "an enemy is never on the Friends tab")

  rr.players["Our Side"], rr.players["Other Side"], rr.players["Plain Foe"] = nil, nil, nil
  rr.hitlist["Other Side"] = nil
  check(ns.errors == errs, "no errors in friend/enemy separation (" .. tostring(ns.lastError) .. ")")
end

-- 0.7.3: a friend Battle.net reports with no character name and game version 0 (seen live:
-- "BN-DROP other WoW version | nil | ... | 0" and "WHISPER-DROP not a (picked) friend")
do
  local errs = ns.errors
  local o = { info = C_BattleNet.GetFriendGameAccountInfo, byId = C_BattleNet.GetGameAccountInfoByID, num = BNGetNumFriends,
    acct = C_BattleNet.GetFriendAccountInfo }
  WOW_PROJECT_ID = 18
  local blank = { isOnline = true, clientProgram = "WoW", characterName = "", realmName = nil, realmID = 0,
    wowProjectID = 0, factionName = nil, gameAccountID = 91 }
  BNGetNumFriends = function() return 1, 1 end
  C_BattleNet.GetFriendGameAccountInfo = function() return blank end
  C_BattleNet.GetGameAccountInfoByID = function(id) if id == 91 then return blank end end
  C_BattleNet.GetFriendAccountInfo = function() return { battleTag = "Blank#9191" } end
  check(ns.Comm.SameWorld(blank), "game version 0 means 'not said', not 'a different game'")
  ns.Comm.RebuildRoster()
  check(ns.Comm.roster["Blank Name"] == nil, "(no name yet: not in the roster until we hear from them)")

  -- their messages are accepted, under the name in the message
  local rr = ns.Data.RealRealm()
  local p = ns.Comm.Encode({ kind = "LVL", id = "bl1", name = "Blank Name", class = "MAGE", level = 20, f = { level = 20 } })
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", p, "WHISPER", 91)
  check(rr.players["Blank Name"] and rr.players["Blank Name"].level == 20, "a friend with no name from Battle.net: their messages still arrive")
  ns.Comm.RebuildRoster()
  check(ns.Comm.roster["Blank Name"] ~= nil and ns.Comm.TagFor("Blank Name") == "Blank#9191",
    "after their first message they're in the roster (you send to them too), BattleTag known")

  -- a real other game version is still kept out
  local other = { isOnline = true, clientProgram = "WoW", characterName = "Retail Guy", wowProjectID = 1, gameAccountID = 92 }
  check(not ns.Comm.SameWorld(other), "a friend playing another WoW version is still left out")

  BNGetNumFriends, C_BattleNet.GetFriendGameAccountInfo, C_BattleNet.GetGameAccountInfoByID, C_BattleNet.GetFriendAccountInfo = o.num, o.info, o.byId, o.acct
  WOW_PROJECT_ID = nil
  rr.players["Blank Name"] = nil
  ns.Comm.RebuildRoster()
  check(ns.errors == errs, "no errors with a nameless Battle.net friend (" .. tostring(ns.lastError) .. ")")
end

-- 0.7.3: a Battle.net friend without the addon (seen online on your faction) is on your side too
do
  local errs = ns.errors
  local rr = ns.Data.RealRealm()
  local tags = FriendsAndFoesDB.friendTags
  tags["Tag Friend"] = "Tagfriend#2523"
  rr.players["Tag Friend"] = nil

  check(ns.PvP.IsFriendly("Tag Friend"), "a Battle.net friend seen on your faction counts, even without the addon")

  -- named as a helper in a death: dropped
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("DIE", { zone = "Duskwood", killer = "Real Foe:ROGUE:40:", conf = "c", assists = "Tag Friend:MAGE:40:" }, "tf1"), "WHISPER", 77)
  drainToasts()
  local e = rr.feed[#rr.feed]
  check(e.foes[1] == "Real Foe" and #e.foes == 1, "not listed as a helper")
  check(rr.players["Tag Friend"] == nil, "and no enemy record made for them")

  -- already marked as an enemy by an older version: not on the Enemies tab, profile opens as a friend
  rr.players["Tag Friend"] = { name = "Tag Friend", enemy = true, k = 0, d = 0, a = 1, lastSeen = time() }
  ns.UI.Show("enemies")
  local listed = false
  for _, r in ipairs(ns.UI.Rows()) do if r.name == "Tag Friend" then listed = true end end
  check(not listed, "a Battle.net friend wrongly marked as an enemy isn't on the Enemies tab")
  check(ns.Profile.KindOf("Tag Friend") == "friend", "their profile opens as a friend")

  -- the same friend later seen playing the other faction: can be an enemy
  rr.players["Tag Friend"].faction = "Alliance"
  check(not ns.PvP.IsFriendly("Tag Friend"), "seen on the other faction: can fight you")

  tags["Tag Friend"], rr.players["Tag Friend"] = nil, nil
  check(ns.errors == errs, "no errors with Battle.net friends without the addon (" .. tostring(ns.lastError) .. ")")
end

-- your own character on your own profile
do
  local errs = ns.errors
  ns.UI.Show("profile")
  local m = ns.UI.ProfileModel()
  check(m ~= nil, "the profile page has a model")
  local unit
  m.SetUnit = function(_, u) unit = u end
  m:Hide()
  ns.UI.ShowProfile(ns.me)
  check(m:IsShown() and unit == "player", "your own profile shows your character")
  ns.UI.ShowProfile("Buddy Pal")
  check(not m:IsShown(), "a friend's profile doesn't")
  ns.UI.ShowProfile(ns.me)
  check(m:IsShown(), "and yours again")
  ns.UI.Show("hitlist")
  m.SetUnit = nil
  check(ns.errors == errs, "no errors with the profile model (" .. tostring(ns.lastError) .. ")")
end

-- the window's look: medals, Wanted poster, ledger, count-up, window sounds
do
  local errs = ns.errors
  local Art = ns.Art
  check(strtrim(ns.Plain(Art.RankText(1))) == "1" and Art.RankText(1):find("GoldIcon", 1, true), "rank 1: gold, with a gold coin after the number")
  check(Art.RankText(3):find("CopperIcon", 1, true) and Art.RankText(4) == "4" and Art.RankText(nil) == "", "rank 3 copper, 4 and up plain")

  -- window sounds: the game's own, always on (alert sounds have their own switch)
  SOUNDKIT = { IG_CHARACTER_INFO_OPEN = 1, IG_CHARACTER_INFO_CLOSE = 2, IG_ABILITY_PAGE_TURN = 3, IG_QUEST_LIST_SELECT = 4 }
  local before = SOUNDS_PLAYED or 0
  ns.UI.Show("hitlist")
  ns.UI.SelectTab("feed")
  check((SOUNDS_PLAYED or 0) == before + 1, "turning to another tab plays a page sound")
  ns.UI.SelectTab("feed")
  check((SOUNDS_PLAYED or 0) == before + 1, "the same tab again: no sound")
  ns.S().sound.enabled = false
  ns.UI.SelectTab("hitlist")
  check((SOUNDS_PLAYED or 0) == before + 2, "alert sounds off: window sounds still play")
  ns.S().sound.enabled = true
  SOUNDKIT = nil
  ns.UI.SelectTab("hitlist")
  check((SOUNDS_PLAYED or 0) == before + 2, "a client without the sound list: silent, no error")

  -- parchment is only for Wanted posters: the lists keep their plain look
  local fr = ns.UI.Frames()
  check(fr.rows.ledger == nil, "the Hitlist has no parchment")

  -- an enemy's profile is a Wanted poster; a friend's and yours aren't
  ns.UI.Show("enemies") -- (from the Hitlist the poster waits for its button)
  ns.UI.ShowPlayer("Rogz Fang")
  local P = fr.profile
  check(ns.UI.CurrentTab() == "profile" and P.poster:IsShown(), "an enemy's profile: Wanted poster")
  check(P.wanted:GetText() == "WANTED" and P.deadOrAlive:GetText() == "DEAD OR ALIVE", "WANTED ... DEAD OR ALIVE")
  check(P.posterName:GetText() == "Rogz Fang", "their name on the poster, in plain ink")
  check(ns.Plain(P.sub:GetText() or ""):find("Level", 1, true) ~= nil, "their level, race, class and guild under their name on the profile: " .. ns.Plain(P.sub:GetText() or ""))
  check(P.labels[1]:GetText() == "Murders", "the facts beside the poster start with Murders")
  local v = ns.UI.ProfileView("Rogz Fang")
  check(not ns.Plain(v.posterSub):find("Enemy", 1, true), "no \"Enemy\" under the name: " .. v.posterSub)
  -- notoriety: 100 per murder, 25 per attack, no floor in the sum (the floors are in Open)
  check(ns.Bounty.Price(0, 0) == 0 and ns.Bounty.Price(4, 4) == 500 and ns.Bounty.Price(1, 2) == 150, "notoriety sums")
  check(P.bounty:GetText() == ns.Art.Points(v.bounty) and not P.bounty:GetText():find("|T", 1, true) and P.bountyLabel:GetText() == "Notoriety",
    "notoriety on the poster: points, no gold coin: " .. ns.Plain(P.bounty:GetText()))
  check(ns.Plain(ns.Art.Gold(12500)):match("^12,500") and ns.Plain(ns.Art.Gold(950)):match("^950") and ns.Plain(ns.Art.Gold(1000000)):match("^1,000,000"), "gold with thousands separators")
  check(P.factionIcon:IsShown(), "the faction crest in the corner")
  -- the portrait: race unknown -> their class crest fills it (no corner badge then)
  local rogz = ns.Data.FindPlayer("Rogz Fang") or ns.Data.FindHit("Rogz Fang")
  local hadClass = rogz.class
  local hadCoords = CLASS_ICON_TCOORDS
  CLASS_ICON_TCOORDS = CLASS_ICON_TCOORDS or { ROGUE = { 0.5, 0.75, 0, 0.25 } }
  rogz.class = rogz.class or "ROGUE"
  ns.UI.ShowProfile("Rogz Fang")
  check(P.portraitIcon:IsShown() and not P.badge:IsShown(), "race unknown: their class crest is the portrait")
  -- seen them: their race symbol, with the class crest on the corner, and the race in the line
  RACE_ICON_TCOORDS = { ORC_MALE = { 0.25, 0.375, 0.25, 0.5 } }
  rogz.race, rogz.raceName, rogz.sex = "Orc", "Orc", 2
  ns.UI.ShowProfile("Rogz Fang")
  check(P.portraitIcon:IsShown() and P.badge:IsShown(), "seen them: race in the portrait, class on its corner")
  check(ns.Plain(P.posterSub:GetText()):find("Orc", 1, true) ~= nil, "race in the line under the name: " .. ns.Plain(P.posterSub:GetText()))
  -- the portrait is the game's painted face for their race and sex
  local file
  P.portraitIcon.SetTexture = function(_, f) file = f; return true end
  ns.UI.ShowProfile("Rogz Fang")
  check(file == "Interface\\CharacterFrame\\TemporaryPortrait-Male-Orc", "the game's painted face for a male orc: " .. tostring(file))
  rogz.sex = 3
  ns.UI.ShowProfile("Rogz Fang")
  check(file == "Interface\\CharacterFrame\\TemporaryPortrait-Female-Orc", "and for a female one")
  rogz.sex = 2
  P.portraitIcon.SetTexture = function(_, f) file = f; return false end -- (a client without the file)
  ns.UI.ShowProfile("Rogz Fang")
  check(P.portraitIcon:IsShown() and file:find("CharacterCreate-Races", 1, true), "no face file: the race symbol instead")
  P.portraitIcon.SetTexture = nil
  check(ns.UI.IsTarget == nil and P.portraitModel == nil, "no 3D model on posters")
  rogz.race, rogz.raceName, rogz.sex, rogz.class = nil, nil, nil, hadClass
  RACE_ICON_TCOORDS = nil
  CLASS_ICON_TCOORDS = hadCoords
  -- level line: unknown level leaves out "Level ?"; a known one reads "Level 35 ..."
  local hadLevel, hadGuild = rogz.level, rogz.guild
  rogz.level = nil
  v = ns.UI.ProfileView("Rogz Fang")
  check(not v.posterSub:find("?", 1, true) and not v.posterSub:find("Level", 1, true), "unknown level: no \"Level ?\" on the poster: " .. v.posterSub)
  check(not v.sub:find("?", 1, true) and not v.sub:find("Level", 1, true), "unknown level: none in the header line either: " .. v.sub)
  rogz.level = 35
  v = ns.UI.ProfileView("Rogz Fang")
  check(ns.Plain(v.posterSub):find("^Level 35 ") ~= nil, "known level: \"Level 35 ...\": " .. v.posterSub)
  -- the render path with and without the guild and rank lines
  rogz.guild = "The Pack"
  ns.UI.ShowProfile("Rogz Fang")
  check(select(1, pcall(P.CenterPoster)) and P.posterGuild:IsShown(), "poster with a guild line renders")
  rogz.guild = nil
  ns.UI.ShowProfile("Rogz Fang")
  check(select(1, pcall(P.CenterPoster)) and not P.posterGuild:IsShown(), "poster without a guild line renders, the line takes no room")
  rogz.level, rogz.guild = hadLevel, hadGuild
  -- numbers show their real value straight away (the count-up only animates on screen)
  v = ns.UI.ProfileView("Rogz Fang")
  check(fr.profile.values[1]:GetText() == tostring(v.lines[1][2]), "the numbers are right from the start")
  ns.UI.ShowProfile(ns.me)
  check(not fr.profile.poster:IsShown(), "your own profile: no poster")
  ns.UI.Show("hitlist")
  check(ns.errors == errs, "no errors with the window's look (" .. tostring(ns.lastError) .. ")")
end

-- 0.8.1: Leaderboard ties on the sorted column stay in rank order (live: rank 8 above three rank 5s)
do
  local rr = ns.Data.RealRealm()
  local t = time()
  rr.players["Tie Zero"] = { name = "Tie Zero", friend = true, k = 0, d = 0, sk = 0, sd = 0, lastSeen = t }
  rr.players["Aa Onedeath"] = { name = "Aa Onedeath", friend = true, k = 0, d = 1, sk = 0, sd = 1, lastSeen = t }
  ns.UI.Show("board")
  ns.UI.SetBoardView("friends")
  ns.UI.SortBy(2)
  ns.UI.SortBy(4) -- Kills, most first
  local okOrder, prev = true, 0
  for _, r in ipairs(ns.UI.Rows()) do
    if r.rank then
      if r.rank < prev then okOrder = false end
      prev = r.rank
    end
  end
  check(okOrder, "sorted by kills, the ranks never go backwards")
  rr.players["Tie Zero"], rr.players["Aa Onedeath"] = nil, nil
end

-- 0.8.1: an enemy you see yourself: their race is read (for their Wanted poster)
do
  local saved = { UnitExists, UnitIsPlayer, UnitFactionGroup, UnitName, UnitClass, UnitLevel, UnitRace, UnitSex, UnitIsUnit }
  UnitExists = function(u) return u == "target" end
  UnitIsPlayer = function(u) return u == "target" end
  UnitFactionGroup = function(u) if u == "player" then return MY_FACTION end return "Alliance" end
  UnitName = function(u) if u == "player" then return ME, MY_SURNAME end if u == "target" then return "Racey", "Elf" end end
  UnitClass = function(u) if u == "player" then return "Warrior", "WARRIOR" end return "Priest", "PRIEST" end
  UnitLevel = function() return 30 end
  UnitRace = function(u) if u == "target" then return "Night Elf", "NightElf", 4 end end
  UnitSex = function(u) if u == "target" then return 3 end end
  UnitIsUnit = function() return false end
  local info = ns.PvP.ReadEnemy("target")
  check(info and info.race == "NightElf" and info.raceName == "Night Elf" and info.sex == 3, "race and sex read from a seen enemy")
  UnitSex = function() return 1 end
  info = ns.PvP.ReadEnemy("target")
  check(info and info.sex == nil, "unknown sex: left out")
  UnitExists, UnitIsPlayer, UnitFactionGroup, UnitName, UnitClass, UnitLevel, UnitRace, UnitSex, UnitIsUnit = (unpack or table.unpack)(saved, 1, 9)
end

-- notoriety: level difference tiers, by the killer's own level
do
  local B = ns.Bounty
  local rr = ns.Data.RealRealm()
  local savedBounty = FriendsAndFoesDB.profile.bounty
  local origLevel, origChat = UnitLevel, ns.Toast.Chat
  local chats = {}
  ns.Toast.Chat = function(line) chats[#chats + 1] = line end
  check(B.GreyLevel(5) == 0 and B.GreyLevel(10) == 4 and B.GreyLevel(20) == 13 and B.GreyLevel(35) == 27
    and B.GreyLevel(45) == 35 and B.GreyLevel(60) == 51, "grey levels follow the Classic rule")
  local function kill(name, vlevel, myLevel)
    -- a 500-point enemy (4 murders, 4 attacks) at the given level, killed alone by you
    rr.players[name] = { name = name, enemy = true, class = "ROGUE", k = 4, d = 0, atk = 4, level = vlevel, lastSeen = time() }
    FriendsAndFoesDB.profile.bounty = nil
    UnitLevel = function(u) if u == "player" then return myLevel end return 0 end
    chats = {}
    ADVANCE(120)
    B.OnKill(ns.me, name)
    UnitLevel = function(u) if u == "player" then return 99 end return 0 end -- (you dinged before it settled)
    B.SettleAll()
    return (B.Mine())
  end
  check(kill("Lv Grey", 49, 60) == 0 and #chats == 0, "a grey victim pays nothing and says nothing")
  check(kill("Lv Low", 28, 35) == 125, "-7 (not grey): x0.25")
  check(kill("Lv Mid", 31, 35) == 250, "-4: x0.5")
  check(kill("Lv Even", 36, 35) == 500 and #chats == 1, "+1: x1, with a chat line")
  check(kill("Lv High", 39, 35) == 625, "+4: x1.25")
  check(kill("Lv Top", 45, 35) == 750, "+10: x1.5")
  check(kill("Lv Skull", -1, 35) == 750, "a ?? victim: x1.5")
  check(kill("Lv Nil", nil, 35) == 500, "unknown victim level: x1")
  check(kill("Lv Zero", 0, 35) == 500, "level 0: x1")
  check(kill("Lv NoMe", 40, 0) == 500, "unknown killer level: x1")
  -- a shared kill: your share is halved first, then only YOUR factor applies
  rr.players["Lv Shared"] = { name = "Lv Shared", enemy = true, class = "ROGUE", k = 4, d = 0, atk = 4, level = 45, lastSeen = time() }
  FriendsAndFoesDB.profile.bounty = nil
  UnitLevel = function(u) if u == "player" then return 35 end return 0 end
  ADVANCE(120)
  B.OnKill(ns.me, "Lv Shared")
  B.OnKill("Buddy Pal", "Lv Shared")
  B.SettleAll()
  check(B.Mine() == 375, "shared kill: 250 x1.5 for you, got " .. B.Mine())
  UnitLevel, ns.Toast.Chat = origLevel, origChat
  FriendsAndFoesDB.profile.bounty = savedBounty
  for _, n in ipairs({ "Lv Grey", "Lv Low", "Lv Mid", "Lv Even", "Lv High", "Lv Top", "Lv Skull", "Lv Nil", "Lv Zero", "Lv NoMe", "Lv Shared" }) do
    rr.players[n] = nil
  end
end

-- Resurrection Sickness: no notoriety, unless the victim is a skull to you
do
  local errs = ns.errors
  local B = ns.Bounty
  local rr = ns.Data.RealRealm()
  local savedBounty = FriendsAndFoesDB.profile.bounty
  local saved = { UnitExists, UnitIsPlayer, UnitFactionGroup, UnitName, UnitClass, UnitLevel, UnitIsUnit, C_UnitAuras, ns.Toast.Chat }
  local chats = {}
  ns.Toast.Chat = function(line) chats[#chats + 1] = line end
  local targetLevel, auras
  UnitExists = function(u) return u == "target" end
  UnitIsPlayer = function(u) return u == "target" end
  UnitFactionGroup = function(u) if u == "player" then return MY_FACTION end return "Alliance" end
  UnitClass = function(u) if u == "player" then return "Warrior", "WARRIOR" end return "Rogue", "ROGUE" end
  UnitIsUnit = function() return false end
  UnitLevel = function(u) if u == "player" then return 35 end return targetLevel end
  C_UnitAuras = { GetAuraDataByIndex = function(unit, i) return auras and auras[i] end }
  -- sees the victim (with the given auras), then kills them alone; returns what you got
  local function sickKill(name, level, list)
    UnitName = function(u) if u == "player" then return ME, MY_SURNAME end if u == "target" then return name:match("^(%S+)"), name:match("^%S+ (.+)$") end end
    rr.players[name] = { name = name, enemy = true, class = "ROGUE", k = 4, d = 0, atk = 4, level = level > 0 and level or nil, lastSeen = time() }
    FriendsAndFoesDB.profile.bounty = nil
    if list == "sick" then list = { { spellId = 15007, expirationTime = GetTime() + 300 } } end
    targetLevel, auras = level, list
    ns.PvP.ReadEnemy("target")
    chats = {}
    ADVANCE(120)
    B.OnKill(ns.me, name)
    B.SettleAll()
    return (B.Mine())
  end
  local sick = "sick" -- (a fresh sickness aura, 300 s left, each time)
  check(sickKill("Sick Same", 35, sick) == 0 and #chats == 0, "a sick victim at your level: nothing, and no chat line")
  check(sickKill("Sick Skull", -1, sick) == 750, "a sick skull victim: normal, x1.5")
  check(sickKill("Sick Plus", 45, sick) == 750, "a sick victim 10 levels above you: normal, x1.5")
  local over = sickKill("Sick Over", 40, sick)
  check(over == 0, "a sick victim 5 levels above you: nothing, got " .. over .. " " .. tostring(ns.PvP.IsSick("Sick Over")))
  check(sickKill("Well Same", 35, {}) == 500, "not sick: normal")
  check(sickKill("Other Aura", 35, { { spellId = 12345, expirationTime = GetTime() + 300 } }) == 500, "another debuff isn't sickness")
  -- expired: the remembered sickness ends
  sickKill("Sick Gone", 35, sick)
  ADVANCE(2000)
  check(not ns.PvP.IsSick("Sick Gone"), "sickness expires")
  FriendsAndFoesDB.profile.bounty = nil
  B.OnKill(ns.me, "Sick Gone")
  B.SettleAll()
  check(B.Mine() > 0, "sickness over: normal notoriety (a repeat kill, so less than 500: " .. B.Mine() .. ")")
  -- no expiration given: assumed ten minutes
  sickKill("Sick NoExp", 35, { { spellId = 15007 } })
  check(ns.PvP.IsSick("Sick NoExp"), "sickness without an expiration is still known")
  -- secret or unavailable aura data: not known sick
  C_UnitAuras = { GetAuraDataByIndex = function() return { spellId = "secret", expirationTime = "secret" } end }
  check(pcall(ns.PvP.ReadEnemy, "target") and not ns.PvP.IsSick("Sick NoExp2"), "unreadable aura data: no error")
  C_UnitAuras = nil
  UnitAura = nil
  check(sickKill("Unavail", 35, nil) == 500, "no aura API: normal notoriety")
  C_UnitAuras = { GetAuraDataByIndex = function() error("boom") end }
  check(sickKill("Boom", 35, nil) == 500, "an aura read that errors: normal notoriety")
  UnitExists, UnitIsPlayer, UnitFactionGroup, UnitName, UnitClass, UnitLevel, UnitIsUnit, C_UnitAuras, ns.Toast.Chat = (unpack or table.unpack)(saved, 1, 9)
  FriendsAndFoesDB.profile.bounty = savedBounty
  for _, n in ipairs({ "Sick Same", "Sick Skull", "Sick Plus", "Sick Over", "Well Same", "Other Aura", "Sick Gone", "Sick NoExp", "Unavail", "Boom" }) do rr.players[n] = nil end
  check(ns.errors == errs, "no errors in resurrection sickness (" .. tostring(ns.lastError) .. ")")
end

-- 0.9: bounties - an enemy's open bounty, collected (and shared) by whoever kills them
do
  local errs = ns.errors
  local B = ns.Bounty
  local rr = ns.Data.RealRealm()
  local saved = FriendsAndFoesDB.profile.bounty
  FriendsAndFoesDB.profile.bounty = nil
  rr.players["Bounty Bob"] = { name = "Bounty Bob", enemy = true, class = "ROGUE", k = 4, d = 0, atk = 4, lastSeen = time() }
  check(B.Open("Bounty Bob") == 500, "open bounty: 4 murders and 4 attacks = 500, got " .. B.Open("Bounty Bob"))
  check(B.Mine() == 0, "nothing collected yet")

  -- you and a friend get the kill: you share it
  B.OnKill(ns.me, "Bounty Bob")
  B.OnKill("Buddy Pal", "Bounty Bob")
  B.OnKill(ns.me, "Bounty Bob") -- (the same kill reported twice counts once)
  B.SettleAll()
  local total, n, best = B.Mine()
  check(total == 250 and n == 1, "split two ways: 250 each, got " .. total)
  check(best and best.name == "Bounty Bob" and best.amount == 250, "your biggest bounty remembered")
  check(B.Open("Bounty Bob") == B.HITLIST_MIN, "collected: the open bounty starts again")

  -- they murder again: the bounty grows from there
  rr.players["Bounty Bob"].k = 6
  check(B.Open("Bounty Bob") == 200, "two new murders since: 200")

  -- a friend kills them without you (from their message): nothing for you, but it resets
  ADVANCE(120)
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("KILL", { victim = "Bounty Bob", vclass = "ROGUE", vlevel = "60", vguild = "", zone = "Duskwood" }, "bty1"), "WHISPER", 77)
  drainToasts()
  B.SettleAll()
  check(B.Mine() == 250 and B.Open("Bounty Bob") == B.HITLIST_MIN, "a friend collected it: yours unchanged, the poster starts again")

  -- your own kill, through the real kill handler: collected after the friends' reports had time
  rr.players["Bounty Bob"].k = 7
  ADVANCE(120)
  ns.Events.Emit("KILL", { victim = "Bounty Bob", vclass = "ROGUE", vlevel = "30", vguild = "", zone = "Duskwood" })
  RUN_TIMERS()
  check(B.Mine() == 350 and select(2, B.Mine()) == 2, "your own kill collects it (alone: all 100), got " .. B.Mine())

  -- your total goes to friends with your profile; theirs comes back the same way
  check(tostring(ns.Profile.Fields().bt) == "350", "your total is in your profile message")
  rr.players["Bounty Pal"] = { name = "Bounty Pal", friend = true, faction = MY_FACTION, class = "MAGE", k = 0, d = 0, lastSeen = time() }
  local buddy = rr.players["Bounty Pal"]
  ns.Profile.Apply(buddy, { k = "1", d = "1", wanted = "", zone = "Duskwood", status = "", t = "", bt = "1300" })
  check(buddy.sbt == 1300, "a friend's total arrives with their profile")
  ns.Profile.Apply(buddy, { k = "1", d = "1", wanted = "", zone = "Duskwood", status = "", t = "" })
  check(buddy.sbt == nil, "an older version sends none: unknown, not 0")
  ns.Profile.Apply(buddy, { k = "1", d = "1", wanted = "", zone = "Duskwood", status = "", t = "", bt = "1300" })

  -- the Leaderboard has a Bounties column; your profile and theirs show it
  local cols, bcol = ns.UI.TabColumns("board"), nil
  for i, c in ipairs(cols) do if c[1] == ns.L.COL_BOUNTY then bcol = i end end
  check(bcol ~= nil, "Leaderboard: a Bounties column")
  local mineRow, buddyRow
  for _, r in ipairs(ns.Profile.Board()) do
    if r.me then mineRow = r elseif r.name == "Bounty Pal" then buddyRow = r end
  end
  check(mineRow.bounty == 350, "Leaderboard: your row has your total")
  check(buddyRow ~= nil and buddyRow.bounty == 1300, "and a friend's row theirs")
  check(ns.Plain(cols[bcol][3]({ bounty = 1300 })):match("^1,300") ~= nil, "shown in gold: " .. ns.Plain(cols[bcol][3]({ bounty = 1300 })))
  check(cols[bcol][3]({ name = "Old Version" }) == "" and cols[bcol][3]({ bounty = 5, invited = true }) == "", "unknown or invited: empty")
  local function lineOf(v, label) for _, l in ipairs(v.lines) do if l[1] == label then return ns.Plain(tostring(l[2])) end end end
  check(lineOf(ns.UI.ProfileView(ns.me), ns.L.PROF_BOUNTIES):find("350", 1, true) ~= nil, "your profile: your bounties")
  local bv = ns.UI.ProfileView("Bounty Pal")
  check(bv and (lineOf(bv, ns.L.PROF_BOUNTIES) or ""):find("1,300", 1, true) ~= nil, "a friend's profile: theirs: " .. tostring(bv and bv.kind) .. " " .. tostring(bv and lineOf(bv, ns.L.PROF_BOUNTIES)) .. " sbt=" .. tostring(buddy.sbt))

  rr.players["Bounty Bob"] = nil
  rr.players["Bounty Pal"] = nil
  rr.hitlist["Bounty Bob"] = nil
  FriendsAndFoesDB.profile.bounty = saved
  check(ns.errors == errs, "no errors with bounties (" .. tostring(ns.lastError) .. ")")
end

-- 0.9: every message kind - registered, round-trips, and fits the 255-byte limit with worst-case
-- content (longest names, guilds, zones, item links). A message that doesn't fit is never sent,
-- so this is where a too-long new field would be caught.
do
  local errs = ns.errors
  local C = ns.Comm
  local NAME = "Abcdefghijkl Mnopqrstuvwx" -- 12 + 12 letters
  local GUILD = "Abcdefghijklmnopqrstuvwx" -- 24
  local ZONE = string.rep("Z", 48) -- the longest zone the add-on keeps
  local LINK = "|cffa335ee|Hitem:19019:2564:0:0:0:0:0:0:60:0:0:0:0|h[Thunderfury, Blessed Blade of the Windseeker]|h|r"
  local UNIT = NAME .. ":WARRIOR:60:" .. GUILD
  local worst = {
    LVL = { level = "60", ago = "86400", rl = "1" },
    LOOT = { link = LINK, source = NAME, ago = "86400", rl = "1" },
    GEAR = { link = LINK, count = "19", epics = "19", ago = "86400", rl = "1" },
    ATK = { enc = "ffffffff", zone = ZONE, attackers = UNIT .. ";" .. UNIT, ago = "86400", rl = "1" },
    DIE = { zone = ZONE, killer = UNIT, conf = "c", assists = UNIT .. ";" .. UNIT .. ";" .. UNIT, ended = "99", ago = "86400", rl = "1" },
    KILL = { victim = NAME, vclass = "WARRIOR", vlevel = "60", vguild = GUILD, zone = ZONE, streak = "99", ago = "86400", rl = "1", blow = "1", last = "120" },
    SIGHT = { name = NAME, class = "WARRIOR", level = "60", guild = GUILD, zone = ZONE },
    ENG = { zone = ZONE, target = UNIT, ago = "86400", rl = "1" },
    REQ = { window = "86400" },
    PRO = { k = "99999", d = "99999", wanted = NAME, zone = ZONE, status = "pvp", t = "1999999999", bt = "999999999", btw = "999999999", bwk = "99999", rl = "1" },
    PRL = { origin = NAME, k = "99999", d = "99999", t = "1999999999", bt = "999999999", btw = "999999999", bwk = "99999" },
    HIT = { share = "ffffffffff", entries = NAME .. ":WARRIOR:60:" .. GUILD .. ":99999:99999:99999:99999;" .. NAME .. ":WARRIOR:60:" .. GUILD .. ":99999:99999:99999:99999", auto = "1" },
    RLY = { origin = NAME, oclass = "WARRIOR", olevel = "60", okind = "KILL", oid = "ffffffffff", ago = "604800", alt = "1",
      data = table.concat({ NAME, "WARRIOR", "60", GUILD, ZONE, "99", "86400", "1", "1", "120" }, "^") },
    KLQ = { who = NAME },
    BTY = { cid = "ffffffffff", target = UNIT, amount = "999999999", state = "done", killer = NAME, age = "5184000", updage = "5184000", days = "30", blow = "pet", last = "120", poster = NAME,
      killers = table.concat({ NAME, "Bbbbbbbbbbbb Nnnnnnnnnnnn", "Cccccccccccc Oooooooooooo", "Dddddddddddd Pppppppppppp", "Eeeeeeeeeeee Qqqqqqqqqqqq" }, ","),
      note = string.rep("n", 60) }, -- (the note is trimmed first when it doesn't fit)
  }
  local tooLong, broken = {}, {}
  for kind, schema in pairs(C.SCHEMA) do
    check(C.KINDS[kind] ~= nil, kind .. ": registered in Comm.KINDS")
    local hasRl = false
    for _, f in ipairs(schema) do if f == "rl" then hasRl = true end end
    -- (PRO's rl is for PRL: its own numbers, not an event)
    check(kind == "PRO" or (C.KINDS[kind] and C.KINDS[kind].relay or false) == hasRl, kind .. ": may be passed on exactly when it carries 'rl'")
    local fields = worst[kind]
    if fields then
      local msg = { kind = kind, id = "ffffffffff", name = NAME, class = "WARRIOR", level = 60, f = fields }
      local payload = C.Fit(msg)
      if not payload then
        tooLong[#tooLong + 1] = kind .. " (" .. #C.Encode(msg) .. " bytes)"
      else
        local back = C.Decode(payload)
        if not back or back.kind ~= kind or back.name ~= NAME then broken[#broken + 1] = kind end
        -- every field survives (guild names may be dropped from unit lists to make it fit)
        for _, f in ipairs(schema) do
          if back and back.f[f] ~= tostring(fields[f]) and not (f == "attackers" or f == "killer" or f == "assists" or f == "target" or f == "killers" or f == "note") then
            broken[#broken + 1] = kind .. "." .. f
          end
        end
      end
    end
  end
  check(#tooLong == 0, "every message fits 255 bytes even at its longest: " .. table.concat(tooLong, ", "))
  check(worst.DIE.assists:find(";.*;"), "(trimming a death to fit leaves your own copy alone)")
  check(#broken == 0, "every message reads back the same: " .. table.concat(broken, ", "))
  -- a friend's version: what it can do
  check(C.VersionSupports("0.9.0", "bounties") and not C.VersionSupports("0.8.0", "bounties"), "bounties: 0.9.0 and later")
  check(C.VersionSupports("0.7.1", "groups") and not C.VersionSupports(nil, "groups"), "unknown version: assume not")
  check(ns.errors == errs, "no errors checking messages (" .. tostring(ns.lastError) .. ")")
end

-- 0.9: older friends - one chat line per session naming them; the debug report
do
  local errs = ns.errors
  ns.Events.OlderVersion("Old Timer", "0.7.2")
  ns.Events.OlderVersion("Older Still", "0.6.3")
  ns.Events.OlderVersion("Old Timer", "0.7.2")
  local said = {}
  local oldChat = ns.Toast.Chat
  ns.Toast.Chat = function(text) said[#said + 1] = ns.Plain(text) end
  RUN_TIMERS()
  check(#said == 1 and said[1]:find("Old Timer (0.7.2)", 1, true) and said[1]:find("Older Still (0.6.3)", 1, true), "one line naming both: " .. tostring(said[1]))
  ns.Events.OlderVersion("Old Timer", "0.7.2")
  RUN_TIMERS()
  check(#said == 1, "and not again for the same friend this session")
  ns.Toast.Chat = oldChat
  local text = ns.Report.Text()
  check(text:find("Friends & Foes " .. ns.VERSION, 1, true) and text:find("== errors", 1, true) and text:find("== debug log", 1, true), "the debug report has its sections")
  check(not text:find("|", 1, true), "no '|' in the report (it would turn into colour codes)")
  check(not text:find("#%d%d%d%d"), "no BattleTags in the report")
  ns.Report.Show()
  check(ns.errors == errs, "no errors with the report and version notes (" .. tostring(ns.lastError) .. ")")
end

-- 0.9: layout helpers - each item placed against the one before it
do
  local function region() local r = { points = {} }
    r.ClearAllPoints = function(self) self.points = {} end
    r.SetPoint = function(self, ...) self.points[#self.points + 1] = { ... } end
    return r end
  local parent = region()
  local col = ns.UI.Column(parent, "TOP", 0, -5)
  local a, b = col:Add(region(), 10), col:Add(region(), 4)
  check(a.points[1][1] == "TOP" and a.points[1][2] == parent and a.points[1][5] == -15, "a column's first item: on the parent, gap included")
  check(b.points[1][2] == a and b.points[1][3] == "BOTTOM" and b.points[1][5] == -4, "the next one: under the one before")
  local row = ns.UI.Row(parent, "BOTTOMRIGHT", -2, 3)
  local x, y = row:Add(region()), row:Add(region(), 6)
  check(x.points[1][1] == "BOTTOMRIGHT" and x.points[1][4] == -2, "a row's first item: in the corner")
  check(y.points[1][1] == "RIGHT" and y.points[1][2] == x and y.points[1][4] == -6, "from a right corner, the row grows leftwards")
end

-- 0.9: saved data - upgrade steps run once, in order; what grows has a limit
do
  local errs = ns.errors
  local S = ns.Saved
  check(FriendsAndFoesDB.dataVersion == #S.STEPS, "saved data is at the latest step: " .. tostring(FriendsAndFoesDB.dataVersion))
  local ran = 0
  table.insert(S.STEPS, function() ran = ran + 1 end)
  S.Upgrade(FriendsAndFoesDB)
  S.Upgrade(FriendsAndFoesDB)
  check(ran == 1 and FriendsAndFoesDB.dataVersion == #S.STEPS, "a new step runs once")
  table.remove(S.STEPS)
  FriendsAndFoesDB.dataVersion = #S.STEPS

  -- a kill list over the limit keeps the victims killed most
  local rr = ns.Data.RealRealm()
  local killer = { name = "Trim Test", friend = true, k = 0, d = 0, slain = {} }
  for i = 1, S.KILL_LIST_MAX + 20 do killer.slain["Victim " .. i] = { n = (i == 1) and 50 or 1, t = i } end
  rr.players["Trim Test"] = killer
  -- enemy records over the limit: the oldest harmless ones go, never the hitlist or killers
  local before = 0
  for _ in pairs(rr.players) do before = before + 1 end
  local extra = S.PLAYERS_MAX - before + 10
  for i = 1, extra do rr.players["Old Enemy " .. i] = { name = "Old Enemy " .. i, enemy = true, k = 0, d = 0, lastSeen = i } end
  rr.players["Old Enemy 1"].k = 2 -- killed one of you: kept
  rr.hitlist["Old Enemy 2"] = { name = "Old Enemy 2", victims = {} } -- on the hitlist: kept
  local kills, players = S.Trim()
  local n = 0
  for _ in pairs(killer.slain) do n = n + 1 end
  check(kills == 20 and n == S.KILL_LIST_MAX and killer.slain["Victim 1"], "kill list trimmed to the limit, the top victim kept")
  local total = 0
  for _ in pairs(rr.players) do total = total + 1 end
  check(players == 10 and total == S.PLAYERS_MAX, "enemy records trimmed to the limit: " .. total)
  check(rr.players["Old Enemy 1"] and rr.players["Old Enemy 2"] and not rr.players["Old Enemy 3"], "the oldest harmless ones went; killers and the hitlist stayed")
  for i = 1, extra do rr.players["Old Enemy " .. i] = nil end
  rr.hitlist["Old Enemy 2"], rr.players["Trim Test"] = nil, nil
  check(ns.errors == errs, "no errors with saved data upkeep (" .. tostring(ns.lastError) .. ")")
end

-- 0.9: the first-run tour - once per account, three pages, then gone
do
  local errs = ns.errors
  local T = ns.Tour
  FriendsAndFoesDB.toured = nil
  ns.UI.Show("hitlist")
  check(T.IsShown() and T.Page() == 1 and FriendsAndFoesDB.toured, "first time the window opens: the tour")
  T.Next(); T.Next()
  check(T.Page() == 3, "Next, Next: page 3")
  T.Next()
  check(not T.IsShown(), "Got it: gone")
  ns.UI.Show("hitlist")
  check(not T.IsShown(), "and not again")
  SlashCmdList.FRIENDSANDFOES("tour")
  check(T.IsShown() and T.Page() == 1, "/fnf tour shows it again")
  T.Next(); T.Next(); T.Next()
  check(ns.errors == errs, "no errors with the tour (" .. tostring(ns.lastError) .. ")")
end

-- 0.9.4: "What's new" popup - once per version, only the current notes, never in combat
do
  local errs = ns.errors
  local WN, db = ns.WhatsNew, FriendsAndFoesDB
  local function hideAll() if WN.Frame() then WN.Frame():Hide() end; if ns.Tour.IsShown() then ns.Tour.Next(); ns.Tour.Next(); ns.Tour.Next() end end
  hideAll()
  check(WN.Entry() ~= nil and #WN.Entry().lines >= 3, "patch notes missing for " .. ns.VERSION .. ": add them in WhatsNew.lua")
  for _, line in ipairs(WN.Entry().lines) do check(type(line) == "string" and line ~= "", "patch note text exists") end

  -- an upgrading user: saved data, seenVersion unset
  db.toured, db.seenVersion = true, nil
  ns.UI.Show("hitlist")
  check(WN.IsShown() and db.seenVersion == ns.VERSION, "upgrade: popup shown, seenVersion set")
  check(WN.Text():find(ns.VERSION, 1, true) and WN.Text():find(ns.L.NEW_101_1, 1, true), "popup has the version header and the notes")
  WN.Frame():Hide()
  ns.UI.Show("hitlist")
  check(not WN.IsShown(), "second open: not again")

  -- a fresh install: silent, the tour covers it
  db.toured, db.seenVersion = nil, nil
  ns.UI.Show("hitlist")
  check(not WN.IsShown() and db.seenVersion == ns.VERSION and ns.Tour.IsShown(), "fresh install: no notes, seenVersion set, tour shown")
  hideAll()

  -- an older seenVersion: only the current version's notes
  db.seenVersion = "0.9.2"
  ns.UI.Show("hitlist")
  check(WN.IsShown() and db.seenVersion == ns.VERSION, "older seenVersion: shown")
  local _, count = WN.Text():gsub("\n|cffffd100\226\128\162", "")
  check(not WN.Text():find("0.9.3", 1, true) and count == #WN.Entry().lines, "only the current version's notes")
  WN.Frame():Hide()

  -- in combat: waits until the next open
  local lockdown = true
  InCombatLockdown = function() return lockdown end
  db.seenVersion = "0.9.2"
  ns.UI.Show("hitlist")
  check(not WN.IsShown() and db.seenVersion == "0.9.2", "in combat: not shown, not marked seen")
  lockdown = false
  ns.UI.Show("hitlist")
  check(WN.IsShown() and db.seenVersion == ns.VERSION, "next open: shown")
  InCombatLockdown = nil
  WN.Frame():Hide()

  -- /fnf new (and its aliases) any time
  for _, cmd in ipairs({ "new", "whatsnew", "changes" }) do
    WN.Frame():Hide()
    SlashCmdList.FRIENDSANDFOES(cmd)
    check(WN.IsShown(), "/fnf " .. cmd .. " shows it")
  end
  WN.Frame():Hide()
  check(ns.errors == errs, "no errors with the popup (" .. tostring(ns.lastError) .. ")")
end

-- 0.9: hover explanations - the numbers that need it have one, on every tab and profile
do
  check(ns.UI.ColumnTip("board", ns.L.COL_KD) and ns.UI.ColumnTip("board", ns.L.COL_BOUNTY), "Leaderboard: K/D and Bounties explained")
  check(ns.UI.ColumnTip("hitlist", ns.L.COL_KILLS):find("best guesses", 1, true), "Hitlist: Kills says where the best guesses are")
  check(ns.UI.ColumnTip("hitlist", ns.L.COL_KILLS) ~= ns.UI.ColumnTip("board", ns.L.COL_KILLS), "the same header means different things on different tabs")
  check(ns.UI.ColumnTip("feed", "Time") == nil, "and nothing where there's nothing to explain")
  local missing = {}
  for _, key in ipairs({ "PROF_KILLS", "PROF_DEATHS", "PROF_KD", "PROF_RANK", "PROF_BOUNTIES", "PROF_KILLS_ON_US", "PROF_DIED_TO_US", "PROF_ATTACKS", "PROF_REVENGE" }) do
    if not ns.L.PROFILE_TIPS[ns.L[key]] then missing[#missing + 1] = key end
  end
  check(#missing == 0, "every profile number explained: " .. table.concat(missing, ", "))
end

-- layout: hidden items take no room; a row can start next to another frame
do
  local function region() local r = { points = {}, shown = true }
    r.ClearAllPoints = function(self) self.points = {} end
    r.SetPoint = function(self, ...) self.points[#self.points + 1] = { ... } end
    r.IsShown = function(self) return self.shown end
    return r end
  local bar, dropdown = region(), region()
  local row = ns.UI.Row(bar, "LEFT", 8, 0, dropdown)
  local new, invite, leave = row:Add(region()), row:Add(region()), row:Add(region(), 4)
  check(new.points[1][2] == dropdown and new.points[1][4] == 8, "the first button sits 8 right of the dropdown")
  new.shown = false
  row:Layout()
  check(invite.points[1][2] == dropdown and invite.points[1][4] == 8, "first one hidden: the next takes its place")
  check(leave.points[1][2] == invite and leave.points[1][4] == 4, "and the rest follow it")
  new.shown, invite.shown, leave.shown = true, false, false
  row:Layout()
  check(new.points[1][2] == dropdown, "back again: in its place")
  local col = ns.UI.Column(bar, "TOP", 0, 0)
  local a, b, c = col:Add(region()), col:Add(region(), 6), col:Add(region(), 3)
  b.shown = false
  col:Layout()
  check(c.points[1][2] == a, "a column closes up around a hidden line")
end

-- 0.9.1: the Wanted poster is part of the enemy's profile page (left column), not a window
do
  local errs = ns.errors
  local P = ns.UI.Frames().profile
  for _, tab in ipairs({ "hitlist", "enemies" }) do
    ns.UI.Show(tab)
    ns.UI.ShowPlayer("Rogz Fang")
    check(P.poster:IsShown(), "an enemy's profile has their poster (from the " .. tab .. ")")
  end
  check(not P.title:IsShown() and P.labels[1]:GetText() == "Murders", "their name is on the poster; their facts beside it")
  check(P.controls.posterBtn == nil and ns.UI.TogglePoster == nil, "no separate poster window, no button for one")
  ns.UI.ShowProfile(ns.me)
  check(not P.poster:IsShown(), "your own profile: no poster")
  ns.UI.Show("hitlist")
  check(ns.errors == errs, "no errors with the poster (" .. tostring(ns.lastError) .. ")")
end

-- 0.9: the group window - members, totals and the buttons that apply, beside the Leaderboard
do
  local errs = ns.errors
  local G = ns.Groups
  local oldInfo = BNGetInfo
  BNGetInfo = function() return 1, "Testme#1111" end
  local g = G.Create("Window Crew")
  local KB = G.KeyOf("Buddy#2222")
  g.members[KB] = { a = time(), name = "Buddy Pal" } -- invited, not joined
  ns.UI.Show("board")
  ns.UI.SetBoardView(g.id)
  ns.UI.ShowGroupWindow(FriendsAndFoesFrame)
  local w = ns.UI.GroupWindow()
  check(w:IsShown() and w.title:GetText() == "Window Crew", "the group window: its name on top")
  local levelSet
  w.SetFrameLevel = function(_, n) levelSet = n end
  local fakeMain = { GetFrameLevel = function() return 5 end }
  ns.UI.ShowGroupWindow(fakeMain)
  check(levelSet == 55, "the group window sits well above the main window and its buttons: " .. tostring(levelSet))
  w.SetFrameLevel = nil
  check(w.sub:GetText() == ns.L.GROUPWIN_YOU_LEAD, "you made it, so you lead it")
  check(w.leave:IsShown() and w.invite:IsShown() and not w.join:IsShown(), "a member: Invite and Leave")
  local mine = g.members[G.MyKey()]
  local joined = mine.j
  mine.j = nil -- (as if someone had invited you)
  ns.UI.RefreshGroupWindow()
  check(w.join:IsShown() and w.decline:IsShown() and not w.leave:IsShown() and not w.invite:IsShown(), "invited: Join and Decline")
  mine.j = joined
  ns.UI.RefreshGroupWindow()
  check(w.totals:GetText() ~= "" and not w.totals:GetText():find("Group button", 1, true), "the group's totals, without the board's hint")
  ns.UI.SetBoardView("friends")
  check(not w:IsShown(), "back to your friends' board: no group, no window")
  ns.UI.SetBoardView(g.id)
  ns.UI.ShowGroupWindow(FriendsAndFoesFrame)
  ns.UI.Show("hitlist")
  check(not w:IsShown(), "another tab: the window goes with the Leaderboard")
  G.Leave(g)
  BNGetInfo = oldInfo
  ns.UI.SetBoardView("friends")
  check(ns.errors == errs, "no errors with the group window (" .. tostring(ns.lastError) .. ")")
end


-- 1.0 fixes: a friend's old simulation, bounties, friends' text, your own profile
do
  local errs = ns.errors
  local rr = ns.Data.RealRealm()
  -- a friend on an older version testing with /fnf sim: their made-up events are ignored
  local buddyLevel = rr.players["Buddy Pal"].level
  local feedN = #rr.feed
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("LVL", { level = 33 }, "Sx1"), "WHISPER", 77)
  drainToasts()
  check(#rr.feed == feedN and rr.players["Buddy Pal"].level == buddyLevel and FriendsAndFoesDB.sim == nil,
    "a friend's simulated events (older versions) are ignored")


  -- text from friends: plain text, class tokens and real item links only
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("KILL", { victim = "Clean Vic", vclass = "ROGUE|T", vlevel = 30,
    vguild = "|TInterfaceIconsX:0|tGuild", zone = "Duskwood|TInterfaceIconsX:0|t" }, "cl1"), "WHISPER", 77)
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("LOOT", { link = "|cffa335ee|Hurl:evil|h[Click me]|h|r", source = "loot" }, "cl2"), "WHISPER", 77)
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("ATK", { enc = "cl3", zone = "Duskwood", attackers = "Ev|Til:ROGUE:60:" }, "cl3"), "WHISPER", 77)
  drainToasts()
  local cv = rr.players["Clean Vic"]
  check(cv and cv.class == nil and not (cv.guild or ""):find("|", 1, true) and not (cv.lastZone or ""):find("|", 1, true),
    "a friend's zone, guild and class can't carry escape codes")
  local loot
  for _, e in ipairs(rr.feed) do if e.text:find("Click me", 1, true) then loot = e.text end end
  check(loot and not loot:find("|Hurl", 1, true), "a link that isn't an item link is shown as plain text: " .. tostring(loot))
  check(rr.players["Ev|Til"] == nil and rr.hitlist["Ev|Til"] == nil, "a name with escape codes is never recorded")
  check(ns.SafeLink("|cffa335ee|Hitem:12584::::::::60:::::::|h[Grand Marshal's Longsword]|h|r") ~= nil
    and ns.SafeLink("|cffa335ee|Hitem:12584::::::::60:::::::|h[Grand Marshal's Longsword]|h|r"):find("|Hitem:", 1, true),
    "a real item link is kept")

  -- your own profile: "You", "killed you", no action button
  rr.hitlist["Nem Esis"] = { name = "Nem Esis", kills = 2, attacks = 0, suspect = 0, revenge = 0, victims = {}, kv = { [ns.me] = 2 } }
  local v = ns.UI.ProfileView(ns.me)
  local nemText
  for _, l in ipairs(v.lines) do if l[1] == ns.L.PROF_NEMESIS then nemText = tostring(l[2]) end end
  check(v.sub:sub(1, #ns.L.PROF_ME) == ns.L.PROF_ME and nemText and nemText:find("killed you", 1, true),
    "your profile says You, and your nemesis 'killed you': " .. tostring(nemText))
  check(nemText and nemText:find("|Hfnfplayer:Nem Esis|h", 1, true), "Nemesis: the name is a link: " .. tostring(nemText))
  rr.hitlist["Nem Esis"] = nil
  ns.UI.Show("profile")
  local action = ns.UI.Frames().profile.controls.action
  check(not action:IsShown(), "your own profile: no action button")
  check(ns.errors == errs, "no errors in the 1.0 fixes (" .. tostring(ns.lastError) .. ")")
end

-- 1.0: no number is ever shown with a minus in front, even from broken or odd saved data
do
  local errs = ns.errors
  local rr = ns.Data.RealRealm()
  local future = time() + 900
  rr.players["Neg Friend"] = { name = "Neg Friend", friend = true, class = "MAGE", level = -5, k = -3, d = -0.0, a = -4,
    sk = -2, sd = -1, sbt = -250, kx = -1, lastSeen = future, version = ns.VERSION,
    slain = { ["Neg Vic"] = { n = -2, t = future } }, slainRep = { ["Neg Vic"] = { n = -6, t = future } } }
  rr.players["Neg Foe"] = { name = "Neg Foe", enemy = true, class = "ROGUE", level = -1, k = -1, d = -2, a = -1, lastSeen = future }
  rr.hitlist["Neg Foe"] = { name = "Neg Foe", class = "ROGUE", level = -1, kills = -2, attacks = -5, suspect = -1,
    revenge = -1, victims = { ["Neg Friend"] = true }, kv = { ["Neg Friend"] = -3 }, lastSeen = future, bk0 = 99, ba0 = 99 }
  local bounty = FriendsAndFoesDB.profile.bounty
  FriendsAndFoesDB.profile.bounty = { total = -100, count = -2, best = -50 }
  SHOWN = {}
  for _, key in ipairs({ "hitlist", "contracts", "board", "friends", "feed", "profile" }) do ns.UI.Show(key) end
  for _, who in ipairs({ "Neg Friend", "Neg Foe", ns.me }) do
    ns.UI.ShowPlayer(who)
    ns.UI.ShowKills(who)
  end
  ns.UI.HitTooltip(UIParent, rr.hitlist["Neg Foe"])
  ns.Minimap.ShowTooltip(UIParent)
  for _ = 1, 10 do RUN_TICKERS(1) end
  -- a friend sending odd numbers: toasts, chat lines and the Feed
  CHAT = {}
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("LVL", { level = -5 }, "ng1"), "WHISPER", 77)
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("KILL", { victim = "Neg Foe", vclass = "ROGUE", vlevel = -1, vguild = "", zone = "Duskwood", streak = -3 }, "ng2"), "WHISPER", 77)
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("DIE", { zone = "Duskwood", killer = "Neg Foe:ROGUE:-1:", conf = "c", assists = "", ended = -7 }, "ng3"), "WHISPER", 77)
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("GEAR", { link = "[Odd Boots]", count = -4, epics = -1 }, "ng4"), "WHISPER", 77)
  drainToasts()
  ns.UI.Show("feed")
  for _, l in ipairs(CHAT) do SHOWN[#SHOWN + 1] = l end
  local lvl0 = false
  for _, e in ipairs(ns.Data.RealRealm().feed) do if e.text:find("reached level 0", 1, true) then lvl0 = true end end
  check(not lvl0, "a level-up with a broken level is dropped, not shown as level 0")
  local bad, n = {}, 0
  for _, s in ipairs(SHOWN) do
    if type(s) == "string" then
      n = n + 1
      local p = " " .. ns.Plain(s)
      if p:find("[^%w]%-[%s,%.]*%d") then bad[#bad + 1] = p end
    end
  end
  SHOWN = nil
  -- no symbols stuck to numbers either: "2*" and "24+" are plain, the tooltip explains
  local stuck = {}
  for _, key in ipairs({ "hitlist", "board", "friends" }) do
    ns.UI.Show(key)
    for _, row in ipairs(ns.UI.Rows()) do
      for _, col in ipairs(ns.UI.TabColumns(key)) do
        local ok, val = pcall(col[3], row)
        local s = ok and ns.Plain(tostring(val)) or ""
        if s:find("%d[%*%+~]") or s:find("[%*%+~]%d") then stuck[#stuck + 1] = key .. ":" .. s end
      end
    end
  end
  check(#stuck == 0, "no * + or ~ next to a number in any list: " .. table.concat(stuck, ", "))
  SHOWN = {}
  rr.hitlist["Neg Foe"].kills, rr.hitlist["Neg Foe"].suspect = 3, 2
  rr.players["Neg Foe"].level, rr.players["Neg Foe"].lastSeen = 24, time() - 400 * 86400
  ns.UI.HitTooltip(UIParent, rr.hitlist["Neg Foe"])
  local tip = table.concat(SHOWN, " / ")
  check(tip:find("2 of them likely", 1, true) and tip:find("probably higher now", 1, true),
    "the hitlist tooltip says how many kills were likely, and that an old level is probably higher: " .. tip)
  check(n > 50 and #bad == 0, "no minus in front of any number (" .. n .. " texts): " .. table.concat(bad, " || "))
  FriendsAndFoesDB.profile.bounty = bounty
  rr.players["Neg Friend"], rr.players["Neg Foe"], rr.hitlist["Neg Foe"] = nil, nil, nil
  ns.UI.Show("hitlist")
  check(ns.errors == errs, "no errors showing odd numbers (" .. tostring(ns.lastError) .. ")")
end

-- the Bounty board: contracts are promises in gold, silver and copper, paid by trade
do
  local errs = ns.errors
  local C = ns.Contracts
  local rr = ns.Data.RealRealm()
  local saved = FriendsAndFoesDB.contracts
  FriendsAndFoesDB.contracts = {}
  local showWas = ns.S().show.contract
  check(showWas == "toast" and ns.S().sound.contract == true, "Bounty board alerts: toasts with sound by default")
  ns.S().show.contract = "chat" -- (so the tests can read them)
  -- days: the poster picks how long it stays open
  local a1, d1 = C.ParseOffer("10g 50s 3d")
  local a2, d2 = C.ParseOffer("10g for 3 days")
  local a3, d3 = C.ParseOffer("10g")
  local a4, d4 = C.ParseOffer("5s 1 day")
  check(a1 == 100000 + 5000 and d1 == 3 and a2 == 100000 and d2 == 3 and a3 == 100000 and d3 == 7 and a4 == 500 and d4 == 1,
    "amount and days: 10g 50s 3d, 10g for 3 days, 10g (7 days), 5s 1 day")
  check(select(2, C.ParseOffer("10g 31d")) == "CONTRACT_BAD_DAYS" and select(2, C.ParseOffer("10g 0d")) == "CONTRACT_BAD_DAYS"
    and select(2, C.ParseOffer("3d")) == "CONTRACT_BAD_AMOUNT", "1 to 30 days, and an amount is needed")
  -- money
  check(C.ParseMoney("10g 50s 3c") == 105003 and C.ParseMoney("10") == 100000 and C.ParseMoney("50s") == 5000
    and C.ParseMoney("1.5g") == 15000 and C.ParseMoney("10 g") == 100000 and C.ParseMoney("2G 5S") == 20500,
    "amounts: 10g 50s 3c, 10 (gold), 50s, 1.5g, 10 g, 2G 5S")
  check(C.ParseMoney("abc") == nil and C.ParseMoney("0") == nil and C.ParseMoney("-5g") == nil and C.ParseMoney("") == nil
    and C.ParseMoney("10x") == nil, "not amounts: abc, 0, -5g, empty, 10x")
  local mt = ns.Plain(C.MoneyText(105003))
  check(mt:find("10 ", 1, true) and mt:find("50 ", 1, true) and mt:find("3", 1, true) and ns.Plain(C.MoneyText(100000)) == "10 ",
    "money shows as 10 gold 50 silver 3 copper, and 10 gold alone: " .. mt)

  -- posting: an enemy only, on your hitlist, sent to every friend with the add-on
  SENT = {}
  local c, why = C.Post({ name = "Bad Guy", class = "ROGUE", level = 60 }, 100000, 3)
  RUN_TICKERS(40) -- (sent at the normal pace, behind anything already queued)
  local sent = false
  for _, s in ipairs(SENT) do if s.payload:find("^3\tBTY\t") and s.payload:find("Bad Guy", 1, true) then sent = true end end
  check(c and c.state == "open" and c.days == 3 and rr.hitlist["Bad Guy"] ~= nil and sent, "a bounty: open, target on your hitlist, sent to friends (" .. tostring(why) .. ")")
  check(select(2, C.Post({ name = "Buddy Pal" }, 100)) == "CONTRACT_NOT_ENEMY" and select(2, C.Post({ name = ns.me }, 100)) == "CONTRACT_NOT_ENEMY",
    "no bounties on friends or yourself")
  check(select(2, C.Post({ name = "Bad Guy" }, 0)) == "CONTRACT_BAD_AMOUNT" and select(2, C.Post({ name = "Bad Guy" }, C.AMOUNT_MAX + 1)) == "CONTRACT_BAD_AMOUNT",
    "no bounty of nothing or over 10,000 gold")
  local again = C.Post({ name = "Bad Guy" }, 50000)
  check(again == c and c.amount == 50000 and C.MineOpen() == 1, "posting again on the same enemy changes the amount")
  for i = 1, 4 do C.Post({ name = "Extra" .. i .. " Foe" }, 100) end
  check(select(2, C.Post({ name = "Extra5 Foe" }, 100)) == "CONTRACT_TOO_MANY", "at most 5 open bounties")

  -- a friend gets the kill: done, and you are told to pay
  CHAT = {}
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("KILL", { victim = "Bad Guy", vclass = "ROGUE", vlevel = 60, vguild = "", zone = "Duskwood" }, "ct1"), "WHISPER", 77)
  drainToasts()
  local told = false
  for _, l in ipairs(CHAT) do if l:find("fulfilled your bounty", 1, true) then told = true end end
  check(c.state == "done" and c.killer == "Buddy Pal" and told, "a friend kills the target: done, and you are told to pay them")
  local k = ns.me .. "/" .. c.id
  check(C.Cancel(k) == false and C.MarkPaid(k) and c.state == "paid", "a done bounty can't be cancelled; you mark it paid")

  -- a friend's bounty reaches you
  CHAT = {}
  local function bty(fields, id) FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("BTY", fields, id), "WHISPER", 77) end
  bty({ cid = "abc1", target = "Their Mark:MAGE:50:", amount = 5000, state = "open", killer = "", age = 60, updage = 60, days = 2 }, "bt1")
  local theirs = FriendsAndFoesDB.contracts["Buddy Pal/abc1"]
  check(theirs and theirs.days == 2 and C.TimeLeft(theirs) == "1d", "a friend's bounty keeps the days they picked: " .. tostring(theirs and C.TimeLeft(theirs)))
  local postedLine = false
  for _, l in ipairs(CHAT) do if l:find("put a bounty of", 1, true) then postedLine = true end end
  check(theirs and theirs.by == "Buddy Pal" and theirs.amount == 5000 and rr.hitlist["Their Mark"] and rr.hitlist["Their Mark"].sharedBy == "Buddy Pal" and postedLine,
    "a friend's bounty: on your board and hitlist (shared by them), one chat line")
  bty({ cid = "abc2", target = "Buddy Pal:PRIEST:31:", amount = 5000, state = "open", killer = "", age = 1, updage = 1 }, "bt2")
  bty({ cid = "abc3", target = "Odd One:MAGE:50:", amount = -5, state = "open", killer = "", age = 1, updage = 1 }, "bt3")
  bty({ cid = "abc4", target = "Odd Two:MAGE:50:", amount = 500, state = "weird", killer = "", age = 1, updage = 1 }, "bt4")
  bty({ cid = "abc5", target = "Sim Mark:MAGE:50:", amount = 500, state = "open", killer = "", age = 1, updage = 1 }, "Sbt5")
  check(not FriendsAndFoesDB.contracts["Buddy Pal/abc2"] and not FriendsAndFoesDB.contracts["Buddy Pal/abc3"]
    and not FriendsAndFoesDB.contracts["Buddy Pal/abc4"] and not FriendsAndFoesDB.contracts["Buddy Pal/abc5"],
    "ignored: a bounty on one of us, a negative amount, an unknown state, a simulated one")

  -- you get the kill on their target: done, you're told you'll be paid
  CHAT = {}
  ns.Events.Emit("KILL", { victim = "Their Mark", vclass = "MAGE", vlevel = 50, vguild = "", zone = "Duskwood" })
  local youDid = false
  for _, l in ipairs(CHAT) do if l:find("You fulfilled", 1, true) then youDid = true end end
  check(theirs.state == "done" and theirs.killer == ns.me and youDid, "your kill on a friend's target: done, they pay you")
  -- an older "open" from them doesn't undo it; their "paid" does go through
  bty({ cid = "abc1", target = "Their Mark:MAGE:50:", amount = 5000, state = "open", killer = "", age = 60, updage = 50 }, "bt6")
  check(theirs.state == "done", "an older message doesn't reopen a done bounty")
  CHAT = {}
  bty({ cid = "abc1", target = "Their Mark:MAGE:50:", amount = 5000, state = "paid", killer = ns.me, age = 60, updage = 0 }, "bt7")
  local paidLine = false
  for _, l in ipairs(CHAT) do if l:find("as paid", 1, true) then paidLine = true end end
  check(theirs.state == "paid" and paidLine, "they mark it paid: you're told")

  -- cancelled ones leave the board; the board tab and profiles show the rest
  C.Cancel(ns.me .. "/" .. C.On("Extra1 Foe")[1].id)
  local listed = {}
  for _, r in ipairs(C.List()) do listed[r.name] = r.state end
  check(listed["Extra1 Foe"] == nil and listed["Extra2 Foe"] == "open" and listed["Bad Guy"] == "paid", "cancelled bounties leave the board")
  -- finished ones stay, with who closed them (even long after)
  c.doneAt, c.upd = time() - 60 * 86400, time() - 60 * 86400
  C.Tidy()
  local closed
  for _, r in ipairs(C.List()) do if r.name == "Bad Guy" then closed = r end end
  local closedCell
  for _, col in ipairs(ns.UI.TabColumns("contracts")) do
    if col[1] == ns.L.COL_CLOSED_BY then closedCell = ns.Plain(col[3](closed)) end
  end
  check(closed and closedCell == "Buddy Pal", "a finished bounty stays on the board, closed by who got the kill: " .. tostring(closedCell))
  ns.UI.Show("contracts")
  check(ns.UI.CurrentTab() == "contracts" and #ns.UI.Rows() >= 4 and ns.UI.Rows()[1].state == "open", "Bounty board tab: open bounties first")
  local view = ns.UI.ProfileView("Extra2 Foe")
  local line
  for _, l in ipairs(view.lines) do if l[1] == ns.L.PROF_CONTRACTS then line = ns.Plain(tostring(l[2])) end end
  check(line and line:find("from You", 1, true), "an enemy's profile lists the bounties on them: " .. tostring(line))
  -- old ones run out
  C.On("Extra2 Foe")[1].t = time() - 8 * 86400
  C.Tidy()
  check(#C.On("Extra2 Foe") == 0, "an open bounty runs out after 7 days")

  -- toasts (the default): a friend's bounty going up, and one being done
  ns.S().show.contract = "toast"
  local pushed = {}
  local push = ns.Toast.Push
  ns.Toast.Push = function(spec) pushed[#pushed + 1] = spec end
  bty({ cid = "abc8", target = "Toast Mark:MAGE:50:", amount = 700, state = "open", killer = "", age = 1, updage = 1, days = 4 }, "bt8")
  ns.Events.Emit("KILL", { victim = "Toast Mark", vclass = "MAGE", vlevel = 50, vguild = "", zone = "Duskwood" })
  ns.Toast.Push = push
  local up, done
  for _, sp in ipairs(pushed) do
    if sp.kind == "contract" and sp.header == ns.L.HEADER_CONTRACT_POSTED then up = sp end
    if sp.kind == "contract" and sp.header == ns.L.HEADER_CONTRACT_DONE then done = sp end
  end
  check(up and up.category == "bounty" and up.player == "Toast Mark" and ns.Plain(up.text):find("4 days", 1, true),
    "a toast when a friend posts a bounty, with how long it's open")
  check(done and done.player == "Toast Mark" and ns.Plain(done.title):find("You fulfilled", 1, true) and ns.Plain(done.text):find("they pay you", 1, true),
    "a toast when you fulfil a friend's bounty: they pay you")
  rr.hitlist["Toast Mark"], rr.players["Toast Mark"] = nil, nil
  ns.S().show.contract = showWas

  for _, name in ipairs({ "Bad Guy", "Their Mark", "Extra1 Foe", "Extra2 Foe", "Extra3 Foe", "Extra4 Foe" }) do
    rr.hitlist[name], rr.players[name] = nil, nil
  end
  FriendsAndFoesDB.contracts = saved
  ns.UI.Show("hitlist")
  check(ns.errors == errs, "no errors on the Bounty board (" .. tostring(ns.lastError) .. ")")
end

-- the minimap button: shown by default; one hidden automatically before (0.6-0.9) comes back
do
  local mm = { hide = true, compartmentDefaulted = true, angle = 210 }
  ns.Saved.STEPS[8]({ settings = { minimap = mm } })
  check(mm.hide == false and mm.compartmentDefaulted == nil, "a minimap button hidden automatically before is shown again")
  check(ns.S().minimap.hide == false, "the minimap button is on by default")
end

-- the Bounty board: edge cases
do
  local errs = ns.errors
  local C = ns.Contracts
  local rr = ns.Data.RealRealm()
  local saved = FriendsAndFoesDB.contracts
  FriendsAndFoesDB.contracts = {}
  local showWas = ns.S().show.contract
  ns.S().show.contract = "chat"
  local function bty(fields, id) FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("BTY", fields, id), "WHISPER", 77) end
  local function chatHas(text)
    for _, l in ipairs(CHAT) do if l:find(text, 1, true) then return true end end
    return false
  end

  -- junk amounts and days
  check(C.ParseMoney("inf") == nil and C.ParseMoney("nan") == nil and select(2, C.Post({ name = "Edge Foe" }, 0 / 0)) == "CONTRACT_BAD_AMOUNT"
    and select(2, C.Post({ name = "Edge Foe" }, 100, 0 / 0)) == "CONTRACT_BAD_DAYS", "no inf or nan amounts or days")
  check(C.DaysOf({ days = 0 / 0 }) == 7 and C.DaysOf({ days = 99 }) == 7 and C.DaysOf({ days = 3 }) == 3, "odd saved days count as 7")

  -- a kill caught up on at login that happened before the bounty was posted doesn't count
  local c = C.Post({ name = "Edge Foe", class = "ROGUE" }, 500, 3)
  ns.eventTime = c.t - 3600
  check(C.OnKill("Buddy Pal", "Edge Foe") == 0 and c.state == "open", "a kill from before the bounty doesn't fulfil it")
  -- one from while it was open does, even if it has run out since
  c.t = time() - 4 * 86400
  C.Tidy()
  check(c.state == "expired", "(ran out)")
  ns.eventTime = c.t + 86400
  check(C.OnKill("Buddy Pal", "Edge Foe") == 1 and c.state == "done" and c.doneAt == ns.eventTime,
    "a kill caught up on later, from while it was open, fulfils it at the time it happened")
  ns.eventTime = nil

  -- posting again starts the days again from now
  local c2 = C.Post({ name = "Edge Two" }, 500, 2)
  c2.t = time() - 86400 * 1.9
  C.Post({ name = "Edge Two" }, 900, 3)
  check(c2.amount == 900 and c2.days == 3 and C.TimeLeft(c2) == "3d",
    "posting again: the new amount, open for the new days from now: " .. C.TimeLeft(c2))
  check(time() - c2.t < 5, "posting again counts from now")

  -- a bounty on a bare first name matches the full name of who died, and takes it
  local c3 = C.Post({ name = "Firstonly" }, 500, 3)
  check(c3 and C.OnKill("Buddy Pal", "Firstonly Fullname") == 1 and c3.target == "Firstonly Fullname" and c3.state == "done",
    "a bounty on a first name is fulfilled by a kill of that first name's full name")

  -- a friend's bounty: the poster's word on who got it wins; a cancel never undoes a kill
  bty({ cid = "e1", target = "Edge Three:MAGE:50:", amount = 700, state = "open", killer = "", age = 60, updage = 60, days = 5 }, "edg1")
  local theirs = FriendsAndFoesDB.contracts["Buddy Pal/e1"]
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("KILL", { victim = "Edge Three", vclass = "MAGE", vlevel = 50, vguild = "", zone = "Duskwood" }, "edg2"), "WHISPER", 77)
  check(theirs.state == "paid" and theirs.killer == "Buddy Pal", "(the poster got them: closed, nothing to pay)")
  bty({ cid = "e2", target = "Edge Four:MAGE:50:", amount = 700, state = "open", killer = "", age = 60, updage = 60, days = 5 }, "edg3")
  local four = FriendsAndFoesDB.contracts["Buddy Pal/e2"]
  ns.Events.Emit("KILL", { victim = "Edge Four", vclass = "MAGE", vlevel = 50, vguild = "", zone = "Duskwood" })
  check(four.state == "done" and four.killer == ns.me, "(you got them)")
  bty({ cid = "e2", target = "Edge Four:MAGE:50:", amount = 700, state = "cancelled", killer = "", age = 60, updage = 0, days = 5 }, "edg4")
  check(four.state == "done", "a cancel from the poster (who hadn't heard of the kill) doesn't undo it")
  bty({ cid = "e2", target = "Edge Four:MAGE:50:", amount = 700, state = "done", killer = "Alice Wonder", age = 60, updage = 0, days = 5 }, "edg5")
  check(four.killer == "Alice Wonder", "two of you got honor for the same death: the poster's word on who closed it wins")

  -- a friend coming online sends all their bounties again: no toasts for old news
  ns.S().show.contract = "toast"
  local pushed = 0
  local push = ns.Toast.Push
  ns.Toast.Push = function(spec) if spec.kind == "contract" then pushed = pushed + 1 end end
  bty({ cid = "e3", target = "Edge Five:MAGE:50:", amount = 700, state = "open", killer = "", age = 3 * 86400, updage = 3 * 86400, days = 5 }, "edg6")
  ns.Toast.Push = push
  check(pushed == 0 and FriendsAndFoesDB.contracts["Buddy Pal/e3"] ~= nil, "an old bounty from a friend who just came online: on the board, no toast")
  ns.S().show.contract = "chat"

  -- a friend who ran out here, then the poster posts it again: open again
  bty({ cid = "e4", target = "Edge Six:MAGE:50:", amount = 700, state = "open", killer = "", age = 3 * 86400, updage = 3 * 86400, days = 2 }, "edg7")
  local six = FriendsAndFoesDB.contracts["Buddy Pal/e4"]
  C.Tidy()
  check(six.state == "expired", "(ran out here)")
  bty({ cid = "e4", target = "Edge Six:MAGE:50:", amount = 900, state = "open", killer = "", age = 0, updage = 0, days = 2 }, "edg8")
  check(six.state == "open" and six.amount == 900, "posted again by the poster: open again here too")

  -- greeting a friend: open, unpaid and recently finished ones only
  local old = C.Post({ name = "Edge Seven" }, 100, 1)
  old.state, old.killer, old.upd = "paid", "Buddy Pal", time() - 30 * 86400
  RUN_TICKERS(80) -- (what was sent when it was posted)
  SENT = {}
  ns.Contracts.Greet({ "Buddy Pal" })
  RUN_TICKERS(80)
  local sentOld, sentOpen = false, false
  for _, s in ipairs(SENT) do
    if s.payload:find("Edge Seven", 1, true) then sentOld = true end
    if s.payload:find("Edge Two", 1, true) then sentOpen = true end
  end
  check(sentOpen and not sentOld, "a friend coming online gets your open bounties, not long-finished ones")

  for _, name in ipairs({ "Edge Foe", "Edge Two", "Firstonly", "Firstonly Fullname", "Edge Three", "Edge Four", "Edge Five", "Edge Six", "Edge Seven" }) do
    rr.hitlist[name], rr.players[name] = nil, nil
  end
  FriendsAndFoesDB.contracts = saved
  ns.S().show.contract = showWas
  check(ns.errors == errs, "no errors in the Bounty board edge cases (" .. tostring(ns.lastError) .. ")")
end

-- 0.9.4: most wanted and notes are gone; their saved values are cleared once
do
  local db = { profile = { wanted = "Rogz Fang" }, realms = { Forever = {
    players = { ["Buddy Pal"] = { wanted = "Rogz Fang" }, ["Rogz Fang"] = { bwPaid = { x = true } } },
    hitlist = { ["Rogz Fang"] = { note = "camps the flight path" } } } } }
  ns.Saved.STEPS[9](db)
  local r = db.realms.Forever
  check(db.profile.wanted == nil and r.players["Buddy Pal"].wanted == nil and r.players["Rogz Fang"].bwPaid == nil
    and r.hitlist["Rogz Fang"].note == nil, "upgrade: saved most wanted and notes cleared")
  local s1 = { settings = { where = { party = "chat", raid = "off", pvp = "show" } }, sim = { feed = {} } }
  ns.Saved.STEPS[10](s1)
  local s2 = { settings = { where = { party = "off", raid = "hold", pvp = "hold" } } }
  ns.Saved.STEPS[10](s2)
  check(s1.settings.instances == "hold" and s1.settings.where == nil and s1.sim == nil and s2.settings.instances == "off",
    "upgrade: one instances setting (the dungeon choice; chat line only -> wait), the simulation store removed")
end

-- 0.9.4: one sound per kind of alert; milestones and gear quality are fixed
do
  local db = { settings = { soundPick = { attacked = "alarm", died = "whisper", sighting = "mapping", loot = "coin", contract = "default" },
    milestones = false, gearMin = 3 } }
  ns.Saved.STEPS[11](db)
  local sp = db.settings.soundPick
  check(sp.trouble == "whisper" and sp.victory == "default" and sp.pvp == nil and sp.sighting == "mapping" and sp.progress == "coin" and sp.bounty == "default" and sp.attacked == nil
    and db.settings.milestones == nil and db.settings.gearMin == nil, "upgrade: per-alert sounds become one per kind; fixed settings dropped")
  check(#ns.Saved.STEPS == 14, "fourteen upgrade steps")
  local g = { settings = { show = { attacked = "chat", engage = "toast", died = "off", kill = "toast", loot = "toast", gear = "chat", level = "chat" },
    sound = { attacked = true, engage = true, died = false, kill = false, loot = true, gear = false, level = true } } }
  ns.Saved.STEPS[12](g)
  local gs, gn = g.settings.show, g.settings.sound
  check(gs.engage == "chat" and gs.died == "chat" and gs.kill == "chat" and gn.died and gn.kill and not gn.engage
    and gs.gear == "toast" and gs.level == "toast" and gn.gear and not gn.level,
    "upgrade: each alert group takes its lead alert's setting; attacking someone and level-ups stay quiet")
end

-- 0.9.4: the alert list is a window opened from Options (not on the Friends tab); the Friends tab
-- shows the Bounty board gold each person collected
do
  local errs = ns.errors
  local cols = ns.UI.TabColumns("friends")
  local hasAlerts, bcol = false, nil
  for i, c in ipairs(cols) do
    if c[1] == "Alerts" then hasAlerts = true end
    if c[1] == ns.L.COL_BOUNTIES then bcol = i end
  end
  check(not hasAlerts and bcol ~= nil, "Friends tab: no Alerts column; a Bounties column")
  local saved = FriendsAndFoesDB.contracts
  FriendsAndFoesDB.contracts = {
    ["Someone Else/a1"] = { id = "a1", by = "Someone Else", target = "X Y", amount = 50000, state = "paid", killer = "Buddy Pal", t = time() },
    ["Someone Else/a2"] = { id = "a2", by = "Someone Else", target = "X Z", amount = 1234, state = "done", killer = "Buddy Pal", t = time() },
    ["Buddy Pal/a3"] = { id = "a3", by = "Buddy Pal", target = "X W", amount = 9999, state = "paid", killer = "Buddy Pal", t = time() },
  }
  check(ns.Contracts.EarnedBy("Buddy Pal") == 50000, "bounties collected: paid ones only, not their own")
  check(ns.Plain(cols[bcol][3]({ name = "Buddy Pal" })):find("5 ", 1, true) and cols[bcol][3]({ name = "Nobody Here" }) == "",
    "the Bounties cell: gold collected, empty for none")
  FriendsAndFoesDB.contracts = saved
  -- the window: one tick box per friend account; ticking adds them to the alert list
  ns.Comm.ClearPicks()
  ns.UI.ShowAlertList()
  local w = ns.UI.AlertListWindow()
  local accts = ns.UI.AlertAccounts()
  local buddyAcct
  for _, a in ipairs(accts) do if a.tag == "Buddy#1234" then buddyAcct = a end end
  check(w and w:IsShown() and buddyAcct ~= nil, "alert list window lists friend accounts")
  SlashCmdList.FRIENDSANDFOES("alerts")
  check(w:IsShown(), "/fnf alerts opens it")
  ns.Comm.TogglePick("Buddy#1234")
  ns.UI.RefreshAlertList()
  check(ns.Comm.IsPicked("Buddy#1234") and ns.Comm.GroupActive(), "ticking a friend puts them on the alert list")
  ns.Comm.ClearPicks()
  w:Hide()
  check(ns.errors == errs, "no errors in the alert list window (" .. tostring(ns.lastError) .. ")")
end

-- 0.9.4: the killing blow decides who gets the credit; without one, the old rules
do
  local errs = ns.errors
  local rr = ns.Data.RealRealm()
  local B, C = ns.Bounty, ns.Contracts

  -- notoriety: shared equally between everyone who got the kill, whoever landed the blow
  B.SettleAll() -- (anything left over from earlier)
  rr.players["Kb Target"] = { name = "Kb Target", enemy = true, k = 3, d = 0, a = 0 }
  local before = B.Mine()
  B.OnKill(ns.me, "Kb Target", false)
  B.OnKill("Buddy Pal", "Kb Target", true)
  B.SettleAll()
  check(B.Mine() == before + 150, "a friend's killing blow: notoriety is shared equally, not winner takes all (" .. (B.Mine() - before) .. ")")
  ADVANCE(120)
  rr.players["Kb Target"].k = 6
  before = B.Mine()
  B.OnKill("Buddy Pal", "Kb Target", false)
  B.OnKill(ns.me, "Kb Target", true)
  B.SettleAll()
  check(B.Mine() == before + 150, "your killing blow with another killer: half, not all (" .. (B.Mine() - before) .. ")")
  ADVANCE(120)
  rr.players["Kb Target"].k = 8
  before = B.Mine()
  B.OnKill("Buddy Pal", "Kb Target", false)
  B.OnKill(ns.me, "Kb Target", false)
  B.SettleAll()
  check(B.Mine() == before + 100, "no killing blow known: shared equally, as before (" .. (B.Mine() - before) .. ")")
  rr.players["Kb Target"] = nil

  -- the bounty board: a killing blow closes it, even if someone else reported the kill first
  local saved = FriendsAndFoesDB.contracts
  FriendsAndFoesDB.contracts = {}
  local showWas = ns.S().show.contract
  ns.S().show.contract = "chat"
  local c = C.Post({ name = "Kb Mark", class = "ROGUE" }, 10000, 3)
  C.OnKill("Alice Wonder", "Kb Mark", false)
  check(c.state == "done" and c.killer == "Alice Wonder" and not c.blow, "(first to report it, no killing blow)")
  CHAT = {}
  C.OnKill("Buddy Pal", "Kb Mark", true)
  local told = false
  for _, l in ipairs(CHAT) do if l:find("Buddy Pal", 1, true) and l:find("in on the kill too", 1, true) then told = true end end
  check(c.killer == "Buddy Pal" and c.blow and #c.killers == 2 and told, "a killing blow on the same death takes over the lead, and you are told they joined")
  C.OnKill("Alice Wonder", "Kb Mark", false)
  check(c.killer == "Buddy Pal", "a later kill without a killing blow doesn't take it back")
  -- a friend's bounty: their message without a killing blow doesn't undo the one you know of
  local function bty(fields, id) FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("BTY", fields, id), "WHISPER", 77) end
  bty({ cid = "kb1", target = "Kb Other:MAGE:50:", amount = 500, state = "open", killer = "", age = 60, updage = 60, days = 3 }, "kbm1")
  local theirs = FriendsAndFoesDB.contracts["Buddy Pal/kb1"]
  ns.Events.Emit("KILL", { victim = "Kb Other", vclass = "MAGE", vlevel = 50, vguild = "", zone = "Duskwood", blow = "1" })
  check(theirs.killer == ns.me and theirs.blow, "your killing blow on a friend's target")
  bty({ cid = "kb1", target = "Kb Other:MAGE:50:", amount = 500, state = "done", killer = "Alice Wonder", age = 60, updage = 0, days = 3, blow = "" }, "kbm2")
  check(theirs.killer == ns.me, "the poster naming someone without a killing blow doesn't override yours")
  bty({ cid = "kb1", target = "Kb Other:MAGE:50:", amount = 500, state = "paid", killer = ns.me, age = 60, updage = 0, days = 3, blow = "1" }, "kbm3")
  check(theirs.state == "paid" and theirs.killer == ns.me, "and their 'paid' goes through")
  for _, name in ipairs({ "Kb Mark", "Kb Other" }) do rr.hitlist[name], rr.players[name] = nil, nil end
  FriendsAndFoesDB.contracts = saved
  ns.S().show.contract = showWas
  RUN_TICKERS(80)
  check(ns.errors == errs, "no errors in killing-blow credit (" .. tostring(ns.lastError) .. ")")
end

-- 0.9.4: pets credit their owner; with no killing blow, the latest attacker gets the credit
do
  local errs = ns.errors
  local rr = ns.Data.RealRealm()
  local B, C = ns.Bounty, ns.Contracts
  local BC = ns.Events.BetterCredit

  -- the rank: a blow beats none; the first blow stays; smaller `last` wins; known beats unknown; ties keep the first
  check(BC({ blow = "1" }, { last = 1 }) and not BC({ last = 1 }, { blow = "pet" }), "credit rank: a killing blow beats a last attack")
  check(BC({ blow = "pet" }, {}) and not BC({}, { blow = "1" }), "credit rank: a pet's blow beats nothing")
  check(not BC({ blow = "1" }, { blow = "pet" }) and not BC({ blow = "pet" }, { blow = "1" }), "credit rank: of two blows the first stays")
  check(BC({ last = 3 }, { last = 9 }) and not BC({ last = 9 }, { last = 3 }), "credit rank: the more recent attacker wins")
  check(BC({ last = 90 }, {}) and not BC({}, { last = 90 }), "credit rank: a known last attack beats an unknown one")
  check(not BC({}, {}) and not BC({ last = 5 }, { last = 5 }), "credit rank: nothing known / a tie keeps the first")

  -- mocks, as in the PARTY_KILL tests
  local enemyUnits = {}
  local o = { UnitExists = UnitExists, UnitIsPlayer = UnitIsPlayer, UnitFactionGroup = UnitFactionGroup, UnitName = UnitName,
    UnitClass = UnitClass, UnitLevel = UnitLevel, UnitIsDeadOrGhost = UnitIsDeadOrGhost, UnitIsUnit = UnitIsUnit, UnitGUID = UnitGUID }
  local oEmit = ns.Events.Emit
  UnitExists = function(u) return enemyUnits[u] ~= nil or o.UnitExists(u) end
  UnitIsPlayer = function(u) if enemyUnits[u] then return true end return o.UnitIsPlayer and o.UnitIsPlayer(u) end
  UnitFactionGroup = function(u) if enemyUnits[u] then return "Alliance" end return o.UnitFactionGroup(u) end
  UnitName = function(u) local e = enemyUnits[u]; if e then return e[1], e[2] end return o.UnitName(u) end
  UnitClass = function(u) if enemyUnits[u] then return "Rogue", "ROGUE" end return o.UnitClass(u) end
  UnitLevel = function(u) if enemyUnits[u] then return 24 end return o.UnitLevel(u) end
  UnitIsDeadOrGhost = function(u) local e = enemyUnits[u]; return e and e[3] or false end
  UnitIsUnit = function() return false end
  UnitGUID = function(u)
    if u == "player" then return "Player-1-00000001" end
    if u == "pet" then return "Pet-0-1-2-3-4-5" end
    if enemyUnits[u] then return "Player-1-" .. enemyUnits[u][1] end
  end
  local sent
  ns.Events.Emit = function(kind, f) if kind == "KILL" then sent = f end return oEmit(kind, f) end
  local HONOR = "You have been awarded 7 Honor."

  -- your pet's killing blow is yours, marked as the pet's
  enemyUnits.target = { "Pet", "Prey", false }
  ns.PvP.ReadEnemy("target")
  enemyUnits.target = nil
  ADVANCE(40)
  FIRE("PARTY_KILL", "Pet-0-1-2-3-4-5", "Player-1-Pet")
  FIRE("CHAT_MSG_COMBAT_HONOR_GAIN", HONOR)
  check(sent and sent.blow == "pet" and sent.victim == "Pet Prey", "your pet's killing blow: sent as 'pet' with the victim named")
  check(lastFeed():find("Pet Prey", 1, true) and lastFeed():find(ns.L.PET_BLOW_TAG, 1, true), "your pet's killing blow: the pet tag in the feed: " .. lastFeed())

  -- a creature killing blow is logged once a session, not every time
  local debugWas = ns.S().debug
  ns.S().debug = true
  local function creatureLogs()
    local n = 0
    for _, l in ipairs(FriendsAndFoesDB.debugLog or {}) do if l:find("not a player", 1, true) then n = n + 1 end end
    return n
  end
  FIRE("PARTY_KILL", "Player-1-00000001", "Creature-0-1-2-3-4-5")
  local afterFirst = creatureLogs()
  FIRE("PARTY_KILL", "Player-1-00000001", "Creature-0-1-2-3-4-6")
  FIRE("PARTY_KILL", "Pet-0-1-2-3-4-5", "Creature-0-1-2-3-4-7")
  check(creatureLogs() == afterFirst, "creature killing blows: logged once a session, not every time")
  ns.S().debug = debugWas

  -- UNIT_SPELLCAST_SENT with a first name records your last attack; the KILL then carries `last`
  enemyUnits.target = { "Cast", "Target", false }
  FIRE("PLAYER_TARGET_CHANGED")
  check(ns.PvP.LastAttack("Cast Target") == nil, "no attack recorded yet")
  ADVANCE(30)
  FIRE("UNIT_SPELLCAST_SENT", "player", "Cast", "cast-guid", 133)
  ADVANCE(7)
  local la = ns.PvP.LastAttack("Cast Target")
  check(la and la >= 6.9 and la <= 7.1, "a spell sent at a first name records your last attack on the seen enemy: " .. tostring(la))
  enemyUnits.target[3] = true
  sent = nil
  FIRE("CHAT_MSG_COMBAT_HONOR_GAIN", HONOR)
  check(sent and sent.victim == "Cast Target" and sent.last == "7" and sent.blow == "", "the KILL message carries `last` (" .. tostring(sent and sent.last) .. ")")
  enemyUnits.target = nil
  FIRE("UNIT_SPELLCAST_SENT", "player", "Nobody", "cast-guid", 133)
  check(ns.PvP.LastAttack("Nobody") == nil and ns.PvP.LastAttack("Nobody Here") == nil, "a spell at someone unseen records nothing")

  -- auto-attack / auto-shot (events) keep refreshing your last attack on your target's health changes
  enemyUnits.target = { "Auto", "Swinger", false }
  FIRE("PLAYER_TARGET_CHANGED")
  ADVANCE(5)
  FIRE("UNIT_HEALTH", "target")
  check(ns.PvP.LastAttack("Auto Swinger") == nil, "a health change alone isn't an attack")
  FIRE("PLAYER_ENTER_COMBAT")
  ADVANCE(2)
  FIRE("UNIT_HEALTH", "target")
  check((ns.PvP.LastAttack("Auto Swinger") or 99) < 0.5, "auto-attacking: a health change refreshes your last attack")
  FIRE("PLAYER_LEAVE_COMBAT")
  ADVANCE(5)
  FIRE("UNIT_HEALTH", "target")
  check((ns.PvP.LastAttack("Auto Swinger") or 0) >= 4.9, "auto-attack off: no longer refreshed")
  FIRE("START_AUTOREPEAT_SPELL")
  ADVANCE(2)
  FIRE("UNIT_HEALTH", "target")
  check((ns.PvP.LastAttack("Auto Swinger") or 99) < 0.5, "auto-shot on: refreshed")
  FIRE("STOP_AUTOREPEAT_SPELL")
  ADVANCE(5)
  FIRE("UNIT_HEALTH", "target")
  check((ns.PvP.LastAttack("Auto Swinger") or 0) >= 4.9, "auto-shot off: no longer refreshed")
  FIRE("PLAYER_ENTER_COMBAT")
  FIRE("START_AUTOREPEAT_SPELL")
  FIRE("PLAYER_REGEN_ENABLED")
  local aa, ar = ns.PvP.AutoFlags()
  check(not aa and not ar, "leaving combat resets both flags")
  enemyUnits.target = nil

  ns.Events.Emit = oEmit
  for k, v in pairs(o) do _G[k] = v end
  FriendsAndFoesCharDB.streak = 0

  -- notoriety: equal shares whatever the credit says
  B.SettleAll() -- (anything left over from earlier)
  rr.players["Lp Target"] = { name = "Lp Target", enemy = true, k = 3, d = 0, a = 0 }
  local amount = B.Open("Lp Target")
  local before = B.Mine()
  B.OnKill(ns.me, "Lp Target", { last = 20 })
  B.OnKill("Buddy Pal", "Lp Target", { last = 5 })
  B.SettleAll()
  check(B.Mine() == before + math.floor(amount / 2), "notoriety: the friend attacked more recently, still half for you")
  ADVANCE(120)
  rr.players["Lp Target"].k = 6
  amount = B.Open("Lp Target")
  before = B.Mine()
  B.OnKill("Buddy Pal", "Lp Target", { last = 30 })
  B.OnKill(ns.me, "Lp Target", { last = 3 })
  B.SettleAll()
  check(B.Mine() == before + math.floor(amount / 2), "notoriety: you attacked last, still just half (" .. (B.Mine() - before) .. " of " .. amount .. ")")
  ADVANCE(120)
  rr.players["Lp Target"].k = 9
  before = B.Mine()
  B.OnKill(ns.me, "Lp Target", {})
  B.OnKill("Buddy Pal", "Lp Target", { last = 50 })
  B.SettleAll()
  check(B.Mine() == before + math.floor(amount / 2), "notoriety: credit never changes the split")
  ADVANCE(120)
  rr.players["Lp Target"].k = 12
  before = B.Mine()
  B.OnKill(ns.me, "Lp Target", { last = 10 })
  B.OnKill("Buddy Pal", "Lp Target", { blow = "pet" })
  B.SettleAll()
  check(B.Mine() == before + math.floor(amount / 2), "notoriety: a pet's blow doesn't change the split either")
  ADVANCE(120)
  rr.players["Lp Target"].k = 15
  amount = B.Open("Lp Target")
  before = B.Mine()
  B.OnKill(ns.me, "Lp Target", {})
  B.OnKill("Buddy Pal", "Lp Target", {})
  B.SettleAll()
  check(B.Mine() == before + math.floor(amount / 2), "notoriety: nothing known, shared equally as before")
  ADVANCE(120)
  -- three killers, 300 points: 100 each, credited or not; one killer: all of it
  rr.players["Lp Target"].k = 18
  amount = B.Open("Lp Target")
  before = B.Mine()
  B.OnKill(ns.me, "Lp Target", {})
  B.OnKill("Buddy Pal", "Lp Target", { blow = "1" })
  B.OnKill("Alice Wonder", "Lp Target", { last = 5 })
  B.SettleAll()
  check(amount == 300 and B.Mine() == before + 100, "notoriety: 3 killers, 300 points, 100 each (" .. (B.Mine() - before) .. ")")
  ADVANCE(120)
  rr.players["Lp Target"].k = 21
  before = B.Mine()
  B.OnKill(ns.me, "Lp Target", { blow = "1" })
  B.OnKill("Buddy Pal", "Lp Target", {})
  B.OnKill("Alice Wonder", "Lp Target", {})
  B.SettleAll()
  check(B.Mine() == before + 100, "notoriety: 3 killers, your killing blow, still 100")
  ADVANCE(120)
  rr.players["Lp Target"].k = 24
  before = B.Mine()
  B.OnKill(ns.me, "Lp Target", { blow = "1" })
  B.SettleAll()
  check(B.Mine() == before + 300, "notoriety: alone, all of it")
  rr.players["Lp Target"] = nil

  -- the bounty board
  local saved = FriendsAndFoesDB.contracts
  FriendsAndFoesDB.contracts = {}
  local showWas = ns.S().show.contract
  ns.S().show.contract = "chat"
  local c = C.Post({ name = "Lp Mark", class = "ROGUE" }, 10000, 3)
  C.OnKill("Alice Wonder", "Lp Mark", { last = 40 })
  check(c.state == "done" and c.killer == "Alice Wonder" and c.last == 40 and not c.blow, "(first report, last attack 40 s ago)")
  C.OnKill("Buddy Pal", "Lp Mark", { last = 10 })
  check(c.killer == "Buddy Pal" and c.last == 10, "a smaller last attack takes the contract over")
  C.OnKill("Alice Wonder", "Lp Mark", { last = 30 })
  check(c.killer == "Buddy Pal", "a larger last attack doesn't take it back")
  C.OnKill("Alice Wonder", "Lp Mark", { blow = "1" })
  check(c.killer == "Alice Wonder" and c.blow == "1", "a killing blow beats them both")
  C.OnKill("Buddy Pal", "Lp Mark", { blow = "pet" })
  check(c.killer == "Alice Wonder", "of two killing blows the first stays")
  -- a friend's bounty: the poster's message with a worse credit doesn't override yours
  local function bty(fields, id) FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("BTY", fields, id), "WHISPER", 77) end
  bty({ cid = "lp1", target = "Lp Other:MAGE:50:", amount = 500, state = "open", killer = "", age = 60, updage = 60, days = 3 }, "lpm1")
  local theirs = FriendsAndFoesDB.contracts["Buddy Pal/lp1"]
  ns.Events.Emit("KILL", { victim = "Lp Other", vclass = "MAGE", vlevel = 50, vguild = "", zone = "Duskwood", last = "5" })
  check(theirs.killer == ns.me and theirs.last == 5 and not theirs.blow, "your last attack counted on a friend's target")
  bty({ cid = "lp1", target = "Lp Other:MAGE:50:", amount = 500, state = "done", killer = "Alice Wonder", age = 60, updage = 0, days = 3, last = "40" }, "lpm2")
  check(theirs.killer == ns.me, "the poster naming someone with an older last attack doesn't override yours")
  bty({ cid = "lp1", target = "Lp Other:MAGE:50:", amount = 500, state = "done", killer = "Alice Wonder", age = 60, updage = 0, days = 3, blow = "pet", last = "" }, "lpm3")
  check(theirs.killer == "Alice Wonder" and theirs.blow == "pet", "...but one with a pet's blow outranks it")
  for _, name in ipairs({ "Lp Mark", "Lp Other" }) do rr.hitlist[name], rr.players[name] = nil, nil end
  FriendsAndFoesDB.contracts = saved
  ns.S().show.contract = showWas
  RUN_TICKERS(80)
  check(ns.errors == errs, "no errors in pet and last-attack credit (" .. tostring(ns.lastError) .. ")")
end

-- 1.0: notoriety rules - randoms, hitlist enemies, rampage, cooling, ranks, titles, fading,
-- takedown toasts, this week
do
  local errs = ns.errors
  local B = ns.Bounty
  local L = ns.L
  local rr = ns.Data.RealRealm()
  local P = FriendsAndFoesDB.profile
  local savedB, savedW = P.bounty, FriendsAndFoesDB.weekly
  P.bounty = nil
  FriendsAndFoesDB.weekly = { start = time(), k = 0, d = 0, killers = {}, bt = 0 }
  B.SettleAll() -- (leftover claims settle too)
  local pushed = {}
  local realPush = ns.Toast.Push
  ns.Toast.Push = function(spec) pushed[#pushed + 1] = spec end
  local function enemy(name, k, atk)
    rr.players[name] = { name = name, enemy = true, class = "ROGUE", k = k or 0, d = 0, a = 0, atk = atk or 0, lastSeen = time() }
    return rr.players[name]
  end
  local function hit(name, kills, attacks)
    rr.hitlist[name] = { name = name, attacks = attacks or 0, kills = kills or 0, suspect = 0, revenge = 0, victims = {}, firstSeen = time() }
    return rr.hitlist[name]
  end
  local function claim(victim, killer, credit)
    ADVANCE(120)
    B.OnKill(killer or ns.me, victim, credit)
    B.SettleAll()
  end
  local function find(header)
    local got
    for _, sp in ipairs(pushed) do if sp.header == header then got = sp end end
    return got
  end
  local names = { "Rando One", "Hit Hank", "Hit Hugo", "Rank Ron", "Title Tim", "Wk Wendy" }

  -- a random: 10, then less for repeats within 30 minutes (wall time moves with ns.eventTime)
  FriendsAndFoesDB.repeats = nil
  local wall = time()
  local function at(secs) ns.eventTime = wall + secs end
  at(0)
  local rec = enemy("Rando One")
  check(B.Open("Rando One") == 10 and B.Rank("Rando One") == nil, "a random is worth 10 and has no rank")
  local before = B.Mine()
  claim("Rando One")
  check(B.Mine() == before + 10, "claimed a random: 10")
  check(B.Open("Rando One") == 5, "the same random again within 30 minutes: 5")
  FriendsAndFoesDB.repeats = nil
  hit("Rando One", 0, 0)
  check(B.Open("Rando One") == 10 and B.Rank("Rando One") == nil, "an empty hitlist entry is still a random")

  -- a hitlist enemy: 100 per kill, 25 per attack, at least 50
  enemy("Hit Hank", 2, 0)
  local h = hit("Hit Hank", 2, 2)
  check(B.Open("Hit Hank") == 250, "2 kills and 2 attacks = 250, got " .. B.Open("Hit Hank"))
  enemy("Hit Hugo", 0, 0)
  hit("Hit Hugo", 1, 0)
  check(B.Open("Hit Hugo") == 50, "a hitlist enemy is worth at least 50, got " .. B.Open("Hit Hugo"))
  check(B.Price(0, 0) == 0 and B.Price(1, 1) == 125, "the sum itself")

  -- a rampage: 3 kills on your group in an hour: x1.5
  h.attacks = 0
  local now = ns.Now()
  h.killTimes = { now - 5000, now - 400, now - 100 }
  check(not B.OnRampage("Hit Hank") and B.Open("Hit Hank") == 200, "2 kills in the hour: no rampage")
  h.killTimes = { now - 300, now - 200, now - 100 }
  check(B.OnRampage("Hit Hank") and B.Open("Hit Hank") == 300, "3 kills in the hour: x1.5, got " .. B.Open("Hit Hank"))
  local v = ns.UI.ProfileView("Hit Hank")
  check(v and v.rank and v.rank:find(L.RAMPAGE_TAG, 1, true) and v.rank:find(L.RANK_WANTED, 1, true), "the profile says on a rampage: " .. tostring(v and v.rank))
  h.killTimes = { now - 7000, now - 6000, now - 5000 }
  check(not B.OnRampage("Hit Hank") and B.Open("Hit Hank") == 200, "3 kills but not within the hour: no rampage")

  -- cooling: x0.9 per full day since their last offence
  h.lastOffence = now - 3 * 86400 - 100
  check(B.Open("Hit Hank") == 145, "3 quiet days: 200 x 0.9^3 = 145, got " .. B.Open("Hit Hank"))
  h.lastOffence = now - 86400 + 100
  check(B.Open("Hit Hank") == 200, "less than a day: no cooling")
  h.lastOffence = now - 60 * 86400
  check(B.Open("Hit Hank") == 50, "cooled right down: never below 50")
  h.lastOffence = nil

  -- ranks
  enemy("Rank Ron", 0, 0)
  hit("Rank Ron", 1, 0)
  local function rankAt(k) rr.players["Rank Ron"].k = k; return B.Rank("Rank Ron") end
  check(rankAt(0) == L.RANK_NUISANCE, "50: Nuisance")
  check(rankAt(1) == L.RANK_MENACE, "100: Menace")
  check(rankAt(2) == L.RANK_MENACE and rankAt(3) == L.RANK_WANTED, "300: Wanted")
  check(rankAt(5) == L.RANK_WANTED and rankAt(6) == L.RANK_MOST_WANTED, "600: Most Wanted")
  check(rankAt(9) == L.RANK_MOST_WANTED and rankAt(10) == L.RANK_PUBLIC_ENEMY, "1000: Public Enemy")
  check(B.RankFor(99) == L.RANK_NUISANCE and B.RankFor(299) == L.RANK_MENACE, "just under a threshold")
  check(ns.Plain(ns.UI.ProfileView("Rank Ron").rank) == L.RANK_PUBLIC_ENEMY, "the rank is on the profile")

  -- titles, from what you have now
  check(B.Title(0) == L.TITLE_TRACKER and B.Title(499) == L.TITLE_TRACKER and B.Title(500) == L.TITLE_HUNTER, "titles: Tracker, Hunter")
  check(B.Title(1999) == L.TITLE_HUNTER and B.Title(2000) == L.TITLE_BOUNTY_HUNTER, "Bounty Hunter at 2000")
  check(B.Title(4999) == L.TITLE_BOUNTY_HUNTER and B.Title(5000) == L.TITLE_MANHUNTER, "Manhunter at 5000")
  check(B.Title(9999) == L.TITLE_MANHUNTER and B.Title(10000) == L.TITLE_LEGEND, "Legend at 10000")
  enemy("Title Tim", 1, 0)
  hit("Title Tim", 1, 0)
  P.bounty = { total = 480, allTime = 480, count = 1, clock = time() }
  pushed = {}
  claim("Title Tim")
  local tt = find(L.HEADER_TITLE)
  check(B.Mine() == 580 and tt and tt.milestone and tt.kind == "kill" and tt.category == "pvp" and ns.Plain(tt.title):find(L.TITLE_HUNTER, 1, true),
    "a toast for reaching a new title")
  pushed = {}
  rr.players["Title Tim"].k = 2
  claim("Title Tim")
  check(find(L.HEADER_TITLE) == nil, "no second toast within the same title")

  -- your notoriety fades: 10% per full idle week; a claim starts the clock again; all-time stays
  P.bounty = { total = 1000, allTime = 1000, count = 1, clock = time() - 6 * 86400 }
  check(B.Mine() == 1000, "within a week: nothing fades")
  P.bounty = { total = 1000, allTime = 1000, count = 1, clock = time() - 8 * 86400 }
  check(B.Mine() == 900 and B.Mine() == 900, "one full week: 900, and not taken off twice")
  P.bounty = { total = 1000, allTime = 1000, count = 1, clock = time() - 22 * 86400 }
  check(B.Mine() == 729 and B.AllTime() == 1000, "three idle weeks: 729; all-time unchanged, got " .. B.Mine())
  P.bounty = { total = 5000, allTime = 5000, count = 1, clock = time() - 15 * 86400 }
  pushed = {}
  check(B.Title(B.Mine()) == L.TITLE_BOUNTY_HUNTER and #pushed == 0, "two weeks fade a Manhunter to Bounty Hunter, quietly")
  P.bounty = { total = 1000, allTime = 1000, count = 1, clock = time() - 22 * 86400 }
  rr.players["Title Tim"].k = 5
  claim("Title Tim") -- (300: it fades first, then adds)
  check(B.Mine() == 729 + 300 and B.AllTime() == 1300 and time() - P.bounty.clock < 60, "a claim: fades first, adds, restarts the clock, got " .. B.Mine())
  P.bounty = { total = 700 } -- (from before the fading)
  check(B.Mine() == 700 and B.AllTime() == 700, "an older save: all you had is your all-time")

  -- a takedown: a claim of 300 or more is a toast for everyone, whoever got it
  enemy("Hit Hugo", 3, 0)
  hit("Hit Hugo", 3, 0)
  P.bounty = { total = 0, allTime = 0, count = 0, clock = time() }
  pushed = {}
  claim("Hit Hugo", "Buddy Pal", true)
  local td = find(L.HEADER_TAKEDOWN)
  local plain = td and ns.Plain(td.title) or ""
  check(td and td.milestone and td.kind == "kill" and td.category == "pvp" and plain:find("Buddy Pal brought down Hit Hugo", 1, true)
    and plain:find(L.RANK_WANTED, 1, true) and plain:find("300", 1, true), "a friend's takedown: " .. plain)
  check(B.Mine() == 0, "...and nothing for you")
  rr.players["Hit Hugo"].k = 6
  pushed = {}
  ADVANCE(120)
  B.OnKill(ns.me, "Hit Hugo", {})
  B.OnKill("Buddy Pal", "Hit Hugo", {})
  B.SettleAll()
  td = find(L.HEADER_TAKEDOWN)
  plain = td and ns.Plain(td.title) or ""
  check(td and plain:find("brought down Hit Hugo", 1, true) and plain:find("shared", 1, true) and plain:find("Buddy Pal", 1, true), "a shared takedown says so: " .. plain)
  check(B.Mine() == 150, "...and you take your half (150 of 300), got " .. B.Mine())
  rr.players["Hit Hugo"].k = 7
  pushed = {}
  claim("Hit Hugo", "Buddy Pal", true)
  check(find(L.HEADER_TAKEDOWN) == nil, "100 is no takedown: no toast")

  -- this week
  FriendsAndFoesDB.weekly = { start = time(), k = 0, d = 0, killers = {}, bt = 0 }
  P.bounty = { total = 0, allTime = 0, count = 0, clock = time() }
  enemy("Wk Wendy", 2, 0)
  hit("Wk Wendy", 2, 0)
  claim("Wk Wendy")
  check(B.Week() == 200 and FriendsAndFoesDB.weekly.bt == 200, "this week: 200")
  local f = ns.Profile.Fields()
  check(tostring(f.btw) == "200" and f.bwk == math.floor(FriendsAndFoesDB.weekly.start / 86400), "this week goes out with your profile")
  local weekLine
  for _, l in ipairs(ns.UI.ProfileView(ns.me).lines) do if l[1] == L.PROF_BOUNTIES_WEEK then weekLine = ns.Plain(tostring(l[2])) end end
  check(weekLine and weekLine:find("200", 1, true), "your profile shows this week")
  local pal = { name = "Pal Wk", friend = true }
  local today = math.floor(time() / 86400)
  ns.Profile.Apply(pal, { k = "1", d = "1", wanted = "", zone = "", status = "", t = "", bt = "900", btw = "350", bwk = tostring(today) })
  check(B.FriendWeek(pal) == 350, "a friend's this week arrives")
  ns.Profile.Apply(pal, { k = "1", d = "1", wanted = "", zone = "", status = "", t = "", bt = "900", btw = "350", bwk = tostring(today - 10) })
  check(B.FriendWeek(pal) == 0, "a stale week shows as 0")
  ns.Profile.Apply(pal, { k = "1", d = "1", wanted = "", zone = "", status = "", t = "", bt = "900" })
  check(B.FriendWeek(pal) == nil, "an older version: unknown")
  FriendsAndFoesDB.weekly.start = time() - 8 * 86400
  check(B.Week() == 0, "the week is over: back to 0")
  rr.players["Wk Wendy"].k = 3
  claim("Wk Wendy")
  check(B.Week() == 100 and time() - FriendsAndFoesDB.weekly.start < 60, "a claim after the boundary starts a new week with it, got " .. B.Week())
  FriendsAndFoesDB.weekly = { start = time() - 8 * 86400, k = 1, d = 0, killers = {}, bt = 350 }
  CHAT = {}
  ns.Events.WeeklyRoll()
  RUN_TIMERS()
  local summary
  for _, line in ipairs(CHAT) do if line:find("Your PvP week", 1, true) then summary = ns.Plain(line) end end
  check(summary and summary:find("350 notoriety", 1, true), "the weekly summary has the notoriety: " .. tostring(summary))

  ns.Toast.Push = realPush
  ns.eventTime = nil
  FriendsAndFoesDB.repeats = nil
  for _, n in ipairs(names) do rr.players[n], rr.hitlist[n] = nil, nil end
  P.bounty, FriendsAndFoesDB.weekly = savedB, savedW
  RUN_TICKERS(80)
  check(ns.errors == errs, "no errors with the notoriety rules (" .. tostring(ns.lastError) .. ")")
end

-- notoriety: diminishing returns for repeat kills of the same enemy within 30 minutes
do
  local errs = ns.errors
  local B = ns.Bounty
  local rr = ns.Data.RealRealm()
  local P = FriendsAndFoesDB.profile
  local savedB, savedW, savedR = P.bounty, FriendsAndFoesDB.weekly, FriendsAndFoesDB.repeats
  P.bounty = { total = 0, allTime = 0, count = 0, clock = time() }
  FriendsAndFoesDB.weekly = { start = time(), k = 0, d = 0, killers = {}, bt = 0 }
  FriendsAndFoesDB.repeats = nil
  B.SettleAll()
  local pushed = {}
  local realPush = ns.Toast.Push
  ns.Toast.Push = function(spec) pushed[#pushed + 1] = spec end
  local wall = time()
  local function at(min) ns.eventTime = wall + min * 60 end
  local function enemy(name, k)
    rr.players[name] = { name = name, enemy = true, class = "ROGUE", k = k or 0, d = 0, a = 0, atk = 0, lastSeen = time() }
    return rr.players[name]
  end
  local function hit(name, kills)
    rr.hitlist[name] = { name = name, attacks = 0, kills = kills or 0, suspect = 0, revenge = 0, victims = {}, firstSeen = time() }
  end
  -- a kill at minute m; returns what you got
  local function kill(name, m, killers)
    at(m)
    ADVANCE(300)
    local before = B.Mine()
    for _, who in ipairs(killers or { ns.me }) do B.OnKill(who, name, {}) end
    B.SettleAll()
    return B.Mine() - before
  end

  -- a random: 10, 5, 2, 0 for kills 5 minutes apart; after 31 idle minutes back to 10
  enemy("Camp Carl")
  local got = { kill("Camp Carl", 0), kill("Camp Carl", 5), kill("Camp Carl", 10) }
  check(got[1] == 10 and got[2] == 5 and got[3] == 2, "a random camped: 10, 5, 2, got " .. table.concat(got, ","))
  CHAT, pushed = {}, {}
  local counted = select(2, B.Mine())
  check(kill("Camp Carl", 15) == 0 and B.Open("Camp Carl") == 0, "the fourth kill is worth 0")
  check(#CHAT == 0 and #pushed == 0 and select(2, B.Mine()) == counted, "...and says nothing, counts no claim")
  at(15 + 31)
  check(B.Repeats("Camp Carl") == 0 and B.Open("Camp Carl") == 10, "31 quiet minutes later: worth 10 again")
  check(kill("Camp Carl", 46) == 10, "...and pays 10")

  -- every repeat extends the window: kills at 0, 25, 50 minutes -> the third is still x0.25
  enemy("Chain Cher")
  got = { kill("Chain Cher", 100), kill("Chain Cher", 125), kill("Chain Cher", 150) }
  check(got[1] == 10 and got[2] == 5 and got[3] == 2, "a chain of kills 25 minutes apart: 10, 5, 2, got " .. table.concat(got, ","))

  -- a hitlist enemy with no new deeds: 50, 25, 12, 0
  enemy("Hit Hal", 0)
  hit("Hit Hal", 1)
  got = { kill("Hit Hal", 200), kill("Hit Hal", 201), kill("Hit Hal", 202), kill("Hit Hal", 203) }
  check(got[1] == 50 and got[2] == 25 and got[3] == 12 and got[4] == 0, "a hitlist enemy camped: 50, 25, 12, 0, got " .. table.concat(got, ","))

  -- ...but one who kills a friend in between is worth the full earned points, and the chain starts again
  at(204)
  rr.players["Hit Hal"].k = 1
  check(B.Open("Hit Hal") == 100, "they killed a friend: full 100 even after being camped, got " .. B.Open("Hit Hal"))
  check(kill("Hit Hal", 204) == 100 and B.Repeats("Hit Hal") == 0, "...paid in full, and the repeat counter is back to 0")
  check(B.Open("Hit Hal") == 50, "the next kill with no new deeds: the full 50 again")

  -- two friends reporting the same kill within a minute are one repeat
  enemy("Dup Dan")
  check(kill("Dup Dan", 300, { ns.me, "Buddy Pal" }) == 5, "shared: your half of 10")
  check(B.Repeats("Dup Dan") == 1 and B.Open("Dup Dan") == 5, "two reports of one kill count as one repeat")

  -- caught-up (past) kills pay nothing and are not repeats
  enemy("Past Pat")
  ns.past = true
  B.OnKill("Buddy Pal", "Past Pat", {})
  ns.past = nil
  check(B.Repeats("Past Pat") == 0 and B.Open("Past Pat") == 10, "a caught-up kill is not a repeat")

  -- the saved list is pruned and small
  at(400)
  kill("Camp Carl", 400)
  local n = 0
  for _ in pairs(FriendsAndFoesDB.repeats) do n = n + 1 end
  check(n == 1 and #FriendsAndFoesDB.repeats["Camp Carl"] <= 4, "old chains are dropped from the saved list")

  ns.Toast.Push = realPush
  ns.eventTime = nil
  for _, nm in ipairs({ "Camp Carl", "Chain Cher", "Hit Hal", "Dup Dan", "Past Pat" }) do rr.players[nm], rr.hitlist[nm] = nil, nil end
  P.bounty, FriendsAndFoesDB.weekly, FriendsAndFoesDB.repeats = savedB, savedW, savedR
  RUN_TICKERS(80)
  check(ns.errors == errs, "no errors with repeat kills (" .. tostring(ns.lastError) .. ")")
end

-- 0.9.4: better syncing. Shared helpers for the blocks below: pretend these friends are online.
local SYNC = {}
function SYNC.friends(F)
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
  return function()
    BNGetNumFriends, C_BattleNet.GetFriendGameAccountInfo, C_BattleNet.GetFriendAccountInfo, C_BattleNet.GetGameAccountInfoByID =
      o.num, o.info, o.acct, o.byId
    ns.Comm.RebuildRoster()
    RUN_TIMERS(); RUN_TICKERS(80)
  end
end
function SYNC.from(name, gid, kind, fields, id, version)
  local p = ns.Comm.Encode({ kind = kind, id = id and ("z94" .. id) or ns.NewId(), name = name, class = "PRIEST", level = 40, f = fields })
  if version then p = p:gsub("\t" .. ns.VERSION .. "\t", "\t" .. version .. "\t", 1) end
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", p, "WHISPER", gid)
end
function SYNC.sent(gid, kind)
  local out = {}
  for _, s in ipairs(SENT) do
    if s.route == "bn" and s.target == gid then
      local m = ns.Comm.Decode(s.payload)
      if m and m.kind == kind then out[#out + 1] = m end
    end
  end
  return out
end
function SYNC.drain() RUN_TIMERS(); RUN_TICKERS(80) end

-- 1) your alts' events reach friends who ask for a catch-up
do
  local errs = ns.errors
  local S = SYNC
  local F = { { gid = 77, name = "Buddy Pal", tag = "Buddy#1234" } }
  local restore = S.friends(F)
  ns.Comm.ClearPicks()
  ns.Comm.RebuildRoster()
  S.drain()
  local rr = ns.Data.RealRealm()
  local savedBox, savedOld, savedMoved = FriendsAndFoesDB.outbox, FriendsAndFoesCharDB.outbox, FriendsAndFoesCharDB.outboxMoved
  FriendsAndFoesDB.outbox = {}
  ns.Comm.Remember("LVL", "mine1", { level = 31 })
  local box = ns.Comm.Outbox()
  box[#box + 1] = { t = time() - 600, kind = "KILL", id = "altk1", who = "Testme Alt", c = "MAGE", l = 22,
    f = { victim = "Alt Victim", vclass = "MAGE", vlevel = "40", vguild = "", zone = "Duskwood", streak = "1", rl = "" } }
  check(box[1].who == ns.me and box[1].c == "WARRIOR", "an event remembers which character it's from")

  ADVANCE(100)
  SENT = {}
  S.from("Buddy Pal", 77, "REQ", { window = 3600 }, "alq1")
  S.drain()
  local rly, lvl = S.sent(77, "RLY"), S.sent(77, "LVL")
  check(#lvl == 1 and lvl[1].id == "mine1", "this character's own event goes out as before")
  check(#rly == 1 and rly[1].f.origin == "Testme Alt" and rly[1].f.alt == "1" and rly[1].f.okind == "KILL" and rly[1].f.oid == "altk1"
    and rly[1].f.oclass == "MAGE" and tonumber(rly[1].f.ago) >= 600, "your alt's event goes out as a relayed one marked alt")
  local fits = true
  for _, s in ipairs(SENT) do if #s.payload > 255 then fits = false end end
  check(fits, "and fits")

  -- a friend on an older version only gets this character's events
  ADVANCE(100)
  SENT = {}
  S.from("Buddy Pal", 77, "REQ", { window = 3600 }, "alq2", "0.9.3")
  S.drain()
  check(#S.sent(77, "RLY") == 0 and #S.sent(77, "LVL") == 1, "an older add-on doesn't get alt events")
  -- your own share settings apply
  ADVANCE(100)
  SENT = {}
  ns.S().share.pvp = false
  S.from("Buddy Pal", 77, "REQ", { window = 3600 }, "alq3")
  S.drain()
  ns.S().share.pvp = true
  check(#S.sent(77, "RLY") == 0, "sharing PvP off: the alt's kill isn't sent")

  -- receiving: a friend's alt events, filed under the alt, and its tag is learned
  local feedBefore = #rr.feed
  local data = table.concat({ "Far Away", "ROGUE", "50", "", "Duskwood", "1" }, "^")
  S.from("Buddy Pal", 77, "RLY", { origin = "Pal Alt", oclass = "MAGE", olevel = 22, okind = "KILL", oid = "pk1", ago = 900, data = data, alt = "1" }, "ra1")
  S.drain()
  local alt = rr.players["Pal Alt"]
  local e
  for _, x in ipairs(rr.feed) do if x.who == "Pal Alt" then e = x end end
  check(alt and alt.friend and e and math.abs(e.t - (time() - 900)) <= 5 and #rr.feed == feedBefore + 1, "the alt's event is in your Feed under the alt, as a friend")
  check(FriendsAndFoesDB.friendTags["Pal Alt"] == "Buddy#1234", "and its BattleTag is remembered")
  S.from("Buddy Pal", 77, "RLY", { origin = "Pal Alt", oclass = "MAGE", olevel = 22, okind = "KILL", oid = "pk1", ago = 900, data = data, alt = "1" }, "ra2")
  check(#rr.feed == feedBefore + 1, "the same event again: once")
  -- not an alt claim: a stranger is still ignored
  S.from("Buddy Pal", 77, "RLY", { origin = "Total Stranger", oclass = "", olevel = "", okind = "LVL", oid = "s1", ago = 60, data = "20", alt = "" }, "ra3")
  check(rr.players["Total Stranger"] == nil, "without alt, a stranger is still ignored")
  -- a name that's already tied to another account can't be claimed
  rr.players["Other Friend"] = { name = "Other Friend", friend = true, k = 0, d = 0, a = 0, lastSeen = time() }
  FriendsAndFoesDB.friendTags["Other Friend"] = "Other#9999"
  S.from("Buddy Pal", 77, "RLY", { origin = "Other Friend", oclass = "", olevel = "", okind = "LVL", oid = "s2", ago = 60, data = "20", alt = "1" }, "ra4")
  check(FriendsAndFoesDB.friendTags["Other Friend"] == "Other#9999" and #rr.feed == feedBefore + 1, "an alt claim on someone else's friend is ignored")
  -- an enemy can't be turned into a friend
  rr.hitlist["Evil Twin"] = { name = "Evil Twin", attacks = 1, kills = 1, suspect = 0, revenge = 0, victims = {} }
  S.from("Buddy Pal", 77, "RLY", { origin = "Evil Twin", oclass = "", olevel = "", okind = "LVL", oid = "s3", ago = 60, data = "20", alt = "1" }, "ra5")
  check(not (rr.players["Evil Twin"] and rr.players["Evil Twin"].friend), "someone on your hitlist can't be claimed as an alt")
  -- your picks still apply to the alt (through Buddy's tag)
  FriendsAndFoesDB.group = { ["Someone#1"] = true }
  ns.Comm.RebuildRoster()
  S.from("Buddy Pal", 77, "RLY", { origin = "Pal Twin", oclass = "", olevel = "", okind = "LVL", oid = "s4", ago = 60, data = "20", alt = "1" }, "ra6")
  check(rr.players["Pal Twin"] == nil, "Buddy not on your alert list: his alts' events aren't taken")
  FriendsAndFoesDB.group = { ["Buddy#1234"] = true }
  ns.Comm.RebuildRoster()
  S.from("Buddy Pal", 77, "RLY", { origin = "Pal Twin", oclass = "", olevel = "", okind = "LVL", oid = "s5", ago = 60, data = "20", alt = "1" }, "ra7")
  check(rr.players["Pal Twin"] and rr.players["Pal Twin"].friend, "Buddy on your list: his alt's events are taken")
  ns.Comm.ClearPicks()

  -- the old per-character list is merged once
  FriendsAndFoesDB.outbox = {}
  FriendsAndFoesCharDB.outbox = { { t = time() - 300, kind = "LVL", id = "old1", f = { level = "7" } }, { t = time() - 200, kind = "LVL", id = "old2", f = { level = "8" } } }
  FriendsAndFoesCharDB.outboxMoved = nil
  ns.Comm.Remember("LVL", "new1", { level = 9 })
  local merged = FriendsAndFoesDB.outbox
  check(#merged == 3 and merged[1].id == "old1" and merged[1].who == ns.me and merged[2].id == "old2" and merged[3].id == "new1"
    and FriendsAndFoesCharDB.outbox == nil, "the old list is merged in time order, tagged with this character, and cleared")
  FriendsAndFoesCharDB.outbox = { { t = time(), kind = "LVL", id = "old3", f = { level = "10" } } }
  ns.Comm.Outbox()
  check(#FriendsAndFoesDB.outbox == 3, "merged only once")
  FriendsAndFoesCharDB.outbox = nil
  for i = 1, 300 do ns.Comm.Remember("LVL", "cap" .. i, { level = i }) end
  check(#ns.Comm.Outbox() == 250, "250 events in all, for all your characters")

  FriendsAndFoesDB.outbox, FriendsAndFoesCharDB.outbox, FriendsAndFoesCharDB.outboxMoved = savedBox, savedOld, savedMoved
  for _, n in ipairs({ "Pal Alt", "Pal Twin", "Other Friend", "Far Away", "Alt Victim" }) do rr.players[n] = nil; FriendsAndFoesDB.friendTags[n] = nil end
  rr.hitlist["Evil Twin"] = nil
  restore()
  check(ns.errors == errs, "no errors with alt catch-up (" .. tostring(ns.lastError) .. ")")
end

-- 2) the hitlist digest
do
  local errs = ns.errors
  local S = SYNC
  local F = { { gid = 77, name = "Buddy Pal", tag = "Buddy#1234" } }
  local restore = S.friends(F)
  ns.Comm.ClearPicks()
  local rr = ns.Data.RealRealm()
  local savedHit, savedAt = rr.hitlist, FriendsAndFoesDB.digestAt
  rr.hitlist = {}
  FriendsAndFoesDB.digestAt = nil
  for i = 1, 60 do
    rr.hitlist["Digest" .. i .. " Foe"] = { name = "Digest" .. i .. " Foe", class = "ROGUE", level = 40 + i % 20, guild = "Some: Guild; Name|x",
      attacks = i, kills = 1, revenge = 0, suspect = 0, victims = { ["Some Victim"] = true }, lastSeen = time() - i * 3600 }
  end
  rr.hitlist["Quiet Qed"] = { name = "Quiet Qed", attacks = 0, kills = 0, suspect = 0, revenge = 0, victims = {}, lastSeen = time() }
  local buddy = ns.Data.Player("Buddy Pal")
  buddy.friend, buddy.version = true, ns.VERSION

  local function meetAgain()
    BNGetNumFriends = function() return 0, 0 end
    ns.Comm.RebuildRoster()
    BNGetNumFriends = function() return #F, #F end
    SENT = {}
    ns.Comm.RebuildRoster()
    S.drain()
  end
  local function digests()
    local out = {}
    for _, m in ipairs(S.sent(77, "HIT")) do if m.f.auto == "1" then out[#out + 1] = m end end
    return out
  end
  meetAgain()
  local d = digests()
  local entries, fits = {}, true
  for _, m in ipairs(d) do
    for raw in m.f.entries:gmatch("[^;]+") do entries[#entries + 1] = raw end
  end
  for _, s in ipairs(SENT) do if #s.payload > 255 then fits = false end end
  check(#d >= 2 and #entries == ns.Comm.DIGEST_MAX and fits, "a friend you meet gets the 40 most active entries in a few small messages: " .. #d .. " / " .. #entries)
  check(entries[1]:find("^Digest1 Foe:ROGUE:") ~= nil and not entries[1]:find("|", 1, true) and select(2, entries[1]:gsub(":", ":")) == 8
    and not table.concat(entries, ";"):find("Quiet", 1, true), "the newest first, one packed form, nothing empty")
  check(FriendsAndFoesDB.digestAt["Buddy#1234"] ~= nil, "remembered per BattleTag")
  meetAgain()
  check(#digests() == 0, "meeting again soon: not sent again")
  FriendsAndFoesDB.digestAt["Buddy#1234"] = time() - 8 * 86400
  meetAgain()
  check(#digests() >= 2, "after a week: sent again")

  -- an older add-on gets none, until its messages show a version that has it
  FriendsAndFoesDB.digestAt = nil
  buddy.version = "0.9.3"
  meetAgain()
  check(#digests() == 0, "a friend on 0.9.3 doesn't get one")
  SENT = {}
  S.from("Buddy Pal", 77, "LVL", { level = 33 }, "dg1", "0.9.3")
  S.drain()
  check(#digests() == 0, "still not after another message from 0.9.3")
  S.from("Buddy Pal", 77, "LVL", { level = 34 }, "dg2")
  S.drain()
  check(#digests() >= 2, "once a message shows 0.9.4, the digest follows")

  -- receiving: merged, no toast, no Feed line
  local feed = #rr.feed
  local t = toasted(function()
    S.from("Buddy Pal", 77, "HIT", { share = "dd1", entries = "Digest Newcomer:HUNTER:59:Their Guild:3:2:0:5:Buddy Pal;Digest1 Foe:ROGUE:50::99:7:1:1:Buddy Pal", auto = "1" }, "dg3")
  end)
  check(not t and #CHAT == 0 and #rr.feed == feed, "a digest: no toast, no chat line, no Feed line")
  check(rr.hitlist["Digest Newcomer"] and rr.hitlist["Digest Newcomer"].kills == 2 and rr.hitlist["Digest1 Foe"].attacks == 99
    and rr.hitlist["Digest Newcomer"].sharedBy == "Buddy Pal", "but merged into your hitlist as a share is")
  -- (a manual share from an older version still gets its Feed line)
  local snd = SOUNDS_PLAYED or 0
  local savedShow = ns.S().show.kill
  ns.S().show.kill, ns.S().sound.enabled = "toast", true
  local t2 = toasted(function()
    S.from("Buddy Pal", 77, "HIT", { share = "dd2", entries = "Digest Second:HUNTER:59:Their Guild:3:2:0:5", auto = "" }, "dg4")
  end)
  check(#rr.feed == feed + 1, "a share without auto still gets its Feed line")
  check(not t2 and #CHAT == 1 and CHAT[1]:find("sharing their hitlist", 1, true) and (SOUNDS_PLAYED or 0) == snd,
    "an old version's manual share: one chat line, no toast, no sound")
  ns.S().show.kill = savedShow

  rr.hitlist, FriendsAndFoesDB.digestAt = savedHit, savedAt
  for name in pairs(rr.players) do if name:find("^Digest") then rr.players[name] = nil end end
  restore()
  check(ns.errors == errs, "no errors with the digest (" .. tostring(ns.lastError) .. ")")
end

-- 3) bounty contracts passed on
do
  local errs = ns.errors
  local S, C = SYNC, ns.Contracts
  local F = { { gid = 77, name = "Buddy Pal", tag = "Buddy#1234" }, { gid = 78, name = "Alice Wonder", tag = "Alice#5678" } }
  local restore = S.friends(F)
  ns.Comm.ClearPicks()
  ns.Comm.RebuildRoster()
  S.drain()
  local rr = ns.Data.RealRealm()
  local savedStore = FriendsAndFoesDB.contracts
  FriendsAndFoesDB.contracts = {}
  local store = FriendsAndFoesDB.contracts
  rr.players["Alice Wonder"] = rr.players["Alice Wonder"] or { name = "Alice Wonder", k = 0, d = 0, a = 0 }
  rr.players["Alice Wonder"].friend, rr.players["Alice Wonder"].version = true, ns.VERSION
  ns.Data.Player("Buddy Pal").version = ns.VERSION
  local function bty(cid, state, poster, extra)
    local f = { cid = cid, target = ns.EncodeUnit({ name = "Bounty Mark", class = "ROGUE", level = 50 }), amount = "50000", state = state,
      killer = "", age = "100", updage = "100", days = "7", blow = "", last = "", poster = poster or "" }
    for k, v in pairs(extra or {}) do f[k] = v end
    return f
  end

  -- Buddy passes on Alice's contract: kept under Alice, not as one received directly
  S.from("Buddy Pal", 77, "BTY", bty("rc1", "open", "Alice Wonder"), "b1")
  local c = store["Alice Wonder/rc1"]
  check(c and c.by == "Alice Wonder" and c.state == "open" and not c.direct and store["Buddy Pal/rc1"] == nil, "a passed-on contract is kept under its poster")
  check(rr.hitlist["Bounty Mark"] ~= nil, "and its target goes on your hitlist")
  -- poster not your friend, or you: ignored
  S.from("Buddy Pal", 77, "BTY", bty("rc2", "open", "Total Stranger"), "b2")
  S.from("Buddy Pal", 77, "BTY", bty("rc3", "open", ns.me), "b3")
  S.from("Buddy Pal", 77, "BTY", bty("rc4", "paid", "Alice Wonder"), "b4")
  check(next(store, next(store)) == nil and store["Total Stranger/rc2"] == nil, "a stranger's, your own, and a 'paid' one passed on are ignored")
  -- Alice's own message is direct, and the contract can't go back
  S.from("Alice Wonder", 78, "BTY", bty("rc1", "done", "", { killer = "Buddy Pal", updage = "10", amount = "60000" }), "b5")
  check(c.direct and c.state == "done" and c.amount == 60000, "from the poster: direct")
  S.from("Buddy Pal", 77, "BTY", bty("rc1", "open", "Alice Wonder", { updage = "5000", amount = "99999" }), "b6")
  check(c.state == "done" and c.amount == 60000, "an older copy passed on can't roll it back")
  -- a second contract only ever passed on (never direct) isn't passed on again
  S.from("Buddy Pal", 77, "BTY", bty("rc7", "open", "Alice Wonder"), "b7")
  check(store["Alice Wonder/rc7"] ~= nil, "(another passed-on one)")

  SENT = {}
  check(C.SendRelayed("Buddy Pal") == 1, "passing on: only the one you got directly")
  S.drain()
  local out = S.sent(77, "BTY")
  check(#out == 1 and out[1].f.poster == "Alice Wonder" and out[1].f.cid == "rc1" and out[1].f.state == "done", "to Buddy, naming Alice as the poster")
  check(C.SendRelayed("Alice Wonder") == 0, "never to the poster")
  -- limits and the version check
  for i = 1, 15 do
    store["Alice Wonder/lim" .. i] = { id = "lim" .. i, by = "Alice Wonder", target = "Lim" .. i .. " Mark", amount = 1000, state = "open", t = time(), upd = time() + i, days = 7, direct = true }
  end
  SENT = {}
  check(C.SendRelayed("Buddy Pal") == C.RELAY_MAX, "at most " .. C.RELAY_MAX .. " are passed on")
  S.drain()
  local fits = true
  for _, s in ipairs(SENT) do if #s.payload > 255 then fits = false end end
  check(fits, "and they fit")
  ns.Data.Player("Buddy Pal").version = "0.9.3"
  SENT = {}
  C.Greet({ "Buddy Pal" })
  S.drain()
  local relayed = 0
  for _, m in ipairs(S.sent(77, "BTY")) do if m.f.poster ~= "" then relayed = relayed + 1 end end
  check(relayed == 0, "a friend on 0.9.3 gets none")
  ns.Data.Player("Buddy Pal").version = ns.VERSION
  SENT = {}
  C.Greet({ "Buddy Pal" })
  S.drain()
  relayed = 0
  for _, m in ipairs(S.sent(77, "BTY")) do if m.f.poster ~= "" then relayed = relayed + 1 end end
  check(relayed == C.RELAY_MAX, "greeting a friend on 0.9.4 passes them on")

  FriendsAndFoesDB.contracts = savedStore
  rr.hitlist["Bounty Mark"], rr.players["Bounty Mark"] = nil, nil
  for i = 1, 15 do rr.hitlist["Lim" .. i .. " Mark"] = nil end
  restore()
  check(ns.errors == errs, "no errors passing on contracts (" .. tostring(ns.lastError) .. ")")
end

-- 4) profiles passed on
do
  local errs = ns.errors
  local S, P = SYNC, ns.Profile
  local F = { { gid = 77, name = "Buddy Pal", tag = "Buddy#1234" }, { gid = 78, name = "Alice Wonder", tag = "Alice#5678" } }
  local restore = S.friends(F)
  ns.Comm.ClearPicks()
  ns.Comm.RebuildRoster()
  S.drain()
  local rr = ns.Data.RealRealm()
  local function friend(name, rl, t)
    local p = rr.players[name] or { name = name, k = 0, d = 0, a = 0 }
    rr.players[name] = p
    p.friend, p.lastSeen, p.faction = true, time(), "Horde"
    P.Apply(p, { k = "12", d = "3", wanted = "", zone = "Old Zone", status = "", t = t or tostring(time() - 3600), bt = "40", btw = "10", bwk = "2", rl = rl })
    return p
  end
  check(P.Fields().rl == "1", "your own profile says friends may pass it on")
  ns.S().share.relay = false
  check(P.Fields().rl == "", "and not when you've switched that off")
  ns.S().share.relay = true
  local carol = friend("Carol Ghost", "1")
  local dora = friend("Dora Dark", "")
  local erin = friend("Erin Elf", "1", "")
  local alice = friend("Alice Wonder", "1")
  check(carol.relayOk and not dora.relayOk and not erin.relayOk, "kept to pass on only when they allow it and say when the numbers are from")
  local list = P.RelayList("Buddy Pal")
  check(#list == 1 and list[1].name == "Carol Ghost", "passed on: Carol only (not Dora, Erin, nor Alice who is online)")

  rr.players["Buddy Pal"].version = ns.VERSION
  SENT = {}
  P.Greet({ "Buddy Pal" })
  S.drain()
  local prl = S.sent(77, "PRL")
  check(#prl == 1 and prl[1].f.origin == "Carol Ghost" and prl[1].f.k == "12" and prl[1].f.d == "3" and prl[1].f.bt == "40"
    and tonumber(prl[1].f.t) == carol.statAt, "greeting Buddy: Carol's numbers go too")
  rr.players["Buddy Pal"].version = "0.9.3"
  SENT = {}
  P.Greet({ "Buddy Pal" })
  S.drain()
  check(#S.sent(77, "PRL") == 0, "not to an add-on without it")
  rr.players["Buddy Pal"].version = ns.VERSION
  for i = 1, 15 do friend("Many" .. i .. " Friend", "1", tostring(time() - i * 60)) end
  check(#P.RelayList("Buddy Pal") == P.PRL_MAX and P.RelayList("Buddy Pal")[1].name == "Many1 Friend", "at most " .. P.PRL_MAX .. ", the freshest first")
  SENT = {}
  P.Greet({ "Buddy Pal" })
  S.drain()
  check(#S.sent(77, "PRL") == P.PRL_MAX, "that many are sent")
  for i = 1, 15 do rr.players["Many" .. i .. " Friend"] = nil end

  -- receiving
  local now = time()
  S.from("Buddy Pal", 77, "PRL", { origin = "Carol Ghost", k = "20", d = "4", t = tostring(now - 60), bt = "50", btw = "", bwk = "" }, "pl1")
  check(carol.sk == 20 and carol.sd == 4 and carol.sbt == 50 and math.abs(carol.statAt - (now - 60)) <= 2, "newer numbers are applied")
  check(carol.zone == "Old Zone" and not carol.relayOk, "never a zone, and not passed on again")
  S.from("Buddy Pal", 77, "PRL", { origin = "Carol Ghost", k = "99", d = "9", t = tostring(now - 7200), bt = "", btw = "", bwk = "" }, "pl2")
  check(carol.sk == 20, "older numbers are ignored")
  S.from("Buddy Pal", 77, "PRL", { origin = "Alice Wonder", k = "99", d = "9", t = tostring(now - 5), bt = "", btw = "", bwk = "" }, "pl3")
  check(alice.sk == 12, "a friend who is online speaks for themselves")
  S.from("Buddy Pal", 77, "PRL", { origin = "Total Stranger", k = "99", d = "9", t = tostring(now - 5), bt = "", btw = "", bwk = "" }, "pl4")
  S.from("Buddy Pal", 77, "PRL", { origin = ns.me, k = "99", d = "9", t = tostring(now - 5), bt = "", btw = "", bwk = "" }, "pl5")
  S.from("Buddy Pal", 77, "PRL", { origin = "Dora Dark", k = "x", d = "9", t = tostring(now - 5), bt = "", btw = "", bwk = "" }, "pl6")
  check(rr.players["Total Stranger"] == nil and dora.sk == 12, "strangers, yourself and broken numbers are ignored")
  check(#P.RelayList("Buddy Pal") == 0, "(Carol is not passed on again)")
  -- a profile of their own, directly, makes it passable again
  P.Apply(carol, { k = "21", d = "4", wanted = "", zone = "", status = "", t = tostring(now), bt = "", btw = "", bwk = "", rl = "1" })
  check(P.RelayList("Buddy Pal")[1].name == "Carol Ghost", "her own next profile makes it passable again")

  for _, n in ipairs({ "Carol Ghost", "Dora Dark", "Erin Elf" }) do rr.players[n] = nil end
  rr.players["Alice Wonder"].relayOk = nil
  restore()
  check(ns.errors == errs, "no errors passing on profiles (" .. tostring(ns.lastError) .. ")")
end

-- 5) gaps while both are online
do
  local errs = ns.errors
  local S, C = SYNC, ns.Comm
  local ALL = { { gid = 291, name = "Gap Pal", tag = "Gap#1" }, { gid = 292, name = "Gap Quiet", tag = "Quiet#2" } }
  local F = { ALL[1], ALL[2] }
  local restore = S.friends(F)
  C.ClearPicks()
  local function setOnline(on)
    for i = #F, 1, -1 do F[i] = nil end
    if on then for i, f in ipairs(ALL) do F[i] = f end end
  end
  local function cycle(wait)
    setOnline(false)
    C.RebuildRoster()
    ADVANCE(wait)
    setOnline(true)
    SENT = {}
    C.RebuildRoster()
    S.drain()
  end
  C.RebuildRoster()
  S.drain()
  C.SetAwayFrom(time() - 7200)
  cycle(5)
  local first = S.sent(291, "REQ")
  check(#first == 1 and math.abs(tonumber(first[1].f.window) - 7200) <= 5, "back after a short while, first time this session: asked as usual")
  -- Gap Pal sends an event that happened 10 minutes ago; Gap Quiet sends nothing
  S.from("Gap Pal", 291, "LVL", { level = 33, ago = 600 }, "gp1")
  S.drain()
  check(C.LastEventFrom("Gap Pal") and math.abs(C.LastEventFrom("Gap Pal") - (time() - 600)) <= 2 and C.LastEventFrom("Gap Quiet") == nil,
    "the newest event time is kept per friend")
  S.from("Gap Pal", 291, "LVL", { level = 34, ago = 3000 }, "gp2")
  check(math.abs(C.LastEventFrom("Gap Pal") - (time() - 600)) <= 2, "an older one doesn't replace it")
  cycle(60)
  check(#S.sent(291, "REQ") == 0, "gone for a minute: not asked")
  cycle(130)
  local back = S.sent(291, "REQ")
  check(#back == 1 and math.abs(tonumber(back[1].f.window) - 605) <= 3, "gone for two minutes: asked for what came after the newest event: " .. tostring(back[1] and back[1].f.window))
  check(#S.sent(292, "REQ") == 0, "a friend with no event from them yet: not asked again (as before)")

  -- once an hour: only friends who sent nothing for an hour, and who we have an event time for
  SENT = {}
  check(C.AskSilent() == 0, "everyone was heard from lately: nobody asked")
  ADVANCE(3700)
  SENT = {}
  check(C.AskSilent() == 1, "an hour of silence: Gap Pal is asked")
  S.drain()
  local silent = S.sent(291, "REQ")
  check(#silent >= 1 and tonumber(silent[1].f.window) >= 600 and #S.sent(292, "REQ") == 0, "with the small window; Gap Quiet (no event time) is left alone")
  S.from("Gap Pal", 291, "PRO", { k = "1", d = "1", wanted = "", zone = "", status = "", t = "", bt = "", btw = "", bwk = "", rl = "" }, "gp3")
  ADVANCE(100)
  SENT = {}
  RUN_TICKERS(1)
  S.drain()
  check(#S.sent(291, "REQ") == 0, "the hourly timer: he sent something a minute ago, so nothing")
  ADVANCE(3700)
  SENT = {}
  RUN_TICKERS(1)
  S.drain()
  check(#S.sent(291, "REQ") == 1, "the hourly timer: an hour of silence, asked: " .. #S.sent(291, "REQ"))

  restore()
  local rr = ns.Data.RealRealm()
  rr.players["Gap Pal"], rr.players["Gap Quiet"] = nil, nil
  check(ns.errors == errs, "no errors filling gaps (" .. tostring(ns.lastError) .. ")")
end
-- the digest only brings enemies who hurt the sender, you, or a friend you share
do
  local errs = ns.errors
  local S = SYNC
  local F = { { gid = 77, name = "Buddy Pal", tag = "Buddy#1234" } }
  local restore = S.friends(F)
  ns.Comm.ClearPicks()
  local rr = ns.Data.RealRealm()
  local savedHit, savedAt = rr.hitlist, FriendsAndFoesDB.digestAt
  rr.hitlist = {}
  FriendsAndFoesDB.digestAt = nil
  local buddy = ns.Data.Player("Buddy Pal")
  buddy.friend, buddy.version = true, ns.VERSION
  ns.Data.Player("Mutual Friend").friend = true
  local function share(entries, auto, id)
    S.from("Buddy Pal", 77, "HIT", { share = id, entries = entries, auto = auto }, id)
  end
  local function row(name, who) return name .. ":ROGUE:50:Gx:4:2:0:3" .. (who and (":" .. who) or "") end

  share(table.concat({
    row("Fw Sender", "Buddy Pal,Some Stranger"),
    row("Fw Mine", "Some Stranger," .. ns.me),
    row("Fw Common", "Mutual Friend"),
    row("Fw Stranger", "Some Stranger,Other Stranger"),
    row("Fw Bare"),
  }, ";"), "1", "fw1")
  check(rr.hitlist["Fw Sender"] and rr.hitlist["Fw Mine"] and rr.hitlist["Fw Common"], "kept: hurt the sender, you, or a friend you share")
  check(not rr.hitlist["Fw Stranger"], "dropped: only hurt strangers")
  check(not rr.hitlist["Fw Bare"], "dropped: an automatic entry without the victims field")
  check(rr.hitlist["Fw Sender"].sharedBy == "Buddy Pal" and rr.hitlist["Fw Sender"].kills == 2 and rr.hitlist["Fw Sender"].attacks == 4, "kept ones merge as before")
  check(rr.hitlist["Fw Sender"].hitWho["Buddy Pal"] and not rr.hitlist["Fw Sender"].hitWho["Some Stranger"]
    and rr.hitlist["Fw Mine"].hitWho[ns.me] and not rr.hitlist["Fw Mine"].hitWho["Some Stranger"]
    and rr.hitlist["Fw Common"].hitWho["Mutual Friend"], "only the names that passed are kept")

  -- an old manual share (no auto) merges as it always did
  share(row("Fw Old"), "", "fw2")
  check(rr.hitlist["Fw Old"] and rr.hitlist["Fw Old"].kills == 2, "a manual share without the field still merges")

  -- an attack records who was hit (a friend's, and your own)
  S.from("Buddy Pal", 77, "ATK", { enc = "fwa1", zone = "Duskwood", attackers = "Fw Attacker:ROGUE:60:" }, "fwa1")
  local ha = rr.hitlist["Fw Attacker"]
  check(ha and ha.hitWho and ha.hitWho["Buddy Pal"], "an attack records who was attacked")
  for i = 1, 14 do S.from("Buddy Pal", 77, "ATK", { enc = "fwb" .. i, zone = "Duskwood", attackers = "Fw Attacker:ROGUE:60:" }, "fwb" .. i) end
  for i = 1, 14 do ns.Events.NoteWho(ha, "Victim" .. i) end
  local n = 0
  for _ in pairs(ha.hitWho) do n = n + 1 end
  check(n <= 10, "hitWho is capped: " .. n)

  -- the sender: entries with no victims aren't sent; names are packed (you first), and it all fits
  FriendsAndFoesDB.digestAt = nil
  rr.hitlist = {}
  for i = 1, 45 do
    rr.hitlist["Longname" .. i .. " Verylongsurnamehere"] = { name = "Longname" .. i .. " Verylongsurnamehere", class = "ROGUE", level = 60,
      guild = "A Rather Long Guild Name Indeed", attacks = i, kills = 1, revenge = 0, suspect = 0, lastSeen = time() - i * 60,
      victims = { ["Aaaaaaaaaaaa Bbbbbbbbbbbbb"] = true }, kv = { ["Aaaaaaaaaaaa Bbbbbbbbbbbbb"] = 3, ["Cc, Dd:x"] = 1 },
      hitWho = { [ns.me] = 5, ["Eeeeeeeeeeee Ffffffffffff"] = 9, ["Gggggggggggg Hhhhhhhhhhhh"] = 8 } }
  end
  rr.hitlist["Fw Nobody"] = { name = "Fw Nobody", attacks = 5, kills = 0, suspect = 0, revenge = 0, victims = {}, lastSeen = time() }
  local list = ns.Comm.DigestList()
  local hasNobody = false
  for _, h in ipairs(list) do if h.name == "Fw Nobody" then hasNobody = true end end
  check(#list == ns.Comm.DIGEST_MAX and not hasNobody, "an entry with no victims isn't in the digest")
  buddy.version = ns.VERSION
  BNGetNumFriends = function() return 0, 0 end
  ns.Comm.RebuildRoster()
  BNGetNumFriends = function() return #F, #F end
  SENT = {}
  ns.Comm.RebuildRoster()
  S.drain()
  local fits, got = true, nil
  for _, s in ipairs(SENT) do if #s.payload > 255 then fits = false end end
  for _, m in ipairs(S.sent(77, "HIT")) do
    if m.f.auto == "1" and not got then got = m.f.entries:match("[^;]+") end
  end
  local who = got and got:match("^[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:[^:]*:(.*)$")
  check(fits and who and who:match("^" .. ns.me) and select(2, who:gsub(",", ",")) == 2 and not who:find("[:;|\t]"),
    "long names: packed under 255 bytes, you first, 3 names: " .. tostring(who))

  rr.hitlist, FriendsAndFoesDB.digestAt = savedHit, savedAt
  for name in pairs(rr.players) do if name:find("^Fw ") or name == "Mutual Friend" then rr.players[name] = nil end end
  restore()
  check(ns.errors == errs, "no errors with the filtered digest (" .. tostring(ns.lastError) .. ")")
end

-- how long players stay on the hitlist: three settings (attackers 14 days, killers forever by default)
do
  local day = 86400
  local errs = ns.errors
  local s = ns.S()
  local saved = { s.forgetAttackers, s.forgetKilledOnce, s.forgetKilledMore }
  local savedContracts = FriendsAndFoesDB.contracts
  FriendsAndFoesDB.contracts = {}
  local function put(name, kills, attacks, days)
    real.hitlist[name] = { name = name, kills = kills, attacks = attacks, victims = {}, lastSeen = time() - days * day }
  end
  local function clear()
    for _, n in ipairs({ "Ftest Atk13", "Ftest Atk15", "Ftest One89", "Ftest One91", "Ftest Rep364", "Ftest Rep366", "Ftest Keeper", "Ftest Old" }) do real.hitlist[n] = nil end
  end
  local function fill()
    put("Ftest Atk13", 0, 2, 13); put("Ftest Atk15", 0, 2, 15)
    put("Ftest One89", 1, 0, 89); put("Ftest One91", 1, 0, 91)
    put("Ftest Rep364", 2, 0, 364); put("Ftest Rep366", 5, 0, 366)
  end
  local function has(n) return real.hitlist[n] ~= nil end
  local function set(a, o, m) s.forgetAttackers, s.forgetKilledOnce, s.forgetKilledMore = a, o, m end
  -- defaults: attackers 14 days, killers forever
  set(nil, nil, nil)
  fill()
  check(ns.Data.CountForget(FriendsAndFoesDB) == 1, "default count: " .. ns.Data.CountForget(FriendsAndFoesDB))
  ns.Data.ForgetOld(FriendsAndFoesDB)
  check(has("Ftest Atk13") and not has("Ftest Atk15"), "attacker: kept at 13 days, removed at 15 (default)")
  check(has("Ftest One91") and has("Ftest Rep366"), "killers are never removed by default")
  clear()
  -- each setting is honoured on its own
  set(14, 90, 365)
  fill()
  ns.Data.ForgetOld(FriendsAndFoesDB)
  check(has("Ftest One89") and not has("Ftest One91"), "one-time killers at 90: kept at 89, removed at 91")
  check(has("Ftest Rep364") and not has("Ftest Rep366"), "repeat killers at 365: kept at 364, removed at 366")
  check(has("Ftest Atk13") and not has("Ftest Atk15"), "attackers unaffected by the killer settings")
  clear()
  -- counting with a pending value changes only that kind
  fill()
  set(0, 0, 0)
  check(ns.Data.CountForget(FriendsAndFoesDB, "forgetKilledOnce", 90) == 1, "count with a pending one-time killer value")
  check(ns.Data.CountForget(FriendsAndFoesDB, "forgetAttackers", 7) == 2, "count with a pending attacker value")
  check(ns.Data.CountForget(FriendsAndFoesDB, "forgetKilledMore", 0) == 0, "count with Forever")
  clear()
  -- Forever keeps everyone
  set(0, 0, 0)
  put("Ftest Atk15", 0, 2, 5000)
  check(ns.Data.ForgetOld(FriendsAndFoesDB) == 0 and has("Ftest Atk15"), "Forever keeps all")
  clear()
  -- an open contract keeps an old attacker; once it is closed they can go
  set(14, 0, 0)
  put("Ftest Keeper", 0, 1, 200)
  FriendsAndFoesDB.contracts["Pal/1"] = { id = "1", by = "Pal", target = "Ftest Keeper", amount = 100, state = "open", t = time() }
  ns.Data.ForgetOld(FriendsAndFoesDB)
  check(has("Ftest Keeper"), "an open bounty keeps an old attacker")
  FriendsAndFoesDB.contracts["Pal/1"].state = "cancelled"
  ns.Data.ForgetOld(FriendsAndFoesDB)
  check(not has("Ftest Keeper"), "no open bounty: forgotten")
  -- seeing them again resets the clock
  put("Ftest Atk15", 0, 2, 15)
  real.hitlist["Ftest Atk15"].lastSeen = time()
  ns.Data.ForgetOld(FriendsAndFoesDB)
  check(has("Ftest Atk15"), "seen again: kept")
  clear()
  -- grey-out after 30 days
  check(not ns.Data.IsStale({ lastSeen = time() - 29 * day }) and ns.Data.IsStale({ lastSeen = time() - 31 * day }), "grey after 30 days unseen")
  -- upgrade step 14: the old mode becomes three numbers and goes away
  local function upgrade(mode)
    s.forget, s.forgetAttackers, s.forgetKilledOnce, s.forgetKilledMore = mode, 99, 99, 99
    FriendsAndFoesDB.dataVersion = #ns.Saved.STEPS - 1
    ns.Saved.Upgrade(FriendsAndFoesDB)
  end
  upgrade("never")
  check(s.forget == nil and s.forgetAttackers == 0 and s.forgetKilledOnce == 0 and s.forgetKilledMore == 0, "upgrade: never -> all forever")
  upgrade("double")
  check(s.forget == nil and s.forgetAttackers == 28 and s.forgetKilledOnce == 0 and s.forgetKilledMore == 0, "upgrade: double -> attackers 28 days")
  upgrade("normal")
  check(s.forget == nil and s.forgetAttackers == 14 and s.forgetKilledOnce == 0 and s.forgetKilledMore == 0, "upgrade: normal -> the defaults")
  s.forget = nil
  s.forgetAttackers, s.forgetKilledOnce, s.forgetKilledMore = 7, 30, 90
  FriendsAndFoesDB.dataVersion = #ns.Saved.STEPS - 1
  ns.Saved.Upgrade(FriendsAndFoesDB)
  check(s.forgetAttackers == 7 and s.forgetKilledOnce == 30 and s.forgetKilledMore == 90, "upgrade: new settings are left alone")
  -- the login run says so once when it removed players; silent when nothing goes
  do
    local said, oldChat = {}, ns.Toast.Chat
    ns.Toast.Chat = function(text) said[#said + 1] = ns.Plain(text) end
    set(14, 90, 0)
    put("Ftest Atk15", 0, 2, 20); put("Ftest One91", 1, 0, 100)
    ns.Data.ForgetAtLogin()
    check(#said == 1 and said[1]:find("2", 1, true), "login forgetting: one line with the count: " .. tostring(said[1]))
    ns.Data.ForgetAtLogin()
    check(#said == 1, "nothing removed: nothing printed")
    ns.Toast.Chat = oldChat
    clear()
  end
  s.forgetAttackers, s.forgetKilledOnce, s.forgetKilledMore = saved[1], saved[2], saved[3]
  FriendsAndFoesDB.contracts = savedContracts
  check(ns.errors == errs, "no errors in forgetting (" .. tostring(ns.lastError) .. ")")
end
RUN_TICKERS(80)

-- the Bounty board: several players who got the kill complete a bounty together
do
  local errs = ns.errors
  local C = ns.Contracts
  local rr = ns.Data.RealRealm()
  local saved = FriendsAndFoesDB.contracts
  FriendsAndFoesDB.contracts = {}
  local showWas = ns.S().show.contract
  ns.S().show.contract = "chat"
  local function bty(fields, id) FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("BTY", fields, id), "WHISPER", 77) end
  local function chatHas(text)
    for _, l in ipairs(CHAT) do if l:find(text, 1, true) then return true end end
    return false
  end
  local function has(list, name)
    for _, n in ipairs(list or {}) do if n == name then return true end end
    return false
  end
  local t0 = time()

  -- two friends kill the target within a minute: both share it
  local c = C.Post({ name = "Share Foe", class = "ROGUE", level = 60 }, 100000, 3)
  CHAT = {}
  ns.eventTime = t0
  C.OnKill("Buddy Pal", "Share Foe")
  check(c.state == "done" and #c.killers == 1 and chatHas("fulfilled your bounty"), "the first kill: done, you are told to pay")
  CHAT = {}
  ns.eventTime = t0 + 20
  C.OnKill("Alice Wonder", "Share Foe")
  check(c.state == "done" and #c.killers == 2 and has(c.killers, "Buddy Pal") and has(c.killers, "Alice Wonder")
    and c.killer == "Buddy Pal", "a second kill within 60 s joins: both killers, the lead stays")
  check(C.ShareOf(c) == 50000, "the gold is shared equally: half each")
  check(chatHas("was in on the kill too") and not chatHas("fulfilled your bounty"), "the poster gets one more chat line for the late killer")
  C.OnKill("Alice Wonder", "Share Foe")
  check(#c.killers == 2, "the same killer twice counts once")
  ns.eventTime = t0 + 120
  C.OnKill("Third Wheel", "Share Foe")
  check(#c.killers == 2 and not has(c.killers, "Third Wheel"), "a kill 2 minutes later doesn't join")
  ns.eventTime = nil

  -- the toasts
  ns.S().show.contract = "toast"
  local pushed = {}
  local push = ns.Toast.Push
  ns.Toast.Push = function(spec) pushed[#pushed + 1] = spec end
  C.ToastDone(c)
  local theirs = { id = "tt1", by = "Cara Dune", target = "Toast Foe", amount = 90000, state = "done", killer = ns.me, killers = { ns.me, "Alice Wonder" }, doneAt = t0 }
  C.ToastDone(theirs)
  theirs.killers, theirs.killer = { "Alice Wonder", "Buddy Pal" }, "Alice Wonder"
  C.ToastDone(theirs)
  ns.Toast.Push = push
  ns.S().show.contract = "chat"
  local p1, p2, p3 = ns.Plain(pushed[1].title), ns.Plain(pushed[2].title), ns.Plain(pushed[3].title)
  check(p1:find("Buddy Pal and Alice Wonder fulfilled your bounty", 1, true) and ns.Plain(pushed[1].text):find("Pay each of them", 1, true),
    "poster's toast: both names, pay each: " .. p1)
  check(p2:find("You and Alice Wonder fulfilled Cara Dune's bounty", 1, true) and ns.Plain(pushed[2].text):find("each, promised", 1, true),
    "a killer's toast: you and the others, the share each: " .. p2 .. " / " .. ns.Plain(pushed[2].text))
  check(p3:find("Alice Wonder and Buddy Pal fulfilled Cara Dune's bounty", 1, true), "anyone else's: the names: " .. p3)

  -- the confirm-paid dialog lists everyone and the share
  local asked
  local confirm = ns.UI.Confirm
  ns.UI.Confirm = function(text) asked = text end
  local row = setmetatable({ key = ns.me .. "/" .. c.id, name = c.target }, { __index = c })
  ns.UI.ContractAction(row)
  ns.UI.Confirm = confirm
  check(asked and ns.Plain(asked):find("Buddy Pal and Alice Wonder", 1, true) and ns.Plain(asked):find("each", 1, true),
    "confirm paid lists everyone and the share each: " .. tostring(asked and ns.Plain(asked)))

  -- marking it paid: sent once with both, and each killer collects their share
  SENT = {}
  local k = ns.me .. "/" .. c.id
  check(C.MarkPaid(k) and c.state == "paid", "the poster marks it paid once for everyone")
  RUN_TICKERS(40)
  local seen
  for _, s in ipairs(SENT) do
    local m = s.payload:find("^3\tBTY\t") and ns.Comm.Decode(s.payload)
    if m and m.f.state == "paid" then seen = m end
  end
  check(seen and seen.f.killers == "Buddy Pal,Alice Wonder" and seen.f.killer == "Buddy Pal", "the BTY killers field round-trips: " .. tostring(seen and seen.f.killers))
  check(C.EarnedBy("Buddy Pal") == 50000 and C.EarnedBy("Alice Wonder") == 50000 and C.EarnedBy("Third Wheel") == 0,
    "paid: each killer's Bounties column counts their share")
  C.OnKill("Late Comer", "Share Foe")
  check(#c.killers == 2 and c.state == "paid", "a paid bounty doesn't change")
  c.doneAt, c.upd = t0 - 60 * 86400, t0 - 60 * 86400
  local cell
  for _, r in ipairs(C.List()) do if r.name == "Share Foe" then cell = r end end
  local closedCell
  for _, col in ipairs(ns.UI.TabColumns("contracts")) do
    if col[1] == ns.L.COL_CLOSED_BY then closedCell = ns.Plain(col[3](cell)) end
  end
  check(closedCell == "Buddy Pal, Alice Wonder", "the board's Closed by shows everyone: " .. tostring(closedCell))
  c.killers = { "Aa Bb", "Cc Dd", "Ee Ff", "Gg Hh", "Ii Jj" }
  c.killer = "Aa Bb"
  for _, r in ipairs(C.List()) do if r.name == "Share Foe" then cell = r end end
  for _, col in ipairs(ns.UI.TabColumns("contracts")) do
    if col[1] == ns.L.COL_CLOSED_BY then closedCell = ns.Plain(col[3](cell)) end
  end
  check(closedCell:find("+3", 1, true) and not closedCell:find("Gg Hh", 1, true), "a long list is cut with +N: " .. closedCell)

  -- the poster among the killers doesn't owe themselves
  local own = C.Post({ name = "Own Foe", class = "MAGE", level = 60 }, 80000, 3)
  ns.eventTime = t0
  C.OnKill("Buddy Pal", "Own Foe")
  ns.eventTime = t0 + 10
  C.OnKill(ns.me, "Own Foe")
  ns.eventTime = nil
  check(own.state == "done" and #own.killers == 2 and #C.Payees(own) == 1 and C.Payees(own)[1] == "Buddy Pal" and C.ShareOf(own) == 40000,
    "the poster among the killers: only the other is owed, half the gold")
  C.MarkPaid(ns.me .. "/" .. own.id)
  check(C.EarnedBy("Buddy Pal") == 40000 and C.EarnedBy(ns.me) == 0, "the poster's own share isn't counted as earned")
  -- the poster kills first, a friend within 60 s (no killing blow known): they join and are owed
  local pf = C.Post({ name = "Pf Foe", class = "MAGE", level = 60 }, 60000, 3)
  ns.eventTime = t0
  C.OnKill(ns.me, "Pf Foe")
  check(pf.state == "paid" and #C.Payees(pf) == 0, "(the poster got them first: closed)")
  CHAT = {}
  ns.eventTime = t0 + 30
  C.OnKill("Buddy Pal", "Pf Foe")
  check(pf.state == "done" and C.Payees(pf)[1] == "Buddy Pal" and C.ShareOf(pf) == 30000 and chatHas("fulfilled your bounty"),
    "a friend within 60 s of the poster's own kill joins: done, they are owed half, the poster is told to pay")
  ns.eventTime = t0 + 200
  C.OnKill("Late Friend", "Pf Foe")
  check(#pf.killers == 2, "a friend 2 minutes after the poster's kill doesn't join")
  local pf2 = C.Post({ name = "Pf Two", class = "MAGE", level = 60 }, 60000, 3)
  ns.eventTime = t0
  C.OnKill(ns.me, "Pf Two")
  ns.eventTime = t0 + 5
  C.OnKill("Alice Wonder", "Pf Two")
  C.MarkPaid(ns.me .. "/" .. pf2.id)
  ns.eventTime = t0 + 10
  C.OnKill("Buddy Pal", "Pf Two")
  check(pf2.state == "paid" and #pf2.killers == 2, "once the poster marked it paid, no one joins")
  ns.eventTime = nil
  local solo = C.Post({ name = "Solo Foe", class = "MAGE", level = 60 }, 80000, 3)
  C.OnKill(ns.me, "Solo Foe")
  check(solo.state == "paid" and #C.Payees(solo) == 0, "the poster alone: closed with nothing to pay")

  -- a friend's bounty: your kill, then the poster's list merges with yours (union, never fewer, at most 5)
  bty({ cid = "m1", target = "Merge Foe:MAGE:50:", amount = 9000, state = "open", killer = "", age = 60, updage = 60, days = 5 }, "mg1")
  local m = FriendsAndFoesDB.contracts["Buddy Pal/m1"]
  C.OnKill(ns.me, "Merge Foe")
  check(m.state == "done" and #m.killers == 1 and m.killers[1] == ns.me, "(you got them)")
  bty({ cid = "m1", target = "Merge Foe:MAGE:50:", amount = 9000, state = "done", killer = "Alice Wonder", killers = "Alice Wonder,Cara Dune", age = 60, updage = 0, days = 5 }, "mg2")
  check(#m.killers == 3 and m.killers[1] == "Alice Wonder" and m.killers[2] == "Cara Dune" and m.killers[3] == ns.me,
    "the poster's list and yours are merged, theirs first: " .. table.concat(m.killers, ","))
  check(C.ShareOf(m) == 3000, "(a third each)")
  bty({ cid = "m1", target = "Merge Foe:MAGE:50:", amount = 9000, state = "done", killer = "Alice Wonder", killers = "Cara Dune", age = 60, updage = 0, days = 5 }, "mg3")
  check(#m.killers == 3, "a shorter list never shrinks yours")
  bty({ cid = "m1", target = "Merge Foe:MAGE:50:", amount = 9000, state = "done", killer = "Aa Bb", killers = "Aa Bb,Cc Dd,Ee Ff,Gg Hh,Ii Jj,Kk Ll", age = 60, updage = 0, days = 5 }, "mg4")
  check(#m.killers == 5 and m.killers[1] == "Aa Bb", "at most 5 killers, the poster's first")
  bty({ cid = "m1", target = "Merge Foe:MAGE:50:", amount = 9000, state = "paid", killer = "Aa Bb", killers = "Aa Bb,Cc Dd", age = 60, updage = 0, days = 5 }, "mg5")
  check(m.state == "paid" and #m.killers == 5, "(paid by the poster)")

  -- an older client: no killers field, only the one killer
  bty({ cid = "m2", target = "Old Foe:MAGE:50:", amount = 700, state = "done", killer = "Alice Wonder", age = 60, updage = 5, days = 5 }, "mg6")
  local old = FriendsAndFoesDB.contracts["Buddy Pal/m2"]
  check(old and old.state == "done" and old.killer == "Alice Wonder" and #old.killers == 1 and old.killers[1] == "Alice Wonder" and C.ShareOf(old) == 700,
    "an old-format message (no killers field) still works")
  local legacy = { by = "Buddy Pal", state = "paid", killer = "Alice Wonder", amount = 700 }
  FriendsAndFoesDB.contracts["Buddy Pal/legacy"] = legacy
  check(C.EarnedBy("Alice Wonder") == 700 + 30000 and C.ShareOf(legacy) == 700, "a saved contract without a list: the one killer, the full amount")

  -- 5 long names still fit in one message
  local longc = C.Post({ name = "Long Foe", class = "MAGE", level = 60 }, 500000, 3)
  longc.killers = { "Abcdefghijkl Mnopqrstuvwx", "Bbbbbbbbbbbb Nnnnnnnnnnnn", "Cccccccccccc Oooooooooooo", "Dddddddddddd Pppppppppppp", "Eeeeeeeeeeee Qqqqqqqqqqqq" }
  longc.killer, longc.state, longc.doneAt, longc.guild = longc.killers[1], "done", t0, "Abcdefghijklmnopqrstuvwx"
  RUN_TICKERS(80)
  SENT = {}
  C.MarkPaid(ns.me .. "/" .. longc.id)
  RUN_TICKERS(80)
  local longMsg
  for _, s in ipairs(SENT) do
    if s.payload:find("^3\tBTY\t") and s.payload:find("Long Foe", 1, true) then longMsg = s.payload end
  end
  local back = longMsg and ns.Comm.Decode(longMsg)
  check(longMsg and #longMsg <= 255 and back and back.f.killers:find("^Abcdefghijkl Mnopqrstuvwx"), "a bounty with 5 long names fits in 255 bytes: " .. tostring(longMsg and #longMsg))

  for _, name in ipairs({ "Share Foe", "Own Foe", "Pf Foe", "Pf Two", "Solo Foe", "Merge Foe", "Old Foe", "Long Foe" }) do
    rr.hitlist[name], rr.players[name] = nil, nil
  end
  FriendsAndFoesDB.contracts = saved
  ns.S().show.contract = showWas
  ns.eventTime = nil
  check(ns.errors == errs, "no errors in shared bounties (" .. tostring(ns.lastError) .. ")")
end
RUN_TICKERS(80)

-- assists by support (AST): you healed or buffed a friend who got the kill
do
  local errs = ns.errors
  local B, C, P = ns.Bounty, ns.Contracts, ns.PvP
  local rr = ns.Data.RealRealm()
  local function has(list, name)
    for _, n in ipairs(list or {}) do if n == name then return true end end
    return false
  end
  local oEmit = ns.Events.Emit
  local asts = {}
  ns.Events.Emit = function(kind, f) if kind == "AST" then asts[#asts + 1] = f end return oEmit(kind, f) end
  local savedContracts = FriendsAndFoesDB.contracts
  FriendsAndFoesDB.contracts = {}
  local showWas = ns.S().show.contract
  ns.S().show.contract = "chat"
  local mine = rr.players[ns.me]
  local streakWas = FriendsAndFoesCharDB.streak

  -- a friend's live (or caught-up, `ago`) KILL as the add-on applies it
  local nextId = 0
  local function friendKill(victim, ago)
    nextId = nextId + 1
    ns.Events.Apply({ kind = "KILL", id = "ast" .. nextId, from = "Buddy Pal", class = "PRIEST", level = 31, ago = ago,
      f = { victim = victim, vclass = "ROGUE", vlevel = "30", vguild = "", zone = "Testland", streak = "1", blow = "", last = "", rl = "" } }, false)
  end
  local function foe(name, k)
    rr.players[name] = { name = name, enemy = true, k = k or 3, d = 0, a = 0 }
  end

  -- the support is recorded for a friend, not for an enemy (that's a last attack)
  B.SettleAll()
  foe("As One")
  FIRE("UNIT_SPELLCAST_SENT", "player", "Buddy Pal", "cast-guid", 2061)
  check(P.SupportedRecently("Buddy Pal") and P.SupportedRecently("Buddy Pal", 5) and not P.SupportedRecently("Alice Wonder"),
    "a spell at a friend records support for them only")
  FIRE("UNIT_SPELLCAST_SENT", "player", ns.me, "cast-guid", 2061)
  check(not P.SupportedRecently(ns.me), "a spell at yourself records nothing")
  ADVANCE(6)
  check(P.SupportedRecently("Buddy Pal") and not P.SupportedRecently("Buddy Pal", 5), "support: the seconds asked about count")
  FIRE("UNIT_SPELLCAST_SENT", "player", "Buddy", "cast-guid", 2061)
  check(P.SupportedRecently("Buddy Pal", 5), "a bare first name matching exactly one friend counts")

  -- a friend's live kill after your heal: one AST, you share the notoriety and the bounty
  local amount = B.Open("As One")
  local c = C.Post({ name = "As One", class = "ROGUE", level = 30 }, 50000, 3)
  local before, kills, k0 = B.Mine(), mine and mine.k or 0, FriendsAndFoesCharDB.streak or 0
  asts = {}
  SENT = {}
  friendKill("As One")
  RUN_TICKERS(40)
  local onWire = 0
  for _, s in ipairs(SENT) do if s.payload:find("\tAST\t", 1, true) then onWire = onWire + 1 end end
  check(#asts == 1 and asts[1].victim == "As One" and asts[1].helped == "Buddy Pal" and onWire >= 1, "a friend's kill after your heal: one AST, sent to friends")
  B.SettleAll()
  check(amount > 0 and B.Mine() == before + math.floor(amount / 2), "the supporter shares the notoriety equally (" .. (B.Mine() - before) .. " of " .. amount .. ")")
  check(has(c.killers, ns.me) and has(c.killers, "Buddy Pal"), "the supporter is a payee of the bounty")
  check((mine and mine.k or 0) == kills and (FriendsAndFoesCharDB.streak or 0) == k0, "no kill, no streak for the supporter")
  friendKill("As One")
  check(#asts == 1, "never twice for the same victim")

  -- no AST: the heal was too long ago, you got the kill yourself, or the kill is a caught-up one
  ADVANCE(120)
  foe("As Two")
  FIRE("UNIT_SPELLCAST_SENT", "player", "Buddy Pal", "cast-guid", 2061)
  ADVANCE(31)
  asts = {}
  friendKill("As Two")
  check(#asts == 0, "a heal 31 s ago: no AST")

  foe("As Three")
  FIRE("UNIT_SPELLCAST_SENT", "player", "Buddy Pal", "cast-guid", 2061)
  ns.Events.Emit("KILL", { victim = "As Three", vclass = "ROGUE", vlevel = "24", vguild = "", zone = "Testland", blow = "", last = "" })
  friendKill("As Three")
  check(#asts == 0, "you reported the kill yourself: no AST")
  FriendsAndFoesCharDB.streak = k0

  foe("As Four")
  FIRE("UNIT_SPELLCAST_SENT", "player", "Buddy Pal", "cast-guid", 2061)
  friendKill("As Four", 300)
  check(#asts == 0, "a caught-up kill: no AST")
  friendKill("As Four")
  check(#asts == 1, "(the same victim, live: it counts)")

  -- receiving an AST: the sender joins the claim and the contract, a feed line, no kill for them
  ADVANCE(120)
  B.SettleAll()
  foe("As Five")
  local c5 = C.Post({ name = "As Five", class = "ROGUE", level = 30 }, 50000, 3)
  amount = B.Open("As Five")
  before = B.Mine()
  local buddy = rr.players["Buddy Pal"]
  local bk = buddy.k
  B.OnKill(ns.me, "As Five", {})
  C.OnKill("Alice Wonder", "As Five", {})
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("AST", { victim = "As Five", vclass = "ROGUE", vlevel = "24", zone = "Testland", helped = "Alice Wonder" }, "ast-r1"), "WHISPER", 77)
  B.SettleAll()
  check(B.Mine() == before + math.floor(amount / 2), "a received AST: the sender is counted in the claim, you share with them")
  check(has(c5.killers, "Buddy Pal") and has(c5.killers, "Alice Wonder"), "a received AST: the sender is on the contract's killers")
  local function feedHas(...) for i = #rr.feed, 1, -1 do local t = rr.feed[i].text or ""; local ok = true; for _, s in ipairs({ ... }) do if not t:find(s, 1, true) then ok = false end end; if ok then return true end end return false end
  check(buddy.k == bk, "a received AST: no kill for the sender")
  check(feedHas("helped", "Alice Wonder", "As Five"), "feed: sender helped X kill Y")
  check(not (rr.hitlist["As Five"] and (rr.hitlist["As Five"].kills or 0) > 0), "no hitlist change from an AST")
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("AST", { victim = "As Five", vclass = "ROGUE", vlevel = "24", zone = "Testland", helped = ns.me }, "ast-r2"), "WHISPER", 77)
  check(feedHas("helped you kill", "As Five"), "feed: helped you kill")

  -- round trip, under 255 bytes
  local NAME = "Abcdefghijkl Mnopqrstuvwx"
  local msg = { kind = "AST", id = "ffffffffff", name = NAME, class = "WARRIOR", level = 60,
    f = { victim = NAME, vclass = "WARRIOR", vlevel = "60", zone = string.rep("Z", 48), helped = NAME } }
  local wire = ns.Comm.Fit(msg)
  local back = wire and ns.Comm.Decode(wire)
  check(wire and #wire <= 255 and back and back.f.helped == NAME and back.f.victim == NAME and back.kind == "AST", "AST round-trips under 255 bytes: " .. tostring(wire and #wire))
  check(not ns.Comm.KINDS.AST.relay, "AST isn't passed on")
  local box = #ns.Comm.Outbox()
  ns.Comm.Remember("AST", "x", msg.f)
  check(#ns.Comm.Outbox() == box, "AST isn't kept for catch-up")

  for _, n in ipairs({ "As One", "As Two", "As Three", "As Four", "As Five" }) do rr.players[n], rr.hitlist[n] = nil, nil end
  ns.Events.Emit = oEmit
  FriendsAndFoesDB.contracts = savedContracts
  ns.S().show.contract = showWas
  FriendsAndFoesCharDB.streak = streakWas
  check(ns.errors == errs, "no errors in assists by support (" .. tostring(ns.lastError) .. ")")
end
RUN_TICKERS(80)

-- one death counts at most once per player, whatever path the report takes (and what the log says)
do
  local errs = ns.errors
  local B, C = ns.Bounty, ns.Contracts
  local rr = ns.Data.RealRealm()
  local function has(list, name)
    local n = 0
    for _, v in ipairs(list or {}) do if v == name then n = n + 1 end end
    return n
  end
  local function logHas(tag, sub)
    for _, l in ipairs(FriendsAndFoesDB.debugLog or {}) do
      if l:find("[" .. tag .. "]", 1, true) and (not sub or l:find(sub, 1, true)) then return true end
    end
    return false
  end
  local debugWas = ns.S().debug
  ns.S().debug = true
  FriendsAndFoesDB.debugLog = {}
  local savedContracts = FriendsAndFoesDB.contracts
  FriendsAndFoesDB.contracts = {}
  local showWas = ns.S().show.contract
  ns.S().show.contract = "chat"
  local buddy = rr.players["Buddy Pal"]
  local function foe(name) rr.players[name] = { name = name, enemy = true, k = 3, d = 0, a = 0 } end
  local function killFields(victim, ago)
    return { victim = victim, vclass = "ROGUE", vlevel = "24", vguild = "", zone = "Testland", streak = "1", blow = "", last = "", ago = ago }
  end
  local function bn(kind, fields, id) FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload(kind, fields, id), "WHISPER", 77) end
  local function slainN(v) return buddy.slain and buddy.slain[v] and buddy.slain[v].n or 0 end
  local function feedN(v)
    local n = 0
    for _, e in ipairs(rr.feed) do
      if e.foes and e.foes[1] == v and e.kind == "kill" and e.who == "Buddy Pal" and not (e.text or ""):find("helped", 1, true) then n = n + 1 end
    end
    return n
  end
  local function relayData(victim)
    return table.concat({ victim, "ROGUE", "24", "", "Testland", "1", "300", "", "", "" }, "^")
  end
  B.SettleAll()

  -- 1. the same message over Battle.net and whisper
  foe("Du One")
  local c1 = C.Post({ name = "Du One", class = "ROGUE", level = 24 }, 50000, 3)
  local k0 = buddy.k
  bn("KILL", killFields("Du One"), "du1")
  FIRE("CHAT_MSG_ADDON", "FNF1", payload("KILL", killFields("Du One"), "du1"), "WHISPER", "Buddy Pal")
  check(buddy.k == k0 + 1 and slainN("Du One") == 1 and feedN("Du One") == 1 and has(c1.killers, "Buddy Pal") == 1 and #c1.killers == 1,
    "one death, two routes: the kill, kill list, feed and bounty killers count once")
  check(logHas("DUP", "Buddy Pal:du1"), "the second route is logged as DUP with its key")
  check(logHas("KILL", "Du One") and logHas("BOUNTY-CLAIM", "Du One") and logHas("CONTRACT-DONE", "Du One"), "the kill, the claim and the contract closing are logged")

  -- 2. a live KILL, then the same event in a catch-up (the sender's own id)
  bn("KILL", killFields("Du One", "300"), "du1")
  check(buddy.k == k0 + 1 and slainN("Du One") == 1 and feedN("Du One") == 1, "a live KILL, then the same one caught up: counted once")

  -- 3. a live KILL, then a relayed copy (origin and its id match the direct key)
  ns.Comm.OnRelay("Alice Wonder", { origin = "Buddy Pal", oclass = "PRIEST", olevel = "31", okind = "KILL", oid = "du1", ago = "300", data = relayData("Du One") })
  check(buddy.k == k0 + 1 and slainN("Du One") == 1 and feedN("Du One") == 1, "a live KILL, then a relayed copy: counted once")
  foe("Du Two")
  ns.Comm.OnRelay("Alice Wonder", { origin = "Buddy Pal", oclass = "PRIEST", olevel = "31", okind = "KILL", oid = "du2", ago = "300", data = relayData("Du Two") })
  local k1 = buddy.k
  bn("KILL", killFields("Du Two"), "du2")
  ns.Comm.OnRelay("Alice Wonder", { origin = "Buddy Pal", oclass = "PRIEST", olevel = "31", okind = "KILL", oid = "du2", ago = "300", data = relayData("Du Two") })
  check(buddy.k == k1 and slainN("Du Two") == 1, "a relayed copy first, then the live one and the relay again: counted once")
  check(logHas("DUP", "Buddy Pal:du2"), "the dropped copies are logged as DUP")

  -- 4. an alt's event delivered twice (RLY alt=1)
  local relay = { origin = "Buddy Alt", oclass = "PRIEST", olevel = "20", okind = "KILL", oid = "du3", ago = "300", alt = "1", data = relayData("Du Alt Foe") }
  ns.Comm.OnRelay("Buddy Pal", relay)
  local alt = rr.players["Buddy Alt"]
  local ak = alt and alt.k
  ns.Comm.OnRelay("Buddy Pal", relay)
  ns.Comm.OnRelay("Alice Wonder", relay)
  check(not alt or alt.k == ak, "an alt's kill passed on twice: counted once")

  -- 5. your own event echoed back to you
  local mine = rr.players[ns.me]
  local mk, feedWas = mine and mine.k or 0, #rr.feed
  ns.Comm.OnRelay("Buddy Pal", { origin = ns.me, oclass = "MAGE", olevel = "60", okind = "KILL", oid = "du4", ago = "300", data = relayData("Du Echo") })
  check((mine and mine.k or 0) == mk and #rr.feed == feedWas, "your own kill echoed back: not counted again")
  check(logHas("RELAY-DROP", "own event"), "...and the reason is logged")

  -- 6. a friend's KILL plus their AST for the same victim
  foe("Du Five")
  local c5 = C.Post({ name = "Du Five", class = "ROGUE", level = 24 }, 50000, 3)
  local k2 = buddy.k
  bn("KILL", killFields("Du Five"), "du5")
  bn("AST", { victim = "Du Five", vclass = "ROGUE", vlevel = "24", zone = "Testland", helped = "Alice Wonder" }, "du5a")
  check(buddy.k == k2 + 1 and slainN("Du Five") == 1 and has(c5.killers, "Buddy Pal") == 1, "a friend's KILL and their own AST: one kill, one killer entry")
  check(logHas("AST-GOT", "Du Five"), "a received AST is logged")

  -- 7. two honor messages for one death (the second names nobody: no second kill of the victim)
  local enemyUnits = {}
  local o = { UnitExists = UnitExists, UnitIsPlayer = UnitIsPlayer, UnitFactionGroup = UnitFactionGroup, UnitName = UnitName,
    UnitClass = UnitClass, UnitLevel = UnitLevel, UnitIsDeadOrGhost = UnitIsDeadOrGhost, UnitIsUnit = UnitIsUnit, UnitGUID = UnitGUID }
  local oEmit = ns.Events.Emit
  UnitExists = function(u) return enemyUnits[u] ~= nil or o.UnitExists(u) end
  UnitIsPlayer = function(u) if enemyUnits[u] then return true end return o.UnitIsPlayer and o.UnitIsPlayer(u) end
  UnitFactionGroup = function(u) if enemyUnits[u] then return "Alliance" end return o.UnitFactionGroup(u) end
  UnitName = function(u) local e = enemyUnits[u]; if e then return e[1], e[2] end return o.UnitName(u) end
  UnitClass = function(u) if enemyUnits[u] then return "Rogue", "ROGUE" end return o.UnitClass(u) end
  UnitLevel = function(u) if enemyUnits[u] then return 24 end return o.UnitLevel(u) end
  UnitIsDeadOrGhost = function(u) local e = enemyUnits[u]; return e and e[3] or false end
  UnitIsUnit = function() return false end
  UnitGUID = function(u)
    if u == "player" then return "Player-1-00000001" end
    if enemyUnits[u] then return "Player-1-" .. enemyUnits[u][1] end
  end
  local victims = {}
  ns.Events.Emit = function(kind, f) if kind == "KILL" then victims[#victims + 1] = f.victim end return oEmit(kind, f) end
  ADVANCE(200)
  enemyUnits.target = { "Du", "Six", false }
  FIRE("PLAYER_TARGET_CHANGED")
  enemyUnits.target[3] = true
  FIRE("CHAT_MSG_COMBAT_HONOR_GAIN", "You have been awarded 7 Honor.")
  FIRE("CHAT_MSG_COMBAT_HONOR_GAIN", "You have been awarded 7 Honor.")
  local named = 0
  for _, v in ipairs(victims) do if v == "Du Six" then named = named + 1 end end
  check(named == 1, "two honor messages for one corpse: the victim is named in one KILL only (" .. named .. ")")
  check(logHas("KILL-DETECT", "nameless honor"), "kill detection logs where the victim name came from")
  enemyUnits.target = nil
  ns.Events.Emit = oEmit
  for k, v in pairs(o) do _G[k] = v end
  FriendsAndFoesCharDB.streak = 0

  -- 8. notoriety: an old (caught-up) kill pays nothing; a late repeat of a settled claim pays nothing
  ADVANCE(200)
  B.SettleAll()
  foe("Du Seven")
  local before = B.Mine()
  ns.past = true
  B.OnKill(ns.me, "Du Seven", {})
  ns.past = nil
  B.SettleAll()
  check(B.Mine() == before and logHas("BOUNTY-PAST", "Du Seven"), "a caught-up kill pays no notoriety (and says so in the log)")
  foe("Du Eight")
  B.OnKill(ns.me, "Du Eight", {})
  B.SettleAll()
  local paid = B.Mine() - before
  check(paid > 0 and logHas("BOUNTY-SETTLE", "your share"), "a live kill pays, and the settle logs your share")
  ADVANCE(70)
  B.OnKill(ns.me, "Du Eight", {})
  B.OnKill("Buddy Pal", "Du Eight", {})
  B.SettleAll()
  check(B.Mine() - before == paid and logHas("BOUNTY-LATE", "Du Eight"), "the same death reported 70 s later: no second claim")
  ADVANCE(150)
  B.OnKill(ns.me, "Du Eight", {})
  B.SettleAll()
  check(B.Mine() - before > paid, "a real second kill much later claims again")

  -- 9. the bounty board: a late duplicate doesn't close again or toast again
  foe("Du Nine")
  local c9 = C.Post({ name = "Du Nine", class = "ROGUE", level = 24 }, 50000, 3)
  C.OnKill("Buddy Pal", "Du Nine", {})
  local nk = #c9.killers
  CHAT = {}
  ns.Events.Apply({ kind = "KILL", id = "du9", from = "Buddy Pal", class = "PRIEST", level = 31, ago = 400, f = killFields("Du Nine", "400") }, false)
  C.OnKill("Buddy Pal", "Du Nine", {})
  check(c9.state == "done" and #c9.killers == nk and #CHAT == 0, "a late duplicate kill: the bounty isn't closed or announced again")

  -- the log: rejected bounty message, digest counts
  bn("BTY", { cid = "x", target = "Du Foe:ROGUE:24:", amount = "0", state = "open", killer = "", age = "0", updage = "0", days = "3", blow = "", last = "", poster = "", killers = "" }, "du-bty")
  check(logHas("CONTRACT-DROP", "amount"), "a rejected bounty message is logged with its reason")
  bn("HIT", { share = "dd01", entries = "Du Dig:ROGUE:24::1:1:0:1:Buddy Pal", auto = "1" }, "du-hit")
  check(logHas("DIGEST-GOT", "entries 1"), "a digest is logged with its counts")

  for _, n in ipairs({ "Du One", "Du Two", "Du Five", "Du Six", "Du Seven", "Du Eight", "Du Nine", "Du Dig", "Du Alt Foe", "Du Echo" }) do rr.players[n], rr.hitlist[n] = nil, nil end
  FriendsAndFoesDB.contracts = savedContracts
  ns.S().show.contract = showWas
  ns.S().debug = debugWas
  check(ns.errors == errs, "no errors in once-per-death (" .. tostring(ns.lastError) .. ")")
end
RUN_TICKERS(80)

-- the Friends tab leaves out friends' characters below level 15 (bank alts, fresh alts)
do
  local errs = ns.errors
  local rr = ns.Data.RealRealm()
  local S = ns.S()
  local was = S.hideLowAlts
  local tagsWas = FriendsAndFoesDB.friendTags
  FriendsAndFoesDB.friendTags = {}
  local function mk(name, level, tag)
    rr.players[name] = { name = name, friend = true, level = level, k = 1, d = 0, sk = 1, sd = 0, lastSeen = time() - 500 }
    if tag then FriendsAndFoesDB.friendTags[name] = tag end
  end
  mk("Lowa Hider", 10, "Lowa#1001")
  mk("Highr Shown", 20, "Highr#1002")
  mk("Nolevel Pal", nil, "Nolvl#1003")
  mk("Zed Tiny", 3, "Zed#9001")
  mk("Zed Main", 40, "Zed#9001")
  mk("Zed Mid", 25, "Zed#9001")
  rr.players["Zed Mid"].lastSeen = time() - 9000
  local myRec = rr.players[ns.me]
  local myLevel = myRec and myRec.level
  if myRec then myRec.level = 5 end
  local function names()
    ns.UI.Show("friends")
    local out = {}
    for _, r in ipairs(ns.UI.Rows()) do out[r.name] = r end
    return out
  end

  S.hideLowAlts = true
  local rows = names()
  check(rows["Lowa Hider"] == nil and rows["Highr Shown"] ~= nil, "Friends tab: a level 10 friend character is hidden, a level 20 one shown")
  check(rows[ns.me] ~= nil and rows[ns.me].me, "Friends tab: your own low level character is still shown")
  check(rows["Nolevel Pal"] ~= nil, "Friends tab: unknown level is shown")
  ns.Comm.everyone["Pending Newbie"] = { tag = "Pend#1004", zone = "Elwynn Forest" }
  rows = names()
  check(rows["Pending Newbie"] == nil, "Friends tab: a Battle.net friend online without the add-on is not listed")
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("LVL", { level = 30 }, "pnl1"), "WHISPER", 77)
  check(names()["Buddy Pal"] ~= nil, "Friends tab: a friend who sent an add-on message is listed")
  ns.Comm.everyone["Pending Newbie"] = nil

  -- ranks stay 1..n after the filter
  local ranks = {}
  for _, r in pairs(names()) do if r.rank then ranks[#ranks + 1] = r.rank end end
  table.sort(ranks)
  local contiguous = #ranks > 0
  for i, v in ipairs(ranks) do if v > i then contiguous = false end end
  check(contiguous and ranks[1] == 1, "Friends tab: ranks have no gaps after filtering")

  -- online on a hidden alt: the account's best shown character says so
  ns.Comm.everyone["Zed Tiny"] = { tag = "Zed#9001", zone = "Elwynn Forest" }
  rows = names()
  check(rows["Zed Tiny"] == nil and rows["Zed Main"] ~= nil, "alt: the hidden alt is not listed")
  local cols = ns.UI.TabColumns("friends")
  local nowCell = cols[#cols][3]
  check(ns.Plain(nowCell(rows["Zed Main"])) == ns.L.FRIEND_ONLINE_ALT and ns.L.FRIEND_ONLINE_ALT == "online (on an alt)",
    "alt: the level 40 main shows 'online (on an alt)'")
  check(not rows["Zed Mid"].onAlt and ns.Plain(nowCell(rows["Zed Mid"])) ~= ns.L.FRIEND_ONLINE_ALT, "alt: only the highest-level character of the account")
  ns.Comm.everyone["Zed Tiny"] = nil
  rows = names()
  check(not rows["Zed Main"].onAlt, "alt: nothing said when their account isn't online on a hidden alt")
  -- all of an account's characters low: nothing shown
  mk("Lone Alt", 2, "Lone#1005")
  ns.Comm.everyone["Lone Alt"] = { tag = "Lone#1005" }
  check(names()["Lone Alt"] == nil, "alt: an account with only low characters shows nothing")
  ns.Comm.everyone["Lone Alt"] = nil

  -- option off: everyone
  S.hideLowAlts = false
  rows = names()
  check(rows["Lowa Hider"] and rows["Zed Tiny"] and rows["Lone Alt"], "option off: low characters are listed")
  S.hideLowAlts = true

  -- group boards aren't filtered
  local calls, orig = 0, ns.Profile.HideLowAlts
  ns.Profile.HideLowAlts = function(r) calls = r and (calls + 1) or calls; return orig(r) end
  local g = ns.Groups.Create("Low Level Crew")
  if g then
    ns.UI.Show("friends")
    ns.UI.SetBoardView(g.id)
    local before = calls
    local grows = ns.UI.Rows()
    check(calls == before and #grows >= 1 and grows[1].me ~= nil, "group board: rows aren't filtered")
    ns.UI.SetBoardView("friends")
    ns.Groups.Leave(g)
  else
    check(true, "group board: (no group could be made here)")
  end
  ns.Profile.HideLowAlts = orig

  check(ns.Profile.MIN_LEVEL == 15 and ns.DEFAULTS.hideLowAlts == true, "the filter starts on, at level 15")

  for _, n in ipairs({ "Lowa Hider", "Highr Shown", "Nolevel Pal", "Zed Tiny", "Zed Main", "Zed Mid", "Lone Alt" }) do rr.players[n] = nil end
  if myRec then myRec.level = myLevel end
  FriendsAndFoesDB.friendTags = tagsWas
  S.hideLowAlts = was
  ns.UI.Show("friends")
  check(ns.errors == errs, "no errors in the low alt filter (" .. tostring(ns.lastError) .. ")")
end

-- one toast and one Feed line per death, however many friends report the kill
do
  local errs = ns.errors
  drainToasts()
  ns.S().show.kill = "toast"
  ns.S().flavor = true
  FriendsAndFoesCharDB.streak = 0
  local function kill(from, victim, extra)
    local f = { victim = victim, vclass = "MAGE", vlevel = "30", vguild = "", zone = "Duskwood" }
    for k, v in pairs(extra or {}) do f[k] = v end
    ns.Events.Apply({ kind = "KILL", id = ns.NewId(), from = from, class = "PRIEST", level = 40, f = f }, false)
  end
  local function kills() local n, last = 0; for _, e in ipairs(real.feed) do if e.kind == "kill" then n, last = n + 1, e.text end end return n, last end
  local function count() return ns.Toast.shown or 0, (kills()) end
  local t0, f0 = count()
  local aliceK = ns.Data.Player("Alice Wonder").k

  kill("Buddy Pal", "Dup One")
  ADVANCE(5)
  kill("Alice Wonder", "Dup One")
  local t1, f1 = count()
  check(t1 == t0 + 1 and f1 == f0 + 1, "two friends, one death: one toast, one Feed line (" .. (t1 - t0) .. ", " .. (f1 - f0) .. ")")
  local line = nolv(select(2, kills()))
  check(line:find("Buddy Pal and Alice Wonder killed Dup One", 1, true) ~= nil, "the line names both: " .. line)
  check(ns.Data.Player("Alice Wonder").k == aliceK + 1, "each killer still gets their own count")
  kill("Carol Third", "Dup One")
  line = nolv(select(2, kills()))
  check((kills()) == f1 and line:find("Buddy Pal, Alice Wonder and Carol Third killed", 1, true) ~= nil, "a third killer joins the same line: " .. line)

  kill("Buddy Pal", "Dup One") -- the same friend again: a new death
  check((kills()) == f1 + 1, "the same friend twice: a second line")

  drainToasts()
  local t2, f2 = count()
  kill("Buddy Pal", "Dup Two")
  ADVANCE(5)
  local realSeen = ns.PvP.SeenAliveSince
  ns.PvP.SeenAliveSince = function() return true end
  kill("Alice Wonder", "Dup Two")
  ns.PvP.SeenAliveSince = realSeen
  local t3, f3 = count()
  check(f3 == f2 + 2 and t3 == t2 + 2, "seen alive in between: a new death, its own toast and line")

  kill("Buddy Pal", "Dup Three")
  ADVANCE(70)
  kill("Alice Wonder", "Dup Three")
  check((kills()) == f3 + 2, "70 s apart: a new death")

  drainToasts()
  FriendsAndFoesCharDB.streak = 0
  local t4, f4 = count()
  ns.Events.Emit("KILL", { victim = "Dup Four", vclass = "MAGE", vlevel = "30", vguild = "", zone = "Duskwood" })
  kill("Alice Wonder", "Dup Four")
  local t5, f5 = count()
  check(f5 == f4 + 1 and t5 == t4, "your own kill and a friend's: one line, no toast of yours")
  line = nolv(select(2, kills()))
  check(line:find("You and Alice Wonder killed Dup Four", 1, true) ~= nil, "'You and ...': " .. line)

  drainToasts()
  kill("Buddy Pal", "Dup Five")
  local t6, f6 = count()
  kill("Alice Wonder", "Dup Five", { streak = "5" })
  local t7, f7 = count()
  check(t7 == t6 + 1 and f7 == f6, "a second killer's streak milestone still toasts (" .. (t7 - t6) .. ")")
  check(ns.errors == errs, "no errors in one toast per death (" .. tostring(ns.lastError) .. ")")
end

-- 0.9.4 UI fixes: the Bounty board's row stays on its tab; profile rank = Friends tab rank; alert list
do
  local errs = ns.errors
  local fr = ns.UI.Frames()
  ns.UI.Show("contracts")
  check(fr.contractBar:IsShown(), "Bounty board: its bottom row shows")
  ns.UI.ShowProfile("Rogz Fang")
  check(ns.UI.CurrentTab() == "profile" and not fr.contractBar:IsShown(), "an enemy's profile from the Bounty board: the board's row is gone")
  ns.UI.Show("contracts")
  check(fr.contractBar:IsShown(), "back on the Bounty board: the row is back")
  ns.UI.Show("hitlist")
  check(not fr.contractBar:IsShown(), "other tabs: no Bounty board row")

  -- rank: same filtered list as the Friends tab
  local rr = ns.Data.RealRealm()
  local hideWas = ns.S().hideLowAlts
  rr.players["Low Alt"] = { name = "Low Alt", friend = true, k = 500, d = 0, a = 0, level = 5, class = "MAGE", lastSeen = time() }
  local function rankOf(name)
    for _, l in ipairs(ns.UI.ProfileView(name).lines) do
      if l[1] == ns.L.PROF_RANK then return ns.Plain(l[2]) end
    end
  end
  ns.S().hideLowAlts = false
  local all = #ns.Profile.Board()
  local pos0
  for _, r in ipairs(ns.Profile.Board()) do if r.name == "Buddy Pal" then pos0 = r.rank end end
  check(rankOf("Buddy Pal") == ns.L.PROF_RANK_OF:format(pos0, all), "filter off: rank among everyone (" .. tostring(rankOf("Buddy Pal")) .. ")")
  check(rankOf("Low Alt") ~= "-" and rankOf("Low Alt"):find("#", 1, true) ~= nil, "filter off: a low alt is ranked")
  ns.S().hideLowAlts = true
  local shown = ns.Profile.HideLowAlts(ns.Profile.Board())
  local pos
  for _, r in ipairs(shown) do if r.name == "Buddy Pal" then pos = r.rank end end
  check(#shown == all - 1 and rankOf("Buddy Pal") == ns.L.PROF_RANK_OF:format(pos, #shown), "filter on: rank and total are the Friends tab's (" .. tostring(rankOf("Buddy Pal")) .. ")")
  check(rankOf("Low Alt") == "-" or rankOf("Low Alt") == ns.Plain(rankOf("Low Alt")) and not rankOf("Low Alt"):find("#", 1, true), "filter on: a hidden low alt shows no rank (" .. tostring(rankOf("Low Alt")) .. ")")
  ns.S().hideLowAlts = hideWas
  rr.players["Low Alt"] = nil

  -- alert list: just the names, no "online" tag
  ns.Comm.ClearPicks()
  ns.UI.ShowAlertList()
  local w = ns.UI.AlertListWindow()
  local onlineAcct
  for i, a in ipairs(ns.UI.AlertAccounts()) do if a.online then onlineAcct = i end end
  if onlineAcct then
    local label = ns.Plain(w.rows and w.rows[onlineAcct].label:GetText() or "")
    check(not label:find(ns.L.FRIEND_ONLINE, 1, true), "alert list: an online account has no online text (" .. label .. ")")
  end
  w:Hide()
  check(ns.errors == errs, "no errors in the UI fixes (" .. tostring(ns.lastError) .. ")")
end

-- Recent PvP on profiles: wrapped in full, paged
do
  local errs = ns.errors
  local feed = ns.Data.ViewRealm().feed
  local base = #feed
  local pg = ns.UI.Frames().profile.recentPager
  for _, count in ipairs({ 0, 3, 25 }) do
    for _, name in ipairs({ ns.me, "Buddy Pal", "Rogz Fang" }) do
      while #feed > base do table.remove(feed) end
      for i = 1, count do
        ns.Data.Feed("attacked", "Rogz Fang and Helper Guy ganked Buddy Pal and Testme Tester near the Tarren Mill graveyard, again and again, number " .. i, name, { name })
      end
      ns.UI.ShowProfile(name)
      check(ns.errors == errs, "recent PvP renders (" .. name .. ", " .. count .. "): " .. tostring(ns.lastError))
      if count == 25 then
        check(pg.pages and pg.pages > 1 and pg.label:IsShown() and pg.next:IsShown(), "25 entries on " .. name .. ": more than one page")
        check(pg.label:GetText() == ns.L.PROF_PAGE:format(1, pg.pages), "page label starts at 1/n")
        pg.next._scripts.OnClick()
        check(pg.page == 2 and pg.label:GetText() == ns.L.PROF_PAGE:format(2, pg.pages), "Next advances the page")
        ns.UI.ShowProfile(name == "Buddy Pal" and ns.me or "Buddy Pal")
        ns.UI.ShowProfile(name)
        check(pg.page == 1, "a different profile opens on page 1")
      elseif count == 3 and name == "Rogz Fang" then
        -- (older entries from earlier tests may already be in the feed: only a single page hides the arrows)
        check((pg.pages > 1) == pg.next:IsShown() and (pg.pages > 1) == pg.label:IsShown(), "arrows only with more than one page")
      end
    end
  end
  while #feed > base do table.remove(feed) end
  ns.UI.ShowProfile(ns.me)
  check(ns.errors == errs, "no errors in the recent PvP paging (" .. tostring(ns.lastError) .. ")")
end

-- clickable names: Feed rows and Recent PvP entries carry player links; clicking one opens the profile
do
  local errs = ns.errors
  local feed = ns.Data.ViewRealm().feed
  local base = #feed
  ns.Data.Feed("attacked", "Rogz Fang ganked Buddy Pal near the mill", "Buddy Pal", { "Rogz Fang" })
  ns.UI.Show("feed")
  local linked
  for _, o in ipairs(FRAMES) do
    if o.cells and o._shown and o.entry and o.entry.text and o.entry.text:find("near the mill", 1, true) then
      linked = o.cells[2]._text
    end
  end
  check(linked and linked:find("|Hfnfplayer:Rogz Fang|h", 1, true) and linked:find("|Hfnfplayer:Buddy Pal|h", 1, true),
    "feed row: player names are links (" .. tostring(linked) .. ")")
  ns.UI.ShowProfile("Buddy Pal")
  local p = ns.UI.Frames().profile
  local seen
  for _, fs in ipairs(p.recent) do
    if fs._text and fs._text:find("|Hfnfplayer:Rogz Fang|h", 1, true) then seen = true end
  end
  check(seen, "recent PvP entry: names are links")
  check(p._scripts.OnHyperlinkClick and p._scripts.OnHyperlinkEnter and p._scripts.OnHyperlinkLeave, "the profile answers link clicks and hovers")
  ns.UI.Show("hitlist")
  p._scripts.OnHyperlinkClick(p, "fnfplayer:Rogz Fang")
  check(ns.UI.CurrentTab() == "profile" and ns.UI.ProfileName() == "Rogz Fang", "clicking a name link opens that profile")
  p._scripts.OnHyperlinkClick(p, "item:1234")
  check(ns.UI.ProfileName() == "Rogz Fang", "other links are ignored")
  p._scripts.OnHyperlinkEnter(p, "fnfplayer:Rogz Fang")
  p._scripts.OnHyperlinkLeave(p)
  -- the open profile's own name is never a link on its page
  ns.UI.ShowProfile("Rogz Fang")
  local selfLink, otherLink, headerLink = false, false, false
  for _, fs in ipairs(p.recent) do
    if fs._text and fs._text:find("|Hfnfplayer:Rogz Fang|h", 1, true) then selfLink = true end
    if fs._text and fs._text:find("|Hfnfplayer:Buddy Pal|h", 1, true) then otherLink = true end
  end
  for _, fs in ipairs({ p.title, p.sub, p.posterName, p.posterSub }) do
    if fs._text and fs._text:find("|H", 1, true) then headerLink = true end
  end
  check(not selfLink and otherLink and not headerLink, "recent PvP on a profile: no link to itself, a link to the other player")
  check(ns.UI.LinkName("Rogz Fang", "Rogz Fang", "Rogz Fang") == "Rogz Fang"
    and ns.UI.LinkName("Rogz Fang", "Rogz Fang", "Other"):find("|Hfnfplayer:Rogz Fang|h", 1, true), "LinkName skips the open profile")
  while #feed > base do table.remove(feed) end
  ns.UI.ShowProfile(ns.me)
  check(ns.errors == errs, "no errors in the name links (" .. tostring(ns.lastError) .. ")")
end

-- levels at the time in the Feed
do
  local errs = ns.errors
  local S = SYNC
  local rr = ns.Data.RealRealm()
  local restore = S.friends({ { gid = 77, name = "Buddy Pal", tag = "Buddy#1234" } })
  ns.Comm.ClearPicks()
  ns.Comm.RebuildRoster()
  S.drain()
  local GREY = "|cff9d9d9d"
  local function last() return rr.feed[#rr.feed].text end
  local function recv(level, kind, fields, id)
    local p = ns.Comm.Encode({ kind = kind, id = "lv" .. id, name = "Buddy Pal", class = "PRIEST", level = level, f = fields })
    FIRE("BN_CHAT_MSG_ADDON", "FNF1", p, "WHISPER", 77)
  end
  recv(35, "KILL", { victim = "Bob Gank", vclass = "ROGUE", vlevel = "38", zone = "Duskwood", streak = "1" }, "k1")
  local t = last()
  local pal, bob = t:find("Buddy Pal", 1, true), t:find("Bob Gank", 1, true)
  check(t:find("Buddy Pal|r " .. GREY .. "(35)|r", 1, true) or t:find("Buddy Pal " .. GREY .. "(35)|r", 1, true), "feed: friend's level after their name: " .. t)
  check(t:find("Bob Gank|r " .. GREY .. "(38)|r", 1, true) or t:find("Bob Gank " .. GREY .. "(38)|r", 1, true), "feed: victim's level after their name")
  check(ns.UI.Linkify(t, rr.feed[#rr.feed]):find("|Hfnfplayer:Bob Gank|h", 1, true), "feed: the names stay links with levels in the text")
  check(ns.Plain(t):find("Buddy Pal (35)", 1, true) and ns.Plain(t):find("Bob Gank (38)", 1, true), "feed: plain text reads well (and is searchable)")
  -- an old-format message: no sender level
  recv(nil, "KILL", { victim = "Old Victim", vclass = "ROGUE", vlevel = "20", zone = "Duskwood", streak = "1" }, "k2")
  t = last()
  check(not t:find("Buddy Pal|r " .. GREY, 1, true) and t:find("(20)", 1, true), "no sender level: none for the friend, the victim's still shown")
  -- skull
  recv(35, "KILL", { victim = "Skull Guy", vclass = "ROGUE", vlevel = "0", zone = "Duskwood", streak = "1" }, "k3")
  check(last():find("(" .. ns.L.LEVEL_SKULL .. ")", 1, true) and ns.L.LEVEL_SKULL == "Skull", "a skull-level victim shows (Skull)")
  check(ns.LevelTag(0) == "" and ns.LevelTag("") == "" and ns.LevelTag(nil, true) == "", "no level / a friend's 0: nothing")
  -- attacked, with the attacker's level
  recv(34, "ATK", { enc = "e-lv", zone = "Duskwood", attackers = "Gank Two:ROGUE:38:" }, "a1")
  t = last()
  check(ns.Plain(t):find("Buddy Pal (34)", 1, true) and ns.Plain(t):find("Gank Two (38)", 1, true), "attacked: both levels")
  -- a second killer of the same death: levels kept in the merged line
  recv(35, "KILL", { victim = "Merge Man", vclass = "ROGUE", vlevel = "36", zone = "Duskwood", streak = "1" }, "m1")
  ns.Events.Emit("KILL", { victim = "Merge Man", vclass = "ROGUE", vlevel = "36", zone = "Duskwood" })
  t = ns.Plain(last())
  check(t:find("(35)", 1, true) and t:find("You (" .. UnitLevel("player") .. ")", 1, true) and t:find("Merge Man (36)", 1, true), "merged kill keeps each level: " .. t)
  -- your own death: your level
  ns.Events.Emit("DIE", { zone = "Duskwood", killer = "Lv Killer:ROGUE:" .. (UnitLevel("player") + 3) .. ":", conf = "c", assists = "" })
  t = ns.Plain(last())
  check(t:find(ns.me .. " (" .. UnitLevel("player") .. ")", 1, true) and t:find("Lv Killer (" .. (UnitLevel("player") + 3) .. ")", 1, true), "your own death: your level and the killer's: " .. t)
  -- the outbox replays the level from when it happened
  local savedBox = FriendsAndFoesDB.outbox
  FriendsAndFoesDB.outbox = {}
  ns.Comm.Remember("KILL", "obx1", { victim = "Old Foe", vclass = "MAGE", vlevel = "9", zone = "Duskwood", streak = "1" })
  ns.Comm.Outbox()[1].l = 22 -- (you were 22 then)
  S.drain() -- (live messages still queued from above go out first)
  ADVANCE(100)
  SENT = {}
  S.from("Buddy Pal", 77, "REQ", { window = 3600 }, "lvq1")
  S.drain()
  local kills = S.sent(77, "KILL")
  check(#kills == 1 and kills[1].level == 22, "catch-up replay keeps the level from when it happened")
  FriendsAndFoesDB.outbox = savedBox
  -- size: long names with the levels
  local NAME = "Abcdefghijkl Mnopqrstuvwx"
  for _, m in ipairs({
    { kind = "KILL", f = { victim = NAME, vclass = "WARRIOR", vlevel = "60", vguild = string.rep("G", 24), zone = string.rep("Z", 48), streak = "12", rl = "1", blow = "pet", last = "120" } },
    { kind = "DIE", f = { zone = string.rep("Z", 48), killer = NAME .. ":WARRIOR:60:" .. string.rep("G", 24), conf = "c", assists = NAME .. ":MAGE:60:;" .. NAME .. ":MAGE:60:", ended = "12", rl = "1" } },
  }) do
    m.id, m.name, m.class, m.level = "ffffffffff", NAME, "WARRIOR", 60
    local wire = ns.Comm.Fit(m)
    check(wire and #wire <= 255, m.kind .. " with long names and levels fits: " .. tostring(wire and #wire))
  end
  restore()
  check(ns.errors == errs, "no errors in feed levels (" .. tostring(ns.lastError) .. ")")
end

-- sighting text: kills, else attacks, else nothing
do
  local flavorWas = ns.S().flavor
  ns.S().flavor = true
  local function line(hit) return ns.Plain(ns.Toast.Sighting("Sight Seer", "ROGUE", "Duskwood", hit, nil)) end
  local t = line({ kills = 3, attacks = 5 })
  check(t:find("3 kills on us", 1, true) and not t:find("attacked", 1, true), "sighting: kills first: " .. t)
  check(line({ kills = 1, attacks = 0 }):find("1 kill on us", 1, true) and not line({ kills = 1 }):find("1 kills", 1, true), "sighting: one kill, singular")
  t = line({ kills = 0, attacks = 4 })
  check(t:find("attacked us 4 times", 1, true) and not t:find("kills", 1, true), "sighting: only attacks: " .. t)
  check(line({ kills = 0, attacks = 1 }):find("attacked us once", 1, true), "sighting: one attack")
  t = line({ kills = 0, attacks = 0 })
  check(not t:find("kill", 1, true) and not t:find("attacked", 1, true) and t:find("Duskwood", 1, true) and not t:find("\194\183 \194\183", 1, true), "sighting: nothing known, no empty part: " .. t)
  check(line(nil):find("Duskwood", 1, true) ~= nil, "sighting: not on your hitlist: just the place")
  ns.S().flavor = false
  t = line({ kills = 0, attacks = 4 })
  check(not t:find("kill", 1, true) and not t:find("attacked us", 1, true), "sighting, short wording: who and where only")
  ns.S().flavor = flavorWas
  drainToasts()
end

-- 1.0.1: add by name, bounty notes, bounty target spotted, nemesis ties
do
  local errs = ns.errors
  local L, D, C, P = ns.L, ns.Data, ns.Contracts, ns.Profile
  local rr = D.RealRealm()
  local debugWas = ns.S().debug
  ns.S().debug = true
  local savedContracts = FriendsAndFoesDB.contracts
  FriendsAndFoesDB.contracts = {}
  local slash = SlashCmdList.FRIENDSANDFOES
  local function printed(text)
    for _, l in ipairs(PRINTED) do if l:find(text, 1, true) then return true end end
    return false
  end
  local function bty(fields, id) FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("BTY", fields, id), "WHISPER", 77) end

  -- name rules
  check(D.ParseName("Ru Mia") == "Ru Mia" and D.ParseName("Père Sévérance") == "Père Sévérance", "names: a space and accents are fine")
  check(D.ParseName("  ru   mia ") == "Ru Mia" and D.ParseName("zed") == "Zed" and D.ParseName("d'arcy") == "D'arcy", "names: trimmed, a capital for each word")
  check(D.ParseName("Ru-Mia") == "Ru Mia", "names: a hyphen is the space (First-Last)")
  local bad = { "x", "", "   ", "abc123", "Bob!", "a b c", string.rep("a", 25), "Bob|cffff0000", "'", "12" }
  local allBad = true
  for _, b in ipairs(bad) do
    local n, why = D.ParseName(b)
    if n or why ~= "NAME_BAD" then allBad = false; check(false, "names: '" .. b .. "' is refused") end
  end
  check(allBad, "names: too short or long, digits, symbols and more than two words are refused")
  check(D.ParseName(string.rep("a", 24)) ~= nil and D.ParseName(string.rep("\195\169", 24)) ~= nil, "names: 24 characters (not bytes) is the limit")
  check(select(2, D.ManualTarget(ns.me)) == "NAME_FRIEND" and select(2, D.ManualTarget("Buddy Pal")) == "NAME_FRIEND",
    "names: you and your friends can't go on the hitlist")

  -- /fnf hitlist add: a manual entry, not forgotten, not in the digest
  PRINTED = {}
  slash("hitlist add ru mia")
  local h = rr.hitlist["Ru Mia"]
  check(h and h.manual and (h.kills or 0) == 0, "hitlist add: a manual entry, named properly")
  check(printed("Ru Mia") and printed("hitlist"), "hitlist add: says so in chat")
  PRINTED = {}
  slash("hitlist add Ru Mia")
  check(printed(L.HIT_ALREADY:format("Ru Mia")), "hitlist add: already on the list")
  PRINTED = {}
  slash("hitlist add abc123")
  slash("hitlist add " .. ns.me)
  slash("hitlist add Buddy Pal")
  check(printed(L.NAME_BAD) and printed(L.NAME_FRIEND) and rr.hitlist["Abc123"] == nil and rr.hitlist["Buddy Pal"] == nil,
    "hitlist add: bad names, you and friends are refused with a message")
  h.firstSeen, h.lastSeen = time() - 400 * 86400, nil
  D.ForgetOld(FriendsAndFoesDB)
  check(rr.hitlist["Ru Mia"] == h and D.CountForget(FriendsAndFoesDB) == 0, "a manual entry is never forgotten by itself")
  local plain = D.Hit("Plain Attacker")
  plain.attacks, plain.firstSeen = 2, time() - 400 * 86400
  plain.victims["Buddy Pal"] = true
  plain.hitWho = { ["Buddy Pal"] = time() }
  local inDigest = {}
  for _, e in ipairs(ns.Comm.DigestList(100)) do inDigest[e.name] = true end
  check(not inDigest["Ru Mia"] and inDigest["Plain Attacker"], "a manual entry with no deeds isn't in the digest; an attacker is")
  D.ForgetOld(FriendsAndFoesDB)
  check(rr.hitlist["Plain Attacker"] == nil, "(an old attacker is forgotten)")
  check(ns.UI.AddHit("Ui Added") and rr.hitlist["Ui Added"] and rr.hitlist["Ui Added"].manual, "the Add button's path adds one too")

  -- seen: a manual entry learns class and level, and alerts like any hitlist entry
  local enemyUnits = {}
  local o = { UnitExists = UnitExists, UnitIsPlayer = UnitIsPlayer, UnitFactionGroup = UnitFactionGroup, UnitName = UnitName,
    UnitClass = UnitClass, UnitLevel = UnitLevel, UnitIsUnit = UnitIsUnit }
  UnitExists = function(u) return enemyUnits[u] ~= nil or o.UnitExists(u) end
  UnitIsPlayer = function(u) if enemyUnits[u] then return true end return o.UnitIsPlayer and o.UnitIsPlayer(u) end
  UnitFactionGroup = function(u) if enemyUnits[u] then return "Alliance" end return o.UnitFactionGroup(u) end
  UnitName = function(u) local e = enemyUnits[u]; if e then return e[1], e[2] end return o.UnitName(u) end
  UnitClass = function(u) if enemyUnits[u] then return "Rogue", "ROGUE" end return o.UnitClass(u) end
  UnitLevel = function(u) if enemyUnits[u] then return 24 end return o.UnitLevel(u) end
  UnitIsUnit = function() return false end
  local pushed, centre = {}, {}
  local realPush = ns.Toast.Push
  ns.Toast.Push = function(spec) pushed[#pushed + 1] = spec end
  local showWas, sightWas = ns.S().show.contract, ns.S().show.sighting
  ns.S().show.sighting = "toast"
  ns.S().show.contract = "toast"
  enemyUnits.target = { "Ru", "Mia", false }
  FIRE("PLAYER_TARGET_CHANGED")
  check(h.class == "ROGUE" and h.level == 24, "a manual entry gets their class and level when you see them")
  check(pushed[1] and pushed[1].kind == "sighting", "...and the normal sighting alert")
  enemyUnits.target = nil

  -- a bounty by name, no target: the BTY carries the name only, with the note
  PRINTED, SENT = {}, {}
  slash("bounty Zork Quux 10g 3d Caught me AFK")
  local zork
  for _, c in pairs(FriendsAndFoesDB.contracts) do if c.target == "Zork Quux" then zork = c end end
  check(zork and zork.amount == 100000 and zork.days == 3 and zork.note == "Caught me AFK", "bounty by name: posted without a target, with days and a note")
  check(rr.hitlist["Zork Quux"] and rr.hitlist["Zork Quux"].manual, "bounty by name: the target is on your hitlist as manual")
  RUN_TICKERS(4)
  local wire
  for _, s in ipairs(SENT) do if s.payload:find("\tBTY\t", 1, true) and s.payload:find("Zork Quux", 1, true) then wire = ns.Comm.Decode(s.payload) end end
  check(wire and wire.f.target == "Zork Quux:::" and wire.f.note == "Caught me AFK", "bounty by name: the message has the name, empty class and level, and the note")
  check(printed("Caught me AFK"), "the chat line quotes the note")
  local cmd = C.ParseCommand("Ru Mia 10g for 3 days revenge time")
  check(cmd.name == "Ru Mia" and cmd.offer == "10g for 3 days" and cmd.note == "revenge time", "/fnf bounty: name, offer and message are told apart")
  cmd = C.ParseCommand("10g 50s 3d")
  check(cmd.name == nil and cmd.offer == "10g 50s 3d" and cmd.note == nil, "/fnf bounty: the old '<amount> [days]' still works")
  cmd = C.ParseCommand("Père Sévérance 5g \"quoted words\"")
  check(cmd.name == "Père Sévérance" and cmd.note == "quoted words", "/fnf bounty: accents and quotes")
  PRINTED = {}
  local before = 0
  for _ in pairs(FriendsAndFoesDB.contracts) do before = before + 1 end
  slash("bounty 10g")
  local after = 0
  for _ in pairs(FriendsAndFoesDB.contracts) do after = after + 1 end
  check(printed(L.CONTRACT_NEED_TARGET) and after == before, "/fnf bounty with no name and no target: asks for one")
  enemyUnits.target = { "Targ", "Et", false }
  slash("bounty 7g 2d")
  local targ
  for _, c in pairs(FriendsAndFoesDB.contracts) do if c.target == "Targ Et" then targ = c end end
  check(targ and targ.amount == 70000 and targ.days == 2 and not (rr.hitlist["Targ Et"] or {}).manual, "/fnf bounty on your target as before (not manual)")
  enemyUnits.target = nil
  PRINTED = {}
  slash("bounty Buddy Pal 10g")
  slash("bounty bad1 10g")
  check(printed(L.CONTRACT_NOT_ENEMY) and printed(L.NAME_BAD), "bounty by name: friends and bad names are refused")
  PRINTED = {}
  slash("bounty " .. ns.me .. " 10g")
  check(printed(L.NAME_FRIEND) or printed(L.CONTRACT_NOT_ENEMY), "bounty by name: not on yourself")
  -- the dialog (no target): name, amount, days and message
  slash("bounty")
  local win, fields = ns.UI.Frames_Bounty()
  check(win and win:IsShown(), "Post bounty without a target opens the dialog")
  fields.name:SetText("dlg foe"); fields.amount:SetText("5g"); fields.days:SetText("2"); fields.note:SetText("From the dialog")
  fields.note._scripts.OnEnterPressed(fields.note)
  local dlg
  for _, c in pairs(FriendsAndFoesDB.contracts) do if c.target == "Dlg Foe" then dlg = c end end
  check(dlg and dlg.amount == 50000 and dlg.days == 2 and dlg.note == "From the dialog" and not win:IsShown(), "the dialog posts it and closes")
  enemyUnits.target = { "Pre", "Filled", false }
  ns.UI.PostBounty()
  check(fields.name:GetText() == "Pre Filled", "with a target, the dialog fills in the name")
  enemyUnits.target = nil
  win:Hide()

  -- the note: filtered, "|" stripped, 60 characters, and again when received
  check(select(2, C.Post({ name = "Note Foe" }, 100, 3, "Hitler Fans")) == "TEXT_OFFENSIVE", "a note that fails the language filter isn't posted")
  local piped = C.Post({ name = "Note Foe" }, 100, 3, "hi |cffff0000red|r\ttext")
  check(piped and not piped.note:find("|", 1, true) and not piped.note:find("\t", 1, true), "a note has no '|' or control characters: " .. tostring(piped and piped.note))
  local long = C.Post({ name = "Note Foe" }, 100, 3, string.rep("a", 100))
  check(long and P.Length(long.note) == 60, "a note is cut at 60 characters")
  local accent = C.Post({ name = "Note Foe" }, 100, 3, string.rep("\195\169", 70))
  check(accent and P.Length(accent.note) == 60 and #accent.note == 120, "...counted in characters")
  check(C.Post({ name = "Note Foe" }, 100, 3, "   ").note == nil, "an empty note is no note")
  bty({ cid = "n1", target = "Rude Foe:MAGE:50:", amount = 700, state = "open", killer = "", age = 1, updage = 1, days = 4, note = "Hitler Fans" }, "n1")
  local rude = FriendsAndFoesDB.contracts["Buddy Pal/n1"]
  check(rude and rude.note == nil, "a friend's note that fails the filter is dropped when received (the bounty stays)")
  bty({ cid = "n2", target = "Kind Foe:MAGE:50:", amount = 700, state = "open", killer = "", age = 1, updage = 1, days = 4, note = "Good |cffff0000luck|r" }, "n2")
  local kind = FriendsAndFoesDB.contracts["Buddy Pal/n2"]
  check(kind and kind.note and not kind.note:find("|", 1, true), "a received note has its '|' stripped: " .. tostring(kind and kind.note))
  bty({ cid = "n3", target = "Old Foe:MAGE:50:", amount = 700, state = "open", killer = "", age = 1, updage = 1, days = 4 }, "n3")
  check(FriendsAndFoesDB.contracts["Buddy Pal/n3"] and FriendsAndFoesDB.contracts["Buddy Pal/n3"].note == nil, "an older friend's bounty has no note: fine")
  -- fits 255 bytes: a full note with a long name and no helper names is kept whole; with everything at its longest the note goes first
  local NAME = "Abcdefghijkl Mnopqrstuvwx"
  local msg = { kind = "BTY", id = "ffffffffff", name = NAME, class = "WARRIOR", level = 60, f = { cid = "ffffffffff",
    target = NAME .. ":WARRIOR:60:" .. string.rep("G", 24), amount = "999999999", state = "open", killer = "", age = "5184000", updage = "5184000", days = "30",
    blow = "", last = "", poster = "", killers = "", note = string.rep("n", 60) } }
  local w = ns.Comm.Fit(msg)
  check(w and #w <= 255 and ns.Comm.Decode(w).f.note == string.rep("n", 60), "BTY with a 60-character note and long names fits 255 bytes whole: " .. tostring(w and #w))
  msg.f.state, msg.f.killer, msg.f.poster, msg.f.blow, msg.f.last = "done", NAME, NAME, "pet", "120"
  msg.f.killer, msg.f.poster = "Ab Cd", ""
  msg.f.killers = table.concat({ "Ab Cd", "Bbbbbbbbbbbb Nnnnnnnnnnnn", "Cccccccccccc Oooooooooooo" }, ",")
  w = ns.Comm.Fit(msg)
  local back = w and ns.Comm.Decode(w)
  check(w and #w <= 255 and back.f.killers:find("Cccccccccccc", 1, true) and #back.f.note < 60,"when it's too long the note is trimmed before anyone's name: " .. tostring(w and #w) .. " killers=" .. tostring(back and back.f.killers) .. " note=" .. tostring(back and back.f.note))
  -- the profile line's hover and the board row show the note (data only: the row is the contract)
  check(C.List()[1] ~= nil and (function() for _, r in ipairs(C.List()) do if r.note == "Caught me AFK" then return true end end end)(), "the Bounty board rows carry the note")

  -- a bounty target spotted
  ns.Toast.Push = function(spec) pushed[#pushed + 1] = spec end
  RaidWarningFrame = {}
  RaidNotice_AddMessage = function(_, text) centre[#centre + 1] = text end
  pushed = {}
  bty({ cid = "sp1", target = "Hunted One:ROGUE:24:", amount = 250000, state = "open", killer = "", age = 1, updage = 1, days = 5, note = "Gank him" }, "sp1")
  pushed = {}
  ADVANCE(400)
  enemyUnits.target = { "Hunted", "One", false }
  FIRE("PLAYER_TARGET_CHANGED")
  check(#centre == 1 and centre[1]:find("Hunted One", 1, true) and centre[1]:find("25g", 1, true) and centre[1]:find("Hillsbrad", 1, true),
    "bounty target spotted: a centre-screen message with the name, amount and zone: " .. tostring(centre[1]))
  local spot = pushed[#pushed]
  check(spot and spot.kind == "contract" and spot.category == "bounty" and spot.alert and spot.longer and spot.alertSound
    and spot.header == L.HEADER_BOUNTY_SPOTTED and spot.player == "Hunted One" and #pushed == 1 and ns.Plain(spot.text):find("Gank him", 1, true),
    "...and one bounty toast (the longer, louder kind), not a normal sighting")
  FIRE("PLAYER_TARGET_CHANGED")
  FIRE("UPDATE_MOUSEOVER_UNIT")
  check(#centre == 1 and #pushed == 1, "not again within 5 minutes")
  local logged = false
  for _, l in ipairs(FriendsAndFoesDB.debugLog or {}) do if l:find("BOUNTY-SPOTTED", 1, true) then logged = true end end
  check(logged, "[BOUNTY-SPOTTED] is in the debug log")
  ADVANCE(301)
  FIRE("PLAYER_TARGET_CHANGED")
  check(#centre == 2 and #pushed == 2, "after 5 minutes: again")
  -- a friend sees them: the bounty toast style, no centre-screen message
  ADVANCE(301)
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("SIGHT", { name = "Hunted One", class = "ROGUE", level = "24", guild = "", zone = "Duskwood" }, "sp2"), "WHISPER", 77)
  local fs = pushed[#pushed]
  check(#centre == 2 and #pushed == 3 and fs.alert and fs.header == L.HEADER_BOUNTY_SPOTTED and ns.Plain(fs.title):find("spotted by", 1, true),
    "a friend's sighting of a bounty target: the bounty toast, no centre message")
  -- nobody with a bounty: a normal sighting
  FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("SIGHT", { name = "Plain Foe", class = "MAGE", level = "24", guild = "", zone = "Duskwood" }, "sp3"), "WHISPER", 77)
  check(pushed[#pushed].kind == "sighting" and not pushed[#pushed].alert, "a sighting with no bounty is the normal toast")
  -- done or run-out bounties don't count
  FriendsAndFoesDB.contracts["Buddy Pal/sp1"].state = "done"
  ADVANCE(301)
  FIRE("PLAYER_TARGET_CHANGED")
  check(#centre == 2, "a finished bounty: no alert")
  FriendsAndFoesDB.contracts["Buddy Pal/sp1"].state = "open"
  FriendsAndFoesDB.contracts["Buddy Pal/sp1"].t = time() - 6 * 86400
  ADVANCE(301)
  FIRE("PLAYER_TARGET_CHANGED")
  check(#centre == 2, "a bounty past its days: no alert")
  FriendsAndFoesDB.contracts["Buddy Pal/sp1"].t = time()
  -- the bounty alert setting: chat = a chat line only; off = nothing
  ns.S().show.contract = "chat"
  ADVANCE(301)
  CHAT = {}
  local nBefore = #pushed
  FIRE("PLAYER_TARGET_CHANGED")
  check(#centre == 2 and #pushed == nBefore + 1 and pushed[#pushed].alert, "alerts on 'chat': no centre message (the toast goes out as a chat line)")
  ns.S().show.contract = "off"
  ADVANCE(301)
  local n = #pushed
  FIRE("PLAYER_TARGET_CHANGED")
  check(#centre == 2 and #pushed == n, "alerts off: nothing at all")
  ns.S().show.contract = "toast"
  -- Where it works: in an instance set to 'off' nothing; 'hold' no centre message
  IN_INSTANCE = true
  ns.S().instances = "off"
  ADVANCE(301)
  FIRE("PLAYER_TARGET_CHANGED")
  check(#centre == 2 and #pushed == n, "in an instance set to off: nothing")
  IN_INSTANCE = nil
  -- the real toast: twice as long, the raid-warning sound, a red edge (real Toast.Push)
  ns.Toast.Push = realPush
  drainToasts()
  ns.S().sound.enabled, ns.S().sound.contract = true, true
  local lastSound
  local origPlay = PlaySound
  PlaySound = function(id) lastSound = id end
  local shown = ns.Toast.shown or 0
  ADVANCE(301)
  FIRE("PLAYER_TARGET_CHANGED")
  check((ns.Toast.shown or 0) == shown + 1 and lastSound == 8959, "the real bounty toast shows with the raid-warning sound: " .. tostring(lastSound))
  PlaySound = origPlay
  drainToasts()
  -- no RaidNotice: the error text frame is used instead, never an error
  RaidNotice_AddMessage = nil
  local errText
  UIErrorsFrame = { AddMessage = function(_, text) errText = text end }
  ns.Toast.Centre("hello")
  check(errText == "hello", "without the raid-warning frame the centre message uses the error text")
  UIErrorsFrame, RaidWarningFrame = nil, nil
  ns.Toast.Centre("nowhere")
  ns.S().instances, ns.S().show.contract, ns.S().show.sighting = ns.S().instances, showWas, sightWas

  -- nemesis: most kills; a tie goes to the most recent killer; no times known = the old order
  local a, b = D.Hit("Nem Alpha"), D.Hit("Nem Bravo")
  a.kv, b.kv = { ["Tie Victim"] = 3 }, { ["Tie Victim"] = 3 }
  check(P.Nemesis("Tie Victim").name == "Nem Alpha", "nemesis tie, no times known: the first by name (as before)")
  a.kt, b.kt = { ["Tie Victim"] = 1000 }, { ["Tie Victim"] = 2000 }
  local nem, times = P.Nemesis("Tie Victim")
  check(nem.name == "Nem Bravo" and times == 3, "nemesis tie: the one who killed most recently")
  a.kt["Tie Victim"] = 3000
  check(P.Nemesis("Tie Victim").name == "Nem Alpha", "...whichever it is")
  a.kv["Tie Victim"] = 2
  check(P.Nemesis("Tie Victim").name == "Nem Bravo", "more kills still beat a more recent kill")
  b.kv["Tie Victim"] = nil
  check(P.Nemesis("Tie Victim").name == "Nem Alpha", "(and one kill count is enough)")
  check(P.NemesisBeats(1, nil, "A", nil, nil, nil) and not P.NemesisBeats(1, nil, "B", 1, nil, "A") and P.NemesisBeats(1, 5, "B", 1, nil, "A"),
    "the shared rule: nothing yet, then times, then names")
  ns.eventTime = 5000
  local killer = D.Hit("Nem Charlie")
  ns.Flavor.Died({ name = "Tie Victim" }, "Tie Victim", "Nem Charlie", killer, "Duskwood")
  ns.eventTime = nil
  check(killer.kt and killer.kt["Tie Victim"] == 5000, "a death at their hands records when")
  -- the weekly summary uses the same rule
  local weeklyWas = FriendsAndFoesDB.weekly
  FriendsAndFoesDB.weekly = { start = time() - 8 * 86400, k = 1, d = 4, killers = { Aaa = 2, Bbb = 2 }, killedAt = { Aaa = 100, Bbb = 200 }, bt = 0 }
  local said = {}
  local chatWas = ns.Toast.Chat
  ns.Toast.Chat = function(text) said[#said + 1] = ns.Plain(text) end
  ns.Events.WeeklyRoll()
  RUN_TIMERS()
  check(said[1] and said[1]:find("Nemesis: Bbb", 1, true), "weekly summary: a tie goes to the most recent killer: " .. tostring(said[1]))
  FriendsAndFoesDB.weekly = { start = time() - 8 * 86400, k = 1, d = 4, killers = { Aaa = 2, Bbb = 2 }, killedAt = { Aaa = 300, Bbb = 200 }, bt = 0 }
  said = {}
  ns.Events.WeeklyRoll()
  RUN_TIMERS()
  check(said[1] and said[1]:find("Nemesis: Aaa", 1, true), "...either way round")
  ns.Toast.Chat = chatWas
  FriendsAndFoesDB.weekly = { start = time(), k = 0, d = 0, killers = {}, bt = 0 }
  ns.Events.WeeklyAdd("d", "Zed Zed")
  check(FriendsAndFoesDB.weekly.killedAt and FriendsAndFoesDB.weekly.killedAt["Zed Zed"], "a death records when its killer got you")
  FriendsAndFoesDB.weekly = weeklyWas

  -- tidy up
  for _, name in ipairs({ "Ru Mia", "Ui Added", "Zork Quux", "Targ Et", "Dlg Foe", "Note Foe", "Rude Foe", "Kind Foe", "Old Foe", "Hunted One",
    "Nem Alpha", "Nem Bravo", "Nem Charlie", "Plain Foe" }) do
    rr.hitlist[name], rr.players[name] = nil, nil
  end
  for k, v in pairs(o) do _G[k] = v end
  FriendsAndFoesDB.contracts = savedContracts
  ns.S().debug = debugWas
  drainToasts()
  check(ns.errors == errs, "no errors in 1.0.1 features (" .. tostring(ns.lastError) .. ")")
end

-- 1.0.1: the Stats page and your kill log
do
  local errs = ns.errors
  local St = ns.Stats
  local logWas, bestWas, streakWas = FriendsAndFoesDB.killLog, FriendsAndFoesCharDB.bestStreak, FriendsAndFoesCharDB.streak
  FriendsAndFoesDB.killLog = nil
  -- your own live kill is logged with both levels and the zone (you are level 30 in the mock)
  ns.Events.Emit("KILL", { victim = "Log Bob", vclass = "MAGE", vlevel = "33", vguild = "", zone = "Duskwood" })
  local e1 = FriendsAndFoesDB.killLog and FriendsAndFoesDB.killLog[1]
  check(e1 and e1.n == "Log Bob" and e1.vl == 33 and e1.ml == 30 and e1.z == "Duskwood" and e1.t, "a live kill is logged: name, both levels, zone, time")
  ns.Events.Emit("KILL", { victim = "Log Skull", vclass = "MAGE", vlevel = "0", vguild = "", zone = "Duskwood" })
  ns.Events.Emit("KILL", { victim = "Log Unknown", vclass = "MAGE", vlevel = "", vguild = "", zone = "" })
  local log = FriendsAndFoesDB.killLog
  check(#log == 3 and log[2].vl == -1 and log[3].vl == nil and log[3].z == nil, "skull is stored as -1, unknown as nil")
  -- caught-up kills are never logged
  ns.past = true
  ns.Events.Emit("KILL", { victim = "Log Old", vclass = "MAGE", vlevel = "30", vguild = "", zone = "Duskwood" })
  ns.past = nil
  check(#FriendsAndFoesDB.killLog == 3, "a caught-up kill is not logged")
  -- the cap: 1000, oldest dropped
  FriendsAndFoesDB.killLog = {}
  for i = 1, St.LOG_MAX do FriendsAndFoesDB.killLog[i] = { t = i, n = "N" .. i, vl = 30, ml = 30 } end
  St.Log("Newest One", "31", "Duskwood")
  local capped = FriendsAndFoesDB.killLog
  check(#capped == 1000 and capped[1].n == "N2" and capped[1000].n == "Newest One", "the log keeps the newest 1000")
  -- the best streak is remembered (the current one is Events.lua's)
  FriendsAndFoesDB.bestStreak, FriendsAndFoesCharDB.bestStreak, FriendsAndFoesCharDB.streak = 99, nil, 0
  for i = 1, 3 do ns.Events.Emit("KILL", { victim = "Streak Log" .. i, vclass = "MAGE", vlevel = "30", vguild = "", zone = "Duskwood" }) end
  local cur, best = St.Streaks()
  check(cur == 3 and best == 3 and FriendsAndFoesDB.bestStreak == 99, "streaks: current and best (per character; the old account value is ignored)")
  FriendsAndFoesCharDB.streak = 0
  cur, best = St.Streaks()
  check(cur == 0 and best == 3, "a death ends the current streak, the best stays")

  -- the numbers (a made-up log, noon on a Monday; you are 30)
  local noon = time({ year = 2026, month = 6, day = 15, hour = 12 })
  local function k(ago, vl, ml, z) return { t = noon - ago, c = ns.me, n = "V", vl = vl, ml = ml, z = z } end
  FriendsAndFoesDB.killLog = {
    k(3600, 20, 30, "Duskwood"),     -- grey (22 or less), today, Monday 11:00
    k(3700, 26, 30, "Duskwood"),     -- lower (4 below), today, Monday 10:58
    k(3650, 28, 30, "Duskwood"),     -- even (2 below), today, Monday 10:59
    k(2 * 86400, 30, 30, "Barrens"), -- even, this week
    k(2 * 86400 + 60, 32, 30, "Barrens"), -- even (2 above)
    k(3 * 86400, 33, 30, "Barrens"), -- higher (3 above)
    k(20 * 86400, 40, 30, "Ashenvale"), -- higher, this month only
    k(40 * 86400, -1, 30, "Ashenvale"), -- skull, older than a month
    k(5 * 86400, nil, 30, nil),      -- unknown level: not in the bars or averages
  }
  local s = St.Compute(noon)
  check(s.tiers.grey == 1 and s.tiers.lower == 1 and s.tiers.even == 3 and s.tiers.higher == 2 and s.tiers.skull == 1 and s.tiered == 8,
    "gap tiers: grey / lower / even / higher / skull, unknown left out")
  check(s.today == 3 and s.week == 7 and s.month == 8 and s.n == 9, "kills today / last 7 days / last 30 days: " .. s.today .. "/" .. s.week .. "/" .. s.month)
  -- average level: 20 26 28 30 32 33 40 = 209 / 7 (skull and unknown excluded); gap = -10 -4 -2 0 2 3 10 = -1 / 7
  check(math.abs(s.avgLevel - 209 / 7) < 1e-9 and math.abs(s.avgGap - (-1 / 7)) < 1e-9, "averages leave out skull and unknown levels")
  check(St.GapText(s.avgGap) == "your level" and St.GapText(3.2) == "3 higher than you" and St.GapText(-1.6) == "2 lower than you" and St.GapText(nil) == nil, "the gap in words")
  check(s.zones[1].name == "Barrens" and s.zones[1].n == 3 and s.zones[2].name == "Duskwood" and s.zones[2].n == 3 and s.zones[3].name == "Ashenvale" and #s.zones == 3,
    "top zones: most first, ties by name")
  local many = {}
  for i = 1, 8 do many[#many + 1] = { t = noon, c = ns.me, vl = 30, ml = 30, z = "Zone" .. i } end
  FriendsAndFoesDB.killLog = many
  check(#St.Compute(noon).zones == 5, "at most 5 zones")
  -- busiest weekday and hour: only from 20 logged kills (19 shows nothing)
  local mon = time({ year = 2026, month = 6, day = 15, hour = 11, min = 30 })
  local busy = {}
  for i = 1, 19 do busy[i] = { t = mon - i, c = ns.me, vl = 30, ml = 30, z = "A" } end
  FriendsAndFoesDB.killLog = busy
  s = St.Compute(noon)
  check(s.n == 19 and s.busyDay == nil and s.busyHour == nil, "19 kills: no busiest weekday or hour yet")
  busy[20] = { t = mon - 20, c = ns.me, vl = 30, ml = 30, z = "B" }
  s = St.Compute(noon)
  check(s.n == 20 and s.busyDay == 2 and s.busyHour == 11, "20 kills: busiest weekday and hour (Monday, 11:00)")
  -- average level and gap: only from 5 kills with a known, non-skull level (4 shows nothing)
  local function lv(n) local l = {} for i = 1, n do l[i] = { t = noon - i, c = ns.me, vl = 30 + i, ml = 30 } end return l end
  FriendsAndFoesDB.killLog = lv(4)
  s = St.Compute(noon)
  check(s.avgLevel == nil and s.avgGap == nil and s.levelN == 4, "4 known levels: no average level or gap yet")
  local tiles4 = ns.UI.StatsView().tiles
  check(tiles4[3][1] == "-" and tiles4[3][4] and tiles4[3][2] == "Average victim" and tiles4[3][6] == "4/5 kills" and tiles4[3][7] == "4/5 kills", "locked average shows its progress, visibly")
  check(ns.UI.StatsView().hunt[4][2] == "4/20 kills" and ns.UI.StatsView().hunt[4][3] and ns.UI.StatsView().hunt[4][4] == "4/20 kills" and ns.UI.StatsView().hunt[4][5], "locked busiest day shows its progress and explains the unlock")
  busy[20] = nil
  FriendsAndFoesDB.killLog = busy -- (19 kills)
  check(ns.UI.StatsView().hunt[5][4] == "19/20 kills", "19/20 kills: still locked")
  busy[20] = { t = mon - 20, c = ns.me, vl = 30, ml = 30, z = "B" }
  check(ns.UI.StatsView().hunt[5][4] == nil and ns.UI.StatsView().hunt[4][2] == "Monday", "20/20: the lock is gone and the value shows")
  FriendsAndFoesDB.killLog = lv(5)
  s = St.Compute(noon)
  check(s.avgLevel == 33 and s.avgGap == 3, "5 known levels: the averages show")
  -- per character: another character's entries and entries without one don't count
  FriendsAndFoesDB.killLog = { { t = noon - 5, c = "Other Char", vl = 30, ml = 30, z = "Elsewhere" }, { t = noon - 6, vl = 30, ml = 30, z = "Elsewhere" },
    { t = noon - 7, c = ns.me, vl = 30, ml = 30, z = "Here" } }
  s = St.Compute(noon)
  check(s.n == 1 and s.today == 1 and s.tiered == 1 and #s.zones == 1 and s.zones[1].name == "Here", "only this character's entries count")
  St.Log("Mine Too", "30", "Here")
  check(FriendsAndFoesDB.killLog[#FriendsAndFoesDB.killLog].c == ns.me, "a logged kill records its character")
  -- the tiles: Kills logged first, and no overlap with the profile
  local vw = ns.UI.StatsView()
  check(#vw.tiles == 3 and vw.tiles[1][1] == "2" and vw.tiles[1][2] == "Kills logged", "Kills logged is the first tile and counts this character's log")
  check(vw.tiles[2][2] == "Best streak" and vw.tiles[2][6]:find("now ", 1, true) and vw.tiles[1][6] == "", "the streak tile shows the best and, on its own line, the current run")
  local blob = ""
  for _, tl in ipairs(vw.tiles) do blob = blob .. tl[2] end
  for _, h in ipairs(vw.hunt) do blob = blob .. h[1] end
  check(not blob:find("Nemesis", 1, true) and not blob:find("Most killed", 1, true) and not blob:find("Players killed", 1, true), "the profile's lines are not repeated")
  -- the tile for the average: level, and the gap folded into its caption
  FriendsAndFoesDB.killLog = lv(5)
  vw = ns.UI.StatsView()
  check(vw.tiles[3][1] == "Level 33.0" and vw.tiles[3][2] == "Average victim" and vw.tiles[3][6] == "3 higher than you" and not vw.tiles[3][4], "average tile: level, with the gap in words on its own line")
  -- the charts: Skull to Grey, counts with their share of Kills logged; a long zone name is kept whole
  local longZone = "Hillsbrad Foothills (Tarren Mill and the Whole Old Hillsbrad Area)"
  FriendsAndFoesDB.killLog = {
    { t = noon - 1, c = ns.me, vl = -1, ml = 30, z = longZone },
    { t = noon - 2, c = ns.me, vl = 30, ml = 30, z = longZone },
    { t = noon - 3, c = ns.me, vl = 30, ml = 30, z = "Duskwood" },
    { t = noon - 4, c = ns.me, vl = 10, ml = 30, z = "Duskwood" },
  }
  vw = ns.UI.StatsView()
  local order = {}
  for _, r in ipairs(vw.gap) do order[#order + 1] = r[1] end
  check(table.concat(order, ",") == "Skull,Higher,Even,Lower,Grey", "level-gap rows run Skull to Grey")
  check(vw.gap[1][4] == "1 (25%)" and vw.gap[3][4] == "2 (50%)" and vw.gap[2][4] == "0" and vw.gap[5][4] == "1 (25%)", "counts with their share of Kills logged; zero is just 0")
  check(vw.gap[4][5] and vw.gap[4][5]:find("3 or more levels below you", 1, true), "a level-gap row explains its tier")
  check(vw.zones[1][1] == "Duskwood" and vw.zones[2][1] == longZone and vw.zones[2][4] == "2 (50%)", "zone names are not cut in the view data")
  FriendsAndFoesDB.killLog = {}
  vw = ns.UI.StatsView()
  check(vw.empty and vw.tiles[1][1] == "0" and vw.tiles[3][1] == "-" and vw.tiles[3][6] == "0/5 kills" and vw.hunt[1][2] == "0", "empty log: zeros, dashes and progress")

  -- the page: a Stats button on your own profile only
  ns.UI.ShowProfile(ns.me)
  local ctl = ns.UI.Frames().profile.controls
  check(ctl.stats:IsShown(), "your own profile has a Stats button")
  ns.UI.ShowProfile("Buddy Pal")
  check(not ctl.stats:IsShown(), "a friend's profile has none")
  ns.UI.ShowProfile("Rogz Fang")
  check(not ctl.stats:IsShown(), "an enemy's profile has none")
  ns.UI.ShowProfile(ns.me)
  for _, log2 in ipairs({ {}, { { t = noon - 100, c = ns.me, n = "Log Bob", vl = 33, ml = 30, z = "Duskwood" }, { t = noon - 5, c = ns.me, vl = -1, ml = 30 } } }) do
    FriendsAndFoesDB.killLog = log2
    ns.UI.ShowProfile(ns.me)
    ns.UI.ShowStats()
    local page = ns.UI.Frames().stats
    check(ns.UI.CurrentTab() == "stats" and page:IsShown() and not ns.UI.Frames().profile:IsShown(), "Stats opens in the tab (" .. #log2 .. " kills)")
    local v = ns.UI.StatsView()
    check(v.empty == (#log2 == 0) and #v.tiles == 3 and #v.hunt == 5 and #v.gap == 5, "the page has its lines and five gap bars")
    local frames = ns.UI.Frames().stats
    if #log2 == 0 then
      local allGap = true
      for i, r in ipairs(frames.gap.rows) do allGap = allGap and r:IsShown() and r.count:GetText() == "0" and not r.fill:IsShown() end
      local placeholders = true
      for _, r in ipairs(frames.zones.rows) do placeholders = placeholders and r:IsShown() and r.label:GetText() == "" and r.count:GetText() == "" and not r.fill:IsShown() end
      check(allGap and frames.gap.rows[1].label:GetText() == "Skull" and frames.gap.rows[5].label:GetText() == "Grey", "empty: the five level rows show with 0 and no fill")
      check(placeholders and #frames.zones.rows == 5, "empty: five bare zone rows")
      check(frames.gap.alpha == 0.4 and frames.zones.alpha == 0.4 and frames.empty:IsShown() and frames.empty:GetText() == "Your first kill fills these in.", "empty: charts faded, one message")
      check(frames.tiles[3].lock:IsShown() and frames.hunt.rows[4].lock:IsShown() and frames.hunt.rows[4].value:GetText():find("0/20 kills", 1, true), "empty: locked stats show a padlock and progress")
    else
      check(frames.gap.alpha == 1 and frames.zones.alpha == 1 and not frames.empty:IsShown(), "with kills: charts at full strength, no message")
      check(frames.zones.rows[1]:IsShown() and not frames.zones.rows[2]:IsShown() and not frames.zones.rows[5]:IsShown(), "fewer than 5 zones: the unused rows are hidden, not skeletons")
      check(frames.tiles[3].lock:IsShown() and frames.tiles[3].extra:GetText() == "1/5 kills", "locked average tile: padlock, progress")
    end
    check(ns.UI.BackLabel() == ns.me, "Back goes to your profile")
    ns.UI.Back()
    check(ns.UI.CurrentTab() == "profile" and ns.UI.Frames().profile:IsShown() and not page:IsShown(), "Back returns to your profile")
  end
  FriendsAndFoesDB.killLog, FriendsAndFoesDB.bestStreak, FriendsAndFoesCharDB.bestStreak, FriendsAndFoesCharDB.streak = logWas, nil, bestWas, streakWas
  drainToasts()
  check(ns.errors == errs, "no errors in the Stats page (" .. tostring(ns.lastError) .. ")")
end

RESULTS[#RESULTS + 1] = string.format("%d passed, %d failed", passed, failed)
