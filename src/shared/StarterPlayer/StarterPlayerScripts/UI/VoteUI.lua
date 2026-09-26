-- UI/VoteUI.lua
--[[
    Card Vote Overlay
    =================
    Renders 3 selectable cards when the server fires "VoteStart".
    Players click to cast one anonymous vote. Live vote counts update
    in real-time. After resolution, shows the winning card briefly.

    Mounted in CombatApp; renders nothing when no vote is active.
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React             = require(ReplicatedStorage.Packages.React)

local Modules        = script.Parent.Parent:WaitForChild("Modules")
local NetworkManager = require(Modules:WaitForChild("NetworkManager"))
-- §AGX/UI-P4: the pre-vote heads-up and the post-vote "Get ready!" alerts
-- are Notify banners ("vote" priority) instead of VoteUI-drawn frames.
local Notify         = require(script.Parent:WaitForChild("Common"):WaitForChild("Notify"))
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
-- PALETTE
-- ═══════════════════════════════════════════════════════════

local C = {
    overlay     = Color3.fromRGB(  0,   0,   0),
    cardBg      = Color3.fromRGB( 28,  28,  38),
    cardBorder  = Color3.fromRGB( 60,  70, 110),
    cardHover   = Color3.fromRGB( 40,  45,  65),
    cardSelected = Color3.fromRGB( 50,  80, 140),
    text        = Color3.fromRGB(220, 220, 230),
    textDim     = Color3.fromRGB(140, 140, 160),
    textBright  = Color3.fromRGB(255, 255, 255),
    timerBg     = Color3.fromRGB( 35,  35,  50),
    timerBar    = Color3.fromRGB( 80, 160, 255),
    voteBadge   = Color3.fromRGB( 80, 210, 255),
    winnerGlow  = Color3.fromRGB(255, 200,  60),
    -- Lane colors
    greed       = Color3.fromRGB(200,  60,  60),
    control     = Color3.fromRGB( 60, 140, 200),
    relief      = Color3.fromRGB( 60, 180,  80),
    supply      = Color3.fromRGB(210, 150,  40),
    tactical    = Color3.fromRGB(120, 100, 200),
}

local function getLaneColor(card)
    if card.lane == "greed"   then return C.greed end
    if card.lane == "control" then return C.control end
    if card.lane == "relief"  then return C.relief end
    if card.cardType == "supply"   then return C.supply end
    if card.cardType == "tactical" then return C.tactical end
    return C.cardBorder
end

-- ═══════════════════════════════════════════════════════════
-- CARD COMPONENT
-- ═══════════════════════════════════════════════════════════

local function VoteCard(props)
    -- props: card, index, voteCount, isSelected, isWinner, onSelect, hideVoteCount
    local card       = props.card
    local isHovered, setHovered = React.useState(false)

    local bgColor = props.isWinner and C.winnerGlow
        or props.isSelected and C.cardSelected
        or isHovered and C.cardHover
        or C.cardBg

    local borderColor = props.isWinner and C.winnerGlow or getLaneColor(card)

    return React.createElement("Frame", {
        Size             = UDim2.fromScale(0.28, 0.85),
        BackgroundColor3 = bgColor,
        BorderSizePixel  = 0,
        LayoutOrder      = props.index,
    }, {
        corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 12) }),
        stroke = React.createElement("UIStroke", {
            Color     = borderColor,
            Thickness = props.isWinner and 3 or 2,
        }),
        padding = React.createElement("UIPadding", {
            PaddingTop    = UDim.new(0, 14),
            PaddingBottom = UDim.new(0, 14),
            PaddingLeft   = UDim.new(0, 16),
            PaddingRight  = UDim.new(0, 16),
        }),

        -- Lane tag (top)
        laneTag = card.lane and React.createElement("TextLabel", {
            Size             = UDim2.new(1, 0, 0, 18),
            Position         = UDim2.fromOffset(0, 0),
            BackgroundTransparency = 1,
            Font             = Enum.Font.GothamBold,
            TextSize         = 13,
            Text             = string.upper(card.lane),
            TextColor3       = getLaneColor(card),
            TextXAlignment   = Enum.TextXAlignment.Left,
        }) or nil,

        -- Card name
        name = React.createElement("TextLabel", {
            Size             = UDim2.new(1, 0, 0, 28),
            Position         = UDim2.new(0, 0, 0, card.lane and 22 or 0),
            BackgroundTransparency = 1,
            Font             = Enum.Font.GothamBold,
            TextSize         = 20,
            Text             = card.name,
            TextColor3       = C.textBright,
            TextXAlignment   = Enum.TextXAlignment.Left,
            TextWrapped      = true,
        }),

        -- Description
        desc = React.createElement("TextLabel", {
            Size             = UDim2.new(1, 0, 0, 48),
            Position         = UDim2.new(0, 0, 0, card.lane and 54 or 32),
            BackgroundTransparency = 1,
            Font             = Enum.Font.Gotham,
            TextSize         = 14,
            Text             = card.description,
            TextColor3       = C.textDim,
            TextXAlignment   = Enum.TextXAlignment.Left,
            TextYAlignment   = Enum.TextYAlignment.Top,
            TextWrapped      = true,
        }),

        -- Vote count badge (hidden for personal votes — no tallying there)
        voteBadge = (not props.hideVoteCount) and React.createElement("TextLabel", {
            Size             = UDim2.fromScale(0.021, 0.022),
            Position         = UDim2.new(1, -40, 1, -30),
            AnchorPoint      = Vector2.new(0, 0),
            BackgroundColor3 = C.voteBadge,
            BackgroundTransparency = (props.voteCount or 0) > 0 and 0.15 or 0.7,
            Font             = Enum.Font.GothamBold,
            TextSize         = 16,
            Text             = tostring(props.voteCount or 0),
            TextColor3       = C.textBright,
        }, {
            corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 6) }),
        }) or nil,

        -- Click detector
        button = React.createElement("TextButton", {
            Size                   = UDim2.fromScale(1, 1),
            Position               = UDim2.fromScale(0, 0),
            BackgroundTransparency = 1,
            Text                   = "",
            ZIndex                 = 10,
            [React.Event.MouseEnter]  = function() setHovered(true) end,
            [React.Event.MouseLeave]  = function() setHovered(false) end,
            [React.Event.Activated]   = function()
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
                color = Color3.fromRGB(255, 215, 80),
            })
        elseif resumeCountdown and not hasVoteData then
            Notify.banner("▶  Get ready!  " .. tostring(resumeCountdown), {
                key = "vote", priority = "vote", sticky = true,
                color = Color3.fromRGB(160, 230, 255),
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
        cardElements["card" .. i] = React.createElement(VoteCard, {
            card          = card,
            index         = i,
            voteCount     = voteCounts[i] or 0,
            isSelected    = mySelection == i,
            isWinner      = winnerIndex == i,
            onSelect      = onSelect,
            hideVoteCount = isPersonal,
        })
    end

    -- Timer bar
    local timerFraction = voteData.timerSeconds > 0
        and math.clamp(timeLeft / voteData.timerSeconds, 0, 1) or 0

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
        layout = React.createElement("UIListLayout", {
            FillDirection       = Enum.FillDirection.Horizontal,
            HorizontalAlignment = Enum.HorizontalAlignment.Center,
            VerticalAlignment   = Enum.VerticalAlignment.Center,
            Padding             = UDim.new(0, 16),
            SortOrder           = Enum.SortOrder.LayoutOrder,
        }),
    }
    for key, element in pairs(cardElements) do
        cardRowChildren[key] = element
    end

    return React.createElement("Frame", {
        Name                   = "VoteOverlay",
        Size                   = UDim2.fromScale(1, 1),
        BackgroundColor3       = C.overlay,
        BackgroundTransparency = 0.55,
        ZIndex                 = 50,
    }, {
        -- Center container
        container = React.createElement("Frame", {
            Size             = UDim2.fromScale(0.72, 0.38),
            Position         = UDim2.fromScale(0.5, 0.42),
            AnchorPoint      = Vector2.new(0.5, 0.5),
            BackgroundTransparency = 1,
        }, {
            -- Header
            header = React.createElement("TextLabel", {
                Size             = UDim2.new(1, 0, 0, 32),
                Position         = UDim2.new(0, 0, 0, -40),
                BackgroundTransparency = 1,
                Font             = Enum.Font.GothamBold,
                TextSize         = 22,
                Text             = headerText,
                TextColor3       = winnerIndex and C.winnerGlow or C.textBright,
            }),

            -- Timer bar
            timerBg = (not winnerIndex) and React.createElement("Frame", {
                Size             = UDim2.new(1, 0, 0, 6),
                Position         = UDim2.new(0, 0, 0, -6),
                BackgroundColor3 = C.timerBg,
                BorderSizePixel  = 0,
            }, {
                corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 3) }),
                fill = React.createElement("Frame", {
                    Size             = UDim2.fromScale(timerFraction, 1),
                    BackgroundColor3 = C.timerBar,
                    BorderSizePixel  = 0,
                }, {
                    corner = React.createElement("UICorner", { CornerRadius = UDim.new(0, 3) }),
                }),
            }) or nil,

            -- Timer text
            timerText = (not winnerIndex) and React.createElement("TextLabel", {
                Size             = UDim2.fromScale(0.031, 0.022),
                Position         = UDim2.new(1, -60, 0, -36),
                BackgroundTransparency = 1,
                Font             = Enum.Font.GothamBold,
                TextSize         = 16,
                Text             = tostring(timeLeft) .. "s",
                TextColor3       = timeLeft <= 3 and Color3.fromRGB(255, 80, 80) or C.textDim,
                TextXAlignment   = Enum.TextXAlignment.Right,
            }) or nil,

            -- Card row
            cardRow = React.createElement("Frame", {
                Size                   = UDim2.fromScale(1, 1),
                BackgroundTransparency = 1,
            }, cardRowChildren),
        }),
    })
end

return VoteUI
