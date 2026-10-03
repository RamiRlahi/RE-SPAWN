--[[
	GunslingerController.luau
	Client side of the Gunslinger (server: GunslingerServer).

	  • Shooting: your own shots are predicted — the tracer, muzzle flash and
	    ammo tick happen on click; the server resolves hits and sends other
	    players' shots over GunslingerFX.
	  • Aim: while shooting the character faces the cursor (strafe-and-shoot)
	    and the gun arm is held level; Fan the Hammer adds the fanning hand.
	  • Roll (F; Space stays jump): a quick forward flip in the movement direction,
	    then one shot at the cursor as you land.
	  • All Gunslinger effects: tracers, muzzle flashes, gunpowder smoke,
	    spinning coins, seeking ricochets, blasts, marks, reload cylinders and
	    the High Noon cinematic. Everything goes under VariantFX.RootFor(the
	    shooter) so VFX variants recolour it.
	  • HUD state: GetState() + Changed (ammo, reload progress, Deadeye).
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Network = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Network"))
local VariantFX = require(script.Parent:WaitForChild("VariantFX"))
local UltimateCameraChoreography = require(script.Parent:WaitForChild("UltimateCameraChoreography"))
local SafeMove = require(script.Parent:WaitForChild("SafeMove"))

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local GunslingerController = {}

-- ── Tuning (mirrors GunslingerServer) ───────────────────────────────────────
local FIRE_INTERVAL = 0.26
local BULLET_RANGE = 62
local BULLET_WIDTH = 1.9
local COIN_HIT_RADIUS = 2.8
local FAN_INTERVAL = 0.075
local ROLL_TIME = 0.26
local ROLL_DISTANCE = 15
local NOON_CINEMATIC = 1.3 -- the sunset shot; GunslingerServer's NOON_WINDUP is a bit longer
local AIM_HOLD = 1.1 -- seconds the gun stays raised after a shot

local GOLD = Color3.fromRGB(255, 200, 96)
local HOT = Color3.fromRGB(255, 244, 214)
local BRASS = Color3.fromRGB(214, 160, 72)
local SMOKE = Color3.fromRGB(140, 128, 116)
local CRIMSON = Color3.fromRGB(230, 60, 50)
local TEX_SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"

-- ── Sounds (Roblox's licensed Pro Sound Effects library) ────────────────────
-- Swap any id here to change a sound everywhere it's used.
local SFX = {
	shot = { "rbxassetid://9118163044", "rbxassetid://9118162552" }, -- Revolver Standard Bullets 5 / 5
	heavyShot = { "rbxassetid://9114729252" },  -- Gun Single Shots 11: final shot, Deadeye, execution
	dryFire = { "rbxassetid://9117048518" },    -- click on an empty cylinder
	shellsOut = { "rbxassetid://9113108632" },  -- Ammo Shell Drop 1: reload starts
	loaded = { "rbxassetid://9113104176" },     -- Ammo Magazine 1: reload snaps shut
	coinToss = { "rbxassetid://9113849651" },   -- Coin Throws 3
	coinPing = { "rbxassetid://9118168612" },   -- Ricochet Metal 1: the shot coin
	ricochet = { "rbxassetid://9118168943", "rbxassetid://9118168962", "rbxassetid://9118168610" }, -- Ricochet Metal 4 / 5 / 2
	blast = { "rbxassetid://9119236749" },      -- Small Explosion 1
	roll = { "rbxassetid://9126229255" },       -- fast whoosh
	deadeyeReady = { "rbxassetid://9116394545" }, -- soft magic chime
	refund = { "rbxassetid://9113849492" },     -- Coins Or Keys Jingle 6
	highNoon = { "rbxassetid://9113804436" },   -- Church Bell Tolling 1 (faded out)
}

-- Play a sound at a world position (or on the listener if pos is nil).
-- fadeAfter: seconds before a long clip fades out.
local function playSound(name: string, pos: Vector3?, volume: number, pitch: number?, fadeAfter: number?)
	local list = SFX[name]
	if not list or #list == 0 then return end
	local sound = Instance.new("Sound")
	sound.SoundId = list[math.random(1, #list)]
	sound.Volume = volume
	sound.PlaybackSpeed = (pitch or 1) * (0.95 + math.random() * 0.1)
	sound.RollOffMode = Enum.RollOffMode.InverseTapered
	sound.RollOffMinDistance = 45 -- the iso camera sits ~45 studs away
	sound.RollOffMaxDistance = 160
	local holder: Instance
	if pos then
		local a = Instance.new("Attachment")
		a.WorldPosition = pos
		a.Parent = Workspace.Terrain
		holder = a
	else
		holder = sound
	end
	sound.Parent = if pos then holder else Workspace.CurrentCamera
	sound:Play()
	if fadeAfter then
		task.delay(fadeAfter, function()
			if sound.Parent then
				TweenService:Create(sound, TweenInfo.new(0.8), { Volume = 0 }):Play()
			end
		end)
		Debris:AddItem(holder, fadeAfter + 1)
	else
		Debris:AddItem(holder, 4)
	end
end

type Deps = {
	shake: (number, number) -> (),
	fovPunch: (number, number) -> (),
	useSkill: (number) -> (),
	getAim: (BasePart) -> Vector3,
	getCursor: (BasePart) -> Vector3,
}
local deps: Deps = nil :: any

-- ── Predicted state ─────────────────────────────────────────────────────────
local localAmmo = 6
local lastShot = 0
local lastDryFire = 0
local localReloadEnd = 0 -- predicted (os.clock), until the server confirms
local busyUntil = 0 -- fanning / rolling / High Noon
local onNoonEnd: (any) -> () -- defined with the High Noon effects below
local changed = Instance.new("BindableEvent")
GunslingerController.Changed = changed.Event

-- Own coins, for predicting which shots will hit one.
type LocalCoin = { part: BasePart?, pos: Vector3, landAt: number, expires: number, alive: boolean, attacker: Player }
local coins: { [number]: LocalCoin } = {}

local function isGunslinger(): boolean
	return player:GetAttribute("SelectedClass") == "gunslinger"
end

local function serverAmmo(): number
	return tonumber(player:GetAttribute("GS_Ammo")) or 6
end

local function maxAmmo(): number
	return tonumber(player:GetAttribute("GS_MaxAmmo")) or 6
end

local function serverReloadRemaining(): number
	local ends = tonumber(player:GetAttribute("GS_ReloadEnd")) or 0
	return math.max(0, ends - Workspace:GetServerTimeNow())
end

local function isReloading(): boolean
	return os.clock() < localReloadEnd or serverReloadRemaining() > 0
end

function GunslingerController.GetState()
	local reloadTime = tonumber(player:GetAttribute("GS_ReloadTime")) or 1.1
	local remaining = math.max(serverReloadRemaining(), localReloadEnd - os.clock())
	return {
		ammo = localAmmo,
		max = maxAmmo(),
		reloading = remaining > 0,
		reloadProgress = if remaining > 0 then 1 - math.clamp(remaining / reloadTime, 0, 1) else 1,
		deadeye = tonumber(player:GetAttribute("GS_Deadeye")) or 0,
	}
end

local function reconcile(force: boolean?)
	local s = serverAmmo()
	-- Adopt the server's count unless it's an older reply from before our
	-- latest shot (that would briefly bounce the count back up).
	if force or s <= localAmmo or os.clock() - lastShot > 0.35 then
		localAmmo = s
	end
	if serverReloadRemaining() <= 0 and os.clock() - localReloadEnd > 0.4 and s > 0 then
		localReloadEnd = 0
	end
	changed:Fire()
end

-- ── Small VFX helpers ───────────────────────────────────────────────────────
local function vfxRoot(owner: Player?): Instance
	return VariantFX.RootFor(owner)
end

local function neon(parent: Instance, props: { [string]: any }): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	for k, v in pairs(props) do (p :: any)[k] = v end
	p.Parent = parent
	return p
end

local function seq(...): NumberSequence
	local a = { ... }
	local k = {}
	for i = 1, #a, 2 do table.insert(k, NumberSequenceKeypoint.new(a[i], a[i + 1])) end
	return NumberSequence.new(k)
end

local function burst(owner: Player?, pos: Vector3, props: { [string]: any }, count: number, life: number?)
	local a = Instance.new("Attachment")
	a.WorldPosition = pos
	a.Parent = vfxRoot(owner)
	local pe = Instance.new("ParticleEmitter")
	pe.Rate = 0
	pe.LightInfluence = 0
	pe.SpreadAngle = Vector2.new(180, 180)
	for k, v in pairs(props) do (pe :: any)[k] = v end
	pe.Parent = a
	pe:Emit(count)
	Debris:AddItem(a, life or 1.6)
end

local function flash(owner: Player?, pos: Vector3, color: Color3, brightness: number, range: number, t: number)
	local a = Instance.new("Attachment")
	a.WorldPosition = pos
	a.Parent = vfxRoot(owner)
	local l = Instance.new("PointLight")
	l.Color, l.Brightness, l.Range, l.Shadows = color, brightness, range, false
	l.Parent = a
	TweenService:Create(l, TweenInfo.new(t), { Brightness = 0 }):Play()
	Debris:AddItem(a, t + 0.05)
end

local function gunSmoke(owner: Player?, pos: Vector3, amount: number)
	burst(owner, pos, { Texture = TEX_SMOKE, Color = ColorSequence.new(Color3.fromRGB(200, 188, 170), SMOKE), LightEmission = 0,
		Size = seq(0, 0.5, 1, 2.2 * amount), Transparency = seq(0, 0.45, 1, 1), Lifetime = NumberRange.new(0.5, 0.9),
		Speed = NumberRange.new(1, 3), Acceleration = Vector3.new(0, 2, 0) }, math.max(2, math.floor(3 * amount)), 1.2)
end

-- Where the muzzle is: the revolver's Muzzle attachment if the arm is up,
-- otherwise a point in front of the right shoulder (the arm pose lands a
-- frame later, so the first shot from rest uses this).
local function muzzleOf(char: Model): Vector3
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return char:GetPivot().Position end
	local fallback = root.Position + root.CFrame.LookVector * 2.4 + root.CFrame.RightVector * 1.0 + Vector3.new(0, 1.5, 0)
	local tool = char:FindFirstChild("Revolver")
	local m = tool and tool:FindFirstChild("Muzzle", true)
	if m and m:IsA("Attachment") and (m.WorldPosition - fallback).Magnitude < 1.5 then
		return m.WorldPosition
	end
	return fallback
end

-- ── Arm poses (gun raised / fanning / roll flip) ────────────────────────────
-- Applied every frame after the Animator, so they hold over any animation.
type Pose = { aimUntil: number, fanUntil: number, rollStart: number, rollUntil: number, lowUntil: number, twist: number,
	tossAt: number, coinPart: BasePart?, coinPos: Vector3?, coinUntil: number, recoilAt: number }
local poses: { [Model]: Pose } = {}

local function poseOf(char: Model): Pose
	local p = poses[char]
	if not p then
		p = { aimUntil = 0, fanUntil = 0, rollStart = 0, rollUntil = 0, lowUntil = 0, twist = 0, tossAt = -10, coinPart = nil, coinPos = nil, coinUntil = 0, recoilAt = -10 }
		poses[char] = p
	end
	return p
end

local function holdAim(char: Model, seconds: number)
	local p = poseOf(char)
	p.aimUntil = math.max(p.aimUntil, os.clock() + seconds)
end

local function motor(char: Model, part: string, name: string): Motor6D?
	local limb = char:FindFirstChild(part)
	local m = limb and limb:FindFirstChild(name)
	return if m and m:IsA("Motor6D") then m else nil
end

-- Adds a yaw (about the parent part's up axis, at the joint) on top of
-- whatever the Animator wrote this frame. If the Animator didn't touch the
-- joint since our last write, start again from its last animated value so
-- the twist never accumulates.
local written: { [Motor6D]: CFrame } = setmetatable({}, { __mode = "k" }) :: any
local animated: { [Motor6D]: CFrame } = setmetatable({}, { __mode = "k" }) :: any
local function yawOver(m: Motor6D, yaw: number)
	local cur = m.Transform
	if written[m] ~= cur then animated[m] = cur end
	local r = m.C0.Rotation
	local out = r:Inverse() * CFrame.Angles(0, yaw, 0) * r * (animated[m] or cur)
	m.Transform = out
	written[m] = out
end

local function applyPoses()
	local now = os.clock()
	-- Every Gunslinger holding the revolver gets a pose entry, so the gun arm
	-- is always driven here and never swings with the walk/idle animations.
	for _, plr in ipairs(Players:GetPlayers()) do
		local c = plr.Character
		if c and c:FindFirstChild("Revolver") then poseOf(c) end
	end
	for char, p in pairs(poses) do
		if not char.Parent then
			poses[char] = nil
			continue
		end
		local rightR6 = motor(char, "Torso", "Right Shoulder")
		local leftR6 = motor(char, "Torso", "Left Shoulder")
		if now < p.coinUntil then
			-- Coin trick: the gun arm tracks the coin as it rises, then kicks
			-- up with the shot's recoil and settles.
			if p.coinPart and p.coinPart.Parent then p.coinPos = p.coinPart.Position end
			local deg = 150
			local torso = char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")
			if p.coinPos and torso and torso:IsA("BasePart") then
				local v = torso.CFrame:PointToObjectSpace(p.coinPos) - Vector3.new(1.5, 0.5, 0)
				deg = math.clamp(90 + math.deg(math.atan2(v.Y, math.max(-v.Z, 0.05))), 70, 172)
			end
			-- Raise from level to the coin over the first 0.12s of the toss.
			local rise = math.clamp((now - p.tossAt) / 0.12, 0, 1)
			deg = 90 + (deg - 90) * (1 - (1 - rise) ^ 2)
			local since = now - p.recoilAt
			if since >= 0 and since < 0.5 then
				deg += 28 * math.exp(-since * 11) * math.min(since / 0.03, 1)
			end
			if rightR6 then
				rightR6.Transform = CFrame.Angles(0, 0, math.rad(deg))
			else
				local r15 = motor(char, "RightUpperArm", "RightShoulder")
				if r15 then r15.Transform = CFrame.Angles(math.rad(deg), 0, 0) end
				local elbow = motor(char, "RightLowerArm", "RightElbow")
				if elbow then elbow.Transform = CFrame.Angles(math.rad(-18 * math.exp(-math.max(since, 0) * 11)), 0, 0) end
			end
		elseif now < p.lowUntil then
			-- Quickdraw stance (the High Noon standoff): gun holstered on the
			-- right hip, both arms hanging a little out from the body with the
			-- right hand hovering over the grip, feet planted wide.
			local out = math.rad(14)
			if rightR6 then
				rightR6.Transform = CFrame.Angles(-out, 0, math.rad(-6))
				if leftR6 then leftR6.Transform = CFrame.Angles(-out, 0, 0) end
				local rh, lh = motor(char, "Torso", "Right Hip"), motor(char, "Torso", "Left Hip")
				if rh then rh.Transform = CFrame.Angles(math.rad(-7), 0, 0) end
				if lh then lh.Transform = CFrame.Angles(math.rad(-7), 0, 0) end
			else
				local r15 = motor(char, "RightUpperArm", "RightShoulder")
				if r15 then r15.Transform = CFrame.Angles(math.rad(-6), 0, out) end
				local l15 = motor(char, "LeftUpperArm", "LeftShoulder")
				if l15 then l15.Transform = CFrame.Angles(0, 0, -out) end
				local rh, lh = motor(char, "LowerTorso", "RightHip") or motor(char, "RightUpperLeg", "RightHip"),
					motor(char, "LeftUpperLeg", "LeftHip")
				if rh then rh.Transform = CFrame.Angles(0, 0, math.rad(7)) end
				if lh then lh.Transform = CFrame.Angles(0, 0, math.rad(-7)) end
			end
		elseif now < p.aimUntil or (char:FindFirstChild("Revolver") and now >= p.rollUntil) then
			-- Gun always up: arm straight out in front (R6 shoulders turn about their Z).
			if rightR6 then
				rightR6.Transform = CFrame.Angles(0, 0, math.rad(90))
			else
				local r15 = motor(char, "RightUpperArm", "RightShoulder")
				if r15 then r15.Transform = CFrame.Angles(math.rad(90), 0, 0) end
				local elbow = motor(char, "RightLowerArm", "RightElbow")
				if elbow then elbow.Transform = CFrame.identity end
				local wrist = motor(char, "RightHand", "RightWrist")
				if wrist then wrist.Transform = CFrame.identity end
			end
		end
		if p.twist ~= 0 and now >= p.rollUntil then
			-- Upper body turns to the cursor; legs stay on the move direction.
			local root = motor(char, "HumanoidRootPart", "RootJoint")
			if root then
				yawOver(root, p.twist)
				local rh, lh = motor(char, "Torso", "Right Hip"), motor(char, "Torso", "Left Hip")
				if rh then yawOver(rh, -p.twist) end
				if lh then yawOver(lh, -p.twist) end
			else
				local waist = motor(char, "UpperTorso", "Waist")
				if waist then yawOver(waist, p.twist) end
			end
		end
		local tossT = now - p.tossAt
		if tossT < 0.42 then
			-- Off hand flicks the coin up with the thumb, then drops back.
			local deg = if tossT < 0.12 then 20 + 110 * (tossT / 0.12) else 130 * (1 - (tossT - 0.12) / 0.3)
			if leftR6 then
				leftR6.Transform = CFrame.Angles(0, 0, -math.rad(deg))
			else
				local l15 = motor(char, "LeftUpperArm", "LeftShoulder")
				if l15 then l15.Transform = CFrame.Angles(math.rad(deg), 0, 0) end
			end
		end
		if now < p.fanUntil then
			-- Off hand sweeping over the hammer.
			local sweep = math.rad(78 + math.sin(now * 55) * 14)
			if leftR6 then
				leftR6.Transform = CFrame.Angles(0, 0, -sweep)
			else
				local l15 = motor(char, "LeftUpperArm", "LeftShoulder")
				if l15 then l15.Transform = CFrame.Angles(sweep, 0, math.rad(-25)) end
			end
		end
		if now < p.rollUntil then
			-- Forward flip about the root.
			local joint = motor(char, "HumanoidRootPart", "RootJoint") or motor(char, "LowerTorso", "Root")
			if joint then
				local a = math.clamp((now - p.rollStart) / (p.rollUntil - p.rollStart), 0, 1)
				local c0 = joint.C0.Rotation
				joint.Transform = c0:Inverse() * CFrame.Angles(-a * math.pi * 2, 0, 0) * c0
			end
		end
	end
end

-- Legs follow movement, the upper body (and gun) follows the cursor.
-- Backpedalling keeps the legs on the movement axis; standing still, the
-- feet only turn once the cursor swings past ~80 degrees.
local MAX_TWIST = math.rad(100)
local function faceCursor(dt: number)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not char or not root or not hum or not isGunslinger() then return end
	local p = poseOf(char)
	local now = os.clock()
	-- (During High Noon the volley turns you toward each target instead.)
	if player:GetAttribute("InLobby") ~= false or char:GetAttribute("IsUltActive") == true or now < p.rollUntil then
		p.twist = 0
		if not hum.AutoRotate and char:GetAttribute("IsUltActive") ~= true and now >= p.rollUntil then
			hum.AutoRotate = true
		end
		return
	end
	hum.AutoRotate = false
	local aim = deps.getAim(root)
	aim = Vector3.new(aim.X, 0, aim.Z)
	if aim.Magnitude < 0.01 then return end
	aim = aim.Unit
	local look = root.CFrame.LookVector
	look = Vector3.new(look.X, 0, look.Z).Unit
	local move = Vector3.new(hum.MoveDirection.X, 0, hum.MoveDirection.Z)
	local body = look
	if move.Magnitude > 0.1 then
		move = move.Unit
		body = if move:Dot(aim) < -0.35 then -move else move
	elseif look:Dot(aim) < math.cos(math.rad(80)) then
		body = aim
	end
	local newLook = if look:Dot(body) < -0.95 then body else look:Lerp(body, math.min(1, dt * 14)).Unit
	root.CFrame = CFrame.lookAt(root.Position, root.Position + newLook)
	local l = root.CFrame:VectorToObjectSpace(aim)
	p.twist = math.clamp(math.atan2(-l.X, -l.Z), -MAX_TWIST, MAX_TWIST)
end

-- ── High Noon standoff (local cinematic) ────────────────────────────────────
-- A low shot from behind: the Gunslinger as a black silhouette against a
-- painted sunset sky, a huge sun on the horizon, wind-blown dust, a leaning
-- grave cross and tumbleweeds rolling through. Only the caster sees it.
local SKY_TOP = Color3.fromRGB(70, 18, 16)
local SKY_MID = Color3.fromRGB(214, 88, 30)
local SKY_LOW = Color3.fromRGB(255, 186, 96)
local SUN = Color3.fromRGB(255, 240, 190)
local DUSK = Color3.fromRGB(26, 12, 10)
local DUST = Color3.fromRGB(226, 146, 84)

local function uiFrame(parent: Instance, props: { [string]: any }): Frame
	local f = Instance.new("Frame")
	f.BorderSizePixel = 0
	for k, v in pairs(props) do (f :: any)[k] = v end
	f.Parent = parent
	return f
end

local function round(f: Frame)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0.5, 0)
	c.Parent = f
end

local function prop(folder: Instance, props: { [string]: any }): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	for k, v in pairs(props) do (p :: any)[k] = v end
	p.Parent = folder
	return p
end

-- The painted backdrop: gradient sky, sun with halo, cloud streaks, mesas.
local function skyBackdrop(folder: Instance, cf: CFrame)
	local board = prop(folder, { Size = Vector3.new(140, 80, 0.2), CFrame = cf, Transparency = 1 })
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.LightInfluence = 0
	gui.Brightness = 1.6
	gui.PixelsPerStud = 7
	gui.Parent = board

	local sky = uiFrame(gui, { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(1, 1, 1) })
	local grad = Instance.new("UIGradient")
	grad.Rotation = 90
	grad.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, SKY_TOP),
		ColorSequenceKeypoint.new(0.45, SKY_MID),
		ColorSequenceKeypoint.new(0.72, SKY_LOW),
		ColorSequenceKeypoint.new(1, SKY_MID),
	})
	grad.Parent = sky

	-- Sun sits a touch right of centre so the hat breaks its edge.
	for i, s in ipairs({ { 0.9, 0.82 }, { 0.62, 0.6 }, { 0.44, 0 } }) do
		local f = uiFrame(sky, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(0.53, 0.6),
			Size = UDim2.fromScale(s[1] * 0.57, s[1]),
			BackgroundColor3 = if i == 3 then SUN else SKY_LOW,
			BackgroundTransparency = s[2],
		})
		round(f)
	end

	-- Dark cloud streaks drifting across the sun.
	local rng = Random.new()
	for _ = 1, 9 do
		uiFrame(sky, {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromScale(rng:NextNumber(0.05, 0.95), rng:NextNumber(0.08, 0.66)),
			Size = UDim2.fromScale(rng:NextNumber(0.2, 0.45), rng:NextNumber(0.012, 0.03)),
			BackgroundColor3 = Color3.fromRGB(110, 34, 22),
			BackgroundTransparency = rng:NextNumber(0.25, 0.55),
		})
	end

	-- Mesa silhouettes on the horizon, hazy with dust.
	for _, m in ipairs({ { 0.1, 0.26, 0.2 }, { 0.2, 0.12, 0.14 }, { 0.8, 0.3, 0.28 }, { 0.9, 0.16, 0.2 } }) do
		uiFrame(sky, {
			AnchorPoint = Vector2.new(0.5, 1),
			Position = UDim2.fromScale(m[1], 0.82),
			Size = UDim2.fromScale(m[2], m[3]),
			BackgroundColor3 = Color3.fromRGB(96, 40, 28),
			BackgroundTransparency = 0.15,
		})
	end
	uiFrame(sky, {
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0.2),
		BackgroundColor3 = Color3.fromRGB(120, 52, 30),
	})
