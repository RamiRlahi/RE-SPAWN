--!strict
--[[
	GachaConfig
	Every economic value for the summon system lives here — costs, odds, pity,
	banners, duplicate conversions, Pull Ticket drops and Robux products.
	Nothing else in the project hardcodes these numbers. The reasoning behind
	them is in docs/gacha-economy.md.

	Pull Tickets are the only summoning currency: 1 ticket = 1 summon on any
	banner. They drop from kills (TicketDrops) and are sold for Robux
	(TicketProducts). There is no other paid currency.

	ODDS DISCLOSURE: the in-game "Rates & Pity" panel is generated from this
	module, so what players see is always exactly what the server rolls.
--]]

local GachaConfig = {}

-- ── Development switch ────────────────────────────────────────────────────────
-- While true, summons cost nothing (pity and results still behave normally).
-- Set to false to charge Pull Tickets as configured below.
GachaConfig.FREE_SUMMONS = false

-- ── Currencies ────────────────────────────────────────────────────────────────
-- tickets     : Pull Tickets. Dropped by mobs, sold for Robux. 1 ticket = 1 pull.
-- soulEssence : from duplicate classes and the altar's commons; spent in the
--               Essence Shop (classes, cosmetics). Never buys tickets.
GachaConfig.Currencies = {
	tickets = { name = "Pull Ticket", glyph = "TICKETS" },
	soulEssence = { name = "Soul Essence", glyph = "ESSENCE" },
	soulShards = { name = "Soul Shard", glyph = "SHARDS" },
	relicDust = { name = "Relic Dust", glyph = "DUST" },
}

GachaConfig.Cost = {
	single = { tickets = 1, count = 1 },
	multi = { tickets = 10, count = 10 },  -- at least one Rare+ (Pity.multiGuarantee)
	big = { tickets = 25, count = 25 },    -- at least one Epic+ (Pity.bigGuarantee)
}

-- Starting balances for brand-new profiles.
GachaConfig.StartingCurrencies = { tickets = 3 }

-- Old saves: crystals (removed) become Pull Tickets at their old summon price
-- (rounded up).
GachaConfig.CrystalsPerTicket = 300
-- Old saves: a one-time gift of tickets when classes became locked.
GachaConfig.LockGiftTickets = 10

-- ── Rarities & base odds (must sum to 100) ───────────────────────────────────
GachaConfig.RarityOrder = { "Common", "Rare", "Epic", "Legendary", "Mythic" }
GachaConfig.Rarities = {
	Common    = { odds = 59.5, color = Color3.fromRGB(190, 195, 205) },
	Rare      = { odds = 28.0, color = Color3.fromRGB(90, 170, 255) },
	Epic      = { odds = 9.0,  color = Color3.fromRGB(190, 95, 255) },
	Legendary = { odds = 3.0,  color = Color3.fromRGB(255, 200, 70) },
	Mythic    = { odds = 0.5,  color = Color3.fromRGB(255, 70, 120) },
}

-- ── Pity (per banner, carried between sessions) ──────────────────────────────
GachaConfig.Pity = {
	epicEvery = 10,          -- guaranteed Epic or better within every 10 pulls
	legendarySoftStart = 55, -- from this pull, Legendary odds rise…
	legendarySoftStep = 6.0, -- …by this many % per pull
	legendaryHard = 70,      -- guaranteed Legendary or better on this pull
	multiGuarantee = "Rare", -- every 10-pull contains at least one of this rarity or better
	bigGuarantee = "Epic",   -- every 25-pull contains at least one of this rarity or better
	-- mythicHard (per banner, optional): guaranteed Mythic on this pull without one
}

