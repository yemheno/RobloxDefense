-- UI/ShopUI.lua
--[[
    Shop overlay triggered by "NPCShopOpen" server event.
    
    Displays item cards with name, description, price, and a
    Buy button. Fires "NPCResponse" → { npcId, action = "Buy", itemId }.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local React             = require(ReplicatedStorage.Packages.React)

local SharedModules  = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Modules")
local NetworkManager = require(SharedModules:WaitForChild("NetworkManager"))

-- ── Palette ───────────────────────────────────────────────
local C = {
	overlay    = Color3.fromRGB(  0,   0,   0),
	panel      = Color3.fromRGB( 22,  22,  30),
	card       = Color3.fromRGB( 32,  32,  46),
	accent     = Color3.fromRGB(105, 190, 255),
	green      = Color3.fromRGB( 50, 170,  80),
	red        = Color3.fromRGB(170,  50,  50),
	yellow     = Color3.fromRGB(255, 210,  60),
	text       = Color3.fromRGB(220, 220, 230),
	text_dim   = Color3.fromRGB(140, 140, 160),
	white      = Color3.fromRGB(255, 255, 255),
}

-- ── Item Card ─────────────────────────────────────────────
local function ItemCard(props)
	local item = props.item
	local npcId = props.npcId
	local statusMsg, setStatusMsg = React.useState(nil)
	local mountedRef = React.useRef(true)
	React.useEffect(function()
		return function() mountedRef.current = false end
	end, {})

	return React.createElement("Frame", {
		Size             = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.card,
		BorderSizePixel  = 0,
		LayoutOrder      = props.order,
	}, {
		corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.06, 0) }),
		pad = React.createElement("UIPadding", {
			PaddingLeft = UDim.new(0.04, 0), PaddingRight = UDim.new(0.04, 0),
			PaddingTop = UDim.new(0.06, 0), PaddingBottom = UDim.new(0.06, 0),
		}),

		-- Item name
		nameLabel = React.createElement("TextLabel", {
			Size = UDim2.fromScale(0.7, 0.25),
			BackgroundTransparency = 1,
			Text = item.name or item.id or "???",
			TextColor3 = C.accent,
			Font = Enum.Font.GothamBold,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
		}),

		-- Price
		priceLabel = React.createElement("TextLabel", {
			AnchorPoint = Vector2.new(1, 0),
			Position = UDim2.fromScale(1, 0),
			Size = UDim2.fromScale(0.28, 0.22),
			BackgroundTransparency = 1,
			Text = tostring(item.price or 0) .. " " .. (item.currency or "Essence"),
			TextColor3 = C.yellow,
			Font = Enum.Font.GothamBold,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Right,
		}),

		-- Description
		descLabel = React.createElement("TextLabel", {
			Position = UDim2.fromScale(0, 0.30),
			Size = UDim2.fromScale(1, 0.35),
			BackgroundTransparency = 1,
			Text = item.description or "",
			TextColor3 = C.text_dim,
			Font = Enum.Font.Gotham,
			TextSize = 14,
			TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left,
			TextYAlignment = Enum.TextYAlignment.Top,
		}),

		-- Status message (after buy attempt)
		statusLabel = statusMsg and React.createElement("TextLabel", {
			AnchorPoint = Vector2.new(0, 1),
			Position = UDim2.fromScale(0, 0.98),
			Size = UDim2.fromScale(0.6, 0.2),
			BackgroundTransparency = 1,
			Text = statusMsg,
			TextColor3 = C.green,
			Font = Enum.Font.Gotham,
			TextScaled = true,
			TextXAlignment = Enum.TextXAlignment.Left,
		}) or nil,

		-- Buy button
		buyBtn = React.createElement("TextButton", {
			AnchorPoint = Vector2.new(1, 1),
			Position = UDim2.fromScale(1, 0.98),
			Size = UDim2.fromScale(0.28, 0.25),
			BackgroundColor3 = C.green,
			BorderSizePixel = 0,
			Text = "Buy",
			TextColor3 = C.white,
			Font = Enum.Font.GothamBold,
			TextScaled = true,
			[React.Event.Activated] = function()
				NetworkManager.FireServer("NPCResponse", {
					npcId  = npcId,
					action = "Buy",
					itemId = item.id,
				})
				setStatusMsg("Purchasing…")
				task.delay(2, function()
					if mountedRef.current then setStatusMsg(nil) end
				end)
			end,
		}, {
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.25, 0) }),
		}),
	})
