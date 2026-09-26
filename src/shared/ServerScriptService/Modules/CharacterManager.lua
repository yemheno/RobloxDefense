-- ServerScriptService/Modules/CharacterManager
--[[
    CharacterManager
    ================
    Orchestrates one-time character creation for new players and manages
    template application on every spawn.

    Flow
    ----
      1. PlayerDataManager.OnPlayerDataReady fires for a player.
      2. SetupPlayer (private) runs once per player session:
           • Subscribes to player.CharacterAdded so every spawn re-applies.
           • If CharacterData.isCreated is false, fires CharacterCreationRequired
             through ReadyGate so the client is guaranteed to receive it.
           • If isCreated and the Character is already up (Studio race),
             applies the template immediately.
      3. Client confirms by firing CharacterCreationComplete.
         SaveCharacterCreation persists + calls ApplyTemplate.
      4. CharacterAdded handler re-applies the template on every respawn.

    Template assets
    ---------------
    Gender templates live in ServerStorage/CharacterTemplates/<Name>.
    Each contains CharacterMesh instances (body shape), Humanoid +
    HumanoidDescription, and one or more Accessory items (hair).
    ApplyTemplate clones the CharacterMesh items onto the player's
    default R6 rig, copies Motor6D C0/C1 from the template torso, then
    welds the hair accessory via the carefully-tested pipeline below.

    (The cosmetic system handles weapons, armor, hats, and other
     accessories as welded equipment — see CosmeticManager and
     VisualEquipmentManager.)

    Memory & races
    --------------
    Per-player and per-character lifetimes use Janitor. The per-character
    Janitor is linked to the Character instance so every respawn
    self-cleans without magic timers or unbounded lists (§T1.1/D8/D9).

    The CharacterCreationRequired push is routed through ReadyGate so it
    survives the client-UI mount race that previously caused the
    character-creation panel to silently not appear (§T1.1/D7).
]]

local CharacterManager = {}

local Players       = game:GetService("Players")
local ServerStorage = game:GetService("ServerStorage")
local StarterPlayer = game:GetService("StarterPlayer")

local Modules           = script.Parent
local NetworkManager    = require(Modules:WaitForChild("NetworkManager"))
local PlayerDataManager = require(Modules:WaitForChild("PlayerDataManager"))
local CharacterConfig   = require(Modules:WaitForChild("CharacterConfig"))
local Janitor           = require(Modules:WaitForChild("Janitor"))
local ReadyGate         = require(Modules:WaitForChild("ReadyGate"))

-- Lazy-loaded to avoid circular requires; CosmeticManager itself requires
-- this module's siblings during its own Init.
local CosmeticManager = nil

local TEMPLATES_FOLDER_NAME = "CharacterTemplates"
-- Attribute used to identify CharacterMesh and Accessory items we cloned
-- from the template so we don't wipe them when other systems add their own.
local TEMPLATE_TAG = "_TemplateCharacterMesh"
-- Per-character attribute set once ApplyTemplate has run successfully on
-- that Character. Lets the CharacterAdded handler dedupe vs an explicit
-- "apply now" path that races it.
local APPLIED_ATTR = "_CharacterTemplateApplied"

-- ─────────────────────────────────────────────────────────────────────
-- LIFETIMES
-- ─────────────────────────────────────────────────────────────────────
-- Weak-keyed: entry GCs when the player or character object is collected.
local playerJanitors    = setmetatable({}, { __mode = "k" })  -- [Player]    = Janitor
local templateJanitors  = setmetatable({}, { __mode = "k" })  -- [Character] = Janitor
-- Idempotency latch for OnPlayerDataReady — see SetupPlayer.
local setupFired        = setmetatable({}, { __mode = "k" })

local function getPlayerJanitor(player)
    local jan = playerJanitors[player]
    if not jan then
        jan = Janitor.new()
        playerJanitors[player] = jan
    end
    return jan
end

local function getTemplatesFolder()
    return ServerStorage:FindFirstChild(TEMPLATES_FOLDER_NAME)
end