-- ── Banners ───────────────────────────────────────────────────────────────────
-- featured: rate-up reward id (or featuredRotation: one per week, FeaturedFor).
-- When a reward of featuredRarity (default Legendary) is rolled, featuredRate
-- is the chance it's the featured one; losing that guarantees it next time.
-- odds / pity / spark (optional) replace the base values for that banner only
-- (pity keys left out keep the base value). Each banner keeps its own pity
-- counters, so pulling on one never spends another's.
GachaConfig.Banners = {
	-- The class banner: every class except the five starters.
	altar_of_souls = {
		name = "Altar of Souls",
		subtitle = "Unlock new classes",
		featuredRotation = { "class_heavy_knight", "class_berserker", "class_martial_artist" },
		featuredRarity = "Epic",
		featuredRate = 0.5,
		pool = "classes",
		odds = { Common = 60.0, Rare = 27.0, Epic = 9.4, Legendary = 3.0, Mythic = 0.6 },
		pity = {
			epicEvery = 10,
			legendarySoftStart = 60,
			legendarySoftStep = 6.0,
			legendaryHard = 75,
			mythicHard = 150,
			multiGuarantee = "Rare",
			bigGuarantee = "Epic",
		},
		spark = { perPull = 1, cost = 100, minRarity = "Rare" },
	},
	divine_summoning = {
		name = "The Divine Summoning",
		subtitle = "Featured: Celestial Wings",
		featured = "wings_celestial",
		featuredRate = 0.5,
		pool = "standard",
	},
	beastmaster_call = {
		name = "Beastmaster's Call",
		subtitle = "Featured: Void Serpent & Infernal Dragon",
		featured = "mount_infernal_dragon",
		featuredRate = 0.5,
		pool = "mounts",
		-- Mounts are rare: the only banner that has them, at much lower odds,
		-- with a longer (but always reached) pity.
		odds = { Common = 74.0, Rare = 21.0, Epic = 4.0, Legendary = 0.8, Mythic = 0.2 },
		pity = {
			epicEvery = 25,
			legendarySoftStart = 70,
			legendarySoftStep = 5.0,
			legendaryHard = 90,
			multiGuarantee = "Rare",
		},
	},
}
GachaConfig.DefaultBanner = "altar_of_souls"
-- The order the banner tabs appear on the summon page.
GachaConfig.BannerOrder = { "altar_of_souls", "divine_summoning", "beastmaster_call" }

