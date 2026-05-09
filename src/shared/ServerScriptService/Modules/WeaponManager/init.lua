-- ServerScriptService/Modules/WeaponManager

local WeaponManager = {}

local Players = game:GetService("Players")

local Modules = script.Parent
local WeaponConfig = require(Modules:WaitForChild("WeaponConfig"))
local WeaponRegistry = require(Modules:WaitForChild("WeaponRegistry"))
local PlayerDataManager = require(Modules:WaitForChild("PlayerDataManager"))
local NetworkManager = require(Modules:WaitForChild("NetworkManager"))
local VisualEquipmentManager = require(Modules:WaitForChild("VisualEquipmentManager"))

-- Child systems (loaded in Init)
local XPSystem
local Refinement
local TierSystem
local BonusSystem

--============================================
-- INITIALIZATION
--============================================

local initializedPlayers = {}

function WeaponManager.Init()
	-- Load child systems
	XPSystem = require(script:WaitForChild("WeaponXPSystem"))
	Refinement = require(script:WaitForChild("WeaponRefinement"))
	TierSystem = require(script:WaitForChild("WeaponTierSystem"))
	BonusSystem = require(script:WaitForChild("WeaponBonusSystem"))

	-- Give children access to parent.
	-- Factory systems (EquipmentTierSystem) look for .Manager; keep .WeaponManager
	-- for WeaponXPSystem / WeaponRefinement which reference it by that name.
	XPSystem.WeaponManager    = WeaponManager
	Refinement.WeaponManager  = WeaponManager
	TierSystem.WeaponManager  = WeaponManager
	BonusSystem.WeaponManager = WeaponManager
	XPSystem.Manager    = WeaponManager  -- EquipmentXPSystem factory uses .Manager
	Refinement.Manager  = WeaponManager  -- EquipmentRefinement factory uses .Manager
	TierSystem.Manager  = WeaponManager  -- EquipmentTierSystem factory uses .Manager
	BonusSystem.Manager = WeaponManager  -- EquipmentBonusSystem factory uses .Manager

	-- Initialize children
	BonusSystem.Init()  -- First, others may need it
	XPSystem.Init()
	Refinement.Init()
	TierSystem.Init()

	-- Create network events
	NetworkManager.GetEvent("WeaponEquipped")

	-- §LD-W2: setup the starter weapon BOTH on PlayerAdded (mints
	-- data on a brand-new account) AND on every CharacterAdded (so
	-- the visual is re-attached after respawn / class switch).
	-- The old one-shot version had two real failure modes:
	--   1) PlayerAdded fires before the character spawns — the
	--      polling loop only waits for CLASS DATA, so AttachClassWeapon
	--      reached a nil character and silent-returned; nothing
	--      retried.
	--   2) Respawn dropped the weapon visual since the per-player
	--      `initializedPlayers` guard blocked re-runs and the
	--      VisualEquipmentManager.ReattachAll path needs the in-memory
	--      cache that bug #1 prevented from ever being populated.
	-- Calling EnsureStarterWeapon multiple times is safe — its
	-- internal logic is idempotent (data row created once, AttachClassWeapon
	-- always re-attaches the visual on the live character).
	local function ensureWeaponSetup(player)
		task.spawn(function()
			-- Wait up to 5s for PlayerDataManager to set up the player.
			for _ = 1, 50 do
				if PlayerDataManager.GetActiveClassData(player) then break end
				task.wait(0.1)
			end
			if PlayerDataManager.GetActiveClassData(player) then
				WeaponManager.EnsureStarterWeapon(player)
			else
				warn("[WeaponManager] No class data for", player.Name, "after 5s")
			end
		end)
	end

	local function wireCharacterAdded(player)
		player.CharacterAdded:Connect(function()
			-- Settle: let Humanoid + R6 grip attachments wire up
			-- before we ask the visual layer to install welds.
			task.wait(0.5)
			ensureWeaponSetup(player)
		end)
		if player.Character then
			ensureWeaponSetup(player)
		end
	end

	-- Future joins: PRE-spawn AND character-added
	Players.PlayerAdded:Connect(function(player)
		ensureWeaponSetup(player)
		wireCharacterAdded(player)
	end)

	-- Existing players (Init ran late)
	for _, player in ipairs(Players:GetPlayers()) do
		ensureWeaponSetup(player)
		wireCharacterAdded(player)
	end

	-- Clean up on player leaving
	Players.PlayerRemoving:Connect(function(player)
		initializedPlayers[player] = nil
	end)

	print("[WeaponManager] Initialized")
