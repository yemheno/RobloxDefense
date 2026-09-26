-- UI/VoteUI.lua
--[[
    Card Vote Overlay
    =================
    Renders 3 selectable cards when the server fires "VoteStart".
    Players click to cast one anonymous vote. Live vote counts update
    in real-time. After resolution, shows the winning card briefly.

    Mounted in CombatApp; renders nothing when no vote is active.

    §AGX/UI-P6: Theme v2 re-skin (docs/UI_REVAMP.md D1 Hybrid / D2).
      • Content = design px inside UIScaleRoot.Local (the Shell mounts this
        unscaled). Header Text + timer Bar + a row of Common Card tiles.
      • Card: selected = blue focus ring, winner = legendary (gold) stroke;
        the lane tag + vote count sit in the card footer.
      • Private palette gone: lane colours map onto Theme roles (LANE_ROLE).
      • Kept: useModalPresence("vote"), the Notify "vote" banner, the §VG5
        anti-misclick window, every server event and payload.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React             = require(ReplicatedStorage.Packages.React)

local Modules        = script.Parent.Parent:WaitForChild("Modules")
local NetworkManager = require(Modules:WaitForChild("NetworkManager"))
-- §AGX/UI-P4: the pre-vote heads-up and the post-vote "Get ready!" alerts
-- are Notify banners ("vote" priority) instead of VoteUI-drawn frames.
local Notify         = require(script.Parent:WaitForChild("Common"):WaitForChild("Notify"))

-- §AGX/UI-P6: shared components
local Common      = script.Parent:WaitForChild("Common")
local Theme       = require(Common:WaitForChild("Theme"))
local UIScaleRoot = require(Common:WaitForChild("UIScaleRoot"))
local Text        = require(Common:WaitForChild("Text"))
local Bar         = require(Common:WaitForChild("Bar"))
local Card        = require(Common:WaitForChild("Card"))
local GamepadFocus = require(Common:WaitForChild("GamepadFocus"))   -- §AGX/UI-P7

local e  = React.createElement
local R  = Theme.Roles
local SP = Theme.Space
-- §AGX/UI-P3: PanelStack hooks, nil-safe (no-ops without UI/Shell or
-- outside a PanelHost, so Wave 1 behaves exactly as before).
local PanelStackHooks = { useCloseHandler = function(_fn) end, useModalPresence = function(_k, _v) end }
do
	local shell = script.Parent:FindFirstChild("Shell")
	local mod = shell and shell:FindFirstChild("PanelStack")
	if mod then
		local ok, PanelStack = pcall(require, mod)
		if ok and type(PanelStack) == "table" then
			PanelStackHooks.useCloseHandler  = PanelStack.useCloseHandler or PanelStackHooks.useCloseHandler
			PanelStackHooks.useModalPresence = PanelStack.useModalPresence or PanelStackHooks.useModalPresence
		end
	end
end

-- ═══════════════════════════════════════════════════════════
-- LAYOUT + LANE COLOURS (§AGX/UI-P6: design px, Theme roles)
-- ═══════════════════════════════════════════════════════════

local CARD_W    = 232      -- 3 x 232 + 2 x 12 = 720 <= 844 phone width
local CARD_GAP  = SP.md
local TIMER_H   = 8
local OVERLAY_Z = Theme.Z.modal   -- was a literal 50

-- Lane / card-type identity (was the private palette: greed red, control
-- blue, relief green, supply amber, tactical purple).
local LANE_ROLE = {
    greed    = "state.danger",
    control  = "accent.secondary",
    relief   = "state.success",
}
local TYPE_ROLE = {
    supply   = "vital.xp",
    tactical = "rarity.epic",
}

local function getLaneColor(card)
    local role = (card.lane and LANE_ROLE[card.lane]) or (card.cardType and TYPE_ROLE[card.cardType])
    return Theme.color(role or "text.secondary")
end

-- ═══════════════════════════════════════════════════════════
-- CARD COMPONENT
-- ═══════════════════════════════════════════════════════════

local function VoteCard(props)
    -- props: card, index, voteCount, isSelected, isWinner, onSelect, hideVoteCount
    local card = props.card
    local z = OVERLAY_Z + 2
    local count = props.voteCount or 0

    -- §AGX/UI-P6: footer = lane tag (left) + live vote count (right).
    local footer = e("Frame", {
        Size                   = UDim2.new(1, 0, 0, 24),
        BackgroundTransparency = 1,
        ZIndex                 = z,
    }, {
        lane = card.lane and e(Text, {
            style  = "label",
            text   = string.upper(card.lane),
            color  = getLaneColor(card),
            size   = UDim2.new(1, -52, 1, 0),
            zIndex = z + 1,
        }) or nil,
        -- Vote count badge (hidden for personal votes — no tallying there)
        voteBadge = (not props.hideVoteCount) and e("Frame", {
            Name                   = "VoteCount",
            AnchorPoint            = Vector2.new(1, 0.5),
            Position               = UDim2.fromScale(1, 0.5),
            Size                   = UDim2.fromOffset(44, 24),
            BackgroundColor3       = R.accent.secondary,
            BackgroundTransparency = count > 0 and 0 or 0.7,
            BorderSizePixel        = 0,
            ZIndex                 = z + 1,
        }, {
            corner = e("UICorner", { CornerRadius = Theme.Radius.pill }),
            label  = e(Text, {
                style  = "numeric",
                text   = tostring(count),
                color  = count > 0 and "text.onAccent" or "text.primary",
                align  = "center",
                size   = UDim2.fromScale(1, 1),
                zIndex = z + 2,
            }),
        }) or nil,
    })

    -- Fixed-width column; the Card grows in Y with its text.
    return e("Frame", {
        Name                   = "VoteCard" .. tostring(props.index),
        Size                   = UDim2.fromOffset(CARD_W, 0),
        AutomaticSize          = Enum.AutomaticSize.Y,
        BackgroundTransparency = 1,
        LayoutOrder            = props.index,
        ZIndex                 = z,
    }, {
        card = e(Card, {
            title       = card.name,
            subtitle    = card.description,
            selected    = props.isSelected and not props.isWinner,
            rarity      = props.isWinner and "legendary" or nil,
            footer      = footer,
            zIndex      = z,
            -- The whole card is the tap target (was a transparent overlay button).
            onActivated = function()
                if props.onSelect then
                    props.onSelect(props.index)
                end
            end,
        }),
    })
end

-- ═══════════════════════════════════════════════════════════
-- MAIN VOTE UI COMPONENT
-- ═══════════════════════════════════════════════════════════

local function VoteUI()
    local voteData,        setVoteData        = React.useState(nil)    -- { cards, timerSeconds, voteType, isPersonal? }
    local voteCounts,      setVoteCounts      = React.useState({})
    local mySelection,     setMySelection     = React.useState(nil)    -- index I voted for
    local winnerIndex,     setWinnerIndex     = React.useState(nil)
    local timeLeft,        setTimeLeft        = React.useState(0)
    local voteEndTime,     setVoteEndTime     = React.useState(0)
    local pendingCountdown, setPendingCountdown = React.useState(nil)  -- pre-vote heads-up countdown
    -- §VG4: post-resolve countdown ("Get ready!") shown after cards
    -- dismiss but before the world resumes. Server fires VoteCountdown
    -- with the duration; we tick down locally for the UI display.
    local resumeCountdown, setResumeCountdown = React.useState(nil)
    local timerTaskRef     = React.useRef(nil)
    local pendingTaskRef   = React.useRef(nil)
    -- §UI3: guards the 2 s auto-dismiss delays against firing after unmount.
    local mountedRef       = React.useRef(true)
    local resumeTaskRef    = React.useRef(nil)
    -- §VG5: anti-misclick guard. When the cards first appear, players who
    -- happened to be left-click attacking can fire a vote inadvertently in
    -- the same frame the overlay mounts. Stamp os.clock() at appear and
    -- reject any onSelect that lands within VOTE_INPUT_GRACE_SEC of that
    -- stamp. Ref (not state) so it doesn't trigger a re-render.
    local cardsShownAtRef = React.useRef(0)

    -- Listen for server events
    React.useEffect(function()
        local conn1 = NetworkManager.OnServerEvent("VoteStart", function(data)
            data.isPersonal = false
            setVoteData(data)
            setVoteCounts({})
            setMySelection(nil)
            setWinnerIndex(nil)
            setTimeLeft(data.timerSeconds)
            setVoteEndTime(os.clock() + data.timerSeconds)
            -- §VG5: stamp the appear time so onSelect can reject the
            -- first 2 s of clicks as accidental.
            cardsShownAtRef.current = os.clock()
        end)

        local conn2 = NetworkManager.OnServerEvent("VoteUpdate", function(data)
            setVoteCounts(data.counts or {})
        end)

        local conn3 = NetworkManager.OnServerEvent("VoteResult", function(data)
            setWinnerIndex(data.winnerIndex)
            setVoteCounts(data.counts or {})
            -- §VG4: dismiss cards after VOTE_RESULT_DISPLAY_SEC (2 s);
            -- VoteCountdown event below takes over with the "Get ready!"
            -- counter for the next 3 s before world resumes.
            task.delay(2, function()
                if not mountedRef.current then return end  -- §UI3
                setVoteData(nil)
                setWinnerIndex(nil)
            end)
        end)

        -- §VG4: VoteCountdown drives the "Get ready!" display that runs
        -- between card-dismiss and world-resume. Mirrors VotePending below.
        local connCountdown = NetworkManager.OnServerEvent("VoteCountdown", function(data)
            local secs = data.seconds or 3
            setResumeCountdown(secs)
            if resumeTaskRef.current then
                task.cancel(resumeTaskRef.current)
            end
            resumeTaskRef.current = task.spawn(function()
                while secs > 0 do
                    task.wait(1)
                    secs = secs - 1
                    setResumeCountdown(secs > 0 and secs or nil)
                end
            end)
        end)

        local conn4 = NetworkManager.OnServerEvent("VotePending", function(data)
            local secs = data.countdown or 2
            setPendingCountdown(secs)
            -- Cancel previous pending task if present
            if pendingTaskRef.current then
                task.cancel(pendingTaskRef.current)
            end
            -- Spawn new pending countdown task
            pendingTaskRef.current = task.spawn(function()
                while secs > 0 do
                    task.wait(1)
                    secs = secs - 1
                    setPendingCountdown(secs > 0 and secs or nil)
                end
            end)
        end)

        -- PERSONAL vote flow — each player independently picks a card.
        -- Uses the same UI shell, but the vote-count badge is hidden and the
        -- cast goes through VoteCastPersonal instead of VoteCast.
        local conn5 = NetworkManager.OnServerEvent("VoteStartPersonal", function(data)
            data.isPersonal = true
            setVoteData(data)
            setVoteCounts({})
            setMySelection(nil)
            setWinnerIndex(nil)
            setTimeLeft(data.timerSeconds)
            setVoteEndTime(os.clock() + data.timerSeconds)
            -- §VG5: same anti-misclick stamp as the shared flow.
            cardsShownAtRef.current = os.clock()
        end)

        local conn6 = NetworkManager.OnServerEvent("VoteResultPersonal", function(data)
            setWinnerIndex(data.winnerIndex)
            -- §VG4: 2 s display, countdown handled by VoteCountdown.
            task.delay(2, function()
                if not mountedRef.current then return end  -- §UI3
                setVoteData(nil)
                setWinnerIndex(nil)
            end)
        end)

        return function()
            mountedRef.current = false  -- §UI3
            if conn1 then conn1:Disconnect() end
            if conn2 then conn2:Disconnect() end
            if connCountdown then connCountdown:Disconnect() end
            if resumeTaskRef.current then task.cancel(resumeTaskRef.current); resumeTaskRef.current = nil end
            if conn3 then conn3:Disconnect() end
            if conn4 then conn4:Disconnect() end
            if conn5 then conn5:Disconnect() end
            if conn6 then conn6:Disconnect() end
            if pendingTaskRef.current then
                task.cancel(pendingTaskRef.current)
                pendingTaskRef.current = nil
            end
        end
    end, {})

    -- Timer countdown
    React.useEffect(function()
        if not voteData or winnerIndex then return end
        -- Cancel old timer task if present
        if timerTaskRef.current then
            task.cancel(timerTaskRef.current)
        end
        -- Spawn new timer task and store in ref
        timerTaskRef.current = task.spawn(function()
            while not winnerIndex do
                local remaining = math.max(0, voteEndTime - os.clock())
                setTimeLeft(math.ceil(remaining))
                if remaining <= 0 then break end
                task.wait(0.1)
            end
        end)
        return function()
            if timerTaskRef.current then
                task.cancel(timerTaskRef.current)
                timerTaskRef.current = nil
            end
        end
    end, { voteData, winnerIndex, voteEndTime })

    -- §AGX/UI-P4: pre-vote heads-up countdown + §VG4 post-vote "Get ready!"
    -- countdown, as ONE sticky "vote" banner (same text and colour, same
    -- precedence: heads-up first, both only while no cards are up). Key
    -- "vote" updates it in place each tick; it is cleared the moment the
    -- countdowns end or the cards appear, so it never outlives them.
    local hasVoteData = voteData ~= nil
    React.useEffect(function()
        if pendingCountdown and not hasVoteData then
            Notify.banner("⚠  Vote starting in  " .. tostring(pendingCountdown) .. "s", {
                key = "vote", priority = "vote", sticky = true,
                color = R.state.warning,          -- §AGX/UI-P6: Theme role
            })
        elseif resumeCountdown and not hasVoteData then
            Notify.banner("▶  Get ready!  " .. tostring(resumeCountdown), {
                key = "vote", priority = "vote", sticky = true,
                color = R.accent.secondary,       -- §AGX/UI-P6: Theme role
            })
        else
            Notify.clearBanner("vote")
        end
    end, { pendingCountdown, resumeCountdown, hasVoteData })
    React.useEffect(function()
        return function() Notify.clearBanner("vote") end
    end, {})

    -- Nothing to show
    -- §AGX/UI-P3: A12. While the cards are up the vote is a modal presence:
    -- open panels are suspended and new opens are refused (rail dimmed).
    PanelStackHooks.useModalPresence("vote", voteData ~= nil)

    -- §AGX/UI-P7: gamepad only: focus the first card when the cards appear
    -- (the §VG5 grace window below still eats an early A). The vote is a
    -- modal presence, so taking the selection from a panel is intended.
    local overlayRef = React.useRef(nil)
    GamepadFocus.useAutoSelect(overlayRef, voteData, { steal = true })

    if not voteData then return nil end

    local cards = voteData.cards or {}

    local isPersonal = voteData.isPersonal == true

    -- §VG5: 2-second anti-misclick window. A player who happened to be
    -- left-click attacking at the moment cards mounted would otherwise
    -- fire a vote inadvertently on the same frame as the overlay appears.
    local VOTE_INPUT_GRACE_SEC = 2

    local onSelect = function(index)
        if mySelection or winnerIndex then return end  -- already voted or resolved
        if (os.clock() - (cardsShownAtRef.current or 0)) < VOTE_INPUT_GRACE_SEC then
            return  -- guard window — eat the click
        end
        setMySelection(index)
        if isPersonal then
            NetworkManager.FireServer("VoteCastPersonal", index)
        else
            NetworkManager.FireServer("VoteCast", index)
        end
    end

    -- Build card elements
    local cardElements = {}
    for i, card in ipairs(cards) do
        cardElements["card" .. i] = e(VoteCard, {
            card          = card,
            index         = i,
            voteCount     = voteCounts[i] or 0,
            isSelected    = mySelection == i,
            isWinner      = winnerIndex == i,
            onSelect      = onSelect,
            hideVoteCount = isPersonal,
        })
    end

    -- Header text
    local headerText
    if winnerIndex then
        local label = isPersonal and "Chosen: " or "Winner: "
        headerText = label .. (cards[winnerIndex] and cards[winnerIndex].name or "")
    elseif isPersonal then
        headerText = string.upper(voteData.voteType or "SUPPLY") .. " — YOUR PICK"
    else
        headerText = string.upper(voteData.voteType or "VOTE") .. " VOTE"
    end

    -- Card row children (merge layout + card elements)
    local cardRowChildren = {
        layout = e("UIListLayout", {
            FillDirection       = Enum.FillDirection.Horizontal,
            HorizontalAlignment = Enum.HorizontalAlignment.Center,
            VerticalAlignment   = Enum.VerticalAlignment.Top,
            Padding             = UDim.new(0, CARD_GAP),
            SortOrder           = Enum.SortOrder.LayoutOrder,
        }),
    }
    for key, element in pairs(cardElements) do
        cardRowChildren[key] = element
    end

    local rowW = math.max(1, #cards) * CARD_W + math.max(0, #cards - 1) * CARD_GAP
    local z = OVERLAY_Z + 1

    return e("Frame", {
        Name                   = "VoteOverlay",
        Size                   = UDim2.fromScale(1, 1),
        BackgroundColor3       = R.surface.scrim,
        BackgroundTransparency = 0.55,
        ZIndex                 = OVERLAY_Z,
        -- §AGX/UI-P7: D-pad stays on the cards.
        ref                    = overlayRef,
        SelectionGroup         = true,
        SelectionBehaviorUp    = Enum.SelectionBehavior.Stop,
        SelectionBehaviorDown  = Enum.SelectionBehavior.Stop,
        SelectionBehaviorLeft  = Enum.SelectionBehavior.Stop,
        SelectionBehaviorRight = Enum.SelectionBehavior.Stop,
    }, {
        content = e(UIScaleRoot.Local, { name = "VoteContent", zIndex = z }, {
            -- Center container (design px)
            container = e("Frame", {
                Name                   = "Container",
                AnchorPoint            = Vector2.new(0.5, 0.5),
                Position               = UDim2.fromScale(0.5, 0.45),
                Size                   = UDim2.fromOffset(rowW, 0),
                AutomaticSize          = Enum.AutomaticSize.Y,
                BackgroundTransparency = 1,
                ZIndex                 = z,
            }, {
                layout = e("UIListLayout", {
                    SortOrder = Enum.SortOrder.LayoutOrder,
                    Padding   = UDim.new(0, SP.sm),
                }),

                -- Header row: title + seconds left
                headerRow = e("Frame", {
                    LayoutOrder            = 1,
                    Size                   = UDim2.new(1, 0, 0, Theme.Type.title.lineHeight),
                    BackgroundTransparency = 1,
                    ZIndex                 = z,
                }, {
                    header = e(Text, {
                        style  = "title",
                        text   = headerText,
                        color  = winnerIndex and "rarity.legendary" or "text.primary",
                        align  = "center",
                        size   = UDim2.new(1, -120, 1, 0),
                        position = UDim2.fromOffset(60, 0),
                        zIndex = z + 1,
                    }),
                    timerText = (not winnerIndex) and e(Text, {
                        style       = "numeric",
                        text        = tostring(timeLeft) .. "s",
                        color       = timeLeft <= 3 and "state.danger" or "text.secondary",
                        align       = "right",
                        anchorPoint = Vector2.new(1, 0),
                        position    = UDim2.fromScale(1, 0),
                        size        = UDim2.new(0, 56, 1, 0),
                        zIndex      = z + 1,
                    }) or nil,
                }),

                -- Timer bar (§AGX/UI-P6: Common Bar, blue progress)
                timerBar = (not winnerIndex) and e(Bar, {
                    value       = timeLeft,
                    max         = voteData.timerSeconds,
                    height      = TIMER_H,
                    layoutOrder = 2,
                    zIndex      = z,
                }) or nil,

                -- Card row
                cardRow = e("Frame", {
                    Name                   = "CardRow",
                    LayoutOrder            = 3,
                    Size                   = UDim2.fromScale(1, 0),
                    AutomaticSize          = Enum.AutomaticSize.Y,
                    BackgroundTransparency = 1,
                    ZIndex                 = z,
                }, cardRowChildren),
            }),
        }),
    })
end

return VoteUI
