-- lobby/StarterPlayerScripts/UI/WeaponSmithUI.lua
--[[
    Forge overlay triggered by "NPCSmithOpen" server event.
    
    Displays weapon / armor info and an action button based on the
    smith sub-type: Refinement, TierUpgrade, or BonusReroll.
    
    Fires "NPCResponse" with the appropriate action string so the
    server-side WeaponSmithHandler can act.
    After each successful action, requests a Refresh to update displayed data.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local React             = require(ReplicatedStorage.Packages.React)

local SharedModules  = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Modules")
local useNpcDistanceClose = require(Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("UI"):WaitForChild("Common"):WaitForChild("useNpcDistanceClose"))  -- §AGX/X29
local NetworkManager = require(SharedModules:WaitForChild("NetworkManager"))

-- ── Palette ───────────────────────────────────────────────
local C = {
	overlay    = Color3.fromRGB(  0,   0,   0),
	panel      = Color3.fromRGB( 22,  22,  30),
	card       = Color3.fromRGB( 32,  32,  46),
	accent     = Color3.fromRGB(105, 190, 255),
	green      = Color3.fromRGB( 50, 170,  80),
	red        = Color3.fromRGB(200,  60,  60),
	yellow     = Color3.fromRGB(255, 210,  60),
	orange     = Color3.fromRGB(230, 150,  40),
	purple     = Color3.fromRGB(160, 100, 220),
	text       = Color3.fromRGB(220, 220, 230),
	text_dim   = Color3.fromRGB(140, 140, 160),
	white      = Color3.fromRGB(255, 255, 255),
}

-- ── Helpers ───────────────────────────────────────────────

local function StatLine(props)
	return React.createElement("TextLabel", {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Text = (props.label or "") .. ": " .. tostring(props.value or "—"),
		TextColor3 = props.color or C.text,
		Font = Enum.Font.Gotham,
		TextSize = 14,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = props.order or 0,
	})
end

local function ActionButton(props)
	return React.createElement("TextButton", {
		Size = UDim2.new(1, 0, 0, 36),
		BackgroundColor3 = props.color or C.green,
		BorderSizePixel = 0,
		Text = props.text or "Action",
		TextColor3 = C.white,
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		LayoutOrder = props.order or 99,
		[React.Event.Activated] = props.onActivated,
	}, {
		corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 6) }),
	})
end

local function SectionHeader(props)
	return React.createElement("TextLabel", {
		Size = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1,
		Text = props.text or "",
		TextColor3 = C.accent,
		Font = Enum.Font.GothamBold,
		TextSize = 16,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = props.order or 0,
	})
end

local function BonusRow(props)
	local bonus = props.bonus
	return React.createElement("TextLabel", {
		Size = UDim2.fromScale(1, 0),
		AutomaticSize = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		Text = "  • " .. (bonus.stat or "?") .. " +" .. tostring(bonus.value or 0),
		TextColor3 = C.purple,
		Font = Enum.Font.Gotham,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		LayoutOrder = props.order or 0,
	})
end

-- ═══════════════════════════════════════════════════════════
-- EQUIPMENT COLUMN (one for weapon, one for armor)
-- ═══════════════════════════════════════════════════════════

