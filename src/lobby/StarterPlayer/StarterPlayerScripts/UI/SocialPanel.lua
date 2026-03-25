-- UI/SocialPanel.lua
--
-- Full-screen Social window (Party + Guild tabs).
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
--   PartyError       → show transient error toast
--
-- Party actions fired to server via PartyRequest event:
--   InviteById   { userId }
--   Create
--   Leave
--   Disband
--   KickMember   { userId }
--   PromoteMember { userId }

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React             = require(ReplicatedStorage.Packages.React)

local SharedModules  = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Modules")
local NetworkManager = require(SharedModules:WaitForChild("NetworkManager"))

local LocalPlayer = Players.LocalPlayer

-- ── Colours ──────────────────────────────────────────────────────────────────
local C = {
	bg_dark    = Color3.fromRGB( 18,  18,  24),
	bg_panel   = Color3.fromRGB( 24,  24,  33),
	bg_row     = Color3.fromRGB( 30,  30,  44),
	bg_row_alt = Color3.fromRGB( 34,  34,  50),
	accent     = Color3.fromRGB(105, 190, 255),
	friend     = Color3.fromRGB( 90, 210, 140),   -- friend name colour
	text       = Color3.fromRGB(225, 225, 230),
	text_dim   = Color3.fromRGB(140, 140, 160),
	text_leader= Color3.fromRGB(255, 200,  60),   -- gold for leader tag
	btn_blue   = Color3.fromRGB( 60, 135, 235),
	btn_green  = Color3.fromRGB( 45, 175,  95),
	btn_red    = Color3.fromRGB(185,  60,  60),
	btn_grey   = Color3.fromRGB( 58,  58,  78),
	tab_active = Color3.fromRGB( 35,  35,  52),
	tab_idle   = Color3.fromRGB( 22,  22,  32),
	close_bg   = Color3.fromRGB( 80,  36,  36),
	close_text = Color3.fromRGB(245, 100, 100),
	divider    = Color3.fromRGB( 50,  50,  70),
	bonus_bg   = Color3.fromRGB( 18,  30,  48),
}

local MAX_PARTY = 5

-- ── Tiny helpers ─────────────────────────────────────────────────────────────
local function UICorner(r)
	return React.createElement("UICorner", { CornerRadius = UDim.new(r or 0.12, 0) })
end

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

-- SmallButton removed — was unused. If a small button component is needed
-- in future, define it locally here with the same signature.

-- ── TabButton ─────────────────────────────────────────────────────────────────
local function TabButton(props)
	local active = props.active
	return React.createElement("TextButton", {
		Size             = UDim2.fromScale(0.18, 1),
		BackgroundColor3 = active and C.tab_active or C.tab_idle,
		BorderSizePixel  = 0,
		Text             = props.label,
		TextColor3       = active and C.accent or C.text_dim,
		Font             = active and Enum.Font.GothamBold or Enum.Font.Gotham,
		TextScaled       = true,
		LayoutOrder      = props.order or 1,
		[React.Event.Activated] = props.onSelect,
	}, { UICorner(0.35) })
end

