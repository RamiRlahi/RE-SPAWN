--!strict
--[[
	RunScope.luau
	Several parties can each be in their own run at once (RunManager), so a
	run's shared state can't live on the Workspace. Each run has a folder,
	Workspace.Runs[<runId>], whose attributes hold what used to be server-wide:

	  RunTier, RunElapsed   the Threat clock (DifficultyManager)
	  RunLevel              the level (floor) of the run
	  ClearedRooms          "|id|id|" of rooms cleared
	  TomesPaused,          someone in the run is choosing a tome (the run
	  TomesChoosing         pauses), and who
	  MobsFrozenUntil       an ultimate's cutscene holds the run's mobs
	  MapId                 the map being played

	Players and mobs carry a "RunId" attribute naming their run.

	  RunScope.Of(inst)               the RunId of a player / model (or its owner)
	  RunScope.Folder(runId)          the run's folder (nil if gone)
	  RunScope.Get(runId, name)       a run attribute
	  RunScope.Set(runId, name, v)    (server) set one
	  RunScope.Mine(name)             (client) an attribute of the local player's run
--]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local RunScope = {}

local function root(create: boolean): Folder?
	local f = Workspace:FindFirstChild("Runs")
	if f and f:IsA("Folder") then return f end
	if not create then return nil end
	local nf = Instance.new("Folder")
	nf.Name = "Runs"
	nf.Parent = Workspace
	return nf
end

-- The RunId an instance belongs to: its own attribute, its model's, or (for
-- a character) its player's.
function RunScope.Of(inst: Instance?): string?
	local i = inst
	while i and i ~= Workspace and i ~= game do
		local id = i:GetAttribute("RunId")
		if typeof(id) == "string" then return id end
		if i:IsA("Model") then
			local plr = Players:GetPlayerFromCharacter(i)
			if plr then
				local pid = plr:GetAttribute("RunId")
				return if typeof(pid) == "string" then pid else nil
			end
		end
		i = i.Parent
	end
	return nil
end

function RunScope.Folder(runId: string?): Folder?
	if not runId then return nil end
	local r = root(false)
	local f = r and r:FindFirstChild(runId)
	return if f and f:IsA("Folder") then f else nil
end

-- (server) The run's folder, made if missing.
function RunScope.Create(runId: string): Folder
	local r = root(true) :: Folder
	local f = r:FindFirstChild(runId)
	if f and f:IsA("Folder") then return f end
	local nf = Instance.new("Folder")
	nf.Name = runId
	nf.Parent = r
	return nf
end

function RunScope.Destroy(runId: string)
	local f = RunScope.Folder(runId)
	if f then f:Destroy() end
end

function RunScope.Get(runId: string?, name: string): any
	local f = RunScope.Folder(runId)
	return if f then f:GetAttribute(name) else nil
end

function RunScope.Set(runId: string?, name: string, value: any)
	if not RunService:IsServer() then return end
	local f = RunScope.Folder(runId)
	if f then f:SetAttribute(name, value) end
end

-- (client) An attribute of the local player's run.
function RunScope.Mine(name: string): any
	local plr = Players.LocalPlayer
	if not plr then return nil end
	local id = plr:GetAttribute("RunId")
	return RunScope.Get(if typeof(id) == "string" then id else nil, name)
end

-- Whether `inst`'s run is paused for a tome choice.
function RunScope.Paused(inst: Instance?): boolean
	return RunScope.Get(RunScope.Of(inst), "TomesPaused") == true
end

-- Whether `inst`'s run's mobs are held by an ultimate's cutscene.
function RunScope.Frozen(inst: Instance?): boolean
	local untilT = RunScope.Get(RunScope.Of(inst), "MobsFrozenUntil")
	return typeof(untilT) == "number" and untilT > Workspace:GetServerTimeNow()
end

return RunScope
