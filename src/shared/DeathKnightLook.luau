--!strict
--[[
	DeathKnightLook.luau
	The Death Knight's look, the Soul Reaper, built from parts (no uploaded
	assets) after the class sheet: about 80% obsidian, charcoal and black,
	15% ash and cold steel, 5% icy spectral blue.

	  BuildGraveblade()  his weapon (the tool keeps the name "Graveblade"): a
	                     huge two-handed chained maul. A long black haft wound
	                     with chain; a massive head of stacked, spiked black
	                     blocks, spectral light burning through the cracks
	                     between them, a glowing skull set in each face,
	                     chains bound round it, ghostly blue flame and black
	                     mist pouring off it; a jagged spearhead on the butt.
	  Dress(char)        the plate, over an R6 body: a crowned helm with
	                     narrow eye slits glowing ice-blue, layered spiked
	                     pauldrons, a heavy cuirass crossed with chains,
	                     gauntlets, tassets, ragged black cloth, sabatons,
	                     and black mist leaking from all of it. (The cape is
	                     cloth: ClothCape.DEATH_KNIGHT, on the client.)
	  Undress(char)      take it off, giving back everything it hid.

	The plate is built clearly bigger than the body on every side, every piece
	welded to its own limb, and the body under it (head, limbs, the avatar's
	hats and hair) is hidden: whatever pose the body takes (an attack, a seat
	at the campfire) the plate goes with it and nothing of the avatar can poke
	through. Neighbouring pieces never share a face (no flicker).

	Used by the server (the real character, seen by everyone: DeathKnightServer)
	and the menus (ClassLook, on client-only copies).
--]]

local DeathKnightLook = {}

local ATTR = "DKLook"        -- on everything added (cleanup)
local HIDDEN = "DKHidden"    -- the transparency of what was hidden under it
DeathKnightLook.ATTR = ATTR
DeathKnightLook.MIST = "DKMist" -- the armor's mist emitters (the client thickens them in Dread)

-- The sheet's palette.
local OBSIDIAN = Color3.fromRGB(8, 11, 16)     -- #080B10
local CHARCOAL = Color3.fromRGB(23, 29, 39)    -- #171D27
local ASH = Color3.fromRGB(53, 63, 77)         -- #353F4D
local STEEL = Color3.fromRGB(100, 124, 153)    -- #647C99
local SPECTRAL = Color3.fromRGB(112, 201, 245) -- #70C9F5
local FROST = Color3.fromRGB(185, 232, 255)    -- #B9E8FF
local VOID = Color3.fromRGB(3, 4, 6)
DeathKnightLook.OBSIDIAN = OBSIDIAN
DeathKnightLook.CHARCOAL = CHARCOAL
DeathKnightLook.ASH = ASH
DeathKnightLook.STEEL = STEEL
DeathKnightLook.SPECTRAL = SPECTRAL
DeathKnightLook.FROST = FROST

local TEX_SMOKE = "rbxasset://textures/particles/smoke_main.dds"
local M = Enum.Material

local function R(d: number): number return math.rad(d) end

-- A part at `offset` from `base`, welded to it.
local function piece(parent: Instance, base: BasePart, name: string, size: Vector3, offset: CFrame, color: Color3,
	material: Enum.Material?, shape: string?): BasePart
	local p: BasePart
	if shape == "wedge" then
		p = Instance.new("WedgePart")
	elseif shape == "corner" then
		p = Instance.new("CornerWedgePart")
	else
		p = Instance.new("Part")
	end
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material or M.Metal
	p.CanCollide, p.CanTouch, p.CanQuery, p.Massless = false, false, false, true
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CFrame = base.CFrame * offset
	p:SetAttribute(ATTR, true)
	local w = Instance.new("WeldConstraint")
	w.Part0 = base
	w.Part1 = p
	w.Parent = p
	p.Parent = parent
	return p
end

-- A flat triangular spike (a fin): its triangle stands in `at`'s XY plane,
-- base at the bottom, point up (`at` is the middle of its box), `thick` deep.
local function fin(parent: Instance, base: BasePart, name: string, at: CFrame, width: number, height: number, thick: number,
	color: Color3, material: Enum.Material?)
	-- (two wedges back to back, their upright faces meeting under the point)
	local frame = at * CFrame.Angles(0, math.pi / 2, 0)
	piece(parent, base, name, Vector3.new(thick, height, width / 2), frame * CFrame.new(0, 0, -width / 4), color, material, "wedge")
	piece(parent, base, name, Vector3.new(thick, height, width / 2), frame * CFrame.new(0, 0, width / 4) * CFrame.Angles(0, math.pi, 0),
		color, material, "wedge")
end