-- ── PlayerRow (left panel) ────────────────────────────────────────────────────
-- props: entry {userId, name}, inParty, partyFull, alreadyInMyParty
local function PlayerRow(props)
	local entry           = props.entry
	local partyFull       = props.partyFull
	local alreadyInParty  = props.alreadyInParty
	local isSelf          = (entry.userId == LocalPlayer.UserId)
	local friend          = isFriend(entry.userId)
	local nameColor       = friend and C.friend or C.text

	local canInvite = not isSelf and not alreadyInParty and not partyFull

	return React.createElement("Frame", {
		Size             = UDim2.fromScale(1, 0.065),
		BackgroundColor3 = C.bg_row,
		BorderSizePixel  = 0,
		LayoutOrder      = props.order or 1,
	}, {
		UICorner(0.2),

		nameLabel = React.createElement("TextLabel", {
			Position               = UDim2.fromScale(0.03, 0.12),
			Size                   = UDim2.fromScale(0.62, 0.76),
			BackgroundTransparency = 1,
			Text                   = entry.name .. (friend and "  ♥" or "") .. (isSelf and " (you)" or ""),
			TextColor3             = nameColor,
			Font                   = Enum.Font.Gotham,
			TextScaled             = true,
			TextXAlignment         = Enum.TextXAlignment.Left,
		}),

		inviteBtn = (not isSelf) and React.createElement("TextButton", {
			AnchorPoint      = Vector2.new(1, 0.5),
			Position         = UDim2.fromScale(0.97, 0.5),
			Size             = UDim2.fromScale(0.30, 0.70),
			BackgroundColor3 = canInvite and C.btn_blue or C.btn_grey,
			BorderSizePixel  = 0,
			Text             = alreadyInParty and "In Party" or (partyFull and "Full" or "Invite"),
			TextColor3       = C.text,
			Font             = Enum.Font.GothamBold,
			TextScaled       = true,
			Active           = canInvite,
			[React.Event.Activated] = canInvite and function()
				NetworkManager.FireServer("PartyRequest", { action = "InviteById", userId = entry.userId })
			end or nil,
		}, { UICorner(0.3) }) or nil,
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

	return React.createElement("Frame", {
		Size             = UDim2.fromScale(1, 0.085),
		BackgroundColor3 = C.bg_row_alt,
		BorderSizePixel  = 0,
		LayoutOrder      = props.order or 1,
	}, {
		UICorner(0.2),

		-- Name + (Leader) tag
		nameLabel = React.createElement("TextLabel", {
			Position               = UDim2.fromScale(0.03, 0.12),
			Size                   = UDim2.fromScale(isLocalLeader and 0.45 or 0.70, 0.76),
			BackgroundTransparency = 1,
			Text                   = member.name,
			TextColor3             = isLeader and C.text_leader or C.text,
			Font                   = isLeader and Enum.Font.GothamBold or Enum.Font.Gotham,
			TextScaled             = true,
			TextXAlignment         = Enum.TextXAlignment.Left,
		}),

		leaderTag = isLeader and React.createElement("TextLabel", {
			Position               = UDim2.fromScale(0.03, 0.60),
			Size                   = UDim2.fromScale(0.30, 0.35),
			BackgroundTransparency = 1,
			Text                   = "★ Leader",
			TextColor3             = C.text_leader,
			Font                   = Enum.Font.Gotham,
			TextScaled             = true,
			TextXAlignment         = Enum.TextXAlignment.Left,
		}) or nil,

		-- Kick + Promote buttons (only leader sees, only for others)
		kickBtn = (isLocalLeader and not isSelf) and React.createElement("TextButton", {
			AnchorPoint      = Vector2.new(1, 0.5),
			Position         = UDim2.fromScale(0.97, 0.5),
			Size             = UDim2.fromScale(0.16, 0.65),
			BackgroundColor3 = C.btn_red,
			BorderSizePixel  = 0,
			Text             = "Kick",
			TextColor3       = C.text,
			Font             = Enum.Font.GothamBold,
			TextScaled       = true,
			[React.Event.Activated] = function()
					NetworkManager.FireServer("PartyRequest", { action = "KickMember", userId = member.userId })
			end,
		}, { UICorner(0.3) }) or nil,

		promoteBtn = (isLocalLeader and not isSelf) and React.createElement("TextButton", {
			AnchorPoint      = Vector2.new(1, 0.5),
			Position         = UDim2.fromScale(0.79, 0.5),
			Size             = UDim2.fromScale(0.16, 0.65),
			BackgroundColor3 = C.btn_blue,
			BorderSizePixel  = 0,
			Text             = "▲ Lead",
			TextColor3       = C.text,
			Font             = Enum.Font.GothamBold,
			TextScaled       = true,
			[React.Event.Activated] = function()
					NetworkManager.FireServer("PartyRequest", { action = "PromoteMember", userId = member.userId })
			end,
		}, { UICorner(0.3) }) or nil,
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

	return React.createElement("Frame", {
		AnchorPoint      = Vector2.new(0, 1),
		Position         = UDim2.fromScale(0, 1),
		Size             = UDim2.fromScale(1, 0.22),
		BackgroundColor3 = C.bonus_bg,
		BorderSizePixel  = 0,
	}, {
		UICorner(0.08),

		layout = React.createElement("UIListLayout", {
			FillDirection  = Enum.FillDirection.Vertical,
			Padding        = UDim.new(0.01, 0),
			SortOrder      = Enum.SortOrder.LayoutOrder,
		}),

		padding = React.createElement("UIPadding", {
			PaddingLeft   = UDim.new(0.04, 0),
			PaddingTop    = UDim.new(0.06, 0),
			PaddingRight  = UDim.new(0.04, 0),
		}),

		row1 = React.createElement("TextLabel", {
			Size                   = UDim2.fromScale(1, 0.28),
			BackgroundTransparency = 1,
			Text                   = "🎯  +2.5% XP per party ally",
			TextColor3             = C.text_dim,
			Font                   = Enum.Font.Gotham,
			TextScaled             = true,
			TextXAlignment         = Enum.TextXAlignment.Left,
			LayoutOrder            = 1,
		}),

		row2 = React.createElement("TextLabel", {
			Size                   = UDim2.fromScale(1, 0.28),
			BackgroundTransparency = 1,
			Text                   = "💙  +5.0% XP per friend ally",
			TextColor3             = C.friend,
			Font                   = Enum.Font.Gotham,
			TextScaled             = true,
			TextXAlignment         = Enum.TextXAlignment.Left,
			LayoutOrder            = 2,
		}),

		row3 = React.createElement("TextLabel", {
			Size                   = UDim2.fromScale(1, 0.28),
			BackgroundTransparency = 1,
			Text                   = liveText,
			TextColor3             = (memberCount > 1) and C.accent or C.text_dim,
			Font                   = Enum.Font.GothamBold,
			TextScaled             = true,
			TextXAlignment         = Enum.TextXAlignment.Left,
			LayoutOrder            = 3,
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
	for _, e in ipairs(friends) do table.insert(sortedList, e) end
	for _, e in ipairs(others)  do table.insert(sortedList, e) end

	-- Build row children
	local rowChildren = {
		layout = React.createElement("UIListLayout", {
			FillDirection  = Enum.FillDirection.Vertical,
			Padding        = UDim.new(0.008, 0),
			SortOrder      = Enum.SortOrder.LayoutOrder,
		}),
	}
	for i, entry in ipairs(sortedList) do
		rowChildren["row_" .. tostring(entry.userId)] = React.createElement(PlayerRow, {
			entry         = entry,
			partyFull     = partyFull,
			alreadyInParty= memberIds[entry.userId] or false,
			order         = i,
		})
	end

	return React.createElement("Frame", {
		Size             = UDim2.fromScale(0.38, 1),
		BackgroundColor3 = C.bg_panel,
		BorderSizePixel  = 0,
	}, {
		UICorner(0.04),

		-- Header
		header = React.createElement("Frame", {
			Size             = UDim2.fromScale(1, 0.07),
			BackgroundColor3 = C.bg_dark,
			BorderSizePixel  = 0,
		}, {
			UICorner(0.25),
			title = React.createElement("TextLabel", {
				Position               = UDim2.fromScale(0.04, 0),
				Size                   = UDim2.fromScale(0.65, 1),
				BackgroundTransparency = 1,
				Text                   = "Players",
				TextColor3             = C.text,
				Font                   = Enum.Font.GothamBold,
				TextScaled             = true,
				TextXAlignment         = Enum.TextXAlignment.Left,
			}),
			refreshBtn = React.createElement("TextButton", {
				AnchorPoint      = Vector2.new(1, 0.5),
				Position         = UDim2.fromScale(0.97, 0.5),
				Size             = UDim2.fromScale(0.26, 0.75),
				BackgroundColor3 = C.btn_grey,
				BorderSizePixel  = 0,
				Text             = "⟳ Refresh",
				TextColor3       = C.text_dim,
				Font             = Enum.Font.Gotham,
				TextScaled       = true,
				[React.Event.Activated] = function()
					NetworkManager.FireServer("PlayerListRequest")
				end,
			}, { UICorner(0.35) }),
		}),

		-- Scroll frame for player rows
		scroll = React.createElement("ScrollingFrame", {
			Position         = UDim2.fromScale(0, 0.09),
			Size             = UDim2.fromScale(1, 0.91),
			BackgroundTransparency = 1,
			BorderSizePixel  = 0,
			ScrollBarThickness = 4,
			ScrollBarImageColor3 = C.accent,
			CanvasSize       = UDim2.fromScale(1, 0),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
		}, rowChildren),
	})
end

-- ── RightPanel: Party Roster ──────────────────────────────────────────────────
local function RightPanel(props)
	local party    = props.party     -- nil or { id, leaderId, members = [{userId, name}] }
	local errorMsg = props.errorMsg

	local inParty       = (party ~= nil)
	local memberCount   = inParty and #party.members or 0
	local partyFull     = (memberCount >= MAX_PARTY)
	local isLocalLeader = inParty and (party.leaderId == LocalPlayer.UserId)

	-- ── No-party state ─────────────────────────────────────────────────────
	local rosterSection
	if not inParty then
		rosterSection = React.createElement("Frame", {
			Size             = UDim2.fromScale(1, 0.70),
			BackgroundTransparency = 1,
		}, {
			label = React.createElement("TextLabel", {
				AnchorPoint            = Vector2.new(0.5, 0.4),
				Position               = UDim2.fromScale(0.5, 0.4),
				Size                   = UDim2.fromScale(0.75, 0.08),
				BackgroundTransparency = 1,
				Text                   = "You are not in a party.",
				TextColor3             = C.text_dim,
				Font                   = Enum.Font.Gotham,
				TextScaled             = true,
			}),
			createBtn = React.createElement("TextButton", {
				AnchorPoint      = Vector2.new(0.5, 0),
				Position         = UDim2.fromScale(0.5, 0.52),
				Size             = UDim2.fromScale(0.55, 0.10),
				BackgroundColor3 = C.btn_green,
				BorderSizePixel  = 0,
				Text             = "+ Create Party",
				TextColor3       = C.text,
				Font             = Enum.Font.GothamBold,
				TextScaled       = true,
				[React.Event.Activated] = function()
					NetworkManager.FireServer("PartyRequest", { action = "Create" })
				end,
			}, { UICorner(0.25) }),
		})
	else
		-- ── In-party state ──────────────────────────────────────────────────
		local memberChildren = {
			layout = React.createElement("UIListLayout", {
				FillDirection  = Enum.FillDirection.Vertical,
				Padding        = UDim.new(0.010, 0),
				SortOrder      = Enum.SortOrder.LayoutOrder,
			}),
		}
		for i, m in ipairs(party.members) do
			memberChildren["m_" .. tostring(m.userId)] = React.createElement(MemberRow, {
				member        = m,
				leaderId      = party.leaderId,
				isLocalLeader = isLocalLeader,
				order         = i,
			})
		end

		local actionText = isLocalLeader and "⚑ Disband Party" or "← Leave Party"
		local actionColor = isLocalLeader and C.btn_red or C.btn_grey

		rosterSection = React.createElement("Frame", {
			Size             = UDim2.fromScale(1, 0.70),
			BackgroundTransparency = 1,
		}, {
			sizeLabel = React.createElement("TextLabel", {
				Position               = UDim2.fromScale(0.03, 0.01),
				Size                   = UDim2.fromScale(0.60, 0.06),
				BackgroundTransparency = 1,
				Text                   = string.format("Party  %d / %d", memberCount, MAX_PARTY),
				TextColor3             = partyFull and C.accent or C.text_dim,
				Font                   = Enum.Font.GothamBold,
				TextScaled             = true,
				TextXAlignment         = Enum.TextXAlignment.Left,
			}),

			memberScroll = React.createElement("ScrollingFrame", {
				Position         = UDim2.fromScale(0, 0.09),
				Size             = UDim2.fromScale(1, 0.78),
				BackgroundTransparency = 1,
				BorderSizePixel  = 0,
				ScrollBarThickness = 4,
				ScrollBarImageColor3 = C.accent,
				CanvasSize       = UDim2.fromScale(1, 0),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
			}, memberChildren),

			actionBtn = React.createElement("TextButton", {
				AnchorPoint      = Vector2.new(0, 1),
				Position         = UDim2.fromScale(0.03, 1),
				Size             = UDim2.fromScale(0.94, 0.09),
				BackgroundColor3 = actionColor,
				BorderSizePixel  = 0,
				Text             = actionText,
				TextColor3       = C.text,
				Font             = Enum.Font.GothamBold,
				TextScaled       = true,
				[React.Event.Activated] = function()
					local action = isLocalLeader and "Disband" or "Leave"
					NetworkManager.FireServer("PartyRequest", { action = action })
				end,
			}, { UICorner(0.2) }),
		})
	end

	return React.createElement("Frame", {
		Size             = UDim2.fromScale(0.59, 1),
		BackgroundColor3 = C.bg_panel,
		BorderSizePixel  = 0,
	}, {
		UICorner(0.04),

		rosterSection = rosterSection,

		-- Bonus info panel always at bottom
		bonusInfo = React.createElement(BonusInfoPanel, {
			party       = party,
			memberCount = memberCount,
		}),

		-- Transient error toast
		errorToast = errorMsg and React.createElement("TextLabel", {
			AnchorPoint            = Vector2.new(0.5, 0),
			Position               = UDim2.fromScale(0.5, 0.01),
			Size                   = UDim2.fromScale(0.90, 0.06),
			BackgroundColor3       = Color3.fromRGB(90, 30, 30),
			BackgroundTransparency = 0.15,
			BorderSizePixel        = 0,
			Text                   = errorMsg,
			TextColor3             = Color3.fromRGB(255, 130, 130),
			Font                   = Enum.Font.GothamBold,
			TextScaled             = true,
		}, { UICorner(0.3) }) or nil,
	})
end

-- ── SocialPanel (root) ────────────────────────────────────────────────────────
local function SocialPanel(props)
	local onClose = props.onClose or function() end

	local activeTab,       setActiveTab       = React.useState("party")
	local playerList,      setPlayerList      = React.useState({})
	local party,           setParty           = React.useState(nil)
	local errorMsg,        setErrorMsg        = React.useState(nil)
	-- Incremented after async friend-status pre-fetch completes,
	-- causing LeftPanel to re-render with correct friend indicators.
	local friendsVersion,  setFriendsVersion  = React.useState(0)

	-- Mount: request current data
	React.useEffect(function()
		local mounted = true
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

		local connErr = NetworkManager.OnServerEvent("PartyError", function(data)
			local msg = (type(data) == "table" and data.message) or tostring(data) or "Something went wrong."
			setErrorMsg(msg)
			task.delay(3.5, function()
				if mounted then setErrorMsg(nil) end
			end)
		end)

		return function()
			mounted = false
			if connList  then connList:Disconnect()  end
			if connParty then connParty:Disconnect() end
			if connErr   then connErr:Disconnect()   end
		end
	end, {})

	local partyFull = (party ~= nil) and (#party.members >= MAX_PARTY)

	-- ── Tab content ───────────────────────────────────────────────────────────
	local partyTabContent
	if activeTab == "party" then
		partyTabContent = React.createElement("Frame", {
			Position         = UDim2.fromScale(0, 0.11),
			Size             = UDim2.fromScale(1, 0.89),
			BackgroundTransparency = 1,
		}, {
			layout = React.createElement("UIListLayout", {
				FillDirection       = Enum.FillDirection.Horizontal,
				VerticalAlignment   = Enum.VerticalAlignment.Top,
				HorizontalAlignment = Enum.HorizontalAlignment.Left,
				SortOrder           = Enum.SortOrder.LayoutOrder,
				Padding             = UDim.new(0.02, 0),
			}),
			padding = React.createElement("UIPadding", {
				PaddingLeft  = UDim.new(0.015, 0),
				PaddingRight = UDim.new(0.015, 0),
				PaddingTop   = UDim.new(0.01, 0),
			}),
			leftPanel = React.createElement(LeftPanel, {
				playerList = playerList,
				party      = party,
				partyFull  = partyFull,
				-- Passed only to force LeftPanel to re-render after async friend pre-fetch.
				_fv        = friendsVersion,
			}),
			rightPanel = React.createElement(RightPanel, {
				party    = party,
				errorMsg = errorMsg,
			}),
		})
	else
		-- Guild tab stub
		partyTabContent = React.createElement("Frame", {
			Position               = UDim2.fromScale(0, 0.11),
			Size                   = UDim2.fromScale(1, 0.89),
			BackgroundTransparency = 1,
		}, {
			label = React.createElement("TextLabel", {
				AnchorPoint            = Vector2.new(0.5, 0.4),
				Position               = UDim2.fromScale(0.5, 0.4),
				Size                   = UDim2.fromScale(0.60, 0.08),
				BackgroundTransparency = 1,
				Text                   = "Guilds — coming soon!",
				TextColor3             = C.text_dim,
				Font                   = Enum.Font.GothamBold,
				TextScaled             = true,
			}),
		})
	end

	-- ── Panel ─────────────────────────────────────────────────────────────────
	local panelChildren = {
		corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.015, 0) }),

		-- Title
		title = React.createElement("TextLabel", {
			Position               = UDim2.fromScale(0.025, 0.015),
			Size                   = UDim2.fromScale(0.50, 0.065),
			BackgroundTransparency = 1,
			Text                   = "Social",
			TextColor3             = C.text,
			Font                   = Enum.Font.GothamBold,
			TextScaled             = true,
			TextXAlignment         = Enum.TextXAlignment.Left,
		}),

		-- Close button
		closeBtn = React.createElement("TextButton", {
			Position         = UDim2.fromScale(0.915, 0.015),
			Size             = UDim2.fromScale(0.07, 0.065),
			BackgroundColor3 = C.close_bg,
			BorderSizePixel  = 0,
			Text             = "✕",
			TextColor3       = C.close_text,
			Font             = Enum.Font.GothamBold,
			TextScaled       = true,
			[React.Event.Activated] = onClose,
		}, { UICorner(0.3) }),

		-- Tab bar
		tabBar = React.createElement("Frame", {
			Position         = UDim2.fromScale(0.025, 0.088),
			Size             = UDim2.fromScale(0.40, 0.048),
			BackgroundTransparency = 1,
		}, {
			layout = React.createElement("UIListLayout", {
				FillDirection = Enum.FillDirection.Horizontal,
				Padding       = UDim.new(0.02, 0),
				SortOrder     = Enum.SortOrder.LayoutOrder,
			}),
			partyTab = React.createElement(TabButton, {
				label    = "Party",
				active   = (activeTab == "party"),
				order    = 1,
				onSelect = function() setActiveTab("party") end,
			}),
			guildTab = React.createElement(TabButton, {
				label    = "Guild",
				active   = (activeTab == "guild"),
				order    = 2,
				onSelect = function() setActiveTab("guild") end,
			}),
		}),

		-- Tab content
		content = partyTabContent,
	}

	-- ── Root: fullscreen backdrop ─────────────────────────────────────────────
	return React.createElement("Frame", {
		Name                   = "SocialPanelBackdrop",
		Size                   = UDim2.fromScale(1, 1),
		BackgroundColor3       = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.42,
		ZIndex                 = 10,
	}, {
		panel = React.createElement("Frame", {
			Name             = "SocialPanel",
			AnchorPoint      = Vector2.new(0.5, 0.5),
			Position         = UDim2.fromScale(0.5, 0.5),
			Size             = UDim2.fromScale(0.88, 0.82),
			BackgroundColor3 = C.bg_dark,
			BorderSizePixel  = 0,
			ZIndex           = 11,
		}, panelChildren),
	})
end

return SocialPanel