end

local function tumbleweed(folder: Instance, from: Vector3, to: Vector3, size: number, dur: number)
	local ball = prop(folder, {
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * size,
		Color = Color3.fromRGB(70, 40, 24),
		Material = Enum.Material.Grass,
		Transparency = 0.15,
	})
	local dir = (to - from)
	local axis = Vector3.yAxis:Cross(dir.Unit)
	local t0 = os.clock()
	local conn: RBXScriptConnection? = nil
	conn = RunService.RenderStepped:Connect(function()
		local a = (os.clock() - t0) / dur
		if a >= 1 or not ball.Parent then
			if conn then conn:Disconnect() end
			return
		end
		local bounce = math.abs(math.sin(a * math.pi * 3)) * size * 0.7
		ball.CFrame = CFrame.new(from + dir * a + Vector3.new(0, bounce, 0))
			* CFrame.fromAxisAngle(axis, (dir.Magnitude * a) / (size * 0.5))
	end)
end

-- For the standoff: hide the revolver in the hand and show a copy of it
-- sitting in the right-hip holster, barrel down, grip tilted forward for
-- the draw. Put back after `dur`.
local function holsterGun(char: Model, dur: number)
	local tool = char:FindFirstChild("Revolver")
	local torso = char:FindFirstChild("Torso") or char:FindFirstChild("LowerTorso")
	if not tool or not torso or not torso:IsA("BasePart") then return end
	local copy = Instance.new("Model")
	copy.Name = "HolsteredRevolver"
	for _, child in ipairs(tool:Clone():GetChildren()) do
		if child:IsA("BasePart") then
			child.Anchored = false
			child.CanCollide, child.CanTouch, child.CanQuery = false, false, false
			child.Massless = true
		end
		child.Parent = copy
	end
	local handle = copy:FindFirstChild("Handle") :: BasePart?
	if not handle then copy:Destroy() return end
	copy.PrimaryPart = handle
	local hip = if torso.Name == "Torso" then CFrame.new(1.2, -1.15, 0.02) else CFrame.new(1.05, -0.2, 0.02)
	copy:PivotTo(torso.CFrame * hip * CFrame.Angles(math.rad(-90 + 14), 0, 0))
	local weld = Instance.new("WeldConstraint")
	weld.Part0, weld.Part1 = torso, handle
	weld.Parent = handle
	copy.Parent = char
	Debris:AddItem(copy, dur)

	local hidden: { BasePart } = {}
	for _, d in ipairs(tool:GetDescendants()) do
		if d:IsA("BasePart") then
			d.LocalTransparencyModifier = 1
			table.insert(hidden, d)
		end
	end
	task.delay(dur, function()
		for _, d in ipairs(hidden) do d.LocalTransparencyModifier = 0 end
	end)
