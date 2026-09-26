-- StarterPlayerScripts/Modules/SkillInput

local SkillInput = {}

local Players      = game:GetService("Players")
-- §AGX/UI-P4: StarterGui (SetCore chat message) no longer needed; M6.

-- §AGX/UI-P4: Notify (UI/Common) is required lazily on first failure so
-- this module's load order is unaffected (SkillPad requires SkillInput).
local Notify = nil
local function getNotify()
	if not Notify then
		local ok, mod = pcall(function()
			return require(Players.LocalPlayer:WaitForChild("PlayerScripts")
				:WaitForChild("UI"):WaitForChild("Common"):WaitForChild("Notify"))
		end)
		if ok then Notify = mod end
	end
	return Notify
end

local player = Players.LocalPlayer

-- Dependencies (set during init)
local NetworkManager = nil
local InputSystem    = nil

-- Cooldown display (local)
-- §AGX/UI-P2: was `[skillId] = endTime` with the SERVER's os.clock(), which
-- can't be compared with the client clock and had no reader. Now keyed by
-- skillId -> { endsAt = client os.clock(), total = seconds } from the
-- event's `cooldown` duration, and exposed per slot via GetCooldown().
local skillCooldowns = {}

-- §AGX/UI-P2: slot <-> skillId. The server reports cooldowns by real skill id
-- (SkillManager.StartCooldown) but the client only knows slots. Filled from
-- the SetupPlayer `skills` list when we catch it, otherwise learned by
-- matching each SkillRequest to its reply (cooldown start or SkillFailed),
-- which the server sends in request order.
local slotToSkillId   = {}   -- [slot] = skillId
local skillIdToSlot   = {}   -- [skillId] = slot
local pendingRequests = {}   -- FIFO { slot, t, cur }
local PENDING_TTL     = 3    -- s; a request dropped by the rate limiter expires

