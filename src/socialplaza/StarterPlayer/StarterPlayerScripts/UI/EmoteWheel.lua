-- socialplaza/StarterPlayerScripts/UI/EmoteWheel.lua
-- This module is now shared and located at:
-- src/shared/StarterPlayer/StarterPlayerScripts/UI/EmoteWheel.lua
-- Both lobby and socialplaza load this via the Rojo project mapping.

-- At runtime this script lives at PlayerScripts.SocialPlaza.UI.EmoteWheel
-- Navigate: script → SocialPlaza.UI → SocialPlaza → PlayerScripts → UI → EmoteWheel
local PlayerScripts = script.Parent.Parent.Parent
local EmoteWheel = require(PlayerScripts:WaitForChild("UI"):WaitForChild("EmoteWheel"))

return EmoteWheel
