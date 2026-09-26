-- WeaponManager/WeaponXPSystem
--[[
    Class-aware weapon XP system.

    Each class role earns weapon XP from a different combat source:
      "dps"     — mob kills            (Arcanist, Hunter, future offensive classes)
      "tank"    — incoming damage      (Aegis, future defensive classes)
      "healer"  — HP healed + revives  (LifeSteward)
      "support" — buffs + revives      (future support classes; partial heal credit)

    Weapon level feeds the talent-point budget. Each weapon caps at 50
    (unlocked at player level 200); with 2 weapons per class that's a
    per-class ceiling of 100.  The TalentManager sums every owned weapon
    across every class — see TalentPointProvider.GetTotalPoints.

    Public surface
    ══════════════
      WeaponXPSystem.AddKillXP(player, mobLevel, mobType)     → DPS
      WeaponXPSystem.AddDamageTakenXP(player, incomingDmg)    → Tank
      WeaponXPSystem.AddHealXP(healer, hpHealed)              → Healer/Support
      WeaponXPSystem.AddBuffXP(player)                        → Healer/Support
      WeaponXPSystem.AddReviveXP(player)                      → Healer/Support
      WeaponXPSystem.GetXPProgress(player)                    → UI info table

    WeaponXPSystem.WeaponManager must be set before any method is called.
    (Done by WeaponManager.Init.)
]]

local WeaponXPSystem = {}

-- ── Dependencies ─────────────────────────────────────────────────────────────

local Modules           = script.Parent.Parent
local WeaponConfig      = require(Modules:WaitForChild("WeaponConfig"))
local PlayerDataManager = require(Modules:WaitForChild("PlayerDataManager"))
local NetworkManager    = require(Modules:WaitForChild("NetworkManager"))

-- Set externally by WeaponManager.Init() — avoids circular require.
WeaponXPSystem.WeaponManager = nil

-- Lazy-load ClassConfig (avoids startup-order issues)
local _ClassConfig = nil
local function getClassConfig()
	if not _ClassConfig then
		_ClassConfig = require(Modules:WaitForChild("ClassConfig"))
	end
	return _ClassConfig
end

-- Lazy-load AchievementManager for weapon-level-up tracking.
local _AchievementManager = nil
local function getAM()
	if not _AchievementManager then
		local mod = Modules:FindFirstChild("AchievementManager")
		if mod then
			local ok, am = pcall(require, mod)
			if ok then _AchievementManager = am end
		end
	end
	return _AchievementManager
end

-- Lazy-load BonusExpSystem for dynamic multipliers
local _BonusExpSystem = nil
local function getBES()
	if _BonusExpSystem == nil then
		local mod = Modules:FindFirstChild("BonusExpSystem")
		_BonusExpSystem = mod and require(mod) or false
	end
	return _BonusExpSystem or nil
end

-- ── Initialization ────────────────────────────────────────────────────────────

function WeaponXPSystem.Init()
	NetworkManager.GetEvent("WeaponLevelUp")
	NetworkManager.GetEvent("WeaponXPGained")
end

-- ── Internal helpers ─────────────────────────────────────────────────────────

--- Returns the weaponXPRole of the player's active class.
local function getRole(player)
	local data = PlayerDataManager.GetData(player)
	if not data then return "dps" end
	local className = data.ActiveClass
	local cfg = getClassConfig()
	local class = cfg and cfg.Classes[className]
	return (class and class.weaponXPRole) or "dps"
end

-- §AGX/X22, §SCALE/S5: WeaponXPGained is coalesced (ARCHITECTURE.md#scaling)
-- instead of firing per kill (dps) / per hit taken (tank). Gains are
-- summed per player and weapon and flushed once per WEAPON_XP_WINDOW with
-- the weapon's CURRENT xp/level (a snapshot, so the summed xpGained plus
-- the latest totals is all the client needs — EquipmentUI only refreshes).
-- WeaponLevelUp stays immediate (rare, and it drives the level-up toast).
local WEAPON_XP_WINDOW = 0.25
local pendingWeaponXP = {}  -- [player] = { [weapon] = { xp = sum, maxLevel = n } }
local weaponXPScheduled = false