-- §AGX/UI-P2: affordability (D10). Skill costs are server-only
-- (ClassSkills/*.lua), so the client learns a lower bound per slot from
-- failures ("Not enough X" -> cost > resource at request time,
-- "Need at least N" -> N) and relaxes it when a cast succeeds.
local minCost     = {}   -- [slot] = resource needed (learned)
local unlockLevel = {}   -- [slot] = level from "unlocks at level N"
local activeClass = nil

local ResourceCache = nil

-- §AGX/UI-P2: tiny signals for the SkillPad / ActionBar.
local cooldownListeners = {}
local stateListeners    = {}
local listenerNextId    = 1

local function addListener(list, cb)
	local id = listenerNextId
	listenerNextId = listenerNextId + 1
	list[id] = cb
	return function() list[id] = nil end
end

local function emit(list, ...)
	for _, cb in pairs(list) do
		task.spawn(cb, ...)
	end
end

local function currentResource()
	if not ResourceCache then return nil end
	return ResourceCache.GetLatest().cur
end

local function mapSlot(slot, skillId)
	if type(slot) ~= "number" or type(skillId) ~= "string" then return end
	if skillId:sub(1, 5) == "slot_" then return end
	local oldId = slotToSkillId[slot]
	if oldId and oldId ~= skillId then skillIdToSlot[oldId] = nil end
	local oldSlot = skillIdToSlot[skillId]
	if oldSlot and oldSlot ~= slot then slotToSkillId[oldSlot] = nil end
	slotToSkillId[slot] = skillId
	skillIdToSlot[skillId] = slot
end

-- Pops the oldest live request (the one this reply answers).
local function popPending()
	local now = os.clock()
	while #pendingRequests > 0 do
		local req = table.remove(pendingRequests, 1)
		if now - req.t <= PENDING_TTL then return req end
	end
	return nil
end

local function resetSlotKnowledge()
	table.clear(slotToSkillId)
	table.clear(skillIdToSlot)
	table.clear(minCost)
	table.clear(unlockLevel)
	table.clear(skillCooldowns)
	table.clear(pendingRequests)
end

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

local initialized = false

function SkillInput.Init()
	if initialized then return end
	initialized = true

	local Modules = script.Parent
	NetworkManager = require(Modules:WaitForChild("NetworkManager"))
	InputSystem    = require(Modules:WaitForChild("InputSystem"))

	-- Bind each skill slot to the corresponding InputSystem action
	for slot = 1, 4 do
		InputSystem.BindAction("Skill" .. slot, function(_actionName, inputState)
			if inputState ~= "Began" then return end
			SkillInput.TryUseSkill(slot)
		end)
	end

	-- Bind Dash (slot 5) to the dedicated Dash action (Spacebar)
	InputSystem.BindAction("Dash", function(_actionName, inputState)
		if inputState ~= "Began" then return end
		SkillInput.TryUseSkill(5)
	end)

	-- §AGX/UI-P2: resource snapshot for affordability; re-emit on change.
	ResourceCache = require(Modules:WaitForChild("ResourceCache"))
	ResourceCache.Subscribe(function()
		emit(stateListeners)
	end)

	-- Listen for cooldown updates
	-- §AGX/UI-P2: payload shapes (SkillManager/init.lua):
	--   SetupPlayer   { skills = {[slot] = id}, cooldowns = {} }
	--   StartCooldown { skillId, cooldown, endTime }   (endTime = server clock)
	--   Reset*        { skillId, cooldown = 0, reset = true }
	NetworkManager.OnServerEvent("SkillCooldownUpdate", function(data)
		if type(data) ~= "table" then return end

		if type(data.skills) == "table" then
			for slot, id in pairs(data.skills) do
				mapSlot(tonumber(slot), id)
			end
			-- §AGX/UI-P2: server-sent base costs seed affordability.
			if type(data.costs) == "table" then
				for slot, cost in pairs(data.costs) do
					local s = tonumber(slot)
					if s and type(cost) == "number" and cost > 0 then minCost[s] = cost end
				end
			end
			emit(stateListeners)
		end

		local skillId = data.skillId
		if not skillId then return end

		if data.reset or not data.cooldown or data.cooldown <= 0 then
			skillCooldowns[skillId] = nil
			emit(cooldownListeners, skillIdToSlot[skillId])
			return
		end

		-- A cooldown start answers our oldest pending SkillRequest.
		local req = popPending()
		if req then
			mapSlot(req.slot, skillId)
			-- Success proves cost <= resource at request time.
			local need = minCost[req.slot]
			if need and req.cur and req.cur < need then
				minCost[req.slot] = req.cur
			end
		end

		skillCooldowns[skillId] = {
			endsAt = os.clock() + data.cooldown,
			total  = data.cooldown,
		}
		emit(cooldownListeners, skillIdToSlot[skillId])
	end)

	-- §AGX/UI-P2: a class change invalidates every slot mapping and cost.
	NetworkManager.OnServerEvent("PlayerInfoUpdate", function(data)
		if type(data) ~= "table" or not data.activeClass then return end
		if activeClass ~= nil and data.activeClass ~= activeClass then
			resetSlotKnowledge()
			emit(cooldownListeners, nil)
		end
		activeClass = data.activeClass
		emit(stateListeners)
	end)

	-- SkillActivated / SkillFailed: same late-loading issue as SkillVisuals.
	-- Use task.spawn + infinite WaitForChild to avoid the 3s timeout race.
	local Events = game:GetService("ReplicatedStorage"):WaitForChild("Events")

	-- §AGX/X21 (G21): removed the per-cast debug print on SkillActivated.

	task.spawn(function()
		Events:WaitForChild("SkillFailed").OnClientEvent:Connect(function(data)
			warn("[SkillInput] Skill failed:", data.skillId, "-", data.reason)
			-- §AGX/UI-P2: a failure also answers the oldest pending request.
			SkillInput._LearnFromFailure(data)
			-- §AGX/UI-P4: M6: was a SetCore("ChatMakeSystemMessage") line,
			-- invisible on phones where chat is collapsed. Now a warning
			-- toast; one key so spamming a skill on cooldown updates a
			-- single toast (×N) instead of stacking.
			local notify = getNotify()
			if notify then
				notify.toast("warning", tostring(data.reason or "Skill failed"), { key = "skillFailed" })
			end
		end)
	end)

	-- Restore player's saved keybindings when the server sends PlayerInfoUpdate
	NetworkManager.OnServerEvent("PlayerInfoUpdate", function(data)
		if data and data.keybindings then
			InputSystem.LoadBindings(data.keybindings)
		end
	end)

end

-- ═══════════════════════════════════════════════════════════
-- SKILL USAGE
-- ═══════════════════════════════════════════════════════════

function SkillInput.TryUseSkill(slot)
	-- Scene gate: skills disabled in Village
	if player:GetAttribute("SkillsEnabled") == false then return end

	-- Block skills while knocked down or dead.
	-- §LD-PA1 follow-up: same first-spawn race as PlayerAttack — was
	-- `~= "Alive"` and treated nil as death. SkillManager's server-side
	-- check is strict, so the client only needs to suppress the
	-- explicit not-alive states.
	local deathState = player:GetAttribute("DeathState")
	if deathState == "KnockedDown" or deathState == "Dead" then return end

	local moveDirection = SkillInput.GetMoveDirection()
	local lookDirection = SkillInput.GetLookDirection()

	-- §AGX/UI-P2: remember the request so its reply can be tied to this slot.
	table.insert(pendingRequests, { slot = slot, t = os.clock(), cur = currentResource() })

	NetworkManager.FireServer("SkillRequest", "slot_" .. slot, {
		slot          = slot,
		moveDirection = moveDirection,
		lookDirection = lookDirection,   -- authoritative facing direction for projectile skills
	})
end

function SkillInput.GetMoveDirection()
	local character = player.Character
	if not character then return Vector3.zero end

	local humanoid = character:FindFirstChild("Humanoid")
	if not humanoid then return Vector3.zero end

	local moveDir = humanoid.MoveDirection

	if moveDir.Magnitude > 0.1 then
		return Vector3.new(moveDir.X, 0, moveDir.Z).Unit
	end

	return Vector3.zero
end

--- Returns the direction the character is currently FACING (flat Y=0, normalised).
--- Uses the client-side rootPart.CFrame which FaceDirection has already corrected,
--- making this the authoritative look direction to send to the server for projectile skills.
function SkillInput.GetLookDirection()
	local character = player.Character
	if not character then return Vector3.new(0, 0, -1) end

	local rootPart = character:FindFirstChild("HumanoidRootPart")
	if not rootPart then return Vector3.new(0, 0, -1) end

	local look = rootPart.CFrame.LookVector
	local flat = Vector3.new(look.X, 0, look.Z)
	if flat.Magnitude > 0.001 then
		return flat.Unit
	end

	return Vector3.new(0, 0, -1)
end

-- ═══════════════════════════════════════════════════════════
-- COOLDOWN / AFFORDABILITY QUERIES (§AGX/UI-P2)
-- ═══════════════════════════════════════════════════════════

--- Internal: update slot mapping and learned costs from a SkillFailed payload.
function SkillInput._LearnFromFailure(data)
	if type(data) ~= "table" then return end
	local req = popPending()
	local skillId = data.skillId
	local slot = nil
	if type(skillId) == "string" and skillId:sub(1, 5) == "slot_" then
		slot = tonumber(skillId:sub(6))
	elseif req then
		mapSlot(req.slot, skillId)
		slot = req.slot
	end
	if not slot then slot = skillIdToSlot[skillId] end
	if not slot then return end

	local reason = tostring(data.reason or "")
	local changed = false
	local needAtLeast = tonumber(string.match(reason, "Need at least (%d+)"))
	local level = tonumber(string.match(reason, "unlocks at level (%d+)"))
	if needAtLeast then
		minCost[slot] = needAtLeast
		changed = true
	elseif string.find(reason, "Not enough", 1, true) then
		local cur = (req and req.cur) or currentResource()
		if cur then
			minCost[slot] = math.max(minCost[slot] or 0, math.floor(cur) + 1)
			changed = true
		end
	elseif level then
		unlockLevel[slot] = level
		changed = true
	elseif reason == "On cooldown" and type(data.cooldownRemaining) == "number" and skillId then
		-- Resync a cooldown we missed (e.g. UI mounted after the cast).
		if not skillCooldowns[skillId] and data.cooldownRemaining > 0 then
			skillCooldowns[skillId] = {
				endsAt = os.clock() + data.cooldownRemaining,
				total  = data.cooldownRemaining,
			}
			emit(cooldownListeners, slot)
		end
	end
	if changed then emit(stateListeners) end
end

--- Remaining and total cooldown seconds for a slot (1-4 skills, 5 = Dash).
--- Returns 0, 0 when ready or unknown.
function SkillInput.GetCooldown(slot)
	local skillId = slotToSkillId[slot]
	local cd = skillId and skillCooldowns[skillId]
	if not cd then return 0, 0 end
	local remaining = cd.endsAt - os.clock()
	if remaining <= 0 then
		skillCooldowns[skillId] = nil
		return 0, 0
	end
	return remaining, cd.total
end

--- cb(slot | nil) when a cooldown starts or resets (nil = all slots).
--- Returns a disconnect function. Remaining time is polled via GetCooldown.
function SkillInput.OnCooldownChanged(callback)
	return addListener(cooldownListeners, callback)
end

--- Whether the slot can be paid for right now (D10 dimming).
--- Returns affordable, known: `known` is false while nothing has been
--- learned for the slot yet (then affordable is optimistically true).
--- Also false while the slot is level-locked.
function SkillInput.IsAffordable(slot)
	local lvl = unlockLevel[slot]
	if lvl then
		if (player:GetAttribute("Level") or 1) < lvl then return false, true end
		unlockLevel[slot] = nil
	end
	local need = minCost[slot]
	if not need then return true, false end
	local cur = currentResource()
	if not cur then return true, false end
	return cur >= need, true
end

--- cb() when resource, learned costs, slot mapping or class change.
--- Returns a disconnect function.
function SkillInput.OnSkillStateChanged(callback)
	return addListener(stateListeners, callback)
end

--- Active class name from PlayerInfoUpdate (nil until known).
function SkillInput.GetActiveClass()
	return activeClass
end

return SkillInput