--!strict
--[[
	PowerBadge.luau
	Your POWER (the attribute "Power": LootManager / PowerGear), always on
	screen in a run and in the plaza: a small plaque under the minimap in a
	run, at the top centre in the plaza (the party panel has the corner). When
	it goes up (a better piece worn, a hero level gained) the number counts
	up, the plaque flashes and "+38 POWER" floats off it.

	PowerBadge.Init()
--]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

local PowerBadge = {}

local GOLD = Color3.fromRGB(240, 196, 110)
local GREEN = Color3.fromRGB(120, 230, 140)
local BOLD = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Bold)

function PowerBadge.Init()
	local g = Instance.new("ScreenGui")
	g.Name = "PowerBadge"
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.DisplayOrder = 12
	g.Parent = player:WaitForChild("PlayerGui")

	local plaque = Instance.new("Frame")
	plaque.Name = "Plaque"
	plaque.Position = UDim2.fromOffset(30, 284)
	plaque.Size = UDim2.fromOffset(184, 34)
	plaque.BackgroundColor3 = Color3.fromRGB(22, 16, 14)
	plaque.BackgroundTransparency = 0.15
	plaque.Parent = g
	Instance.new("UICorner", plaque).CornerRadius = UDim.new(0, 6)
	local stroke = Instance.new("UIStroke")
	stroke.Color = GOLD
	stroke.Transparency = 0.3
	stroke.Thickness = 1.4
	stroke.Parent = plaque

	local function text(name: string, x: number, w: number, size: number, color: Color3, align: Enum.TextXAlignment): TextLabel
		local l = Instance.new("TextLabel")
		l.Name = name
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromOffset(x, 0)
		l.Size = UDim2.new(0, w, 1, 0)
		l.FontFace = BOLD
		l.TextSize = size
		l.TextColor3 = color
		l.TextXAlignment = align
		l.TextStrokeTransparency = 0.5
		l.Parent = plaque
		return l
	end
	text("Caption", 12, 80, 12, Color3.fromRGB(222, 200, 160), Enum.TextXAlignment.Left).Text = "◆  POWER"
	local value = text("Value", 84, 88, 20, GOLD, Enum.TextXAlignment.Right)

	local shown = 0
	local counting = 0
	local function set(v: number)
		shown = v
		value.Text = tostring(math.floor(v + 0.5))
	end

	local function refresh()
		local hub = player:GetAttribute("InHub") == true
		local here = hub or player:GetAttribute("InLobby") == false
		g.Enabled = here and player:GetAttribute("UIModal") ~= true and player:GetAttribute("Forging") ~= true
		if hub then
			plaque.AnchorPoint = Vector2.new(0.5, 0)
			plaque.Position = UDim2.new(0.5, 0, 0, 16)
		else
			plaque.AnchorPoint = Vector2.zero
			plaque.Position = UDim2.fromOffset(30, 284)
		end
	end

	local last: number? = nil
	local function onPower()
		local v = player:GetAttribute("Power")
		if typeof(v) ~= "number" then return end
		if last == nil or v <= last then
			last = v
			set(v)
			return
		end
		-- it went up: count up, flash, and float the gain off the plaque
		local gain = v - last
		last = v
		counting += 1
		local mine = counting
		local from = shown
		task.spawn(function()
			local t0 = os.clock()
			while os.clock() - t0 < 0.9 and mine == counting do
				local k = (os.clock() - t0) / 0.9
				set(from + (v - from) * (1 - (1 - k) ^ 3))
				task.wait()
			end
			if mine == counting then set(v) end
		end)
		stroke.Color = GREEN
		stroke.Transparency = 0
		TweenService:Create(stroke, TweenInfo.new(1.2), { Color = GOLD, Transparency = 0.3 }):Play()
		local pop = Instance.new("TextLabel")
		pop.BackgroundTransparency = 1
		pop.AnchorPoint = Vector2.new(0, 0.5)
		pop.Position = UDim2.new(1, 10, 0.5, 0)
		pop.Size = UDim2.fromOffset(160, 24)
		pop.FontFace = BOLD
		pop.TextSize = 20
		pop.TextColor3 = GREEN
		pop.TextStrokeTransparency = 0.3
		pop.TextXAlignment = Enum.TextXAlignment.Left
		pop.Text = `+{gain} POWER`
		pop.Parent = plaque
		TweenService:Create(pop, TweenInfo.new(1.8, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Position = UDim2.new(1, 10, 0.5, -30), TextTransparency = 1, TextStrokeTransparency = 1,
		}):Play()
		task.delay(1.9, function() pop:Destroy() end)
	end

	player:GetAttributeChangedSignal("Power"):Connect(onPower)
	player:GetAttributeChangedSignal("InHub"):Connect(refresh)
	player:GetAttributeChangedSignal("InLobby"):Connect(refresh)
	player:GetAttributeChangedSignal("UIModal"):Connect(refresh)
	player:GetAttributeChangedSignal("Forging"):Connect(refresh)
	onPower()
	refresh()
end

return PowerBadge
