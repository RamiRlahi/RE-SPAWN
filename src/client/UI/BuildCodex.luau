--!strict
--[[
	BuildCodex.luau
	Evolutions: the moment and the record.

	  • The banner: when a boon evolves mid-run (PlayerStats → Evolution), a
	    big "EVOLUTION" banner in its colour, with what it now does, and
	    "NEW: added to the Build Codex" the first time you ever find it.
	  • The Codex (the lobby's DIVINE ARCHIVE, from the party panel): every
	    evolution in the game. Found ones show their name, what they do and
	    the recipe; the rest are ??? with only their boon as a clue.

	BuildCodex.Init()   BuildCodex.Open()   BuildCodex.Close()
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))
local TomeData = require(Shared:WaitForChild("TomeData"))
local ClassData = require(Shared:WaitForChild("ClassData"))

local player = Players.LocalPlayer

local BuildCodex = {}

local GOLD = Color3.fromRGB(240, 196, 110)
local PARCH = Color3.fromRGB(238, 226, 204)
local MUTED = Color3.fromRGB(150, 140, 125)
local DARK = Color3.fromRGB(16, 12, 14)
local CARD = Color3.fromRGB(30, 24, 26)
local BODY = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Regular)
local BOLD = Font.new("rbxasset://fonts/families/Merriweather.json", Enum.FontWeight.Bold)

local discovered: { [string]: boolean } = {}

