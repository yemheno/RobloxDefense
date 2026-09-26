-- UI/Shell/Registry.lua
--[[
    §AGX/UI-P3: the ONE table of every menu entry in the game
    (docs/ui_audit/shell-spec.md §2). Places declare WHICH entries exist;
    PanelStack / PanelHost decide HOW they open. No React in here.

    Place kinds (passed by the App / Shell as `place`):
        "Lobby" | "Plaza" (SocialPlaza) | "Combat" (LaneDefense, HordeMode, CentralBoss)

    ENTRY SCHEMA (all fields but id / kind optional)
        id, kind = "panel" | "action" | "external" | "modal" | "presence" | "menu"
        group, order, slot, rail            -- rail=false: not on the rail/sheet/radial
        label (Locale key), icon (Theme.Icons key), glyph (fallback text)
        module = { folder = "UI" | "Lobby" | "Shell", name, export? }
              or byPlace = { Combat = {module=..., props=...}, default = {...} }
        props       static props merged under the stack's props
        places      { Lobby=true, Plaza=true, Combat=true }
        lockedReason { Combat = "nav_locked_lobby" }   -- Locale keys
        class       "system" > "modal" > "panel" > "menu"
        presentation "windowed" | "side" | "fullscreen" | "dialog" | "sheet"  (PC / tablet)
        phone       "sheet" | "fullscreen" | "dialog"
        combatSide  true = D7 right side sheet in Combat on Tablet / Desktop
        dismissOnBackdrop  D8 click-outside
        closable    false = only the component itself can close it
        mount       "onOpen" (default) | "always" (externals: PanelHost keeps them mounted)
        subOf       parent id for PanelStack.push
        badge       BadgeStore key;  clearBadgeOnOpen = true clears it on open
        closeProps  prop names PanelHost wires to "close me" (default { "onClose" })
        dim         transparency of a non-dismissing scrim PanelHost draws
                    behind entries that have no backdrop of their own
        run(ctx)    kind="action": ctx = { PanelStack, place }
        gate(place) -> available, lockedReason?   §AGX/X18b: runtime lock on
                    top of `places` (e.g. "has an appearance change"); read
                    from LocalPlayer attributes, never yields
        gateAttributes { attrName... }  LocalPlayer attributes `gate` reads;
                    menus re-read the model when one changes (subscribeGates)

    API
        Registry.Groups                   ordered array of { id, icon, glyph, label }
        Registry.Entries                  [id] = entry
        Registry.PlaceFolders             place -> PlayerScripts child name(s)
        Registry.forPlace(place)  -> { { group, entries = { { entry, available, lockedReason } } } }
        Registry.get(id)          -> entry | nil
        Registry.spec(entry, place) -> module spec, props   (byPlace resolved)
        Registry.resolve(entry, place) -> component | nil   NON-YIELDING (cache /
            already-replicated ModuleScript); nil = not loaded yet or locked.
        Registry.load(entry, place) -> component | nil      may YIELD (WaitForChild);
            call it from a task, never from render. PanelHost preloads every
            entry of its place on mount.
        Registry.isAvailable(entry, place) -> bool, lockedReason?
        Registry.subscribeGates(cb) -> unsub   §AGX/X18b: cb() when any
            entry's gateAttributes changes (MenuIcon.Model.useGroups)
]]

local Players = game:GetService("Players")

local Registry = {}

-- ═══════════════════════════════════════════════════════════
-- PLACES
-- ═══════════════════════════════════════════════════════════

-- PlayerScripts child that holds a place's own UI folder (Rojo:
-- PlayerScripts.<Folder>.UI, lobby.project.json:46-54 and the other four).
Registry.PlaceFolders = {
	Lobby  = { "Lobby" },
	Plaza  = { "SocialPlaza" },
	Combat = { "LaneDefense", "HordeMode", "CentralBoss" },
}

