--[[
	SummonAnnouncer.luau
	Lobby flex: when someone else in the server wishes a Legendary or better
	(GachaManager → SummonAnnounce), everyone sees a banner slide down — who,
	what, how rare — and, if that player's character is around, a column of
	starlight coming down on them for a few seconds.

	SummonAnnouncer.Init()
--]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))
local GachaConfig = require(Shared:WaitForChild("GachaConfig"))
local GachaRewards = require(Shared:WaitForChild("GachaRewards"))

local player = Players.LocalPlayer

local SummonAnnouncer = {}

local gui: ScreenGui? = nil
local queue: { any } = {}
local showing = false

local function ensureGui(): ScreenGui
	if gui and gui.Parent then return gui end
	local g = Instance.new("ScreenGui")
	g.Name = "SummonAnnouncer"
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.DisplayOrder = 180
	g.Parent = player:WaitForChild("PlayerGui")
	gui = g
	return g
end

-- A column of starlight on the lucky player.
local function beam(userId: number, color: Color3)
	local who = Players:GetPlayerByUserId(userId)
	local root = who and who.Character and who.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then return end
	local function part(props: { [string]: any }): BasePart
		local p = Instance.new("Part")
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
		p.Material = Enum.Material.Neon
		p.Shape = Enum.PartType.Cylinder
		for k, v in pairs(props) do (p :: any)[k] = v end
		p.Parent = Workspace.Terrain
		Debris:AddItem(p, 7)
		return p
	end
	local top = root.Position + Vector3.new(0, 60, 0)
	local cf = CFrame.new((top + root.Position) / 2 + Vector3.new(0, -2, 0)) * CFrame.Angles(0, 0, math.rad(90))
	local core = part({ Size = Vector3.new(64, 0.2, 0.2), CFrame = cf, Color = Color3.fromRGB(255, 250, 235), Transparency = 0.1 })
	local glow = part({ Size = Vector3.new(64, 0.2, 0.2), CFrame = cf, Color = color, Transparency = 0.6 })
	TweenService:Create(core, TweenInfo.new(0.3, Enum.EasingStyle.Back), { Size = Vector3.new(64, 1.6, 1.6) }):Play()
	TweenService:Create(glow, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Size = Vector3.new(64, 5, 5) }):Play()
	local att = Instance.new("Attachment")
	att.Parent = core
	local pe = Instance.new("ParticleEmitter")
	pe.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	pe.Color = ColorSequence.new(Color3.new(1, 1, 1), color)
	pe.LightEmission, pe.LightInfluence = 1, 0
	pe.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0) })
	pe.Lifetime = NumberRange.new(1, 2)
	pe.Speed = NumberRange.new(2, 5)
	pe.SpreadAngle = Vector2.new(180, 180)
	pe.Rate = 40
	pe.Parent = att
	task.delay(5, function()
		pe.Enabled = false
		TweenService:Create(core, TweenInfo.new(1), { Size = Vector3.new(64, 0, 0), Transparency = 1 }):Play()
		TweenService:Create(glow, TweenInfo.new(1), { Size = Vector3.new(64, 0, 0), Transparency = 1 }):Play()
	end)
end

local function show(info: any)
	local reward = GachaRewards.Get(info.id)
	if not reward then return end
	local color = GachaConfig.Rarities[info.rarity] and GachaConfig.Rarities[info.rarity].color or Color3.new(1, 1, 1)
	local g = ensureGui()
	local card = Instance.new("Frame")
	card.AnchorPoint = Vector2.new(0.5, 0)
	card.Position = UDim2.new(0.5, 0, 0, -90)
	card.Size = UDim2.fromOffset(520, 70)
	card.BackgroundColor3 = Color3.fromRGB(14, 14, 28)
	card.BackgroundTransparency = 0.1
	card.BorderSizePixel = 0
	card.Parent = g
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = card
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Thickness = 2
	stroke.Parent = card
	local function line(str: string, y: number, size: number, col: Color3, font: Enum.Font)
		local t = Instance.new("TextLabel")
		t.BackgroundTransparency = 1
		t.Position = UDim2.fromOffset(0, y)
		t.Size = UDim2.new(1, 0, 0, size + 6)
		t.Font = font
		t.TextSize = size
		t.TextColor3 = col
		t.TextStrokeTransparency = 0.4
		t.Text = str
		t.Parent = card
	end
	line(`✦ {string.upper(info.name or "Someone")} WISHED UPON A STAR ✦`, 8, 14, Color3.fromRGB(220, 225, 255), Enum.Font.GothamBold)
	line(`{reward.glyph}  {string.upper(reward.name)}  ·  {string.upper(info.rarity)}`, 32, 22, color, Enum.Font.Antique)
	TweenService:Create(card, TweenInfo.new(0.5, Enum.EasingStyle.Back), { Position = UDim2.new(0.5, 0, 0, 72) }):Play()
	beam(info.userId, color)
	task.wait(4.5)
	TweenService:Create(card, TweenInfo.new(0.4), { Position = UDim2.new(0.5, 0, 0, -90) }):Play()
	task.wait(0.45)
	card:Destroy()
end

function SummonAnnouncer.Init()
	Network.GetRemoteEvent(Network.Remotes.SummonAnnounce).OnClientEvent:Connect(function(info: any)
		-- (your own wish has its own moment)
		if typeof(info) ~= "table" or info.userId == player.UserId then return end
		table.insert(queue, info)
		if showing then return end
		showing = true
		task.spawn(function()
			while #queue > 0 do
				show(table.remove(queue, 1))
			end
			showing = false
		end)
	end)
end

return SummonAnnouncer
