--!strict
--[[
	MobHitFeedback.luau
	Makes a hit on a mob feel like one (on this screen only):

	  • its HP bar (MobManager's MobHealthBar) shows the chunk just lost as a
	    white band that holds for a moment, then drains down to the new health
	  • the bar kicks: a quick pop in size, its frame flashing white
	  • the mob's name / HP text flashes too

	Per hit, so budgeted (FxBudget.Allow, CLAUDE.md): with hundreds of hits a
	second the band still follows the health, only the kicks are dropped.

	  MobHitFeedback.Init()
--]]

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local FxBudget = require(script.Parent:WaitForChild("FxBudget"))

local MobHitFeedback = {}

local HOLD = 0.35   -- the white band stays this long before draining
local DRAIN = 0.45  -- and takes this long to drain
local WHITE = Color3.fromRGB(255, 255, 255)

local hooked: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function hook(bb: BillboardGui)
	if hooked[bb] then return end
	local model = bb.Parent
	local hum = model and model:FindFirstChildOfClass("Humanoid")
	local bg = bb:FindFirstChild("Background") :: Frame?
	local fill = bg and bg:FindFirstChild("Fill") :: Frame?
	if not (model and hum and bg and fill) then return end
	hooked[bb] = true

	-- the white band, under the red fill, the same shape
	local band = Instance.new("Frame")
	band.Name = "DamageBand"
	band.BackgroundColor3 = WHITE
	band.BorderSizePixel = 0
	band.Position = fill.Position
	band.Size = fill.Size
	band.ZIndex = fill.ZIndex
	fill.ZIndex += 1
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 3)
	c.Parent = band
	band.Parent = bg
	local pop = Instance.new("UIScale")
	pop.Parent = bg
	local stroke = bg:FindFirstChildOfClass("UIStroke")
	local strokeColor = stroke and stroke.Color
	local name = bg:FindFirstChild("MobName") :: TextLabel?

	local last = hum.Health
	local drainAt = 0
	local drain: Tween? = nil
	hum.HealthChanged:Connect(function(health: number)
		local max = math.max(hum.MaxHealth, 1)
		local h = fill.Size.Y
		if health >= last then
			-- healed (or a fresh bar): the band just follows
			last = health
			if drain then drain:Cancel() end
			band.Size = UDim2.new(math.clamp(health / max, 0, 1), -6 * math.clamp(health / max, 0, 1), h.Scale, h.Offset)
			return
		end
		last = health
		-- The band holds where the health was (the hits of a quick combo pile
		-- into one band), then drains to the new health after a moment.
		if drain then drain:Cancel() drain = nil end
		local now = os.clock()
		drainAt = now + HOLD
		local myAt = drainAt
		task.delay(HOLD, function()
			if drainAt ~= myAt or not band.Parent then return end
			local k = math.clamp(hum.Health / max, 0, 1)
			drain = TweenService:Create(band, TweenInfo.new(DRAIN, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Size = UDim2.new(k, -6 * k, h.Scale, h.Offset) })
			;(drain :: Tween):Play()
		end)

		-- the kick (budgeted)
		if health > 0 and FxBudget.Allow("MobBarKick", 24) then
			pop.Scale = 1.12
			TweenService:Create(pop, TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
			if stroke and strokeColor then
				stroke.Color = WHITE
				TweenService:Create(stroke, TweenInfo.new(0.2), { Color = strokeColor }):Play()
			end
			if name then
				name.TextColor3 = Color3.fromRGB(255, 235, 150)
				TweenService:Create(name, TweenInfo.new(0.25), { TextColor3 = WHITE }):Play()
			end
		end
	end)
end

local function watchModel(model: Instance)
	local bb = model:FindFirstChild("MobHealthBar")
	if bb and bb:IsA("BillboardGui") then
		task.defer(hook, bb)
		return
	end
	local conn: RBXScriptConnection
	conn = model.ChildAdded:Connect(function(child)
		if child.Name == "MobHealthBar" and child:IsA("BillboardGui") then
			conn:Disconnect()
			task.defer(hook, child)
		end
	end)
end

function MobHitFeedback.Init()
	local function watchFolder(folder: Instance)
		for _, m in ipairs(folder:GetChildren()) do watchModel(m) end
		folder.ChildAdded:Connect(watchModel)
	end
	local mobs = Workspace:FindFirstChild("Mobs")
	if mobs then watchFolder(mobs) end
	Workspace.ChildAdded:Connect(function(c)
		if c.Name == "Mobs" then watchFolder(c) end
	end)
end

return MobHitFeedback
