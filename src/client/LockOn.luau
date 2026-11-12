--!strict
--[[
	LockOn.luau
	A hard lock on one mob. The middle mouse button (or a controller's right
	stick click) locks on to the mob nearest the cursor; pressing it again
	lets go, and so does the mob dying, leaving or getting too far away.
	While locked, AimInput hands every aim in the game (every class's attacks
	and abilities, the body's turn) the locked mob instead of the cursor.

	  LockOn.Target() → BasePart?   (the locked mob's HumanoidRootPart)
	  LockOn.Point() → Vector3?     (where to aim: the locked mob, or nil)
	  LockOn.Toggle(screenPoint)  (lock the mob nearest it, or let go)
	  LockOn.Release()

	The marker is a reticle on a ScreenGui (no Highlight: one per character
	is the rule), moved to the mob each frame only when it has moved; its spin
	and pulse are looped tweens. The checks that let go run at 8 Hz, and mobs
	are found in Workspace.Mobs only.
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local LockOn = {}

local player = Players.LocalPlayer

local PICK_RADIUS = 160   -- pixels: how far from the cursor a mob may be to lock on
local PICK_RANGE = 90     -- studs from you: the farthest mob that can be locked
local HOLD_RANGE = 110    -- studs: past this the lock lets go
local CHECK_EVERY = 0.125 -- seconds between checks that let go
local COLOR = Color3.fromRGB(255, 70, 70)

local target: BasePart? = nil
local targetHum: Humanoid? = nil
local marker: ScreenGui? = nil
local reticle: Frame? = nil
local markerSize = 5 -- studs across: the mob's footprint
local lastPos, lastPx = Vector2.new(-1, -1), -1
local spin: Tween? = nil
local pulse: Tween? = nil
local diedConn: RBXScriptConnection? = nil

local function myRoot(): BasePart?
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

local function alive(m: Instance): (BasePart?, Humanoid?)
	local root = m:FindFirstChild("HumanoidRootPart")
	local hum = m:FindFirstChildOfClass("Humanoid")
	if not root or not root:IsA("BasePart") or not hum or hum.Health <= 0 then return nil, nil end
	return root, hum
end

-- ─── the marker ──────────────────────────────────────────────────────────────
local function corner(parent: Instance, ax: number, ay: number)
	-- an L of two bars in one corner of the box
	local t = 0.14
	local len = 0.34
	local h = Instance.new("Frame")
	h.BorderSizePixel = 0
	h.BackgroundColor3 = COLOR
	h.AnchorPoint = Vector2.new(ax, ay)
	h.Position = UDim2.fromScale(ax, ay)
	h.Size = UDim2.fromScale(len, t)
	h.Parent = parent
	local v = h:Clone()
	v.Size = UDim2.fromScale(t, len)
	v.Parent = parent
	for _, f in ipairs({ h, v }) do
		local s = Instance.new("UIStroke")
		s.Color = Color3.new(0, 0, 0)
		s.Thickness = 1.5
		s.Transparency = 0.3
		s.Parent = f
	end
end

local function buildMarker(root: BasePart): ScreenGui
	local model = root.Parent
	markerSize = 5
	if model and model:IsA("Model") then
		local ext = model:GetExtentsSize()
		markerSize = math.clamp(math.max(ext.X, ext.Y * 0.6, ext.Z) * 1.1, 4.5, 24)
	end
	lastPos, lastPx = Vector2.new(-1, -1), -1
	local gui = Instance.new("ScreenGui")
	gui.Name = "LockOnMarker"
	gui.IgnoreGuiInset = true -- (viewport pixels, as the camera projects)
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 5
	local box = Instance.new("Frame")
	box.Name = "Reticle"
	box.BackgroundTransparency = 1
	box.AnchorPoint = Vector2.new(0.5, 0.5)
	box.Visible = false
	box.Parent = gui
	reticle = box

	-- the reticle: four corner brackets, turning, and pulsing in size
	local holder = Instance.new("Frame")
	holder.BackgroundTransparency = 1
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, 0.5)
	holder.Size = UDim2.fromScale(0.8, 0.8)
	holder.Parent = box
	-- (a CanvasGroup: a plain Frame's Rotation doesn't turn its children)
	local ring = Instance.new("CanvasGroup")
	ring.Name = "Ring"
	ring.BackgroundTransparency = 1
	ring.Size = UDim2.fromScale(1, 1)
	ring.Parent = holder
	corner(ring, 0, 0); corner(ring, 1, 0); corner(ring, 0, 1); corner(ring, 1, 1)

	-- a dot in the middle
	local dot = Instance.new("Frame")
	dot.BorderSizePixel = 0
	dot.BackgroundColor3 = COLOR
	dot.AnchorPoint = Vector2.new(0.5, 0.5)
	dot.Position = UDim2.fromScale(0.5, 0.5)
	dot.Size = UDim2.fromScale(0.09, 0.09)
	dot.Parent = holder
	local round = Instance.new("UICorner")
	round.CornerRadius = UDim.new(1, 0)
	round.Parent = dot
	local ds = Instance.new("UIStroke")
	ds.Color = Color3.new(0, 0, 0)
	ds.Thickness = 1.5
	ds.Parent = dot

	-- a chevron over the head, so the mob reads as locked even in a crowd
	local chev = Instance.new("TextLabel")
	chev.BackgroundTransparency = 1
	chev.AnchorPoint = Vector2.new(0.5, 1)
	chev.Position = UDim2.fromScale(0.5, -0.02)
	chev.Size = UDim2.fromScale(0.5, 0.3)
	chev.Text = "▼"
	chev.TextScaled = true
	chev.TextColor3 = COLOR
	chev.TextStrokeTransparency = 0.2
	chev.Font = Enum.Font.GothamBlack
	chev.Parent = box

	gui.Parent = player:WaitForChild("PlayerGui")

	spin = TweenService:Create(ring, TweenInfo.new(2.4, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1), { Rotation = 360 })
	pulse = TweenService:Create(holder, TweenInfo.new(0.45, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), { Size = UDim2.fromScale(0.95, 0.95) })
	;(spin :: Tween):Play()
	;(pulse :: Tween):Play()
	return gui
end

-- (each frame: the reticle over the mob, sized to it at its distance; written
-- only when it has moved)
RunService:BindToRenderStep("LockOnMarker", Enum.RenderPriority.Camera.Value + 2, function()
	local box, t = reticle, target
	local cam = Workspace.CurrentCamera
	if not box or not t or not cam then return end
	local v = cam:WorldToViewportPoint(t.Position)
	if v.Z <= 0 then
		if box.Visible then box.Visible = false end
		return
	end
	-- pixels per stud at that depth
	local ppsd = cam.ViewportSize.Y / (2 * v.Z * math.tan(math.rad(cam.FieldOfView) / 2))
	local px = math.clamp(math.floor(markerSize * ppsd + 0.5), 44, 260)
	local pos = Vector2.new(math.floor(v.X + 0.5), math.floor(v.Y + 0.5))
	if pos ~= lastPos then
		lastPos = pos
		box.Position = UDim2.fromOffset(pos.X, pos.Y)
	end
	if px ~= lastPx then
		lastPx = px
		box.Size = UDim2.fromOffset(px, px)
	end
	if not box.Visible then box.Visible = true end
end)

local function clearMarker()
	if spin then spin:Cancel(); spin = nil end
	if pulse then pulse:Cancel(); pulse = nil end
	if marker then marker:Destroy(); marker = nil end
	reticle = nil
end

-- ─── locking ─────────────────────────────────────────────────────────────────
function LockOn.Release()
	target, targetHum = nil, nil
	if diedConn then diedConn:Disconnect(); diedConn = nil end
	clearMarker()
	player:SetAttribute("LockOnTarget", nil)
end

local function lock(root: BasePart, hum: Humanoid)
	LockOn.Release()
	target, targetHum = root, hum
	diedConn = hum.Died:Connect(LockOn.Release)
	marker = buildMarker(root)
	local model = root.Parent
	player:SetAttribute("LockOnTarget", if model then model.Name else nil)
end

-- The living mob nearest `screen` on the screen, within reach of you.
local function pick(screen: Vector2): (BasePart?, Humanoid?)
	local mobs = Workspace:FindFirstChild("Mobs")
	local cam = Workspace.CurrentCamera
	local me = myRoot()
	if not mobs or not cam or not me then return nil, nil end
	local best: BasePart?, bestHum: Humanoid?, bestD = nil, nil, PICK_RADIUS
	for _, m in ipairs(mobs:GetChildren()) do
		local root, hum = alive(m)
		if not root then continue end
		if (root.Position - me.Position).Magnitude > PICK_RANGE then continue end
		local v, onScreen = cam:WorldToViewportPoint(root.Position)
		if not onScreen then continue end
		local d = (Vector2.new(v.X, v.Y) - screen).Magnitude
		if d < bestD then best, bestHum, bestD = root, hum, d end
	end
	return best, bestHum
end

-- Lock on to the mob nearest `screen`, or let go if already locked.
function LockOn.Toggle(screen: Vector2)
	if target then LockOn.Release(); return end
	if player:GetAttribute("SettingsOpen") == true or player:GetAttribute("DeathMenuOpen") == true then return end
	local root, hum = pick(screen)
	if root and hum then lock(root, hum) end
end

function LockOn.Target(): BasePart?
	return target
end

function LockOn.Point(): Vector3?
	local t = target
	if t and t.Parent then return t.Position end
	return nil
end

UserInputService.InputBegan:Connect(function(input, gameProcessed)
	if input.UserInputType == Enum.UserInputType.MouseButton3 then
		if gameProcessed then return end
		LockOn.Toggle(UserInputService:GetMouseLocation())
	end
	-- (a controller's right stick click: AimInput, from its aim point)
end)

-- (letting go: the mob gone, dead or too far, or you gone)
local acc = 0
RunService.Heartbeat:Connect(function(dt)
	if not target then return end
	acc += dt
	if acc < CHECK_EVERY then return end
	acc = 0
	local t, hum = target, targetHum
	local me = myRoot()
	local mobs = Workspace:FindFirstChild("Mobs")
	if not me or not t or not hum or hum.Health <= 0 or not mobs or not t:IsDescendantOf(mobs)
		or (t.Position - me.Position).Magnitude > HOLD_RANGE
		or player:GetAttribute("InLobby") == true then
		LockOn.Release()
	end
end)

return LockOn
