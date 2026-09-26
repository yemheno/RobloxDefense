-- StarterPlayerScripts/Modules/VipTag.lua
--[[
    §AGX/UI-FREE: VipTag, the reader of the `VIP` player attribute
    (§AGX/X40-VIP). MonetizationService sets `VIP = true` on the Player when
    the VIP GamePass is owned (ShopConfig "premium_vip": perks
    nameplate_tag + chat_tag, "Social perks only, no gameplay advantage").

    PURELY COSMETIC, CLIENT-SIDE. Nothing here is sent to the server or
    changes any number; each client decorates what it displays.

      chat_tag       TextChatService.OnIncomingMessage prefixes "[VIP]" in
                     the body accent (Theme.Roles.accent.secondary) to
                     messages whose sender has VIP == true.
      nameplate_tag  NOT built: players have no custom nameplate or
                     BillboardGui (overheads are Roblox's default Humanoid
                     name). When one exists, it should read
                     VipTag.IsVip(player) / the same attribute.

    OnIncomingMessage is a single-assignment callback: this module OWNS it.
    Anything else that needs it must be merged in here, not assigned
    elsewhere (the last assignment wins silently).

    Load it from a place client (Load(SharedModules, "VipTag")); Init is
    idempotent.
]]

local Players         = game:GetService("Players")
local TextChatService = game:GetService("TextChatService")

local VipTag = {}

local ATTRIBUTE = "VIP"          -- ShopConfig premium_vip grant.attribute
local TAG_TEXT  = "[VIP]"

local initialized = false

--- True when `player` owns VIP (attribute set by MonetizationService).
function VipTag.IsVip(player)
	return player ~= nil and player:GetAttribute(ATTRIBUTE) == true
end

-- Lazy getter (house pattern): the tag markup, coloured from Theme v2
-- roles. NON-YIELDING (FindFirstChild only): it runs inside the chat
-- callback, which must never yield. Cached once Theme was found.
local prefixCache = nil
local function tagPrefix()
	if prefixCache then return prefixCache end
	local hex, found = "5ABEFF", false   -- fallback = Theme.Palette.blue400
	local ps = Players.LocalPlayer:FindFirstChild("PlayerScripts")
	local ui = ps and ps:FindFirstChild("UI")
	local common = ui and ui:FindFirstChild("Common")
	local mod = common and common:FindFirstChild("Theme")
	if mod then
		local ok, Theme = pcall(require, mod)
		if ok and type(Theme) == "table" and Theme.Roles then
			hex, found = Theme.Roles.accent.secondary:ToHex(), true
		end
	end
	local prefix = string.format('<font color="#%s">%s</font>', hex, TAG_TEXT)
	if found then prefixCache = prefix end
	return prefix
end

function VipTag.Init()
	if initialized then return end
	initialized = true

	if TextChatService.ChatVersion ~= Enum.ChatVersion.TextChatService then
		warn("[VipTag] Legacy chat in use: the [VIP] chat tag needs TextChatService.")
		return
	end

	tagPrefix()   -- warm the cache (Theme is already replicated at boot)

	-- Must not yield and must return quickly; nil = default rendering.
	TextChatService.OnIncomingMessage = function(message)
		local source = message.TextSource
		if not source then return nil end   -- system messages
		local sender = Players:GetPlayerByUserId(source.UserId)
		if not VipTag.IsVip(sender) then return nil end
		local props = Instance.new("TextChatMessageProperties")
		props.PrefixText = tagPrefix() .. " " .. (message.PrefixText or "")
		return props
	end
end

return VipTag