-- ═══════════════════════════════════════════════════════════
-- TEMPLATE APPLICATION
-- ═══════════════════════════════════════════════════════════

--- Clone all CharacterMesh instances from the template (body + head).
local function ApplyCharacterMeshes(character, template)
    -- Remove any previously-applied template CharacterMeshes
    for _, child in ipairs(character:GetChildren()) do
        if child:IsA("CharacterMesh") and child:GetAttribute(TEMPLATE_TAG) then
            child:Destroy()
        end
    end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid and humanoid.RigType == Enum.HumanoidRigType.R15 then
        warn("[CharacterManager] R15 rig detected — CharacterMesh has no effect.")
        return
    end

    for _, child in ipairs(template:GetChildren()) do
        if child:IsA("CharacterMesh") then
            local clone = child:Clone()
            clone:SetAttribute(TEMPLATE_TAG, true)
            clone.Parent = character
        end
    end
end

--- Force the correct head mesh + texture onto the player's Head Part.
--- CharacterMesh(BodyPart=Head) does NOT update character.Head.SpecialMesh
--- at runtime; we must set both MeshId AND TextureId explicitly. Also
--- strips the player's avatar face Decal (distorted on an Rthro head).
local function ApplyHeadAppearance(character, template, jan)
    local head = character:FindFirstChild("Head")
    if not head then return end

    -- Read head mesh + texture from the template's Head Part SpecialMesh
    local templateMeshId, templateTexture
    local templateHead = template:FindFirstChild("Head")
    if templateHead then
        local tm = templateHead:FindFirstChildOfClass("SpecialMesh")
        if tm then
            templateMeshId  = tm.MeshId
            templateTexture = tm.TextureId
        end
    end

    local function apply()
        if not head.Parent then return end
        local mesh = head:FindFirstChildOfClass("SpecialMesh")
        if mesh then
            if templateMeshId  and templateMeshId  ~= "" then mesh.MeshId   = templateMeshId  end
            if templateTexture and templateTexture ~= "" then mesh.TextureId = templateTexture end
        end
        -- Remove avatar face Decal (distorted on Rthro head mesh)
        for _, child in ipairs(head:GetChildren()) do
            if child:IsA("Decal") and child.Name == "face" then
                child:Destroy()
            end
        end
    end

    apply()
    -- Re-apply after Roblox's async ApplyDescription may have reset things.
    -- Two short re-applies catch the common cases; the watcher below catches
    -- the long tail without polling.
    task.delay(0.15, apply)
    task.delay(1,    apply)

    -- Watch for the engine reassigning MeshId (async avatar loader). Setting
    -- the same MeshId does not re-fire Changed, so this can't loop.
    local mesh = head:FindFirstChildOfClass("SpecialMesh")
    if mesh and templateMeshId and templateMeshId ~= "" then
        jan:Add(mesh:GetPropertyChangedSignal("MeshId"):Connect(apply))
    end

    -- Guard against the engine re-adding the face Decal.
    jan:Add(head.ChildAdded:Connect(function(child)
        if child:IsA("Decal") and child.Name == "face" then
            child:Destroy()
        end
    end))
end

--- Copy Motor6D C0/C1 joints from the template Torso to the character
--- Torso. Template files have the correct values baked in.
local function ApplyMotor6DFromTemplate(character, template)
    local charTorso  = character:FindFirstChild("Torso")
    local templTorso = template:FindFirstChild("Torso")
    if not charTorso or not templTorso then
        warn("[CharacterManager] ApplyMotor6D — missing Torso:", charTorso ~= nil, templTorso ~= nil)
        return
    end
    for _, templJoint in ipairs(templTorso:GetChildren()) do
        if templJoint:IsA("Motor6D") then
            local charJoint = charTorso:FindFirstChild(templJoint.Name)
            if charJoint then
                charJoint.C0 = templJoint.C0
                charJoint.C1 = templJoint.C1
            end
        end
    end
end