local function flushWeaponXP()
	weaponXPScheduled = false
	local batch = pendingWeaponXP
	pendingWeaponXP = {}
	for player, byWeapon in pairs(batch) do
		if player.Parent then
			for weapon, entry in pairs(byWeapon) do
				NetworkManager.FireClient(player, "WeaponXPGained", {
					xpGained   = entry.xp,
					currentXP  = weapon.xp,
					requiredXP = WeaponConfig.GetXPRequired(weapon.level),
					level      = weapon.level,
					maxLevel   = entry.maxLevel,
				})
			end
		end
	end
end

local function queueWeaponXP(player, weapon, xpGained, maxLevel)
	local byWeapon = pendingWeaponXP[player]
	if not byWeapon then
		byWeapon = {}
		pendingWeaponXP[player] = byWeapon
	end
	local entry = byWeapon[weapon]
	if entry then
		entry.xp += xpGained
		entry.maxLevel = maxLevel
	else
		byWeapon[weapon] = { xp = xpGained, maxLevel = maxLevel }
	end
	if not weaponXPScheduled then
		weaponXPScheduled = true
		task.delay(WEAPON_XP_WINDOW, flushWeaponXP)
	end
end

--- Core XP processor — adds XP, runs the level-up loop, fires client events.
local function processXP(player, xpToAdd)
	local wm = WeaponXPSystem.WeaponManager
	if not wm then return end

	local weapon = wm.GetEquippedWeapon(player)
	if not weapon then return end

	-- Check cap — if already maxed, silently ignore (no XP banks past the cap)
	local playerLevel = PlayerDataManager.GetAccountData(player, "Level") or 1
	local maxLevel    = WeaponConfig.GetMaxWeaponLevel(playerLevel)
	if weapon.level >= maxLevel then return end

	-- Apply global XP bonus: static (equipment/stats) + dynamic (party/events via BonusExpSystem)
	local xpBonus = PlayerDataManager.GetBonus(player, "XPBonus") or 0
	local staticMult = 1 + (xpBonus / 100)
	local bes = getBES()
	local dynamicMult = bes and bes.GetMultiplier(player) or 1.0
	local finalXP = math.max(1, math.floor(xpToAdd * staticMult * dynamicMult))

	weapon.xp = weapon.xp + finalXP

	-- ── Level-up loop ──────────────────────────────────────────────────
	local levelsGained = 0
	while weapon.level < maxLevel do
		local required = WeaponConfig.GetXPRequired(weapon.level)
		if weapon.xp >= required then
			weapon.xp    = weapon.xp - required
			weapon.level = weapon.level + 1
			levelsGained = levelsGained + 1
		else
			break
		end
	end

	-- Clamp XP to zero at cap (no banking)
	if weapon.level >= maxLevel then
		weapon.xp = 0
	end

	-- ── Fire events ────────────────────────────────────────────────────
	if levelsGained > 0 then
		-- Refresh server-side stat bonuses (weapon stats scale with level)
		PlayerDataManager.RefreshWeaponStats(player)

		NetworkManager.FireClient(player, "WeaponLevelUp", {
			newLevel     = weapon.level,
			levelsGained = levelsGained,
			maxLevel     = maxLevel,
			talentPoints = weapon.level,    -- 1 talent point per weapon level
		})

		-- Track weapon level for achievements (Arms Master).
		local am = getAM()
		if am then am.OnWeaponLevelUp(player, weapon.level) end

		print(string.format("[WeaponXPSystem] %s weapon %d → %d (talent pts: %d)",
			player.Name, weapon.level - levelsGained, weapon.level, weapon.level))
	else
		-- Incremental XP gain (no level-up) — batched (§AGX/X22).
		queueWeaponXP(player, weapon, finalXP, maxLevel)
	end
end

-- ══════════════════════════════════════════════════════════════════════════════
-- PUBLIC API — ROLE-GATED XP GRANT METHODS
-- ══════════════════════════════════════════════════════════════════════════════

