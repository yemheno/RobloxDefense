-- StarterPlayerScripts/Modules/PlayerAttack
-- Client-authoritative attacks: animations play instantly, hits detected locally,
-- hit reports sent to server for validation and damage application.

local PlayerAttack = {}

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer

local Modules = script.Parent
local SharedGeometry = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("SharedGeometry"))
local NetworkManager = require(Modules:WaitForChild("NetworkManager"))
local InputSystem    = require(Modules:WaitForChild("InputSystem"))

-- Lazy-loaded modules
local AnimationSystem = nil
local ClientProjectile = nil

-- Combat config received from server (class attack data)
local combatConfig = nil
local lastAttackTime = 0
local attackCounter = 0   -- incrementing attack ticket ID
local currentAttackId = 0 -- the attackId for the current swing

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function PlayerAttack.Init()
	-- Lazy-load AnimationSystem
	task.spawn(function()
		local as = Modules:FindFirstChild("AnimationSystem")
		if as then AnimationSystem = require(as) end
	end)

	-- Load ClientProjectile
	task.spawn(function()
		local cp = Modules:FindFirstChild("ClientProjectile")
		if cp then
			ClientProjectile = require(cp)
			ClientProjectile.Init()
		end
	end)

	-- Receive combat config from server (on spawn and class change)
	NetworkManager.OnServerEvent("CombatConfig", function(data)
		combatConfig = data
		-- §AGX/STATS: a "stats" resend (AttackSpeed bonus changed mid-fight)
		-- only re-paces; resetting the timer would fire an early swing the
		-- server rejects.
		if type(data) ~= "table" or data.reason ~= "stats" then
			lastAttackTime = 0
		end
	end)

	-- Input handling
	InputSystem.BindAction("Attack", function(_actionName, inputState)
		if inputState ~= "Began" then return end
		PlayerAttack.DoAttack()
	end)

	-- Visual replication of other players' attacks
	NetworkManager.OnServerEvent("AttackFired", function(data)
		PlayerAttack.OnOtherPlayerAttack(data)
	end)

	-- Fix first-spawn race condition: the server may fire CombatConfig before
	-- this listener was registered, or the handler may not be connected yet.
	-- Retry until combatConfig is received.
	task.spawn(function()
		while not combatConfig do
			NetworkManager.FireServer("RequestCombatConfig")
			task.wait(0.5)
		end
	end)
	-- Also re-request on every subsequent spawn (respawn, class change, etc.)
	LocalPlayer.CharacterAdded:Connect(function()
		combatConfig = nil
		task.spawn(function()
			while not combatConfig do
				NetworkManager.FireServer("RequestCombatConfig")
				task.wait(0.5)
			end
		end)
	end)

end

-- ═══════════════════════════════════════════════════════════
-- LOCAL ATTACK (immediate — no server round-trip)
-- ═══════════════════════════════════════════════════════════

function PlayerAttack.DoAttack()
	if not combatConfig then return end

	-- Block attacks while knocked down or dead.
	-- §LD-PA1: "fail open" on nil: a not-yet-replicated attribute is not a
	-- death state (else the very first attack on spawn is swallowed). The
	-- server still gates with the strict `== "Alive"` check, so any actual
	-- race (player clicks during a real knockdown) is caught there.
	local deathState = LocalPlayer:GetAttribute("DeathState")
	if deathState == "KnockedDown" or deathState == "Dead" then return end

	-- Casting lock
	if LocalPlayer:GetAttribute("CastingLockAttack") then return end

	-- Local cooldown check
	local now = os.clock()
	local cooldown = 1 / (combatConfig.attackSpeed or 1)
	if (now - lastAttackTime) < cooldown then return end
	lastAttackTime = now

	local char = LocalPlayer.Character
	if not char then return end
	local rootPart = char:FindFirstChild("HumanoidRootPart")
	if not rootPart then return end
	local humanoid = char:FindFirstChild("Humanoid")
	-- §A2b: do NOT gate on Humanoid.Health here. On the very first spawn
	-- the Humanoid is created with Health=0 and Roblox sets it to MaxHealth
	-- on the next frame; if the player clicks during that ~1-frame window
	-- the attack would silently swallow. The DeathState attribute checked
	-- above is the real source of truth (and §LD-DS5 pins server-side
	-- Health=1 during knockdown/dead anyway, so this check would be a
	-- no-op there too).
	if not humanoid then return end

	local lookDir = PlayerAttack.GetLookDirection(rootPart)

	-- Generate attack ticket ID
	attackCounter = attackCounter + 1
	currentAttackId = attackCounter

	-- Play animation IMMEDIATELY
	if combatConfig.animationId then
		PlayerAttack.PlayAttackAnimationOnCharacter(char, combatConfig.animationId, combatConfig.attackSpeed or 1.5)
	end

	-- Notify server FIRST so the attack ticket is registered before hit reports arrive.
	-- (PlayerHitReport is sent inside DoMeleeAttack; the ticket must exist by then.)
	NetworkManager.FireServer("AttackEvent", { lookDirection = lookDir, attackId = currentAttackId })

	-- Fire attack based on type
	if combatConfig.isRanged then
		PlayerAttack.DoRangedAttack(rootPart, lookDir)
	else
		PlayerAttack.DoMeleeAttack(rootPart, lookDir)
	end
