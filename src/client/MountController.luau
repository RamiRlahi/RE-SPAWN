--!strict
--[[
	MountController.luau
	Riding (MountManager on the server): the mount key (B by default, Settings
	> Keybinds) calls your equipped mount, and sends it away again. Riding is
	faster than running; attacking or casting sends the mount away too.

	A hit while riding throws you off (MountManager → "thrown"): the tumble is
	worked out here from your momentum (Tumble.Plan), played, and the plan sent
	back so everyone else sees the same tumble ("tumble").
--]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))
local SettingsConfig = require(Shared:WaitForChild("SettingsConfig"))
local Tumble = require(script.Parent:WaitForChild("Tumble"))

local player = Players.LocalPlayer

local MountController = {}

local STILL = 6          -- slower than this: thrown off the front, the way you face

local function isMountKey(input: InputObject): boolean
	local keyName = player:GetAttribute("Keybind_Mount") or SettingsConfig.DefaultSettings.keybinds.Mount
	if typeof(keyName) ~= "string" or keyName == "" or keyName == "None" then return false end
	if input.UserInputType == Enum.UserInputType.Keyboard then return input.KeyCode.Name == keyName end
	return input.UserInputType.Name == keyName
end

local function toggle()
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not char or not hum or hum.Health <= 0 or char:GetAttribute("Tumbling") then return end
	-- (only in the lobby plaza or a run, never the menus)
	if not (player:GetAttribute("InHub") == true or player:GetAttribute("InLobby") == false) then return end
	local riding = char:GetAttribute("Riding") ~= nil
	if not riding and typeof(player:GetAttribute("Mount")) ~= "string" then return end
	Network.GetRemoteEvent(Network.Remotes.MountToggle):FireServer(not riding)
end

-- Thrown off: the tumble goes the way we were going, as far as that speed carries us.
local function thrown()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not char or not root or not hum or hum.Health <= 0 then return end
	local v = root.AssemblyLinearVelocity
	local flat = Vector3.new(v.X, 0, v.Z)
	local speed = flat.Magnitude
	local dir = if speed > STILL then flat.Unit else root.CFrame.LookVector
	local plan = Tumble.Plan(char, root, dir, speed)
	Tumble.Play(char, plan, true)
	Network.GetRemoteEvent(Network.Remotes.TumblePlan):FireServer(plan)
end

function MountController.Init()
	UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe or player:GetAttribute("SettingsOpen") == true then return end
		if isMountKey(input) then toggle() end
	end)
	Network.GetRemoteEvent(Network.Remotes.MountFX).OnClientEvent:Connect(function(msg: any)
		if typeof(msg) ~= "table" then return end
		if msg.kind == "thrown" then
			local ok, err = pcall(thrown)
			if not ok then warn("[MountController] thrown", err) end
		elseif msg.kind == "tumble" and typeof(msg.player) == "Instance" and msg.player:IsA("Player") and typeof(msg.plan) == "table" then
			local char = msg.player.Character
			if char then
				local ok, err = pcall(Tumble.Play, char, msg.plan, false)
				if not ok then warn("[MountController] tumble", err) end
			end
		end
	end)
end

return MountController
