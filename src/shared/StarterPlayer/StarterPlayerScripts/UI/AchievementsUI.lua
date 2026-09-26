-- StarterPlayerScripts/UI/AchievementsUI.lua
--[[
    Achievement browser + unlock toast.
    §AGX/UI-P6: the panel is an AppWindow (windowed; sheet on phone) with
    Tabs for the categories and Panel/Text/Bar cards, in design px inside
    UIScaleRoot.Local. Removed: the private palette, the hand-rolled
    backdrop/panel/header/✕ (+ hitArea), CategoryTab, the TextScaled labels
    and the private progress bar. The Toast bridge to Notify is unchanged
    (its colour now reads the same RGB from Theme.Roles.state.warning).

    Exports two React components:
      • AchievementsUI (default)  — fullscreen panel, opened manually
      • AchievementsUI.Toast      — always-mounted toast, self-manages

    AchievementsUI props:
      onClose  function   Called when the ✕ button is pressed

    AchievementsUI.Toast props: none — self-contained via AchievementClient
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React             = require(ReplicatedStorage.Packages.React)

local PlayerScripts    = Players.LocalPlayer:WaitForChild("PlayerScripts")
local SharedModules    = PlayerScripts:WaitForChild("Modules")
local AchievementClient = require(SharedModules:WaitForChild("AchievementClient"))
local AchievementConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AchievementConfig"))

-- §AGX/UI-P6: shared components
local Common      = script.Parent:WaitForChild("Common")
local AppWindow   = require(Common:WaitForChild("AppWindow"))
local Theme       = require(Common:WaitForChild("Theme"))
local UIScaleRoot = require(Common:WaitForChild("UIScaleRoot"))
local Text        = require(Common:WaitForChild("Text"))
local Panel       = require(Common:WaitForChild("Panel"))
local Tabs        = require(Common:WaitForChild("Tabs"))
local Bar         = require(Common:WaitForChild("Bar"))

local e  = React.createElement
local R  = Theme.Roles
local SP = Theme.Space

-- §AGX/UI-P6: design px
local CARD_H     = 88
local ICON_W     = 44
local BADGE_W    = 96
local PROGRESS_W = 120

-- ═══════════════════════════════════════════════════════════
-- SUB-COMPONENTS
-- ═══════════════════════════════════════════════════════════

-- ── AchievementCard ──────────────────────────────────────────────────────────
local function AchievementCard(props)
    local ach         = props.achievement
    local tierReached = props.tierReached or 0   -- integer 0..N
    local statVal     = props.statVal     or 0
    local maxTier     = #ach.tiers
    local isMax       = tierReached >= maxTier
    local isActive    = tierReached >= 1

    -- §AGX/UI-P6: roles. Max = legendary gold, active = blue body accent,
    -- not started = disabled text.
    local nameColor = isMax and "rarity.legendary" or (isActive and "text.primary" or "text.secondary")
    local descColor = isActive and "text.secondary" or "text.disabled"
    local iconText  = isActive and ach.icon   or "?"

    -- Progress bar fill fraction
    local fillFrac, nextLabel
    if isMax then
        fillFrac  = 1
        nextLabel = "MAX"
    elseif tierReached == 0 then
        local nextReq = ach.tiers[1]
        fillFrac  = math.clamp(statVal / nextReq, 0, 1)
        nextLabel = AchievementConfig.FormatNumber(statVal) .. " / " .. AchievementConfig.FormatNumber(nextReq)
    else
        local prevReq = ach.tiers[tierReached]
        local nextReq = ach.tiers[tierReached + 1]
        fillFrac  = math.clamp((statVal - prevReq) / (nextReq - prevReq), 0, 1)
        nextLabel = AchievementConfig.FormatNumber(statVal) .. " / " .. AchievementConfig.FormatNumber(nextReq)
    end

    -- Tier badge
    local tierBadgeText  = "Lv " .. tierReached .. " / " .. maxTier
    local tierBadgeColor = isMax and "rarity.legendary" or (isActive and "accent.secondary" or "text.disabled")
    local textLeft = ICON_W + SP.sm

    return e(Panel, {
        name         = "Ach_" .. tostring(ach.id),
        elevation    = isActive and "raised" or "sunken",
        padding      = "md",
        size         = UDim2.new(1, 0, 0, CARD_H),
        -- Border: gold for max, blue for active (none when not started)
        accent       = isMax and "rarity.legendary" or (isActive and "accent.secondary" or nil),
        stroke       = isActive,
        layoutOrder  = props.order,
    }, {
        -- Icon
        iconLbl = e("TextLabel", {
            Size                   = UDim2.fromOffset(ICON_W, ICON_W),
            AnchorPoint            = Vector2.new(0, 0.5),
            Position               = UDim2.fromScale(0, 0.5),
            BackgroundColor3       = R.surface.sunken,
            BackgroundTransparency = isActive and 0 or 1,
            BorderSizePixel        = 0,
            Text                   = iconText,
            TextColor3             = Theme.color(nameColor),
            FontFace               = Theme.FontFaces.heavy,
            TextSize               = 24,
            TextTransparency       = isActive and 0 or 0.4,
        }, {
            corner = e("UICorner", { CornerRadius = Theme.Radius.md }),
        }),

        -- Name (leaves room for tier badge)
        nameLbl = e(Text, {
            style    = "heading",
            text     = ach.name,
            color    = nameColor,
            position = UDim2.fromOffset(textLeft, 0),
            size     = UDim2.new(1, -(textLeft + BADGE_W + SP.sm), 0, 22),
        }),

        -- Tier badge (top-right)
        tierBadge = e(Text, {
            style       = "label",
            text        = tierBadgeText,
            color       = tierBadgeColor,
            align       = "right",
            anchorPoint = Vector2.new(1, 0),
            position    = UDim2.fromScale(1, 0),
            size        = UDim2.fromOffset(BADGE_W, 22),
        }),

        -- Description
        descLbl = e(Text, {
            style    = "caption",
            text     = ach.desc,
            color    = descColor,
            position = UDim2.fromOffset(textLeft, 23),
            size     = UDim2.new(1, -textLeft, 0, 18),
        }),

        -- Progress bar (§AGX/UI-P6: Bar; amber "xp" fill once maxed)
        bar = e(Bar, {
            kind     = isMax and "xp" or "progress",
            value    = fillFrac,
            max      = 1,
            height   = 12,
            position = UDim2.fromOffset(textLeft, 48),
            size     = UDim2.new(1, -(textLeft + PROGRESS_W + SP.sm), 0, 12),
        }),
        barLabel = e(Text, {
            style       = "numeric",
            text        = nextLabel,
            color       = isActive and "text.primary" or "text.secondary",
            align       = "right",
            anchorPoint = Vector2.new(1, 0),
            position    = UDim2.new(1, 0, 0, 44),
            size        = UDim2.fromOffset(PROGRESS_W, 20),
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

    -- ── Build tab list (§AGX/UI-P6: Tabs; chip row on phones) ──────────────
    local tabItems = {}
    for _, cat in ipairs(AchievementConfig.Categories) do
        table.insert(tabItems, { id = cat, label = cat })
    end

    -- ── Build card list ───────────────────────────────────────────────────────
    local cards = {
        layout = e("UIListLayout", {
            FillDirection     = Enum.FillDirection.Vertical,
            SortOrder         = Enum.SortOrder.LayoutOrder,
            Padding           = UDim.new(0, SP.sm),
        }),
        pad = e("UIPadding", {
            PaddingLeft   = UDim.new(0, SP.lg),
            PaddingRight  = UDim.new(0, SP.lg),
            PaddingTop    = UDim.new(0, SP.md),
            PaddingBottom = UDim.new(0, SP.lg),
        }),
    }
    for i, ach in ipairs(achievements) do
        cards["card_" .. ach.id] = e(AchievementCard, {
            achievement = ach,
            tierReached = unlockedMap[ach.id] or 0,
            statVal     = AchievementConfig.GetStatValue(ach, statsMap),
            order       = i,
        })
    end

    local tabsH = Theme.Metrics.tabs.height

    return e(AppWindow, {
        variant = "windowed",
        title   = "Achievements",
        icon    = "achievements",
        onClose = onClose,
        size    = UDim2.fromScale(0.72, 0.88),
        zIndex  = 8,
        -- earned / total tiers, right of the ribbon
        headerContent = e(UIScaleRoot.Local, { name = "TierCount" }, {
            count = e(Text, {
                style       = "numeric",
                text        = "🏆 " .. earnedTiers .. " / " .. totalTiers .. " tiers",
                color       = "rarity.legendary",
                align       = "right",
                anchorPoint = Vector2.new(1, 0.5),
                position    = UDim2.fromScale(1, 0.5),
                size        = UDim2.new(1, 0, 0, 24),
            }),
        }),
    }, {
        -- §AGX/UI-P6: design px from here down.
        content = e(UIScaleRoot.Local, { name = "AchievementsBody" }, {
            tabs = e(Tabs, {
                items    = tabItems,
                value    = selectedCat,
                onChange = setSelectedCat,
            }),
            cardScroll = e("ScrollingFrame", {
                Name                 = "Cards",
                Position             = UDim2.fromOffset(0, tabsH),
                Size                 = UDim2.new(1, 0, 1, -tabsH),
                BackgroundTransparency = 1,
                BorderSizePixel      = 0,
                ScrollBarThickness   = Theme.Metrics.scrollBar,
                ScrollBarImageColor3 = R.text.secondary,
                AutomaticCanvasSize  = Enum.AutomaticSize.Y,
                CanvasSize           = UDim2.fromScale(0, 0),
                ScrollingDirection   = Enum.ScrollingDirection.Y,
            }, cards),
        }),
    })
end

-- ═══════════════════════════════════════════════════════════
-- TOAST COMPONENT (always mounted, self-manages)
-- ═══════════════════════════════════════════════════════════
-- §AGX/UI-P4: the unlock toast is now a Notify BANNER (top-centre, priority
-- "achievement", the lowest). It used to be its own CanvasGroup at
-- (0.5, 0.07) scale with a private queue, a 4 s timer and a fade tween,
-- i.e. under the topbar on phones and on top of the HUD wave banner.
-- This component only bridges AchievementClient.OnUnlocked → Notify and
-- renders nothing; the export name stays so the App roots are untouched.
-- Notify's banner queue replaces the private queue; staleAfter = inf so a
-- burst of unlocks is never dropped while a wave/boss banner is showing.

local TOAST_DURATION = 4.0   -- seconds visible (unchanged)

local Notify = require(script.Parent:WaitForChild("Common"):WaitForChild("Notify"))  -- §AGX/UI-P4

local function AchievementToast()
    React.useEffect(function()
        return AchievementClient.OnUnlocked(function(data)
            data = data or {}
            local name = (data.icon or "") .. "  " .. (data.name or "")
                .. (data.tier and ("  [Tier " .. data.tier .. "/" .. (data.maxTier or "?") .. "]") or "")
            local subtitle = name
            if data.rewards and #data.rewards > 0 then
                subtitle = subtitle .. "  ·  Rewards: " .. table.concat(data.rewards, ", ")
            end
            Notify.banner("🏆  Achievement Unlocked!", {
                subtitle   = subtitle,
                priority   = "achievement",
                color      = R.state.warning,   -- §AGX/UI-P6: = old toast_gold 255,200,60
                duration   = TOAST_DURATION,
                staleAfter = math.huge,
            })
        end)
    end, {})

    return nil
end

-- ═══════════════════════════════════════════════════════════
-- EXPORTS
-- ═══════════════════════════════════════════════════════════

return {
    default = AchievementsUIPanel,
    Toast   = AchievementToast,
}
