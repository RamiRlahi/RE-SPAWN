--!strict
--[[
	FloorPortalHUD.luau
	The count at the floor's exit (DungeonGenerator's abyss gate): once anyone
	steps into it, every player of the run sees how many are in and who it's
	waiting for; the run goes down only when every living player is in.

	FloorPortalHUD.Init()
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Network = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Network"))

local player = Players.LocalPlayer

local FloorPortalHUD = {}

local GOLD = Color3.fromRGB(232, 196, 120)
local PARCH = Color3.fromRGB(240, 226, 200)
local DARK = Color3.fromRGB(14, 10, 12)
local FONT = Enum.Font.Antique
local TOP = 320 -- (under the timer, the week's omen, the corruption meter and a horde's count)

local gui: ScreenGui? = nil
local panel: Frame? = nil
local countLabel: TextLabel? = nil
local titleLabel: TextLabel? = nil
local subLabel: TextLabel? = nil
local shown = false

local function label(parent: Instance, text: string, size: number, color: Color3, props: { [string]: any }): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = FONT
	l.Text = text
	l.TextSize = size
	l.TextColor3 = color
	l.TextStrokeTransparency = 0.5
	for k, v in pairs(props) do (l :: any)[k] = v end
	l.Parent = parent
	return l
end

local function build()
	local g = Instance.new("ScreenGui")
	g.Name = "FloorPortalHUD"
	g.ResetOnSpawn = false
	g.IgnoreGuiInset = true
	g.DisplayOrder = 40
	g.Enabled = false
	g.Parent = player:WaitForChild("PlayerGui")
	gui = g
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(0.5, 0)
	f.Position = UDim2.new(0.5, 0, 0, TOP)
	f.Size = UDim2.fromOffset(520, 92)
	f.BackgroundColor3 = DARK
	f.BackgroundTransparency = 0.25
	f.Parent = g
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 10)
	c.Parent = f
	local st = Instance.new("UIStroke")
	st.Color = GOLD
	st.Transparency = 0.4
	st.Parent = f
	panel = f
	titleLabel = label(f, "THE ABYSS GATE", 14, GOLD, { Position = UDim2.fromOffset(0, 8), Size = UDim2.new(1, 0, 0, 16), TextTransparency = 0.2 })
	countLabel = label(f, "", 30, PARCH, { Position = UDim2.fromOffset(0, 24), Size = UDim2.new(1, 0, 0, 32) })
	subLabel = label(f, "", 13, PARCH, { Position = UDim2.fromOffset(12, 58), Size = UDim2.new(1, -24, 0, 30),
		TextTransparency = 0.15, TextWrapped = true })
end

local function show(on: boolean)
	local g = gui
	local f = panel
	if not g or not f or on == shown then return end
	shown = on
	if on then
		g.Enabled = true
		f.Position = UDim2.new(0.5, 0, 0, TOP - 20)
		f.BackgroundTransparency = 1
		TweenService:Create(f, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ Position = UDim2.new(0.5, 0, 0, TOP), BackgroundTransparency = 0.25 }):Play()
	else
		g.Enabled = false
	end
end

function FloorPortalHUD.Init()
	build()
	Network.GetRemoteEvent(Network.Remotes.FloorPortal).OnClientEvent:Connect(function(state: any)
		if typeof(state) ~= "table" then return end
		local ready = tonumber(state.ready) or 0
		local total = tonumber(state.total) or 0
		if ready <= 0 or total <= 0 or player:GetAttribute("InLobby") ~= false then
			show(false)
			return
		end
		local mine = typeof(state.readyIds) == "table" and table.find(state.readyIds, player.UserId) ~= nil
		local waiting: { string } = if typeof(state.waiting) == "table" then state.waiting else {}
		local counts = if typeof(state.counts) == "table" then state.counts else {}
		local going = state.going
		if state.extractFloor then
			-- The choice: out with everything, or down into the corruption.
			if titleLabel then titleLabel.Text = "EXTRACT  OR  DESCEND" end
			if countLabel then
				countLabel.Text = if going == "extract" then "EXTRACTING..."
					elseif going == "descend" then "DESCENDING..."
					else `⬆ Extract {counts.extract or 0}    ·    ⬇ Descend {counts.descend or 0}    of {total}`
			end
			if subLabel then
				subLabel.Text = if going then "Everyone agrees."
					elseif #waiting > 0 then "Waiting for " .. table.concat(waiting, ", ")
					else "Everyone must stand in the same portal. Extract keeps all your loot; descending corrupts the dungeon (harder, richer)."
			end
		else
			if titleLabel then titleLabel.Text = "THE ABYSS GATE" end
			if countLabel then
				countLabel.Text = if going == "descend" or state.descending then "DESCENDING..."
					elseif going == "extract" then "ESCAPING..."
					else `{ready} / {total} ready`
			end
			if subLabel then
				subLabel.Text = if going then "Everyone's in."
					elseif #waiting > 0 and mine then "Waiting for " .. table.concat(waiting, ", ")
					elseif #waiting > 0 then "Your party waits at the portal. Step in to go."
					else ""
			end
		end
		show(true)
	end)
	-- (out of the run: nothing to count)
	player:GetAttributeChangedSignal("InLobby"):Connect(function()
		if player:GetAttribute("InLobby") ~= false then show(false) end
	end)
end

return FloorPortalHUD