end

--============================================
-- WEAPON INSTANCE CREATION
--============================================
function WeaponManager.CreateWeaponInstance(weaponId)
	local weaponDef = WeaponRegistry.GetWeapon(weaponId)
	if not weaponDef then
		warn("[WeaponManager] Weapon not found:", weaponId)
		return nil
	end

	local initialBonuses = BonusSystem.RollBonuses(weaponId, 1)

	return {
		weaponId = weaponId,
		level = 1,
		xp = 0,
		refinement = 0,
		tier = 1,
		bonuses = initialBonuses,
	}
end

--============================================
-- STARTER WEAPON
--============================================
function WeaponManager.EnsureStarterWeapon(player)
	local activeClass = PlayerDataManager.GetActiveClass(player)
	local classData = PlayerDataManager.GetActiveClassData(player)

	if not classData then
		warn("[WeaponManager] No class data for", player.Name)
		return
	end

	-- §LD-W1 fix: returning players already have classData.EquippedWeapon
	-- populated from saved data, so the early-return below skipped the
	-- entire AttachClassWeapon path. Result: weapon model never loaded
	-- visually on first spawn even though the weapon is "equipped" in
	-- data. Always attach the visual at the end; only the create-new
	-- branch needs to mint a fresh instance.
	if classData.EquippedWeapon and classData.EquippedWeapon.weaponId then
		local equippedId = classData.EquippedWeapon.weaponId
		local def = WeaponRegistry.GetWeapon(equippedId)
		if def and def.weaponSlot then
			VisualEquipmentManager.AttachClassWeapon(player, activeClass, def.weaponSlot)
		end
		-- Echo the equipped weapon to the client so the EquipmentUI
		-- snapshot matches the visual immediately, instead of waiting
		-- for the next class-switch / re-equip event.
		NetworkManager.FireClient(player, "WeaponEquipped", {
			weaponId   = equippedId,
			weaponData = classData.EquippedWeapon,
			stats      = WeaponManager.GetCalculatedStats(player),
		})
		return
	end

	local starterWeaponId = WeaponRegistry.GetStarterWeaponId(activeClass)
	if not starterWeaponId then
		warn("[WeaponManager] No starter weapon for class:", activeClass)
		return
	end

	local weaponInstance = WeaponManager.CreateWeaponInstance(starterWeaponId)
	if weaponInstance then
		classData.EquippedWeapon = weaponInstance
		print("[WeaponManager] Gave starter weapon to", player.Name, ":", starterWeaponId)

		PlayerDataManager.RefreshWeaponStats(player)

		NetworkManager.FireClient(player, "WeaponEquipped", {
			weaponId = starterWeaponId,
			weaponData = weaponInstance,
			stats = WeaponManager.GetCalculatedStats(player),
		})

		-- Attach weapon accessory
		local def = WeaponRegistry.GetWeapon(starterWeaponId)
		if def and def.weaponSlot then
			VisualEquipmentManager.AttachClassWeapon(player, activeClass, def.weaponSlot)
		end
	end
end

--============================================
-- WEAPON ACCESS
--============================================
function WeaponManager.GetEquippedWeapon(player, className)
	local classData
	if className then
		classData = PlayerDataManager.GetClassData(player, className)
	else
		classData = PlayerDataManager.GetActiveClassData(player)
	end

	if not classData then return nil end
	return classData.EquippedWeapon
end

function WeaponManager.GetEquippedWeaponDef(player)
	local weaponInstance = WeaponManager.GetEquippedWeapon(player)
	if not weaponInstance then return nil end

	return WeaponRegistry.GetWeapon(weaponInstance.weaponId)
end

