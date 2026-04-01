-- StarterPlayerScripts/UI/AchievementsUI.lua
--[[
    Fullscreen achievement browser + unlock toast.

    Exports two React components:
      • AchievementsUI (default)  — fullscreen panel, opened manually
      • AchievementsUI.Toast      — always-mounted toast, self-manages

    AchievementsUI props:
      onClose  function   Called when the ✕ button is pressed

    AchievementsUI.Toast props: none — self-contained via AchievementClient
]]

local Players           = game:GetService("Players")
local TweenService      = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React             = require(ReplicatedStorage.Packages.React)

local PlayerScripts    = Players.LocalPlayer:WaitForChild("PlayerScripts")
local SharedModules    = PlayerScripts:WaitForChild("Modules")
local AchievementClient = require(SharedModules:WaitForChild("AchievementClient"))
local AchievementConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AchievementConfig"))

-- ── Palette ───────────────────────────────────────────────────────────────────
local C = {
    bg         = Color3.fromRGB( 15,  15,  22),
    panel      = Color3.fromRGB( 24,  24,  36),
    card_bg    = Color3.fromRGB( 30,  30,  46),
    card_lock  = Color3.fromRGB( 22,  22,  34),
    gold       = Color3.fromRGB(255, 200,  60),
    gold_dim   = Color3.fromRGB(180, 140,  40),
    blue       = Color3.fromRGB( 80, 160, 255),
    text       = Color3.fromRGB(220, 220, 230),
    text_dim   = Color3.fromRGB(130, 130, 150),
    locked_txt = Color3.fromRGB( 80,  80, 100),
    tab_active = Color3.fromRGB( 50,  80, 160),
    tab_idle   = Color3.fromRGB( 28,  28,  42),
    close_bg   = Color3.fromRGB(180,  50,  50),
    toast_bg   = Color3.fromRGB( 24,  24,  36),
    toast_gold = Color3.fromRGB(255, 200,  60),
}

-- ═══════════════════════════════════════════════════════════
-- SUB-COMPONENTS
-- ═══════════════════════════════════════════════════════════

-- ── CategoryTab ──────────────────────────────────────────────────────────────
local function CategoryTab(props)
    local active = props.active
    return React.createElement("TextButton", {
        Size             = UDim2.new(1, 0, 0, 32),
        BackgroundColor3 = active and C.tab_active or C.tab_idle,
        BorderSizePixel  = 0,
        Text             = props.label,
        TextColor3       = active and C.text or C.text_dim,
        Font             = Enum.Font.GothamBold,
        TextScaled       = true,
        LayoutOrder      = props.order,
        [React.Event.Activated] = props.onSelect,
    }, {
        corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.25, 0) }),
    })
end