--[[
    AddKillXP — DPS classes only.
    Called from KillRewardManager after each mob kill.
    XP = DPS_BASE × mob_type_mult × level_mult(mob vs player)
]]
function WeaponXPSystem.AddKillXP(player, mobLevel, mobType)
	if getRole(player) ~= "dps" then return end

	local rates    = WeaponConfig.XP_RATES
	local typeMult = WeaponConfig.XP_MOB_MULTIPLIER[mobType] or 1.0

	-- Level multiplier: mob level relative to player level (not weapon level).
	-- Gentle penalty for farming low-level content; no extra bonus for harder mobs.
	local playerLevel = PlayerDataManager.GetAccountData(player, "Level") or 1
	local levelDiff   = mobLevel - playerLevel
	local levelMult   = math.max(0.5, 1 + levelDiff * 0.05)

	local xp = math.max(1, math.floor(rates.DPS_BASE * typeMult * levelMult))
	processXP(player, xp)
end

--[[
    AddDamageTakenXP — Tank classes only.
    Called from DamageSystem BEFORE damage reduction is applied.
    XP = (min(incomingDmg, TANK_MAX_PER_HIT) / 100) × TANK_PER_100_DMG
    Counting pre-DR damage rewards the tank for putting themselves in danger
    regardless of how much their defense mitigates.
]]
function WeaponXPSystem.AddDamageTakenXP(player, incomingDamage)
	if getRole(player) ~= "tank" then return end

	local rates     = WeaponConfig.XP_RATES
	local cappedDmg = math.min(incomingDamage, rates.TANK_MAX_PER_HIT)
	local xp        = math.floor((cappedDmg / 100) * rates.TANK_PER_100_DMG)
	if xp <= 0 then return end

	processXP(player, xp)
end

--[[
    AddHealXP — Healer / Support classes.
    Called from SkillEffects.HealPlayer with the ACTUAL hp healed (capped to target's missing hp).
    XP = (hpHealed / 100) × SUPP_PER_100_HEAL
    Overheal (healing a full-health ally) is never counted.
]]
function WeaponXPSystem.AddHealXP(healer, hpHealed)
	local role = getRole(healer)
	if role ~= "healer" and role ~= "support" then return end

	local rates = WeaponConfig.XP_RATES
	local xp    = math.floor((hpHealed / 100) * rates.SUPP_PER_100_HEAL)
	if xp <= 0 then return end

	processXP(healer, xp)
end

--[[
    AddBuffXP — Healer / Support classes.
    Called from SkillEffects when a beneficial buff is applied to an ally.
    Each application = flat XP.
]]
function WeaponXPSystem.AddBuffXP(player)
	local role = getRole(player)
	if role ~= "healer" and role ~= "support" then return end

	processXP(player, WeaponConfig.XP_RATES.SUPP_PER_BUFF)
end

--[[
    AddReviveXP — Healer / Support classes.
    Called from DeathSystem when the player fully revives a downed ally.
    Large flat XP reward — revives are high-impact, high-risk actions.
]]
function WeaponXPSystem.AddReviveXP(player)
	local role = getRole(player)
	if role ~= "healer" and role ~= "support" then return end

	processXP(player, WeaponConfig.XP_RATES.SUPP_PER_REVIVE)
end

-- ══════════════════════════════════════════════════════════════════════════════
-- UI QUERY
-- ══════════════════════════════════════════════════════════════════════════════

--[[
    GetXPProgress — returns a table for the client HUD weapon XP bar.
    Fields: level, xp, required, percent, maxLevel, atCap, talentPoints, role
]]
function WeaponXPSystem.GetXPProgress(player)
	local wm = WeaponXPSystem.WeaponManager
	local empty = {
		level = 1, xp = 0, required = 200, percent = 0,
		maxLevel = 10, atCap = false, talentPoints = 1, role = "dps",
	}
	if not wm then return empty end

	local weapon = wm.GetEquippedWeapon(player)
	if not weapon then return empty end

	local playerLevel = PlayerDataManager.GetAccountData(player, "Level") or 1
	local maxLevel    = WeaponConfig.GetMaxWeaponLevel(playerLevel)
	local atCap       = weapon.level >= maxLevel
	local required    = atCap and 0 or WeaponConfig.GetXPRequired(weapon.level)
	local percent     = atCap and 100 or math.floor((weapon.xp / math.max(1, required)) * 100)

	return {
		level        = weapon.level,
		xp           = weapon.xp,
		required     = required,
		percent      = percent,
		maxLevel     = maxLevel,
		atCap        = atCap,
		talentPoints = weapon.level,
		role         = getRole(player),
	}
end

return WeaponXPSystem
