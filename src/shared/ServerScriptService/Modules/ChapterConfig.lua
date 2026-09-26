-- ServerScriptService/Modules/ChapterConfig
--[[
    Chapter progression configuration (numbers: BALANCE_NUMBERS.md#chapters)
    ═══════════════════════════════════════════════════════════════════════════
    Defines chapter boundaries, gear caps, and progression gates.
]]

local ChapterConfig = {}

--============================================
-- CHAPTER DEFINITIONS (§4)
--============================================
ChapterConfig.CHAPTERS = {
	{ chapter = 1, minLevel = 1,   maxLevel = 50  },
	{ chapter = 2, minLevel = 51,  maxLevel = 100 },
	{ chapter = 3, minLevel = 101, maxLevel = 150 },
	{ chapter = 4, minLevel = 151, maxLevel = 200 },
}

--============================================
-- CHAPTER GEAR CAPS
--============================================

-- Maximum refinement by chapter (§13)
ChapterConfig.MAX_REFINE = {
	[1] = 8,
	[2] = 11,
	[3] = 13,
	[4] = 15,
}

-- Maximum tier by chapter (§12)
ChapterConfig.MAX_TIER = {
	[1] = 5,   -- Tier V
	[2] = 8,   -- Tier VIII
	[3] = 10,  -- Tier X
	[4] = 12,  -- Tier XII
}

-- §11: Ascension Crest tokens awarded on ascension boss clear
ChapterConfig.ASCENSION_CRESTS = {
	[1] = "AscensionCrest_50",
	[2] = "AscensionCrest_100",
	[3] = "AscensionCrest_150",
}

--============================================
-- HELPERS
--============================================

function ChapterConfig.GetChapter(level)
	level = level or 1
	for i = #ChapterConfig.CHAPTERS, 1, -1 do
		if level >= ChapterConfig.CHAPTERS[i].minLevel then
			return ChapterConfig.CHAPTERS[i].chapter
		end
	end
	return 1
end

function ChapterConfig.GetChapterLevelCap(chapterNum)
	local ch = ChapterConfig.CHAPTERS[chapterNum]
	return ch and ch.maxLevel or 200
end

function ChapterConfig.GetMaxRefine(level)
	local chapter = ChapterConfig.GetChapter(level)
	return ChapterConfig.MAX_REFINE[chapter] or 15
end

function ChapterConfig.GetMaxTier(level)
	local chapter = ChapterConfig.GetChapter(level)
	return ChapterConfig.MAX_TIER[chapter] or 12
end

return ChapterConfig
