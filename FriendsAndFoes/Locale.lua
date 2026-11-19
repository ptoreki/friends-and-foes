local _, ns = ...

-- All user-facing strings live here, in English. A missing one shows its key instead of breaking
-- anything (tests/locale.js checks every string the code uses is defined).
--
-- Translating: add a file Locale_xxXX.lua (deDE, frFR, esES, ...) to the .toc right after this
-- one, starting with
--   local _, ns = ...
--   if GetLocale() ~= "deDE" then return end
--   local L = ns.L
-- then set only the strings you translate (L.TAB_HITLIST = "Abschussliste"); the rest stay
-- English. Keep every %s / %d in the same order. Don't translate keys used as tables
-- (L.COLUMN_TIPS, L.PROFILE_TIPS) without their labels: they're looked up by the label text.
local L = setmetatable({}, { __index = function(_, k) return k end })
ns.L = L

L.ADDON = "Friends & Foes"
L.UNKNOWN_ENEMY = "an unknown enemy"

-- toasts
L.TOAST_LEVEL = "%s leveled up"
L.TOAST_GEAR_MORE = "%s +%d more"
L.TOAST_LEVEL_MAX = "%s hit level %d!"
L.CHAT_PREFIX = "F&F:"
-- toast themes
L.OPT_THEME = "Toast style"
L.THEME_NAMES = { minimal = "Modern", achievement = "Classic", alliance = "Alliance", horde = "Horde" }
-- Achievement-style toasts: the small header above the message
L.HEADER = {
  attacked = "Friend under attack", engage = "Friend on the attack", died = "Friend killed", kill = "Friend's kill",
  level = "Level up", loot = "Epic loot", gear = "New gear", sighting = "Hitlist sighting",
  contract = "Bounty board",
}
L.HEADER_MILESTONE = { level = "Max level!", loot = "Epic BoE!" }
L.HEADER_REVENGE = "Revenge!"
L.HEADER_STREAK = "Kill streak!"
L.CHAT_SHARE = "%s is sharing their hitlist with you"
L.TOOLTIP_HIT = "Hitlist: %d kills on us"
L.TOOLTIP_VICTIMS = "killed %s"
-- sightings: "Hitlist: Rogz nearby · 2 kills, 3 attacks · Refuge Pointe"
L.SIGHTING = "Hitlist: %s nearby"
L.SIGHTING_RECORD = "%d kills on us"

-- PvP wording (Flavor.lua): who did what; extras and the place follow after " · ".
-- Lists: one is picked at random for variety.
L.DIED = { "%s killed by %s", "%s fell to %s", "%s ganked by %s", "%s taken down by %s" }
L.DIED_UNKNOWN = { "%s killed by an enemy player", "%s fell to an unseen enemy", "%s got ganked" }
L.DIED_AGAIN = "%s killed %s again (%s)"
L.DIED_NUMBER = "%s has %s's number (%s)"
L.DIED_NEMESIS = "%s's nemesis %s strikes (%s)"
L.TODAY = "%s today"
L.STREAK = "%d in a row"
L.STREAK_BIG = "%d in a row!"
L.STREAK_ENDED = "ended a %d-kill streak"
L.KILL = { "%s killed %s", "%s took down %s", "%s dropped %s", "%s sent %s to the spirit healer" }
L.KILL_UNKNOWN = "%s got a kill"
L.KILL_REVENGE = "%s got revenge on %s"
L.KILL_AVENGED = "%s avenged %s on %s"
L.KILL_OWNS = "%s owns %s (%s)"
L.ATTACKED = { "%s attacked by %s", "%s jumped by %s", "%s in a fight with %s" }
L.ATTACKER_HISTORY = "(killed them %d×)"
-- flavor off: who did what (the place is added after " · ")
L.SHORT_DIED = "%s killed by %s"
L.SHORT_DIED_UNKNOWN = "%s killed by an enemy player"
L.SHORT_KILL = "%s killed %s"
L.SHORT_REVENGE = "%s killed %s (revenge)"
L.SHORT_ATTACKED = "%s attacked by %s"
L.SHORT_ENGAGE = "%s attacked %s"
L.ENGAGE = { "%s attacked %s", "%s jumped %s", "%s picked a fight with %s" }
L.ENGAGE_HITLIST = "%s is going after %s (hitlist)"

-- feed
L.FEED_LEVEL = "%s reached level %d"
L.FEED_LOOT = "%s looted %s"
L.FEED_CRAFT = "%s crafted %s"
L.FEED_GEAR = "%s equipped %s"

-- window
L.TAB_HITLIST = "Hitlist"
L.TAB_FRIENDS = "Friends"
L.BTN_OPTIONS = "Options"
L.FRIEND_ONLINE = "online"
L.PICK_ON = "%s (%s) added to your alert list - you now get their alerts and they get yours."
L.PICK_OFF = "%s (%s) removed from your alert list - no alerts to or from them."
L.PICK_NOW_ALL = "Your alert list is empty - alerts from every friend with the addon again."
L.PICK_NO_TAG = "Can't add %s to your alert list: Battle.net doesn't show their BattleTag right now (are they online?)."
L.PICK_NOT_FOUND = "No online friend in WoW Forever matches '%s'."
L.PICK_AMBIGUOUS = "Several friends match '%s' - use their full name or BattleTag."
L.TAB_FEED = "Feed"
L.COL_NAME = "Name"
L.COL_LEVEL = "Lvl"
L.COL_KILLS = "Kills"
L.COL_VICTIMS = "Victims"
L.COL_LAST = "Last seen"
L.COL_DEATHS = "Deaths"
L.COL_TIME = "When"
L.COL_EVENT = "Event"
L.EMPTY = "Nothing here yet."

