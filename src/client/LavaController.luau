--!strict
--[[
	LavaController.luau
	Stuck in a boss arena's lava (Hazards: the character's "LavaStuck"):
	  • you: a quick-time sequence of five movement keys (W A S D, or the
	    arrows) to press in order; a wrong one starts it over; beaten, you're
	    out (LavaEscape)
	  • a teammate within HELP_RANGE: a bubble over you and a prompt at the
	    bottom of their screen, PRESS E TO HELP; their E pulls you out
	    (LavaHelp; "HelpReady" keeps that E from casting their skill)
	  • everyone: the stuck one flails, arms up (their shoulders, each frame)
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Network = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Network"))

local LavaController = {}

local player = Players.LocalPlayer
local HELP_RANGE = 12
local KEYS = { "W", "A", "S", "D" }
local ARROWS: { [string]: string } = { Up = "W", Left = "A", Down = "S", Right = "D" }
local GOLD = Color3.fromRGB(255, 214, 110)
local INK = Color3.fromRGB(24, 18, 16)

local gui: ScreenGui? = nil
local caps: { TextLabel } = {}
local seq: { string } = {}
local progress = 0
local helpTarget: Player? = nil

local function label(parent: Instance, text: string, size: number, color: Color3): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = Enum.Font.Arcade
	l.Text = text
	l.TextSize = size
	l.TextColor3 = color
	l.Parent = parent
	return l
end

local function build()
	local g = Instance.new("ScreenGui")
	g.Name = "LavaQTE"
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.DisplayOrder = 70
	g.Enabled = false
	g.Parent = player:WaitForChild("PlayerGui")
	gui = g
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 1)
	f.Position = UDim2.new(0.5, 0, 1, -170)
	f.Size = UDim2.fromOffset(420, 120)
	f.BackgroundColor3 = INK
	f.BackgroundTransparency = 0.15
	f.Parent = g
	Instance.new("UICorner").Parent = f
	local st = Instance.new("UIStroke")
	st.Color = Color3.fromRGB(255, 110, 30)
	st.Thickness = 2
	st.Parent = f
	local t = label(f, "STUCK IN LAVA!", 24, Color3.fromRGB(255, 140, 50))
	t.Size = UDim2.new(1, 0, 0, 34)
	local sub = label(f, "Press the keys in order (or a friend can pull you out)", 12, Color3.fromRGB(230, 220, 200))
	sub.Position = UDim2.fromOffset(0, 92)
	sub.Size = UDim2.new(1, 0, 0, 20)
	for i = 1, 5 do
		local c = label(f, "", 26, Color3.new(1, 1, 1))
		c.BackgroundTransparency = 0
		c.BackgroundColor3 = Color3.fromRGB(50, 40, 40)
		c.Size = UDim2.fromOffset(52, 46)
		c.Position = UDim2.new(0.5, (i - 3) * 64 - 26, 0, 40)
		Instance.new("UICorner").Parent = c
		caps[i] = c
	end
end

local function render()
	for i, c in ipairs(caps) do
		c.Text = seq[i] or ""
		c.BackgroundColor3 = if i <= progress then Color3.fromRGB(70, 160, 70)
			elseif i == progress + 1 then GOLD else Color3.fromRGB(50, 40, 40)
		c.TextColor3 = if i == progress + 1 then INK else Color3.new(1, 1, 1)
	end
end

local function startQTE()
	table.clear(seq)
	for i = 1, 5 do seq[i] = KEYS[math.random(1, 4)] end
	progress = 0
	render()
	if gui then gui.Enabled = true end
end

local function stuckMe(): boolean
	local c = player.Character
	return c ~= nil and c:GetAttribute("LavaStuck") == true
end