end

local function sunsetStandoff(char: Model, aimDir: Vector3, dur: number)
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end
	local flat = Vector3.new(aimDir.X, 0, aimDir.Z)
	flat = if flat.Magnitude > 0.01 then flat.Unit else root.CFrame.LookVector
	local right = flat:Cross(Vector3.yAxis).Unit
	local base = root.Position
	-- Back to the camera, facing the sun, gun held low until the volley.
	root.CFrame = CFrame.lookAt(base, base + flat)
	poseOf(char).lowUntil = os.clock() + dur
	holsterGun(char, dur)

	local folder = Instance.new("Folder")
	folder.Name = "HighNoonStandoff"
	folder.Parent = Workspace
	Debris:AddItem(folder, dur + 0.05)

	local skyPos = base + flat * 42 + Vector3.new(0, 12, 0)
	skyBackdrop(folder, CFrame.lookAt(skyPos, skyPos - flat))

	-- Leaning grave cross with a lantern, left of frame.
	local crossPos = base + flat * 9 - right * 7 + Vector3.new(0, 1.5, 0)
	local lean = CFrame.lookAt(crossPos, crossPos - flat) * CFrame.Angles(0, 0, math.rad(-8))
	prop(folder, { Size = Vector3.new(0.5, 9, 0.5), CFrame = lean, Color = DUSK, Material = Enum.Material.Wood })
	prop(folder, { Size = Vector3.new(4.2, 0.45, 0.45), CFrame = lean * CFrame.new(0, 3, 0), Color = DUSK, Material = Enum.Material.Wood })
	local lantern = prop(folder, { Size = Vector3.new(0.4, 0.55, 0.4), CFrame = lean * CFrame.new(1.7, 2.3, 0),
		Color = Color3.fromRGB(255, 190, 90), Material = Enum.Material.Neon })
	local glow = Instance.new("PointLight")
	glow.Color = Color3.fromRGB(255, 170, 80)
	glow.Range = 8
	glow.Brightness = 2
	glow.Parent = lantern
	-- Broken fence posts, right of frame.
	for i = 0, 2 do
		local p = base + flat * (7 + i * 3) + right * (7 + i * 0.6) + Vector3.new(0, 0.2, 0)
		prop(folder, { Size = Vector3.new(0.5, 3.4 - i * 0.5, 0.5),
			CFrame = CFrame.new(p) * CFrame.Angles(0, 0, math.rad(6 - i * 7)), Color = DUSK, Material = Enum.Material.Wood })
	end

	-- Wind-blown dust sweeping right to left through the whole frame.
	local emitterPart = prop(folder, { Size = Vector3.new(20, 1, 20), Transparency = 1,
		CFrame = CFrame.new(base + flat * 6 + right * 10 + Vector3.new(0, -1.5, 0)) })
	local dust = Instance.new("ParticleEmitter")
	dust.Texture = TEX_SMOKE
	dust.Color = ColorSequence.new(DUST)
	dust.LightEmission = 0.3
	dust.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2), NumberSequenceKeypoint.new(1, 6) })
	dust.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.55), NumberSequenceKeypoint.new(1, 1) })
	dust.Lifetime = NumberRange.new(1, 1.6)
	dust.Rate = 70
	dust.Speed = NumberRange.new(14, 22)
	dust.EmissionDirection = Enum.NormalId.Top
	dust.SpreadAngle = Vector2.new(20, 20)
	dust.Acceleration = -right * 30
	dust.Parent = emitterPart
	dust:Emit(40)
	local flecks = dust:Clone()
	flecks.Texture = TEX_SPARKLE
	flecks.Color = ColorSequence.new(DUSK)
	flecks.LightEmission = 0
	flecks.Size = NumberSequence.new(0.18)
	flecks.Transparency = NumberSequence.new(0.1)
	flecks.Rate = 40
	flecks.Parent = emitterPart

	tumbleweed(folder, base + flat * 16 + right * 16, base + flat * 18 - right * 20, 2.6, dur)
	tumbleweed(folder, base + flat * 3 + right * 9 - Vector3.new(0, 1.8, 0), base + flat * 4 - right * 12 - Vector3.new(0, 1.8, 0), 1.6, dur * 0.8)

	-- Black silhouette with a warm rim.
	local rim = Instance.new("Highlight")
	rim.FillColor = Color3.fromRGB(18, 9, 7)
	rim.FillTransparency = 0.08
	rim.OutlineColor = Color3.fromRGB(255, 150, 60)
	rim.OutlineTransparency = 0.35
	rim.DepthMode = Enum.HighlightDepthMode.Occluded
	rim.Parent = folder
	rim.Adornee = char

	local grade = Instance.new("ColorCorrectionEffect")
	grade.TintColor = Color3.fromRGB(255, 196, 150)
	grade.Contrast = 0.3
	grade.Saturation = 0.25
	grade.Parent = Lighting
	Debris:AddItem(grade, dur)

	-- Low, behind and a little left; slow push-in toward the sun.
	UltimateCameraChoreography.PlayCloseUp(char, flat, dur, nil, nil, {
		startOffset = { -22, -2.6, 1.2 },
		endOffset = { -18, -2.2, 1.6 },
		focusHeight = 3,
		fovStart = 54,
		fovEnd = 50,
	})
