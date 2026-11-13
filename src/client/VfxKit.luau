--!strict
--[[
	VfxKit.luau
	The shared building blocks of the reference-standard effects
	(docs/vfx-reference-timing.md), on the generated library (VfxAssets):

	  VfxKit.FloorGlow(pos, color, size, life, wide?)   a glow lying on the floor (frame 0)
	  VfxKit.Stain(kind, pos, size, life)               "scorch" | "frost" | "holy" ground stain
	  VfxKit.Flash(pos, palette, size, life?, tint?)    the starburst flash frame (2x2 flipbook)
	  VfxKit.Puffs(points, palette, size, life?)        torn explosion chunks (hot spots, soot, wisps)
	  VfxKit.Sweep(cf, radius, palette, sweep, life?)   a 3D slash: the swept_shell mesh in a swing's plane
	  VfxKit.Tornado(getCenter, radius, height, palette, dur) -> stop()
	                                                    spinning tornado meshes + a floor glow that follows

	Conventions: `palette` is a VfxAssets palette ("fire", "ice", "holy", "void").
	Sweep's `cf` is laid out like FireFX.Slash / SwordFX arcs: the swing's centre
	and plane, the arc bulging toward cf's -Z in its XZ plane, `sweep` 1 = right
	to left, -1 = left to right.

	Budgets (CLAUDE.md): every call goes through FxBudget, and particles run on
	pooled emitters (created once, moved, Emit()ed). Meshes are cloned from a
	template made once per mesh (AssetService:CreateMeshPartAsync; a script
	can't set MeshId), and are animated by one RenderStepped updater.
--]]

local AssetService = game:GetService("AssetService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local VfxAssets = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("VfxAssets"))
local FxBudget = require(script.Parent:WaitForChild("FxBudget"))

local VfxKit = {}

local player = Players.LocalPlayer

local function nsk(t: number, v: number): NumberSequenceKeypoint
	return NumberSequenceKeypoint.new(t, v)
end

-- ── Folder ──────────────────────────────────────────────────────────────────
local folder: Folder? = nil
local function root(): Folder
	if folder and folder.Parent then return folder end
	local f = Instance.new("Folder")
	f.Name = "VfxKit"
	f.Parent = Workspace
	folder = f
	return f
end

local function lowDetail(): boolean
	return player:GetAttribute("Setting_lowDetailVFX") == true or player:GetAttribute("PerfMode") == true
end

-- ── Pooled emitters ─────────────────────────────────────────────────────────
-- One emitter per distinct look (its key), moved to each use and Emit()ed.
-- Particles are world-space once emitted, so moving the holder is safe.
local pool: { [string]: { att: Attachment, pe: ParticleEmitter } } = {}

local function emitter(key: string, build: (ParticleEmitter) -> ()): (Attachment, ParticleEmitter)
	local e = pool[key]
	if e and e.att.Parent and e.att.Parent.Parent then return e.att, e.pe end
	local holder = Instance.new("Part")
	holder.Name = key
	holder.Anchored, holder.CanCollide, holder.CanQuery, holder.CanTouch, holder.CastShadow = true, false, false, false, false
	holder.Transparency = 1
	holder.Size = Vector3.one * 0.2
	holder.Parent = root()
	local att = Instance.new("Attachment")
	att.Parent = holder
	local pe = Instance.new("ParticleEmitter")
	pe.Rate = 0
	pe.LightInfluence = 0
	pe.LockedToPart = false
	build(pe)
	pe.Parent = att
	pool[key] = { att = att, pe = pe }
	return att, pe
end

local function flat(pe: ParticleEmitter)
	pe.EmissionDirection = Enum.NormalId.Top
	pe.Orientation = Enum.ParticleOrientation.VelocityPerpendicular
	pe.Speed = NumberRange.new(0.01)
	pe.SpreadAngle = Vector2.zero
	pe.Rotation = NumberRange.new(0, 360)
end

local function r1(x: number): string
	return string.format("%.1f", x)
end

-- ── Floor layers ────────────────────────────────────────────────────────────
-- A glow on the floor, full on frame 0 and gone over `life` (the polearm clip:
-- the whole floor tints on the impact frame, gone by ~f12-15).
function VfxKit.FloorGlow(pos: Vector3, color: Color3, size: number, life: number, wide: boolean?)
	if not FxBudget.Allow("kitGlow", 20) then return end
	local tex = if wide then VfxAssets.Glow.wide else VfxAssets.Glow.soft
	local key = `glow_{color:ToHex()}_{r1(size)}_{r1(life)}_{wide and 1 or 0}`
	local att, pe = emitter(key, function(pe)
		flat(pe)
		pe.Texture = tex.id
		pe.Color = ColorSequence.new(color)
		pe.LightEmission = 1
		pe.Brightness = 1.5
		pe.Lifetime = NumberRange.new(life)
		pe.Size = NumberSequence.new(size)
		pe.Transparency = NumberSequence.new({ nsk(0, 0.1), nsk(0.3, 0.45), nsk(1, 1) })
	end)
	att.WorldPosition = pos + Vector3.new(0, 0.12, 0)
	pe:Emit(1)
end

function VfxKit.Stain(kind: string, pos: Vector3, size: number, life: number)
	if lowDetail() or not FxBudget.Allow("kitStain", 6) then return end
	local tex = (VfxAssets.Stain :: any)[kind]
	if not tex then return end
	local key = `stain_{kind}_{r1(size)}_{r1(life)}`
	local att, pe = emitter(key, function(pe)
		flat(pe)
		pe.Texture = tex.id
		pe.LightEmission = 0
		pe.LightInfluence = 0.4
		pe.Brightness = 1.4
		pe.Lifetime = NumberRange.new(life)
		pe.Size = NumberSequence.new({ nsk(0, size * 0.7), nsk(0.08, size), nsk(1, size * 1.05) })
		pe.Transparency = NumberSequence.new({ nsk(0, 0.05), nsk(0.6, 0.15), nsk(1, 1) })
	end)
	att.WorldPosition = pos + Vector3.new(0, 0.06, 0)
	pe:Emit(1)
end

-- ── The flash frame ─────────────────────────────────────────────────────────
-- The starburst turned to the camera: f0 full, f1 stretched, f2 thin, then
-- gone (2x2 flipbook over `life`, ~3 frames by default).
function VfxKit.Flash(pos: Vector3, palette: string, size: number, life: number?, tint: Color3?)
	if not FxBudget.Allow("kitFlash", 20) then return end
	local tex = (VfxAssets.Starburst :: any)[palette] or VfxAssets.Starburst.fire
	local lt = life or 0.1
	local key = `flash_{palette}_{r1(size)}_{r1(lt * 10)}_{(tint or Color3.new(1, 1, 1)):ToHex()}`
	local att, pe = emitter(key, function(pe)
		pe.Texture = tex.id
		pe.FlipbookLayout = tex.layout :: Enum.ParticleFlipbookLayout
		pe.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
		pe.Color = ColorSequence.new(tint or Color3.new(1, 1, 1))
		pe.LightEmission = 1
		pe.Brightness = 4
		pe.Lifetime = NumberRange.new(lt)
		pe.Size = NumberSequence.new(size)
		pe.Speed = NumberRange.new(0)
		pe.Rotation = NumberRange.new(0, 360)
		pe.ZOffset = 2
	end)
	att.WorldPosition = pos
	pe:Emit(1)
end

-- ── Torn explosion chunks ───────────────────────────────────────────────────
-- One puff per point (the polearm clip f1-f9: chunks along the arc, white-hot
-- spots, dark brown specks, burning out into soot and curly wisps). Lit by
-- LightEmission 0.15 only, so the dark parts stay dark.
function VfxKit.Puffs(points: { Vector3 }, palette: string, size: number, life: number?)
	local tex = (VfxAssets.Puff :: any)[palette] or VfxAssets.Puff.fire
	local lt = life or 0.5
	local key = `puff_{palette}_{r1(size)}_{r1(lt * 10)}`
	local att, pe = emitter(key, function(pe)
		pe.Texture = tex.id
		pe.FlipbookLayout = tex.layout :: Enum.ParticleFlipbookLayout
		pe.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
		pe.LightEmission = 0.15
		pe.Brightness = 2.6
		pe.Lifetime = NumberRange.new(lt * 0.85, lt)
		pe.Size = NumberSequence.new({ nsk(0, size * 0.7), nsk(0.4, size), nsk(1, size * 1.1) })
		pe.Speed = NumberRange.new(0.5, 2)
		pe.SpreadAngle = Vector2.new(180, 180)
		pe.Acceleration = Vector3.new(0, 3, 0)
		pe.Drag = 3
		pe.Rotation = NumberRange.new(-25, 25)
		pe.ZOffset = 1
	end)
	for _, p in ipairs(points) do
		if not FxBudget.Allow("kitPuff", 60) then break end
		att.WorldPosition = p
		pe:Emit(1)
	end
end

-- ── Meshes ──────────────────────────────────────────────────────────────────
type MeshSpec = { id: string, native: Vector3 }
local MESHES: { [string]: MeshSpec } = {
	swept_shell = { id = VfxAssets.Mesh.swept_shell, native = Vector3.new(1.64, 0.16, 2.8) },
	tornado = { id = VfxAssets.Mesh.tornado, native = Vector3.new(1.9765, 2.2994, 1.8502) },
	crystal_cluster = { id = VfxAssets.Mesh.crystal_cluster, native = Vector3.new(1.6401, 1.3018, 1.4525) },
	shock_cone = { id = VfxAssets.Mesh.shock_cone, native = Vector3.new(1.12, 1.12, 1) },
	dash_tunnel = { id = VfxAssets.Mesh.dash_tunnel, native = Vector3.new(0.9939, 0.9952, 1.182) },
}
-- (swept_shell, measured in Studio: the arc's circle centre is +0.578 studs
-- along X from the part's centre at native size, the outer edge (the texture's
-- hot top row) at radius 1.4, the inner at 0.75; it bulges toward -X, its head
-- (u = 1) at +Z)
local SHELL_CENTER_X, SHELL_OUTER = 0.578, 1.4

local templates: { [string]: MeshPart } = {}
local loading: { [string]: boolean } = {}

local function loadTemplate(name: string)
	if templates[name] or loading[name] then return end
	local spec = MESHES[name]
	if not spec or spec.id == "" then return end
	loading[name] = true
	task.spawn(function()
		local ok, mp = pcall(function()
			return AssetService:CreateMeshPartAsync(Content.fromUri(spec.id))
		end)
		if ok and mp then
			mp.Anchored, mp.CanCollide, mp.CanQuery, mp.CanTouch, mp.CastShadow = true, false, false, false, false
			mp.DoubleSided = true
			mp.Material = Enum.Material.Neon
			mp.Color = Color3.new(1, 1, 1)
			mp.Transparency = 1
			templates[name] = mp
		else
			warn("[VfxKit] mesh failed to load:", name, mp)
		end
		loading[name] = nil
	end)
end

-- Load every mesh and texture now (they're small): call once at start. (A
-- mesh drawn before its texture arrives shows as a plain white shape.)
function VfxKit.Preload()
	for name in pairs(MESHES) do loadTemplate(name) end
	task.spawn(function()
		local decals: { Instance } = {}
		local function add(t: any)
			if typeof(t) == "table" then
				if typeof(t.id) == "string" then
					local d = Instance.new("Decal")
					d.Texture = t.id
					table.insert(decals, d)
				else
					for _, v in pairs(t) do add(v) end
				end
			end
		end
		add(VfxAssets)
		pcall(function() game:GetService("ContentProvider"):PreloadAsync(decals) end)
		for _, d in ipairs(decals) do d:Destroy() end
	end)
end

-- A copy of a mesh with `texture`, or nil while it's still loading.
local function mesh(name: string, texture: string): MeshPart?
	local t = templates[name]
	if not t then loadTemplate(name); return nil end
	local mp = t:Clone()
	mp.TextureID = texture
	return mp
end
VfxKit.Mesh = mesh

-- One updater for every animated mesh: step(dt, t) returns true when done.
type Job = { t: number, step: (number, number) -> boolean }
local jobs: { Job } = {}
local running = false
local function run(step: (number, number) -> boolean)
	table.insert(jobs, { t = 0, step = step })
	if running then return end
	running = true
	local conn: RBXScriptConnection
	conn = RunService.RenderStepped:Connect(function(dt)
		for i = #jobs, 1, -1 do
			local j = jobs[i]
			j.t += dt
			local ok, done = pcall(j.step, dt, j.t)
			if not ok or done then table.remove(jobs, i) end
		end
		if #jobs == 0 then
			running = false
			conn:Disconnect()
		end
	end)
end

local function ease(t: number): number -- quart out
	return 1 - (1 - math.clamp(t, 0, 1)) ^ 4
end

-- A 3D slash: the swept_shell mesh with the palette's sweep texture (white-hot
-- outer edge, saturated body, dark inner core) laid in the swing's plane. It
-- is already mostly drawn on frame 0, widens a little as it goes and fades
-- out over `life`.
function VfxKit.Sweep(cf: CFrame, radius: number, palette: string, sweep: number, life: number?)
	if not FxBudget.Allow("kitSweep", 16) then return end
	local tex = (VfxAssets.Sweep :: any)[palette] or VfxAssets.Sweep.fire
	local mp = mesh("swept_shell", tex.id)
	if not mp then return end
	local lt = life or 0.32
	local spec = MESHES.swept_shell
	-- the mesh's -X (its bulge) onto cf's -Z; its head (+Z) onto cf's -X for a
	-- right-to-left sweep, flipped over for left-to-right
	local frame = cf * CFrame.Angles(0, -math.pi / 2, 0)
	if sweep < 0 then frame *= CFrame.Angles(math.pi, 0, 0) end
	local k1 = radius / SHELL_OUTER
	local function place(k: number, tr: number)
		mp.Size = spec.native * k
		mp.CFrame = frame * CFrame.new(-SHELL_CENTER_X * k, 0, 0)
		mp.Transparency = tr
	end
	place(k1 * 0.9, 0.02)
	mp.Parent = root()
	run(function(_dt, t)
		local a = t / lt
		if a >= 1 or not mp.Parent then mp:Destroy(); return true end
		place(k1 * (0.9 + 0.14 * ease(a * 2.5)), 0.02 + 0.98 * math.clamp((a - 0.3) / 0.7, 0, 1) ^ 1.4)
		return false
	end)