-- settings
L.SHARE_HEADER = "Share with friends"
L.ALERTS_HEADER = "Alerts"
L.OPT_ALL_SOUNDS = "Alert sounds"
L.MILESTONE_NOTE = "Milestones always pop up as a toast with a sound, even when set to a chat line (but not when Off): level 60, a looted epic BoE, revenge, and kill streaks of 5, 10, 15 and so on."
L.OPT_MARK = "Skull on hitlist players"
L.CHAT_TAB_SET = "Chat lines now go to chat tab %d."
L.CHAT_TAB_USAGE = "/fnf chat <tab number> - which chat tab gets Friends & Foes lines (now %d)"
L.OPT_LEVEL = "Level ups"
L.OPT_LOOT = "Epic BoE loot"
L.OPT_GEAR = "New epic gear"
L.OPT_PVP = "World PvP"
L.MINIMAP_TIP = "Left-click: open  |  Right-click: options\nDrag: move round the minimap  |  Shift-drag: anywhere"
L.OPT_DEBUG = "Debug logging"
L.BTN_UNLOCK = "Move toasts"
L.BTN_TEST = "Test toasts"
L.ANCHOR_LABEL = "Friends & Foes toasts - drag, then /fnf lock"

-- 0.2: versions, sharing, revenge, guilds, do-not-disturb, simulation
L.TOAST_NEWER_VERSION = "Friends & Foes update available"
L.TOAST_NEWER_VERSION_TEXT = "%s has %s (you have %s)"
L.TOAST_NEWER_PROTOCOL_TEXT = "%s uses a newer, incompatible version - please update"
L.TOAST_OLDER_VERSION = "Friend needs to update Friends & Foes"
L.CHAT_OLDER_VERSIONS = "On an older Friends & Foes: %s. You have %s - newer things (like the Bounty board) won't sync with them until they update."
L.TOAST_OLDER_PROTOCOL_TEXT = "%s runs an old, incompatible version - send them the new one"
L.FEED_SHARE = "%s shared their hitlist (%d new entries)"
L.COL_GUILD = "Guild"
L.BTN_REPORT = "Copy debug report"
L.OPT_REPORT = "Debug report"
L.TIP_REPORT = "Everything a bug report needs in one box (version, what works on this client, friends' versions, errors, the debug log), ready to copy and paste. Also: /fnf report"
L.REPORT_TITLE = "Friends & Foes debug report"
L.REPORT_HINT = "Press Ctrl+C to copy (it's all selected), then paste it where you report the bug."
L.REPORT_SELECT = "Select all again"
L.OPT_DND_COMBAT = "Hold progress toasts in combat"
L.OPT_NEARBY_ONLY = "Fights outside my zone: chat only"
L.DEBUG_AUTO_OFF = "Debug logging switched itself off after 7 days. /fnf debug turns it back on."

-- slash
L.HELP = "/fnf [board | groups | profile | alerts | options | unlock | lock | test | status | chat | size | duration | debug | debug clear | report | tour | new | minimap | minimap reset | bounty]"

-- native options panel (Options.lua): pages, choices and hover tooltips
L.PAGE_APPEARANCE = "Appearance"
L.PAGE_FRIENDS = "Friends & sharing"
L.PAGE_ADVANCED = "Advanced"
L.DISPLAY_TOAST_SOUND = "Toast + sound"
L.DISPLAY_TOAST = "Toast"
L.DISPLAY_CHAT_SOUND = "Chat line + sound"
L.DISPLAY_CHAT = "Chat line"
L.DISPLAY_OFF = "Off"
L.TIP_SIGHTING = "Someone on your hitlist shows up near you."
L.TIP_NEARBY_ONLY = "Fights in another zone (a friend attacked, or attacking someone) show as a chat line instead of a toast - you can't get there in time anyway."
L.TIP_ALL_SOUNDS = "Turn the sounds of all alerts on or off at once. Opening the window and turning its pages always sound, like the game's own windows."
L.TIP_DND_COMBAT = "While you are in combat, only fights and hitlist sightings pop up. The rest wait until combat ends."
L.TOASTS_HEADER = "Toasts"
L.THEME_TIPS = {
  minimal = "Modern: a slim one-line strip with a coloured edge.",
  achievement = "Classic: styled like WoW's achievement pop-up, with a header saying what happened.",
  alliance = "Alliance: deep blue with gold trim and the Alliance crest.",
  horde = "Horde: deep red with bronze trim and the Horde crest.",
}
L.TIP_THEME = "How pop-up toasts look. Use Test alerts to compare."
L.OPT_POSITION = "Position"
L.TIP_POSITION = "Shows a handle you can drag to move the toasts. Click again (or /fnf lock) when done."
L.MESSAGES_HEADER = "Messages"
L.OPT_STYLE = "Message style"
L.STYLE_FLAVOR = "With flavor"
L.STYLE_SHORT = "Short"
L.TIP_STYLE_FLAVOR = "Varied wording and extras: repeat killers, kill streaks, revenge, 5th today."
L.TIP_STYLE_SHORT = "Just who did what, and where."
L.TIP_STYLE = "How alerts are worded, in toasts, chat and the Feed."
L.OPT_CHAT_TAB = "Chat lines go to"
L.TIP_CHAT_TAB = "Which chat tab shows Friends & Foes chat lines."
L.TIP_SHARE_HEADER = "What your addon tells your friends about you."
L.TIP_SHARE_KIND = "Send this to friends who have the addon."
L.PICK_HEADER = "Alert list (who you exchange alerts with)"
L.OPT_PICK = "Alert list"
L.BTN_PICK = "Choose friends..."
L.TIP_PICK = "Who you exchange alerts with. Nothing ticked: every friend with the add-on. Tick friends to get alerts only from them (and only they get yours). Profiles, victims lists, groups and bounties still work with everyone."
L.HITLIST_HEADER = "Hitlist"
L.TIP_MARK = "A skull next to hitlist players' nameplates."
L.OPT_MINIMAP_SHOW = "Minimap button"
L.TIP_MINIMAP = "The round button on the minimap. Friends & Foes is also in the minimap's addon menu."
L.TIP_DEBUG = "Logs what the addon sees, for bug reports. Saved on /reload. Switches itself off after 7 days."
L.OPT_SIM = "Test alerts"
L.TIP_SIM = "Shows one sample of each alert and a chat line, so you can see how they look. Nothing is recorded or sent."