end

-- Another Gunslinger's High Noon: the same standoff shot on their character.
function GunslingerController.PlayStandoff(char: Model, aimDir: Vector3)
	sunsetStandoff(char, aimDir, NOON_CINEMATIC)
end

-- ── Shots ───────────────────────────────────────────────────────────────────
-- A tracer from muzzle to `to`: bright core, brass glow, muzzle flash and
-- gunpowder smoke. Final and Deadeye shots are bigger.
local function drawShot(owner: Player?, from: Vector3, to: Vector3, final: boolean?, deadeye: boolean?)
	local root = vfxRoot(owner)
	local len = (to - from).Magnitude
	if len < 0.2 then return end
	local mid = CFrame.lookAt((from + to) / 2, to)
	local width = if deadeye then 0.34 elseif final then 0.22 else 0.12
	local core = neon(root, { Size = Vector3.new(width, width, len), CFrame = mid, Color = HOT, Transparency = 0.05 })
	local glow = neon(root, { Size = Vector3.new(width * 3, width * 3, len), CFrame = mid, Color = if deadeye then GOLD else BRASS,
		Transparency = if deadeye then 0.35 else 0.6 })
	local fade = TweenInfo.new(if deadeye then 0.35 else 0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(core, fade, { Transparency = 1, Size = Vector3.new(0.02, 0.02, len) }):Play()
	TweenService:Create(glow, fade, { Transparency = 1 }):Play()
	Debris:AddItem(core, 0.4)
	Debris:AddItem(glow, 0.4)

	-- Muzzle flash: a star of light, bigger on the final shot.
	local s = if deadeye then 2 elseif final then 1.7 else 1
	local dir = (to - from).Unit
	local star = neon(root, { Shape = Enum.PartType.Ball, Size = Vector3.one * 0.5 * s, CFrame = CFrame.new(from), Color = HOT })
	TweenService:Create(star, TweenInfo.new(0.08), { Size = Vector3.one * 1.6 * s, Transparency = 1 }):Play()
	Debris:AddItem(star, 0.1)
	local spike = neon(root, { Size = Vector3.new(0.18 * s, 0.18 * s, 1.4 * s), CFrame = CFrame.lookAt(from + dir * 0.7 * s, from + dir * 2), Color = GOLD })
	TweenService:Create(spike, TweenInfo.new(0.07), { Transparency = 1 }):Play()
	Debris:AddItem(spike, 0.1)
	flash(owner, from, GOLD, 3 * s, 10 * s, 0.1)
	gunSmoke(owner, from + dir * 0.4, 0.6 * s)
	if final or deadeye then
		playSound("heavyShot", from, 0.9, if deadeye then 0.85 else 0.95)
	else
		playSound("shot", from, 0.7)
	end
	if final or deadeye then
		burst(owner, from, { Texture = TEX_SPARKLE, Color = ColorSequence.new(HOT, GOLD), LightEmission = 1, Size = seq(0, 0.45, 1, 0),
			Lifetime = NumberRange.new(0.1, 0.25), Speed = NumberRange.new(14, 26) }, 14)
	end
	if deadeye then
		-- Golden sparks along the whole line.
		for i = 1, 6 do
			burst(owner, from:Lerp(to, i / 7), { Texture = TEX_SPARKLE, Color = ColorSequence.new(HOT, GOLD), LightEmission = 1,
				Size = seq(0, 0.35, 1, 0), Lifetime = NumberRange.new(0.2, 0.4), Speed = NumberRange.new(2, 6) }, 4)
		end
	end
end

local function aliveMobs(): { any }
	local out = {}
	local folder = Workspace:FindFirstChild("Mobs")
	if not folder then return out end
	for _, m in ipairs(folder:GetChildren()) do
		local hum = m:FindFirstChildOfClass("Humanoid")
		local root = m:FindFirstChild("HumanoidRootPart") or (m:IsA("Model") and m.PrimaryPart)
		if hum and hum.Health > 0 and root and root:IsA("BasePart") then
			table.insert(out, root)
		end
	end
	return out
end

-- Client guess of where a shot ends (mirrors the server's rules).
local function predictShot(origin: Vector3, dir: Vector3, deadeyeReady: boolean): (Vector3, boolean, Model?)
	local width = BULLET_WIDTH * (tonumber(player:GetAttribute("Stat_size")) or 1)
	local bestAlong, best = math.huge, nil
	for _, root in ipairs(aliveMobs()) do
		local diff = root.Position - origin
		local along = Vector3.new(diff.X, 0, diff.Z):Dot(dir)
		if along >= 0 and along <= BULLET_RANGE then
			local closest = origin + dir * along
			local lateral = Vector3.new(root.Position.X - closest.X, 0, root.Position.Z - closest.Z).Magnitude
			-- Same reach as the server, minus its lag leniency (so we never draw a hit it won't give).
			local size = (root.Parent :: Model):GetExtentsSize()
			local reach = width + math.min(math.max(size.X, size.Z) * 0.5, 8) * 0.6
			if lateral <= reach and along < bestAlong then bestAlong, best = along, root end
		end
	end
	local now = os.clock()
	for _, coin in pairs(coins) do
		if coin.attacker == player and coin.alive and now >= coin.landAt - 0.08 and now <= coin.expires then
			local diff = coin.pos - origin
			local along = Vector3.new(diff.X, 0, diff.Z):Dot(dir)
			if along >= 0 and along <= BULLET_RANGE and along < bestAlong then
				local closest = origin + dir * along
				if Vector3.new(coin.pos.X - closest.X, 0, coin.pos.Z - closest.Z).Magnitude <= COIN_HIT_RADIUS then
					return coin.pos, false, nil
				end
			end
		end
	end
	local model = if best then best.Parent :: Model else nil
	if best and not deadeyeReady then return best.Position, true, model end
	return origin + dir * BULLET_RANGE, best ~= nil, model
end

-- Brief hit-stop: freeze the character's animations for a beat.
local function hitStop(char: Model, seconds: number)
	local hum = char:FindFirstChildOfClass("Humanoid")
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if not animator then return end
	local tracks = animator:GetPlayingAnimationTracks()
	local speeds = {}
	for _, t in ipairs(tracks) do
		speeds[t] = t.Speed
		t:AdjustSpeed(0)
	end
	task.delay(seconds, function()
		for t, sp in pairs(speeds) do
			if t.IsPlaying then t:AdjustSpeed(sp) end
		end
	end)
end

-- Your own click / roll landing shot. Returns true if a shot was fired.
function GunslingerController.Shoot(rollShot: boolean?): boolean
	if player:GetAttribute("InLobby") == true or Workspace:GetAttribute("TomesPaused") == true then return false end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not char or not root or not hum or hum.Health <= 0 then return false end
	local now = os.clock()
	if now < busyUntil and not rollShot then return false end
	if isReloading() or localAmmo <= 0 then
		if not rollShot and now - lastDryFire > 0.3 then
			lastDryFire = now
			playSound("dryFire", nil, 0.5, 1.3)
		end
		return false
	end
	if not rollShot then
		local interval = FIRE_INTERVAL / math.max(tonumber(player:GetAttribute("Stat_basicAttackSpeed")) or 1, 0.1)
		if now - lastShot < interval then return false end
	end
	lastShot = now

	local aim = deps.getAim(root)
	root.CFrame = CFrame.lookAt(root.Position, root.Position + aim)
	holdAim(char, AIM_HOLD)
	localAmmo -= 1
	local final = localAmmo == 0
	local deadeyeReady = (tonumber(player:GetAttribute("GS_Deadeye")) or 0) >= 100
	local origin = root.Position + Vector3.new(0, 1.4, 0)
	local to, hitEnemy, struck = predictShot(origin, aim, deadeyeReady)
	local deadeyeShot = deadeyeReady and hitEnemy
	drawShot(player, muzzleOf(char), if deadeyeShot then origin + aim * BULLET_RANGE else to, final, deadeyeShot)
	if deadeyeShot or final then
		deps.shake(if deadeyeShot then 0.7 else 0.45, 0.16)
		hitStop(char, 0.06)
	else
		deps.shake(0.12, 0.06)
	end

	-- (`target`: the enemy our screen saw the bullet strike, so the server can
	-- allow for it having moved on since: what we see is a moment old)
	Network.GetRemoteEvent(Network.Remotes.PerformAttack):FireServer({ direction = aim, rollShot = rollShot == true, target = struck })
	if final then
		localReloadEnd = now + (tonumber(player:GetAttribute("GS_ReloadTime")) or 1.1) + 0.1
	end
	changed:Fire()
	return true
end

-- ── Skills ──────────────────────────────────────────────────────────────────
function GunslingerController.CanCast(skillIndex: number): boolean
	if os.clock() < busyUntil then return false end
	if skillIndex == 1 then
		return localAmmo > 0 and not isReloading()
	end
	return true
end

local function doRoll(char: Model, root: BasePart, hum: Humanoid)
	local dir = hum.MoveDirection
	dir = Vector3.new(dir.X, 0, dir.Z)
	if dir.Magnitude < 0.1 then dir = deps.getAim(root) end
	dir = dir.Unit
	local now = os.clock()
	busyUntil = now + ROLL_TIME
	local p = poseOf(char)
	p.rollStart, p.rollUntil = now, now + ROLL_TIME
	-- Rolling reloads the cylinder instantly (the server does the same).
	localAmmo = maxAmmo()
	localReloadEnd = 0
	changed:Fire()
	p.aimUntil = 0

	-- Drive the roll with a horizontal-only velocity so gravity still works.
	local att = Instance.new("Attachment")
	att.Parent = root
	local lv = Instance.new("LinearVelocity")
	lv.Attachment0 = att
	lv.RelativeTo = Enum.ActuatorRelativeTo.World
	lv.ForceLimitMode = Enum.ForceLimitMode.PerAxis
	lv.MaxAxesForce = Vector3.new(1e6, 0, 1e6)
	-- Stop short of walls / steps (no clipping into the level), land on the floor.
	local rollStand = SafeMove.StandHeight(root)
	local rollDist = SafeMove.ClampDash(root, dir, ROLL_DISTANCE)
	lv.VectorVelocity = dir * (rollDist / ROLL_TIME)
	lv.Parent = root
	hum.AutoRotate = false
	root.CFrame = CFrame.lookAt(root.Position, root.Position + dir)

	playSound("roll", root.Position, 0.6)
	-- Dust at take-off and a fading afterimage streak.
	burst(player, root.Position - Vector3.new(0, 2.5, 0), { Texture = TEX_SMOKE, Color = ColorSequence.new(Color3.fromRGB(190, 170, 140)),
		Size = seq(0, 1, 1, 3), Transparency = seq(0, 0.5, 1, 1), Lifetime = NumberRange.new(0.4, 0.7), Speed = NumberRange.new(2, 5),
		SpreadAngle = Vector2.new(60, 10) }, 6)
	task.delay(ROLL_TIME, function()
		lv:Destroy()
		att:Destroy()
		if not char.Parent then return end
		char:SetAttribute("IsSkillCasting", false)
		char:SetAttribute("AllowSkillMovement", false)
		root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
		SafeMove.SnapToFloor(root, rollStand)
		-- Land and shoot.
		GunslingerController.Shoot(true)
	end)
end

-- Called by SkillController.UseSkill after the cooldown starts. Returns the
-- target position to send to the server (the coin's landing spot).
function GunslingerController.OnCast(skillIndex: number, char: Model, root: BasePart, aimDir: Vector3, config: any): Vector3?
	local hum = char:FindFirstChildOfClass("Humanoid") :: Humanoid
	if skillIndex == 1 then
		-- Fan the Hammer: the server fires every bullet; keep moving.
		char:SetAttribute("AllowSkillMovement", true)
		char:SetAttribute("IsSkillCasting", false)
		local t = localAmmo * FAN_INTERVAL + 0.1
		busyUntil = os.clock() + t
		holdAim(char, t + 0.5)
		poseOf(char).fanUntil = os.clock() + t
		localAmmo = 0
		localReloadEnd = os.clock() + t + (tonumber(player:GetAttribute("GS_ReloadTime")) or 1.1) + 0.1
		changed:Fire()
	elseif skillIndex == 2 then
		char:SetAttribute("AllowSkillMovement", false)
		doRoll(char, root, hum)
	elseif skillIndex == 3 then
		-- Deadeye Ricochet: the server flips the coin up and auto-shoots it.
		char:SetAttribute("AllowSkillMovement", true)
		task.delay(0.12, function()
			char:SetAttribute("IsSkillCasting", false)
		end)
		local range = config.range or 24
		local cursor = deps.getCursor(root)
		local offset = Vector3.new(cursor.X - root.Position.X, 0, cursor.Z - root.Position.Z)
		local dist = math.clamp(offset.Magnitude, 6, range)
		local dir = if offset.Magnitude > 0.5 then offset.Unit else aimDir
		return root.Position + dir * dist
	elseif skillIndex == 4 then
		-- High Noon: a short close-up, then the volley plays in the iso view.
		char:SetAttribute("AllowSkillMovement", false)
		-- Runs until every enemy in range is down; the server's noonEnd
		-- releases the character (see onNoonEnd).
		busyUntil = math.huge
		sunsetStandoff(char, aimDir, NOON_CINEMATIC)
		task.delay(35, function()
			if busyUntil == math.huge and char.Parent then onNoonEnd({ attacker = player }) end
		end)
	end
	return nil
end

-- ── Server effects (GunslingerFX) ───────────────────────────────────────────
local function charOf(p: Player?): Model?
	return p and p.Character or nil
end

local function onCoin(msg: any)
	local owner = msg.attacker
	local from, to = msg.from :: Vector3, msg.to :: Vector3
	local now = os.clock()
	local coin: LocalCoin = { part = nil, pos = to, landAt = now + msg.flight, expires = now + msg.flight + msg.hang, alive = true, attacker = owner }
	coins[msg.id] = coin
	playSound("coinToss", from, 0.8)

	local root = vfxRoot(owner)
	local body = Instance.new("Part")
	body.Name = "GunslingerCoin"
	body.Shape = Enum.PartType.Cylinder
	body.Size = Vector3.new(0.14, 1.2, 1.2)
	body.Color = if msg.heads then Color3.fromRGB(255, 205, 90) else Color3.fromRGB(226, 214, 190)
	body.Material = Enum.Material.Metal
	body.Reflectance = 0.25
	body.Anchored, body.CanCollide, body.CanTouch, body.CanQuery = true, false, false, false
	body.CFrame = CFrame.new(from)
	body.Parent = root
	local rim = neon(body, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 1.28, 1.28), CFrame = body.CFrame, Color = GOLD, Transparency = 0.35 })
	coin.part = body
	-- The thrower's pose: thumb flick, then the gun tracks the coin up.
	local thrower = charOf(owner)
	if thrower then
		local p = poseOf(thrower)
		p.tossAt, p.coinPart, p.coinPos = now, body, to
		p.coinUntil = now + msg.flight + 0.5
	end
	local light = Instance.new("PointLight")
	light.Color, light.Brightness, light.Range = GOLD, 1.6, 9
	light.Parent = body
	local att = Instance.new("Attachment")
	att.Parent = body
	local glint = Instance.new("ParticleEmitter")
	glint.Texture = TEX_SPARKLE
	glint.Color = ColorSequence.new(HOT, GOLD)
	glint.LightEmission, glint.LightInfluence = 1, 0
	glint.Size = seq(0, 0.3, 1, 0)
	glint.Lifetime = NumberRange.new(0.3, 0.6)
	glint.Speed = NumberRange.new(0.5, 1.5)
	glint.Rate = 10
	glint.Parent = att
	if msg.showFace then
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(70, 20)
		bb.StudsOffsetWorldSpace = Vector3.new(0, 1.3, 0)
		bb.AlwaysOnTop = true
		bb.LightInfluence = 0
		bb.Parent = body
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.Font = Enum.Font.Antique
		t.TextSize = 16
		t.Text = if msg.heads then "HEADS" else "TAILS"
		t.TextColor3 = if msg.heads then GOLD else Color3.fromRGB(230, 226, 240)
		t.TextStrokeTransparency = 0.2
		t.Parent = bb
	end

	-- Arc out, then hang: spin fast and flip, bobbing slightly.
	local throwerChar = charOf(owner)
	local throwerRoot = throwerChar and throwerChar:FindFirstChild("HumanoidRootPart") :: BasePart?
	local rootAtToss = if throwerRoot then throwerRoot.Position else Vector3.zero
	local hangAt = to
	local t0 = os.clock()
	local conn: RBXScriptConnection? = nil
	conn = RunService.RenderStepped:Connect(function()
		if not body.Parent then
			if conn then conn:Disconnect() end
			return
		end
		local t = os.clock() - t0
		local pos
		if t < msg.flight then
			local a = t / msg.flight
			if msg.up then
				-- Flipped straight up: fast off the thumb, slowing to the apex,
				-- carried along with the thrower while it rises.
				local drift = if throwerRoot and throwerRoot.Parent then throwerRoot.Position - rootAtToss else Vector3.zero
				-- Forward at a steady pace, upward fast then slowing: an arc.
				local flat = from:Lerp(to, a)
				local y = from.Y + (to.Y - from.Y) * (1 - (1 - a) * (1 - a))
				pos = Vector3.new(flat.X, y, flat.Z) + drift
				coin.pos = to + drift
				hangAt = coin.pos
			else
				pos = from:Lerp(to, a) + Vector3.new(0, math.sin(a * math.pi) * 4, 0)
			end
		else
			pos = hangAt + Vector3.new(0, math.sin(t * 3) * 0.15, 0)
		end
		local spin = CFrame.Angles(0, t * 9, 0) * CFrame.Angles(t * 14, 0, 0)
		body.CFrame = CFrame.new(pos) * spin * CFrame.Angles(0, 0, math.rad(90))
		rim.CFrame = body.CFrame
	end)
end

local function removeCoin(id: number, pop: boolean)
	local coin = coins[id]
	if not coin then return end
	coin.alive = false
	coins[id] = nil
	local body = coin.part
	if not body then return end
	if pop then
		TweenService:Create(body, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Size = Vector3.new(0.05, 0.3, 0.3), Transparency = 1 }):Play()
		Debris:AddItem(body, 0.4)
	else
		TweenService:Create(body, TweenInfo.new(0.25), { Transparency = 1 }):Play()
		Debris:AddItem(body, 0.3)
	end
end

local function onCoinHit(msg: any)
	local owner = msg.attacker
	local pos = msg.pos :: Vector3
	local root = vfxRoot(owner)
	-- The satisfying "ping": white flash, golden ring, spark spray.
	local core = neon(root, { Shape = Enum.PartType.Ball, Size = Vector3.one * 0.8, CFrame = CFrame.new(pos), Color = HOT })
	TweenService:Create(core, TweenInfo.new(0.18, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = Vector3.one * 4, Transparency = 1 }):Play()
	Debris:AddItem(core, 0.2)
	local ring = neon(root, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.08, 1, 1),
		CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)), Color = GOLD, Transparency = 0.2 })
	TweenService:Create(ring, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = Vector3.new(0.04, 9, 9), Transparency = 1 }):Play()
	Debris:AddItem(ring, 0.32)
	burst(owner, pos, { Texture = TEX_SPARKLE, Color = ColorSequence.new(HOT, GOLD), LightEmission = 1, Size = seq(0, 0.5, 1, 0),
		Lifetime = NumberRange.new(0.2, 0.45), Speed = NumberRange.new(18, 34) }, 26)
	flash(owner, pos, GOLD, 6, 16, 0.25)
	playSound("coinPing", pos, 1, 1.1)
	if owner == player then deps.shake(0.35, 0.12) end
	if msg.survives then
		local c = coins[msg.id]
		if c and c.part then
			burst(owner, pos, { Texture = TEX_SPARKLE, Color = ColorSequence.new(Color3.fromRGB(150, 255, 150)), LightEmission = 1,
				Size = seq(0, 0.6, 1, 0), Lifetime = NumberRange.new(0.3, 0.5), Speed = NumberRange.new(2, 5) }, 10)
		end
	else
		removeCoin(msg.id, true)
	end
