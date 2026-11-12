--!strict
--[[
	GearView.luau
	The pieces both gear screens are made of: the Armory's EQUIPMENT tab
	(ArmoryGear, the gear you keep) and the Forgotten Isle's G screen
	(EquipmentScreen, the gear of one run).

	  GearView.C / SERIF / SERIF_BOLD     the in-game HUD's palette and fonts
	  GearView.new / label / button       little builders
	  GearView.Cell(parent, props, vpProps) → Cell   a button with a model
	                                         viewport, framed in a grade
	  GearView.Pips(parent, props)        up to six grade diamonds
	  GearView.Style(cell, color?, tier, tiers, text?)  a cell in its grade:
	                                         border, colour wash, diamonds,
	                                         label (tier 0 = empty); the top
	                                         grades shimmer (GearView.Shimmer)
	  GearView.SetIcon(cell, key?, make, tilt?)  the model in a cell, rebuilt
	                                         only when `key` changes
	  GearView.FrameIcon(model, cam, tilt?, spin?)
	  GearView.Preview(stage) → Preview   your character, live in a
	                                         ViewportFrame: :Show(), :Hide()
	                                         (empties it), :Step(dt) (the slow
	                                         turn; drag to turn it)
--]]

local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local player = Players.LocalPlayer

local GearView = {}

GearView.C = {
	stone = Color3.fromRGB(14, 11, 17),
	stone2 = Color3.fromRGB(28, 23, 32),
	stone3 = Color3.fromRGB(40, 33, 46),
	gold = Color3.fromRGB(212, 172, 92),
	goldBright = Color3.fromRGB(255, 222, 140),
	white = Color3.fromRGB(242, 236, 224),
	dim = Color3.fromRGB(160, 150, 140),
	faint = Color3.fromRGB(90, 82, 96),
	red = Color3.fromRGB(214, 64, 58),
	green = Color3.fromRGB(120, 230, 140),
}
local C = GearView.C
GearView.SERIF = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Regular)
GearView.SERIF_BOLD = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Bold)

-- ── Little builders ─────────────────────────────────────────────────────────
function GearView.new(class: string, props: { [string]: any }, parent: Instance?): any
	local i = Instance.new(class)
	for k, v in pairs(props) do (i :: any)[k] = v end
	if parent then i.Parent = parent end
	return i
end
local new = GearView.new

function GearView.label(parent: Instance, props: { [string]: any }): TextLabel
	local l = new("TextLabel", {
		BackgroundTransparency = 1, FontFace = GearView.SERIF, TextColor3 = C.white, TextSize = 14,
		TextStrokeTransparency = 0.6, TextXAlignment = Enum.TextXAlignment.Left,
	}, parent)
	for k, v in pairs(props) do (l :: any)[k] = v end
	return l
end

