-- UI/SocialPanel.lua
--
-- Social window (Party + Guild tabs).
-- Replaces the old compact PartyPanel.
--
-- Layout (Party tab):
--   Left  40% ─ Player Browser: all lobby players, friends sorted first,
--               Invite button per row.
--   Right 60% ─ Party Roster: Create Party when solo; member list + controls
--               when in a party. Bonus XP info always visible at bottom.
--
-- Data flow:
--   mount          → FireServer("PlayerListRequest"), FireServer("GetPlayerInfo")
--   PlayerListUpdate → rebuild playerList state
--   PartyUpdate      → rebuild party state
--   PartyError       → error toast (§AGX/UI-P6: via Notify, was an inline label)
--
-- Party actions fired to server via PartyRequest event:
--   InviteById   { userId }
--   Create
--   Leave
--   Disband
--   KickMember   { userId }
--   PromoteMember { userId }
--
-- §AGX/UI-P6 (UI-FREE): §T10/U3 Theme v2 re-skin, the one screen the revamp
-- missed. Mounted by Shell/Registry entry "party" (module Lobby/SocialPanel,
-- windowed / phone sheet); props unchanged ({ onClose }). Chrome = AppWindow
-- variant "auto" (sheet on phone), body = design px inside UIScaleRoot.Local:
-- Common Tabs, two flat Panel columns of raised Panel rows, Common Buttons
-- (44 px, sm). "+ Create Party" is the screen's one primary (orange) CTA;
-- everything else is blue-accent secondary / danger. Removed: the private
-- `C` palette, the hand-rolled fullscreen backdrop, title, ✕ close button,
-- TabButton, every Scale-sized TextScaled label and the inline error toast
-- (PartyError now raises a Notify error toast, the one rejection channel).
-- Events, payloads, friend pre-fetch and sorting are unchanged.

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React             = require(ReplicatedStorage.Packages.React)

local PlayerScripts  = Players.LocalPlayer:WaitForChild("PlayerScripts")
local SharedModules  = PlayerScripts:WaitForChild("Modules")
local NetworkManager = require(SharedModules:WaitForChild("NetworkManager"))

-- §AGX/UI-P6: shared components
local Common      = PlayerScripts:WaitForChild("UI"):WaitForChild("Common")
local AppWindow   = require(Common:WaitForChild("AppWindow"))  -- §T10/U3
local Theme       = require(Common:WaitForChild("Theme"))
local UIScaleRoot = require(Common:WaitForChild("UIScaleRoot"))
local Text        = require(Common:WaitForChild("Text"))
local Tabs        = require(Common:WaitForChild("Tabs"))
local Panel       = require(Common:WaitForChild("Panel"))
local Button      = require(Common:WaitForChild("Button"))
local Notify      = require(Common:WaitForChild("Notify"))

local LocalPlayer = Players.LocalPlayer

local e  = React.createElement
local R  = Theme.Roles
local SP = Theme.Space

local MAX_PARTY = 5

-- §AGX/UI-P6: layout in DESIGN px (phone scale).
local ROW_H      = 52                          -- row = 44 px button + 2 x 4 px
local HEAD_H     = 44                          -- column header rows (hold a 44 px button)
local BTN_W      = 88                          -- Theme.Metrics.button.minWidth
local REFRESH_W  = 124                         -- "⟳ REFRESH"
local ACTION_W   = 184                         -- "⚑ DISBAND PARTY" / "← LEAVE PARTY"
local ROW_INSET  = Theme.Metrics.scrollBar     -- rows stop short of the scroll bar
local TABS_H     = Theme.Metrics.tabs.height   -- 44
local LEFT_FRAC  = 0.40
local COL_GAP    = SP.md
local BONUS_H    = 2 * Theme.Type.caption.lineHeight + 2 * SP.sm + SP.xxs

-- Roles for the social colours (were friend green / leader gold literals).
local FRIEND_COLOR = "state.success"     -- + the ♥ glyph, so colour is never the only cue
local LEADER_COLOR = "rarity.legendary"  -- gold, + the ★ Leader tag