end

-- Seeking ricochet projectiles: each streaks from the split point to its
-- target on a gentle curve, tracking the target as it moves.
-- A struck coin's shots: straight, instant tracers like the revolver's own
-- (no curving), one after another from the coin to each target.
local function onSplit(msg: any)
	local owner = msg.attacker
	local from = msg.from :: Vector3
	local root = vfxRoot(owner)
	flash(owner, from, GOLD, 4, 12, 0.12)
	for i, shot in ipairs(msg.shots) do
		task.delay(shot.delay or 0, function()
			local to = shot.to :: Vector3
			local model = shot.model
			if model and model.Parent then
				local r = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
				if r and r:IsA("BasePart") then to = r.Position end
			end
			local len = (to - from).Magnitude
			if len < 0.2 then return end
			local mid = CFrame.lookAt((from + to) / 2, to)
			local core = neon(root, { Size = Vector3.new(0.12, 0.12, len), CFrame = mid, Color = HOT, Transparency = 0.05 })
			local glow = neon(root, { Size = Vector3.new(0.36, 0.36, len), CFrame = mid, Color = BRASS, Transparency = 0.6 })
			local fade = TweenInfo.new(0.14, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
			TweenService:Create(core, fade, { Transparency = 1, Size = Vector3.new(0.02, 0.02, len) }):Play()
			TweenService:Create(glow, fade, { Transparency = 1 }):Play()
			Debris:AddItem(core, 0.2)
			Debris:AddItem(glow, 0.2)
			if i <= 3 then playSound("ricochet", from, 0.45, 1 + i * 0.08) end
			burst(owner, to, { Texture = TEX_SPARKLE, Color = ColorSequence.new(HOT, BRASS), LightEmission = 1, Size = seq(0, 0.35, 1, 0),
				Lifetime = NumberRange.new(0.1, 0.25), Speed = NumberRange.new(10, 20) }, 8)
		end)
	end
end

local function onBlast(msg: any)
	local owner = msg.attacker
	local pos = msg.pos :: Vector3
	local radius = msg.radius or 7
	local ball = neon(vfxRoot(owner), { Shape = Enum.PartType.Ball, Size = Vector3.one, CFrame = CFrame.new(pos), Color = Color3.fromRGB(255, 150, 60), Transparency = 0.1 })
	TweenService:Create(ball, TweenInfo.new(0.3, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = Vector3.one * radius * 2, Transparency = 1 }):Play()
	Debris:AddItem(ball, 0.32)
	gunSmoke(owner, pos, 1.6)
	flash(owner, pos, Color3.fromRGB(255, 160, 70), 5, radius * 2.5, 0.3)
	playSound("blast", pos, 0.6, 1.1)
end

-- Marked Currency: a spinning gold coin over the enemy's head.
local function onMark(msg: any)
	local model = msg.model
	if not model or not model.Parent then return end
	local head = model:FindFirstChild("Head") or model:FindFirstChild("HumanoidRootPart")
	if not head then return end
	local old = head:FindFirstChild("GS_Mark")
	if old then old:Destroy() end
	local bb = Instance.new("BillboardGui")
	bb.Name = "GS_Mark"
	bb.Size = UDim2.fromOffset(26, 26)
	bb.StudsOffsetWorldSpace = Vector3.new(0, 2.6, 0)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Parent = head
	local disc = Instance.new("Frame")
	disc.AnchorPoint = Vector2.new(0.5, 0.5)
	disc.Position = UDim2.fromScale(0.5, 0.5)
	disc.Size = UDim2.fromScale(1, 1)
	disc.BackgroundColor3 = GOLD
	disc.Parent = bb
	Instance.new("UICorner", disc).CornerRadius = UDim.new(1, 0)
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(120, 80, 20)
	stroke.Thickness = 2
	stroke.Parent = disc
	-- The spin: squash horizontally back and forth.
	local t0 = os.clock()
	local conn: RBXScriptConnection? = nil
	conn = RunService.RenderStepped:Connect(function()
		if not bb.Parent or os.clock() - t0 > (msg.duration or 6) or (model:GetAttribute("GS_MarkUntil") or 0) < os.clock() - 0.1 then
			if conn then conn:Disconnect() end
			bb:Destroy()
			return
		end
		disc.Size = UDim2.fromScale(math.abs(math.cos((os.clock() - t0) * 5)), 1)
	end)
end

local function popText(owner: Player?, pos: Vector3, text: string, color: Color3)
	local a = Instance.new("Part")
	a.Anchored, a.CanCollide, a.CanQuery, a.CanTouch = true, false, false, false
	a.Transparency = 1
	a.Size = Vector3.new(0.1, 0.1, 0.1)
	a.CFrame = CFrame.new(pos + Vector3.new(0, 3, 0))
	a.Parent = vfxRoot(owner)
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(80, 30)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Parent = a
	local t = Instance.new("TextLabel")
	t.Size = UDim2.fromScale(1, 1)
	t.BackgroundTransparency = 1
	t.Font = Enum.Font.Arcade
	t.TextSize = 22
	t.Text = text
	t.TextColor3 = color
	t.TextStrokeTransparency = 0
	t.Parent = bb
	TweenService:Create(bb, TweenInfo.new(0.7), { StudsOffsetWorldSpace = Vector3.new(0, 2.5, 0) }):Play()
	TweenService:Create(t, TweenInfo.new(0.7), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(a, 0.75)
end

-- Reload: the gun drops, a ghost cylinder spins beside it and six brass
-- casings tumble out.
local function onReload(msg: any)
	local owner = msg.attacker
	local char = charOf(owner)
	if not char then return end
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end
	local p = poseOf(char)
	p.aimUntil = 0
	local duration = msg.duration or 1.1
	playSound("shellsOut", root.Position, 0.6)
	task.delay(math.max(0.1, duration - 0.15), function()
		if root.Parent then playSound("loaded", root.Position, 0.7) end
	end)
	local holder = vfxRoot(owner)
	local chambers = {}
	for i = 1, 6 do
		chambers[i] = neon(holder, { Shape = Enum.PartType.Ball, Size = Vector3.one * 0.26, Color = BRASS, Transparency = 0.6 })
	end
	local t0 = os.clock()
	local conn: RBXScriptConnection? = nil
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		if t > duration or not root.Parent then
			if conn then conn:Disconnect() end
			for _, c in ipairs(chambers) do c:Destroy() end
			return
		end
		local center = root.Position + root.CFrame.RightVector * 1.2 + root.CFrame.LookVector * 0.8 + Vector3.new(0, 0.6, 0)
		local fill = t / duration
		for i, c in ipairs(chambers) do
			local a = (i / 6) * math.pi * 2 + t * 10
			local offset = (root.CFrame.RightVector * math.cos(a) + Vector3.yAxis * math.sin(a)) * 0.5
			c.CFrame = CFrame.new(center + offset)
			c.Color = if fill > i / 6 then GOLD else BRASS
			c.Transparency = if fill > i / 6 then 0.05 else 0.6
		end
	end)
	-- Spent casings.
	for i = 1, 6 do
		task.delay(i * 0.03, function()
			local start = root.Position + root.CFrame.RightVector * 1 + Vector3.new(0, 1, 0)
			local casing = neon(holder, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.22, 0.1, 0.1), Color = BRASS, Material = Enum.Material.Metal,
				CFrame = CFrame.new(start) })
			local fling = root.CFrame.RightVector * (2 + math.random() * 2) + root.CFrame.LookVector * (math.random() - 0.5) * 2
			local groundY = root.Position.Y - 2.9
			local c0 = os.clock()
			local cc: RBXScriptConnection? = nil
			cc = RunService.RenderStepped:Connect(function()
				local t = os.clock() - c0
				local pos = start + fling * t + Vector3.new(0, 5 * t - 18 * t * t, 0)
				if pos.Y < groundY then pos = Vector3.new(pos.X, groundY, pos.Z) end
				casing.CFrame = CFrame.new(pos) * CFrame.Angles(t * 20, t * 13, 0)
				if t > 0.8 then
					if cc then cc:Disconnect() end
					casing:Destroy()
				end
			end)
		end)
	end
