-- UI/EquipmentUI.lua
--[[
    React component: equipment viewer.
    §AGX/UI-P6: now an AppWindow (windowed; sheet on phone) instead of a
    hand-rolled fullscreen Frame + close button; body in design px inside
    UIScaleRoot.Local; weapon/armor = Panel cards side by side when the body
    is wide, stacked otherwise; XP = Bar kind "xp". The private palette,
    the MIN_TAP_PX hit box, the XPBar and the TextScaled title are gone.

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

-- §AGX/UI-P6: shared components
local Common        = script.Parent:WaitForChild("Common")
local AppWindow     = require(Common:WaitForChild("AppWindow"))
local Theme         = require(Common:WaitForChild("Theme"))
local UIScaleRoot   = require(Common:WaitForChild("UIScaleRoot"))
local Text          = require(Common:WaitForChild("Text"))
local Panel         = require(Common:WaitForChild("Panel"))
local Bar           = require(Common:WaitForChild("Bar"))
local useFormFactor = require(Common:WaitForChild("useFormFactor"))

local e  = React.createElement
local R  = Theme.Roles
local SP = Theme.Space

local WIDE_MIN = 600   -- §AGX/UI-P6: design px for side-by-side cards
local LINE_H   = 24

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
	-- §AGX/D-FIX2: rolls that map to real stats (labels, never raw keys)
	healingPower     = "Healing Power",
	healingPercent   = "Healing %",
	lifeEnergy       = "Life Energy",
	mana             = "Aether",
	focus            = "Killer Instinct",
}

local function StatLabel(stat)
	return STAT_LABELS[stat] or stat
end

-- ── Stat line sub-component (also the bonus row, §AGX/UI-P6) ─────────────────
local function StatLine(props)
	return e("Frame", {
		Size                   = UDim2.new(1, 0, 0, LINE_H),
		BackgroundTransparency = 1,
		LayoutOrder            = props.order or 0,
	}, {
		lbl = e(Text, {
			style = "body",
			text  = (props.bullet and "•  " or "") .. props.label,
			color = props.bullet and "text.primary" or "text.secondary",
			size  = UDim2.fromScale(0.6, 1),
		}),
		val = e(Text, {
			style       = "numeric",
			text        = tostring(props.value),
			color       = props.color or "text.primary",
			align       = "right",
			anchorPoint = Vector2.new(1, 0),
			position    = UDim2.fromScale(1, 0),
			size        = UDim2.fromScale(0.4, 1),
		}),
	})
end

local function Divider(props)
	return e("Frame", {
		Size             = UDim2.new(1, 0, 0, 1),
		BackgroundColor3 = R.border.subtle,
		BorderSizePixel  = 0,
		LayoutOrder      = props.order,
	})
end

-- ── Equipment card (weapon or armor) ─────────────────────────────────────────
local function EquipmentCard(props)
	local data       = props.data or {}
	local cardTitle  = props.title or "Equipment"

	local name       = data.name or "None"
	local level      = data.level or 1
	local maxLevel   = data.maxLevel or 1
	local xp         = data.xp or 0
	local required   = data.required or 100
	local refinement = data.refinement or 0
	local tier       = data.tier or 1
	local bonuses    = data.bonuses or {}

	local statChildren = {}

	-- Title row + item name
	statChildren.title = e(Text, {
		style = "title", text = cardTitle, color = "accent.secondary",
		align = "center", layoutOrder = 0,
	})
	statChildren.name = e(Text, {
		style = "heading", text = name, align = "center", layoutOrder = 1,
	})

	-- XP bar (§AGX/UI-P6: Bar kind "xp")
	statChildren.xpBar = e(Bar, {
		kind        = "xp",
		value       = xp,
		max         = math.max(required, 1),
		label       = "Lv " .. tostring(level) .. "/" .. tostring(maxLevel),
		showValue   = true,
		layoutOrder = 2,
	})

	statChildren.div1 = e(Divider, { order = 3 })

	-- Core stats
	local statOrder = 10
	if data.attack then
		statChildren.atk = e(StatLine, {
			label = "Attack",
			value = tostring(data.attack),
			order = statOrder,
		})
		statOrder = statOrder + 1
	end
	if data.attackSpeed then
		statChildren.spd = e(StatLine, {
			label = "ATK Speed",
			value = string.format("%.1f/s", data.attackSpeed),
			order = statOrder,
		})
		statOrder = statOrder + 1
	end
	if data.attackShape then
		statChildren.shape = e(StatLine, {
			label = "Shape",
			value = data.attackShape,
			order = statOrder,
		})
		statOrder = statOrder + 1
	end
	if data.defense then
		statChildren.def = e(StatLine, {
			label = "Defense",
			value = tostring(data.defense),
			order = statOrder,
		})
		statOrder = statOrder + 1
	end
	if data.bonusHealth then
		statChildren.hp = e(StatLine, {
			label = "Bonus HP",
			value = "+" .. tostring(data.bonusHealth),
			order = statOrder,
		})
		statOrder = statOrder + 1
	end

	-- Refinement + Tier
	statChildren.ref = e(StatLine, {
		label = "Refinement",
		value = "+" .. tostring(refinement),
		color = "accent.secondary",
		order = 20,
	})
	statChildren.tier = e(StatLine, {
		label = "Tier",
		value = tostring(tier),
		color = "accent.secondary",
		order = 21,
	})

	statChildren.div2 = e(Divider, { order = 30 })

	-- Bonuses header
	statChildren.bonusHdr = e(Text, {
		style       = "label",
		text        = "Random Bonuses (" .. tostring(#bonuses) .. ")",
		color       = "state.success",
		layoutOrder = 31,
	})

	-- Bonus rows
	for i, bonus in ipairs(bonuses) do
		statChildren["bonus_" .. i] = e(StatLine, {
			label  = StatLabel(bonus.stat),
			value  = "+" .. tostring(bonus.value),
			color  = "state.success",
			bullet = true,
			order  = 31 + i,
		})
	end

	return e(Panel, {
		name        = props.name or "EquipmentCard",
		elevation   = "raised",
		padding     = "lg",
		radius      = "lg",
		layout      = "vertical",
		gap         = "xs",
		size        = UDim2.new(props.width or UDim.new(1, 0), UDim.new(0, 0)),
		autoSize    = "Y",
		layoutOrder = props.layoutOrder or 0,
	}, statChildren)
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

	-- §AGX/UI-P6: body width (design px) -> side by side or stacked.
	local ff = useFormFactor()
	local bodyW, setBodyW = React.useState(WIDE_MIN)
	local onBodySize = React.useCallback(function(rbx)
		local w = rbx.AbsoluteSize.X
		if w > 0 then setBodyW(w / math.max(ff.uiScale or 1, 0.01)) end
	end, { ff.uiScale })
	local wide = bodyW >= WIDE_MIN
	local gap = SP.lg
	local cardW = wide and UDim.new(0.5, -gap / 2) or UDim.new(1, 0)

	return e(AppWindow, {
		variant = "windowed",
		title   = "Equipment",
		icon    = "equipment",
		onClose = onClose,
		zIndex  = 10,
	}, {
		content = e(UIScaleRoot.Local, { name = "EquipmentBody" }, {
			scroll = e("ScrollingFrame", {
				Name                   = "Scroll",
				Size                   = UDim2.fromScale(1, 1),
				BackgroundTransparency = 1,
				BorderSizePixel        = 0,
				CanvasSize             = UDim2.new(0, 0, 0, 0),
				AutomaticCanvasSize    = Enum.AutomaticSize.Y,
				ScrollingDirection     = Enum.ScrollingDirection.Y,
				ScrollBarThickness     = Theme.Metrics.scrollBar,
				ScrollBarImageColor3   = R.text.secondary,
				[React.Change.AbsoluteSize] = onBodySize,
			}, {
				pad = e("UIPadding", {
					PaddingLeft = UDim.new(0, SP.lg), PaddingRight = UDim.new(0, SP.lg),
					PaddingTop = UDim.new(0, SP.md), PaddingBottom = UDim.new(0, SP.lg),
				}),
				layout = e("UIListLayout", {
					FillDirection     = wide and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical,
					VerticalAlignment = Enum.VerticalAlignment.Top,
					Padding           = UDim.new(0, gap),
					SortOrder         = Enum.SortOrder.LayoutOrder,
				}),

				-- Weapon card
				weaponCard = e(EquipmentCard, {
					name        = "Weapon",
					title       = "⚔  WEAPON",
					data        = weaponData,
					width       = cardW,
					layoutOrder = 1,
				}),

				-- Armor card
				armorCard = e(EquipmentCard, {
					name        = "Armor",
					title       = "🛡  ARMOR",
					data        = armorData,
					width       = cardW,
					layoutOrder = 2,
				}),
			}),
		}),
	})
end

return EquipmentUI
