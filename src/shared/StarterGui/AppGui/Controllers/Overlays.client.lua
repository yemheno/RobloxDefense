-- Overlays.client.lua
-- Keyboard shortcuts, navigation panel slide tween, panel close buttons,
-- tab bars, and all panel-local static button wiring.
-- This replaces the non-live-data portion of the old AppGuiWiring LocalScript.
--
-- Live data (HP / XP / currency / events) lives in HUD.client.lua.
-- Social-specific logic lives in SocialPanel.client.lua.

local TweenService = game:GetService("TweenService")
local UIS          = game:GetService("UserInputService")
local UIUtils      = require(script.Parent:WaitForChild("UIUtils"))

local w    = UIUtils.w
local nm   = UIUtils.nm()
local root = UIUtils.root()

-- ── Panel reference helpers ───────────────────────────────────────────────────
-- "bd" = Backdrop    "op" = inner Panel child
local function bd(name)           return w(root, name .. "Backdrop")             end
local function op(backdrop, name) return w(backdrop, name .. "Panel")            end

-- ── Instance references ───────────────────────────────────────────────────────
local hud       = w(root, "HUD")
local menuBtn   = w(hud,  "MenuBtn")
local navToggle = w(hud,  "NavToggle")
local navPanel  = w(hud,  "NavPanel")

local cmBd  = bd("ClassMenu");       local cmPn   = op(cmBd,  "ClassMenu")
local smBd  = bd("StatsMenu");       local smPn   = op(smBd,  "StatsMenu")
local eqBd  = bd("EquipmentUI");     local eqPn   = op(eqBd,  "EquipmentUI")
local ttBd  = w(root, "TalentTreeBackdrop")
local wdBd  = w(root, "WardrobeBackdrop");        local wdPn   = w(wdBd,  "WardrobePanel")
local achBd = bd("AchievementsUI");  local achPn  = op(achBd, "AchievementsUI")
local setBd = bd("SettingsUI");      local setPn  = op(setBd, "SettingsUI")
local gsBd  = bd("GlobalShop");      local gsPn   = op(gsBd,  "GlobalShop")
local ccBd  = w(root, "CharCreationBackdrop");    local ccPn  = w(ccBd,  "CharCreationPanel")
local emBd  = w(root, "EmoteWheelBackdrop")
local voteBd = w(root, "VoteUIBackdrop");         local voteP = w(voteBd, "VotePanel")
local mmBd  = w(root, "MainMenuBackdrop")
local mmkBar = w(root, "MatchmakingUI")
local spBd  = bd("SocialPanel");     local spPn   = op(spBd,  "SocialPanel")
local npcBd = w(root, "NPCDialogBackdrop");       local npcPn  = w(npcBd, "NPCDialogPanel")
local shopBd = w(root, "ShopUIBackdrop");         local shopPn = w(shopBd, "ShopUIPanel")
local wsBd  = bd("WeaponSmith");     local wsPn   = op(wsBd,  "WeaponSmith")
local dlBd  = bd("DailyLogin");      local dlPn   = op(dlBd,  "DailyLogin")
local lbBd  = bd("Leaderboard");     local lbPn   = op(lbBd,  "Leaderboard")
local invBd = bd("Inventory");       local invPn  = op(invBd, "Inventory")
local piToast = w(root, "PartyInviteToast")
local testUI  = w(root, "TestingUI")
local appBar  = w(root, "AppearanceBar")

-- ── Escape key: close topmost open overlay ────────────────────────────────────
local OVERLAYS = {
	cmBd, smBd, eqBd, ttBd, wdBd, achBd, setBd, gsBd,
	mmBd, spBd, shopBd, wsBd, dlBd, lbBd, invBd,
}

UIS.InputBegan:Connect(function(inp, proc)
	if proc then return end
	if inp.KeyCode == Enum.KeyCode.Escape then
		for _, overlay in ipairs(OVERLAYS) do
			if overlay.Visible then
				overlay.Visible = false
				return
			end
		end
	elseif inp.KeyCode == Enum.KeyCode.Q then
		emBd.Visible = not emBd.Visible
	end
end)

-- ── Nav panel: slide tween ────────────────────────────────────────────────────
local navOpen     = false
local navCloseTid = nil

