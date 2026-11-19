local _, ns = ...
local L = ns.L

-- Slash commands: /fnf and everything after it. Each one calls into the window (UI.lua,
-- UIProfile.lua) or the add-on's other parts; nothing here keeps state of its own.
local UI = ns.UI

local function say(text) print("|cff33ff99" .. L.ADDON .. "|r " .. text) end
local function why(reason) say(L[reason] or tostring(reason)) end

local function groupCommand(arg)
  local prefix = "|cff33ff99" .. L.ADDON .. "|r "
  if arg == "all" or arg == "clear" then
    ns.Comm.ClearPicks()
    print(prefix .. L.PICK_NOW_ALL)
  elseif arg ~= "" then
    ns.Comm.RebuildRoster()
    local name, tagOrWhy = ns.Comm.FindCandidate(arg)
    if not name then
      print(prefix .. (tagOrWhy == "ambiguous" and L.PICK_AMBIGUOUS or L.PICK_NOT_FOUND):format(arg))
      return
    end
    UI.TogglePick(name)
    return
  end
  ns.Comm.RebuildRoster()
  print(prefix .. (ns.Comm.GroupActive() and L.PICK_HINT_ACTIVE or L.PICK_HINT_ALL))
  local names = ns.Comm.EveryoneNames()
  if #names == 0 then print("  " .. L.SHARE_NO_FRIENDS) end
  for _, name in ipairs(names) do
    local tag = ns.Comm.TagFor(name)
    local mark = ns.Comm.Allowed(tag) and "|cff33ff33[x]|r " or "[ ] "
    print("  " .. mark .. name .. " (" .. tostring(tag or "?") .. ")")
  end
  print("  " .. L.PICK_USAGE)
end

SLASH_FRIENDSANDFOES1 = "/fnf"
-- /fnf wanted [name | clear]: no name = your current target
local function wantedCommand(arg)
  local prefix = "|cff33ff99" .. L.ADDON .. "|r "
  if arg:lower() == "clear" then
    ns.Profile.SetWanted(nil)
    print(prefix .. L.WANTED_CLEARED)
    return
  end
  local name = ns.CleanName(arg)
  if not name then
    local info = ns.PvP.ReadEnemy("target")
    name = info and info.name
  end
  if not name then
    print(prefix .. L.WANTED_USAGE)
    return
  end
  -- a bare first name means the one enemy you know by it, if there's exactly one
  local players = ns.Data.RealRealm().players
  name = ns.Data.Resolve(players, name)
  print(prefix .. L.WANTED_SET:format(ns.Profile.SetWanted(name)))
  UI.Refresh()
end