-- A run of chain links from `a` to `b` (`base`'s space), each link turned a
-- quarter round from the last.
local function chain(parent: Instance, base: BasePart, a: Vector3, b: Vector3, link: number?, color: Color3?)
	local L = link or 0.3
	local d = b - a
	local n = math.max(1, math.floor(d.Magnitude / (L * 0.82)))
	for i = 0, n do
		local p = a + d * (i / n)
		local cf = CFrame.lookAt(p, p + d.Unit) * CFrame.Angles(0, 0, if i % 2 == 0 then 0 else math.pi / 2)
		piece(parent, base, "ChainLink", Vector3.new(L * 0.36, L * 0.62, L), cf, color or ASH, M.Metal)
	end
end

-- A loop of chain round a box (`base`'s space): a ring at `y` hugging a box
-- `w` wide and `d` deep.
local function chainRing(parent: Instance, base: BasePart, y: number, w: number, d: number, tilt: number?)
	local hw, hd = w / 2, d / 2
	local pts = { Vector3.new(-hw, 0, -hd), Vector3.new(hw, 0, -hd), Vector3.new(hw, 0, hd), Vector3.new(-hw, 0, hd) }
	local turn = CFrame.new(0, y, 0) * CFrame.Angles(0, 0, R(tilt or 0))
	for i = 1, 4 do
		local a, b = turn * pts[i], turn * pts[i % 4 + 1]
		chain(parent, base, a, b, 0.28)
	end
end

-- Black mist leaking off a piece (the body's own breath of it; Dread
-- thickens it on the client).
local function mist(at: BasePart, rate: number, rise: number)
	local e = Instance.new("ParticleEmitter")
	e.Name = DeathKnightLook.MIST
	e.Texture = TEX_SMOKE
	e.Color = ColorSequence.new(OBSIDIAN, CHARCOAL)
	e.LightEmission = 0
	e.LightInfluence = 0.6
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.9), NumberSequenceKeypoint.new(1, 2.4) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.55),
		NumberSequenceKeypoint.new(1, 1) })
	e.Lifetime = NumberRange.new(1.1, 1.8)
	e.Speed = NumberRange.new(0.2, 0.7)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = Vector3.new(0, rise, 0)
	e.Drag = 1.5
	e.Rotation = NumberRange.new(0, 360)
	e.RotSpeed = NumberRange.new(-25, 25)
	e.Shape = Enum.ParticleEmitterShape.Box
	e.Rate = rate
	e:SetAttribute("BaseRate", rate)
	e:SetAttribute(ATTR, true)
	e.Parent = at
end

-- ═════════════════════════════════════════════════════════════════════════════
-- The maul
-- ═════════════════════════════════════════════════════════════════════════════
-- Handle space (as the Berserker's greatsword, so the two-handed hold works
-- the same): the head is down -Y from the hands, the butt's spearhead up +Y;
-- the Grip holds it on the wrapped haft. Laid out at full size, built at
-- MAUL_SCALE. The head's glowing core is the part named "Blade" (the Dread
-- look, the ghostfire and the mist find it), with GraveBase / GraveTip across
-- the head along the haft (the swing trail, and where the chain leaves it).
local MAUL_SCALE = 0.8
local GRIP_Y = 3.95
local HEAD_Y = -5.2  -- the head's middle
local BUTT_Y = 6.7   -- the haft's top end (the spearhead above)

-- Cold spectral fire (always on: it's the weapon's look): a white-hot core
-- burning out to electric blue, then deep blue at its edges; drawn out into
-- tall sharp tongues that rise and trail behind it as it moves.
local FLAME_CORE = Color3.fromRGB(215, 248, 255)
local FLAME_BLUE = Color3.fromRGB(45, 160, 255)
local FLAME_DEEP = Color3.fromRGB(12, 34, 120)
-- (tuned in game, filmed close up against the reference: drawn toward the
-- camera so the tongues lie over the head instead of sinking into it)
local function ghostflame(at: BasePart, rate: number, size: number, zOffset: number?): ParticleEmitter
	local K = NumberSequenceKeypoint.new
	local e = Instance.new("ParticleEmitter")
	e.Name = "Ghostflame"
	e.Texture = "rbxasset://textures/particles/fire_main.dds"
	e.Color = ColorSequence.new({ ColorSequenceKeypoint.new(0, FLAME_CORE), ColorSequenceKeypoint.new(0.18, Color3.fromRGB(110, 205, 255)),
		ColorSequenceKeypoint.new(0.65, Color3.fromRGB(40, 140, 255)), ColorSequenceKeypoint.new(1, FLAME_DEEP) })
	e.LightEmission = 1
	e.LightInfluence = 0
	e.Brightness = 2.2
	e.Size = NumberSequence.new({ K(0, size * 0.3), K(0.3, size), K(1, 0) })
	e.Transparency = NumberSequence.new({ K(0, 0.05), K(0.7, 0.35), K(1, 1) })
	-- (stretched tall: sharp tongues, not round puffs)
	e.Squash = NumberSequence.new(-0.5)
	e.Lifetime = NumberRange.new(0.45, 0.8)
	e.Speed = NumberRange.new(0.5, 1.5)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Acceleration = Vector3.new(0, 9, 0)
	e.Rotation = NumberRange.new(-15, 15)
	e.RotSpeed = NumberRange.new(-30, 30)
	e.ZOffset = zOffset or 0.3
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	e.LockedToPart = false
	e.Rate = rate
	e.Parent = at
	return e
end