-- ── AchievementCard ──────────────────────────────────────────────────────────
local function AchievementCard(props)
    local ach         = props.achievement
    local tierReached = props.tierReached or 0   -- integer 0..N
    local statVal     = props.statVal     or 0
    local maxTier     = #ach.tiers
    local isMax       = tierReached >= maxTier
    local isActive    = tierReached >= 1

    local cardColor = isActive and C.card_bg  or C.card_lock
    local nameColor = isMax    and C.gold     or (isActive and C.text    or C.locked_txt)
    local descColor = isActive and C.text_dim or C.locked_txt
    local iconText  = isActive and ach.icon   or "?"

    -- Progress bar fill fraction
    local fillFrac, barColor, nextLabel
    if isMax then
        fillFrac  = 1
        barColor  = C.gold
        nextLabel = "MAX"
    elseif tierReached == 0 then
        local nextReq = ach.tiers[1]
        fillFrac  = math.clamp(statVal / nextReq, 0, 1)
        barColor  = C.text_dim
        nextLabel = AchievementConfig.FormatNumber(statVal) .. " / " .. AchievementConfig.FormatNumber(nextReq)
    else
        local prevReq = ach.tiers[tierReached]
        local nextReq = ach.tiers[tierReached + 1]
        fillFrac  = math.clamp((statVal - prevReq) / (nextReq - prevReq), 0, 1)
        barColor  = C.blue
        nextLabel = AchievementConfig.FormatNumber(statVal) .. " / " .. AchievementConfig.FormatNumber(nextReq)
    end

    -- Tier badge
    local tierBadgeText  = "Lv " .. tierReached .. " / " .. maxTier
    local tierBadgeColor = isMax and C.gold or (isActive and C.blue or C.locked_txt)

    return React.createElement("Frame", {
        Size             = UDim2.new(1, -8, 0, 88),
        BackgroundColor3 = cardColor,
        BorderSizePixel  = 0,
        LayoutOrder      = props.order,
    }, {
        corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.05, 0) }),

        -- Border: gold for max, blue for active
        stroke = isActive and React.createElement("UIStroke", {
            Color        = isMax and C.gold_dim or C.blue,
            Thickness    = 1.5,
            Transparency = 0,
        }) or nil,

        -- Icon
        iconLbl = React.createElement("TextLabel", {
            Position               = UDim2.fromScale(0.01, 0.06),
            Size                   = UDim2.fromScale(0.12, 0.55),
            BackgroundTransparency = 1,
            Text                   = iconText,
            TextColor3             = isMax and C.gold or (isActive and C.text or C.locked_txt),
            Font                   = Enum.Font.GothamBold,
            TextScaled             = true,
        }),

        -- Name (leaves room for tier badge)
        nameLbl = React.createElement("TextLabel", {
            Position               = UDim2.fromScale(0.14, 0.05),
            Size                   = UDim2.fromScale(0.62, 0.32),
            BackgroundTransparency = 1,
            Text                   = ach.name,
            TextColor3             = nameColor,
            Font                   = Enum.Font.GothamBold,
            TextScaled             = true,
            TextXAlignment         = Enum.TextXAlignment.Left,
        }),

        -- Tier badge (top-right)
        tierBadge = React.createElement("TextLabel", {
            Position               = UDim2.fromScale(0.78, 0.05),
            Size                   = UDim2.fromScale(0.20, 0.32),
            BackgroundTransparency = 1,
            Text                   = tierBadgeText,
            TextColor3             = tierBadgeColor,
            Font                   = Enum.Font.GothamBold,
            TextScaled             = true,
            TextXAlignment         = Enum.TextXAlignment.Right,
        }),

        -- Description
        descLbl = React.createElement("TextLabel", {
            Position               = UDim2.fromScale(0.14, 0.38),
            Size                   = UDim2.fromScale(0.84, 0.22),
            BackgroundTransparency = 1,
            Text                   = ach.desc,
            TextColor3             = descColor,
            Font                   = Enum.Font.Gotham,
            TextScaled             = true,
            TextXAlignment         = Enum.TextXAlignment.Left,
        }),

        -- Progress bar background
        barBg = React.createElement("Frame", {
            Position         = UDim2.fromScale(0.13, 0.65),
            Size             = UDim2.fromScale(0.84, 0.20),
            BackgroundColor3 = C.card_lock,
            BorderSizePixel  = 0,
        }, {
            corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.5, 0) }),

            -- Fill bar
            fill = React.createElement("Frame", {
                Size             = UDim2.fromScale(fillFrac, 1),
                BackgroundColor3 = barColor,
                BorderSizePixel  = 0,
            }, {
                corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
            }),

            -- Progress text
            barLabel = React.createElement("TextLabel", {
                Size                   = UDim2.fromScale(1, 1),
                BackgroundTransparency = 1,
                Text                   = nextLabel,
                TextColor3             = C.text,
                Font                   = Enum.Font.Gotham,
                TextScaled             = true,
                TextXAlignment         = Enum.TextXAlignment.Right,
                ZIndex                 = 2,
            }),
        }),
    })
end

-- ═══════════════════════════════════════════════════════════
-- MAIN PANEL
-- ═══════════════════════════════════════════════════════════

