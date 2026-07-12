-- ServerScriptService/Modules/PartyRequirements
--[[
    PartyRequirements  (§DISC/D6 round 2)
    =====================================
    THE single home for "can these players play together / launch this
    run" rules. PartyManager (invite-time) and TeleportManager
    (launch-time) both call in here, so a rule added once applies at
    both gates automatically.

    Pablo: "if we need to fold more cap features — which is really
    common — it may be worth it." This is that fold point. Future gates
    that belong here:
      • per-difficulty requiredLevel  (currently in MatchmakingManager §S3
        — migrate here when it grows)
      • achievement-gated content     (§DISC/D5 — e.g. chapter boss
        achievements unlocking Nightmare)
      • class-composition rules       (if a mode ever requires a healer)
]]

local PartyRequirements = {}

local Modules = script.Parent

-- §L11: MaxLevelGap value is single-sourced from PlayerDataConfig.
local _maxGap = 10
do
	local ok, cfg = pcall(function()
		return require(Modules:WaitForChild("PlayerDataConfig"))
	end)
	if ok and cfg and cfg.Matchmaking and cfg.Matchmaking.MaxLevelGap then
		_maxGap = cfg.Matchmaking.MaxLevelGap
	else
		warn("[PartyRequirements] PlayerDataConfig.Matchmaking.MaxLevelGap missing — defaulting to 10")
	end
end

function PartyRequirements.MaxLevelGap()
	return _maxGap
end

--- Two individual levels compatible? (invite-time pairwise check)
function PartyRequirements.FitsLevelGap(levelA, levelB)
	return math.abs((levelA or 1) - (levelB or 1)) <= _maxGap
end

--- Whole-party check from a list of levels (launch-time).
--- Returns ok, minLevel, maxLevel.
function PartyRequirements.CheckLevels(levels)
	local minL, maxL = math.huge, 0
	for _, lvl in ipairs(levels) do
		lvl = lvl or 1
		if lvl < minL then minL = lvl end
		if lvl > maxL then maxL = lvl end
	end
	if minL == math.huge then return true, 1, 1 end
	return (maxL - minL) <= _maxGap, minL, maxL
end

return PartyRequirements
