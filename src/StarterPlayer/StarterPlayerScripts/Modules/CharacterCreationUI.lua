-- StarterPlayerScripts/Modules/CharacterCreationUI
--[[
    CharacterCreationUI
    ====================
    Client-side character creation screen shown to new players once
    at first login.  The server fires "CharacterCreationRequired" to
    trigger it; this module builds a ScreenGui, waits for the player
    to pick a gender and body preset, then fires
    "CharacterCreationComplete" back to the server.

    Layout:
        ┌──────────────────────────────────┐
        │        Choose your character     │
        │                                  │
        │  [♂ Male]        [♀ Female]       │
        │                                  │
        │  [Athletic]  [Balanced]  [Brawny] │
        │                                  │
        │            [Confirm]             │
        └──────────────────────────────────┘
]]

local CharacterCreationUI = {}

local Players       = game:GetService("Players")
local TweenService  = game:GetService("TweenService")

local Modules = script.Parent
local NetworkManager = require(Modules:WaitForChild("NetworkManager"))

local LocalPlayer  = Players.LocalPlayer
local PlayerGui    = LocalPlayer:WaitForChild("PlayerGui")

-- ═══════════════════════════════════════════════════════════
-- STATE
-- ═══════════════════════════════════════════════════════════

local selectedGender = nil   -- "Male" or "Female"
local selectedPreset = nil   -- 1, 2, or 3

-- ═══════════════════════════════════════════════════════════
-- COLOURS
-- ═══════════════════════════════════════════════════════════

local COLOUR = {
	Background   = Color3.fromRGB(20,  20,  30 ),
	Panel        = Color3.fromRGB(30,  30,  45 ),
	Accent       = Color3.fromRGB(80, 140, 220 ),
	AccentDark   = Color3.fromRGB(50,  90, 160 ),
	Selected     = Color3.fromRGB(60, 200, 120 ),
	SelectedDark = Color3.fromRGB(40, 140,  85 ),
	Text         = Color3.fromRGB(230, 230, 240),
	SubText      = Color3.fromRGB(160, 160, 180),
	Disabled     = Color3.fromRGB(60,  60,  75 ),
	Confirm      = Color3.fromRGB(80, 200, 120 ),
	ConfirmDark  = Color3.fromRGB(50, 140,  85 ),
}

-- ═══════════════════════════════════════════════════════════
-- UI HELPERS
-- ═══════════════════════════════════════════════════════════

local function MakeFrame(parent, name, size, position, colour, zIndex)
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = size
	f.Position = position
	f.BackgroundColor3 = colour
	f.BorderSizePixel = 0
	f.ZIndex = zIndex or 1
	f.Parent = parent
	return f
end

local function MakeCorner(parent, radius)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, radius or 8)
	c.Parent = parent
	return c
end

local function MakeLabel(parent, text, size, position, colour, fontSize, zIndex)
	local l = Instance.new("TextLabel")
	l.Name = "Label"
	l.Size = size
	l.Position = position
	l.BackgroundTransparency = 1
	l.Text = text
	l.TextColor3 = colour or COLOUR.Text
	l.TextScaled = true
	l.Font = Enum.Font.GothamBold
	l.ZIndex = zIndex or 2
	l.Parent = parent
	return l
end

local function MakeButton(parent, text, size, position, bgColour, zIndex)
	local b = Instance.new("TextButton")
	b.Name = text
	b.Size = size
	b.Position = position
	b.BackgroundColor3 = bgColour
	b.BorderSizePixel = 0
	b.Text = text
	b.TextColor3 = COLOUR.Text
	b.TextScaled = true
	b.Font = Enum.Font.GothamBold
	b.ZIndex = zIndex or 2
	b.AutoButtonColor = false
	b.Parent = parent
	MakeCorner(b, 8)
	return b
end

-- ═══════════════════════════════════════════════════════════
-- SELECTION HIGHLIGHT
-- ═══════════════════════════════════════════════════════════

local genderButtons = {}
local presetButtons = {}

local function SetSelected(btn, selected)
	TweenService:Create(btn, TweenInfo.new(0.15), {
		BackgroundColor3 = selected and COLOUR.Selected or COLOUR.Panel,
	}):Play()
end

local function SelectGender(gender, presetsPayload)
	selectedGender = gender
	for g, btn in pairs(genderButtons) do
		SetSelected(btn, g == gender)
	end
end

local function SelectPreset(preset)
	selectedPreset = preset
	for p, btn in pairs(presetButtons) do
		SetSelected(btn, p == preset)
	end
end

-- ═══════════════════════════════════════════════════════════
-- BUILD GUI
-- ═══════════════════════════════════════════════════════════

