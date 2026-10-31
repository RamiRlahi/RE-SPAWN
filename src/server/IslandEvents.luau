--!strict
--[[
	IslandEvents.luau
	The Forgotten Isle's world events (IslandConfig.Events): the first a while
	into the run, then one every few minutes, never the same twice running.
	Each is announced on every HUD of the run (IslandEvent "event", and
	"event_end"), and sets RunScope "IslandEvent" while it lasts (the clients'
	sky: the rifts' violet, the blood moon's red).

	  RIFT SURGE       purple gates break open in the sky over the island,
	                   light pouring down from them: more enemies, more XP,
	                   better loot while they're open
	  CURSED TREASURE  a cursed chest surfaces somewhere on the island (its
	                   beam seen from afar): break its seal, survive its ambush
	  ANCIENT ECHO     a forgotten shrine rises: whoever communes with it
	                   wakes a blessing for the whole run (stronger, faster)
	                   or, sometimes, a curse (savage enemies, richer loot)
	  ELITE HUNT       a great named beast roams the island: slay it for an
	                   Elite Chest and gold for everyone
	  BLOOD MOON       the moon bleeds: enemies hit harder and come faster and
	                   in greater numbers; XP and loot are richer

	Their numbers go through the run's modifiers (IslandMode.Mods: spawn, xp,
	loot, damage, speed), which only this module writes: each event's own
	are multiplied together while it lasts, and taken off when it ends.

	  IslandEvents.Start(runId) / Stop(runId)   (IslandMode)
	  IslandEvents.Force(runId, eventId) → string   (DevHooks isle_event)
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local IslandConfig = require(Shared:WaitForChild("IslandConfig"))
local RunScope = require(Shared:WaitForChild("RunScope"))
local IslandGenerator = require(script.Parent:WaitForChild("IslandGenerator"))
local IslandMode = require(script.Parent:WaitForChild("IslandMode"))
local MobManager = require(script.Parent:WaitForChild("MobManager"))
local PlayerStats = require(script.Parent:WaitForChild("PlayerStats"))

local IslandEvents = {}

local E = IslandConfig.Events
local rgb = Color3.fromRGB
local RIFT = rgb(175, 80, 255)

type Mods = IslandMode.Mods
type Active = { id: string, mods: { [string]: number }, ends: number, cleanup: { () -> () } }
type RunEvents = {
	runId: string,
	island: any,
	alive: boolean,
	active: Active?,
	last: string?,
	nextAt: number,
	rng: Random,
}

local runs: { [string]: RunEvents } = {}

-- What each does to the run's modifiers while it lasts.
local MODS: { [string]: { [string]: number } } = {
	rift_surge = { spawn = 1.6, xp = 1.5, loot = 1.3 },
	blood_moon = { spawn = 1.3, damage = 1.35, speed = 1.15, xp = 1.4, loot = 1.5 },
}
local ECHO_BLESSING = {
	{ stat = "damage", operation = "multiplier", value = 0.25 },
	{ stat = "movementSpeed", operation = "percent", value = 0.2 },
}
local ECHO_CURSE = { damage = 1.3, loot = 1.6 }
local ECHO_BUFF_SECONDS = 90
local HUNT_GOLD = 150

-- ── Helpers ─────────────────────────────────────────────────────────────────
local function setMods(re: RunEvents, mods: { [string]: number }?)
	local st = IslandMode.Of(re.runId)
	if not st then return end
	local m: Mods = { spawn = 1, xp = 1, loot = 1, damage = 1, speed = 1 }
	if mods then
		for k, v in pairs(mods) do (m :: any)[k] = ((m :: any)[k] or 1) * v end
	end
	st.mods = m
end

local function part(props: { [string]: any }, parent: Instance): BasePart
	local p = Instance.new("Part")
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material = Enum.Material.Neon
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	for k, v in pairs(props) do (p :: any)[k] = v end
	p.Parent = parent
	return p
end

-- A tall pale beam up from `pos`, so it's seen from across the island.
local function beacon(pos: Vector3, color: Color3, parent: Instance): BasePart
	return part({ Size = Vector3.new(2.5, 220, 2.5), CFrame = CFrame.new(pos + Vector3.new(0, 110, 0)), Color = color, Transparency = 0.6 }, parent)
end

local function living(re: RunEvents)
	return IslandMode.Living(re.runId)
end

-- ── Rift Surge: the gates in the sky ────────────────────────────────────────
-- A ring of jagged violet shards round a black heart, cracks spidering out of
-- it and a shaft of light down to the ground; when the surge ends its shards
-- fly apart and fade.
local function skyGate(center: Vector3, ground: Vector3, size: number, rng: Random, parent: Instance): { BasePart }
	local parts: { BasePart } = {}
	local facing = CFrame.lookAt(center, Vector3.new(ground.X, center.Y, ground.Z) + Vector3.new(0.01, 0, 0)) * CFrame.Angles(math.rad(-60), 0, 0)
	table.insert(parts, part({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.6, size * 1.5, size * 1.5),
		CFrame = facing * CFrame.Angles(0, math.rad(90), 0), Color = rgb(12, 0, 24), Material = Enum.Material.SmoothPlastic, Transparency = 0.05 }, parent))
	local n = 14
	for i = 0, n - 1 do
		local a = i / n * math.pi * 2 + rng:NextNumber(-0.1, 0.1)
		local r = size * rng:NextNumber(0.78, 0.95)
		local len = size * rng:NextNumber(0.35, 0.6)
		table.insert(parts, part({ Size = Vector3.new(rng:NextNumber(1, 2.2), len, rng:NextNumber(1, 2)), Color = RIFT, Transparency = 0.1,
			CFrame = facing * CFrame.new(math.cos(a) * r, math.sin(a) * r, 0) * CFrame.Angles(0, 0, a + math.pi / 2 + rng:NextNumber(-0.3, 0.3)) }, parent))
	end
	for _ = 1, 7 do
		local a = rng:NextNumber(0, math.pi * 2)
		local len = size * rng:NextNumber(0.6, 1.3)
		table.insert(parts, part({ Size = Vector3.new(0.5, len, 0.3), Color = rgb(225, 170, 255), Transparency = 0.3,
			CFrame = facing * CFrame.new(math.cos(a) * (size * 0.75 + len / 2), math.sin(a) * (size * 0.75 + len / 2), 0) * CFrame.Angles(0, 0, a + math.pi / 2) }, parent))
	end
	local d = ground - center
	table.insert(parts, part({ Size = Vector3.new(size * 0.5, size * 0.5, d.Magnitude), CFrame = CFrame.lookAt((center + ground) / 2, ground),
		Color = RIFT, Transparency = 0.82 }, parent))
	return parts
