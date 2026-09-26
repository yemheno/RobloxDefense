-- ServerScriptService/Modules/ClassManager
--[[
    ClassManager
    ============
    Thin orchestration layer over ClassConfig, PlayerDataManager, and
    the per-class equipment / cosmetic / resource modules.

    State storage: NONE in this module. Everything persistent lives in
    PlayerData (Account.UnlockedClasses, ActiveClass, LastClassSwitch,
    data.Classes[name]); transient class metadata lives in ClassConfig.

    Public API
    ----------
      ClassManager.Init()
      ClassManager.GetClassName(player)
      ClassManager.GetClassData(player)
      ClassManager.IsRanged(player)
      ClassManager.GetAttackShape(player)        -- WeaponManager
      ClassManager.GetShapeParams(player)        -- WeaponManager
      ClassManager.GetAttackSpeed(player)        -- WeaponManager
      ClassManager.GetAttackCooldown(player)
      ClassManager.GetWeaponAttack(player)       -- WeaponManager
      ClassManager.GetProjectileConfig(player)
      ClassManager.GetBasicAttackAnimation(player)
      ClassManager.ApplyInnateBonus(player, className?)
      ClassManager.SetClass(player, className)

    Network events
    --------------
      RequestClassSwitch  (client → server)
      ClassSwitchResult   (server → client)

    §T1.2 changes
    -------------
      • D2 — six `task.spawn(require(...))` Init fan-outs replaced with
        lazy getters (same pattern as the existing getBonusManager).
        Eliminates the boot race where a class-switch in the first
        ~100 ms would silently no-op the equipment/visual/resource
        updates because the module ref was still nil.
      • D3 — `GetClassConfig(name)` deleted. Use `ClassConfig.GetClass`.
      • D7 — class-side attack fallbacks dropped. WeaponManager owns
        attackShape / shapeParams / attackSpeed; ClassConfig no longer
        carries them.
      • D8 — comment on the GameStateManager silent-pass in non-combat
        places.
]]

local ClassManager = {}

local Modules = script.Parent
local ClassConfig       = require(Modules:WaitForChild("ClassConfig"))
local PlayerDataManager = require(Modules:WaitForChild("PlayerDataManager"))

-- ─────────────────────────────────────────────────────────────────────
-- LAZY GETTERS (§T1.2/D2)
-- Required modules are loaded on first use rather than spawned-and-
-- forgotten in Init. Each getter caches the result in an upvalue so
-- the require() runs at most once per server.
-- ─────────────────────────────────────────────────────────────────────

local _BonusManager
local function getBonusManager()
    if _BonusManager == nil then
        local mod = Modules:FindFirstChild("BonusManager")
        _BonusManager = (mod and require(mod)) or false
    end
    return _BonusManager or nil
end

local _WeaponManager
local function getWeaponManager()
    if _WeaponManager == nil then
        local mod = Modules:FindFirstChild("WeaponManager")
        _WeaponManager = (mod and require(mod)) or false
    end
    return _WeaponManager or nil
end

local _ArmorManager
local function getArmorManager()
    if _ArmorManager == nil then
        local mod = Modules:FindFirstChild("ArmorManager")
        _ArmorManager = (mod and require(mod)) or false
    end
    return _ArmorManager or nil
end

local _ResourceManager
local function getResourceManager()
    if _ResourceManager == nil then
        local mod = Modules:FindFirstChild("ResourceManager")
        _ResourceManager = (mod and require(mod)) or false
    end
    return _ResourceManager or nil
end

local _VisualEquipmentManager
local function getVisualEquipmentManager()
    if _VisualEquipmentManager == nil then
        local mod = Modules:FindFirstChild("VisualEquipmentManager")
        _VisualEquipmentManager = (mod and require(mod)) or false
    end
    return _VisualEquipmentManager or nil
end

local _CosmeticManager
local function getCosmeticManager()
    if _CosmeticManager == nil then
        local mod = Modules:FindFirstChild("CosmeticManager")
        _CosmeticManager = (mod and require(mod)) or false
    end
    return _CosmeticManager or nil
