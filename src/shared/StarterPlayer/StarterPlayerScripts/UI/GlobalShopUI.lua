-- UI/GlobalShopUI.lua
--[[
    3-tab Shop panel: Cosmetics, Consumables, Premium.
    Reads ShopConfig for catalog, ConsumableConfig / CosmeticConfig for display info.
    Fires "ShopPurchase" { tab, itemId, quantity } to server.
    Listens for "ShopResult" (ok, message) and "ShopState" (merits, essence, level, owned).

    §AGX/UI-P6: Theme v2 re-skin. AppWindow chrome (auto: sheet on phone),
    Tabs, Card items, CurrencyPill balances/prices, Button buys. The private
    palette, the hand-rolled backdrop/close/tabs/cards and formatCurrency are
    gone (CurrencyPill formats).

    Props:
      onClose  function  — callback to close the panel
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players           = game:GetService("Players")
local React             = require(ReplicatedStorage.Packages.React)

local Shared          = ReplicatedStorage:WaitForChild("Shared")
local ShopConfig      = require(Shared:WaitForChild("ShopConfig"))
local ConsumableConfig = require(Shared:WaitForChild("ConsumableConfig"))

local PlayerScripts  = Players.LocalPlayer:WaitForChild("PlayerScripts")
local SharedModules  = PlayerScripts:WaitForChild("Modules")
local NetworkManager = require(SharedModules:WaitForChild("NetworkManager"))

-- §AGX/UI-P6: shared components.
local Common       = script.Parent:WaitForChild("Common")
local Theme        = require(Common:WaitForChild("Theme"))
local AppWindow    = require(Common:WaitForChild("AppWindow"))
local UIScaleRoot  = require(Common:WaitForChild("UIScaleRoot"))
local Text         = require(Common:WaitForChild("Text"))
local Button       = require(Common:WaitForChild("Button"))
local Card         = require(Common:WaitForChild("Card"))
local Tabs         = require(Common:WaitForChild("Tabs"))
local CurrencyPill = require(Common:WaitForChild("CurrencyPill"))

-- CosmeticConfig lives in ServerScriptService/Modules (server-only) and is not
-- accessible from the client. The shop uses ShopConfig display info as fallback.
-- We check via FindFirstChild so the IDE does not flag a missing path.
local CosmeticConfig = nil
do
	local m = Shared:FindFirstChild("CosmeticConfig")
	if m then
		local ok, cfg = pcall(require, m)
		if ok then CosmeticConfig = cfg end
	end
end

local e  = React.createElement
local R  = Theme.Roles
local SP = Theme.Space

local TAB_ITEMS = {
	{ id = "Cosmetics",   label = "Cosmetics" },
	{ id = "Consumables", label = "Consumables" },
	{ id = "Premium",     label = "Premium" },
}

-- ShopConfig currency -> CurrencyPill key (Robux has no pill: not a game currency).
local PILL_CURRENCY = { Merits = "merits", Essence = "essence" }

local STATUS_H = 24   -- design px

-- ═══════════════════════════════════════════════════════════
-- ITEM CARD  (§AGX/UI-P6: Card + CurrencyPill + Button)
-- ═══════════════════════════════════════════════════════════

local function ShopItemCard(props)
	local entry     = props.entry       -- ShopConfig entry
	local itemInfo  = props.itemInfo    -- { name, desc, icon, rarity? }
	local isOwned   = props.isOwned
	local playerLvl = props.playerLevel or 1
	local onBuy     = props.onBuy
	local balances  = props.balances or {}

	local name     = itemInfo and itemInfo.name or entry.itemId
	local desc     = itemInfo and itemInfo.desc or ""
	local icon     = itemInfo and itemInfo.icon or "📦"
	local rarity   = itemInfo and itemInfo.rarity
	local locked   = entry.levelReq and playerLvl < entry.levelReq

	local pillKey = PILL_CURRENCY[entry.currency]
	local price
	if pillKey then
		price = e(CurrencyPill, {
			currency     = pillKey,
			value        = entry.price or 0,
			cost         = true,
			insufficient = (not isOwned) and (balances[pillKey] or 0) < (entry.price or 0),
			layoutOrder  = 1,
		})
	else
		price = e(Text, {
			style = "numeric", color = "text.secondary", autoSize = "X",
			size  = UDim2.fromOffset(0, Theme.Metrics.pill.height),
			text  = tostring(entry.price) .. " " .. (entry.currency or ""),
			layoutOrder = 1,
		})
	end

	local btnLabel, btnVariant
	if isOwned then
		btnLabel, btnVariant = "Owned", "locked"
	elseif locked then
		btnLabel, btnVariant = "Lv " .. entry.levelReq, "locked"
	else
		btnLabel, btnVariant = "Buy", "secondary"
	end

	return e(Card, {
		-- The config icons are emoji: they lead the title instead of a thumbnail.
		title       = icon .. "  " .. name,
		subtitle    = desc ~= "" and desc or nil,
		rarity      = rarity and string.lower(rarity) or nil,
		badge       = isOwned and "Owned" or nil,
		locked      = locked or nil,
		layoutOrder = props.order or 0,
		footer      = e("Frame", {
			Size                   = UDim2.new(1, 0, 0, Theme.Metrics.button.sm),
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
				variant     = btnVariant,
				size        = "sm",
				width       = 104,
				label       = btnLabel,
				layoutOrder = 2,
				onActivated = function()
					if not isOwned and not locked and onBuy then
						onBuy()
					end
				end,
			}),
		}),
	})
end

-- ═══════════════════════════════════════════════════════════
-- MAIN SHOP UI
-- ═══════════════════════════════════════════════════════════

