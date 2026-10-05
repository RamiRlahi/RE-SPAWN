--!strict
--[[
	PrisonFX.luau
	The prison's searchlights and alarm, on this screen (the server runs them:
	Prison.luau):

	  • each searchlight (tagged "PrisonSpotlight") throws a pool of light on
	    the floor and a beam down from its lamp to it, gliding smoothly to
	    where the server says it is ("SpotAt"); pale while it wanders, amber
	    while it hunts someone, red when it sees someone, dim while it rests
	  • three eyes at the top of the screen: the run's sightings. Each one
	    opens red as you're seen; the third sounds the ALARM, a banner and
	    a red pulse round the screen while the inmates come down the lifts
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")
local TweenService = game:GetService("TweenService")

local RunScope = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RunScope"))

local PrisonFX = {}

local player = Players.LocalPlayer
local TAG = "PrisonSpotlight"
local DRAW_RANGE = 220
local RADIUS = 6.5

local PALE = Color3.fromRGB(255, 248, 220)
local AMBER = Color3.fromRGB(255, 196, 110)
local RED = Color3.fromRGB(255, 60, 50)

type Light = { disc: BasePart, a1: Attachment, beam: Beam?, pos: Vector3? }
local lights: { [Model]: Light } = {}
local folder: Folder? = nil

local function holder(): Folder
	if folder and folder.Parent then return folder end
	local f = Instance.new("Folder")
	f.Name = "PrisonLights"
	f.Parent = Workspace
	folder = f
	return f
end

local function lightFor(lamp: Model): Light
	local l = lights[lamp]
	if l then return l end
	local disc = Instance.new("Part")
	disc.Name = "SpotPool"
	disc.Shape = Enum.PartType.Cylinder
	disc.Anchored, disc.CanCollide, disc.CanTouch, disc.CanQuery, disc.CastShadow = true, false, false, false, false
	disc.Material = Enum.Material.Neon
	disc.Size = Vector3.new(0.1, RADIUS * 2, RADIUS * 2)
	disc.Color = PALE
	disc.Transparency = 0.6
	disc.Parent = holder()
	local a1 = Instance.new("Attachment")
	a1.Parent = disc
	local beam: Beam? = nil
	local a0 = lamp:FindFirstChild("Beam0", true)
	if a0 and a0:IsA("Attachment") then
		local b = Instance.new("Beam")
		b.Attachment0, b.Attachment1 = a0, a1
		b.Width0, b.Width1 = 1.6, RADIUS * 1.7
		b.FaceCamera = true
		b.LightEmission = 1
		b.LightInfluence = 0
		b.Segments = 1
		b.Transparency = NumberSequence.new(0.7, 0.88)
		b.Color = ColorSequence.new(PALE)
		b.Parent = disc
		beam = b
	end
	l = { disc = disc, a1 = a1, beam = beam, pos = nil }
	lights[lamp] = l
	return l
end

local function drop(lamp: Model)
	local l = lights[lamp]
	if l then
		l.disc:Destroy()
		lights[lamp] = nil
	end
end

local function stepLights(dt: number)
	local cam = Workspace.CurrentCamera
	local camPos = if cam then cam.CFrame.Position else Vector3.zero
	local serverNow = Workspace:GetServerTimeNow()
	for _, inst in ipairs(CollectionService:GetTagged(TAG)) do
		if not inst:IsA("Model") or not inst:IsDescendantOf(Workspace) then continue end
		local lamp = inst :: Model
		local at = lamp:GetAttribute("SpotAt")
		local floorY = lamp:GetAttribute("FloorY")
		if typeof(at) ~= "Vector3" or typeof(floorY) ~= "number" then continue end
		if (at - camPos).Magnitude > DRAW_RANGE then
			drop(lamp)
			continue
		end
		local l = lightFor(lamp)
		local cur = l.pos or at
		cur = cur:Lerp(at, 1 - math.exp(-10 * dt))
		l.pos = cur
		l.disc.CFrame = CFrame.new(cur.X, floorY + 0.15, cur.Z) * CFrame.Angles(0, 0, math.rad(90))
		-- its mood
		local seenAt = lamp:GetAttribute("SeenAt")
		local seen = typeof(seenAt) == "number" and serverNow - seenAt < 0.9
		local color, alpha
		if seen then
			color, alpha = RED, 0.3
		elseif lamp:GetAttribute("Resting") == true then
			color, alpha = PALE, 0.88
		elseif lamp:GetAttribute("Hunting") == true then
			color, alpha = AMBER, 0.5
		else
			color, alpha = PALE, 0.62
		end
		if l.disc.Color ~= color then l.disc.Color = color end
		if math.abs(l.disc.Transparency - alpha) > 0.01 then l.disc.Transparency = alpha end
		if l.beam then
			l.beam.Color = ColorSequence.new(color)
			l.beam.Transparency = NumberSequence.new(math.min(0.95, alpha + 0.12), math.min(0.97, alpha + 0.28))
		end
	end
	for lamp in pairs(lights) do
		if not lamp:IsDescendantOf(Workspace) then drop(lamp) end
	end
end

-- ── The eyes and the alarm ───────────────────────────────────────────────────
local gui: ScreenGui? = nil
local eyes: { { lid: Frame, pupil: Frame } } = {}
local banner: TextLabel? = nil
local edge: Frame? = nil

local function buildHud()
	local pg = player:WaitForChild("PlayerGui")
	local g = Instance.new("ScreenGui")
	g.Name = "PrisonHUD"
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.DisplayOrder = 20
	g.Enabled = false
	g.Parent = pg
	gui = g
	local row = Instance.new("Frame")
	row.AnchorPoint = Vector2.new(0.5, 0)
	row.Position = UDim2.new(0.5, 0, 0, 92)
	row.Size = UDim2.fromOffset(3 * 58, 40)
	row.BackgroundTransparency = 1
	row.Parent = g
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.Padding = UDim.new(0, 10)
	layout.Parent = row
	for _ = 1, 3 do
		-- an almond eye: a dark lid, a pupil that fills red when you're seen
		local lid = Instance.new("Frame")
		lid.Size = UDim2.fromOffset(48, 30)
		lid.BackgroundColor3 = Color3.fromRGB(28, 30, 34)
		lid.BorderSizePixel = 0
		lid.Parent = row
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(1, 0)
		c.Parent = lid
		local st = Instance.new("UIStroke")
		st.Color = Color3.fromRGB(190, 200, 205)
		st.Thickness = 2
		st.Parent = lid
		local pupil = Instance.new("Frame")
		pupil.AnchorPoint = Vector2.new(0.5, 0.5)
		pupil.Position = UDim2.fromScale(0.5, 0.5)
		pupil.Size = UDim2.fromOffset(14, 14)
		pupil.BackgroundColor3 = Color3.fromRGB(70, 74, 80)
		pupil.BorderSizePixel = 0
		pupil.Parent = lid
		local pc = Instance.new("UICorner")
		pc.CornerRadius = UDim.new(1, 0)
		pc.Parent = pupil
		table.insert(eyes, { lid = lid, pupil = pupil })
	end
	local b = Instance.new("TextLabel")
	b.AnchorPoint = Vector2.new(0.5, 0)
	b.Position = UDim2.new(0.5, 0, 0, 140)
	b.Size = UDim2.fromOffset(640, 44)
	b.BackgroundTransparency = 1
	b.Font = Enum.Font.Arcade
	b.TextSize = 34
	b.TextColor3 = RED
	b.TextStrokeColor3 = Color3.fromRGB(30, 0, 0)
	b.TextStrokeTransparency = 0
	b.Text = ""
	b.TextTransparency = 1
	b.TextStrokeTransparency = 1
	b.Parent = g
	banner = b
	local e = Instance.new("Frame")
	e.Size = UDim2.fromScale(1, 1)
	e.BackgroundTransparency = 1
	e.BorderSizePixel = 0
	e.Parent = g
	local es = Instance.new("UIStroke")
	es.Name = "Pulse"
	es.Color = RED
	es.Thickness = 26
	es.Transparency = 1
	es.Parent = e
	edge = e
end

local function flash(text: string, hold: number)
	local b = banner
	if not b then return end
	b.Text = text
	b.TextTransparency, b.TextStrokeTransparency = 0, 0
	TweenService:Create(b, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, hold),
		{ TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
end

local shownStrikes = 0
local shownAlarm: number? = nil
local function stepHud()
	local g = gui
	if not g then return end
	local on = player:GetAttribute("InLobby") == false and RunScope.Mine("Prison") == true
	if g.Enabled ~= on then g.Enabled = on end
	if not on then return end
	local strikes = tonumber(RunScope.Mine("SpotStrikes")) or 0
	if strikes ~= shownStrikes then
		if strikes > shownStrikes and strikes < 3 then flash("SEEN", 0.8) end
		shownStrikes = strikes
		for i, e in ipairs(eyes) do
			local open = i <= strikes
			e.pupil.BackgroundColor3 = if open then RED else Color3.fromRGB(70, 74, 80)
			e.pupil.Size = if open then UDim2.fromOffset(20, 20) else UDim2.fromOffset(14, 14)
			if open and i == strikes then
				e.lid.Size = UDim2.fromOffset(58, 38)
				TweenService:Create(e.lid, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(48, 30) }):Play()
			end
		end
	end
	local alarm = RunScope.Mine("AlarmAt")
	if typeof(alarm) == "number" and alarm ~= shownAlarm then
		local fresh = shownAlarm ~= nil or Workspace:GetServerTimeNow() - alarm < 3
		shownAlarm = alarm
		if fresh then
			flash("ALARM! THE INMATES ARE COMING", 2.6)
			local pulse = edge and edge:FindFirstChild("Pulse") :: UIStroke?
			if pulse then
				pulse.Transparency = 0.2
				TweenService:Create(pulse, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, 4, true), { Transparency = 0.8 }):Play()
				task.delay(5, function() pulse.Transparency = 1 end)
			end
		end
	end
end

function PrisonFX.Init()
	buildHud()
	RunService.RenderStepped:Connect(function(dt)
		local ok, err = pcall(stepLights, dt)
		if not ok then warn("[PrisonFX]", err) end
		pcall(stepHud)
	end)
end

return PrisonFX
