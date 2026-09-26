-- UI/EquipmentUI.lua
--[[
    React component: fullscreen equipment viewer.

    Shows two columns:
      • Left  — Weapon (name, level/XP, refinement, tier, ATK, speed, bonuses)
      • Right — Armor  (name, level/XP, refinement, tier, DEF, HP bonus, bonuses)

    Data source: listens to NetworkManager events for real-time updates.
    Requests a snapshot on mount via "GetEquipmentInfo".

    Props:
      onClose  — callback to dismiss the panel
]]

local Players           = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React             = require(ReplicatedStorage.Packages.React)

local PlayerScripts  = Players.LocalPlayer:WaitForChild("PlayerScripts")
local SharedModules  = PlayerScripts:WaitForChild("Modules")
local NetworkManager = require(SharedModules:WaitForChild("NetworkManager"))

-- ── Palette ───────────────────────────────────────────────────────────────────
local C = {
	bg         = Color3.fromRGB( 12,  12,  18),
	panel      = Color3.fromRGB( 22,  22,  32),
	card       = Color3.fromRGB( 28,  28,  42),
	card_hi    = Color3.fromRGB( 35,  35,  52),
	text       = Color3.fromRGB(220, 220, 230),
	text_dim   = Color3.fromRGB(140, 140, 160),
	text_val   = Color3.fromRGB(255, 220, 100),
	weapon_c   = Color3.fromRGB(255, 120,  80),
	armor_c    = Color3.fromRGB( 80, 180, 255),
	bonus_c    = Color3.fromRGB(140, 220, 140),
	bar_bg     = Color3.fromRGB( 35,  35,  50),
	bar_fill   = Color3.fromRGB(210, 150,  40),
	btn_bg     = Color3.fromRGB( 35,  35,  52),
	btn_text   = Color3.fromRGB(105, 190, 255),
	btn_stroke = Color3.fromRGB( 60, 100, 180),
	close_bg   = Color3.fromRGB(180,  50,  50),
	divider    = Color3.fromRGB( 50,  50,  70),
}

-- §AGX/UI-P1: minimum tap target (close was 51x21 px on a phone).
local MIN_TAP_PX = 44

-- ── Stat formatting helper ────────────────────────────────────────────────────
local STAT_LABELS = {
	critChance       = "Crit Chance",
	critDamage       = "Crit Damage",
	flatAttack       = "Flat ATK",
	attackSpeed      = "ATK Speed",
	determination    = "Determination",
	damageReduction  = "Damage Red.",
	skillDamage      = "Skill DMG",
	tauntDuration    = "Taunt Dur.",
	lifesteal        = "Life Steal",
	aoeSize          = "AoE Size",
	movementSpeed    = "Move Speed",
	cooldownReduction = "CDR",
	bonusHealth      = "Bonus HP",
	thorns           = "Thorns",
	statusResistance = "Status Res.",
}

local function StatLabel(stat)
	return STAT_LABELS[stat] or stat
end

-- ── Bonus row sub-component ──────────────────────────────────────────────────
local function BonusRow(props)
	return React.createElement("Frame", {
		Size               = UDim2.fromScale(1, 0),
		AutomaticSize      = Enum.AutomaticSize.Y,
		BackgroundTransparency = 1,
		LayoutOrder        = props.order or 0,
	}, {
		layout = React.createElement("UIListLayout", {
			FillDirection = Enum.FillDirection.Horizontal,
			Padding       = UDim.new(0.02, 0),
		}),
		dot = React.createElement("TextLabel", {
			-- §AGX/UI-P1: V1: was fromScale(0.006, 0.017) of the bonus row
			-- (~2 px wide). Pixel box for the 14 pt bullet.
			Size               = UDim2.fromOffset(12, 16),
			BackgroundTransparency = 1,
			Text               = "•",
			TextColor3         = C.bonus_c,
			Font               = Enum.Font.GothamBold,
			TextSize           = 14,
			TextXAlignment     = Enum.TextXAlignment.Center,
		}),
		lbl = React.createElement("TextLabel", {
			Size               = UDim2.fromScale(0.55, 0),
			AutomaticSize      = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Text               = StatLabel(props.stat),
			TextColor3         = C.text,
			Font               = Enum.Font.Gotham,
			TextSize           = 13,
			TextXAlignment     = Enum.TextXAlignment.Left,
		}),
		val = React.createElement("TextLabel", {
			Size               = UDim2.fromScale(0.30, 0),
			AutomaticSize      = Enum.AutomaticSize.Y,
			BackgroundTransparency = 1,
			Text               = "+" .. tostring(props.value),
			TextColor3         = C.text_val,
			Font               = Enum.Font.GothamBold,
			TextSize           = 13,
			TextXAlignment     = Enum.TextXAlignment.Right,
		}),
	})
