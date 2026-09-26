-- shared/StarterPlayerScripts/UI/InventoryUI.lua  (§AGX/UI-P3 W4: moved from lobby/UI; its manager loads in every place)
--[[
    Minimal Inventory panel.  Shows owned accessories with equipped slots.
    Equip/unequip buttons fire the appropriate server events.
    Server pushes InventoryUpdate after each action with the fresh state.

    Props:
      onClose  function

    §AGX/UI-P6: Theme v2 re-skin. AppWindow chrome (auto: sheet on phone,
    windowed 0.50 x 0.70 elsewhere) replaces the hand-rolled panel and its
    17x23 close button (T14). Body = design px inside UIScaleRoot.Local:
    an "Equipped" summary Panel over a scrolling list of Panel rows with a
    48 px Button (Equip / Unequip, "Full" = locked). The private palette,
    hitArea/minText helpers and TextScaled labels are gone. Same events.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React             = require(ReplicatedStorage.Packages.React)

local PlayerScripts  = Players.LocalPlayer:WaitForChild("PlayerScripts")
local SharedModules  = PlayerScripts:WaitForChild("Modules")
local NetworkManager = require(SharedModules:WaitForChild("NetworkManager"))

-- §AGX/UI-P6: shared components
local Common      = script.Parent:WaitForChild("Common")
local Theme       = require(Common:WaitForChild("Theme"))
local UIScaleRoot = require(Common:WaitForChild("UIScaleRoot"))
local AppWindow   = require(Common:WaitForChild("AppWindow"))
local Text        = require(Common:WaitForChild("Text"))
local Button      = require(Common:WaitForChild("Button"))
local Panel       = require(Common:WaitForChild("Panel"))

local e  = React.createElement
local R  = Theme.Roles
local SP = Theme.Space

-- §AGX/UI-P6: layout in DESIGN px (phone scale).
local ROW_H      = 64
local ACTION_W   = 124
local SLOT_W     = 88
local SUMMARY_H  = 44

local SLOT_LABELS = {
	Trinket = "Trinket",
	Ring1   = "Ring 1",
	Ring2   = "Ring 2",
}

local function InventoryUI(props)
	local onClose = props.onClose or function() end

	local invData, setInvData = React.useState(nil)

	React.useEffect(function()
		local mounted = true
		NetworkManager.FireServer("GetInventory")

		local conn = NetworkManager.OnServerEvent("InventoryUpdate", function(data)
			if mounted then setInvData(data) end
		end)

		return function()
			mounted = false
			if conn then conn:Disconnect() end
		end
	end, {})

	local items    = invData and invData.items    or {}
	local equipped = invData and invData.equipped or {}

	-- Build rows
	local rows = {}
	rows["layout"] = e("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding   = UDim.new(0, SP.sm),
	})

	if #items == 0 then
		rows["empty"] = e(Text, {
			style       = "body",
			text        = invData and "No accessories owned." or "Loading…",
			color       = "text.secondary",
			align       = "center",
			size        = UDim2.new(1, 0, 0, 40),
			layoutOrder = 1,
		})
	else
		for i, item in ipairs(items) do
			-- Find which slot this item is equipped in (if any)
			local equippedSlot = nil
			for slot, id in pairs(equipped) do
				if id == item.itemId then
					equippedSlot = slot
					break
				end
			end

			local isEquipped = equippedSlot ~= nil
			local targetSlot = nil
			for _, slot in ipairs({"Trinket", "Ring1", "Ring2"}) do
				if not equipped[slot] then
					targetSlot = slot
					break
				end
			end
			local canEquip = isEquipped or targetSlot ~= nil

			local function onAction()
				if isEquipped then
					NetworkManager.FireServer("UnequipAccessory", equippedSlot)
				elseif targetSlot then
					NetworkManager.FireServer("EquipAccessory", item.itemId, targetSlot)
				end
			end

			local textW = -(ACTION_W + SP.sm + (isEquipped and (SLOT_W + SP.sm) or 0))
			rows["item_" .. i] = e(Panel, {
				name        = "Item_" .. tostring(item.itemId),
				elevation   = "raised",
				padding     = "sm",
				accent      = isEquipped and "accent.secondary" or nil,   -- equipped = blue ring
				size        = UDim2.new(1, 0, 0, ROW_H),
				layoutOrder = i,
			}, {
				nameLbl = e(Text, {
					style = "heading",
					text  = item.itemId,
					size  = UDim2.new(1, textW, 0, 24),
				}),
				qtyLbl = e(Text, {
					style    = "caption",
					text     = "×" .. tostring(item.quantity or 1),
					color    = "text.secondary",
					position = UDim2.fromOffset(0, 26),
					size     = UDim2.new(1, textW, 0, 18),
				}),
				slotLbl = isEquipped and e(Text, {
					style       = "label",
					text        = SLOT_LABELS[equippedSlot] or equippedSlot,
					color       = "state.success",
					align       = "center",
					anchorPoint = Vector2.new(1, 0.5),
					position    = UDim2.new(1, -(ACTION_W + SP.sm), 0.5, 0),
					size        = UDim2.fromOffset(SLOT_W, 24),
				}) or nil,
				-- §AGX/UI-P1 (T14, 44 px target) re-expressed: 48 design px Button.
				actionBtn = e(Button, {
					variant     = isEquipped and "secondary" or (canEquip and "secondary" or "locked"),
					label       = isEquipped and "Unequip" or (canEquip and "Equip" or "Full"),
					width       = ACTION_W,
					anchorPoint = Vector2.new(1, 0.5),
					position    = UDim2.fromScale(1, 0.5),
					onActivated = (isEquipped or canEquip) and onAction or nil,
				}),
			})
		end
	end

	-- Equipped summary at top
	local equippedLines = {}
	for slot, id in pairs(equipped) do
		if id then
			table.insert(equippedLines, (SLOT_LABELS[slot] or slot) .. ": " .. id)
		end
	end
	local equippedText = #equippedLines > 0 and table.concat(equippedLines, "  ·  ") or "None equipped"

	return e(AppWindow, {
		variant = "auto",
		title   = "Inventory",
		icon    = "inventory",
		onClose = onClose,
		size    = UDim2.fromScale(0.50, 0.70),
	}, {
		content = e(UIScaleRoot.Local, { name = "InventoryBody", zIndex = Theme.Z.window + 2 }, {
			pad = e("UIPadding", {
				PaddingLeft = UDim.new(0, SP.lg), PaddingRight = UDim.new(0, SP.lg),
				PaddingTop = UDim.new(0, SP.md), PaddingBottom = UDim.new(0, SP.md),
			}),
			equippedBar = e(Panel, {
				name      = "Equipped",
				elevation = "sunken",
				padding   = "sm",
				size      = UDim2.new(1, 0, 0, SUMMARY_H),
			}, {
				text = e(Text, {
					style = "body",
					text  = "Equipped: " .. equippedText,
					color = "accent.secondary",
					size  = UDim2.fromScale(1, 1),
				}),
			}),
			listFrame = e("ScrollingFrame", {
				Name                   = "List",
				Position               = UDim2.fromOffset(0, SUMMARY_H + SP.md),
				Size                   = UDim2.new(1, 0, 1, -(SUMMARY_H + SP.md)),
				BackgroundTransparency = 1,
				BorderSizePixel        = 0,
				ScrollBarThickness     = Theme.Metrics.scrollBar,
				ScrollBarImageColor3   = R.text.secondary,
				ScrollingDirection     = Enum.ScrollingDirection.Y,
				AutomaticCanvasSize    = Enum.AutomaticSize.Y,
				CanvasSize             = UDim2.fromScale(0, 0),
			}, rows),
		}),
	})
end

return InventoryUI
