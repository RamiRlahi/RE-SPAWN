--[[
	SkateController.luau
	Ice Mage locomotion: the mage skates instead of walking.

	Local player (physics):
	  A LinearVelocity on the root drives horizontal motion with momentum —
	  accelerate into a glide, coast when input is released, carve turns, and
	  hockey-stop (with a snow spray) when reversing or when a cast halts you.
	  Vertical motion (gravity, jumps) is untouched; airborne keeps momentum.

	Every ice mage (visuals, including other players):
	  crystal blades on the feet, frost lines carved into the floor, snow spray,
	  and a procedural skating stride that replaces the walk cycle.
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")
local RunScope = require(game:GetService("ReplicatedStorage"):WaitForChild("Shared"):WaitForChild("RunScope"))

local CastPoses = require(script.Parent:WaitForChild("CastPoses"))

local player = Players.LocalPlayer

local ICE_WHITE = Color3.fromRGB(240, 252, 255)
local ICE_PALE = Color3.fromRGB(190, 240, 255)
local ICE_CYAN = Color3.fromRGB(90, 220, 255)
local TEX_SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"

-- ── Tuning ──────────────────────────────────────────────────────────────────
local SKATE_SPEED_MULT = 1.25 -- skating top speed vs the humanoid's WalkSpeed
local CAST_SPEED_MULT = 0.7   -- top speed while skating during a movable cast (Ice Beam)
local ACCEL = 3.2             -- how fast you reach top speed (higher = snappier)
local TURN_ACCEL = 5.5        -- carving strength when changing direction
local GLIDE_DECAY = 0.9       -- coasting friction with no input (lower = longer glide)
local STOP_DECAY = 6.0        -- skid-to-stop strength when a cast roots you
local HOCKEY_DECAY = 8.0      -- reversing hard
local DRIVE_FORCE = 2500      -- per unit mass; enough to override the humanoid's own drive

local SkateController = {}

local function isIceMage(plr: Player?): boolean
	return plr ~= nil and plr:GetAttribute("SelectedClass") == "ice_mage" and plr:GetAttribute("InLobby") ~= true
end

-- On a mount, or thrown off one: no skating (the mount carries you; the
-- tumble moves and poses the body).
local function skates(plr: Player): boolean
	local char = plr.Character
	return isIceMage(plr) and not (char and (char:GetAttribute("Riding") or char:GetAttribute("Tumbling")))
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function newPart(parent: Instance, props: { [string]: any }): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	for k, v in pairs(props) do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

local function getFeet(char: Model): (BasePart?, BasePart?)
	local l = char:FindFirstChild("LeftFoot") or char:FindFirstChild("Left Leg")
	local r = char:FindFirstChild("RightFoot") or char:FindFirstChild("Right Leg")
	return l :: BasePart?, r :: BasePart?
end

-- ═════════════════════════════════════════════════════════════════════════════
-- Per-character skating visuals
-- ═════════════════════════════════════════════════════════════════════════════
type SkaterState = {
	char: Model,
	root: BasePart,
	humanoid: Humanoid,
	motors: any,
	folder: Folder,
	feet: { { part: BasePart, last: Vector3?, spray: ParticleEmitter } },
	phase: number,
	speedSmooth: number,
	lean: number,
	glide: number,
	lastVel: Vector3,
	lastCarve: number,
	lastSprayBurst: number,
}

local skaters: { [Model]: SkaterState } = {}

local function buildBlade(folder: Folder, foot: BasePart): ParticleEmitter
	-- Crystal runner under the sole: neon core + glass edge, welded to the foot.
	local sole = foot.CFrame * CFrame.new(0, -foot.Size.Y * 0.5 - 0.12, 0)
	local blade = newPart(folder, {
		Name = "SkateBlade",
		Size = Vector3.new(0.12, 0.22, foot.Size.Z + 0.6),
		CFrame = sole,
		Color = ICE_CYAN,
		Material = Enum.Material.Neon,
		Transparency = 0.05,
		Anchored = false,
		Massless = true,
	})
	local edge = newPart(folder, {
		Name = "SkateEdge",
		Size = Vector3.new(0.3, 0.1, foot.Size.Z + 0.3),
		CFrame = sole * CFrame.new(0, 0.12, 0),
		Color = ICE_PALE,
		Material = Enum.Material.Glass,
		Transparency = 0.3,
		Anchored = false,
		Massless = true,
	})
	for _, p in ipairs({ blade, edge }) do
		local w = Instance.new("WeldConstraint")
		w.Part0, w.Part1 = foot, p
		w.Parent = p
	end
	local a = Instance.new("Attachment")
	a.Position = Vector3.new(0, -0.1, blade.Size.Z * 0.35)
	a.Parent = blade
	local spray = Instance.new("ParticleEmitter")
	spray.Texture = TEX_SPARKLE
	spray.Color = ColorSequence.new(ICE_WHITE, ICE_CYAN)
	spray.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	spray.Lifetime = NumberRange.new(0.25, 0.5)
	spray.Speed = NumberRange.new(3, 7)
	spray.SpreadAngle = Vector2.new(35, 20)
	spray.EmissionDirection = Enum.NormalId.Back
	spray.Acceleration = Vector3.new(0, -20, 0)
	spray.LightEmission = 1
	spray.LightInfluence = 0
	spray.Rate = 0
	spray.Parent = a
	return spray
end

local function sprayBurst(pos: Vector3, dir: Vector3, count: number)
	local att = Instance.new("Attachment")
	att.Parent = Workspace.Terrain
	att.WorldCFrame = CFrame.lookAt(pos, pos + (dir.Magnitude > 0.01 and dir.Unit or Vector3.zAxis))
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = TEX_SPARKLE
	pe.Color = ColorSequence.new(ICE_WHITE, ICE_PALE)
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	pe.Lifetime = NumberRange.new(0.3, 0.6)
	pe.Speed = NumberRange.new(10, 22)
	pe.SpreadAngle = Vector2.new(40, 25)
	pe.EmissionDirection = Enum.NormalId.Front
	pe.Acceleration = Vector3.new(0, -35, 0)
	pe.LightEmission = 1
	pe.Rate = 0
	pe.Parent = att
	pe:Emit(count)
	local mist = pe:Clone()
	mist.Texture = TEX_SMOKE
	mist.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.2), NumberSequenceKeypoint.new(1, 3.5) })
	mist.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 1) })
	mist.Speed = NumberRange.new(3, 7)
	mist.LightEmission = 0.3
	mist.Parent = att
	mist:Emit(math.ceil(count / 5))
	Debris:AddItem(att, 1)
