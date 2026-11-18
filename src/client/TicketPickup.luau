--!strict
--[[
	TicketPickup.luau
	A Pull Ticket dropped from a kill, in the world (GachaManager → TicketDrop
	{ drop = true }): it pops out of the mob, arcs to the floor with a bounce,
	then hovers there spinning like old-school loot until you walk up to it.
	The server decides the pickup (and collects it anyway after a while); its
	{ id } then flies the ticket into you and TicketToast says so.

	The ticket is a classic red "ADMIT ONE" stub: perforated short edges, an
	inner border, the serial number up both ends. It is printed on a SurfaceGui
	(both faces) over a thin red core, so it still has an edge when it turns.
	Effects are kept slight: a shine sweeping across it now and then, a few
	sparkles, and a soft shadow on the floor (no light, no glow).

	Only the player it dropped for sees it. Drops are rare (a few an hour,
	capped server-side) and must be seen, so nothing here is budgeted.

	TicketPickup.Spawn({ id, position, tier })
	TicketPickup.Collect(id)
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local TicketPickup = {}

local RED = Color3.fromRGB(218, 64, 54)
local RED_DARK = Color3.fromRGB(150, 34, 30)
local INK = Color3.fromRGB(62, 16, 14)
local HOVER = 2.4        -- the ticket's centre above the floor
local FALL_TIME = 0.7
local SETTLE_TIME = 0.3
local SPIN_IDLE = math.rad(150) -- per second
local SPIN_FALL = math.rad(900)
local SHINE_EVERY = 2.6  -- seconds between shine sweeps
local TICKET = Vector3.new(4.2, 1.86, 0.08)  -- the printed outline (teeth included)
local CORE = Vector3.new(3.84, 1.7, 0.05)   -- the red core inside it (its edge)
local TILT = math.rad(-28) -- leaned back, so the top-down camera sees its face
local CANVAS = Vector2.new(452, 200)
local TEETH = 9          -- perforation teeth down each short edge

type Drop = {
	model: Model,
	ticket: BasePart,
	core: BasePart,
	shadow: BasePart,
	shines: { Frame },
	from: Vector3,
	floor: Vector3,
	born: number,
	angle: number,
	flying: number?, -- when the pickup started
	flyFrom: Vector3?,
}

local drops: { [number]: Drop } = {}
local count = 0
local conn: RBXScriptConnection? = nil
local folder: Folder? = nil

local function getFolder(): Folder
	if folder and folder.Parent then return folder end
	local f = Instance.new("Folder")
	f.Name = "TicketDrops"
	f.Parent = Workspace
	folder = f
	return f
end

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide, p.CanTouch, p.CanQuery = false, false, false
	p.CastShadow = false
	p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth
	for k, v in pairs(props) do (p :: any)[k] = v end
	return p
end

local function frame(parent: Instance, pos: UDim2, size: UDim2, color: Color3): Frame
	local f = Instance.new("Frame")
	f.Position = pos
	f.Size = size
	f.BackgroundColor3 = color
	f.BorderSizePixel = 0
	f.Parent = parent
	return f
end

-- One printed face of the stub. Returns its shine strip (swept by `step`).
local function face(ticket: BasePart, side: Enum.NormalId): Frame
	local g = Instance.new("SurfaceGui")
	g.Face = side
	g.CanvasSize = CANVAS
	g.LightInfluence = 0.35
	g.ClipsDescendants = true
	g.Parent = ticket
	local W, H = CANVAS.X, CANVAS.Y
	local inset = 18 -- the teeth stick out this far past the body

	-- the body
	local body = frame(g, UDim2.fromOffset(inset, 0), UDim2.fromOffset(W - inset * 2, H), RED)
	body.ClipsDescendants = true
	-- perforations: a row of small squares turned 45° down both short edges
	local step = H / TEETH
	for i = 0, TEETH - 1 do
		for _, x in ipairs({ inset, W - inset }) do
			local t = frame(g, UDim2.fromOffset(x, step * (i + 0.5)), UDim2.fromOffset(step * 0.72, step * 0.72), RED)
			t.AnchorPoint = Vector2.new(0.5, 0.5)
			t.Rotation = 45
		end
	end
	-- the inner border
	local border = frame(body, UDim2.fromOffset(16, 14), UDim2.new(1, -32, 1, -28), RED)
	border.BackgroundTransparency = 1
	local stroke = Instance.new("UIStroke")
	stroke.Color = RED_DARK
	stroke.Thickness = 3
	stroke.Parent = border
	-- the stub lines between the serials and the middle
	for _, x in ipairs({ 62, W - inset * 2 - 62 }) do
		frame(body, UDim2.fromOffset(x, 14), UDim2.fromOffset(3, H - 28), RED_DARK)
	end

	local function label(text: string, pos: UDim2, size: UDim2, textSize: number, rot: number?)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.AnchorPoint = Vector2.new(0.5, 0.5)
		l.Position = pos
		l.Size = size
		l.Font = Enum.Font.GothamBlack
		l.TextSize = textSize
		l.TextColor3 = INK
		l.TextTransparency = 0
		l.Text = text
		l.Rotation = rot or 0
		l.Parent = body
		return l
	end
	label("ADMIT", UDim2.new(0.5, 0, 0.5, -33), UDim2.fromOffset(290, 66), 66)
	label("ONE", UDim2.new(0.5, 0, 0.5, 33), UDim2.fromOffset(290, 66), 66)
	local serial = tostring(math.random(100000, 999999))
	label(serial, UDim2.new(0, 39, 0.5, 0), UDim2.fromOffset(170, 34), 28, 90)
	label(serial, UDim2.new(1, -39, 0.5, 0), UDim2.fromOffset(170, 34), 28, 90)

	-- the shine: a soft white band, parked off the left edge between sweeps
	local shine = frame(g, UDim2.new(-0.3, 0, -0.2, 0), UDim2.new(0.18, 0, 1.4, 0), Color3.new(1, 1, 1))
	shine.Rotation = 18
	shine.BackgroundTransparency = 0
	local grad = Instance.new("UIGradient")
	grad.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.55), NumberSequenceKeypoint.new(1, 1),
	})
	grad.Parent = shine
	return shine
