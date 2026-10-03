--[[
	SummonCinematic.luau
	"The Divine Summoning" — the pull cinematic, scaled by the best rarity.

	  1 SILENCE   fade near-black, game audio ducked, camera creeps in, heartbeat
	  2 TOME      a tome rises and opens itself; pages flip; runes; motes fall UP
	  3 CIRCLE    a vast rotating rune circle; camera pulls back to reveal its size
	  4 SKY       BOOM — a beam from above strikes the tome; white-out
	  5 REVEAL    silhouette → reveal, staged by rarity:
	              Common    small flash → silhouette → reveal
	              Rare      several beams → silhouette spins → reveal
	              Epic      the sky cracks → explosion → silhouette descends
	              Legendary everything stops; one golden mote drifts past; BOOM —
	                        a celestial sigil; the figure walks forward, camera
	                        circles, colours appear piece by piece; name card
	              Mythic    the summon "fails" — circle dies, tome shuts, "…";
	                        the tome snaps open, an eye opens in the sky, reality
	                        warps, camera rockets up to reveal a sky-wide formation,
	                        the figure descends; "???" … then the real name

	SummonCinematic.Play(reward, onDone) — `reward` is a GachaRewards entry.
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")
local Lighting = game:GetService("Lighting")
local SoundService = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local GachaConfig = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("GachaConfig"))
local RewardPreview = require(script.Parent:WaitForChild("RewardPreview"))
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local TEX_SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"
local HOLY = Color3.fromRGB(255, 244, 215)
local GOLD = Color3.fromRGB(255, 205, 95)

local SummonCinematic = {}

-- ─── Small helpers ──────────────────────────────────────────────────────────
local function part(parent: Instance, props: { [string]: any }): BasePart
	local p = Instance.new(props.ClassName or "Part") :: BasePart
	props.ClassName = nil
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

local function emitter(parent: Instance, props: { [string]: any }): ParticleEmitter
	local pe = Instance.new("ParticleEmitter")
	pe.LightInfluence = 0
	pe.LightEmission = 1
	pe.Texture = TEX_SPARKLE
	for k, v in pairs(props) do (pe :: any)[k] = v end
	pe.Parent = parent
	return pe
end

local function tween(obj: Instance, t: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local tw = TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

-- Ring of segments (flat, around `center`) the render loop can re-lay.
local function ringParts(parent: Instance, n: number, color: Color3, transparency: number): { BasePart }
	local out = {}
	for i = 1, n do out[i] = part(parent, { Color = color, Transparency = transparency }) end
	return out
end
local function layRing(parts: { BasePart }, cf: CFrame, radius: number, thick: number, dashed: boolean?)
	local segLen = 2 * math.pi * radius / #parts * (if dashed then 0.55 else 1.08)
	for i, p in ipairs(parts) do
		local a = (i / #parts) * math.pi * 2
		p.Size = Vector3.new(thick, thick * 0.4, math.max(segLen, 0.05))
		p.CFrame = cf * CFrame.new(math.cos(a) * radius, 0, math.sin(a) * radius) * CFrame.Angles(0, -a, 0)
	end
end

-- ─── The stage: isolated, in the church, in front of the angel statue ────────
-- 1. a part named "SummonStage" (its front face points away from the statue),
-- 2. else anything named like an angel/statue — the stage sits in front of it,
-- 3. else near the church spawn.
local function findStage(): CFrame?
	local stage = Workspace:FindFirstChild("SummonStage", true)
	if stage and stage:IsA("BasePart") then
		return CFrame.lookAt(stage.Position, stage.Position + Vector3.new(stage.CFrame.LookVector.X, 0, stage.CFrame.LookVector.Z))
	end
	for _, d in ipairs(Workspace:GetDescendants()) do
		if (d:IsA("Model") or d:IsA("BasePart")) and d.Parent ~= Workspace.Terrain then
			local n = string.lower(d.Name)
			if string.find(n, "angel") or string.find(n, "statue") then
				local cf, size
				if d:IsA("Model") then cf, size = d:GetBoundingBox() else cf, size = d.CFrame, d.Size end
				local look = Vector3.new(cf.LookVector.X, 0, cf.LookVector.Z)
				if look.Magnitude < 0.01 then look = Vector3.new(0, 0, -1) end
				local base = Vector3.new(cf.Position.X, cf.Position.Y - size.Y * 0.5, cf.Position.Z)
				local pos = base + look.Unit * (math.max(size.X, size.Z) * 0.5 + 8)
				return CFrame.lookAt(pos, pos + look.Unit)
			end
		end
	end
	local spawn = Workspace:FindFirstChild("ChurchSpawn", true)
	if spawn and spawn:IsA("BasePart") then
		local look = Vector3.new(spawn.CFrame.LookVector.X, 0, spawn.CFrame.LookVector.Z)
		local pos = spawn.Position + look.Unit * 10
		return CFrame.lookAt(pos, pos + look.Unit)
	end
	return nil
end

-- Hide the real character on this client during the summon.
local function setCharacterHidden(char: Model, hidden: boolean)
	for _, d in ipairs(char:GetDescendants()) do
		if d:IsA("BasePart") or d:IsA("Decal") then
			(d :: any).LocalTransparencyModifier = if hidden then 1 else 0
		end
	end
end

-- Silhouette a preview model; returns a function that reveals it (staggered).
local function silhouette(model: Model, accent: Color3): (number) -> ()
	local parts: { { any } } = {}
	local hiddenBits: { { any } } = {}
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 1 then
			table.insert(parts, { d, d.Color, d.Material, if d:IsA("MeshPart") then d.TextureID else nil })
			d.Color = Color3.new(0, 0, 0)
			d.Material = Enum.Material.SmoothPlastic
			if d:IsA("MeshPart") then d.TextureID = "" end
		elseif d:IsA("SurfaceAppearance") then
			table.insert(hiddenBits, { d, "Parent", d.Parent })
			d.Parent = nil
		elseif d:IsA("Decal") or d:IsA("Texture") then
			table.insert(hiddenBits, { d, "Transparency", d.Transparency })
			d.Transparency = 1
		elseif d:IsA("Shirt") then
			table.insert(hiddenBits, { d, "ShirtTemplate", d.ShirtTemplate })
			d.ShirtTemplate = ""
		elseif d:IsA("Pants") then
			table.insert(hiddenBits, { d, "PantsTemplate", d.PantsTemplate })
			d.PantsTemplate = ""
		elseif d:IsA("BillboardGui") or d:IsA("ParticleEmitter") or d:IsA("Light") then
			table.insert(hiddenBits, { d, "Enabled", d.Enabled })
			d.Enabled = false
		end
	end
	return function(stagger: number)
		for _, bit in ipairs(hiddenBits) do (bit[1] :: any)[bit[2]] = bit[3] end
		for i, entry in ipairs(parts) do
			task.delay(stagger * (i - 1) / math.max(#parts, 1), function()
				local p = entry[1] :: BasePart
				if not p.Parent then return end
				p.Material = entry[3]
				if entry[4] then (p :: MeshPart).TextureID = entry[4] end
				TweenService:Create(p, TweenInfo.new(0.35), { Color = entry[2] }):Play()
				if i % 3 == 1 then
					local att = Instance.new("Attachment")
					att.Parent = p
					local pe = Instance.new("ParticleEmitter")
					pe.Texture = TEX_SPARKLE
					pe.Color = ColorSequence.new(Color3.new(1, 1, 1), accent)
					pe.LightEmission, pe.LightInfluence = 1, 0
					pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0) })
					pe.Lifetime = NumberRange.new(0.3, 0.6)
					pe.Speed = NumberRange.new(3, 7)
					pe.SpreadAngle = Vector2.new(180, 180)
					pe.Rate = 0
					pe.Parent = att
					pe:Emit(6)
					Debris:AddItem(att, 1)
				end
			end)
		end
	end
end

-- ─── Cinematic ──────────────────────────────────────────────────────────────
function SummonCinematic.Play(reward: any, onDone: (() -> ())?)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not char or not root then
		if onDone then onDone() end
		return
	end
	local rarity: string = reward.rarity
	local rarityColor: Color3 = GachaConfig.Rarities[rarity].color
	local accent: Color3 = reward.accent or rarityColor
	local fast = rarity == "Common" or rarity == "Rare"
	local S = if fast then 0.35 elseif rarity == "Epic" then 0.7 else 1 -- scale for the shared intro

	local world = Instance.new("Folder")
	world.Name = "SummonCinematic"
	world.Parent = Workspace.Terrain
	-- Isolated stage in the church; no summoner rig, just the reveal.
	local stageCF = findStage() or CFrame.lookAt(root.Position - Vector3.new(0, 3, 0), root.Position - Vector3.new(0, 3, 0) + root.CFrame.LookVector)
	local base = stageCF.Position + Vector3.new(0, 3, 0)
	local fwd = Vector3.new(stageCF.LookVector.X, 0, stageCF.LookVector.Z).Unit
	setCharacterHidden(char, true)
	local right = fwd:Cross(Vector3.yAxis).Unit
	local ground = base - Vector3.new(0, 3, 0)
	do
		local rp = RaycastParams.new()
		rp.FilterType = Enum.RaycastFilterType.Exclude
		rp.FilterDescendantsInstances = { char, world }
		local hit = Workspace:Raycast(base, Vector3.new(0, -12, 0), rp)
		if hit then ground = hit.Position end
	end
	local tomePos = base + fwd * 3.2 + Vector3.new(0, 1.2, 0)

	-- Overlay: black fade, white flash, vignette pulse, text.
	local gui = Instance.new("ScreenGui")
	gui.Name = "SummonCinematicGui"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 200
	gui.ResetOnSpawn = false
	gui.Parent = player:WaitForChild("PlayerGui")
	local black = Instance.new("Frame")
	black.Size = UDim2.fromScale(1, 1)
	black.BackgroundColor3 = Color3.new(0, 0, 0)
	black.BackgroundTransparency = 1
	black.Parent = gui
	local white = black:Clone()
	white.BackgroundColor3 = Color3.new(1, 1, 1)
	white.Parent = gui
	local function label(size: number, y: number): TextLabel
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.AnchorPoint = Vector2.new(0.5, 0.5)
		t.Position = UDim2.fromScale(0.5, y)
		t.Size = UDim2.new(1, 0, 0, size + 10)
		t.Font = Enum.Font.Antique
		t.TextSize = size
		t.TextColor3 = Color3.new(1, 1, 1)
		t.TextStrokeTransparency = 0.3
		t.TextTransparency = 1
		t.TextStrokeColor3 = Color3.new(0, 0, 0)
		t.Parent = gui
		return t
	end
	local nameLabel = label(54, 0.78)
	local rarityLabel = label(26, 0.86)
	local centerText = label(60, 0.5)

	-- Silence: duck every playing sound (restored at the end).
	local ducked: { [Sound]: number } = {}
	for _, container in ipairs({ Workspace, SoundService, player:WaitForChild("PlayerGui") }) do
		for _, s in ipairs(container:GetDescendants()) do
			if s:IsA("Sound") and s.Volume > 0 then
				ducked[s] = s.Volume
				tween(s, 0.6, { Volume = 0 })
			end
		end
	end

	-- Camera control (the lobby camera is paused by the caller).
	camera.CameraType = Enum.CameraType.Scriptable
	local camPos, camLook, camFov = camera.CFrame.Position, base + Vector3.new(0, 1, 0), camera.FieldOfView
	local shakeAmp = 0
	local camConn = RunService.RenderStepped:Connect(function(dt)
		local jitter = Vector3.new((math.random() - 0.5), (math.random() - 0.5), 0) * shakeAmp
		camera.CFrame = CFrame.lookAt(camPos, camLook) * CFrame.new(jitter)
		camera.FieldOfView = camFov
		shakeAmp *= math.exp(-6 * dt)
	end)
	local function moveCam(pos: Vector3, look: Vector3, fov: number, t: number, style: Enum.EasingStyle?)
		local fromPos, fromLook, fromFov = camPos, camLook, camFov
		local t0 = os.clock()
		task.spawn(function()
			while os.clock() - t0 < t do
				local a = math.clamp((os.clock() - t0) / t, 0, 1)
				local e = if style == Enum.EasingStyle.Linear then a else a * a * (3 - 2 * a)
				camPos = fromPos:Lerp(pos, e)
				camLook = fromLook:Lerp(look, e)
				camFov = fromFov + (fov - fromFov) * e
				RunService.RenderStepped:Wait()
			end
			camPos, camLook, camFov = pos, look, fov
		end)
	end
	local function flashWhite(hold: number)
		white.BackgroundTransparency = 0
		task.delay(hold, function() tween(white, 0.35, { BackgroundTransparency = 1 }) end)
	end
	local function heartbeat()
		tween(black, 0.08, { BackgroundTransparency = 0.72 })
		shakeAmp = 0.15
		task.delay(0.12, function() tween(black, 0.35, { BackgroundTransparency = 0.82 }) end)
	end

	-- ── 1. SILENCE ── (hard cut to the stage under black)
	black.BackgroundTransparency = 0
	camPos, camLook, camFov = base + fwd * 11 + Vector3.new(0, 2.4, 0), base + Vector3.new(0, 1.2, 0), 55
	task.wait(0.15)
	tween(black, 0.6 * S, { BackgroundTransparency = 0.82 })
	moveCam(base + fwd * 7 + Vector3.new(0, 1.8, 0), base + Vector3.new(0, 1.2, 0), 55, 1.4 * S)
	heartbeat()
	task.wait(0.5 * S)
	heartbeat()
	task.wait(0.5 * S)

	-- ── 2. THE TOME ──
	local tome = Instance.new("Model")
	tome.Name = "Tome"
	tome.Parent = world
	local spine = part(tome, { Size = Vector3.new(0.3, 1.6, 1.2), Color = Color3.fromRGB(70, 40, 25), Material = Enum.Material.Leather, CFrame = CFrame.new(tomePos - Vector3.new(0, 3, 0)) })
	local covers = {}
	for side = -1, 1, 2 do
		covers[side] = part(tome, { Size = Vector3.new(1.1, 1.6, 0.1), Color = Color3.fromRGB(90, 50, 30), Material = Enum.Material.Leather })
	end
	local pages = {}
	for i = 1, 7 do
		pages[i] = part(tome, { Size = Vector3.new(1, 1.5, 0.02), Color = Color3.fromRGB(245, 232, 200), Material = Enum.Material.SmoothPlastic })
	end
	local tomeGlow = part(tome, { Shape = Enum.PartType.Ball, Size = Vector3.new(0.6, 0.6, 0.6), Color = HOLY, Transparency = 0.2 })
	local tomeLight = Instance.new("PointLight")
	tomeLight.Color, tomeLight.Brightness, tomeLight.Range = HOLY, 0, 16
	tomeLight.Parent = tomeGlow
	local upMotes = emitter(tomeGlow, {
		Color = ColorSequence.new(HOLY, GOLD), Size = seq(0, 0.25, 1, 0), Lifetime = NumberRange.new(1.5, 2.5),
		Speed = NumberRange.new(0.5, 1.5), SpreadAngle = Vector2.new(180, 180), Acceleration = Vector3.new(0, 2.5, 0), Rate = 0,
	})
	local runeGui: { BillboardGui } = {}
	local RUNES = { "ᚠ", "ᚢ", "ᚦ", "ᚨ", "ᚱ", "ᚲ", "ᛃ", "ᛉ", "ᛊ", "ᛏ" }
	for i = 1, 8 do
		local anchor = part(tome, { Size = Vector3.new(0.1, 0.1, 0.1), Transparency = 1 })
		local bb = Instance.new("BillboardGui")
		bb.Size = UDim2.fromOffset(40, 40)
		bb.LightInfluence = 0
		bb.AlwaysOnTop = true
		bb.Adornee = anchor
		bb.Parent = anchor
		local t = Instance.new("TextLabel")
		t.Size = UDim2.fromScale(1, 1)
		t.BackgroundTransparency = 1
		t.Font = Enum.Font.GothamBold
		t.TextScaled = true
		t.TextColor3 = GOLD
		t.TextTransparency = 1
		t.Text = RUNES[(i - 1) % #RUNES + 1]
		t.Parent = bb
		runeGui[i] = bb
	end
	local tomeOpen = 0      -- 0 closed .. 1 open
	local flipSpeed = 0     -- page flips per second
	local tomeRise = 0      -- 0 below .. 1 in place
	local t0 = os.clock()
	local tomeConn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		local c = tomePos - Vector3.new(0, 3 * (1 - tomeRise), 0) + Vector3.new(0, math.sin(t * 2) * 0.08, 0)
		local face = CFrame.lookAt(c, c + (-fwd)) -- faces the character
		spine.CFrame = face
		local ang = math.rad(88 * tomeOpen)
		covers[-1].CFrame = face * CFrame.Angles(0, ang, 0) * CFrame.new(-0.55, 0, 0)
		covers[1].CFrame = face * CFrame.Angles(0, -ang, 0) * CFrame.new(0.55, 0, 0)
		for i, pg in ipairs(pages) do
			local phase = ((t * flipSpeed) + i / #pages) % 1
			local pa = if flipSpeed > 0 then -ang + phase * 2 * ang else ang * (i / #pages * 2 - 1) * 0.9
			pg.CFrame = face * CFrame.Angles(0, pa, 0) * CFrame.new(0.5 * (if pa < 0 then -1 else 1), 0, 0.02)
			pg.Transparency = 1 - tomeOpen
		end
		tomeGlow.CFrame = face * CFrame.new(0, 0, 0.3)
		for i, bb in ipairs(runeGui) do
			local a = (i / #runeGui) * math.pi * 2 + t * 1.3
			local anchor = bb.Adornee :: BasePart
			anchor.CFrame = CFrame.new(c + Vector3.new(math.cos(a) * 1.4, math.sin(a * 2) * 0.3 + 0.2, math.sin(a) * 1.4))
		end
	end)
	tween(tomeLight, 0.8 * S, { Brightness = 3 })
	local riseT0 = os.clock()
	while os.clock() - riseT0 < 0.9 * S do
		tomeRise = math.clamp((os.clock() - riseT0) / (0.9 * S), 0, 1)
		RunService.RenderStepped:Wait()
	end
	tomeRise = 1
	moveCam(base + fwd * 5 - right * 1.5 + Vector3.new(0, 1.6, 0), tomePos, 45, 1 * S)
	local openT0 = os.clock()
	while os.clock() - openT0 < 0.6 * S do
		tomeOpen = math.clamp((os.clock() - openT0) / (0.6 * S), 0, 1)
		RunService.RenderStepped:Wait()
	end
	tomeOpen = 1
	flipSpeed = 9
	upMotes.Rate = 40
	for _, bb in ipairs(runeGui) do tween(bb:FindFirstChildOfClass("TextLabel") :: TextLabel, 0.4, { TextTransparency = 0 }) end
	task.wait(0.6 * S)

	-- ── 3. THE CIRCLE ──
	local circleCF = CFrame.new(ground + Vector3.new(0, 0.12, 0))
	local rings = {
		{ parts = ringParts(world, 64, accent, 0.15), r = 16, th = 0.5, spin = 0.25, dashed = false },
		{ parts = ringParts(world, 48, HOLY, 0.3), r = 12, th = 0.3, spin = -0.4, dashed = true },
		{ parts = ringParts(world, 40, accent, 0.25), r = 8.5, th = 0.35, spin = 0.6, dashed = false },
		{ parts = ringParts(world, 28, HOLY, 0.35), r = 5, th = 0.2, spin = -0.9, dashed = true },
	}
	local crosses = {}
	for i = 1, 8 do
		local v = part(world, { Size = Vector3.new(0.2, 1.4, 0.2), Color = GOLD })
		local h = part(world, { Size = Vector3.new(0.8, 0.2, 0.2), Color = GOLD })
		crosses[i] = { v = v, h = h, a = (i / 8) * math.pi * 2 }
	end
	local spiralAtt = part(world, { Size = Vector3.new(0.1, 0.1, 0.1), Transparency = 1, CFrame = circleCF })
	local spiral = emitter(spiralAtt, {
		Color = ColorSequence.new(accent, HOLY), Size = seq(0, 0.35, 1, 0), Lifetime = NumberRange.new(1, 1.4),
		Speed = NumberRange.new(4, 7), SpreadAngle = Vector2.new(180, 5), Acceleration = (tomePos - ground) * 1.2, Rate = 0,
	})
	local circleGrow = 0
	local circleAlpha = 1
	local circleConn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		for _, ring in ipairs(rings) do
			layRing(ring.parts, circleCF * CFrame.Angles(0, t * ring.spin, 0), ring.r * circleGrow, ring.th, ring.dashed)
			for _, p in ipairs(ring.parts) do p.LocalTransparencyModifier = 1 - circleAlpha end
		end
		for _, c in ipairs(crosses) do
			local a = c.a + t * 0.3
			local p = ground + Vector3.new(math.cos(a) * 14 * circleGrow, 2.2 + math.sin(t * 1.5 + c.a) * 0.4, math.sin(a) * 14 * circleGrow)
			c.v.CFrame = CFrame.lookAt(p, p + fwd)
			c.h.CFrame = c.v.CFrame * CFrame.new(0, 0.3, 0)
			c.v.LocalTransparencyModifier, c.h.LocalTransparencyModifier = 1 - circleAlpha, 1 - circleAlpha
		end
	end)
	local growT0 = os.clock()
	spiral.Rate = 60
	moveCam(base - fwd * 18 + right * 10 + Vector3.new(0, 16, 0), ground, 60, 1.4 * S) -- pull back: how vast it is
	while os.clock() - growT0 < 0.9 * S do
		circleGrow = 1 - (1 - math.clamp((os.clock() - growT0) / (0.9 * S), 0, 1)) ^ 3
		RunService.RenderStepped:Wait()
	end
	circleGrow = 1
	task.wait(0.6 * S)

	-- ── Mythic: the summon "fails" first ──
	if rarity == "Mythic" then
		tween(black, 0.8, { BackgroundTransparency = 0 })
		local fadeT0 = os.clock()
		while os.clock() - fadeT0 < 0.8 do
			circleAlpha = 1 - (os.clock() - fadeT0) / 0.8
			tomeOpen = 1 - (os.clock() - fadeT0) / 0.8
			RunService.RenderStepped:Wait()
		end
		circleAlpha, tomeOpen, flipSpeed = 0, 0, 0
		spiral.Rate, upMotes.Rate = 0, 0
		centerText.Text = "…"
		tween(centerText, 0.6, { TextTransparency = 0 })
		task.wait(2)
		tween(centerText, 0.3, { TextTransparency = 1 })
		task.wait(0.4)
		-- The tome snaps back open.
		moveCam(base + fwd * 5 + Vector3.new(0, 1.6, 0), tomePos, 50, 0.01)
		tween(black, 0.15, { BackgroundTransparency = 0.6 })
		tomeOpen, flipSpeed, circleAlpha = 1, 14, 1
		shakeAmp = 0.8
		task.wait(0.5)
	end

	-- ── 4. THE SKY OPENS ──
	local beamTop = tomePos + Vector3.new(0, 140, 0)
	local beam = part(world, {
		Shape = Enum.PartType.Cylinder, Size = Vector3.new(140, 0.2, 0.2),
		CFrame = CFrame.new((beamTop + tomePos) / 2) * CFrame.Angles(0, 0, math.rad(90)), Color = HOLY, Transparency = 0.05,
	})
	local beamGlow = part(world, {
		Shape = Enum.PartType.Cylinder, Size = Vector3.new(140, 0.2, 0.2), CFrame = beam.CFrame, Color = accent, Transparency = 0.7,
	})
	tween(beam, 0.25, { Size = Vector3.new(140, 2.4, 2.4) }, Enum.EasingStyle.Back)
	tween(beamGlow, 0.3, { Size = Vector3.new(140, 7, 7) }, Enum.EasingStyle.Back)
	flashWhite(if fast then 0.05 else 0.14)
	shakeAmp = if fast then 0.4 else 1
	tween(black, 0.3, { BackgroundTransparency = 1 })
	moveCam(base + fwd * 11 + Vector3.new(0, 2.5, 0), tomePos + Vector3.new(0, 1.5, 0), 55, 0.5)
	task.wait(0.4)

	-- ── 5. REVEAL ──
	-- The figure: how the reward looks on the character it belongs to
	-- (RewardPreview), silhouetted until the reveal.
	local revealAt = tomePos + fwd * 2.5 + Vector3.new(0, 0.6, 0)
	local figure, cleanupFigure = RewardPreview.Build(reward)
	local reveal = silhouette(figure, accent)
	figure.Parent = world
	local function placeFigure(pos: Vector3, yaw: number)
		figure:PivotTo(CFrame.new(pos) * CFrame.lookAt(Vector3.zero, fwd).Rotation * CFrame.Angles(0, yaw, 0))
	end
	local function revealColors(stagger: number)
		reveal(stagger)
	end
	local function nameCard(hidden: boolean?)
		nameLabel.Text = if hidden then "???" else string.upper(reward.name)
		nameLabel.TextColor3 = if hidden then Color3.new(1, 1, 1) else accent
		rarityLabel.Text = if hidden then "" else string.upper(rarity)
		rarityLabel.TextColor3 = rarityColor
		tween(nameLabel, 0.5, { TextTransparency = 0 })
		tween(rarityLabel, 0.5, { TextTransparency = 0 })
	end

	if rarity == "Common" then
		placeFigure(revealAt, 0)
		shakeAmp = 0.3
		task.wait(0.35)
		revealColors(0.2)
		nameCard()
		task.wait(1)
	elseif rarity == "Rare" then
		for k = -1, 1, 2 do
			local b = part(world, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(90, 1.2, 1.2), Color = rarityColor, Transparency = 0.3,
				CFrame = CFrame.new(revealAt + right * k * 3 + Vector3.new(0, 45, 0)) * CFrame.Angles(0, 0, math.rad(90 + k * 8)) })
			tween(b, 0.6, { Transparency = 1 }, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
		end
		placeFigure(revealAt, 0)
		task.wait(0.8)
		flashWhite(0.04)
		revealColors(0.25)
		nameCard()
		task.wait(1.2)
	elseif rarity == "Epic" then
		-- The sky cracks.
		local crackRoot = beamTop - Vector3.new(0, 110, 0)
		for i = 1, 7 do
			local p = crackRoot
			local dir = Vector3.new(math.cos(i), 0, math.sin(i))
			for _ = 1, 5 do
				local nxt = p + (dir * 6 + Vector3.new((math.random() - 0.5) * 4, (math.random() - 0.3) * 4, (math.random() - 0.5) * 4))
				local len = (nxt - p).Magnitude
				part(world, { Size = Vector3.new(0.35, 0.35, len), CFrame = CFrame.lookAt((p + nxt) / 2, nxt), Color = rarityColor })
				p = nxt
			end
		end
		shakeAmp = 0.8
		task.wait(0.5)
		-- Huge explosion.
		local boom = part(world, { Shape = Enum.PartType.Ball, Size = Vector3.one * 2, CFrame = CFrame.new(revealAt + Vector3.new(0, 4, 0)), Color = rarityColor, Transparency = 0.1 })
		tween(boom, 0.7, { Size = Vector3.one * 34, Transparency = 1 }, Enum.EasingStyle.Quart)
		flashWhite(0.08)
		shakeAmp = 1.3
		-- Silhouette descends.
		local descT0 = os.clock()
		moveCam(revealAt + fwd * 8 + Vector3.new(0, 1.5, 0), revealAt + Vector3.new(0, 1.2, 0), 50, 2.2)
		while os.clock() - descT0 < 2.2 do
			local a = (os.clock() - descT0) / 2.2
			placeFigure(revealAt + Vector3.new(0, 14 * (1 - a) ^ 2, 0), 0)
			RunService.RenderStepped:Wait()
		end
		placeFigure(revealAt, 0)
		revealColors(0.5)
		nameCard()
		task.wait(1.6)
	else -- Legendary / Mythic
		if rarity == "Legendary" then
			-- EVERYTHING STOPS.
			tween(black, 0.2, { BackgroundTransparency = 0 })
			flipSpeed, spiral.Rate, upMotes.Rate = 0, 0, 0
			task.wait(0.7)
			-- One tiny golden particle drifts past the camera.
			local mote = part(world, { Shape = Enum.PartType.Ball, Size = Vector3.one * 0.08, Color = GOLD })
			local ml = Instance.new("PointLight")
			ml.Color, ml.Brightness, ml.Range = GOLD, 2, 3
			ml.Parent = mote
			local camCF = CFrame.lookAt(camPos, camLook)
			tween(black, 0.4, { BackgroundTransparency = 0.25 })
			local moteT0 = os.clock()
			while os.clock() - moteT0 < 1.6 do
				local a = (os.clock() - moteT0) / 1.6
				mote.CFrame = camCF * CFrame.new(-1.6 + a * 3.2, -0.3 + math.sin(a * math.pi) * 0.5, -3)
				RunService.RenderStepped:Wait()
			end
			mote:Destroy()
			tween(black, 0.1, { BackgroundTransparency = 0 })
			task.wait(0.4)
		else
			-- Mythic: an eye opens in the sky; reality warps; the true formation.
			local eyeCenter = ground + Vector3.new(0, 120, 0) - fwd * 40
			local eyeCF = CFrame.lookAt(eyeCenter, base)
			for side = -1, 1, 2 do
				for i = 0, 11 do
					local a1, a2 = i / 12 * math.pi, (i + 1) / 12 * math.pi
					local p1 = eyeCF * Vector3.new(math.cos(a1) * 30, side * math.sin(a1) * 12, 0)
					local p2 = eyeCF * Vector3.new(math.cos(a2) * 30, side * math.sin(a2) * 12, 0)
					part(world, { Size = Vector3.new(1.2, 1.2, (p2 - p1).Magnitude), CFrame = CFrame.lookAt((p1 + p2) / 2, p2), Color = rarityColor })
				end
			end
			part(world, { Shape = Enum.PartType.Ball, Size = Vector3.one * 14, CFrame = eyeCF, Color = Color3.fromRGB(255, 230, 240) })
			part(world, { Shape = Enum.PartType.Ball, Size = Vector3.one * 6, CFrame = eyeCF * CFrame.new(0, 0, 3), Color = Color3.new(0, 0, 0), Material = Enum.Material.SmoothPlastic })
			local warp = Instance.new("ColorCorrectionEffect")
			warp.Parent = Lighting
			local warpT0 = os.clock()
			task.spawn(function()
				while warp.Parent and os.clock() - warpT0 < 3 do
					local t = os.clock() - warpT0
					warp.Saturation = math.sin(t * 17) * 0.6
					warp.TintColor = Color3.fromHSV((t * 0.7) % 1, 0.25, 1)
					camFov = 60 + math.sin(t * 9) * 12
					RunService.RenderStepped:Wait()
				end
				warp:Destroy()
			end)
			-- The circle was one small part of a sky-wide formation.
			for k = 1, 5 do
				local rr = ringParts(world, 90, if k % 2 == 0 then HOLY else rarityColor, 0.2)
				layRing(rr, CFrame.new(ground + Vector3.new(0, 0.2 + k * 0.1, 0)), 30 + k * 26, 1.2 + k * 0.4, k % 2 == 0)
			end
			moveCam(ground + Vector3.new(0, 220, 0) - fwd * 30, ground, 70, 1.6, Enum.EasingStyle.Linear)
			task.wait(2.2)
			moveCam(revealAt + fwd * 12 + Vector3.new(0, 3, 0), revealAt + Vector3.new(0, 6, 0), 55, 1.2)
			task.wait(0.6)
		end

		-- BOOM: the celestial sigil behind the figure.
		tween(black, 0.15, { BackgroundTransparency = 1 })
		flashWhite(0.2)
		shakeAmp = 1.6
		local sigilCF = CFrame.lookAt(revealAt - fwd * 4 + Vector3.new(0, 5, 0), revealAt - fwd * 4 + Vector3.new(0, 5, 0) + fwd)
		local spokes = {}
		for i = 1, 24 do
			spokes[i] = part(world, { Size = Vector3.new(0.3, if i % 2 == 0 then 6 else 10, 0.3), Color = if i % 2 == 0 then HOLY else accent, Transparency = 0.1 })
		end
		local sigilRings = { ringParts(world, 56, accent, 0.1), ringParts(world, 40, HOLY, 0.3) }
		local sigilT0 = os.clock()
		local sigilConn = RunService.RenderStepped:Connect(function()
			local t = os.clock() - sigilT0
			local grow = 1 - (1 - math.clamp(t / 0.6, 0, 1)) ^ 3
			for i, s in ipairs(spokes) do
				local a = (i / #spokes) * math.pi * 2 + t * 0.3
				s.CFrame = sigilCF * CFrame.Angles(0, 0, a) * CFrame.new(0, (5 + s.Size.Y * 0.5) * grow, 0)
			end
			layRing(sigilRings[1], sigilCF * CFrame.Angles(math.rad(90), 0, 0) * CFrame.Angles(0, t * 0.4, 0), 11 * grow, 0.5)
			layRing(sigilRings[2], sigilCF * CFrame.Angles(math.rad(90), 0, 0) * CFrame.Angles(0, -t * 0.6, 0), 7.5 * grow, 0.3, true)
		end)
		-- The figure walks (or descends) forward through the light; camera holds in front.
		local startPos = if rarity == "Mythic" then revealAt + Vector3.new(0, 26, 0) else revealAt - fwd * 6
		local walkT0 = os.clock()
		local WALK = if rarity == "Mythic" then 3.4 else 3
		task.spawn(function()
			while os.clock() - walkT0 < WALK do
				local a = (os.clock() - walkT0) / WALK
				-- Fixed front view (no orbit), easing in slightly.
				camPos = revealAt + fwd * (11 - a) + Vector3.new(0, 2.5 - a, 0)
				camLook = revealAt + Vector3.new(0, 1.3, 0)
				camFov = 48
				RunService.RenderStepped:Wait()
			end
		end)
		while os.clock() - walkT0 < WALK do
			local a = (os.clock() - walkT0) / WALK
			local e = 1 - (1 - a) ^ 2
			placeFigure(startPos:Lerp(revealAt, e), 0)
			RunService.RenderStepped:Wait()
		end
		placeFigure(revealAt, 0)
		-- Weapon / armour / colours appear piece by piece.
		revealColors(1.4)
		task.wait(1.6)
		if rarity == "Mythic" then
			nameCard(true) -- "???"
			task.wait(2.5)
			tween(nameLabel, 0.3, { TextTransparency = 1 })
			task.wait(0.35)
			flashWhite(0.1)
		end
		nameCard()
		task.wait(2.2)
		sigilConn:Disconnect()
	end

	-- ── Tear down ──
	tween(black, 0.4, { BackgroundTransparency = 0 })
	task.wait(0.45)
	camConn:Disconnect()
	tomeConn:Disconnect()
	circleConn:Disconnect()
	cleanupFigure()
	world:Destroy()
	setCharacterHidden(char, false)
	for s, vol in pairs(ducked) do
		if s.Parent then tween(s, 0.8, { Volume = vol }) end
	end
	tween(black, 0.4, { BackgroundTransparency = 1 })
	tween(nameLabel, 0.3, { TextTransparency = 1 })
	tween(rarityLabel, 0.3, { TextTransparency = 1 })
	Debris:AddItem(gui, 0.5)
	if onDone then onDone() end
end

-- ─── Showcase: a reward on its character, at the stage (from the results) ────
function SummonCinematic.Showcase(reward: any, onDone: (() -> ())?)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not char or not root then
		if onDone then onDone() end
		return
	end
	local stageCF = findStage() or CFrame.lookAt(root.Position - Vector3.new(0, 3, 0), root.Position - Vector3.new(0, 3, 0) + root.CFrame.LookVector)
	local base = stageCF.Position + Vector3.new(0, 3, 0)
	local fwd = Vector3.new(stageCF.LookVector.X, 0, stageCF.LookVector.Z).Unit
	setCharacterHidden(char, true)
	local world = Instance.new("Folder")
	world.Name = "SummonShowcase"
	world.Parent = Workspace.Terrain
	local figure, cleanupFigure = RewardPreview.Build(reward)
	figure.Parent = world
	figure:PivotTo(CFrame.lookAt(base, base + fwd))
	local rarityColor = GachaConfig.Rarities[reward.rarity].color
	local accent = reward.accent or rarityColor
	-- Soft light on the figure.
	local lamp = part(world, { Size = Vector3.new(0.2, 0.2, 0.2), Transparency = 1, CFrame = CFrame.new(base + fwd * 4 + Vector3.new(0, 4, 0)) })
	local l = Instance.new("PointLight")
	l.Color, l.Brightness, l.Range = Color3.fromRGB(255, 240, 220), 2.5, 16
	l.Parent = lamp

	local gui = Instance.new("ScreenGui")
	gui.Name = "SummonShowcaseGui"
	gui.IgnoreGuiInset = true
	gui.DisplayOrder = 200
	gui.Parent = player:WaitForChild("PlayerGui")
	local function label(str: string, size: number, y: number, color: Color3, font: Enum.Font)
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.AnchorPoint = Vector2.new(0.5, 0.5)
		t.Position = UDim2.fromScale(0.5, y)
		t.Size = UDim2.new(1, 0, 0, size + 10)
		t.Font = font
		t.TextSize = size
		t.TextColor3 = color
		t.TextStrokeTransparency = 0.3
		t.Text = str
		t.Parent = gui
	end
	label(string.upper(reward.name), 44, 0.8, accent, Enum.Font.Antique)
	label(string.upper(reward.rarity), 22, 0.87, rarityColor, Enum.Font.GothamBold)
	label(reward.description or "", 16, 0.92, Color3.fromRGB(220, 220, 230), Enum.Font.GothamMedium)
	label("Click to continue", 14, 0.97, Color3.fromRGB(150, 150, 160), Enum.Font.Gotham)

	camera.CameraType = Enum.CameraType.Scriptable
	local t0 = os.clock()
	local done = false
	local conn = RunService.RenderStepped:Connect(function()
		local orbit = fwd * 8.5 -- fixed front view, like the class-select screen
		camera.CFrame = CFrame.lookAt(base + orbit + Vector3.new(0, 1.6, 0), base + Vector3.new(0, 0.9, 0))
		camera.FieldOfView = 50
	end)
	local function finish()
		if done then return end
		done = true
		conn:Disconnect()
		cleanupFigure()
		world:Destroy()
		gui:Destroy()
		setCharacterHidden(char, false)
		if onDone then onDone() end
	end
	local input
	input = UserInputService.InputBegan:Connect(function(io)
		if os.clock() - t0 < 0.4 then return end
		if io.UserInputType == Enum.UserInputType.MouseButton1 or io.UserInputType == Enum.UserInputType.Touch
			or io.KeyCode == Enum.KeyCode.Space or io.KeyCode == Enum.KeyCode.Return then
			input:Disconnect()
			finish()
		end
	end)
end

return SummonCinematic
