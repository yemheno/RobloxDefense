-- UI/HUD.lua
--
-- Always-visible heads-up display. Contains:
--   • Currency strip (top)  – Essence ♦  /  Merits ★
--   • Status bars  (bottom-left) – HP  /  Resource  /  XP
--   • Classes button (right)
--   • Talents button (right)
--
-- Data sources:
--   HP          → LocalPlayer character Humanoid  (pure client, no event needed)
--   Resource    → ResourceCache (early-subscribed module; eliminates queue-exhaustion)
--   XP / level  → NetworkManager "PlayerInfoUpdate" (extended payload)
--   Currency    → NetworkManager "PlayerInfoUpdate" + live "CurrencyUpdate"
--
-- All sizes are Scale-based for multi-resolution support.

local Players           = game:GetService("Players")
local GuiService        = game:GetService("GuiService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService      = game:GetService("TweenService")
local UserInputService  = game:GetService("UserInputService")
local Workspace         = game:GetService("Workspace")
local React             = require(ReplicatedStorage.Packages.React)

local Modules        = script.Parent.Parent:WaitForChild("Modules")
local NetworkManager = require(Modules:WaitForChild("NetworkManager"))
local ResourceCache  = require(Modules:WaitForChild("ResourceCache"))
local Locale         = require(Modules:WaitForChild("Locale"))
local LightningBar   = require(script.Parent:WaitForChild("Common"):WaitForChild("LightningBar"))

local LocalPlayer = Players.LocalPlayer
local cachedDefenseHP = nil

-- ── Palette ───────────────────────────────────────────────────────────────────
local C = {
	panel      = Color3.fromRGB( 18,  18,  24),
	bar_bg     = Color3.fromRGB( 35,  35,  50),
	bar_hp     = Color3.fromRGB( 80, 210,  90),
	bar_res    = Color3.fromRGB( 80, 160, 255),
	bar_xp     = Color3.fromRGB(210, 150,  40),
	essence_c  = Color3.fromRGB( 80, 210, 255),
	merits_c   = Color3.fromRGB(255, 200,  60),
	text       = Color3.fromRGB(220, 220, 230),
	text_dim   = Color3.fromRGB(140, 140, 160),
	white      = Color3.fromRGB(255, 255, 255),
	btn_bg     = Color3.fromRGB( 35,  35,  52),
	btn_text   = Color3.fromRGB(105, 190, 255),
	btn_stroke = Color3.fromRGB( 60, 100, 180),
}

-- ── §AGX/UI-P1: mobile placement + minimum sizes ─────────────────────────────
-- TODO(FormFactor): replace these with FormFactor / useFormFactor() and
-- Theme.Layout[formFactor] once that module lands (UI_REVAMP §3).
local MIN_TAP_PX  = 44   -- mobile.md §1.3 absolute floor
local EDGE_GAP_PX = 8
-- Client-local attributes on ReplicatedStorage (never replicated, since the
-- client writes them) that let sibling HUD pieces avoid each other until
-- the P5 HUD-regions split:
local ATTR_TOP_CENTRE = "UI_TopCentreReservedPx" -- BossHud: px it uses below safeTop
local ATTR_TL_BOTTOM  = "UI_TopLeftBottomPx"     -- HUD: bottom of the touch vitals stack
local ATTR_TL_X       = "UI_TopLeftXPx"          -- HUD: left edge of the touch vitals stack
local ATTR_TR_BOTTOM  = "UI_TopRightBottomPx"    -- HUD: bottom of menu/currency/killfeed block
local ATTR_NAV_TOP    = "UI_NavToggleTopPx"      -- HUD: top of the ⋮ toggle

-- TODO(FormFactor): touch-primary heuristic until FormFactor lands.
local function isTouchPrimary()
	return UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
end

local function minTap(w, h)
	return React.createElement("UISizeConstraint", {
		MinSize = Vector2.new(w or 0, h or MIN_TAP_PX),
	})
end

local function minText()
	return React.createElement("UITextSizeConstraint", { MinTextSize = 12 })
end

-- Live viewport size, so scale sizes can be floored in pixels.
local function useViewportSize()
	local function read()
		local cam = Workspace.CurrentCamera
		return cam and cam.ViewportSize or Vector2.new(1920, 1080)
	end
	local size, setSize = React.useState(read)
	React.useEffect(function()
		local vpConn
		local function bind()
			if vpConn then vpConn:Disconnect() vpConn = nil end
			local cam = Workspace.CurrentCamera
			if cam then
				vpConn = cam:GetPropertyChangedSignal("ViewportSize"):Connect(function()
					setSize(cam.ViewportSize)
				end)
			end
			setSize(read())
		end
		bind()
		local camConn = Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(bind)
		return function()
			camConn:Disconnect()
			if vpConn then vpConn:Disconnect() end
		end
	end, {})
	return size
end

-- Numeric attribute on an Instance, as React state.
local function useNumberAttribute(inst, name)
	local value, setValue = React.useState(function()
		return tonumber(inst:GetAttribute(name)) or 0
	end)
	React.useEffect(function()
		local conn = inst:GetAttributeChangedSignal(name):Connect(function()
			setValue(tonumber(inst:GetAttribute(name)) or 0)
		end)
		setValue(tonumber(inst:GetAttribute(name)) or 0)
		return function() conn:Disconnect() end
	end, {})
	return value
end

-- ── StatusBar ─────────────────────────────────────────────────────────────────
-- label | [====-------] | current / max
local function StatusBar(props)
	local label   = props.label   or "?"
	local current = math.max(props.current or 0, 0)
	local max     = math.max(props.max     or 1, 1)
	local color   = props.color
	local pct     = math.clamp(current / max, 0, 1)
	local valText = math.floor(current) .. " / " .. math.floor(max)

	-- §BEAUTY/P2: opt-in lightning crackle (effect = "lightning") — used by
	-- the Resource row. LightningBar brings its own track/fill chrome.
	local track
	if props.effect == "lightning" then
		track = React.createElement(LightningBar, {
			value       = pct,
			color       = color,
			position    = UDim2.fromScale(0.19, 0.15),
			size        = UDim2.fromScale(0.55, 0.70),
			anchorPoint = Vector2.new(0, 0),
			intensity   = 0.9,
			zIndex      = 2,
		})
	else
		track = React.createElement("Frame", {
			Position         = UDim2.fromScale(0.19, 0.15),
			Size             = UDim2.fromScale(0.55, 0.70),
			BackgroundColor3 = C.bar_bg,
			BorderSizePixel  = 0,
		}, {
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
			fill = React.createElement("Frame", {
				Size             = UDim2.fromScale(pct, 1),
				BackgroundColor3 = color,
				BorderSizePixel  = 0,
			}, {
				corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
			}),
		})
	end

	return React.createElement("Frame", {
		Size                   = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
	}, {
		lbl = React.createElement("TextLabel", {
			Position               = UDim2.fromScale(0, 0),
			Size                   = UDim2.fromScale(0.18, 1),
			BackgroundTransparency = 1,
			Text                   = label,
			TextColor3             = C.text_dim,
			Font                   = Enum.Font.GothamBold,
			TextScaled             = true,
			TextXAlignment         = Enum.TextXAlignment.Left,
		}, { minText = minText() }),  -- §AGX/UI-P1: 12 px text floor

		track = track,

		val = React.createElement("TextLabel", {
			Position               = UDim2.fromScale(0.75, 0),
			Size                   = UDim2.fromScale(0.25, 1),
			BackgroundTransparency = 1,
			Text                   = valText,
			TextColor3             = C.text,
			Font                   = Enum.Font.Gotham,
			TextScaled             = true,
			TextXAlignment         = Enum.TextXAlignment.Left,
		}, { minText = minText() }),  -- §AGX/UI-P1: 12 px text floor
	})
end

-- ── HUD ───────────────────────────────────────────────────────────────────────
local function HUD(props)
	local onClassesClick      = props.onClassesClick
	local onStatsClick        = props.onStatsClick
	local onTalentsClick      = props.onTalentsClick
	local onEquipClick        = props.onEquipClick
	local onCosmeticsClick    = props.onCosmeticsClick
	local onAchievementsClick = props.onAchievementsClick
	local onSettingsClick     = props.onSettingsClick
	local onShopClick         = props.onShopClick
	local onMenuClick         = props.onMenuClick
	local onPartyClick        = props.onPartyClick    -- nil in LaneDefense → no button
	local hideStartButton     = props.hideStartButton -- true in Lobby → hide Start Game
	local onDailyLoginClick  = props.onDailyLoginClick
	local onLeaderboardClick = props.onLeaderboardClick
	local onInventoryClick   = props.onInventoryClick
	-- §AGX/UX-02: the Apps keep the HUD mounted while a menu is open and
	-- pass hidden=true instead of unmounting it (unmounting reset
	-- gameState/runEnded/betweenWaves to their defaults mid-run).
	local hidden             = props.hidden

	-- Nav panel: collapsed / expanded
	local menuOpen, setMenuOpen = React.useState(false)
	local panelRef = React.useRef(nil)
	local didMount        = React.useRef(false)
	local closeTimerRef   = React.useRef(nil)

	-- Health (from the character Humanoid — updated via Roblox events, no server round-trip)
	local hp,  setHp  = React.useState({ cur = 100, max = 100 })

	-- §HUD-HP1: cosmetic HP override. Engine-side we pin Health=1
	-- during knockdown/death so Roblox's humanoid state machine doesn't
	-- tear down the character (§LD-DS5). UI-side we want the player to
	-- SEE 0 HP for dramatic feel — ninja style. We watch the DeathState
	-- attribute and zero the HP bar when not Alive.
	local deathState, setDeathState = React.useState(LocalPlayer:GetAttribute("DeathState") or "Alive")

	-- Class resource — seeded immediately from ResourceCache (prevents empty bar on mount)
	local res, setRes = React.useState(ResourceCache.GetLatest())

	-- XP & level from "PlayerInfoUpdate"
	local xpData, setXpData = React.useState({ cur = 0, max = 100, level = 1 })

	-- Currencies from "PlayerInfoUpdate" and live "CurrencyUpdate"
	local currency, setCurrency = React.useState({ essence = 0, merits = 0 })

	-- Power Level from "PlayerGearScore"
	local powerLevel, setPowerLevel = React.useState(0)

	-- Game state: "Idle" is the waiting state inside the defense place.
	-- Lobby never fires GameStateChanged so it stays at "Idle" — that's fine
	-- because hideStartButton suppresses the button there.
	local gameState, setGameState = React.useState("Idle")
	local countdown, setCountdown = React.useState(nil)
	-- §AGX/X14: true after Defeat/Victory until a new run starts.
	local runEnded, setRunEnded = React.useState(false)

	-- Combo counter from HitTracker (nil = hidden)
	local combo, setCombo = React.useState(nil)

	-- Wave info banner (nil = hidden)
	local waveInfo, setWaveInfo = React.useState(nil) -- { text, color }

	-- Defense line health
	local defenseHP, setDefenseHP = React.useState(nil) -- { cur, max, pct }

	-- Defense line combo
	local defCombo, setDefCombo = React.useState(nil) -- { level, multiplier, hitCount }

	-- Combo summary toast (ComboEnded)
	local comboSummary, setComboSummary = React.useState(nil)

	-- Death killfeed notification
	local deathNotice, setDeathNotice = React.useState(nil)

	-- Between-waves flag (true after WaveCompleted, false after WaveStarted)
	local betweenWaves, setBetweenWaves = React.useState(false)
	-- §AGX/UI-P1: the AppGui roots now use ScreenInsets = DeviceSafeInsets.
	-- That inset does NOT include the Roblox topbar, and in landscape (now
	-- forced) the device's top inset is 0, so GetGuiInset().Y is still the
	-- exact distance to clear and is not double-counted. Left/right notch
	-- trimming is done by the ScreenGui itself.
	local topLeftInset = select(1, GuiService:GetGuiInset())
	local safeTop = topLeftInset.Y + 10

	-- ── §AGX/UI-P1: pixel layout (floors for phones; desktop keeps scale) ──
	-- Measured AppGui size (DeviceSafeInsets makes it smaller than the
	-- camera viewport on notched phones, and scale sizes resolve against
	-- it); the viewport is only the first-frame fallback.
	local viewportFallback = useViewportSize()
	local guiSize, setGuiSize = React.useState(nil)
	local onRootSize = React.useCallback(function(rbx)
		local sz = rbx.AbsoluteSize
		if sz.X > 0 and sz.Y > 0 then setGuiSize(sz) end
	end, {})
	local viewport     = guiSize or viewportFallback
	local vpW, vpH     = viewport.X, viewport.Y
	local bossReserved = useNumberAttribute(ReplicatedStorage, ATTR_TOP_CENTRE)
	local touchLayout  = isTouchPrimary()  -- TODO(FormFactor)

	-- Top-right block (M7/V3): ☰ + currency strip BELOW the topbar, in the
	-- top-right corner Roblox leaves free; the killfeed goes under them.
	local menuW   = math.max(MIN_TAP_PX, 0.05 * vpW)
	local menuH   = math.max(MIN_TAP_PX, 0.07 * vpH)
	local stripH  = math.max(28, 0.055 * vpH)
	local topRowH = onMenuClick and math.max(menuH, stripH) or stripH
	local stripRightInset = onMenuClick and (menuW + EDGE_GAP_PX) or 0
	local feedY   = safeTop + topRowH + EDGE_GAP_PX
	local feedH   = math.max(22, 0.04 * vpH)
	local topRightBottom = feedY + feedH + EDGE_GAP_PX

	-- Right-middle ⋮ toggle
	local toggleH   = math.max(MIN_TAP_PX, 0.09 * vpH)
	local toggleTop = 0.5 * vpH - toggleH / 2

	-- Top-centre column: BossHud (if any) owns safeTop..safeTop+bossReserved;
	-- Start / Next Wave / Return and then the wave banner stack below it.
	local btnY  = safeTop + math.max(34, bossReserved)
	local btnH  = math.max(MIN_TAP_PX, 0.065 * vpH)
	local showStart     = (not hideStartButton) and (gameState == "Idle")
	local showCountdown = countdown ~= nil
	local showNextWave  = (not hideStartButton) and (gameState == "Defending") and betweenWaves
	local showReturn    = (not hideStartButton)
		and (gameState == "Defeat" or gameState == "Victory" or (gameState == "Idle" and runEnded))
	-- Return keeps its old scale spot on desktop, but never above the column
	-- (0.14 x 390 = 55 px was under the topbar on phones) and, in Idle,
	-- always below the Start button.
	local returnY = math.max((gameState == "Idle" and 0.22 or 0.14) * vpH,
		btnY + ((gameState == "Idle") and (btnH + EDGE_GAP_PX) or 0))
	local columnBottom = safeTop + bossReserved
	if showStart or showCountdown or showNextWave then
		columnBottom = math.max(columnBottom, btnY + btnH)
	end
	if showReturn then
		columnBottom = math.max(columnBottom, returnY + btnH)
	end
	local bannerY = math.max(safeTop + 88, columnBottom + EDGE_GAP_PX)

	-- Vitals (M9): bottom-left sits under the left thumbstick on phones, so
	-- on touch they move to the top-left under the topbar. In combat the
	-- BattleClassUI badge owns (safeLeft, safeTop+40, 0.13W x 0.07H)
	-- (BattleClassUI.lua:419,444), so the stack starts right of it and stops
	-- short of the top-centre button column (0.5W - 0.08W).
	-- TODO(FormFactor): §2.5 hides the class badge on phones; then use x = 16.
	local statusH    = math.max(72, 0.17 * vpH)
	local defenseH   = math.max(24, 0.05 * vpH)
	local inCombat   = not hideStartButton
	local vitalsX    = inCombat and (0.14 * vpW + EDGE_GAP_PX) or (0.01 * vpW)
	local vitalsMaxW = inCombat and math.max(200, 0.42 * vpW - EDGE_GAP_PX - vitalsX) or math.huge
	local vitalsW    = math.min(math.max(280, 0.32 * vpW), vitalsMaxW)
	local topLeftBottom = safeTop + statusH
		+ ((defenseHP ~= nil) and (6 + defenseH) or 0) + EDGE_GAP_PX

	-- Publish the regions TeammateVitals needs (client-local attributes).
	React.useEffect(function()
		ReplicatedStorage:SetAttribute(ATTR_TL_BOTTOM, touchLayout and topLeftBottom or nil)
		ReplicatedStorage:SetAttribute(ATTR_TL_X, touchLayout and vitalsX or nil)
		ReplicatedStorage:SetAttribute(ATTR_TR_BOTTOM, topRightBottom)
		ReplicatedStorage:SetAttribute(ATTR_NAV_TOP, toggleTop)
	end, { touchLayout, topLeftBottom, vitalsX, topRightBottom, toggleTop })
	React.useEffect(function()
		return function()
			ReplicatedStorage:SetAttribute(ATTR_TL_BOTTOM, nil)
			ReplicatedStorage:SetAttribute(ATTR_TL_X, nil)
			ReplicatedStorage:SetAttribute(ATTR_TR_BOTTOM, nil)
			ReplicatedStorage:SetAttribute(ATTR_NAV_TOP, nil)
		end
	end, {})

	-- Nav grid (T3): cells in pixels with a 44 px floor; the panel scrolls
	-- when 6 rows no longer fit (phones). 1080p values equal the old scales.
	local navPanelH = 0.62 * vpH
	local navCellH  = math.max(MIN_TAP_PX, 0.135 * navPanelH)
	local navGapY   = 0.018 * navPanelH
	local navPadY   = 0.02 * navPanelH

	-- ── Wire up events ────────────────────────────────────────────────────────
	local mountedRef = React.useRef(true)
	local comboTimeoutRef = React.useRef(nil)
	React.useEffect(function()
		if cachedDefenseHP ~= nil then
			setDefenseHP(cachedDefenseHP)
		end

		-- Request initial snapshot from the server
		NetworkManager.FireServer("GetPlayerInfo")
		-- §AGX/UX-02: GameStateChanged only fires on transitions, so a HUD
		-- that mounts mid-run (late join, respawned ScreenGui) would sit in
		-- "Idle" and show Start Game. Ask for a snapshot; the reply arrives
		-- as a GameStateChanged. Lobby (hideStartButton) has no state machine.
		if not hideStartButton then
			NetworkManager.FireServer("RequestGameState")
		end

-- ResourceCache handles the early subscription; we just register as a
		-- downstream subscriber here so the HUD stays in sync with live updates.
		local resUnsub = ResourceCache.Subscribe(function(data)
			setRes({
				cur  = data.cur  or 0,
				max  = data.max  or 100,
				name = data.name or "Resource",
			})
		end)

		-- PlayerInfoUpdate: receives XP, currency, and initial resource snapshot
		local infoConn = NetworkManager.OnServerEvent("PlayerInfoUpdate", function(data)
			if data.xp ~= nil then
				setXpData({
					cur   = data.xp       or 0,
					max   = data.xpNeeded or 100,
					level = data.level    or 1,
				})
			end
			if data.essence ~= nil or data.merits ~= nil then
				setCurrency({
					essence = data.essence or 0,
					merits  = data.merits  or 0,
				})
			end
			-- Seed initial resource values before the first ResourceUpdate tick arrives
			if data.resource ~= nil then
				setRes({
					cur  = data.resource     or 0,
					max  = data.maxResource  or 100,
					name = data.resourceName or "Resource",
				})
			end
		end)

		-- CurrencyUpdate: live updates whenever merits/essence change on the server
		local curConn = NetworkManager.OnServerEvent("CurrencyUpdate", function(data)
			setCurrency({
				essence = data.essence or 0,
				merits  = data.merits  or 0,
			})
		end)

		-- PowerLevel: subscribe to gear score / power level updates
		local powerConn = NetworkManager.OnServerEvent("PlayerGearScore", function(data)
			if data and data.score then
				setPowerLevel(data.score)
			end
		end)
		-- Request initial power level from server
		NetworkManager.FireServer("PlayerGearScore")

		-- GameStateChanged: track lobby / defending etc. so we can show the Start button
		local stateConn = NetworkManager.OnServerEvent("GameStateChanged", function(data)
			setGameState(data.newState or "Lobby")
			-- §AGX/X14: remember that a run ended so Return stays reachable
			-- in the post-run Idle state if the return teleport fails.
			if data.newState == "Defeat" or data.newState == "Victory" then
				setRunEnded(true)
			elseif data.newState == "Preparing" or data.newState == "Defending" then
				setRunEnded(false)
			end
			if data.newState ~= "Preparing" then
				setCountdown(nil)
			end
			-- §AGX/UX-02: RequestGameState snapshots carry the flags that
			-- transitions alone can't rebuild (both optional).
			if data.runEnded ~= nil then
				setRunEnded(data.runEnded == true)
			end
			if data.betweenWaves ~= nil then
				setBetweenWaves(data.betweenWaves == true)
			end
		end)

		-- CountdownUpdate: show "Starting in N..." while the countdown runs
		local cdConn = NetworkManager.OnServerEvent("CountdownUpdate", function(data)
			if (data.remaining or 0) > 0 then
				setCountdown(data.remaining)
			else
				setCountdown(nil)
			end
		end)

		-- ComboUpdate: consume server event (prevents queue exhaustion) + show counter
		local comboConn = NetworkManager.OnServerEvent("ComboUpdate", function(data)
			setCombo(data.current or 0)
			-- Auto-hide the counter 3 s after the last hit (mirrors server decay time)
			if comboTimeoutRef.current then
				task.cancel(comboTimeoutRef.current)
			end
			comboTimeoutRef.current = task.delay(3, function()
				setCombo(nil)
			end)
		end)

		-- WaveStarted: show "Wave N" banner
		local waveStartConn = NetworkManager.OnServerEvent("WaveStarted", function(data)
			setBetweenWaves(false)
			setWaveInfo({
				text  = "WAVE " .. tostring(data.wave or "?") .. "  (" .. tostring(data.mobCount or 0) .. " mobs)",
				color = Color3.fromRGB(80, 210, 255),
			})
			task.delay(3, function() if mountedRef.current then setWaveInfo(nil) end end)
		end)

		-- WaveCompleted: show "Wave N Cleared" banner
		local waveCompleteConn = NetworkManager.OnServerEvent("WaveCompleted", function(data)
			setBetweenWaves(true)
			setWaveInfo({
				text  = "WAVE " .. tostring(data.wave or "?") .. " CLEARED!",
				color = Color3.fromRGB(80, 255, 120),
			})
			task.delay(3, function() if mountedRef.current then setWaveInfo(nil) end end)
		end)

		-- AllWavesCompleted: show victory banner
		local allWavesConn = NetworkManager.OnServerEvent("AllWavesCompleted", function(data)
			setWaveInfo({
				text  = "ALL WAVES CLEARED!  (Wave " .. tostring(data.finalWave or "?") .. ")",
				color = Color3.fromRGB(255, 215, 0),
			})
			-- Don't auto-hide — let it stay
		end)

		-- DefenseLineUpdate: live HP sync for the defense line bar
		local defUpdateConn = NetworkManager.OnServerEvent("DefenseLineUpdate", function(data)
			cachedDefenseHP = {
				cur = data.currentHealth or 0,
				max = data.maxHealth     or 1,
				pct = data.percent       or 0,
			}
			setDefenseHP(cachedDefenseHP)
		end)

		-- DefenseLineDamaged: flash + update HP
		local defDmgConn = NetworkManager.OnServerEvent("DefenseLineDamaged", function(data)
			cachedDefenseHP = {
				cur = data.currentHealth or 0,
				max = data.maxHealth     or 1,
				pct = data.percent       or 0,
			}
			setDefenseHP(cachedDefenseHP)
		end)

		-- DefenseLineDestroyed: set to zero
		local defDestroyConn = NetworkManager.OnServerEvent("DefenseLineDestroyed", function(data)
			cachedDefenseHP = {
				cur = 0,
				max = data.maxHealth or 1,
				pct = 0,
			}
			setDefenseHP(cachedDefenseHP)
			setWaveInfo({
				text  = "DEFENSE LINE DESTROYED!",
				color = Color3.fromRGB(255, 60, 60),
			})
		end)

		-- DefenseLineCombo: defense line combo multiplier display
		local defComboConn = NetworkManager.OnServerEvent("DefenseLineCombo", function(data)
			if data.ended then
				setDefCombo(nil)
			else
				setDefCombo({
					level      = data.level      or 0,
					multiplier = data.multiplier  or 1,
					hitCount   = data.hitCount    or 0,
				})
			end
		end)

		-- PlayerDeath: killfeed notification
		local deathConn = NetworkManager.OnServerEvent("PlayerDeath", function(data)
			setDeathNotice(
				(data.playerName or "???") .. " was slain by "
				.. (data.killerMob or "a mob")
			)
			task.delay(4, function() if mountedRef.current then setDeathNotice(nil) end end)
		end)

		-- ComboEnded: personal summary toast
		local comboEndConn = NetworkManager.OnServerEvent("ComboEnded", function(data)
			setComboSummary({
				combo  = data.finalCombo  or 0,
				damage = data.totalDamage or 0,
				crits  = data.totalCrits  or 0,
				best   = data.best        or 0,
			})
			task.delay(4, function() if mountedRef.current then setComboSummary(nil) end end)
		end)

		-- MobDeath: consume the event (prevents queue exhaustion).
		-- Actual death VFX are handled by MobVisuals; HUD just drains the queue.
		local mobDeathConn = NetworkManager.OnServerEvent("MobDeath", function(_data) end)

		-- Health: read directly from the Humanoid; reconnect on respawn
		local hpConn     = nil
		local maxHpConn  = nil
		local charAddedConn = nil

		local function connectHumanoid(character)
			local humanoid = character:WaitForChild("Humanoid", 5)
			if not humanoid then return end
			setHp({ cur = humanoid.Health, max = humanoid.MaxHealth })
			hpConn = humanoid.HealthChanged:Connect(function(newHp)
				setHp({ cur = newHp, max = humanoid.MaxHealth })
			end)
			-- Also track MaxHealth changes (e.g. when VIT stats are applied)
			maxHpConn = humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
				setHp({ cur = humanoid.Health, max = humanoid.MaxHealth })
			end)
		end

		charAddedConn = LocalPlayer.CharacterAdded:Connect(function(char)
			if hpConn then hpConn:Disconnect() hpConn = nil end
			if maxHpConn then maxHpConn:Disconnect() maxHpConn = nil end
			connectHumanoid(char)
		end)

		if LocalPlayer.Character then
			connectHumanoid(LocalPlayer.Character)
		end

		-- §HUD-HP1: track DeathState attribute for the cosmetic 0-HP
		-- override.
		local deathStateConn = LocalPlayer:GetAttributeChangedSignal("DeathState"):Connect(function()
			setDeathState(LocalPlayer:GetAttribute("DeathState") or "Alive")
		end)

		return function()
			mountedRef.current = false
			if resUnsub      then resUnsub()                 end
			if infoConn      then infoConn:Disconnect()      end
			if curConn       then curConn:Disconnect()       end
			if powerConn     then powerConn:Disconnect()     end
			if stateConn     then stateConn:Disconnect()     end
			if deathStateConn then deathStateConn:Disconnect() end
			if cdConn        then cdConn:Disconnect()        end
			if comboConn     then comboConn:Disconnect()     end
			if comboTimeoutRef.current then task.cancel(comboTimeoutRef.current) end
			if waveStartConn    then waveStartConn:Disconnect()    end
			if waveCompleteConn then waveCompleteConn:Disconnect() end
			if allWavesConn     then allWavesConn:Disconnect()     end
			if defUpdateConn    then defUpdateConn:Disconnect()    end
			if defDmgConn       then defDmgConn:Disconnect()       end
			if defDestroyConn   then defDestroyConn:Disconnect()   end
			if defComboConn     then defComboConn:Disconnect()     end
			if deathConn        then deathConn:Disconnect()        end
			if comboEndConn     then comboEndConn:Disconnect()     end
			if mobDeathConn     then mobDeathConn:Disconnect()     end
			if charAddedConn then charAddedConn:Disconnect() end
			if hpConn        then hpConn:Disconnect()        end
			if maxHpConn     then maxHpConn:Disconnect()     end
		end
	end, {})

	-- ── Nav panel slide animation ──────────────────────────────────────────
	React.useEffect(function()
		local frame = panelRef.current
		if not frame then return end

		if not didMount.current then
			-- First mount: park off-screen and hide immediately (no flash)
			frame.Position = UDim2.fromScale(1.20, 0.50)
			frame.Visible  = false
			didMount.current = true
			return
		end

		if menuOpen then
			-- Cancel any pending close-hide timer so a quick toggle doesn't hide the panel
			if closeTimerRef.current then
				task.cancel(closeTimerRef.current)
				closeTimerRef.current = nil
			end
			frame.Visible = true
			TweenService:Create(
				frame,
				TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out),
				{ Position = UDim2.fromScale(0.985, 0.50) }
			):Play()
		else
			local CLOSE_TIME = 0.13
			TweenService:Create(
				frame,
				TweenInfo.new(CLOSE_TIME, Enum.EasingStyle.Quart, Enum.EasingDirection.In),
				{ Position = UDim2.fromScale(1.20, 0.50) }
			):Play()
			closeTimerRef.current = task.delay(CLOSE_TIME, function()
				closeTimerRef.current = nil
				if frame and frame.Parent then frame.Visible = false end
			end)
		end
	end, { menuOpen })

	-- ── Currency pill ─────────────────────────────────────────────────────────
	local function CurrencyPill(pillProps)
		return React.createElement("Frame", {
			-- §AGX/UI-P1: 3 pills fill the (now 0.30-wide) right-aligned strip.
			Size             = UDim2.fromScale(0.31, 0.75),
			BackgroundColor3 = Color3.fromRGB(28, 28, 42),
			BorderSizePixel  = 0,
			LayoutOrder      = pillProps.order,
		}, {
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.3, 0) }),
			lbl = React.createElement("TextLabel", {
				Size               = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text               = pillProps.icon .. "  " .. tostring(pillProps.value),
				TextColor3         = pillProps.color,
				Font               = Enum.Font.GothamBold,
				TextScaled         = true,
			}, { minText = minText() }),  -- §AGX/UI-P1: 12 px text floor
		})
	end

	-- ── Layout ────────────────────────────────────────────────────────────────
	return React.createElement("Frame", {
		Name                   = "HUD",
		Size                   = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible                = not hidden,  -- §AGX/UX-02: hide, don't unmount
		[React.Change.AbsoluteSize] = onRootSize,  -- §AGX/UI-P1: gui-space layout maths
	}, {
		-- ── Top-right: Menu button ────────────────────────────────────────────
		-- §UI-HUD1: was 3.5% × 5% — at 1080p that's 67×54, at higher resolutions
		-- the icon was unclickable. Bumped to 5% × 7% pure-scale per the
		-- "no hardcoded pixel sizes" rule.
		-- §AGX/UI-P1: M7/V3/T1: was top-left at (0.005, 0.008), i.e. under
		-- Roblox's own menu button on phones (the only non-NPC route to
		-- matchmaking). Now top-right, below the topbar (safeTop), with a
		-- 44x44 floor. Same 5% x 7% size on desktop.
		menuBtn = onMenuClick and React.createElement("TextButton", {
			AnchorPoint      = Vector2.new(1, 0),
			Position         = UDim2.new(0.995, 0, 0, safeTop),
			Size             = UDim2.fromScale(0.05, 0.07),
			BackgroundColor3 = C.btn_bg,
			BorderSizePixel  = 0,
			Text             = "☰",
			TextColor3       = C.btn_text,
			Font             = Enum.Font.GothamBold,
			TextScaled       = true,
			ZIndex           = 4,
			[React.Event.Activated] = onMenuClick,
		}, {
			minSize = minTap(MIN_TAP_PX, MIN_TAP_PX),  -- §AGX/UI-P1
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.2, 0) }),
			stroke = React.createElement("UIStroke", {
				Color        = C.btn_stroke,
				Thickness    = 1.5,
				Transparency = 0,
			}),
		}) or nil,

		-- ── Top strip: currency counters ──────────────────────────────────────
		-- §AGX/UI-P1: M7/V3: was (0.04, 0) x (0.96, 0.055), i.e. inside the
		-- topbar band. Now right-aligned below the topbar, left of the ☰, with
		-- a 28 px height floor so the pill text stays readable. Width 0.30 so
		-- it stays right of the top-centre column (Start/Next: 0.42-0.58 W;
		-- BossHud bar: 0.32-0.68 W) at every resolution. Pills are narrower
		-- than before (0.093 W vs 0.192 W); same height, colours and text.
		currencyStrip = React.createElement("Frame", {
			AnchorPoint            = Vector2.new(1, 0),
			Position               = UDim2.new(0.995, -stripRightInset, 0, safeTop),
			Size                   = UDim2.fromScale(0.30, 0.055),
			BackgroundColor3       = C.panel,
			BackgroundTransparency = 0.30,
			BorderSizePixel        = 0,
		}, {
			minSize = minTap(0, 28),  -- §AGX/UI-P1
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.2, 0) }),
			layout = React.createElement("UIListLayout", {
				FillDirection       = Enum.FillDirection.Horizontal,
				VerticalAlignment   = Enum.VerticalAlignment.Center,
				HorizontalAlignment = Enum.HorizontalAlignment.Right,
				SortOrder           = Enum.SortOrder.LayoutOrder,
				Padding             = UDim.new(0.008, 0),
			}),
			pad = React.createElement("UIPadding", {
				PaddingLeft  = UDim.new(0.01, 0),
				PaddingRight = UDim.new(0.01, 0),  -- §AGX/UI-P1: right-aligned now
			}),

			essencePill = React.createElement(CurrencyPill, {
				icon  = "♦",
				value = currency.essence,
				color = C.essence_c,
				order = 1,
			}),
			meritsPill = React.createElement(CurrencyPill, {
				icon  = "★",
				value = currency.merits,
				color = C.merits_c,
				order = 2,
			}),
			powerPill = React.createElement(CurrencyPill, {
				icon  = "⚡",
				value = powerLevel,
				color = Color3.fromRGB(255, 180, 40),
				order = 3,
			}),
		}),

		-- ── Bottom-left panel: status bars ────────────────────────────────────
		-- §AGX/UI-P1: M9: on touch, top-left under the topbar (off the left
		-- thumbstick). Desktop keeps bottom-left with a readable-size floor.
		statusPanel = React.createElement("Frame", {
			AnchorPoint      = touchLayout and Vector2.new(0, 0) or Vector2.new(0, 1),
			Position         = touchLayout and UDim2.fromOffset(vitalsX, safeTop)
				or UDim2.fromScale(0.01, 0.985),
			Size             = touchLayout and UDim2.fromOffset(vitalsW, statusH)
				or UDim2.fromScale(0.32, 0.17),
			BackgroundColor3 = C.panel,
			BackgroundTransparency = 0.30,
			BorderSizePixel  = 0,
		}, {
			minSize = (not touchLayout) and React.createElement("UISizeConstraint", {
				MinSize = Vector2.new(280, 72),  -- §AGX/UI-P1
			}) or nil,
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.04, 0) }),
			layout = React.createElement("UIListLayout", {
				FillDirection     = Enum.FillDirection.Vertical,
				VerticalAlignment = Enum.VerticalAlignment.Center,
				SortOrder         = Enum.SortOrder.LayoutOrder,
				Padding           = UDim.new(0.03, 0),
			}),
			pad = React.createElement("UIPadding", {
				PaddingLeft   = UDim.new(0.03, 0),
				PaddingRight  = UDim.new(0.03, 0),
				PaddingTop    = UDim.new(0.03, 0),
				PaddingBottom = UDim.new(0.03, 0),
			}),

			-- HP row
			hpRow = React.createElement("Frame", {
				Size               = UDim2.fromScale(1, 0.27),
				BackgroundTransparency = 1,
				LayoutOrder        = 1,
			}, {
				bar = React.createElement(StatusBar, {
					label   = "HP",
					-- §HUD-HP1: 0 HP when knocked down or dead, real HP otherwise.
					current = (deathState == "Alive") and hp.cur or 0,
					max     = hp.max,
					color   = C.bar_hp,
				}),
			}),

			-- Resource row
			resRow = React.createElement("Frame", {
				Size               = UDim2.fromScale(1, 0.27),
				BackgroundTransparency = 1,
				LayoutOrder        = 2,
			}, {
				bar = React.createElement(StatusBar, {
					label   = res.name,
					current = res.cur,
					max     = res.max,
					color   = C.bar_res,
					effect  = "lightning",  -- §BEAUTY/P2: mana crackle
				}),
			}),

			-- XP row
			xpRow = React.createElement("Frame", {
				Size               = UDim2.fromScale(1, 0.27),
				BackgroundTransparency = 1,
				LayoutOrder        = 3,
			}, {
				bar = React.createElement(StatusBar, {
					label   = "Lv" .. xpData.level,
					current = xpData.cur,
					max     = xpData.max,
					color   = C.bar_xp,
				}),
			}),
		}),

		-- ── Top-centre: Start Game button (Idle in defense) / Countdown badge (Preparing) ─
		-- §AGX/UI-P1: T4: 44 px floor; pushed below BossHud's slot (btnY).
		startBtn = showStart and React.createElement("TextButton", {
			AnchorPoint      = Vector2.new(0.5, 0),
			Position         = UDim2.new(0.5, 0, 0, btnY),
			Size             = UDim2.fromScale(0.16, 0.065),
			BackgroundColor3 = Color3.fromRGB(50, 160, 70),
			BorderSizePixel  = 0,
			Text             = "▶  Start Game",
			TextColor3       = Color3.fromRGB(255, 255, 255),
			Font             = Enum.Font.GothamBold,
			TextScaled       = true,
			ZIndex           = 3,
			[React.Event.Activated] = function()
				NetworkManager.FireServer("RequestStartGame")
			end,
		}, {
			minSize = minTap(120, MIN_TAP_PX),  -- §AGX/UI-P1
			minText = minText(),
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.35, 0) }),
		}) or nil,

		countdownBadge = showCountdown and React.createElement("TextLabel", {
			AnchorPoint            = Vector2.new(0.5, 0),
			Position               = UDim2.new(0.5, 0, 0, btnY),  -- §AGX/UI-P1
			Size                   = UDim2.fromScale(0.16, 0.065),
			BackgroundColor3       = Color3.fromRGB(200, 140, 30),
			BackgroundTransparency = 0,
			BorderSizePixel        = 0,
			Text                   = "Starting in " .. tostring(countdown) .. "...",
			TextColor3             = Color3.fromRGB(255, 255, 255),
			Font                   = Enum.Font.GothamBold,
			TextScaled             = true,
			ZIndex                 = 3,
		}, {
			minSize = minTap(120, MIN_TAP_PX),  -- §AGX/UI-P1: same slot size as Start
			minText = minText(),
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.35, 0) }),
		}) or nil,

		-- ── Bottom-centre: Combo counter (visible when combo ≥ 3) ────────────────
		comboBadge = (combo ~= nil and combo >= 3) and React.createElement("Frame", {
			AnchorPoint      = Vector2.new(0.5, 1),
			Position         = UDim2.fromScale(0.5, 0.92),
			Size             = UDim2.fromScale(0.14, 0.07),
			BackgroundColor3 = Color3.fromRGB(20, 20, 30),
			BackgroundTransparency = 0.25,
			BorderSizePixel  = 0,
			ZIndex           = 3,
		}, {
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.3, 0) }),
			stroke = React.createElement("UIStroke", {
				Color        = Color3.fromRGB(255, 200, 50),
				Thickness    = 2,
				Transparency = 0,
			}),
			lbl = React.createElement("TextLabel", {
				Size                   = UDim2.fromScale(1, 0.55),
				Position               = UDim2.fromScale(0, 0),
				BackgroundTransparency = 1,
				Text                   = tostring(combo) .. "x  COMBO",
				TextColor3             = Color3.fromRGB(255, 210, 60),
				Font                   = Enum.Font.GothamBold,
				TextScaled             = true,
			}, { minText = minText() }),  -- §AGX/UI-P1
		}) or nil,

		-- ── Top-centre: Wave banner (appears briefly when waves start/end) ───────
		waveBanner = (waveInfo ~= nil) and React.createElement("TextLabel", {
			AnchorPoint            = Vector2.new(0.5, 0),
			-- §AGX/UI-P1: M9: below BossHud and any visible top-centre button.
			Position               = UDim2.new(0.5, 0, 0, bannerY),
			Size                   = UDim2.fromScale(0.30, 0.055),
			BackgroundColor3       = Color3.fromRGB(20, 20, 30),
			BackgroundTransparency = 0.20,
			BorderSizePixel        = 0,
			Text                   = waveInfo.text,
			TextColor3             = waveInfo.color or C.white,
			Font                   = Enum.Font.GothamBold,
			TextScaled             = true,
			ZIndex                 = 3,
		}, {
			minSize = minTap(0, 24),  -- §AGX/UI-P1: room for 12 px text
			minText = minText(),
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.35, 0) }),
			stroke = React.createElement("UIStroke", {
				Color     = waveInfo.color or C.white,
				Thickness = 1.5,
				Transparency = 0.4,
			}),
		}) or nil,

		-- ── Bottom-left: Defense line HP bar (only when defenseHP is known) ──────
		-- §AGX/UI-P1: M9: on touch, stacked under the vitals (top-left).
		defenseBar = (defenseHP ~= nil) and React.createElement("Frame", {
			AnchorPoint      = touchLayout and Vector2.new(0, 0) or Vector2.new(0, 1),
			Position         = touchLayout and UDim2.fromOffset(vitalsX, safeTop + statusH + 6)
				or UDim2.fromScale(0.01, 0.80),
			Size             = touchLayout and UDim2.fromOffset(vitalsW, defenseH)
				or UDim2.fromScale(0.32, 0.05),
			BackgroundColor3 = C.panel,
			BackgroundTransparency = 0.30,
			BorderSizePixel  = 0,
			ZIndex           = 3,
		}, {
			minSize = (not touchLayout) and React.createElement("UISizeConstraint", {
				MinSize = Vector2.new(280, 24),  -- §AGX/UI-P1
			}) or nil,
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.3, 0) }),
			bar = React.createElement(StatusBar, {
				label   = "Defense",
				current = defenseHP.cur,
				max     = defenseHP.max,
				color   = Color3.fromRGB(210, 80, 80),
			}),
		}) or nil,

		-- ── Bottom-centre: Defense line combo badge ─────────────────────────────
		defComboBadge = (defCombo ~= nil and defCombo.level >= 1) and React.createElement("TextLabel", {
			AnchorPoint            = Vector2.new(0.5, 1),
			Position               = UDim2.fromScale(0.5, 0.84),
			Size                   = UDim2.fromScale(0.18, 0.04),
			BackgroundColor3       = Color3.fromRGB(30, 20, 40),
			BackgroundTransparency = 0.20,
			BorderSizePixel        = 0,
			Text                   = "Defense Combo Lv" .. tostring(defCombo.level)
				.. "  x" .. string.format("%.1f", defCombo.multiplier),
			TextColor3             = Color3.fromRGB(255, 180, 80),
			Font                   = Enum.Font.GothamBold,
			TextScaled             = true,
			ZIndex                 = 3,
		}, {
			minSize = minTap(0, 22),  -- §AGX/UI-P1: room for 12 px text
			minText = minText(),
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.35, 0) }),
		}) or nil,

		-- ── Top-right: Death killfeed notice ────────────────────────────────────
		deathFeed = (deathNotice ~= nil) and React.createElement("TextLabel", {
			AnchorPoint            = Vector2.new(1, 0),
			-- §AGX/UI-P1: M9: under the top-right ☰/currency row (was safeTop+52,
			-- which the moved strip now occupies); 22 px floor for 12 px text.
			Position               = UDim2.new(0.98, 0, 0, feedY),
			Size                   = UDim2.new(0.24, 0, 0, feedH),
			BackgroundColor3       = Color3.fromRGB(60, 15, 15),
			BackgroundTransparency = 0.25,
			BorderSizePixel        = 0,
			Text                   = deathNotice,
			TextColor3             = Color3.fromRGB(255, 100, 100),
			Font                   = Enum.Font.GothamBold,
			TextScaled             = true,
			ZIndex                 = 4,
		}, {
			minText = minText(),  -- §AGX/UI-P1
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.3, 0) }),
		}) or nil,

		-- ── Centre: Combo summary toast (personal) ──────────────────────────────
		comboToast = (comboSummary ~= nil) and React.createElement("TextLabel", {
			AnchorPoint            = Vector2.new(0.5, 0.5),
			Position               = UDim2.fromScale(0.5, 0.40),
			Size                   = UDim2.fromScale(0.22, 0.06),
			BackgroundColor3       = Color3.fromRGB(25, 20, 40),
			BackgroundTransparency = 0.15,
			BorderSizePixel        = 0,
			Text                   = tostring(comboSummary.combo) .. "x Combo!  "
					.. tostring(math.floor(comboSummary.damage)) .. " dmg  "
				.. tostring(comboSummary.crits) .. " crits",
			TextColor3             = Color3.fromRGB(255, 210, 60),
			Font                   = Enum.Font.GothamBold,
			TextScaled             = true,
			ZIndex                 = 5,
		}, {
			minSize = minTap(0, 24),  -- §AGX/UI-P1
			minText = minText(),
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.3, 0) }),
			stroke = React.createElement("UIStroke", {
				Color     = Color3.fromRGB(200, 160, 40),
				Thickness = 1.5,
				Transparency = 0.3,
			}),
		}) or nil,

		-- ── Top-centre: "Next Wave" button (visible between waves) ──────────────
		-- §AGX/UI-P1: T4: 44 px floor; below BossHud's slot (CentralBoss, M9).
		nextWaveBtn = showNextWave and React.createElement("TextButton", {
			AnchorPoint      = Vector2.new(0.5, 0),
			Position         = UDim2.new(0.5, 0, 0, btnY),
			Size             = UDim2.fromScale(0.16, 0.065),
			BackgroundColor3 = Color3.fromRGB(40, 130, 200),
			BorderSizePixel  = 0,
			Text             = "Next Wave  >>",
			TextColor3       = Color3.fromRGB(255, 255, 255),
			Font             = Enum.Font.GothamBold,
			TextScaled       = true,
			ZIndex           = 3,
			[React.Event.Activated] = function()
				NetworkManager.FireServer("RequestNextWave")
			end,
		}, {
			minSize = minTap(120, MIN_TAP_PX),  -- §AGX/UI-P1
			minText = minText(),
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.35, 0) }),
		}) or nil,

		-- ── Top-centre: "Return to Lobby" button (game over or victory) ────────
		-- §AGX/X14: also shown in post-run Idle (runEnded) — if the return
		-- teleport fails, players otherwise sit in Idle with no way out.
		-- Nudged below the Idle Start button so the two don't overlap.
		-- §AGX/UI-P1: T4: 44 px floor; returnY never under the topbar/BossHud.
		returnBtn = showReturn
			and React.createElement("TextButton", {
				AnchorPoint      = Vector2.new(0.5, 0),
				Position         = UDim2.new(0.5, 0, 0, returnY),
				Size             = UDim2.fromScale(0.16, 0.065),
				BackgroundColor3 = Color3.fromRGB(160, 60, 60),
				BorderSizePixel  = 0,
				Text             = "Return to Lobby",
				TextColor3       = Color3.fromRGB(255, 255, 255),
				Font             = Enum.Font.GothamBold,
				TextScaled       = true,
				ZIndex           = 3,
				[React.Event.Activated] = function()
					NetworkManager.FireServer("RequestReturnToLobby")
				end,
			}, {
				minSize = minTap(120, MIN_TAP_PX),  -- §AGX/UI-P1
				minText = minText(),
				corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.35, 0) }),
			}) or nil,

		-- ── Right: Classes + Stats buttons ─────────────────────────────────────
		-- Nav toggle button: always visible, slides the panel open/closed
		-- §UI-HUD2: bumped from 5.5% × 7.5% → 7% × 9% so the ⋮/✕ chip is
		-- comfortably clickable at any viewport.
		navToggle = React.createElement("TextButton", {
			AnchorPoint      = Vector2.new(1, 0.5),
			Position         = UDim2.fromScale(0.985, 0.50),
			Size             = UDim2.fromScale(0.07, 0.09),
			BackgroundColor3 = menuOpen and Color3.fromRGB(60, 45, 80) or C.btn_bg,
			BorderSizePixel  = 0,
			Text             = menuOpen and "✕" or "⋮",
			TextColor3       = menuOpen and Color3.fromRGB(200, 170, 255) or C.btn_text,
			Font             = Enum.Font.GothamBold,
			TextScaled       = true,
			ZIndex           = 6,
			[React.Event.Activated] = function() setMenuOpen(not menuOpen) end,
		}, {
			minSize = minTap(MIN_TAP_PX, MIN_TAP_PX),  -- §AGX/UI-P1: T2 (was 59x35 on iPhone)
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.2, 0) }),
			stroke = React.createElement("UIStroke", {
				Color        = menuOpen and Color3.fromRGB(120, 80, 200) or C.btn_stroke,
				Thickness    = 1.5,
				Transparency = 0,
			}),
		}),

		-- Nav panel: slides from right via TweenService (Position controlled by panelRef effect).
		-- §UI-HUD3: navPanel was AutomaticSize.Y with a pixel-sized grid
		-- (CellSize 0,36 height + 0,5 padding = 41 px per row × 6 rows = 246 px).
		-- That made every button "nano" on a 4K monitor and unclickable on
		-- mobile. Switched to a pure-scale Y dimension on the panel and
		-- pure-scale CellSize/CellPadding on the grid so buttons resize with
		-- the viewport.
		-- §AGX/UI-P1: T3: ScrollingFrame (was Frame) + pixel cell heights with
		-- a 44 px floor. At 1080p the pixel values equal the old scales and
		-- all rows fit, so no scrollbar shows; on phones it scrolls.
		navPanel = React.createElement("ScrollingFrame", {
			ref              = panelRef,
			AnchorPoint      = Vector2.new(1, 0.5),
			-- Position is NOT a managed prop — TweenService controls it via panelRef
			Size             = UDim2.fromScale(0.22, 0.62),
			BackgroundColor3 = Color3.fromRGB(18, 18, 28),
			BackgroundTransparency = 0.10,
			BorderSizePixel  = 0,
			CanvasSize       = UDim2.new(0, 0, 0, 0),
			AutomaticCanvasSize = Enum.AutomaticSize.Y,
			ScrollingDirection  = Enum.ScrollingDirection.Y,
			ScrollBarThickness  = 4,
			VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar,
			ZIndex           = 5,
		}, {
			minSize = React.createElement("UISizeConstraint", {
				MinSize = Vector2.new(180, 0),  -- §AGX/UI-P1: two 44+ px wide columns
			}),
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.04, 0) }),
			stroke = React.createElement("UIStroke", {
				Color        = Color3.fromRGB(60, 80, 160),
				Thickness    = 1.5,
				Transparency = 0,
			}),
			-- 2-column grid: 12 buttons → 6 rows of 2.
			-- 6 rows × 0.135 height + 5 paddings × 0.018 = 0.90 of panel
			-- height → fits within the 4% UIPadding above/below.
			layout = React.createElement("UIGridLayout", {
				CellSize            = UDim2.new(0.47, 0, 0, navCellH),   -- §AGX/UI-P1
				CellPadding         = UDim2.new(0.02, 0, 0, navGapY),    -- §AGX/UI-P1
				SortOrder           = Enum.SortOrder.LayoutOrder,
				FillDirection       = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment   = Enum.VerticalAlignment.Top,
			}),
			pad = React.createElement("UIPadding", {
				PaddingLeft   = UDim.new(0.02, 0),
				PaddingRight  = UDim.new(0.02, 0),
				PaddingTop    = UDim.new(0, navPadY),     -- §AGX/UI-P1
				PaddingBottom = UDim.new(0, navPadY),     -- §AGX/UI-P1
			}),

			navClasses = onClassesClick and React.createElement("TextButton", {
				Size             = UDim2.fromScale(1, 1),
				BackgroundColor3 = C.btn_bg, BorderSizePixel = 0,
				Text = Locale.Get("btn_classes"), TextColor3 = C.btn_text,
				Font = Enum.Font.GothamBold, TextScaled = true,
				LayoutOrder = 1, ZIndex = 6,
				[React.Event.Activated] = function()
					setMenuOpen(false) if onClassesClick then onClassesClick() end
				end,
			}, {
				mt = minText(),  -- §AGX/UI-P1: 12 px text floor
				cc = React.createElement("UICorner", { CornerRadius = UDim.new(0.18, 0) }),
				ss = React.createElement("UIStroke", { Color = C.btn_stroke, Thickness = 1.5 }),
			}) or nil,

			navStats = React.createElement("TextButton", {
				Size             = UDim2.fromScale(1, 1),
				BackgroundColor3 = C.btn_bg, BorderSizePixel = 0,
				Text = "Stats", TextColor3 = C.btn_text,
				Font = Enum.Font.GothamBold, TextScaled = true,
				LayoutOrder = 2, ZIndex = 6,
				[React.Event.Activated] = function()
					setMenuOpen(false) if onStatsClick then onStatsClick() end
				end,
			}, {
				mt = minText(),  -- §AGX/UI-P1: 12 px text floor
				cc = React.createElement("UICorner", { CornerRadius = UDim.new(0.18, 0) }),
				ss = React.createElement("UIStroke", { Color = C.btn_stroke, Thickness = 1.5 }),
			}),

			navEquip = React.createElement("TextButton", {
				Size             = UDim2.fromScale(1, 1),
				BackgroundColor3 = C.btn_bg, BorderSizePixel = 0,
				Text = "Equipment", TextColor3 = C.btn_text,
				Font = Enum.Font.GothamBold, TextScaled = true,
				LayoutOrder = 3, ZIndex = 6,
				[React.Event.Activated] = function()
					setMenuOpen(false) if onEquipClick then onEquipClick() end
				end,
			}, {
				mt = minText(),  -- §AGX/UI-P1: 12 px text floor
				cc = React.createElement("UICorner", { CornerRadius = UDim.new(0.18, 0) }),
				ss = React.createElement("UIStroke", { Color = C.btn_stroke, Thickness = 1.5 }),
			}),

			-- §AGX/UX-01: Wardrobe entry was dropped in v0.5 (d862558), leaving
			-- WardrobeUI unreachable; restored in the empty LayoutOrder 4 slot.
			navWardrobe = onCosmeticsClick and React.createElement("TextButton", {
				Size             = UDim2.fromScale(1, 1),
				BackgroundColor3 = C.btn_bg, BorderSizePixel = 0,
				Text = "Wardrobe", TextColor3 = C.btn_text,
				Font = Enum.Font.GothamBold, TextScaled = true,
				LayoutOrder = 4, ZIndex = 6,
				[React.Event.Activated] = function()
					setMenuOpen(false) if onCosmeticsClick then onCosmeticsClick() end
				end,
			}, {
				mt = minText(),  -- §AGX/UI-P1: 12 px text floor
				cc = React.createElement("UICorner", { CornerRadius = UDim.new(0.18, 0) }),
				ss = React.createElement("UIStroke", { Color = C.btn_stroke, Thickness = 1.5 }),
			}) or nil,

			navTalents = React.createElement("TextButton", {
				Size             = UDim2.fromScale(1, 1),
				BackgroundColor3 = C.btn_bg, BorderSizePixel = 0,
				Text = "Talents", TextColor3 = C.btn_text,
				Font = Enum.Font.GothamBold, TextScaled = true,
				LayoutOrder = 5, ZIndex = 6,
				[React.Event.Activated] = function()
					setMenuOpen(false) if onTalentsClick then onTalentsClick() end
				end,
			}, {
				mt = minText(),  -- §AGX/UI-P1: 12 px text floor
				cc = React.createElement("UICorner", { CornerRadius = UDim.new(0.18, 0) }),
				ss = React.createElement("UIStroke", { Color = C.btn_stroke, Thickness = 1.5 }),
			}),

			navAchievements = React.createElement("TextButton", {
				Size             = UDim2.fromScale(1, 1),
				BackgroundColor3 = C.btn_bg, BorderSizePixel = 0,
				Text = "Achievements",
				TextColor3 = Color3.fromRGB(255, 200, 60),
				Font = Enum.Font.GothamBold, TextScaled = true,
				LayoutOrder = 6, ZIndex = 6,
				[React.Event.Activated] = function()
					setMenuOpen(false) if onAchievementsClick then onAchievementsClick() end
				end,
			}, {
				mt = minText(),  -- §AGX/UI-P1: 12 px text floor
				cc = React.createElement("UICorner", { CornerRadius = UDim.new(0.18, 0) }),
				ss = React.createElement("UIStroke", {
					Color = Color3.fromRGB(160, 120, 30), Thickness = 1.5,
				}),
			}),

			navSocial = onPartyClick and React.createElement("TextButton", {
				Size             = UDim2.fromScale(1, 1),
				BackgroundColor3 = C.btn_bg, BorderSizePixel = 0,
				Text = "Social", TextColor3 = C.btn_text,
				Font = Enum.Font.GothamBold, TextScaled = true,
				LayoutOrder = 7, ZIndex = 6,
				[React.Event.Activated] = function()
					setMenuOpen(false) if onPartyClick then onPartyClick() end
				end,
			}, {
				mt = minText(),  -- §AGX/UI-P1: 12 px text floor
				cc = React.createElement("UICorner", { CornerRadius = UDim.new(0.18, 0) }),
				ss = React.createElement("UIStroke", { Color = C.btn_stroke, Thickness = 1.5 }),
			}) or nil,

			navShop = React.createElement("TextButton", {
				Size             = UDim2.fromScale(1, 1),
				BackgroundColor3 = C.btn_bg, BorderSizePixel = 0,
				Text = "\u{1F6D2} Shop",
				TextColor3 = Color3.fromRGB(255, 210, 60),
				Font = Enum.Font.GothamBold, TextScaled = true,
				LayoutOrder = 8, ZIndex = 6,
				[React.Event.Activated] = function()
					setMenuOpen(false) if onShopClick then onShopClick() end
				end,
			}, {
				mt = minText(),  -- §AGX/UI-P1: 12 px text floor
				cc = React.createElement("UICorner", { CornerRadius = UDim.new(0.18, 0) }),
				ss = React.createElement("UIStroke", {
					Color = Color3.fromRGB(160, 130, 30), Thickness = 1.5,
				}),
			}),

			navSettings = React.createElement("TextButton", {
				Size             = UDim2.fromScale(1, 1),
				BackgroundColor3 = C.btn_bg, BorderSizePixel = 0,
				Text = "\u{2699} Settings",
				TextColor3 = Color3.fromRGB(180, 180, 180),
				Font = Enum.Font.GothamBold, TextScaled = true,
				LayoutOrder = 9, ZIndex = 6,
				[React.Event.Activated] = function()
					setMenuOpen(false) if onSettingsClick then onSettingsClick() end
				end,
			}, {
				mt = minText(),  -- §AGX/UI-P1: 12 px text floor
				cc = React.createElement("UICorner", { CornerRadius = UDim.new(0.18, 0) }),
				ss = React.createElement("UIStroke", { Color = C.btn_stroke, Thickness = 1.5 }),
			}),

			navInventory = onInventoryClick and React.createElement("TextButton", {
				Size             = UDim2.fromScale(1, 1),
				BackgroundColor3 = C.btn_bg, BorderSizePixel = 0,
				-- §AGX/UX-01 (freebie): was U+1F3BA (trumpet); backpack fits Inventory.
				Text = "\u{1F392} Inventory",
				TextColor3 = C.btn_text,
				Font = Enum.Font.GothamBold, TextScaled = true,
				LayoutOrder = 10, ZIndex = 6,
				[React.Event.Activated] = function()
					setMenuOpen(false) if onInventoryClick then onInventoryClick() end
				end,
			}, {
				mt = minText(),  -- §AGX/UI-P1: 12 px text floor
				cc = React.createElement("UICorner", { CornerRadius = UDim.new(0.18, 0) }),
				ss = React.createElement("UIStroke", { Color = C.btn_stroke, Thickness = 1.5 }),
			}) or nil,

			navLeaderboard = onLeaderboardClick and React.createElement("TextButton", {
				Size             = UDim2.fromScale(1, 1),
				BackgroundColor3 = C.btn_bg, BorderSizePixel = 0,
				Text = "\u{1F3C6} Leaderboard",
				TextColor3 = Color3.fromRGB(255, 200, 60),
				Font = Enum.Font.GothamBold, TextScaled = true,
				LayoutOrder = 11, ZIndex = 6,
				[React.Event.Activated] = function()
					setMenuOpen(false) if onLeaderboardClick then onLeaderboardClick() end
				end,
			}, {
				mt = minText(),  -- §AGX/UI-P1: 12 px text floor
				cc = React.createElement("UICorner", { CornerRadius = UDim.new(0.18, 0) }),
				ss = React.createElement("UIStroke", {
					Color = Color3.fromRGB(160, 130, 30), Thickness = 1.5,
				}),
			}) or nil,

			navDailyLogin = onDailyLoginClick and React.createElement("TextButton", {
				Size             = UDim2.fromScale(1, 1),
				BackgroundColor3 = C.btn_bg, BorderSizePixel = 0,
				Text = "\u{1F4C5} Daily Login",
				TextColor3 = Color3.fromRGB(100, 220, 120),
				Font = Enum.Font.GothamBold, TextScaled = true,
				LayoutOrder = 12, ZIndex = 6,
				[React.Event.Activated] = function()
					setMenuOpen(false) if onDailyLoginClick then onDailyLoginClick() end
				end,
			}, {
				mt = minText(),  -- §AGX/UI-P1: 12 px text floor
				cc = React.createElement("UICorner", { CornerRadius = UDim.new(0.18, 0) }),
				ss = React.createElement("UIStroke", {
					Color = Color3.fromRGB(40, 140, 60), Thickness = 1.5,
				}),
			}) or nil,
		}),
	})
end

return HUD