--[[
    ApplyTemplate(player)
    Applies the gender template's full appearance to the player's R6
    character. Safe to call any time; no-op if data or character is missing.

    Pipeline:
      1. Disable AutomaticScaling (otherwise it fights the Motor6D copy).
      2. Clone CharacterMesh instances (body + head shape).
      3. Copy Motor6D C0/C1 from the template torso (joint pivots).
      4. Re-apply mesh on a guard signal in case the avatar loader runs late.
      5. Force the head SpecialMesh + strip the face Decal.
      6. Clone the hair Accessory and weld it via the staff-pipeline-grade
         dance below (see §LD-CM2 — this is the same pattern that fixed the
         held-weapon weld bug; do not "simplify").
      7. Apply skin color through BodyColors.
]]
function CharacterManager.ApplyTemplate(player)
    local data = PlayerDataManager.GetData(player)
    if not data or not data.Account or not data.Account.CharacterData then return end

    local cd = data.Account.CharacterData
    if not cd.isCreated then return end

    local character = player.Character
    if not character then return end

    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end

    -- §CC-LEGACY: cd.bodyModel is the canonical body slot. Fall back to
    -- cd.preset for save-data that pre-dates the rename.
    local bodySlot = cd.bodyModel or cd.preset
    local templateName = CharacterConfig.GetTemplateName(bodySlot, cd.gender)

    local folder = getTemplatesFolder()
    if not folder then
        warn(("[CharacterManager] CharacterTemplates folder not found — using default avatar for %s"):format(player.Name))
        return
    end
    local template = folder:FindFirstChild(templateName)
    if not template then
        warn(("[CharacterManager] Template '%s' not found — using default avatar for %s"):format(templateName, player.Name))
        return
    end

    -- Fresh per-character Janitor. LinkToInstance cleans it up when the
    -- character is destroyed (respawn / leave). Calling ApplyTemplate
    -- again on the same Character first destroys the previous Janitor.
    local existing = templateJanitors[character]
    if existing then existing:Destroy() end
    local jan = Janitor.new()
    jan:LinkToInstance(character)
    templateJanitors[character] = jan

    -- ── 0) Disable AutomaticScaling BEFORE the Motor6D copy ───────────
    humanoid.AutomaticScalingEnabled = false

    -- ── 1) CharacterMesh items (body + head shape) ────────────────────
    -- We do NOT call Humanoid:ApplyDescription — it resets Motor6D pivots
    -- and would undo step 2.
    ApplyCharacterMeshes(character, template)

    -- ── 2) Motor6D C0/C1 from the template ────────────────────────────
    task.wait()
    ApplyMotor6DFromTemplate(character, template)

    -- ── 3) Guard against the avatar loader re-enabling AutomaticScaling
    --        and resetting our joints during the spawn-in animation.
    jan:Add(humanoid:GetPropertyChangedSignal("AutomaticScalingEnabled"):Connect(function()
        if humanoid.AutomaticScalingEnabled and character.Parent then
            humanoid.AutomaticScalingEnabled = false
            task.spawn(function()
                task.wait()
                if character.Parent then
                    ApplyMotor6DFromTemplate(character, template)
                end
            end)
        end
    end))

    -- ── 4) Head mesh + texture + Decal-strip ──────────────────────────
    ApplyHeadAppearance(character, template, jan)

    -- Remove Roblox's ShirtGraphic Decal from the Torso.
    local torso = character:FindFirstChild("Torso")
    if torso then
        for _, child in ipairs(torso:GetChildren()) do
            if child:IsA("Decal") then child:Destroy() end
        end
    end

    -- ── 5) Hair accessory ─────────────────────────────────────────────
    -- §LD-CM2 / "the staff fix": this dance is intentionally elaborate.
    -- Roblox's avatar loader re-injects accessories and toggles
    -- AutomaticScaling DURING the task.wait() inside the loop below; the
    -- watcher must be installed BEFORE we start cloning so it catches the
    -- injected items, and we have to re-apply Motor6D on every wait.
    -- This pattern is what made hair AND weapons reliable — do not
    -- "simplify". When porting to other accessories (cosmetics), reuse
    -- exactly this shape (see TODO: standardize accessory weld pipeline).
    jan:Add(character.ChildAdded:Connect(function(child)
        if child:IsA("Accessory") and not child:GetAttribute(TEMPLATE_TAG) then
            child:Destroy()
        end
    end))

    -- Hard wipe of any pre-existing non-tagged accessories. Tagged ones
    -- (weapons, cosmetic items applied by other systems) survive.
    for _, child in ipairs(character:GetChildren()) do
        if child:IsA("Accessory") and not child:GetAttribute(TEMPLATE_TAG) then
            child:Destroy()
        end
    end

    for _, child in ipairs(template:GetChildren()) do
        if child:IsA("Accessory") then
            -- Read weld values from the template's existing AccessoryWeld
            -- BEFORE cloning. Roblox injects this weld at runtime into the
            -- template model with the correct C0/C1 (tune by editing
            -- HairAttachment.CFrame in Studio). Fallback to the attachment
            -- CFrame if no weld exists yet.
            local templateHandle = child:FindFirstChild("Handle")
            local templateWeld   = templateHandle and templateHandle:FindFirstChild("AccessoryWeld")
            local templateAtt    = templateHandle and templateHandle:FindFirstChildOfClass("Attachment")
            local c0 = (templateWeld and templateWeld.C0)
                     or (templateAtt and templateAtt.CFrame)
                     or CFrame.identity
            local c1 = (templateWeld and templateWeld.C1) or CFrame.identity

            local clone = child:Clone()
            clone:SetAttribute(TEMPLATE_TAG, true)

            -- Destroy pre-existing AccessoryWelds on the clone so Roblox
            -- creates exactly one when we parent it to the character.
            local cloneHandle = clone:FindFirstChild("Handle")
            if cloneHandle then
                for _, w in ipairs(cloneHandle:GetChildren()) do
                    if w.Name == "AccessoryWeld" then w:Destroy() end
                end
            end

            clone.Parent = character

            -- Wait one frame for Roblox to auto-create its single
            -- AccessoryWeld. Roblox may also re-enable AutomaticScaling
            -- during this yield — re-apply Motor6D immediately after.
            task.wait()
            humanoid.AutomaticScalingEnabled = false
            ApplyMotor6DFromTemplate(character, template)

            if cloneHandle then
                local weld = cloneHandle:FindFirstChild("AccessoryWeld")
                if weld then
                    weld.Part0 = cloneHandle
                    weld.Part1 = character:FindFirstChild("Head")
                    weld.C0   = c0
                    weld.C1   = c1
                end
            end
        end
    end

    -- ── 6) Skin color via BodyColors ──────────────────────────────────
    CharacterManager.ApplySkinColor(player)

    -- Mark the character as fully templated. The CharacterAdded handler
    -- below uses this to avoid double-applying when SetupPlayer races it.
    character:SetAttribute(APPLIED_ATTR, true)
