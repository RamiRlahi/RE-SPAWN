--!strict
--[[
	PackFX.luau
	Effects from the VFX pack (ReplicatedStorage.VFXPack, the pack's emitters
	switched off at rest), fired in code: a copy of an effect's part dropped
	where it's wanted, every emitter recoloured and scaled to taste, emitted
	once in a burst or left running for a while, then cleared away.

	  PackFX.Burst(path, cf, opts?)            one burst, gone when it's done
	  PackFX.Run(path, cf, seconds, opts?)     running for `seconds`; returns a
	                                           mover (move(cf)) and stop()

	`path` is "Group/Effect" ("Anime/Portal-01", "Big/Explosion-01", ...).
	opts: color (Color3: every emitter that isn't black, which is kept for
	dark cores), scale (sizes and speeds), count (× the emit count), light
	(LightEmission), keepColor (don't recolour).

	Every call is an effect someone asked for; the caller budgets the per-hit
	ones (FxBudget).
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local PackFX = {}

export type Opts = { color: Color3?, scale: number?, count: number?, light: number?, keepColor: boolean? }

local cache: { [string]: BasePart } = {}

local function template(path: string): BasePart?
	local got = cache[path]
	if got and got.Parent then return got end
	local pack = ReplicatedStorage:FindFirstChild("VFXPack")
	local inst: Instance? = pack
	for _, n in ipairs(string.split(path, "/")) do
		inst = inst and inst:FindFirstChild(n)
	end
	if inst and inst:IsA("BasePart") then
		cache[path] = inst
		return inst
	end
	return nil
end

local function folder(): Instance
	local f = Workspace:FindFirstChild("ClassFX")
	if f then return f end
	local nf = Instance.new("Folder")
	nf.Name = "ClassFX"
	nf.Parent = Workspace
	return nf
end

local function scaleSeq(seq: NumberSequence, k: number): NumberSequence
	local kps = {}
	for _, kp in ipairs(seq.Keypoints) do
		table.insert(kps, NumberSequenceKeypoint.new(kp.Time, kp.Value * k, kp.Envelope * k))
	end
	return NumberSequence.new(kps)
end

local function isBlack(seq: ColorSequence): boolean
	local c = seq.Keypoints[1].Value
	return c.R + c.G + c.B < 0.06
end

-- A ready copy of the effect at `cf`: every emitter off, recoloured, scaled.
local function copy(path: string, cf: CFrame, o: Opts): (BasePart?, { ParticleEmitter }, number)
	local t = template(path)
	if not t then return nil, {}, 0 end
	local p = t:Clone()
	p.Anchored = true
	p.CanCollide, p.CanQuery, p.CanTouch = false, false, false
	p.Transparency = 1
	p.CastShadow = false
	p.CFrame = cf
	local emitters = {}
	local longest = 0
	local k = o.scale or 1
	for _, d in ipairs(p:GetDescendants()) do
		if d:IsA("ParticleEmitter") then
			d.Enabled = false
			if o.color and not o.keepColor and not isBlack(d.Color) then d.Color = ColorSequence.new(o.color) end
			if k ~= 1 then
				d.Size = scaleSeq(d.Size, k)
				d.Speed = NumberRange.new(d.Speed.Min * k, d.Speed.Max * k)
			end
			if o.light then d.LightEmission = o.light end
			longest = math.max(longest, d.Lifetime.Max)
			table.insert(emitters, d)
		elseif d:IsA("Beam") or d:IsA("Trail") or d:IsA("Light") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Transparency = 1
			d.CanCollide, d.CanQuery, d.CanTouch = false, false, false
		end
	end
	p.Parent = folder()
	return p, emitters, longest
end

function PackFX.Burst(path: string, cf: CFrame, opts: Opts?)
	local o = opts or {}
	local p, emitters, longest = copy(path, cf, o)
	if not p then return end
	for _, e in ipairs(emitters) do
		local n = tonumber(e:GetAttribute("EmitCount"))
		if not n or n <= 0 then
			-- (no count of its own: what it would make over one lifetime)
			n = math.clamp(math.floor(e.Rate * e.Lifetime.Max + 0.5), 1, 40)
		end
		e:Emit(math.max(1, math.floor(n * (o.count or 1) + 0.5)))
	end
	Debris:AddItem(p, longest + 0.2)
end

export type Running = { move: (CFrame) -> (), stop: () -> () }

function PackFX.Run(path: string, cf: CFrame, seconds: number, opts: Opts?): Running
	local o = opts or {}
	local p, emitters, longest = copy(path, cf, o)
	local stopped = false
	local function stop()
		if stopped then return end
		stopped = true
		for _, e in ipairs(emitters) do
			if e.Parent then
				e.Enabled = false
			end
		end
		if p then Debris:AddItem(p, longest + 0.2) end
	end
	if p then
		for _, e in ipairs(emitters) do
			if o.count then e.Rate *= o.count end
			e.Enabled = true
		end
		task.delay(seconds, stop)
	end
	return {
		move = function(to: CFrame)
			if p and p.Parent and not stopped then p.CFrame = to end
		end,
		stop = stop,
	}
end

return PackFX
