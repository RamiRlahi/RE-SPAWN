--[[
	DifficultyManager.luau
	Server-side run clock + escalating difficulty (the Threat tier).
	Publishes elapsed run seconds + difficulty tier as Workspace attributes so the
	client HUD can read them directly (attributes replicate, no remote needed).

	The clock starts when a player is actually in the dungeon and runs until
	Reset (a new run, or the whole party back at the menu); after a Reset it
	starts again with the next run.
--]]

local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local DifficultyManager = {}

-- Seconds of run time per difficulty tier.
local TIER_SECONDS = 60
-- Growth applied to spawned mobs per tier.
local HEALTH_PER_TIER = 0.25
local DAMAGE_PER_TIER = 0.12
local SPEED_PER_TIER  = 0.04
local MAX_TIER = 30

local startClock: number? = nil
local currentTier = 0

function DifficultyManager.GetElapsed(): number
	if not startClock then return 0 end
	return os.clock() - startClock
end

function DifficultyManager.GetTier(): number
	return currentTier
end

-- Multipliers applied to freshly spawned mobs.
function DifficultyManager.GetMobScale(): { health: number, damage: number, speed: number, tier: number }
	local tier = currentTier
	return {
		health = 1 + tier * HEALTH_PER_TIER,
		damage = 1 + tier * DAMAGE_PER_TIER,
		speed  = math.min(1 + tier * SPEED_PER_TIER, 1.75),
		tier = tier,
	}
end

local function playerInRun(): boolean
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr:GetAttribute("InLobby") ~= true and plr:GetAttribute("SpawnedInMap") == true then
			return true
		end
	end
	return false
end

function DifficultyManager.Start()
	if startClock then return end
	startClock = os.clock()
	currentTier = 0
	Workspace:SetAttribute("RunElapsed", 0)
	Workspace:SetAttribute("RunTier", 0)
end

-- Back to Threat 0 with the clock stopped (it starts again with the next run).
function DifficultyManager.Reset()
	startClock = nil
	currentTier = 0
	Workspace:SetAttribute("RunElapsed", 0)
	Workspace:SetAttribute("RunTier", 0)
end

-- The one clock loop: starts the clock once a player has actually entered the
-- dungeon, then ticks the elapsed time and the Threat tier while a run is on.
-- (It used to start only the first time and spawn a ticker per Start, so a
-- Reset stopped the clock for good and the Threat never went back to 0.)
task.spawn(function()
	while true do
		task.wait(0.5)
		if not startClock then
			if playerInRun() then DifficultyManager.Start() end
		else
			local elapsed = DifficultyManager.GetElapsed()
			currentTier = math.min(math.floor(elapsed / TIER_SECONDS), MAX_TIER)
			Workspace:SetAttribute("RunElapsed", math.floor(elapsed))
			Workspace:SetAttribute("RunTier", currentTier)
		end
	end
end)

return DifficultyManager