local TAB_ITEMS = {
	{ id = "party", label = "Party" },
	{ id = "guild", label = "Guild" },
}

-- Friend-status cache: populated asynchronously to avoid blocking the first render.
-- [userId] = true/false | nil (not yet fetched)
local friendsCache = {}

local function isFriend(userId)
	-- Return cached value instantly (no network call during render)
	local cached = friendsCache[userId]
	if cached ~= nil then return cached end
	-- Not yet cached — return false now, async fetch will cause a re-render later
	return false
end

-- Fetch the friend status for one userId in a background thread and store it.
local function prefetchFriend(userId, onDone)
	if friendsCache[userId] ~= nil then
		if onDone then onDone() end
		return
	end
	-- Mark as in-progress (prevent duplicate spawns)
	friendsCache[userId] = false
	task.spawn(function()
		local ok, result = pcall(function()
			return LocalPlayer:IsFriendsWith(userId)
		end)
		friendsCache[userId] = ok and result or false
		if onDone then onDone() end
	end)
end

-- §AGX/UI-P6: shared scroll list (was two copies with Scale padding).
local function ScrollList(props, rows)
	rows.layout = e("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		Padding       = UDim.new(0, SP.xs),
		SortOrder     = Enum.SortOrder.LayoutOrder,
	})
	return e("ScrollingFrame", {
		Name                   = props.name,
		Position               = props.position,
		Size                   = props.size,
		BackgroundTransparency = 1,
		BorderSizePixel        = 0,
		ScrollBarThickness     = Theme.Metrics.scrollBar,
		ScrollBarImageColor3   = R.text.secondary,
		ScrollingDirection     = Enum.ScrollingDirection.Y,
		CanvasSize             = UDim2.fromScale(0, 0),
		AutomaticCanvasSize    = Enum.AutomaticSize.Y,
	}, rows)
end

-- ── PlayerRow (left panel) ────────────────────────────────────────────────────
-- props: entry {userId, name}, partyFull, alreadyInParty
local function PlayerRow(props)
	local entry           = props.entry
	local partyFull       = props.partyFull
	local alreadyInParty  = props.alreadyInParty
	local isSelf          = (entry.userId == LocalPlayer.UserId)
	local friend          = isFriend(entry.userId)

	local canInvite = not isSelf and not alreadyInParty and not partyFull
	local actionW = isSelf and 0 or (BTN_W + SP.sm)

	-- Right-hand control: Invite, a disabled "Full", or an "In party" tag.
	local control = nil
	if not isSelf then
		if alreadyInParty then
			control = e(Text, {
				style       = "caption",
				text        = "In party",
				color       = "accent.secondary",
				align       = "right",
				anchorPoint = Vector2.new(1, 0.5),
				position    = UDim2.new(1, -SP.sm, 0.5, 0),
				size        = UDim2.fromOffset(BTN_W, ROW_H),
			})
		else
			control = e(Button, {
				variant     = "secondary",
				size        = "sm",
				label       = partyFull and "Full" or "Invite",
				disabled    = not canInvite,
				width       = BTN_W,
				anchorPoint = Vector2.new(1, 0.5),
				position    = UDim2.new(1, -SP.xs, 0.5, 0),
				onActivated = canInvite and function()
					NetworkManager.FireServer("PartyRequest", { action = "InviteById", userId = entry.userId })
				end or nil,
			})
		end
	end

	return e(Panel, {
		name        = "Player_" .. tostring(entry.userId),
		elevation   = "raised",
		padding     = "none",
		accent      = isSelf and "accent.secondary" or nil,   -- you = blue ring
		size        = UDim2.new(1, -ROW_INSET, 0, ROW_H),
		layoutOrder = props.order or 1,
	}, {
		nameLabel = e(Text, {
			style    = "label",
			text     = entry.name .. (friend and "  ♥" or "") .. (isSelf and " (you)" or ""),
			color    = friend and FRIEND_COLOR or "text.primary",
			position = UDim2.fromOffset(SP.md, 0),
			size     = UDim2.new(1, -(SP.md + actionW), 1, 0),
		}),
		control = control,
	})
