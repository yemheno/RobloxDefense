-- StarterPlayerScripts/Modules/Locale
--
-- Central language file.  All UI strings are looked up via Locale.Get(key).
-- To add a language, duplicate the "en" block with the new language code and
-- translate the values.  Then set  Locale.Language = "es"  (or wherever needed)
-- before any component mounts.
--
-- Usage:
--   local Locale = require(Modules:WaitForChild("Locale"))
--   Locale.Get("btn_classes")               --> "Classes"
--   Locale.Get("class_locked", 10)          --> "Lv. 10"
--   Locale.Get("switch_cooldown", 3)        --> "On cooldown (3s)"

local Locale = {}

-- ── Dictionaries ──────────────────────────────────────────────────────────────

local LANG = {

	en = {
		-- ── HUD ───────────────────────────────────────────────────
		btn_classes         = "Classes",

		-- ── Class selection menu ──────────────────────────────────
		menu_classes_title  = "Class Selection",
		menu_close          = "✕",

		-- ── Category column headers ───────────────────────────────
		-- (names are suggestions — feel free to rename in a future pass)
		cat_vanguard        = "Vanguard",      -- Physical melee
		cat_ranger          = "Ranger",        -- Physical ranged
		cat_mage            = "Spellcaster",   -- Magical
		cat_support         = "Support",       -- Support  (future classes)

		-- ── Class display names & short descriptions ──────────────
		class_Aegis_name    = "Aegis",
		class_Aegis_desc    = "Sturdy frontline fighter",

		class_Hunter_name   = "Hunter",
		class_Hunter_desc   = "Precision marksman",

		class_Arcanist_name = "Arcanist",
		class_Arcanist_desc = "Elemental spellcaster",

		class_LifeSteward_name = "Life Steward",
		class_LifeSteward_desc = "Nature's healer",

		-- ── Slot state labels ─────────────────────────────────────
		class_active        = "Active",
		class_locked        = "Lv. %d",        -- %d is substituted with required level
		class_locked_match  = "Locked",         -- shown during a match (switching not allowed)
		class_switch        = "Switch",
		class_empty         = "Coming Soon",

		-- ── Switch result feedback ────────────────────────────────
		switch_success      = "Class changed!",
		switch_cooldown     = "On cooldown (%ds)",
		switch_failed       = "Cannot switch.",
		class_locked_match_feedback = "Class is locked while in defense.",

		-- ── §AGX/UI-P3: shell menu (shell-spec §2.2, B2) ──────────
		-- Entry labels (rail tooltips, sheet/flyout tiles, radial centre).
		-- Keep them short: a sheet tile's label line is ~84 px wide.
		nav_menu_title      = "Menu",
		nav_play            = "Play",
		nav_leave           = "Leave",
		nav_stats           = "Stats",
		nav_talents         = "Talents",
		nav_equipment       = "Equipment",
		nav_wardrobe        = "Wardrobe",
		nav_inventory       = "Inventory",
		nav_appearance      = "Change appearance",   -- §AGX/X18b
		nav_achievements    = "Achievements",
		nav_daily           = "Daily Reward",
		nav_leaderboard     = "Leaderboard",
		nav_party           = "Party",
		nav_emotes          = "Emotes",
		nav_shop            = "Shop",
		nav_settings        = "Settings",
		nav_close           = "Close",

		-- Group (section) labels, Registry.Groups order.
		nav_group_play      = "Play",
		nav_group_exit      = "Exit",
		nav_group_character = "Character",
		nav_group_progress  = "Progress",
		nav_group_social    = "Social",
		nav_group_store     = "Store",
		nav_group_system    = "System",

		-- Locked reasons. The short form fits on a tile; `<key>_long` is
		-- used where there is room (radial centre, toasts, tooltips).
		nav_locked_lobby         = "Lobby only",
		nav_locked_lobby_long    = "Available in the Lobby",
		nav_locked_party         = "Lobby only",
		nav_locked_party_long    = "Parties are formed in the Lobby",
		nav_locked_battle        = "Not in battle",
		nav_locked_battle_long   = "Not available in battle",
		nav_locked_plaza         = "Not in the Plaza",
		nav_locked_plaza_long    = "Not available in the Plaza",
		nav_locked               = "Locked",            -- Registry.isAvailable default
		nav_locked_long          = "Not available here",
		nav_locked_generic       = "Locked",
		nav_locked_generic_long  = "Not available here",
		nav_blocked              = "Finish what's open first",
		-- §AGX/X18b: "Change appearance" (Veteran achievement, level 50)
		nav_locked_appearance_level      = "Unlocks at level 50",
		nav_locked_appearance_level_long = "Unlocks at level 50 (Veteran achievement)",
		nav_locked_appearance_none       = "No changes left",
		nav_locked_appearance_none_long  = "No appearance changes left. More are in the Shop.",

		-- Leave / exit confirmation (ConfirmDialog, `leave` action).
		nav_leave_confirm_title        = "Return to Lobby?",
		nav_leave_confirm_body         = "You'll leave this place and travel back to the Lobby.",
		nav_leave_confirm_body_combat  = "You'll leave the battle and return to the Lobby. Your team carries on without you.",
		nav_leave_confirm_yes          = "Leave",
		nav_leave_confirm_no           = "Stay",
		nav_leave_confirm_pending      = "Travelling…",
		nav_leave_confirm_failed       = "Couldn't reach the Lobby. Try again.",

		-- Radial / sheet hints.
		nav_hint_radial     = "Stick to choose  •  Ⓐ Select  •  Ⓑ Back",
	},

	-- ── Future language example ────────────────────────────────────────────────
	-- es = {
	--     btn_classes         = "Clases",
	--     menu_classes_title  = "Selección de Clase",
	--     ...
	-- },
}

-- ── Active language ────────────────────────────────────────────────────────────
-- Change this value to switch the whole game's language at runtime.
Locale.Language = "en"

-- ── Lookup ────────────────────────────────────────────────────────────────────
-- Locale.Get(key [, ...])
--   Returns the localised string for `key` in the active language,
--   falling back to English if the key or language is missing.
--   Any extra arguments are forwarded to string.format.
function Locale.Get(key, ...)
	local dict = LANG[Locale.Language] or LANG.en
	local str  = dict[key] or (LANG.en[key])

	if not str then
		return "[" .. tostring(key) .. "]"   -- obvious placeholder for missing keys
	end

	local args = { ... }
	if #args > 0 then
		return string.format(str, table.unpack(args))
	end
	return str
end

-- §AGX/UI-P3: true when `key` exists (in the active language or English),
-- so callers can prefer an optional variant ("<key>_long") without
-- rendering the "[key]" placeholder.
function Locale.Has(key)
	local dict = LANG[Locale.Language] or LANG.en
	return (dict[key] or LANG.en[key]) ~= nil
end

return Locale
