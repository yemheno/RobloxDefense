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
local useNpcDistanceClose = require(Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("UI"):WaitForChild("Common"):WaitForChild("useNpcDistanceClose"))  -- §AGX/X29
local NetworkManager = require(SharedModules:WaitForChild("NetworkManager"))
-- §AGX/UI-P4: inline request feedback (pending/ok/err + 4 s timeout)
local useRequest = require(Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("UI"):WaitForChild("Common"):WaitForChild("useRequest"))

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
	-- §AGX/UI-P4: the card's inline status is useRequest (was a local
	-- statusMsg + flashStatus timer fed by a ShopUI-level listener).
	-- Same behaviour: "Purchasing…" while pending, the server's
	-- ShopSuccess/ShopError message for 3 s. Results still arrive as
	-- NPCDialogue { type = "ShopSuccess"|"ShopError", npcId, message,
	-- itemId? } (ShopHandler.lua); ShopError has no itemId, so it goes
	-- to the card the player last clicked (props.getPendingItem), as
	-- before (§AGX/UX-03). New: no reply within 4 s shows an error
	-- instead of silently clearing (out of range / dropped request).
	local getPendingItem = props.getPendingItem
	local buy = useRequest("NPCResponse", {
		reply       = "NPCDialogue",
		pendingText = "Purchasing…",
		holdFor     = 3,
		timeout     = 4,
		match       = function(data, payload)
			if type(data) ~= "table" or type(payload) ~= "table" then return nil end
			if data.type ~= "ShopSuccess" and data.type ~= "ShopError" then return nil end
			if data.npcId ~= payload.npcId then return nil end
			local target = data.itemId or (getPendingItem and getPendingItem())
			if target ~= payload.itemId then return nil end
			local ok = data.type == "ShopSuccess"
			return ok, data.message or (ok and "Purchased!" or "Purchase failed.")
		end,
	})
	local statusMsg = (buy.state ~= "idle") and buy.message or nil
	local statusOk  = buy.state ~= "err"

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
			TextColor3 = statusOk and C.green or C.red,  -- §AGX/UX-03
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
				if props.onBuy then props.onBuy(item.id) end  -- §AGX/UX-03
				-- §AGX/UI-P4: fires NPCResponse and owns pending/timeout.
				buy.send({
					npcId  = npcId,
					action = "Buy",
					itemId = item.id,
				})
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
	-- §AGX/UI-P4: result routing moved into each card's useRequest; only
	-- the last-clicked item is kept here (ShopError carries no itemId).
	local pendingItemRef = React.useRef(nil)   -- item.id of the last Buy click
	local getPendingItem = React.useCallback(function() return pendingItemRef.current end, {})

	React.useEffect(function()
		local conns = {}

		conns[1] = NetworkManager.OnServerEvent("NPCShopOpen", function(data)
			-- data = { npcId, npcName, items = { { id, name, description, price, currency } } }
			setShopData(data)
		end)

		return function()
			for _, c in conns do
				if c then c:Disconnect() end
			end
		end
	end, {})

	-- §AGX/X29: the server now drops NPC responses from out of range, so
	-- close the panel when the player walks away (same as NPCDialog).
	useNpcDistanceClose(shopData and shopData.npcId, shopData ~= nil, function()
		setShopData(nil)
		onClose()
	end)

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
				-- §AGX/UI-P4: each card matches its own result (useRequest)
				getPendingItem = getPendingItem,
				onBuy  = function(itemId) pendingItemRef.current = itemId end,
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
