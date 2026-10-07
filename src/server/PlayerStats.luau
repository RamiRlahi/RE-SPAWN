--!strict
-- Server-authoritative run stats, experience, and tome selection.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))
local ClassData = require(Shared:WaitForChild("ClassData"))
local TomeData = require(Shared:WaitForChild("TomeData"))
local RunScope = require(Shared:WaitForChild("RunScope"))
local TalentManager = require(script.Parent:WaitForChild("TalentManager"))
local GachaManager = require(script.Parent:WaitForChild("GachaManager"))
local AccountManager = require(script.Parent:WaitForChild("AccountManager"))
local RunStats = require(script.Parent:WaitForChild("RunStats"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))
local WeeklyModifiers = require(Shared:WaitForChild("WeeklyModifiers"))

local PlayerStats = {}

local BASE_XP_TO_LEVEL = 100
local MAX_UNIQUE_TOMES = 6 -- (tomes and boons: the build's slots)
local MAX_RELICS = 3       -- run relics have their own
local SELECTION_LOCK_DURATION = 2
local REROLLS_PER_LEVEL = 1

type RunState = {
	offered: { string }?,
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
	talentEffects: { any }, -- unlocked class talents (TalentManager), fixed for the run
	stats: { [string]: number },
	evolutions: { [string]: boolean }, -- boons evolved this run (TomeData.Evolutions)
	relics: { string },                -- run relics carried (TomeData.RelicOrder)
	relicOffers: number,               -- relic choices waiting to be shown
	curses: number,                    -- cursed altars accepted (-25% max HP each)
	presentingRelics: boolean,         -- the choice up now is a relic choice
}

local states: { [Player]: RunState } = {}

local function setGamePaused(owner: Player, paused: boolean)
	local state = states[owner]
	if not state then return end
	state.isPausingGame = paused
	-- (only the chooser's run pauses: other parties' runs carry on)
	local runId = owner:GetAttribute("RunId")
	local shouldPause = false
	local choosing: { string } = {}
	for p, otherState in pairs(states) do
		if otherState.isPausingGame and p:GetAttribute("RunId") == runId then
			shouldPause = true
			table.insert(choosing, p.DisplayName)
		end
	end
	RunScope.Set(runId, "TomesPaused", shouldPause)
	-- Who everyone is waiting on (clients show "waiting for … to choose").
	RunScope.Set(runId, "TomesChoosing", if #choosing > 0 then table.concat(choosing, ", ") else nil)

	for _, player in ipairs(Players:GetPlayers()) do
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		local root = character and character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if humanoid and root and player:GetAttribute("InLobby") ~= true and player:GetAttribute("RunId") == runId then
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

-- The level bar shows the account level (AccountManager); the run keeps its
-- own count of rooms claimed.
local function syncProgress(player: Player, _state: RunState)
	AccountManager.Sync(player)
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
							-- Diminishing: each tome cuts what's left.
							stats[effect.stat] *= (1 - value) ^ count
						elseif effect.stat == "size" then
							-- Additive per tome (not compounding).
							stats.size = (stats.size or 1) * (1 + value * count)
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
						elseif effect.stat == "size" then
							stats.size = (stats.size or 1) * (1 + value)
						else
							percentageBonuses[effect.stat] = (percentageBonuses[effect.stat] or 0) + value
						end
					end
				end
			end
		end
	end

	-- Unlocked class talents (same effect rules as a single tome).
	for _, effect in ipairs(state.talentEffects or {}) do
		local value = effect.value
		if effect.operation == "add" then
			stats[effect.stat] = (stats[effect.stat] or 0) + value
		elseif effect.operation == "multiplier" then
			stats[effect.stat] = (stats[effect.stat] or 1) + value
		elseif effect.operation == "percent" then
			if effect.stat == "evasion" or effect.stat == "critChance" or effect.stat == "lifesteal" or effect.stat == "luck" then
				stats[effect.stat] = (stats[effect.stat] or 0) + value
			elseif effect.stat == "abilityCooldown" then
				stats[effect.stat] *= math.max(0.1, 1 - value)
			elseif effect.stat == "size" then
				stats.size = (stats.size or 1) * (1 + value)
			else
				percentageBonuses[effect.stat] = (percentageBonuses[effect.stat] or 0) + value
			end
		end
	end

	for stat, bonus in pairs(percentageBonuses) do
		stats[stat] = (stats[stat] or 1) * (1 + bonus)
	end
	-- (the Frozen Abyss: everyone a little slower)
	if WeeklyModifiers.Is("frozen_abyss") then stats.movementSpeed *= 0.9 end
	-- (a cursed altar's price: a quarter of your max health, each)
	if (state.curses or 0) > 0 then stats.maxHealth *= math.max(0.25, 1 - 0.25 * state.curses) end
	-- Evolutions: a flag stat each (Boons reads them).
	for id in pairs(state.evolutions or {}) do stats[id] = 1 end
	-- Caps, so stacking one tome can't break the game.
	stats.size = math.min(stats.size or 1, 1.75)
	stats.abilityCooldown = math.max(stats.abilityCooldown or 1, 0.5)
	stats.basicAttackSpeed = math.min(stats.basicAttackSpeed or 1, 2)
	state.stats = stats

	for stat, value in pairs(stats) do
		player:SetAttribute(`Stat_{stat}`, value)
	end
	player:SetAttribute("TomeSlots", #state.uniqueTomes)

	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if humanoid then
		-- Shield Tomes stack extra HP on top of max HP (the HUD draws it white).
		local newMax = stats.maxHealth + (stats.shield or 0)
		local oldMaxHealth = humanoid.MaxHealth
		humanoid.MaxHealth = newMax
		if humanoid.Health <= 0 then
			-- Dead: leave it that way (don't revive by raising max HP).
		elseif newMax > oldMaxHealth then
			-- Newly gained max HP (Health / Shield Tomes) arrives filled.
			humanoid.Health = math.min(humanoid.Health + (newMax - oldMaxHealth), newMax)
		else
			humanoid.Health = math.clamp(humanoid.Health, 1, newMax)
		end
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

-- What a level-up can offer: new tomes and boons while there are free slots,
-- and another level of what you already carry (boons stop at their max).
local function buildPool(player: Player, state: RunState, noNew: { [string]: boolean }?): { string }
	local pool: { string } = {}
	local classId = player:GetAttribute("SelectedClass")
	for _, id in ipairs(state.uniqueTomes) do
		if (state.tomeCounts[id] or 0) < TomeData.MaxLevel(id) then table.insert(pool, id) end
	end
	if #state.uniqueTomes < MAX_UNIQUE_TOMES then
		for _, id in ipairs(TomeData.Order) do
			if not state.tomeCounts[id] and TomeData.IsForClass(id, classId) and not (noNew and noNew[id]) then
				table.insert(pool, id)
			end
		end
	end
	return pool
end

-- A choice as its card shows it: a boon's card reads its next level (and
-- what it evolves into at max).
local function choiceView(player: Player, state: RunState, id: string): any
	local tome = TomeData.GetTome(id)
	if not tome then return nil end
	if tome.category ~= "Boon" then return tome end
	local nextLevel = (state.tomeCounts[id] or 0) + 1
	local view = table.clone(tome) :: any
	view.level = nextLevel
	local lines = { (tome.levels and tome.levels[nextLevel]) or tome.description }
	local hint = TomeData.EvolveHint(id, player:GetAttribute("SelectedClass"))
	if hint and nextLevel >= (tome.maxLevel or 3) then table.insert(lines, hint) end
	view.description = table.concat(lines, "\n")
	return view
end

local function sendChoices(player: Player, state: RunState)
	local choices = {}
	for _, id in ipairs(state.pendingChoices or {}) do
		local view = choiceView(player, state, id)
		if view then table.insert(choices, view) end
	end
	Network.GetRemoteEvent(Network.Remotes.TomeChoices):FireClient(player, {
		choices = choices,
		rerollsRemaining = state.rerollsRemaining,
		lockDuration = SELECTION_LOCK_DURATION,
	})
end

-- A boon at its max level evolves: with its tome (class-free ones), or on its
-- class (that class's signature skill changes). Found ones go in the Codex.
local function checkEvolutions(player: Player, state: RunState)
	local classId = player:GetAttribute("SelectedClass")
	for _, evo in ipairs(TomeData.Evolutions) do
		if state.evolutions[evo.id] then continue end
		if (state.tomeCounts[evo.boon] or 0) < TomeData.MaxLevel(evo.boon) then continue end
		local ready = if evo.with then (state.tomeCounts[evo.with] or 0) > 0 else evo.classId == classId
		if not ready then continue end
		state.evolutions[evo.id] = true
		player:SetAttribute(`Evo_{evo.id}`, true)
		local isNew = false
		local p = PlayerData.Get(player)
		if p then
			p.codex = p.codex or {}
			isNew = not p.codex[evo.id]
			p.codex[evo.id] = true
			PlayerData.MarkDirty(player)
		end
		Network.GetRemoteEvent(Network.Remotes.Evolution):FireClient(player, {
			id = evo.id, name = evo.name, description = evo.description, color = evo.color, isNew = isNew,
		})
		RunStats.AddLoot(player, { kind = "evolution", glyph = "◆", name = evo.name, rarity = "Legendary", isNew = isNew })
		print(`[PlayerStats] {player.Name} evolved {evo.name}{if isNew then " (new to the Codex)" else ""}`)
	end
	applyStats(player, state)
end

-- The run relics this player could still be offered.
local function relicPool(player: Player, state: RunState): { string }
	local pool = {}
	local classId = player:GetAttribute("SelectedClass")
	for _, id in ipairs(TomeData.RelicOrder) do
		if not state.tomeCounts[id] and TomeData.IsForClass(id, classId) then table.insert(pool, id) end
	end
	return pool
end

local function presentChoices(player: Player, state: RunState)
	if state.pendingChoices or state.pendingLevelUps <= 0 then return end
	-- (a relic found waits its turn, then shows before any level-up)
	local pool: { string }
	if state.relicOffers > 0 and #state.relics < MAX_RELICS and #relicPool(player, state) > 0 then
		state.relicOffers -= 1
		state.presentingRelics = true
		pool = relicPool(player, state)
	else
		if state.relicOffers > 0 then
			-- (no room for a relic: that offer lapses)
			state.pendingLevelUps -= state.relicOffers
			state.relicOffers = 0
			if state.pendingLevelUps <= 0 then return end
		end
		state.presentingRelics = false
		pool = buildPool(player, state)
	end

	state.pendingChoices = sampleChoices(pool)
	state.rerollsRemaining = REROLLS_PER_LEVEL
	-- A room reward offers its own buffs first (those this player can take).
	local offered = state.offered
	state.offered = nil
	if offered then
		local picks: { string } = {}
		for _, id in ipairs(offered) do
			if table.find(pool, id) and #picks < 3 then table.insert(picks, id) end
		end
		for _, id in ipairs(state.pendingChoices) do
			if #picks >= 3 then break end
			if not table.find(picks, id) then table.insert(picks, id) end
		end
		state.pendingChoices = picks
	end
	state.selectionUnlockAt = os.clock() + SELECTION_LOCK_DURATION
	setGamePaused(player, true)
	sendChoices(player, state)
end

function PlayerStats.StartRun(player: Player)
	-- Last run's tome counts (read by the client's Tab tome list).
	for name in pairs(player:GetAttributes()) do
		if string.sub(name, 1, 5) == "Tome_" or string.sub(name, 1, 4) == "Evo_" or string.sub(name, 1, 11) == "ChaosBonus_" then
			player:SetAttribute(name, nil)
		end
	end
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
		talentEffects = {},
		stats = {},
		evolutions = {},
		relics = {},
		relicOffers = 0,
		curses = 0,
		presentingRelics = false,
	}
	local classId = player:GetAttribute("SelectedClass")
	if typeof(classId) == "string" then
		-- Class talents + gacha bonuses (awakening, relics).
		state.talentEffects = TalentManager.GetEffects(player, classId)
		for _, e in ipairs(GachaManager.GetEffects(player, classId)) do
			table.insert(state.talentEffects, e)
		end
	end
	states[player] = state
	player:SetAttribute("Gold", 150)
	player:SetAttribute("ArtifactCount", 0)
	player:SetAttribute("LastArtifact", "")
	applyStats(player, state)
	syncProgress(player, state)
end

-- Kill XP goes to the account level (tome choices come from room emblems).
function PlayerStats.AwardXP(player: Player, amount: number)
	AccountManager.AddXP(player, amount)
end

-- How far the current room is cleared (the room's emblem appears when done).
function PlayerStats.SetRoomProgress(player: Player, cleared: number, total: number)
	local state = states[player]
	if not state then return end
	state.xp = cleared
	state.xpToNext = math.max(total, 1)
end

-- Three random base tomes for a room reward to offer (and colour it by).
function PlayerStats.RollRewardBuffs(): { string }
	local pool = {}
	for _, id in ipairs(TomeData.Order) do
		if TomeData.IsForClass(id, nil) then table.insert(pool, id) end
	end
	return sampleChoices(pool)
end

-- One level (a tome choice) from a claimed room emblem, offering `offered`.
function PlayerStats.LevelUp(player: Player, offered: { string }?)
	local state = states[player]
	if not state then return end
	state.offered = offered
	state.level += 1
	state.pendingLevelUps += 1
	state.xp = 0
	AccountManager.AddXP(player, AccountManager.ROOM_XP)
	presentChoices(player, state)
end

-- Gold earned in the run, scaled by the Golden Tome's goldGain stat.
function PlayerStats.AwardGold(player: Player, amount: number): number
	local state = states[player]
	local rush = if WeeklyModifiers.Is("gold_rush") then 2 else 1
	local gain = math.floor(amount * ((state and state.stats.goldGain) or 1) * rush + 0.5)
	if gain <= 0 then return 0 end
	player:SetAttribute("Gold", (player:GetAttribute("Gold") or 0) + gain)
	RunStats.Add(player, "gold", gain)
	return gain
end

-- Spend gold if the player can afford it. Returns whether it was spent.
function PlayerStats.SpendGold(player: Player, amount: number): boolean
	local gold = player:GetAttribute("Gold") or 0
	if gold < amount then return false end
	player:SetAttribute("Gold", gold - amount)
	return true
end

-- A Chaos Tome's roll: one random stat tome's effect (ChaosBonus_<n>, which
-- the tome's tooltip lists).
local function rollChaos(player: Player, state: RunState)
	local chaosPool: { string } = {}
	for _, candidateId in ipairs(TomeData.Order) do
		local candidate = TomeData.GetTome(candidateId)
		if candidateId ~= "chaos" and candidateId ~= "cursed" and not TomeData.IsBoon(candidateId) and candidate and candidate.effects[1] and candidate.effects[1].value
			and TomeData.IsForClass(candidateId, player:GetAttribute("SelectedClass")) then
			table.insert(chaosPool, candidateId)
		end
	end
	if #chaosPool == 0 then return end
	local bonusId = chaosPool[math.random(1, #chaosPool)]
	table.insert(state.chaosBoosts, bonusId)
	player:SetAttribute(`ChaosBonus_{#state.chaosBoosts}`, bonusId)
end

-- Room rewards (treasure, shop, gambling): grant a tome outside the level-up
-- flow. New tomes while slots remain, otherwise a level on an owned tome.
-- `preferredId` (e.g. a shop's listed tome) is honoured when it fits.
function PlayerStats.GrantTome(player: Player, preferredId: string?): TomeData.TomeDefinition?
	local state = states[player]
	if not state then return nil end
	local slotsFull = #state.uniqueTomes >= MAX_UNIQUE_TOMES
	local tomeId: string? = nil
	if preferredId and TomeData.GetTome(preferredId) and (state.tomeCounts[preferredId] or not slotsFull)
		and (state.tomeCounts[preferredId] or 0) < TomeData.MaxLevel(preferredId) then
		tomeId = preferredId
	else
		local pool = buildPool(player, state, { chaos = true, cursed = true })
		if #pool == 0 then return nil end
		tomeId = pool[math.random(1, #pool)]
	end
	local id = tomeId :: string
	if not state.tomeCounts[id] then
		state.tomeCounts[id] = 0
		table.insert(state.uniqueTomes, id)
	end
	state.tomeCounts[id] += 1
	if id == "chaos" then rollChaos(player, state) end
	player:SetAttribute(`Tome_{id}`, state.tomeCounts[id])
	applyStats(player, state)
	checkEvolutions(player, state)
	return TomeData.GetTome(id)
end

-- A run relic found (a boss, an elite, a cursed altar): a choice of three on
-- the same cards as the tomes. False if there's no room for one.
function PlayerStats.OfferRelics(player: Player): boolean
	local state = states[player]
	if not state or #state.relics >= MAX_RELICS or #relicPool(player, state) == 0 then return false end
	state.relicOffers += 1
	state.pendingLevelUps += 1
	presentChoices(player, state)
	return true
end

-- A cursed altar's bargain accepted: a quarter of your max health, for good.
function PlayerStats.AddCurse(player: Player)
	local state = states[player]
	if not state then return end
	state.curses += 1
	player:SetAttribute("Curses", state.curses)
	applyStats(player, state)
end

-- Whether a specific tome could be granted right now (shop listings).
function PlayerStats.CanReceiveTome(player: Player, tomeId: string): boolean
	local state = states[player]
	if not state then return false end
	if (state.tomeCounts[tomeId] or 0) >= TomeData.MaxLevel(tomeId) then return false end
	return state.tomeCounts[tomeId] ~= nil or #state.uniqueTomes < MAX_UNIQUE_TOMES
end

function PlayerStats.GetStat(player: Player, stat: string): number
	local state = states[player]
	return state and (state.stats[stat] or 0) or 0
end

function PlayerStats.GetHeldTomes(player: Player): { { id: string, count: number, name: string, description: string, category: string } }
	local state = states[player]
	local list = {}
	if not state then return list end
	for _, id in ipairs(state.uniqueTomes) do
		local count = state.tomeCounts[id] or 0
		if count > 0 then
			local tome = TomeData.GetTome(id)
			table.insert(list, {
				id = id,
				count = count,
				name = (tome and tome.name) or id,
				description = (tome and tome.description) or "",
				category = (tome and tome.category) or "Base",
			})
		end
	end
	for _, id in ipairs(state.relics) do
		local count = state.tomeCounts[id] or 0
		if count > 0 then
			local tome = TomeData.GetTome(id)
			table.insert(list, {
				id = id,
				count = count,
				name = (tome and tome.name) or id,
				description = (tome and tome.description) or "",
				category = (tome and tome.category) or "Relic",
			})
		end
	end
	return list
end

function PlayerStats.DiscardTome(player: Player, tomeId: string): (boolean, string?)
	local state = states[player]
	if not state or typeof(tomeId) ~= "string" then return false, "No state" end
	local count = state.tomeCounts[tomeId]
	if not count or count <= 0 then return false, "Tome not held" end

	state.tomeCounts[tomeId] = count - 1
	if state.tomeCounts[tomeId] <= 0 then
		state.tomeCounts[tomeId] = nil
		player:SetAttribute(`Tome_{tomeId}`, nil)
		local uIdx = table.find(state.uniqueTomes, tomeId)
		if uIdx then table.remove(state.uniqueTomes, uIdx) end
		local rIdx = table.find(state.relics, tomeId)
		if rIdx then table.remove(state.relics, rIdx) end
	else
		player:SetAttribute(`Tome_{tomeId}`, state.tomeCounts[tomeId])
	end

	if tomeId == "chaos" and #state.chaosBoosts > 0 then
		local lastIdx = #state.chaosBoosts
		player:SetAttribute(`ChaosBonus_{lastIdx}`, nil)
		table.remove(state.chaosBoosts, lastIdx)
	end

	-- Check if any evolution was broken
	for _, evo in ipairs(TomeData.Evolutions) do
		if state.evolutions[evo.id] then
			if (state.tomeCounts[evo.boon] or 0) < TomeData.MaxLevel(evo.boon) or (evo.with and (state.tomeCounts[evo.with] or 0) <= 0) then
				state.evolutions[evo.id] = nil
				player:SetAttribute(`Evo_{evo.id}`, nil)
			end
		end
	end

	applyStats(player, state)
	local tome = TomeData.GetTome(tomeId)
	return true, (tome and tome.name) or tomeId
end

function PlayerStats.Init()
	Network.GetRemoteEvent(Network.Remotes.DiscardTome).OnServerEvent:Connect(function(player: Player, payload: any)
		if typeof(payload) ~= "table" then return end
		local tomeId = payload.tomeId
		local roomId = payload.roomId
		if typeof(tomeId) ~= "string" then return end
		local SpecialRooms = require(script.Parent:WaitForChild("SpecialRooms")) :: any
		if SpecialRooms.CanPurge and not SpecialRooms.CanPurge(player, roomId) then return end
		local success, name = PlayerStats.DiscardTome(player, tomeId)
		if success and SpecialRooms.OnPurged then
			SpecialRooms.OnPurged(player, roomId, name or tomeId)
		end
	end)
	Network.GetRemoteEvent(Network.Remotes.ChooseTome).OnServerEvent:Connect(function(player: Player, tomeId: any)
		local state = states[player]
		if not state or typeof(tomeId) ~= "string" or not state.pendingChoices then return end
		if os.clock() < state.selectionUnlockAt then return end
		if not table.find(state.pendingChoices, tomeId) then return end

		if (state.tomeCounts[tomeId] or 0) >= TomeData.MaxLevel(tomeId) then return end
		if TomeData.IsRelic(tomeId) and #state.relics >= MAX_RELICS then return end
		state.pendingChoices = nil
		state.pendingLevelUps -= 1
		if TomeData.IsRelic(tomeId) then
			-- (its own slots)
			table.insert(state.relics, tomeId)
			state.tomeCounts[tomeId] = 0
		elseif not state.tomeCounts[tomeId] then
			if #state.uniqueTomes >= MAX_UNIQUE_TOMES then return end
			state.tomeCounts[tomeId] = 0
			table.insert(state.uniqueTomes, tomeId)
		end
		state.tomeCounts[tomeId] += 1
		if tomeId == "chaos" then rollChaos(player, state) end
		player:SetAttribute(`Tome_{tomeId}`, state.tomeCounts[tomeId])
		applyStats(player, state)
		checkEvolutions(player, state)
		setGamePaused(player, false)
		presentChoices(player, state)
	end)

	Network.GetRemoteEvent(Network.Remotes.RerollTomes).OnServerEvent:Connect(function(player: Player)
		local state = states[player]
		if not state or not state.pendingChoices or state.rerollsRemaining <= 0 then return end
		if os.clock() < state.selectionUnlockAt then return end
		state.pendingChoices = sampleChoices(if state.presentingRelics then relicPool(player, state) else buildPool(player, state))
		state.rerollsRemaining -= 1
		state.selectionUnlockAt = os.clock() + SELECTION_LOCK_DURATION
		sendChoices(player, state)
	end)

	-- The Build Codex (the lobby's archive): the evolutions you've found.
	local function syncCodex(player: Player)
		local p = PlayerData.Get(player)
		Network.GetRemoteEvent(Network.Remotes.CodexState):FireClient(player, { discovered = if p then (p.codex or {}) else {} })
	end
	Network.GetRemoteEvent(Network.Remotes.RequestCodex).OnServerEvent:Connect(syncCodex)

	Players.PlayerRemoving:Connect(function(player)
		if states[player] and states[player].isPausingGame then
			setGamePaused(player, false)
		end
		states[player] = nil
	end)
end

return PlayerStats