end

-- ── MemberRow (right panel) ───────────────────────────────────────────────────
-- props: member {userId, name}, leaderId, isLocalLeader
local function MemberRow(props)
	local member        = props.member
	local leaderId      = props.leaderId
	local isLocalLeader = props.isLocalLeader
	local isLeader      = (member.userId == leaderId)
	local isSelf        = (member.userId == LocalPlayer.UserId)
	local showControls  = isLocalLeader and not isSelf
	local controlsW     = showControls and (2 * BTN_W + 2 * SP.sm) or 0
	local nameH         = Theme.Type.label.lineHeight
	local tagH          = Theme.Type.caption.lineHeight

	return e(Panel, {
		name        = "Member_" .. tostring(member.userId),
		elevation   = "raised",
		padding     = "none",
		accent      = isSelf and "accent.secondary" or nil,
		size        = UDim2.new(1, -ROW_INSET, 0, ROW_H),
		layoutOrder = props.order or 1,
	}, {
		-- Name (+ ★ Leader tag under it for the leader)
		nameLabel = e(Text, {
			style    = "label",
			text     = member.name,
			color    = isLeader and LEADER_COLOR or "text.primary",
			position = isLeader and UDim2.fromOffset(SP.md, (ROW_H - nameH - tagH) / 2)
				or UDim2.fromOffset(SP.md, 0),
			size     = UDim2.new(1, -(SP.md + controlsW), 0, isLeader and nameH or ROW_H),
		}),
		leaderTag = isLeader and e(Text, {
			style    = "caption",
			text     = "★ Leader",
			color    = LEADER_COLOR,
			position = UDim2.fromOffset(SP.md, (ROW_H - nameH - tagH) / 2 + nameH),
			size     = UDim2.new(1, -(SP.md + controlsW), 0, tagH),
		}) or nil,

		-- Promote + Kick (only the leader sees them, only for others)
		promoteBtn = showControls and e(Button, {
			variant     = "secondary",
			size        = "sm",
			label       = "▲ Lead",
			width       = BTN_W,
			anchorPoint = Vector2.new(1, 0.5),
			position    = UDim2.new(1, -(SP.xs + BTN_W + SP.sm), 0.5, 0),
			onActivated = function()
				NetworkManager.FireServer("PartyRequest", { action = "PromoteMember", userId = member.userId })
			end,
		}) or nil,
		kickBtn = showControls and e(Button, {
			variant     = "danger",
			size        = "sm",
			label       = "Kick",
			width       = BTN_W,
			anchorPoint = Vector2.new(1, 0.5),
			position    = UDim2.new(1, -SP.xs, 0.5, 0),
			onActivated = function()
				NetworkManager.FireServer("PartyRequest", { action = "KickMember", userId = member.userId })
			end,
		}) or nil,
	})
end

-- ── BonusInfoPanel ────────────────────────────────────────────────────────────
-- Shows static XP bonus rates and live total when in a party.
-- props: party (nil or party table), memberCount
local function BonusInfoPanel(props)
	local party       = props.party
	local memberCount = props.memberCount or 0

	-- Build a rough client-side estimate of the bonus (server is authoritative)
	local bonusPct = 0
	if party and party.members then
		for _, m in ipairs(party.members) do
			if m.userId ~= LocalPlayer.UserId then
				bonusPct = bonusPct + (isFriend(m.userId) and 5.0 or 2.5)
			end
		end
	end

	local liveText = (memberCount > 1)
		and string.format("Current bonus: +%.1f%%", bonusPct)
		or  "Join or create a party for bonus XP!"
	local lineH = Theme.Type.caption.lineHeight

	-- §AGX/UI-P6: the two rate rows share one line (phone height budget).
	return e(Panel, {
		name        = "BonusInfo",
		elevation   = "sunken",
		padding     = "sm",
		layout      = "vertical",
		gap         = "xxs",
		anchorPoint = Vector2.new(0, 1),
		position    = UDim2.fromScale(0, 1),
		size        = UDim2.new(1, 0, 0, BONUS_H),
	}, {
		rates = e(Text, {
			style       = "caption",
			text        = "🎯 +2.5% XP per party ally   ·   ♥ +5.0% per friend ally",
			color       = "text.secondary",
			size        = UDim2.new(1, 0, 0, lineH),
			layoutOrder = 1,
		}),
		live = e(Text, {
			style       = "label",
			text        = liveText,
			color       = (memberCount > 1) and "accent.secondary" or "text.secondary",
			size        = UDim2.new(1, 0, 0, lineH),
			layoutOrder = 2,
		}),
	})
