--!strict
--[[
	TalentScreen.luau
	The skill tree (talents), opened in the lobby: a window over the plaza with
	a class's talent constellation (TalentConstellation: souls, nodes to
	unlock), the class you play first, arrows to look at the others you own.
	Closed by its X or a click outside it (ClickOutside).

	  TalentScreen.Open() / Close() / Toggle()
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))
local ClassData = require(Shared:WaitForChild("ClassData"))
local TalentConstellation = require(script.Parent:WaitForChild("TalentConstellation"))
local ClickOutside = require(script.Parent:WaitForChild("ClickOutside"))
local Icons = require(script.Parent:WaitForChild("Icons"))

local player = Players.LocalPlayer

local TalentScreen = {}

local W, H = 620, 700
local FONT = Enum.Font.GothamMedium
local FONT_BOLD = Enum.Font.GothamBold

local gui: ScreenGui? = nil
local constellation: any = nil
local nameLabel: TextLabel? = nil
local index = 1

local function order(): { string }
	return (ClassData :: any).Order
end

local function show()
	local classId = order()[index]
	local info = ClassData.GetClass(classId)
	if not (info and constellation and nameLabel) then return end
	local locked = not (ClassData :: any).IsOwnedBy(player, classId)
	nameLabel.Text = string.upper(info.name or classId) .. (if locked then "  (locked)" else "")
	nameLabel.TextColor3 = if locked then Color3.fromRGB(150, 150, 155) else info.accentColor
	constellation.Show(classId, if locked then Color3.fromRGB(110, 110, 115) else info.accentColor, locked)
end

local function step(dir: number)
	local n = #order()
	index = (index - 1 + dir) % n + 1
	show()
end

local function build(): ScreenGui
	local g = Instance.new("ScreenGui")
	g.Name = "TalentScreen"
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.DisplayOrder = 40
	g.Enabled = false
	g:SetAttribute("KeepFont", true) -- (plain Roblox fonts, not the Arcade one)
	g.Parent = player:WaitForChild("PlayerGui")

	local dim = Instance.new("TextButton")
	dim.Name = "Dim"
	dim.Text = ""
	dim.AutoButtonColor = false
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 0.45
	dim.BorderSizePixel = 0
	dim.Parent = g

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = UDim2.fromOffset(W, H)
	panel.BackgroundColor3 = Color3.fromRGB(25, 27, 29)
	panel.BackgroundTransparency = 0.08
	panel.BorderSizePixel = 0
	panel.Active = true
	panel.Parent = g
	local pc = Instance.new("UICorner")
	pc.CornerRadius = UDim.new(0, 8)
	pc.Parent = panel
	ClickOutside.Bind(dim, panel, TalentScreen.Close)
	local scale = Instance.new("UIScale")
	scale.Parent = panel
	local function fit()
		local vs = workspace.CurrentCamera.ViewportSize
		scale.Scale = math.min(1, (vs.X - 24) / W, (vs.Y - 24) / H)
	end
	fit()
	workspace.CurrentCamera:GetPropertyChangedSignal("ViewportSize"):Connect(fit)

	local function label(text: string, size: number, pos: UDim2, dims: UDim2, bold: boolean?): TextLabel
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Position = pos
		l.Size = dims
		l.Font = if bold then FONT_BOLD else FONT
		l.TextSize = size
		l.TextColor3 = Color3.new(1, 1, 1)
		l.Text = text
		l.Parent = panel
		return l
	end
	local function button(text: string, pos: UDim2, dims: UDim2, onClick: () -> ()): TextButton
		local b = Instance.new("TextButton")
		b.Position = pos
		b.Size = dims
		b.BackgroundColor3 = Color3.fromRGB(57, 59, 61)
		b.BorderSizePixel = 0
		b.Font = FONT_BOLD
		b.TextSize = 20
		b.TextColor3 = Color3.new(1, 1, 1)
		b.Text = text
		b.Parent = panel
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 8)
		c.Parent = b
		Icons.Press(b)
		b.Activated:Connect(onClick)
		return b
	end

	local title = label("SKILL TREE", 22, UDim2.fromOffset(20, 12), UDim2.new(1, -80, 0, 28), true)
	title.TextXAlignment = Enum.TextXAlignment.Left
	local close = button("X", UDim2.new(1, -46, 0, 10), UDim2.fromOffset(34, 34), function() TalentScreen.Close() end)
	close.Name = "Close"
	close.BackgroundColor3 = Icons.CLOSE_RED -- (Roblox's close button: square, red, a white X, top right)
	button("<", UDim2.fromOffset(20, 52), UDim2.fromOffset(36, 36), function() step(-1) end).Name = "Prev"
	button(">", UDim2.new(1, -56, 0, 52), UDim2.fromOffset(36, 36), function() step(1) end).Name = "Next"
	local name = label("", 20, UDim2.fromOffset(64, 52), UDim2.new(1, -128, 0, 36), true)
	name.Name = "ClassName"
	nameLabel = name

	local c = TalentConstellation.Create(panel)
	c.Frame.Position = UDim2.fromOffset(30, 100)
	c.Frame.Size = UDim2.new(1, -60, 1, -130)
	c.Frame:SetAttribute("KeepFont", false) -- (the tree keeps the game's own lettering)
	constellation = c
	return g
end

function TalentScreen.Open()
	if not gui then gui = build() end
	-- (the class you play, first)
	local mine = player:GetAttribute("SelectedClass")
	local at = if typeof(mine) == "string" then table.find(order(), mine) else nil
	index = at or index
	;(gui :: ScreenGui).Enabled = true
	show()
	Network.GetRemoteEvent(Network.Remotes.RequestTalents):FireServer()
end

function TalentScreen.Close()
	if gui then gui.Enabled = false end
end

function TalentScreen.IsOpen(): boolean
	return gui ~= nil and gui.Enabled
end

function TalentScreen.Toggle()
	if TalentScreen.IsOpen() then TalentScreen.Close() else TalentScreen.Open() end
end

return TalentScreen