function GearView.button(parent: Instance, text: string, color: Color3, props: { [string]: any }): TextButton
	local b = new("TextButton", {
		BackgroundColor3 = C.stone2, BorderSizePixel = 0, AutoButtonColor = true, FontFace = GearView.SERIF_BOLD,
		Text = text, TextColor3 = color, TextSize = 15,
	}, parent)
	for k, v in pairs(props) do (b :: any)[k] = v end
	new("UICorner", { CornerRadius = UDim.new(0, 4) }, b)
	new("UIStroke", { Name = "Edge", Color = color, Thickness = 1.4, Transparency = 0.25, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
	return b
end

-- A button greyed out (and dead) or live.
function GearView.Enable(b: TextButton, on: boolean)
	b.Active = on
	b.AutoButtonColor = on
	b.TextTransparency = if on then 0 else 0.6
	local e = b:FindFirstChild("Edge") :: UIStroke?
	if e then e.Transparency = if on then 0.25 else 0.75 end
end

-- ── Cells ───────────────────────────────────────────────────────────────────
export type Cell = { button: TextButton, vp: ViewportFrame, cam: Camera, stroke: UIStroke, grad: UIGradient, key: string?,
	model: Model?, nameL: TextLabel?, gradeL: TextLabel?, slotL: TextLabel?, extraL: TextLabel?, pips: Frame?, shimmer: boolean }

function GearView.Cell(parent: Instance, props: { [string]: any }, vpProps: { [string]: any }): Cell
	local b = new("TextButton", { BackgroundColor3 = C.stone2, BorderSizePixel = 0, Text = "", AutoButtonColor = false, ClipsDescendants = true }, parent)
	for k, v in pairs(props) do (b :: any)[k] = v end
	new("UICorner", { CornerRadius = UDim.new(0, 5) }, b)
	local stroke = new("UIStroke", { Color = C.faint, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, b)
	local grad = new("UIGradient", { Rotation = -90 }, b)
	local vp = new("ViewportFrame", { BackgroundTransparency = 1, Ambient = Color3.fromRGB(150, 145, 165), LightColor = Color3.new(1, 1, 1),
		LightDirection = Vector3.new(-0.5, -1, -0.7), ZIndex = 2 }, b)
	for k, v in pairs(vpProps) do (vp :: any)[k] = v end
	local cam = new("Camera", { FieldOfView = 30 }, vp)
	vp.CurrentCamera = cam
	return { button = b, vp = vp, cam = cam, stroke = stroke, grad = grad, key = nil, model = nil, shimmer = false }
end

function GearView.Pips(parent: Instance, props: { [string]: any }): Frame
	local f = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(70, 12), ZIndex = 4 }, parent)
	for k, v in pairs(props) do (f :: any)[k] = v end
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder,
		HorizontalAlignment = if f.AnchorPoint.X > 0.5 then Enum.HorizontalAlignment.Right else Enum.HorizontalAlignment.Left,
		VerticalAlignment = Enum.VerticalAlignment.Center }, f)
	for i = 1, 6 do
		local d = new("Frame", { Name = tostring(i), LayoutOrder = i, BorderSizePixel = 0, Size = UDim2.fromOffset(7, 7), Rotation = 45, ZIndex = 4, Visible = false }, f)
		new("UIStroke", { Color = C.stone, Thickness = 1 }, d)
	end
	return f
end

-- A cell in its grade: `tier` of `tiers` (0 = empty). The top grade (and
-- the one under it, with six) shimmers.
function GearView.Style(cell: Cell, color: Color3?, tier: number, tiers: number, text: string?)
	local has = color ~= nil and tier > 0
	local col = color or C.faint
	cell.stroke.Color = col
	cell.stroke.Thickness = if has then 1.4 + tier * (1.5 / tiers) else 1
	cell.stroke.Transparency = if has then 0 else 0.5
	cell.button.BackgroundColor3 = if has then col:Lerp(C.stone, 0.72) else C.stone2
	cell.grad.Color = ColorSequence.new(col:Lerp(C.stone, 0.35), C.stone)
	cell.grad.Transparency = NumberSequence.new(if has then 0.1 else 1, 0.4)
	cell.shimmer = has and tier >= tiers - (if tiers >= 5 then 1 else 0)
	if not cell.shimmer then cell.grad.Offset = Vector2.zero end
	if cell.pips then
		for _, p in ipairs(cell.pips:GetChildren()) do
			if p:IsA("Frame") then
				local i = tonumber(p.Name) or 0
				p.Visible = has and i <= tier
				p.BackgroundColor3 = col:Lerp(Color3.new(1, 1, 1), 0.25)
			end
		end
	end
	if cell.gradeL then
		cell.gradeL.Text = if has and text then string.upper(text) else ""
		cell.gradeL.TextColor3 = col:Lerp(Color3.new(1, 1, 1), 0.2)
	end
end

-- The shimmer on the top grades' wash (call while the screen is open).
function GearView.Shimmer(cells: { Cell })
	local x = (os.clock() * 0.6) % 2 - 1
	for _, cell in ipairs(cells) do
		if cell.shimmer then cell.grad.Offset = Vector2.new(0, x * 0.15) end
	end
end

-- ── Icons ───────────────────────────────────────────────────────────────────
-- A model framed in a viewport, turned to show its depth (`tilt`: long
-- weapons lie corner to corner).
function GearView.FrameIcon(model: Model, cam: Camera, tilt: boolean?, spin: number?)
	local t = if tilt then CFrame.Angles(0, 0, math.rad(-38)) else CFrame.identity
	model:PivotTo(CFrame.Angles(0, math.rad(-24) + (spin or 0), 0) * t)
	local bb, ext = model:GetBoundingBox()
	local size = math.max(ext.X, ext.Y, ext.Z * 0.6)
	local dist = size / (2 * math.tan(math.rad(cam.FieldOfView / 2))) * 1.12 + ext.Z / 2
	cam.CFrame = CFrame.lookAt(bb.Position + Vector3.new(0, size * 0.12, dist), bb.Position)