-- ═══════════════════════════════════════════════════════════
-- GROUPS (same order everywhere: rail top->bottom, sheet top->bottom,
-- radial clockwise from 12 o'clock)
-- ═══════════════════════════════════════════════════════════

Registry.Groups = {
	{ id = "play",      icon = "play",         glyph = "PLAY", glyphElsewhere = "EXIT", label = "nav_group_play" },
	{ id = "character", icon = "classes",      glyph = "CHAR", label = "nav_group_character" },
	{ id = "progress",  icon = "achievements", glyph = "PROG", label = "nav_group_progress" },
	{ id = "social",    icon = "social",       glyph = "SOC",  label = "nav_group_social" },
	{ id = "store",     icon = "shop",         glyph = "SHOP", label = "nav_group_store" },
	{ id = "system",    icon = "settings",     glyph = "SET",  label = "nav_group_system" },
}

local ALL   = { Lobby = true, Plaza = true, Combat = true }
local LOBBY = { Lobby = true }
-- §AGX/UI-P3 (W4): InventoryUI / LeaderboardUI / DailyLoginUI moved to the
-- shared UI folder (their managers load in every place), so the
-- NOT_LOBBY_YET lock is gone and those entries are available everywhere.

-- ═══════════════════════════════════════════════════════════
-- ENTRIES (§2.2)
-- ═══════════════════════════════════════════════════════════

local E = {}

-- ── play / exit slot ─────────────────────────────────────
E.play = {
	id = "play", kind = "panel", group = "play", order = 1, slot = "exit",
	label = "nav_play", icon = "play", glyph = "PLAY",
	module = { folder = "Lobby", name = "MainMenu" },
	places = LOBBY,
	class = "panel", presentation = "windowed", phone = "sheet",
	closeProps = { "onClose", "onPlay" },
}

E.leave = {
	id = "leave", kind = "action", group = "play", order = 1, slot = "exit",
	label = "nav_leave", icon = "leave", glyph = "EXIT",
	places = { Plaza = true, Combat = true },
	-- ❓ mid-run leave is allowed behind the confirm (server has no state gate).
	-- Shell/ConfirmDialog (Agent B) owns the "leave" preset: its texts and
	-- the FireServer("RequestReturnToLobby") on confirm.
	run = function(ctx)
		ctx.PanelStack.open("leaveConfirm", { preset = "leave", place = ctx.place })
	end,
}

E.class = {
	id = "class", kind = "panel", group = "character", order = 1,
	label = "btn_classes", icon = "classes", glyph = "CLASS",
	byPlace = {
		-- Combat: read-only reference (switching is server-blocked in combat)
		Combat = {
			module = { folder = "UI", name = "BattleClassUI" },
			props = {
				showBadge = false, expanded = true,
				panelScale = 0.72, panelScaleY = 0.78,
				position = UDim2.fromScale(0.5, 0.5), anchorPoint = Vector2.new(0.5, 0.5),
				zIndex = 7,
			},
			-- §AGX/UI-P6: no `dim` — the reference is an AppWindow now and
			-- draws its own (non-dismissing, F6) backdrop; a second dim stacked.
		},
		default = { module = { folder = "UI", name = "ClassMenu" } },
	},
	places = ALL,
	class = "panel", presentation = "windowed", phone = "sheet",
	-- F6: D8 limits click-outside to small dialogs; CombatApp's reference
	-- used to close on a backdrop click (CombatApp.lua:122-131). Deliberate.
	dismissOnBackdrop = false,
}

E.stats = {
	id = "stats", kind = "panel", group = "character", order = 2,
	label = "nav_stats", icon = "stats", glyph = "STATS",
	module = { folder = "UI", name = "StatsMenu" },
	places = ALL, class = "panel", presentation = "windowed", phone = "sheet",
	combatSide = true, badge = "stats",
}

E.talents = {
	id = "talents", kind = "panel", group = "character", order = 3,
	label = "nav_talents", icon = "talents", glyph = "TAL",
	module = { folder = "UI", name = "TalentTreeUI" },
	places = ALL, class = "panel", presentation = "fullscreen", phone = "fullscreen",
	badge = "talents",
}

E.equipment = {
	id = "equipment", kind = "panel", group = "character", order = 4,
	label = "nav_equipment", icon = "equipment", glyph = "EQUIP",
	module = { folder = "UI", name = "EquipmentUI" },
	places = ALL, class = "panel", presentation = "windowed", phone = "sheet",
}

E.wardrobe = {
	id = "wardrobe", kind = "panel", group = "character", order = 5,
	label = "nav_wardrobe", icon = "wardrobe", glyph = "WARD",
	module = { folder = "UI", name = "WardrobeUI" },
	places = ALL, class = "panel", presentation = "windowed", phone = "sheet",
}

E.inventory = {
	id = "inventory", kind = "panel", group = "character", order = 6,
	label = "nav_inventory", icon = "inventory", glyph = "INV",
	module = { folder = "UI", name = "InventoryUI" },   -- §AGX/UI-P3 (W4)
	places = ALL,
	class = "panel", presentation = "windowed", phone = "sheet",
}

-- §AGX/X18b: spend an appearance change (free one from the Veteran
-- achievement at level 50; paid ones are auto-applied on purchase). No
-- panel of its own: the server answers UseAppearanceChange with
-- CharacterCreationRequired and ServerOpen opens `characterCreation`.
-- Not in Combat: the creation screen is a full-screen modal.
local APPEARANCE_LEVEL = 50  -- = AchievementConfig "veteran" tier
E.appearance = {
	id = "appearance", kind = "action", group = "character", order = 7,
	label = "nav_appearance", icon = "appearance", glyph = "LOOK",
	places = { Lobby = true, Plaza = true },
	lockedReason = { Combat = "nav_locked_battle" },
	badge = "appearance",
	gateAttributes = { "AppearanceChangesAvailable", "Level" },
	gate = function()
		local lp = Players.LocalPlayer
		if (tonumber(lp:GetAttribute("AppearanceChangesAvailable")) or 0) > 0 then
			return true, nil
		end
		if (tonumber(lp:GetAttribute("Level")) or 0) < APPEARANCE_LEVEL then
			return false, "nav_locked_appearance_level"
		end
		return false, "nav_locked_appearance_none"
	end,
	run = function()
		local ok, NetworkManager = pcall(function()
			return require(Players.LocalPlayer:WaitForChild("PlayerScripts")
				:WaitForChild("Modules"):WaitForChild("NetworkManager"))
		end)
		if ok and type(NetworkManager) == "table" and NetworkManager.FireServer then
			NetworkManager.FireServer("UseAppearanceChange")
		end
	end,
}

-- ── progress (flyout) ────────────────────────────────────
E.achievements = {
	id = "achievements", kind = "panel", group = "progress", order = 1,
	label = "nav_achievements", icon = "achievements", glyph = "ACH",
	module = { folder = "UI", name = "AchievementsUI", export = "default" },
	places = ALL, class = "panel", presentation = "windowed", phone = "sheet",
	badge = "achievements", clearBadgeOnOpen = true,
}

E.dailyLogin = {
	id = "dailyLogin", kind = "panel", group = "progress", order = 2,
	label = "nav_daily", icon = "dailyLogin", glyph = "DAILY",
	module = { folder = "UI", name = "DailyLoginUI" },  -- §AGX/UI-P3 (W4)
	places = ALL,
	class = "panel", presentation = "dialog", phone = "dialog",
	dismissOnBackdrop = true,   -- D8: small dialog (DailyLoginUI, AppWindow variant "dialog")
	badge = "daily",
}

E.leaderboard = {
	id = "leaderboard", kind = "panel", group = "progress", order = 3,
	label = "nav_leaderboard", icon = "leaderboard", glyph = "RANK",
	module = { folder = "UI", name = "LeaderboardUI" },  -- §AGX/UI-P3 (W4)
	places = ALL,
	class = "panel", presentation = "windowed", phone = "sheet", combatSide = true,
}

-- ── social (flyout) ──────────────────────────────────────
E.party = {
	id = "party", kind = "panel", group = "social", order = 1,
	label = "nav_party", icon = "social", glyph = "PARTY",
	module = { folder = "Lobby", name = "SocialPanel" },
	places = LOBBY,
	lockedReason = { Plaza = "nav_locked_party", Combat = "nav_locked_party" },
	class = "panel", presentation = "windowed", phone = "sheet",
	badge = "party",
}

E.emotes = {
	id = "emotes", kind = "action", group = "social", order = 2,
	label = "nav_emotes", icon = "emote", glyph = "EMOTE",
	places = { Lobby = true, Plaza = true },
	lockedReason = { Combat = "nav_locked_battle" },
	-- Not a stack entry: the menu gives way, then the wheel toggles.
	run = function()
		local ok, EmoteWheel = pcall(function()
			return require(Players.LocalPlayer:WaitForChild("PlayerScripts")
				:WaitForChild("UI"):WaitForChild("EmoteWheel"))
		end)
		if ok and type(EmoteWheel) == "table" and EmoteWheel.toggle then
			EmoteWheel.toggle()
		end
	end,
}

-- ── store / system (direct) ──────────────────────────────
E.shop = {
	id = "shop", kind = "panel", group = "store", order = 1,
	label = "nav_shop", icon = "shop", glyph = "SHOP",
	module = { folder = "UI", name = "GlobalShopUI" },
	places = ALL, class = "panel", presentation = "windowed", phone = "sheet",
}

E.settings = {
	id = "settings", kind = "panel", group = "system", order = 1,
	label = "nav_settings", icon = "settings", glyph = "SET",
	module = { folder = "UI", name = "SettingsUI" },
	places = ALL, class = "panel", presentation = "windowed", phone = "sheet",
	combatSide = true,
	-- SettingsUI vetoes Back while a key is being captured (A11).
}

-- ── non-rail entries ─────────────────────────────────────
E.keybinds = {
	id = "keybinds", kind = "panel", rail = false,
	module = { folder = "UI", name = "KeybindSettings" },
	places = { Combat = true }, class = "panel", subOf = "class",
	presentation = "windowed", phone = "sheet",
	-- P3 keeps it as BattleClassUI's internal overlay (A13); P6 merges it
	-- into Settings (UX-13). The entry exists so push("keybinds") works.
}

E.npcDialog = {
	id = "npcDialog", kind = "external", rail = false,
	module = { folder = "Lobby", name = "NPCDialog" },
	places = LOBBY, class = "panel", mount = "always",
	presentation = "dialog", phone = "dialog", dismissOnBackdrop = false,
	-- D8 would allow click-outside (small), but the component still draws
	-- its own 0.5 dim with no click handler; the scrim stays off until P6
	-- restyles it, so a stray tap can't send NPCResponse Close.
}

E.npcShop = {
	id = "npcShop", kind = "external", rail = false,
	module = { folder = "Lobby", name = "ShopUI" },
	places = LOBBY, class = "panel", mount = "always",
	presentation = "windowed", phone = "sheet",
}

E.npcSmith = {
	id = "npcSmith", kind = "external", rail = false,
	module = { folder = "Lobby", name = "WeaponSmithUI" },
	places = LOBBY, class = "panel", mount = "always",
	presentation = "windowed", phone = "sheet",
}

E.characterCreation = {
	id = "characterCreation", kind = "modal", rail = false,
	module = { folder = "UI", name = "CharacterCreation" },
	places = ALL, class = "modal", closable = false,
	presentation = "fullscreen", phone = "fullscreen",
	closeProps = { "onDismiss" },
}

E.leaveConfirm = {
	id = "leaveConfirm", kind = "modal", rail = false,
	module = { folder = "Shell", name = "ConfirmDialog" },   -- Agent B (B7)
	places = { Plaza = true, Combat = true }, class = "modal",
	presentation = "dialog", phone = "dialog", dismissOnBackdrop = true,
	closeProps = { "onClose", "onCancel" },
}

E.vote = {
	id = "vote", kind = "presence", rail = false, class = "modal",
	places = { Combat = true },
	-- VoteUI self-manages; it calls PanelStack.useModalPresence("vote", visible).
}

E.death = {
	id = "death", kind = "presence", rail = false, class = "system",
	places = { Combat = true },
	-- ServerOpen reads LocalPlayer.DeathState; DeathUI is not edited.
}

local MENU_COMMON = {
	kind = "menu", rail = false, class = "menu", places = ALL,
	dismissOnBackdrop = true,
}
local function menuEntry(id, name, presentation)
	local t = table.clone(MENU_COMMON)
	t.id = id
	t.module = { folder = "Shell", name = name }
	t.presentation = presentation
	t.phone = "sheet"
	return t
end
E.menuSheet  = menuEntry("menuSheet",  "MenuSheet",  "sheet")
E.menuFlyout = menuEntry("menuFlyout", "MenuFlyout", "flyout")
E.menuRadial = menuEntry("menuRadial", "MenuRadial", "radial")

Registry.Entries = E

-- ═══════════════════════════════════════════════════════════
-- LOOKUPS
-- ═══════════════════════════════════════════════════════════

function Registry.get(id)
	return E[id]
end

--- Module spec + static props (+ dim) for this place (byPlace resolved).
function Registry.spec(entry, place)
	if not entry then return nil, nil, nil end
	if entry.byPlace then
		local b = entry.byPlace[place] or entry.byPlace.default
		if b then return b.module, b.props, b.dim end
	end
	return entry.module, entry.props, entry.dim
end

--- available?, lockedReason (Locale key)
function Registry.isAvailable(entry, place)
	if not entry then return false, "nav_locked" end
	if entry.places and entry.places[place] then
		-- §AGX/X18b: runtime gate (only where the place allows the entry).
		if type(entry.gate) == "function" then
			local ok, avail, reason = pcall(entry.gate, place)
			if not ok then return false, "nav_locked" end
			if not avail then return false, reason or "nav_locked" end
		end
		return true, nil
	end
	local reason = entry.lockedReason and entry.lockedReason[place]
	return false, reason or "nav_locked"
end

--- §AGX/X18b: cb() whenever a LocalPlayer attribute some entry's `gate`
--- reads changes. Returns an unsubscribe function.
function Registry.subscribeGates(cb)
	local lp = Players.LocalPlayer
	if not lp then return function() end end
	local seen, conns = {}, {}
	for _, entry in pairs(E) do
		for _, attr in ipairs(entry.gateAttributes or {}) do
			if not seen[attr] then
				seen[attr] = true
				table.insert(conns, lp:GetAttributeChangedSignal(attr):Connect(function()
					task.spawn(cb)
				end))
			end
		end
	end
	return function()
		for _, c in ipairs(conns) do c:Disconnect() end
		table.clear(conns)
	end
end

-- ═══════════════════════════════════════════════════════════
-- MODULE RESOLUTION (lazy, cached)
-- ═══════════════════════════════════════════════════════════

local cache = {}   -- [folder .. "/" .. name .. "#" .. export] = component | false

local function playerScripts()
	local lp = Players.LocalPlayer
	return lp and lp:FindFirstChild("PlayerScripts")
end

-- Folder instance for a module spec (non-yielding unless `wait`).
local function folderFor(spec, place, wait)
	local ps = playerScripts()
	if not ps and wait then
		ps = Players.LocalPlayer:WaitForChild("PlayerScripts")
	end
	if not ps then return nil end

	local function child(parent, name)
		if not parent then return nil end
		local c = parent:FindFirstChild(name)
		if not c and wait then c = parent:WaitForChild(name, 5) end
		return c
	end

	if spec.folder == "UI" then
		return child(ps, "UI")
	elseif spec.folder == "Shell" then
		return child(child(ps, "UI"), "Shell")
	elseif spec.folder == "Lobby" or spec.folder == "SocialPlaza" then
		-- A place folder: only when it IS the current place's folder;
		-- otherwise nil -> the entry reads as locked (defensive).
		local wanted = (spec.folder == "Lobby") and "Lobby" or "SocialPlaza"
		local names = Registry.PlaceFolders[place] or {}
		if not table.find(names, wanted) then return nil end
		return child(ps:FindFirstChild(wanted), "UI")
	end
	-- Any other folder name: first existing place folder of this place.
	for _, name in ipairs(Registry.PlaceFolders[place] or {}) do
		local f = ps:FindFirstChild(name)
		if f then return child(f, "UI") end
	end
	return nil
end

local function cacheKey(spec, place)
	local placeScoped = spec.folder ~= "UI" and spec.folder ~= "Shell"
	return (placeScoped and (place .. ":") or "") .. spec.folder .. "/" .. spec.name .. "#" .. tostring(spec.export)
end

local function requireComponent(module, spec)
	local ok, result = pcall(require, module)
	if not ok then
		warn("[Registry] require failed:", spec.name, result)
		return false
	end
	if spec.export then
		result = type(result) == "table" and result[spec.export] or nil
	end
	return result or false
end

--- Non-yielding: the cached component, or nil if not loaded yet / locked.
function Registry.resolve(entry, place)
	local spec = Registry.spec(entry, place)
	if not spec then return nil end
	local hit = cache[cacheKey(spec, place)]
	if hit ~= nil then return hit or nil end
	return nil
end

--- May yield (WaitForChild, first require). Never call from render.
function Registry.load(entry, place)
	local spec = Registry.spec(entry, place)
	if not spec then return nil end
	local key = cacheKey(spec, place)
	local hit = cache[key]
	if hit ~= nil then return hit or nil end
	local folder = folderFor(spec, place, true)
	local module = folder and (folder:FindFirstChild(spec.name) or folder:WaitForChild(spec.name, 5))
	if not module then
		-- Shell modules owned by other agents may not exist yet: don't
		-- cache the miss, so they resolve once they land.
		return nil
	end
	local comp = requireComponent(module, spec)
	cache[key] = comp
	return comp or nil
end

-- ═══════════════════════════════════════════════════════════
-- forPlace (menu surfaces)
-- ═══════════════════════════════════════════════════════════

local function sortedGroupEntries(groupId)
	local list = {}
	for _, entry in pairs(E) do
		if entry.group == groupId and entry.rail ~= false then
			table.insert(list, entry)
		end
	end
	table.sort(list, function(a, b)
		if (a.order or 0) ~= (b.order or 0) then return (a.order or 0) < (b.order or 0) end
		return a.id < b.id
	end)
	return list
end

--- { { group, entries = { { entry, available, lockedReason } } } } in group
--- order. Locked entries are kept (dimmed with their reason) so muscle memory
--- is stable across places; a `slot` keeps only its alternate for this place.
function Registry.forPlace(place)
	local out = {}
	for _, group in ipairs(Registry.Groups) do
		local rows = {}
		local slotSeen = {}
		local slotFallback = {}
		for _, entry in ipairs(sortedGroupEntries(group.id)) do
			local available, reason = Registry.isAvailable(entry, place)
			if entry.slot then
				if available and not slotSeen[entry.slot] then
					slotSeen[entry.slot] = true
					table.insert(rows, { entry = entry, available = true })
				elseif not slotFallback[entry.slot] then
					slotFallback[entry.slot] = { entry = entry, available = false, lockedReason = reason }
				end
			else
				table.insert(rows, { entry = entry, available = available, lockedReason = reason })
			end
		end
		for slot, row in pairs(slotFallback) do
			if not slotSeen[slot] then table.insert(rows, 1, row) end
		end
		table.insert(out, { group = group, entries = rows })
	end
	return out
end

--- Every entry id of this place PanelHost should preload / mount.
function Registry.entriesForPlace(place)
	local list = {}
	for _, entry in pairs(E) do
		if entry.kind ~= "action" and entry.kind ~= "presence"
			and (entry.module or entry.byPlace)
			and Registry.isAvailable(entry, place) then
			table.insert(list, entry)
		end
	end
	table.sort(list, function(a, b) return a.id < b.id end)
	return list
end

return Registry
