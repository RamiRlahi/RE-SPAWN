--[[
	RoomFX.luau
	Client-side motion and feedback for special rooms (see server SpecialRooms):

	  • Float     — parts with attribute Float bob and slowly spin (wares, moonstone)
	  • Wheel     — Wheel of Fate spin from the model's Spin* attributes, blinking rim
	  • Water     — ripples across the Moonwell
	  • RoomEvent — reward pop-ups, coin bursts, light bursts, heal sparkles,
	                jackpot celebration, coin toss
	  • Gold HUD  — animated gold counter above the health bar
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Network = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Network"))

local player = Players.LocalPlayer
local camera = Workspace.CurrentCamera

local GOLD = Color3.fromRGB(255, 205, 80)
local TEX_SPARKLE = "rbxasset://textures/particles/sparkles_main.dds"

local RoomFX = {}

-- ─── Tracked objects ────────────────────────────────────────────────────────
local floaters: { [BasePart]: { base: CFrame, phase: number } } = {}
local wheels: { [Model]: { rotors: { [BasePart]: CFrame }, lastTick: number } } = {}
local waters: { [BasePart]: number } = {}

local function track(inst: Instance)
	if inst:IsA("BasePart") then
		if inst:GetAttribute("Float") == true and not floaters[inst] then
			floaters[inst] = { base = inst.CFrame, phase = math.random() * 6.28 }
		end
		if inst:GetAttribute("RoomFX") == "Water" then
			waters[inst] = 0
		end
	elseif inst:IsA("Model") and inst:GetAttribute("RoomFX") == "Wheel" and not wheels[inst] then
		wheels[inst] = { rotors = {}, lastTick = 0 }
	end
end

-- Rotor parts may stream in after the model; record each one's angle-0 pose
-- (the server never moves them) the first time we see it.
local function wheelRotors(model: Model, state): { [BasePart]: CFrame }
	for _, d in ipairs(model:GetChildren()) do
		if d:IsA("BasePart") and d:GetAttribute("WheelRotor") == true and not state.rotors[d] then
			state.rotors[d] = d.CFrame
		end
	end
	return state.rotors
end

local function wheelAngle(model: Model): (number, boolean)
	local start = model:GetAttribute("SpinStart")
	local dur = model:GetAttribute("SpinDuration") or 4
	local from = model:GetAttribute("SpinFrom") or 0
	local to = model:GetAttribute("SpinTo") or 0
	if typeof(start) == "number" then
		local a = (Workspace:GetServerTimeNow() - start) / dur
		if a < 1 then
			local e = 1 - (1 - math.clamp(a, 0, 1)) ^ 4 -- quartic ease-out: fast, then agonisingly slow
			return from + (to - from) * e, true
		end
		return to, false
	end
	return model:GetAttribute("WheelAngle") or 0, false
end

-- ─── Feedback helpers ───────────────────────────────────────────────────────
local function popText(position: Vector3, text: string, color: Color3)
	local anchor = Instance.new("Part")
	anchor.Anchored, anchor.CanCollide, anchor.CanQuery, anchor.CanTouch = true, false, false, false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.1, 0.1, 0.1)
	anchor.CFrame = CFrame.new(position)
	anchor.Parent = Workspace.Terrain
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(420, 60)
	gui.AlwaysOnTop = true
	gui.LightInfluence = 0
	gui.Adornee = anchor
	gui.Parent = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.2
	label.Text = text
	label.Parent = gui
	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = label
	TweenService:Create(scale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	TweenService:Create(anchor, TweenInfo.new(2.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { CFrame = CFrame.new(position + Vector3.new(0, 4, 0)) }):Play()
	task.delay(1.5, function()
		TweenService:Create(label, TweenInfo.new(0.7), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end)
	Debris:AddItem(anchor, 2.3)
end

local function coinBurst(position: Vector3, count: number)
	for _ = 1, math.min(count, 60) do
		local coin = Instance.new("Part")
		coin.Shape = Enum.PartType.Cylinder
		coin.Size = Vector3.new(0.12, 0.7, 0.7)
		coin.Color = GOLD
		coin.Material = Enum.Material.Metal
		coin.Reflectance = 0.3
		coin.CanQuery, coin.CanTouch = false, false
		coin.CollisionGroup = "Default"
		coin.CFrame = CFrame.new(position) * CFrame.Angles(math.random() * 6, math.random() * 6, math.random() * 6)
		coin.Parent = Workspace.Terrain
		local dir = Vector3.new(math.random() - 0.5, 1.2 + math.random(), math.random() - 0.5).Unit
		coin.AssemblyLinearVelocity = dir * (22 + math.random() * 18)
		coin.AssemblyAngularVelocity = Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 30
		task.delay(1.4 + math.random() * 0.6, function()
			if coin.Parent then
				TweenService:Create(coin, TweenInfo.new(0.4), { Transparency = 1, Size = coin.Size * 0.4 }):Play()
			end
		end)
		Debris:AddItem(coin, 2.6)
	end
end

local function lightBurst(position: Vector3, color: Color3, size: number)
	local att = Instance.new("Attachment")
	att.Parent = Workspace.Terrain
	att.WorldPosition = position
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = TEX_SPARKLE
	pe.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	pe.LightEmission = 1
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8 * size), NumberSequenceKeypoint.new(1, 0) })
	pe.Lifetime = NumberRange.new(0.5, 1)
	pe.Speed = NumberRange.new(8 * size, 20 * size)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Drag = 3
	pe.Rate = 0
	pe.Parent = att
	pe:Emit(math.floor(30 * size))
	local light = Instance.new("PointLight")
	light.Color, light.Brightness, light.Range = color, 5 * size, 18 * size
	light.Parent = att
	TweenService:Create(light, TweenInfo.new(0.8), { Brightness = 0 }):Play()
	local orb = Instance.new("Part")
	orb.Shape = Enum.PartType.Ball
	orb.Anchored, orb.CanCollide, orb.CanQuery, orb.CanTouch = true, false, false, false
	orb.Material = Enum.Material.Neon
	orb.Color = color
	orb.Size = Vector3.one * 1.5
	orb.CFrame = CFrame.new(position)
	orb.Parent = Workspace.Terrain
	TweenService:Create(orb, TweenInfo.new(0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), { Size = Vector3.one * 7 * size, Transparency = 1 }):Play()
	Debris:AddItem(orb, 0.5)
	Debris:AddItem(att, 1.2)
end

local function healSparkles(model: Instance?)
	if not (model and model:IsA("Model")) then return end
	local root = model:FindFirstChild("HumanoidRootPart")
	if not (root and root:IsA("BasePart")) then return end
	local att = Instance.new("Attachment")
	att.Position = Vector3.new(0, -2, 0)
	att.Parent = root
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = TEX_SPARKLE
	pe.Color = ColorSequence.new(Color3.fromRGB(200, 255, 220), Color3.fromRGB(110, 255, 160))
	pe.LightEmission = 1
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.4), NumberSequenceKeypoint.new(1, 0) })
	pe.Lifetime = NumberRange.new(0.6, 1)
	pe.Speed = NumberRange.new(3, 6)
	pe.SpreadAngle = Vector2.new(15, 15)
	pe.EmissionDirection = Enum.NormalId.Top
	pe.Rate = 0
	pe.Parent = att
	pe:Emit(6)
	Debris:AddItem(att, 1.2)