end

-- The model in a cell: rebuilt only when `key` changes (nil empties it).
function GearView.SetIcon(cell: Cell, key: string?, make: () -> Model?, tilt: boolean?)
	if cell.key == key and (key == nil or cell.model ~= nil) then return end
	if cell.model then cell.model:Destroy() end
	cell.model = nil
	cell.key = key
	if not key then return end
	local m = make()
	if not m then return end
	m.Parent = cell.vp
	GearView.FrameIcon(m, cell.cam, tilt)
	cell.model = m
end

-- ── Your character ──────────────────────────────────────────────────────────
type Joint = { p0: BasePart, p1: BasePart, c0: CFrame, c1: CFrame, rel: CFrame?, name: string, motor: boolean }

-- Character-space turn → a motor's own frame (RewardPreview, CastPoses).
local function inFrame(c0: CFrame, r: CFrame): CFrame
	local basis = c0.Rotation
	return basis:Inverse() * r * basis
end

-- A copy of the character: no scripts, sounds or effects, every joint
-- recorded and removed (it's posed by hand: anchored, no physics), standing
-- relaxed at the origin facing -Z.
local function copyCharacter(): Model?
	local char = player.Character
	if not char or not char:FindFirstChild("HumanoidRootPart") then return nil end
	local was = char.Archivable
	char.Archivable = true
	local ok, c = pcall(function() return char:Clone() end)
	char.Archivable = was
	if not ok or not c then return nil end
	local m = c :: Model
	m.Name = "GearPreview"
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BaseScript") or d:IsA("ModuleScript") or d:IsA("Sound") or d:IsA("ForceField") or d:IsA("ParticleEmitter")
			or d:IsA("Trail") or d:IsA("Beam") or d:IsA("Light") or d:IsA("Highlight") or d:IsA("BillboardGui")
			or d:IsA("Fire") or d:IsA("Smoke") or d:IsA("Sparkles") or d:IsA("BodyMover") or d:IsA("Constraint") then
			d:Destroy()
		end
	end
	local hum = m:FindFirstChildOfClass("Humanoid")
	if hum then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		local animator = hum:FindFirstChildOfClass("Animator")
		if animator then animator:Destroy() end
	end
	local saved: { [BasePart]: CFrame } = {}
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			saved[d] = d.CFrame
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.CastShadow = false
		end
	end
	local joints: { Joint } = {}
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("JointInstance") or d:IsA("WeldConstraint") then
			local j = d :: any
			local p0, p1 = j.Part0, j.Part1
			if p0 and p1 and saved[p0] and saved[p1] then
				if d:IsA("JointInstance") then
					table.insert(joints, { p0 = p0, p1 = p1, c0 = j.C0, c1 = j.C1, name = d.Name, motor = d:IsA("Motor6D") })
				else
					table.insert(joints, { p0 = p0, p1 = p1, c0 = CFrame.identity, c1 = CFrame.identity, rel = saved[p0]:Inverse() * saved[p1], name = d.Name, motor = false })
				end
			end
		end
	end
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("JointInstance") or d:IsA("WeldConstraint") then d:Destroy() end
	end
	local hrp = m:FindFirstChild("HumanoidRootPart") :: BasePart
	hrp.Transparency = 1
	-- the pose: arms a little out, feet a little apart
	local function c0(name: string): CFrame
		for _, j in ipairs(joints) do
			if j.name == name and j.motor then return j.c0 end
		end
		return CFrame.identity
	end
	local pose = {
		["Right Shoulder"] = inFrame(c0("Right Shoulder"), CFrame.Angles(math.rad(8), 0, math.rad(9))),
		["Left Shoulder"] = inFrame(c0("Left Shoulder"), CFrame.Angles(math.rad(4), 0, math.rad(-9))),
		["Right Hip"] = inFrame(c0("Right Hip"), CFrame.Angles(0, 0, math.rad(4))),
		["Left Hip"] = inFrame(c0("Left Hip"), CFrame.Angles(0, 0, math.rad(-4))),
	}
	-- (anything no joint reaches keeps its place against the root)
	local root = CFrame.new(0, 3, 0)
	for p, cf in pairs(saved) do p.CFrame = root * saved[hrp]:Inverse() * cf end
	hrp.CFrame = root
	local done: { [BasePart]: boolean } = { [hrp] = true }
	local edges: { [BasePart]: { Joint } } = {}
	for _, j in ipairs(joints) do
		edges[j.p0] = edges[j.p0] or {}
		table.insert(edges[j.p0], j)
		edges[j.p1] = edges[j.p1] or {}
		table.insert(edges[j.p1], j)
	end
	local queue = { hrp }
	local i = 1
	while i <= #queue do
		local a = queue[i]
		i += 1
		for _, j in ipairs(edges[a] or {}) do
			local other = if j.p0 == a then j.p1 else j.p0
			if done[other] then continue end
			local t = if j.motor then (pose[j.name] or CFrame.identity) else CFrame.identity
			if j.rel then
				other.CFrame = if j.p0 == a then a.CFrame * j.rel else a.CFrame * j.rel:Inverse()
			elseif j.p0 == a then
				other.CFrame = a.CFrame * j.c0 * t * j.c1:Inverse()
			else
				other.CFrame = a.CFrame * j.c1 * t:Inverse() * j.c0:Inverse()
			end
			done[other] = true
			table.insert(queue, other)
		end
	end
	return m
end

export type Preview = { Show: (Preview) -> (), Hide: (Preview) -> (), Step: (Preview, number) -> (), viewport: ViewportFrame }

-- Your character in `stage` (a Frame): a ViewportFrame filling it, a floor
-- glow, "drag to turn".
function GearView.Preview(stage: Frame): Preview
	local glow = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 1, -42), Size = UDim2.fromOffset(230, 46),
		BackgroundColor3 = C.gold, BackgroundTransparency = 0.25, BorderSizePixel = 0 }, stage)
	new("UICorner", { CornerRadius = UDim.new(0.5, 0) }, glow)
	new("UIGradient", { Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.5, 0.55),
		NumberSequenceKeypoint.new(1, 1) }) }, glow)
	local vp: ViewportFrame = new("ViewportFrame", { Name = "Character", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1),
		Ambient = Color3.fromRGB(135, 125, 150), LightColor = Color3.fromRGB(255, 240, 220), LightDirection = Vector3.new(-0.4, -1, 0.6), ZIndex = 2 }, stage)
	local cam: Camera = new("Camera", { FieldOfView = 30 }, vp)
	vp.CurrentCamera = cam
	GearView.label(stage, { Text = "drag to turn", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -6), Size = UDim2.fromOffset(200, 14),
		TextSize = 10, TextColor3 = C.faint, TextXAlignment = Enum.TextXAlignment.Center, ZIndex = 3 })

	local clone: Model? = nil
	local shown = false
	local yaw, lastDrag, dragging, lastTry = math.rad(-28), 0, false, 0
	local function place()
		local center = Vector3.new(0, 3.1, 0)
		cam.CFrame = CFrame.lookAt(center + CFrame.Angles(0, yaw, 0):VectorToWorldSpace(Vector3.new(0, 1.2, -14.5)), center)
	end
	vp.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			dragging = true
			lastDrag = os.clock()
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then dragging = false end
	end)
	UserInputService.InputChanged:Connect(function(input)
		if not shown or not dragging then return end
		if input.UserInputType == Enum.UserInputType.MouseMovement or input.UserInputType == Enum.UserInputType.Touch then
			yaw -= input.Delta.X * 0.012
			lastDrag = os.clock()
			place()
		end
	end)

	local self = { viewport = vp } :: any
	function self.Show(_: Preview)
		shown = true
		yaw, lastDrag = math.rad(-28), os.clock()
		if clone then clone:Destroy() end
		clone = copyCharacter()
		if clone then clone.Parent = vp end
		place()
	end
	function self.Hide(_: Preview)
		shown = false
		dragging = false
		if clone then clone:Destroy() end
		clone = nil
	end
	function self.Step(_: Preview, dt: number)
		if not shown then return end
		if not clone and os.clock() - lastTry > 1 then
			-- (no body yet when it opened: try again, now and then)
			lastTry = os.clock()
			clone = copyCharacter()
			if clone then clone.Parent = vp end
		end
		if not dragging and os.clock() - lastDrag > 2.5 then
			yaw += dt * math.rad(14)
			place()
		end
	end
	-- (a new body while it's shown: show the new one)
	player.CharacterAdded:Connect(function()
		if not shown then return end
		task.wait(0.5)
		if shown then self:Show() end
	end)
	return self :: Preview
end

return GearView