end

function PlayerAttack.GetLookDirection(rootPart)
	local lv = rootPart.CFrame.LookVector
	local flat = Vector3.new(lv.X, 0, lv.Z)
	if flat.Magnitude > 0.001 then
		return flat.Unit
	end
	return Vector3.new(1, 0, 0)
end

-- ═══════════════════════════════════════════════════════════
-- RANGED ATTACK (local projectile + hit detection)
-- ═══════════════════════════════════════════════════════════

function PlayerAttack.DoRangedAttack(rootPart, direction)
	if not ClientProjectile then return end
	local config = combatConfig.projectile
	if not config then return end

	ClientProjectile.Fire(rootPart.Position, direction, config, currentAttackId)
end

-- ═══════════════════════════════════════════════════════════
-- MELEE ATTACK (local shape query + hit report)
-- ═══════════════════════════════════════════════════════════

function PlayerAttack.DoMeleeAttack(rootPart, direction)
	local origin = rootPart.Position
	local shape = combatConfig.attackShape or "Circle"
	local params = combatConfig.shapeParams or { range = 5 }

	local targets = PlayerAttack.GetMobsInShape(origin, direction, shape, params)

	for _, mob in ipairs(targets) do
		NetworkManager.FireServer("PlayerHitReport", {
			target = mob,
			damageMultiplier = 1.0,
			attackId = currentAttackId,
		})
	end
end

function PlayerAttack.GetMobsInShape(origin, direction, shape, params)
	local mobs = {}

	local function checkModel(model)
		if not model:IsA("Model") then return end
		if not model:GetAttribute("IsMob") then return end
		local hum = model:FindFirstChild("Humanoid")
		if not hum or hum.Health <= 0 then return end
		local rp = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
		if not rp then return end
		if PlayerAttack.IsInShape(rp.Position, origin, direction, shape, params) then
			table.insert(mobs, model)
		end
	end

	for _, child in ipairs(workspace:GetChildren()) do
		checkModel(child)
	end
	local mobsFolder = workspace:FindFirstChild("Mobs")
	if mobsFolder then
		for _, child in ipairs(mobsFolder:GetChildren()) do
			checkModel(child)
		end
	end

	return mobs
end

function PlayerAttack.IsInShape(targetPos, origin, direction, shape, params)
	local p = { range = params.range or 5, angle = params.angle, width = params.width, innerRadius = params.innerRadius, direction = direction }
	return SharedGeometry.IsInShape(targetPos, origin, shape, p)
end

-- ═══════════════════════════════════════════════════════════
-- OTHER PLAYERS' ATTACKS (visual replication)
-- ═══════════════════════════════════════════════════════════

function PlayerAttack.OnOtherPlayerAttack(data)
	local playerChar = data.character
	if not playerChar or not playerChar.Parent then return end
	if playerChar == LocalPlayer.Character then return end

	-- Play animation
	if data.animationId then
		PlayerAttack.PlayAttackAnimationOnCharacter(playerChar, data.animationId, data.attackSpeed or 1.5)
	end

	-- Visual-only projectile for ranged attacks
	if data.isRanged and data.lookDirection and ClientProjectile then
		local rootPart = playerChar:FindFirstChild("HumanoidRootPart")
		if rootPart and data.projectileConfig then
			ClientProjectile.FireVisual(rootPart.Position, data.lookDirection, data.projectileConfig)
		end
	end
end

-- ═══════════════════════════════════════════════════════════
-- ANIMATION
-- ═══════════════════════════════════════════════════════════

function PlayerAttack.PlayAttackAnimationOnCharacter(character, animationId, attackSpeed)
	if not AnimationSystem then return end
	AnimationSystem.Play(character, animationId, {
		category = "attack",
		speed    = (attackSpeed or 1.5) / 1.5,
		fadeIn   = 0.1,
	})
end

return PlayerAttack