end

-- ── Stat line sub-component ──────────────────────────────────────────────────
local function StatLine(props)
	return React.createElement("Frame", {
		Size               = UDim2.new(1, 0, 0, 22),
		BackgroundTransparency = 1,
		LayoutOrder        = props.order or 0,
	}, {
		lbl = React.createElement("TextLabel", {
			Position               = UDim2.fromScale(0, 0),
			Size                   = UDim2.fromScale(0.55, 1),
			BackgroundTransparency = 1,
			Text                   = props.label,
			TextColor3             = C.text_dim,
			Font                   = Enum.Font.Gotham,
			TextSize               = 14,
			TextXAlignment         = Enum.TextXAlignment.Left,
		}),
		val = React.createElement("TextLabel", {
			Position               = UDim2.fromScale(0.55, 0),
			Size                   = UDim2.fromScale(0.45, 1),
			BackgroundTransparency = 1,
			Text                   = tostring(props.value),
			TextColor3             = props.color or C.text,
			Font                   = Enum.Font.GothamBold,
			TextSize               = 14,
			TextXAlignment         = Enum.TextXAlignment.Right,
		}),
	})
end

-- ── XP Bar sub-component ─────────────────────────────────────────────────────
local function XPBar(props)
	local pct = math.clamp((props.xp or 0) / math.max(props.required or 1, 1), 0, 1)
	return React.createElement("Frame", {
		Size               = UDim2.new(1, 0, 0, 30),
		BackgroundTransparency = 1,
		LayoutOrder        = props.order or 0,
	}, {
		lbl = React.createElement("TextLabel", {
			Size               = UDim2.fromScale(0.30, 1),
			BackgroundTransparency = 1,
			Text               = "Lv " .. tostring(props.level) .. "/" .. tostring(props.maxLevel),
			TextColor3         = C.text,
			Font               = Enum.Font.GothamBold,
			TextSize           = 14,
			TextXAlignment     = Enum.TextXAlignment.Left,
		}),
		track = React.createElement("Frame", {
			Position         = UDim2.fromScale(0.32, 0.20),
			Size             = UDim2.fromScale(0.45, 0.60),
			BackgroundColor3 = C.bar_bg,
			BorderSizePixel  = 0,
		}, {
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
			fill = React.createElement("Frame", {
				Size             = UDim2.fromScale(pct, 1),
				BackgroundColor3 = C.bar_fill,
				BorderSizePixel  = 0,
			}, {
				corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.5, 0) }),
			}),
		}),
		txt = React.createElement("TextLabel", {
			Position               = UDim2.fromScale(0.79, 0),
			Size                   = UDim2.fromScale(0.21, 1),
			BackgroundTransparency = 1,
			Text                   = tostring(props.xp) .. "/" .. tostring(props.required),
			TextColor3             = C.text_dim,
			Font                   = Enum.Font.Gotham,
			TextSize               = 11,
			TextXAlignment         = Enum.TextXAlignment.Right,
		}),
	})
end