function DeathKnightLook.BuildGraveblade(): Tool
	local S = MAUL_SCALE
	local tool = Instance.new("Tool")
	tool.Name = "Graveblade"
	tool.CanBeDropped = false
	tool.Grip = CFrame.new(0, GRIP_Y * S, -0.49) * CFrame.Angles(math.pi, 0, 0)
	local handle = Instance.new("Part")
	handle.Name = "Handle"
	handle.Size = Vector3.new(0.4, 1.8, 0.4) * S
	handle.Transparency = 1
	handle.CanCollide, handle.CanTouch, handle.CanQuery, handle.Massless = false, false, false, true
	handle.Parent = tool

	-- (pieces laid out at full size, scaled as they're made)
	-- (the whole maul turned a quarter round the haft as it's built, so the
	-- head's striking faces, not its broad sides, lead every swing)
	local TURN = CFrame.Angles(0, math.rad(90), 0)
	local function bp(name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: string?): BasePart
		local q = piece(tool, handle, name, size * S, TURN * CFrame.new(cf.Position * S) * cf.Rotation, color, material, shape)
		q:SetAttribute(ATTR, nil)
		return q
	end
	-- a flat spike, its point along `at`'s +Y
	local function bfin(name: string, at: CFrame, width: number, height: number, thick: number, color: Color3)
		local frame = at * CFrame.Angles(0, math.pi / 2, 0)
		bp(name, Vector3.new(thick, height, width / 2), frame * CFrame.new(0, 0, -width / 4), color, M.Metal, "wedge")
		bp(name, Vector3.new(thick, height, width / 2), frame * CFrame.new(0, 0, width / 4) * CFrame.Angles(0, math.pi, 0), color, M.Metal, "wedge")
	end
	local function bchain(a: Vector3, b: Vector3, link: number, color: Color3)
		local d = b - a
		local n = math.max(1, math.floor(d.Magnitude / (link * 0.82)))
		-- (black iron catching a little of the blue light round it)
		local tinted = color:Lerp(SPECTRAL, 0.12)
		for i = 0, n do
			local q = a + d * (i / n)
			local l = bp("ChainLink", Vector3.new(link * 0.36, link * 0.62, link),
				CFrame.lookAt(q, q + d.Unit) * CFrame.Angles(0, 0, if i % 2 == 0 then 0 else math.pi / 2), tinted, M.Metal)
			l.Reflectance = 0.12
		end
	end
	-- (which way is out from each face, for the spikes: the frame's +Y)
	local OUT: { [string]: CFrame } = {
		px = CFrame.Angles(0, 0, R(-90)), nx = CFrame.Angles(0, 0, R(90)),
		pz = CFrame.Angles(R(90), 0, 0), nz = CFrame.Angles(R(-90), 0, 0),
		ny = CFrame.Angles(R(180), 0, 0),
	}

	-- ── The head ──
	-- A glowing spectral core, and round it a 3 × 2 × 2 stack of black blocks
	-- with narrow gaps between them: the light burns out through the cracks.
	local core = bp("Blade", Vector3.new(4.4, 3.0, 3.0), CFrame.new(0, HEAD_Y, 0), SPECTRAL, M.Neon)
	local BX, BY, BZ, GAP = 1.42, 1.5, 1.5, 0.24
	local n = 0
	for ix = -1, 1 do
		for iy = -1, 1, 2 do
			for iz = -1, 1, 2 do
				n += 1
				local c = Vector3.new(ix * (BX + GAP), HEAD_Y + iy * (BY + GAP) / 2, iz * (BZ + GAP) / 2)
				-- (each a hair different, a little askew: hewn, not cast)
				local j = (n % 3) * 0.02
				bp("HeadBlock", Vector3.new(BX - j, BY + j, BZ - j * 0.5),
					CFrame.new(c) * CFrame.Angles(R((n % 2) * 2 - 1), R(((n * 7) % 5) - 2), 0),
					if n % 3 == 0 then OBSIDIAN else CHARCOAL, M.Slate)
			end
		end
	end
	-- the striking faces: a heavy ash-steel plate on each end, a raised boss
	for _, sx in ipairs({ -1, 1 }) do
		local x = sx * (1.5 * BX + GAP + 0.14)
		bp("Face", Vector3.new(0.3, 2.9, 2.9), CFrame.new(x, HEAD_Y, 0), ASH, M.Metal)
		bp("FaceBoss", Vector3.new(0.24, 1.5, 1.5), CFrame.new(x + sx * 0.2, HEAD_Y, 0) * CFrame.Angles(R(45), 0, 0), CHARCOAL, M.Metal)
		for _, c in ipairs({ { 1, 1 }, { 1, -1 }, { -1, 1 }, { -1, -1 } }) do
			bfin("FaceSpike", CFrame.new(x + sx * 0.5, HEAD_Y + c[1] * 1.05, c[2] * 1.05) * (if sx > 0 then OUT.px else OUT.nx),
				0.42, 0.75, 0.2, OBSIDIAN)
		end
	end
	-- spikes off the blocks all round
	local spikes: { { any } } = {
		{ Vector3.new(-1.6, HEAD_Y + 0.7, 1.68), "pz" }, { Vector3.new(1.6, HEAD_Y - 0.7, 1.68), "pz" },
		{ Vector3.new(1.6, HEAD_Y + 0.7, -1.68), "nz" }, { Vector3.new(-1.6, HEAD_Y - 0.7, -1.68), "nz" },
		{ Vector3.new(-1.6, HEAD_Y - 1.68, 0.7), "ny" }, { Vector3.new(1.6, HEAD_Y - 1.68, -0.7), "ny" },
		{ Vector3.new(0, HEAD_Y - 1.68, 0), "ny" },
	}
	for _, sp in ipairs(spikes) do
		bfin("HeadSpike", CFrame.new(sp[1] :: Vector3) * OUT[sp[2] :: string] * CFrame.new(0, 0.3, 0), 0.4, 0.7, 0.2, ASH)
	end
	-- a dark iron skull set in the front and back, ringed with contained
	-- spectral light, its eye sockets blazing
	for _, sz in ipairs({ -1, 1 }) do
		local z = sz * (BZ + GAP / 2 + 0.06)
		bp("SkullSetting", Vector3.new(1.3, 1.36, 0.1), CFrame.new(0, HEAD_Y, z), SPECTRAL, M.Neon)
		bp("Skull", Vector3.new(0.9, 0.94, 0.12), CFrame.new(0, HEAD_Y + 0.03, z + sz * 0.05), CHARCOAL, M.Metal)
		for _, ex in ipairs({ -0.2, 0.2 }) do
			bp("SkullEye", Vector3.new(0.26, 0.24, 0.1), CFrame.new(ex, HEAD_Y + 0.1, z + sz * 0.1), FLAME_CORE, M.Neon)
		end
		bp("SkullJaw", Vector3.new(0.46, 0.1, 0.1), CFrame.new(0, HEAD_Y - 0.25, z + sz * 0.1), FLAME_BLUE, M.Neon)
	end
	-- thin fissures of blue light cracking through the black blocks
	local FISSURES = {
		{ Vector3.new(-2.1, HEAD_Y + 0.9, 1.64), Vector3.new(-1.4, HEAD_Y + 0.3, 1.64) },
		{ Vector3.new(-1.4, HEAD_Y + 0.3, 1.64), Vector3.new(-1.0, HEAD_Y + 0.55, 1.64) },
		{ Vector3.new(1.2, HEAD_Y - 0.4, 1.64), Vector3.new(1.9, HEAD_Y - 1.0, 1.64) },
		{ Vector3.new(1.9, HEAD_Y + 1.1, -1.64), Vector3.new(1.3, HEAD_Y + 0.5, -1.64) },
		{ Vector3.new(-1.3, HEAD_Y - 0.5, -1.64), Vector3.new(-2.0, HEAD_Y - 0.2, -1.64) },
		{ Vector3.new(-2.0, HEAD_Y - 0.2, -1.64), Vector3.new(-2.2, HEAD_Y - 0.9, -1.64) },
		{ Vector3.new(-1.0, HEAD_Y + 1.64, 0.9), Vector3.new(-1.9, HEAD_Y + 1.64, 0.3) },
		{ Vector3.new(1.1, HEAD_Y + 1.64, -0.2), Vector3.new(2.0, HEAD_Y + 1.64, -0.9) },
	}
	for _, f in ipairs(FISSURES) do
		local a, b = f[1], f[2]
		bp("Fissure", Vector3.new(0.05, 0.05, (b - a).Magnitude), CFrame.lookAt((a + b) / 2, b), FLAME_BLUE, M.Neon)
	end
	-- chains bound round it, either side of the middle
	for _, x in ipairs({ -0.83, 0.83 }) do
		local hw = 1.68
		local pts = { Vector3.new(x, HEAD_Y - hw, -hw), Vector3.new(x, HEAD_Y + hw, -hw), Vector3.new(x, HEAD_Y + hw, hw), Vector3.new(x, HEAD_Y - hw, hw) }
		for i = 1, 4 do bchain(pts[i], pts[i % 4 + 1], 0.42, if x < 0 then ASH else CHARCOAL) end
	end
	-- the socket the haft goes into
	bp("Socket", Vector3.new(0.95, 0.5, 0.95), CFrame.new(0, HEAD_Y + 1.78, 0), ASH, M.Metal)
	bp("SocketRing", Vector3.new(0.75, 0.3, 0.75), CFrame.new(0, HEAD_Y + 2.15, 0) * CFrame.Angles(0, R(45), 0), CHARCOAL, M.Metal)

	-- ── The haft ──
	local low = HEAD_Y + 2.28
	bp("Haft", Vector3.new(0.42, BUTT_Y - low, 0.42), CFrame.new(0, (BUTT_Y + low) / 2, 0), OBSIDIAN, M.Metal)
	bp("Wrap", Vector3.new(0.47, 2.4, 0.47), CFrame.new(0, GRIP_Y + 0.2, 0), VOID, M.Leather)
	for _, y in ipairs({ low + 0.3, -0.4, 1.6, GRIP_Y - 1.1, GRIP_Y + 1.5, BUTT_Y - 0.25 }) do
		bp("HaftBand", Vector3.new(0.54, 0.18, 0.54), CFrame.new(0, y, 0), STEEL, M.Metal)
	end
	-- chain spiralled up the haft from the head toward the hands...
	local prev: Vector3? = nil
	for k = 0, 16 do
		local ang = k * math.pi / 2
		local q = Vector3.new(math.cos(ang) * 0.3, low + 0.5 + k * 0.32, math.sin(ang) * 0.3)
		if prev then bchain(prev, q, 0.3, ASH) end
		prev = q
	end
	-- ...and a loose length hanging from the haft down to the head
	bchain(Vector3.new(0.3, 1.1, 0.2), Vector3.new(0.8, -1.4, 0.35), 0.34, CHARCOAL)
	bchain(Vector3.new(0.8, -1.4, 0.35), Vector3.new(1.5, HEAD_Y + 1.68, 0.5), 0.34, CHARCOAL)

	-- ── The butt: a jagged spearhead ──
	bp("ButtCollar", Vector3.new(0.6, 0.4, 0.6), CFrame.new(0, BUTT_Y + 0.15, 0) * CFrame.Angles(0, R(45), 0), CHARCOAL, M.Metal)
	bfin("Spearhead", CFrame.new(0, BUTT_Y + 1.25, 0), 0.95, 1.8, 0.24, ASH)
	bfin("Spearhead", CFrame.new(0, BUTT_Y + 1.1, 0) * CFrame.Angles(0, math.pi / 2, 0), 0.7, 1.5, 0.2, CHARCOAL)
	for _, sx in ipairs({ -1, 1 }) do
		bfin("SpearBarb", CFrame.new(sx * 0.42, BUTT_Y + 0.55, 0) * CFrame.Angles(0, 0, R(-sx * 50)), 0.32, 0.6, 0.16, OBSIDIAN)
	end
	local spear = bp("SpearCore", Vector3.new(0.12, 0.8, 0.27), CFrame.new(0, BUTT_Y + 0.95, 0), SPECTRAL, M.Neon)

	-- Ghostly blue flame pouring off the head in sheets, licking up the haft,
	-- wisps of spectral light trailing off it, black mist under it all; a
	-- flame at the butt.
	-- (the fire and smoke pour off an invisible shell just outside the head:
	-- from the core inside it they'd die inside the blocks unseen)
	local shell = bp("FlameShell", Vector3.new(5.3, 3.8, 3.8), CFrame.new(0, HEAD_Y, 0), SPECTRAL, M.SmoothPlastic)
	shell.Transparency = 1
	ghostflame(shell, 70, 1.7, 1.4)
	-- (the flames' deep-blue outer edges: bigger, softer tongues round them)
	local outer = ghostflame(shell, 26, 2.4, 0.8)
	outer.Name = "GhostflameOuter"
	outer.Color = ColorSequence.new(Color3.fromRGB(40, 120, 255), Color3.fromRGB(10, 26, 110))
	outer.Brightness = 1
	outer.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.35), NumberSequenceKeypoint.new(0.6, 0.6),
		NumberSequenceKeypoint.new(1, 1) })
	outer.Lifetime = NumberRange.new(0.6, 1)
	outer.Acceleration = Vector3.new(0, 7, 0)
	ghostflame(spear, 10, 1)
	local haft = tool:FindFirstChild("Haft") :: BasePart
	ghostflame(haft, 8, 0.6)
	-- The aura: a pale glow wrapped round the whole head, always there.
	local aura = Instance.new("ParticleEmitter")
	aura.Name = "Ghostaura"
	aura.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	aura.Color = ColorSequence.new(FROST, SPECTRAL)
	aura.LightEmission = 1
	aura.LightInfluence = 0
	aura.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.6), NumberSequenceKeypoint.new(0.5, 3.4), NumberSequenceKeypoint.new(1, 2.2) })
	aura.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.3, 0.7),
		NumberSequenceKeypoint.new(1, 1) })
	aura.Lifetime = NumberRange.new(0.5, 0.8)
	aura.Speed = NumberRange.new(0, 0.3)
	aura.Rotation = NumberRange.new(0, 360)
	aura.RotSpeed = NumberRange.new(-40, 40)
	aura.LockedToPart = true
	aura.Shape = Enum.ParticleEmitterShape.Box
	aura.Rate = 12
	aura.Parent = shell
	-- Smoke curling round it in two layers: glowing blue wisps drawn out into
	-- long trails, and dark navy smoke under them (kept close to the head).
	local wisp = Instance.new("ParticleEmitter")
	wisp.Name = "Ghostwisp"
	wisp.Texture = TEX_SMOKE
	wisp.Color = ColorSequence.new(Color3.fromRGB(60, 130, 230), Color3.fromRGB(14, 26, 70))
	wisp.LightEmission = 0.3
	wisp.LightInfluence = 0
	wisp.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 2.6) })
	wisp.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.2, 0.5),
		NumberSequenceKeypoint.new(1, 1) })
	wisp.Squash = NumberSequence.new(-0.8)
	wisp.Lifetime = NumberRange.new(1, 1.6)
	wisp.Speed = NumberRange.new(0.4, 1.2)
	wisp.SpreadAngle = Vector2.new(180, 180)
	wisp.Drag = 1.2
	wisp.Acceleration = Vector3.new(0, 1.8, 0)
	wisp.Rotation = NumberRange.new(0, 360)
	wisp.RotSpeed = NumberRange.new(-70, 70)
	wisp.Shape = Enum.ParticleEmitterShape.Box
	wisp.LockedToPart = false
	wisp.Rate = 12
	wisp.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	wisp.Parent = shell
	local navy = Instance.new("ParticleEmitter")
	navy.Name = "Ghostsmoke"
	navy.Texture = TEX_SMOKE
	navy.Color = ColorSequence.new(Color3.fromRGB(20, 34, 80), Color3.fromRGB(6, 10, 26))
	navy.LightEmission = 0
	navy.LightInfluence = 0.4
	navy.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1.4), NumberSequenceKeypoint.new(1, 3) })
	navy.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(0.25, 0.6),
		NumberSequenceKeypoint.new(1, 1) })
	navy.Lifetime = NumberRange.new(0.9, 1.4)
	navy.Speed = NumberRange.new(0.2, 0.6)
	navy.SpreadAngle = Vector2.new(180, 180)
	navy.Drag = 1.5
	navy.Acceleration = Vector3.new(0, 1, 0)
	navy.Rotation = NumberRange.new(0, 360)
	navy.RotSpeed = NumberRange.new(-40, 40)
	navy.Shape = Enum.ParticleEmitterShape.Box
	navy.LockedToPart = false
	navy.Rate = 7
	navy.ShapeStyle = Enum.ParticleEmitterShapeStyle.Surface
	navy.Parent = shell
	mist(core, 5, -0.25)
	for _, d in ipairs(core:GetChildren()) do
		if d:IsA("ParticleEmitter") then d:SetAttribute(ATTR, nil) end
	end

	-- Attachments for the swing trail, the chain it fires and the ghostfire:
	-- across the head along the haft (the base nearer the hands).
	local a0 = Instance.new("Attachment")
	a0.Name = "GraveBase"
	a0.Position = Vector3.new(0, 1.3, 0) * S
	a0.Parent = core
	local a1 = Instance.new("Attachment")
	a1.Name = "GraveTip"
	a1.Position = Vector3.new(0, -1.6, 0) * S
	a1.Parent = core
	return tool
