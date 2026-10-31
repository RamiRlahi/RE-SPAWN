--!strict
--[[
	Summons/Rig.luau
	The Summoner's beasts drawn on the client from their exported models
	(Summons/Models: tools/summons/export.py from the artist's GLBs).

	  local rig = Rig.new(data, scale, parent)
	  rig.L[i]          bone i's own turn this frame (written by the animation)
	  rig.move          the root bone's extra offset this frame (a CFrame:
	                    hops, lunges, the baked move's own travel)
	  rig:render(cf)    places every part: `cf` is the beast's spot on the
	                    ground (feet at its origin, facing its look)
	  rig:clip(t, w)    blends the baked signature move at `t` seconds over
	                    the procedural pose by `w` (0..1)
	  rig:fade(a)       0 solid .. 1 gone (the summon and dismiss)
	  rig:glow(k)       the glowing parts flare toward white (0..1)

	Bones go parents first; a bone's world frame is its parent's, moved by
	its rest offset, turned by its own L. Every part is anchored and moved
	in one BulkMoveTo a frame.
--]]

local Workspace = game:GetService("Workspace")

local Rig = {}
Rig.__index = Rig

export type Clip = { fps: number, length: number, frames: number, tracks: { [number]: { CFrame } }, moves: { Vector3 }? }

type Data = any

-- (each model's baked move, unpacked into CFrames once)
local clips: { [string]: Clip } = {}

local function clipOf(data: Data, byName: { [string]: number }): Clip
	local cached = clips[data.name]
	if cached then return cached end
	local a = data.anim
	local c: Clip = { fps = a.fps, length = a.length, frames = a.frames, tracks = {}, moves = nil }
	local rest = data.bones[1]
	for name, tr in pairs(a.tracks) do
		local i = byName[name]
		if not i then continue end
		local list: { CFrame } = {}
		local withT = tr[1] == "qt"
		local stride = if withT then 7 else 4
		local moves: { Vector3 } = {}
		for f = 0, a.frames - 1 do
			local o = 2 + f * stride
			table.insert(list, CFrame.new(0, 0, 0, tr[o], tr[o + 1], tr[o + 2], tr[o + 3]))
			if withT then
				-- (the root's travel, relative to where it rests)
				table.insert(moves, Vector3.new(tr[o + 4] - rest[3], tr[o + 5] - rest[4], tr[o + 6] - rest[5]))
			end
		end
		c.tracks[i] = list
		if withT and i == 1 then c.moves = moves end
	end
	clips[data.name] = c
	return c
end

function Rig.new(data: Data, scale: number, parent: Instance?): any
	local model = Instance.new("Model")
	model.Name = "Summon_" .. data.name
	local bones, byName = {}, {}
	for i, b in ipairs(data.bones) do
		byName[b[1]] = i
		table.insert(bones, { name = b[1], parent = b[2], rest = Vector3.new(b[3], b[4], b[5]) * scale })
	end
	local parts, offsets, boneOf, glows, base = {}, {}, {}, {}, {}
	for _, d in ipairs(data.parts) do
		local p = Instance.new(if d[2] == "W" then "CornerWedgePart" else "Part") :: BasePart
		p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
		p.Size = Vector3.new(d[15], d[16], d[17]) * scale
		p.Color = Color3.fromRGB(d[18], d[19], d[20])
		p.Material = if d[21] then Enum.Material.Neon else Enum.Material.SmoothPlastic
		if p:IsA("Part") then p.TopSurface, p.BottomSurface = Enum.SurfaceType.Smooth, Enum.SurfaceType.Smooth end
		-- (only the big pieces of the body throw a shadow)
		p.CastShadow = not d[21] and math.max(d[15], d[16], d[17]) * scale > 1.6
		p.Parent = model
		table.insert(parts, p)
		table.insert(offsets, CFrame.new(d[3] * scale, d[4] * scale, d[5] * scale, d[6], d[7], d[8], d[9], d[10], d[11], d[12], d[13], d[14]))
		table.insert(boneOf, d[1])
		table.insert(base, p.Color)
		if d[21] then table.insert(glows, #parts) end
	end
	local L = table.create(#bones, CFrame.identity)
	local self = setmetatable({
		data = data, scale = scale, model = model, bones = bones, byName = byName,
		parts = parts, offsets = offsets, boneOf = boneOf, glows = glows, base = base,
		L = L, move = CFrame.identity, W = table.create(#bones, CFrame.identity),
		cfs = table.create(#parts, CFrame.identity), clipData = clipOf(data, byName),
		faded = 0, glowK = 0,
	}, Rig)
	model.Parent = parent or Workspace
	return self
end

-- Bone index by name (nil if this beast has no such bone).
function Rig:bone(name: string): number?
	return self.byName[name]
end

-- Every bone back to rest.
function Rig:reset()
	local L = self.L
	for i = 1, #L do L[i] = CFrame.identity end
	self.move = CFrame.identity
end

-- The baked move at `t` seconds, blended in by `w`; `travel` scales the
-- root's own travel per axis (a wider circle for the Skyfeather's cyclone).
function Rig:clip(t: number, w: number, travel: Vector3?)
	if w <= 0 then return end
	local c = self.clipData
	local f = math.clamp(t * c.fps, 0, c.frames - 1)
	local i = math.floor(f)
	local a = f - i
	local j = math.min(i + 1, c.frames - 1)
	local L = self.L
	for bi, list in pairs(c.tracks) do
		local cf = list[i + 1]:Lerp(list[j + 1], a)
		L[bi] = if w >= 1 then cf else L[bi]:Lerp(cf, w)
	end
	if c.moves then
		local m = c.moves[i + 1]:Lerp(c.moves[j + 1], a) * self.scale
		if travel then m *= travel end
		local mv = CFrame.new(m)
		self.move = if w >= 1 then mv else self.move:Lerp(mv, w)
	end
end

function Rig:clipLength(): number
	return self.clipData.length
end

-- Bone i's frame in the world, as of the last render.
function Rig:world(i: number): CFrame
	return self.W[i]
end

function Rig:render(cf: CFrame)
	local bones, L, W = self.bones, self.L, self.W
	for i, b in ipairs(bones) do
		if b.parent == 0 then
			W[i] = cf * CFrame.new(b.rest) * self.move * L[i]
		else
			W[i] = W[b.parent] * CFrame.new(b.rest) * L[i]
		end
	end
	local cfs, offsets, boneOf = self.cfs, self.offsets, self.boneOf
	for k = 1, #offsets do
		cfs[k] = W[boneOf[k]] * offsets[k]
	end
	-- (a WorldModel's own world for the menu's previews)
	local world = self.model:FindFirstAncestorWhichIsA("WorldRoot") or Workspace
	world:BulkMoveTo(self.parts, cfs, Enum.BulkMoveMode.FireCFrameChanged)
end

function Rig:fade(a: number)
	a = math.clamp(a, 0, 1)
	if math.abs(a - self.faded) < 0.01 then return end
	self.faded = a
	for _, p in ipairs(self.parts) do p.Transparency = a end
end

local WHITE = Color3.new(1, 1, 1)
function Rig:glow(k: number)
	k = math.clamp(k, 0, 1)
	if math.abs(k - self.glowK) < 0.02 then return end
	self.glowK = k
	for _, i in ipairs(self.glows) do
		self.parts[i].Color = self.base[i]:Lerp(WHITE, k * 0.75)
	end
end

-- Every part tinted toward `c` by `k` (a hit flash, the fusion's light).
function Rig:tint(c: Color3, k: number)
	for i, p in ipairs(self.parts) do
		p.Color = self.base[i]:Lerp(c, math.clamp(k, 0, 1))
	end
	self.glowK = -1
end

function Rig:destroy()
	self.model:Destroy()
end

return Rig
