--!strict
-- Server-authoritative run stats, experience, and tome selection.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))
local ClassData = require(Shared:WaitForChild("ClassData"))
local TomeData = require(Shared:WaitForChild("TomeData"))

local PlayerStats = {}

local BASE_XP_TO_LEVEL = 100
local XP_GROWTH = 1.25
local MAX_UNIQUE_TOMES = 4
local SELECTION_LOCK_DURATION = 2
local REROLLS_PER_LEVEL = 1

type RunState = {
	level: number,
	xp: number,
	xpToNext: number,
	pendingLevelUps: number,
	pendingChoices: { string }?,
	selectionUnlockAt: number,
	rerollsRemaining: number,
	isPausingGame: boolean,
	tomeCounts: { [string]: number },
	uniqueTomes: { string },
	chaosBoosts: { string },
	stats: { [string]: number },
}

local states: { [Player]: RunState } = {}

local function setGamePaused(owner: Player, paused: boolean)
	local state = states[owner]
	if not state then return end
	state.isPausingGame = paused
	local shouldPause = false
	for _, otherState in pairs(states) do
		if otherState.isPausingGame then
			shouldPause = true
			break
		end
	end
	Workspace:SetAttribute("TomesPaused", shouldPause)

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if humanoid and root and player:GetAttribute("InLobby") ~= true then
			root.Anchored = shouldPause
			if shouldPause then
				humanoid.WalkSpeed = 0
			else
				local otherState = states[player]
				local speed = otherState and otherState.stats.movementSpeed or 16
				humanoid.WalkSpeed = player:GetAttribute("IsSprinting") == true and speed * (34 / 16) or speed
			end
		end
	end
end

local function baseStats(player: Player): { [string]: number }
	local classId = player:GetAttribute("SelectedClass")
	local class = typeof(classId) == "string" and ClassData.GetClass(classId) or nil
	local maxHealth = (class and class.stats.maxHealth) or 100
	return {
		movementSpeed = 16,
		basicAttackSpeed = 1,
		abilityCooldown = 1,
		damage = 1,
		evasion = 0,
		goldGain = 1,
		maxHealth = maxHealth,
		knockback = 1,
		critChance = 0,
		projectileSpeed = 1,
		healthRegenPerMinute = 0,
		shield = 0,
		silverGain = 1,
		size = 1,
		armor = 1,
		pickupRange = 1,
		lifesteal = 0,
		difficulty = 1,
		abilityDuration = 1,
		luck = 0,
		projectileCount = 0,
		thornsDamage = 0,
		xpGain = 1,
	}
end

local function syncProgress(player: Player, state: RunState)
	player:SetAttribute("Level", state.level)
	player:SetAttribute("XP", state.xp)
	player:SetAttribute("XPToNext", state.xpToNext)
	Network.GetRemoteEvent(Network.Remotes.TomeProgress):FireClient(player, {
		level = state.level,
		xp = state.xp,
		xpToNext = state.xpToNext,
	})
end