local function GlobalShopUI(props)
	local onClose = props.onClose

	local activeTab, setActiveTab = React.useState("Cosmetics")
	local status, setStatus = React.useState(nil)   -- { text, ok }

	-- Server state
	local shopState, setShopState = React.useState({
		merits = 0, essence = 0, level = 1, owned = {},
	})

	-- Request state on mount
	React.useEffect(function()
		local mounted = true
		NetworkManager.FireServer("GetShopState")

		local conn1 = NetworkManager.OnServerEvent("ShopState", function(data)
			if data then setShopState(data) end
		end)

		local conn2 = NetworkManager.OnServerEvent("ShopResult", function(data)
			if data then
				setStatus({
					text = data.message or (data.ok and "Success!" or "Failed."),
					ok   = data.ok ~= false,
				})
				-- Refresh state
				NetworkManager.FireServer("GetShopState")
				-- Clear after 3s
				task.delay(3, function() if mounted then setStatus(nil) end end)
			end
		end)

		return function()
			mounted = false
			if conn1 then conn1:Disconnect() end
			if conn2 then conn2:Disconnect() end
		end
	end, {})

	-- ── Build item list for the active tab ─────────────────
	local children = {
		layout = e("UIListLayout", {
			SortOrder = Enum.SortOrder.LayoutOrder,
			Padding   = UDim.new(0, SP.sm),
		}),
		padding = e("UIPadding", {
			PaddingLeft = UDim.new(0, SP.lg), PaddingRight = UDim.new(0, SP.lg),
			PaddingTop = UDim.new(0, SP.sm), PaddingBottom = UDim.new(0, SP.lg),
		}),
	}

	local balances = { merits = shopState.merits or 0, essence = shopState.essence or 0 }
	local owned = shopState.owned or {}

	local entries = ShopConfig.GetTab(activeTab)
	for i, entry in ipairs(entries) do
		-- Skip items that have been explicitly disabled in ShopConfig
		if entry.enabled == false then continue end

		-- Resolve display info
		local itemInfo = nil
		if activeTab == "Cosmetics" then
			if CosmeticConfig then
				itemInfo = CosmeticConfig.GetCosmetic(entry.itemId)
			end
			-- Fallback
			if not itemInfo then
				itemInfo = { name = entry.itemId, desc = "", icon = "👕" }
			end
		elseif activeTab == "Consumables" then
			itemInfo = ConsumableConfig.GetById(entry.itemId)
			if not itemInfo then
				itemInfo = { name = entry.itemId, desc = "", icon = "📦" }
			end
		elseif activeTab == "Premium" then
			-- Premium items have inline display info
			itemInfo = {
				name  = entry.name or entry.itemId,
				desc  = entry.desc or "",
				icon  = entry.icon or "💎",
			}
		end

		local isOwned = false
		if activeTab == "Cosmetics" then
			isOwned = owned[entry.itemId] == true
		end

		children["item_" .. i] = e(ShopItemCard, {
			entry       = entry,
			itemInfo    = itemInfo,
			isOwned     = isOwned,
			playerLevel = shopState.level,
			balances    = balances,
			order       = i,
			onBuy       = function()
				local qty = (activeTab == "Consumables") and 1 or nil
				NetworkManager.FireServer("ShopPurchase", activeTab, entry.itemId, qty)
			end,
		})
	end

	local tabsH = Theme.Metrics.tabs.height
	local listTop = tabsH + (status and STATUS_H + SP.xs or 0)
	local z = Theme.Z.window

	-- ── Render ─────────────────────────────────────────────
	return e(AppWindow, {
		variant = "auto",
		title   = "Shop",
		icon    = "shop",
		onClose = onClose,
		size    = UDim2.fromScale(0.55, 0.78),
		minSize = Vector2.new(520, 420),
		zIndex  = z,
		-- Balances: CurrencyPill in the header slot (right-aligned).
		headerContent = e("Frame", {
			Size                   = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
		}, {
			layout = e("UIListLayout", {
				FillDirection       = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Right,
				VerticalAlignment   = Enum.VerticalAlignment.Center,
				SortOrder           = Enum.SortOrder.LayoutOrder,
				Padding             = UDim.new(0, SP.sm),
			}),
			merits  = e(CurrencyPill, { currency = "merits",  value = balances.merits,  compact = true, layoutOrder = 1 }),
			essence = e(CurrencyPill, { currency = "essence", value = balances.essence, compact = true, layoutOrder = 2 }),
		}),
	}, {
		scaled = e(UIScaleRoot.Local, { name = "ShopBody", zIndex = z + 2 }, {
			tabs = e(Tabs, {
				items    = TAB_ITEMS,
				value    = activeTab,
				onChange = setActiveTab,
				zIndex   = z + 2,
			}),
			-- Status message
			status = status and e(Text, {
				style    = "label",
				text     = status.text,
				color    = status.ok and "state.success" or "state.danger",
				align    = "center",
				position = UDim2.fromOffset(0, tabsH + SP.xs),
				size     = UDim2.new(1, 0, 0, STATUS_H),
				zIndex   = z + 2,
			}) or nil,
			-- Scrolling item list
			list = e("ScrollingFrame", {
				Name                   = "Items",
				Position               = UDim2.fromOffset(0, listTop),
				Size                   = UDim2.new(1, 0, 1, -listTop),
				BackgroundTransparency = 1,
				BorderSizePixel        = 0,
				ScrollBarImageColor3   = R.text.secondary,
				ScrollBarThickness     = Theme.Metrics.scrollBar,
				CanvasSize             = UDim2.fromScale(0, 0), -- auto-sized
				AutomaticCanvasSize    = Enum.AutomaticSize.Y,
				ScrollingDirection     = Enum.ScrollingDirection.Y,
				ZIndex                 = z + 2,
			}, children),
		}),
	})
end

return GlobalShopUI
