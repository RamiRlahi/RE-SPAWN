--[[
	TicketToast.luau
	A Pull Ticket dropped from a kill (GachaManager → TicketDrop): it is
	already in your inventory; this only says so. A small gold plaque slides
	in at the right edge with the new total, then fades. Drops are rare (a few
	an hour, capped server-side), so nothing here needs budgeting.

	TicketToast.Init()
--]]

local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))

local player = Players.LocalPlayer

local TicketToast = {}

local TIER_TEXT = { normal = "", elite = "ELITE DROP", miniboss = "BEHEMOTH DROP", boss = "BOSS DROP" }
local stack = 0

local function show(payload: any)
	local g = player:WaitForChild("PlayerGui"):FindFirstChild("TicketToast") :: ScreenGui?
	if not g then
		g = Instance.new("ScreenGui")
		g.Name = "TicketToast"
		g.ResetOnSpawn = false
		g.DisplayOrder = 170
		g.Parent = player.PlayerGui
	end
	local slot = stack
	stack += 1
	local f = Instance.new("Frame")
	f.AnchorPoint = Vector2.new(1, 0)
	f.Position = UDim2.new(1, 260, 0.3, slot * 62)
	f.Size = UDim2.fromOffset(240, 54)
	f.BackgroundColor3 = Color3.fromRGB(40, 28, 20)
	f.BackgroundTransparency = 0.08
	f.Parent = g
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(255, 205, 110)
	stroke.Thickness = 2
	stroke.Parent = f
	Instance.new("UICorner", f).CornerRadius = UDim.new(0, 6)
	local function text(t: string, y: number, size: number, color: Color3)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromOffset(12, y)
		l.Size = UDim2.new(1, -24, 0, size + 4)
		l.Font = Enum.Font.Antique
		l.TextSize = size
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.TextColor3 = color
		l.TextStrokeTransparency = 0.4
		l.Text = t
		l.Parent = f
	end
	local tier = TIER_TEXT[payload.tier] or ""
	text(`+{payload.amount or 1} PULL TICKET{if tier ~= "" then "  ·  " .. tier else ""}`, 6, 18, Color3.fromRGB(255, 225, 150))
	text(`{payload.total or 0} in your inventory`, 30, 14, Color3.fromRGB(222, 196, 156))
	TweenService:Create(f, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Position = UDim2.new(1, -16, 0.3, slot * 62) }):Play()
	task.delay(3.2, function()
		TweenService:Create(f, TweenInfo.new(0.4), { Position = UDim2.new(1, 260, 0.3, slot * 62) }):Play()
		task.delay(0.45, function()
			f:Destroy()
			stack = math.max(0, stack - 1)
		end)
	end)
end

function TicketToast.Init()
	Network.GetRemoteEvent(Network.Remotes.TicketDrop).OnClientEvent:Connect(function(payload)
		if typeof(payload) == "table" then show(payload) end
	end)
end

return TicketToast
