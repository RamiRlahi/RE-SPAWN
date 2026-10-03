--[[
	DifficultyManager.luau
	Server-side run clocks + escalating difficulty (the Threat tier), one per
	run (RunManager: every party's run is its own). Publishes elapsed run
	seconds + the Threat tier on the run's folder (RunScope: RunElapsed,
	RunTier) so the HUD of everyone in it can read them directly.

	A run's clock starts when one of its players is actually in its dungeon and
	runs until Reset (a new run, or the run ending).
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RunScope = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RunScope"))
local WeeklyModifiers = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WeeklyModifiers"))

local DifficultyManager = {}

-- Seconds of run time per difficulty tier.
local TIER_SECONDS = 75
-- Growth applied to spawned mobs per tier.
local HEALTH_PER_TIER = 0.18
local DAMAGE_PER_TIER = 0.07
local SPEED_PER_TIER  = 0.03
local MAX_TIER = 30
-- Every mob hit is scaled by this (all mobs, elites and bosses).
local BASE_DAMAGE = 0.85

type Clock = { start: number?, tier: number }
local clocks: { [string]: Clock } = {}

local function clockOf(runId: string?): Clock?
	return if runId then clocks[runId] else nil
end

function DifficultyManager.GetElapsed(runId: string?): number
	local c = clockOf(runId)
	if not c or not c.start then return 0 end
	return os.clock() - c.start
end

function DifficultyManager.GetTier(runId: string?): number
	local c = clockOf(runId)
	return if c then c.tier else 0
end

-- Multipliers applied to freshly spawned mobs of `runId`.
function DifficultyManager.GetMobScale(runId: string?): { health: number, damage: number, speed: number, tier: number }
	local tier = DifficultyManager.GetTier(runId)
	-- (Corruption: every level makes the dungeon's mobs 10% tougher and harder-hitting)
	local corruption = (runId and RunScope.Get(runId, "Corruption")) or 0
	local c = 1 + 0.1 * corruption
	local moon = if WeeklyModifiers.Is("blood_moon") then 1.5 else 1
	return {
		health = (1 + tier * HEALTH_PER_TIER) * c * moon,
		damage = (BASE_DAMAGE + tier * DAMAGE_PER_TIER) * c,
		speed  = math.min(1 + tier * SPEED_PER_TIER, 1.5),
		tier = tier,
	}
end

local function playerInRun(runId: string): boolean
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr:GetAttribute("RunId") == runId and plr:GetAttribute("InLobby") ~= true and plr:GetAttribute("SpawnedInMap") == true then
			return true
		end
	end
	return false
end

-- Back to Threat 0 with the clock stopped (it starts again once someone is
-- in the run's dungeon).
function DifficultyManager.Reset(runId: string?)
	if not runId then return end
	clocks[runId] = { start = nil, tier = 0 }
	RunScope.Set(runId, "RunElapsed", 0)
	RunScope.Set(runId, "RunTier", 0)
end

-- The run is over.
function DifficultyManager.Forget(runId: string)
	clocks[runId] = nil
end

-- The one clock loop: starts each run's clock once a player has actually
-- entered its dungeon, then ticks its elapsed time and Threat tier.
task.spawn(function()
	while true do
		task.wait(0.5)
		for runId, c in pairs(clocks) do
			if not c.start then
				if playerInRun(runId) then
					c.start = os.clock()
					c.tier = 0
				end
			else
				local elapsed = os.clock() - c.start
				c.tier = math.min(math.floor(elapsed / TIER_SECONDS), MAX_TIER)
				RunScope.Set(runId, "RunElapsed", math.floor(elapsed))
				RunScope.Set(runId, "RunTier", c.tier)
			end
		end
	end
end)

return DifficultyManager