end

-- ═════════════════════════════════════════════════════════════════════════════
-- The plate
-- ═════════════════════════════════════════════════════════════════════════════
-- Hide `inst` under the plate (its transparency kept to give back).
local function hide(inst: Instance)
	if inst:IsA("BasePart") or inst:IsA("Decal") or inst:IsA("Texture") then
		if inst:GetAttribute(HIDDEN) == nil then
			inst:SetAttribute(HIDDEN, (inst :: any).Transparency)
			;(inst :: any).Transparency = 1
		end
	end
end

-- An accessory the avatar wears (hat, hair, shoulder pet...): all of it goes
-- under the plate. (The server hides any that load in later with this too.)
function DeathKnightLook.HideAccessory(acc: Instance)
	if not acc:IsA("Accessory") then return end
	for _, d in ipairs(acc:GetDescendants()) do hide(d) end
end

function DeathKnightLook.IsDressed(char: Model): boolean
	return char:FindFirstChild("SoulReaperPlate") ~= nil
end

function DeathKnightLook.Undress(char: Model)
	local plate = char:FindFirstChild("SoulReaperPlate")
	if plate then plate:Destroy() end
	for _, d in ipairs(char:GetDescendants()) do
		if d:GetAttribute(ATTR) and not d:FindFirstAncestorOfClass("Tool") then
			if d.Parent then d:Destroy() end
		elseif d:GetAttribute(HIDDEN) ~= nil then
			(d :: any).Transparency = d:GetAttribute(HIDDEN)
			d:SetAttribute(HIDDEN, nil)
		end
	end
