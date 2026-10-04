--[[
	MountManager.luau
	Riding in the lobby. While a player is in the hub with a mount equipped
	(the "Mount" attribute, GachaManager), they ride it: lifted onto its back
	(HipHeight) and walking faster (RideData.SpeedByRarity). Anywhere else, or
	with no mount, everything is put back. Every client draws the mount under
	them (WingsMounts) from the character's "Riding" attribute.

	Cosmetic in runs: mounts never ride (or speed anyone up) in the dungeon.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GachaRewards = require(Shared:WaitForChild("GachaRewards"))
local RideData = require(Shared:WaitForChild("RideData"))

local MountManager = {}

local BASE_SPEED = 16

local function update(player: Player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not char or not hum then return end
	local id = player:GetAttribute("Mount")
	local reward = typeof(id) == "string" and GachaRewards.Get(id) or nil
	local shouldRide = player:GetAttribute("InHub") == true and hum.Health > 0 and reward ~= nil and reward.type == "mount"
	local riding = char:GetAttribute("Riding")
	if shouldRide and reward then
		if riding ~= reward.id then
			-- (switching mounts: back to the base height first)
			local base = char:GetAttribute("BaseHipHeight")
			if typeof(base) ~= "number" then
				base = hum.HipHeight
				char:SetAttribute("BaseHipHeight", base)
			end
			hum.HipHeight = base + RideData.RideHeight(reward.look)
			char:SetAttribute("Riding", reward.id)
		end
		-- (only while they can walk: a frozen player stays frozen)
		if hum.WalkSpeed > 0 then
			hum.WalkSpeed = BASE_SPEED * (RideData.SpeedByRarity[reward.rarity] or 1.5)
		end
	elseif riding then
		local base = char:GetAttribute("BaseHipHeight")
		if typeof(base) == "number" then hum.HipHeight = base end
		char:SetAttribute("Riding", nil)
		if player:GetAttribute("InHub") == true and hum.WalkSpeed > 0 then hum.WalkSpeed = BASE_SPEED end
	end
end

function MountManager.Init()
	task.spawn(function()
		while true do
			for _, player in ipairs(Players:GetPlayers()) do
				local ok, err = pcall(update, player)
				if not ok then warn("[MountManager]", err) end
			end
			task.wait(0.25)
		end
	end)
	print("[MountManager] initialized.")
end

return MountManager
