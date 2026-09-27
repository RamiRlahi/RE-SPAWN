--[[
	TalentConstellation.luau
	The class-selection talent tree: a glowing line-art constellation per class
	(TalentData) with talent nodes placed on it.

	  owned      filled, bright
	  available  outline pulsing — click to unlock (server validates)
	  locked     dim, 🔒 until its prerequisite is owned

	Hover shows the talent, its buff, cost and status. The souls counter sits
	above, the constellation name and progress below.
--]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))
local TalentData = require(Shared:WaitForChild("TalentData"))

local TalentConstellation = {}

local NODE_SIZE = 34

type State = { souls: number, unlocked: { [string]: { [string]: boolean } } }

local function line(parent: Instance, a: Vector2, b: Vector2, thickness: number, color: Color3, transparency: number, z: number): Frame
	local d = b - a
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromOffset((a.X + b.X) / 2, (a.Y + b.Y) / 2)
	f.Size = UDim2.fromOffset(d.Magnitude + thickness * 0.5, thickness)
	f.Rotation = math.deg(math.atan2(d.Y, d.X))
	f.BackgroundColor3 = color
	f.BackgroundTransparency = transparency
	f.BorderSizePixel = 0
	f.ZIndex = z
	f.Parent = parent
	Instance.new("UICorner", f).CornerRadius = UDim.new(1, 0)
	return f
end