end

local function jackpot(position: Vector3)
	for k = 0, 4 do
		task.delay(k * 0.15, function()
			lightBurst(position + Vector3.new((math.random() - 0.5) * 8, math.random() * 5, (math.random() - 0.5) * 4),
				Color3.fromHSV(math.random(), 0.7, 1), 1.4)
		end)
	end
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root and (root.Position - position).Magnitude < 60 then
		task.spawn(function()
			local t0 = os.clock()
			while os.clock() - t0 < 0.5 do
				local amp = (1 - (os.clock() - t0) / 0.5) * 0.6
				camera.CFrame *= CFrame.new((math.random() - 0.5) * amp, (math.random() - 0.5) * amp, 0)
				RunService.RenderStepped:Wait()
			end
		end)
	end
end

local function coinToss(coin: Instance?)
	if not (coin and coin:IsA("BasePart")) then return end
	local f = floaters[coin]
	local base = f and f.base or coin.CFrame
	if f then floaters[coin] = nil end
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		if t >= 1.5 or not coin.Parent then
			conn:Disconnect()
			if coin.Parent then
				coin.CFrame = base
				floaters[coin] = { base = base, phase = 0 }
			end
			return
		end
		local h = 9 * math.sin(math.pi * t / 1.5)
		coin.CFrame = base * CFrame.new(0, 0, 0) + Vector3.new(0, h, 0)
		coin.CFrame *= CFrame.Angles(t * 28, 0, 0)
	end)
