--!strict
--[[
	Corruption.luau
	The greed: what extracting does, and what staying costs.

	  EXTRACT (every third floor's golden portal, the whole party in it): the
	    run ends for everyone as a success. All the loot they carry is kept
	    (LootManager), plus two drops each, Rare or better.

	  DESCEND past an extraction floor: the dungeon wakes. Its Corruption
	    climbs, one level per floor and one per minute after that:
	      enemies +10% health and damage a level, more elites (+4% a level),
	      better loot (LootManager's luck). The HUD shows it (CorruptionHUD).

	Run attributes (RunScope): Corruption, CorruptionActive, CorruptionFloors,
	CorruptionSince (RunElapsed when it woke).
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local RunScope = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RunScope"))
local DungeonGenerator = require(script.Parent:WaitForChild("DungeonGenerator"))
local DeathManager = require(script.Parent:WaitForChild("DeathManager"))
local LootManager = require(script.Parent:WaitForChild("LootManager"))

local Corruption = {}

local PER_MINUTE = 60

local function runPlayers(runId: string): { Player }
	local out = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p:GetAttribute("RunId") == runId and p:GetAttribute("InLobby") == false then table.insert(out, p) end
	end
	return out
end

-- The party extracts: every one of them out, with everything carried.
local function extract(runId: string, party: { Player })
	for _, p in ipairs(runPlayers(runId)) do
		-- (who gave up and was only watching doesn't share the haul)
		if p:GetAttribute("Spectating") == true then
			DeathManager.EndRun(p, "fallen")
		elseif RunScope.Get(runId, "Tutorial") == true then
			-- (the tutorial's end: no haul, it can be replayed; done now)
			pcall(function() (require(script.Parent:WaitForChild("Tutorial")) :: any).Complete(p) end)
			DeathManager.EndRun(p, "extracted")
		else
			for _ = 1, 2 do LootManager.Drop(p, "extract", nil, "Rare") end
			DeathManager.EndRun(p, "extracted")
		end
	end
end

-- The party went down a floor.
local function descended(runId: string, fromLevel: number, wasExtractFloor: boolean)
	local active = RunScope.Get(runId, "CorruptionActive") == true
	if not active and not wasExtractFloor then return end
	if not active then
		RunScope.Set(runId, "CorruptionActive", true)
		RunScope.Set(runId, "CorruptionSince", RunScope.Get(runId, "RunElapsed") or 0)
		RunScope.Set(runId, "CorruptionFloors", 0)
		print(`[Corruption] Run {runId} chose greed: the dungeon wakes.`)
	end
	RunScope.Set(runId, "CorruptionFloors", (RunScope.Get(runId, "CorruptionFloors") or 0) + 1)
end

local function tick(runId: string)
	if RunScope.Get(runId, "CorruptionActive") ~= true then return end
	local elapsed = RunScope.Get(runId, "RunElapsed") or 0
	local since = RunScope.Get(runId, "CorruptionSince") or elapsed
	local level = (RunScope.Get(runId, "CorruptionFloors") or 0) + math.floor(math.max(0, elapsed - since) / PER_MINUTE)
	if level ~= RunScope.Get(runId, "Corruption") then
		RunScope.Set(runId, "Corruption", level)
	end
end

function Corruption.Init()
	DungeonGenerator.Hooks.extract = extract
	DungeonGenerator.Hooks.descended = descended
	task.spawn(function()
		while true do
			task.wait(1)
			local runs = Workspace:FindFirstChild("Runs")
			if runs then
				for _, folder in ipairs(runs:GetChildren()) do
					local ok, err = pcall(tick, folder.Name)
					if not ok then warn("[Corruption]", err) end
				end
			end
		end
	end)
end

return Corruption
