--[[
	GachaManager.luau
	Server-authoritative summons, class unlocks, collection and Robux products.
	The economy's numbers live in GachaConfig; the reasoning is in
	docs/gacha-economy.md.

	Classes: a profile owns its classes (p.classes). New profiles own the five
	starters (ClassData.Starter); the rest come from the Altar of Souls (a
	"class" reward), the Essence Shop or a Robux unlock, and are kept for good.
	The owned list is mirrored on the player as "OwnedClasses" (",id,id,"),
	which ClassManager checks before a class can be picked or entered.

	Pull Tickets are the only summoning currency. Kills drop them
	(OnMobKilled, by tier: GachaConfig.TicketDrops); Robux buys them
	(TicketProducts). Duplicate classes become Soul Essence.

	Pull (per pull, per banner pity):
	  1. Mythic is rolled first at its base odds.
	  2. Legendary odds rise each pull from the soft-pity start; hard pity
	     guarantees Legendary+.
	  3. Otherwise Common / Rare / Epic by base odds — forced to Epic if the
	     "Epic every N pulls" pity is due.
	  4. A Legendary is the banner's featured reward featuredRate of the time;
	     losing that guarantees the featured one on the next Legendary.
	  5. A 10-pull always contains at least one Rare-or-better.

	Duplicates never waste: classes → Soul Essence; characters, VFX variants
	and armor → Soul Shards; relics → levels (then Relic Dust); cosmetics →
	Relic Dust.

	Around the pulls:
	  • Daily wish: one free single summon per UTC day ({ free = true }).
	  • Starlight: every summon on a banner adds GachaConfig.Spark.perPull to
	    that banner's pity.starlight; at Spark.cost it buys any unowned
	    Epic-or-better reward of the banner ({ kind = "spark", id }). The
	    exchange is sent back like a summon, so it gets the wish reveal.
	  • Sets (GachaRewards.Sets): completing one pays its bonus once.
	  • Summons of GachaConfig.AnnounceRarity or better are announced to
	    everyone in the server (SummonAnnounce).

	Premium: ticket packs and class unlocks are Developer Products, granted
	idempotently in ProcessReceipt (saved before PurchaseGranted). Ticket packs
	can't be bought by players whose PolicyService marks paid random items as
	restricted; earned tickets and direct (non-random) unlocks still work.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local MarketplaceService = game:GetService("MarketplaceService")
local PolicyService = game:GetService("PolicyService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))
local GachaConfig = require(Shared:WaitForChild("GachaConfig"))
local GachaRewards = require(Shared:WaitForChild("GachaRewards"))
local ClassData = require(Shared:WaitForChild("ClassData"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local TalentManager = require(script.Parent:WaitForChild("TalentManager"))

local GachaManager = {}

local rng = Random.new()
local announce: (Player, { any }) -> ()
local addHistory: (any, any, string) -> ()
local restricted: { [Player]: boolean } = {}
local busy: { [Player]: boolean } = {}

-- ─── State sync ─────────────────────────────────────────────────────────────
local function pityFor(p: any, bannerId: string)
	local pity = p.pity[bannerId]
	if not pity then
		pity = { sinceEpic = 0, sinceLegendary = 0, sinceMythic = 0, guaranteedFeatured = false, starlight = 0 }
		p.pity[bannerId] = pity
	end
	pity.starlight = pity.starlight or 0
	pity.sinceMythic = pity.sinceMythic or 0
	return pity
end

-- ─── Daily wish ──────────────────────────────────────────────────────────────
local function today(): number
	return math.floor(os.time() / 86400)
end
local function freeAvailable(p: any): boolean
	return GachaConfig.DailyFree.enabled and (p.stats.lastFreeDay or -1) < today()
end

-- ─── Ownership & sets ────────────────────────────────────────────────────────
local function owns(p: any, r: any): boolean
	if r.type == "class" then return p.classes[r.classId] == true end
	if r.type == "character" or r.type == "variant" then return p.collection.characters[r.id] ~= nil end
	if r.type == "relic" then return p.collection.relics[r.id] ~= nil end
	if r.type == "cosmetic" or r.type == "armor" or r.type == "wings" or r.type == "mount" then return p.collection.cosmetics[r.id] == true end
	return false
end

-- Sets newly completed by what the player now owns: their bonus is paid once.
local function checkSets(p: any): { string }
	local done = {}
	for _, set in ipairs(GachaRewards.Sets) do
		if not p.stats[`set:{set.id}`] and #set.items > 0 then
			local all = true
			for _, id in ipairs(set.items) do
				local r = GachaRewards.Get(id)
				if not r or not owns(p, r) then
					all = false
					break
				end
			end
			if all then
				p.stats[`set:{set.id}`] = 1
				for currency, amount in pairs(set.bonus) do
					p.currencies[currency] = (p.currencies[currency] or 0) + amount
				end
				table.insert(done, set.id)
			end
		end
	end
	return done
end

-- Clients recolour a player's ability VFX from this attribute (VariantFX).
local function refreshVariantAttribute(player: Player)
	local classId = player:GetAttribute("SelectedClass")
	local id = if typeof(classId) == "string" then GachaManager.GetVariant(player, classId) else nil
	player:SetAttribute("Variant", id)
end

-- Armor_<classId> = true while that class's armor is owned and equipped; the
-- server dresses characters from it and the class-select preview reads it.
local function refreshArmorAttributes(player: Player, p: any)
	for _, classId in ipairs(ClassData.Order) do
		local id = p.equipped.armor[classId]
		local r = id and GachaRewards.Get(id)
		local worn = GachaRewards.BuiltInArmor[classId] == true
			or (r ~= nil and r.type == "armor" and p.collection.cosmetics[id] == true)
		player:SetAttribute(`Armor_{classId}`, if worn then true else nil)
	end
end

-- Wings / Mount = the equipped id while owned; every client builds them on
-- that player's character (WingsMounts), and MountManager rides the mount.
local function refreshRideAttributes(player: Player, p: any)
	for _, kind in ipairs({ "wings", "mount" }) do
		local id = p.equipped[kind]
		local r = id and GachaRewards.Get(id)
		local ok = r ~= nil and r.type == kind and p.collection.cosmetics[id] == true
		player:SetAttribute(if kind == "wings" then "Wings" else "Mount", if ok then id else nil)
	end
end

-- "OwnedClasses" = ",id,id," (ClassData.IsOwnedBy reads it on both sides).
local function refreshClassAttribute(player: Player, p: any)
	local ids = {}
	for _, classId in ipairs(ClassData.Order) do
		if p.classes[classId] then table.insert(ids, classId) end
	end
	player:SetAttribute("OwnedClasses", "," .. table.concat(ids, ",") .. ",")
end

local function classReward(classId: string): any
	for _, r in ipairs(GachaRewards.All) do
		if r.type == "class" and r.classId == classId then return r end
	end
	return nil
end

local function sync(player: Player)
	local p = PlayerData.Get(player)
	if not p then return end
	refreshVariantAttribute(player)
	refreshArmorAttributes(player, p)
	refreshRideAttributes(player, p)
	refreshClassAttribute(player, p)
	player:SetAttribute("Tickets", p.currencies.tickets or 0)
	local setsDone = {}
	for _, set in ipairs(GachaRewards.Sets) do
		if p.stats[`set:{set.id}`] then setsDone[set.id] = true end
	end
	local products = {}
	for _, prod in ipairs(GachaConfig.TicketProducts) do
		if prod.productId and prod.productId > 0 then
			table.insert(products, { id = prod.id, label = prod.label, tickets = prod.tickets, robux = prod.robux })
		end
	end
	local classProducts = {}
	for _, prod in ipairs(GachaConfig.ClassProducts) do
		if prod.productId and prod.productId > 0 then classProducts[prod.classId] = prod.robux end
	end
	Network.GetRemoteEvent(Network.Remotes.GachaState):FireClient(player, {
		currencies = p.currencies,
		collection = p.collection,
		equipped = p.equipped,
		pity = pityFor(p, GachaConfig.DefaultBanner),
		-- every banner's own pity (the summon page's banner tabs)
		pityAll = (function()
			local all = {}
			for id in pairs(GachaConfig.Banners) do all[id] = pityFor(p, id) end
			return all
		end)(),
		freeAvailable = freeAvailable(p),
		nextFreeIn = (today() + 1) * 86400 - os.time(),
		setsDone = setsDone,
		paidRestricted = restricted[player] == true,
		products = products,
		classes = p.classes,
		classProducts = classProducts,
		history = p.history,
		altarPulls = p.stats.altarPulls or 0,
	})
end
GachaManager.Sync = sync

local function addCurrency(p: any, currency: string, amount: number)
	p.currencies[currency] = (p.currencies[currency] or 0) + amount
end

-- ─── Rolling ────────────────────────────────────────────────────────────────
local function weightedPick(list: { any }): any
	local total = 0
	for _, r in ipairs(list) do total += (r.weight or 1) end
	local x = rng:NextNumber() * total
	for _, r in ipairs(list) do
		x -= (r.weight or 1)
		if x <= 0 then return r end
	end
	return list[#list]
end

local function rollRarity(pity: any, bannerId: string): string
	local odds = GachaConfig.OddsFor(bannerId)
	local P = GachaConfig.PityFor(bannerId)
	if P.mythicHard and pity.sinceMythic >= P.mythicHard then return "Mythic" end
	if rng:NextNumber() * 100 < odds.Mythic then return "Mythic" end
	if pity.sinceLegendary >= P.legendaryHard then return "Legendary" end
	local legendary = odds.Legendary
	if pity.sinceLegendary >= P.legendarySoftStart then
		legendary += (pity.sinceLegendary - P.legendarySoftStart + 1) * P.legendarySoftStep
	end
	if rng:NextNumber() * 100 < legendary then return "Legendary" end
	if pity.sinceEpic >= P.epicEvery then return "Epic" end
	local lower = odds.Common + odds.Rare + odds.Epic
	local x = rng:NextNumber() * lower
	if x < odds.Epic then return "Epic" end
	if x < odds.Epic + odds.Rare then return "Rare" end
	return "Common"
end

local function pickReward(bannerId: string, banner: any, rarity: string, pity: any): any
	local list = GachaRewards.InPoolByRarity(banner.pool, rarity)
	local featuredId = GachaConfig.FeaturedFor(bannerId)
	if featuredId and rarity == (banner.featuredRarity or "Legendary") then
		local featured = GachaRewards.Get(featuredId)
		local others = {}
		for _, r in ipairs(list) do
			if r.id ~= featuredId then table.insert(others, r) end
		end
		if featured and (pity.guaranteedFeatured or #others == 0 or rng:NextNumber() < banner.featuredRate) then
			pity.guaranteedFeatured = false
			return featured
		end
		pity.guaranteedFeatured = true
		return weightedPick(others)
	end
	if #list == 0 then
		list = GachaRewards.InPoolByRarity(banner.pool, "Common")
	end
	return weightedPick(list)
end

local function rarityIndex(r: string): number
	return table.find(GachaConfig.RarityOrder, r) or 1
end

-- ─── Granting (duplicates always convert into something useful) ─────────────
local function grant(p: any, reward: any): (boolean, string)
	local D = GachaConfig.Duplicates
	if reward.type == "class" then
		if not p.classes[reward.classId] then
			p.classes[reward.classId] = true
			return true, "NEW CLASS UNLOCKED"
		end
		local essence = D.classEssence[reward.rarity] or 40
		addCurrency(p, "soulEssence", essence)
		return false, `+{essence} Soul Essence`
	elseif reward.type == "character" then
		local c = p.collection.characters[reward.id]
		if not c then
			p.collection.characters[reward.id] = { copies = 1, ascension = 0 }
			return true, "Awakened!"
		end
		c.copies += 1
		local shards = D.characterShards[reward.rarity] or 5
		addCurrency(p, "soulShards", shards)
		return false, `+{shards} Soul Shards`
	elseif reward.type == "variant" then
		-- Stored with the characters (older saves keep working).
		local c = p.collection.characters[reward.id]
		if not c then
			p.collection.characters[reward.id] = { copies = 1, ascension = 0 }
			return true, "NEW VFX VARIANT"
		end
		c.copies += 1
		local shards = D.variantShards[reward.rarity] or 30
		addCurrency(p, "soulShards", shards)
		return false, `+{shards} Soul Shards`
	elseif reward.type == "armor" then
		-- Stored with the titles; the first copy is put on straight away.
		if not p.collection.cosmetics[reward.id] then
			p.collection.cosmetics[reward.id] = true
			if reward.classId then p.equipped.armor[reward.classId] = reward.id end
			return true, "NEW ARMOR"
		end
		local shards = D.characterShards[reward.rarity] or 25
		addCurrency(p, "soulShards", shards)
		return false, `+{shards} Soul Shards`
	elseif reward.type == "relic" then
		local r = p.collection.relics[reward.id]
		if not r then
			p.collection.relics[reward.id] = { level = 1 }
			return true, "NEW RELIC"
		end
		if r.level < D.maxRelicLevel then
			r.level += 1
			return false, `Relic Level {r.level}`
		end
		local dust = D.relicOverflowDust[reward.rarity] or 5
		addCurrency(p, "relicDust", dust)
		return false, `+{dust} Relic Dust`
	elseif reward.type == "material" then
		addCurrency(p, reward.currency, reward.amount or 1)
		return false, `+{reward.amount or 1} {GachaConfig.Currencies[reward.currency] and GachaConfig.Currencies[reward.currency].name or reward.currency}`
	elseif reward.type == "wings" or reward.type == "mount" then
		-- The first copy is worn straight away if nothing of its kind is.
		if not p.collection.cosmetics[reward.id] then
			p.collection.cosmetics[reward.id] = true
			if not p.equipped[reward.type] then p.equipped[reward.type] = reward.id end
			return true, if reward.type == "wings" then "NEW WINGS" else "NEW MOUNT"
		end
		local shards = D.characterShards[reward.rarity] or 10
		addCurrency(p, "soulShards", shards)
		return false, `+{shards} Soul Shards`
	elseif reward.type == "cosmetic" then
		if not p.collection.cosmetics[reward.id] then
			p.collection.cosmetics[reward.id] = true
			return true, "NEW TITLE"
		end
		local dust = D.cosmeticDust[reward.rarity] or 10
		addCurrency(p, "relicDust", dust)
		return false, `+{dust} Relic Dust`
	end
	return false, ""
end

-- The last HistoryLength summons (the summon page's History).
addHistory = function(p: any, reward: any, bannerId: string)
	table.insert(p.history, { id = reward.id, rarity = reward.rarity, banner = bannerId, time = os.time() })
	while #p.history > GachaConfig.HistoryLength do table.remove(p.history, 1) end
end

-- ─── Lobby flex: everyone hears about a Legendary ──────────────────────────
announce = function(player: Player, results: { any })
	local top
	for _, res in ipairs(results) do
		if rarityIndex(res.rarity) >= rarityIndex(GachaConfig.AnnounceRarity)
			and (not top or rarityIndex(res.rarity) > rarityIndex(top.rarity)) then
			top = res
		end
	end
	if not top then return end
	Network.GetRemoteEvent(Network.Remotes.SummonAnnounce):FireAllClients({
		userId = player.UserId, name = player.DisplayName, id = top.id, rarity = top.rarity,
	})
end

-- ─── Summon ─────────────────────────────────────────────────────────────────
local function summon(player: Player, payload: any)
	if busy[player] then return end
	local p = PlayerData.Get(player)
	if not p or typeof(payload) ~= "table" then return end
	local bannerId = typeof(payload.banner) == "string" and payload.banner or GachaConfig.DefaultBanner
	local banner = GachaConfig.Banners[bannerId]
	if not banner then return end
	local free = payload.free == true
	local cost = GachaConfig.Cost.single
	if not free and payload.count == GachaConfig.Cost.multi.count then cost = GachaConfig.Cost.multi end
	if not free and payload.count == GachaConfig.Cost.big.count then cost = GachaConfig.Cost.big end
	local count = cost.count

	if free then
		-- The daily wish: one free single summon a day.
		if not freeAvailable(p) then
			Network.GetRemoteEvent(Network.Remotes.SummonResult):FireClient(player, { error = "Your daily wish is spent. A new one rises at midnight (UTC)." })
			return
		end
		p.stats.lastFreeDay = today()
	elseif not GachaConfig.FREE_SUMMONS then
		-- Payment: Pull Tickets only (skipped entirely while FREE_SUMMONS is on).
		local price = cost.tickets
		local have = p.currencies.tickets or 0
		if have < price then
			Network.GetRemoteEvent(Network.Remotes.SummonResult):FireClient(player, { error = `Not enough Pull Tickets ({have}/{price})` })
			return
		end
		p.currencies.tickets = have - price
	end

	busy[player] = true
	local pity = pityFor(p, bannerId)
	local P = GachaConfig.PityFor(bannerId)
	local spark = GachaConfig.SparkFor(bannerId)
	-- ×10 / ×25: the last pull is at least this rarity if none was before it.
	local guarantee = if count == GachaConfig.Cost.big.count then P.bigGuarantee
		elseif count == GachaConfig.Cost.multi.count then P.multiGuarantee else nil
	local results = {}
	local best = "Common"
	for i = 1, count do
		pity.sinceEpic += 1
		pity.sinceLegendary += 1
		pity.sinceMythic += 1
		pity.starlight += spark.perPull
		local rarity = rollRarity(pity, bannerId)
		if guarantee and i == count then
			local gotGuarantee = false
			for _, r in ipairs(results) do
				if rarityIndex(r.rarity) >= rarityIndex(guarantee) then gotGuarantee = true end
			end
			if not gotGuarantee and rarityIndex(rarity) < rarityIndex(guarantee) then
				rarity = guarantee
			end
		end
		if rarityIndex(rarity) >= rarityIndex("Epic") then pity.sinceEpic = 0 end
		if rarityIndex(rarity) >= rarityIndex("Legendary") then pity.sinceLegendary = 0 end
		if rarity == "Mythic" then pity.sinceMythic = 0 end
		local reward = pickReward(bannerId, banner, rarity, pity)
		local isNew, note = grant(p, reward)
		if rarityIndex(reward.rarity) > rarityIndex(best) then best = reward.rarity end
		table.insert(results, { id = reward.id, rarity = reward.rarity, isNew = isNew, note = note })
		addHistory(p, reward, bannerId)
	end
	p.stats.pulls = (p.stats.pulls or 0) + count
	if bannerId == GachaConfig.AltarBanner then
		local before = p.stats.altarPulls or 0
		p.stats.altarPulls = before + count
		for _, m in ipairs(GachaConfig.AltarMilestones) do
			if before < m.at and p.stats.altarPulls >= m.at then
				addCurrency(p, "soulEssence", m.soulEssence)
				table.insert(results, { id = "essence_wisp", rarity = "Common", isNew = false,
					note = `{m.at} SUMMONS: +{m.soulEssence} Soul Essence` })
			end
		end
	end
	local sets = checkSets(p)
	PlayerData.MarkDirty(player)
	sync(player)
	Network.GetRemoteEvent(Network.Remotes.SummonResult):FireClient(player, { results = results, best = best, sets = sets })
	busy[player] = false
	announce(player, results)
end

-- ─── Collection actions ─────────────────────────────────────────────────────
local function action(player: Player, payload: any)
	local p = PlayerData.Get(player)
	if not p or typeof(payload) ~= "table" then return end
	local kind = payload.kind
	if kind == "equipRelic" and typeof(payload.id) == "string" and p.collection.relics[payload.id] then
		local slots = p.equipped.relics
		if not table.find(slots, payload.id) then
			if #slots >= GachaConfig.RelicSlots then table.remove(slots, 1) end
			table.insert(slots, payload.id)
		end
	elseif kind == "unequipRelic" and typeof(payload.id) == "string" then
		local i = table.find(p.equipped.relics, payload.id)
		if i then table.remove(p.equipped.relics, i) end
	elseif kind == "equipVariant" and typeof(payload.classId) == "string" then
		local id = payload.id
		if id == nil then
			p.equipped.variants[payload.classId] = nil
		elseif typeof(id) == "string" and ClassData.GetClass(payload.classId) then
			local r = GachaRewards.Get(id)
			-- Class-bound variants fit their class; universal ones (no classId) fit any.
			if r and r.type == "variant" and (r.classId == nil or r.classId == payload.classId) and p.collection.characters[id] then
				p.equipped.variants[payload.classId] = id
			end
		end
	elseif kind == "equipArmor" and typeof(payload.classId) == "string" and ClassData.GetClass(payload.classId) then
		local id = payload.id
		if id == nil then
			p.equipped.armor[payload.classId] = nil
		elseif typeof(id) == "string" then
			local r = GachaRewards.Get(id)
			if r and r.type == "armor" and r.classId == payload.classId and p.collection.cosmetics[id] then
				p.equipped.armor[payload.classId] = id
			end
		end
	elseif (kind == "equipWings" or kind == "equipMount") then
		local slot = if kind == "equipWings" then "wings" else "mount"
		local id = payload.id
		if id == nil then
			p.equipped[slot] = nil
		elseif typeof(id) == "string" then
			local r = GachaRewards.Get(id)
			if r and r.type == slot and p.collection.cosmetics[id] then
				p.equipped[slot] = id
			end
		end
	elseif kind == "refineShards" then
		local per = GachaConfig.Duplicates.shardsPerSoul
		local souls = math.floor((p.currencies.soulShards or 0) / per)
		if souls > 0 then
			p.currencies.soulShards -= souls * per
			TalentManager.AwardSouls(player, souls)
		end
	elseif kind == "buyShopItem" and typeof(payload.id) == "string" and typeof(payload.pay) == "string" then
		local item
		for _, it in ipairs(GachaConfig.ShopItems) do
			if it.id == payload.id then item = it end
		end
		local reward = item and GachaRewards.Get(item.id)
		local price = item and item.price[payload.pay]
		if not (reward and price) then return end
		local function fail(message: string)
			Network.GetRemoteEvent(Network.Remotes.SummonResult):FireClient(player, { error = message })
		end
		if owns(p, reward) then
			return fail(`You already own {reward.name}.`)
		end
		if (p.currencies[payload.pay] or 0) < price then
			return fail(`Not enough {GachaConfig.Currencies[payload.pay].name}`)
		end
		p.currencies[payload.pay] -= price
		grant(p, reward)
		checkSets(p)
	elseif kind == "spark" and typeof(payload.id) == "string" then
		-- Starlight exchange: the reward you choose, sent back like a summon.
		local bannerId = typeof(payload.banner) == "string" and payload.banner or GachaConfig.DefaultBanner
		local banner = GachaConfig.Banners[bannerId]
		local reward = GachaRewards.Get(payload.id)
		local function fail(message: string)
			Network.GetRemoteEvent(Network.Remotes.SummonResult):FireClient(player, { error = message })
		end
		if not banner or not reward or busy[player] then return end
		local spark = GachaConfig.SparkFor(bannerId)
		if not table.find(GachaRewards.Pool(banner.pool), reward.id) or reward.type == "material"
			or rarityIndex(reward.rarity) < rarityIndex(spark.minRarity) then
			return fail("That can't be bought with Starlight.")
		end
		if owns(p, reward) then return fail(`You already own {reward.name}.`) end
		local pity = pityFor(p, bannerId)
		if pity.starlight < spark.cost then
			return fail(`Not enough Starlight ({pity.starlight}/{spark.cost}).`)
		end
		pity.starlight -= spark.cost
		local isNew, note = grant(p, reward)
		addHistory(p, reward, bannerId)
		local sets = checkSets(p)
		PlayerData.MarkDirty(player)
		sync(player)
		local results = { { id = reward.id, rarity = reward.rarity, isNew = isNew, note = note } }
		Network.GetRemoteEvent(Network.Remotes.SummonResult):FireClient(player, { results = results, best = reward.rarity, sets = sets, spark = true })
		announce(player, results)
		return
	elseif kind == "buyTickets" and typeof(payload.id) == "string" then
		-- (tickets only buy random rewards: not where those are restricted)
		if restricted[player] then
			Network.GetRemoteEvent(Network.Remotes.SummonResult):FireClient(player, { error = "Pull Ticket packs aren't available in your region. Tickets from kills still work." })
			return
		end
		for _, prod in ipairs(GachaConfig.TicketProducts) do
			if prod.id == payload.id and prod.productId > 0 then
				MarketplaceService:PromptProductPurchase(player, prod.productId)
			end
		end
		return
	elseif (kind == "unlockClass" or kind == "buyClassRobux") and typeof(payload.classId) == "string" then
		-- Direct (non-random) unlocks: Soul Essence by rarity, or Robux.
		local reward = classReward(payload.classId)
		local function fail(message: string)
			Network.GetRemoteEvent(Network.Remotes.SummonResult):FireClient(player, { error = message })
		end
		if not reward then return end
		if p.classes[reward.classId] then return fail(`You already own the {reward.name}.`) end
		if kind == "buyClassRobux" then
			for _, prod in ipairs(GachaConfig.ClassProducts) do
				if prod.classId == reward.classId and prod.productId > 0 then
					MarketplaceService:PromptProductPurchase(player, prod.productId)
				end
			end
			return
		end
		local price = GachaConfig.ClassEssencePrice[reward.rarity]
		if not price then return end
		if (p.currencies.soulEssence or 0) < price then
			return fail(`Not enough Soul Essence ({p.currencies.soulEssence or 0}/{price}).`)
		end
		p.currencies.soulEssence -= price
		local isNew, note = grant(p, reward)
		local sets = checkSets(p)
		PlayerData.MarkDirty(player)
		sync(player)
		Network.GetRemoteEvent(Network.Remotes.SummonResult):FireClient(player, { results = { { id = reward.id, rarity = reward.rarity, isNew = isNew, note = note } }, best = reward.rarity, sets = sets, spark = true })
		return
	end
	PlayerData.MarkDirty(player)
	sync(player)
end

-- ─── Run effects (read by PlayerStats at the start of every run) ────────────
function GachaManager.GetEffects(player: Player, classId: string): { any }
	local out = {}
	local p = PlayerData.Get(player)
	if not p then return out end
	local function addScaled(effects: { any }?, mult: number)
		for _, e in ipairs(effects or {}) do
			table.insert(out, { stat = e.stat, operation = e.operation, value = e.value * mult })
		end
	end
	-- Awakened normal character for this class.
	for id, _ in pairs(p.collection.characters) do
		local r = GachaRewards.Get(id)
		if r and r.type == "character" and r.classId == classId then addScaled(r.effects, 1) end
	end
	-- Equipped relics, scaled by level.
	for _, relicId in ipairs(p.equipped.relics) do
		local relic = GachaRewards.Get(relicId)
		local ownedRelic = p.collection.relics[relicId]
		if relic and ownedRelic then
			addScaled(relic.effects, 1 + (ownedRelic.level - 1) * GachaConfig.RelicLevelBonus)
		end
	end
	return out
end

-- Whether the player owns `classId` (ClassManager's gate).
function GachaManager.OwnsClass(player: Player, classId: string): boolean
	local p = PlayerData.Get(player)
	-- (still loading: the starters, which every profile owns)
	if not p then return table.find(ClassData.Starter, classId) ~= nil end
	return p.classes[classId] == true
end

-- Equipped VFX variant for a class (nil if none, or no longer owned).
function GachaManager.GetVariant(player: Player, classId: string): string?
	local p = PlayerData.Get(player)
	local id = p and p.equipped.variants[classId]
	if not id or not p.collection.characters[id] then return nil end
	local r = GachaRewards.Get(id)
	return if r and r.type == "variant" then id else nil
end

-- ─── Earning tickets through gameplay ───────────────────────────────────────
function GachaManager.AwardTickets(player: Player, amount: number, _reason: string?)
	local p = PlayerData.Get(player)
	if not p or amount <= 0 then return end
	addCurrency(p, "tickets", amount)
	PlayerData.MarkDirty(player)
	sync(player)
	pcall(function()
		(require(script.Parent:WaitForChild("RunStats")) :: any).Add(player, "tickets", amount)
	end)
end

-- A kill `player` gets credit for: one independent roll at the tier's odds
-- ("normal" | "elite" | "miniboss" | "boss"; MobManager), collected straight
-- away. The roll is the server's own; nothing from the client is involved.
local recentDrops: { [Player]: { number } } = {}
function GachaManager.OnMobKilled(player: Player, tier: string)
	local p = PlayerData.Get(player)
	if not p then return end
	local D = GachaConfig.TicketDrops
	local chance = D[tier]
	if typeof(chance) ~= "number" or rng:NextNumber() >= chance then return end
	-- (the anti-farm cap: drops in the last hour)
	local now = os.clock()
	local list = recentDrops[player] or {}
	recentDrops[player] = list
	while list[1] and now - list[1] > 3600 do table.remove(list, 1) end
	if #list >= D.hourlyCap then return end
	table.insert(list, now)
	p.stats.ticketDrops = (p.stats.ticketDrops or 0) + 1
	GachaManager.AwardTickets(player, 1, tier)
	Network.GetRemoteEvent(Network.Remotes.TicketDrop):FireClient(player, { amount = 1, total = p.currencies.tickets or 0, tier = tier })
end

-- ─── Premium purchases ──────────────────────────────────────────────────────
local function processReceipt(info: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not player then return Enum.ProductPurchaseDecision.NotProcessedYet end
	local p = PlayerData.Await(player, 10)
	if not p then return Enum.ProductPurchaseDecision.NotProcessedYet end
	if p.purchases[info.PurchaseId] then return Enum.ProductPurchaseDecision.PurchaseGranted end
	local granted = false
	for _, prod in ipairs(GachaConfig.TicketProducts) do
		if prod.productId > 0 and prod.productId == info.ProductId then
			addCurrency(p, "tickets", prod.tickets)
			granted = true
		end
	end
	for _, prod in ipairs(GachaConfig.ClassProducts) do
		local reward = classReward(prod.classId)
		if not granted and prod.productId > 0 and prod.productId == info.ProductId and reward then
			-- (already owned, e.g. pulled while the prompt was open: its Essence)
			grant(p, reward)
			addHistory(p, reward, "robux")
			checkSets(p)
			granted = true
		end
	end
	if not granted then return Enum.ProductPurchaseDecision.NotProcessedYet end
	p.purchases[info.PurchaseId] = true
	-- Persist before confirming; if the save fails Roblox retries the receipt
	-- later, and the PurchaseId above keeps that from granting twice.
	if not PlayerData.Save(player) then
		p.purchases[info.PurchaseId] = nil
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	sync(player)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function GachaManager.Init()
	Network.GetRemoteEvent(Network.Remotes.Summon).OnServerEvent:Connect(function(player, payload)
		local ok, err = pcall(summon, player, payload)
		if not ok then
			busy[player] = false
			warn("[GachaManager] summon failed:", err)
		end
	end)
	Network.GetRemoteEvent(Network.Remotes.GachaAction).OnServerEvent:Connect(action)
	Network.GetRemoteEvent(Network.Remotes.RequestGacha).OnServerEvent:Connect(sync)
	MarketplaceService.ProcessReceipt = processReceipt

	PlayerData.OnLoaded(function(player, p)
		-- First-time starting balances.
		local newProfile = not p.stats.gachaInit
		if not p.stats.gachaInit then
			p.stats.gachaInit = 1
			for k, v in pairs(GachaConfig.StartingCurrencies) do addCurrency(p, k, v) end
			PlayerData.MarkDirty(player)
		end
		-- Drop anything whose reward no longer exists (removed rewards, and the
		-- old Ascension Sigil currency) so saves only hold live items.
		local cleaned = false
		for id in pairs(p.collection.characters) do
			if not GachaRewards.Get(id) then p.collection.characters[id] = nil; cleaned = true end
		end
		for classId, id in pairs(p.equipped.variants) do
			if not p.collection.characters[id] then p.equipped.variants[classId] = nil; cleaned = true end
		end
		for id in pairs(p.collection.relics) do
			if not GachaRewards.Get(id) then p.collection.relics[id] = nil; cleaned = true end
		end
		for i = #p.equipped.relics, 1, -1 do
			if not GachaRewards.Get(p.equipped.relics[i]) then table.remove(p.equipped.relics, i); cleaned = true end
		end
		if p.currencies.ascension then p.currencies.ascension = nil; cleaned = true end
		-- Crystals are gone: old balances become Pull Tickets (rounded up).
		if (p.currencies.crystals or 0) > 0 then
			addCurrency(p, "tickets", math.ceil(p.currencies.crystals / GachaConfig.CrystalsPerTicket))
		end
		if p.currencies.crystals then p.currencies.crystals = nil; cleaned = true end
		-- Classes: new profiles own the starters. Profiles from before classes
		-- were locked (they'd been through the gacha set-up) also keep every
		-- class they had invested in: an Awakened character, or talents.
		if not p.stats.classInit then
			p.stats.classInit = 1
			for _, classId in ipairs(ClassData.Starter) do p.classes[classId] = true end
			if p.stats.gachaInit and not newProfile then
				for _, classId in ipairs(ClassData.Order) do
					local invested = p.collection.characters[`char_{classId}`] ~= nil
					for _ in pairs(p.unlocked[classId] or {}) do invested = true end
					if invested and ClassData.IsPlayable(classId) then p.classes[classId] = true end
				end
				addCurrency(p, "tickets", GachaConfig.LockGiftTickets)
			end
			cleaned = true
		end
		-- (sets already complete from before sets existed pay out now)
		if #checkSets(p) > 0 then cleaned = true end
		if cleaned then PlayerData.MarkDirty(player) end
		local ok, info = pcall(function() return PolicyService:GetPolicyInfoForPlayerAsync(player) end)
		restricted[player] = ok and info and info.ArePaidRandomItemsRestricted == true or false
		player:GetAttributeChangedSignal("SelectedClass"):Connect(function()
			refreshVariantAttribute(player)
		end)
		sync(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		restricted[player] = nil
		busy[player] = nil
		recentDrops[player] = nil
	end)
	print("[GachaManager] initialized.")
end

return GachaManager
