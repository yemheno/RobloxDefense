-- InputSystem/InputActions.lua
--[[
	Centralized action definitions.

	Each action declares:
	  • displayName  — UI label text
	  • category     — grouping for settings UI ("Combat", "Social", etc.)
	  • contexts     — set of contexts where the action is active
	                   (keys are context names, values are true)
	  • defaults     — per-platform default bindings
	                   Keys: "Keyboard", "Gamepad", "Touch"
	                   Values: array of Enum.KeyCode / Enum.UserInputType

	Touch bindings are empty because mobile on-screen buttons call
	InputSystem.FireAction() directly — no physical key involved.
]]

local InputActions = {}

InputActions.Definitions = {
	-- ═══ Combat ═══════════════════════════════════════════

	Attack = {
		displayName = "Attack",
		category    = "Combat",
		contexts    = { Combat = true },
		defaults    = {
			Keyboard = { Enum.UserInputType.MouseButton1 },
			Gamepad  = { Enum.KeyCode.ButtonR2 },
			Touch    = {},
		},
	},

	Dash = {
		displayName = "Dash",
		category    = "Combat",
		contexts    = { Combat = true },
		defaults    = {
			Keyboard = { Enum.KeyCode.Space },
			Gamepad  = { Enum.KeyCode.ButtonB },
			Touch    = {},
		},
	},

	Skill1 = {
		displayName = "Skill 1",
		category    = "Combat",
		contexts    = { Combat = true },
		defaults    = {
			Keyboard = { Enum.KeyCode.Q },
			Gamepad  = { Enum.KeyCode.ButtonX },
			Touch    = {},
		},
	},

	Skill2 = {
		displayName = "Skill 2",
		category    = "Combat",
		contexts    = { Combat = true },
		defaults    = {
			Keyboard = { Enum.KeyCode.E },
			Gamepad  = { Enum.KeyCode.ButtonY },
			Touch    = {},
		},
	},

	Skill3 = {
		displayName = "Skill 3",
		category    = "Combat",
		contexts    = { Combat = true },
		defaults    = {
			Keyboard = { Enum.KeyCode.R },
			Gamepad  = { Enum.KeyCode.ButtonL1 },
			Touch    = {},
		},
	},

	Skill4 = {
		displayName = "Skill 4",
		category    = "Combat",
		contexts    = { Combat = true },
		defaults    = {
			Keyboard = { Enum.KeyCode.F },
			Gamepad  = { Enum.KeyCode.ButtonR1 },
			Touch    = {},
		},
	},

	-- ═══ Lobby ════════════════════════════════════════════

	Interact = {
		displayName = "Interact",
		category    = "Lobby",
		contexts    = { Lobby = true },
		defaults    = {
			Keyboard = { Enum.KeyCode.E },
			Gamepad  = { Enum.KeyCode.ButtonA },
			Touch    = {},
		},
	},

	EmoteWheel = {
		displayName = "Emote Wheel",
		category    = "Social",
		contexts    = { Lobby = true },
		defaults    = {
			Keyboard = { Enum.KeyCode.Q },
			Gamepad  = { Enum.KeyCode.DPadUp },
			Touch    = {},
		},
	},
}

return InputActions
