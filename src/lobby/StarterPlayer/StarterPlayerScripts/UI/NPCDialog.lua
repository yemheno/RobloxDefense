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
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local React             = require(ReplicatedStorage.Packages.React)

local PlayerScripts  = Players.LocalPlayer:WaitForChild("PlayerScripts")
local SharedModules  = PlayerScripts:WaitForChild("Modules")
local NetworkManager = require(SharedModules:WaitForChild("NetworkManager"))
local useNpcDistanceClose = require(PlayerScripts:WaitForChild("UI"):WaitForChild("Common"):WaitForChild("useNpcDistanceClose"))  -- §DISC/D8
local useRequest = require(PlayerScripts:WaitForChild("UI"):WaitForChild("Common"):WaitForChild("useRequest"))  -- §AGX/UI-P4

-- ── Palette ───────────────────────────────────────────────
local C = {
	overlay    = Color3.fromRGB(  0,   0,   0),
	panel      = Color3.fromRGB( 22,  22,  30),
	accent     = Color3.fromRGB(105, 190, 255),
	green      = Color3.fromRGB( 50, 170,  80),
	red        = Color3.fromRGB(170,  50,  50),
	yellow     = Color3.fromRGB(255, 210,  60),
	text       = Color3.fromRGB(220, 220, 230),
	text_dim   = Color3.fromRGB(140, 140, 160),
	white      = Color3.fromRGB(255, 255, 255),
	choice_bg  = Color3.fromRGB( 38,  38,  54),
}

-- ── Choice Button ─────────────────────────────────────────
local function ChoiceButton(props)
	return React.createElement("TextButton", {
		Size             = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.choice_bg,
		BorderSizePixel  = 0,
		Text             = props.text,
		TextColor3       = C.accent,
		Font             = Enum.Font.Gotham,
		TextScaled       = true,
		LayoutOrder      = props.order,
		[React.Event.Activated] = props.onClick,
	}, {
		corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.2, 0) }),
		pad = React.createElement("UIPadding", {
			PaddingLeft = UDim.new(0.04, 0), PaddingRight = UDim.new(0.04, 0),
		}),
	})
end

-- ── Quest Reward Line ─────────────────────────────────────
local function RewardLine(props)
	return React.createElement("TextLabel", {
		Size = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text = "• " .. props.text,
		TextColor3 = C.yellow,
		Font = Enum.Font.Gotham,
		TextScaled = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = props.order,
	})
end

