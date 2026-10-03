--!strict
--[[
	RunStats.luau
	What each player does in a run, counted for the post-run summary:

	  kills (and how many were elites, bosses), the best kill streak, damage
	  dealt (and the biggest single hit), damage taken, deaths, healing done,
	  abilities used, allies revived, and what the run earned them: gold
	  collected, souls, account XP, summon tickets, loot. With the floor
	  reached, the time and the Threat.

	When the run ends for someone (they leave, fall for good, extract, or the
	party wipes), Finish sends them the summary (RunSummary): their numbers,
	their rewards, and their party's numbers beside them.

	  RunStats.Begin(player, runId)            a run starts for them (fresh counters)
	  RunStats.Add(player, key, n)             count something (ignored outside a run)
	  RunStats.OnDamage(player, target, n)     every hit a player lands (SkillManager)
	  RunStats.AddLoot(player, item)           something they found, for the summary
	  RunStats.Finish(player, result)          "left" | "fallen" | "extracted" | "wiped"
	  RunStats.Of(player)                      the live counters (or nil)
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))
local RunScope = require(Shared:WaitForChild("RunScope"))
local PlayerData = require(script.Parent:WaitForChild("PlayerData"))

local RunStats = {}

export type Counters = {
	kills: number, elites: number, bosses: number,
	streak: number, bestStreak: number,
	damage: number, bestHit: number,
	taken: number, deaths: number,
	healing: number, abilities: number, revives: number,
	gold: number, souls: number, xp: number, tickets: number,
	synergies: number,
}

type Record = {
	userId: number,
	name: string,
	classId: string,
	runId: string,
	startedAt: number,
	c: Counters,
	loot: { any },
	lastKill: number,
	finished: boolean,
	conns: { RBXScriptConnection },
}

local STREAK_WINDOW = 2.5 -- kills this close together keep a streak going

local live: { [Player]: Record } = {}
local byRun: { [string]: { [number]: Record } } = {} -- (kept for the party table, finished or not)

local function zero(): Counters
	return {
		kills = 0, elites = 0, bosses = 0, streak = 0, bestStreak = 0,
		damage = 0, bestHit = 0, taken = 0, deaths = 0,
		healing = 0, abilities = 0, revives = 0,
		gold = 0, souls = 0, xp = 0, tickets = 0,
		synergies = 0,
	}
end

-- Damage taken and deaths: watched on each character they play in the run.
local function watch(rec: Record, player: Player, char: Model)
	local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
	if not hum or rec.finished then return end
	local last = hum.Health
	table.insert(rec.conns, hum.HealthChanged:Connect(function(h)
		if h < last then rec.c.taken += last - h end
		last = h
	end))
	table.insert(rec.conns, hum.Died:Connect(function()
		if player:GetAttribute("InLobby") == false then rec.c.deaths += 1 end
	end))
end

local function stop(rec: Record)
	for _, c in ipairs(rec.conns) do c:Disconnect() end
	table.clear(rec.conns)
end

function RunStats.Begin(player: Player, runId: string)
	local old = live[player]
	if old then stop(old) end
	local classId = player:GetAttribute("SelectedClass")
	local rec: Record = {
		userId = player.UserId,
		name = player.DisplayName,
		classId = if typeof(classId) == "string" then classId else "",
		runId = runId,
		startedAt = os.clock(),
		c = zero(),
		loot = {},
		lastKill = 0,
		finished = false,
		conns = {},
	}
	live[player] = rec
	byRun[runId] = byRun[runId] or {}
	byRun[runId][player.UserId] = rec
	if player.Character then task.spawn(watch, rec, player, player.Character) end
	table.insert(rec.conns, player.CharacterAdded:Connect(function(char) watch(rec, player, char) end))
end

function RunStats.Of(player: Player): Counters?
	local rec = live[player]
	return if rec then rec.c else nil
end

function RunStats.Add(player: Player, key: string, n: number)
	local rec = live[player]
	if not rec or n == 0 then return end
	local c = rec.c :: any
	if typeof(c[key]) == "number" then c[key] += n end
end

-- Every hit a player lands; the killing blow counts the kill.
function RunStats.OnDamage(player: Player, target: { character: Model, humanoid: Humanoid }, amount: number)
	local rec = live[player]
	if not rec then return end
	rec.c.damage += amount
	if amount > rec.c.bestHit then rec.c.bestHit = amount end
	if target.humanoid.Health > 0 or target.character:GetAttribute("RS_Killed") then return end
	target.character:SetAttribute("RS_Killed", true)
	rec.c.kills += 1
	if target.character:GetAttribute("IsBoss") == true then
		rec.c.bosses += 1
	elseif target.character:GetAttribute("IsElite") == true then
		rec.c.elites += 1
	end
	local now = os.clock()
	rec.c.streak = if now - rec.lastKill <= STREAK_WINDOW then rec.c.streak + 1 else 1
	rec.lastKill = now
	if rec.c.streak > rec.c.bestStreak then rec.c.bestStreak = rec.c.streak end
end

-- What happens to the loot as the run ends (LootManager: kept or lost).
local settle: ((Player, string, { any }) -> ())? = nil
function RunStats.SetSettle(fn: (Player, string, { any }) -> ())
	settle = fn