end

-- ── The helm ────────────────────────────────────────────────────────────────
local function helm(model: Model, head: BasePart)
	-- The bucket: well past the head on every side.
	piece(model, head, "Helm", Vector3.new(1.64, 1.62, 1.66), CFrame.new(0, 0.12, 0.02), CHARCOAL)
	piece(model, head, "HelmBrow", Vector3.new(1.74, 0.3, 0.32), CFrame.new(0, 0.42, -0.74), OBSIDIAN)
	piece(model, head, "Faceplate", Vector3.new(1.34, 0.92, 0.14), CFrame.new(0, -0.22, -0.86), OBSIDIAN)
	piece(model, head, "BreathSlit", Vector3.new(0.07, 0.52, 0.05), CFrame.new(0, -0.3, -0.95), VOID, M.SmoothPlastic)
	for _, sx in ipairs({ -1, 1 }) do
		-- The eye slits: narrow, angled, glowing ice-blue out of the dark.
		piece(model, head, "EyeShadow", Vector3.new(0.5, 0.17, 0.05), CFrame.new(sx * 0.27, 0.2, -0.95) * CFrame.Angles(0, 0, R(sx * -9)), VOID,
			M.SmoothPlastic)
		piece(model, head, "EyeSlit", Vector3.new(0.38, 0.065, 0.04), CFrame.new(sx * 0.27, 0.2, -0.985) * CFrame.Angles(0, 0, R(sx * -9)), SPECTRAL,
			M.Neon)
		-- cheek guards swept back and down, and a jagged fin over each ear
		piece(model, head, "Cheek", Vector3.new(0.24, 0.8, 0.9), CFrame.new(sx * 0.86, -0.3, -0.36) * CFrame.Angles(0, math.pi, 0), OBSIDIAN, nil, "wedge")
		fin(model, head, "HelmFin", CFrame.new(sx * 0.9, 0.62, 0.15) * CFrame.Angles(0, math.pi / 2, 0) * CFrame.Angles(0, 0, R(sx * 22)), 0.7, 0.95,
			0.14, ASH)
	end
	-- The crown: a band and a ring of jagged spikes, tallest at the front.
	piece(model, head, "CrownBand", Vector3.new(1.72, 0.22, 1.74), CFrame.new(0, 0.98, 0.02), ASH)
	for _, s in ipairs({ { a = 0, h = 1.35 }, { a = 32, h = 1.0 }, { a = -32, h = 1.0 }, { a = 64, h = 0.8 }, { a = -64, h = 0.8 },
		{ a = 100, h = 0.62 }, { a = -100, h = 0.62 }, { a = 145, h = 0.5 }, { a = -145, h = 0.5 } }) do
		local at = CFrame.new(0, 1.06 + s.h / 2, 0.02) * CFrame.Angles(0, R(s.a), 0) * CFrame.new(0, 0, -0.74)
		fin(model, head, "CrownSpike", at, 0.42, s.h, 0.15, if s.a == 0 then OBSIDIAN else CHARCOAL)
	end
	piece(model, head, "CrownGem", Vector3.new(0.16, 0.16, 0.06), CFrame.new(0, 1.0, -0.9) * CFrame.Angles(0, 0, R(45)), SPECTRAL, M.Neon).Transparency = 0.3
