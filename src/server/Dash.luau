--!strict
--[[
	Dash.luau
	The dash (right click by default, the "Dash" keybind: DashController): a
	quick burst along the way you're moving (or toward the cursor standing
	still). The client moves the character (it owns its physics); here, the
	dodge: a moment no hit lands (InvulnerableUntil, the same i-frames every
	mob, boss and trap already respects), and the move you were in is cut short
	(Dash.OnDash: every class server). CHARGES dashes held, each coming back
	COOLDOWN seconds after the last refilled (one at a time).
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))
local RunScope = require(Shared:WaitForChild("RunScope"))

local Dash = {}

Dash.COOLDOWN = 1.1 -- seconds for one charge to come back (DashController's is the same)
Dash.CHARGES = 3     -- dashes held at once (DashController's MAX_CHARGES; the bars by the reticle)
local LEEWAY = 0.85  -- (charges come back a little faster here, for lag)
local IFRAMES = 0.3

type Stock = { n: number, at: number }
local hooks: { (Player) -> () } = {}

-- `fn(player)` runs on every dash: the class drops the move it was in the
-- middle of (it's free to cast again, and what was left of it doesn't land).
function Dash.OnDash(fn: (Player) -> ())
	table.insert(hooks, fn)
end
local stock: { [Player]: Stock } = {}

function Dash.Init()
	Network.GetRemoteEvent(Network.Remotes.Dash).OnServerEvent:Connect(function(player: Player)
		local now = os.clock()
		local s = stock[player] or { n = Dash.CHARGES, at = now }
		stock[player] = s
		s.n = math.min(Dash.CHARGES, s.n + (now - s.at) / (Dash.COOLDOWN * LEEWAY))
		s.at = now
		if s.n < 1 then return end
		if player:GetAttribute("InLobby") ~= false or player:GetAttribute("IsDead") == true then return end
		local char = player.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if not char or not hum or hum.Health <= 0 or RunScope.Paused(char) then return end
		s.n -= 1
		for _, fn in ipairs(hooks) do task.spawn(fn, player) end
		local untilT = char:GetAttribute("InvulnerableUntil")
		char:SetAttribute("InvulnerableUntil", math.max(if typeof(untilT) == "number" then untilT else 0, now + IFRAMES))
		-- (the Forgotten Isle's dash perks: the Riftwalker Greaves, the Riftbound Blade)
		local perks = script.Parent:FindFirstChild("EquipmentPerks")
		if perks then pcall(function() (require(perks) :: any).OnDash(player) end) end
	end)
	Players.PlayerRemoving:Connect(function(p) stock[p] = nil end)
end

return Dash
