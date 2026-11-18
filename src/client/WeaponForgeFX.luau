--!strict
--[[
	WeaponForgeFX.luau
	A weapon shows how far it's been forged (the attribute "WeaponPlus" on its
	owner: the worn power weapon's level, LootManager). On the held weapon's
	blade (the tool's longest part), for every player:

	  +3..+5   gold sparks drifting off the edge
	  +6..+8   ... and embers rising from it
	  +9..+10  ... and flames licking up the blade

	A few particles a weapon, a handful of players: cheap enough not to need
	the FxBudget (no lights). Checked once a second, per player.

	WeaponForgeFX.Init()
--]]

local Players = game:GetService("Players")

local WeaponForgeFX = {}

local TAG = "ForgeFX"

local function tierOf(plus: number): number
	return if plus >= 9 then 3 elseif plus >= 6 then 2 elseif plus >= 3 then 1 else 0
end

local function blade(tool: Tool): BasePart?
	local best: BasePart? = nil
	local size = 0
	for _, d in ipairs(tool:GetDescendants()) do
		if d:IsA("BasePart") then
			-- (the blade: the longest part, not the bulkiest: a pommel can outweigh a thin blade)
			local v = math.max(d.Size.X, d.Size.Y, d.Size.Z)
			if v > size then best, size = d, v end
		end
	end
	return best
end

local function emitter(parent: BasePart, props: { [string]: any })
	local e = Instance.new("ParticleEmitter")
	e.Name = TAG
	e.LightEmission = 1
	e.LockedToPart = false
	for k, v in pairs(props) do (e :: any)[k] = v end
	e.Parent = parent
end

local function dress(part: BasePart, tier: number)
	for _, c in ipairs(part:GetChildren()) do
		if c.Name == TAG then c:Destroy() end
	end
	part:SetAttribute("ForgeTier", tier)
	if tier >= 1 then
		emitter(part, {
			Texture = "rbxasset://textures/particles/sparkles_main.dds",
			Color = ColorSequence.new(Color3.fromRGB(255, 220, 140)),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.22), NumberSequenceKeypoint.new(1, 0) }),
			Lifetime = NumberRange.new(0.3, 0.6), Rate = 4 + tier * 2, Speed = NumberRange.new(0.5, 1.5),
			SpreadAngle = Vector2.new(180, 180),
		})
	end
	if tier >= 2 then
		emitter(part, {
			Texture = "rbxasset://textures/particles/sparkles_main.dds",
			Color = ColorSequence.new(Color3.fromRGB(255, 140, 50), Color3.fromRGB(255, 70, 20)),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.14), NumberSequenceKeypoint.new(1, 0.04) }),
			Lifetime = NumberRange.new(0.8, 1.3), Rate = 8, Speed = NumberRange.new(1, 2.5),
			Acceleration = Vector3.new(0, 4, 0), SpreadAngle = Vector2.new(30, 30),
		})
	end
	if tier >= 3 then
		emitter(part, {
			Texture = "rbxasset://textures/particles/fire_main.dds",
			Color = ColorSequence.new(Color3.fromRGB(255, 190, 80), Color3.fromRGB(255, 60, 20)),
			Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(1, 1) }),
			Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.6), NumberSequenceKeypoint.new(1, 0.1) }),
			Lifetime = NumberRange.new(0.25, 0.45), Rate = 22, Speed = NumberRange.new(0.5, 1.5),
			Acceleration = Vector3.new(0, 6, 0), Rotation = NumberRange.new(0, 360), RotSpeed = NumberRange.new(-90, 90),
		})
	end
end

local function check(p: Player)
	local char = p.Character
	local tool = char and char:FindFirstChildOfClass("Tool")
	if not tool then return end
	local part = blade(tool)
	if not part then return end
	local plus = p:GetAttribute("WeaponPlus")
	local tier = tierOf(if typeof(plus) == "number" then plus else 0)
	if part:GetAttribute("ForgeTier") ~= tier then dress(part, tier) end
end

function WeaponForgeFX.Init()
	task.spawn(function()
		while true do
			for _, p in ipairs(Players:GetPlayers()) do
				pcall(check, p)
			end
			task.wait(1)
		end
	end)
end

return WeaponForgeFX