end

-- ── Main Component ────────────────────────────────────────
local function ShopUI(props)
	local onClose = props.onClose or function() end

	local shopData, setShopData = React.useState(nil)

	React.useEffect(function()
		local conns = {}

		conns[1] = NetworkManager.OnServerEvent("NPCShopOpen", function(data)
			-- data = { npcId, npcName, items = { { id, name, description, price, currency } } }
			setShopData(data)
		end)

		-- Success / error feedback
		conns[2] = NetworkManager.OnServerEvent("NPCResponse", function(data)
			-- Could show toast-style feedback; for now ignored
		end)

		return function()
			for _, c in conns do
				if c then c:Disconnect() end
			end
		end
	end, {})

	if not shopData then
		return nil
	end

	-- Build item cards
	local items = shopData.items or {}
	local cardElements = {}
	cardElements["layout"] = React.createElement("UIGridLayout", {
		CellSize                = UDim2.fromScale(0.46, 0.3),
		CellPadding             = UDim2.fromScale(0.04, 0.04),
		FillDirection           = Enum.FillDirection.Horizontal,
		SortOrder               = Enum.SortOrder.LayoutOrder,
		FillDirectionMaxCells   = 2,
	})

	for i, item in ipairs(items) do
		cardElements["item_" .. i] = React.createElement("Frame", {
			BackgroundTransparency = 1,
			LayoutOrder = i,
		}, {
			card = React.createElement(ItemCard, {
				item   = item,
				npcId  = shopData.npcId,
				order  = i,
			}),
		})
	end

	local function closeShop()
		NetworkManager.FireServer("NPCResponse", {
			npcId  = shopData.npcId,
			action = "Close",
		})
		setShopData(nil)
		onClose()
	end

	return React.createElement("Frame", {
		Name = "ShopUI",
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = C.overlay,
		BackgroundTransparency = 0.45,
		BorderSizePixel = 0,
		ZIndex = 20,
	}, {
		panel = React.createElement("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.5, 0.5),
			Size = UDim2.fromScale(0.5, 0.55),
			BackgroundColor3 = C.panel,
			BorderSizePixel = 0,
		}, {
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.02, 0) }),
			pad = React.createElement("UIPadding", {
				PaddingLeft = UDim.new(0.03, 0), PaddingRight = UDim.new(0.03, 0),
				PaddingTop = UDim.new(0.03, 0), PaddingBottom = UDim.new(0.03, 0),
			}),

			-- Header
			header = React.createElement("TextLabel", {
				Size = UDim2.fromScale(0.8, 0.1),
				BackgroundTransparency = 1,
				Text = (shopData.npcName or "Shop"),
				TextColor3 = C.accent,
				Font = Enum.Font.GothamBold,
				TextScaled = true,
				TextXAlignment = Enum.TextXAlignment.Left,
			}),

			closeBtn = React.createElement("TextButton", {
				AnchorPoint = Vector2.new(1, 0),
				Position = UDim2.fromScale(1, 0),
				Size = UDim2.fromScale(0.06, 0.08),
				BackgroundTransparency = 1,
				Text = "✕",
				TextColor3 = C.text_dim,
				Font = Enum.Font.GothamBold,
				TextScaled = true,
				[React.Event.Activated] = closeShop,
			}),

			-- Item grid
			itemGrid = React.createElement("ScrollingFrame", {
				Position = UDim2.fromScale(0, 0.13),
				Size = UDim2.fromScale(1, 0.85),
				BackgroundTransparency = 1,
				ScrollBarThickness = 4,
				CanvasSize = UDim2.fromScale(0, 0),
				AutomaticCanvasSize = Enum.AutomaticSize.Y,
				BorderSizePixel = 0,
			}, cardElements),
		}),
	})
end

return ShopUI
