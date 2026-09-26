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
		}),

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
		}),
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
	local topLeftInset = select(1, GuiService:GetGuiInset())
	local safeTop = topLeftInset.Y + 10

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
			Size             = UDim2.fromScale(0.20, 0.75),
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
			}),
		})
	end

	-- ── Layout ────────────────────────────────────────────────────────────────
	return React.createElement("Frame", {
		Name                   = "HUD",
		Size                   = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		Visible                = not hidden,  -- §AGX/UX-02: hide, don't unmount
	}, {
		-- ── Top-left: Menu button ─────────────────────────────────────────────
		-- §UI-HUD1: was 3.5% × 5% — at 1080p that's 67×54, at higher resolutions
		-- the icon was unclickable. Bumped to 5% × 7% pure-scale per the
		-- "no hardcoded pixel sizes" rule.
		menuBtn = onMenuClick and React.createElement("TextButton", {
			Position         = UDim2.fromScale(0.005, 0.008),
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
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.2, 0) }),
			stroke = React.createElement("UIStroke", {
				Color        = C.btn_stroke,
				Thickness    = 1.5,
				Transparency = 0,
			}),
		}) or nil,

		-- ── Top strip: currency counters ──────────────────────────────────────
		currencyStrip = React.createElement("Frame", {
			Position               = UDim2.fromScale(0.04, 0),
			Size                   = UDim2.fromScale(0.96, 0.055),
			BackgroundColor3       = C.panel,
			BackgroundTransparency = 0.30,
			BorderSizePixel        = 0,
		}, {
			layout = React.createElement("UIListLayout", {
				FillDirection       = Enum.FillDirection.Horizontal,
				VerticalAlignment   = Enum.VerticalAlignment.Center,
				HorizontalAlignment = Enum.HorizontalAlignment.Left,
				SortOrder           = Enum.SortOrder.LayoutOrder,
				Padding             = UDim.new(0.008, 0),
			}),
			pad = React.createElement("UIPadding", { PaddingLeft = UDim.new(0.01, 0) }),

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
		statusPanel = React.createElement("Frame", {
			AnchorPoint      = Vector2.new(0, 1),
			Position         = UDim2.fromScale(0.01, 0.985),
			Size             = UDim2.fromScale(0.32, 0.17),
			BackgroundColor3 = C.panel,
			BackgroundTransparency = 0.30,
			BorderSizePixel  = 0,
		}, {
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
		startBtn = (not hideStartButton) and (gameState == "Idle") and React.createElement("TextButton", {
			AnchorPoint      = Vector2.new(0.5, 0),
			Position         = UDim2.new(0.5, 0, 0, safeTop + 34),
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
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.35, 0) }),
		}) or nil,

		countdownBadge = (countdown ~= nil) and React.createElement("TextLabel", {
			AnchorPoint            = Vector2.new(0.5, 0),
			Position               = UDim2.new(0.5, 0, 0, safeTop + 34),
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
			}),
		}) or nil,

		-- ── Top-centre: Wave banner (appears briefly when waves start/end) ───────
		waveBanner = (waveInfo ~= nil) and React.createElement("TextLabel", {
			AnchorPoint            = Vector2.new(0.5, 0),
			Position               = UDim2.new(0.5, 0, 0, safeTop + 88),
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
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.35, 0) }),
			stroke = React.createElement("UIStroke", {
				Color     = waveInfo.color or C.white,
				Thickness = 1.5,
				Transparency = 0.4,
			}),
		}) or nil,

		-- ── Bottom-left: Defense line HP bar (only when defenseHP is known) ──────
		defenseBar = (defenseHP ~= nil) and React.createElement("Frame", {
			AnchorPoint      = Vector2.new(0, 1),
			Position         = UDim2.fromScale(0.01, 0.80),
			Size             = UDim2.fromScale(0.32, 0.05),
			BackgroundColor3 = C.panel,
			BackgroundTransparency = 0.30,
			BorderSizePixel  = 0,
			ZIndex           = 3,
		}, {
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
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.35, 0) }),
		}) or nil,

		-- ── Top-right: Death killfeed notice ────────────────────────────────────
		deathFeed = (deathNotice ~= nil) and React.createElement("TextLabel", {
			AnchorPoint            = Vector2.new(1, 0),
			Position               = UDim2.new(0.98, 0, 0, safeTop + 52),
			Size                   = UDim2.fromScale(0.24, 0.04),
			BackgroundColor3       = Color3.fromRGB(60, 15, 15),
			BackgroundTransparency = 0.25,
			BorderSizePixel        = 0,
			Text                   = deathNotice,
			TextColor3             = Color3.fromRGB(255, 100, 100),
			Font                   = Enum.Font.GothamBold,
			TextScaled             = true,
			ZIndex                 = 4,
		}, {
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
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.3, 0) }),
			stroke = React.createElement("UIStroke", {
				Color     = Color3.fromRGB(200, 160, 40),
				Thickness = 1.5,
				Transparency = 0.3,
			}),
		}) or nil,

		-- ── Top-centre: "Next Wave" button (visible between waves) ──────────────
		nextWaveBtn = (not hideStartButton) and (gameState == "Defending") and betweenWaves and React.createElement("TextButton", {
			AnchorPoint      = Vector2.new(0.5, 0),
			Position         = UDim2.new(0.5, 0, 0, safeTop + 34),
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
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.35, 0) }),
		}) or nil,

		-- ── Top-centre: "Return to Lobby" button (game over or victory) ────────
		-- §AGX/X14: also shown in post-run Idle (runEnded) — if the return
		-- teleport fails, players otherwise sit in Idle with no way out.
		-- Nudged below the Idle Start button so the two don't overlap.
		returnBtn = (not hideStartButton)
			and (gameState == "Defeat" or gameState == "Victory" or (gameState == "Idle" and runEnded))
			and React.createElement("TextButton", {
				AnchorPoint      = Vector2.new(0.5, 0),
				Position         = UDim2.fromScale(0.5, gameState == "Idle" and 0.22 or 0.14),
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
		navPanel = React.createElement("Frame", {
			ref              = panelRef,
			AnchorPoint      = Vector2.new(1, 0.5),
			-- Position is NOT a managed prop — TweenService controls it via panelRef
			Size             = UDim2.fromScale(0.22, 0.62),
			BackgroundColor3 = Color3.fromRGB(18, 18, 28),
			BackgroundTransparency = 0.10,
			BorderSizePixel  = 0,
			ZIndex           = 5,
		}, {
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
				CellSize            = UDim2.fromScale(0.47, 0.135),
				CellPadding         = UDim2.fromScale(0.02, 0.018),
				SortOrder           = Enum.SortOrder.LayoutOrder,
				FillDirection       = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment   = Enum.VerticalAlignment.Top,
			}),
			pad = React.createElement("UIPadding", {
				PaddingLeft   = UDim.new(0.02, 0),
				PaddingRight  = UDim.new(0.02, 0),
				PaddingTop    = UDim.new(0.02, 0),
				PaddingBottom = UDim.new(0.02, 0),
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
				cc = React.createElement("UICorner", { CornerRadius = UDim.new(0.18, 0) }),
				ss = React.createElement("UIStroke", {
					Color = Color3.fromRGB(40, 140, 60), Thickness = 1.5,
				}),
			}) or nil,
		}),
	})
end

return HUD