local function BuildGui(payload)
	-- Clean up any previous instance
	local existing = PlayerGui:FindFirstChild("CharacterCreation")
	if existing then existing:Destroy() end

	-- Root ScreenGui
	local sg = Instance.new("ScreenGui")
	sg.Name = "CharacterCreation"
	sg.ResetOnSpawn = false
	sg.IgnoreGuiInset = true
	sg.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	sg.Parent = PlayerGui

	-- Darkened background
	local overlay = MakeFrame(sg, "Overlay",
		UDim2.fromScale(1, 1), UDim2.fromScale(0, 0),
		Color3.new(0, 0, 0), 1)
	overlay.BackgroundTransparency = 0.35

	-- Main panel
	local panel = MakeFrame(sg, "Panel",
		UDim2.new(0, 480, 0, 360), UDim2.new(0.5, -240, 0.5, -180),
		COLOUR.Background, 2)
	MakeCorner(panel, 16)

	-- Title
	MakeLabel(panel, "Choose Your Character",
		UDim2.new(1, -40, 0, 40), UDim2.new(0, 20, 0, 16),
		COLOUR.Text, nil, 3)

	-- ── Gender section ─────────────────────────────────────
	MakeLabel(panel, "Gender",
		UDim2.new(1, -40, 0, 24), UDim2.new(0, 20, 0, 68),
		COLOUR.SubText, nil, 3)

	local genders   = payload.genders or { "Male", "Female" }
	local gBtnWidth = (480 - 40 - (#genders - 1) * 10) / #genders
	genderButtons   = {}

	for i, g in ipairs(genders) do
		local xOff = 20 + (i - 1) * (gBtnWidth + 10)
		local btn  = MakeButton(panel, g,
			UDim2.new(0, gBtnWidth, 0, 44),
			UDim2.new(0, xOff, 0, 96),
			COLOUR.Panel, 3)
		genderButtons[g] = btn

		btn.MouseButton1Click:Connect(function()
			SelectGender(g, payload)
		end)
	end

	-- ── Preset section ─────────────────────────────────────
	MakeLabel(panel, "Body Type",
		UDim2.new(1, -40, 0, 24), UDim2.new(0, 20, 0, 160),
		COLOUR.SubText, nil, 3)

	local presets  = payload.presets or {
		[1] = { id = 1, name = "Athletic", description = "Lean and agile." },
		[2] = { id = 2, name = "Balanced", description = "Reliable all-rounder." },
		[3] = { id = 3, name = "Brawny",   description = "Built to endure." },
	}
	presetButtons  = {}

	local pCount   = 0
	for _ in pairs(presets) do pCount = pCount + 1 end
	local pBtnW    = (480 - 40 - (pCount - 1) * 10) / pCount

	local idx = 0
	for i = 1, pCount do
		local p = presets[i]
		if p then
			local xOff = 20 + idx * (pBtnW + 10)

			local container = MakeFrame(panel, "Preset" .. i,
				UDim2.new(0, pBtnW, 0, 80),
				UDim2.new(0, xOff, 0, 190),
				COLOUR.Panel, 3)
			MakeCorner(container, 8)

			-- Preset name
			MakeLabel(container, p.name,
				UDim2.new(1, -8, 0, 28), UDim2.new(0, 4, 0, 6),
				COLOUR.Text, nil, 4)

			-- Preset description
			MakeLabel(container, p.description,
				UDim2.new(1, -8, 0, 32), UDim2.new(0, 4, 0, 38),
				COLOUR.SubText, nil, 4)

			presetButtons[i] = container

			container.InputBegan:Connect(function(input)
				if input.UserInputType == Enum.UserInputType.MouseButton1
					or input.UserInputType == Enum.UserInputType.Touch then
					SelectPreset(i)
				end
			end)

			idx = idx + 1
		end
	end

	-- ── Confirm button ─────────────────────────────────────
	local confirmBtn = MakeButton(panel, "Confirm",
		UDim2.new(0, 200, 0, 44),
		UDim2.new(0.5, -100, 1, -60),
		COLOUR.Confirm, 3)
	confirmBtn.ZIndex = 3

	confirmBtn.MouseButton1Click:Connect(function()
		if not selectedGender then
			-- Flash gender section to hint player
			MakeLabel(panel, "Please choose a gender!", 
				UDim2.new(1, -40, 0, 20), UDim2.new(0, 20, 0, 144),
				Color3.fromRGB(255, 100, 100), nil, 5)
			return
		end
		if not selectedPreset then
			MakeLabel(panel, "Please choose a body type!", 
				UDim2.new(1, -40, 0, 20), UDim2.new(0, 20, 0, 278),
				Color3.fromRGB(255, 100, 100), nil, 5)
			return
		end

		-- Submit to server
		NetworkManager.FireServer("CharacterCreationComplete", {
			gender = selectedGender,
			preset = selectedPreset,
		})

		print("[CharacterCreationUI] Submitted:", selectedGender, "Preset", selectedPreset)
	end)

	-- ── Listen for server confirmation ─────────────────────
	NetworkManager.OnServerEvent("CharacterCreationSaved", function(savedData)
		-- Fade out and destroy
		local tween = TweenService:Create(panel, TweenInfo.new(0.4), {
			Position = UDim2.new(0.5, -240, 0.5, -180 + 30),
			BackgroundTransparency = 1,
		})
		tween:Play()
		tween.Completed:Connect(function()
			sg:Destroy()
			print("[CharacterCreationUI] Character creation complete!")
		end)
	end)
end

-- ═══════════════════════════════════════════════════════════
-- INITIALIZATION
-- ═══════════════════════════════════════════════════════════

function CharacterCreationUI.Init()
	-- Listen for the server to request character creation
	NetworkManager.OnServerEvent("CharacterCreationRequired", function(payload)
		print("[CharacterCreationUI] Character creation required")
		BuildGui(payload or {})
	end)

	print("[CharacterCreationUI] Initialized")
end

return CharacterCreationUI