end

local function onRoll(msg: any)
	local owner = msg.attacker
	local char = charOf(owner)
	if not char then return end
	local p = poseOf(char)
	p.rollStart, p.rollUntil = os.clock(), os.clock() + ROLL_TIME
	p.aimUntil = 0
	playSound("roll", msg.from, 0.6)
	burst(owner, msg.from - Vector3.new(0, 2.5, 0), { Texture = TEX_SMOKE, Color = ColorSequence.new(Color3.fromRGB(190, 170, 140)),
		Size = seq(0, 1, 1, 3), Transparency = seq(0, 0.5, 1, 1), Lifetime = NumberRange.new(0.4, 0.7), Speed = NumberRange.new(2, 5) }, 6)
end

-- ── High Noon ───────────────────────────────────────────────────────────────
local function crosshair(model: Model, big: boolean): BillboardGui?
	local root = model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart
	if not root then return nil end
	local bb = Instance.new("BillboardGui")
	bb.Name = "HighNoonMark"
	local size = if big then 90 else 60
	bb.Size = UDim2.fromOffset(size, size)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Adornee = root
	bb.Parent = root
	local color = if big then CRIMSON else GOLD
	local ring = Instance.new("Frame")
	ring.AnchorPoint = Vector2.new(0.5, 0.5)
	ring.Position = UDim2.fromScale(0.5, 0.5)
	ring.Size = UDim2.fromScale(0.7, 0.7)
	ring.BackgroundTransparency = 1
	ring.Parent = bb
	Instance.new("UICorner", ring).CornerRadius = UDim.new(1, 0)
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = if big then 4 else 3
	stroke.Parent = ring
	for _, t in ipairs({ { 0.5, 0, 0.08, 0.28 }, { 0.5, 1, 0.08, 0.28 }, { 0, 0.5, 0.28, 0.08 }, { 1, 0.5, 0.28, 0.08 } }) do
		local tick = Instance.new("Frame")
		tick.AnchorPoint = Vector2.new(0.5, 0.5)
		tick.Position = UDim2.fromScale(t[1], t[2])
		tick.Size = UDim2.fromScale(t[3], t[4])
		tick.BackgroundColor3 = color
		tick.BorderSizePixel = 0
		tick.Parent = bb
	end
	local scale = Instance.new("UIScale")
	scale.Scale = 2.2
	scale.Parent = bb
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	-- Slow rotation while locked on.
	local t0 = os.clock()
	local conn: RBXScriptConnection? = nil
	conn = RunService.RenderStepped:Connect(function()
		if not bb.Parent then
			if conn then conn:Disconnect() end
			return
		end
		ring.Rotation = (os.clock() - t0) * 90
	end)
	return bb
