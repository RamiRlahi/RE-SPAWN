--!strict
--[[
	Dash.luau
	The dash (right click by default, the "Dash" keybind: DashController): a
	quick burst along the way you're moving (or toward the cursor standing
	still). The client moves the character (it owns its physics); here, the
	dodge: a moment no hit lands (InvulnerableUntil, the same i-frames every
	mob, boss and trap already respects), at most once per COOLDOWN.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))
local RunScope = require(Shared:WaitForChild("RunScope"))

local Dash = {}

Dash.COOLDOWN = 1.1 -- (DashController's is the same, less a hair for lag)
local IFRAMES = 0.3

local last: { [Player]: number } = {}

function Dash.Init()
	Network.GetRemoteEvent(Network.Remotes.Dash).OnServerEvent:Connect(function(player: Player)
		local now = os.clock()
		if now - (last[player] or 0) < Dash.COOLDOWN - 0.15 then return end
		if player:GetAttribute("InLobby") ~= false or player:GetAttribute("IsDead") == true then return end
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not char or not hum or hum.Health <= 0 or RunScope.Paused(char) then return end
		last[player] = now
		local untilT = char:GetAttribute("InvulnerableUntil")
		char:SetAttribute("InvulnerableUntil", math.max(if typeof(untilT) == "number" then untilT else 0, now + IFRAMES))
		-- (the Forgotten Isle's dash perks: the Riftwalker Greaves, the Riftbound Blade)
		local perks = script.Parent:FindFirstChild("EquipmentPerks")
		if perks then pcall(function() (require(perks) :: any).OnDash(player) end) end
	end)
	Players.PlayerRemoving:Connect(function(p) last[p] = nil end)
end

return Dash