end

-- ═══════════════════════════════════════════════════════════
-- SKIN COLOR
-- ═══════════════════════════════════════════════════════════

--[[
    ApplySkinColor(player)
    Reads the saved skinColor id from CharacterData and sets all six
    BodyColors slots on the player's character uniformly.
]]
function CharacterManager.ApplySkinColor(player)
    local character = player.Character
    if not character then return end

    local cd = CharacterManager.GetCharacterData(player)
    if not cd then return end

    local skinEntry = CharacterConfig.GetSkinColor(cd.skinColor)
    if not skinEntry then
        -- Fallback: first skin color in the palette
        skinEntry = CharacterConfig.SkinColors[1]
    end
    if not skinEntry then return end

    local bodyColors = character:FindFirstChildOfClass("BodyColors")
    if not bodyColors then
        bodyColors = Instance.new("BodyColors")
        bodyColors.Parent = character
    end

    local c = skinEntry.color
    bodyColors.HeadColor3     = c
    bodyColors.TorsoColor3    = c
    bodyColors.LeftArmColor3  = c
    bodyColors.RightArmColor3 = c
    bodyColors.LeftLegColor3  = c
    bodyColors.RightLegColor3 = c
end

-- ═══════════════════════════════════════════════════════════
-- GENDERED CLASS TITLE
-- ═══════════════════════════════════════════════════════════