end

-- High Noon runs until the server says it's over (noonEnd): one entry per
-- Gunslinger with the running effects so noonShot / noonEnd can reach them.
type Noon = { shots: number, stop: () -> (), marks: { [Model]: BillboardGui } }
local noons: { [Player]: Noon } = {}

local function onHighNoon(msg: any)
	local owner = msg.attacker :: Player
	local char = charOf(owner)
	if not char then return end
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end
	if noons[owner] then noons[owner].stop() end
	local windup = msg.windup or 0.7
	local isMine = owner == player
	local myRoot = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local grade: ColorCorrectionEffect? = nil
	if isMine or (myRoot and (myRoot.Position - root.Position).Magnitude < 70) then
		grade = Instance.new("ColorCorrectionEffect")
		local g = grade :: ColorCorrectionEffect
		g.Name = "HighNoonGrade"
		g.Parent = Lighting
		TweenService:Create(g, TweenInfo.new(0.25), { TintColor = Color3.fromRGB(255, 226, 176), Saturation = -0.4, Contrast = 0.18 }):Play()
	end
	playSound("highNoon", root.Position, 0.8, 1, 3)

	-- A golden revolver cylinder of six chambers circling the Gunslinger;
	-- a chamber goes dark per shot and they all light up again on reload.
	local holder = vfxRoot(owner)
	local chambers = {}
	for i = 1, 6 do
		chambers[i] = neon(holder, { Shape = Enum.PartType.Ball, Size = Vector3.one * 0.55, Color = GOLD, Transparency = 0.15 })
	end
	local ring = neon(holder, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.06, 6, 6), Color = GOLD, Transparency = 0.55 })
	local noon: Noon = { shots = 0, stop = function() end, marks = {} }
	-- Lock a crosshair onto everyone in range, one after another, during the standoff.
	local list = msg.marks or {}
	for i, model in ipairs(list) do
		task.delay(windup * 0.8 * (i / math.max(#list, 1)), function()
			if noons[owner] == noon and model.Parent and not noon.marks[model] then
				noon.marks[model] = crosshair(model, false)
			end
		end)
	end
	local t0 = os.clock()
	local conn = RunService.RenderStepped:Connect(function()
		if not root.Parent then noon.stop() return end
		local t = os.clock() - t0
		local center = root.Position - Vector3.new(0, 2.6, 0)
		ring.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
		-- Marks come off as their targets die.
		for model, bb in pairs(noon.marks) do
			local hum = model:FindFirstChildOfClass("Humanoid")
			if not model.Parent or not hum or hum.Health <= 0 then
				noon.marks[model] = nil
				if bb then
					TweenService:Create(bb, TweenInfo.new(0.2), { Size = UDim2.fromOffset(10, 10) }):Play()
					Debris:AddItem(bb, 0.22)
				end
			end
		end
		local spent = noon.shots % 6
		for i, c in ipairs(chambers) do
			local a = (i / 6) * math.pi * 2 + noon.shots * (math.pi / 3) + t * 0.6
			c.CFrame = CFrame.new(center + Vector3.new(math.cos(a) * 3, 0.15, math.sin(a) * 3))
			c.Transparency = if i <= spent then 0.75 else 0.15
		end
	end)
	-- Gun stays low through the standoff, snaps up when the volley starts.
	task.delay(windup, function()
		if noons[owner] == noon and char.Parent then holdAim(char, 30) end
	end)
	local stopped = false
	noon.stop = function()
		if stopped then return end
		stopped = true
		if noons[owner] == noon then noons[owner] = nil end
		conn:Disconnect()
		for _, c in ipairs(chambers) do c:Destroy() end
		ring:Destroy()
		for _, bb in pairs(noon.marks) do if bb then bb:Destroy() end end
		noon.marks = {}
		poseOf(char).aimUntil = os.clock() + AIM_HOLD
		if grade then
			TweenService:Create(grade, TweenInfo.new(0.4), { TintColor = Color3.new(1, 1, 1), Saturation = 0, Contrast = 0 }):Play()
			Debris:AddItem(grade, 0.45)
		end
	end
	noons[owner] = noon
	-- Safety net if noonEnd never arrives.
	task.delay(30, noon.stop)
end

local function onNoonShot(msg: any)
	local owner = msg.attacker :: Player
	local char = charOf(owner)
	local noon = noons[owner]
	local model = msg.model :: Model?
	local r = model and (model:FindFirstChild("HumanoidRootPart") or model.PrimaryPart) :: BasePart?
	local to = if r then r.Position else msg.to :: Vector3
	local isMine = owner == player
	if noon then noon.shots += 1 end
	if not char then return end
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end
	local aim = Vector3.new(to.X - root.Position.X, 0, to.Z - root.Position.Z)
	local dir = if aim.Magnitude > 0.1 then aim.Unit else root.CFrame.LookVector
	root.CFrame = CFrame.lookAt(root.Position, root.Position + dir)
	local from = muzzleOf(char)
	if model and noon then
		-- Newcomers get marked on their first shot; each hit makes the mark kick.
		local bb = noon.marks[model]
		if not bb then
			bb = crosshair(model, false)
			if bb then noon.marks[model] = bb end
		end
		local scale = bb and bb:FindFirstChildOfClass("UIScale")
		if scale then
			scale.Scale = if msg.final then 1.8 else 1.35
			TweenService:Create(scale, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		end
	end
	if not msg.final then
		drawShot(owner, from, to, false, false)
		if isMine then deps.shake(0.25, 0.08) end
		return
	end
	-- The execution round: shock ring, pillar of light, heavy smoke.
	drawShot(owner, from, from + dir * BULLET_RANGE, true, true)
	local holder = vfxRoot(owner)
	local shock = neon(holder, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 2, 2),
		CFrame = CFrame.new(to - Vector3.new(0, 2.5, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = CRIMSON, Transparency = 0.1 })
	TweenService:Create(shock, TweenInfo.new(0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = Vector3.new(0.05, 18, 18), Transparency = 1 }):Play()
	Debris:AddItem(shock, 0.5)
	local pillar = neon(holder, { Size = Vector3.new(1.2, 20, 1.2), CFrame = CFrame.new(to + Vector3.new(0, 8, 0)), Color = HOT, Transparency = 0.1 })
	TweenService:Create(pillar, TweenInfo.new(0.35), { Size = Vector3.new(0.1, 26, 0.1), Transparency = 1 }):Play()
	Debris:AddItem(pillar, 0.4)
	gunSmoke(owner, from, 2)
	flash(owner, to, HOT, 10, 30, 0.4)
	playSound("blast", to, 0.8, 0.8)
	if isMine then
		deps.shake(0.9, 0.25)
		deps.fovPunch(8, 0.35)
	end
end

onNoonEnd = function(msg: any)
	local owner = msg.attacker :: Player
	local noon = noons[owner]
	if noon then noon.stop() end
	if owner == player then
		local char = player.Character
		busyUntil = 0
		localAmmo = maxAmmo()
		localReloadEnd = 0
		changed:Fire()
		if char then
			char:SetAttribute("IsSkillCasting", false)
			char:SetAttribute("AllowSkillMovement", false)
		end
	end
end

local function onShot(msg: any)
	local char = charOf(msg.attacker)
	local upward = (msg.to - msg.from).Unit.Y > 0.6
	if char then
		if upward then
			local p = poseOf(char)
			p.recoilAt = os.clock()
			p.coinPos = msg.to
			p.coinUntil = math.max(p.coinUntil, os.clock() + 0.4)
		else
			holdAim(char, AIM_HOLD)
		end
	end
	local from = if char then muzzleOf(char) else msg.from
	if char and upward then
		-- Arm is raised at the coin: use the revolver's real muzzle.
		local tool = char:FindFirstChild("Revolver")
		local m = tool and tool:FindFirstChild("Muzzle", true)
		from = if m and m:IsA("Attachment") and (m.WorldPosition - msg.from).Magnitude < 4 then m.WorldPosition else msg.from
	end
	if upward then gunSmoke(msg.attacker, from, 1) end
	drawShot(msg.attacker, from, msg.to, msg.final, msg.deadeye)
	if msg.attacker == player then
		-- Fan the Hammer shots come from the server for the shooter too.
		deps.shake(if msg.final then 0.4 else 0.15, 0.06)
	end
end

local HANDLERS: { [string]: (any) -> () } = {
	shot = onShot,
	coin = onCoin,
	coinHit = onCoinHit,
	coinGone = function(msg) removeCoin(msg.id, false) end,
	split = onSplit,
	blast = onBlast,
	mark = onMark,
	refund = function(msg)
		popText(msg.attacker, msg.pos, "+1", GOLD)
		playSound("refund", msg.pos, 0.6)
	end,
	reload = onReload,
	roll = onRoll,
	highNoon = onHighNoon,
	noonShot = onNoonShot,
	noonEnd = onNoonEnd,
}

-- ── Deadeye glow on your revolver ───────────────────────────────────────────
local function updateRunes()
	local char = player.Character
	local tool = char and char:FindFirstChild("Revolver")
	if not tool then return end
	local ready = (tonumber(player:GetAttribute("GS_Deadeye")) or 0) >= 100
	for _, name in ipairs({ "Runes", "RuneRib" }) do
		local p = tool:FindFirstChild(name)
		if p and p:IsA("BasePart") then
			p.Color = if ready then Color3.fromRGB(255, 250, 220) else Color3.fromRGB(255, 196, 88)
			p.Transparency = if ready then 0 else 0.1
		end
	end
	local muzzle = tool:FindFirstChild("Muzzle", true)
	if muzzle then
		local glow = muzzle:FindFirstChild("DeadeyeGlow") :: ParticleEmitter?
		if ready and not glow then
			local pe = Instance.new("ParticleEmitter")
			pe.Name = "DeadeyeGlow"
			pe.Texture = TEX_SPARKLE
			pe.Color = ColorSequence.new(HOT, GOLD)
			pe.LightEmission, pe.LightInfluence = 1, 0
			pe.Size = seq(0, 0.35, 1, 0)
			pe.Lifetime = NumberRange.new(0.2, 0.4)
			pe.Speed = NumberRange.new(0.5, 1.5)
			pe.Rate = 18
			pe.Parent = muzzle
		elseif not ready and glow then
			glow:Destroy()
		end
	end
end

function GunslingerController.Init(d: Deps)
	deps = d
	RunService.Stepped:Connect(applyPoses)
	RunService.RenderStepped:Connect(faceCursor)
	Network.GetRemoteEvent(Network.Remotes.GunslingerFX).OnClientEvent:Connect(function(msg: any)
		if typeof(msg) ~= "table" then return end
		local handler = HANDLERS[msg.kind]
		if handler then
			local ok, err = pcall(handler, msg)
			if not ok then warn("[GunslingerController]", msg.kind, err) end
		end
	end)
	for _, name in ipairs({ "GS_Ammo", "GS_MaxAmmo", "GS_ReloadEnd" }) do
		player:GetAttributeChangedSignal(name):Connect(function() reconcile() end)
	end
	local wasReady = false
	player:GetAttributeChangedSignal("GS_Deadeye"):Connect(function()
		local ready = (tonumber(player:GetAttribute("GS_Deadeye")) or 0) >= 100
		if ready and not wasReady then playSound("deadeyeReady", nil, 0.7) end
		wasReady = ready
		updateRunes()
		changed:Fire()
	end)
	player:GetAttributeChangedSignal("SelectedClass"):Connect(function()
		reconcile(true)
	end)
	player.CharacterAdded:Connect(function()
		busyUntil = 0
		localReloadEnd = 0
		task.delay(0.5, function() reconcile(true) end)
	end)
	-- Catch up with the server now and then (e.g. a shot the server refused).
	task.spawn(function()
		while true do
			task.wait(0.25)
			if isGunslinger() and os.clock() - lastShot > 0.35 then reconcile() end
		end
	end)
	reconcile(true)
end

return GunslingerController
