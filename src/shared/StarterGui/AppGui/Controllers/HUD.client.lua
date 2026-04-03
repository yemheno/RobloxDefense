-- HUD.client.lua
-- Subscribes to all server events and updates every live HUD element:
--   HP bar, Resource bar, XP bar, currency pills (Essence/Merits/Power),
--   game-state action buttons (StartGame / NextWave / Return),
--   countdown badge, wave banner, combo badge, defense line bar,
--   defense combo badge, death killfeed, combo summary toast.
--
-- All state that was previously React useState hooks is now held as plain
-- Lua locals; server events directly mutate the corresponding UI properties.

local Players  = game:GetService("Players")
local UIUtils  = require(script.Parent:WaitForChild("UIUtils"))

local w           = UIUtils.w
local nm          = UIUtils.nm()
local rc          = UIUtils.rc()
local root        = UIUtils.root()
local LocalPlayer = Players.LocalPlayer

-- ── Instance references ───────────────────────────────────────────────────────
local hud          = w(root, "HUD")
local statusPanel  = w(hud,  "StatusPanel")
local hpRow        = w(statusPanel, "HPRow")
local resRow       = w(statusPanel, "ResRow")
local xpRow        = w(statusPanel, "XPRow")

local currStrip   = w(hud, "CurrencyStrip")
local essencePill = w(currStrip, "EssencePill")
local meritsPill  = w(currStrip, "MeritsPill")
local powerPill   = w(currStrip, "PowerPill")

local startBtn    = w(hud, "StartBtn")
local nextWaveBtn = w(hud, "NextWaveBtn")
local returnBtn   = w(hud, "ReturnBtn")
local cdBadge     = w(hud, "CountdownBadge")
local comboBadge  = w(hud, "ComboBadge")
local comboLabel  = w(comboBadge, "ComboLabel")
local waveBanner  = w(hud, "WaveBanner")
local defenseBar  = w(hud, "DefenseBar")
local defBarRow   = w(defenseBar, "DefenseBarInner")
local defComboBadge = w(hud, "DefComboBadge")
local deathFeed   = w(hud, "DeathFeed")
local comboToast  = w(hud, "ComboToast")

-- ── State ─────────────────────────────────────────────────────────────────────
-- Default to "Lobby" so action buttons stay hidden until a GameStateChanged
-- event tells us we're in an active defense round.
local gameState    = "Lobby"
local betweenWaves = false
local alive        = true          -- cleared on script removal (guard for task.delay closures)
local comboTid     = nil           -- task id for combo auto-hide timer

-- ── Helpers ───────────────────────────────────────────────────────────────────
local function showActionBtns()
	startBtn.Visible    = (gameState == "Idle")
	nextWaveBtn.Visible = (gameState == "Defending") and betweenWaves
	returnBtn.Visible   = (gameState == "Defeat" or gameState == "Victory")
end

local function setWaveBanner(text, color, autoHide)
	waveBanner.Text       = text
	waveBanner.TextColor3 = color
	waveBanner.Visible    = true
	local stroke = waveBanner:FindFirstChildOfClass("UIStroke")
	if stroke then stroke.Color = color end
	if autoHide then
		local snapshot = text
		task.delay(3, function()
			if alive and waveBanner.Text == snapshot then
				waveBanner.Visible = false
			end
		end)
	end
end

-- ── HP ────────────────────────────────────────────────────────────────────────
local hpConn, maxHpConn, charConn

local function connectHumanoid(char)
	local humanoid = char:WaitForChild("Humanoid", 5)
	if not humanoid then return end
	UIUtils.updateBar(hpRow, humanoid.Health, humanoid.MaxHealth)
	hpConn = humanoid.HealthChanged:Connect(function(hp)
		UIUtils.updateBar(hpRow, hp, humanoid.MaxHealth)
	end)
	maxHpConn = humanoid:GetPropertyChangedSignal("MaxHealth"):Connect(function()
		UIUtils.updateBar(hpRow, humanoid.Health, humanoid.MaxHealth)
	end)
end

charConn = LocalPlayer.CharacterAdded:Connect(function(char)
	if hpConn    then hpConn:Disconnect();    hpConn    = nil end
	if maxHpConn then maxHpConn:Disconnect(); maxHpConn = nil end
	connectHumanoid(char)
end)

if LocalPlayer.Character then
	connectHumanoid(LocalPlayer.Character)
end

-- ── Resource bar ─────────────────────────────────────────────────────────────
local function applyResource(data)
	UIUtils.setBarLabel(resRow, data.name or "Resource")
	UIUtils.updateBar(resRow, data.cur or 0, data.max or 100)
end

-- Seed instantly from cache so the bar isn't empty on first frame
applyResource(rc.GetLatest())

rc.Subscribe(function(data)
	applyResource(data)
end)

-- ── PlayerInfoUpdate: XP, level, currencies, initial resource ─────────────────
nm.OnServerEvent("PlayerInfoUpdate", function(data)
	if data.level ~= nil then
		UIUtils.setBarLabel(xpRow, "Lv" .. tostring(data.level))
	end
	if data.xp ~= nil then
		UIUtils.updateBar(xpRow, data.xp, data.xpNeeded or 100)
	end
	if data.essence ~= nil then
		UIUtils.setCurrencyPill(essencePill, "♦", data.essence)
	end
	if data.merits ~= nil then
		UIUtils.setCurrencyPill(meritsPill, "★", data.merits)
	end
	-- Initial resource snapshot (before first ResourceUpdate tick)
	if data.resource ~= nil then
		applyResource({
			cur  = data.resource,
			max  = data.maxResource  or 100,
			name = data.resourceName or "Resource",
		})
	end
end)