function CharacterManager.GetClassTitle(player, className)
    local data   = PlayerDataManager.GetData(player)
    local gender = data and data.Account and data.Account.CharacterData and data.Account.CharacterData.gender
    return CharacterConfig.GetClassTitle(className, gender)
end

-- ═══════════════════════════════════════════════════════════
-- CHARACTER CREATION SAVE
-- ═══════════════════════════════════════════════════════════

-- §AGX/X18 (Pablo): once a character exists, changing its appearance is
-- behind a flag — `CharacterData.appearanceChangeUnlocked`, set by
-- CharacterManager.GrantAppearanceChange (call it from an item's use
-- handler or a store grant). One grant = one re-customization.
local lastCreationSubmit = {}  -- [player] = os.clock() of last accepted submit
local CREATION_SUBMIT_COOLDOWN = 1

local function SaveCharacterCreation(player, payload)
    local data = PlayerDataManager.GetData(player)
    if not data then
        warn("[CharacterManager] No data for", player.Name)
        return
    end

    local now = os.clock()
    if lastCreationSubmit[player] and now - lastCreationSubmit[player] < CREATION_SUBMIT_COOLDOWN then
        return
    end

    local existing = data.Account.CharacterData
    local isRecustomize = existing ~= nil and existing.isCreated == true
    if isRecustomize and not existing.appearanceChangeUnlocked then
        warn("[CharacterManager] Rejected appearance change (not unlocked) from", player.Name)
        return
    end

    local gender    = payload.gender
    local skinColor = payload.skinColor
    -- The client may submit `bodyModel` (new) or `preset` (legacy UI).
    -- Either way we persist to `bodyModel`. `preset` is preserved for
    -- back-compat reads until we drop it from the schema in v0.7.
    local bodyModel = payload.bodyModel or payload.preset

    if not CharacterConfig.IsValidGender(gender) then
        warn("[CharacterManager] Invalid gender from", player.Name, ":", tostring(gender))
        return
    end
    if not CharacterConfig.IsValidBodyModel(bodyModel) then
        bodyModel = 1   -- forward-compat: default to first body slot
    end
    if not CharacterConfig.IsValidSkinColor(skinColor) then
        skinColor = CharacterConfig.SkinColors[1].id
    end

    local cd = data.Account.CharacterData
    cd.gender    = gender
    cd.bodyModel = bodyModel
    cd.preset    = bodyModel   -- §CC-LEGACY mirror; drop in v0.7
    cd.skinColor = skinColor
    cd.isCreated = true
    if isRecustomize then
        cd.appearanceChangeUnlocked = nil  -- §AGX/X18: grant consumed
    end
    lastCreationSubmit[player] = now
    CharacterManager.RefreshAppearanceAttribute(player)  -- §AGX/X18b: menu count

    -- §T1.4/Y12: character-created info print removed.
    -- Response to client→server submit; client already has a listener for
    -- this event, so a plain FireClient is fine (no ReadyGate needed).
    NetworkManager.FireClient(player, "CharacterCreationSaved", {
        gender    = gender,
        preset    = bodyModel,
        bodyModel = bodyModel,
        skinColor = skinColor,
    })

    -- Apply immediately if the character already exists
    CharacterManager.ApplyTemplate(player)

    if CosmeticManager then
        CosmeticManager.ApplyPlayerVisuals(player)
    end
end

-- ═══════════════════════════════════════════════════════════
-- PER-PLAYER LIFECYCLE
-- ═══════════════════════════════════════════════════════════

local function sendCreationRequired(player)
    ReadyGate.FireClient(player, "CharacterCreationRequired", {
        genders    = CharacterConfig.Genders,
        skinColors = CharacterConfig.SkinColors,
    })
end