local function AchievementsUIPanel(props)
    local onClose = props.onClose

    local selectedCat,  setSelectedCat  = React.useState("All")
    local achievements, setAchievements = React.useState({})
    local unlockedMap,  setUnlockedMap  = React.useState({})
    local statsMap,     setStatsMap     = React.useState({})

    -- Load / refresh data on open
    React.useEffect(function()
        AchievementClient.Request()
    end, {})

    -- Keep local state in sync with AchievementClient cache
    React.useEffect(function()
        local function refresh()
            setUnlockedMap(AchievementClient.GetUnlocked())
            setStatsMap(AchievementClient.GetStats())
        end
        refresh()

        -- Also subscribe to new unlocks while panel is open
        local unsub1 = AchievementClient.OnUnlocked(function()
            refresh()
        end)
        -- Subscribe to initial data load (server response)
        local unsub2 = AchievementClient.OnDataReceived(function()
            refresh()
        end)
        return function()
            unsub1()
            unsub2()
        end
    end, {})

    -- Filter by selected category
    React.useEffect(function()
        setAchievements(AchievementConfig.GetByCategory(selectedCat))
    end, { selectedCat })

    -- Count earned tiers and total tiers across all achievements
    local earnedTiers = 0
    for _, val in pairs(unlockedMap) do
        if type(val) == "number" then earnedTiers = earnedTiers + val end
    end
    local totalTiers = AchievementConfig.TotalTiers()

    -- ── Build tab list ────────────────────────────────────────────────────────
    local tabs = {}
    for i, cat in ipairs(AchievementConfig.Categories) do
        tabs["tab_" .. cat] = React.createElement(CategoryTab, {
            label    = cat,
            active   = selectedCat == cat,
            order    = i,
            onSelect = function() setSelectedCat(cat) end,
        })
    end

    -- ── Build card list ───────────────────────────────────────────────────────
    local cards = {}
    for i, ach in ipairs(achievements) do
        cards["card_" .. ach.id] = React.createElement(AchievementCard, {
            achievement = ach,
            tierReached = unlockedMap[ach.id] or 0,
            statVal     = AchievementConfig.GetStatValue(ach, statsMap),
            order       = i,
        })
    end

    return React.createElement("Frame", {
        Name                   = "AchievementsUI",
        Size                   = UDim2.fromScale(1, 1),
        BackgroundColor3       = Color3.fromRGB(0, 0, 0),
        BackgroundTransparency = 0.45,
        ZIndex                 = 8,
    }, {
        -- ── Centre panel ─────────────────────────────────────────────────────
        panel = React.createElement("Frame", {
            AnchorPoint      = Vector2.new(0.5, 0.5),
            Position         = UDim2.fromScale(0.5, 0.5),
            Size             = UDim2.fromScale(0.72, 0.88),
            BackgroundColor3 = C.bg,
            BorderSizePixel  = 0,
            ZIndex           = 9,
        }, {
            corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.02, 0) }),
            stroke = React.createElement("UIStroke", {
                Color        = Color3.fromRGB(60, 80, 160),
                Thickness    = 2,
                Transparency = 0,
            }),

            -- Header bar
            header = React.createElement("Frame", {
                Size             = UDim2.fromScale(1, 0.09),
                BackgroundColor3 = C.panel,
                BorderSizePixel  = 0,
                ZIndex           = 10,
            }, {
                hcorner = React.createElement("UICorner", { CornerRadius = UDim.new(0.04, 0) }),

                title = React.createElement("TextLabel", {
                    Position               = UDim2.fromScale(0.04, 0),
                    Size                   = UDim2.fromScale(0.7, 1),
                    BackgroundTransparency = 1,
                    Text                   = "🏆  Achievements  —  " .. earnedTiers .. " / " .. totalTiers .. " tiers",
                    TextColor3             = C.gold,
                    Font                   = Enum.Font.GothamBold,
                    TextScaled             = true,
                    TextXAlignment         = Enum.TextXAlignment.Left,
                    ZIndex                 = 10,
                }),

                closeBtn = React.createElement("TextButton", {
                    AnchorPoint      = Vector2.new(1, 0.5),
                    Position         = UDim2.fromScale(0.99, 0.5),
                    Size             = UDim2.fromScale(0.019, 0.033),
                    BackgroundColor3 = C.close_bg,
                    BorderSizePixel  = 0,
                    Text             = "✕",
                    TextColor3       = Color3.fromRGB(255, 255, 255),
                    Font             = Enum.Font.GothamBold,
                    TextScaled       = true,
                    ZIndex           = 11,
                    [React.Event.Activated] = onClose,
                }, {
                    cc = React.createElement("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
                }),
            }),

            -- Left: category tabs
            sidebar = React.createElement("Frame", {
                Position         = UDim2.fromScale(0, 0.1),
                Size             = UDim2.fromScale(0.18, 0.88),
                BackgroundColor3 = C.panel,
                BorderSizePixel  = 0,
                ZIndex           = 9,
            }, {
                layout = React.createElement("UIListLayout", {
                    FillDirection     = Enum.FillDirection.Vertical,
                    SortOrder         = Enum.SortOrder.LayoutOrder,
                    Padding           = UDim.new(0, 4),
                }),
                pad = React.createElement("UIPadding", {
                    PaddingLeft   = UDim.new(0.04, 0),
                    PaddingRight  = UDim.new(0.04, 0),
                    PaddingTop    = UDim.new(0.02, 0),
                }),
                React.createElement(React.Fragment, nil, tabs),
            }),

            -- Right: achievement cards (scrolling)
            cardScroll = React.createElement("ScrollingFrame", {
                Position             = UDim2.fromScale(0.19, 0.10),
                Size                 = UDim2.fromScale(0.80, 0.88),
                BackgroundTransparency = 1,
                BorderSizePixel      = 0,
                ScrollBarThickness   = 4,
                ScrollBarImageColor3 = C.gold_dim,
                AutomaticCanvasSize  = Enum.AutomaticSize.Y,
                CanvasSize           = UDim2.fromScale(0, 0),
                ZIndex               = 9,
            }, {
                layout = React.createElement("UIListLayout", {
                    FillDirection     = Enum.FillDirection.Vertical,
                    SortOrder         = Enum.SortOrder.LayoutOrder,
                    Padding           = UDim.new(0, 6),
                }),
                pad = React.createElement("UIPadding", {
                    PaddingLeft   = UDim.new(0.01, 0),
                    PaddingRight  = UDim.new(0.01, 0),
                    PaddingTop    = UDim.new(0.01, 0),
                }),
                React.createElement(React.Fragment, nil, cards),
            }),
        }),
    })
