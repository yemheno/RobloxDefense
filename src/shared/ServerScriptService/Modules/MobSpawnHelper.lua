-- ServerScriptService/Modules/MobSpawnHelper
--[[
    MobSpawnHelper  (§T3/W9)
    ========================
    Shared spawning primitives for MobSpawner (wave defense) and
    HordeModeSpawner. Consolidates the three helpers that had drifted
    into per-spawner copies, with the semantics Pablo picked:

    • CloneTemplate — NEVER gives up (§W9a). A run must always deliver
      its full mob count — "imagine you skip a miniboss". Transient
      Clone failures retry forever with exponential backoff; the only
      exits are success or the caller's shouldAbort() (run reset /
      spawner stopped). Missing/invalid templates are the CALLER's
      problem (config error — warn loudly, don't retry the impossible).

    • GetSpawnCFrame — uniform scatter across the WHOLE spawn part
      (§W9b). Spawn probability is uniform over the part's X/Z
      footprint in the part's own space (orientation preserved), so
      resizing the part in Studio directly reshapes the spawn area.
      Replaces MobSpawner's fixed-X ±5-stud Z hack and HordeMode's
      exact-marker-point spawns.

    • PickWeightedId — the weighted-random pick that existed verbatim
      in both spawners.

    Difficulty-override stacking intentionally stays per-spawner:
    HordeMode stacks mode-base × tier (from GameModeConfig), wave
    defense applies the tier directly — a real mode difference, not
    duplication.
]]

local MobSpawnHelper = {}

-- ═══════════════════════════════════════════════════════════
-- WEIGHTED PICK
-- ═══════════════════════════════════════════════════════════

--- Weighted random pick from a { [id] = weight } table.
--- Returns nil only for an empty table.
function MobSpawnHelper.PickWeightedId(weights)
	local totalWeight = 0
	for _, weight in pairs(weights) do
		totalWeight = totalWeight + weight
	end
	if totalWeight <= 0 then
		for id in pairs(weights) do
			return id
		end
		return nil
	end

	local roll = math.random() * totalWeight
	local cumulative = 0
	for id, weight in pairs(weights) do
		cumulative = cumulative + weight
		if roll <= cumulative then
			return id
		end
	end

	-- Float-edge fallback: return any entry.
	for id in pairs(weights) do
		return id
	end
	return nil
end

-- ═══════════════════════════════════════════════════════════
-- CLONE (never-fail)
-- ═══════════════════════════════════════════════════════════

--- Clone `template` with infinite retry + exponential backoff.
--- @param template Instance   the cached mob template (caller validates non-nil)
--- @param mobId string        for log messages
--- @param tag string          log prefix, e.g. "[MobSpawner]"
--- @param shouldAbort function|nil  returns true → stop retrying, return nil
--- @return Model|nil          the clone, or nil ONLY if aborted
function MobSpawnHelper.CloneTemplate(template, mobId, tag, shouldAbort)
	local backoff = 0.05
	local attempt = 0
	while true do
		attempt += 1
		local ok, result = pcall(template.Clone, template)
		if ok and result then
			if attempt > 1 then
				warn(string.format("%s Clone for %s succeeded on attempt %d.",
					tag, tostring(mobId), attempt))
			end
			return result
		end

		warn(string.format("%s Clone failed for %s (attempt %d): %s — retrying in %.2fs.",
			tag, tostring(mobId), attempt, tostring(result), backoff))
		task.wait(backoff)
		backoff = math.min(backoff * 2, 1)

		if shouldAbort and shouldAbort() then
			warn(string.format("%s Aborting Clone retry for %s — spawner stopped/reset.",
				tag, tostring(mobId)))
			return nil
		end
	end
end

-- ═══════════════════════════════════════════════════════════
-- SPAWN POSITION (uniform over the spawn part)
-- ═══════════════════════════════════════════════════════════

--- Uniform-random CFrame across a spawn part's X/Z footprint, lifted
--- `yOffset` studs above the part's top surface, preserving the part's
--- orientation. Resize the part in Studio to reshape the spawn area.
--- @param spawnPart BasePart
--- @param yOffset number|nil  default 3 (§LD-MS1 ground-clip lift)
function MobSpawnHelper.GetSpawnCFrame(spawnPart, yOffset)
	yOffset = yOffset or 3
	local size = spawnPart.Size
	local rx = (math.random() - 0.5) * size.X
	local rz = (math.random() - 0.5) * size.Z
	return spawnPart.CFrame * CFrame.new(rx, size.Y / 2 + yOffset, rz)
end

-- ═══════════════════════════════════════════════════════════
-- NETWORK OWNERSHIP (server-pinned mob physics)
-- ═══════════════════════════════════════════════════════════

-- §AGX/X45: which tiers get their physics pinned to the server. Default:
-- ALL tiers, normal included. The Humanoid budget
-- (ARCHITECTURE.md#scaling) is already a server-side cost; Horde's
-- aliveCap = 72 sits well inside it, so server-owning trash adds only
-- the assembly integration and removes the ownership hand-off churn.
-- Auto ownership let a nearby client own a mob: the client's sim fought
-- the server's MoveTo (rubber-banding) and an exploiter could teleport
-- it past DefenseDetection's X check. Flip `normal = false` here if a
-- Studio profile of a 72-mob Horde shows server physics over budget.
local SERVER_OWNED_TIERS = {
	normal   = true,
	elite    = true,
	miniboss = true,
	boss     = true,
}

--- Pin a mob's physics assembly to the server. Call right after the
--- model is parented to workspace. No-op (and never errors) for
--- anchored assemblies, unparented models or tiers not in the table.
--- @param rootPart BasePart  the mob's HumanoidRootPart
--- @param tier string|nil    MobTier ("normal" when nil)
--- @return boolean           true if ownership was set to the server
function MobSpawnHelper.PinServerOwnership(rootPart, tier)
	-- §AGX/X45: unknown tiers default to server-owned (safe side).
	local want = SERVER_OWNED_TIERS[tier or "normal"]
	if want == false then return false end
	if not rootPart or not rootPart:IsA("BasePart") then return false end
	if not rootPart:IsDescendantOf(workspace) then return false end
	-- §AGX/X45: SetNetworkOwner errors on anchored parts / assemblies
	-- welded to anchored parts; CanSetNetworkOwnership covers both.
	if rootPart.Anchored then return false end
	local okCan, can = pcall(rootPart.CanSetNetworkOwnership, rootPart)
	if not okCan or not can then return false end
	local ok = pcall(rootPart.SetNetworkOwner, rootPart, nil)
	return ok
end

return MobSpawnHelper
