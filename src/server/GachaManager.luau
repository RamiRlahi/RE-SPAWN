--[[
	GachaManager.luau
	Server-authoritative summons, collection and premium currency.

	Pull (per pull, per banner pity):
	  1. Mythic is rolled first at its base odds.
	  2. Legendary odds rise each pull from the soft-pity start; hard pity
	     guarantees Legendary+.
	  3. Otherwise Common / Rare / Epic by base odds — forced to Epic if the
	     "Epic every N pulls" pity is due.
	  4. A Legendary is the banner's featured reward featuredRate of the time;
	     losing that guarantees the featured one on the next Legendary.
	  5. A 10-pull always contains at least one Rare-or-better.

	Duplicates never waste: characters, VFX variants and armor → Soul Shards,
	relics → levels (then Relic Dust), cosmetics → Relic Dust.

	Around the pulls:
	  • Daily wish: one free single summon per UTC day ({ free = true }).
	  • Starlight: every summon on a banner adds GachaConfig.Spark.perPull to
	    that banner's pity.starlight; at Spark.cost it buys any unowned
	    Epic-or-better reward of the banner ({ kind = "spark", id }). The
	    exchange is sent back like a summon, so it gets the wish reveal.
	  • Sets (GachaRewards.Sets): completing one pays its bonus once.
	  • Summons of GachaConfig.AnnounceRarity or better are announced to
	    everyone in the server (SummonAnnounce).

	Premium: crystal Developer Products are granted idempotently in
	ProcessReceipt. Crystal (paid) summons are blocked for players whose
	PolicyService marks paid random items as restricted; tickets still work.
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
local restricted: { [Player]: boolean } = {}
local busy: { [Player]: boolean } = {}

-- ─── State sync ─────────────────────────────────────────────────────────────
local function pityFor(p: any, bannerId: string)
	local pity = p.pity[bannerId]
	if not pity then
		pity = { sinceEpic = 0, sinceLegendary = 0, guaranteedFeatured = false, starlight = 0 }
		p.pity[bannerId] = pity
	end
	pity.starlight = pity.starlight or 0
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

local function sync(player: Player)
	local p = PlayerData.Get(player)
	if not p then return end
	refreshVariantAttribute(player)
	refreshArmorAttributes(player, p)
	refreshRideAttributes(player, p)
	player:SetAttribute("Tickets", p.currencies.tickets or 0)
	player:SetAttribute("Crystals", p.currencies.crystals or 0)
	local setsDone = {}
	for _, set in ipairs(GachaRewards.Sets) do
		if p.stats[`set:{set.id}`] then setsDone[set.id] = true end
	end
	local products = {}
	for _, prod in ipairs(GachaConfig.CrystalProducts) do
		if prod.productId and prod.productId > 0 then
			table.insert(products, { id = prod.id, label = prod.label, crystals = prod.crystals })
		end
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

local function pickReward(banner: any, rarity: string, pity: any): any
	local list = GachaRewards.InPoolByRarity(banner.pool, rarity)
	if rarity == "Legendary" and banner.featured then
		local featured = GachaRewards.Get(banner.featured)
		local others = {}
		for _, r in ipairs(list) do
			if r.id ~= banner.featured then table.insert(others, r) end
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
	if reward.type == "character" then
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
	local multi = payload.count == 10 and not free
	local count = multi and GachaConfig.Cost.multi.count or 1
	local cost = multi and GachaConfig.Cost.multi or GachaConfig.Cost.single

	if free then
		-- The daily wish: one free single summon a day.
		if not freeAvailable(p) then
			Network.GetRemoteEvent(Network.Remotes.SummonResult):FireClient(player, { error = "Your daily wish is spent. A new one rises at midnight (UTC)." })
			return
		end
		p.stats.lastFreeDay = today()
	elseif not GachaConfig.FREE_SUMMONS then
		-- Payment (skipped entirely while FREE_SUMMONS is on).
		local pay = payload.pay == "crystals" and "crystals" or "tickets"
		if pay == "crystals" and restricted[player] then
			Network.GetRemoteEvent(Network.Remotes.SummonResult):FireClient(player, { error = "Crystal summons aren't available in your region. Tickets still work." })
			return
		end
		local price = cost[pay]
		if (p.currencies[pay] or 0) < price then
			Network.GetRemoteEvent(Network.Remotes.SummonResult):FireClient(player, { error = `Not enough {GachaConfig.Currencies[pay].name}s` })
			return
		end
		p.currencies[pay] -= price
	end

	busy[player] = true
	local pity = pityFor(p, bannerId)
	local results = {}
	local best = "Common"
	for i = 1, count do
		pity.sinceEpic += 1
		pity.sinceLegendary += 1
		pity.starlight += GachaConfig.Spark.perPull
		local rarity = rollRarity(pity, bannerId)
		local multiGuarantee = GachaConfig.PityFor(bannerId).multiGuarantee
		-- 10-pull guarantee: the last pull is at least the configured rarity.
		if multi and i == count then
			local gotGuarantee = false
			for _, r in ipairs(results) do
				if rarityIndex(r.rarity) >= rarityIndex(multiGuarantee) then gotGuarantee = true end
			end
			if not gotGuarantee and rarityIndex(rarity) < rarityIndex(multiGuarantee) then
				rarity = multiGuarantee
			end
		end
		if rarityIndex(rarity) >= rarityIndex("Epic") then pity.sinceEpic = 0 end
		if rarityIndex(rarity) >= rarityIndex("Legendary") then pity.sinceLegendary = 0 end
		local reward = pickReward(banner, rarity, pity)
		local isNew, note = grant(p, reward)
		if rarityIndex(reward.rarity) > rarityIndex(best) then best = reward.rarity end
		table.insert(results, { id = reward.id, rarity = reward.rarity, isNew = isNew, note = note })
	end
	p.stats.pulls = (p.stats.pulls or 0) + count
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
		if p.collection.characters[reward.id] or p.collection.relics[reward.id] or p.collection.cosmetics[reward.id] then
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
		if not table.find(GachaRewards.Pool(banner.pool), reward.id) or reward.type == "material"
			or rarityIndex(reward.rarity) < rarityIndex(GachaConfig.Spark.minRarity) then
			return fail("That can't be bought with Starlight.")
		end
		if owns(p, reward) then return fail(`You already own {reward.name}.`) end
		local pity = pityFor(p, bannerId)
		if pity.starlight < GachaConfig.Spark.cost then
			return fail(`Not enough Starlight ({pity.starlight}/{GachaConfig.Spark.cost}).`)
		end
		pity.starlight -= GachaConfig.Spark.cost
		local isNew, note = grant(p, reward)
		local sets = checkSets(p)
		PlayerData.MarkDirty(player)
		sync(player)
		local results = { { id = reward.id, rarity = reward.rarity, isNew = isNew, note = note } }
		Network.GetRemoteEvent(Network.Remotes.SummonResult):FireClient(player, { results = results, best = reward.rarity, sets = sets, spark = true })
		announce(player, results)
		return
	elseif kind == "buyCrystals" and typeof(payload.id) == "string" then
		for _, prod in ipairs(GachaConfig.CrystalProducts) do
			if prod.id == payload.id and prod.productId > 0 then
				MarketplaceService:PromptProductPurchase(player, prod.productId)
			end
		end
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

function GachaManager.OnMobKilled(player: Player, isBoss: boolean)
	local p = PlayerData.Get(player)
	if not p then return end
	if isBoss then
		GachaManager.AwardTickets(player, GachaConfig.TicketRewards.bossKill, "boss")
		return
	end
	p.stats.ticketKills = (p.stats.ticketKills or 0) + 1
	if p.stats.ticketKills >= GachaConfig.TicketRewards.killsPerTicket then
		p.stats.ticketKills = 0
		GachaManager.AwardTickets(player, 1, "kills")
	end
end

-- ─── Premium purchases ──────────────────────────────────────────────────────
local function processReceipt(info: any): Enum.ProductPurchaseDecision
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not player then return Enum.ProductPurchaseDecision.NotProcessedYet end
	local p = PlayerData.Await(player, 10)
	if not p then return Enum.ProductPurchaseDecision.NotProcessedYet end
	if p.purchases[info.PurchaseId] then return Enum.ProductPurchaseDecision.PurchaseGranted end
	for _, prod in ipairs(GachaConfig.CrystalProducts) do
		if prod.productId == info.ProductId then
			addCurrency(p, "crystals", prod.crystals)
			p.purchases[info.PurchaseId] = true
			PlayerData.Save(player) -- persist before confirming the purchase
			sync(player)
			return Enum.ProductPurchaseDecision.PurchaseGranted
		end
	end
	return Enum.ProductPurchaseDecision.NotProcessedYet
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
	end)
	print("[GachaManager] initialized.")
end

return GachaManager