--- Called once per player session via OnPlayerDataReady.
--- Handles the first-login fork and arms the per-respawn re-apply.
local function SetupPlayer(player)
    if setupFired[player] then return end
    setupFired[player] = true

    local jan = getPlayerJanitor(player)

    -- Re-apply on every respawn. The APPLIED_ATTR dedupe prevents a
    -- second call when SetupPlayer's own "apply now" branch (below)
    -- already ran for the same Character.
    jan:Add(player.CharacterAdded:Connect(function(character)
        task.wait(0.5)  -- wait for body parts + Humanoid
        if character:GetAttribute(APPLIED_ATTR) then return end
        CharacterManager.ApplyTemplate(player)
    end), "characterAdded")

    local data = PlayerDataManager.GetData(player)
    if not data then return end

    -- §AGX/X18b: expose the usable appearance-change count on load.
    CharacterManager.RefreshAppearanceAttribute(player)

    local cd = data.Account.CharacterData
    if not cd or not cd.isCreated then
        sendCreationRequired(player)
        return
    end

    -- Existing character — apply now. CharacterAdded won't fire for the
    -- initial spawn if our listener registered after it did, so we cover
    -- that race here explicitly.
    if player.Character and not player.Character:GetAttribute(APPLIED_ATTR) then
        CharacterManager.ApplyTemplate(player)
    end
end

local function CleanupPlayer(player)
    setupFired[player] = nil
    local jan = playerJanitors[player]
    if jan then
        jan:Destroy()
        playerJanitors[player] = nil
    end
end

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function CharacterManager.Init()
    -- Force R6 for all players so CharacterMesh works. CharacterMesh is a
    -- no-op on R15. Note: StarterPlayer.CharacterRigType is not always
    -- scriptable at runtime; configure it via Game Settings → Avatar in
    -- Studio if this warn fires.
    local ok, rigType = pcall(function() return StarterPlayer.CharacterRigType end)
    if ok and rigType ~= Enum.HumanoidRigType.R6 then
        local setOk = pcall(function()
            StarterPlayer.CharacterRigType = Enum.HumanoidRigType.R6
        end)
        if setOk then
            print("[CharacterManager] Forced StarterPlayer.CharacterRigType = R6")
        else
            warn("[CharacterManager] Cannot set CharacterRigType at runtime — please set Avatar type to R6 in Game Settings.")
        end
    elseif not ok then
        warn("[CharacterManager] CharacterRigType not accessible — please ensure Avatar type is R6 in Game Settings.")
    end

    -- Pre-register network events so the client's WaitForChild doesn't race.
    NetworkManager.GetEvent("CharacterCreationRequired")
    NetworkManager.GetEvent("CharacterCreationSaved")
    NetworkManager.GetEvent("CharacterCreationComplete")
    NetworkManager.GetEvent("RequestCharacterStatus")
    NetworkManager.GetEvent("UseAppearanceChange")  -- §AGX/X18b

    -- §AGX/X18: forget the submit cooldown on leave.
    Players.PlayerRemoving:Connect(function(player)
        lastCreationSubmit[player] = nil
    end)

    -- §AGX/X18b: menu "Change appearance" → spend one free token (or
    -- reopen a change that is already unlocked but was never submitted).
    NetworkManager.OnClientEvent("UseAppearanceChange", function(player)
        CharacterManager.UseAppearanceChange(player)
    end)

    -- Client submits its creation form.
    NetworkManager.OnClientEvent("CharacterCreationComplete", function(player, payload)
        if type(payload) ~= "table" then return end
        SaveCharacterCreation(player, payload)
    end)

    -- Client asks "do I need to do creation?" (mount-time check). Same
    -- code path that SetupPlayer takes, but reactive to a client request.
    NetworkManager.OnClientEvent("RequestCharacterStatus", function(player)
        local data = PlayerDataManager.GetData(player)
        if not data then return end
        if not data.Account.CharacterData or not data.Account.CharacterData.isCreated then
            sendCreationRequired(player)
        end
    end)

    -- Lazy-load CosmeticManager (sibling module — avoid require cycle).
    task.spawn(function()
        local cmMod = Modules:FindFirstChild("CosmeticManager")
        if cmMod then
            local okReq, mod = pcall(require, cmMod)
            if okReq then CosmeticManager = mod end
        end
    end)

    -- Per-player lifecycle. OnPlayerDataReady is the single entry point —
    -- it fires once per player after PlayerData has loaded. Studio-race
    -- cover: sweep any player whose data is already loaded (joined before
    -- this listener registered).
    if PlayerDataManager.OnPlayerDataReady then
        PlayerDataManager.OnPlayerDataReady(SetupPlayer)
        for _, player in ipairs(Players:GetPlayers()) do
            if PlayerDataManager.GetData(player) then
                task.spawn(SetupPlayer, player)
            end
        end
    else
        warn("[CharacterManager] PlayerDataManager.OnPlayerDataReady missing — character creation will not fire.")
    end

    Players.PlayerRemoving:Connect(CleanupPlayer)