end

-- ── The body ────────────────────────────────────────────────────────────────
local function cuirass(model: Model, torso: BasePart)
	piece(model, torso, "Gorget", Vector3.new(1.96, 0.52, 1.82), CFrame.new(0, 1.12, 0.03), OBSIDIAN)
	piece(model, torso, "Cuirass", Vector3.new(2.36, 2.2, 1.58), CFrame.new(0, 0.04, 0.02), CHARCOAL)
	-- The breastplate, a keel down it, its jagged upper edges.
	piece(model, torso, "Breastplate", Vector3.new(2.08, 1.22, 0.22), CFrame.new(0, 0.42, -0.86), OBSIDIAN)
	piece(model, torso, "Keel", Vector3.new(0.16, 1.12, 0.12), CFrame.new(0, 0.42, -1.02), ASH)
	for _, sx in ipairs({ -1, 1 }) do
		piece(model, torso, "PlateEdge", Vector3.new(0.95, 0.1, 0.09), CFrame.new(sx * 0.48, 0.98, -0.99) * CFrame.Angles(0, 0, R(sx * -14)), STEEL)
		fin(model, torso, "PlateTooth", CFrame.new(sx * 0.95, 1.08, -0.92), 0.3, 0.32, 0.1, CHARCOAL)
	end
	-- Layered lames down the belly.
	for i, y in ipairs({ -0.3, -0.58, -0.84 }) do
		piece(model, torso, "Lame", Vector3.new(2.2 - i * 0.04, 0.26, 0.2), CFrame.new(0, y, -0.84), if i % 2 == 0 then CHARCOAL else OBSIDIAN)
		piece(model, torso, "LameTrim", Vector3.new(2.16 - i * 0.04, 0.05, 0.2), CFrame.new(0, y - 0.14, -0.86), ASH)
	end
	-- The heavy belt, its buckle set with a dim spectral stone.
	piece(model, torso, "Belt", Vector3.new(2.46, 0.42, 1.7), CFrame.new(0, -1.0, 0.02), OBSIDIAN)
	piece(model, torso, "Buckle", Vector3.new(0.62, 0.5, 0.12), CFrame.new(0, -1.0, -0.9), ASH)
	piece(model, torso, "BuckleStone", Vector3.new(0.16, 0.16, 0.05), CFrame.new(0, -1.0, -0.98) * CFrame.Angles(0, 0, R(45)), SPECTRAL, M.Neon).Transparency = 0.35
	-- Chains crossing the chest and the back.
	chain(model, torso, Vector3.new(1.0, 1.02, -1.06), Vector3.new(-1.02, -0.72, -1.04))
	chain(model, torso, Vector3.new(-1.0, 1.02, 0.86), Vector3.new(1.02, -0.72, 0.88))
	-- Ridged plates down the spine (the cape hangs over them).
	for i, y in ipairs({ 0.7, 0.2, -0.3 }) do
		piece(model, torso, "SpinePlate", Vector3.new(0.7 - i * 0.08, 0.34, 0.16), CFrame.new(0, y, 0.86), OBSIDIAN)
	end
