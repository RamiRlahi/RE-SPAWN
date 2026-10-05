--[[
	MountManager.luau
	Riding. The mount key (B, MountController) calls the
	equipped mount (the "Mount" attribute, GachaManager): the rider is lifted
	onto its back (HipHeight) and goes faster than running (RideData.Speed,
	the client's AnimationController). Pressing it again sends it away; so
	does attacking or casting (SkillManager calls Dismount), dying, or going
	back to the menus. Every client draws the mount under the rider
	(WingsMounts) from the character's "Riding" attribute.

	Thrown: taking a hit while riding throws the rider off. The mount
	vanishes; the rider's own client works out the tumble from their momentum
	(Tumble, TumbleData) and sends the plan back here, which passes it on to
	everyone else. "Tumbling" (on the character) blocks attacks, skills and
	the mount until they're back on their feet.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GachaRewards = require(Shared:WaitForChild("GachaRewards"))
local RideData = require(Shared:WaitForChild("RideData"))
local TumbleData = require(Shared:WaitForChild("TumbleData"))
local Network = require(Shared:WaitForChild("Network"))

local MountManager = {}

local REMOUNT = 1.2           -- seconds after getting up before the mount can be called again
local PLAN_WAIT = 1.5         -- (the rider's plan never came: back up after this long)

local want: { [Player]: boolean } = {}
local tumbleUntil: { [Player]: number } = {}
local cooldownUntil: { [Player]: number } = {}

local function mountOf(player: Player): any?
	local id = player:GetAttribute("Mount")
	local reward = typeof(id) == "string" and GachaRewards.Get(id) or nil
	return if reward and reward.type == "mount" then reward else nil
end

-- In the lobby plaza or in a run (not the menus), alive, on their feet.
local function canRide(player: Player, char: Model, hum: Humanoid): boolean
	if hum.Health <= 0 then return false end
	if not (player:GetAttribute("InHub") == true or player:GetAttribute("InLobby") == false) then return false end
	if player:GetAttribute("IsDead") or player:GetAttribute("Spectating") then return false end
	if char:GetAttribute("Tumbling") then return false end
	return true
end

local function mount(char: Model, hum: Humanoid, reward: any)
	if char:GetAttribute("Riding") == reward.id then return end
	-- (switching mounts: back to the base height first)
	local base = char:GetAttribute("BaseHipHeight")
	if typeof(base) ~= "number" then
		base = hum.HipHeight
		char:SetAttribute("BaseHipHeight", base)
	end
	-- (seated astride: hips on the mount's back, legs bent round it)
	local legLen = if hum.RigType == Enum.HumanoidRigType.R6 then 2 else math.max(base, 1)
	hum.HipHeight = base + RideData.SeatLift(reward.look, legLen)
	char:SetAttribute("Riding", reward.id)
end

local function dismount(char: Model, hum: Humanoid)
	if not char:GetAttribute("Riding") then return end
	local base = char:GetAttribute("BaseHipHeight")
	if typeof(base) == "number" then hum.HipHeight = base end
	char:SetAttribute("Riding", nil)
end

local function update(player: Player)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not char or not hum then return end
	-- back on their feet
	local tu = tumbleUntil[player]
	if tu and os.clock() >= tu then
		tumbleUntil[player] = nil
		char:SetAttribute("Tumbling", nil)
		cooldownUntil[player] = os.clock() + REMOUNT
	end
	local reward = mountOf(player)
	if want[player] and reward and canRide(player, char, hum) then
		mount(char, hum, reward)
	else
		want[player] = nil
		dismount(char, hum)
	end
end

-- Off the mount, no tumble (attacking, casting).
function MountManager.Dismount(player: Player)
	if not want[player] then return end
	want[player] = nil
	update(player)
end

function MountManager.IsTumbling(player: Player): boolean
	return tumbleUntil[player] ~= nil
end

-- A hit while riding: the mount vanishes and the rider is thrown off.
local function thrown(player: Player, char: Model, hum: Humanoid)
	want[player] = nil
	tumbleUntil[player] = os.clock() + PLAN_WAIT
	-- (told first, so the rider's client holds the body before the lowered
	-- HipHeight drops it)
	Network.GetRemoteEvent(Network.Remotes.MountFX):FireClient(player, { kind = "thrown" })
	char:SetAttribute("Tumbling", true)
	dismount(char, hum)
end

-- The rider's client sends how its tumble goes: checked, then passed on.
local function onPlan(player: Player, plan: any)
	if typeof(plan) ~= "table" or not tumbleUntil[player] then return end
	local dir, speed, dist, rolls = plan.dir, plan.speed, plan.dist, plan.rolls
	if typeof(dir) ~= "Vector3" or typeof(speed) ~= "number" or typeof(dist) ~= "number" or typeof(rolls) ~= "number" then return end
	local flat = Vector3.new(dir.X, 0, dir.Z)
	if flat.Magnitude < 0.01 or speed ~= speed or dist ~= dist then return end
	local clean = {
		dir = flat.Unit,
		speed = math.clamp(speed, 0, TumbleData.MAX_SPEED),
		dist = math.clamp(dist, 0, TumbleData.MAX_SPEED),
		rolls = math.clamp(math.floor(rolls), 0, 4),
		yaw = math.clamp(tonumber(plan.yaw) or 0, -math.pi, math.pi),
		lift = math.clamp(tonumber(plan.lift) or 0, 0, 10),
		startedAt = tonumber(plan.startedAt) or workspace:GetServerTimeNow(),
	}
	local elapsed = math.clamp(workspace:GetServerTimeNow() - clean.startedAt, 0, 1)
	tumbleUntil[player] = os.clock() + TumbleData.Times(clean).total - elapsed
	local fx = Network.GetRemoteEvent(Network.Remotes.MountFX)
	for _, other in ipairs(Players:GetPlayers()) do
		if other ~= player then fx:FireClient(other, { kind = "tumble", player = player, plan = clean }) end
	end
end

local function watchCharacter(player: Player, char: Model)
	want[player] = nil
	tumbleUntil[player] = nil
	local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
	if not hum then return end
	local lastHealth, lastMax = hum.Health, hum.MaxHealth
	hum.HealthChanged:Connect(function(health: number)
		local hit = health < lastHealth - 0.5 and hum.MaxHealth == lastMax
		lastHealth, lastMax = health, hum.MaxHealth
		if hit and health > 0 and char:GetAttribute("Riding") then thrown(player, char, hum) end
	end)
end

-- Call the mount (on) or send it away.
function MountManager.Request(player: Player, on: boolean)
	if on then
		if tumbleUntil[player] or os.clock() < (cooldownUntil[player] or 0) then return end
		want[player] = true
	else
		want[player] = nil
	end
	update(player)
end

function MountManager.Init()
	Network.GetRemoteEvent(Network.Remotes.MountToggle).OnServerEvent:Connect(function(player: Player, on: any)
		MountManager.Request(player, on == true)
	end)
	Network.GetRemoteEvent(Network.Remotes.TumblePlan).OnServerEvent:Connect(onPlan)
	local function hook(player: Player)
		player.CharacterAdded:Connect(function(char) watchCharacter(player, char) end)
		if player.Character then task.spawn(watchCharacter, player, player.Character) end
	end
	Players.PlayerAdded:Connect(hook)
	for _, p in ipairs(Players:GetPlayers()) do hook(p) end
	Players.PlayerRemoving:Connect(function(p)
		want[p], tumbleUntil[p], cooldownUntil[p] = nil, nil, nil
	end)
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