end

-- ═══════════════════════════════════════════════════════════
-- TOAST COMPONENT (always mounted, self-manages)
-- ═══════════════════════════════════════════════════════════

local TOAST_DURATION   = 4.0   -- seconds visible
local TOAST_FADE_TIME  = 0.4   -- seconds to fade out

local function AchievementToast()
    local toastData,       setToastData       = React.useState(nil)
    local toastVisible,    setToastVisible    = React.useState(false)
    local toastTransp,     setToastTransp     = React.useState(1)     -- 1 = invisible
    local panelRef = React.useRef(nil)

    React.useEffect(function()
        local queue   = {}
        local showing = false

        local function showNext()
            if #queue == 0 then showing = false; return end
            showing = true
            local item = table.remove(queue, 1)

            setToastData(item)
            setToastVisible(true)
            setToastTransp(0)  -- fully visible (BackgroundTransparency = 0)

            -- Auto-dismiss after TOAST_DURATION
            task.delay(TOAST_DURATION, function()
                -- Fade out (we tween directly via ref for smoothness)
                local frame = panelRef.current
                if frame then
                    TweenService:Create(frame,
                        TweenInfo.new(TOAST_FADE_TIME, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
                        { GroupTransparency = 1 }
                    ):Play()
                end
                task.delay(TOAST_FADE_TIME, function()
                    setToastVisible(false)
                    setToastTransp(1)
                    showNext()
                end)
            end)
        end

        local unsub = AchievementClient.OnUnlocked(function(data)
            table.insert(queue, data)
            if not showing then
                showNext()
            end
        end)

        return unsub
    end, {})

    if not toastVisible then return nil end

    local data = toastData or {}
    local rewardsText = ""
    if data.rewards and #data.rewards > 0 then
        rewardsText = "Rewards: " .. table.concat(data.rewards, ", ")
    end
    local hasRewards = rewardsText ~= ""

    return React.createElement("CanvasGroup", {
        ref              = panelRef,
        AnchorPoint      = Vector2.new(0.5, 0),
        Position         = UDim2.fromScale(0.5, 0.07),
        Size             = UDim2.fromScale(0.36, hasRewards and 0.12 or 0.09),
        BackgroundColor3 = C.toast_bg,
        GroupTransparency  = toastTransp,
        BackgroundTransparency = 0,
        BorderSizePixel  = 0,
        ZIndex           = 20,
    }, {
        corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.2, 0) }),
        stroke = React.createElement("UIStroke", {
            Color        = C.toast_gold,
            Thickness    = 2,
            Transparency = 0,
        }),

        -- Header label
        header = React.createElement("TextLabel", {
            Position               = UDim2.fromScale(0.03, 0.02),
            Size                   = UDim2.fromScale(0.94, hasRewards and 0.28 or 0.38),
            BackgroundTransparency = 1,
            Text                   = "🏆  Achievement Unlocked!",
            TextColor3             = C.toast_gold,
            Font                   = Enum.Font.GothamBold,
            TextScaled             = true,
            TextXAlignment         = Enum.TextXAlignment.Left,
            ZIndex                 = 21,
        }),

        -- Achievement name
        achName = React.createElement("TextLabel", {
            Position               = UDim2.fromScale(0.03, hasRewards and 0.32 or 0.45),
            Size                   = UDim2.fromScale(0.94, hasRewards and 0.34 or 0.5),
            BackgroundTransparency = 1,
            Text                   = (data.icon or "") .. "  " .. (data.name or "") .. (data.tier and ("  [Tier " .. data.tier .. "/" .. (data.maxTier or "?") .. "]") or ""),
            TextColor3             = C.text,
            Font                   = Enum.Font.GothamBold,
            TextScaled             = true,
            TextXAlignment         = Enum.TextXAlignment.Left,
            ZIndex                 = 21,
        }),

        -- Rewards line (conditional)
        rewards = hasRewards and React.createElement("TextLabel", {
            Position               = UDim2.fromScale(0.03, 0.70),
            Size                   = UDim2.fromScale(0.94, 0.26),
            BackgroundTransparency = 1,
            Text                   = rewardsText,
            TextColor3             = Color3.fromRGB(140, 255, 140),
            Font                   = Enum.Font.Gotham,
            TextScaled             = true,
            TextXAlignment         = Enum.TextXAlignment.Left,
            ZIndex                 = 21,
        }) or nil,
    })
end

-- ═══════════════════════════════════════════════════════════
-- EXPORTS
-- ═══════════════════════════════════════════════════════════

return {
    default = AchievementsUIPanel,
    Toast   = AchievementToast,
}