-- ── Duplicates: nothing is ever worthless ─────────────────────────────────────
GachaConfig.Duplicates = {
	-- Classes: every copy after the first becomes Soul Essence.
	classEssence = { Rare = 40, Epic = 100, Legendary = 250, Mythic = 600 },
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
-- it on any reward of minRarity or better of that banner you don't own yet. ──
GachaConfig.Spark = { perPull = 1, cost = 90, minRarity = "Epic" }

-- ── Lobby flex: summons of this rarity or better are announced server-wide ──
GachaConfig.AnnounceRarity = "Legendary"

-- ── Equipment ────────────────────────────────────────────────────────────────
GachaConfig.RelicSlots = 3
GachaConfig.RelicLevelBonus = 0.25 -- each relic level above 1 adds +25% of its base effect

-- ── Pull Ticket drops ─────────────────────────────────────────────────────────
-- Every kill rolls once per player who gets credit for it (within 120 studs),
-- independently, by the mob's tier. Collected straight into the inventory.
-- Summoned minions (boss adds, risen dead, horde spawns) and tutorial runs
-- never drop. hourlyCap: drops per player per rolling hour (anti-farm).
GachaConfig.TicketDrops = {
	normal = 0.0025,   -- 1 in 400
	elite = 0.006,     -- 1 in ~167
	miniboss = 0.05,   -- Forgotten Isle Behemoths: 1 in 20
	boss = 0.15,       -- floor bosses and isle bosses: 1 in ~7
	hourlyCap = 15,
}

-- ── Shop: rewards bought directly (not random) ───────────────────────────────
-- price: currency → amount; each listed currency is a way to pay. Items you
-- already own can't be bought again.
GachaConfig.ShopItems = {
	{ id = "dark_variant", price = { soulEssence = 1500, relicDust = 1500 } },
	-- (the Essence Shop's long-term sink: every class armor, also a summon reward)
	{ id = "armor_heavy_knight", price = { soulEssence = 600 } },
	{ id = "armor_ranger", price = { soulEssence = 600 } },
	{ id = "armor_cleric", price = { soulEssence = 600 } },
	{ id = "armor_ice_mage", price = { soulEssence = 600 } },
	{ id = "armor_gunslinger", price = { soulEssence = 600 } },
	{ id = "armor_swordsman", price = { soulEssence = 600 } },
	{ id = "armor_rogue", price = { soulEssence = 600 } },
	{ id = "armor_mage", price = { soulEssence = 600 } },
	{ id = "armor_martial_artist", price = { soulEssence = 600 } },
	{ id = "armor_berserker", price = { soulEssence = 600 } },
	{ id = "armor_death_knight", price = { soulEssence = 600 } },
}

-- ── Direct class unlocks (not random) ────────────────────────────────────────
-- Soul Essence price by rarity: the bad-luck backstop, deliberately dearer
-- than the expected pulls. ClassProducts: a Developer Product per class
-- (productId 0 hides it). Mythic classes are never sold for Robux.
GachaConfig.ClassEssencePrice = { Rare = 350, Epic = 900, Legendary = 2000, Mythic = 4000 }
GachaConfig.ClassProducts = {
	{ classId = "ice_mage", productId = 0, robux = 199 },
	{ classId = "gunslinger", productId = 0, robux = 199 },
	{ classId = "heavy_knight", productId = 0, robux = 499 },
	{ classId = "berserker", productId = 0, robux = 499 },
	{ classId = "martial_artist", productId = 0, robux = 499 },
	{ classId = "summoner", productId = 0, robux = 999 },
}

-- ── Pull Ticket packs (Developer Products) ───────────────────────────────────
-- Fill productId with real Developer Product ids (Creator Hub → Monetization
-- → Developer Products, priced as `robux`) to enable a pack; a 0 id hides it.
GachaConfig.TicketProducts = {
	{ id = "tickets_1", productId = 0, tickets = 1, robux = 25, label = "1 Pull Ticket" },
	{ id = "tickets_5", productId = 0, tickets = 5, robux = 119, label = "5 Pull Tickets" },
	{ id = "tickets_10", productId = 0, tickets = 10, robux = 225, label = "10 Pull Tickets" },
	{ id = "tickets_25", productId = 0, tickets = 25, robux = 525, label = "25 Pull Tickets" },
	{ id = "tickets_50", productId = 0, tickets = 50, robux = 999, label = "50 Pull Tickets" },
	{ id = "tickets_100", productId = 0, tickets = 100, robux = 1799, label = "100 Pull Tickets" },
}

-- ── Altar milestones: lifetime Altar of Souls summons → Soul Essence ───────
GachaConfig.AltarBanner = "altar_of_souls"
GachaConfig.AltarMilestones = {
	{ at = 25, soulEssence = 100 },
	{ at = 50, soulEssence = 200 },
	{ at = 100, soulEssence = 400 },
	{ at = 200, soulEssence = 800 },
}

-- Summons kept in each player's history (newest last).
GachaConfig.HistoryLength = 50

-- ── Cinematic length per rarity (seconds, excluding the reveal card) ─────────
GachaConfig.CinematicLength = { Common = 2.5, Rare = 3.5, Epic = 6, Legendary = 10, Mythic = 12 }

-- The odds a banner rolls with (its own, else the base ones).
function GachaConfig.OddsFor(bannerId: string?): { [string]: number }
	local b = bannerId and GachaConfig.Banners[bannerId]
	local out = {}
	for r, info in pairs(GachaConfig.Rarities) do
		out[r] = (b and b.odds and b.odds[r]) or info.odds
	end
	return out
end

-- The pity rules a banner uses (its own, else the base ones).
function GachaConfig.PityFor(bannerId: string?): { [string]: any }
	local b = bannerId and GachaConfig.Banners[bannerId]
	local out = table.clone(GachaConfig.Pity)
	if b and b.pity then
		for k, v in pairs(b.pity) do out[k] = v end
	end
	return out
end

-- A banner's Starlight rules (its own, else the base ones).
function GachaConfig.SparkFor(bannerId: string?): { perPull: number, cost: number, minRarity: string }
	local b = bannerId and GachaConfig.Banners[bannerId]
	return (b and b.spark) or GachaConfig.Spark
end

-- A banner's featured reward id right now: one of its featuredRotation, a
-- new one every Monday 00:00 UTC, else its fixed `featured`.
local WEEK, MONDAY = 604800, 345600 -- (1970-01-05 00:00 UTC was a Monday)
function GachaConfig.FeaturedFor(bannerId: string?, now: number?): string?
	local b = bannerId and GachaConfig.Banners[bannerId]
	if not b then return nil end
	if b.featuredRotation and #b.featuredRotation > 0 then
		local week = math.floor(((now or os.time()) - MONDAY) / WEEK)
		return b.featuredRotation[(week % #b.featuredRotation) + 1]
	end
	return b.featured
end

-- Seconds until the featured rewards rotate.
function GachaConfig.RotationIn(now: number?): number
	return WEEK - ((now or os.time()) - MONDAY) % WEEK
end

return GachaConfig
