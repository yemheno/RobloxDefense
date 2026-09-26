-- UI/NPCDialog.lua
--[[
    NPC Dialogue / Quest overlay.
    
    Handles three server events:
      • "NPCDialogue"  → display branching dialogue tree
      • "NPCQuestOffer" → display quest accept/decline panel
      • "NPCTeleportOffer" → display destination list
    
    All client navigation is performed locally through the
    dialogue tree. When the player closes, fires:
      "NPCResponse" → { npcId, action = "Close" }

    §AGX/UI-P6: AppWindow "dialog" chrome, Card choices / quests /
    destinations, Button actions, Text, design px under UIScaleRoot.Local.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local React             = require(ReplicatedStorage.Packages.React)

local PlayerScripts  = Players.LocalPlayer:WaitForChild("PlayerScripts")
local SharedModules  = PlayerScripts:WaitForChild("Modules")
local NetworkManager = require(SharedModules:WaitForChild("NetworkManager"))
local useNpcDistanceClose = require(PlayerScripts:WaitForChild("UI"):WaitForChild("Common"):WaitForChild("useNpcDistanceClose"))  -- §DISC/D8
local useRequest = require(PlayerScripts:WaitForChild("UI"):WaitForChild("Common"):WaitForChild("useRequest"))  -- §AGX/UI-P4
local PlayerScripts_UI = PlayerScripts:WaitForChild("UI")
-- §AGX/UI-P3: register with the shell's PanelStack (A10, shell-spec §3.2.3).
-- Nil-safe: without UI/Shell (or outside a PanelHost) useExternal is a no-op.
local useExternal = function(_id, _isOpen, _closeFn) end
do
	local shell = PlayerScripts_UI:FindFirstChild("Shell")
	local mod = shell and shell:FindFirstChild("PanelStack")
	if mod then
		local ok, PanelStack = pcall(require, mod)
		if ok and type(PanelStack) == "table" and PanelStack.useExternal then
			useExternal = PanelStack.useExternal
		end
	end
end

-- §AGX/UI-P6: shared components.
local Common      = PlayerScripts_UI:WaitForChild("Common")
local Theme       = require(Common:WaitForChild("Theme"))
local AppWindow   = require(Common:WaitForChild("AppWindow"))
local UIScaleRoot = require(Common:WaitForChild("UIScaleRoot"))
local Text        = require(Common:WaitForChild("Text"))
local Button      = require(Common:WaitForChild("Button"))
local Card        = require(Common:WaitForChild("Card"))

local e  = React.createElement
local R  = Theme.Roles
local SP = Theme.Space

-- Quest status -> Card badge / state.
local QUEST_STATUS = {
	Available     = { badge = "Available" },
	InProgress    = { badge = "In progress" },
	ReadyToTurnIn = { badge = "Ready" },
	Completed     = { badge = "Completed" },
	Locked        = { badge = "Locked", locked = true },
}

-- ── Main Component ────────────────────────────────────────
local function NPCDialog(props)
	local onClose = props.onClose or function() end

	-- Dialog state
	local dialogData, setDialogData = React.useState(nil)     -- { npcId, npcName, dialogueTree, type }
	local currentNode, setCurrentNode = React.useState(nil)    -- current node key in tree
	local questData, setQuestData = React.useState(nil)        -- quest offer data
	local teleportData, setTeleportData = React.useState(nil)  -- teleport destinations
	-- §AGX/UI-P4: the quest action's inline result is useRequest: "Working…"
	-- while pending, the QuestAccepted/QuestCompleted/QuestError message for
	-- 4 s, and on success the open quest list is patched for the questId
	-- that was sent. No reply within 4 s shows an error.
	local questReq = useRequest("NPCResponse", {
		reply       = "NPCDialogue",
		pendingText = "Working…",
		holdFor     = 4,
		timeout     = 4,
		match       = function(data)
			if type(data) ~= "table" then return nil end
			local kind = data.type
			if kind ~= "QuestAccepted" and kind ~= "QuestCompleted" and kind ~= "QuestError" then
				return nil
			end
			local ok = kind ~= "QuestError"
			return ok, data.message or (ok and "Done." or "Failed.")
		end,
		onResult    = function(ok, data, payload)
			-- Patch the open quest list so its button reflects the result.
			local qid = type(payload) == "table" and payload.questId or nil
			if not (ok and qid and type(data) == "table") then return end
			local kind = data.type
			setQuestData(function(prev)
				if not prev or not prev.quests then return prev end
				local nextQuests = {}
				for i, q in ipairs(prev.quests) do
					if (q.questId or q.id) == qid then
						local copy = table.clone(q)
						copy.status = (kind == "QuestAccepted") and "InProgress" or "Completed"
						nextQuests[i] = copy
					else
						nextQuests[i] = q
					end
				end
				local nextData = table.clone(prev)
				nextData.quests = nextQuests
				return nextData
			end)
		end,
	})
	local resetQuestStatus = questReq.reset  -- stable (useCallback), safe in the {} effect
	local statusMsg = (questReq.state ~= "idle") and {
		text = questReq.message or "",
		ok   = questReq.state ~= "err",
	} or nil

	-- ── Event listeners ──────────────────────────────────
	React.useEffect(function()
		local conns = {}

		conns[1] = NetworkManager.OnServerEvent("NPCDialogue", function(data)
			-- data = { npcId, npcName, dialogue = { [key] = { text, choices = { { text, next } } } } }
			-- §AGX/UX-03: the server reuses this event for action RESULTS
			-- (ShopHandler/QuestHandler/TeleportHandler send
			-- { type = "ShopSuccess"|"ShopError"|"Quest*"|"TeleportComplete", message }).
			-- Only "Dialogue" (LoreHandler) or an untyped payload is a tree.
			if type(data) ~= "table" then return end
			local kind = data.type
			if kind ~= nil and kind ~= "Dialogue" and kind ~= "Lore" then
				-- §AGX/UI-P4: Quest* results are consumed by questReq
				-- (useRequest), Shop* by ShopUI's cards; TeleportComplete
				-- needs no UI. None of them is a dialogue tree.
				return
			end
			resetQuestStatus()  -- §AGX/UI-P4
			setDialogData({
				npcId    = data.npcId,
				npcName  = data.npcName,
				tree     = data.dialogue,
				type     = "Lore",
			})
			-- §AGX/UX-03: LoreHandler sends an ARRAY of nodes ({ {text, choices} },
			-- choices use `label` and numeric `next`, 0 = end), with no "start" key.
			-- Accept both shapes.
			local tree = data.dialogue
			setCurrentNode((type(tree) == "table" and tree.start ~= nil) and "start" or 1)
			setQuestData(nil)
			setTeleportData(nil)
		end)

		conns[2] = NetworkManager.OnServerEvent("NPCQuestOffer", function(data)
			-- data = { npcId, npcName, quests = { { id, name, description, objectives, rewards, status } } }
			setQuestData(data)
			setDialogData(nil)
			setTeleportData(nil)
			resetQuestStatus()  -- §AGX/UX-03, §AGX/UI-P4
		end)

		conns[3] = NetworkManager.OnServerEvent("NPCTeleportOffer", function(data)
			-- data = { npcId, npcName, destinations = { { id, name, description } } }
			setTeleportData(data)
			setDialogData(nil)
			setQuestData(nil)
			resetQuestStatus()  -- §AGX/UX-03, §AGX/UI-P4
		end)

		return function()
			for _, c in conns do
				if c then c:Disconnect() end
			end
			-- §AGX/UI-P4: useRequest cancels its own timers on unmount.
		end
	end, {})

	------------------------------------------------------------
	-- Close helper
	------------------------------------------------------------
	local function closeDialog()
		local npcId
		if dialogData then npcId = dialogData.npcId end
		if questData  then npcId = questData.npcId end
		if teleportData then npcId = teleportData.npcId end
		if npcId then
			NetworkManager.FireServer("NPCResponse", { npcId = npcId, action = "Close" })
		end
		setDialogData(nil)
		setQuestData(nil)
		setTeleportData(nil)
		setCurrentNode(nil)
		questReq.reset()  -- §AGX/UX-03, §AGX/UI-P4 (a late result is then ignored)
		onClose()
	end

	-- §DISC/D8: auto-close when the player walks away from the NPC.
	local activeNpcId = (dialogData and dialogData.npcId)
		or (questData and questData.npcId)
		or (teleportData and teleportData.npcId)
	useNpcDistanceClose(activeNpcId, activeNpcId ~= nil, closeDialog)

	-- §AGX/UI-P3: A10. Opening replaces Stats / another NPC panel (UX-05);
	-- a stack-initiated close (replace / back / blocked) runs closeDialog,
	-- which still fires NPCResponse Close. closeDialog's own onClose() ->
	-- close(id, "self") is then a no-op (the stack already removed it).
	useExternal("npcDialog", activeNpcId ~= nil, closeDialog)

	-- §AGX/UX-03: a dialogue that points at a missing node (end of tree)
	-- closes from an effect, never during render (that would set state and
	-- fire NPCResponse mid-render).
	local missingNode = dialogData ~= nil
		and (dialogData.tree == nil or dialogData.tree[currentNode] == nil)
	React.useEffect(function()
		if missingNode then
			closeDialog()
		end
	end, { missingNode })

	------------------------------------------------------------
	-- Nothing to show
	------------------------------------------------------------
	if not dialogData and not questData and not teleportData then
		return nil
	end

	------------------------------------------------------------
	-- Build inner content depending on type
	-- §AGX/UI-P6: one vertical list (design px) inside a ScrollingFrame, so
	-- every variant scrolls on the phone's bottom sheet. Choices, quests and
	-- destinations are Cards (>= 44 px taps); actions are Buttons.
	------------------------------------------------------------
	local list = {}

	-- ═══════════════════════════════════════════════════════
	-- LORE / DIALOGUE TREE
	-- ═══════════════════════════════════════════════════════
	if dialogData then
		local tree = dialogData.tree or {}
		local node = tree[currentNode]
		if not node then
			-- fallback end: the effect above closes it (§AGX/UX-03)
			return nil
		end

		list.dialogText = e(Text, {
			style       = "body",
			text        = node.text or "",
			wrap        = true,
			valign      = "top",
			size        = UDim2.fromScale(1, 0),
			layoutOrder = 1,
		})

		local choices = node.choices or {}
		for i, choice in ipairs(choices) do
			list["c" .. i] = e(Card, {
				title       = choice.text or choice.label or "...",  -- §AGX/UX-03: registry uses `label`
				layoutOrder = 1 + i,
				onActivated = function()
					if choice.next and choice.next ~= 0 then  -- §AGX/UX-03: 0 = end
						setCurrentNode(choice.next)
					else
						closeDialog()
					end
				end,
			})
		end

		-- If no choices, show a "Close" button
		if #choices == 0 then
			list.close = e(Button, {
				variant     = "secondary",
				size        = "sm",
				label       = "Close",
				layoutOrder = 2,
				onActivated = function() closeDialog() end,
			})
		end

	-- ═══════════════════════════════════════════════════════
	-- QUEST OFFER
	-- ═══════════════════════════════════════════════════════
	elseif questData then
		local quests = questData.quests or {}

		for i, quest in ipairs(quests) do
			local actionText = nil
			if quest.status == "Available" then
				actionText = "Accept"
			elseif quest.status == "ReadyToTurnIn" then
				actionText = "Turn In"
			end
			local st = QUEST_STATUS[quest.status] or {}

			-- Build objective text
			local objText = ""
			if quest.objectives then
				for _, obj in ipairs(quest.objectives) do
					local progress = obj.current or 0
					local objLabel = obj.description or obj.label or obj.type or "?"
					local objTarget = obj.count or obj.target or 0
					objText = objText .. "\n  ▸ " .. objLabel .. " (" .. progress .. "/" .. objTarget .. ")"
				end
			end

			-- Build reward text
			local rewardText = ""
			if quest.rewards then
				for _, entry in ipairs(quest.rewards) do
					local rType   = entry.type or "?"
					local rAmount = entry.amount or entry.percent or entry.levels or "?"
					rewardText = rewardText .. "  ★ " .. rType .. ": " .. tostring(rAmount) .. "  "
				end
			end

			list["q" .. i] = e(Card, {
				title       = quest.name or quest.title or quest.questId or quest.id or "?",
				subtitle    = (quest.description or "") .. objText,
				badge       = st.badge or quest.status,
				locked      = st.locked,
				layoutOrder = i,
				footer      = (rewardText ~= "" or actionText) and e("Frame", {
					Size                   = UDim2.new(1, 0, 0, Theme.Metrics.button.sm),
					BackgroundTransparency = 1,
				}, {
					rewards = rewardText ~= "" and e(Text, {
						style = "caption",
						text  = "Rewards: " .. rewardText,
						color = "rarity.legendary",
						size  = UDim2.new(1, actionText and -(120 + SP.sm) or 0, 1, 0),
					}) or nil,
					action = actionText and e(Button, {
						variant     = "secondary",
						size        = "sm",
						width       = 120,
						label       = actionText,
						anchorPoint = Vector2.new(1, 0.5),
						position    = UDim2.fromScale(1, 0.5),
						onActivated = function()
							local act = quest.status == "Available" and "AcceptQuest" or "TurnInQuest"
							-- §AGX/UX-03, §AGX/UI-P4: stay open so the QuestAccepted/QuestError
							-- result can show inline; questReq fires NPCResponse and owns the
							-- pending/ok/err state; onResult patches the list.
							questReq.send({
								npcId = questData.npcId,
								action = act,
								questId = quest.questId or quest.id,
							})
						end,
					}) or nil,
				}) or nil,
			})
		end

	-- ═══════════════════════════════════════════════════════
	-- TELEPORT DESTINATIONS
	-- ═══════════════════════════════════════════════════════
	elseif teleportData then
		local dests = teleportData.destinations or {}

		for i, dest in ipairs(dests) do
			list["d" .. i] = e(Card, {
				title       = dest.name,
				subtitle    = dest.description,
				layoutOrder = i,
				onActivated = function()
					NetworkManager.FireServer("NPCResponse", {
						npcId = teleportData.npcId,
						action = "Teleport",
						destinationId = dest.id,
					})
					closeDialog()
				end,
			})
		end

		if #dests == 0 then
			list.empty = e(Text, {
				style       = "body",
				text        = "No destinations available yet.",
				color       = "text.secondary",
				align       = "center",
				layoutOrder = 1,
			})
		end
	end

	list.layout = e("UIListLayout", {
		FillDirection = Enum.FillDirection.Vertical,
		SortOrder     = Enum.SortOrder.LayoutOrder,
		Padding       = UDim.new(0, SP.sm),
	})
	list.padding = e("UIPadding", {
		PaddingLeft = UDim.new(0, SP.lg), PaddingRight = UDim.new(0, SP.lg),
		PaddingTop = UDim.new(0, SP.md), PaddingBottom = UDim.new(0, SP.lg),
	})

	------------------------------------------------------------
	-- Determine speaker name
	------------------------------------------------------------
	local speakerName = ""
	if dialogData then speakerName = dialogData.npcName or "" end
	if questData  then speakerName = questData.npcName or "" end
	if teleportData then speakerName = teleportData.npcName or "" end

	------------------------------------------------------------
	-- Render wrapper
	-- §AGX/UI-P6: AppWindow "dialog" (phone: bottom sheet; the shell's
	-- presentation wins). Its panel is Active (A10 / UX-14). ✕ = closeDialog.
	-- The quest result (§AGX/UX-03) sits in the header's right slot.
	------------------------------------------------------------
	local z = Theme.Z.windowOver
	return e(AppWindow, {
		variant = "dialog",
		title   = speakerName,
		onClose = function() closeDialog() end,
		size    = UDim2.fromScale(0.5, 0.5),
		minSize = Vector2.new(480, 320),
		zIndex  = z,
		headerContent = statusMsg and e(Text, {
			style = "label",
			text  = statusMsg.text,
			color = statusMsg.ok and "state.success" or "state.danger",
			align = "right",
			size  = UDim2.fromScale(1, 1),
		}) or nil,
	}, {
		scaled = e(UIScaleRoot.Local, { name = "NPCDialogBody", zIndex = z + 2 }, {
			content = e("ScrollingFrame", {
				Name                   = "Content",
				Size                   = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				BorderSizePixel        = 0,
				ScrollBarThickness     = Theme.Metrics.scrollBar,
				ScrollBarImageColor3   = R.text.secondary,
				CanvasSize             = UDim2.fromScale(0, 0),
				AutomaticCanvasSize    = Enum.AutomaticSize.Y,
				ScrollingDirection     = Enum.ScrollingDirection.Y,
				ZIndex                 = z + 2,
			}, list),
		}),
	})
end

return NPCDialog