end

-- A carved frost line from the foot's last position to its current one.
local function carve(folder: Folder, a: Vector3, b: Vector3)
	local len = (b - a).Magnitude
	if len < 0.3 then return end
	local mid = (a + b) * 0.5
	local line = newPart(folder, {
		Name = "Carve",
		Size = Vector3.new(0.22, 0.04, len + 0.1),
		CFrame = CFrame.lookAt(mid, b),
		Color = ICE_WHITE,
		Material = Enum.Material.Neon,
		Transparency = 0.25,
	})
	local frost = newPart(folder, {
		Name = "CarveFrost",
		Size = Vector3.new(0.9, 0.03, len + 0.2),
		CFrame = CFrame.lookAt(mid, b) * CFrame.new(0, -0.01, 0),
		Color = ICE_PALE,
		Material = Enum.Material.Glass,
		Transparency = 0.55,
	})
	TweenService:Create(line, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1, Color = ICE_CYAN }):Play()
	TweenService:Create(frost, TweenInfo.new(1.8, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Transparency = 1, Size = frost.Size * Vector3.new(1.6, 1, 1) }):Play()
	Debris:AddItem(line, 1.5)
	Debris:AddItem(frost, 1.9)
end

local groundParams = RaycastParams.new()
groundParams.FilterType = Enum.RaycastFilterType.Exclude
local function groundUnder(pos: Vector3, exclude: { Instance }): Vector3?
	groundParams.FilterDescendantsInstances = exclude
	local hit = Workspace:Raycast(pos + Vector3.new(0, 1, 0), Vector3.new(0, -4, 0), groundParams)
	return hit and (hit.Position + Vector3.new(0, 0.03, 0)) or nil
end