end

-- ── LeftPanel: Player Browser ─────────────────────────────────────────────────
local function LeftPanel(props)
	local playerList  = props.playerList  -- { {userId, name}, ... }
	local party       = props.party       -- nil or party table
	local partyFull   = props.partyFull

	-- Collect member userIds for fast lookup
	local memberIds = {}
	if party and party.members then
		for _, m in ipairs(party.members) do
			memberIds[m.userId] = true
		end
	end

	-- Sort: friends first, alphabetically within groups
	local friends, others = {}, {}
	for _, entry in ipairs(playerList) do
		if entry.userId ~= LocalPlayer.UserId then
			if isFriend(entry.userId) then
				table.insert(friends, entry)
			else
				table.insert(others, entry)
			end
		end
	end
	-- Insert self at top
	local sortedList = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p == LocalPlayer then
			table.insert(sortedList, { userId = LocalPlayer.UserId, name = LocalPlayer.Name })
			break
		end
	end
	table.sort(friends, function(a, b) return a.name < b.name end)
	table.sort(others,  function(a, b) return a.name < b.name end)
	for _, e_ in ipairs(friends) do table.insert(sortedList, e_) end
	for _, e_ in ipairs(others)  do table.insert(sortedList, e_) end

	-- Build row children
	local rowChildren = {}
	for i, entry in ipairs(sortedList) do
		rowChildren["row_" .. tostring(entry.userId)] = e(PlayerRow, {
			entry          = entry,
			partyFull      = partyFull,
			alreadyInParty = memberIds[entry.userId] or false,
			order          = i,
		})
	end

	return e(Panel, {
		name      = "PlayerBrowser",
		elevation = "flat",
		padding   = "sm",
		size      = UDim2.new(LEFT_FRAC, -COL_GAP / 2, 1, 0),
	}, {
		-- Header
		title = e(Text, {
			style = "heading",
			text  = "Players",
			size  = UDim2.new(1, -(REFRESH_W + SP.sm), 0, HEAD_H),
		}),
		refreshBtn = e(Button, {
			variant     = "ghost",
			size        = "sm",
			label       = "⟳ Refresh",
			width       = REFRESH_W,
			anchorPoint = Vector2.new(1, 0),
			position    = UDim2.fromScale(1, 0),
			onActivated = function()
				NetworkManager.FireServer("PlayerListRequest")
			end,
		}),

		-- Scroll frame for player rows
		scroll = ScrollList({
			name     = "PlayerList",
			position = UDim2.fromOffset(0, HEAD_H + SP.sm),
			size     = UDim2.new(1, 0, 1, -(HEAD_H + SP.sm)),
		}, rowChildren),
	})
end