end

-- ═══════════════════════════════════════════════════════════
-- PUBLIC GETTERS
-- ═══════════════════════════════════════════════════════════

function CharacterManager.GetCharacterData(player)
    local data = PlayerDataManager.GetData(player)
    return data and data.Account and data.Account.CharacterData
end

function CharacterManager.IsCreated(player)
    local cd = CharacterManager.GetCharacterData(player)
    return cd ~= nil and cd.isCreated == true
end

function CharacterManager.GetGender(player)
    local cd = CharacterManager.GetCharacterData(player)
    return cd and cd.gender
end

--- §CC-LEGACY: returns the body slot (was `preset` in v0.5).
function CharacterManager.GetBodyModel(player)
    local cd = CharacterManager.GetCharacterData(player)
    return cd and (cd.bodyModel or cd.preset)
end
CharacterManager.GetPreset = CharacterManager.GetBodyModel  -- legacy alias

function CharacterManager.GetHeadModel(player)
    local cd = CharacterManager.GetCharacterData(player)
    return cd and cd.headModel
end

function CharacterManager.GetHairModel(player)
    local cd = CharacterManager.GetCharacterData(player)
    return cd and cd.hairModel
end

function CharacterManager.GetSkinColorId(player)
    local cd = CharacterManager.GetCharacterData(player)
    return cd and cd.skinColor
end

function CharacterManager.GetHairColorId(player)
    local cd = CharacterManager.GetCharacterData(player)
    return cd and cd.hairColor
end

function CharacterManager.GetClothingColorId(player)
    local cd = CharacterManager.GetCharacterData(player)
    return cd and cd.clothingColor
end


-- ═══════════════════════════════════════════════════════════
-- APPEARANCE CHANGE GRANT  (§AGX/X18)
-- ═══════════════════════════════════════════════════════════

--- Unlock ONE appearance change for a player who already created their
--- character, and open the creation screen for them. Intended callers:
--- a consumable's use handler, or a store/premium grant. `source` is a
--- free-form tag for logs (e.g. "item:appearance_token", "store").
--- Returns true if granted.
function CharacterManager.GrantAppearanceChange(player, source)
    local data = PlayerDataManager.GetData(player)
    local cd = data and data.Account and data.Account.CharacterData
    if not cd or not cd.isCreated then
        return false  -- first-time creation is always free; nothing to unlock
    end
    cd.appearanceChangeUnlocked = true
    print("[CharacterManager] Appearance change granted to", player.Name, "via", tostring(source))
    CharacterManager.RefreshAppearanceAttribute(player)  -- §AGX/X18b
    sendCreationRequired(player)
    return true
end

function CharacterManager.HasAppearanceChange(player)
    local data = PlayerDataManager.GetData(player)
    local cd = data and data.Account and data.Account.CharacterData
    return cd ~= nil and cd.appearanceChangeUnlocked == true
end

-- ═══════════════════════════════════════════════════════════
-- FREE APPEARANCE CHANGE TOKENS  (§AGX/X18b)
-- ═══════════════════════════════════════════════════════════
-- §AGX/X18b (Pablo): the first re-customization is earned, not bought —
-- the "Veteran" achievement (account level 50) stores ONE free token in
-- `CharacterData.freeAppearanceTokens` (number; missing = 0). It does NOT
-- open the creation screen: the player spends it from the menu
-- ("Change appearance" → UseAppearanceChange). Later changes are paid
-- (MonetizationService, banked in Account.Monetization.appearanceTokens).

