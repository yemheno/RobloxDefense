-- lobby/ServerScriptService/Modules/LobbyNPCRegistry
--[[
    NPC definitions for the Lobby place (Village scene).
    Returned as a plain array and passed to NPCManager.Init via deps.npcs:

        NPCManager.Init({ SceneManager = sm, npcs = require(LobbyNPCRegistry) })

    To add, remove, or reposition lobby NPCs, edit this file only.
    No changes needed to the shared NPCManager or NPCRegistry.
]]

local Vector3  = Vector3
local BrickColor = BrickColor

return {

	-- ── SHOP NPCs ───────────────────────────────────────────────────────────
	{
		id       = "blacksmith",
		name     = "Grimjaw",
		title    = "Blacksmith",
		npcType  = "Shop",
		scene    = "Village",
		position = Vector3.new(20, 0.5, 10),
		color    = BrickColor.new("Dark stone grey"),

		shopItems = {
			{
				itemId      = "iron_sword",
				name        = "Iron Sword",
				description = "A sturdy blade forged in fire.",
				price       = 50,
				currency    = "Essence",
				category    = "Weapon",
			},
			{
				itemId      = "steel_shield",
				name        = "Steel Shield",
				description = "Blocks incoming blows.",
				price       = 75,
				currency    = "Essence",
				category    = "Weapon",
			},
			{
				itemId      = "health_potion",
				name        = "Health Potion",
				description = "Restores 50 HP.",
				price       = 10,
				currency    = "Essence",
				category    = "Consumable",
			},
		},
	},

	{
		id       = "enchantress",
		name     = "Mirael",
		title    = "Enchantress",
		npcType  = "Shop",
		scene    = "Village",
		position = Vector3.new(30, 0.5, -5),
		color    = BrickColor.new("Bright violet"),

		shopItems = {
			{
				itemId      = "arcane_focus",
				name        = "Arcane Focus",
				description = "Amplifies magical energy.",
				price       = 100,
				currency    = "Essence",
				category    = "Accessory",
			},
			{
				itemId      = "mana_crystal",
				name        = "Mana Crystal",
				description = "Restores 30 Aether.",
				price       = 15,
				currency    = "Essence",
				category    = "Consumable",
			},
		},
	},

	-- ── QUEST NPCs ──────────────────────────────────────────────────────────
	{
		id       = "captain",
		name     = "Captain Aldric",
		title    = "Guard Captain",
		npcType  = "Quest",
		scene    = "Village",
		position = Vector3.new(0, 0.5, 20),
		color    = BrickColor.new("Bright blue"),

		quests = {
			{
				questId     = "first_defense",
				title       = "A Line in the Sand",
				description = "Complete your first defense mission.",
				objectives  = {
					{ type = "CompleteMode", mode = "Defense", count = 1, label = "Complete 1 Defense" },
				},
				rewards     = {
					{ type = "Essence", amount = 100 },
					{ type = "XP",      percent = 35 },
				},
				repeatable  = false,
			},
			{
				questId      = "veteran_defender",
				title        = "Veteran Defender",
				description  = "Prove your mettle by completing 5 defense missions.",
				objectives   = {
					{ type = "CompleteMode", mode = "Defense", count = 5, label = "Complete 5 Defenses" },
				},
				rewards      = {
					{ type = "Merits",  amount = 10  },
					{ type = "Essence", amount = 300 },
				},
				repeatable   = false,
				prerequisite = "first_defense",
			},
		},
	},

	-- ── LORE NPCs ───────────────────────────────────────────────────────────
	{
		id       = "elder",
		name     = "Elder Theron",
		title    = "Village Elder",
		npcType  = "Lore",
		scene    = "Village",
		position = Vector3.new(-10, 0.5, 0),
		color    = BrickColor.new("Sand red"),

		dialogue = {
			{
				speaker = "Elder Theron",
				text    = "Welcome, guardian. Our village has stood for generations, but darkness gathers at the borders.",
				choices = {
					{ label = "Tell me more.",      next = 2 },
					{ label = "I'm ready to fight.", next = 3 },
				},
			},
			{
				speaker = "Elder Theron",
				text    = "The creatures grow bolder with each moon. We've built defensive lines, but we need warriors like you to hold them.",
				choices = {
					{ label = "I understand.", next = 3 },
				},
			},
			{
				speaker = "Elder Theron",
				text    = "Speak with Captain Aldric — he'll set you on your path. May the elements guide your blade.",
				choices = {},
			},
		},
	},

	{
		id       = "scholar",
		name     = "Lyris",
		title    = "Elemental Scholar",
		npcType  = "Lore",
		scene    = "Village",
		position = Vector3.new(-15, 0.5, 15),
		color    = BrickColor.new("Bright orange"),

		dialogue = {
			{
				speaker = "Lyris",
				text    = "The four elements — Wood, Earth, Water, Fire — form a cycle of strength and weakness. Understanding this cycle is key to victory.",
				choices = {
					{ label = "How does it work?", next = 2 },
					{ label = "Thanks.",           next = 0 },
				},
			},
			{
				speaker = "Lyris",
				text    = "Wood overcomes Earth, Earth overcomes Water, Water overcomes Fire, and Fire overcomes Wood. Strike with the right element for double damage!",
				choices = {
					{ label = "Interesting!", next = 0 },
				},
			},
		},
	},

	-- ── TELEPORT NPCs ───────────────────────────────────────────────────────
	{
		id       = "gatekeeper",
		name     = "Warden Kael",
		title    = "Gatekeeper",
		npcType  = "Teleport",
		scene    = "Village",
		position = Vector3.new(40, 0.5, 0),
		color    = BrickColor.new("Bright green"),

		dialogue = {
			{
				speaker = "Warden Kael",
				text    = "The gates are sealed for now, guardian. When new lands open, I shall be your guide.",
				choices = {},
			},
		},
	},

	-- ── MATCHMAKING NPC ─────────────────────────────────────────────────────
	{
		id       = "commander",
		name     = "Commander Vex",
		title    = "Field Commander",
		npcType  = "Matchmaking",
		scene    = "Village",
		position = Vector3.new(0, 0.5, 0),
		color    = BrickColor.new("Bright red"),

		-- Displayed as selectable destinations in the NPCTeleportOffer UI.
		-- Each entry triggers MatchmakingManager.QueueForMode(player, mode.id).
		-- §LN1 fix: was Defense-only; alpha launches with both modes available
		-- so list both. CentralBoss is intentionally omitted — see TODO_PARKING_LOT.md.
		modes = {
			{
				id          = "Defense",
				name        = "Defense Mission",
				description = "Hold the line — deploy now!",
			},
			{
				id          = "HordeMode",
				name        = "Horde Mode",
				description = "Survive endless waves in the top-down arena.",
			},
		},
	},

	-- ── WEAPON SMITH NPCs ───────────────────────────────────────────────────
	{
		id        = "refiner",
		name      = "Durgan",
		title     = "Weapon Refiner",
		npcType   = "WeaponSmith",
		smithType = "Refinement",
		scene     = "Village",
		position  = Vector3.new(25, 0.5, 15),
		color     = BrickColor.new("Nougat"),
	},

	{
		id        = "tiersmith",
		name      = "Kaelen",
		title     = "Tier Smith",
		npcType   = "WeaponSmith",
		smithType = "TierUpgrade",
		scene     = "Village",
		position  = Vector3.new(28, 0.5, 20),
		color     = BrickColor.new("Deep orange"),
	},

	{
		id        = "enchanter",
		name      = "Sylwen",
		title     = "Enchanter",
		npcType   = "WeaponSmith",
		smithType = "BonusReroll",
		scene     = "Village",
		position  = Vector3.new(32, 0.5, 18),
		color     = BrickColor.new("Alder"),
	},
}
