--!strict
--[[
	StoreManager.luau
	The Robux store outside the summon banners, and the community rewards
	(StoreConfig holds the prices and product ids).

	  StoreAction (client → server):
	    { kind = "buyMount", rewardId }   prompt that mount's Developer Product
	    { kind = "forgeSkip", slot }      skip the forge's minigame: a skip you
	                                      hold is used now; otherwise its product
	                                      is prompted, and the skip is used the
	                                      moment the purchase goes through
	    { kind = "claimGroup" }           in the group (IsInGroup): its reward, once
	    { kind = "claimLike" }            the "liked & favorited" reward, once
	                                      (Roblox can't check a like or a
	                                      favorite: it's on trust)
	  StoreResult (server → client): { kind, ok, message }

	The player's attributes the client shows: ForgeSkips (skips held),
	ClaimedGroup, ClaimedLike. Purchases go through GachaManager's one
	ProcessReceipt (GachaManager.ProductHandlers), which saves before
	confirming, so a purchase is never lost or granted twice.
--]]

local Players = game:GetService("Players")
local MarketplaceService = game:GetService("MarketplaceService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))
local StoreConfig = require(Shared:WaitForChild("StoreConfig"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local GachaManager = require(script.Parent:WaitForChild("GachaManager"))
local LootManager = require(script.Parent:WaitForChild("LootManager"))

local StoreManager = {}

-- the forge slot a player is buying a skip for (used as the purchase lands)
local pendingSkip: { [Player]: string } = {}

local function store(p: any): any
	if typeof(p.store) ~= "table" then p.store = {} end
	return p.store
end

local function refresh(player: Player)
	local p = PlayerData.Get(player)
	if not p then return end
	local s = store(p)
	player:SetAttribute("ForgeSkips", s.forgeSkips or 0)
	player:SetAttribute("ClaimedGroup", s.claimedGroup == true)
	player:SetAttribute("ClaimedLike", s.claimedLike == true)
end

local function result(player: Player, kind: string, ok: boolean, message: string)
	Network.GetRemoteEvent(Network.Remotes.StoreResult):FireClient(player, { kind = kind, ok = ok, message = message })
end

-- Use a held skip on `slot`: the piece forged as if every strike was perfect.
local function useSkip(player: Player, slot: string): boolean
	local p = PlayerData.Get(player)
	if not p then return false end
	local s = store(p)
	if (s.forgeSkips or 0) <= 0 then return false end
	if not LootManager.Craft(player, slot, 1, true) then
		result(player, "forgeSkip", false, "Not enough scrap to forge. Your skip is kept.")
		return false
	end
	s.forgeSkips -= 1
	PlayerData.MarkDirty(player)
	refresh(player)
	return true
end

local function claim(player: Player, flag: string, reward: { currency: string, amount: number }): boolean
	local p = PlayerData.Get(player)
	if not p then return false end
	local s = store(p)
	if s[flag] then return false end
	s[flag] = true
	GachaManager.AddCurrency(player, reward.currency, reward.amount)
	PlayerData.MarkDirty(player)
	refresh(player)
	return true
end

local function onAction(player: Player, payload: any)
	if typeof(payload) ~= "table" then return end
	local kind = payload.kind
	if kind == "buyMount" and typeof(payload.rewardId) == "string" then
		local item = StoreConfig.Mount(payload.rewardId)
		if not item then return end
		if GachaManager.Owns(player, item.rewardId) then
			return result(player, kind, false, "You already own this mount.")
		end
		if item.productId <= 0 then
			return result(player, kind, false, "Not on sale yet.")
		end
		MarketplaceService:PromptProductPurchase(player, item.productId)
	elseif kind == "forgeSkip" and typeof(payload.slot) == "string" then
		if useSkip(player, payload.slot) then return end
		local p = PlayerData.Get(player)
		if p and (store(p).forgeSkips or 0) > 0 then return end -- (held, but no scrap: said above)
		if StoreConfig.ForgeSkip.productId <= 0 then
			return result(player, kind, false, "Forge skips aren't on sale yet.")
		end
		pendingSkip[player] = payload.slot
		MarketplaceService:PromptProductPurchase(player, StoreConfig.ForgeSkip.productId)
	elseif kind == "claimGroup" then
		local gid = StoreConfig.Community.groupId
		if gid <= 0 then return end
		local ok, inGroup = pcall(function() return player:IsInGroup(gid) end)
		if not (ok and inGroup) then
			return result(player, kind, false, "Join the group first, then claim.")
		end
		local r = StoreConfig.Community.groupReward
		if claim(player, "claimedGroup", r) then
			result(player, kind, true, `Thanks for joining! +{r.amount} Pull Tickets`)
		end
	elseif kind == "claimLike" then
		local r = StoreConfig.Community.likeReward
		if claim(player, "claimedLike", r) then
			result(player, kind, true, `Thank you! +{r.amount} Pull Tickets`)
		end
	end
end

function StoreManager.Init()
	Network.GetRemoteEvent(Network.Remotes.StoreAction).OnServerEvent:Connect(onAction)
	Network.GetRemoteEvent(Network.Remotes.StoreResult)
	-- the mounts
	for _, item in ipairs(StoreConfig.Mounts) do
		if item.productId > 0 then
			GachaManager.ProductHandlers[item.productId] = function(player: Player): boolean
				return GachaManager.GrantReward(player, item.rewardId, "robux")
			end
		end
	end
	-- the forge skip: held, then used on the slot being forged (if any)
	if StoreConfig.ForgeSkip.productId > 0 then
		GachaManager.ProductHandlers[StoreConfig.ForgeSkip.productId] = function(player: Player, p: any): boolean
			local s = store(p)
			s.forgeSkips = (s.forgeSkips or 0) + 1
			refresh(player)
			local slot = pendingSkip[player]
			pendingSkip[player] = nil
			if slot then task.defer(useSkip, player, slot) end
			return true
		end
	end
	MarketplaceService.PromptProductPurchaseFinished:Connect(function(userId: number, productId: number, purchased: boolean)
		if purchased or productId ~= StoreConfig.ForgeSkip.productId then return end
		local plr = Players:GetPlayerByUserId(userId)
		if plr then pendingSkip[plr] = nil end
	end)
	PlayerData.OnLoaded(function(player)
		refresh(player)
	end)
	Players.PlayerRemoving:Connect(function(player)
		pendingSkip[player] = nil
	end)
	print("[StoreManager] initialized.")
end

-- (Studio test hook: a skip given)
function StoreManager.DevGiveSkip(player: Player, n: number)
	local p = PlayerData.Get(player)
	if not p then return end
	local s = store(p)
	s.forgeSkips = math.max(0, (s.forgeSkips or 0) + n)
	refresh(player)
end

return StoreManager
