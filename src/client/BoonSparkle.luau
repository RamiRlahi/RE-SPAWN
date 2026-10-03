--!strict
-- BoonSparkle.luau
-- Hades-style "boon acquired" sparkle: whenever a player picks a tome (their
-- Tome_<id> attribute goes up), a small, quick iridescent burst pops around
-- their character. Every client watches every player, so teammates see it.
--   • a small central flash cycling through the rainbow
--   • a handful of tiny rainbow sparks radiating out
--   • a few brighter four-point stars that pop and fade
-- About 0.5 s end to end; Neon + particles only (no lights).

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local BoonSparkle = {}

local LIFE = 0.5
local RAINBOW = ColorSequence.new({
	ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 120, 150)),
	ColorSequenceKeypoint.new(0.2, Color3.fromRGB(255, 210, 110)),
	ColorSequenceKeypoint.new(0.4, Color3.fromRGB(150, 255, 150)),
	ColorSequenceKeypoint.new(0.6, Color3.fromRGB(120, 220, 255)),
	ColorSequenceKeypoint.new(0.8, Color3.fromRGB(190, 150, 255)),
	ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 140, 220)),
})

local function folder(): Folder
	local f = Workspace:FindFirstChild("ClassFX")
	if f and f:IsA("Folder") then return f end
	local nf = Instance.new("Folder")
	nf.Name = "ClassFX"
	nf.Parent = Workspace
	return nf
end

function BoonSparkle.Play(char: Model)
	local torso = (char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso") or char:FindFirstChild("HumanoidRootPart")) :: BasePart?
	if not torso then return end
	local parent = folder()

	-- Central flash, hue cycling while it swells and fades.
	local flash = Instance.new("Part")
	flash.Shape = Enum.PartType.Ball
	flash.Anchored, flash.CanCollide, flash.CanQuery, flash.CanTouch, flash.CastShadow = true, false, false, false, false
	flash.Material = Enum.Material.Neon
	flash.Size = Vector3.one * 0.6
	flash.Transparency = 0.1
	flash.CFrame = torso.CFrame
	flash.Parent = parent
	TweenService:Create(flash, TweenInfo.new(LIFE * 0.7, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
		{ Size = Vector3.one * 4.2, Transparency = 1 }):Play()
	local t0 = os.clock()
	local hue0 = math.random()
	local conn: RBXScriptConnection? = nil
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		if t > LIFE or not flash.Parent then
			if conn then conn:Disconnect() end
			return
		end
		flash.Color = Color3.fromHSV((hue0 + t * 2.4) % 1, 0.55, 1)
		if torso.Parent then flash.CFrame = torso.CFrame end
	end)
	Debris:AddItem(flash, LIFE + 0.05)

	-- Tiny rainbow sparks radiating out.
	local att = Instance.new("Attachment")
	att.Parent = torso
	local sparks = Instance.new("ParticleEmitter")
	sparks.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sparks.Color = RAINBOW
	sparks.LightEmission = 1
	sparks.LightInfluence = 0
	sparks.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 0) })
	sparks.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	sparks.Lifetime = NumberRange.new(0.3, LIFE)
	sparks.Speed = NumberRange.new(8, 14)
	sparks.Drag = 6
	sparks.SpreadAngle = Vector2.new(180, 180)
	sparks.Rate = 0
	sparks.Parent = att
	sparks:Emit(16)
	Debris:AddItem(att, LIFE + 0.3)

	-- A few bright four-point stars around the body.
	for i = 1, 3 do
		local a = (i / 3) * math.pi * 2 + math.random() * 0.8
		local bb = Instance.new("BillboardGui")
		bb.Adornee = torso
		bb.Size = UDim2.fromOffset(40, 40)
		bb.StudsOffset = Vector3.new(math.cos(a) * 1.6, 0.4 + math.sin(a) * 1.3, 0)
		bb.AlwaysOnTop = true
		bb.LightInfluence = 0
		bb.Parent = parent
		local star = Instance.new("TextLabel")
		star.BackgroundTransparency = 1
		star.Size = UDim2.fromScale(1, 1)
		star.Font = Enum.Font.GothamBold
		star.Text = "✦"
		star.TextScaled = true
		star.TextColor3 = Color3.fromHSV((hue0 + i / 3) % 1, 0.35, 1)
		star.Parent = bb
		local scale = Instance.new("UIScale")
		scale.Scale = 0.2
		scale.Parent = star
		local delay = (i - 1) * 0.06
		task.delay(delay, function()
			TweenService:Create(scale, TweenInfo.new(0.16, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			TweenService:Create(star, TweenInfo.new(0.22, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 0.16),
				{ TextTransparency = 1, Rotation = 45 }):Play()
		end)
		Debris:AddItem(bb, LIFE + delay + 0.1)
	end
end

-- Sparkle whenever any player's tome count goes up.
local function watch(plr: Player)
	local counts: { [string]: number } = {}
	for name, v in pairs(plr:GetAttributes()) do
		if string.sub(name, 1, 5) == "Tome_" and typeof(v) == "number" then counts[name] = v end
	end
	plr.AttributeChanged:Connect(function(name)
		if string.sub(name, 1, 5) ~= "Tome_" then return end
		local v = plr:GetAttribute(name)
		local before = counts[name] or 0
		counts[name] = if typeof(v) == "number" then v else nil
		if typeof(v) == "number" and v > before and plr.Character then
			BoonSparkle.Play(plr.Character)
		end
	end)
end

function BoonSparkle.Init()
	for _, p in ipairs(Players:GetPlayers()) do watch(p) end
	Players.PlayerAdded:Connect(watch)
end

return BoonSparkle