-- ── Main Component ────────────────────────────────────────
local function NPCDialog(props)
	local onClose = props.onClose or function() end

	-- Dialog state
	local dialogData, setDialogData = React.useState(nil)     -- { npcId, npcName, dialogueTree, type }
	local currentNode, setCurrentNode = React.useState(nil)    -- current node key in tree
	local questData, setQuestData = React.useState(nil)        -- quest offer data
	local teleportData, setTeleportData = React.useState(nil)  -- teleport destinations
	-- §AGX/UI-P4: the quest action's inline result is useRequest (was a
	-- statusMsg + showStatus 4 s timer + pendingQuestRef, fed from the
	-- NPCDialogue listener below). Same behaviour: "Working…" while
	-- pending, the QuestAccepted/QuestCompleted/QuestError message for
	-- 4 s, and on success the open quest list is patched for the questId
	-- that was sent. New: no reply within 4 s shows an error.
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
			-- Those used to be opened as an empty lore tree and closed the panel.
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
			-- choices use `label` and numeric `next`, 0 = end), so "start" was
			-- always nil and every lore chat closed itself. Accept both shapes.
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

	-- §AGX/UX-03: a dialogue that points at a missing node (end of tree)
	-- closes from an effect. It used to call closeDialog() during render,
	-- which set state mid-render and fired NPCResponse from render.
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
	------------------------------------------------------------
	local innerContent

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

		local choices = node.choices or {}
		local choiceElements = {}
		choiceElements["layout"] = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder     = Enum.SortOrder.LayoutOrder,
			Padding       = UDim.new(0.02, 0),
		})

		for i, choice in ipairs(choices) do
			choiceElements["c" .. i] = React.createElement("Frame", {
				Size = UDim2.fromScale(1, 0.2),
				BackgroundTransparency = 1,
				LayoutOrder = i,
			}, {
				btn = React.createElement(ChoiceButton, {
					text  = choice.text or choice.label or "...",  -- §AGX/UX-03: registry uses `label`
					order = i,
					onClick = function()
						if choice.next and choice.next ~= 0 then  -- §AGX/UX-03: 0 = end
							setCurrentNode(choice.next)
						else
							closeDialog()
						end
					end,
				}),
			})
		end

		-- If no choices, show a "Continue" / "Close" button
		if #choices == 0 then
			choiceElements["close"] = React.createElement("Frame", {
				Size = UDim2.fromScale(1, 0.2),
				BackgroundTransparency = 1,
				LayoutOrder = 1,
			}, {
				btn = React.createElement(ChoiceButton, {
					text    = "Close",
					order   = 1,
					onClick = closeDialog,
				}),
			})
		end

		innerContent = React.createElement(React.Fragment, nil, {
			dialogText = React.createElement("TextLabel", {
				Size = UDim2.fromScale(1, 0.55),
				BackgroundTransparency = 1,
				Text = node.text or "",
				TextColor3 = C.text,
				Font = Enum.Font.Gotham,
				TextSize = 18,
				TextWrapped = true,
				TextXAlignment = Enum.TextXAlignment.Left,
				TextYAlignment = Enum.TextYAlignment.Top,
				LayoutOrder = 1,
			}),

			choiceFrame = React.createElement("Frame", {
				Size = UDim2.fromScale(1, 0.4),
				Position = UDim2.fromScale(0, 0.58),
				BackgroundTransparency = 1,
				LayoutOrder = 2,
			}, choiceElements),
		})

	-- ═══════════════════════════════════════════════════════
	-- QUEST OFFER
	-- ═══════════════════════════════════════════════════════
	elseif questData then
		local quests = questData.quests or {}
		local questElements = {}
		questElements["layout"] = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder     = Enum.SortOrder.LayoutOrder,
			Padding       = UDim.new(0.02, 0),
		})

		for i, quest in ipairs(quests) do
			local statusColor = C.text_dim
			local actionText  = nil
			local actionColor = C.green

			if quest.status == "Available" then
				statusColor = C.green
				actionText  = "Accept"
			elseif quest.status == "InProgress" then
				statusColor = C.yellow
				actionText  = nil -- no action, just info
			elseif quest.status == "ReadyToTurnIn" then
				statusColor = C.accent
				actionText  = "Turn In"
			elseif quest.status == "Completed" then
				statusColor = C.text_dim
			elseif quest.status == "Locked" then
				statusColor = C.red
			end

			-- Build objective text
			local objText = ""
			if quest.objectives then
				for _, obj in ipairs(quest.objectives) do
					local progress = obj.current or 0
					local objLabel = obj.description or obj.label or obj.type or "?"
					local objTarget = obj.count or obj.target or 0
					objText = objText .. "  ▸ " .. objLabel .. " (" .. progress .. "/" .. objTarget .. ")\n"
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

			questElements["q" .. i] = React.createElement("Frame", {
				Size = UDim2.fromScale(1, 0.3),
				BackgroundColor3 = C.choice_bg,
				BorderSizePixel = 0,
				LayoutOrder = i,
			}, {
				corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.05, 0) }),
				pad = React.createElement("UIPadding", {
					PaddingLeft = UDim.new(0.03, 0), PaddingRight = UDim.new(0.03, 0),
					PaddingTop = UDim.new(0.03, 0), PaddingBottom = UDim.new(0.03, 0),
				}),

				questName = React.createElement("TextLabel", {
					Size = UDim2.fromScale(0.65, 0.25),
					BackgroundTransparency = 1,
					Text = quest.name or quest.title or quest.questId or quest.id or "?",
					TextColor3 = statusColor,
					Font = Enum.Font.GothamBold,
					TextScaled = true,
					TextXAlignment = Enum.TextXAlignment.Left,
				}),

				statusLabel = React.createElement("TextLabel", {
					AnchorPoint = Vector2.new(1, 0),
					Position = UDim2.fromScale(1, 0),
					Size = UDim2.fromScale(0.3, 0.2),
					BackgroundTransparency = 1,
					Text = quest.status or "",
					TextColor3 = statusColor,
					Font = Enum.Font.Gotham,
					TextScaled = true,
					TextXAlignment = Enum.TextXAlignment.Right,
				}),

				descLabel = React.createElement("TextLabel", {
					Position = UDim2.fromScale(0, 0.28),
					Size = UDim2.fromScale(1, 0.3),
					BackgroundTransparency = 1,
					Text = (quest.description or "") .. "\n" .. objText,
					TextColor3 = C.text_dim,
					Font = Enum.Font.Gotham,
					TextSize = 14,
					TextWrapped = true,
					TextXAlignment = Enum.TextXAlignment.Left,
					TextYAlignment = Enum.TextYAlignment.Top,
				}),

				rewardsLabel = rewardText ~= "" and React.createElement("TextLabel", {
					Position = UDim2.fromScale(0, 0.62),
					Size = UDim2.fromScale(1, 0.15),
					BackgroundTransparency = 1,
					Text = "Rewards: " .. rewardText,
					TextColor3 = C.yellow,
					Font = Enum.Font.Gotham,
					TextScaled = true,
					TextXAlignment = Enum.TextXAlignment.Left,
				}) or nil,

				actionBtn = actionText and React.createElement("TextButton", {
					AnchorPoint = Vector2.new(1, 1),
					Position = UDim2.fromScale(1, 1),
					Size = UDim2.fromScale(0.28, 0.22),
					BackgroundColor3 = actionColor,
					BorderSizePixel = 0,
					Text = actionText,
					TextColor3 = C.white,
					Font = Enum.Font.GothamBold,
					TextScaled = true,
					[React.Event.Activated] = function()
						local act = quest.status == "Available" and "AcceptQuest" or "TurnInQuest"
						-- §AGX/UX-03: stay open so the QuestAccepted/QuestError
						-- result can show inline (it was closed before it arrived).
						-- §AGX/UI-P4: questReq fires NPCResponse and owns the
						-- pending/ok/err state; onResult patches the list.
						questReq.send({
							npcId = questData.npcId,
							action = act,
							questId = quest.questId or quest.id,
						})
					end,
				}, {
					corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.25, 0) }),
				}) or nil,
			})
		end

		innerContent = React.createElement("ScrollingFrame", {
			Size = UDim2.fromScale(1, 0.9),
			Position = UDim2.fromScale(0, 0.05),
			BackgroundTransparency = 1,
			ScrollBarThickness = 4,
			CanvasSize = UDim2.fromScale(0, 0),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			BorderSizePixel = 0,
		}, questElements)

	-- ═══════════════════════════════════════════════════════
	-- TELEPORT DESTINATIONS
	-- ═══════════════════════════════════════════════════════
	elseif teleportData then
		local dests = teleportData.destinations or {}
		local destElements = {}
		destElements["layout"] = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Vertical,
			SortOrder     = Enum.SortOrder.LayoutOrder,
			Padding       = UDim.new(0.02, 0),
		})

		for i, dest in ipairs(dests) do
			destElements["d" .. i] = React.createElement("Frame", {
				Size = UDim2.fromScale(1, 0.18),
				BackgroundTransparency = 1,
				LayoutOrder = i,
			}, {
				btn = React.createElement("TextButton", {
					Size = UDim2.fromScale(1, 1),
					BackgroundColor3 = C.choice_bg,
					BorderSizePixel = 0,
					Text = dest.name .. (dest.description and (" — " .. dest.description) or ""),
					TextColor3 = C.accent,
					Font = Enum.Font.Gotham,
					TextScaled = true,
					[React.Event.Activated] = function()
						NetworkManager.FireServer("NPCResponse", {
							npcId = teleportData.npcId,
							action = "Teleport",
							destinationId = dest.id,
						})
						closeDialog()
					end,
				}, {
					corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.15, 0) }),
				}),
			})
		end

		if #dests == 0 then
			destElements["empty"] = React.createElement("TextLabel", {
				Size = UDim2.fromScale(1, 0.25),
				BackgroundTransparency = 1,
				Text = "No destinations available yet.",
				TextColor3 = C.text_dim,
				Font = Enum.Font.Gotham,
				TextScaled = true,
				LayoutOrder = 1,
			})
		end

		innerContent = React.createElement("Frame", {
			Size = UDim2.fromScale(1, 0.85),
			Position = UDim2.fromScale(0, 0.1),
			BackgroundTransparency = 1,
		}, destElements)
	end

	------------------------------------------------------------
	-- Determine speaker name
	------------------------------------------------------------
	local speakerName = ""
	if dialogData then speakerName = dialogData.npcName or "" end
	if questData  then speakerName = questData.npcName or "" end
	if teleportData then speakerName = teleportData.npcName or "" end

	------------------------------------------------------------
	-- Render wrapper
	------------------------------------------------------------
	return React.createElement("Frame", {
		Name = "NPCDialog",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.overlay,
		BackgroundTransparency = 0.5,
		BorderSizePixel = 0,
		ZIndex = 20,
	}, {
		panel = React.createElement("Frame", {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(0.5, 0.92),
			Size = UDim2.fromScale(0.45, 0.35),
			BackgroundColor3 = C.panel,
			BorderSizePixel = 0,
		}, {
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.02, 0) }),
			pad = React.createElement("UIPadding", {
				PaddingLeft = UDim.new(0.03, 0), PaddingRight = UDim.new(0.03, 0),
				PaddingTop = UDim.new(0.04, 0), PaddingBottom = UDim.new(0.04, 0),
			}),

			-- NPC Name header
			nameLabel = React.createElement("TextLabel", {
				Size = UDim2.fromScale(0.8, 0.12),
				BackgroundTransparency = 1,
				Text = speakerName,
				TextColor3 = C.accent,
				Font = Enum.Font.GothamBold,
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),

			-- Close X
			closeBtn = React.createElement("TextButton", {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.fromScale(1, 0),
				Size = UDim2.fromScale(0.08, 0.1),
				BackgroundTransparency = 1,
				Text = "✕",
				TextColor3 = C.text_dim,
				Font = Enum.Font.GothamBold,
				TextScaled = true,
				[React.Event.Activated] = closeDialog,
			}),

			-- Content area
			content = React.createElement("Frame", {
				Position = UDim2.fromScale(0, 0.15),
				Size = UDim2.fromScale(1, 0.85),
				BackgroundTransparency = 1,
			}, {
				inner = innerContent,
			}),

			-- §AGX/UX-03: quest action result, header row between name and ✕
			statusLabel = statusMsg and React.createElement("TextLabel", {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.fromScale(0.9, 0),
				Size = UDim2.fromScale(0.5, 0.1),
				BackgroundTransparency = 1,
				Text = statusMsg.text,
				TextColor3 = statusMsg.ok and C.green or C.red,
				Font = Enum.Font.GothamBold,
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Right,
			}) or nil,
		}),
	})
end

return NPCDialog
