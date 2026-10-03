--!strict
--[[
	DevHooks.luau
	Studio-only test hooks (never in a live server), so a test can grant tomes
	and relics, force drops, set the Corruption, start a horde or jump floors
	without playing there. A command is an attribute on ServerStorage.DevHooks
	(a Folder): set "Cmd" to "name|a|b"; the answer appears in "Result".
	(An attribute, not a BindableFunction: the Studio test tools may set
	properties but not invoke the game's functions.)

	  tome|userId|tomeId         a level of a tome / boon
	  relics|userId              a relic choice
	  drop|userId|rarity         a gear drop
	  corruption|runId|level     set it (wakes it)
	  horde|runId                a horde, now
	  descend|runId              straight to the next floor
	  extract|runId              the party extracts
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local DevHooks = {}

function DevHooks.Init()
	if not RunService:IsStudio() then return end
	local RunScope = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RunScope"))
	local folder = Instance.new("Folder")
	folder.Name = "DevHooks"
	local function run(cmd: string, a: any, b: any): any
		local function plr(id: any): Player?
			return Players:GetPlayerByUserId(tonumber(id) or 0)
		end
		if cmd == "tome" then
			local p = plr(a)
			local PlayerStats = require(script.Parent:WaitForChild("PlayerStats")) :: any
			local t = p and PlayerStats.GrantTome(p, b)
			return if t then t.name else "none"
		elseif cmd == "relics" then
			local p = plr(a)
			local PlayerStats = require(script.Parent:WaitForChild("PlayerStats")) :: any
			return p and PlayerStats.OfferRelics(p)
		elseif cmd == "drop" then
			local p = plr(a)
			local LootManager = require(script.Parent:WaitForChild("LootManager")) :: any
			return p and LootManager.Drop(p, "dev", nil, b)
		elseif cmd == "corruption" then
			RunScope.Set(a, "CorruptionActive", true)
			RunScope.Set(a, "CorruptionSince", RunScope.Get(a, "RunElapsed") or 0)
			RunScope.Set(a, "CorruptionFloors", tonumber(b) or 0)
			return true
		elseif cmd == "horde" then
			-- (the next tick starts it)
			RunScope.Set(a, "DevHordeNow", true)
			return true
		elseif cmd == "descend" then
			local DungeonGenerator = require(script.Parent:WaitForChild("DungeonGenerator")) :: any
			task.spawn(DungeonGenerator.NextLevel, a)
			return true
		elseif cmd == "extract" then
			local DungeonGenerator = require(script.Parent:WaitForChild("DungeonGenerator")) :: any
			local hook = DungeonGenerator.Hooks.extract
			if hook then task.spawn(hook, a, {}) end
			return hook ~= nil
		end
		return "unknown command"
	end
	folder:GetAttributeChangedSignal("Cmd"):Connect(function()
		local line = folder:GetAttribute("Cmd")
		if typeof(line) ~= "string" or line == "" then return end
		local parts = string.split(line, "|")
		local ok, res = pcall(run, parts[1], parts[2], parts[3])
		folder:SetAttribute("Result", (if ok then "ok: " else "error: ") .. tostring(res))
		folder:SetAttribute("Cmd", "")
	end)
	folder.Parent = ServerStorage
	print("[DevHooks] Studio test hooks ready (ServerStorage.DevHooks).")
end

return DevHooks