-- "Where it works" options page
L.TIP_WHERE_ALERTS = "What happens to alerts from friends while you're in a dungeon, raid or battleground. Outside, your normal alert settings apply."
L.WHERE_INSTANCES = "Dungeons, raids, battlegrounds"
L.WHERE_SHOW = "Show"
L.WHERE_HOLD = "Wait until I'm out"
L.WHERE_OFF = "Off"
L.TIP_WHERE_SHOW = "Alerts work as usual."
L.TIP_WHERE_HOLD = "Toasts wait and pop up when you leave. Fights older than a minute are skipped."
L.TIP_WHERE_OFF = "Nothing is shown. Events are still recorded in the Feed."
L.TRACK_HEADER = "Track my PvP in"
L.TIP_TRACK = "Where your own fights are tracked and sent to friends: attacks on you, your deaths, your kills, and hitlist sightings."
L.TRACK_WORLD = "Open world"
L.TRACK_PVP = "Battlegrounds"
L.TIP_TRACK_WORLD = "World PvP - what the addon is made for. Objective areas (like the Eastern Plaguelands towers) are always skipped."
L.TIP_TRACK_PVP = "Also track battleground fights. Anyone who kills or attacks you or a friend there goes on your hitlist too."
L.OPTIONS_IN_COMBAT = "Options can't be opened during combat."
L.CONFIRM_REMOVE_HIT = "Remove %s from your hitlist?"
L.CONFIRM_REMOVE_PLAYER = "Remove %s and their kill/death record?"
L.CONFIRM_CLEAR_HITLIST = "Clear your whole hitlist (%d players)? This can't be undone."
L.BTN_CLEAR_HITLIST = "Clear hitlist"
L.REMOVE_HINT = "Right-click a player to remove them."

-- 0.6: shared sightings, toast size/duration, search, polish
L.SIGHTING_BY = "%s spotted by %s"
L.HEADER_SIGHT_FRIEND = "Spotted by a friend"
L.OPT_TOAST_SIZE = "Toast size"
L.TIP_TOAST_SIZE = "Make toasts bigger or smaller."
L.OPT_TOAST_DURATION = "Show toasts for"
L.TIP_TOAST_DURATION = "How long a toast stays. PvP toasts stay 2 seconds longer. Hover a toast to keep it."
L.OPT_WEEKLY = "Weekly summary"
L.TIP_WEEKLY = "Once a week at login, a chat line with your PvP week: kills, deaths and your nemesis."
L.WEEKLY = "Your PvP week: %d kills, %d deaths."
L.WEEKLY_NEMESIS = "Nemesis: %s (%d kills on you)."
L.SEARCH = "Search"
L.SEARCH_NONE = "No matches."
L.WELCOME_1 = "is on. You'll hear about your friends' level-ups, loot and world PvP fights."
L.WELCOME_2 = "Type /fnf for the window, or open Options -> AddOns -> Friends & Foes to choose what pops up."
L.TOUR_1_TITLE = "Friends & Foes"
L.TOUR_1_TEXT = "Your Battle.net friends who have Friends & Foes share their level-ups, loot and world PvP with you, and you with them. Fights, kills and deaths pop up as alerts; everything is kept here in this window."
L.TOUR_2_TITLE = "Foes"
L.TOUR_2_TEXT = "Anyone who kills one of you, or attacks one of you first, goes on your Hitlist, with a skull on their nameplate. Click a name for their Wanted poster: what they've done, and their notoriety. Kill them to claim it - shared with the friends who help. Want to pay gold for a kill? Post a bounty on the Bounty board."
L.TOUR_3_TITLE = "Friends"
L.TOUR_3_TEXT = "Your friends need the add-on too: it's on CurseForge and Wago. The Friends tab ranks you and your friends by kills; start a group there to compete with friends of friends. What pops up and what you share: the Options button, top right."
L.TOUR_STEP = "%d of %d"
L.TOUR_NEXT = "Next"
L.TOUR_BACK = "Back"
L.TOUR_DONE = "Got it"
L.TIP_FRIENDS_ONLINE = "Friends online: %d"
L.TIP_HITLIST_SIZE = "On your hitlist: %d"
L.TIP_LAST_FIGHT = "Last fight: %s"
L.SIZE_USAGE = "/fnf size <70-150> - toast size in percent (now %d%%)"
L.DURATION_USAGE = "/fnf duration <2-10> - seconds a toast stays (now %d)"
L.DURATION_SET = "Toasts now stay %d seconds."

