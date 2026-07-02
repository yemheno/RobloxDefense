-- ServerScriptService/Modules/DefenseLine/DefenseHealth

local DefenseHealth = {}

local TweenService = game:GetService("TweenService")

-- References (set by parent)
DefenseHealth.Config = nil
DefenseHealth.NetworkManager = nil
DefenseHealth.DefensePart = nil

-- ═══════════════════════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════════════════════

local currentHealth = 0
local maxHealth = 0
local lastDamageTime = 0
local isDestroyed = false
local originalColor = nil
local chapterLevel = 1

-- Callbacks
local onDestroyedCallbacks = {}
local onDamagedCallbacks = {}
local onHealedCallbacks = {}

-- Forward declaration — handleDestroyed is defined after TakeDamage which calls it.
-- In Lua, local variables are only visible to code that follows them lexically,
-- so we pre-declare the upvalue here and assign the function body below.
local handleDestroyed

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function DefenseHealth.Init()
	local config = DefenseHealth.Config

	maxHealth = config.GetMaxHealth(chapterLevel)
	currentHealth = maxHealth
	isDestroyed = false
	lastDamageTime = 0

	if DefenseHealth.DefensePart then
		originalColor = DefenseHealth.DefensePart.Color
	end

	DefenseHealth.UpdateVisuals()

end

-- §47.1: Update defense line HP based on the highest player's chapter
function DefenseHealth.SetChapterLevel(level)
	chapterLevel = level or 1
	local config = DefenseHealth.Config
	maxHealth = config.GetMaxHealth(chapterLevel)
	currentHealth = maxHealth
	isDestroyed = false

	DefenseHealth.UpdateVisuals()
	DefenseHealth.BroadcastHealth()

	print("[DefenseHealth] Chapter level set to", chapterLevel, "- HP:", currentHealth, "/", maxHealth)
end

-- ═══════════════════════════════════════════════════════════
-- DAMAGE & HEALING
-- ═══════════════════════════════════════════════════════════

function DefenseHealth.TakeDamage(amount, source)
	if isDestroyed then return false end
	if amount <= 0 then return false end

	currentHealth = math.max(0, currentHealth - amount)
	lastDamageTime = os.clock()

	-- Update visuals
	DefenseHealth.UpdateVisuals()

	-- Flash effect
	DefenseHealth.FlashOnHit()

	-- Notify clients
	if DefenseHealth.NetworkManager then
		DefenseHealth.NetworkManager.FireAllClients("DefenseLineDamaged", {
			damage = amount,
			currentHealth = currentHealth,
			maxHealth = maxHealth,
			percent = DefenseHealth.GetHealthPercent(),
			source = source,
		})
	end

	-- Fire callbacks
	for _, callback in ipairs(onDamagedCallbacks) do
		task.spawn(callback, amount, currentHealth, source)
	end

	-- Check destruction
	if currentHealth <= 0 then
		handleDestroyed()
	end

	return true
end

function DefenseHealth.Heal(amount)
	if isDestroyed then return false end
	if amount <= 0 then return false end
	if currentHealth >= maxHealth then return false end

	local oldHealth = currentHealth
	currentHealth = math.min(maxHealth, currentHealth + amount)

	DefenseHealth.UpdateVisuals()

	-- Only notify if significant
	if currentHealth - oldHealth >= 1 then
		if DefenseHealth.NetworkManager then
			DefenseHealth.NetworkManager.FireAllClients("DefenseLineUpdate", {
				currentHealth = currentHealth,
				maxHealth = maxHealth,
				percent = DefenseHealth.GetHealthPercent(),
			})
		end

		for _, callback in ipairs(onHealedCallbacks) do
			task.spawn(callback, amount, currentHealth)
		end
	end

	return true
end

function DefenseHealth.SetHealth(value)
	currentHealth = math.clamp(value, 0, maxHealth)
	DefenseHealth.UpdateVisuals()
	DefenseHealth.BroadcastHealth()
end

-- ═══════════════════════════════════════════════════════════
-- DESTRUCTION
-- ═══════════════════════════════════════════════════════════

handleDestroyed = function()
	if isDestroyed then return end

	isDestroyed = true
	currentHealth = 0

	print("[DefenseHealth] ═══════════════════════════════════")
	print("[DefenseHealth] 💀 DEFENSE LINE DESTROYED!")
	print("[DefenseHealth] ═══════════════════════════════════")

	DefenseHealth.UpdateVisuals()

	if DefenseHealth.NetworkManager then
		DefenseHealth.NetworkManager.FireAllClients("DefenseLineDestroyed", {
			finalHealth = 0,
			maxHealth = maxHealth,
		})
	end

	for _, callback in ipairs(onDestroyedCallbacks) do
		task.spawn(callback)
	end
end

-- ═══════════════════════════════════════════════════════════
-- VISUALS
-- ═══════════════════════════════════════════════════════════