local function EquipColumn(props)
	local data      = props.data         -- weapon or armor table from smithInfo
	local refInfo   = props.refInfo      -- refinement info (optional)
	local tierInfo  = props.tierInfo     -- tier info (optional)
	local rerollInfo = props.rerollInfo  -- reroll info (optional)
	local slotLabel = props.slotLabel    -- "Weapon" or "Armor"
	local npcId     = props.npcId
	local smithType = props.smithType
	local status    = props.status
	local setStatus = props.setStatus

	local children = {}
	local order = 0

	local function next()
		order = order + 1
		return order
	end

	-- Slot header
	children["header"] = React.createElement(SectionHeader, {
		text  = slotLabel,
		order = next(),
	})

	if not data then
		children["empty"] = React.createElement("TextLabel", {
			Size = UDim2.new(1, 0, 0, 24),
			BackgroundTransparency = 1,
			Text = "No " .. slotLabel:lower() .. " equipped",
			TextColor3 = C.text_dim,
			Font = Enum.Font.Gotham,
			TextSize = 14,
			TextXAlignment = Enum.TextXAlignment.Left,
			LayoutOrder = next(),
		})
	else
		-- Name
		children["name"] = React.createElement(StatLine, {
			label = "Name", value = data.name or data.weaponId or data.armorId,
			color = C.yellow, order = next(),
		})
		children["level"] = React.createElement(StatLine, {
			label = "Level", value = data.level, order = next(),
		})
		children["refLevel"] = React.createElement(StatLine, {
			label = "Refinement", value = "+" .. tostring(data.refinement or 0), order = next(),
		})
		children["tierLevel"] = React.createElement(StatLine, {
			label = "Tier", value = data.tier or 1, order = next(),
		})

		-- Bonuses
		if data.bonuses and #data.bonuses > 0 then
			children["bonusHeader"] = React.createElement(StatLine, {
				label = "Random Bonuses", value = "",
				color = C.purple, order = next(),
			})
			for i, bonus in ipairs(data.bonuses) do
				children["bonus_" .. i] = React.createElement(BonusRow, {
					bonus = bonus, order = next(),
				})
			end
		end

		-- ── Refinement action ──────────────────────────────
		if smithType == "Refinement" and refInfo then
			children["refSpacer"] = React.createElement("Frame", {
				Size = UDim2.new(1, 0, 0, 8),
				BackgroundTransparency = 1,
				LayoutOrder = next(),
			})
			children["refChance"] = React.createElement(StatLine, {
				label = "Success Chance",
				value = string.format("%.0f%%", refInfo.successChance or 0),
				color = (refInfo.successChance or 0) >= 50 and C.green or C.orange,
				order = next(),
			})
			children["refCost"] = React.createElement(StatLine, {
				label = "Cost",
				value = tostring(refInfo.cost or 0) .. " " .. (refInfo.currency or "Merits"),
				color = C.yellow, order = next(),
			})
				if refInfo.isMax then
					children["refMax"] = React.createElement(StatLine, {
						label = "Status", value = "MAX refinement reached",
					color = C.accent, order = next(),
				})
				else
					local actionId = slotLabel == "Weapon" and "RefineWeapon" or "RefineArmor"
					children["refBtn"] = React.createElement(ActionButton, {
					text = "Refine " .. slotLabel,
					color = C.green,
					order = next(),
					onActivated = function()
						setStatus("Refining…")
						NetworkManager.FireServer("NPCResponse", {
							npcId  = npcId,
							action = actionId,
						})
					end,
				})
			end
		end

		-- ── Tier Upgrade action ────────────────────────────
		if smithType == "TierUpgrade" and tierInfo then
			children["tierSpacer"] = React.createElement("Frame", {
				Size = UDim2.new(1, 0, 0, 8),
				BackgroundTransparency = 1,
				LayoutOrder = next(),
			})
			children["tierSlots"] = React.createElement(StatLine, {
				label = "Bonus Slots", value = tierInfo.currentSlots or "?",
				order = next(),
			})
			children["tierCost"] = React.createElement(StatLine, {
				label = "Cost",
				value = tostring(tierInfo.cost or 0) .. " " .. (tierInfo.currency or "Merits"),
				color = C.yellow, order = next(),
			})
			if tierInfo.isMax then
				children["tierMax"] = React.createElement(StatLine, {
					label = "Status", value = "MAX tier reached",
					color = C.accent, order = next(),
				})
			else
				local actionId = slotLabel == "Weapon" and "TierWeapon" or "TierArmor"
				children["tierBtn"] = React.createElement(ActionButton, {
					text = "Upgrade " .. slotLabel .. " Tier",
					color = C.orange,
					order = next(),
					onActivated = function()
						setStatus("Upgrading tier…")
						NetworkManager.FireServer("NPCResponse", {
							npcId  = npcId,
							action = actionId,
						})
					end,
				})
			end
		end

		-- ── Bonus Reroll action ────────────────────────────
		if smithType == "BonusReroll" and rerollInfo then
			children["rerollSpacer"] = React.createElement("Frame", {
				Size = UDim2.new(1, 0, 0, 8),
				BackgroundTransparency = 1,
				LayoutOrder = next(),
			})
			children["rerollCost"] = React.createElement(StatLine, {
				label = "Reroll Cost",
				value = tostring(rerollInfo.cost or 0) .. " " .. (rerollInfo.currency or "Merits"),
				color = C.yellow, order = next(),
			})
			children["rerollCount"] = React.createElement(StatLine, {
				label = "Rerolls Used", value = rerollInfo.rerollCount or 0,
				order = next(),
			})
			local hasBonuses = data.bonuses and #data.bonuses > 0
			if hasBonuses then
				local actionId = slotLabel == "Weapon" and "RerollWeapon" or "RerollArmor"
				children["rerollBtn"] = React.createElement(ActionButton, {
					text = "Reroll " .. slotLabel .. " Bonuses",
					color = C.purple,
					order = next(),
					onActivated = function()
						setStatus("Rerolling…")
						NetworkManager.FireServer("NPCResponse", {
							npcId  = npcId,
							action = actionId,
						})
					end,
				})
			else
				children["noBonuses"] = React.createElement(StatLine, {
					label = "Info", value = "No bonuses to reroll yet",
					color = C.text_dim, order = next(),
				})
			end
		end
	end

	children["layout"] = React.createElement("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding   = UDim.new(0, 4),
	})

	return React.createElement("ScrollingFrame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.card,
		BorderSizePixel = 0,
		ScrollBarThickness = 3,
		CanvasSize = UDim2.fromScale(0, 0),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		LayoutOrder = props.layoutOrder or 0,
	}, {
		corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 8) }),
		pad = React.createElement("UIPadding", {
			PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
			PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 10),
		}),
		content = React.createElement("Frame", {
			Size = UDim2.fromScale(1, 0),
			AutomaticSize = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
		}, children),
	})