end

local function pauldron(model: Model, arm: BasePart, sx: number)
	-- Three layered plates sloping off the shoulder, each edged in cold
	-- steel, and spikes raking out of the top.
	local layers = {
		{ size = Vector3.new(1.98, 0.62, 1.9), at = Vector3.new(sx * 0.16, 0.98, 0), rz = -14, color = OBSIDIAN },
		{ size = Vector3.new(1.86, 0.44, 1.8), at = Vector3.new(sx * 0.3, 0.6, 0), rz = -27, color = CHARCOAL },
		{ size = Vector3.new(1.62, 0.38, 1.66), at = Vector3.new(sx * 0.4, 0.28, 0), rz = -38, color = OBSIDIAN },
	}
	for _, L in ipairs(layers) do
		local cf = CFrame.new(L.at) * CFrame.Angles(0, 0, R(sx * L.rz))
		piece(model, arm, "Pauldron", L.size, cf, L.color)
		piece(model, arm, "PauldronEdge", Vector3.new(0.1, L.size.Y + 0.02, L.size.Z + 0.02), cf * CFrame.new(sx * (L.size.X / 2 + 0.03), 0, 0), STEEL)
	end
	for k = -1, 1 do
		local h = if k == 0 then 1.35 else 0.95
		fin(model, arm, "PauldronSpike", CFrame.new(sx * 0.42, 1.28 + h / 2, k * 0.55) * CFrame.Angles(0, 0, R(sx * -30)), 0.5, h, 0.16,
			if k == 0 then ASH else CHARCOAL)
	end
end

local function armPlate(model: Model, arm: BasePart, sx: number)
	-- the whole arm in plate, a little wider than the arm on every side
	piece(model, arm, "ArmShell", Vector3.new(1.3 + sx * 0.01, 2.06, 1.32), CFrame.new(0, -0.02, 0), CHARCOAL)
	piece(model, arm, "ArmBand", Vector3.new(1.36, 0.12, 1.38), CFrame.new(0, 0.05, 0), ASH)
	-- a chain wound round the forearm
	chainRing(model, arm, -0.22, 1.38, 1.4, sx * 8)
	-- the gauntlet: a flared cuff with jagged teeth, plated knuckles
	piece(model, arm, "Gauntlet", Vector3.new(1.48, 0.82, 1.5), CFrame.new(0, -0.68, 0), OBSIDIAN)
	piece(model, arm, "Knuckles", Vector3.new(0.96, 0.3, 0.2), CFrame.new(0, -0.88, -0.8), ASH)
	for _, z in ipairs({ -0.45, 0.05, 0.5 }) do
		fin(model, arm, "CuffTooth", CFrame.new(sx * 0.62, -0.12, z) * CFrame.Angles(0, 0, R(sx * -20)), 0.36, 0.42, 0.1, CHARCOAL)
	end
	pauldron(model, arm, sx)
