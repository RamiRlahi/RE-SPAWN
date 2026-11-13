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
local VariantFX = require(script.Parent:WaitForChild("VariantFX"))

local VfxKit = {}

local player = Players.LocalPlayer

-- VFX variants: the library's textures have their colours baked in, so
-- VariantFX's ramp recolouring can't restyle them. Instead the caster's
-- variant picks a matching texture set: the ink ("dark") variant uses the
-- `ink` textures (black bodies, white contour and core) and dark floor marks.
-- The caster is found the way VariantFX does it: the character nearest the
-- effect when it appears.
local function variantPalette(pos: Vector3, palette: string): (string, boolean)
	local owner = VariantFX.OwnerNear(pos)
	local p = owner and VariantFX.PaletteFor(owner)
	if p and p.ink then return "ink", true end
	return palette, false
end

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
	-- (the ink variant: a dark shadow on the floor instead of a light)
	local _, ink = variantPalette(pos, "")
	local key = `glow_{if ink then "ink" else color:ToHex()}_{r1(size)}_{r1(life)}_{wide and 1 or 0}`
	local att, pe = emitter(key, function(pe)
		flat(pe)
		pe.Texture = tex.id
		pe.Color = ColorSequence.new(if ink then Color3.new(0, 0, 0) else color)
		pe.LightEmission = if ink then 0 else 1
		pe.Brightness = if ink then 1 else 1.5
		pe.Lifetime = NumberRange.new(life)
		pe.Size = NumberSequence.new(size)
		pe.Transparency = if ink then NumberSequence.new({ nsk(0, 0.35), nsk(0.4, 0.55), nsk(1, 1) })
			else NumberSequence.new({ nsk(0, 0.1), nsk(0.3, 0.45), nsk(1, 1) })
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

-- A shockwave ring racing out flat across the floor to `radius` over `life`
-- (the Ring flipbook: thin white-hot leading edge, coloured body, dark smoky
-- wake inside, breaking into arcs as it ages). The texture's ring reaches 46%
-- of the cell, so the particle is sized for the ring to end at `radius`.
function VfxKit.FloorRing(pos: Vector3, palette: string, radius: number, life: number)
	if not FxBudget.Allow("kitRing", 12) then return end
	palette = variantPalette(pos, palette)
	local tex = (VfxAssets.Ring :: any)[palette] or VfxAssets.Ring.fire
	local size = radius * 2 / 0.92
	local key = `ring_{palette}_{r1(size)}_{r1(life * 10)}`
	local att, pe = emitter(key, function(pe)
		flat(pe)
		pe.Texture = tex.id
		pe.FlipbookLayout = tex.layout :: Enum.ParticleFlipbookLayout
		pe.FlipbookMode = Enum.ParticleFlipbookMode.OneShot
		pe.LightEmission = 0.4
		pe.Brightness = 3
		pe.Lifetime = NumberRange.new(life)
		pe.Size = NumberSequence.new(size)
	end)
	att.WorldPosition = pos + Vector3.new(0, 0.18, 0)
	pe:Emit(1)
end

-- ── The flash frame ─────────────────────────────────────────────────────────
-- The starburst turned to the camera: f0 full, f1 stretched, f2 thin, then
-- gone (2x2 flipbook over `life`, ~3 frames by default).
function VfxKit.Flash(pos: Vector3, palette: string, size: number, life: number?, tint: Color3?)
	if not FxBudget.Allow("kitFlash", 20) then return end
	palette = variantPalette(pos, palette)
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
	if #points == 0 then return end
	palette = variantPalette(points[1], palette)
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
		-- (through ParticleEmitters: a Decal request for these image assets
		-- fails with "No asset content representation found", and the
		-- texture never counts as loaded)
		local holders: { Instance } = {}
		local function add(t: any)
			if typeof(t) == "table" then
				if typeof(t.id) == "string" then
					local pe = Instance.new("ParticleEmitter")
					pe.Texture = t.id
					table.insert(holders, pe)
				else
					for _, v in pairs(t) do add(v) end
				end
			end
		end
		-- the mesh textures first (a mesh waits, hidden, for its texture), then
		-- everything else
		local A = VfxAssets :: any
		for _, set in ipairs({ A.Swirl, A.Ribbon, A.Sweep, A.FlameFeather, A.Cone, A.Facet }) do add(set) end
		local first = holders
		holders = {}
		pcall(function() game:GetService("ContentProvider"):PreloadAsync(first) end)
		add(VfxAssets)
		pcall(function() game:GetService("ContentProvider"):PreloadAsync(holders) end)
		for _, d in ipairs(first) do d:Destroy() end
		for _, d in ipairs(holders) do d:Destroy() end
	end)
