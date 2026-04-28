-- UI/GlobalShopUI.lua
--[[
    3-tab Shop panel: Cosmetics, Consumables, Premium.
    Reads ShopConfig for catalog, ConsumableConfig / CosmeticConfig for display info.
    Fires "ShopPurchase" { tab, itemId, quantity } to server.
    Listens for "ShopResult" (ok, message) and "ShopState" (merits, essence, level, owned).

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

-- §U1 fix: strata-aware currency formatter so the shop bar doesn't
-- overflow at late-game balances. Mirrors UIUtils.formatCurrency in
-- the AppGui controllers; inlined here because StarterPlayerScripts
-- and StarterGui have separate require roots.
local function formatCurrency(n)
    n = tonumber(n) or 0
    if n >= 1e12 then return string.format("%.2fT", n / 1e12) end
    if n >= 1e9  then return string.format("%.2fB", n / 1e9 ) end
    if n >= 1e6  then return string.format("%.2fM", n / 1e6 ) end
    if n >= 1e4  then return string.format("%.1fk", n / 1e3 ) end
    -- 0–9999 with comma separators
    local s = tostring(math.floor(n))
    if #s <= 3 then return s end
    local result = ""
    local len = #s
    for i = 1, len do
        if i > 1 and (len - i + 1) % 3 == 0 then
            result = result .. ","
        end
        result = result .. s:sub(i, i)
    end
    return result
end

-- ── Colors ─────────────────────────────────────────────────
local C = {
    bg         = Color3.fromRGB( 18,  18,  24),
    panel      = Color3.fromRGB( 26,  26,  38),
    card       = Color3.fromRGB( 32,  32,  46),
    card_owned = Color3.fromRGB( 26,  40,  32),
    accent     = Color3.fromRGB(105, 190, 255),
    green      = Color3.fromRGB( 50, 170,  80),
    red        = Color3.fromRGB(170,  50,  50),
    yellow     = Color3.fromRGB(255, 210,  60),
    orange     = Color3.fromRGB(255, 160,  50),
    text       = Color3.fromRGB(220, 220, 230),
    text_dim   = Color3.fromRGB(140, 140, 160),
    white      = Color3.fromRGB(255, 255, 255),
    tab_active = Color3.fromRGB( 60,  80, 120),
    tab_inactive = Color3.fromRGB( 30,  30,  42),
}

local RARITY_COLORS = {
    Common    = Color3.fromRGB(200, 200, 200),
    Uncommon  = Color3.fromRGB( 80, 200,  80),
    Rare      = Color3.fromRGB( 60, 120, 255),
    Epic      = Color3.fromRGB(180,  60, 255),
    Legendary = Color3.fromRGB(255, 180,  40),
}

local CURRENCY_COLORS = {
    Merits  = Color3.fromRGB(255, 210,  60),
    Essence = Color3.fromRGB(105, 190, 255),
    Robux   = Color3.fromRGB( 50, 200,  80),
}

-- ═══════════════════════════════════════════════════════════
-- ITEM CARD
-- ═══════════════════════════════════════════════════════════

local function ShopItemCard(props)
    local entry     = props.entry       -- ShopConfig entry
    local itemInfo  = props.itemInfo    -- { name, desc, icon, rarity? }
    local isOwned   = props.isOwned
    local playerLvl = props.playerLevel or 1
    local onBuy     = props.onBuy

    local name     = itemInfo and itemInfo.name or entry.itemId
    local desc     = itemInfo and itemInfo.desc or ""
    local icon     = itemInfo and itemInfo.icon or "📦"
    local rarity   = itemInfo and itemInfo.rarity
    local locked   = entry.levelReq and playerLvl < entry.levelReq

    local bgColor  = isOwned and C.card_owned or C.card
    local priceColor = CURRENCY_COLORS[entry.currency] or C.yellow

    local btnText, btnColor
    if isOwned then
        btnText, btnColor = "Owned", C.text_dim
    elseif locked then
        btnText, btnColor = "Lv " .. entry.levelReq, C.red
    else
        btnText, btnColor = "Buy", C.green
    end

    return React.createElement("Frame", {
        Size             = UDim2.new(1, 0, 0, 90),
        BackgroundColor3 = bgColor,
        BorderSizePixel  = 0,
        LayoutOrder      = props.order or 0,
    }, {
        corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 8) }),
        pad = React.createElement("UIPadding", {
            PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10),
            PaddingTop = UDim.new(0, 6), PaddingBottom = UDim.new(0, 6),
        }),

        -- Icon
        iconLabel = React.createElement("TextLabel", {
            Position             = UDim2.fromScale(0, 0.1),
            Size                 = UDim2.fromScale(0.08, 0.80),
            BackgroundTransparency = 1,
            Text = icon,
            TextScaled = true,
        }),

        -- Name (with rarity color)
        nameLabel = React.createElement("TextLabel", {
            Position               = UDim2.fromScale(0.10, 0.05),
            Size                   = UDim2.fromScale(0.50, 0.40),
            BackgroundTransparency = 1,
            Text       = name,
            TextColor3 = rarity and RARITY_COLORS[rarity] or C.text,
            Font       = Enum.Font.GothamBold,
            TextScaled = true,
            TextXAlignment = Enum.TextXAlignment.Left,
        }),

        -- Description
        descLabel = React.createElement("TextLabel", {
            Position               = UDim2.fromScale(0.10, 0.48),
            Size                   = UDim2.fromScale(0.55, 0.45),
            BackgroundTransparency = 1,
            Text       = desc,
            TextColor3 = C.text_dim,
            Font       = Enum.Font.Gotham,
            TextScaled = true,
            TextXAlignment = Enum.TextXAlignment.Left,
            TextYAlignment = Enum.TextYAlignment.Top,
            TextWrapped = true,
        }),

        -- Price
        priceLabel = React.createElement("TextLabel", {
            Position               = UDim2.fromScale(0.66, 0.05),
            Size                   = UDim2.fromScale(0.18, 0.40),
            BackgroundTransparency = 1,
            Text       = tostring(entry.price) .. " " .. (entry.currency or ""),
            TextColor3 = priceColor,
            Font       = Enum.Font.GothamBold,
            TextScaled = true,
        }),

        -- Buy button
        buyBtn = React.createElement("TextButton", {
            Position         = UDim2.fromScale(0.82, 0.15),
            Size             = UDim2.fromScale(0.16, 0.70),
            BackgroundColor3 = btnColor,
            BorderSizePixel  = 0,
            Text     = btnText,
            TextColor3 = C.white,
            Font     = Enum.Font.GothamBold,
            TextScaled = true,
            Active   = not isOwned and not locked,
            [React.Event.Activated] = function()
                if not isOwned and not locked and onBuy then
                    onBuy()
                end
            end,
        }, {
            corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.2, 0) }),
        }),
    })