-- Sounds page
L.SOUNDS_HEADER = "Sounds"
L.TIP_SOUNDS_HEADER = "One sound for each kind of alert - you'll hear it as you pick. Whether an alert makes a sound at all is set above (Toast + sound, Chat line + sound)."
L.SOUND_TROUBLE = "Friend in trouble"
L.TIP_SOUND_TROUBLE = "A friend attacked or killed. On Default, attacked and killed each have their own sound (an alarm, a raid warning); a pick plays for both."
L.SOUND_VICTORY = "Friend's kill"
L.TIP_SOUND_VICTORY = "A friend gets a kill, and kill streaks and revenge. Default: the level-up chime."
L.SOUND_SIGHTING = "Hitlist sightings"
L.SOUND_PROGRESS = "Friends' progress"
L.SOUND_BOUNTY = "Bounty board"
L.TIP_SOUND_PICK = "The sound these alerts play. Default keeps the built-in one."
L.SND_DEFAULT = "Default"
L.SND_WHISPER = "Whisper ping"
L.SND_BNET = "Battle.net chime"
L.SND_BOSS_WHISPER = "Boss whisper"
L.SND_RAID_WARNING = "Raid warning"
L.SND_READY_CHECK = "Ready check"
L.SND_LEVEL_UP = "Level-up fanfare"
L.SND_QUEST = "Quest complete"
L.SND_INVITE = "Group invite"
L.SND_MAP_PING = "Map ping"
L.SND_ALARM = "Alarm"
L.SND_COIN = "Coins"
L.WITH_HELPERS = "(with %s)"
L.KILLS_ON_COUNT = "%s %dx"
L.HIT_TIP_RECORD = "%d kills on your group"
L.HIT_TIP_KILLED = "Killed:"
L.HIT_TIP_TIMES = "%dx"
L.HIT_TIP_EARLIER = "before counting began"
L.HIT_TIP_LAST = "Last seen %s"
L.HIT_TIP_LIKELY = "%d of them likely, not certain (the death recap couldn't name the killer)"
L.HIT_TIP_LEVEL_OLD = "Level seen a while ago (grey): probably higher now."
-- old data
-- 0.6.2 options
L.OPT_MARK_TOOLTIP = "Hitlist info in tooltips"
L.TIP_MARK_TOOLTIP = "Hovering a hitlist player shows their kills on your group and who they killed."
L.OPT_LEVEL_EVERY = "Level-ups to show"
L.TIP_LEVEL_EVERY = "Fewer level-up alerts while leveling. Level 60 always shows. Every level-up is still in the Feed."
L.LEVEL_EVERY_1 = "Every level"
L.LEVEL_EVERY_5 = "Every 5 levels"
L.LEVEL_EVERY_10 = "Every 10 levels"
L.LEVEL_EVERY_MAX = "Only level 60"
L.OPT_TOAST_GROW = "Toasts stack"
L.TIP_TOAST_GROW = "Down from where you placed them, or up - pick up if your toasts sit near the bottom of the screen."
L.GROW_DOWN = "Downward"
L.GROW_UP = "Upward"
L.OPT_TOAST_MAX = "Toasts on screen"
L.TIP_TOAST_MAX = "How many toasts show at once. Extra ones wait their turn."
L.CONFIRM_FORGET = "This removes %d hitlist players right away Continue?"
-- catch-up after being offline
L.CHAT_CAUGHT_UP = "While you were away: %d events from %s. They're in the Feed."
-- 0.7: leaderboard and profiles
L.TAB_PROFILE = "Profile"
L.COL_RANK = "#"
L.COL_KD = "K/D"
L.COL_NOW = "Now"
L.YOU = "(you)"
L.STATUS_AFK = "AFK"
L.STATUS_FIGHT = "in a fight"
L.BOARD_HINT = "World PvP kills, deaths and notoriety, all-time. Click a name for their profile."
L.PROFILE_EMPTY = "Nothing known about this player yet. Click a name on any list to see their profile."
L.PROF_KILLS = "Kills"
L.PROF_DEATHS = "Deaths"
L.PROF_KD = "K/D"
L.PROF_RANK = "Rank"
L.PROF_RANK_OF = "#%d of %d"
L.PROF_NEMESIS = "Nemesis"
L.PROF_NEMESIS_TEXT = "%s (killed them %dx)"
L.PROF_NEMESIS_ME = "%s (killed you %dx)"
L.PROF_WANTED_POSTER = "WANTED"
L.PROF_DEAD_OR_ALIVE = "DEAD OR ALIVE"
L.PROF_BOUNTY = "Notoriety"
L.TIP_BOUNTY = "Just for fun, points not gold: %d for every murder and %d for every attack since someone last claimed it. Kill them to claim it: everyone who gets the kill shares it."
L.COL_BOUNTY = "Notoriety"
L.COL_BOUNTIES = "Bounties"
L.PROF_BOUNTIES = "Notoriety"
L.BOUNTY_COLLECTED = "You claimed %s notoriety from %s."
L.BOUNTY_COLLECTED_SHARED = "You claimed %s notoriety from %s, shared with %s."
L.PROF_NOW = "Now"
L.PROF_LAST_SEEN = "Last seen"
L.PROF_ADDON = "Addon"
L.PROF_OUTDATED = "%s (older than yours - tell them to update)"
L.PROF_NEWER = "%s (newer than yours - time to update)"
L.PROF_ESTIMATED = "Counted from their alerts: they need 0.7 or newer to report their own numbers."
L.PROF_KILLS_ON_US = "Murders"
L.PROF_DIED_TO_US = "Died to us"
L.PROF_ATTACKS = "Attacks on us"
L.PROF_REVENGE = "Revenge taken"
L.PROF_RECENT = "Recent PvP"
L.LINK_TIP = "Click to open profile"
L.PROF_RECENT_NONE = "Nothing yet."
L.PROF_FRIEND = "Friend"
L.PROF_ME = "You"
L.PROF_LEVEL_CLASS = "Level %s %s"
L.BTN_PICK_ON = "Add to alert list"
L.BTN_PICK_OFF = "Remove from alert list"
-- shared groups
L.BOARD_FRIENDS = "My friends"
L.BTN_GROUP_NEW = "New group"
L.BTN_GROUP_INVITE = "Invite"
L.BTN_GROUP_LEAVE = "Leave"
L.BTN_GROUP_JOIN = "Join"
L.BTN_GROUP_DECLINE = "Decline"
L.BTN_GROUP_OPEN = "Group"
L.BTN_GROUP_INVITATION = "Invitation"
L.BTN_GROUP_REMOVE = "Remove"
L.GROUPWIN_INVITED = "You're invited. Join to share your kills, deaths and notoriety with this group."
L.GROUPWIN_YOU_LEAD = "You lead this group (whoever has been in longest leads)."
L.GROUPWIN_LED_BY = "Led by %s (whoever has been in longest leads)."
L.GROUP_INVITED_TAG = "(invited)"
L.GROUP_ROW_INVITED = "invited - hasn't joined yet"
L.GROUP_ROW_VIA = "as of %s, via %s"
L.GROUP_ROW_UNKNOWN = "no numbers yet - they reach you through other members"
L.GROUP_TOTALS = "%s: %s, %s, %s (K/D %s)."
-- counts: { one, more }
L.N_MEMBERS = { "%d member", "%d members" }
L.N_KILLS = { "%d kill", "%d kills" }
L.N_DEATHS = { "%d death", "%d deaths" }
L.GROUP_TOTALS_PARTIAL = { "1 member without numbers yet.", "%d without numbers yet." }
L.GROUP_HINT = "The Group button has the members, invites and Leave."
L.GROUP_HINT_LEADER = "You lead this group. The Group button has the members, invites and Remove."
L.GROUP_NEW_PROMPT = "Name your new group:"
L.GROUP_CREATED = "Group %s created. Invite friends from its window (the Group button on the Friends tab)."
L.GROUP_INVITE_TITLE = "Invite to %s"
L.GROUP_INVITE_SENT = "Invited %s to %s. They'll get it when they're online."
L.GROUP_NOBODY_TO_INVITE = "No friends left to invite - friends show up here once the addon has seen them."
L.GROUP_INVITED = "%s invited you to %s"
L.GROUP_INVITED_TEXT = "Join or decline on the Friends tab: pick the group, then Invitation (/fnf board)."
L.GROUP_JOINED = "You joined %s."
L.GROUP_LEFT = "You left %s."
L.GROUP_DECLINED = "You declined the invite to %s."
L.GROUP_REMOVED = "You're no longer in the group %s."
L.GROUP_MEMBER_REMOVED = "Removed %s from %s."
L.GROUP_UNKNOWN = "You're not in a group called '%s'."
L.GROUPS_NONE = "You're not in any shared group yet."
L.GROUPS_USAGE = "/fnf groups new <name> | invite <group> <friend> | join <group> | decline <group> | leave <group> | remove <group> <member>"
L.CONFIRM_LEAVE_GROUP = "Leave the group %s? You'd need a new invite to come back."
L.CONFIRM_REMOVE_MEMBER = "Remove %s from %s?"
L.GROUP_BAD_NAME = "Give the group a name of 2 to 24 characters."
L.GROUP_TOO_MANY = "You can be in at most 5 groups. Leave one first."
L.GROUP_EXISTS = "You already have a group with that name."
L.GROUP_NOT_IN = "You're not in that group."
L.GROUP_NOT_FRIEND = "You can only invite your own Battle.net friends who use the addon."
L.GROUP_ALREADY = "They're already in the group (or invited)."
L.GROUP_FULL = "The group is full (10 members, invites included)."
L.GROUP_NOT_INVITED = "You haven't been invited to that group."
L.GROUP_NOT_LEADER = "Only the group leader (the member who has been in longest) can remove members. You can leave yourself."
L.GROUP_NOT_MEMBER = "They're not in that group."
L.GROUP_OLD_VERSION = "They need Friends & Foes 0.7 or newer for groups - an older version would never see the invite."
L.GROUP_LEADER_TAG = "(leader)"
L.GROUP_NO_TAG = "Battle.net isn't telling the addon your BattleTag right now - groups need it. Try again in a moment."
L.GROUP_NO_FRIEND_TAG = "Battle.net doesn't show their BattleTag right now (are they online?) - groups need it."
-- language filter (ProfanityLib)
L.TEXT_OFFENSIVE = "That text didn't pass the language filter. Try different words."
L.GROUP_UNNAMED = "Unnamed group"
L.FILTER_STATUS_ON = "language filter: on (ProfanityLib, bundled)"
L.FILTER_STATUS_OFF = "language filter: not working - group names from others are hidden. Please report this with your debug log."
L.GROUP_NAME_TOO_LONG = "Group names can be at most 24 characters, like guild names."
-- 0.7 sharing options
L.OPT_SHARE_WHERE = "Where I am"
L.TIP_SHARE_WHERE = "Your zone, and whether you're AFK or in a fight, on your profile for friends. Off: friends only see what Battle.net shows them."
L.TIP_SHARE_PVP = "Your attacks, deaths and kills, and your kill/death numbers in friends' rankings and in your shared groups."
L.BTN_BACK = "< %s"
-- kill lists (0.7.1)
L.TAB_KILLS = "Victims"
L.COL_LAST_KILL = "Last kill"
L.BTN_KILL_LIST = "Victims"
L.BTN_KILL_LIST_N = "Victims (%d)"
L.KILLS_OF = "%s's victims"
L.KILLS_HINT = "%s: %d players killed, %d kills in all. Click a name for their profile."
L.KILLS_SRC_ME = "Your kills since 0.7.0."
L.KILLS_SRC_ENEMY = "Which of your friends they killed (from your hitlist)."
L.KILLS_SRC_REPORT = "Includes their own list, sent %s."
L.KILLS_SRC_ASKING = "Asking them for their own list..."
L.KILLS_SRC_LOCAL = "Counted from their alerts; when they're online, their own list is added."
-- relayed catch-up (0.7.1)
L.OPT_SHARE_RELAY = "Friends may pass on my events"
L.TIP_SHARE_RELAY = "When a friend of yours who was offline logs in, your other friends who are online may pass on what you did in the last week, but only if you're friends with them too. Off: only you send your own events. (Never passed on while your alert list has anyone on it.)"
L.PROF_LAST_PLACE = "Last place"
-- 0.7.2: one click = profile everywhere
L.HITLIST_HINT = "Click a name for their profile (victims, post a bounty). Right-click to remove."
L.PROF_SHARED_BY = "Shared by"

