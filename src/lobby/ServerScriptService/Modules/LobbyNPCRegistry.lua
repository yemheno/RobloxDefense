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

-- §AGX/X24: NPC shop listings are BUILT from ShopConfig (single source of
-- truth, ARCHITECTURE.md#single-source-of-truth). The registry names only
-- itemIds; price, currency, tab, level requirement and `enabled` come from
-- ShopConfig, display text from ConsumableConfig, so the NPC price is
-- always what ShopManager charges.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared            = ReplicatedStorage:WaitForChild("Shared")
local ShopConfig        = require(Shared:WaitForChild("ShopConfig"))
local ConsumableConfig  = require(Shared:WaitForChild("ConsumableConfig"))

local function buildShopItems(npcId, itemIds)
	local items = {}
	for _, itemId in ipairs(itemIds) do
		local entry = ShopConfig.FindByItemId(itemId)
		if not entry then
			-- Not sold anywhere: ShopManager would reject every purchase.
			warn("[LobbyNPCRegistry] " .. npcId .. " lists '" .. itemId ..
				"', which is not in ShopConfig — skipped (§AGX/X24)")
		else
			local info = ConsumableConfig.GetById(itemId)
			local desc = (info and info.desc) or entry.desc or ""
			-- §AGX/X10: unusable consumables stay listed but are marked; the
			-- server (ShopManager.PurchaseConsumable) rejects the purchase.
			if entry.enabled == false then
				desc = desc .. " (Coming soon)"
			end
			table.insert(items, {
				id          = itemId,   -- ShopUI.lua sends `item.id` on Buy
				itemId      = itemId,   -- ShopHandler matches on `itemId`
				name        = (info and info.name) or entry.name or itemId,
				description = desc,
				price       = entry.price,
				currency    = entry.currency,
				tab         = entry.tab,
				levelReq    = entry.levelReq,
				enabled     = entry.enabled ~= false,
				category    = (entry.tab == "Consumables") and "Consumable" or entry.tab,
			})
		end
	end
	return items
end

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

		-- §AGX/X24: dropped `iron_sword` (50 Essence) and `steel_shield`
		-- (75 Essence): they exist only here, never in ShopConfig, so every
		-- purchase failed. Re-add them to ShopConfig first if wanted (Pablo).
		shopItems = buildShopItems("blacksmith", {
			"health_potion",
		}),
	},

	{
		id       = "enchantress",
		name     = "Mirael",
		title    = "Enchantress",
		npcType  = "Shop",
		scene    = "Village",
		position = Vector3.new(30, 0.5, -5),
		color    = BrickColor.new("Bright violet"),

		-- §AGX/X24: dropped `arcane_focus` (100 Essence), which exists only
		-- here, never in ShopConfig. Re-add via ShopConfig if wanted (Pablo).
		shopItems = buildShopItems("enchantress", {
			"mana_crystal",
		}),
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
				-- §AGX/X41: 25 Essence pays the first two tier-ups (10 + 15) — a
				-- welcome gift, not a stockpile.
				rewards     = {
					{ type = "Essence", amount = 25 },
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
				-- §AGX/X41: ≈5,000 Merits of value at the 250:1 anchor
				-- (BALANCE_NUMBERS.md#economy-anchor).
				rewards      = {
					{ type = "Merits",  amount = 2500 },
					{ type = "Essence", amount = 10   },
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
		-- §LN1: list every live mode. CentralBoss is intentionally omitted
		-- until it ships (BACKLOG §AGX/X28-NEXT).
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