end

local _GameStateManager
local function getGameStateManager()
    if _GameStateManager == nil then
        local mod = Modules:FindFirstChild("GameStateManager")
        _GameStateManager = (mod and require(mod)) or false
    end
    return _GameStateManager or nil
end

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════
function ClassManager.Init()
    -- §T1.2/D1: ClassManager owns the per-player innate-bonus pump.
    -- PlaceLifecycle's per-player chain DELIBERATELY does not call this;
    -- routing it through OnPlayerDataReady directly here means the call
    -- fires regardless of place and regardless of whether PlaceLifecycle
    -- ran for this player.
    PlayerDataManager.OnPlayerDataReady(function(player)
        ClassManager.ApplyInnateBonus(player)
        -- §AGX/WC: mirror the loaded class into the ActiveClass attribute
        -- (read by the lobby's TeleportManager for partyData.class and by
        -- TeleportDataReader's fallbacks). Idempotent.
        player:SetAttribute("ActiveClass", PlayerDataManager.GetActiveClass(player))
    end)

    local NetworkManager = require(Modules:WaitForChild("NetworkManager"))

    -- Pre-create ClassSwitchResult so the client's WaitForChild resolves
    -- immediately on mount.
    NetworkManager.GetEvent("ClassSwitchResult")

    NetworkManager.OnClientEvent("RequestClassSwitch", function(player, className)
        if not ClassConfig.Classes[className] then
            NetworkManager.FireClient(player, "ClassSwitchResult", false, "Unknown class: " .. tostring(className))
            return
        end

        -- §T1.2/D8: GameStateManager is only loaded in combat places
        -- (LaneDefense / HordeMode / CentralBoss). Non-combat places
        -- (Lobby / SocialPlaza) don't load it and this check falls
        -- through — by design, since there is no "combat" state to
        -- block against in those places.
        local gsm = getGameStateManager()
        if gsm and gsm.IsInGame() then
            NetworkManager.FireClient(player, "ClassSwitchResult", false, "Cannot switch class during combat")
            return
        end

        local canSwitch, reason = PlayerDataManager.CanSwitchClass(player)
        if not canSwitch then
            NetworkManager.FireClient(player, "ClassSwitchResult", false, "Cooldown: " .. tostring(math.ceil(reason)) .. "s remaining")
            return
        end

        local ok, err = ClassManager.SetClass(player, className)
        NetworkManager.FireClient(player, "ClassSwitchResult", ok, err or className)
    end)
end

-- ═══════════════════════════════════════════════════════════
-- CLASS INFO
-- ═══════════════════════════════════════════════════════════
function ClassManager.GetClassName(player)
    return PlayerDataManager.GetActiveClass(player)
end

function ClassManager.GetClassData(player)
    local className = ClassManager.GetClassName(player)
    return ClassConfig.Classes[className]
end

-- ═══════════════════════════════════════════════════════════
-- ATTACK TYPE (Class determines melee vs ranged)
-- ═══════════════════════════════════════════════════════════
function ClassManager.IsRanged(player)
    local classData = ClassManager.GetClassData(player)
    return classData and classData.ranged == true
end

-- ═══════════════════════════════════════════════════════════
-- ATTACK SHAPE / SPEED — owned by WeaponManager (§T1.2/D7)
-- The class-side defaults (attackShape, shapeParams, baseAttackSpeed)
-- have been removed from ClassConfig. WeaponManager.GetAttackShape /
-- GetAttackSpeed are the canonical sources; they handle the "no
-- weapon equipped" case themselves.
-- ═══════════════════════════════════════════════════════════

function ClassManager.GetAttackShape(player)
    local wm = getWeaponManager()
    if not wm then return nil end
    local shape, _ = wm.GetAttackShape(player)
    return shape
end

function ClassManager.GetShapeParams(player)
    local wm = getWeaponManager()
    if not wm then return nil end
    local _, params = wm.GetAttackShape(player)
    return params
end

-- §AGX/STATS: AttackSpeed bonus (percent points; gear rolls, Frenzy card,
-- Eagle Eye's -X%, talents) scales the weapon's attacks/sec, clamped by
-- StatCaps.AttackSpeed. Per-attack path: one table read + one clamp, and
-- the clamp function is resolved once (Audit_4.7 §5.4).
local _capStat = nil
local function capAttackSpeed(pct)
    if not _capStat then
        local cfg = require(Modules:WaitForChild("PlayerDataConfig"))
        _capStat = cfg.CapStat or function(_, v) return v end
    end
    return _capStat("AttackSpeed", pct)
end

--- Attacks per second. `bonusOverride` (optional) evaluates the same
--- formula with a different AttackSpeed % — AttackHandler uses it to price
--- the pre-change cadence for its transition grace.
function ClassManager.GetAttackSpeed(player, bonusOverride)
    local wm = getWeaponManager()
    local speed = (wm and wm.GetAttackSpeed(player)) or 1.0
    local pct = bonusOverride
    if pct == nil then
        local data = PlayerDataManager.GetData(player)
        local bonus = data and data.Bonus
        pct = bonus and bonus.AttackSpeed or 0
    end
    if pct ~= 0 then
        speed = speed * (1 + capAttackSpeed(pct) / 100)
    end
    return speed
end

function ClassManager.GetAttackCooldown(player)
    return 1 / ClassManager.GetAttackSpeed(player)
end

-- ═══════════════════════════════════════════════════════════
-- WEAPON ATTACK VALUE
-- ═══════════════════════════════════════════════════════════
function ClassManager.GetWeaponAttack(player)
    local wm = getWeaponManager()
    if wm then return wm.GetWeaponAttack(player) end
    return 10  -- pre-WeaponManager fallback; should never fire in practice
end

-- ═══════════════════════════════════════════════════════════
-- PROJECTILE CONFIG (Ranged classes only)
-- ═══════════════════════════════════════════════════════════
function ClassManager.GetProjectileConfig(player)
    local classData = ClassManager.GetClassData(player)
    return classData and classData.projectile or nil
end

-- ═══════════════════════════════════════════════════════════
-- ANIMATIONS
-- ═══════════════════════════════════════════════════════════
function ClassManager.GetBasicAttackAnimation(player)
    local classData = ClassManager.GetClassData(player)
    if not classData then return nil end
    return classData.animations and classData.animations.basicAttack or nil
end

-- ═══════════════════════════════════════════════════════════
-- INNATE BONUS APPLICATION
-- ═══════════════════════════════════════════════════════════
--- Read the active (or given) class's innateBonuses and write them into
--- BonusManager's "innate" source, replacing any old class's passives.
function ClassManager.ApplyInnateBonus(player, className)
    local bm = getBonusManager()
    if not bm then return end
    local cn = className or PlayerDataManager.GetActiveClass(player)
    local classConfig = ClassConfig.Classes[cn]
    bm.SetSourceBonuses(player, "innate", (classConfig and classConfig.innateBonuses) or {})
end

-- ═══════════════════════════════════════════════════════════
-- CLASS SWITCHING
-- ═══════════════════════════════════════════════════════════
function ClassManager.SetClass(player, className)
    if not ClassConfig.Classes[className] then
        return false, "Invalid class"
    end

    local oldClassName = PlayerDataManager.GetActiveClass(player)

    local success, err = PlayerDataManager.SetActiveClass(player, className)
    if not success then
        return false, err
    end

    -- Resource bar reset for the new class
    local rm = getResourceManager()
    if rm and rm.OnClassChanged then
        rm.OnClassChanged(player, className, oldClassName)
    end

    -- Ensure starter equipment for the new class
    local wm = getWeaponManager()
    if wm then
        wm.EnsureStarterWeapon(player)
        PlayerDataManager.RefreshWeaponStats(player)
    end

    local am = getArmorManager()
    if am then
        am.EnsureStarterArmor(player)
    end

    -- Re-attach the weapon visual for the new class
    local vem = getVisualEquipmentManager()
    if vem and wm then
        local WeaponRegistry = require(Modules:WaitForChild("WeaponRegistry"))
        local wInst = wm.GetEquippedWeapon(player)
        if wInst then
            local wDef = WeaponRegistry.GetWeapon(wInst.weaponId)
            if wDef and wDef.weaponSlot then
                vem.AttachClassWeapon(player, className, wDef.weaponSlot)
            end
        end
    end

    -- Swap cosmetics (outfit, headgear) to match new class defaults
    local cm = getCosmeticManager()
    if cm then
        cm.OnClassSwitched(player, className)
    end

    -- Apply innate class passives via BonusManager
    ClassManager.ApplyInnateBonus(player, className)

    return true
end

-- ═══════════════════════════════════════════════════════════
-- §AGX/WC: §T0P2-TPCLASS — PARTY-SELECTED CLASS ON ARRIVAL
-- ═══════════════════════════════════════════════════════════
local _ReadyGate
local function getReadyGate()
    if _ReadyGate == nil then
        local mod = Modules:FindFirstChild("ReadyGate")
        local ok, result = false, nil
        if mod then ok, result = pcall(require, mod) end
        _ReadyGate = ok and result or false
    end
    return _ReadyGate or nil
end

--- Consume the one-shot "TeleportClass" attribute (set by
--- TeleportDataReader.ApplyPlayerData from the party payload). The payload
--- transits the client, so it is NEVER trusted: the class must exist in
--- ClassConfig AND be in this player's Account.UnlockedClasses, and the
--- run must not be in combat yet. Otherwise it's ignored with a warn.
--- Applied through ClassManager.SetClass (the normal class-change path).
--- The 30 s switch cooldown is deliberately not checked: this restores the
--- class picked in the lobby (usually right before queueing), it isn't a
--- new switch. Returns true if the player ends up on the requested class.
function ClassManager.ApplyTeleportClass(player)
    local requested = player:GetAttribute("TeleportClass")
    if requested == nil then return false end
    player:SetAttribute("TeleportClass", nil)  -- one-shot

    if type(requested) ~= "string" or not ClassConfig.Classes[requested] then
        warn("[ClassManager] Ignoring TeleportClass for", player.Name, "— unknown class:", tostring(requested))
        return false
    end
    if not PlayerDataManager.GetData(player) then
        warn("[ClassManager] Ignoring TeleportClass for", player.Name, "— data not loaded")
        return false
    end
    if PlayerDataManager.GetActiveClass(player) == requested then
        return true
    end
    if not PlayerDataManager.IsClassUnlocked(player, requested) then
        warn("[ClassManager] Ignoring TeleportClass for", player.Name, "—", requested, "is not unlocked")
        return false
    end
    local gsm = getGameStateManager()
    if gsm and gsm.IsInGame() then
        warn("[ClassManager] Ignoring TeleportClass for", player.Name, "— run already in combat")
        return false
    end

    -- §AGX/STATS (N1): SetClass stamps LastClassSwitch = os.time(), which
    -- started the 30 s manual-switch cooldown on arrival. Restoring the
    -- lobby pick isn't a new switch, so put the previous stamp back.
    local data = PlayerDataManager.GetData(player)
    local prevSwitch = data and data.LastClassSwitch
    local ok, err = ClassManager.SetClass(player, requested)
    if ok and data and prevSwitch ~= nil then
        data.LastClassSwitch = prevSwitch
    end
    if not ok then
        warn("[ClassManager] TeleportClass switch to", requested, "failed for", player.Name, ":", tostring(err))
        return false
    end
    print("[ClassManager]", player.Name, "arrived as party-selected class", requested)
    -- Same reply the manual switch sends; queued until ClientReady.
    local rg = getReadyGate()
    if rg then
        rg.FireClient(player, "ClassSwitchResult", true, requested)
    end
    return true
end

return ClassManager
