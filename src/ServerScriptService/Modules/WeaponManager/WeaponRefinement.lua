-- ServerScriptService/Modules/WeaponManager/WeaponRefinement

local WeaponRefinement = {}

local Modules = script.Parent.Parent
local WeaponConfig = require(Modules:WaitForChild("WeaponConfig"))
local NetworkManager = require(Modules:WaitForChild("NetworkManager"))

-- Set by WeaponManager
WeaponRefinement.WeaponManager = nil

--============================================
-- INITIALIZATION
--============================================
function WeaponRefinement.Init()
	NetworkManager.GetEvent("WeaponRefinementResult")

	print("[WeaponRefinement] Initialized")
end

--============================================
-- ATTEMPT REFINEMENT
--============================================
function WeaponRefinement.Attempt(player)
	local weaponInstance = WeaponRefinement.WeaponManager.GetEquippedWeapon(player)
	if not weaponInstance then
		return false, 0, "No weapon equipped"
	end

	local currentRefinement = weaponInstance.refinement

	-- Check max
	if currentRefinement >= WeaponConfig.REFINEMENT_MAX then
		return false, currentRefinement, "Already at max refinement"
	end

	-- TODO: Check/consume materials here

	-- Get success chance
	local successChance = WeaponConfig.REFINEMENT_SUCCESS[currentRefinement] or 0.01

	-- Roll
	local roll = math.random()
	local success = roll <= successChance

	if success then
		-- Success!
		weaponInstance.refinement = currentRefinement + 1

		NetworkManager.FireClient(player, "WeaponRefinementResult", {
			success = true,
			oldRefinement = currentRefinement,
			newRefinement = weaponInstance.refinement,
			stats = WeaponRefinement.WeaponManager.GetCalculatedStats(player),
		})

		print("[WeaponRefinement]", player.Name, "SUCCESS: +" .. currentRefinement, "→ +" .. weaponInstance.refinement)
		return true, weaponInstance.refinement, "Success!"
	else
		-- Failed
		local newRefinement = currentRefinement
		local downgraded = false

		-- Check ceiling
		if not WeaponConfig.IsCeiling(currentRefinement) then
			-- Roll for downgrade
			if math.random() <= WeaponConfig.REFINEMENT_DOWNGRADE_CHANCE then
				local ceiling = WeaponConfig.GetCeilingBelow(currentRefinement)
				newRefinement = math.max(ceiling, currentRefinement - 1)
				downgraded = true
			end
		end

		weaponInstance.refinement = newRefinement

		NetworkManager.FireClient(player, "WeaponRefinementResult", {
			success = false,
			downgraded = downgraded,
			oldRefinement = currentRefinement,
			newRefinement = newRefinement,
			stats = WeaponRefinement.WeaponManager.GetCalculatedStats(player),
		})

		if downgraded then
			print("[WeaponRefinement]", player.Name, "FAIL+DOWN: +" .. currentRefinement, "→ +" .. newRefinement)
			return false, newRefinement, "Failed and downgraded!"
		else
			print("[WeaponRefinement]", player.Name, "FAIL: +" .. currentRefinement, "stays")
			return false, newRefinement, "Failed but held!"
		end
	end
end

--============================================
-- REFINEMENT INFO
--============================================
function WeaponRefinement.GetInfo(player)
	local weaponInstance = WeaponRefinement.WeaponManager.GetEquippedWeapon(player)
	if not weaponInstance then
		return { refinement = 0, successChance = 100, isMax = false, isCeiling = true }
	end

	local refinement = weaponInstance.refinement
	local successChance = WeaponConfig.REFINEMENT_SUCCESS[refinement] or 0
	local isCeiling = WeaponConfig.IsCeiling(refinement)

	return {
		refinement = refinement,
		successChance = math.floor(successChance * 100),
		downgradeChance = isCeiling and 0 or math.floor(WeaponConfig.REFINEMENT_DOWNGRADE_CHANCE * 100),
		isMax = refinement >= WeaponConfig.REFINEMENT_MAX,
		isCeiling = isCeiling,
		ceilingBelow = WeaponConfig.GetCeilingBelow(refinement),
	}
end

return WeaponRefinement