-- The help prompt: a bubble over the stuck teammate, a line at the bottom.
local bubble: BillboardGui? = nil
local helpGui: ScreenGui? = nil
local function buildHelp()
	local b = Instance.new("BillboardGui")
	b.Name = "LavaHelpBubble"
	b.Size = UDim2.fromOffset(120, 44)
	b.StudsOffset = Vector3.new(0, 4, 0)
	b.AlwaysOnTop = true
	b.Enabled = false
	b.Parent = player:WaitForChild("PlayerGui")
	local l = label(b, "[E] HELP!", 22, INK)
	l.Size = UDim2.fromScale(1, 1)
	l.BackgroundTransparency = 0
	l.BackgroundColor3 = Color3.fromRGB(250, 246, 236)
	Instance.new("UICorner").Parent = l
	bubble = b
	local g = Instance.new("ScreenGui")
	g.Name = "LavaHelpPrompt"
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.DisplayOrder = 60
	g.Enabled = false
	g.Parent = player:WaitForChild("PlayerGui")
	local p = label(g, "PRESS E TO PULL THEM OUT", 20, Color3.new(1, 1, 1))
	p.AnchorPoint = Vector2.new(0.5, 1)
	p.Position = UDim2.new(0.5, 0, 1, -150)
	p.Size = UDim2.fromOffset(360, 48)
	p.BackgroundTransparency = 0.25
	p.BackgroundColor3 = INK
	Instance.new("UICorner").Parent = p
	local s = Instance.new("UIStroke")
	s.Color = GOLD
	s.Parent = p
	helpGui = g
end

function LavaController.Init()
	build()
	buildHelp()
	UserInputService.InputBegan:Connect(function(input, gpe)
		if gpe or input.UserInputType ~= Enum.UserInputType.Keyboard then return end
		local name = input.KeyCode.Name
		if stuckMe() and #seq == 5 then
			local key = ARROWS[name] or (if table.find(KEYS, name) then name else nil)
			if not key then return end
			if key == seq[progress + 1] then
				progress += 1
				if progress >= 5 then
					Network.GetRemoteEvent(Network.Remotes.LavaEscape):FireServer()
					table.clear(seq)
				end
			else
				progress = 0 -- (wrong: start over)
			end
			render()
		elseif helpTarget and input.KeyCode == Enum.KeyCode.E then
			Network.GetRemoteEvent(Network.Remotes.LavaHelp):FireServer(helpTarget.UserId)
		end
	end)
	-- the QTE, the help prompt, and the flailing
	local wasStuck = false
	RunService.Stepped:Connect(function()
		local now = stuckMe()
		if now and not wasStuck then startQTE() end
		if not now and wasStuck and gui then gui.Enabled = false; table.clear(seq) end
		wasStuck = now
		-- a stuck teammate nearby?
		local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		local best: Player? = nil
		local t = os.clock()
		for _, p in ipairs(Players:GetPlayers()) do
			local c = p.Character
			if c and c:GetAttribute("LavaStuck") == true then
				-- flailing arms (R6 shoulders turn about their Z)
				local rs = c:FindFirstChild("Right Shoulder", true) :: Motor6D?
				local ls = c:FindFirstChild("Left Shoulder", true) :: Motor6D?
				if rs then rs.Transform = CFrame.Angles(0, 0, 2.3 + math.sin(t * 14) * 0.6) end
				if ls then ls.Transform = CFrame.Angles(0, 0, -(2.3 + math.sin(t * 14 + math.pi) * 0.6)) end
				local r = c:FindFirstChild("HumanoidRootPart") :: BasePart?
				if p ~= player and root and r and not now and (r.Position - root.Position).Magnitude <= HELP_RANGE then best = p end
			end
		end
		helpTarget = best
		player:SetAttribute("HelpReady", if best then true else nil)
		if bubble then
			bubble.Enabled = best ~= nil
			bubble.Adornee = if best and best.Character then best.Character:FindFirstChild("Head") :: BasePart? else nil
		end
		if helpGui then helpGui.Enabled = best ~= nil end
	end)
end

return LavaController