local function openNav()
	if navCloseTid then task.cancel(navCloseTid); navCloseTid = nil end
	navPanel.Visible = true
	TweenService:Create(
		navPanel,
		TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
		{ Position = UDim2.fromScale(0.985, 0.50) }
	):Play()
end

local function closeNav()
	local CLOSE_TIME = 0.13
	TweenService:Create(
		navPanel,
		TweenInfo.new(CLOSE_TIME, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
		{ Position = UDim2.fromScale(1.20, 0.50) }
	):Play()
	navCloseTid = task.delay(CLOSE_TIME, function()
		navCloseTid = nil
		if navPanel and navPanel.Parent then navPanel.Visible = false end
	end)
end

-- Initialise nav panel off-screen
navPanel.Position = UDim2.fromScale(1.20, 0.50)
navPanel.Visible  = false

navToggle.Activated:Connect(function()
	navOpen = not navOpen
	if navOpen then openNav() else closeNav() end
end)

-- Menu button (hamburger, top-left) → open MainMenu
menuBtn.Activated:Connect(function()
	navOpen = false
	closeNav()
	mmBd.Visible = true
end)

-- Nav panel buttons → open their matching panel
local NAV_MAP = {
	NavClasses      = cmBd,
	NavStats        = smBd,
	NavEquip        = eqBd,
	NavTalents      = ttBd,
	NavAchievements = achBd,
	NavSocial       = spBd,
	NavShop         = gsBd,
	NavSettings     = setBd,
	NavInventory    = invBd,
	NavLeaderboard  = lbBd,
	NavDailyLogin   = dlBd,
}

for _, b in ipairs(navPanel:GetChildren()) do
	if b:IsA("TextButton") and NAV_MAP[b.Name] then
		local tgt = NAV_MAP[b.Name]
		b.Activated:Connect(function()
			navOpen = false
			closeNav()
			tgt.Visible = true
		end)
	end
end

-- ── Close buttons on panels ───────────────────────────────────────────────────
-- TalentTree close is wired by TalentTree.client.lua (if present).
local CLOSE_PAIRS = {
	{ cmPn,   cmBd  }, { smPn,  smBd  }, { eqPn,  eqBd  },
	{ wdPn,   wdBd  }, { achPn, achBd }, { setPn, setBd },
	{ gsPn,   gsBd  }, { mmBd,  mmBd  }, { spPn,  spBd  },
	{ npcPn,  npcBd }, { shopPn, shopBd }, { wsPn, wsBd  },
	{ dlPn,   dlBd  }, { lbPn,  lbBd  }, { invPn, invBd },
}

for _, pair in ipairs(CLOSE_PAIRS) do
	local btn = pair[1]:FindFirstChild("CloseBtn")
	if btn then
		btn.Activated:Connect(function() pair[2].Visible = false end)
	end
end

-- ── Daily Login: Claim button ─────────────────────────────────────────────────
local claimBtn = dlPn:FindFirstChild("ClaimBtn")
if claimBtn then
	claimBtn.Activated:Connect(function()
		claimBtn.Text             = "Claimed!  ✓"
		claimBtn.BackgroundColor3 = Color3.fromRGB(35, 90, 45)
		claimBtn.Active           = false
		nm.FireServer("ClaimDailyLogin")
		task.delay(1.5, function() dlBd.Visible = false end)
	end)
end

-- ── Matchmaking: Cancel button ────────────────────────────────────────────────
-- §EV9 fix: route through the MatchmakingRequest bus
-- (MatchmakingManager.HandleRequest); legacy "CancelQueue" event doesn't
-- exist server-side.
w(mmkBar, "CancelBtn").Activated:Connect(function()
	nm.FireServer("MatchmakingRequest", { action = "Cancel" })
	mmkBar.Visible = false
end)

-- ── Party invite toast ────────────────────────────────────────────────────────
-- §EV8 fix: route accept/decline through the PartyRequest bus
-- (PartyManager.HandleRequest actions "AcceptInvite" / "DeclineInvite");
-- the legacy "PartyInviteResponse" event doesn't exist server-side.
w(piToast, "AcceptBtn").Activated:Connect(function()
	nm.FireServer("PartyRequest", { action = "AcceptInvite" })
	piToast.Visible = false
end)
w(piToast, "DeclineBtn").Activated:Connect(function()
	nm.FireServer("PartyRequest", { action = "DeclineInvite" })
	piToast.Visible = false
end)
w(piToast, "DismissBtn").Activated:Connect(function()
	piToast.Visible = false
end)

-- §EV1 fix: server fires "PartyInvite" (PartyManager.InvitePlayer); the legacy
-- "PartyInviteReceived" name made the client WaitForChild time out, blocking
-- lobby boot for 3 s and warning "Event not found".
nm.OnServerEvent("PartyInvite", function(data)
	local titleLbl = piToast:FindFirstChild("TitleLabel")
	if titleLbl then
		titleLbl.Text = (data.inviterName or "Someone") .. " invited you to a party!"
	end
	piToast.Visible = true
	task.delay(10, function()
		if piToast.Visible then piToast.Visible = false end
	end)
end)

-- ── Testing panel toggle ──────────────────────────────────────────────────────
local testPanel = testUI:FindFirstChild("Panel")
w(testUI, "ToggleBtn").Activated:Connect(function()
	if testPanel then testPanel.Visible = not testPanel.Visible end
end)

-- ── Appearance Bar (Social Plaza) ─────────────────────────────────────────────
w(appBar, "WardrobeBtn").Activated:Connect(function() wdBd.Visible = true end)
w(appBar, "EmoteHint").Activated:Connect(function()   emBd.Visible = not emBd.Visible end)

-- ── Tab bars ──────────────────────────────────────────────────────────────────
local tabBase = Color3.fromRGB(28, 28, 42)
UIUtils.wireTabBar(w(setPn, "TabBar"), Color3.fromRGB(50,  80, 160), tabBase)
UIUtils.wireTabBar(w(gsPn,  "TabBar"), Color3.fromRGB(60,  80, 120), tabBase)
UIUtils.wireTabBar(w(lbPn,  "TabBar"), Color3.fromRGB(60,  80, 120), Color3.fromRGB(30, 30, 42))
UIUtils.wireTabBar(w(wdPn,  "TabBar"), Color3.fromRGB(60,  60,  90), tabBase)
UIUtils.wireTabBar(w(spPn,  "TabBar"), Color3.fromRGB(35,  35,  52), Color3.fromRGB(22, 22, 32))

-- Achievements: category sidebar
local achSidebar = achPn:WaitForChild("CategorySidebar")
for _, b in ipairs(achSidebar:GetChildren()) do
	if b:IsA("TextButton") then
		b.Activated:Connect(function()
			for _, x in ipairs(achSidebar:GetChildren()) do
				if x:IsA("TextButton") then
					x.BackgroundColor3 = tabBase
					x.TextColor3       = Color3.fromRGB(130, 130, 150)
				end
			end
			b.BackgroundColor3 = Color3.fromRGB(50, 80, 160)
			b.TextColor3       = Color3.fromRGB(220, 220, 230)
		end)
	end
end

-- ── Class Menu: switch buttons ────────────────────────────────────────────────
-- §EV10 fix: server registers "RequestClassSwitch" (ClassManager)
-- with signature (player, className). The legacy "RequestClassChange" name
-- + table payload silently no-op'd.
for _, col in ipairs(w(cmPn, "Columns"):GetChildren()) do
	if not col:IsA("Frame") then continue end
	for _, slot in ipairs(col:GetChildren()) do
		if not slot:IsA("Frame") then continue end
		local btn = slot:FindFirstChild("SwitchBtn")
		local lbl = slot:FindFirstChild("ClassName")
		if btn and lbl then
			btn.Activated:Connect(function()
				nm.FireServer("RequestClassSwitch", lbl.Text)
				cmBd.Visible = false
			end)
		end
	end
end

-- ── Stats Menu: allocate + respec ─────────────────────────────────────────────
-- §EV11 fix: server signature is AllocateStat(player, statName, points)
-- where statName is a STRING and points is a NUMBER (SharedEventHandlers
-- AllocateStat handler). Was being fired with a single table payload, which
-- its type check silently rejected.
for _, row in ipairs(w(smPn, "PrimaryStats"):GetChildren()) do
	if not row:IsA("Frame") then continue end
	local addBtn   = row:FindFirstChild("AddBtn")
	local countLbl = row:FindFirstChild("AllocatedCount")
	local nameLbl  = row:FindFirstChild("StatName")
	if addBtn and countLbl then
		addBtn.Activated:Connect(function()
			countLbl.Text = tostring((tonumber(countLbl.Text) or 0) + 1)
			local statName = (nameLbl and nameLbl.Text) or row.Name
			nm.FireServer("AllocateStat", statName, 1)
		end)
	end
end

local respecBtn = smPn:FindFirstChild("RespecBtn")
if respecBtn then
	respecBtn.Activated:Connect(function()
		nm.FireServer("RespecStats")
	end)
end

-- ── Inventory: equip buttons ──────────────────────────────────────────────────
local equippedBar = invPn:WaitForChild("EquippedBar")
for _, item in ipairs(w(invPn, "ListFrame"):GetChildren()) do
	if item:IsA("Frame") then
		local btn = item:FindFirstChild("ActionBtn")
		local lbl = item:FindFirstChild("ItemName")
		if btn and lbl then
			btn.Activated:Connect(function()
				equippedBar.Text = "Equipped:  " .. lbl.Text
				nm.FireServer("EquipItem", { itemId = item.Name })
			end)
		end
	end
end

-- ── Main Menu: play + difficulty buttons ─────────────────────────────────────
for _, wrap in ipairs(w(mmBd, "CardContainer"):GetChildren()) do
	if not wrap:IsA("Frame") then continue end
	local card = wrap:FindFirstChild("Card")
	if not card then continue end

	local diffRow = card:FindFirstChild("DifficultyRow")
	if diffRow then
		for _, dBtn in ipairs(diffRow:GetChildren()) do
			if dBtn:IsA("TextButton") then
				dBtn.Activated:Connect(function()
					for _, x in ipairs(diffRow:GetChildren()) do
						if x:IsA("TextButton") then
							x.BackgroundColor3 = Color3.fromRGB(20, 20, 28)
							x.TextColor3       = Color3.fromRGB(100, 100, 120)
						end
					end
					dBtn.BackgroundColor3 = Color3.fromRGB(50, 160, 70)
					dBtn.TextColor3       = Color3.fromRGB(255, 255, 255)
				end)
			end
		end
	end

	local playBtn = card:FindFirstChild("PlayBtn")
	local modeLbl = card:FindFirstChild("ModeName")
	if playBtn and modeLbl then
		playBtn.Activated:Connect(function()
			mmBd.Visible   = false
			mmkBar.Visible = true
			local sl = mmkBar:FindFirstChild("StatusLabel")
			if sl then sl.Text = "Queued for " .. modeLbl.Text .. "…" end
			-- §EV9 follow-up: route through MatchmakingRequest bus.
			-- modeLbl.Text is the human display name; the server expects
			-- the mode id ("Defense", "HordeMode") so we look it up via
			-- a small display→id table mirroring GameModeConfig.
			local MODE_LABEL_TO_ID = {
				["Defense"]          = "Defense",
				["Defense Mission"]  = "Defense",
				["Horde Mode"]       = "HordeMode",
				["HordeMode"]        = "HordeMode",
				["Central Boss"]     = "CentralBoss",
				["CentralBoss"]      = "CentralBoss",
			}
			local modeId = MODE_LABEL_TO_ID[modeLbl.Text] or modeLbl.Text
			nm.FireServer("MatchmakingRequest", { action = "Queue", mode = modeId })
		end)
	end
end

-- Matchmaking state updates
-- §EV2 fix: there is no "MatchFound" event on the server. MatchmakingManager
-- emits "MatchmakingUpdate" with status ∈ { Queued, Countdown, Launching,
-- Cancelled, Error }. Hide the bar when status is terminal.
nm.OnServerEvent("MatchmakingUpdate", function(data)
	local sl = mmkBar:FindFirstChild("StatusLabel")
	if sl then sl.Text = data.status or "Searching…" end
	if data.status == "Launching"
		or data.status == "Cancelled"
		or data.status == "Error" then
		mmkBar.Visible = false
	end
end)

-- ── NPC Dialog: choices + open event ─────────────────────────────────────────
for _, b in ipairs(w(npcPn, "Choices"):GetChildren()) do
	if b:IsA("TextButton") then
		b.Activated:Connect(function()
			nm.FireServer("NPCDialogChoice", { choice = b.Name })
			npcBd.Visible = false
		end)
	end
end

-- §EV3 fix: server fires a single "NPCDialogue" event (NPCManager and its
-- Shop/Quest/Lore handlers). Different stages carry a `type` field — "Dialogue",
-- "ShopSuccess", "ShopError", "QuestAccepted", "QuestCompleted",
-- "QuestError", "TeleportComplete". Open the panel for actual dialogue
-- nodes; everything else is a transient toast that the panel doesn't show.
nm.OnServerEvent("NPCDialogue", function(data)
	if not data then return end
	if data.type == "Dialogue" or data.dialogue then
		local bodyLbl = npcPn:FindFirstChild("BodyText")
		if bodyLbl then
			-- A dialogue payload is the full node graph; show the first node
			local firstNode = data.dialogue and data.dialogue[1]
			bodyLbl.Text = (firstNode and firstNode.text) or data.text or ""
		end
		npcBd.Visible = true
	else
		-- Transient outcomes: hide the dialog backdrop if it's still open.
		npcBd.Visible = false
	end
end)

-- ── NPC Shop: buy buttons ─────────────────────────────────────────────────────
for _, c in ipairs(w(shopPn, "ItemGrid"):GetChildren()) do
	if c:IsA("Frame") then
		local btn = c:FindFirstChild("BuyBtn")
		if btn then
			btn.Activated:Connect(function()
				nm.FireServer("BuyShopItem", { itemId = c.Name })
			end)
		end
	end
end

-- ── Global Shop: buy buttons ──────────────────────────────────────────────────
for _, c in ipairs(w(gsPn, "ItemGrid"):GetChildren()) do
	if c:IsA("Frame") then
		local btn = c:FindFirstChild("BuyBtn")
		if btn then
			btn.Activated:Connect(function()
				nm.FireServer("BuyGlobalShopItem", { itemId = c.Name })
			end)
		end
	end
end

-- ── Vote panel ────────────────────────────────────────────────────────────────
for _, c in ipairs(voteP:GetChildren()) do
	if c:IsA("Frame") then
		local btn = c:FindFirstChild("VoteBtn")
		if btn then
			btn.Activated:Connect(function()
				nm.FireServer("CastVote", { option = c.Name })
				voteBd.Visible = false
			end)
		end
	end
end

-- §EV4 fix: server emits "VoteStart" / "VoteResult" (VoteManager);
-- the legacy "VoteStarted" / "VoteEnded" names were stalling lobby boot for
-- 3 s each waiting for events that don't exist. Note: in combat places the
-- React VoteUI manages its own panel visibility — these handlers only
-- toggle the BACKDROP frame so the inner React component sees the right
-- parent state.
nm.OnServerEvent("VoteStart",  function(_) voteBd.Visible = true  end)
nm.OnServerEvent("VoteResult", function(_)
	-- Vote panel auto-dismisses 3 s after VoteResult; mirror that here.
	task.delay(3.5, function() voteBd.Visible = false end)
end)

-- ── Character Creation ────────────────────────────────────────────────────────
local cfBtn = ccPn:FindFirstChild("ConfirmBtn")
if cfBtn then
	cfBtn.Activated:Connect(function()
		nm.FireServer("ConfirmCharacterCreation")
		ccBd.Visible = false
	end)
end

local skinGrid = ccPn:FindFirstChild("SkinGrid")
if skinGrid then
	for _, b in ipairs(skinGrid:GetChildren()) do
		if b:IsA("TextButton") then
			b.Activated:Connect(function()
				for _, x in ipairs(skinGrid:GetChildren()) do
					if x:IsA("TextButton") then x.BorderSizePixel = 0 end
				end
				b.BorderSizePixel = 3
			end)
		end
	end
end

-- ── TalentTree: close button (header lives inside ttBd, not in a sub-panel) ──
local ttHeader = ttBd:FindFirstChild("Header")
if ttHeader then
	local ttClose = ttHeader:FindFirstChild("CloseBtn")
	if ttClose then
		ttClose.Activated:Connect(function() ttBd.Visible = false end)
	end
end

print("[Overlays] Wired")