-- 0.9: what a number means, on hover. Column headers (by tab: "Kills" means different things on
-- different tabs) and profile labels.
L.COLUMN_TIPS = {
  contracts = {
    ["Reward"] = "What the poster promised whoever gets the kill. They pay it by trade in the game; the add-on never moves gold.",
    ["Status"] = "Open: how long it has left (the poster picks 1-30 days). Done: someone got the kill; until it's paid, the poster still owes them.",
    ["Closed by"] = "Who got the kill. Finished bounties stay on the board.",
  },
  hitlist = {
    [L.COL_KILLS] = "How many times they killed you or a friend. Hover a row to see how many were best guesses.",
    [L.COL_VICTIMS] = "Which of you they killed, and how often.",
  },
  friends = { -- (the old Leaderboard)
    [L.COL_RANK] = "Place on this board: most kills first; on a tie, fewer deaths first.",
    [L.COL_KILLS] = "World PvP kills, all-time, as each player's own add-on reports them.",
    [L.COL_DEATHS] = "World PvP deaths, all-time.",
    [L.COL_KD] = "Kills per death. With no deaths yet, just the kills.",
    [L.COL_BOUNTIES] = "Gold they collected from the Bounty board: bounties paid to them for a kill (the ones you know of).",
    [L.COL_BOUNTY] = "Notoriety claimed from enemies they killed, all-time (just for fun: points, not gold). Empty: they haven't reported it yet (older add-on version).",
  },
}
L.PROFILE_TIPS = {
  [L.PROF_KILLS] = "World PvP kills, all-time.",
  [L.PROF_DEATHS] = "World PvP deaths, all-time.",
  [L.PROF_KD] = "Kills per death. With no deaths yet, just the kills.",
  [L.PROF_RANK] = "Your place among your friends (Friends tab), by kills.",
  [L.PROF_BOUNTIES] = "Notoriety claimed from enemies they killed, all-time (just for fun: points, not gold).",
  [L.PROF_KILLS_ON_US] = "How many times they killed you or a friend.",
  [L.PROF_DIED_TO_US] = "How many times you or a friend killed them.",
  [L.PROF_ATTACKS] = "How many fights they started with you or a friend.",
  [L.PROF_REVENGE] = "How many times one of you killed them while they were on your hitlist.",
  [L.PROF_NEMESIS] = "The enemy who killed them most.",
}