function DefenseHealth.UpdateVisuals()
	-- Defensive checks
	if not DefenseHealth.Config then return end

	local visuals = DefenseHealth.Config.Visuals
	if not visuals or not visuals.Enabled then return end

	local part = DefenseHealth.DefensePart
	if not part then return end

	local percent = DefenseHealth.GetHealthPercent() / 100
	local color

	if percent <= visuals.CriticalThreshold then
		color = visuals.CriticalColor
	elseif percent <= visuals.DamagedThreshold then
		local t = (percent - visuals.CriticalThreshold) / (visuals.DamagedThreshold - visuals.CriticalThreshold)
		color = visuals.CriticalColor:Lerp(visuals.DamagedColor, t)
	else
		local t = (percent - visuals.DamagedThreshold) / (1 - visuals.DamagedThreshold)
		color = visuals.DamagedColor:Lerp(visuals.HealthyColor, t)
	end

	part.Color = color

	if isDestroyed then
		part.Transparency = 0.7
	end
end

function DefenseHealth.FlashOnHit()
	if not DefenseHealth.Config then return end

	local visuals = DefenseHealth.Config.Visuals
	if not visuals or not visuals.FlashEnabled then return end

	local part = DefenseHealth.DefensePart
	if not part then return end

	part.Color = visuals.FlashColor

	task.delay(visuals.FlashDuration, function()
		if part and not isDestroyed then
			DefenseHealth.UpdateVisuals()
		end
	end)
end

-- ═══════════════════════════════════════════════════════════
-- REGEN (Called from main update loop)
-- ═══════════════════════════════════════════════════════════

function DefenseHealth.UpdateRegen(dt)
	if not DefenseHealth.Config then return end

	local regen = DefenseHealth.Config.Regen
	if not regen or not regen.Enabled then return end
	if regen.PerSecond <= 0 then return end
	if isDestroyed then return end

	local timeSinceDamage = os.clock() - lastDamageTime
	if timeSinceDamage >= regen.Delay then
		DefenseHealth.Heal(regen.PerSecond * dt)
	end
end

-- ═══════════════════════════════════════════════════════════
-- NETWORK
-- ═══════════════════════════════════════════════════════════

function DefenseHealth.BroadcastHealth()
	if not DefenseHealth.NetworkManager then return end

	DefenseHealth.NetworkManager.FireAllClients("DefenseLineUpdate", {
		currentHealth = currentHealth,
		maxHealth = maxHealth,
		percent = DefenseHealth.GetHealthPercent(),
		isDestroyed = isDestroyed,
	})
end

-- §T4/V3 (X9 family): the late-joiner push fires from the data-ready
-- path — exactly the boot window where a raw FireClient drops if the
-- client hasn't subscribed yet. Route through ReadyGate when available.
local _ReadyGate = nil
local function getReadyGate()
	if _ReadyGate ~= nil then return _ReadyGate or nil end
	local mod = script.Parent.Parent:FindFirstChild("ReadyGate")
	if mod then
		local ok, rg = pcall(require, mod)
		_ReadyGate = (ok and rg) or false
	else
		_ReadyGate = false
	end
	return _ReadyGate or nil
end

function DefenseHealth.SendStateToPlayer(player)
	if not DefenseHealth.NetworkManager then return end

	local payload = {
		currentHealth = currentHealth,
		maxHealth = maxHealth,
		percent = DefenseHealth.GetHealthPercent(),
		isDestroyed = isDestroyed,
	}
	local rg = getReadyGate()
	if rg then
		rg.FireClient(player, "DefenseLineUpdate", payload)
	else
		DefenseHealth.NetworkManager.FireClient(player, "DefenseLineUpdate", payload)
	end
end

-- ═══════════════════════════════════════════════════════════
-- RESET
-- ═══════════════════════════════════════════════════════════

function DefenseHealth.Reset()
	local config = DefenseHealth.Config

	maxHealth = config.GetMaxHealth(chapterLevel)
	currentHealth = maxHealth
	isDestroyed = false
	lastDamageTime = 0

	DefenseHealth.UpdateVisuals()

	if DefenseHealth.DefensePart then
		DefenseHealth.DefensePart.Transparency = 0
	end

	DefenseHealth.BroadcastHealth()
end

-- ═══════════════════════════════════════════════════════════
-- CALLBACKS
-- ═══════════════════════════════════════════════════════════

function DefenseHealth.OnDestroyed(callback)
	table.insert(onDestroyedCallbacks, callback)
end

-- ═══════════════════════════════════════════════════════════
-- GETTERS
-- ═══════════════════════════════════════════════════════════

function DefenseHealth.GetHealth()
	return currentHealth
end

function DefenseHealth.GetMaxHealth()
	return maxHealth
end

function DefenseHealth.GetHealthPercent()
	if maxHealth <= 0 then return 0 end
	return (currentHealth / maxHealth) * 100
end

function DefenseHealth.IsDestroyed()
	return isDestroyed
end

return DefenseHealth