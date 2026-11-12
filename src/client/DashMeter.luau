--!strict
--[[
	DashMeter.luau
	The dash charges, drawn round the reticle: a quarter circle of short
	curved bars on its left, one bar per charge (DashController.Charges). A
	bar is bright while its charge is held. The one coming back fills along
	its length, and an empty one is a dim slot.

	  DashMeter.Attach(frame, radius)  draws the bars round `frame`'s centre
	                                   (the top-down cursor, the classic crosshair)

	One RenderStepped drives every meter. It writes a property only when the
	value changes (CLAUDE.md: UI per frame).
--]]

local RunService = game:GetService("RunService")

local DashController = require(script.Parent:WaitForChild("DashController"))

local DashMeter = {}

local FULL = Color3.fromRGB(255, 235, 190)  -- (the reticle's own colour)
local EMPTY = Color3.fromRGB(20, 20, 25)
local FROM, TO = 132, 228                  -- degrees round the reticle (0 right, 90 down): a quarter circle on its left
local THICK = 5
local GAP_DEG = 4                          -- between two bars

type Bar = { slot: Frame, fill: Frame, shown: number }
type Meter = { frame: GuiObject, radius: number, bars: { Bar }, count: number }
local meters: { Meter } = {}
local conn: RBXScriptConnection? = nil

local function build(m: Meter, count: number)
	for _, b in ipairs(m.bars) do b.slot:Destroy() end
	table.clear(m.bars)
	m.count = count
	local span = (TO - FROM - GAP_DEG * (count - 1)) / count
	local len = 2 * math.pi * m.radius * span / 360
	for i = 1, count do
		-- (bar 1 is the top one: the first charge to go; they refill from the bottom up)
		local mid = TO - (i - 0.5) * span - (i - 1) * GAP_DEG
		local a = math.rad(mid)
		local slot = Instance.new("Frame")
		slot.Name = "DashCharge" .. i
		slot.AnchorPoint = Vector2.new(0.5, 0.5)
		slot.Size = UDim2.fromOffset(THICK, len)
		slot.Position = UDim2.new(0.5, math.cos(a) * m.radius, 0.5, math.sin(a) * m.radius)
		slot.Rotation = mid - 180 -- (along the circle)
		slot.BackgroundColor3 = EMPTY
		slot.BackgroundTransparency = 0.45
		slot.BorderSizePixel = 0
		local st = Instance.new("UIStroke")
		st.Color = EMPTY
		st.Thickness = 1
		st.Transparency = 0.3
		st.Parent = slot
		local fill = Instance.new("Frame")
		fill.Name = "Fill"
		fill.AnchorPoint = Vector2.new(0.5, 1)
		fill.Position = UDim2.fromScale(0.5, 1)
		fill.Size = UDim2.fromScale(1, 1)
		fill.BackgroundColor3 = FULL
		fill.BorderSizePixel = 0
		fill.Parent = slot
		slot.Parent = m.frame
		table.insert(m.bars, { slot = slot, fill = fill, shown = 1 })
	end
end

local function step()
	local stock, max = DashController.Charges()
	for i = #meters, 1, -1 do
		local m = meters[i]
		if not m.frame.Parent then
			table.remove(meters, i)
			continue
		end
		if m.count ~= max then build(m, max) end
		for k, b in ipairs(m.bars) do
			-- (bar 1 is the top: held charges are the bottom ones, the top empties first)
			local held = max - k + 1
			local f = math.clamp(stock - (held - 1), 0, 1)
			f = math.floor(f * 20 + 0.5) / 20 -- (5% steps: no write every frame)
			if f ~= b.shown then
				b.shown = f
				b.fill.Size = UDim2.fromScale(1, f)
				b.fill.BackgroundTransparency = if f >= 1 then 0 else 0.35
			end
		end
	end
	if #meters == 0 and conn then
		conn:Disconnect()
		conn = nil
	end
end

function DashMeter.Attach(frame: GuiObject, radius: number)
	local m: Meter = { frame = frame, radius = radius, bars = {}, count = 0 }
	table.insert(meters, m)
	if not conn then conn = RunService.RenderStepped:Connect(step) end
end

return DashMeter
