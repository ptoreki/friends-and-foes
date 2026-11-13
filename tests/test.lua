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
check(ns.Comm.roster.Buddy ~= nil, "roster contains same-realm friend Buddy")

-- helpers
check(("You create: |cff|Hitem:1|h[x]|h|r."):match(ns.ToPattern(LOOT_ITEM_CREATED_SELF)) ~= nil, "ToPattern craft")
check(ns.VersionNewer("0.10.0", "0.9.9") and not ns.VersionNewer("0.2.0", "0.2.0"), "VersionNewer")
check(ns.CleanName("Bob-Nightslayer") == "Bob" and ns.CleanName("  Bob ") == "Bob", "CleanName")
local u = ns.DecodeUnit(ns.EncodeUnit({ name = "Gank", class = "ROGUE", level = 60, guild = "Bad Guys" }))
check(u.name == "Gank" and u.class == "ROGUE" and u.level == 60 and u.guild == "Bad Guys", "unit roundtrip w/ guild")

-- simulated friend events: all kinds, isolated from real data
for _, kind in ipairs(ns.Sim.KINDS) do ns.Sim.Run(kind, false) end
local sim = FriendsAndFoesDB.sim
check(sim ~= nil, "sim store created")
local sf = sim.players.Simfriend
check(sf and sf.k == 1 and sf.d == 1 and sf.level == 43,
  "Simfriend K/D/level in sim store: " .. tostring(sf and sf.k) .. "/" .. tostring(sf and sf.d) .. "/" .. tostring(sf and sf.level))
local sg = sim.hitlist.Simganker
check(sg and sg.attacks == 1 and sg.kills == 1 and sg.revenge == 1 and sg.guild == "Sim Gankers", "Simganker hitlist: attacks/kills/revenge/guild")
check(sim.hitlist.Simhelper ~= nil, "assist added to hitlist")
check(sim.players.Simhelper and sim.players.Simhelper.a == 1, "assist counted")
check(sim.players.Simganker.d == 1 and sim.players.Simganker.k == 1, "enemy K and D")
check(#sim.feed >= 6, "sim feed entries: " .. #sim.feed)
local real = ns.Data.RealRealm()
check(real.players.Simfriend == nil and real.hitlist.Simganker == nil and #real.feed == 0, "real data untouched by sim")
check(ns.viewSim == true, "window switches to sim view")
check(ns.errors == 0, "no errors after sim (" .. tostring(ns.lastError) .. ")")

-- self sim broadcasts with S-id
SENT = {}
ns.Sim.Run("kill", true)
RUN_TICKERS(2)
check(#SENT == 2, "self sim sent on both routes: " .. #SENT)
check(SENT[1] and SENT[1].payload:find("^2\tKILL\tS") ~= nil, "payload protocol 2 + sim id")

-- clear sim
ns.Sim.Clear()
check(FriendsAndFoesDB.sim == nil and not ns.viewSim, "sim cleared")

-- receive real event over BN, then duplicate over whisper
local function payload(kind, fields, id, version)
  local msg = { kind = kind, id = id, class = "PRIEST", level = 31, f = fields }
  local p = ns.Comm.Encode(msg)
  if version then p = p:gsub("\t" .. ns.VERSION .. "\t", "\t" .. version .. "\t", 1) end
  return p
end
local lv = payload("LVL", { level = 32 }, "abc1")
FIRE("BN_CHAT_MSG_ADDON", "FNF1", lv, "WHISPER", 77)
FIRE("CHAT_MSG_ADDON", "FNF1", lv, "WHISPER", "Buddy-Nightslayer")
local buddy = real.players.Buddy
check(buddy and buddy.level == 32 and buddy.friend, "received LVL applied to Buddy")
check(#real.feed == 1, "duplicate (bn + whisper) applied once, feed=" .. #real.feed)
check(ns.caps.bnet == "ok" and ns.caps.whisper == "ok", "caps ok for both routes")

-- stranger whisper ignored
FIRE("CHAT_MSG_ADDON", "FNF1", payload("LVL", { level = 5 }, "zz1"), "WHISPER", "Stranger")
check(real.players.Stranger == nil, "non-friend whisper ignored")

-- newer version
FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("LVL", { level = 33 }, "abc2", "9.9.9"), "WHISPER", 77)
check(buddy.version == "9.9.9", "friend version recorded")
FIRE("BN_CHAT_MSG_ADDON", "FNF1", "3\tLVL\tq\tX\t1\t9.9.9\t5", "WHISPER", 77)
check(ns.errors == 0, "newer protocol handled without error (" .. tostring(ns.lastError) .. ")")

-- received KILL on a hitlist enemy -> revenge; DIE builds hitlist
FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("DIE", { zone = "Duskwood", killer = "Rogz:ROGUE:60:Gank Squad", conf = "s", assists = "" }, "d1"), "WHISPER", 77)
check(real.hitlist.Rogz and real.hitlist.Rogz.kills == 1 and real.hitlist.Rogz.suspect == 1, "DIE -> hitlist with suspect kill")
FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("KILL", { victim = "Rogz", vclass = "ROGUE", vlevel = 60, vguild = "", zone = "Duskwood" }, "k1"), "WHISPER", 77)
check(real.hitlist.Rogz.revenge == 1 and buddy.k == 1, "KILL -> revenge + takedown")

-- own loot: epic BoE emits + queues broadcast
SENT = {}
FIRE("CHAT_MSG_LOOT", "You receive loot: |cffa335ee|Hitem:12584::::::::60:::::::|h[Sword]|h|r.")
RUN_TICKERS(2)
check(real.players.Testme and real.players.Testme.lastText and real.players.Testme.lastText:find("looted") ~= nil, "own loot recorded")
check(#SENT == 2 and SENT[1].payload:find("^2\tLOOT\t") ~= nil, "own loot broadcast")

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
  killer = ns.EncodeUnit({ name = "Abcdefghijkl", class = "WARLOCK", level = 60, guild = long }),
  conf = "c",
  assists = ns.EncodeUnits({
    { name = "Bcdefghijklm", class = "WARLOCK", level = 60, guild = long },
    { name = "Cdefghijklmn", class = "WARLOCK", level = 60, guild = long },
    { name = "Defghijklmno", class = "WARLOCK", level = 60, guild = long },
  }, 3) } }