function WeaponManager.GetCalculatedStats(player)
	local weaponInstance = WeaponManager.GetEquippedWeapon(player)
	if not weaponInstance then
		return {
			attack = 10,
			attackSpeed = 1.0,
			attackShape = "Circle",
			shapeParams = { radius = 5 },
		}
	end

	local weaponId = weaponInstance.weaponId
	local level = weaponInstance.level
	local refinement = weaponInstance.refinement
	local tier = weaponInstance.tier

	return {
		attack = WeaponRegistry.CalculateAttack(weaponId, level, refinement, tier),
		attackSpeed = WeaponRegistry.CalculateAttackSpeed(weaponId, tier),
		attackShape = WeaponRegistry.GetAttackShape(weaponId),
		shapeParams = WeaponRegistry.GetScaledShapeParams(weaponId, tier),
		bonuses = weaponInstance.bonuses,
	}
end

function WeaponManager.GetAttackShape(player)
	local weaponInstance = WeaponManager.GetEquippedWeapon(player)
	if not weaponInstance then
		return "Circle", { radius = 5 }
	end

	local shape, params = WeaponRegistry.GetAttackShape(weaponInstance.weaponId)
	local scaledParams = WeaponRegistry.GetScaledShapeParams(weaponInstance.weaponId, weaponInstance.tier)

	return shape or "Circle", scaledParams or params or { radius = 5 }
end

function WeaponManager.GetAttackSpeed(player)
	local weaponInstance = WeaponManager.GetEquippedWeapon(player)
	if not weaponInstance then return 1.0 end

	return WeaponRegistry.CalculateAttackSpeed(weaponInstance.weaponId, weaponInstance.tier)
end

function WeaponManager.GetWeaponAttack(player)
	local weaponInstance = WeaponManager.GetEquippedWeapon(player)
	if not weaponInstance then return 10 end

	return WeaponRegistry.CalculateAttack(
		weaponInstance.weaponId,
		weaponInstance.level,
		weaponInstance.refinement,
		weaponInstance.tier
	)
end

--============================================
-- MAX WEAPON LEVEL (hard caps at player levels 50/100/150)
--============================================
function WeaponManager.GetMaxWeaponLevel(player)
	local playerLevel = PlayerDataManager.GetAccountData(player, "Level") or 1
	return WeaponConfig.GetMaxWeaponLevel(playerLevel)
end

function WeaponManager.CanWeaponLevelUp(player)
	local weaponInstance = WeaponManager.GetEquippedWeapon(player)
	if not weaponInstance then return false end

	return weaponInstance.level < WeaponManager.GetMaxWeaponLevel(player)
end

--============================================
-- XP GRANT METHODS (class-role-gated via XPSystem)
--============================================

--- DPS: called from KillRewardManager after each mob kill.
function WeaponManager.GrantKillXP(player, mobLevel, mobType)
	if XPSystem then XPSystem.AddKillXP(player, mobLevel, mobType) end
end

--- Tank: called from DamageSystem with raw incoming damage (pre-DR).
function WeaponManager.GrantDamageTakenXP(player, incomingDamage)
	if XPSystem then XPSystem.AddDamageTakenXP(player, incomingDamage) end
end

--- Healer/Support: called from SkillEffects.HealPlayer with actual HP restored.
function WeaponManager.GrantHealXP(healer, hpHealed)
	if XPSystem then XPSystem.AddHealXP(healer, hpHealed) end
end

--- Healer/Support: called from SkillEffects when a buff is applied to an ally.
function WeaponManager.GrantBuffXP(player)
	if XPSystem then XPSystem.AddBuffXP(player) end
end

--- Healer/Support: called from DeathSystem when the player revives an ally.
function WeaponManager.GrantReviveXP(player)
	if XPSystem then XPSystem.AddReviveXP(player) end
end

--- Returns weapon level (= talent point budget for this class).
function WeaponManager.GetWeaponLevel(player)
	local weapon = WeaponManager.GetEquippedWeapon(player)
	return weapon and weapon.level or 1
end