local function label(parent: Instance, text: string, size: number, color: Color3, props: { [string]: any }?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.FontFace = BODY
	l.Text = text
	l.TextSize = size
	l.TextColor3 = color
	l.TextXAlignment = Enum.TextXAlignment.Left
	l.TextWrapped = true
	for k, v in pairs(props or {}) do (l :: any)[k] = v end
	l.Parent = parent
	return l
end

-- ── The banner ────────────────────────────────────────────────────────────
-- (one at a time: two evolving together show one after the other)
local queue: { any } = {}
local showing = false
local banner: (any) -> ()

local function showNext()
	if showing or #queue == 0 then return end
	showing = true
	local e = table.remove(queue, 1)
	local ok = pcall(banner, e)
	task.delay(if ok then 4.7 else 0, function()
		showing = false
		showNext()
	end)
end

function banner(e: any)
	local color: Color3 = if typeof(e.color) == "Color3" then e.color else GOLD
	local g = Instance.new("ScreenGui")
	g.Name = "EvolutionBanner"
	g.IgnoreGuiInset = true
	g.ResetOnSpawn = false
	g.DisplayOrder = 70
	g.Parent = player:WaitForChild("PlayerGui")
	local root = Instance.new("CanvasGroup")
	root.AnchorPoint = Vector2.new(0.5, 0.5)
	root.Position = UDim2.fromScale(0.5, 0.36)
	root.Size = UDim2.fromOffset(760, 170)
	root.BackgroundTransparency = 1
	root.GroupTransparency = 1
	root.Parent = g
	-- a band of its colour across the screen
	local band = Instance.new("Frame")
	band.AnchorPoint = Vector2.new(0.5, 0.5)
	band.Position = UDim2.fromScale(0.5, 0.5)
	band.Size = UDim2.new(1, 0, 0, 130)
	band.BackgroundColor3 = DARK
	band.BackgroundTransparency = 0.2
	band.BorderSizePixel = 0
	band.Parent = root
	local grad = Instance.new("UIGradient")
	grad.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0), NumberSequenceKeypoint.new(0.8, 0), NumberSequenceKeypoint.new(1, 1) })
	grad.Parent = band
	for _, y in ipairs({ 0, 1 }) do
		local line = Instance.new("Frame")
		line.AnchorPoint = Vector2.new(0.5, y)
		line.Position = UDim2.new(0.5, 0, y, if y == 0 then 20 else -20)
		line.Size = UDim2.new(0.8, 0, 0, 2)
		line.BackgroundColor3 = color
		line.BorderSizePixel = 0
		line.Parent = root
		local lg = grad:Clone()
		lg.Parent = line
	end
	label(root, "◆  EVOLUTION  ◆", 16, color, { FontFace = BOLD, Position = UDim2.fromOffset(0, 30), Size = UDim2.new(1, 0, 0, 20), TextXAlignment = Enum.TextXAlignment.Center })
	label(root, string.upper(tostring(e.name)), 40, Color3.new(1, 1, 1), { Font = Enum.Font.Antique, Position = UDim2.fromOffset(0, 50), Size = UDim2.new(1, 0, 0, 46),
		TextXAlignment = Enum.TextXAlignment.Center, TextStrokeTransparency = 0.4, TextStrokeColor3 = color })
	label(root, tostring(e.description), 15, PARCH, { Position = UDim2.fromOffset(60, 98), Size = UDim2.new(1, -120, 0, 36), TextXAlignment = Enum.TextXAlignment.Center })
	if e.isNew then
		label(root, "NEW  ·  added to the Build Codex", 12, GOLD, { FontFace = BOLD, Position = UDim2.fromOffset(0, 136), Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Center })
	end
	local scale = Instance.new("UIScale")
	scale.Scale = 1.3
	scale.Parent = root
	TweenService:Create(root, TweenInfo.new(0.25), { GroupTransparency = 0 }):Play()
	TweenService:Create(scale, TweenInfo.new(0.4, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
	task.delay(4, function()
		TweenService:Create(root, TweenInfo.new(0.6), { GroupTransparency = 1 }):Play()
		task.delay(0.65, function() g:Destroy() end)
	end)
	discovered[tostring(e.id)] = true
end

-- ── The Codex window ──────────────────────────────────────────────────────
local codexGui: ScreenGui? = nil
local grid: ScrollingFrame? = nil
local countLabel: TextLabel? = nil

local function recipe(e: any): string
	local boon = TomeData.GetTome(e.boon)
	local boonName = if boon then boon.name else e.boon
	if e.with then
		local w = TomeData.GetTome(e.with)
		return `{boonName} (max)  +  {if w then w.name else e.with}`
	end
	local c = ClassData.GetClass(e.classId)
	return `{boonName} (max)  as the {if c then c.name else e.classId}  ·  changes {e.skill}`
end

local function render()
	local gr = grid
	if not gr then return end
	for _, c in ipairs(gr:GetChildren()) do
		if c:IsA("Frame") then c:Destroy() end
	end
	local found = 0
	for i, e in ipairs(TomeData.Evolutions) do
		local known = discovered[e.id] == true
		if known then found += 1 end
		local f = Instance.new("Frame")
		f.LayoutOrder = i
		f.BackgroundColor3 = if known then e.color:Lerp(CARD, 0.82) else CARD
		f.BackgroundTransparency = 0.05
		f.Parent = gr
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 8)
		c.Parent = f
		local st = Instance.new("UIStroke")
		st.Color = if known then e.color else Color3.fromRGB(70, 60, 60)
		st.Thickness = if known then 1.5 else 1
		st.Parent = f
		label(f, if known then "◆  " .. string.upper(e.name) else "◆  ? ? ?", 17, if known then e.color:Lerp(Color3.new(1, 1, 1), 0.3) else MUTED,
			{ FontFace = BOLD, Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -24, 0, 22) })
		label(f, if known then e.description else "Not yet discovered.", 13, if known then PARCH else MUTED,
			{ Position = UDim2.fromOffset(12, 32), Size = UDim2.new(1, -24, 0, 36), TextYAlignment = Enum.TextYAlignment.Top })
		-- (the recipe once found; just its boon as a clue before)
		local clue = if known then recipe(e) else (function()
			local boon = TomeData.GetTome(e.boon)
			return `Begins with {if boon then boon.name else "?"}…`
		end)()
		label(f, clue, 11, if known then GOLD else MUTED, { Position = UDim2.fromOffset(12, 70), Size = UDim2.new(1, -24, 0, 16), TextTransparency = if known then 0 else 0.3,
			TextTruncate = Enum.TextTruncate.AtEnd })
	end
	if countLabel then countLabel.Text = `{found} / {#TomeData.Evolutions} discovered` end
end

