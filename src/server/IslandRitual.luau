--!strict
--[[
	IslandRitual.luau
	The Forgotten Isle's ritual site: the altar in the Ancient Sanctuary, its
	eight statues and its ring of runes (IslandGenerator builds them).

	  dormant    until the island has stirred long enough (Ritual.minWave):
	             the altar answers with what it's waiting for
	  ready      anyone of the run can examine the altar (its prompt → the
	             ritual panel on their HUD: IslandEvent "ritual_info") and
	             begin it (IslandAction "ritual_begin", checked here: on the
	             island, alive, at the altar, the altar ready)
	  summoning  the eight statues wake one after another, the runes light,
	             the ground shakes (the clients: "ritual_start"), their light
	             converges on the altar and it sinks into the stone; a boss
	             (one of six, IslandBosses, never the last one twice running)
	             rises in its place
	  fighting   the boss is held to the arena (Ritual.arenaRadius; pulled
	             back if it strays), the island's spawns keep out of it
	             (IslandMode.SetArena), and everyone who comes into the arena
	             counts as having fought it. If they all leave it (or fall)
	             for long enough, the ritual breaks: the boss is gone and the
	             altar sleeps a while.
	  cooldown   after a boss falls: its defeat (IslandBosses.Defeat), XP for
	             everyone who fought it, and a Ritual Chest (IslandChests)
	             with loot for each of them, its boss's own gear among it.
	             Then the altar rests (Ritual.cooldown) and is ready again.

	Only one ritual at a time: begin is refused unless the altar is ready.

	  IslandRitual.Start(runId) / Stop(runId)   (IslandMode)
	  IslandRitual.Begin(runId, player, bossId?, force?) → string
	      (force: a Studio test, DevHooks isle_ritual; still never two at once)
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local IslandConfig = require(Shared:WaitForChild("IslandConfig"))
local RunScope = require(Shared:WaitForChild("RunScope"))
local IslandGenerator = require(script.Parent:WaitForChild("IslandGenerator"))
local IslandMode = require(script.Parent:WaitForChild("IslandMode"))
local IslandBosses = require(script.Parent:WaitForChild("IslandBosses"))
local MobManager = require(script.Parent:WaitForChild("MobManager"))
local PlayerStats = require(script.Parent:WaitForChild("PlayerStats"))

local IslandRitual = {}

local R = IslandConfig.Ritual
local FLEE_SECONDS = 12      -- everyone out of the arena this long: the ritual breaks
local BROKEN_COOLDOWN = 30   -- (a broken ritual rests less than a won one)
local XP_REWARD = 250        -- each who fought (before their xpGain; the kill gives its own too)
local SINK = 9               -- how far the altar sinks into the stone during the fight
local SFX = {
	wake = "rbxassetid://9116394545",  -- a chime, each statue
	boom = "rbxassetid://9125404320",  -- the boss arriving
}

type State = "dormant" | "ready" | "summoning" | "fighting" | "cooldown"
type Ritual = {
	runId: string,
	island: any,
	center: Vector3,
	state: State,
	readyAt: number,
	alive: boolean,
	boss: Model?,
	bossId: string?,
	lastBoss: string?,
	participants: { [number]: boolean },
	slain: number,
	prompt: ProximityPrompt?,
	altarPivot: CFrame,
	extras: { Instance },  -- the summoning's beams, cleared after
}

local rituals: { [string]: Ritual } = {}

local function sound(at: BasePart, id: string, volume: number)
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Volume = volume
	s.RollOffMaxDistance = 400
	s.Parent = at
	s:Play()
	Debris:AddItem(s, 6)
end

local function wave(rt: Ritual): number
	local st = IslandMode.Of(rt.runId)
	return if st then st.wave else 0
end

-- What the altar tells someone who examines it (the ritual panel).
local function info(rt: Ritual): { [string]: any }
	local now = Workspace:GetServerTimeNow()
	return {
		kind = "ritual_info",
		state = rt.state,
		wave = wave(rt),
		minWave = R.minWave,
		cooldown = if rt.state == "cooldown" then math.max(0, math.ceil(rt.readyAt - now)) else 0,
		slain = rt.slain,
		bosses = #IslandBosses.Ids(),
		lore = "Eight wardens sealed what sleeps beneath this stone. Wake them, and one of the island's sovereigns will answer.",
	}
end

-- ── The site's look ─────────────────────────────────────────────────────────
local function glowParts(model: Model): { BasePart }
	local out = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Name == "Glow" then table.insert(out, d) end
	end
	return out
end

local function fade(parts: { BasePart }, transparency: number, t: number)
	for _, p in ipairs(parts) do
		if p.Parent then TweenService:Create(p, TweenInfo.new(t), { Transparency = transparency }):Play() end
	end
end

-- The altar sinking into the platform (or back up), in steps.
local function moveAltar(rt: Ritual, down: boolean, t: number)
	local model = rt.island.altarModel :: Model?
	if not model or not model.Parent then return end
	local from = model:GetPivot()
	local to = if down then rt.altarPivot - Vector3.new(0, SINK, 0) else rt.altarPivot
	task.spawn(function()
		local steps = math.max(1, math.floor(t / 0.05))
		for i = 1, steps do
			if not model.Parent then return end
			model:PivotTo(from:Lerp(to, TweenService:GetValue(i / steps, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut)))
			task.wait(0.05)
		end
	end)
end

-- Everything back to sleep (statues, runes, cracks, the altar up).
local function rest(rt: Ritual)
	for _, s in ipairs(rt.island.statues) do fade(glowParts(s), 0.85, 1.5) end
	fade(rt.island.runes, 0.82, 1.5)
	fade(rt.island.cracks, 0.55, 1.5)
	for _, e in ipairs(rt.extras) do
		if e.Parent then e:Destroy() end
	end
	rt.extras = {}
	moveAltar(rt, false, 2)
	if rt.prompt then rt.prompt.Enabled = true end
end

local function focusPart(rt: Ritual): BasePart?
	local model = rt.island.altarModel :: Model?
	if not model then return nil end
	return (model:FindFirstChild("Focus", true) or model.PrimaryPart) :: BasePart?
end

-- ── The fight ───────────────────────────────────────────────────────────────
local function endFight(rt: Ritual)
	IslandMode.SetArena(rt.runId, nil)
	RunScope.Set(rt.runId, "IslandBossActive", nil)
	rt.boss = nil
end

local function defeated(rt: Ritual, bossId: string, model: Model)
	if not rt.alive or rt.state ~= "fighting" then return end
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	local pos = if root then root.Position else rt.center
	IslandBosses.Defeat(bossId, Vector3.new(pos.X, rt.center.Y, pos.Z), rt.center.Y)
	endFight(rt)
	rt.slain += 1
	rt.state = "cooldown"
	rt.readyAt = Workspace:GetServerTimeNow() + R.cooldown
	RunScope.Set(rt.runId, "IslandBossesSlain", rt.slain)
	local def = IslandBosses.Get(bossId)
	IslandMode.Notify(rt.runId, { kind = "ritual_victory", id = bossId, name = def and def.name or bossId, slain = rt.slain })
	-- XP for everyone who fought it
	for _, p in ipairs(IslandMode.Members(rt.runId)) do
		if rt.participants[p.UserId] then pcall(PlayerStats.AwardXP, p, XP_REWARD) end
	end
	-- the Ritual Chest rises at the altar's foot, for them
	local fought = table.clone(rt.participants)
	task.delay(2.5, function()
		if not rt.alive then return end
		local chests = script.Parent:FindFirstChild("IslandChests")
		if chests then
			local at = rt.center + Vector3.new(0, 0, -20) -- (clear of the altar's own prompt)
			pcall(function()
				(require(chests) :: any).Spawn(rt.runId, "ritual", CFrame.lookAt(at, rt.center * Vector3.new(1, 0, 1) + Vector3.new(0, at.Y, 0)), { boss = bossId, participants = fought })
			end)
		end
		rest(rt)
	end)
end

-- The ritual breaks (everyone left or fell): the boss is gone, the altar rests.
local function broken(rt: Ritual)
	local boss = rt.boss
	endFight(rt)
	if boss and boss.Parent then boss:Destroy() end
	rt.state = "cooldown"
	rt.readyAt = Workspace:GetServerTimeNow() + BROKEN_COOLDOWN
	IslandMode.Notify(rt.runId, { kind = "ritual_failed" })
	rest(rt)
end

local function fight(rt: Ritual, boss: Model)
	local root = boss:FindFirstChild("HumanoidRootPart") :: BasePart?
	local away = 0
	while rt.alive and rt.state == "fighting" and rt.boss == boss and boss.Parent do
		local dt = task.wait(0.5)
		local hum = boss:FindFirstChildOfClass("Humanoid")
		if not hum or hum.Health <= 0 then break end
		-- whoever comes into the arena has fought it
		local inside = 0
		for _, e in ipairs(IslandMode.Living(rt.runId)) do
			local d = Vector3.new(e.root.Position.X - rt.center.X, 0, e.root.Position.Z - rt.center.Z).Magnitude
			if d <= R.arenaRadius + 10 then
				rt.participants[e.player.UserId] = true
				inside += 1
			elseif d <= R.arenaRadius + 40 then
				inside += 1
			end
		end
		away = if inside == 0 then away + dt else 0
		if away >= FLEE_SECONDS then
			broken(rt)
			return
		end
		-- held to the arena
		if root then
			local rel = Vector3.new(root.Position.X - rt.center.X, 0, root.Position.Z - rt.center.Z)
			if rel.Magnitude > R.arenaRadius or root.Position.Y < rt.center.Y - 12 then
				root.AssemblyLinearVelocity = Vector3.zero
				root:PivotTo(CFrame.new(rt.center + Vector3.new(0, root.Size.Y / 2 + 1, 0)) * root.CFrame.Rotation)
			end
		end
	end
	-- (gone without falling: taken away some other way; the altar mustn't stay stuck)
	if rt.alive and rt.state == "fighting" and rt.boss == boss and not boss.Parent then broken(rt) end
end

-- ── The summoning ───────────────────────────────────────────────────────────
local function pickBoss(rt: Ritual, want: string?): string
	if want and IslandBosses.Get(want) then return want end
	local ids = IslandBosses.Ids()
	local options = {}
	for _, id in ipairs(ids) do
		if id ~= rt.lastBoss then table.insert(options, id) end
	end
	return options[math.random(1, #options)]
end

local function summon(rt: Ritual, bossId: string, by: Player)
	local island = rt.island
	local def = IslandBosses.Get(bossId)
	local focus = focusPart(rt)
	local seq = R.sequenceSeconds
	if rt.prompt then rt.prompt.Enabled = false end
	IslandMode.Notify(rt.runId, { kind = "ritual_start", by = by.DisplayName, center = rt.center, duration = seq,
		color = def and def.color or Color3.fromRGB(180, 90, 255) })
	-- the statues wake, one after another (the first ~55% of it)
	local statues = island.statues :: { Model }
	local each = seq * 0.55 / math.max(1, #statues)
	for i, s in ipairs(statues) do
		task.delay((i - 1) * each, function()
			if not rt.alive then return end
			fade(glowParts(s), 0, 0.4)
			local g = glowParts(s)[1]
			if g then sound(g, SFX.wake, 0.5) end
		end)
	end
	-- the runes and the cracks light round the ring
	task.delay(seq * 0.55, function()
		if not rt.alive then return end
		local runes = island.runes :: { BasePart }
		for k, r in ipairs(runes) do
			task.delay(k / #runes * seq * 0.15, function()
				if r.Parent then TweenService:Create(r, TweenInfo.new(0.25), { Transparency = 0.05 }):Play() end
			end)
		end
		fade(island.cracks, 0, seq * 0.2)
	end)
	-- their light converges on the altar, and it sinks
	task.delay(seq * 0.72, function()
		if not rt.alive or not focus then return end
		for _, s in ipairs(statues) do
			local g = glowParts(s)[1]
			if g then
				local a, b = g.Position, focus.Position
				local beam = Instance.new("Part")
				beam.Anchored, beam.CanCollide, beam.CanQuery, beam.CanTouch, beam.CastShadow = true, false, false, false, false
				beam.Material = Enum.Material.Neon
				beam.Color = g.Color
				beam.Size = Vector3.new(0.5, 0.5, (b - a).Magnitude)
				beam.CFrame = CFrame.lookAt((a + b) / 2, b)
				beam.Transparency = 0.2
				beam.Parent = island.folder
				TweenService:Create(beam, TweenInfo.new(seq * 0.28), { Size = Vector3.new(0.15, 0.15, (b - a).Magnitude), Transparency = 0.6 }):Play()
				table.insert(rt.extras, beam)
			end
		end
		moveAltar(rt, true, seq * 0.25)
	end)
	task.wait(seq)
	if not rt.alive then return end
	for _, e in ipairs(rt.extras) do
		if e.Parent then e:Destroy() end
	end
	rt.extras = {}

	-- the boss rises, scaled to how many came and how long the island has stirred
	local people = math.max(1, #IslandMode.Living(rt.runId))
	local healthMult = 1.5 * (1 + 0.6 * (people - 1)) * (1 + 0.04 * wave(rt) + 0.15 * rt.slain)
	rt.participants = {}
	for _, e in ipairs(IslandMode.Living(rt.runId)) do
		if (e.root.Position - rt.center).Magnitude <= R.arenaRadius + 30 then rt.participants[e.player.UserId] = true end
	end
	rt.participants[by.UserId] = true
	rt.state = "fighting"
	rt.bossId = bossId
	rt.lastBoss = bossId
	IslandMode.SetArena(rt.runId, rt.center, R.arenaRadius)
	RunScope.Set(rt.runId, "IslandBossActive", true)
	local model: Model? = nil
	model = MobManager.Spawn({
		bossKind = bossId,
		cf = CFrame.new(rt.center),
		runId = rt.runId,
		healthMult = healthMult,
		attrs = { ArenaCenter = rt.center, AggroRange = R.arenaRadius + 40, IslandBoss = bossId },
		onDied = function(m: Model)
			defeated(rt, bossId, m)
		end,
	})
	if not model then
		warn("[IslandRitual] the boss didn't spawn:", bossId)
		broken(rt)
		return
	end
	rt.boss = model
	if focus then sound(focus, SFX.boom, 1) end
	IslandMode.Notify(rt.runId, { kind = "ritual_boss", id = bossId, name = def and def.name or bossId, title = def and def.title or "",
		color = def and def.color or Color3.new(1, 1, 1), model = model })
	task.spawn(fight, rt, model)
end

function IslandRitual.Begin(runId: any, player: Player, bossId: string?, force: boolean?): string
	local rt = if typeof(runId) == "string" then rituals[runId] else nil
	if not rt or not rt.alive then return "no ritual on this run" end
	if rt.state == "summoning" or rt.state == "fighting" then return "a ritual is already under way" end
	if rt.state ~= "ready" and not force then return "the altar isn't ready" end
	rt.state = "summoning"
	local id = pickBoss(rt, bossId)
	task.spawn(function()
		local ok, err = pcall(summon, rt, id, player)
		if not ok then
			warn("[IslandRitual] summon:", err)
			if rt.state == "summoning" then
				rt.state = "ready"
				rest(rt)
			end
		end
	end)
	return "summoning " .. id
end

-- ── Run ─────────────────────────────────────────────────────────────────────
function IslandRitual.Start(runId: string)
	local island = IslandGenerator.Get(runId)
	if not island or not island.altarModel then return end
	local rt: Ritual = {
		runId = runId,
		island = island,
		center = island.altar.Position,
		state = "dormant",
		readyAt = 0,
		alive = true,
		boss = nil,
		bossId = nil,
		lastBoss = nil,
		participants = {},
		slain = 0,
		prompt = nil,
		altarPivot = (island.altarModel :: Model):GetPivot(),
		extras = {},
	}
	rituals[runId] = rt
	local focus = focusPart(rt)
	if focus then
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = "Examine"
		prompt.ObjectText = "Ritual Altar"
		prompt.HoldDuration = 0.3
		prompt.MaxActivationDistance = 14
		prompt.RequiresLineOfSight = false
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.Parent = focus
		prompt.Triggered:Connect(function(p: Player)
			if p:GetAttribute("RunId") ~= runId or p:GetAttribute("InLobby") ~= false then return end
			IslandMode.Notify(runId, info(rt), p)
		end)
		rt.prompt = prompt
	end
	-- dormant → ready (and back to ready after a cooldown)
	task.spawn(function()
		while rt.alive do
			task.wait(1)
			local now = Workspace:GetServerTimeNow()
			if (rt.state == "dormant" and wave(rt) >= R.minWave) or (rt.state == "cooldown" and now >= rt.readyAt) then
				rt.state = "ready"
				IslandMode.Notify(runId, { kind = "ritual_ready" })
			end
			if rt.prompt then rt.prompt.ActionText = if rt.state == "ready" then "Begin the ritual" else "Examine" end
		end
	end)
end

function IslandRitual.Stop(runId: string)
	local rt = rituals[runId]
	if not rt then return end
	rt.alive = false
	rituals[runId] = nil
	local boss = rt.boss
	if boss and boss.Parent then boss:Destroy() end
	RunScope.Set(runId, "IslandBossActive", nil)
end

function IslandRitual.Init()
	IslandMode.Handle("ritual_begin", function(p: Player, _msg: any, _st: any)
		local runId = p:GetAttribute("RunId")
		local rt = if typeof(runId) == "string" then rituals[runId] else nil
		if not rt then return end
		-- (alive, at the altar)
		local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
		local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not hum or hum.Health <= 0 or not root or (root.Position - rt.center).Magnitude > 24 then return end
		local result = IslandRitual.Begin(runId, p, nil, false)
		if string.sub(result, 1, 9) ~= "summoning" then IslandMode.Notify(rt.runId, info(rt), p) end
	end)
	IslandMode.Handle("ritual_info", function(p: Player, _msg: any, _st: any)
		local runId = p:GetAttribute("RunId")
		local rt = if typeof(runId) == "string" then rituals[runId] else nil
		if rt then IslandMode.Notify(rt.runId, info(rt), p) end
	end)
end

Players.PlayerRemoving:Connect(function(p)
	for _, rt in pairs(rituals) do rt.participants[p.UserId] = nil end
end)

return IslandRitual