end

local function build(at: Vector3): (Model, BasePart, BasePart, BasePart, { Frame })
	local m = Instance.new("Model")
	m.Name = "PullTicket"
	local cf = CFrame.new(at)
	local ticket = part({ Name = "Ticket", Size = TICKET, Transparency = 1, CFrame = cf })
	ticket.Parent = m
	local shines = { face(ticket, Enum.NormalId.Front), face(ticket, Enum.NormalId.Back) }
	local core = part({ Name = "Core", Size = CORE, Color = RED, Material = Enum.Material.SmoothPlastic, CFrame = cf })
	core.Parent = m

	-- a few slow sparkles around it
	local sp = Instance.new("ParticleEmitter")
	sp.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	sp.Color = ColorSequence.new(Color3.fromRGB(255, 236, 200))
	sp.LightEmission = 0.6
	sp.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.28), NumberSequenceKeypoint.new(1, 0) })
	sp.Transparency = NumberSequence.new(0.35)
	sp.Lifetime = NumberRange.new(0.7, 1.1)
	sp.Rate = 3
	sp.Speed = NumberRange.new(0.6, 1.2)
	sp.SpreadAngle = Vector2.new(180, 180)
	sp.Parent = core

	-- a soft shadow on the floor (grounds it; shrinks as it bobs up)
	local shadow = part({ Name = "Shadow", Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.04, 3.2, 3.2), Color = Color3.new(0, 0, 0), Material = Enum.Material.SmoothPlastic, Transparency = 1 })
	shadow.Parent = m

	local bb = Instance.new("BillboardGui")
	bb.Name = "Tag"
	bb.Size = UDim2.fromOffset(140, 26)
	bb.StudsOffset = Vector3.new(0, 1.8, 0)
	bb.MaxDistance = 80
	bb.LightInfluence = 0
	bb.Adornee = core
	local tag = Instance.new("TextLabel")
	tag.BackgroundTransparency = 1
	tag.Size = UDim2.fromScale(1, 1)
	tag.Font = Enum.Font.Antique
	tag.TextSize = 18
	tag.TextColor3 = Color3.fromRGB(255, 226, 210)
	tag.TextStrokeTransparency = 0.3
	tag.Text = "PULL TICKET"
	tag.Parent = bb
	bb.Parent = core

	m.PrimaryPart = core
	m.Parent = getFolder()
	return m, ticket, core, shadow, shines
end

-- Where it lands: the solid floor under (and a little away from) the kill.
local function landing(from: Vector3): Vector3
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.RespectCanCollide = true
	local skip: { Instance } = { getFolder() }
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(skip, p.Character) end
	end
	local mobs = Workspace:FindFirstChild("Mobs")
	if mobs then table.insert(skip, mobs) end
	params.FilterDescendantsInstances = skip
	local a = math.random() * math.pi * 2
	local side = Vector3.new(math.cos(a), 0, math.sin(a)) * (1.5 + math.random() * 1.5)
	for _, off in ipairs({ side, Vector3.zero }) do
		local hit = Workspace:Raycast(from + off + Vector3.new(0, 3, 0), Vector3.new(0, -40, 0), params)
		if hit then return hit.Position end
	end
	return from - Vector3.new(0, 3, 0)