-- ── Equipment card (weapon or armor) ─────────────────────────────────────────
local function EquipmentCard(props)
	local data       = props.data or {}
	local accentColor = props.accentColor or C.text
	local cardTitle   = props.title or "Equipment"

	local name       = data.name or "None"
	local level      = data.level or 1
	local maxLevel   = data.maxLevel or 1
	local xp         = data.xp or 0
	local required   = data.required or 100
	local refinement = data.refinement or 0
	local tier       = data.tier or 1
	local bonuses    = data.bonuses or {}

	-- Build stat lines
	local statChildren = {}
	statChildren.layout = React.createElement("UIListLayout", {
		FillDirection     = Enum.FillDirection.Vertical,
		SortOrder         = Enum.SortOrder.LayoutOrder,
		Padding           = UDim.new(0, 3),
	})

	-- Title row
	statChildren.title = React.createElement("TextLabel", {
		Size               = UDim2.new(1, 0, 0, 28),
		BackgroundTransparency = 1,
		Text               = cardTitle,
		TextColor3         = accentColor,
		Font               = Enum.Font.GothamBold,
		TextSize           = 18,
		TextXAlignment     = Enum.TextXAlignment.Center,
		LayoutOrder        = 0,
	})

	-- Name
	statChildren.name = React.createElement("TextLabel", {
		Size               = UDim2.new(1, 0, 0, 24),
		BackgroundTransparency = 1,
		Text               = name,
		TextColor3         = C.text,
		Font               = Enum.Font.GothamBold,
		TextSize           = 16,
		TextXAlignment     = Enum.TextXAlignment.Center,
		LayoutOrder        = 1,
	})

	-- XP bar
	statChildren.xpBar = React.createElement(XPBar, {
		level    = level,
		maxLevel = maxLevel,
		xp       = xp,
		required = required,
		order    = 2,
	})

	-- Divider
	statChildren.div1 = React.createElement("Frame", {
		Size             = UDim2.new(0.9, 0, 0, 1),
		BackgroundColor3 = C.divider,
		BorderSizePixel  = 0,
		LayoutOrder      = 3,
	})

	-- Core stats
	local statOrder = 10
	if data.attack then
		statChildren.atk = React.createElement(StatLine, {
			label = "Attack",
			value = tostring(data.attack),
			color = C.weapon_c,
			order = statOrder,
		})
		statOrder = statOrder + 1
	end
	if data.attackSpeed then
		statChildren.spd = React.createElement(StatLine, {
			label = "ATK Speed",
			value = string.format("%.1f/s", data.attackSpeed),
			order = statOrder,
		})
		statOrder = statOrder + 1
	end
	if data.attackShape then
		statChildren.shape = React.createElement(StatLine, {
			label = "Shape",
			value = data.attackShape,
			order = statOrder,
		})
		statOrder = statOrder + 1
	end
	if data.defense then
		statChildren.def = React.createElement(StatLine, {
			label = "Defense",
			value = tostring(data.defense),
			color = C.armor_c,
			order = statOrder,
		})
		statOrder = statOrder + 1
	end
	if data.bonusHealth then
		statChildren.hp = React.createElement(StatLine, {
			label = "Bonus HP",
			value = "+" .. tostring(data.bonusHealth),
			color = C.armor_c,
			order = statOrder,
		})
		statOrder = statOrder + 1
	end

	-- Refinement + Tier
	statChildren.ref = React.createElement(StatLine, {
		label = "Refinement",
		value = "+" .. tostring(refinement),
		color = C.text_val,
		order = 20,
	})
	statChildren.tier = React.createElement(StatLine, {
		label = "Tier",
		value = tostring(tier),
		color = C.text_val,
		order = 21,
	})

	-- Divider 2
	statChildren.div2 = React.createElement("Frame", {
		Size             = UDim2.new(0.9, 0, 0, 1),
		BackgroundColor3 = C.divider,
		BorderSizePixel  = 0,
		LayoutOrder      = 30,
	})

	-- Bonuses header
	statChildren.bonusHdr = React.createElement("TextLabel", {
		Size               = UDim2.new(1, 0, 0, 20),
		BackgroundTransparency = 1,
		Text               = "Random Bonuses (" .. tostring(#bonuses) .. ")",
		TextColor3         = C.bonus_c,
		Font               = Enum.Font.GothamBold,
		TextSize           = 13,
		TextXAlignment     = Enum.TextXAlignment.Left,
		LayoutOrder        = 31,
	})

	-- Bonus rows
	for i, bonus in ipairs(bonuses) do
		statChildren["bonus_" .. i] = React.createElement(BonusRow, {
			stat  = bonus.stat,
			value = bonus.value,
			order = 31 + i,
		})
	end

	return React.createElement("Frame", {
		Size             = UDim2.fromScale(0.44, 0.85),
		BackgroundColor3 = C.card,
		BorderSizePixel  = 0,
		LayoutOrder      = props.layoutOrder or 0,
	}, {
		corner  = React.createElement("UICorner", { CornerRadius = UDim.new(0.02, 0) }),
		stroke  = React.createElement("UIStroke", {
			Color     = accentColor,
			Thickness = 1.5,
			Transparency = 0.5,
		}),
		padding = React.createElement("UIPadding", {
			PaddingLeft   = UDim.new(0.04, 0),
			PaddingRight  = UDim.new(0.04, 0),
			PaddingTop    = UDim.new(0.03, 0),
			PaddingBottom = UDim.new(0.03, 0),
		}),
		content = React.createElement("ScrollingFrame", {
			Size                   = UDim2.fromScale(1, 1),
			BackgroundTransparency = 1,
			BorderSizePixel        = 0,
			ScrollBarThickness     = 4,
			CanvasSize             = UDim2.fromScale(0, 0),
			AutomaticCanvasSize    = Enum.AutomaticSize.Y,
		}, statChildren),
	})
end

-- ── EquipmentUI main component ───────────────────────────────────────────────
local function EquipmentUI(props)
	local onClose = props.onClose

	-- State: weapon & armor data from server
	local weaponData, setWeaponData = React.useState(nil)
	local armorData,  setArmorData  = React.useState(nil)

	React.useEffect(function()
		-- Request snapshot
		NetworkManager.FireServer("GetEquipmentInfo")

		local equipConn = NetworkManager.OnServerEvent("EquipmentInfo", function(data)
			if data.weapon then setWeaponData(data.weapon) end
			if data.armor  then setArmorData(data.armor) end
		end)

		-- Debounced re-request: coalesce multiple rapid server events into one
		local refreshThread = nil
		local function requestRefresh()
			if refreshThread then
				task.cancel(refreshThread)
			end
			refreshThread = task.delay(0.1, function()
				refreshThread = nil
				NetworkManager.FireServer("GetEquipmentInfo")
			end)
		end

		-- Live updates — all funnel through the debounced requestRefresh
		local wEquipConn = NetworkManager.OnServerEvent("WeaponEquipped", function(_data)
			requestRefresh()
		end)
		local aEquipConn = NetworkManager.OnServerEvent("ArmorEquipped", function(_data)
			requestRefresh()
		end)

		local wLevelConn = NetworkManager.OnServerEvent("WeaponLevelUp", function(_data)
			requestRefresh()
		end)

		local wRefConn = NetworkManager.OnServerEvent("WeaponRefinementResult", function(_data)
			requestRefresh()
		end)
		local aRefConn = NetworkManager.OnServerEvent("ArmorRefinementResult", function(_data)
			requestRefresh()
		end)

		local wTierConn = NetworkManager.OnServerEvent("WeaponTierUp", function(_data)
			requestRefresh()
		end)
		local aTierConn = NetworkManager.OnServerEvent("ArmorTierUp", function(_data)
			requestRefresh()
		end)

		local wRerollConn = NetworkManager.OnServerEvent("WeaponRerollResult", function(_data)
			requestRefresh()
		end)
		local aRerollConn = NetworkManager.OnServerEvent("ArmorRerollResult", function(_data)
			requestRefresh()
		end)

		-- Incremental XP updates (between level-ups the bar should animate)
		local wXpConn = NetworkManager.OnServerEvent("WeaponXPGained", function(_data)
			requestRefresh()
		end)

		return function()
			if refreshThread then task.cancel(refreshThread) end
			if equipConn   then equipConn:Disconnect()   end
			if wEquipConn  then wEquipConn:Disconnect()  end
			if aEquipConn  then aEquipConn:Disconnect()  end
			if wLevelConn  then wLevelConn:Disconnect()  end
			if wRefConn    then wRefConn:Disconnect()    end
			if aRefConn    then aRefConn:Disconnect()    end
			if wTierConn   then wTierConn:Disconnect()   end
			if aTierConn   then aTierConn:Disconnect()   end
			if wRerollConn then wRerollConn:Disconnect() end
			if aRerollConn then aRerollConn:Disconnect() end
			if wXpConn     then wXpConn:Disconnect()     end
		end
	end, {})

	return React.createElement("Frame", {
		Name                   = "EquipmentUI",
		Size                   = UDim2.fromScale(1, 1),
		BackgroundColor3       = C.bg,
		BackgroundTransparency = 0.05,
		BorderSizePixel        = 0,
		ZIndex                 = 10,
	}, {
		-- Title
		title = React.createElement("TextLabel", {
			AnchorPoint            = Vector2.new(0.5, 0),
			Position               = UDim2.fromScale(0.5, 0.02),
			Size                   = UDim2.fromScale(0.4, 0.06),
			BackgroundTransparency = 1,
			Text                   = "⚔  EQUIPMENT  🛡",
			TextColor3             = C.text,
			Font                   = Enum.Font.GothamBold,
			TextScaled             = true,
		}, {
			-- §AGX/UI-P1: M11 text floor
			minText = React.createElement("UITextSizeConstraint", { MinTextSize = 12 }),
		}),

		-- Close button
		closeBtn = React.createElement("TextButton", {
			AnchorPoint      = Vector2.new(1, 0),
			Position         = UDim2.fromScale(0.98, 0.015),
			Size             = UDim2.fromScale(0.06, 0.055),
			BackgroundColor3 = C.close_bg,
			BorderSizePixel  = 0,
			Text             = "✕",
			TextColor3       = Color3.fromRGB(255, 255, 255),
			Font             = Enum.Font.GothamBold,
			TextScaled       = true,
			ZIndex           = 11,
			[React.Event.Activated] = onClose,
		}, {
			corner = React.createElement("UICorner", { CornerRadius = UDim.new(0.2, 0) }),
			minText = React.createElement("UITextSizeConstraint", { MinTextSize = 12 }),  -- §AGX/UI-P1
			-- §AGX/UI-P1: transparent 44x44 hit box centred on the visual,
			-- which keeps its size (desktop unchanged).
			hit = React.createElement("TextButton", {
				Name                   = "HitArea",
				AnchorPoint            = Vector2.new(0.5, 0.5),
				Position               = UDim2.fromScale(0.5, 0.5),
				Size                   = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				Text                   = "",
				ZIndex                 = 12,
				[React.Event.Activated] = onClose,
			}, {
				minSize = React.createElement("UISizeConstraint", {
					MinSize = Vector2.new(MIN_TAP_PX, MIN_TAP_PX),
				}),
			}),
		}),

		-- Two-column layout
		-- Shifted left of center and limited to 82% width so the right edge
		-- (x ≈ 0.85) stays clear of the HUD nav buttons which start at x ≈ 0.865
		columns = React.createElement("Frame", {
			AnchorPoint            = Vector2.new(0.5, 0.5),
			Position               = UDim2.fromScale(0.44, 0.52),
			Size                   = UDim2.fromScale(0.82, 0.83),
			BackgroundTransparency = 1,
		}, {
			layout = React.createElement("UIListLayout", {
				FillDirection       = Enum.FillDirection.Horizontal,
				HorizontalAlignment = Enum.HorizontalAlignment.Center,
				VerticalAlignment   = Enum.VerticalAlignment.Center,
				Padding             = UDim.new(0.03, 0),
				SortOrder           = Enum.SortOrder.LayoutOrder,
			}),

			-- Weapon card
			weaponCard = React.createElement(EquipmentCard, {
				title       = "⚔  WEAPON",
				accentColor = C.weapon_c,
				data        = weaponData,
				layoutOrder = 1,
			}),

			-- Armor card
			armorCard = React.createElement(EquipmentCard, {
				title       = "🛡  ARMOR",
				accentColor = C.armor_c,
				data        = armorData,
				layoutOrder = 2,
			}),
		}),
	})
end

return EquipmentUI