local function applyStats(player: Player, state: RunState)
	local stats = baseStats(player)
	local percentageBonuses: { [string]: number } = {}

	for tomeId, count in pairs(state.tomeCounts) do
		local tome = TomeData.GetTome(tomeId)
		if tome then
			for _, effect in ipairs(tome.effects) do
				local value = effect.value
				if value then
					if effect.operation == "add" then
						stats[effect.stat] = (stats[effect.stat] or 0) + value * count
					elseif effect.operation == "multiplier" then
						stats[effect.stat] = (stats[effect.stat] or 1) + value * count
					elseif effect.operation == "percent" then
						if effect.stat == "evasion" or effect.stat == "critChance" or effect.stat == "lifesteal" or effect.stat == "luck" then
							stats[effect.stat] = (stats[effect.stat] or 0) + value * count
						elseif effect.stat == "abilityCooldown" then
							stats[effect.stat] *= math.max(0.1, 1 - value * count)
						else
							percentageBonuses[effect.stat] = (percentageBonuses[effect.stat] or 0) + value * count
						end
					end
				end
			end
		end
	end
	-- Each Chaos Tome rolls one concrete, non-curse tome effect at selection time.
	for _, tomeId in ipairs(state.chaosBoosts) do
		local tome = TomeData.GetTome(tomeId)
		if tome then
			for _, effect in ipairs(tome.effects) do
				local value = effect.value
				if value then
					if effect.operation == "add" then
						stats[effect.stat] = (stats[effect.stat] or 0) + value
					elseif effect.operation == "multiplier" then
						stats[effect.stat] = (stats[effect.stat] or 1) + value
					elseif effect.operation == "percent" then
						if effect.stat == "evasion" or effect.stat == "critChance" or effect.stat == "lifesteal" or effect.stat == "luck" then
							stats[effect.stat] = (stats[effect.stat] or 0) + value
						elseif effect.stat == "abilityCooldown" then
							stats[effect.stat] *= math.max(0.1, 1 - value)
						else
							percentageBonuses[effect.stat] = (percentageBonuses[effect.stat] or 0) + value
						end
					end
				end
			end
		end
	end

	for stat, bonus in pairs(percentageBonuses) do
		stats[stat] = (stats[stat] or 1) * (1 + bonus)
	end
	state.stats = stats

	for stat, value in pairs(stats) do
		player:SetAttribute(`Stat_{stat}`, value)
	end
	player:SetAttribute("TomeSlots", #state.uniqueTomes)

	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		local oldMaxHealth = humanoid.MaxHealth
		local healthRatio = oldMaxHealth > 0 and humanoid.Health / oldMaxHealth or 1
		humanoid.MaxHealth = stats.maxHealth
		humanoid.Health = math.clamp(stats.maxHealth * healthRatio, 1, stats.maxHealth)
		if player:GetAttribute("IsSprinting") == true then
			humanoid.WalkSpeed = stats.movementSpeed * (34 / 16)
		else
			humanoid.WalkSpeed = stats.movementSpeed
		end
	end
end

local function sampleChoices(pool: { string }): { string }
	local shuffled = table.clone(pool)
	for index = #shuffled, 2, -1 do
		local other = math.random(1, index)
		shuffled[index], shuffled[other] = shuffled[other], shuffled[index]
	end
	local choices: { string } = {}
	for index = 1, math.min(3, #shuffled) do
		table.insert(choices, shuffled[index])
	end
	return choices
end

local function presentChoices(player: Player, state: RunState)
	if state.pendingChoices or state.pendingLevelUps <= 0 then return end
	local pool: { string } = {}
	if #state.uniqueTomes >= MAX_UNIQUE_TOMES then
		pool = table.clone(state.uniqueTomes)
	else
		for _, id in ipairs(TomeData.Order) do
			if not state.tomeCounts[id] then
				table.insert(pool, id)
			end
		end
	end

	state.pendingChoices = sampleChoices(pool)
	state.rerollsRemaining = REROLLS_PER_LEVEL
	state.selectionUnlockAt = os.clock() + SELECTION_LOCK_DURATION
	setGamePaused(player, true)
	local choices = {}
	for _, id in ipairs(state.pendingChoices) do
		local tome = TomeData.GetTome(id)
		if tome then table.insert(choices, tome) end
	end
	Network.GetRemoteEvent(Network.Remotes.TomeChoices):FireClient(player, {
		choices = choices,
		rerollsRemaining = state.rerollsRemaining,
		lockDuration = SELECTION_LOCK_DURATION,
	})
end

function PlayerStats.StartRun(player: Player)
	local state: RunState = {
		level = 1,
		xp = 0,
		xpToNext = BASE_XP_TO_LEVEL,
		pendingLevelUps = 0,
		pendingChoices = nil,
		selectionUnlockAt = 0,
		rerollsRemaining = 0,
		isPausingGame = false,
		tomeCounts = {},
		uniqueTomes = {},
		chaosBoosts = {},
		stats = {},
	}
	states[player] = state
	applyStats(player, state)
	syncProgress(player, state)
end

function PlayerStats.AwardXP(player: Player, amount: number)
	local state = states[player]
	if not state or amount <= 0 then return end
	local adjustedAmount = math.floor(amount * (state.stats.xpGain or 1))
	state.xp += adjustedAmount

	while state.xp >= state.xpToNext do
		state.xp -= state.xpToNext
		state.level += 1
		state.xpToNext = math.floor(BASE_XP_TO_LEVEL * (XP_GROWTH ^ (state.level - 1)))
		state.pendingLevelUps += 1
	end

	syncProgress(player, state)
	presentChoices(player, state)
end

function PlayerStats.GetStat(player: Player, stat: string): number
	local state = states[player]
	return state and (state.stats[stat] or 0) or 0
end

function PlayerStats.RefreshCharacter(player: Player)
	local state = states[player]
	if state then
		applyStats(player, state)
	end
end

function PlayerStats.Init()
	Network.GetRemoteEvent(Network.Remotes.ChooseTome).OnServerEvent:Connect(function(player: Player, tomeId: any)
		local state = states[player]
		if not state or typeof(tomeId) ~= "string" or not state.pendingChoices then return end
		if os.clock() < state.selectionUnlockAt then return end
		if not table.find(state.pendingChoices, tomeId) then return end

		state.pendingChoices = nil
		state.pendingLevelUps -= 1
		if not state.tomeCounts[tomeId] then
			if #state.uniqueTomes >= MAX_UNIQUE_TOMES then return end
			state.tomeCounts[tomeId] = 0
			table.insert(state.uniqueTomes, tomeId)
		end
		state.tomeCounts[tomeId] += 1
		if tomeId == "chaos" then
			local chaosPool: { string } = {}
			for _, candidateId in ipairs(TomeData.Order) do
				local candidate = TomeData.GetTome(candidateId)
				if candidateId ~= "chaos" and candidateId ~= "cursed" and candidate and candidate.effects[1] and candidate.effects[1].value then
					table.insert(chaosPool, candidateId)
				end
			end
			local bonusId = chaosPool[math.random(1, #chaosPool)]
			table.insert(state.chaosBoosts, bonusId)
			player:SetAttribute(`ChaosBonus_{#state.chaosBoosts}`, bonusId)
		end
		player:SetAttribute(`Tome_{tomeId}`, state.tomeCounts[tomeId])
		applyStats(player, state)
		setGamePaused(player, false)
		presentChoices(player, state)
	end)

	Network.GetRemoteEvent(Network.Remotes.RerollTomes).OnServerEvent:Connect(function(player: Player)
		local state = states[player]
		if not state or not state.pendingChoices or state.rerollsRemaining <= 0 then return end
		if os.clock() < state.selectionUnlockAt then return end
		local pool = #state.uniqueTomes >= MAX_UNIQUE_TOMES and table.clone(state.uniqueTomes) or {}
		if #pool == 0 then
			for _, id in ipairs(TomeData.Order) do
				if not state.tomeCounts[id] then table.insert(pool, id) end
			end
		end
		state.pendingChoices = sampleChoices(pool)
		state.rerollsRemaining -= 1
		state.selectionUnlockAt = os.clock() + SELECTION_LOCK_DURATION
		local choices = {}
		for _, id in ipairs(state.pendingChoices) do
			local tome = TomeData.GetTome(id)
			if tome then table.insert(choices, tome) end
		end
		Network.GetRemoteEvent(Network.Remotes.TomeChoices):FireClient(player, {
			choices = choices,
			rerollsRemaining = state.rerollsRemaining,
			lockDuration = SELECTION_LOCK_DURATION,
		})
	end)

	Players.PlayerRemoving:Connect(function(player)
		if states[player] and states[player].isPausingGame then
			setGamePaused(player, false)
		end
		states[player] = nil
	end)
end

return PlayerStats
