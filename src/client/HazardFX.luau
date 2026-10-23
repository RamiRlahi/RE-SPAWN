--!strict
--[[
	HazardFX.luau
	The traps' motion, drawn here on each client instead of moved by the
	server (Hazards.luau tags each one "HazardFX"): a part the server moves or
	tweens is sent to every player every frame, and on a poor connection that
	crowds out the things that matter (your character, the mobs, your hits).

	  • turning with the clock (the shared one, GetServerTimeNow, the same the
	    server's damage reads, so the blade you see is the blade that hits):
	    the saw blade running its slot (and its sparks), the blade sweeper,
	    the lava's drifting crust and glow
	  • by the model's "State" (rest / warn / active), eased from the moment it
	    changed: the flame vent's glow, the spike trap's warning and spikes,
	    the burning trap's coals
	  • the explosive barrel, from "LitAt": blinking faster and faster, its
	    warning ring spreading to the blast's edge over the fuse
	  • (not a trap, but the same trouble) a cleared room's reward orb,
	    bobbing (MobManager tags it too)

	Parts arrive whenever streaming brings them, so each is looked up by name
	as it's needed. Only traps near the camera are moved.
--]]

local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local HazardFX = {}

local RANGE = 220 -- studs from the camera's focus: further off, left still
local STATE_EASE = 1 -- seconds a state change takes to settle (then left alone)

type Rec = {
	model: Model,
	changedAt: number,
	settled: boolean,
	rest: { [BasePart]: CFrame },
	lastSign: number,
	baseColor: Color3?,
	up: boolean?,
}

local recs: { [Model]: Rec } = {}

local function child(m: Model, name: string): BasePart?
	local p = m:FindFirstChild(name)
	return if p and p:IsA("BasePart") then p else nil
end

local function ease(a: number): number
	a = math.clamp(a, 0, 1)
	return 1 - (1 - a) * (1 - a)
end

local function vec(m: Model, name: string): Vector3?
	local v = m:GetAttribute(name)
	return if typeof(v) == "Vector3" then v else nil
end

local function num(m: Model, name: string, default: number): number
	local v = m:GetAttribute(name)
	return if typeof(v) == "number" then v else default
end

-- ── Turning with the clock ──────────────────────────────────────────────────
local function saw(r: Rec, t: number)
	local m = r.model
	local center = vec(m, "Center")
	if not center then return end
	local phase, speed = num(m, "Phase", 0), num(m, "Speed", 1)
	local reach, radius = num(m, "Reach", 7), num(m, "Radius", 2.4)
	local base = CFrame.new(center) * CFrame.Angles(0, num(m, "Yaw", 0), 0)
	local along = math.sin(phase + speed * t) * reach
	local c = math.cos(phase + speed * t)
	local runSign = if c >= 0 then 1 else -1
	local grind = child(m, "Grind")
	if grind then
		grind.CFrame = base * CFrame.new(along - runSign * radius * 0.45, 0.35, 0)
			* CFrame.lookAt(Vector3.zero, Vector3.new(-runSign, 0.9, 0))
		local pace = math.abs(c)
		local sparks = grind:FindFirstChild("Sparks") :: ParticleEmitter?
		local embers = grind:FindFirstChild("Embers") :: ParticleEmitter?
		if sparks then sparks.Rate = math.floor(90 + 120 * pace) end
		if embers then embers.Rate = math.floor(25 + 35 * pace) end
		-- (turning round at an end of the slot: a burst)
		if runSign ~= r.lastSign then
			if r.lastSign ~= 0 then
				if sparks then sparks:Emit(60) end
				if embers then embers:Emit(25) end
			end
			r.lastSign = runSign
		end
		local heat = child(m, "Heat")
		if heat then
			heat.CFrame = grind.CFrame
			heat.Size = Vector3.one * (0.9 + 0.35 * math.sin(t * 40))
		end
	end
	-- (the blade stands up across the slot: its axis along the slot's side)
	local cf = base * CFrame.new(along, radius * 0.55, 0) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.Angles((t * 14) % (math.pi * 2), 0, 0)
	local disc, hub = child(m, "Disc"), child(m, "Hub")
	if disc then disc.CFrame = cf end
	if hub then hub.CFrame = cf end
	local k = 0
	for _, p in ipairs(m:GetChildren()) do
		if p.Name == "Teeth" and p:IsA("BasePart") then
			p.CFrame = if k == 0 then cf else cf * CFrame.Angles(math.rad(45), 0, 0)
			k += 1
		end
	end
end

local function sweeper(r: Rec, t: number)
	local m = r.model
	local center = vec(m, "Center")
	if not center then return end
	local spin, len = num(m, "Spin", 1), num(m, "Length", 9)
	local rot = CFrame.new(center) * CFrame.Angles(0, num(m, "Phase", 0) + spin * t, 0)
	local blade, edge = child(m, "Blade"), child(m, "Edge")
	if blade then blade.CFrame = rot * CFrame.new(len / 2 + 0.6, 0, 0) end
	if edge then edge.CFrame = rot * CFrame.new(len / 2 + 0.6, 0, -0.6 * math.sign(spin)) end
end

local LAVA_HOT = Color3.fromRGB(255, 104, 24)
local function lava(r: Rec, t: number)
	local m = r.model
	local center = vec(m, "Center")
	if not center then return end
	-- the crust drifting back and forth (4.5 s each way)
	local flow = child(m, "LavaFlow")
	if flow then
		local k = 0.5 - 0.5 * math.cos(t * math.pi / 4.5)
		flow.CFrame = CFrame.new(center + Vector3.new(-1 + 2 * k, 0.27, -0.8 + 1.6 * k))
		flow.Transparency = 0.6 - 0.15 * k
	end
	-- the glow under it, pulsing
	local glow = child(m, "Lava")
	if glow then
		r.baseColor = r.baseColor or glow.Color
		glow.Color = (r.baseColor :: Color3):Lerp(LAVA_HOT, 0.5 - 0.5 * math.cos(t * math.pi / 1.6))
	end
end

-- ── By state ────────────────────────────────────────────────────────────────
local function vent(r: Rec, _a: number, state: string, blend: number)
	local glow = child(r.model, "Glow")
	if not glow then return end
	local to = if state == "rest" then 0.9 else 0.1
	glow.Transparency += (to - glow.Transparency) * blend
end

local function spikes(r: Rec, a: number, state: string, blend: number)
	local m = r.model
	local warn = child(m, "Warn")
	if warn then
		local to = if state == "rest" then 1 else 0.25
		warn.Transparency += (to - warn.Transparency) * blend
	end
	-- (up fast, down slower; down only if they went up: seen first at rest, they stay down)
	if state == "active" then r.up = true end
	local k = if state == "active" then math.clamp(a * 10, 0, 1)
		elseif state == "rest" and r.up then 1 - math.clamp(a * 1.6, 0, 1) else 0
	if state == "rest" and k <= 0 then r.up = false end
	for _, p in ipairs(m:GetChildren()) do
		if p.Name == "Spike" and p:IsA("BasePart") then
			local rest = r.rest[p]
			if not rest then
				rest = p.CFrame
				r.rest[p] = rest
			end
			if state == "rest" and k <= 0 then p.CFrame = rest
			elseif state == "active" or state == "rest" then p.CFrame = (rest :: CFrame) + Vector3.new(0, 2.6 * ease(k), 0)
			end
		end
	end
end

local COALS_REST = Color3.fromRGB(120, 28, 8)
local COALS_HOT = Color3.fromRGB(255, 120, 30)
local function coals(r: Rec, _a: number, state: string, blend: number)
	local pit = child(r.model, "Coals")
	if not pit then return end
	pit.Color = pit.Color:Lerp(if state == "rest" then COALS_REST else COALS_HOT, blend)
end

local BLINK_HOT = Color3.fromRGB(255, 240, 200)
local BLINK_COOL = Color3.fromRGB(255, 90, 20)
local LID_HOT = Color3.fromRGB(255, 80, 50)
local LID_COOL = Color3.fromRGB(160, 40, 30)
local function barrel(r: Rec, t: number)
	local m = r.model
	local litAt = m:GetAttribute("LitAt")
	if typeof(litAt) ~= "number" then return end
	local fuse, radius = num(m, "Fuse", 2), num(m, "Radius", 11)
	local k = math.clamp((t - litAt) / fuse, 0, 1)
	-- blinking faster and faster: a flash of 0.06 s every 0.3 s, down to 0.05
	local period = 0.06 + math.max(0.05, 0.3 * (1 - k))
	local on = ((t - litAt) % period) < 0.06
	for _, p in ipairs(m:GetChildren()) do
		if p.Name == "Slit" and p:IsA("BasePart") then p.Color = if on then BLINK_HOT else BLINK_COOL end
	end
	local lid = child(m, "Lid")
	if lid then lid.Color = if on then LID_HOT else LID_COOL end
	local ring = child(m, "Warning")
	if ring then
		local d = 1 + (radius * 2 - 1) * k
		ring.Size = Vector3.new(0.12, d, d)
		ring.Transparency = 0.55 - 0.2 * k
	end
end

-- The room's reward orb: a gentle bob, the core pulsing (faster once it's
-- charged: "Charged"), until it's claimed.
local function reward(r: Rec, t: number)
	local m = r.model
	local center = vec(m, "Center")
	if not center or m:GetAttribute("Claimed") == true then return end
	local charge = if m:GetAttribute("Charged") == true then 1 else 0
	local cf = CFrame.new(center + Vector3.new(0, math.sin(t * 2) * 0.3, 0))
	local orb, core = child(m, "Orb"), child(m, "Core")
	if orb then orb.CFrame = cf end
	if core then
		core.CFrame = cf
		core.Size = Vector3.one * 1.8 * (1 + math.sin(t * (3 + charge * 6)) * 0.08 * (0.3 + charge))
	end
end

local CLOCKED: { [string]: (Rec, number) -> () } = {
	RoomReward = reward,
	SawBlade = saw,
	BladeSweeper = sweeper,
	LavaField = lava,
	ExplosiveBarrel = barrel,
}
local STATED: { [string]: (Rec, number, string, number) -> () } = {
	FlameVent = vent,
	SpikeTrap = spikes,
	BurningTrap = coals,
}

local function add(inst: Instance)
	if not inst:IsA("Model") or recs[inst] then return end
	local r: Rec = { model = inst, changedAt = os.clock(), settled = false, rest = {}, lastSign = 0 }
	recs[inst] = r
	inst:GetAttributeChangedSignal("State"):Connect(function()
		r.changedAt = os.clock()
		r.settled = false
	end)
	-- (a part streamed in late: show it in the state it's in)
	inst.ChildAdded:Connect(function() r.settled = false end)
end

local function focus(): Vector3
	local cam = Workspace.CurrentCamera
	return if cam then cam.Focus.Position else Vector3.zero
end

local function frame(dt: number)
	local t = Workspace:GetServerTimeNow()
	local blend = 1 - math.exp(-dt * 7) -- (eased toward a state's look, whatever the frame rate)
	local now = os.clock()
	local at = focus()
	for m, r in pairs(recs) do
		if not m.Parent then
			recs[m] = nil
			continue
		end
		local pivot = vec(m, "Center")
		local anyPart = pivot or (m.PrimaryPart and m.PrimaryPart.Position)
		if not anyPart then
			local p = m:FindFirstChildWhichIsA("BasePart")
			anyPart = p and p.Position
		end
		if not anyPart or (anyPart - at).Magnitude > RANGE then continue end
		local clocked = CLOCKED[m.Name]
		if clocked then
			clocked(r, t)
			continue
		end
		local stated = STATED[m.Name]
		if stated and not r.settled then
			local state = m:GetAttribute("State")
			local a = (now - r.changedAt) / STATE_EASE
			if a >= 1 then
				r.settled = true
				a = 1
			end
			stated(r, a, if typeof(state) == "string" then state else "rest", if r.settled then 1 else blend)
		end
	end
end

function HazardFX.Init()
	CollectionService:GetInstanceAddedSignal("HazardFX"):Connect(add)
	CollectionService:GetInstanceRemovedSignal("HazardFX"):Connect(function(inst)
		if inst:IsA("Model") then recs[inst] = nil end
	end)
	for _, inst in ipairs(CollectionService:GetTagged("HazardFX")) do add(inst) end
	RunService.RenderStepped:Connect(frame)
end

return HazardFX