end

local function legPlate(model: Model, leg: BasePart, sx: number)
	-- cuisse and greave in one, a little wider than the leg on every side
	piece(model, leg, "LegShell", Vector3.new(1.27 + sx * 0.01, 2.04, 1.34 + sx * 0.01), CFrame.new(0, 0.02, 0), CHARCOAL)
	-- the knee guard and a ridge down the shin
	piece(model, leg, "Poleyn", Vector3.new(1.36, 0.5, 0.3), CFrame.new(0, -0.08, -0.74), OBSIDIAN)
	fin(model, leg, "KneeSpike", CFrame.new(0, 0.28, -0.86), 0.4, 0.42, 0.12, ASH)
	piece(model, leg, "Shin", Vector3.new(0.32, 0.62, 0.1), CFrame.new(0, -0.55, -0.72), ASH)
	-- the sabaton, its toe a sloped cap
	piece(model, leg, "Sabaton", Vector3.new(1.42, 0.48, 1.62), CFrame.new(0, -0.76, -0.12), OBSIDIAN)
	piece(model, leg, "Toe", Vector3.new(1.38, 0.34, 0.5), CFrame.new(0, -0.83, -1.18), OBSIDIAN, nil, "wedge")
	-- The tassets hanging over the thigh: on the leg itself, so they ride it
	-- up when he sits or kicks instead of the thigh breaking through them.
	piece(model, leg, "Tasset", Vector3.new(1.42, 0.86, 0.16), CFrame.new(sx * 0.04, 0.6, -0.79 - sx * 0.01) * CFrame.Angles(R(-6), 0, 0), OBSIDIAN)
	piece(model, leg, "TassetEdge", Vector3.new(1.44, 0.08, 0.18), CFrame.new(sx * 0.04, 0.17, -0.82 - sx * 0.01) * CFrame.Angles(R(-6), 0, 0), STEEL)
	piece(model, leg, "HipPlate", Vector3.new(0.16, 0.92, 1.32), CFrame.new(sx * 0.74, 0.58, 0), ASH)
	-- Ragged black cloth hanging in front, torn to points.
	for k, s in ipairs({ { x = -0.26, len = 1.0 }, { x = 0.24, len = 1.35 } }) do
		local x = s.x * sx
		local top = 0.95
		piece(model, leg, "Rag", Vector3.new(0.44, s.len, 0.05), CFrame.new(x, top - s.len / 2, -0.92) * CFrame.Angles(0, 0, R(k * 2 - 3)), OBSIDIAN,
			M.Fabric)
		fin(model, leg, "RagTip", CFrame.new(x, top - s.len - 0.22, -0.92) * CFrame.Angles(0, 0, math.pi + R(k * 2 - 3)), 0.44, 0.44, 0.05,
			OBSIDIAN, M.Fabric)
	end
	-- (a chain round the right thigh)
	if sx > 0 then chainRing(model, leg, 0.32, 1.32, 1.4, -10) end
end

-- ── Public ──────────────────────────────────────────────────────────────────
-- Put the plate on (safe to call again).
function DeathKnightLook.Dress(char: Model)
	DeathKnightLook.Undress(char)
	local head = char:FindFirstChild("Head") :: BasePart?
	local torso = char:FindFirstChild("Torso") :: BasePart?
	if not (head and torso) then return end
	local model = Instance.new("Model")
	model.Name = "SoulReaperPlate"
	model:SetAttribute(ATTR, true)

	-- Everything of the avatar goes under the plate: the head (whatever its
	-- shape), the face, every accessory, and the limbs themselves, so no
	-- package mesh, sleeve or hat can ever show through.
	for _, d in ipairs(head:GetDescendants()) do hide(d) end
	hide(head)
	for _, name in ipairs({ "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg" }) do
		local limb = char:FindFirstChild(name)
		if limb then
			hide(limb)
			for _, d in ipairs(limb:GetChildren()) do
				if d:IsA("Decal") or d:IsA("Texture") then hide(d) end
			end
		end
	end
	for _, acc in ipairs(char:GetChildren()) do DeathKnightLook.HideAccessory(acc) end

	helm(model, head)
	cuirass(model, torso)
	for _, side in ipairs({ "Left Arm", "Right Arm" }) do
		local arm = char:FindFirstChild(side) :: BasePart?
		if arm then armPlate(model, arm, if side == "Right Arm" then 1 else -1) end
	end
	for _, side in ipairs({ "Left Leg", "Right Leg" }) do
		local leg = char:FindFirstChild(side) :: BasePart?
		if leg then legPlate(model, leg, if side == "Right Leg" then 1 else -1) end
	end

	-- Black mist leaking from the plate: off the cuirass, rising; off the
	-- pauldrons; and sinking round his feet.
	for _, p in ipairs(model:GetChildren()) do
		if p:IsA("BasePart") then
			if p.Name == "Cuirass" then
				mist(p, 5, 0.5)
			elseif p.Name == "Pauldron" and p.Size.X > 1.9 then
				mist(p, 1.5, 0.3)
			elseif p.Name == "Sabaton" then
				mist(p, 2, -0.25)
			end
		end
	end
	model.Parent = char
end

return DeathKnightLook
