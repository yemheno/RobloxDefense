-- UI/GlobalShopUI.lua
--[[
    3-tab Shop panel: Cosmetics, Consumables, Premium.
    Reads ShopConfig for catalog, ConsumableConfig / CosmeticConfig for display info.
    Fires "ShopPurchase" { tab, itemId, quantity } to server.
    Listens for "ShopResult" (ok, message) and "ShopState" (merits, essence, level, owned).

    §AGX/UI-P6: AppWindow chrome (auto: sheet on phone), Tabs, Card items,
    CurrencyPill balances/prices (CurrencyPill formats), Button buys.

    §AGX/D7: rotating tabs (ShopConfig.Rotation) show their staples plus the
    player's current server-drawn rotation (ShopState.rotation[tab]). A bar
    under the tabs shows "Rotates in hh:mm" and a SECONDARY "Refresh (N ◆)"
    button (D1: orange stays for a view's one primary CTA; this is a sink,
    not the main action). Refresh = two taps (arm, then confirm within 4 s)
    and fires "ShopRefresh" { tab, period, roll } via useRequest; the server
    answers with NotifyService.Inline and a fresh ShopState.

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
local useRequest   = require(Common:WaitForChild("useRequest"))  -- §AGX/D7

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
local ROT_H    = Theme.Metrics.button.sm   -- §AGX/D7: rotation bar height (44)
local REFRESH_W = 168     -- §AGX/D7: design px, fits "Confirm (20 ◆)"
local CONFIRM_WINDOW = 4  -- §AGX/D7: s the armed "Confirm" stays up
local REFETCH_GAP = 5     -- §AGX/D7: s between expiry re-requests

-- §AGX/D7: seconds → "hh:mm" (minutes rounded up, so 59 s reads 00:01).
local function formatHHMM(seconds)
	local mins = math.max(0, math.ceil(seconds / 60))
	return string.format("%02d:%02d", math.floor(mins / 60), mins % 60)
end

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

	-- §AGX/D7: rotation countdown. `receivedAt` = os.clock() when the last
	-- ShopState landed (endsIn is relative to it); `now` ticks once a second.
	local receivedAt, setReceivedAt = React.useState(os.clock())
	local now, setNow = React.useState(os.clock())
	local armedTab, setArmedTab = React.useState(nil)   -- two-tap confirm
	local stateRef = React.useRef(nil)
	stateRef.current = { state = shopState, receivedAt = receivedAt }

	-- §AGX/D7: paid refresh feedback (NotifyService.Inline "ShopRefresh",
	-- the InventoryUI Use pattern).
	local refreshReq = useRequest("ShopRefresh", {
		pendingText = "Refreshing…",
		holdFor     = 3,
	})

	React.useEffect(function()
		local alive = true
		local lastRefetch = 0
		local thread = task.spawn(function()
			while alive do
				task.wait(1)
				if not alive then break end
				local t = os.clock()
				setNow(t)
				-- A tab's rotation ran out: ask for the new one (throttled).
				local cur = stateRef.current
				local rot = cur and cur.state and cur.state.rotation
				if type(rot) == "table" and (t - lastRefetch) >= REFETCH_GAP then
					for _, info in pairs(rot) do
						if type(info) == "table" and type(info.endsIn) == "number"
							and info.endsIn - (t - cur.receivedAt) <= -1 then
							lastRefetch = t
							NetworkManager.FireServer("GetShopState")
							break
						end
					end
				end
			end
		end)
		return function()
			alive = false
			if coroutine.status(thread) == "suspended" then task.cancel(thread) end
		end
	end, {})

	-- §AGX/D7: disarm the confirm tap after CONFIRM_WINDOW.
	React.useEffect(function()
		if not armedTab then return nil end
		local thread = task.delay(CONFIRM_WINDOW, function() setArmedTab(nil) end)
		return function()
			if coroutine.status(thread) == "suspended" then task.cancel(thread) end
		end
	end, { armedTab })

	-- Request state on mount
	React.useEffect(function()
		local mounted = true
		NetworkManager.FireServer("GetShopState")

		local conn1 = NetworkManager.OnServerEvent("ShopState", function(data)
			if data and mounted then
				setShopState(data)
				setReceivedAt(os.clock())  -- §AGX/D7: countdown base
			end
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

	-- §AGX/D7: rotating tab → staples + this player's current rotation.
	-- Until the first ShopState arrives only staples show (server decides).
	local rotCfg  = ShopConfig.GetRotation(activeTab)
	local rotInfo = rotCfg and shopState.rotation and shopState.rotation[activeTab] or nil
	local inRotation = {}
	if rotInfo and type(rotInfo.items) == "table" then
		for _, id in ipairs(rotInfo.items) do inRotation[id] = true end
	end

	local entries = ShopConfig.GetTab(activeTab)
	for i, entry in ipairs(entries) do
		-- Skip items that have been explicitly disabled in ShopConfig
		if entry.enabled == false then continue end
		-- §AGX/D7: skip rotating items that aren't in stock for this player.
		if rotCfg and not entry.staple and not inRotation[entry.itemId] then continue end

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
	local z = Theme.Z.window

	-- §AGX/D7: rotation bar ("Rotates in hh:mm" + secondary Refresh).
	local rotBar = nil
	local rotH = 0
	if rotCfg then
		rotH = ROT_H + SP.xs
		local refresh   = shopState.refresh or {}
		local price     = refresh.price           -- nil = daily cap reached
		local remaining = rotInfo and (rotInfo.endsIn - (now - receivedAt)) or nil
		local armed     = armedTab == activeTab
		local essence   = shopState.essence or 0

		local label, variant, tip = "Refresh", "secondary", nil
		if not rotInfo then
			variant = "locked"
		elseif not price then
			label, variant, tip = "No refreshes left", "locked", "Resets at 00:00 UTC."
		elseif not rotInfo.canRefresh then
			label, variant, tip = "Refresh", "locked", "Nothing to refresh, or the free rotation is under 5 min away."
		elseif essence < price then
			label, variant, tip = "Refresh (" .. price .. " " .. Theme.Glyphs.essence .. ")", "locked", "Not enough Essence."
		else
			label = (armed and "Confirm (" or "Refresh (") .. price .. " " .. Theme.Glyphs.essence .. ")"
			tip   = (refresh.used or 0) .. " / " .. (refresh.cap or 0) .. " refreshes used today. New stock now; the timer doesn't reset."
		end

		rotBar = e("Frame", {
			Name                   = "RotationBar",
			Position               = UDim2.fromOffset(0, tabsH + SP.xs),
			Size                   = UDim2.new(1, 0, 0, ROT_H),
			BackgroundTransparency = 1,
			ZIndex                 = z + 2,
		}, {
			padding = e("UIPadding", {
				PaddingLeft = UDim.new(0, SP.lg), PaddingRight = UDim.new(0, SP.lg),
			}),
			timer = e(Text, {
				style  = "label",
				color  = "text.secondary",
				text   = remaining and ("Rotates in " .. formatHHMM(remaining)) or "Loading stock…",
				size   = UDim2.new(1, -(REFRESH_W + SP.md), 1, 0),
				zIndex = z + 2,
			}),
			refresh = e(Button, {
				name        = "RefreshBtn",
				variant     = variant,
				size        = "sm",
				width       = REFRESH_W,
				label       = label,
				tooltip     = tip,
				loading     = refreshReq.pending,
				anchorPoint = Vector2.new(1, 0),
				position    = UDim2.fromScale(1, 0),
				zIndex      = z + 2,
				onActivated = function()
					if variant ~= "secondary" or not rotInfo then return end
					if not armed then
						setArmedTab(activeTab)
						return
					end
					setArmedTab(nil)
					refreshReq.send({
						tab    = activeTab,
						period = rotInfo.period,
						roll   = rotInfo.roll,
					})
				end,
			}),
		})
	end

	-- Status: the refresh request's inline answer wins while it's showing.
	local shownStatus = status
	if refreshReq.state ~= "idle" and refreshReq.message then
		shownStatus = { text = refreshReq.message, ok = refreshReq.state ~= "err", pending = refreshReq.pending }
	end
	local statusTop = tabsH + rotH + SP.xs
	local listTop = tabsH + rotH + (shownStatus and STATUS_H + SP.xs or 0)

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
				onChange = function(id)
					setArmedTab(nil)  -- §AGX/D7: never carry an armed refresh across tabs
					setActiveTab(id)
				end,
				zIndex   = z + 2,
			}),
			rotation = rotBar,  -- §AGX/D7
			-- Status message
			status = shownStatus and e(Text, {
				style    = "label",
				text     = shownStatus.text,
				color    = shownStatus.pending and "text.secondary"
					or (shownStatus.ok and "state.success" or "state.danger"),
				align    = "center",
				position = UDim2.fromOffset(0, statusTop),
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