-- ── RightPanel: Party Roster ──────────────────────────────────────────────────
local function RightPanel(props)
	local party    = props.party     -- nil or { id, leaderId, members = [{userId, name}] }

	local inParty       = (party ~= nil)
	local memberCount   = inParty and #party.members or 0
	local partyFull     = (memberCount >= MAX_PARTY)
	local isLocalLeader = inParty and (party.leaderId == LocalPlayer.UserId)

	local rosterH = -(BONUS_H + SP.sm)   -- roster fills the column above the bonus panel

	-- ── No-party state ─────────────────────────────────────────────────────
	local rosterSection
	if not inParty then
		rosterSection = e("Frame", {
			Name                   = "Roster",
			Size                   = UDim2.new(1, 0, 1, rosterH),
			BackgroundTransparency = 1,
		}, {
			layout = e("UIListLayout", {
				FillDirection       = Enum.FillDirection.Vertical,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment   = Enum.VerticalAlignment.Center,
				SortOrder           = Enum.SortOrder.LayoutOrder,
				Padding             = UDim.new(0, SP.md),
			}),
			label = e(Text, {
				style       = "body",
				text        = "You are not in a party.",
				color       = "text.secondary",
				align       = "center",
				layoutOrder = 1,
			}),
			-- The screen's ONE primary CTA (orange, D1 Hybrid).
			createBtn = e(Button, {
				variant     = "primary",
				size        = "md",
				label       = "+ Create Party",
				layoutOrder = 2,
				onActivated = function()
					NetworkManager.FireServer("PartyRequest", { action = "Create" })
				end,
			}),
		})
	else
		-- ── In-party state ──────────────────────────────────────────────────
		local memberChildren = {}
		for i, m in ipairs(party.members) do
			memberChildren["m_" .. tostring(m.userId)] = e(MemberRow, {
				member        = m,
				leaderId      = party.leaderId,
				isLocalLeader = isLocalLeader,
				order         = i,
			})
		end

		rosterSection = e("Frame", {
			Name                   = "Roster",
			Size                   = UDim2.new(1, 0, 1, rosterH),
			BackgroundTransparency = 1,
		}, {
			-- Header row: "Party n / 5" + Leave / Disband (was a bottom bar)
			sizeLabel = e(Text, {
				style = "heading",
				text  = string.format("Party  %d / %d", memberCount, MAX_PARTY),
				color = partyFull and "accent.secondary" or "text.secondary",
				size  = UDim2.new(1, -(ACTION_W + SP.sm), 0, HEAD_H),
			}),
			actionBtn = e(Button, {
				variant     = isLocalLeader and "danger" or "secondary",
				size        = "sm",
				label       = isLocalLeader and "⚑ Disband Party" or "← Leave Party",
				width       = ACTION_W,
				anchorPoint = Vector2.new(1, 0),
				position    = UDim2.fromScale(1, 0),
				onActivated = function()
					local action = isLocalLeader and "Disband" or "Leave"
					NetworkManager.FireServer("PartyRequest", { action = action })
				end,
			}),

			memberScroll = ScrollList({
				name     = "MemberList",
				position = UDim2.fromOffset(0, HEAD_H + SP.sm),
				size     = UDim2.new(1, 0, 1, -(HEAD_H + SP.sm)),
			}, memberChildren),
		})
	end

	return e(Panel, {
		name      = "PartyRoster",
		elevation = "flat",
		padding   = "sm",
		position  = UDim2.new(LEFT_FRAC, COL_GAP / 2, 0, 0),
		size      = UDim2.new(1 - LEFT_FRAC, -COL_GAP / 2, 1, 0),
	}, {
		rosterSection = rosterSection,

		-- Bonus info panel always at bottom
		bonusInfo = e(BonusInfoPanel, {
			party       = party,
			memberCount = memberCount,
		}),
	})
end