end

-- A tornado (clip 3): two tornado meshes with the palette's ribbon texture
-- (orange body, white-hot strands, dark strands) spinning against each other
-- about 3 turns a second, a glow on the floor following it. `getCenter` gives
-- the floor point under it each frame (nil = stop). Returns stop().
function VfxKit.Tornado(getCenter: () -> Vector3?, radius: number, height: number, palette: string, dur: number): () -> ()
	local tex = (VfxAssets.Ribbon :: any)[palette] or VfxAssets.Ribbon.fire
	local outer = mesh("tornado", tex.id)
	local inner = mesh("tornado", tex.id)
	local spec = MESHES.tornado
	local stopAt = dur
	local now = 0
	-- the floor glow: a slow stream of glow particles from a holder that follows
	local glowHolder = Instance.new("Part")
	glowHolder.Name = "TornadoGlow"
	glowHolder.Anchored, glowHolder.CanCollide, glowHolder.CanQuery, glowHolder.CanTouch, glowHolder.CastShadow = true, false, false, false, false
	glowHolder.Transparency = 1
	glowHolder.Size = Vector3.one * 0.2
	local ga = Instance.new("Attachment")
	ga.Parent = glowHolder
	local glow = Instance.new("ParticleEmitter")
	flat(glow)
	glow.Texture = VfxAssets.Glow.wide.id
	glow.Color = ColorSequence.new(if palette == "ice" then Color3.fromRGB(80, 160, 255) else Color3.fromRGB(255, 70, 35))
	glow.LightEmission = 1
	glow.LightInfluence = 0
	glow.Brightness = 1.3
	glow.Lifetime = NumberRange.new(0.45)
	glow.Size = NumberSequence.new(radius * 2.6)
	glow.Transparency = NumberSequence.new({ nsk(0, 0.55), nsk(0.5, 0.6), nsk(1, 1) })
	glow.Rate = 10
	glow.LockedToPart = false
	glow.Parent = ga
	glowHolder.Parent = root()

	local parts: { MeshPart } = {}
	if outer then table.insert(parts, outer) end
	if inner then table.insert(parts, inner) end
	for _, p in ipairs(parts) do p.Transparency = 1; p.Parent = root() end
	local spin = { 0, math.pi }
	local function place(p: MeshPart, center: Vector3, r: number, h: number, ang: number, tr: number)
		p.Size = Vector3.new(spec.native.X * r / 1.05, h, spec.native.Z * r / 1.05)
		p.CFrame = CFrame.new(center + Vector3.new(0, h / 2 - 0.2, 0)) * CFrame.Angles(0, ang, 0)
		p.Transparency = tr
	end
	run(function(dt, t)
		now = t
		local c = getCenter()
		if not c or t >= stopAt + 0.35 then
			for _, p in ipairs(parts) do p:Destroy() end
			glow.Enabled = false
			task.delay(0.6, function() glowHolder:Destroy() end)
			return true
		end
		glowHolder.CFrame = CFrame.new(c + Vector3.new(0, 0.12, 0))
		local grow = ease(t / 0.35)
		local fadeIn = 1 - grow
		local fadeOut = math.clamp((t - stopAt) / 0.35, 0, 1)
		if fadeOut > 0 then glow.Enabled = false end
		local tr = math.clamp(0.02 + math.max(fadeIn, fadeOut) * 0.98, 0.02, 1)
		spin[1] += dt * math.pi * 2 * 3.0      -- ~3 turns a second (clip 3: the strands change every frame)
		spin[2] -= dt * math.pi * 2 * 3.8
		local wobble = 0.06 * math.sin(t * 7)
		if outer then place(outer, c, radius * (0.4 + 0.6 * grow) * (1 + wobble), height * (0.5 + 0.5 * grow), spin[1], tr) end
		if inner then place(inner, c, radius * 0.6 * (0.4 + 0.6 * grow), height * 0.82 * (0.5 + 0.5 * grow), spin[2], math.clamp(tr + 0.15, 0, 1)) end
		return false
	end)
	-- stop(): fade out from now (0.35 s)
	return function()
		stopAt = math.min(stopAt, now)
	end
end

return VfxKit