--============================================
-- WEAPON SWITCHING & UNLOCKING
--============================================
function WeaponManager.SwitchWeapon(player, weaponId)
	local activeClass = PlayerDataManager.GetActiveClass(player)

	if not WeaponRegistry.IsWeaponForClass(weaponId, activeClass) then
		return false, "Weapon not available for your class"
	end

	local classData = PlayerDataManager.GetActiveClassData(player)
	if not classData then return false, "No class data" end

	local ownedWeapons = classData.OwnedWeapons or {}
	local weaponInstance = ownedWeapons[weaponId]

	if not weaponInstance then
		return false, "You don't own this weapon"
	end

	-- Store current weapon
	if classData.EquippedWeapon then
		local currentId = classData.EquippedWeapon.weaponId
		ownedWeapons[currentId] = classData.EquippedWeapon
	end

	-- Equip new weapon
	classData.EquippedWeapon = weaponInstance
	classData.OwnedWeapons = ownedWeapons

	-- Refresh server-side weapon stat bonuses
	PlayerDataManager.RefreshWeaponStats(player)

	NetworkManager.FireClient(player, "WeaponEquipped", {
		weaponId = weaponId,
		weaponData = weaponInstance,
		stats = WeaponManager.GetCalculatedStats(player),
	})

	-- Update weapon accessory
	local def = WeaponRegistry.GetWeapon(weaponId)
	if def and def.weaponSlot then
		VisualEquipmentManager.AttachClassWeapon(player, activeClass, def.weaponSlot)
	end

	print("[WeaponManager]", player.Name, "switched to:", weaponId)
	return true, "Weapon equipped!"
end

function WeaponManager.UnlockWeapon(player, weaponId)
	local activeClass = PlayerDataManager.GetActiveClass(player)

	if not WeaponRegistry.IsWeaponForClass(weaponId, activeClass) then
		return false, "Weapon not available for your class"
	end

	local classData = PlayerDataManager.GetActiveClassData(player)
	if not classData then return false, "No class data" end

	classData.OwnedWeapons = classData.OwnedWeapons or {}

	if classData.OwnedWeapons[weaponId] then
		return false, "Weapon already owned"
	end

	local weaponInstance = WeaponManager.CreateWeaponInstance(weaponId)
	if not weaponInstance then return false, "Failed to create weapon" end

	classData.OwnedWeapons[weaponId] = weaponInstance
	print("[WeaponManager]", player.Name, "unlocked:", weaponId)

	return true, "Weapon unlocked!"
end

function WeaponManager.GetOwnedWeapons(player)
	local classData = PlayerDataManager.GetActiveClassData(player)
	if not classData then return {} end

	local result = {}

	if classData.EquippedWeapon then
		local weaponId = classData.EquippedWeapon.weaponId
		result[weaponId] = {
			instance = classData.EquippedWeapon,
			equipped = true,
			definition = WeaponRegistry.GetWeapon(weaponId),
		}
	end

	for weaponId, instance in pairs(classData.OwnedWeapons or {}) do
		if not result[weaponId] then
			result[weaponId] = {
				instance = instance,
				equipped = false,
				definition = WeaponRegistry.GetWeapon(weaponId),
			}
		end
	end

	return result
end

--============================================
-- EXPOSE CHILD SYSTEMS
--============================================
function WeaponManager.GetSystems()
	return {
		XP = XPSystem,
		Refinement = Refinement,
		Tier = TierSystem,
		Bonus = BonusSystem,
	}
end

--============================================
-- DEBUG
--============================================
function WeaponManager.GetDebugInfo(player)
	local weaponInstance = WeaponManager.GetEquippedWeapon(player)
	if not weaponInstance then return "No weapon equipped" end

	-- §LD-W3 file-truncation recovery: the file used to end abruptly
	-- mid-function (same Studio re-sync corruption that nuked
	-- VisualEquipmentManager). Reconstructed to return a useful
	-- summary string for admin testing — does not affect gameplay.
	local def = WeaponRegistry.GetWeapon(weaponInstance.weaponId)
	local lines = {
		string.format("Player: %s", player.Name),
		string.format("Weapon: %s (%s)", weaponInstance.weaponId, def and def.name or "?"),
		string.format("Level: %d  XP: %d", weaponInstance.level or 1, weaponInstance.xp or 0),
		string.format("Refinement: %d  Tier: %d",
			weaponInstance.refinement or 0, weaponInstance.tier or 1),
	}
	if weaponInstance.bonuses then
		table.insert(lines, "Bonuses:")
		for stat, value in pairs(weaponInstance.bonuses) do
			table.insert(lines, string.format("  %s = %s", tostring(stat), tostring(value)))
		end
	end
	return table.concat(lines, "\n")
end

return WeaponManager 