end

local function breakGate(parts: { BasePart }, center: Vector3)
	for _, p in ipairs(parts) do
		if p.Parent then
			local out = (p.Position - center)
			out = if out.Magnitude > 0.1 then out.Unit else Vector3.new(0, 1, 0)
			TweenService:Create(p, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
				{ CFrame = p.CFrame + out * 30, Transparency = 1 }):Play()
			Debris:AddItem(p, 1.5)
		end
	end
end

local START: { [string]: (RunEvents, Active, Folder) -> { [string]: any }? } = {}

START.rift_surge = function(re, ev, folder)
	local island = re.island
	local gates: { { parts: { BasePart }, center: Vector3 } } = {}
	local sources = island.sources :: { any }
	for i = 1, 4 do
		local src = sources[re.rng:NextInteger(1, #sources)]
		local g = src.pos
		local center = Vector3.new(g.X, island.origin.Y + 150 + re.rng:NextNumber(0, 40), g.Z) + Vector3.new(re.rng:NextNumber(-30, 30), 0, re.rng:NextNumber(-30, 30))
		table.insert(gates, { parts = skyGate(center, g, 34 + i * 5, re.rng, folder), center = center })
	end
	table.insert(ev.cleanup, function()
		for _, gate in ipairs(gates) do breakGate(gate.parts, gate.center) end
	end)
	return nil
end

START.cursed_treasure = function(re, ev, folder)
	local island = re.island
	-- (the spots of the isles still standing)
	local spots = {}
	for _, s in ipairs(island.chestSpots :: { any }) do
		if not s.gone then table.insert(spots, s) end
	end
	if #spots == 0 then return end
	-- somewhere far from everyone, so it's a trip
	local best, bestD = nil, -1
	for _ = 1, 10 do
		local s = spots[re.rng:NextInteger(1, #spots)]
		local near = math.huge
		for _, e in ipairs(living(re)) do near = math.min(near, (e.root.Position - s.cf.Position).Magnitude) end
		if near > 120 and near < 600 and near > bestD then best, bestD = s, near end
	end
	best = best or spots[re.rng:NextInteger(1, #spots)]
	local chests = script.Parent:FindFirstChild("IslandChests")
	local model: Model? = nil
	if chests then
		model = (require(chests) :: any).Spawn(re.runId, "cursed", best.cf * CFrame.new(2, 0, 2))
	end
	local beam = beacon(best.cf.Position, rgb(255, 60, 70), folder)
	table.insert(ev.cleanup, function()
		if beam.Parent then beam:Destroy() end
	end)
	-- (it ends early once the chest is opened)
	if model then
		task.spawn(function()
			while re.alive and re.active == ev and model.Parent do task.wait(1) end
			if beam.Parent then beam:Destroy() end
		end)
	end
	return { pos = best.cf.Position }
end

START.ancient_echo = function(re, ev, folder)
	local spots = re.island.shrineSpots :: { CFrame }
	if #spots == 0 then return nil end
	local cf = spots[re.rng:NextInteger(1, #spots)]
	local m = Instance.new("Model")
	m.Name = "EchoShrine"
	local base = part({ Size = Vector3.new(7, 2, 7), CFrame = cf * CFrame.new(0, 1, 0), Color = rgb(70, 66, 80), Material = Enum.Material.Slate, CanCollide = true }, m)
	part({ Size = Vector3.new(4.5, 4, 4.5), CFrame = cf * CFrame.new(0, 4, 0), Color = rgb(90, 86, 100), Material = Enum.Material.Slate, CanCollide = true }, m)
	local crystal = part({ Size = Vector3.new(2, 3.6, 2), CFrame = cf * CFrame.new(0, 8.4, 0) * CFrame.Angles(0, math.rad(45), math.rad(12)), Color = rgb(120, 230, 255) }, m)
	for k = 0, 3 do
		local a = k / 4 * math.pi * 2
		part({ Size = Vector3.new(1, 5, 1), CFrame = cf * CFrame.new(math.cos(a) * 5, 2.5, math.sin(a) * 5), Color = rgb(60, 56, 70), Material = Enum.Material.Slate, CanCollide = true }, m)
		part({ Size = Vector3.new(0.6, 0.6, 0.6), CFrame = cf * CFrame.new(math.cos(a) * 5, 5.4, math.sin(a) * 5), Color = rgb(120, 230, 255) }, m)
	end
	m.PrimaryPart = base
	m.Parent = folder
	-- it rises out of the ground
	local final = m:GetPivot()
	m:PivotTo(final - Vector3.new(0, 10, 0))
	task.spawn(function()
		for i = 1, 20 do
			if not m.Parent then return end
			m:PivotTo((final - Vector3.new(0, 10, 0)):Lerp(final, i / 20))
			task.wait(0.05)
		end
	end)
	local beam = beacon(cf.Position, rgb(120, 230, 255), folder)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Commune"
	prompt.ObjectText = "Forgotten Shrine"
	prompt.HoldDuration = 1.5
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt.Parent = crystal
	prompt.Triggered:Connect(function(p: Player)
		if p:GetAttribute("RunId") ~= re.runId or p:GetAttribute("InLobby") ~= false or re.active ~= ev then return end
		local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 or not prompt.Parent then return end
		prompt:Destroy()
		if beam.Parent then beam:Destroy() end
		local blessed = re.rng:NextNumber() < 0.65
		if blessed then
			for _, e in ipairs(living(re)) do
				PlayerStats.SetExtraEffects(e.player, "echo", ECHO_BLESSING)
				local who = e.player
				task.delay(ECHO_BUFF_SECONDS, function()
					if who.Parent then PlayerStats.SetExtraEffects(who, "echo", nil) end
				end)
			end
			crystal.Color = rgb(255, 230, 140)
			IslandMode.Notify(re.runId, { kind = "echo", blessed = true, by = p.DisplayName, seconds = ECHO_BUFF_SECONDS,
				line = "+25% damage, +20% speed" })
		else
			crystal.Color = rgb(255, 50, 60)
			ev.mods = ECHO_CURSE
			setMods(re, ev.mods)
			IslandMode.Notify(re.runId, { kind = "echo", blessed = false, by = p.DisplayName, seconds = math.max(0, math.floor(ev.ends - os.clock())),
				line = "Enemies are savage, loot is richer" })
		end
		local flash = part({ Shape = Enum.PartType.Ball, Size = Vector3.one * 2, CFrame = crystal.CFrame, Color = crystal.Color, Transparency = 0.2 }, folder)
		TweenService:Create(flash, TweenInfo.new(0.8), { Size = Vector3.one * 30, Transparency = 1 }):Play()
		Debris:AddItem(flash, 0.85)
		-- (a blessing is the whole of it: the event ends; a curse runs its course)
		if blessed then ev.ends = math.min(ev.ends, os.clock() + 6) end
	end)
	table.insert(ev.cleanup, function()
		if m.Parent then
			for _, d in ipairs(m:GetDescendants()) do
				if d:IsA("BasePart") then TweenService:Create(d, TweenInfo.new(1.2), { Transparency = 1 }):Play() end
			end
			Debris:AddItem(m, 1.3)
		end
		if beam.Parent then beam:Destroy() end
	end)
	return { pos = cf.Position }
end

START.elite_hunt = function(re, ev, folder)
	local island = re.island
	local sources = island.sources :: { any }
	-- far from everyone (it roams to them)
	local best, bestD = nil, -1
	for _ = 1, 12 do
		local s = sources[re.rng:NextInteger(1, #sources)]
		local near = math.huge
		for _, e in ipairs(living(re)) do near = math.min(near, (e.root.Position - s.pos).Magnitude) end
		if near > 90 and near > bestD and near < 400 then best, bestD = s, near end
	end
	best = best or sources[re.rng:NextInteger(1, #sources)]
	local st = IslandMode.Of(re.runId)
	local wave = if st then st.wave else 1
	local people = math.max(1, #living(re))
	local slain = false
	local model = MobManager.Spawn({
		kind = "executioner",
		cf = CFrame.new(best.pos),
		runId = re.runId,
		elite = true,
		name = "The Hunted Warlord",
		healthMult = (8 + wave * 0.6) * (1 + 0.5 * (people - 1)),
		damageMult = 1.3,
		xpMult = 10,
		scale = 1.6,
		attrs = { AggroRange = 600, IslandEnemy = "hunt", HuntTarget = true, WalkSpeed = 1.15 },
		onDied = function(m: Model)
			slain = true
			local root = m:FindFirstChild("HumanoidRootPart") :: BasePart?
			local chests = script.Parent:FindFirstChild("IslandChests")
			if root and chests then pcall(function() (require(chests) :: any).DropElite(re.runId, root.Position) end) end
			for _, p in ipairs(IslandMode.Members(re.runId)) do pcall(PlayerStats.AwardGold, p, HUNT_GOLD) end
			IslandMode.Notify(re.runId, { kind = "hunt_done", gold = HUNT_GOLD })
			ev.ends = math.min(ev.ends, os.clock() + 3)
		end,
	})
	table.insert(ev.cleanup, function()
		-- (it slips away if it isn't slain in time)
		if model and model.Parent and not slain then model:Destroy() end
	end)
	return { model = model }
end

START.blood_moon = function(_re, _ev, _folder)
	return nil
end

-- ── Running them ────────────────────────────────────────────────────────────
local function finish(re: RunEvents)
	local ev = re.active
	if not ev then return end
	re.active = nil
	for _, fn in ipairs(ev.cleanup) do pcall(fn) end
	setMods(re, nil)
	RunScope.Set(re.runId, "IslandEvent", nil)
	IslandMode.Notify(re.runId, { kind = "event_end", id = ev.id })
	local lo, hi = E.every[1], E.every[2]
	re.nextAt = os.clock() + re.rng:NextNumber(lo, hi)
end

local function begin(re: RunEvents, id: string): boolean
	local def = E.list[id]
	if not def or re.active or not START[id] then return false end
	local folder = re.island.folder:FindFirstChild("Events") :: Folder?
	if not folder then
		local f = Instance.new("Folder")
		f.Name = "Events"
		f.Parent = re.island.folder
		folder = f
	end
	local ev: Active = { id = id, mods = MODS[id] or {}, ends = os.clock() + def.duration, cleanup = {} }
	re.active = ev
	re.last = id
	setMods(re, ev.mods)
	RunScope.Set(re.runId, "IslandEvent", id)
	local ok, extra = pcall(START[id], re, ev, folder :: Folder)
	if not ok then warn("[IslandEvents] " .. id .. ":", extra) end
	local msg: { [string]: any } = { kind = "event", id = id, name = def.name, line = def.line, duration = def.duration }
	if ok and extra then
		for k, v in pairs(extra) do msg[k] = v end
	end
	IslandMode.Notify(re.runId, msg)
	return true
end

local function pick(re: RunEvents): string?
	local total = 0
	for id, def in pairs(E.list) do
		if id ~= re.last then total += def.weight end
	end
	local r = re.rng:NextNumber() * total
	for id, def in pairs(E.list) do
		if id ~= re.last then
			r -= def.weight
			if r <= 0 then return id end
		end
	end
	return nil
end

function IslandEvents.Start(runId: string)
	local island = IslandGenerator.Get(runId)
	if not island then return end
	local re: RunEvents = { runId = runId, island = island, alive = true, active = nil, last = nil,
		nextAt = os.clock() + E.firstAfter, rng = Random.new() }
	runs[runId] = re
	task.spawn(function()
		while re.alive do
			task.wait(1)
			local ok, err = pcall(function()
				local ev = re.active
				if ev then
					if os.clock() >= ev.ends then finish(re) end
				elseif os.clock() >= re.nextAt and RunScope.Get(runId, "IslandBossActive") ~= true then
					local id = pick(re)
					if id then begin(re, id) end
				end
			end)
			if not ok then warn("[IslandEvents]", err) end
		end
	end)
end

function IslandEvents.Stop(runId: string)
	local re = runs[runId]
	if not re then return end
	re.alive = false
	runs[runId] = nil
	local ev = re.active
	if ev then
		for _, fn in ipairs(ev.cleanup) do pcall(fn) end
	end
	-- (the blessing never outlives the run)
	for _, p in ipairs(Players:GetPlayers()) do
		if p:GetAttribute("RunId") == runId then PlayerStats.SetExtraEffects(p, "echo", nil) end
	end
end

-- Start an event now (ending the one running, if any). A Studio test.
function IslandEvents.Force(runId: string, id: string): string
	local re = runs[runId]
	if not re then return "no island events on this run" end
	if not E.list[id] then return "no such event: " .. tostring(id) end
	if re.active then finish(re) end
	return if begin(re, id) then "started " .. id else "couldn't start " .. id
end

return IslandEvents