local function build()
	local g = Instance.new("ScreenGui")
	g.Name = "BuildCodex"
	g.IgnoreGuiInset = true
	g.ResetOnSpawn = false
	g.DisplayOrder = 60
	g.Enabled = false
	g.Parent = player:WaitForChild("PlayerGui")
	codexGui = g
	local dim = Instance.new("TextButton")
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 0.45
	dim.Parent = g
	dim.MouseButton1Click:Connect(BuildCodex.Close)
	local W, H = 900, 600
	local panel = Instance.new("Frame")
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(W, H)
	panel.BackgroundColor3 = DARK
	panel.Parent = g
	local pc = Instance.new("UICorner")
	pc.CornerRadius = UDim.new(0, 12)
	pc.Parent = panel
	local ps = Instance.new("UIStroke")
	ps.Color = GOLD
	ps.Transparency = 0.35
	ps.Parent = panel
	local sc = Instance.new("UIScale")
	sc.Parent = panel
	local vp = Workspace.CurrentCamera and Workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	sc.Scale = math.min(1, (vp.X - 40) / W, (vp.Y - 40) / H)
	label(panel, "THE DIVINE ARCHIVE", 34, GOLD, { Font = Enum.Font.Antique, Position = UDim2.fromOffset(0, 16), Size = UDim2.new(1, 0, 0, 40), TextXAlignment = Enum.TextXAlignment.Center })
	label(panel, "Every evolution you find is written here. Take a boon to its max level with the right tome, or on the right class.", 14, PARCH,
		{ Position = UDim2.fromOffset(40, 58), Size = UDim2.new(1, -80, 0, 20), TextXAlignment = Enum.TextXAlignment.Center, TextTransparency = 0.15 })
	countLabel = label(panel, "", 14, GOLD, { FontFace = BOLD, Position = UDim2.fromOffset(0, 80), Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Center })
	local sf = Instance.new("ScrollingFrame")
	sf.Position = UDim2.fromOffset(24, 108)
	sf.Size = UDim2.new(1, -48, 1, -170)
	sf.BackgroundTransparency = 1
	sf.BorderSizePixel = 0
	sf.ScrollBarThickness = 5
	sf.AutomaticCanvasSize = Enum.AutomaticSize.Y
	sf.CanvasSize = UDim2.new()
	sf.Parent = panel
	local gl = Instance.new("UIGridLayout")
	gl.CellSize = UDim2.new(0.5, -8, 0, 94)
	gl.CellPadding = UDim2.fromOffset(10, 10)
	gl.SortOrder = Enum.SortOrder.LayoutOrder
	gl.Parent = sf
	grid = sf
	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(0.5, 1)
	close.Position = UDim2.new(0.5, 0, 1, -14)
	close.Size = UDim2.fromOffset(180, 38)
	close.BackgroundColor3 = Color3.fromRGB(60, 40, 30)
	close.FontFace = BOLD
	close.TextSize = 16
	close.TextColor3 = GOLD
	close.Text = "CLOSE"
	close.Parent = panel
	local cc = Instance.new("UICorner")
	cc.CornerRadius = UDim.new(0, 6)
	cc.Parent = close
	close.MouseButton1Click:Connect(BuildCodex.Close)
end

function BuildCodex.Open()
	if not codexGui then build() end
	render()
	Network.GetRemoteEvent(Network.Remotes.RequestCodex):FireServer()
	local g = codexGui :: ScreenGui
	g.Enabled = true
end

function BuildCodex.Close()
	if codexGui then codexGui.Enabled = false end
end

function BuildCodex.Init()
	Network.GetRemoteEvent(Network.Remotes.Evolution).OnClientEvent:Connect(function(e: any)
		if typeof(e) ~= "table" then return end
		table.insert(queue, e)
		showNext()
	end)
	Network.GetRemoteEvent(Network.Remotes.CodexState).OnClientEvent:Connect(function(state: any)
		if typeof(state) ~= "table" or typeof(state.discovered) ~= "table" then return end
		discovered = {}
		for id, v in pairs(state.discovered) do
			if v then discovered[tostring(id)] = true end
		end
		if codexGui and codexGui.Enabled then render() end
	end)
end

return BuildCodex