-- "<group name> <rest>": the longest group name the text starts with
local function splitGroup(text)
  local best, rest
  for _, g in ipairs(ns.Groups.Mine()) do
    local n = ns.Groups.Label(g):lower()
    local t = text:lower()
    if (t == n or t:sub(1, #n + 1) == n .. " ") and (not best or #n > #best.name) then
      best, rest = g, strtrim(text:sub(#n + 1))
    end
  end
  return best, rest
end

-- /fnf groups [new <name> | invite <group> <friend> | join <group> | leave <group> | remove <group> <member>]
local function groupsCommand(arg)
  local sub, rest = arg:match("^(%S+)%s*(.*)$")
  sub = sub and sub:lower()
  if sub == "new" then
    return UI.CreateGroup(rest)
  end
  if sub == "invite" or sub == "join" or sub == "leave" or sub == "decline" or sub == "remove" then
    local g, more = splitGroup(rest)
    if not g then return say(L.GROUP_UNKNOWN:format(rest)) end
    UI.UseBoardView(g.id)
    if sub == "invite" then return UI.InviteToGroup(more) end
    if sub == "join" then return UI.JoinGroup() end
    if sub == "decline" then return UI.LeaveGroup(true) end
    if sub == "leave" then
      local ok, reason = ns.Groups.Leave(g)
      if not ok then return why(reason) end
      UI.UseBoardView("friends")
      return say(L.GROUP_LEFT:format(ns.Groups.Label(g)))
    end
    local key = ns.Groups.MemberByName(g, ns.CleanName(more) or more)
    if not key then return why("GROUP_NOT_MEMBER") end
    local ok, reason = ns.Groups.Remove(g, key)
    if not ok then return why(reason) end
    return say(L.GROUP_MEMBER_REMOVED:format(more, ns.Groups.Label(g)))
  end
  if not ns.Groups.MyKey() then return why("GROUP_NO_TAG") end
  local mine = ns.Groups.Mine()
  if #mine == 0 then say(L.GROUPS_NONE) end
  for _, g in ipairs(mine) do
    local names = {}
    for _, m in ipairs(ns.Groups.Members(g)) do
      names[#names + 1] = m.name .. (m.leader and (" " .. L.GROUP_LEADER_TAG) or "")
        .. (m.state == "invited" and (" " .. L.GROUP_INVITED_TAG) or "")
    end
    local tag = ns.Groups.MyState(g) == "invited" and ("  " .. L.GROUP_INVITED_TAG) or ""
    print("  " .. ns.Groups.Label(g) .. tag .. ": " .. table.concat(names, ", "))
  end
  print("  " .. L.GROUPS_USAGE)
end

SlashCmdList.FRIENDSANDFOES = function(msg)
  local raw = strtrim(msg or "") -- names keep their capitals
  msg = raw:lower()
  local prefix = "|cff33ff99" .. L.ADDON .. "|r "
  if msg == "" then
    UI.Toggle()
  elseif msg == "board" or msg == "leaderboard" then
    UI.Show("board")
  elseif msg == "groups" or msg:find("^groups ") then
    groupsCommand(strtrim(raw:sub(7)))
    UI.Refresh()
  elseif msg == "profile" or msg:find("^profile ") then
    local who = strtrim(raw:sub(8))
    UI.ShowProfile(who ~= "" and (ns.CleanName(who) or who) or ns.me)
  elseif msg == "wanted" or msg:find("^wanted ") then
    wantedCommand(strtrim(raw:sub(7)))
  elseif msg == "settings" or msg == "config" or msg == "options" then
    UI.OpenSettings()
  elseif msg == "unlock" then
    ns.Toast.SetUnlocked(true)
  elseif msg == "lock" then
    ns.Toast.SetUnlocked(false)
  elseif msg == "test" then
    ns.Toast.Test()
  elseif msg == "status" then
    ns.PrintStatus()
  elseif msg == "share" then
    UI.ShareHitlist()
  elseif msg == "debug" then
    ns.SetDebug(not ns.S().debug)
    print(prefix .. "debug: " .. (ns.S().debug and "on" or "off"))
    UI.RefreshSettings()
  elseif msg == "tour" then
    UI.Show()
    ns.Tour.Show(FriendsAndFoesFrame)
  elseif msg == "report" then
    ns.Report.Show()
  elseif msg == "debug clear" then
    wipe(FriendsAndFoesDB.debugLog)
    wipe(FriendsAndFoesDB.errorLog)
    print(prefix .. "debug + error logs cleared")
  elseif msg:find("^size") then
    local n = tonumber(msg:match("%d+"))
    if n and n >= 70 and n <= 150 then
      ns.S().toastScale = n / 100
      ns.Toast.ApplyScale()
      ns.Toast.Test()
    else
      print(prefix .. L.SIZE_USAGE:format(math.floor((tonumber(ns.S().toastScale) or 1) * 100 + 0.5)))
    end
  elseif msg:find("^duration") then
    local n = tonumber(msg:match("%d+"))
    if n and n >= 2 and n <= 10 then
      ns.S().toastDuration = n
      print(prefix .. L.DURATION_SET:format(n))
    else
      print(prefix .. L.DURATION_USAGE:format(tonumber(ns.S().toastDuration) or 3))
    end
  elseif msg == "minimap reset" then
    local mm = ns.S().minimap
    mm.free, mm.x, mm.y, mm.angle, mm.hide = false, nil, nil, 210, false
    if ns.Minimap then ns.Minimap.Place(); ns.Minimap.Update() end
    print(prefix .. L.MINIMAP_RESET)
  elseif msg == "bounty" or msg:find("^bounty ") then
    local amount = strtrim(msg:sub(7))
    if amount == "" then print(prefix .. L.BOUNTY_USAGE) end
    if ns.PvP.ReadEnemy("target") then UI.PostBounty(nil, amount) elseif amount ~= "" then why("CONTRACT_NEED_TARGET") end
  elseif msg == "minimap" then
    ns.S().minimap.hide = not ns.S().minimap.hide
    if ns.Minimap then ns.Minimap.Update() end
  elseif msg == "chat" or msg:find("^chat ") then
    local n = tonumber(strtrim(msg:sub(5)))
    if n and n >= 1 and n <= 10 and math.floor(n) == n then
      ns.S().chatFrame = n
      print(prefix .. L.CHAT_TAB_SET:format(n))
      ns.Toast.Chat(L.CHAT_TAB_SET:format(n))
    else
      print(prefix .. L.CHAT_TAB_USAGE:format(ns.S().chatFrame or 1))
    end
  elseif msg == "alerts" or msg:find("^alerts ") then
    groupCommand(strtrim(msg:sub(7))) -- your alert list
  elseif msg == "group" or msg:find("^group ") then
    groupCommand(strtrim(msg:sub(6))) -- (the old name of /fnf alerts)
  elseif msg == "sim" or msg:find("^sim ") then
    ns.Sim.Command(strtrim(msg:sub(4)))
  else
    print(prefix .. L.HELP)
  end
end
