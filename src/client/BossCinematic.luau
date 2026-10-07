--!strict
--[[
	BossCinematic.luau
	The boss fights' big moments, on every client in the run (BossAI):

	  BossIntro   the boss arrives: letterbox bars, the camera leaves you,
	              sweeps in on the boss (the Fallen Angel coming down out of
	              the sky), its name slams onto the screen with a shake, and
	              the camera comes back to you. The boss can't act or be hurt
	              meanwhile.
	  BossFX      { kind = "signature" } a signature move: the boss turns
	              INVULNERABLE (a golden barrier, server-side) and its name
	              flashes up.
	              { kind = "judgement", phase = "pillars"|"charge"|"strike" }
	              the Fallen Angel's JUDGEMENT: pillars fall from the sky,
	              "HIDE BEHIND A PILLAR!" with a countdown while the void
	              gathers, then a white flash as it strikes.

	All of these are warnings the player must see, so none are budgeted.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local Network = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Network"))

local player = Players.LocalPlayer
local IsometricCamera: any = nil
pcall(function() IsometricCamera = require(script.Parent:WaitForChild("IsometricCamera")) end)

local BossCinematic = {}

local GOLD = Color3.fromRGB(255, 215, 110)

local function tween(obj: Instance, t: number, props: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?)
	local tw = TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props)
	tw:Play()
	return tw
end

local function myRoot(): BasePart?
	local char = player.Character
	return char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
end

local function screen(name: string, order: number): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = name
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = order
	gui.Parent = player:WaitForChild("PlayerGui")
	return gui
end

-- ── Camera shake (on top of whatever camera is running) ─────────────────────
local shakePower, shakeUntil = 0, 0
local function shake(power: number, duration: number)
	if power > shakePower or os.clock() > shakeUntil then shakePower = power end
	shakeUntil = math.max(shakeUntil, os.clock() + duration)
end

-- ── Text: a small line over a big one, with a brass rule ────────────────────
local function title(small: string, big: string, color: Color3, hold: number, y: number?)
	local gui = screen("BossTitle", 145)
	local holder = Instance.new("Frame")
	holder.AnchorPoint = Vector2.new(0.5, 0.5)
	holder.Position = UDim2.fromScale(0.5, y or 0.3)
	holder.Size = UDim2.fromOffset(1000, 150)
	holder.BackgroundTransparency = 1
	holder.Parent = gui
	local top = Instance.new("TextLabel")
	top.BackgroundTransparency = 1
	top.Size = UDim2.new(1, 0, 0, 28)
	top.Font = Enum.Font.GothamBold
	top.TextSize = 22
	top.TextColor3 = Color3.fromRGB(235, 220, 200)
	top.TextStrokeTransparency = 0.4
	top.Text = small
	top.Parent = holder
	local big1 = Instance.new("TextLabel")
	big1.BackgroundTransparency = 1
	big1.Position = UDim2.fromOffset(0, 30)
	big1.Size = UDim2.new(1, 0, 0, 84)
	big1.Font = Enum.Font.GothamBlack
	big1.TextScaled = true
	big1.TextColor3 = color
	big1.TextStrokeColor3 = Color3.fromRGB(20, 6, 20)
	big1.TextStrokeTransparency = 0.15
	big1.Text = big
	big1.Parent = holder
	local rule = Instance.new("Frame")
	rule.AnchorPoint = Vector2.new(0.5, 0)
	rule.Position = UDim2.new(0.5, 0, 0, 120)
	rule.Size = UDim2.fromOffset(0, 3)
	rule.BackgroundColor3 = color
	rule.BorderSizePixel = 0
	rule.Parent = holder
	local scale = Instance.new("UIScale")
	scale.Scale = 1.6
	scale.Parent = holder
	top.TextTransparency, big1.TextTransparency = 1, 1
	tween(scale, 0.35, { Scale = 1 }, Enum.EasingStyle.Back)
	tween(top, 0.3, { TextTransparency = 0 })
	tween(big1, 0.25, { TextTransparency = 0 })
	tween(rule, 0.6, { Size = UDim2.fromOffset(560, 3) }, Enum.EasingStyle.Quart)
	task.delay(hold, function()
		tween(top, 0.5, { TextTransparency = 1, TextStrokeTransparency = 1 })
		tween(big1, 0.5, { TextTransparency = 1, TextStrokeTransparency = 1 })
		tween(rule, 0.5, { BackgroundTransparency = 1 })
		Debris:AddItem(gui, 0.6)
	end)
end

-- A full-screen colour wash (flash or tint).
local function wash(color: Color3, from: number, to: number, t: number, life: number?)
	local gui = screen("BossWash", 135)
	local f = Instance.new("Frame")
	f.Size = UDim2.fromScale(1, 1)
	f.BackgroundColor3 = color
	f.BackgroundTransparency = from
	f.BorderSizePixel = 0
	f.Parent = gui
	tween(f, t, { BackgroundTransparency = to })
	Debris:AddItem(gui, life or t + 0.05)
	return f
end

-- ── The intro ───────────────────────────────────────────────────────────────
local SUBTITLES: { [string]: string } = {
	fallen_angel = "CAST OUT OF HEAVEN",
	warlord = "WARLORD OF IRON",
	colossus = "ANCIENT TITAN",
	witch = "MISTRESS OF HEXES",
}
local playingIntro = false

local function bossFocus(model: Instance?, fallback: Vector3): Vector3
	local root = model and model:IsA("Model") and (model:FindFirstChild("HumanoidRootPart") :: BasePart?)
	return if root and root.Parent then root.Position else fallback
end

local function onIntro(data: any)
	if typeof(data) ~= "table" then return end
	local pos: Vector3 = if typeof(data.pos) == "Vector3" then data.pos else Vector3.zero
	local color: Color3 = if typeof(data.color) == "Color3" then data.color else GOLD
	local duration: number = if typeof(data.duration) == "number" then data.duration else 3.6
	local name: string = if typeof(data.name) == "string" then data.name else "BOSS"
	local model: Instance? = if typeof(data.model) == "Instance" then data.model else nil

	-- Only for the ones in the fight (alive, nearby, not already in a cutscene).
	local root = myRoot()
	local watching = root ~= nil and (root.Position - pos).Magnitude < 160 and player:GetAttribute("IsDead") ~= true
		and not playingIntro and not (IsometricCamera and IsometricCamera.IsPaused and IsometricCamera.IsPaused())
	-- (the name card shows for everyone in the run)
	task.delay(if watching then duration * 0.42 else 0, function()
		title(SUBTITLES[data.kind] or "BOSS ENCOUNTER", string.upper((name:gsub("^★%s*", ""))), color, if watching then duration * 0.5 else 3)
		shake(1.6, 0.45)
		wash(Color3.new(1, 1, 1), 0.45, 1, 0.4)
	end)
	if not watching or not root then return end
	playingIntro = true

	-- Letterbox.
	local bars = screen("BossLetterbox", 130)
	local topBar = Instance.new("Frame")
	topBar.BackgroundColor3 = Color3.new(0, 0, 0)
	topBar.BorderSizePixel = 0
	topBar.Size = UDim2.new(1, 0, 0, 0)
	topBar.Parent = bars
	local botBar = topBar:Clone()
	botBar.AnchorPoint = Vector2.new(0, 1)
	botBar.Position = UDim2.fromScale(0, 1)
	botBar.Parent = bars
	tween(topBar, 0.4, { Size = UDim2.new(1, 0, 0.12, 0) })
	tween(botBar, 0.4, { Size = UDim2.new(1, 0, 0.12, 0) })
	-- A darkening round the edges, tinted the boss's colour.
	local tint = wash(color:Lerp(Color3.new(0, 0, 0), 0.75), 1, 0.7, 0.5, duration + 2)

	local cam = Workspace.CurrentCamera
	local paused = false
	if IsometricCamera and IsometricCamera.Pause then
		IsometricCamera.Pause()
		paused = true
	end
	local savedType = cam.CameraType
	cam.CameraType = Enum.CameraType.Scriptable

	-- The shot: from the player's side of the arena, low and wide, sweeping
	-- round and pushing in on the boss's face as it lands / rises.
	local away = Vector3.new(root.Position.X - pos.X, 0, root.Position.Z - pos.Z)
	away = if away.Magnitude > 1 then away.Unit else Vector3.new(0, 0, -1)
	local right = away:Cross(Vector3.yAxis)
	local t0 = os.clock()
	local conn = RunService.RenderStepped:Connect(function()
		local a = math.clamp((os.clock() - t0) / duration, 0, 1)
		local k = 1 - (1 - a) ^ 3
		local focus = bossFocus(model, pos) + Vector3.new(0, 3, 0)
		local swing = (1 - k) * 0.9 - 0.25
		local dist = 34 - 20 * k
		local height = 3 + 9 * (1 - k)
		local dirFrom = (away * math.cos(swing) + right * math.sin(swing)).Unit
		local camPos = focus + dirFrom * dist + Vector3.new(0, height, 0)
		local cf = CFrame.lookAt(camPos, focus)
		if os.clock() < shakeUntil then
			local p = shakePower
			cf *= CFrame.new((math.random() - 0.5) * p, (math.random() - 0.5) * p * 0.6, 0)
		end
		cam.CFrame = cf
		cam.FieldOfView = 60 - 10 * k
	end)

	task.delay(duration, function()
		conn:Disconnect()
		tween(topBar, 0.5, { Size = UDim2.new(1, 0, 0, 0) })
		tween(botBar, 0.5, { Size = UDim2.new(1, 0, 0, 0) })
		tween(tint, 0.6, { BackgroundTransparency = 1 })
		Debris:AddItem(bars, 0.6)
		if paused and IsometricCamera.Resume then
			IsometricCamera.Resume(0.7)
		else
			cam.CameraType = savedType
		end
		playingIntro = false
	end)
end

-- ── Signature moves and JUDGEMENT ───────────────────────────────────────────
local hideGui: ScreenGui? = nil

local function stopHide()
	if hideGui then
		hideGui:Destroy()
		hideGui = nil
	end
end

local function showHide(duration: number, color: Color3)
	stopHide()
	local gui = screen("BossHideWarning", 146)
	hideGui = gui
	-- The edges darken in the void's colour while it gathers.
	local vignette = Instance.new("Frame")
	vignette.Size = UDim2.fromScale(1, 1)
	vignette.BackgroundColor3 = color:Lerp(Color3.new(0, 0, 0), 0.6)
	vignette.BackgroundTransparency = 1
	vignette.BorderSizePixel = 0
	vignette.Parent = gui
	local g = Instance.new("UIGradient")
	g.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(0.3, 1),
		NumberSequenceKeypoint.new(0.7, 1), NumberSequenceKeypoint.new(1, 0),
	})
	g.Parent = vignette
	tween(vignette, duration, { BackgroundTransparency = 0.1 }, Enum.EasingStyle.Linear)
	local label = Instance.new("TextLabel")
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.2)
	label.Size = UDim2.fromOffset(900, 70)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 235, 200)
	label.TextStrokeColor3 = Color3.fromRGB(60, 0, 40)
	label.TextStrokeTransparency = 0.1
	label.Text = "HIDE BEHIND A PILLAR!"
	label.Parent = gui
	local sub = Instance.new("TextLabel")
	sub.AnchorPoint = Vector2.new(0.5, 0)
	sub.Position = UDim2.new(0.5, 0, 0.2, 40)
	sub.Size = UDim2.fromOffset(700, 26)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.GothamBold
	sub.TextSize = 20
	sub.TextColor3 = Color3.fromRGB(230, 210, 255)
	sub.TextStrokeTransparency = 0.3
	sub.Text = "Put stone between you and the angel"
	sub.Parent = gui
	local back = Instance.new("Frame")
	back.AnchorPoint = Vector2.new(0.5, 0)
	back.Position = UDim2.new(0.5, 0, 0.2, 74)
	back.Size = UDim2.fromOffset(420, 10)
	back.BackgroundColor3 = Color3.fromRGB(25, 12, 30)
	back.BorderSizePixel = 0
	back.Parent = gui
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = color
	fill.BorderSizePixel = 0
	fill.Parent = back
	tween(fill, duration, { Size = UDim2.fromScale(0, 1) }, Enum.EasingStyle.Linear)
	local t0 = os.clock()
	local conn: RBXScriptConnection
	conn = RunService.Heartbeat:Connect(function()
		if not gui.Parent then conn:Disconnect() return end
		-- (it pulses faster as the end nears)
		local left = math.max(0, duration - (os.clock() - t0))
		local rate = 3 + (1 - left / duration) * 9
		label.TextTransparency = 0.25 * (0.5 + 0.5 * math.sin(os.clock() * rate))
	end)
	shake(0.25, duration)