end

-- ═══════════════════════════════════════════════════════════
-- TAB BUTTON
-- ═══════════════════════════════════════════════════════════

local function TabButton(props)
    local isActive = props.isActive
    return React.createElement("TextButton", {
        Size             = UDim2.fromScale(1 / 3, 1),
        BackgroundColor3 = isActive and C.tab_active or C.tab_inactive,
        BorderSizePixel  = 0,
        Text             = props.label,
        TextColor3       = isActive and C.accent or C.text_dim,
        Font             = Enum.Font.GothamBold,
        TextScaled       = true,
        LayoutOrder      = props.order,
        [React.Event.Activated] = props.onActivate,
    }, {
        corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.15, 0) }),
    })
end

-- ═══════════════════════════════════════════════════════════
-- MAIN SHOP UI
-- ═══════════════════════════════════════════════════════════

local function GlobalShopUI(props)
    local onClose = props.onClose

    local activeTab, setActiveTab = React.useState("Cosmetics")
    local statusMsg, setStatusMsg = React.useState(nil)

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
                setStatusMsg(data.message or (data.ok and "Success!" or "Failed."))
                -- Refresh state
                NetworkManager.FireServer("GetShopState")
                -- Clear after 3s
                task.delay(3, function() if mounted then setStatusMsg(nil) end end)
            end
        end)

        return function()
            mounted = false
            if conn1 then conn1:Disconnect() end
            if conn2 then conn2:Disconnect() end
        end
    end, {})

    -- ── Build item list for the active tab ─────────────────
    local children = {}

    -- List layout
    children["layout"] = React.createElement("UIListLayout", {
        SortOrder = Enum.SortOrder.LayoutOrder,
        Padding   = UDim.new(0, 6),
    })

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
            isOwned = shopState.owned[entry.itemId] == true
        end

        children["item_" .. i] = React.createElement(ShopItemCard, {
            entry       = entry,
            itemInfo    = itemInfo,
            isOwned     = isOwned,
            playerLevel = shopState.level,
            order       = i,
            onBuy       = function()
                local qty = (activeTab == "Consumables") and 1 or nil
                NetworkManager.FireServer("ShopPurchase", activeTab, entry.itemId, qty)
            end,
        })
    end

    -- ── Render ─────────────────────────────────────────────
    return React.createElement("Frame", {
        Name                   = "ShopBackdrop",
        Size                   = UDim2.fromScale(1, 1),
        BackgroundColor3       = Color3.fromRGB(0, 0, 0),
        BackgroundTransparency = 0.42,
        ZIndex                 = 10,
    }, {
        panel = React.createElement("Frame", {
            Name             = "ShopPanel",
            AnchorPoint      = Vector2.new(0.5, 0.5),
            Position         = UDim2.fromScale(0.5, 0.5),
            Size             = UDim2.fromScale(0.55, 0.75),
            BackgroundColor3 = C.bg,
            BorderSizePixel  = 0,
            ZIndex           = 11,
        }, {
            corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.015, 0) }),

            -- Title
            title = React.createElement("TextLabel", {
                Position               = UDim2.fromScale(0.03, 0.015),
                Size                   = UDim2.fromScale(0.50, 0.06),
                BackgroundTransparency = 1,
                Text       = "🛒  Shop",
                TextColor3 = C.text,
                Font       = Enum.Font.GothamBold,
                TextScaled = true,
                TextXAlignment = Enum.TextXAlignment.Left,
                ZIndex = 12,
            }),

            -- Currency display
            currencyBar = React.createElement("TextLabel", {
                Position               = UDim2.fromScale(0.45, 0.015),
                Size                   = UDim2.fromScale(0.40, 0.06),
                BackgroundTransparency = 1,
                Text       = "🪙 " .. formatCurrency(shopState.merits) .. "   💎 " .. formatCurrency(shopState.essence),
                TextColor3 = C.yellow,
                Font       = Enum.Font.GothamBold,
                TextScaled = true,
                ZIndex = 12,
            }),

            -- Close button
            close = React.createElement("TextButton", {
                Position         = UDim2.fromScale(0.92, 0.01),
                Size             = UDim2.fromScale(0.06, 0.06),
                BackgroundColor3 = C.red,
                BorderSizePixel  = 0,
                Text     = "✕",
                TextColor3 = C.white,
                Font     = Enum.Font.GothamBold,
                TextScaled = true,
                ZIndex = 12,
                [React.Event.Activated] = onClose,
            }, {
                corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.25, 0) }),
            }),

            -- Tab bar
            tabBar = React.createElement("Frame", {
                Position         = UDim2.fromScale(0.03, 0.085),
                Size             = UDim2.fromScale(0.94, 0.06),
                BackgroundTransparency = 1,
                ZIndex = 12,
            }, {
                layout = React.createElement("UIListLayout", {
                    FillDirection = Enum.FillDirection.Horizontal,
                    SortOrder     = Enum.SortOrder.LayoutOrder,
                    Padding       = UDim.new(0, 4),
                }),
                tab1 = React.createElement(TabButton, {
                    label = "Cosmetics", order = 1,
                    isActive = activeTab == "Cosmetics",
                    onActivate = function() setActiveTab("Cosmetics") end,
                }),
                tab2 = React.createElement(TabButton, {
                    label = "Consumables", order = 2,
                    isActive = activeTab == "Consumables",
                    onActivate = function() setActiveTab("Consumables") end,
                }),
                tab3 = React.createElement(TabButton, {
                    label = "Premium", order = 3,
                    isActive = activeTab == "Premium",
                    onActivate = function() setActiveTab("Premium") end,
                }),
            }),

            -- Status message
            statusText = statusMsg and React.createElement("TextLabel", {
                Position               = UDim2.fromScale(0.03, 0.155),
                Size                   = UDim2.fromScale(0.94, 0.04),
                BackgroundTransparency = 1,
                Text       = statusMsg,
                TextColor3 = C.green,
                Font       = Enum.Font.GothamBold,
                TextScaled = true,
                ZIndex = 12,
            }) or nil,

            -- Scrolling item list
            scrollFrame = React.createElement("ScrollingFrame", {
                Position                  = UDim2.fromScale(0.03, statusMsg and 0.20 or 0.16),
                Size                      = UDim2.fromScale(0.94, statusMsg and 0.78 or 0.82),
                BackgroundTransparency    = 1,
                BorderSizePixel           = 0,
                ScrollBarImageColor3      = C.accent,
                ScrollBarThickness        = 6,
                CanvasSize                = UDim2.fromScale(0, 0), -- auto-sized
                AutomaticCanvasSize       = Enum.AutomaticSize.Y,
                ScrollingDirection        = Enum.ScrollingDirection.Y,
                ZIndex = 12,
            }, children),
        }),
    })
end

return GlobalShopUI