local fit = ns.Comm.Fit(big)
check(fit and #fit <= 255, "Fit strips guilds to stay <=255 (" .. (fit and #fit or "nil") .. ")")

-- hitlist share: packing + receiving merge
for i = 1, 45 do
  local h = ns.Data.Hit("Enemy" .. i)
  h.class, h.level, h.guild, h.attacks, h.kills, h.lastSeen = "MAGE", 60, "Some Long Guild Name", i, 1, time() - i * 60
end
SENT = {}
local shared = ns.Comm.ShareHitlist()
check(shared == 40, "share capped at 40: " .. shared)
RUN_TICKERS(400)
local maxLen, hitMsgs = 0, 0
for _, s in ipairs(SENT) do
  if s.payload:find("^2\tHIT\t") then
    hitMsgs = hitMsgs + 1
    if #s.payload > maxLen then maxLen = #s.payload end
  end
end
check(maxLen <= 255 and hitMsgs > 0, "share payloads <=255 (max " .. maxLen .. ", msgs " .. hitMsgs .. ")")
-- receive a share chunk from Buddy
local before = count(real.hitlist)
FIRE("BN_CHAT_MSG_ADDON", "FNF1", payload("HIT", { share = "s1", entries = "Newguy:HUNTER:59:Their Guild:3:2:0:5;Enemy1:MAGE:60::99:7:1:1" }, "h1"), "WHISPER", 77)
check(count(real.hitlist) == before + 1, "share adds new entry")
check(real.hitlist.Enemy1.attacks == 99 and real.hitlist.Enemy1.kills == 7, "share merges with max()")
check(real.hitlist.Newguy.sharedBy == "Buddy", "sharedBy recorded")

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
ns.Toast.Push({ kind = "level", category = "progress", title = "x", text = "y" })
local heldSounds = SOUNDS_PLAYED or 0
IN_COMBAT = false
FIRE("PLAYER_REGEN_ENABLED")
check(heldSounds == beforeSounds and (SOUNDS_PLAYED or 0) > heldSounds, "progress toast held in combat, shown after")

-- prune
local old = ns.Data.Player("Oldie")
old.enemy, old.lastSeen = true, time() - 100 * 86400
ns.Data.Prune()
check(real.players.Oldie == nil and real.hitlist.Enemy1 ~= nil, "prune removes stale harmless enemies only")

-- UI + slash commands exercise
SlashCmdList.FRIENDSANDFOES("")
for _, tab in ipairs({ "hitlist", "enemies", "friends", "feed", "settings" }) do ns.UI.SelectTab(tab) end
ns.UI.ShowPlayer("Rogz")
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
ns.S().debug = false
ns.Try("forced", function() error("boom") end)
check(#FriendsAndFoesDB.errorLog == 1, "errors recorded even with debug off")

RESULTS[#RESULTS + 1] = string.format("%d passed, %d failed", passed, failed)
