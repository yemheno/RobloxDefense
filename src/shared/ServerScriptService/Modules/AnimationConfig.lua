-- ServerScriptService/Modules/AnimationConfig.lua
--[[
    AnimationConfig
    ===============
    Single source of truth for ALL animation IDs used in the game.

    Categories:
      • Player.Classes  — per-class action animations (basicAttack)
      • Player.Defaults  — override default idle/walk if desired (nil = Roblox default)
      • Emotes           — emote wheel entries
      • Mob              — per-mob-type animations (attack, walk, idle)
      • Projectiles      — per-projectile visual animations (future)

    NOTE: Skill animations are NOT centralized here; each skill definition
    in ClassSkills/ and MobSkills/ owns its own `animation` field.
    The AnimationSystem plays whatever animId the skill provides at runtime.

    Adding new animations:
      1. Upload the animation to Roblox and note the asset ID.
      2. Add it here under the correct category table.
      3. The AnimationSystem picks it up automatically.

    Animation Priority Guide (Roblox AnimationPriority):
      Idle      → looping idle overrides
      Movement  → walk, run
      Action    → basic attacks
      Action2   → skills (player and mob)
      Action3   → emotes (overrides combat, stopped by movement)
      Action4   → reserved for cinematics / cutscenes
]]

local AnimationConfig = {}

-- ═══════════════════════════════════════════════════════════
-- PLAYER ANIMATIONS
-- ═══════════════════════════════════════════════════════════

AnimationConfig.Player = {
	-- Per-class basic attack animations.
	-- Looked up by AnimationSystem via CombatConfig on the client.
	Classes = {
		Aegis = {
			basicAttack = "rbxassetid://128777973",  -- R6 Wave (arm swing → melee)
		},
		Arcanist = {
			basicAttack = "rbxassetid://128777973",  -- R6 Wave (cast motion)
		},
		Hunter = {
			basicAttack = "rbxassetid://128777973",  -- R6 Wave (bow draw)
		},
		LifeSteward = {
			basicAttack = "rbxassetid://128853357",  -- R6 Point (arm extend → cast)
		},
	},

	-- Override Roblox default animations. nil = keep Roblox default.
	-- Set an "rbxassetid://..." string to replace the built-in animation.
	Defaults = {
		idle  = nil,
		walk  = nil,
		run   = nil,
		jump  = nil,
		fall  = nil,
		climb = nil,
	},
}

-- ═══════════════════════════════════════════════════════════
-- EMOTE ANIMATIONS
-- Canonical emote data lives in ReplicatedStorage/Shared/EmoteConfig
-- so both server and client can access it.  This map is built
-- from EmoteConfig at load time for backward-compatible lookups.
-- ═══════════════════════════════════════════════════════════

AnimationConfig.Emotes = {}
do
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local shared = ReplicatedStorage:FindFirstChild("Shared")
	local ecMod = shared and shared:FindFirstChild("EmoteConfig")
	if ecMod then
		local EmoteConfig = require(ecMod)
		for _, emote in ipairs(EmoteConfig.Emotes) do
			AnimationConfig.Emotes[emote.id] = {
				animId      = emote.animId,
				looped      = emote.looped,
				displayName = emote.label,
				icon        = emote.icon,
			}
		end
	end
end

-- ═══════════════════════════════════════════════════════════
-- MOB ANIMATIONS
-- Per mob type. Keyed by MobRegistry id (e.g. "Zombie").
-- MobAI reads `attack` from here. The mob definition files
-- still OWN the raw data — this table is filled at Init time
-- when MobRegistry auto-loads mob configs. See RegisterMob().
-- ═══════════════════════════════════════════════════════════

AnimationConfig.Mob = {
	-- Populated at runtime via RegisterMobAnimations()
	-- Example structure after population:
	--   Zombie = { attack = "rbxassetid://507768375", idle = nil, walk = nil },
}

-- ═══════════════════════════════════════════════════════════
-- PROJECTILE ANIMATIONS (future)
-- ═══════════════════════════════════════════════════════════

AnimationConfig.Projectile = {
	-- Fireball = { onSpawn = "rbxassetid://...", onHit = "rbxassetid://..." },
}

-- ═══════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════

--- Get the basic-attack animation ID for a player class.
function AnimationConfig.GetPlayerAttackAnim(className)
	local classAnims = AnimationConfig.Player.Classes[className]
	return classAnims and classAnims.basicAttack
end

--- Get any animation entry for a mob type.
function AnimationConfig.GetMobAnim(mobId, animName)
	local mobAnims = AnimationConfig.Mob[mobId]
	return mobAnims and mobAnims[animName]
end

--- Get a full emote entry by name.
function AnimationConfig.GetEmote(emoteName)
	return AnimationConfig.Emotes[emoteName]
end

--- Get the entire emote table (for EmoteWheel UI).
function AnimationConfig.GetAllEmotes()
	return AnimationConfig.Emotes
end

--- Get default animation override (nil means Roblox handles it).
function AnimationConfig.GetDefaultOverride(animName)
	return AnimationConfig.Player.Defaults[animName]
end

-- ═══════════════════════════════════════════════════════════
-- RUNTIME REGISTRATION
-- Used by registries and mod loaders to extend the config
-- without editing this file.
-- ═══════════════════════════════════════════════════════════

--- Register (or overwrite) the class animation set for a class.
function AnimationConfig.RegisterClassAnimations(className, animations)
	AnimationConfig.Player.Classes[className] = animations
end

--- Register (or overwrite) mob animations. Called by each mob definition.
function AnimationConfig.RegisterMobAnimations(mobId, animations)
	AnimationConfig.Mob[mobId] = animations
end

--- Register a new emote at runtime.
function AnimationConfig.RegisterEmote(emoteName, emoteData)
	AnimationConfig.Emotes[emoteName] = emoteData
end

--- Register projectile animations.
function AnimationConfig.RegisterProjectileAnimations(projectileId, animations)
	AnimationConfig.Projectile[projectileId] = animations
end

return AnimationConfig