end

function RunStats.AddLoot(player: Player, item: any)
	local rec = live[player]
	if rec then table.insert(rec.loot, item) end
end

-- What a finished run is worth on top of what it already paid out as it
-- went: souls and account XP for every floor you got down to.
local FLOOR_SOULS = 2
local FLOOR_XP = 120

local function publicRow(rec: Record): any
	return {
		userId = rec.userId, name = rec.name, classId = rec.classId,
		kills = rec.c.kills, damage = math.floor(rec.c.damage), healing = math.floor(rec.c.healing),
		taken = math.floor(rec.c.taken), revives = rec.c.revives,
	}
end

-- The run's over for `player`: pays the floor bonus and sends the summary.
function RunStats.Finish(player: Player, result: string)
	local rec = live[player]
	if not rec or rec.finished then return end
	live[player] = nil
	rec.finished = true
	stop(rec)
	local runId = rec.runId
	local floor = RunScope.Get(runId, "RunLevel") or 1
	local elapsed = RunScope.Get(runId, "RunElapsed") or math.floor(os.clock() - rec.startedAt)
	local tier = RunScope.Get(runId, "RunTier") or 0
	local mapId = RunScope.Get(runId, "MapId")

	-- The floor bonus (paid now, so it's in the totals below).
	local bonusSouls = FLOOR_SOULS * floor
	local bonusXP = FLOOR_XP * floor
	pcall(function()
		local TalentManager = require(script.Parent:WaitForChild("TalentManager")) :: any
		TalentManager.AwardSouls(player, bonusSouls)
	end)
	pcall(function()
		local AccountManager = require(script.Parent:WaitForChild("AccountManager")) :: any
		AccountManager.AddXP(player, bonusXP)
	end)

	if settle then
		local ok, err = pcall(settle, player, result, rec.loot)
		if not ok then warn("[RunStats] settling loot:", err) end
	end

	-- Lifetime records (the profile): deepest floor, runs, extractions, kills.
	local records = nil
	local p = PlayerData.Get(player) :: any
	local newBest = false
	if p then
		p.records = p.records or {}
		local r = p.records
		r.runs = (r.runs or 0) + 1
		r.kills = (r.kills or 0) + rec.c.kills
		r.elites = (r.elites or 0) + rec.c.elites
		r.bosses = (r.bosses or 0) + rec.c.bosses
		if result == "extracted" then r.extractions = (r.extractions or 0) + 1 end
		if floor > (r.bestFloor or 0) then
			newBest = (r.bestFloor or 0) > 0
			r.bestFloor = floor
		end
		local corruption = RunScope.Get(runId, "Corruption") or 0
		if corruption > (r.bestCorruption or 0) then r.bestCorruption = corruption end
		PlayerData.MarkDirty(player)
		records = { bestFloor = r.bestFloor, runs = r.runs, extractions = r.extractions or 0, newBest = newBest }
	end
	-- (the Endless Abyss: the Hall of the Deep; and the bests the map picker reads)
	pcall(function()
		local Leaderboard = require(script.Parent:WaitForChild("Leaderboard")) :: any
		local MapData = require(Shared:WaitForChild("MapData")) :: any
		local map = MapData.Get(mapId)
		if map and map.endless then Leaderboard.Submit(player, floor) else Leaderboard.SyncBests(player) end
	end)

	local party = {}
	for uid, other in pairs(byRun[runId] or {}) do
		if uid ~= rec.userId then table.insert(party, publicRow(other)) end
	end
	table.sort(party, function(a, b) return a.damage > b.damage end)

	local c = rec.c
	local summary = {
		result = result,
		mapId = mapId,
		classId = rec.classId,
		floor = floor,
		time = elapsed,
		tier = tier,
		stats = {
			kills = c.kills, elites = c.elites, bosses = c.bosses, bestStreak = c.bestStreak,
			damage = math.floor(c.damage), bestHit = math.floor(c.bestHit),
			taken = math.floor(c.taken), deaths = c.deaths,
			healing = math.floor(c.healing), abilities = c.abilities, revives = c.revives,
			synergies = c.synergies,
		},
		rewards = {
			-- (souls / XP: everything the run gave, the floor bonus included)
			souls = c.souls + bonusSouls, xp = c.xp + bonusXP, gold = c.gold, tickets = c.tickets,
			floorSouls = bonusSouls, floorXP = bonusXP,
			loot = rec.loot,
		},
		party = party,
		level = player:GetAttribute("AccountLevel"),
		records = records,
		corruption = RunScope.Get(runId, "Corruption") or 0,
	}
	Network.GetRemoteEvent(Network.Remotes.RunSummary):FireClient(player, summary)

	-- Forget the run once nobody's left in it.
	local anyLive = false
	for _, other in pairs(byRun[runId] or {}) do
		if not other.finished then anyLive = true end
	end
	if not anyLive then byRun[runId] = nil end
end

function RunStats.Init()
	Players.PlayerRemoving:Connect(function(p)
		local rec = live[p]
		if rec then
			stop(rec)
			rec.finished = true
			live[p] = nil
		end
	end)
end

return RunStats
