--!strict
--[[
	GachaConfig
	Every economic value for the summon system lives here — costs, odds, pity,
	banners, duplicate conversions, reward quantities and crystal products.
	Nothing else in the project hardcodes these numbers.

	ODDS DISCLOSURE: the in-game "Rates & Pity" panel is generated from this
	module, so what players see is always exactly what the server rolls.
--]]

local GachaConfig = {}

-- ── Development switch ────────────────────────────────────────────────────────
-- While true, summons cost nothing (pity and results still behave normally).
-- Set to false to charge Tickets / Crystals as configured below.
GachaConfig.FREE_SUMMONS = true

-- ── Currencies ────────────────────────────────────────────────────────────────
-- tickets  : earned in gameplay, quests, events, achievements. 1 ticket = 1 pull.
-- crystals : premium, from purchases / selected premium rewards.
GachaConfig.Currencies = {
	tickets = { name = "Summon Ticket", glyph = "TICKETS" },
	crystals = { name = "Crystal", glyph = "CRYSTALS" },
	soulShards = { name = "Soul Shard", glyph = "SHARDS" },
	relicDust = { name = "Relic Dust", glyph = "DUST" },
}

GachaConfig.Cost = {
	single = { tickets = 1, crystals = 300 },
	multi = { tickets = 10, crystals = 3000, count = 10 },
}

-- Starting balances for brand-new profiles.
GachaConfig.StartingCurrencies = { tickets = 3, crystals = 0 }

-- ── Rarities & base odds (must sum to 100) ───────────────────────────────────
GachaConfig.RarityOrder = { "Common", "Rare", "Epic", "Legendary", "Mythic" }
GachaConfig.Rarities = {
	Common    = { odds = 60.0, color = Color3.fromRGB(190, 195, 205) },
	Rare      = { odds = 28.0, color = Color3.fromRGB(90, 170, 255) },
	Epic      = { odds = 9.0,  color = Color3.fromRGB(190, 95, 255) },
	Legendary = { odds = 3.0,  color = Color3.fromRGB(255, 200, 70) },
	Mythic    = { odds = 0.0,  color = Color3.fromRGB(255, 70, 120) }, -- no Mythic rewards yet
}

-- ── Pity (per banner, carried between sessions) ──────────────────────────────
GachaConfig.Pity = {
	epicEvery = 10,          -- guaranteed Epic or better within every 10 pulls
	legendarySoftStart = 55, -- from this pull, Legendary odds rise…
	legendarySoftStep = 6.0, -- …by this many % per pull
	legendaryHard = 70,      -- guaranteed Legendary or better on this pull
	multiGuarantee = "Rare", -- every 10-pull contains at least one of this rarity or better
}

-- ── Banners ───────────────────────────────────────────────────────────────────
-- featured: rate-up reward id. When a Legendary is rolled, featuredRate is the
-- chance it's the featured one; losing that 50/50 guarantees it next Legendary.
GachaConfig.Banners = {
	divine_summoning = {
		name = "The Divine Summoning",
		subtitle = "Featured: Dark",
		featured = "dark_variant",
		featuredRate = 0.5,
		pool = "standard",
	},
}
GachaConfig.DefaultBanner = "divine_summoning"

-- ── Duplicates: nothing is ever worthless ─────────────────────────────────────
GachaConfig.Duplicates = {
	-- Normal characters: every copy after the first becomes Soul Shards.
	characterShards = { Common = 5, Rare = 10, Epic = 25, Legendary = 60, Mythic = 120 },
	-- Soul Shards refine into Souls (talent points) at this ratio.
	shardsPerSoul = 10,
	-- VFX variants (cosmetic): every copy after the first becomes Soul Shards.
	variantShards = { Epic = 30, Legendary = 80, Mythic = 160 },
	-- Relics: copies raise the relic's level up to the max, then give Relic Dust.
	maxRelicLevel = 5,
	relicOverflowDust = { Common = 5, Rare = 12, Epic = 30, Legendary = 80 },
	-- Cosmetics: owned copies become Relic Dust.
	cosmeticDust = { Rare = 15, Epic = 40, Legendary = 100 },
}

-- ── Daily wish: one free single summon per day (resets at 00:00 UTC) ───────
GachaConfig.DailyFree = { enabled = true, pulls = 1 }

-- ── Starlight (spark): every summon on a banner earns Starlight there; spend
-- it on any Epic-or-better reward of that banner you don't own yet. ───────────
GachaConfig.Spark = { perPull = 1, cost = 90, minRarity = "Epic" }

-- ── Lobby flex: summons of this rarity or better are announced server-wide ──
GachaConfig.AnnounceRarity = "Legendary"

-- ── Equipment ────────────────────────────────────────────────────────────────
GachaConfig.RelicSlots = 3
GachaConfig.RelicLevelBonus = 0.25 -- each relic level above 1 adds +25% of its base effect

-- ── Earning tickets through gameplay ─────────────────────────────────────────
GachaConfig.TicketRewards = {
	bossKill = 1,
	killsPerTicket = 60, -- every N kills
}

-- ── Shop: rewards bought directly (not random) ───────────────────────────────
-- price: currency → amount; each listed currency is a way to pay. Items you
-- already own can't be bought again.
GachaConfig.ShopItems = {
	{ id = "dark_variant", price = { crystals = 6000, relicDust = 1500 } },
}

-- ── Premium crystal products (Developer Products) ────────────────────────────
-- Fill productId with real Developer Product ids to enable purchases; a 0 id
-- hides that product from the shop.
GachaConfig.CrystalProducts = {
	{ id = "crystals_small", productId = 0, crystals = 300, label = "300 Crystals" },
	{ id = "crystals_medium", productId = 0, crystals = 1650, label = "1,650 Crystals" },
	{ id = "crystals_large", productId = 0, crystals = 3400, label = "3,400 Crystals" },
}

-- ── Cinematic length per rarity (seconds, excluding the reveal card) ─────────
GachaConfig.CinematicLength = { Common = 2.5, Rare = 3.5, Epic = 6, Legendary = 10, Mythic = 12 }

return GachaConfig