end

-- ═══════════════════════════════════════════════════════════
-- MAIN COMPONENT
-- ═══════════════════════════════════════════════════════════

local SMITH_TITLES = {
	Refinement  = "Refinement Forge",
	TierUpgrade = "Ascension Anvil",
	BonusReroll = "Enchanting Table",
}

local function WeaponSmithUI(_props)
	local smithData, setSmithData = React.useState(nil)
	local statusMsg, setStatusMsg = React.useState(nil)

	-- Ref so closures in useEffect can always read the latest smithData
	-- without needing to re-register event subscriptions.
	local smithDataRef = React.useRef(nil)

	React.useEffect(function()
		local conns = {}

		-- Open smith UI
		conns[#conns + 1] = NetworkManager.OnServerEvent("NPCSmithOpen", function(data)
			smithDataRef.current = data
			setSmithData(data)
			setStatusMsg(nil)
		end)

		-- Result events → request a Refresh to update displayed data.
		-- statusMsg auto-clears after 3.5 s so it never persists at max tier/refinement.
		local msgClearHandle = nil
		local function showStatus(msg)
			if msgClearHandle then task.cancel(msgClearHandle) end
			setStatusMsg(msg)
			msgClearHandle = task.delay(3.5, function()
				setStatusMsg(nil)
				msgClearHandle = nil
			end)
		end

		local function onResult(_data)
			-- Small delay before refresh so server state settles
			task.delay(0.15, function()
				local current = smithDataRef.current
				if current then
					NetworkManager.FireServer("NPCResponse", {
						npcId  = current.npcId,
						action = "Refresh",
					})
				end
			end)
		end

		-- Weapon result events
		conns[#conns + 1] = NetworkManager.OnServerEvent("WeaponRefinementResult", function(data)
			if data.success then
				showStatus("✔ Refinement succeeded!  +" .. tostring(data.newRefinement or ""))
			else
				showStatus("✘ Refinement failed — still +" .. tostring(data.newRefinement or ""))
			end
			onResult(data)
		end)

		conns[#conns + 1] = NetworkManager.OnServerEvent("WeaponTierUp", function(data)
			showStatus("⬆ Weapon ascended to Tier " .. tostring(data.newTier or "?") .. "!")
			onResult(data)
		end)

		conns[#conns + 1] = NetworkManager.OnServerEvent("WeaponRerollResult", function(data)
			showStatus("✔ Weapon bonuses rerolled!")
			onResult(data)
		end)

		-- Armor result events
		conns[#conns + 1] = NetworkManager.OnServerEvent("ArmorRefinementResult", function(data)
			if data.success then
				showStatus("✔ Armor refinement succeeded!  +" .. tostring(data.newRefinement or ""))
			else
				showStatus("✘ Armor refinement failed — still +" .. tostring(data.newRefinement or ""))
			end
			onResult(data)
		end)

		conns[#conns + 1] = NetworkManager.OnServerEvent("ArmorTierUp", function(data)
			showStatus("⬆ Armor ascended to Tier " .. tostring(data.newTier or "?") .. "!")
			onResult(data)
		end)

		conns[#conns + 1] = NetworkManager.OnServerEvent("ArmorRerollResult", function(data)
			showStatus("✔ Armor bonuses rerolled!")
			onResult(data)
		end)

		return function()
			if msgClearHandle then task.cancel(msgClearHandle) end
			for _, c in conns do
				if c and c.Disconnect then c:Disconnect() end
			end
		end
	end, {})

	-- §AGX/X29: auto-close when the player walks away (server drops
	-- out-of-range responses, which left "Refining…" hanging).
	useNpcDistanceClose(smithData and smithData.npcId, smithData ~= nil, function()
		smithDataRef.current = nil
		setSmithData(nil)
		setStatusMsg(nil)
	end)

	if not smithData then
		return nil
	end

	local smithType = smithData.smithType or "Refinement"
	local title     = (smithData.npcName or "Smith") .. " — " .. (SMITH_TITLES[smithType] or smithType)
	local npcId     = smithData.npcId

	local function closeSmith()
		NetworkManager.FireServer("NPCResponse", {
			npcId  = npcId,
			action = "Close",
		})
		smithDataRef.current = nil
		setSmithData(nil)
		setStatusMsg(nil)
	end

	return React.createElement("Frame", {
		Name = "WeaponSmithUI",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.overlay,
		BackgroundTransparency = 0.40,
		BorderSizePixel = 0,
		ZIndex = 20,
	}, {
		panel = React.createElement("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.55, 0.6),
			BackgroundColor3 = C.panel,
			BorderSizePixel = 0,
		}, {
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 10) }),
			pad = React.createElement("UIPadding", {
				PaddingLeft = UDim.new(0, 16), PaddingRight = UDim.new(0, 16),
				PaddingTop = UDim.new(0, 14), PaddingBottom = UDim.new(0, 14),
			}),

			-- Header
			header = React.createElement("TextLabel", {
				Size = UDim2.fromScale(0.85, 0.08),
				BackgroundTransparency = 1,
				Text = title,
				TextColor3 = C.accent,
				Font = Enum.Font.GothamBold,
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),

			closeBtn = React.createElement("TextButton", {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.fromScale(1, 0),
				Size = UDim2.fromScale(0.05, 0.07),
				BackgroundTransparency = 1,
				Text = "✕",
				TextColor3 = C.text_dim,
				Font = Enum.Font.GothamBold,
				TextScaled = true,
				[React.Event.Activated] = closeSmith,
			}),

			-- Status message
			statusLabel = statusMsg and React.createElement("TextLabel", {
				Position = UDim2.fromScale(0, 0.09),
				Size = UDim2.fromScale(1, 0.06),
				BackgroundTransparency = 1,
				Text = statusMsg,
				TextColor3 = C.green,
				Font = Enum.Font.Gotham,
				TextSize = 14,
				TextXAlignment = Enum.TextXAlignment.Left,
			}) or nil,

			-- Two-column layout: Weapon | Armor
			columns = React.createElement("Frame", {
				Position = UDim2.fromScale(0, 0.17),
				Size = UDim2.fromScale(1, 0.83),
				BackgroundTransparency = 1,
			}, {
				layout = React.createElement("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					SortOrder     = Enum.SortOrder.LayoutOrder,
					Padding       = UDim.new(0, 12),
				}),

				weaponCol = React.createElement("Frame", {
					Size = UDim2.new(0.48, 0, 1, 0),
					BackgroundTransparency = 1,
					LayoutOrder = 1,
				}, {
					col = React.createElement(EquipColumn, {
						data        = smithData.weapon,
						refInfo     = smithData.weaponRefInfo,
						tierInfo    = smithData.weaponTierInfo,
						rerollInfo  = smithData.weaponRerollInfo,
						slotLabel   = "Weapon",
						npcId       = npcId,
						smithType   = smithType,
						status      = statusMsg,
						setStatus   = setStatusMsg,
						layoutOrder = 1,
					}),
				}),

				armorCol = React.createElement("Frame", {
					Size = UDim2.new(0.48, 0, 1, 0),
					BackgroundTransparency = 1,
					LayoutOrder = 2,
				}, {
					col = React.createElement(EquipColumn, {
						data        = smithData.armor,
						refInfo     = smithData.armorRefInfo,
						tierInfo    = smithData.armorTierInfo,
						rerollInfo  = smithData.armorRerollInfo,
						slotLabel   = "Armor",
						npcId       = npcId,
						smithType   = smithType,
						status      = statusMsg,
						setStatus   = setStatusMsg,
						layoutOrder = 2,
					}),
				}),
			}),
		}),
	})
end

return WeaponSmithUI