function TalentConstellation.Create(parent: GuiObject)
	local state: State = { souls = 0, unlocked = {} }
	local currentClass: string? = nil
	local currentAccent = Color3.new(1, 1, 1)
	local currentLocked = false

	local root = Instance.new("Frame")
	root.Name = "TalentConstellation"
	root.BackgroundTransparency = 1
	root.Size = UDim2.new(0.42, 0, 1, -150)
	root.Position = UDim2.new(0, 24, 0, 70)
	root.Parent = parent

	local soulsLabel = Instance.new("TextLabel")
	soulsLabel.Name = "Souls"
	soulsLabel.BackgroundTransparency = 1
	soulsLabel.Size = UDim2.new(1, 0, 0, 26)
	soulsLabel.Font = Enum.Font.GothamBold
	soulsLabel.TextSize = 18
	soulsLabel.TextXAlignment = Enum.TextXAlignment.Left
	soulsLabel.TextColor3 = Color3.fromRGB(200, 225, 255)
	soulsLabel.TextStrokeTransparency = 0.5
	soulsLabel.Parent = root

	local area = Instance.new("Frame")
	area.Name = "Area"
	area.BackgroundTransparency = 1
	area.Position = UDim2.new(0, 0, 0, 34)
	area.Size = UDim2.new(1, 0, 1, -90)
	area.ClipsDescendants = false
	area.Parent = root
	local aspect = Instance.new("UIAspectRatioConstraint")
	aspect.AspectRatio = 1
	aspect.Parent = area

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.BackgroundTransparency = 1
	title.AnchorPoint = Vector2.new(0.5, 1)
	title.Position = UDim2.new(0.5, 0, 1, -18)
	title.Size = UDim2.new(1, 0, 0, 30)
	title.Font = Enum.Font.Antique
	title.TextSize = 26
	title.TextStrokeTransparency = 0.4
	title.Parent = root
	local progress = title:Clone()
	progress.Name = "Progress"
	progress.Position = UDim2.new(0.5, 0, 1, 2)
	progress.Size = UDim2.new(1, 0, 0, 18)
	progress.Font = Enum.Font.GothamMedium
	progress.TextSize = 14
	progress.Parent = root

	-- Tooltip.
	local tip = Instance.new("Frame")
	tip.Name = "Tooltip"
	tip.Visible = false
	tip.Size = UDim2.fromOffset(220, 74)
	tip.BackgroundColor3 = Color3.fromRGB(12, 12, 18)
	tip.BackgroundTransparency = 0.1
	tip.ZIndex = 50
	tip.Parent = root
	Instance.new("UICorner", tip).CornerRadius = UDim.new(0, 6)
	local tipStroke = Instance.new("UIStroke")
	tipStroke.Thickness = 1.5
	tipStroke.Parent = tip
	local function tipText(name: string, y: number, h: number, size: number, font: Enum.Font): TextLabel
		local t = Instance.new("TextLabel")
		t.Name = name
		t.BackgroundTransparency = 1
		t.Position = UDim2.fromOffset(10, y)
		t.Size = UDim2.new(1, -20, 0, h)
		t.Font = font
		t.TextSize = size
		t.TextXAlignment = Enum.TextXAlignment.Left
		t.TextColor3 = Color3.fromRGB(235, 235, 240)
		t.ZIndex = 51
		t.Parent = tip
		return t
	end
	local tipName = tipText("Name", 6, 20, 16, Enum.Font.GothamBold)
	local tipBuff = tipText("Buff", 27, 18, 14, Enum.Font.GothamMedium)
	local tipStatus = tipText("Status", 48, 18, 12, Enum.Font.Gotham)

	local pulsing: { UIStroke } = {}
	local t0 = os.clock()
	RunService.RenderStepped:Connect(function()
		if not root.Visible then return end
		local a = 0.5 + 0.5 * math.sin((os.clock() - t0) * 4)
		for _, s in ipairs(pulsing) do
			if s.Parent then
				s.Thickness = 1.5 + a * 1.5
				s.Transparency = 0.1 + (1 - a) * 0.4
			end
		end
	end)

	local function owned(classId: string, nodeId: string): boolean
		local c = state.unlocked[classId]
		return c ~= nil and c[nodeId] == true
	end

	local render: () -> ()

	render = function()
		for _, child in ipairs(area:GetChildren()) do
			if not child:IsA("UIAspectRatioConstraint") then child:Destroy() end
		end
		table.clear(pulsing)
		tip.Visible = false
		soulsLabel.Text = `✦ {state.souls} Souls`
		local classId = currentClass
		local constellation = classId and TalentData.Get(classId)
		local size = area.AbsoluteSize
		if not classId or not constellation or size.X < 10 then
			title.Text = if currentLocked then "SEALED" else ""
			progress.Text = if currentLocked then "This class's constellation is still hidden" else ""
			title.TextColor3 = Color3.fromRGB(110, 110, 115)
			progress.TextColor3 = Color3.fromRGB(110, 110, 115)
			return
		end
		local accent = currentAccent
		local function px(x: number, y: number): Vector2
			return Vector2.new(x * size.X, y * size.Y)
		end

		-- Line-art: soft glow under a crisp core.
		for _, s in ipairs(constellation.lines) do
			local a, b = px(s[1], s[2]), px(s[3], s[4])
			line(area, a, b, 9, accent, 0.86, 1)
			line(area, a, b, 2.5, accent, 0.05, 2)
		end

		-- Prerequisite links between nodes.
		local byId = {}
		for _, n in ipairs(constellation.nodes) do byId[n.id] = n end
		for _, n in ipairs(constellation.nodes) do
			local req = n.requires and byId[n.requires]
			if req then
				local bright = owned(classId, n.id)
				line(area, px(req.x, req.y), px(n.x, n.y), 1.5, Color3.new(1, 1, 1), if bright then 0.35 else 0.8, 3)
			end
		end

		-- Nodes.
		local count = 0
		for _, n in ipairs(constellation.nodes) do
			local isOwned = owned(classId, n.id)
			if isOwned then count += 1 end
			local available = not isOwned and (n.requires == nil or owned(classId, n.requires))
			local p = px(n.x, n.y)

			local btn = Instance.new("TextButton")
			btn.Name = n.id
			btn.AutoButtonColor = false
			btn.AnchorPoint = Vector2.new(0.5, 0.5)
			btn.Position = UDim2.fromOffset(p.X, p.Y)
			btn.Size = UDim2.fromOffset(NODE_SIZE, NODE_SIZE)
			btn.BackgroundColor3 = if isOwned then accent else Color3.fromRGB(14, 14, 20)
			btn.BackgroundTransparency = if isOwned then 0 elseif available then 0.1 else 0.3
			btn.Font = Enum.Font.GothamBold
			btn.TextSize = 16
			btn.Text = if isOwned or available then n.glyph else "🔒"
			btn.TextColor3 = if isOwned then Color3.fromRGB(15, 15, 20) elseif available then accent else Color3.fromRGB(110, 110, 120)
			btn.ZIndex = 5
			btn.Parent = area
			Instance.new("UICorner", btn).CornerRadius = UDim.new(1, 0)
			local stroke = Instance.new("UIStroke")
			stroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
			stroke.Color = if isOwned then Color3.new(1, 1, 1) elseif available then accent else Color3.fromRGB(70, 70, 80)
			stroke.Thickness = if isOwned then 2 else 1.5
			stroke.Parent = btn
			if available then table.insert(pulsing, stroke) end
			-- Soft halo behind owned nodes.
			if isOwned then
				local halo = Instance.new("Frame")
				halo.AnchorPoint = Vector2.new(0.5, 0.5)
				halo.Position = btn.Position
				halo.Size = UDim2.fromOffset(NODE_SIZE * 1.9, NODE_SIZE * 1.9)
				halo.BackgroundColor3 = accent
				halo.BackgroundTransparency = 0.82
				halo.ZIndex = 4
				halo.Parent = area
				Instance.new("UICorner", halo).CornerRadius = UDim.new(1, 0)
			end

			btn.MouseEnter:Connect(function()
				tip.Visible = true
				tipStroke.Color = accent
				tipName.Text = n.name
				tipName.TextColor3 = accent
				tipBuff.Text = n.description
				local req = n.requires and byId[n.requires]
				if isOwned then
					tipStatus.Text = "Owned"
				elseif available then
					tipStatus.Text = if state.souls >= n.cost then `Click to unlock · {n.cost} souls` else `Not enough souls · needs {n.cost}`
				else
					tipStatus.Text = `Requires {req and req.name or "?"} · {n.cost} souls`
				end
				local rightSide = p.X < size.X * 0.6
				tip.Position = UDim2.fromOffset(area.Position.X.Offset + p.X + (if rightSide then 26 else -246), 34 + p.Y - 37)
			end)
			btn.MouseLeave:Connect(function()
				tip.Visible = false
			end)
			btn.MouseButton1Click:Connect(function()
				if not available or state.souls < n.cost then return end
				-- Optimistic flash; the server confirms with a TalentState sync.
				local flash = Instance.new("Frame")
				flash.AnchorPoint = Vector2.new(0.5, 0.5)
				flash.Position = btn.Position
				flash.Size = UDim2.fromOffset(NODE_SIZE, NODE_SIZE)
				flash.BackgroundColor3 = Color3.new(1, 1, 1)
				flash.ZIndex = 6
				flash.Parent = area
				Instance.new("UICorner", flash).CornerRadius = UDim.new(1, 0)
				TweenService:Create(flash, TweenInfo.new(0.45, Enum.EasingStyle.Quart, Enum.EasingDirection.Out), {
					Size = UDim2.fromOffset(NODE_SIZE * 3, NODE_SIZE * 3), BackgroundTransparency = 1,
				}):Play()
				Network.GetRemoteEvent(Network.Remotes.UnlockTalent):FireServer({ classId = classId, nodeId = n.id })
			end)
		end

		title.Text = string.upper(constellation.name)
		title.TextColor3 = accent
		progress.Text = `{count}/{#constellation.nodes}`
		progress.TextColor3 = Color3.fromRGB(190, 190, 200)
	end

	area:GetPropertyChangedSignal("AbsoluteSize"):Connect(function()
		render()
	end)

	Network.GetRemoteEvent(Network.Remotes.TalentState).OnClientEvent:Connect(function(payload)
		if typeof(payload) ~= "table" then return end
		state.souls = tonumber(payload.souls) or 0
		state.unlocked = typeof(payload.unlocked) == "table" and payload.unlocked or {}
		render()
	end)
	Network.GetRemoteEvent(Network.Remotes.RequestTalents):FireServer()

	local api = {}
	function api.Show(classId: string, accent: Color3, locked: boolean)
		currentClass = if locked then nil else classId
		currentAccent = accent
		currentLocked = locked
		render()
	end
	api.Frame = root
	return api
end

return TalentConstellation
