--!strict
--[[
	PowerNameplates.luau
	Every player's POWER (their "Power" attribute: LootManager / PowerGear)
	floating over their name, in the lobby and in runs. The higher it is, the
	more it shows off:

	  < 300     plain white
	  300+      green, a thin outline
	  700+      blue, a bigger number, a soft glow
	  1200+     purple, a light sweeping across it
	  2000+     gold, the sweep, a gentle pulse, ◆ either side
	  3500+     MYTHIC: a rainbow sweep, a bigger pulse, ✦ either side

	Drawn on each player's own screen only (a BillboardGui per character, no
	parts, no lights, no Highlight: CLAUDE.md). The moving tiers are animated
	together in one loop, ~30 times a second, only for plates within range.

	  PowerNameplates.Init()
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local PowerNameplates = {}

type Tier = { min: number, color: Color3, stroke: Color3, size: number, sweep: { Color3 }?, pulse: number, mark: string? }
local TIERS: { Tier } = {
	{ min = 0, color = Color3.fromRGB(235, 235, 235), stroke = Color3.new(0, 0, 0), size = 15, pulse = 0 },
	{ min = 300, color = Color3.fromRGB(120, 235, 140), stroke = Color3.fromRGB(10, 50, 20), size = 16, pulse = 0 },
	{ min = 700, color = Color3.fromRGB(110, 190, 255), stroke = Color3.fromRGB(10, 30, 70), size = 18, pulse = 0 },
	{ min = 1200, color = Color3.fromRGB(205, 140, 255), stroke = Color3.fromRGB(40, 10, 70), size = 20, pulse = 0,
		sweep = { Color3.fromRGB(170, 90, 255), Color3.fromRGB(255, 235, 255), Color3.fromRGB(170, 90, 255) } },
	{ min = 2000, color = Color3.fromRGB(255, 210, 90), stroke = Color3.fromRGB(80, 40, 0), size = 22, pulse = 0.06, mark = "◆",
		sweep = { Color3.fromRGB(255, 170, 40), Color3.fromRGB(255, 255, 210), Color3.fromRGB(255, 170, 40) } },
	{ min = 3500, color = Color3.fromRGB(255, 255, 255), stroke = Color3.fromRGB(40, 0, 50), size = 25, pulse = 0.1, mark = "✦",
		sweep = { Color3.fromRGB(255, 80, 80), Color3.fromRGB(255, 220, 60), Color3.fromRGB(80, 255, 140),
			Color3.fromRGB(80, 170, 255), Color3.fromRGB(220, 90, 255), Color3.fromRGB(255, 80, 80) } },
}

local function tierOf(power: number): Tier
	local t = TIERS[1]
	for _, tier in ipairs(TIERS) do
		if power >= tier.min then t = tier end
	end
	return t
end

local function sequence(colors: { Color3 }): ColorSequence
	local keys = {}
	for i, c in ipairs(colors) do
		table.insert(keys, ColorSequenceKeypoint.new((i - 1) / (#colors - 1), c))
	end
	return ColorSequence.new(keys)
end

type Plate = { gui: BillboardGui, label: TextLabel, stroke: UIStroke, grad: UIGradient, scale: UIScale, tier: Tier?, head: BasePart }
local plates: { [Player]: Plate } = {}

local function update(plr: Player)
	local p = plates[plr]
	if not p then return end
	local power = plr:GetAttribute("Power")
	if typeof(power) ~= "number" or power <= 0 then
		p.gui.Enabled = false
		return
	end
	p.gui.Enabled = true
	local tier = tierOf(power)
	local mark = tier.mark
	local text = `{math.floor(power)} POWER`
	p.label.Text = if mark then `{mark} {text} {mark}` else text
	if p.tier ~= tier then
		p.tier = tier
		p.label.TextColor3 = if tier.sweep then Color3.new(1, 1, 1) else tier.color
		p.label.TextSize = tier.size
		p.stroke.Color = tier.stroke
		p.stroke.Thickness = if tier.min >= 700 then 2 else 1
		p.stroke.Transparency = if tier.min >= 300 then 0.1 else 0.4
		p.grad.Enabled = tier.sweep ~= nil
		if tier.sweep then p.grad.Color = sequence(tier.sweep) end
		p.scale.Scale = 1
	end
end

local function attach(plr: Player, char: Model)
	local old = plates[plr]
	if old then old.gui:Destroy() end
	plates[plr] = nil
	local head = char:WaitForChild("Head", 10) :: BasePart?
	if not head or not char.Parent then return end
	local g = Instance.new("BillboardGui")
	g.Name = "PowerNameplate"
	g.Size = UDim2.fromOffset(240, 30)
	-- (over the lobby nameplate, GearLook.Nameplate at 3.4, and over Roblox's
	-- own name in a run)
	g.StudsOffsetWorldSpace = Vector3.new(0, 4.7, 0)
	g.MaxDistance = 90
	g.LightInfluence = 0
	g.Adornee = head
	local l = Instance.new("TextLabel")
	l.Name = "Power"
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(1, 1)
	l.Font = Enum.Font.Arcade
	l.TextStrokeTransparency = 1
	l.Parent = g
	local st = Instance.new("UIStroke")
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual
	st.Parent = l
	local gr = Instance.new("UIGradient")
	gr.Enabled = false
	gr.Parent = l
	local sc = Instance.new("UIScale")
	sc.Parent = l
	g.Parent = head
	plates[plr] = { gui = g, label = l, stroke = st, grad = gr, scale = sc, tier = nil, head = head }
	update(plr)
end

local function watch(plr: Player)
	plr:GetAttributeChangedSignal("Power"):Connect(function() update(plr) end)
	plr.CharacterAdded:Connect(function(char) attach(plr, char) end)
	if plr.Character then task.spawn(attach, plr, plr.Character) end
end

function PowerNameplates.Init()
	for _, plr in ipairs(Players:GetPlayers()) do watch(plr) end
	Players.PlayerAdded:Connect(watch)
	Players.PlayerRemoving:Connect(function(plr)
		local p = plates[plr]
		if p then p.gui:Destroy() end
		plates[plr] = nil
	end)
	-- The sweep and the pulse: one loop for all, ~30 Hz, near plates only.
	local acc = 0
	RunService.RenderStepped:Connect(function(dt)
		acc += dt
		if acc < 1 / 30 then return end
		acc = 0
		local cam = workspace.CurrentCamera
		if not cam then return end
		local t = os.clock()
		for _, p in pairs(plates) do
			local tier = p.tier
			if not tier or not p.gui.Enabled or not tier.sweep or not p.head.Parent then continue end
			if (p.head.Position - cam.CFrame.Position).Magnitude > 90 then continue end
			p.grad.Offset = Vector2.new(((t * 0.6) % 2) - 1, 0)
			if tier.pulse > 0 then p.scale.Scale = 1 + tier.pulse * (0.5 + 0.5 * math.sin(t * 3)) end
		end
	end)
end

return PowerNameplates
