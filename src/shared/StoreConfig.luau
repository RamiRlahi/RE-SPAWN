--!strict
--[[
	StoreConfig.luau
	What the game sells for Robux outside the summon banners, and its
	community rewards (StoreManager on the server, MountShop and ForgeMinigame
	on the client).

	Robux needs a Developer Product for each thing sold: make it on the Creator
	Hub (your experience → Monetization → Developer Products), priced as the
	`robux` here, and put its id in `productId`. While an id is 0 the item still
	shows, with its price, but can't be bought yet ("SOON").

	  StoreConfig.ForgeSkip        skip the forge's minigame: the piece forged
	                               as if every strike was PERFECT (still costs
	                               its scrap). One purchase, one skip.
	  StoreConfig.Mounts           the mounts shop: every mount that can be
	                               summoned (not the secret ones), one product each
	  StoreConfig.MOUNT_ROBUX      the price of a mount, by rarity
	  StoreConfig.Community        the one-time community rewards:
	      groupId                  your Roblox group (0: the group reward is hidden)
	      groupReward              joined the group (checked: IsInGroup)
	      likeReward               "I liked and favorited" (not checkable on
	                               Roblox: an honor-system claim, once)
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local GachaRewards = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GachaRewards"))

local StoreConfig = {}

StoreConfig.ForgeSkip = { productId = 0, robux = 25 }

StoreConfig.MOUNT_ROBUX = { Common = 49, Rare = 99, Epic = 249, Legendary = 499, Mythic = 899 }

-- rewardId → its Developer Product id (0: not on sale yet)
local PRODUCT_IDS: { [string]: number } = {
	-- mount_dire_wolf = 123456789,
}

export type MountItem = { rewardId: string, productId: number, robux: number, rarity: string, name: string }
StoreConfig.Mounts = {} :: { MountItem }
local ORDER = { Common = 1, Rare = 2, Epic = 3, Legendary = 4, Mythic = 5 }
for _, r in ipairs(GachaRewards.All :: { any }) do
	if r.type == "mount" and not r.secret and not r.noDrop then
		table.insert(StoreConfig.Mounts, {
			rewardId = r.id, productId = PRODUCT_IDS[r.id] or 0, robux = StoreConfig.MOUNT_ROBUX[r.rarity] or 499,
			rarity = r.rarity, name = r.name,
		})
	end
end
table.sort(StoreConfig.Mounts, function(a, b)
	local ra, rb = ORDER[a.rarity] or 0, ORDER[b.rarity] or 0
	if ra ~= rb then return ra < rb end
	return a.name < b.name
end)

function StoreConfig.Mount(rewardId: string): MountItem?
	for _, m in ipairs(StoreConfig.Mounts) do
		if m.rewardId == rewardId then return m end
	end
	return nil
end

StoreConfig.Community = {
	groupId = 0,
	groupReward = { currency = "tickets", amount = 5 },
	likeReward = { currency = "tickets", amount = 2 },
}

return StoreConfig
