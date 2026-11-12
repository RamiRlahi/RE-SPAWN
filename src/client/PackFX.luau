--!strict
--[[
	PackFX.luau
	One-shot bursts from the particle pack saved in the place
	(ReplicatedStorage["Particle effects"]: Slashes, Hits, Explosions,
	Lightning, ...). Each effect there is a Part holding its emitters (some
	under an Attachment); a burst clones that Part to a spot, turns its
	emitters off, optionally tints and scales them, emits once and cleans up.

		PackFX.Burst("Slashes/A - CUTS 01", cframe, { scale = 2, color = BLUE })

	Counts: an emitter named like "Sparks (30)" emits that many; otherwise a
	share of its rate x lifetime (capped). Every burst asks FxBudget first and
	emits fewer as the frame rate drops (CLAUDE.md). Missing pack or path:
	nothing happens.
--]]

local ContentProvider = game:GetService("ContentProvider")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local FxBudget = require(script.Parent:WaitForChild("FxBudget"))

local PackFX = {}

local PACK = "Particle effects"

export type Opts = {
	scale: number?,       -- particle sizes (and speeds) times this
	color: Color3?,       -- tint everything this colour (white cores kept: a sequence from white)
	solid: boolean?,      -- ... or exactly this colour, no white in it (a dark layer)
	light: number?,       -- LightEmission for every emitter (0: an unlit, dark layer)
	brightness: number?,  -- Brightness for every emitter (above 1: hot, blooms)
	fade: number?,        -- 0-1: fainter by this much
	zOffset: number?,     -- drawn in front (+) of or behind (-) other effects
	count: number?,       -- emit counts times this
	key: string?,         -- the FxBudget key (default: the path)
	perSecond: number?,   -- the budget (default 10 a second)
}

local function find(path: string): BasePart?
	local node: Instance? = ReplicatedStorage:FindFirstChild(PACK)
	for name in string.gmatch(path, "[^/]+") do
		node = node and node:FindFirstChild(name)
	end
	return if node and node:IsA("BasePart") then node else nil
end

local function scaleSeq(s: NumberSequence, k: number): NumberSequence
	local pts = {}
	for _, kp in ipairs(s.Keypoints) do
		table.insert(pts, NumberSequenceKeypoint.new(kp.Time, kp.Value * k, kp.Envelope * k))
	end
	return NumberSequence.new(pts)
end

local folder: Folder? = nil
local function fxFolder(): Folder
	if folder and folder.Parent then return folder end
	local f = Instance.new("Folder")
	f.Name = "PackFX"
	f.Parent = Workspace
	folder = f
	return f
end

-- How many one emitter sends out in a burst.
local function countOf(e: ParticleEmitter): number
	local n = tonumber(string.match(e.Name, "%((%d+)%)"))
	if n then return n end
	return math.clamp(math.floor(e.Rate * e.Lifetime.Max * 0.5 + 0.5), 1, 24)
end

function PackFX.Burst(path: string, cf: CFrame, opts: Opts?)
	local o: Opts = opts or {}
	if not FxBudget.Allow(o.key or ("pack:" .. path), o.perSecond or 10) then return end
	local src = find(path)
	if not src then return end
	local p = src:Clone()
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	p.Transparency = 1
	p.CastShadow = false
	p.CFrame = cf
	local k = o.scale or 1
	local more = (o.count or 1) * (1 - 0.5 * FxBudget.Pressure())
	local emitters: { ParticleEmitter } = {}
	local longest = 0
	for _, d in ipairs(p:GetDescendants()) do
		if d:IsA("ParticleEmitter") then
			d.Enabled = false
			if k ~= 1 then
				d.Size = scaleSeq(d.Size, k)
				d.Speed = NumberRange.new(d.Speed.Min * k, d.Speed.Max * k)
			end
			if o.color then
				d.Color = if o.solid then ColorSequence.new(o.color :: Color3)
					else ColorSequence.new(Color3.new(1, 1, 1):Lerp(o.color :: Color3, 0.35), o.color :: Color3)
			end
			if o.light then d.LightEmission = o.light :: number end
			if o.brightness then d.Brightness = o.brightness :: number end
			if o.zOffset then d.ZOffset = o.zOffset :: number end
			if o.fade and o.fade > 0 then
				local f = o.fade :: number
				local pts = {}
				for _, kp in ipairs(d.Transparency.Keypoints) do
					table.insert(pts, NumberSequenceKeypoint.new(kp.Time, 1 - (1 - kp.Value) * (1 - f), kp.Envelope))
				end
				d.Transparency = NumberSequence.new(pts)
			end
			longest = math.max(longest, d.Lifetime.Max)
			table.insert(emitters, d)
		elseif d:IsA("Light") or d:IsA("Sound") or d:IsA("LuaSourceContainer") then
			d:Destroy()
		end
	end
	p.Parent = fxFolder()
	for _, e in ipairs(emitters) do
		local n = math.max(1, math.floor(countOf(e) * more + 0.5))
		e:Emit(n)
	end
	Debris:AddItem(p, longest + 0.5)
end

-- The pack's textures loaded ahead (so a first burst isn't blank).
function PackFX.Preload(paths: { string })
	local list = {}
	for _, path in ipairs(paths) do
		local src = find(path)
		if src then table.insert(list, src) end
	end
	if #list > 0 then
		task.spawn(function() pcall(function() ContentProvider:PreloadAsync(list) end) end)
	end
end

return PackFX
