--!strict
--[[
	Horde.luau
	Horde events: the moments the floor disappears under the dead.

	Most floors from the second on (HORDE_CHANCE), once, at a random moment
	(after HORDE_MIN..HORDE_MAX seconds on the floor, never while a boss is
	near): "A HORDE APPROACHES". For HORDE_TIME seconds the starter mobs pour
	into the room the party's in, in waves round each living player, up to
	HORDE_CAP at once. They're frail (you carve through them), and there are
	a lot of them. The music turns, the light goes red (HordeHUD).

	Survive it: everyone living gets a drop (Uncommon or better) and gold.
	When it ends, what's left of the horde crumbles.

	Run attributes (RunScope): HordeUntil (server time it ends), HordeKills.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local RunScope = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RunScope"))
local MobManager = require(script.Parent:WaitForChild("MobManager"))
local LootManager = require(script.Parent:WaitForChild("LootManager"))
local PlayerStats = require(script.Parent:WaitForChild("PlayerStats"))
local WeeklyModifiers = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("WeeklyModifiers"))

local Horde = {}

local HORDE_CHANCE = 0.75
local HORDE_MIN, HORDE_MAX = 50, 130 -- seconds into the floor
local HORDE_TIME = 60
local HORDE_CAP = 60
local WAVE_EVERY = 1.6

type RunState = { level: number, at: number?, done: boolean, mobs: { Model }, kills: number }
local runs: { [string]: RunState } = {}

local function living(runId: string): { Player }
	local out = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p:GetAttribute("RunId") == runId and p:GetAttribute("InLobby") == false and p:GetAttribute("IsDead") ~= true then
			local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
			local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
			if hum and root and hum.Health > 0 then table.insert(out, p) end
		end
	end
	return out
end

-- A boss alive near the party? (no horde over a boss fight)
local function bossNear(runId: string, at: Vector3): boolean
	local mobs = Workspace:FindFirstChild("Mobs")
	if not mobs then return false end
	for _, m in ipairs(mobs:GetChildren()) do
		if m:IsA("Model") and m:GetAttribute("IsBoss") == true and m:GetAttribute("RunId") == runId then
			local hum = m:FindFirstChildOfClass("Humanoid")
			local root = m:FindFirstChild("HumanoidRootPart") :: BasePart?
			if hum and hum.Health > 0 and root and (root.Position - at).Magnitude < 90 then return true end
		end
	end
	return false
end

-- A spot on the floor of the room round `p` (not right on top of them).
local function spotNear(p: Player): Vector3?
	local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return nil end
	local b = MobManager.RoomBoundsAt(root.Position)
	for _ = 1, 6 do
		local pos: Vector3
		if b then
			local x = math.random() * (b.maxX - b.minX - 8) + b.minX + 4
			local z = math.random() * (b.maxZ - b.minZ - 8) + b.minZ + 4
			pos = Vector3.new(x, b.floorY, z)
		else
			local a = math.random() * math.pi * 2
			local r = 16 + math.random() * 12
			pos = Vector3.new(root.Position.X + math.cos(a) * r, root.Position.Y - 3, root.Position.Z + math.sin(a) * r)
		end
		local flat = Vector3.new(pos.X - root.Position.X, 0, pos.Z - root.Position.Z)
		if flat.Magnitude >= 10 then return pos end
	end
	return nil
end

local function alive(list: { Model }): number
	local n = 0
	for i = #list, 1, -1 do
		local m = list[i]
		local hum = m.Parent and m:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then n += 1 else table.remove(list, i) end
	end
	return n
end

local function runHorde(runId: string, st: RunState)
	local endsAt = Workspace:GetServerTimeNow() + HORDE_TIME
	RunScope.Set(runId, "HordeUntil", endsAt)
	RunScope.Set(runId, "HordeKills", 0)
	print(`[Horde] Run {runId}: a horde approaches (floor {st.level}).`)
	local tier = RunScope.Get(runId, "RunTier") or 0
	local perWave = 3 + math.min(4, math.floor(tier / 2))
	while Workspace:GetServerTimeNow() < endsAt do
		if RunScope.Get(runId, "RunLevel") ~= st.level then break end -- (they went down)
		local party = living(runId)
		if #party == 0 then break end
		if RunScope.Get(runId, "TomesPaused") ~= true then
			local cap = if WeeklyModifiers.Is("swarm") then math.floor(HORDE_CAP * 1.3) else HORDE_CAP
			local room = cap - alive(st.mobs)
			for _, p in ipairs(party) do
				for _ = 1, math.min(perWave, room) do
					local at = spotNear(p)
					if at then
						local m = MobManager.SpawnMinion(at)
						if m then
							m:SetAttribute("Horde", true)
							-- frail: you carve through them
							local hum = m:FindFirstChildOfClass("Humanoid")
							if hum then
								hum.MaxHealth = math.max(1, math.floor(hum.MaxHealth * 0.45))
								hum.Health = hum.MaxHealth
								hum.Died:Connect(function()
									st.kills += 1
									RunScope.Set(runId, "HordeKills", st.kills)
								end)
							end
							table.insert(st.mobs, m)
							room -= 1
						end
					end
				end
			end
		end
		task.wait(WAVE_EVERY)
	end
	-- Over: what's left crumbles; the survivors are rewarded.
	RunScope.Set(runId, "HordeUntil", nil)
	for _, m in ipairs(st.mobs) do
		local hum = m.Parent and m:FindFirstChildOfClass("Humanoid")
		if hum and hum.Health > 0 then hum.Health = 0 end
	end
	table.clear(st.mobs)
	if RunScope.Get(runId, "RunLevel") == st.level then
		for _, p in ipairs(living(runId)) do
			LootManager.Drop(p, "horde", nil, "Uncommon")
			PlayerStats.AwardGold(p, 60)
		end
	end
	print(`[Horde] Run {runId}: the horde breaks ({st.kills} slain).`)
end

local function tick(runId: string)
	local level = RunScope.Get(runId, "RunLevel") or 1
	local elapsed = RunScope.Get(runId, "RunElapsed") or 0
	local st = runs[runId]
	if not st or st.level ~= level then
		-- a new floor: will it have a horde, and when?
		st = { level = level, at = nil, done = false, mobs = {}, kills = 0 }
		local swarm = WeeklyModifiers.Is("swarm")
		if (level >= 2 or swarm) and (swarm or math.random() < HORDE_CHANCE) then
			st.at = elapsed + HORDE_MIN + math.random() * (HORDE_MAX - HORDE_MIN)
		end
		runs[runId] = st
	end
	if RunScope.Get(runId, "DevHordeNow") == true then
		RunScope.Set(runId, "DevHordeNow", nil)
		st.done = false
		st.at = elapsed
	end
	if st.done or not st.at or elapsed < st.at then return end
	local party = living(runId)
	if #party == 0 then return end
	local root = party[1].Character and party[1].Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end
	if bossNear(runId, root.Position) or RunScope.Get(runId, "CollapseAt") ~= nil then
		st.at = elapsed + 20 -- (later: not over a boss fight, not while it's coming down)
		return
	end
	st.done = true
	task.spawn(runHorde, runId, st)
end

function Horde.Init()
	task.spawn(function()
		while true do
			task.wait(1)
			local folder = Workspace:FindFirstChild("Runs")
			if folder then
				for _, f in ipairs(folder:GetChildren()) do
					local ok, err = pcall(tick, f.Name)
					if not ok then warn("[Horde]", err) end
				end
				-- (forget runs that are gone)
				for id in pairs(runs) do
					if not folder:FindFirstChild(id) then runs[id] = nil end
				end
			end
		end
	end)
end

return Horde