end

-- ─── Per-frame ──────────────────────────────────────────────────────────────
local function step()
	local t = os.clock()
	for p, f in pairs(floaters) do
		if not p.Parent then
			floaters[p] = nil
		else
			p.CFrame = f.base * CFrame.new(0, math.sin(t * 1.8 + f.phase) * 0.35, 0) * CFrame.Angles(0, t * 0.9 + f.phase, 0)
		end
	end

	for model, state in pairs(wheels) do
		if not model.Parent then
			wheels[model] = nil
			continue
		end
		local faceCF = model:GetAttribute("WheelFaceCF")
		if typeof(faceCF) ~= "CFrame" then continue end
		local angle, spinning = wheelAngle(model)
		local spin = faceCF * CFrame.Angles(0, 0, angle) * faceCF:Inverse()
		for part, base in pairs(wheelRotors(model, state)) do
			if part.Parent then part.CFrame = spin * base end
		end
		-- Rim bulbs: chase while spinning, slow breathe at rest.
		for _, d in ipairs(model:GetChildren()) do
			local idx = d:GetAttribute("RimBulb")
			if idx and d:IsA("BasePart") then
				local on
				if spinning then
					on = (math.floor(t * 14) + idx) % 3 == 0
				else
					on = (math.floor(t * 2) + idx) % 2 == 0
				end
				d.Transparency = on and 0 or 0.6
			end
		end
		-- Pointer ticks as each slice boundary passes.
		if spinning then
			local slices = 12
			local sliceIdx = math.floor(angle / (math.pi * 2 / slices) + 0.5)
			if sliceIdx ~= state.lastTick then
				state.lastTick = sliceIdx
				local pointer = model:FindFirstChild("Pointer")
				if pointer and pointer:IsA("BasePart") then
					local base = faceCF * CFrame.new(0, 7 + 1.1, -0.6) * CFrame.Angles(0, 0, math.rad(45))
					pointer.CFrame = base * CFrame.Angles(0, 0, math.rad(18))
					TweenService:Create(pointer, TweenInfo.new(0.12), { CFrame = base }):Play()
				end
			end
		end
	end

	for water, last in pairs(waters) do
		if not water.Parent then
			waters[water] = nil
		elseif t - last > 1.3 then
			waters[water] = t
			local ring = Instance.new("Part")
			ring.Shape = Enum.PartType.Cylinder
			ring.Anchored, ring.CanCollide, ring.CanQuery, ring.CanTouch = true, false, false, false
			ring.Material = Enum.Material.Neon
			ring.Color = Color3.fromRGB(200, 245, 255)
			ring.Transparency = 0.5
			ring.Size = Vector3.new(0.05, 1, 1)
			ring.CFrame = water.CFrame * CFrame.new(0.2, 0, 0)
			ring.Parent = Workspace.Terrain
			local d = water.Size.Y * 0.95
			TweenService:Create(ring, TweenInfo.new(1.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.new(0.05, d, d), Transparency = 1 }):Play()
			Debris:AddItem(ring, 1.7)
		end
	end
end

function RoomFX.Init()
	for _, d in ipairs(Workspace:GetDescendants()) do track(d) end
	Workspace.DescendantAdded:Connect(function(d)
		task.defer(track, d)
	end)

	Network.GetRemoteEvent(Network.Remotes.RoomEvent).OnClientEvent:Connect(function(payload: any)
		if typeof(payload) ~= "table" then return end
		local pos = payload.position
		if payload.kind == "Pop" and typeof(pos) == "Vector3" then
			popText(pos, tostring(payload.text), typeof(payload.color) == "Color3" and payload.color or GOLD)
		elseif payload.kind == "Coins" and typeof(pos) == "Vector3" then
			coinBurst(pos, payload.count or 10)
		elseif payload.kind == "Burst" and typeof(pos) == "Vector3" then
			lightBurst(pos, typeof(payload.color) == "Color3" and payload.color or GOLD, payload.size or 1)
		elseif payload.kind == "Heal" then
			healSparkles(payload.model)
		elseif payload.kind == "Jackpot" and typeof(pos) == "Vector3" then
			jackpot(pos)
		elseif payload.kind == "CoinToss" then
			coinToss(payload.part)
		end
	end)

	RunService.RenderStepped:Connect(step)
end

return RoomFX