local APPEARANCE_ATTR = "AppearanceChangesAvailable"

local function toast(player, kind, text)
    local mod = Modules:FindFirstChild("NotifyService")
    if not mod then return end
    local ok, NotifyService = pcall(require, mod)
    if ok and type(NotifyService) == "table" and NotifyService.Toast then
        NotifyService.Toast(player, kind, text)
    end
end

--- Free (achievement) tokens not yet spent. Missing/garbage field = 0.
function CharacterManager.GetFreeAppearanceTokens(player)
    local cd = CharacterManager.GetCharacterData(player)
    local n = cd and cd.freeAppearanceTokens
    if type(n) ~= "number" or n ~= n or n < 0 then return 0 end
    return math.floor(n)
end

--- Store `amount` free tokens (default 1). Never opens the creation screen.
--- Returns true when stored. `source` is a free-form log tag.
function CharacterManager.AddFreeAppearanceToken(player, amount, source)
    local data = PlayerDataManager.GetData(player)
    if not data or type(data.Account) ~= "table" then return false end
    local cd = data.Account.CharacterData
    if type(cd) ~= "table" then
        cd = { isCreated = false }
        data.Account.CharacterData = cd
    end
    amount = math.max(1, math.floor(tonumber(amount) or 1))
    cd.freeAppearanceTokens = CharacterManager.GetFreeAppearanceTokens(player) + amount
    print("[CharacterManager] Free appearance change stored for", player.Name, "via", tostring(source))
    CharacterManager.RefreshAppearanceAttribute(player)
    return true
end

--- Player attribute AppearanceChangesAvailable = free tokens + paid banked
--- tokens + 1 while a granted change is still unused (e.g. the player left
--- mid-screen). The client menu reads it for the badge and the lock.
function CharacterManager.RefreshAppearanceAttribute(player)
    if not player or not player.Parent then return end
    local data = PlayerDataManager.GetData(player)
    if not data or type(data.Account) ~= "table" then return end
    local count = CharacterManager.GetFreeAppearanceTokens(player)
    local mon = data.Account.Monetization
    if type(mon) == "table" and type(mon.appearanceTokens) == "number" and mon.appearanceTokens > 0 then
        count += math.floor(mon.appearanceTokens)
    end
    local cd = data.Account.CharacterData
    if type(cd) == "table" and cd.isCreated and cd.appearanceChangeUnlocked then
        count += 1
    end
    player:SetAttribute(APPEARANCE_ATTR, count)
end

--- Client → server "UseAppearanceChange". Order:
---   1. a change already unlocked (paid, or free spent earlier) but never
---      submitted → just reopen the screen, spend nothing;
---   2. a free token → decrement, then GrantAppearanceChange (opens the
---      screen; the §AGX/X18 submit consumes the unlock);
---   3. otherwise refuse with a toast.
--- Returns true when the creation screen was (re)opened.
function CharacterManager.UseAppearanceChange(player)
    local data = PlayerDataManager.GetData(player)
    local cd = data and data.Account and data.Account.CharacterData
    if type(cd) ~= "table" or not cd.isCreated then
        toast(player, "warning", "Create your character first.")
        return false
    end
    if cd.appearanceChangeUnlocked then
        sendCreationRequired(player)
        return true
    end
    local free = CharacterManager.GetFreeAppearanceTokens(player)
    if free <= 0 then
        toast(player, "warning", "No appearance changes left.")
        CharacterManager.RefreshAppearanceAttribute(player)
        return false
    end
    -- Decrement first: token and flag change together in memory and are
    -- saved together by the next save (same pattern as applyBankedAppearance).
    cd.freeAppearanceTokens = free - 1
    local ok, granted = pcall(CharacterManager.GrantAppearanceChange, player, "achievement:veteran")
    if not ok or not granted then
        cd.freeAppearanceTokens = free
        CharacterManager.RefreshAppearanceAttribute(player)
        warn("[CharacterManager] UseAppearanceChange failed for", player.Name, ok and "" or granted)
        return false
    end
    return true
end

return CharacterManager