local function attachSkater(char: Model)
	if skaters[char] then return end
	local root = char:WaitForChild("HumanoidRootPart", 5) :: BasePart?
	local humanoid = char:WaitForChild("Humanoid", 5) :: Humanoid?
	if not root or not humanoid then return end
	local folder = Instance.new("Folder")
	folder.Name = "SkateFX"
	folder.Parent = Workspace.Terrain
	local feet = {}
	local l, r = getFeet(char)
	for _, foot in ipairs({ l, r }) do
		if foot then
			table.insert(feet, { part = foot, last = nil, spray = buildBlade(folder, foot) })
		end
	end
	skaters[char] = {
		char = char,
		root = root,
		humanoid = humanoid,
		motors = CastPoses.resolveMotors(char),
		folder = folder,
		feet = feet,
		phase = 0,
		speedSmooth = 0,
		lean = 0,
		glide = 0,
		lastVel = Vector3.zero,
		lastCarve = 0,
		lastSprayBurst = 0,
	}
end

local function detachSkater(char: Model)
	local s = skaters[char]
	if not s then return end
	skaters[char] = nil
	s.folder:Destroy()
end

-- Skating stride, in the same character-space convention as CastPoses.
-- Speed-skater silhouette: the whole body pitches forward hard; the hips
-- compensate so the support leg plants under the body while the pushing leg
-- drives far out and back (works on R6, which has no knees — R15 also bends
-- the knees deeply). `glide` (0..1) blends into a coasting pose: one leg
-- extended long behind, arms swept back.
local function mix(a: number, b: number, t: number): number
	return a + (b - a) * t
end

local function stridePose(s: number, phase: number, lean: number, glide: number): { [string]: { number } }
	local sw = math.sin(phase)
	local rPush = math.max(0, sw)   -- right leg pushing
	local lPush = math.max(0, -sw)  -- left leg pushing
	local stride = 1 - glide
	local pitch = (34 + 6 * glide) * s -- forward lean of the whole body

	-- Legs: stride values blended with the glide pose.
	local rhX = mix(pitch + 8 * s * lPush - 60 * s * rPush, pitch + 10 * s, glide)
	local rhZ = mix(4 * s + 32 * s * rPush, 3 * s, glide)
	local lhX = mix(pitch + 8 * s * rPush - 60 * s * lPush, pitch - 62 * s, glide)
	local lhZ = mix(-4 * s - 32 * s * lPush, -20 * s, glide)
	-- Arms: big counter-swing while striding; swept back to balance while gliding.
	local rsX = mix(12 * s - 60 * sw * s, -55 * s, glide)
	local rsZ = mix(20 * s, 12 * s, glide)
	local lsX = mix(12 * s + 60 * sw * s, 25 * s, glide)
	local lsZ = mix(-20 * s, -48 * s, glide)

	return {
		-- Drop to keep the planted foot grounded as the legs angle; bob on each push.
		Root = { 0, 0, -lean * 28, 0, -0.38 * s - 0.14 * s * math.abs(sw) * stride, 0 },
		W = { -pitch, lean * 8, lean * 10 },
		N = { pitch * 0.8, 0, -lean * 6 }, -- head stays up, eyes forward
		RH = { rhX, 0, rhZ },
		LH = { lhX, 0, lhZ },
		RK = { mix(-55 * s + 35 * s * rPush, -45 * s, glide), 0, 0 },
		LK = { mix(-55 * s + 35 * s * lPush, -10 * s, glide), 0, 0 },
		RS = { rsX, 0, rsZ },
		LS = { lsX, 0, lsZ },
		RE = { 25 * s, 0, 0 },
		LE = { 25 * s, 0, 0 },
	}
end

-- ═════════════════════════════════════════════════════════════════════════════
-- Local physics
-- ═════════════════════════════════════════════════════════════════════════════
local drive: LinearVelocity? = nil
local driveAtt: Attachment? = nil
local velocity = Vector3.zero
-- The floor reading blinks to Air for a frame over tile seams and small
-- bumps; treating that as airborne cut the drive on and off (jitter).
local AIR_GRACE = 0.15
local lastGrounded = 0

local function ensureDrive(root: BasePart)
	if drive and drive.Parent and driveAtt and driveAtt.Parent == root then return end
	driveAtt = Instance.new("Attachment")
	driveAtt.Name = "SkateDriveAttachment"
	driveAtt.Parent = root
	local lv = Instance.new("LinearVelocity")
	lv.Name = "SkateDrive"
	lv.Attachment0 = driveAtt
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.VelocityConstraintMode = Enum.VelocityConstraintMode.Vector
	lv.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	lv.Enabled = false
	lv.Parent = root
	drive = lv
	velocity = flat(root.AssemblyLinearVelocity)
