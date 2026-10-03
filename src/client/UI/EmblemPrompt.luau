--!strict
-- EmblemPrompt.luau
-- When you're near a room reward that's ready (the server marks it
-- "Charged"), a speech bubble pops up in front of your character and a prompt
-- at the bottom of the screen shows a mouse with its left button lit:
-- "LEFT CLICK TO INTERACT", in the arcade font. Both go away once it's
-- claimed or you walk off.

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

local EmblemPrompt = {}

local RANGE = 16
local WHITE = Color3.fromRGB(250, 246, 236)
local INK = Color3.fromRGB(24, 18, 16)
local GOLD = Color3.fromRGB(255, 214, 110)

-- A little mouse drawn from frames, left button lit.
local function mouseIcon(parent: Instance, height: number, lit: Color3): Frame
	local w = math.floor(height * 0.72)
	local body = Instance.new("Frame")
	body.Name = "Mouse"
	body.Size = UDim2.fromOffset(w, height)
	body.BackgroundColor3 = INK
	body.BorderSizePixel = 0
	body.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.45, 0)
	corner.Parent = body
	local stroke = Instance.new("UIStroke")
	stroke.Color = WHITE
	stroke.Thickness = 2
	stroke.Parent = body
	-- Left button (top-left quarter), lit.
	local left = Instance.new("Frame")
	left.Size = UDim2.new(0.5, -2, 0.42, 0)
	left.Position = UDim2.fromOffset(2, 2)
	left.BackgroundColor3 = lit
	left.BorderSizePixel = 0
	left.Parent = body
	local lc = Instance.new("UICorner")
	lc.CornerRadius = UDim.new(0.6, 0)
	lc.Parent = left
	-- Divider and button line.
	local split = Instance.new("Frame")
	split.AnchorPoint = Vector2.new(0.5, 0)
	split.Position = UDim2.fromScale(0.5, 0)
	split.Size = UDim2.new(0, 2, 0.42, 0)
	split.BackgroundColor3 = WHITE
	split.BorderSizePixel = 0
	split.Parent = body
	local line = Instance.new("Frame")
	line.Position = UDim2.fromScale(0, 0.42)
	line.Size = UDim2.new(1, 0, 0, 2)
	line.BackgroundColor3 = WHITE
	line.BorderSizePixel = 0
	line.Parent = body
	return body
end

local bubble: BillboardGui
local bubbleScale: UIScale
local prompt: Frame
local promptScale: UIScale
local promptGui: ScreenGui
local shown = false

