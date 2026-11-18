--!strict
--[[
	AirShock.luau
	Air shockwaves: the burst of air a cut or a landing throws out. No light,
	no fire: a shimmering ForceField dome that swells and thins away, a flat
	pressure ring rolling out along the plane, and a crisp white rim on it.

		AirShock.Wave(cf, radius, { dome = true, ring = true, life = 0.4 })

	The ring lies in `cf`'s XZ plane (CFrame.new(p) = flat on the floor; a
	CFrame.lookAt(p, p + dir) * CFrame.Angles(math.pi / 2, 0, 0) = upright,
	facing down `dir`, like a sonic boom ring).

	Performance (CLAUDE.md): one budget key per caller (`key`, `perSecond`),
	two parts and one arc at most per wave, no lights, gone after `life`.
--]]

local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local Debris = game:GetService("Debris")

local FxBudget = require(script.Parent:WaitForChild("FxBudget"))
local SwordFX = require(script.Parent:WaitForChild("SwordFX"))

local AirShock = {}

local AIR = Color3.fromRGB(205, 228, 255)
local RIM = Color3.fromRGB(235, 246, 255)

export type Opts = {
	dome: boolean?, -- the swelling dome (default true)
	ring: boolean?, -- the flat pressure ring and its rim (default true)
	life: number?, -- seconds (default 0.4)
	color: Color3?,
	key: string?,
	perSecond: number?,
}

local function folder(): Instance
	local f = Workspace:FindFirstChild("AirShockFX")
	if not f then
		f = Instance.new("Folder")
		f.Name = "AirShockFX"
		f.Parent = Workspace
	end
	return f :: Instance
end

local function shell(shape: Enum.PartType, color: Color3): Part
	local p = Instance.new("Part")
	p.Name = "AirShock"
	p.Shape = shape
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	p.CastShadow = false
	p.Material = Enum.Material.ForceField -- (the shimmer of moving air)
	p.Color = color
	return p
end

function AirShock.Wave(cf: CFrame, radius: number, opts: Opts?)
	local o: Opts = opts or {}
	if not FxBudget.Allow(o.key or "airShock", o.perSecond or 12) then return end
	local life = o.life or 0.4
	local color = o.color or AIR
	local out = TweenInfo.new(life, Enum.EasingStyle.Quart, Enum.EasingDirection.Out)
	local parent = folder()

	if o.dome ~= false then
		local d = shell(Enum.PartType.Ball, color)
		d.Size = Vector3.one * math.max(1, radius * 0.25)
		d.CFrame = cf
		d.Transparency = 0.15
		d.Parent = parent
		TweenService:Create(d, out, { Size = Vector3.one * radius * 2, Transparency = 1 }):Play()
		Debris:AddItem(d, life + 0.05)
	end

	if o.ring ~= false then
		-- the pressure ring: a thin disc rolling out flat along the plane
		local r = shell(Enum.PartType.Cylinder, color)
		local flat = cf * CFrame.Angles(0, 0, math.pi / 2) -- (a cylinder's axis is X: turned to the plane's normal)
		r.Size = Vector3.new(0.25, radius * 0.3, radius * 0.3)
		r.CFrame = flat
		r.Transparency = 0.05
		r.Parent = parent
		TweenService:Create(r, TweenInfo.new(life * 1.15, Enum.EasingStyle.Quart, Enum.EasingDirection.Out),
			{ Size = Vector3.new(0.08, radius * 2.3, radius * 2.3), Transparency = 1 }):Play()
		Debris:AddItem(r, life * 1.15 + 0.05)
		-- its rim: a crisp thin line of white air at the front of the wave
		local r0 = math.max(0.6, radius * 0.15)
		SwordFX.Arc({ cf = cf, radius = r0, arc = 359, width = math.clamp(radius * 0.035, 0.12, 0.45), color = color, core = RIM,
			life = life, draw = 0.001, grow = radius * 1.15 / r0 - 1 })
	end
end

return AirShock