end

local function releaseDrive()
	if drive then drive.Enabled = false end
end

local function updateLocalPhysics(s: SkaterState, dt: number): (boolean, boolean)
	local char, root, hum = s.char, s.root, s.humanoid
	ensureDrive(root)
	local lv = drive :: LinearVelocity
	if hum.FloorMaterial ~= Enum.Material.Air then lastGrounded = os.clock() end
	local grounded = os.clock() - lastGrounded < AIR_GRACE
		and hum:GetState() ~= Enum.HumanoidStateType.Jumping and hum:GetState() ~= Enum.HumanoidStateType.Freefall
	local paused = RunScope.Mine("TomesPaused") == true or root.Anchored or hum.Health <= 0
	if paused then
		velocity = Vector3.zero
		lv.Enabled = false
		return false, false
	end
	if not grounded then
		-- Airborne: physics keeps the momentum; resync when we land.
		lv.Enabled = false
		velocity = flat(root.AssemblyLinearVelocity)
		return false, false
	end

	local casting = char:GetAttribute("IsSkillCasting") == true
	local canMove = not casting or char:GetAttribute("AllowSkillMovement") == true
	local input = flat(hum.MoveDirection)
	local hasInput = input.Magnitude > 0.1 and canMove
	local topSpeed = math.max(hum.WalkSpeed, 16) * SKATE_SPEED_MULT * (casting and CAST_SPEED_MULT or 1)

	local target = hasInput and input.Unit * topSpeed or Vector3.zero
	local k
	local hockey = false
	if not canMove then
		k = STOP_DECAY
	elseif not hasInput then
		k = GLIDE_DECAY
	elseif velocity.Magnitude > 4 and velocity.Unit:Dot(input.Unit) < -0.35 then
		k = HOCKEY_DECAY
		hockey = true
	elseif velocity.Magnitude > 4 and velocity.Unit:Dot(input.Unit) < 0.8 then
		k = TURN_ACCEL
	else
		k = ACCEL
	end
	velocity = velocity:Lerp(target, 1 - math.exp(-k * dt))
	if velocity.Magnitude < 0.2 and not hasInput then velocity = Vector3.zero end

	local mass = root.AssemblyMass
	lv.MaxAxesForce = Vector3.new(mass * DRIVE_FORCE, 0, mass * DRIVE_FORCE)
	lv.VectorVelocity = velocity
	lv.Enabled = true

	-- We steer the body ourselves: face the direction of travel while skating
	-- freely; during casts the skill (e.g. the beam) aims the body instead.
	hum.AutoRotate = false
	if not casting and velocity.Magnitude > 2 then
		local look = flat(root.CFrame.LookVector)
		local desired = velocity.Unit
		local blended = look:Lerp(desired, 1 - math.exp(-10 * dt))
		if blended.Magnitude > 0.01 then
			root.CFrame = CFrame.lookAt(root.Position, root.Position + blended)
		end
	end
	return true, hockey or (not canMove and velocity.Magnitude > 8)
end

-- ═════════════════════════════════════════════════════════════════════════════
-- Per-frame update
-- ═════════════════════════════════════════════════════════════════════════════
local function fadeLocomotion(hum: Humanoid, weight: number)
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then return end
	for _, track in ipairs(animator:GetPlayingAnimationTracks()) do
		local n = track.Animation and track.Animation.Name
		if n == "walk" or n == "run" then
			track:AdjustWeight(weight, 0.15)
		end
	end
end

