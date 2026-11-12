--!strict
--[[
	BigHitFX.luau
	What a big hit feels like, for the one who landed it. The server tags each
	DamageDealt with `big` (SkillManager.dealDamage: the hit's share of the
	target's max health, a boss's counted 6x): 1 = big, 2 = huge.

	  • hit stop: your animations (and the target's) frozen for a few frames
	  • a camera shake, and a lens punch on a huge one
	  • a shockwave ring on the floor and a spray of sparks where it landed,
	    a deep thud on a huge one
	(the damage number itself is drawn bigger by SkillController)

	Every piece is budgeted (CLAUDE.md: a stacked build lands hundreds of
	hits): hit stop at most every HITSTOP_GAP seconds, the shake and the
	effects through FxBudget.

	  BigHitFX.OnDamage(payload)   from the DamageDealt remote
--]]

local Players = game:GetService("Players")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local FxBudget = require(script.Parent:WaitForChild("FxBudget"))
local ClassFX = require(script.Parent:WaitForChild("ClassFX"))
local IsometricCamera = require(script.Parent:WaitForChild("IsometricCamera")) :: any

local player = Players.LocalPlayer

local BigHitFX = {}

local HITSTOP = { 0.05, 0.09 }      -- seconds frozen (big, huge)
local HITSTOP_GAP = 0.22            -- never closer together than this
local SHAKE = { { 0.3, 0.14 }, { 0.6, 0.24 } } -- intensity, seconds
local RING = { 7, 12 }              -- the shockwave's radius
local GOLD = Color3.fromRGB(255, 214, 110)
local HOT = Color3.fromRGB(255, 140, 70)
local TEX_SPARK = "rbxasset://textures/particles/sparkles_main.dds"

-- Every playing track on `model` slowed to a crawl for `seconds`, then back
-- to the speed it had.
local function freeze(model: Model?, seconds: number)
	local hum = model and model:FindFirstChildOfClass("Humanoid")
	local animator = hum and hum:FindFirstChildOfClass("Animator")
	if not animator then
		local ac = model and model:FindFirstChildOfClass("AnimationController")
		animator = ac and ac:FindFirstChildOfClass("Animator")
	end
	if not animator then return end
	local held: { [AnimationTrack]: number } = {}
	for _, t in ipairs(animator:GetPlayingAnimationTracks()) do
		held[t] = t.Speed
		t:AdjustSpeed(0.02)
	end
	task.delay(seconds, function()
		for t, speed in pairs(held) do
			if t.IsPlaying then t:AdjustSpeed(speed) end
		end
	end)
end

local lastStop = 0

local function ring(pos: Vector3, radius: number, color: Color3)
	local p = Instance.new("Part")
	p.Name = "BigHitRing"
	p.Shape = Enum.PartType.Cylinder
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material = Enum.Material.Neon
	p.Color = color
	p.Transparency = 0.15
	p.Size = Vector3.new(0.15, 1, 1)
	p.CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90))
	p.Parent = Workspace.Terrain
	local info = TweenInfo.new(0.28, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
	TweenService:Create(p, info, { Size = Vector3.new(0.05, radius * 2, radius * 2), Transparency = 1 }):Play()
	Debris:AddItem(p, 0.32)
end

local function sparks(pos: Vector3, count: number, color: Color3)
	local a = Instance.new("Attachment")
	a.WorldPosition = pos
	a.Parent = Workspace.Terrain
	local e = Instance.new("ParticleEmitter")
	e.Texture = TEX_SPARK
	e.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Size = NumberSequence.new(0.5, 0)
	e.Lifetime = NumberRange.new(0.2, 0.4)
	e.Speed = NumberRange.new(18, 34)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Drag = 6
	e.Rate = 0
	e.Parent = a
	e:Emit(count)
	Debris:AddItem(a, 0.6)
end

function BigHitFX.OnDamage(payload: any)
	if typeof(payload) ~= "table" then return end
	local tier = tonumber(payload.big)
	if not tier or tier < 1 then return end
	tier = math.clamp(math.floor(tier), 1, 2)
	local pos = payload.position
	if typeof(pos) ~= "Vector3" then return end

	-- hit stop (yours and the target's), rarely
	local now = os.clock()
	if now - lastStop >= HITSTOP_GAP then
		lastStop = now
		local secs = HITSTOP[tier]
		freeze(player.Character, secs)
		local target = payload.model
		if typeof(target) == "Instance" and target:IsA("Model") then freeze(target, secs) end
	end

	-- the camera
	if FxBudget.Allow("bigHitShake", if tier == 2 then 4 else 6) then
		local s = SHAKE[tier]
		pcall(IsometricCamera.Shake, s[1], s[2])
		if tier == 2 then pcall(IsometricCamera.Punch, 3, 0.18) end
	end

	-- the impact where it landed (on the floor under the number)
	if FxBudget.Allow("bigHitFx", if tier == 2 then 5 else 8) then
		local at = pos - Vector3.new(0, 2.5, 0)
		local color = if payload.crit == true then GOLD else HOT
		ring(at - Vector3.new(0, 1.8, 0), RING[tier], color)
		sparks(at, if tier == 2 then 26 else 14, color)
		if tier == 2 then ClassFX.Sound("boom", at, 0.45, 1.25) end
	end
end

return BigHitFX
