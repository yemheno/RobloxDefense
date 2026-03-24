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

return Locale