local function step(dt: number)
	local now = os.clock()
	for char, s in pairs(skaters) do
		if not char.Parent or not s.root.Parent then
			detachSkater(char)
			continue
		end
		local isLocal = char == player.Character
		local skidding = false
		if isLocal then
			local _, skid = updateLocalPhysics(s, dt)
			skidding = skid
		end

		local vel = flat(s.root.AssemblyLinearVelocity)
		local speed = vel.Magnitude
		local grounded = s.humanoid.FloorMaterial ~= Enum.Material.Air
		local topRef = math.max(s.humanoid.WalkSpeed, 16) * SKATE_SPEED_MULT
		local sTarget = grounded and math.clamp(speed / topRef, 0, 1) or 0.4
		s.speedSmooth += (sTarget - s.speedSmooth) * (1 - math.exp(-6 * dt))

		-- Lean into turns: signed rate of change of the travel direction.
		local turn = 0
		if speed > 3 and s.lastVel.Magnitude > 3 then
			turn = s.lastVel.Unit:Cross(vel.Unit).Y / math.max(dt, 1e-3)
		end
		s.lean += (math.clamp(turn * 0.55, -1, 1) - s.lean) * (1 - math.exp(-5 * dt))
		local decel = (s.lastVel.Magnitude - speed) / math.max(dt, 1e-3)
		s.lastVel = vel

		local coasting = flat(s.humanoid.MoveDirection).Magnitude < 0.1
		s.phase += dt * (2.2 + speed * 0.22) * (coasting and 0 or 1)

		-- Replace the walk cycle with the stride once we're really skating.
		fadeLocomotion(s.humanoid, s.speedSmooth > 0.15 and 0.001 or 1)
		if s.speedSmooth > 0.02 then
			s.glide += ((coasting and 1 or 0) - s.glide) * (1 - math.exp(-5 * dt))
		local pose = stridePose(s.speedSmooth, s.phase, s.lean, s.glide)
			local combined: { [Motor6D]: CFrame } = {}
			for key, m in pairs(s.motors) do
				local v = pose[key]
				if v then
					local cf = m.basis:Inverse() * CastPoses.poseCF(v) * m.basis
					combined[m.motor] = (combined[m.motor] or CFrame.identity) * cf
				end
			end
			for motor, cf in pairs(combined) do
				motor.Transform = motor.Transform * cf
			end
		end

		-- Blades: spray scales with speed and turning; carve lines on the floor.
		local carving = grounded and speed > 5
		for _, f in ipairs(s.feet) do
			f.spray.Rate = carving and (speed * 1.2 + math.abs(s.lean) * 40) or 0
		end
		if carving and now - s.lastCarve > 0.05 then
			s.lastCarve = now
			for _, f in ipairs(s.feet) do
				local g = groundUnder(f.part.Position, { char, s.folder })
				if g then
					if f.last and (g - f.last).Magnitude < 6 then
						carve(s.folder, f.last, g)
					end
					f.last = g
				else
					f.last = nil
				end
			end
		elseif not carving then
			for _, f in ipairs(s.feet) do f.last = nil end
		end

		-- Hockey stop / hard skid: big spray off the leading blade.
		if grounded and (skidding or decel > 45) and speed > 6 and now - s.lastSprayBurst > 0.25 then
			s.lastSprayBurst = now
			local _, rFoot = getFeet(char)
			local p = (rFoot and rFoot.Position or s.root.Position - Vector3.new(0, 2.5, 0))
			sprayBurst(p, vel + Vector3.new(0, speed * 0.3, 0), 22)
		end
	end

	-- Drop the drive if the local player stopped being a skater.
	local myChar = player.Character
	if not (myChar and skaters[myChar]) then
		releaseDrive()
	end
end

-- ═════════════════════════════════════════════════════════════════════════════
-- Init: track every ice mage character
-- ═════════════════════════════════════════════════════════════════════════════
function SkateController.Init()
	local function refresh(plr: Player)
		local char = plr.Character
		if not char then return end
		if skates(plr) then
			task.spawn(attachSkater, char)
		else
			detachSkater(char)
			if plr == player then
				releaseDrive()
				local hum = char:FindFirstChildOfClass("Humanoid")
				if hum then
					hum.AutoRotate = true
					fadeLocomotion(hum, 1)
				end
			end
		end
	end
	local function hook(plr: Player)
		local function watch(char: Model)
			char:GetAttributeChangedSignal("Riding"):Connect(function() refresh(plr) end)
			char:GetAttributeChangedSignal("Tumbling"):Connect(function() refresh(plr) end)
		end
		plr.CharacterAdded:Connect(function(char)
			watch(char)
			task.defer(refresh, plr)
		end)
		if plr.Character then watch(plr.Character) end
		plr:GetAttributeChangedSignal("SelectedClass"):Connect(function() refresh(plr) end)
		plr:GetAttributeChangedSignal("InLobby"):Connect(function() refresh(plr) end)
		refresh(plr)
	end
	for _, plr in ipairs(Players:GetPlayers()) do hook(plr) end
	Players.PlayerAdded:Connect(hook)
	-- Stepped: after the Animator has posed the rig, before physics.
	RunService.Stepped:Connect(function(_, dt)
		step(dt)
	end)
end

return SkateController
