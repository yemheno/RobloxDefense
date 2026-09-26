-- UI/ShopUI.lua
--[[
    Shop overlay triggered by "NPCShopOpen" server event.
    
    Displays item cards with name, description, price, and a
    Buy button. Fires "NPCResponse" → { npcId, action = "Buy", itemId }.

    §AGX/UI-P6: AppWindow chrome, Card items, CurrencyPill prices, Button
    buys, design px under UIScaleRoot.Local.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local React             = require(ReplicatedStorage.Packages.React)

local SharedModules  = Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("Modules")
local useNpcDistanceClose = require(Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("UI"):WaitForChild("Common"):WaitForChild("useNpcDistanceClose"))  -- §AGX/X29
local NetworkManager = require(SharedModules:WaitForChild("NetworkManager"))
-- §AGX/UI-P4: inline request feedback (pending/ok/err + 4 s timeout)
local useRequest = require(Players.LocalPlayer:WaitForChild("PlayerScripts"):WaitForChild("UI"):WaitForChild("Common"):WaitForChild("useRequest"))
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

-- §AGX/UI-P6: shared components.
local Common       = PlayerScripts_UI:WaitForChild("Common")
local Theme        = require(Common:WaitForChild("Theme"))
local AppWindow    = require(Common:WaitForChild("AppWindow"))
local UIScaleRoot  = require(Common:WaitForChild("UIScaleRoot"))
local Text         = require(Common:WaitForChild("Text"))
local Button       = require(Common:WaitForChild("Button"))
local Card         = require(Common:WaitForChild("Card"))
local CurrencyPill = require(Common:WaitForChild("CurrencyPill"))

local e  = React.createElement
local R  = Theme.Roles
local SP = Theme.Space

-- NPC item currency -> CurrencyPill key.
local PILL_CURRENCY = { Merits = "merits", Essence = "essence" }
local BUY_W = 104   -- design px

-- ── Item Card ─────────────────────────────────────────────
local function ItemCard(props)
	local item = props.item
	local npcId = props.npcId
	-- §AGX/UI-P4, §AGX/UX-03: the card's inline status is useRequest:
	-- "Purchasing…" while pending, the server's ShopSuccess/ShopError message
	-- for 3 s. Results arrive as NPCDialogue { type = "ShopSuccess"|"ShopError",
	-- npcId, message, itemId? } (NPCManager ShopHandler); ShopError has no
	-- itemId, so it goes to the card the player last clicked
	-- (props.getPendingItem). No reply within 4 s shows an error (out of
	-- range / dropped request) instead of silently clearing.
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

	-- §AGX/UI-P6: price via CurrencyPill (text fallback for other currencies).
	local currency = item.currency or "Essence"
	local pillKey = PILL_CURRENCY[currency]
	local price = pillKey and e(CurrencyPill, {
		currency = pillKey, value = item.price or 0, cost = true, layoutOrder = 1,
	}) or e(Text, {
		style = "numeric", color = "text.secondary", autoSize = "X", layoutOrder = 1,
		size  = UDim2.fromOffset(0, Theme.Metrics.pill.height),
		text  = tostring(item.price or 0) .. " " .. currency,
	})

	-- §AGX/UI-P6: Card (name / description) + footer (status, price, Buy).
	return e(Card, {
		title       = item.name or item.id or "???",
		subtitle    = (item.description and item.description ~= "") and item.description or nil,
		layoutOrder = props.order,
		footer      = e("Frame", {
			Size                   = UDim2.new(1, 0, 0, Theme.Metrics.button.sm),
			BackgroundTransparency = 1,
		}, {
			-- Status message (after buy attempt)  §AGX/UX-03 colours
			status = statusMsg and e(Text, {
				style = "caption",
				text  = statusMsg,
				color = statusOk and "state.success" or "state.danger",
				size  = UDim2.new(1, -(BUY_W + 120), 1, 0),
			}) or nil,
			right = e("Frame", {
				AnchorPoint            = Vector2.new(1, 0),
				Position               = UDim2.fromScale(1, 0),
				Size                   = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
			}, {
				layout = e("UIListLayout", {
					FillDirection       = Enum.FillDirection.Horizontal,
					HorizontalAlignment = Enum.HorizontalAlignment.Right,
					VerticalAlignment   = Enum.VerticalAlignment.Center,
					SortOrder           = Enum.SortOrder.LayoutOrder,
					Padding             = UDim.new(0, SP.md),
				}),
				price = price,
				buy = e(Button, {
					name        = "BuyBtn",
					variant     = "secondary",
					size        = "sm",
					width       = BUY_W,
					label       = "Buy",
					layoutOrder = 2,
					onActivated = function()
						if props.onBuy then props.onBuy(item.id) end  -- §AGX/UX-03
						-- §AGX/UI-P4: fires NPCResponse and owns pending/timeout.
						buy.send({
							npcId  = npcId,
							action = "Buy",
							itemId = item.id,
						})
					end,
				}),
			}),
		}),
	})
end

-- ── Main Component ────────────────────────────────────────
local function ShopUI(props)
	local onClose = props.onClose or function() end

	local shopData, setShopData = React.useState(nil)
	-- §AGX/UI-P4: result routing lives in each card's useRequest; only
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

	-- §AGX/UI-P3: one close helper, defined before the early return so the
	-- stack (useExternal) can call it. Fires NPCResponse Close.
	local shopDataRef = React.useRef(nil)
	shopDataRef.current = shopData
	local function closeShop()
		local data = shopDataRef.current
		if data then
			NetworkManager.FireServer("NPCResponse", {
				npcId  = data.npcId,
				action = "Close",
			})
		end
		setShopData(nil)
		onClose()
	end

	-- §AGX/X29, §AGX/UI-P3: the server drops NPC responses from out of range,
	-- so close the panel when the player walks away; this path also sends
	-- NPCResponse Close (UX-17, same as NPCDialog).
	useNpcDistanceClose(shopData and shopData.npcId, shopData ~= nil, closeShop)

	-- §AGX/UI-P3: A10, register with the PanelStack (replaces / is replaced).
	useExternal("npcShop", shopData ~= nil, closeShop)

	if not shopData then
		return nil
	end

	-- Build item cards
	local items = shopData.items or {}
	local cardElements = {
		layout = e("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding   = UDim.new(0, SP.sm),
		}),
		padding = e("UIPadding", {
			PaddingLeft = UDim.new(0, SP.lg), PaddingRight = UDim.new(0, SP.lg),
			PaddingTop = UDim.new(0, SP.md), PaddingBottom = UDim.new(0, SP.lg),
		}),
	}

	for i, item in ipairs(items) do
		cardElements["item_" .. i] = e(ItemCard, {
			item   = item,
			npcId  = shopData.npcId,
			order  = i,
			-- §AGX/UI-P4: each card matches its own result (useRequest)
			getPendingItem = getPendingItem,
			onBuy  = function(itemId) pendingItemRef.current = itemId end,
		})
	end

	-- §AGX/UI-P6: AppWindow chrome (auto: sheet on phone; the shell's
	-- presentation wins). Its panel is Active (UX-14). ✕ = closeShop.
	local z = Theme.Z.windowOver
	return e(AppWindow, {
		variant = "auto",
		title   = shopData.npcName or "Shop",
		icon    = "shop",
		onClose = function() closeShop() end,
		size    = UDim2.fromScale(0.5, 0.62),
		minSize = Vector2.new(480, 380),
		zIndex  = z,
	}, {
		scaled = e(UIScaleRoot.Local, { name = "ShopBody", zIndex = z + 2 }, {
			-- Item list
			itemGrid = e("ScrollingFrame", {
				Name                   = "Items",
				Size                   = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				BorderSizePixel        = 0,
				ScrollBarThickness     = Theme.Metrics.scrollBar,
				ScrollBarImageColor3   = R.text.secondary,
				CanvasSize             = UDim2.fromScale(0, 0),
				AutomaticCanvasSize    = Enum.AutomaticSize.Y,
				ScrollingDirection     = Enum.ScrollingDirection.Y,
				ZIndex                 = z + 2,
			}, cardElements),
		}),
	})
end

return ShopUI