end

local function easeOut(t: number): number
	return 1 - (1 - t) * (1 - t)
end

local function step(dt: number)
	local now = os.clock()
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	for id, d in pairs(drops) do
		local age = now - d.born
		local pos: Vector3
		local spin = SPIN_IDLE
		local rest = d.floor + Vector3.new(0, HOVER, 0)
		if d.flying then
			-- the pickup: into the player, shrinking
			local t = math.clamp((now - d.flying) / 0.32, 0, 1)
			local target = if root then root.Position else rest
			pos = (d.flyFrom :: Vector3):Lerp(target, t * t) + Vector3.new(0, math.sin(t * math.pi) * 1.5, 0)
			spin = SPIN_FALL
			local s = 1 - t * 0.85
			d.ticket.Size = TICKET * s
			d.core.Size = CORE * s
			d.shadow.Transparency = 0.7 + 0.3 * t
			if t >= 1 then
				d.model:Destroy()
				drops[id] = nil
				count -= 1
				continue
			end
		elseif age < FALL_TIME then
			-- the pop: out of the mob, up and over onto the floor
			local t = age / FALL_TIME
			local ground = d.floor + Vector3.new(0, 0.7, 0)
			pos = d.from:Lerp(ground, t) + Vector3.new(0, math.sin(t * math.pi) * 5, 0)
			spin = SPIN_FALL
		else
			-- a small bounce up to the hover, then the idle bob
			local t = math.clamp((age - FALL_TIME) / SETTLE_TIME, 0, 1)
			local base = d.floor + Vector3.new(0, 0.7 + (HOVER - 0.7) * easeOut(t), 0)
			local bobS = math.sin((age - FALL_TIME) * 2.4)
			pos = base + Vector3.new(0, bobS * 0.25 * t, 0)
			spin = SPIN_FALL + (SPIN_IDLE - SPIN_FALL) * t
			-- the shadow fades in once it has landed, a little smaller at the top of the bob
			d.shadow.Transparency = 1 - (0.3 - 0.05 * bobS) * t
			local r = 3.2 - 0.3 * bobS
			d.shadow.Size = Vector3.new(0.04, r, r)
			-- the shine: one sweep across the face every SHINE_EVERY seconds
			local k = ((age - FALL_TIME) % SHINE_EVERY) / 0.55
			local x = if k < 1 then -0.3 + 1.6 * k else -0.3
			for _, s in ipairs(d.shines) do
				s.Position = UDim2.new(x, 0, -0.2, 0)
			end
		end
		d.angle = (d.angle + spin * dt) % (math.pi * 2)
		local cf = CFrame.new(pos) * CFrame.Angles(0, d.angle, 0) * CFrame.Angles(TILT, 0, 0)
		d.ticket.CFrame = cf
		d.core.CFrame = cf
	end
	if count <= 0 and conn then
		conn:Disconnect()
		conn = nil
	end
end

function TicketPickup.Spawn(payload: any)
	local id, at = payload.id, payload.position
	if typeof(id) ~= "number" or typeof(at) ~= "Vector3" or drops[id] then return end
	local from = at + Vector3.new(0, 1, 0)
	local floor = landing(at)
	local model, ticket, core, shadow, shines = build(from)
	shadow.CFrame = CFrame.new(floor + Vector3.new(0, 0.04, 0)) * CFrame.Angles(0, 0, math.rad(90))
	drops[id] = {
		model = model, ticket = ticket, core = core, shadow = shadow, shines = shines,
		from = from, floor = floor, born = os.clock(), angle = math.random() * math.pi * 2,
	}
	count += 1
	if not conn then conn = RunService.RenderStepped:Connect(step) end
end

function TicketPickup.Collect(id: any)
	local d = typeof(id) == "number" and drops[id] or nil
	if not d or d.flying then return end
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root or (root.Position - d.core.Position).Magnitude > 120 then
		-- (far away, or another floor by now: just gone)
		d.model:Destroy()
		drops[id] = nil
		count -= 1
		return
	end
	d.flying = os.clock()
	d.flyFrom = d.core.Position
	local tag = d.core:FindFirstChild("Tag")
	if tag then tag:Destroy() end
end

return TicketPickup