local function build()
	local playerGui = player:WaitForChild("PlayerGui")

	-- Speech bubble in front of the character.
	bubble = Instance.new("BillboardGui")
	bubble.Name = "InteractBubble"
	bubble.Size = UDim2.fromOffset(64, 60)
	bubble.StudsOffset = Vector3.new(1.6, 3.4, 0)
	bubble.AlwaysOnTop = true
	bubble.LightInfluence = 0
	bubble.Enabled = false
	bubble.Parent = playerGui
	local holder = Instance.new("Frame")
	holder.Size = UDim2.fromScale(1, 1)
	holder.BackgroundTransparency = 1
	holder.Parent = bubble
	bubbleScale = Instance.new("UIScale")
	bubbleScale.Parent = holder
	local cloud = Instance.new("Frame")
	cloud.Size = UDim2.new(1, 0, 0, 46)
	cloud.BackgroundColor3 = WHITE
	cloud.BorderSizePixel = 0
	cloud.Parent = holder
	local cc = Instance.new("UICorner")
	cc.CornerRadius = UDim.new(0, 14)
	cc.Parent = cloud
	local cs = Instance.new("UIStroke")
	cs.Color = INK
	cs.Thickness = 2
	cs.Parent = cloud
	-- Tail pointing down at the character.
	local tail = Instance.new("Frame")
	tail.AnchorPoint = Vector2.new(0.5, 0.5)
	tail.Position = UDim2.new(0, 16, 0, 46)
	tail.Size = UDim2.fromOffset(12, 12)
	tail.Rotation = 45
	tail.BackgroundColor3 = WHITE
	tail.BorderSizePixel = 0
	tail.ZIndex = 0
	tail.Parent = holder
	local ts = Instance.new("UIStroke")
	ts.Color = INK
	ts.Thickness = 2
	ts.Parent = tail
	local icon = mouseIcon(cloud, 30, GOLD)
	icon.AnchorPoint = Vector2.new(0, 0.5)
	icon.Position = UDim2.new(0, 10, 0.5, 0)
	local bang = Instance.new("TextLabel")
	bang.BackgroundTransparency = 1
	bang.AnchorPoint = Vector2.new(1, 0.5)
	bang.Position = UDim2.new(1, -8, 0.5, 0)
	bang.Size = UDim2.fromOffset(18, 30)
	bang.Font = Enum.Font.Arcade
	bang.Text = "!"
	bang.TextSize = 28
	bang.TextColor3 = INK
	bang.Parent = cloud

	-- Prompt at the bottom of the screen.
	promptGui = Instance.new("ScreenGui")
	promptGui.Name = "InteractPrompt"
	promptGui.ResetOnSpawn = false
	promptGui.IgnoreGuiInset = true
	promptGui.DisplayOrder = 60
	promptGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	promptGui.Enabled = false
	promptGui.Parent = playerGui
	prompt = Instance.new("Frame")
	prompt.AnchorPoint = Vector2.new(0.5, 1)
	prompt.Position = UDim2.new(0.5, 0, 1, -150)
	prompt.Size = UDim2.fromOffset(330, 48)
	prompt.BackgroundColor3 = INK
	prompt.BackgroundTransparency = 0.25
	prompt.BorderSizePixel = 0
	prompt.Parent = promptGui
	local pc = Instance.new("UICorner")
	pc.CornerRadius = UDim.new(0, 8)
	pc.Parent = prompt
	local ps = Instance.new("UIStroke")
	ps.Color = GOLD
	ps.Thickness = 1.5
	ps.Transparency = 0.2
	ps.Parent = prompt
	promptScale = Instance.new("UIScale")
	promptScale.Parent = prompt
	local pIcon = mouseIcon(prompt, 32, GOLD)
	pIcon.AnchorPoint = Vector2.new(0, 0.5)
	pIcon.Position = UDim2.new(0, 14, 0.5, 0)
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Position = UDim2.fromOffset(52, 0)
	label.Size = UDim2.new(1, -60, 1, 0)
	label.Font = Enum.Font.Arcade
	label.Text = "LEFT CLICK TO INTERACT"
	label.TextSize = 20
	label.TextColor3 = WHITE
	label.TextXAlignment = Enum.TextXAlignment.Left
	label.Parent = prompt
end

local function setShown(on: boolean)
	if on == shown then return end
	shown = on
	bubble.Enabled = on
	promptGui.Enabled = on
	if on then
		bubbleScale.Scale = 0.3
		TweenService:Create(bubbleScale, TweenInfo.new(0.25, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
		promptScale.Scale = 0.8
		TweenService:Create(promptScale, TweenInfo.new(0.2, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	end
end

local nearest: Model? = nil

local function readyNearby(root: BasePart): Model?
	local folder = Workspace:FindFirstChild("RoomEmblems")
	if not folder then return nil end
	local best, bestD = nil, RANGE
	for _, m in ipairs(folder:GetChildren()) do
		if m:IsA("Model") and m:GetAttribute("Charged") == true and m:GetAttribute("Claimed") ~= true then
			local orb = m.PrimaryPart
			local d = if orb then (orb.Position - root.Position).Magnitude else math.huge
			if d <= bestD then best, bestD = m, d end
		end
	end
	return best
end

function EmblemPrompt.Init()
	build()
	-- Left click while the prompt is up claims the reward (anywhere on
	-- screen; the gameplay input may have already used the click to attack).
	local UserInputService = game:GetService("UserInputService")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local Network = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Network"))
	UserInputService.InputBegan:Connect(function(input)
		if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
		if UserInputService:GetFocusedTextBox() then return end
		if nearest and nearest.Parent then
			Network.GetRemoteEvent(Network.Remotes.ClaimReward):FireServer(nearest)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(0.15)
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			local head = char and char:FindFirstChild("Head") :: BasePart?
			nearest = if root and hum and hum.Health > 0 and player:GetAttribute("InLobby") == false
				then readyNearby(root) else nil
			if nearest and head then bubble.Adornee = head end
			-- Local-only flag: the attack scripts skip clicks while it's set.
			player:SetAttribute("InteractReady", nearest ~= nil)
			setShown(nearest ~= nil)
		end
	end)
end

return EmblemPrompt