end

-- Has `texture` arrived? A textured MeshPart drawn before its texture loads
-- renders as a plain white shape (seen in Studio on a first cast), so meshes
-- stay hidden until it has. Asks for it once if it hasn't.
local ContentProvider = game:GetService("ContentProvider")
local asked: { [string]: boolean } = {}
local function texReady(texture: string): boolean
	if ContentProvider:GetAssetFetchStatus(texture) == Enum.AssetFetchStatus.Success then return true end
	if not asked[texture] then
		asked[texture] = true
		task.spawn(function()
			-- (through a ParticleEmitter: a Decal request for these image assets
			-- fails with "No asset content representation found")
			local pe = Instance.new("ParticleEmitter")
			pe.Texture = texture
			pcall(function() ContentProvider:PreloadAsync({ pe }) end)
			pe:Destroy()
			asked[texture] = nil
		end)
	end
	return false
end
VfxKit.TexReady = texReady

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
			if not ok then warn("[VfxKit] effect step failed:", done) end
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
	palette = variantPalette(cf.Position, palette)
	local tex = (VfxAssets.Sweep :: any)[palette] or VfxAssets.Sweep.fire
	if not texReady(tex.id) then return end -- (never a white shape)
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

-- A tornado (clip 3): three tornado meshes with the palette's ribbon texture
-- (torn see-through sheets, flames licking up inside, sharp dark strokes)
-- spinning 3-4.6 turns a second, the middle one the other way; slivers flung
-- off it; a glow on the floor following it. `getCenter` gives the floor point
-- under it each frame (nil = stop). Returns stop(). (The caller adds the fire
-- inside it: FireKnightController's flame core.)
function VfxKit.Tornado(getCenter: () -> Vector3?, radius: number, height: number, palette: string, dur: number): () -> ()
	local start = getCenter()
	local ink = false
	if start then palette, ink = variantPalette(start, palette) end
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
	glow.Color = ColorSequence.new(if ink then Color3.new(0, 0, 0)
		elseif palette == "ice" then Color3.fromRGB(80, 160, 255) else Color3.fromRGB(255, 70, 35))
	glow.LightEmission = if ink then 0 else 1
	glow.LightInfluence = 0
	glow.Brightness = 1.3
	glow.Lifetime = NumberRange.new(0.45)
	glow.Size = NumberSequence.new(radius * 2.6)
	glow.Transparency = NumberSequence.new({ nsk(0, 0.55), nsk(0.5, 0.6), nsk(1, 1) })
	glow.Rate = 10
	glow.LockedToPart = false
	glow.Parent = ga
	glowHolder.Parent = root()

	-- three ribbon layers (clip 3 up close: many torn see-through sheets over
	-- each other): the outer and inner glow, the middle one is lit so its dark
	-- strokes stay dark between them, and turns the other way
	type Layer = { part: MeshPart, r: number, h: number, speed: number, extra: number }
	local layers: { Layer } = {}
	local function addLayer(mp: MeshPart?, r: number, h: number, speed: number, extra: number, lit: boolean)
		if not mp then return end
		if lit then mp.Material = Enum.Material.SmoothPlastic end
		mp.Transparency = 1
		mp.Parent = root()
		table.insert(layers, { part = mp, r = r, h = h, speed = speed, extra = extra })
	end
	-- (the torn-sheet meshes are the dim body inside now; the swirl arcs below
	-- are the tornado's walls)
	addLayer(outer, 0.62, 0.9, 3.0, 0.35, false)
	addLayer(inner, 0.45, 0.82, -3.8, 0.2, true)
	if outer then outer:Destroy() end -- (one body layer is enough under the arcs)
	table.remove(layers, 1)
	local spin: { number } = {}
	for i = 1, #layers do spin[i] = i * 2.1 end
	local readyAt: number? = if texReady(tex.id) then -1 else nil

	-- THE WALLS (clip 3 at full size): dozens of thin crescent streaks swirling
	-- almost flat around it at every height, each on the swept_shell crescent
	-- with the swirl texture (several thin streaks: yellow-white inner line,
	-- red-orange body, one near-black). Each arc spins at its own speed and
	-- tilt, and respawns with a new height, radius and tilt every ~0.3-0.7 s,
	-- so the pattern churns like the clip's. A few big flat ones swirl on the
	-- floor round its base.
	local swirlTex = ((VfxAssets :: any).Swirl[palette] or (VfxAssets :: any).Swirl.fire).id
	local shellSpec = MESHES.swept_shell
	type Arc = { part: MeshPart, h: number, r: number, tilt: CFrame, ang: number, speed: number, age: number, life: number, floor: boolean }
	local arcs: { Arc } = {}
	local nArcs = math.floor(18 * (1 - 0.5 * FxBudget.Pressure()) + 0.5)
	local function reroll(a: Arc, first: boolean)
		if a.floor then
			a.h = 0.25 + math.random() * 0.4
			a.r = radius * (1.05 + math.random() * 0.35)
			a.tilt = CFrame.Angles(math.rad(math.random(-4, 4)), 0, math.rad(math.random(-4, 4)))
		else
			-- ONE funnel: narrow at the floor, widening upward, every arc on it
			-- (only a little jitter, so the silhouette holds together)
			local f = math.random() ^ 0.85
			a.h = height * (0.06 + 0.92 * f)
			a.r = radius * (0.42 + 0.58 * f ^ 0.8) * (0.94 + math.random() * 0.12)
			-- ONE helix: every arc pitched the same way (its head higher than its
			-- tail), so together they read as a single rising spiral, not rings
			a.tilt = CFrame.Angles(-math.rad(14 + math.random() * 6), 0, 0)
		end
		a.ang = math.random() * math.pi * 2
		-- all the same way, faster near the narrow base (a real vortex)
		a.speed = (2.2 + math.random() * 0.8) * math.pi * 2 * (1.3 - 0.5 * math.clamp(a.h / math.max(height, 1e-3), 0, 1))
		a.age = if first then math.random() * 0.3 else 0
		a.life = 0.3 + math.random() * 0.4
	end
	-- (built as soon as the mesh template has loaded: a cast in the first
	-- moments of a session gets its walls a beat late instead of never)
	local function buildArcs()
		if #arcs > 0 then return end
		for _ = 1, nArcs do -- (no flat floor arcs: they read as loose rings)
			local mp = mesh("swept_shell", swirlTex)
			if not mp then return end
			mp.Transparency = 1
			mp.Parent = root()
			local a: Arc = { part = mp, h = 0, r = 0, tilt = CFrame.identity, ang = 0, speed = 0, age = 0, life = 1, floor = false }
			reroll(a, true)
			table.insert(arcs, a)
		end
	end
	buildArcs()
	-- (performance: resizing a MeshPart is costly, so an arc's Size is only set
	-- when it changes by more than a few percent (while the tornado grows, and
	-- on a reroll); CFrames go out in one BulkMoveTo a frame; Transparency is
	-- only written when it changes)
	local arcParts: { BasePart } = {}
	local arcCFrames: { CFrame } = {}
	local sizeK: { [Arc]: number } = {}
	local lastTr: { [Arc]: number } = {}
	local function placeArc(i: number, a: Arc, center: Vector3, grow: number, trBase: number)
		local r = a.r * (0.35 + 0.65 * grow)
		local k = r / SHELL_OUTER
		local p = a.part
		local kNow = sizeK[a]
		if not kNow or math.abs(kNow - k) > kNow * 0.04 then
			sizeK[a] = k
			p.Size = shellSpec.native * Vector3.new(k, k * 0.6, k)
		end
		k = sizeK[a]
		-- (the pitch is applied in the arc's own turning frame, so it stays a
		-- rising helix as the arc spins)
		local frame = CFrame.new(center + Vector3.new(0, a.h * (0.4 + 0.6 * grow), 0)) * CFrame.Angles(0, a.ang, 0) * a.tilt
		arcParts[i] = p
		arcCFrames[i] = frame * CFrame.new(-SHELL_CENTER_X * k, 0, 0)
		-- each arc: fades in fast, holds, fades out as it's rerolled
		local x = a.age / a.life
		local env = math.clamp(x / 0.15, 0, 1) * math.clamp((1 - x) / 0.3, 0, 1)
		-- (rounded to cut property writes, but never below 0.02: at exactly 0
		-- Roblox ignores the texture's alpha and the arc renders as a solid band)
		local tr = math.max(math.floor(math.clamp(1 - (1 - trBase) * env, 0.02, 1) * 20 + 0.5) / 20, 0.02)
		if lastTr[a] ~= tr then
			lastTr[a] = tr
			p.Transparency = tr
		end
	end
	local function place(p: MeshPart, center: Vector3, r: number, h: number, ang: number, tr: number)
		p.Size = Vector3.new(spec.native.X * r / 1.05, h, spec.native.Z * r / 1.05)
		p.CFrame = CFrame.new(center + Vector3.new(0, h / 2 - 0.2, 0)) * CFrame.Angles(0, ang, 0)
		p.Transparency = tr
	end

	-- slivers flung off it (clip 3: long sharp red and black streaks): spark
	-- streaks stretched along their flight, from a holder riding the funnel
	local sliverAtt = Instance.new("Attachment")
	sliverAtt.Parent = glowHolder
	local slivers: { ParticleEmitter } = {}
	for i, texSet in ipairs({ VfxAssets.Spark, VfxAssets.Spark }) do
		local dark = i == 2
		local st = (texSet :: any)[if dark then "ink" else palette] or VfxAssets.Spark.fire
		local e = Instance.new("ParticleEmitter")
		e.Texture = st.id
		e.Orientation = Enum.ParticleOrientation.VelocityParallel
		e.Rotation = NumberRange.new(90)                      -- (the spark's long axis along its flight)
		-- (an Attachment emits from a point: out of the funnel's middle, in a
		-- wide cone that's mostly sideways and up)
		e.EmissionDirection = Enum.NormalId.Top
		e.SpreadAngle = Vector2.new(78, 78)
		e.Speed = NumberRange.new(16, 30)
		e.Drag = 1.5
		e.Acceleration = Vector3.new(0, 6, 0)
		e.Lifetime = NumberRange.new(0.25, 0.45)
		e.Size = NumberSequence.new({ nsk(0, 1.6), nsk(1, 0.4) })
		e.Transparency = NumberSequence.new({ nsk(0, 0), nsk(0.7, 0.2), nsk(1, 1) })
		e.LightEmission = if dark then 0 else 1
		e.LightInfluence = 0
		e.Brightness = if dark then 1 else 3
		e.Rate = if dark then 5 else 9 -- (a few: many read as random spikes)
		e.LockedToPart = false
		e.Parent = sliverAtt
		table.insert(slivers, e)
	end

	run(function(dt, t)
		now = t
		local c = getCenter()
		if not c or t >= stopAt + 0.35 then
			for _, l in ipairs(layers) do l.part:Destroy() end
			for _, a in ipairs(arcs) do a.part:Destroy() end
			glow.Enabled = false
			for _, e in ipairs(slivers) do e.Enabled = false end
			task.delay(0.6, function() glowHolder:Destroy() end)
			return true
		end
		glowHolder.CFrame = CFrame.new(c + Vector3.new(0, 0.12, 0))
		local grow = ease(t / 0.35)
		local fadeIn = 1 - grow
		local fadeOut = math.clamp((t - stopAt) / 0.35, 0, 1)
		if fadeOut > 0 then
			glow.Enabled = false
			for _, e in ipairs(slivers) do e.Enabled = false end
		end
		local tr = math.clamp(0.02 + math.max(fadeIn, fadeOut) * 0.98, 0.02, 1)
		-- (hidden until the ribbon texture has arrived: never a white shape;
		-- it fades in from then)
		if not texReady(tex.id) then
			tr = 1
			readyAt = nil
		elseif not readyAt then
			readyAt = t
		end
		if readyAt and t - readyAt < 0.25 then tr = math.max(tr, 1 - (t - readyAt) / 0.25) end
		if #arcs == 0 and fadeOut == 0 then buildArcs() end
		local arcTr = if texReady(swirlTex) then tr else 1
		for i, a in ipairs(arcs) do
			a.age += dt
			if a.age >= a.life and fadeOut == 0 then reroll(a, false) end
			a.ang += dt * a.speed
			placeArc(i, a, c, grow, arcTr)
		end
		Workspace:BulkMoveTo(arcParts, arcCFrames, Enum.BulkMoveMode.FireCFrameChanged)
		local wobble = 0.06 * math.sin(t * 7)
		-- (the slivers leave from the funnel's middle height, on its rim)
		sliverAtt.Position = Vector3.new(0, height * 0.45 * (0.5 + 0.5 * grow), 0)
		for i, l in ipairs(layers) do
			-- ~3 turns a second and more (clip 3: the strands change every frame)
			spin[i] += dt * math.pi * 2 * l.speed
			place(l.part, c, radius * l.r * (0.4 + 0.6 * grow) * (1 + wobble * (if i % 2 == 0 then -1 else 1)),
				height * l.h * (0.5 + 0.5 * grow), spin[i], math.clamp(tr + l.extra, 0, 1))
		end
		return false
	end)
	-- stop(): fade out from now (0.35 s)
	return function()
		stopAt = math.min(stopAt, now)
	end
end

return VfxKit