end

local function onFX(data: any)
	if typeof(data) ~= "table" then return end
	local color: Color3 = if typeof(data.color) == "Color3" then data.color else GOLD
	if data.kind == "signature" then
		title("SIGNATURE MOVE  ·  INVULNERABLE", tostring(data.name or ""), GOLD, 1.8, 0.22)
		shake(0.6, 0.3)
	elseif data.kind == "judgement" then
		if data.phase == "pillars" then
			title("THE HEAVENS FALL", "PILLARS FROM THE SKY", Color3.fromRGB(230, 220, 245), 1.6, 0.22)
			shake(0.9, 1.6)
		elseif data.phase == "charge" then
			showHide(if typeof(data.duration) == "number" then data.duration else 3, color)
		elseif data.phase == "strike" then
			stopHide()
			wash(Color3.new(1, 1, 1), 0.05, 1, 0.7)
			shake(2.2, 0.6)
		end
	end
end

function BossCinematic.Init()
	Network.GetRemoteEvent(Network.Remotes.BossIntro).OnClientEvent:Connect(onIntro)
	Network.GetRemoteEvent(Network.Remotes.BossFX).OnClientEvent:Connect(onFX)
	-- Shake on the normal camera (the intro shot shakes itself).
	RunService:BindToRenderStep("BossCinematicShake", Enum.RenderPriority.Camera.Value + 2, function()
		if playingIntro or os.clock() >= shakeUntil then return end
		local cam = Workspace.CurrentCamera
		local a = shakePower
		cam.CFrame *= CFrame.new((math.random() - 0.5) * a, (math.random() - 0.5) * a * 0.6, 0)
	end)
	-- Died or left mid-warning: clear it.
	player.CharacterAdded:Connect(stopHide)
end

return BossCinematic
