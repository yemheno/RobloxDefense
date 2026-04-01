-- ReplicatedStorage/Shared/EmoteConfig.lua
--[[
    Single source of truth for emote definitions.

    Lives in ReplicatedStorage so both server (AnimationConfig) and client
    (EmoteWheel) can read from it without duplication.

    Adding an emote:
      1. Upload the R6 animation to Roblox under your game's creator account.
      2. Replace the animId below with "rbxassetid://<your-asset-id>".
      3. EmoteWheel and AnimationConfig pick it up automatically.

    ⚠ Rig type:
      This game uses R6 characters. Ensure all emote animations are uploaded
      as R6 animations.
]]

local EmoteConfig = {}

EmoteConfig.Emotes = {
	{ id = "Wave",  label = "Wave",  icon = "~", animId = "rbxassetid://507770239", looped = false },
	{ id = "Dance", label = "Dance", icon = "*", animId = "rbxassetid://507771019", looped = true  },
	{ id = "Laugh", label = "Laugh", icon = ":", animId = "rbxassetid://507770818", looped = false },
	{ id = "Point", label = "Point", icon = ">", animId = "rbxassetid://507770453", looped = false },
}

--- Get emote entry by id.
function EmoteConfig.GetEmote(emoteId)
	for _, emote in ipairs(EmoteConfig.Emotes) do
		if emote.id == emoteId then
			return emote
		end
	end
	return nil
end

return EmoteConfig
