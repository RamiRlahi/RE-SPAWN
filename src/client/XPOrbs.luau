--[[
	XPOrbs.luau
	XP sparks: when a mob dies, blue sparks burst out of it, scatter for a beat,
	then home in on the local player along curving paths (accelerating), each
	popping as it's absorbed; the last one sends a soft blue pulse around you.
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local CORE = Color3.fromRGB(200, 240, 255)
local BLUE = Color3.fromRGB(70, 160, 255)
local DEEP = Color3.fromRGB(40, 90, 255)

local SCATTER_TIME = 0.28 -- seconds of free burst before homing starts
local MAX_LIFE = 2.6      -- safety: anything still flying is absorbed

local XPOrbs = {}

type Spark = { part: BasePart, vel: Vector3, age: number, delay: number }
local sparks: { Spark } = {}
local conn: RBXScriptConnection? = nil
local pendingPulse = 0

local function newSpark(pos: Vector3): BasePart
	local p = Instance.new("Part")
	p.Name = "XPSpark"
	p.Shape = Enum.PartType.Ball
	p.Size = Vector3.new(0.32, 0.32, 0.32)
	p.Material = Enum.Material.Neon
	p.Color = CORE
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.CFrame = CFrame.new(pos)
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 0.14, 0)
	a0.Parent = p
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -0.14, 0)
	a1.Parent = p
	local trail = Instance.new("Trail")
	trail.Attachment0, trail.Attachment1 = a0, a1
	trail.Color = ColorSequence.new(BLUE, DEEP)
	trail.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	trail.Lifetime = 0.25
	trail.LightEmission = 1
	trail.FaceCamera = true
	trail.WidthScale = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) })
	trail.Parent = p
	p.Parent = Workspace.Terrain
	return p
end

local function absorbFlash(at: Vector3)
	local a = Instance.new("Attachment")
	a.Parent = Workspace.Terrain
	a.WorldPosition = at
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Color = ColorSequence.new(CORE, BLUE)
	pe.LightEmission = 1
	pe.LightInfluence = 0
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	pe.Lifetime = NumberRange.new(0.15, 0.3)
	pe.Speed = NumberRange.new(3, 7)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Rate = 0
	pe.Parent = a
	pe:Emit(4)
	Debris:AddItem(a, 0.5)
end

-- Soft blue ring rising around the player once a batch has been absorbed.
local function pulse(root: BasePart)
	local ring = Instance.new("Part")
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored, ring.CanCollide, ring.CanQuery, ring.CanTouch, ring.CastShadow = true, false, false, false, false
	ring.Material = Enum.Material.Neon
	ring.Color = BLUE
	ring.Transparency = 0.35
	ring.Size = Vector3.new(0.08, 2, 2)
	ring.CFrame = CFrame.new(root.Position - Vector3.new(0, 2.6, 0)) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = Workspace.Terrain
	TweenService:Create(ring, TweenInfo.new(0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
		Size = Vector3.new(0.05, 6, 6), Transparency = 1,
		CFrame = ring.CFrame + Vector3.new(0, 1.5, 0),
	}):Play()
	Debris:AddItem(ring, 0.5)
	local l = Instance.new("PointLight")
	l.Color, l.Brightness, l.Range, l.Shadows = BLUE, 2.5, 10, false
	l.Parent = root
	TweenService:Create(l, TweenInfo.new(0.4), { Brightness = 0 }):Play()
	Debris:AddItem(l, 0.45)
end

local function step(dt: number)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	for i = #sparks, 1, -1 do
		local s = sparks[i]
		s.age += dt
		if not root or not s.part.Parent then
			s.part:Destroy()
			table.remove(sparks, i)
			continue
		end
		local pos = s.part.Position
		local target = root.Position + Vector3.new(0, 0.8, 0)
		local homing = s.age - s.delay
		if homing <= 0 then
			-- Scatter: drag slows the burst so they hang for a moment.
			s.vel *= math.exp(-4 * dt)
			s.vel += Vector3.new(0, -6 * dt, 0)
		else
			-- Home: steer toward the player, faster and tighter over time.
			local toTarget = target - pos
			local dist = toTarget.Magnitude
			local speed = 18 + homing * 70
			local desired = toTarget.Unit * speed
			local steer = 1 - math.exp(-(4 + homing * 14) * dt)
			s.vel = s.vel:Lerp(desired, steer)
			if dist < 1.3 or s.age > MAX_LIFE then
				absorbFlash(target)
				s.part:Destroy()
				table.remove(sparks, i)
				pendingPulse -= 1
				if pendingPulse <= 0 then
					pendingPulse = 0
					pulse(root)
				end
				continue
			end
		end
		s.part.CFrame = CFrame.new(pos + s.vel * dt)
	end
	if #sparks == 0 and conn then
		conn:Disconnect()
		conn = nil
	end
end

-- Burst `count` XP sparks out of a dying mob at `position`.
function XPOrbs.spawn(position: Vector3, count: number?)
	local n = count or 8
	for i = 1, n do
		local dir = Vector3.new(math.random() - 0.5, 0.5 + math.random() * 0.8, math.random() - 0.5).Unit
		table.insert(sparks, {
			part = newSpark(position + Vector3.new(0, 1, 0)),
			vel = dir * (12 + math.random() * 10),
			age = 0,
			-- Stagger the take-off so they stream in rather than arrive as one clump.
			delay = SCATTER_TIME + (i / n) * 0.25,
		})
	end
	pendingPulse += n
	if not conn then
		conn = RunService.RenderStepped:Connect(step)
	end
end

return XPOrbs