-- Request an immediate snapshot from the server
nm.FireServer("GetPlayerInfo")

-- ── CurrencyUpdate: live essence / merits changes ─────────────────────────────
nm.OnServerEvent("CurrencyUpdate", function(data)
	UIUtils.setCurrencyPill(essencePill, "♦", data.essence or 0)
	UIUtils.setCurrencyPill(meritsPill,  "★", data.merits  or 0)
end)

-- ── Power Level ───────────────────────────────────────────────────────────────
nm.OnServerEvent("PlayerGearScore", function(data)
	if data and data.score ~= nil then
		UIUtils.setCurrencyPill(powerPill, "⚡", data.score)
	end
end)
nm.FireServer("PlayerGearScore")

-- ── Game State ────────────────────────────────────────────────────────────────
nm.OnServerEvent("GameStateChanged", function(data)
	gameState = data.newState or "Lobby"
	if gameState ~= "Preparing" then
		cdBadge.Visible = false
	end
	showActionBtns()
end)

-- ── Countdown ─────────────────────────────────────────────────────────────────
nm.OnServerEvent("CountdownUpdate", function(data)
	local rem = data.remaining or 0
	if rem > 0 then
		cdBadge.Text    = "Starting in " .. tostring(rem) .. "..."
		cdBadge.Visible = true
	else
		cdBadge.Visible = false
	end
end)

-- ── Action button wiring ──────────────────────────────────────────────────────
startBtn.Activated:Connect(function()
	nm.FireServer("RequestStartGame")
end)

nextWaveBtn.Activated:Connect(function()
	nm.FireServer("RequestNextWave")
end)

returnBtn.Activated:Connect(function()
	nm.FireServer("RequestReturnToLobby")
end)

-- ── Wave events ───────────────────────────────────────────────────────────────
nm.OnServerEvent("WaveStarted", function(data)
	betweenWaves = false
	showActionBtns()
	setWaveBanner(
		"WAVE " .. tostring(data.wave or "?")
			.. "  (" .. tostring(data.mobCount or 0) .. " mobs)",
		Color3.fromRGB(80, 210, 255),
		true
	)
end)

nm.OnServerEvent("WaveCompleted", function(data)
	betweenWaves = true
	showActionBtns()
	setWaveBanner(
		"WAVE " .. tostring(data.wave or "?") .. " CLEARED!",
		Color3.fromRGB(80, 255, 120),
		true
	)
end)

nm.OnServerEvent("AllWavesCompleted", function(data)
	setWaveBanner(
		"ALL WAVES CLEARED!  (Wave " .. tostring(data.finalWave or "?") .. ")",
		Color3.fromRGB(255, 215, 0),
		false   -- permanent: don't auto-hide
	)
end)

-- ── Defense line HP ───────────────────────────────────────────────────────────
local function applyDefenseHP(cur, max)
	UIUtils.updateBar(defBarRow, cur, max)
	defenseBar.Visible = true
end

nm.OnServerEvent("DefenseLineUpdate",    function(d) applyDefenseHP(d.currentHealth or 0, d.maxHealth or 1) end)
nm.OnServerEvent("DefenseLineDamaged",   function(d) applyDefenseHP(d.currentHealth or 0, d.maxHealth or 1) end)
nm.OnServerEvent("DefenseLineDestroyed", function(d)
	applyDefenseHP(0, d.maxHealth or 1)
	setWaveBanner("DEFENSE LINE DESTROYED!", Color3.fromRGB(255, 60, 60), false)
end)

-- ── Defense line combo badge ──────────────────────────────────────────────────
nm.OnServerEvent("DefenseLineCombo", function(d)
	if d.ended then
		defComboBadge.Visible = false
	else
		defComboBadge.Text    = "Defense Combo Lv" .. tostring(d.level or 0)
			.. "  x" .. string.format("%.1f", d.multiplier or 1)
		defComboBadge.Visible = true
	end
end)

-- ── Personal combo counter ────────────────────────────────────────────────────
nm.OnServerEvent("ComboUpdate", function(d)
	local n = d.current or 0
	if n >= 3 then
		comboLabel.Text    = tostring(n) .. "x  COMBO"
		comboBadge.Visible = true
	else
		comboBadge.Visible = false
	end
	-- Auto-hide 3 s after the last hit (mirrors server decay time)
	if comboTid then task.cancel(comboTid) end
	comboTid = task.delay(3, function()
		comboTid = nil
		if alive then comboBadge.Visible = false end
	end)
end)

-- ── Combo summary toast ────────────────────────────────────────────────────────
nm.OnServerEvent("ComboEnded", function(d)
	comboToast.Text    = tostring(d.finalCombo or 0) .. "x Combo!  "
		.. tostring(math.floor(d.totalDamage or 0)) .. " dmg  "
		.. tostring(d.totalCrits or 0) .. " crits"
	comboToast.Visible = true
	task.delay(4, function()
		if alive then comboToast.Visible = false end
	end)
end)

-- ── Death killfeed ────────────────────────────────────────────────────────────
nm.OnServerEvent("PlayerDeath", function(d)
	deathFeed.Text    = (d.playerName or "???") .. " was slain by " .. (d.killerMob or "a mob")
	deathFeed.Visible = true
	task.delay(4, function()
		if alive then deathFeed.Visible = false end
	end)
end)

-- ── Mob death drain (queue exhaustion prevention) ─────────────────────────────
nm.OnServerEvent("MobDeath", function(_) end)

print("[HUD] Wired")
