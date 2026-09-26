-- lobby/StarterPlayerScripts/UI/WeaponSmithUI.lua
--[[
    Forge overlay triggered by "NPCSmithOpen" server event.
    
    Displays weapon / armor info and an action button based on the
    smith sub-type: Refinement, TierUpgrade, or BonusReroll.
    
    Fires "NPCResponse" with the appropriate action string so the
    server-side WeaponSmithHandler can act.
    After each successful action, requests a Refresh to update displayed data.

    §AGX/UI-P6: Theme v2 re-skin: AppWindow chrome, Panel columns, Button
    actions, CurrencyPill costs, Text lines, design px under
    UIScaleRoot.Local. The palette table and the hand-rolled backdrop /
    panel / ✕ / ActionButton are gone. useExternal, useNpcDistanceClose,
    closeSmith and every NPCResponse payload unchanged.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local React             = require(ReplicatedStorage.Packages.React)

local SharedModules  = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Modules")
local useNpcDistanceClose = require(Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("UI"):WaitForChild("Common"):WaitForChild("useNpcDistanceClose"))  -- §AGX/X29
local NetworkManager = require(SharedModules:WaitForChild("NetworkManager"))
local PlayerScripts_UI = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("UI")
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

-- §AGX/UI-P6: shared components (the private palette is gone).
local Common       = PlayerScripts_UI:WaitForChild("Common")
local Theme        = require(Common:WaitForChild("Theme"))
local AppWindow    = require(Common:WaitForChild("AppWindow"))
local UIScaleRoot  = require(Common:WaitForChild("UIScaleRoot"))
local Text         = require(Common:WaitForChild("Text"))
local Button       = require(Common:WaitForChild("Button"))
local Panel        = require(Common:WaitForChild("Panel"))
local CurrencyPill = require(Common:WaitForChild("CurrencyPill"))

local e  = React.createElement
local R  = Theme.Roles
local SP = Theme.Space

local ROW_H    = 24     -- design px, one stat line
local COST_H   = Theme.Metrics.pill.height
local STATUS_H = 24

-- Smith cost currency -> CurrencyPill key.
local PILL_CURRENCY = { Merits = "merits", Essence = "essence" }

-- ── Helpers ───────────────────────────────────────────────

-- §AGX/UI-P6: label (secondary) left, value right; `color` is a role path.
local function StatLine(props)
	return e("Frame", {
		Size                   = UDim2.new(1, 0, 0, ROW_H),
		BackgroundTransparency = 1,
		LayoutOrder            = props.order or 0,
	}, {
		label = e(Text, {
			style = "caption", color = "text.secondary",
			text  = props.label or "",
			size  = UDim2.fromScale(0.5, 1),
		}),
		value = e(Text, {
			style       = "body",
			color       = props.color or "text.primary",
			text        = tostring(props.value or "—"),
			align       = "right",
			anchorPoint = Vector2.new(1, 0),
			position    = UDim2.fromScale(1, 0),
			size        = UDim2.fromScale(0.5, 1),
		}),
	})
end

-- §AGX/UI-P6: cost line = label + CurrencyPill (text fallback).
local function CostLine(props)
	local key = PILL_CURRENCY[props.currency or "Merits"]
	return e("Frame", {
		Size                   = UDim2.new(1, 0, 0, COST_H),
		BackgroundTransparency = 1,
		LayoutOrder            = props.order or 0,
	}, {
		label = e(Text, {
			style = "caption", color = "text.secondary",
			text  = props.label or "Cost",
			size  = UDim2.fromScale(0.5, 1),
		}),
		pill = key and e(CurrencyPill, {
			currency    = key,
			value       = props.cost or 0,
			cost        = true,
			anchorPoint = Vector2.new(1, 0.5),
			position    = UDim2.fromScale(1, 0.5),
		}) or e(Text, {
			style       = "numeric",
			text        = tostring(props.cost or 0) .. " " .. tostring(props.currency),
			align       = "right",
			anchorPoint = Vector2.new(1, 0),
			position    = UDim2.fromScale(1, 0),
			size        = UDim2.fromScale(0.5, 1),
		}),
	})
end

-- §AGX/UI-P6: Button (was a hand-rolled 36 px ActionButton).
local function ActionButton(props)
	return e(Button, {
		variant     = "secondary",
		size        = "md",
		width       = UDim.new(1, 0),
		label       = props.text or "Action",
		layoutOrder = props.order or 99,
		onActivated = props.onActivated,
	})
end

local function SectionHeader(props)
	return e(Text, {
		style       = "heading",
		text        = props.text or "",
		size        = UDim2.new(1, 0, 0, 26),
		layoutOrder = props.order or 0,
	})
end

local function BonusRow(props)
	local bonus = props.bonus
	return e(Text, {
		style       = "body",
		color       = "rarity.epic",
		text        = "  • " .. (bonus.stat or "?") .. " +" .. tostring(bonus.value or 0),
		size        = UDim2.new(1, 0, 0, ROW_H),
		layoutOrder = props.order or 0,
	})
end

local function Spacer(order)
	return e("Frame", {
		Size = UDim2.new(1, 0, 0, SP.sm),
		BackgroundTransparency = 1,
		LayoutOrder = order,
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
	children["header"] = e(SectionHeader, {
		text  = slotLabel,
		order = next(),
	})

	if not data then
		children["empty"] = e(Text, {
			style       = "body",
			color       = "text.secondary",
			text        = "No " .. slotLabel:lower() .. " equipped",
			size        = UDim2.new(1, 0, 0, ROW_H),
			layoutOrder = next(),
		})
	else
		-- Name
		children["name"] = e(StatLine, {
			label = "Name", value = data.name or data.weaponId or data.armorId,
			color = "rarity.legendary", order = next(),
		})
		children["level"] = e(StatLine, {
			label = "Level", value = data.level, order = next(),
		})
		children["refLevel"] = e(StatLine, {
			label = "Refinement", value = "+" .. tostring(data.refinement or 0), order = next(),
		})
		children["tierLevel"] = e(StatLine, {
			label = "Tier", value = data.tier or 1, order = next(),
		})

		-- Bonuses
		if data.bonuses and #data.bonuses > 0 then
			children["bonusHeader"] = e(StatLine, {
				label = "Random Bonuses", value = "",
				color = "rarity.epic", order = next(),
			})
			for i, bonus in ipairs(data.bonuses) do
				children["bonus_" .. i] = e(BonusRow, {
					bonus = bonus, order = next(),
				})
			end
		end

		-- ── Refinement action ──────────────────────────────
		if smithType == "Refinement" and refInfo then
			children["refSpacer"] = Spacer(next())
			children["refChance"] = e(StatLine, {
				label = "Success Chance",
				value = string.format("%.0f%%", refInfo.successChance or 0),
				color = (refInfo.successChance or 0) >= 50 and "state.success" or "state.warning",
				order = next(),
			})
			children["refCost"] = e(CostLine, {
				label = "Cost", cost = refInfo.cost, currency = refInfo.currency or "Merits",
				order = next(),
			})
				if refInfo.isMax then
					children["refMax"] = e(StatLine, {
						label = "Status", value = "MAX refinement reached",
					color = "accent.secondary", order = next(),
				})
				else
					local actionId = slotLabel == "Weapon" and "RefineWeapon" or "RefineArmor"
					children["refBtn"] = e(ActionButton, {
					text = "Refine " .. slotLabel,
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
			children["tierSpacer"] = Spacer(next())
			children["tierSlots"] = e(StatLine, {
				label = "Bonus Slots", value = tierInfo.currentSlots or "?",
				order = next(),
			})
			children["tierCost"] = e(CostLine, {
				label = "Cost", cost = tierInfo.cost, currency = tierInfo.currency or "Merits",
				order = next(),
			})
			if tierInfo.isMax then
				children["tierMax"] = e(StatLine, {
					label = "Status", value = "MAX tier reached",
					color = "accent.secondary", order = next(),
				})
			else
				local actionId = slotLabel == "Weapon" and "TierWeapon" or "TierArmor"
				children["tierBtn"] = e(ActionButton, {
					text = "Upgrade " .. slotLabel .. " Tier",
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
			children["rerollSpacer"] = Spacer(next())
			children["rerollCost"] = e(CostLine, {
				label = "Reroll Cost", cost = rerollInfo.cost, currency = rerollInfo.currency or "Merits",
				order = next(),
			})
			children["rerollCount"] = e(StatLine, {
				label = "Rerolls Used", value = rerollInfo.rerollCount or 0,
				order = next(),
			})
			local hasBonuses = data.bonuses and #data.bonuses > 0
			if hasBonuses then
				local actionId = slotLabel == "Weapon" and "RerollWeapon" or "RerollArmor"
				children["rerollBtn"] = e(ActionButton, {
					text = "Reroll " .. slotLabel .. " Bonuses",
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
				children["noBonuses"] = e(StatLine, {
					label = "Info", value = "No bonuses to reroll yet",
					color = "text.secondary", order = next(),
				})
			end
		end
	end

	children["layout"] = e("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding   = UDim.new(0, SP.xs),
	})

	-- §AGX/UI-P6: Panel surface around a scrolling column.
	return e(Panel, {
		name        = slotLabel .. "Column",
		elevation   = "raised",
		padding     = "md",
		layoutOrder = props.layoutOrder or 0,
	}, {
		scroll = e("ScrollingFrame", {
			Size                 = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel      = 0,
			ScrollBarThickness   = Theme.Metrics.scrollBar,
			ScrollBarImageColor3 = R.text.secondary,
			CanvasSize           = UDim2.fromScale(0, 0),
			AutomaticCanvasSize  = Enum.AutomaticSize.Y,
			ScrollingDirection   = Enum.ScrollingDirection.Y,
		}, {
			content = e("Frame", {
				Size = UDim2.new(1, -(Theme.Metrics.scrollBar + SP.xs), 0, 0),
				AutomaticSize = Enum.AutomaticSize.Y,
				BackgroundTransparency = 1,
			}, children),
		}),
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

local function WeaponSmithUI(props)
	-- §AGX/UI-P3: onClose (PanelHost: close(id, "self")); was unused.
	local onClose = (props and props.onClose) or function() end
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
		onClose()   -- §AGX/UI-P3
	end)

	-- §AGX/UI-P3: one close helper before the early return, so the stack
	-- (useExternal) can call it; fires NPCResponse Close as the ✕ did.
	local function closeSmith()
		local current = smithDataRef.current
		if current then
			NetworkManager.FireServer("NPCResponse", {
				npcId  = current.npcId,
				action = "Close",
			})
		end
		smithDataRef.current = nil
		setSmithData(nil)
		setStatusMsg(nil)
		onClose()
	end

	-- §AGX/UI-P3: A10, register with the PanelStack (replaces / is replaced).
	useExternal("npcSmith", smithData ~= nil, closeSmith)

	if not smithData then
		return nil
	end

	local smithType = smithData.smithType or "Refinement"
	local title     = (smithData.npcName or "Smith") .. " — " .. (SMITH_TITLES[smithType] or smithType)
	local npcId     = smithData.npcId

	-- §AGX/UI-P6: status colour by outcome (was always green).
	local statusColor = "state.success"
	if statusMsg then
		if string.sub(statusMsg, 1, #"✘") == "✘" then
			statusColor = "state.danger"
		elseif string.sub(statusMsg, -#"…") == "…" then
			statusColor = "text.secondary"
		end
	end
	local colsTop = statusMsg and (STATUS_H + SP.sm) or 0

	local function column(slot, order)
		local key = string.lower(slot)
		return e("Frame", {
			Size                   = UDim2.new(0.5, -SP.sm / 2, 1, 0),
			BackgroundTransparency = 1,
			LayoutOrder            = order,
		}, {
			col = e(EquipColumn, {
				data        = smithData[key],
				refInfo     = smithData[key .. "RefInfo"],
				tierInfo    = smithData[key .. "TierInfo"],
				rerollInfo  = smithData[key .. "RerollInfo"],
				slotLabel   = slot,
				npcId       = npcId,
				smithType   = smithType,
				status      = statusMsg,
				setStatus   = setStatusMsg,
				layoutOrder = order,
			}),
		})
	end

	-- §AGX/UI-P6: AppWindow chrome (auto: sheet on phone; the shell's
	-- presentation wins). Its panel is Active (UX-14). ✕ = closeSmith.
	local z = Theme.Z.windowOver
	return e(AppWindow, {
		variant = "auto",
		title   = title,
		icon    = "equipment",
		onClose = function() closeSmith() end,
		size    = UDim2.fromScale(0.58, 0.66),
		minSize = Vector2.new(560, 400),
		zIndex  = z,
	}, {
		scaled = e(UIScaleRoot.Local, { name = "SmithBody", zIndex = z + 2 }, {
			pad = e("UIPadding", {
				PaddingLeft = UDim.new(0, SP.lg), PaddingRight = UDim.new(0, SP.lg),
				PaddingTop = UDim.new(0, SP.md), PaddingBottom = UDim.new(0, SP.lg),
			}),
			-- Status message
			statusLabel = statusMsg and e(Text, {
				style  = "label",
				text   = statusMsg,
				color  = statusColor,
				size   = UDim2.new(1, 0, 0, STATUS_H),
				zIndex = z + 2,
			}) or nil,

			-- Two-column layout: Weapon | Armor
			columns = e("Frame", {
				Position               = UDim2.fromOffset(0, colsTop),
				Size                   = UDim2.new(1, 0, 1, -colsTop),
				BackgroundTransparency = 1,
				ZIndex                 = z + 2,
			}, {
				layout = e("UIListLayout", {
					FillDirection = Enum.FillDirection.Horizontal,
					SortOrder     = Enum.SortOrder.LayoutOrder,
					Padding       = UDim.new(0, SP.sm),
				}),
				weaponCol = column("Weapon", 1),
				armorCol  = column("Armor", 2),
			}),
		}),
	})
end

return WeaponSmithUI