-- 1.0
L.SUSPECT_TAG = " (likely)" -- after a killer's name when it's a best guess (the last attacker)
L.KILLING_BLOW_TAG = " (killing blow)" -- after a kill line when the game said it was the killer's blow
L.KILLS_UNKNOWN = "Name not readable" -- kill list row: kills whose victim couldn't be named

-- the Bounty board (contracts: promises between friends, paid by trade in the game)
L.TAB_CONTRACTS = "Bounty board"
L.COL_TARGET = "Target"
L.COL_REWARD = "Reward"
L.COL_POSTED_BY = "Posted by"
L.COL_STATUS = "Status"
L.COL_POSTED = "Posted"
L.COL_CLOSED_BY = "Closed by"
L.CONTRACT_OPEN = "Open, %s left"
L.CONTRACT_DONE = "Done, not paid yet"
L.CONTRACT_PAID = "Done, paid"
L.CONTRACT_SELF = "Done by the poster"
L.CONTRACT_EXPIRED = "Ran out"
L.BTN_POST_BOUNTY = "Post bounty"
L.CONTRACT_HINT = "A bounty is a promise to your friends, paid by trade in the game: Friends & Foes never moves gold. Target an enemy player and click Post bounty. Right-click your own to cancel it, or to mark it paid."
L.CONTRACT_PROMPT = "Bounty on %s: how much, and for how many days? (like 10g 50s 3d; 1-30 days, 7 if you leave it out)"
L.CONTRACT_NEED_TARGET = "Target an enemy player first, or open their profile."
L.CONTRACT_NOT_ENEMY = "Bounties are for enemy players only."
L.CONTRACT_BAD_AMOUNT = "That's not an amount: try 10g, 50s or 10g 50s 3c (up to 10,000 gold)."
L.CONTRACT_BAD_DAYS = "A bounty stays open for 1 to 30 days: like 10g 3d."
L.CONTRACT_TOO_MANY = "You have %d open bounties: cancel one first."
L.CONTRACT_NOT_READY = "Not ready yet: try again in a moment."
L.CONTRACT_POSTED_YOU = "You put a bounty of %s on %s, open for %d days. Your friends see it on their Bounty board."
L.CONTRACT_POSTED = "%s put a bounty of %s on %s."
L.CONTRACT_FEED_POSTED = "%s put a bounty of %s on %s"
L.CONTRACT_TOAST_DAYS = "Open for %d days"
L.HEADER_CONTRACT_POSTED = "Bounty posted"
L.HEADER_CONTRACT_DONE = "Bounty done"
L.CONTRACT_YOURS_DONE_TITLE = "%s is down: %s fulfilled your bounty"
L.CONTRACT_YOURS_DONE_TEXT = "Pay them %s by trade, then mark it paid on the Bounty board"
L.CONTRACT_YOU_DID_TITLE = "You fulfilled %s's bounty on %s"
L.CONTRACT_YOU_DID_TEXT = "%s, promised: they pay you by trade"
L.CONTRACT_DONE_TITLE = "%s fulfilled %s's bounty on %s"
L.OPT_CONTRACT = "Bounty board"
L.TIP_CONTRACT = "A friend posts a bounty, or a bounty is done: who got the kill, and who pays whom."
L.CONTRACT_PAID_YOU = "%s marked the %s for %s as paid."
L.CONTRACT_FEED_DONE = "%s fulfilled %s's bounty on %s (%s)"
L.CONTRACT_CONFIRM_CANCEL = "Cancel your bounty of %s on %s?"
L.CONTRACT_CONFIRM_PAID = "Have you paid %s the %s for %s? It's marked paid for everyone."
L.CONTRACT_CANCELLED = "Bounty cancelled."
L.CONTRACT_BY = "%s from %s"
L.PROF_CONTRACTS = "Bounties posted"
L.BOUNTY_USAGE = "/fnf bounty <amount> [days] - put a bounty on your target, like /fnf bounty 10g 50s 3d (1-30 days, 7 if you leave it out)"
L.MINIMAP_RESET = "Minimap button back on the minimap."
L.TEST_CHAT = "This is how a chat line looks. (Test alerts: nothing was recorded or sent.)"
L.HOLD_HEADER = "When alerts wait"
L.MINIMAP_HEADER = "Minimap"
L.OPTIONS_WHERE = "Options are in the game's Options -> AddOns -> Friends & Foes."
L.ALERT_FIGHTS = "Friends' fights"
L.TIP_ALERT_FIGHTS = "A friend is attacked, attacks someone, is killed, or gets a kill. Attacked, killed and a kill each have their own sound until you pick one fights sound below; attacking someone is always quiet."
L.ALERT_SIGHTINGS = "Hitlist sightings"
L.ALERT_PROGRESS = "Friends' progress"
L.TIP_ALERT_PROGRESS = "Level-ups (how often: below), epic loot and new epic gear. A plain level-up never makes a sound; level 60 and an epic BoE always do."
L.ALERTLIST_TITLE = "Alert list"
L.ALERTLIST_ALL = "Nothing ticked: you get alerts from every friend with the add-on, and they get yours. Tick friends to hear only from them."
L.ALERTLIST_ACTIVE = "You get alerts only from the friends ticked here, and only they get yours. Profiles, groups and bounties still work with everyone."
L.ALERTLIST_EMPTY = "No friends with the add-on yet. Friends show up here once they're online in WoW Forever with Friends & Foes."
L.ALERTLIST_EVERYONE = "Everyone"
L.PET_BLOW_TAG = " (pet's killing blow)" -- after a kill line when the killer's pet landed the blow
-- notoriety ranks, titles, takedowns, this week (1.0)
L.RANK_NUISANCE = "Nuisance"
L.RANK_MENACE = "Menace"
L.RANK_WANTED = "Wanted"
L.RANK_MOST_WANTED = "Most Wanted"
L.RANK_PUBLIC_ENEMY = "Public Enemy"
L.RAMPAGE_TAG = "on a rampage"
L.TITLE_TRACKER = "Tracker"
L.TITLE_HUNTER = "Hunter"
L.TITLE_BOUNTY_HUNTER = "Bounty Hunter"
L.TITLE_MANHUNTER = "Manhunter"
L.TITLE_LEGEND = "Legend"
L.HEADER_TITLE = "New title"
L.TITLE_NEW = "You're now a %s."
L.HEADER_TAKEDOWN = "Takedown"
L.TAKEDOWN = "%s brought down %s (%s): %s notoriety"
L.TAKEDOWN_SHARED = "%s brought down %s (%s, shared): %s notoriety"
L.PROF_STANDING = "Standing"
L.PROF_BOUNTIES_ALL = "%s claimed in all"
L.PROF_BOUNTIES_WEEK = "This week"
L.WEEKLY_NOTORIETY = " and %s notoriety."
L.OPT_FORGET_ATTACKERS = "Forget attackers after"
L.OPT_FORGET_KILLED_ONCE = "Forget one-time killers after"
L.OPT_FORGET_KILLED_MORE = "Forget repeat killers after"
L.TIP_FORGET_ATTACKERS = "Players who attacked one of you but never killed anyone. They leave the hitlist when neither you nor a friend has seen them for this long. Seeing them again starts the time over. Anyone with an open bounty stays. After 30 days unseen they are shown greyed out at the bottom of the list."
L.TIP_FORGET_KILLED_ONCE = "Players who killed one of you once. They leave the hitlist when neither you nor a friend has seen them for this long. Seeing them again starts the time over. Anyone with an open bounty stays. After 30 days unseen they are shown greyed out at the bottom of the list."
L.TIP_FORGET_KILLED_MORE = "Players who killed you or your friends two or more times. They leave the hitlist when neither you nor a friend has seen them for this long. Seeing them again starts the time over. Anyone with an open bounty stays. After 30 days unseen they are shown greyed out at the bottom of the list."
L.FORGET_1W = "1 week"
L.FORGET_2W = "2 weeks"
L.FORGET_1M = "1 month"
L.FORGET_3M = "3 months"
L.FORGET_6M = "6 months"
L.FORGET_1Y = "1 year"
L.FORGET_FOREVER = "Forever"
L.FORGOT_LINE = "Hitlist players not seen for a while were removed: %d (Options: Friends & sharing)."
L.CONTRACT_NAMES_AND = "%s and %s"
L.CONTRACT_YOURS_DONE_MANY_TEXT = "Pay each of them %s by trade, then mark it paid on the Bounty board"
L.CONTRACT_YOU_DID_MANY_TITLE = "You and %s fulfilled %s's bounty on %s"
L.CONTRACT_YOU_DID_MANY_TEXT = "%s each, promised: they pay you by trade"
L.CONTRACT_ALSO_KILLED = "%s was in on the kill too - they get a share."
L.CONTRACT_CONFIRM_PAID_MANY = "Have you paid %s %s each for %s? It's marked paid for everyone."
L.CONTRACT_MORE = "+%d"
L.FEED_ASSIST = "%s helped %s kill %s"
L.FEED_ASSIST_YOU = "%s helped you kill %s"
L.OPT_HIDE_LOW_ALTS = "Hide characters below level 15"
L.TIP_HIDE_LOW_ALTS = "Keeps bank alts and fresh alts off the Friends tab. Their alerts still come through, and they show up once they reach 15."
L.FRIEND_ONLINE_ALT = "online (on an alt)"
L.KILL_TOGETHER = "%s killed %s"
L.KILL_YOU_NAME = "You"
L.PROF_PAGE = "%d/%d"
L.WHATSNEW_TITLE = "What's new in Friends & Foes %s"
L.WHATSNEW_OK = "OK"
L.NEW_100_1 = "Killing blows decide who gets the kill, and your pet's blow counts as yours."
L.NEW_100_2 = "A friend who heals you through a fight shares the kill."
L.NEW_100_3 = "Bounties can be completed by several of you; the gold is split."
L.NEW_100_4 = "Notoriety: killing the same player again within 30 minutes is worth less, grey players give nothing, and higher levels give more."
L.NEW_100_5 = "The Friends tab shows bounty gold collected and hides bank alts under level 15."
L.NEW_100_6 = "Missed something? Catch-up now covers a whole week, including your friends' alts."
L.NEW_100_7 = "Click any name in the Feed or on a profile to open their profile."
L.NEW_100_8 = "Simpler options: four alert groups, five sounds, and a Test alerts button."
