--!strict
--[[
	ArenaCrowd.luau
	The spectators in the arcade's neon arenas (ArenaBuilder leaves a tagged
	"ArenaCrowd" Folder in each: its centre, its stands' radii and tiers).

	Only the arena you are in gets a crowd, built a few dozen figures a frame
	when you arrive and cleared when you leave. Each spectator is a seated
	brick figure (thighs, torso, head, two arms; some with a neon visor, a
	neon crest or a cap, some waving a glowstick): plain Parts,
	anchored, no collision, touch or queries, no shadows, no Humanoid (so
	nothing indexes or outlines them), no lights, no Highlights.

	They sway and look about between fights, and react to it:
	  • cheer (arms up and waving, jumping in their seats, a crowd roar) on a
	    kill, louder on clearing the room (no mob left alive in it) and on a
	    boss's death;
	  • boo (arms thrust down, heads shaking, leaning in, a boo) when a player
	    in the arena takes a big hit, and longest when one dies.
	A reaction ripples out round the stands from where it happened.

	Cheap by construction: only figures near the camera's focus animate
	(the rest hold still), at 30 Hz (15 under frame pressure), every part
	moved in one BulkMoveTo.
--]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local FxBudget = require(script.Parent:WaitForChild("FxBudget"))

local ArenaCrowd = {}

local TAG = "ArenaCrowd"
local SEATS_PER_SEGMENT = 3
local BUILD_PER_FRAME = 40
local ANIM_DIST = 120          -- figures this near the focus animate
local ACTIVE_MARGIN = 70       -- how far past the stands you can be and keep the crowd

local SOUNDS = {
	-- (Pro Sound Effects, on the Creator Store)
	cheer = { id = "rbxassetid://9120973900", volume = 0.55, len = 20 },
	roar = { id = "rbxassetid://9114360647", volume = 0.6, len = 4.2 },
	boo = { id = "rbxassetid://9120974911", volume = 0.6, len = 4.5 },
}

local SKIN = {
	Color3.fromRGB(255, 220, 177), Color3.fromRGB(234, 184, 146), Color3.fromRGB(204, 142, 105),
	Color3.fromRGB(160, 104, 72), Color3.fromRGB(116, 74, 50), Color3.fromRGB(245, 205, 48),
}
-- (a cyberpunk crowd: dark jackets and loud colours)
local CLOTH = {
	Color3.fromRGB(24, 22, 40), Color3.fromRGB(32, 30, 58), Color3.fromRGB(18, 18, 24),
	Color3.fromRGB(255, 70, 210), Color3.fromRGB(66, 221, 245), Color3.fromRGB(120, 87, 255),
	Color3.fromRGB(255, 198, 109), Color3.fromRGB(150, 255, 90), Color3.fromRGB(230, 230, 240),
	Color3.fromRGB(60, 40, 120), Color3.fromRGB(255, 90, 90), Color3.fromRGB(40, 60, 110),
}
local PANTS = {
	Color3.fromRGB(20, 20, 28), Color3.fromRGB(30, 28, 50), Color3.fromRGB(44, 40, 80),
	Color3.fromRGB(60, 62, 76), Color3.fromRGB(24, 40, 70), Color3.fromRGB(70, 30, 70),
}
-- what glows on them: visors, hair, glowsticks
local GLOW = {
	Color3.fromRGB(66, 221, 245), Color3.fromRGB(255, 70, 210), Color3.fromRGB(150, 255, 90),
	Color3.fromRGB(255, 198, 109), Color3.fromRGB(140, 110, 255),
}

type Figure = {
	base: CFrame,
	parts: { BasePart },       -- legs, torso, head, armL, armR, then extras (visor, hair, glowstick)
	angle: number,             -- round the ring
	phase: number,
	rate: number,
	p: number,                 -- joins a reaction when the reaction's intensity is over this
	delayJ: number,
	cheer: number,             -- the blend of each mood, 0..1
	boo: number,
	extras: { { on: number, offset: CFrame } }, -- each extra: the part it rides (3 head, 5 right arm) and where
	awake: boolean,            -- animated last tick (else at rest)
}

type Event = { kind: string, t0: number, dur: number, intensity: number, angle: number }

type Arena = {
	tag: Folder,
	center: Vector3,
	half: number,
	outer: number,
	folder: Folder,
	figures: { Figure },
	built: boolean,
}

local active: Arena? = nil
local events: { Event } = {}
local near: { Figure } = {}
local lastBoo = 0
local lastCheerSound = 0
local killsSinceClear = 0

-- ── Building ────────────────────────────────────────────────────────────────

local function brick(parent: Instance, size: Vector3, color: Color3, glow: boolean?): BasePart
	local p = Instance.new("Part")
	p.Size = size
	p.Color = color
	p.Material = if glow then Enum.Material.Neon else Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- One spectator, seated at `base` (its seat's top, facing the arena: -Z).
local function makeFigure(parent: Instance, base: CFrame, angle: number, rng: Random): Figure
	local skin = SKIN[rng:NextInteger(1, #SKIN)]
	local shirt = CLOTH[rng:NextInteger(1, #CLOTH)]
	local pants = PANTS[rng:NextInteger(1, #PANTS)]
	local legs = brick(parent, Vector3.new(2, 1, 2.2), pants)
	local torso = brick(parent, Vector3.new(2, 2, 1), shirt)
	local head = brick(parent, Vector3.new(2, 1, 1), skin)
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Head
	mesh.Scale = Vector3.new(1.25, 1.25, 1.25)
	mesh.Parent = head
	local face = Instance.new("Decal")
	face.Texture = "rbxasset://textures/face.png"
	face.Face = Enum.NormalId.Front
	face.Parent = head
	local sleeves = rng:NextNumber() < 0.5
	local armL = brick(parent, Vector3.new(1, 2, 1), if sleeves then shirt else skin)
	local armR = brick(parent, Vector3.new(1, 2, 1), if sleeves then shirt else skin)
	local parts = { legs, torso, head, armL, armR }
	local extras = {}
	local glow = GLOW[rng:NextInteger(1, #GLOW)]
	-- (neon on a few of them, cheap: a part each, no light)
	local roll = rng:NextNumber()
	if roll < 0.3 then
		-- a visor across the eyes
		table.insert(parts, brick(parent, Vector3.new(1.3, 0.3, 0.2), glow, true))
		table.insert(extras, { on = 3, offset = CFrame.new(0, 0.12, -0.6) })
	elseif roll < 0.5 then
		-- a neon crest of hair
		table.insert(parts, brick(parent, Vector3.new(0.35, 0.6, 1.3), glow, true))
		table.insert(extras, { on = 3, offset = CFrame.new(0, 0.85, 0) })
	elseif roll < 0.7 then
		-- a dark cap
		table.insert(parts, brick(parent, Vector3.new(1.3, 0.45, 1.3), CLOTH[rng:NextInteger(1, 3)]))
		table.insert(extras, { on = 3, offset = CFrame.new(0, 0.8, 0) })
	end
	if rng:NextNumber() < 0.3 then
		-- a glowstick in the right hand (waved when they cheer)
		table.insert(parts, brick(parent, Vector3.new(0.2, 1.4, 0.2), GLOW[rng:NextInteger(1, #GLOW)], true))
		table.insert(extras, { on = 5, offset = CFrame.new(0, -1.3, -0.3) * CFrame.Angles(math.rad(70), 0, 0) })
	end
	return {
		base = base,
		parts = parts,
		angle = angle,
		phase = rng:NextNumber(0, math.pi * 2),
		rate = rng:NextNumber(0.8, 1.25),
		p = rng:NextNumber(0, 1),
		delayJ = rng:NextNumber(0, 0.3),
		cheer = 0,
		boo = 0,
		extras = extras,
		awake = false,
	}
end

-- The figure's parts' CFrames for a pose.
-- (cheer, boo: the blend of each; t: now)
local function pose(f: Figure, t: number, out: { CFrame })
	local ph, rt = f.phase, f.rate
	local c, b = f.cheer, f.boo
	local idle = 1 - math.max(c, b)
	-- the body: sways idly, bounces cheering, leans in booing
	local jump = c * math.max(0, math.sin(t * 7 * rt + ph)) * 1.3
	local sway = math.sin(t * 0.9 * rt + ph) * 0.07 * idle + math.sin(t * 6 * rt + ph) * 0.06 * c
	local lean = b * 0.22 - c * 0.08
	local body = f.base * CFrame.new(0, jump, 0) * CFrame.Angles(0, 0, sway)
	local torsoCF = body * CFrame.new(0, 1, 0.3) * CFrame.Angles(-lean, 0, 0) * CFrame.new(0, 1, 0)
	out[1] = body * CFrame.new(0, 0.5, -0.5)
	out[2] = torsoCF
	-- the head: looks about, shakes "no" booing
	local yaw = math.sin(t * 0.45 * rt + ph * 2) * 0.25 * idle + math.sin(t * 15 * rt + ph) * 0.5 * b
	local nod = -c * 0.15
	local headCF = torsoCF * CFrame.new(0, 1.5, 0) * CFrame.Angles(nod, yaw, 0)
	out[3] = headCF
	-- the arms (from the shoulder): resting on the lap, raised and waving
	-- cheering, thrust down and out booing
	for i, side in ipairs({ -1, 1 }) do
		local wave = math.sin(t * 11 * rt + ph + i) * 0.35
		local pitchRest = 0.35
		local pitchCheer = math.pi - 0.2 + wave * 0.4
		local pitchBoo = 0.55 + math.sin(t * 9 + ph + i) * 0.08
		local pitch = pitchRest * idle + pitchCheer * c + pitchBoo * b
		local spread = side * (0.05 * idle + (0.35 + wave * 0.3) * c + 0.35 * b)
		out[3 + i] = torsoCF * CFrame.new(side * 1.5, 0.5, 0) * CFrame.Angles(pitch, 0, spread) * CFrame.new(0, -0.5, 0) * CFrame.new(0, -0.5, 0)
	end
	for j, e in ipairs(f.extras) do out[5 + j] = out[e.on] * e.offset end
end

local function clearArena()
	local a = active
	active = nil
	near = {}
	if a then a.folder:Destroy() end
end

local function buildArena(tag: Folder)
	clearArena()
	local center = tag:GetAttribute("Center") :: Vector3
	local ring0 = tag:GetAttribute("RingStart") :: number
	local tiers = tag:GetAttribute("Tiers") :: number
	local depth = tag:GetAttribute("TierDepth") :: number
	local rise = tag:GetAttribute("TierRise") :: number
	local firstSeat = tag:GetAttribute("FirstSeat") :: number
	local segments = tag:GetAttribute("Segments") :: number
	local boxAngle = (tag:GetAttribute("BoxAngle") :: number?) or -math.pi / 2
	local aisleEvery = (tag:GetAttribute("AisleEvery") :: number?) or 8
	local fill = (tag:GetAttribute("Fill") :: number?) or 0.8
	local seed = (tag:GetAttribute("Seed") :: number?) or 1
	local exitGap = tag:GetAttribute("ExitGap") == true
	if typeof(center) ~= "Vector3" or not ring0 then return end
	local folder = Instance.new("Folder")
	folder.Name = "ArenaCrowd"
	folder.Parent = Workspace
	local arena: Arena = {
		tag = tag,
		center = center,
		half = (tag:GetAttribute("Half") :: number?) or 60,
		outer = ring0 + tiers * depth,
		folder = folder,
		figures = {},
		built = false,
	}
	active = arena
	local rng = Random.new(seed)
	-- the seats, nearest the camera's side last (all of them, a frame at a time)
	local seats: { { cf: CFrame, a: number } } = {}
	for t = 1, tiers do
		local r = ring0 + (t - 1) * depth + depth * 0.6
		local y = firstSeat + (t - 1) * rise
		for k = 0, segments - 1 do
			if k % aisleEvery == 0 then continue end -- (the aisles)
			if exitGap and (k == 0 or k == segments - 1) then continue end -- (the boss arena's stairs)
			for s = 1, SEATS_PER_SEGMENT do
				local a = (k + (s - 0.5) / SEATS_PER_SEGMENT + rng:NextNumber(-0.06, 0.06)) / segments * math.pi * 2
				local d = (a - boxAngle + math.pi) % (2 * math.pi) - math.pi
				if t >= 2 and t <= 5 and math.abs(d) < 0.16 then continue end -- (the master's box)
				if rng:NextNumber() > fill then continue end
				local at = Vector3.new(center.X + math.cos(a) * r, y, center.Z + math.sin(a) * r)
				local cf = CFrame.lookAt(at, Vector3.new(center.X, y, center.Z)) * CFrame.Angles(0, rng:NextNumber(-0.15, 0.15), 0)
				table.insert(seats, { cf = cf, a = a })
			end
		end
	end
	task.spawn(function()
		local out: { CFrame } = {}
		local batchParts: { BasePart } = {}
		local batchCF: { CFrame } = {}
		for i, seat in ipairs(seats) do
			if active ~= arena then return end
			local f = makeFigure(folder, seat.cf, seat.a, rng)
			pose(f, 0, out)
			for j, p in ipairs(f.parts) do
				table.insert(batchParts, p)
				table.insert(batchCF, out[j])
			end
			table.insert(arena.figures, f)
			if i % BUILD_PER_FRAME == 0 then
				Workspace:BulkMoveTo(batchParts, batchCF, Enum.BulkMoveMode.FireCFrameChanged)
				table.clear(batchParts)
				table.clear(batchCF)
				task.wait()
			end
		end
		if #batchParts > 0 then Workspace:BulkMoveTo(batchParts, batchCF, Enum.BulkMoveMode.FireCFrameChanged) end
		arena.built = true
	end)
end

-- ── Which arena you are in ──────────────────────────────────────────────────

local function focusPos(): Vector3?
	local char = Players.LocalPlayer.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then return root.Position end
	local cam = Workspace.CurrentCamera
	return cam and cam.Focus.Position
end

local function pickArena()
	local at = focusPos()
	if not at then return end
	local best: Folder?, bestD = nil, math.huge
	for _, tag in ipairs(CollectionService:GetTagged(TAG)) do
		if not tag:IsA("Folder") or not tag:IsDescendantOf(Workspace) then continue end
		local c = tag:GetAttribute("Center")
		local ring0 = tag:GetAttribute("RingStart")
		if typeof(c) ~= "Vector3" or typeof(ring0) ~= "number" then continue end
		local d = Vector3.new(at.X - c.X, 0, at.Z - c.Z).Magnitude
		if d < ring0 + ACTIVE_MARGIN and math.abs(at.Y - c.Y) < 80 and d < bestD then
			best, bestD = tag :: Folder, d
		end
	end
	if best then
		if not active or active.tag ~= best then buildArena(best) end
	elseif active then
		clearArena()
	end
end

-- ── Reactions ───────────────────────────────────────────────────────────────

local sounds: { [string]: Sound } = {}
local function sound(kind: string): Sound
	local s = sounds[kind]
	if s and s.Parent then return s end
	local spec = SOUNDS[kind]
	s = Instance.new("Sound")
	s.Name = "ArenaCrowd_" .. kind
	s.SoundId = spec.id
	s.Volume = spec.volume
	s.Parent = SoundService
	sounds[kind] = s
	return s
end

local function playSound(kind: string, dur: number)
	local s = sound(kind)
	local spec = SOUNDS[kind]
	if s.IsPlaying then s:Stop() end
	s.Volume = spec.volume
	-- (the long cheer: a stretch from somewhere in it)
	s.TimePosition = if kind == "cheer" then math.random() * math.max(0, spec.len - dur - 1) else 0
	s:Play()
	local token = {}
	s:SetAttribute("Token", tostring(token))
	task.delay(math.max(0.3, dur - 0.8), function()
		if s:GetAttribute("Token") ~= tostring(token) then return end
		local tw = TweenService:Create(s, TweenInfo.new(0.8), { Volume = 0 })
		tw:Play()
		tw.Completed:Wait()
		if s:GetAttribute("Token") == tostring(token) then s:Stop() end
	end)
end

local function angleOf(pos: Vector3?): number
	local a = active
	if not (a and pos) then return math.random() * math.pi * 2 end
	return math.atan2(pos.Z - a.center.Z, pos.X - a.center.X)
end

-- A reaction: `kind` "cheer" or "boo", `intensity` the share of the crowd
-- that joins in, from `pos`.
function ArenaCrowd.React(kind: string, intensity: number, dur: number, pos: Vector3?, loud: boolean?)
	if not active then return end
	local now = os.clock()
	-- (a cheer while one's on swells it, rather than starting over)
	for _, e in ipairs(events) do
		if e.kind == kind and now < e.t0 + e.dur then
			e.dur = math.max(e.dur, now - e.t0 + dur)
			e.intensity = math.min(1, math.max(e.intensity, intensity) + 0.1)
			if loud then playSound(if kind == "cheer" then "roar" else "boo", dur) end
			return
		end
	end
	table.insert(events, { kind = kind, t0 = now, dur = dur, intensity = intensity, angle = angleOf(pos) })
	if kind == "cheer" then
		if loud then
			playSound("roar", dur)
		elseif now - lastCheerSound > 1.2 then
			lastCheerSound = now
			playSound("cheer", dur)
		end
	else
		playSound("boo", dur)
	end
end

local function inArena(pos: Vector3, pad: number): boolean
	local a = active
	if not a then return false end
	return math.abs(pos.X - a.center.X) < a.half + pad and math.abs(pos.Z - a.center.Z) < a.half + pad and math.abs(pos.Y - a.center.Y) < 40
end

local function modelPos(m: Model): Vector3?
	local ok, cf = pcall(function() return m:GetPivot() end)
	return if ok then (cf :: CFrame).Position else nil
end

local function aliveMobsIn(): number
	local mobs = Workspace:FindFirstChild("Mobs")
	if not mobs then return 0 end
	local n = 0
	for _, m in ipairs(mobs:GetChildren()) do
		if not m:IsA("Model") or m:GetAttribute("IsAlly") then continue end
		local h = m:FindFirstChildOfClass("Humanoid")
		local pos = modelPos(m)
		if h and h.Health > 0 and pos and inArena(pos, 6) then n += 1 end
	end
	return n
end

local function onMobDied(m: Model, pos: Vector3?)
	if not (active and pos and inArena(pos, 10)) then return end
	killsSinceClear += 1
	if m:GetAttribute("IsBoss") then
		killsSinceClear = 0
		ArenaCrowd.React("cheer", 1, 6, pos, true)
		return
	end
	ArenaCrowd.React("cheer", 0.5, 2.4, pos)
	task.delay(0.5, function()
		if killsSinceClear > 0 and active and aliveMobsIn() == 0 then
			killsSinceClear = 0
			ArenaCrowd.React("cheer", 1, 4, pos, true)
		end
	end)
end

local watchedMobs: { [Instance]: boolean } = {}
local function watchMob(m: Instance)
	if watchedMobs[m] or not m:IsA("Model") then return end
	watchedMobs[m] = true
	local model = m :: Model
	task.spawn(function()
		local h = model:FindFirstChildOfClass("Humanoid") or model:WaitForChild("Humanoid", 10)
		if not (h and h:IsA("Humanoid")) then return end
		local done = false
		local function check()
			if done or h.Health > 0 or model:GetAttribute("IsAlly") then return end
			done = true
			onMobDied(model, modelPos(model))
		end
		h.HealthChanged:Connect(check)
		check()
	end)
	model.AncestryChanged:Connect(function()
		if not model:IsDescendantOf(Workspace) then watchedMobs[model] = nil end
	end)
end

-- (the folder can be made anew: hook whichever one is there now)
local mobsHooked: Instance? = nil
local function hookMobs()
	local mobs = Workspace:FindFirstChild("Mobs")
	if not mobs or mobs == mobsHooked then return end
	mobsHooked = mobs
	for _, m in ipairs(mobs:GetChildren()) do watchMob(m) end
	mobs.ChildAdded:Connect(watchMob)
end

local function watchCharacter(char: Model)
	local h = char:WaitForChild("Humanoid", 10)
	if not (h and h:IsA("Humanoid")) then return end
	local last = h.Health
	local dead = false
	h.HealthChanged:Connect(function(hp)
		local drop = last - hp
		last = hp
		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		local pos = root and root.Position
		if not (active and pos and inArena(pos, 10)) then return end
		if hp <= 0 and not dead then
			dead = true
			ArenaCrowd.React("boo", 1, 4.5, pos)
		elseif drop >= h.MaxHealth * 0.12 and os.clock() - lastBoo > 1.5 then
			lastBoo = os.clock()
			ArenaCrowd.React("boo", if drop >= h.MaxHealth * 0.3 then 0.9 else 0.6, 2.4, pos)
		end
	end)
end

local function watchPlayer(p: Player)
	if p.Character then task.spawn(watchCharacter, p.Character) end
	p.CharacterAdded:Connect(watchCharacter)
end

-- ── Animating ───────────────────────────────────────────────────────────────

local function refreshNear()
	local a = active
	near = {}
	if not a then return end
	local at = focusPos()
	if not at then return end
	for _, f in ipairs(a.figures) do
		local p = f.base.Position
		local dx, dz = p.X - at.X, p.Z - at.Z
		if dx * dx + dz * dz < ANIM_DIST * ANIM_DIST then
			table.insert(near, f)
		elseif f.awake then
			-- (out of range: settle back to rest once, then hold)
			f.awake = false
			f.cheer, f.boo = 0, 0
			local out: { CFrame } = {}
			pose(f, 0, out)
			Workspace:BulkMoveTo(f.parts, out, Enum.BulkMoveMode.FireCFrameChanged)
		end
	end
end

-- The mood a figure wants now: from the reactions under way.
local function wants(f: Figure, now: number): (number, number)
	local c, b = 0, 0
	for _, e in ipairs(events) do
		if f.p > e.intensity then continue end
		local d = math.abs((f.angle - e.angle + math.pi) % (2 * math.pi) - math.pi)
		local t0 = e.t0 + d / math.pi * 0.7 + f.delayJ
		if now >= t0 and now < t0 + e.dur then
			if e.kind == "cheer" then c = 1 else b = 1 end
		end
	end
	if c > 0 and b > 0 then c = 0 end -- (a boo cuts a cheer short)
	-- now and then, someone cheers on their own
	if c == 0 and b == 0 and math.sin(now * 0.13 * f.rate + f.phase * 3) > 0.993 then c = 0.8 end
	return c, b
end

local acc = 0
local nearAt = 0
local function step(dt: number)
	acc += dt
	local pressure = FxBudget.Pressure()
	local interval = if pressure > 0.5 then 1 / 15 else 1 / 30
	if acc < interval then return end
	local elapsed = acc
	acc = 0
	local now = os.clock()
	if now - nearAt > 0.5 then
		nearAt = now
		refreshNear()
	end
	-- (finished reactions drop off)
	for i = #events, 1, -1 do
		if now > events[i].t0 + events[i].dur + 1.5 then table.remove(events, i) end
	end
	if #near == 0 then return end
	local parts: { BasePart } = {}
	local cfs: { CFrame } = {}
	local out: { CFrame } = {}
	local k = math.clamp(elapsed * 6, 0, 1)
	for _, f in ipairs(near) do
		local wc, wb = wants(f, now)
		f.cheer += (wc - f.cheer) * k
		f.boo += (wb - f.boo) * k
		f.awake = true
		pose(f, now, out)
		for j, p in ipairs(f.parts) do
			table.insert(parts, p)
			table.insert(cfs, out[j])
		end
	end
	Workspace:BulkMoveTo(parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
end

function ArenaCrowd.Init()
	for _, p in ipairs(Players:GetPlayers()) do watchPlayer(p) end
	Players.PlayerAdded:Connect(watchPlayer)
	task.spawn(function()
		while true do
			hookMobs()
			pickArena()
			task.wait(0.5)
		end
	end)
	RunService.Heartbeat:Connect(step)
end

return ArenaCrowd
