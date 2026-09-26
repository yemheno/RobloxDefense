-- shared/StarterPlayerScripts/UI/InventoryUI.lua  (§AGX/UI-P3 W4: moved from lobby/UI; its manager loads in every place)
--[[
    Minimal Inventory panel.  Shows owned accessories with equipped slots.
    Equip/unequip buttons fire the appropriate server events.
    Server pushes InventoryUpdate after each action with the fresh state.

    Props:
      onClose  function
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React             = require(ReplicatedStorage.Packages.React)

local PlayerScripts  = Players.LocalPlayer:WaitForChild("PlayerScripts")
local SharedModules  = PlayerScripts:WaitForChild("Modules")
local NetworkManager = require(SharedModules:WaitForChild("NetworkManager"))

local C = {
	bg      = Color3.fromRGB(18, 18, 24),
	row     = Color3.fromRGB(32, 32, 46),
	rowEq   = Color3.fromRGB(26, 40, 32),
	text    = Color3.fromRGB(220, 220, 230),
	dim     = Color3.fromRGB(140, 140, 160),
	gold    = Color3.fromRGB(255, 200, 60),
	green   = Color3.fromRGB(50, 170, 80),
	red     = Color3.fromRGB(170, 60, 60),
	blue    = Color3.fromRGB(80, 160, 255),
	close   = Color3.fromRGB(180, 50, 50),
}

-- §AGX/UI-P1: minimum tap target (T14: close was 8x9 px on a phone).
local MIN_TAP_PX = 44

-- §AGX/UI-P1: transparent hit box centred on a small visual button, at least
-- minSize (default 44x44). The visual keeps its size; only the hit area grows.
local function hitArea(onActivated, zIndex, minSize)
	return React.createElement("TextButton", {
		Name                   = "HitArea",
		AnchorPoint            = Vector2.new(0.5, 0.5),
		Position               = UDim2.fromScale(0.5, 0.5),
		Size                   = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Text                   = "",
		ZIndex                 = zIndex,
		[React.Event.Activated] = onActivated,
	}, {
		minSize = React.createElement("UISizeConstraint", {
			MinSize = minSize or Vector2.new(MIN_TAP_PX, MIN_TAP_PX),
		}),
	})
end

-- §AGX/UI-P1: M11: TextScaled labels get a readable floor on phones.
local function minText()
	return React.createElement("UITextSizeConstraint", { MinTextSize = 12 })
end

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
	rows["layout"] = React.createElement("UIListLayout", {
		SortOrder = Enum.SortOrder.LayoutOrder,
		Padding   = UDim.new(0, 4),
	})

	if #items == 0 then
		rows["empty"] = React.createElement("TextLabel", {
			Size                   = UDim2.new(1, 0, 0, 40),
			BackgroundTransparency = 1,
			Text                   = invData and "No accessories owned." or "Loading…",
			TextColor3             = C.dim,
			Font                   = Enum.Font.Gotham,
			TextScaled             = true,
			LayoutOrder            = 1,
		}, { minText = minText() })  -- §AGX/UI-P1: M11 text floor
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

			-- §AGX/UI-P1: hoisted so the visual button and its hit box share it.
			local function onAction()
				if isEquipped then
					NetworkManager.FireServer("UnequipAccessory", equippedSlot)
				elseif targetSlot then
					NetworkManager.FireServer("EquipAccessory", item.itemId, targetSlot)
				end
			end

			rows["item_" .. i] = React.createElement("Frame", {
				Size             = UDim2.new(1, 0, 0, 46),
				BackgroundColor3 = isEquipped and C.rowEq or C.row,
				BorderSizePixel  = 0,
				LayoutOrder      = i,
			}, {
				corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 6) }),

				nameLbl = React.createElement("TextLabel", {
					Position               = UDim2.fromScale(0.02, 0.10),
					Size                   = UDim2.fromScale(0.40, 0.45),
					BackgroundTransparency = 1,
					Text                   = item.itemId,
					TextColor3             = isEquipped and C.gold or C.text,
					Font                   = Enum.Font.GothamBold,
					TextScaled             = true,
					TextXAlignment         = Enum.TextXAlignment.Left,
				}, { minText = minText() }),  -- §AGX/UI-P1: M11 text floor

				qtyLbl = React.createElement("TextLabel", {
					Position               = UDim2.fromScale(0.02, 0.55),
					Size                   = UDim2.fromScale(0.25, 0.35),
					BackgroundTransparency = 1,
					Text                   = "×" .. tostring(item.quantity or 1),
					TextColor3             = C.dim,
					Font                   = Enum.Font.Gotham,
					TextScaled             = true,
					TextXAlignment         = Enum.TextXAlignment.Left,
				}, { minText = minText() }),  -- §AGX/UI-P1: M11 text floor

				slotLbl = isEquipped and React.createElement("TextLabel", {
					Position               = UDim2.fromScale(0.42, 0.10),
					Size                   = UDim2.fromScale(0.28, 0.80),
					BackgroundTransparency = 1,
					Text                   = SLOT_LABELS[equippedSlot] or equippedSlot,
					TextColor3             = C.green,
					Font                   = Enum.Font.GothamBold,
					TextScaled             = true,
					TextXAlignment         = Enum.TextXAlignment.Center,
				}, { minText = minText() }) or nil,  -- §AGX/UI-P1: M11 text floor

				actionBtn = React.createElement("TextButton", {
					AnchorPoint      = Vector2.new(1, 0.5),
					Position         = UDim2.fromScale(0.98, 0.5),
					Size             = UDim2.fromScale(0.24, 0.72),
					BackgroundColor3 = isEquipped and C.red or (canEquip and C.green or C.blue),
					BorderSizePixel  = 0,
					Text             = isEquipped and "Unequip" or (canEquip and "Equip" or "Full"),
					TextColor3       = Color3.fromRGB(255, 255, 255),
					Font             = Enum.Font.GothamBold,
					TextScaled       = true,
					ZIndex           = 12,
					Active           = isEquipped or canEquip,
					[React.Event.Activated] = onAction,
				}, {
					corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.2, 0) }),
					minText = minText(),  -- §AGX/UI-P1: M11 text floor
					-- §AGX/UI-P1: button is 33 px tall (0.72 of a 46 px row);
					-- hit box makes it 44 px on the tap axis (row pitch is 50).
					hit = hitArea(onAction, 13, Vector2.new(0, MIN_TAP_PX)),
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

	return React.createElement("Frame", {
		Name                   = "InventoryBackdrop",
		Size                   = UDim2.fromScale(1, 1),
		BackgroundColor3       = Color3.fromRGB(0, 0, 0),
		BackgroundTransparency = 0.42,
		ZIndex                 = 10,
	}, {
		panel = React.createElement("Frame", {
			AnchorPoint      = Vector2.new(0.5, 0.5),
			Position         = UDim2.fromScale(0.5, 0.5),
			Size             = UDim2.fromScale(0.50, 0.70),
			BackgroundColor3 = C.bg,
			BorderSizePixel  = 0,
			ZIndex           = 11,
		}, {
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 12) }),

			titleLbl = React.createElement("TextLabel", {
				Position               = UDim2.fromScale(0.04, 0.02),
				Size                   = UDim2.fromScale(0.75, 0.08),
				BackgroundTransparency = 1,
				Text                   = "🎒  Inventory",
				TextColor3             = C.gold,
				Font                   = Enum.Font.GothamBold,
				TextScaled             = true,
				TextXAlignment         = Enum.TextXAlignment.Left,
				ZIndex                 = 12,
			}, { minText = minText() }),  -- §AGX/UI-P1: M11 text floor

			closeBtn = React.createElement("TextButton", {
				AnchorPoint      = Vector2.new(1, 0),
				Position         = UDim2.fromScale(0.97, 0.02),
				Size             = UDim2.fromScale(0.018, 0.031),
				BackgroundColor3 = C.close,
				BorderSizePixel  = 0,
				Text             = "✕",
				TextColor3       = Color3.fromRGB(255, 255, 255),
				Font             = Enum.Font.GothamBold,
				TextScaled       = true,
				ZIndex           = 12,
				[React.Event.Activated] = onClose,
			}, {
				corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
				-- §AGX/UI-P1: T14: visual was 8x9 px on a phone; floor it at
				-- the 1080p size (~17x23) so it stays visible, plus a 44x44
				-- transparent hit box.
				visMin = React.createElement("UISizeConstraint", { MinSize = Vector2.new(17, 17) }),
				minText = minText(),
				hit = hitArea(onClose, 13),
			}),

			equippedBar = React.createElement("TextLabel", {
				Position               = UDim2.fromScale(0.04, 0.12),
				Size                   = UDim2.fromScale(0.92, 0.07),
				BackgroundTransparency = 1,
				Text                   = "Equipped: " .. equippedText,
				TextColor3             = C.blue,
				Font                   = Enum.Font.Gotham,
				TextScaled             = true,
				TextXAlignment         = Enum.TextXAlignment.Left,
				ZIndex                 = 12,
			}, { minText = minText() }),  -- §AGX/UI-P1: M11 text floor

			listFrame = React.createElement("ScrollingFrame", {
				Position              = UDim2.fromScale(0.04, 0.21),
				Size                  = UDim2.fromScale(0.92, 0.76),
				BackgroundTransparency = 1,
				BorderSizePixel       = 0,
				ScrollBarThickness    = 4,
				AutomaticCanvasSize   = Enum.AutomaticSize.Y,
				CanvasSize            = UDim2.fromScale(0, 0),
				ZIndex                = 12,
			}, rows),
		}),
	})
end

return InventoryUI
