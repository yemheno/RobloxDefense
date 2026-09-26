-- UI/HUD/QuickButtons.lua
--[[
    §AGX/UI-P5: touch-only quick buttons (shell-spec §4.2), replacing the
    Plaza AppearanceBar once W3 deletes it:
      Lobby  Emote            (1,-194,1,-24) phone / (1,-338,1,-24) tablet, 56
      Plaza  Emote 64 + Wardrobe 56 (mobile.md §2.5 AppearanceBar spots)
    Each renders only when its callback is given (onEmote / onWardrobe), so
    Wave 1 (no callbacks) shows nothing. Desktop / console use Q / DPadUp
    and the rail instead.
    props: layout (L), onEmote, onWardrobe, visible
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local React = require(ReplicatedStorage.Packages.React)

local Common     = script.Parent.Parent:WaitForChild("Common")
local IconButton = require(Common:WaitForChild("IconButton"))

local e = React.createElement

-- Theme.Icons.emote is Agent B's (B1); the glyph covers it until then.
local EMOTE_GLYPH    = "☺"
local WARDROBE_GLYPH = "👕"

local function quick(name, r, key, glyph, tooltip, onActivated)
	if not r or not onActivated then return nil end
	return e("Frame", {
		Name                   = name,
		AnchorPoint            = r.anchorPoint,
		Position               = r.position,
		Size                   = r.size,
		BackgroundTransparency = 1,
		ZIndex                 = 3,
	}, {
		btn = e(IconButton, {
			icon        = key,     -- art once Theme.GetIcon(key) has an id
			label       = glyph,   -- IconButton's fallback while it is a placeholder
			variant     = "secondary",
			size        = math.max(44, r.w),
			tooltip     = tooltip,
			anchorPoint = Vector2.new(0.5, 0.5),
			position    = UDim2.fromScale(0.5, 0.5),
			zIndex      = 3,
			onActivated = onActivated,
		}),
	})
end

local function QuickButtons(props)
	if not props.visible then return nil end
	local L = props.layout
	return e("Frame", {
		Name                   = "QuickButtons",
		Size                   = UDim2.fromScale(1, 1),
		BackgroundTransparency = 1,
		ZIndex                 = 3,
	}, {
		emote    = quick("Emote", L.emote, "emote", EMOTE_GLYPH, "Emotes", props.onEmote),
		wardrobe = (L.place == "Plaza")
			and quick("Wardrobe", L.wardrobe, "wardrobe", WARDROBE_GLYPH, "Wardrobe", props.onWardrobe)
			or nil,
	})
end

return QuickButtons
