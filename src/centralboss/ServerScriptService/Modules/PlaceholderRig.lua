-- centralboss/ServerScriptService/Modules/PlaceholderRig.lua
--[[
    §AGX/X28: runtime placeholder mob rig (mob .rbxmx templates are not in
    git — AUDIT_FINDINGS G1 — so there is no model file to clone).

    Builds a Part-based "block golem" that satisfies what MobAI.RegisterMob
    and the combat code need from a mob model:
        • Model with a Humanoid and a "HumanoidRootPart" (PrimaryPart)
        • root is the only collider; every other part is welded to it with
          a WeldConstraint, CanCollide = false, Massless = true
        • Humanoid.RigType = R15 so HipHeight + root height set the stand
          height (no Motor6D / Neck needed: RequiresNeck = false)
    The root box spans nearly the whole body, so players can't walk under
    a large rig and melee range checks (root position) stay honest.

    Deliberately ugly and obviously temporary: flat colours, neon eyes and
    a "(placeholder)" name tag. Replace by adding a real template model
    (see Mobs/IronWarden.lua header).

    PlaceholderRig.Build(opts) -> Model
        opts.name        string   model name
        opts.scale       number   1 ≈ a 5-stud humanoid (default 1)
        opts.bodyColor   Color3
        opts.accentColor Color3   eyes + name tag
        opts.label       string   BillboardGui text (nil = no tag)
    The model's pivot is the root; GetStandOffset(model) gives the height
    of the pivot above the floor.
]]

local PlaceholderRig = {}

local DEFAULT_BODY   = Color3.fromRGB(120, 120, 120)
local DEFAULT_ACCENT = Color3.fromRGB(255, 200, 60)

local function makePart(name, size, color, parent)
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = Enum.Material.SmoothPlastic
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Anchored = false
	p.CanCollide = false
	p.Massless = true
	p.CastShadow = true
	p.Parent = parent
	return p
end

-- Place `part` at `offset` from the root (root sits at the origin while
-- building) and weld it.
local function attach(root, part, offset)
	part.CFrame = root.CFrame * CFrame.new(offset)
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = part
	weld.Parent = part
end

function PlaceholderRig.Build(opts)
	opts = opts or {}
	local s      = math.max(0.5, opts.scale or 1)
	local body   = opts.bodyColor or DEFAULT_BODY
	local accent = opts.accentColor or DEFAULT_ACCENT

	local model = Instance.new("Model")
	model.Name = opts.name or "PlaceholderMob"

	-- Layout in "units" of s, floor at y = 0:
	--   legs 0..2 · torso 2..4 · head 4..5.2 · root box 0.2..4.0
	local hipHeight = 0.2 * s
	local rootSize  = Vector3.new(2 * s, 3.8 * s, 1.4 * s)
	local rootY     = hipHeight + rootSize.Y / 2          -- pivot height above floor

	local root = makePart("HumanoidRootPart", rootSize, body, model)
	root.Transparency = 1
	root.CanCollide = true
	root.Massless = false
	root.CFrame = CFrame.new(0, rootY, 0)
	model.PrimaryPart = root

	local function y(worldY) return worldY - rootY end

	local torso = makePart("Torso", Vector3.new(2 * s, 2 * s, 1.2 * s), body, model)
	torso.Material = Enum.Material.DiamondPlate
	attach(root, torso, Vector3.new(0, y(3 * s), 0))

	local head = makePart("Head", Vector3.new(1.2 * s, 1.2 * s, 1.2 * s), body, model)
	attach(root, head, Vector3.new(0, y(4.6 * s), 0))

	for _, side in ipairs({ -1, 1 }) do
		local leg = makePart(side < 0 and "LeftLeg" or "RightLeg",
			Vector3.new(0.9 * s, 2 * s, 0.9 * s), body:Lerp(Color3.new(0, 0, 0), 0.25), model)
		attach(root, leg, Vector3.new(0.5 * s * side, y(1 * s), 0))

		local arm = makePart(side < 0 and "LeftArm" or "RightArm",
			Vector3.new(0.9 * s, 2.2 * s, 0.9 * s), body:Lerp(Color3.new(0, 0, 0), 0.15), model)
		attach(root, arm, Vector3.new(1.45 * s * side, y(2.9 * s), 0))

		-- Eyes on the -Z face (Roblox "front").
		local eye = makePart(side < 0 and "LeftEye" or "RightEye",
			Vector3.new(0.25 * s, 0.2 * s, 0.1 * s), accent, model)
		eye.Material = Enum.Material.Neon
		eye.CastShadow = false
		attach(root, eye, Vector3.new(0.28 * s * side, y(4.75 * s), -0.62 * s))
	end

	local humanoid = Instance.new("Humanoid")
	humanoid.RigType = Enum.HumanoidRigType.R15
	humanoid.HipHeight = hipHeight
	humanoid.RequiresNeck = false
	humanoid.BreakJointsOnDeath = false
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
	humanoid.UseJumpPower = true
	humanoid.JumpPower = 0
	humanoid.Parent = model
	Instance.new("Animator").Parent = humanoid

	if opts.label then
		local gui = Instance.new("BillboardGui")
		gui.Name = "PlaceholderTag"
		gui.Adornee = head
		gui.Size = UDim2.fromOffset(240, 56)
		gui.StudsOffset = Vector3.new(0, 1.2 * s, 0)
		gui.AlwaysOnTop = true
		gui.MaxDistance = 250
		gui.Parent = head

		local text = Instance.new("TextLabel")
		text.Size = UDim2.fromScale(1, 1)
		text.BackgroundTransparency = 1
		text.Text = opts.label
		text.TextColor3 = accent
		text.TextStrokeTransparency = 0.2
		text.Font = Enum.Font.GothamBlack
		text.TextScaled = true
		text.Parent = gui
	end

	return model
end

--- Height of the model's pivot above the floor it stands on, for any
--- Humanoid rig (placeholder or real R15 template).
function PlaceholderRig.GetStandOffset(model)
	local humanoid = model:FindFirstChildOfClass("Humanoid")
	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	if humanoid and root then
		return humanoid.HipHeight + root.Size.Y / 2
	end
	return 3
end

return PlaceholderRig
