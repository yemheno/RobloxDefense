-- SocialPanel.client.lua
-- Social panel: party creation / management, online friends list, tab bar.
-- Tab bar wiring is shared with Overlays.client.lua (wireTabBar); this
-- controller handles the dynamic server-driven content.

local UIUtils = require(script.Parent:WaitForChild("UIUtils"))

local w    = UIUtils.w
local nm   = UIUtils.nm()
local root = UIUtils.root()

-- ── References ────────────────────────────────────────────────────────────────
-- Backdrop: "SocialPanelBackdrop"   Panel: "SocialPanelPanel"
local spBd = w(root, "SocialPanelBackdrop")
local spPn = w(spBd, "SocialPanelPanel")

-- ── Party Roster ──────────────────────────────────────────────────────────────
local rosterFrame = spPn:FindFirstChild("PartyRoster")
local cpBtn       = rosterFrame and rosterFrame:FindFirstChild("CreatePartyBtn")

if cpBtn then
	cpBtn.Activated:Connect(function()
		cpBtn.Text             = "Party Created!  ✓"
		cpBtn.BackgroundColor3 = Color3.fromRGB(40, 160, 80)
		cpBtn.Active           = false
		-- §EV7 fix: server routes party actions via the "PartyRequest"
		-- bus (PartyManager.HandleRequest). The legacy "CreateParty"
		-- direct event doesn't exist server-side.
		nm.FireServer("PartyRequest", { action = "Create" })
	end)
end

-- §EV5 fix: server fires "PartyUpdate" (PartyManager.lua:618 et al). The
-- legacy "PartyUpdated" name made the client WaitForChild time out and
-- warn at lobby boot.
-- Server pushes updated party roster after any member join/leave
nm.OnServerEvent("PartyUpdate", function(data)
	if not rosterFrame then return end
	local memberList = rosterFrame:FindFirstChild("MemberList")
	if not memberList then return end

	-- Remove stale member labels
	for _, child in ipairs(memberList:GetChildren()) do
		if child:IsA("TextLabel") and child.Name:sub(1, 7) == "Member_" then
			child:Destroy()
		end
	end

	-- Restore Create button if party was disbanded
	if cpBtn and (not data.members or #data.members == 0) then
		cpBtn.Text             = "Create Party"
		cpBtn.BackgroundColor3 = Color3.fromRGB(50, 90, 160)
		cpBtn.Active           = true
	end

	for i, memberName in ipairs(data.members or {}) do
		local lbl                  = Instance.new("TextLabel")
		lbl.Name                   = "Member_" .. i
		lbl.Size                   = UDim2.fromScale(1, 0.1)
		lbl.BackgroundTransparency = 1
		lbl.Text                   = memberName
		lbl.TextColor3             = Color3.fromRGB(200, 200, 220)
		lbl.Font                   = Enum.Font.Gotham
		lbl.TextScaled             = true
		lbl.LayoutOrder            = i
		lbl.Parent                 = memberList
	end
end)

-- ── Friends / Online Players ──────────────────────────────────────────────────
local function populateFriendsList(data)
	local friendsFrame = spPn:FindFirstChild("FriendsFrame")
	if not friendsFrame then return end
	local list = friendsFrame:FindFirstChild("List")
	if not list then return end

	for _, child in ipairs(list:GetChildren()) do
		if child:IsA("TextLabel") then child:Destroy() end
	end

	for i, entry in ipairs(data.friends or {}) do
		local lbl                  = Instance.new("TextLabel")
		lbl.Name                   = "Friend_" .. i
		lbl.Size                   = UDim2.fromScale(1, 0.08)
		lbl.BackgroundTransparency = 1
		lbl.Text                   = (entry.online and "● " or "○ ") .. (entry.name or "?")
		lbl.TextColor3             = entry.online
			and Color3.fromRGB(80, 210, 120)
			or  Color3.fromRGB(130, 130, 150)
		lbl.Font                   = Enum.Font.Gotham
		lbl.TextScaled             = true
		lbl.LayoutOrder            = i
		lbl.Parent                 = list
	end
end

-- §EV6 fix: the server has no FriendsOnlineList / GetFriendsOnline /
-- GetPartyState events yet (parking-lot item: §UI2 friends pipeline).
-- Subscribing on a non-existent event blocks lobby boot for 3 s with a
-- "Event not found" warn. Gate the wiring on the events actually
-- existing so we don't pay the WaitForChild timeout — when the friends
-- pipeline is wired server-side later, no client change needed.
local Events = game:GetService("ReplicatedStorage"):FindFirstChild("Events")
if Events and Events:FindFirstChild("FriendsOnlineList") then
	nm.OnServerEvent("FriendsOnlineList", function(data)
		populateFriendsList(data)
	end)
end

-- Request fresh list each time the panel becomes visible. Skip the
-- friends ping if that event doesn't exist on the server (see above).
spBd:GetPropertyChangedSignal("Visible"):Connect(function()
	if not spBd.Visible then return end
	if Events and Events:FindFirstChild("GetFriendsOnline") then
		nm.FireServer("GetFriendsOnline")
	end
	if Events and Events:FindFirstChild("GetPartyState") then
		nm.FireServer("GetPartyState")
	end
end)

-- ── Invite-to-party buttons in friend list ────────────────────────────────────
-- These are spawned dynamically; we watch the List for new children and wire them.
local friendsFrame = spPn:FindFirstChild("FriendsFrame")
local friendList   = friendsFrame and friendsFrame:FindFirstChild("List")
if friendList then
	friendList.ChildAdded:Connect(function(child)
		local invBtn = child:FindFirstChild("InviteBtn")
		if invBtn and child:IsA("Frame") then
			invBtn.Activated:Connect(function()
				-- §EV7 follow-up: route through the PartyRequest bus.
				nm.FireServer("PartyRequest", { action = "Invite", targetName = child.Name })
			end)
		end
	end)
end

print("[SocialPanel] Wired")
