-- ServerScriptService/Modules/AuctionConfig
--[[
    §19 / §20: Auction House rules and Essence Market Anchor

    This is a config-only module.  The actual AuctionManager runtime
    does not exist yet (§52.3).  When the feature is built, it should
    read these tables instead of hard-coding the numbers.
]]

local AuctionConfig = {}

-- ═══════════════════════════════════════════════════════════
-- AUCTION BANDS (§19)
-- ═══════════════════════════════════════════════════════════

AuctionConfig.Bands = {
	{ id = "band_1", minLevel = 1,   maxLevel = 50  },
	{ id = "band_2", minLevel = 51,  maxLevel = 100 },
	{ id = "band_3", minLevel = 101, maxLevel = 150 },
	{ id = "band_4", minLevel = 151, maxLevel = 200 },
}

-- ═══════════════════════════════════════════════════════════
-- TRADING RESTRICTIONS (§19)
-- ═══════════════════════════════════════════════════════════

AuctionConfig.MinTradeLevel = 20

-- Listing tax applied to the seller's payout
AuctionConfig.ListingTax = 0.12

-- New-account daily caps (first 7 days after reaching MinTradeLevel)
AuctionConfig.NewAccountCaps = {
	daysActive         = 7,       -- how many days the caps apply
	maxListingsPerDay  = 3,
	maxPurchasesPerDay = 5,
}

-- ═══════════════════════════════════════════════════════════
-- ESSENCE MARKET ANCHOR (§20)
-- Suggested merit-per-essence exchange range by band.
-- ═══════════════════════════════════════════════════════════

AuctionConfig.EssenceAnchor = {
	global  = { min = 240, max = 340 },
	band_1  = { min = 300, max = 420 },
	band_2  = { min = 350, max = 500 },
	band_3  = { min = 420, max = 600 },
	band_4  = { min = 500, max = 750 },
}

-- ═══════════════════════════════════════════════════════════
-- HELPERS
-- ═══════════════════════════════════════════════════════════

function AuctionConfig.GetBandForLevel(level)
	for _, band in ipairs(AuctionConfig.Bands) do
		if level >= band.minLevel and level <= band.maxLevel then
			return band
		end
	end
	return AuctionConfig.Bands[1]
end

function AuctionConfig.CanTrade(accountLevel)
	return accountLevel >= AuctionConfig.MinTradeLevel
end

function AuctionConfig.AreInSameBand(levelA, levelB)
	local bandA = AuctionConfig.GetBandForLevel(levelA)
	local bandB = AuctionConfig.GetBandForLevel(levelB)
	return bandA.id == bandB.id
end

return AuctionConfig