-- ── SocialPanel (root) ────────────────────────────────────────────────────────
local function SocialPanel(props)
	local onClose = props.onClose or function() end

	local activeTab,       setActiveTab       = React.useState("party")
	local playerList,      setPlayerList      = React.useState({})
	local party,           setParty           = React.useState(nil)
	-- Incremented after async friend-status pre-fetch completes,
	-- causing LeftPanel to re-render with correct friend indicators.
	local friendsVersion,  setFriendsVersion  = React.useState(0)

	-- Mount: request current data
	React.useEffect(function()
		NetworkManager.FireServer("PlayerListRequest")
		NetworkManager.FireServer("GetPlayerInfo")
		NetworkManager.FireServer("GetPartyState")  -- re-sync party roster (may have changed while panel was closed)

		local connList = NetworkManager.OnServerEvent("PlayerListUpdate", function(data)
			setPlayerList(data or {})
			-- Pre-warm friend-status cache for every player in the list.
			-- Rows render immediately (showing false until fetched); once all
			-- statuses are resolved, friendsVersion increments → LeftPanel re-renders.
			local list = data or {}
			local remaining = 0
			for _, entry in ipairs(list) do
				if entry.userId and entry.userId ~= LocalPlayer.UserId
					and friendsCache[entry.userId] == nil then
					remaining = remaining + 1
				end
			end
			if remaining > 0 then
				local done = 0
				for _, entry in ipairs(list) do
					if entry.userId and entry.userId ~= LocalPlayer.UserId
						and friendsCache[entry.userId] == nil then
						prefetchFriend(entry.userId, function()
							done = done + 1
							if done >= remaining then
								setFriendsVersion(function(v) return v + 1 end)
							end
						end)
					end
				end
			end
		end)

		local connParty = NetworkManager.OnServerEvent("PartyUpdate", function(data)
			if data and data.disbanded then
				setParty(nil)
			else
				setParty(data)
			end
		end)

		-- §AGX/UI-P6: rejections go to the one feedback system (Notify
		-- toast, 3.5 s, same key coalesces) instead of an inline label.
		local connErr = NetworkManager.OnServerEvent("PartyError", function(data)
			local msg = (type(data) == "table" and data.message) or tostring(data) or "Something went wrong."
			Notify.toast("error", msg, { key = "party_error" })
		end)

		return function()
			if connList  then connList:Disconnect()  end
			if connParty then connParty:Disconnect() end
			if connErr   then connErr:Disconnect()   end
		end
	end, {})

	local partyFull = (party ~= nil) and (#party.members >= MAX_PARTY)
	local contentTop = TABS_H + SP.sm

	-- ── Tab content ───────────────────────────────────────────────────────────
	local tabContent
	if activeTab == "party" then
		tabContent = e("Frame", {
			Name                   = "PartyTab",
			Position               = UDim2.fromOffset(0, contentTop),
			Size                   = UDim2.new(1, 0, 1, -contentTop),
			BackgroundTransparency = 1,
		}, {
			leftPanel = e(LeftPanel, {
				playerList = playerList,
				party      = party,
				partyFull  = partyFull,
				-- Passed only to force LeftPanel to re-render after async friend pre-fetch.
				_fv        = friendsVersion,
			}),
			rightPanel = e(RightPanel, {
				party = party,
			}),
		})
	else
		-- Guild tab stub
		tabContent = e("Frame", {
			Name                   = "GuildTab",
			Position               = UDim2.fromOffset(0, contentTop),
			Size                   = UDim2.new(1, 0, 1, -contentTop),
			BackgroundTransparency = 1,
		}, {
			label = e(Text, {
				style       = "heading",
				text        = "Guilds — coming soon!",
				color       = "text.secondary",
				align       = "center",
				anchorPoint = Vector2.new(0.5, 0.5),
				position    = UDim2.fromScale(0.5, 0.4),
			}),
		})
	end

	-- §T10/U3 / §AGX/UI-P6: chrome owned by AppWindow (the Registry entry
	-- sets the presentation: windowed, sheet on phone).
	return e(AppWindow, {
		variant = "auto",
		title   = "Social",
		icon    = "social",
		onClose = onClose,
		size    = UDim2.fromScale(0.72, 0.78),
		zIndex  = Theme.Z.window,
	}, {
		content = e(UIScaleRoot.Local, { name = "SocialBody", zIndex = Theme.Z.window + 2 }, {
			pad = e("UIPadding", {
				PaddingLeft = UDim.new(0, SP.lg), PaddingRight = UDim.new(0, SP.lg),
				PaddingTop = UDim.new(0, SP.sm), PaddingBottom = UDim.new(0, SP.md),
			}),

			tabBar = e(Tabs, {
				items    = TAB_ITEMS,
				value    = activeTab,
				onChange = setActiveTab,
				fill     = false,
				size     = UDim2.new(1, 0, 0, TABS_H),
			}),

			content = tabContent,
		}),
	})
end

return SocialPanel
