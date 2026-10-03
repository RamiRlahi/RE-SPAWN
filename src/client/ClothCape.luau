--!strict
--[[
	ClothCape.luau
	A real cloth cape: one EditableMesh sheet whose vertices are a Verlet cloth
	simulated on the client every frame. The top row is pinned across the back
	of the shoulders; the rest hangs under gravity with a light breeze, keeps
	its length through distance constraints, and is pushed out of the torso,
	legs and the ground, so it drapes over whatever pose the character holds
	(standing, kneeling, seated at the fire).

	Two-sided: an outer face (dark) and an inner lining, as separate vertex
	sets so each side lights correctly.

	EditableMesh must be allowed for the experience (Game Settings > Security >
	"Allow Mesh & Image APIs"). Without it the same simulated cloth is drawn
	with thin fabric panels, one per cell of the grid.

	Styles: the Sword Master's (dark cape, white fur) and the Fire Knight's
	(crimson cape, a smaller black fur mantle).

	ClothCape.Attach(character, tag?, style?) → Model?   ClothCape.Detach(character)
--]]

local AssetService = game:GetService("AssetService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ClothCape = {}

local COLS = 11 -- particles across
local ROWS = 15 -- particles down
local TOP_WIDTH = 1.9 -- inside the shoulders, clear of the arms' swing
local BOTTOM_WIDTH = 3.3
local LENGTH = 4.35 -- collar to hem, ankle height on R6
local ITERATIONS = 10
local GRAVITY = Vector3.new(0, -60, 0)
local DAMPING = 0.975
local MARGIN = 0.15 -- how far the cloth stays off the body

export type Style = {
	outer: Color3,     -- the cape's outside
	lining: Color3,    -- its inside
	hem: Color3,       -- the bottom band
	fur: Color3,       -- the mantle
	furShade: Color3,
	mantle: number?,   -- mantle size (1 = over a bare torso; bigger over armor)
	furSize: number?,  -- how big the fur tufts are (1 = the Sword Master's)
	back: number?,     -- how much further off the back the collar hangs (armor)
	armor: boolean?,   -- the cloth also drapes off armor pieces
	tip: Color3?,      -- the cloth fades to this toward the hem
	shred: number?,    -- below this (0..1 down) the cloth tears into ragged strips
	feathers: boolean?, -- shingled feathers ride the cloth (the Berserker's)
	featherTop: Color3?,
	featherTip: Color3?,
	lean: number?,     -- the mantle heavier over the left shoulder (0 = even)
	brooch: boolean?,  -- a crimson-jewelled star at the left collarbone
}

ClothCape.SWORD_MASTER = {
	outer = Color3.fromRGB(26, 20, 26),
	lining = Color3.fromRGB(120, 34, 22),
	hem = Color3.fromRGB(196, 140, 60),
	fur = Color3.fromRGB(240, 234, 226),
	furShade = Color3.fromRGB(190, 180, 172),
} :: Style

-- A crimson cape, ember-gold hem, and a black fur mantle, lighter than the
-- Sword Master's (smaller tufts, close round the shoulders).
ClothCape.FIRE_KNIGHT = {
	outer = Color3.fromRGB(104, 12, 14),
	lining = Color3.fromRGB(40, 7, 8),
	hem = Color3.fromRGB(200, 118, 40),
	fur = Color3.fromRGB(20, 18, 20),
	furShade = Color3.fromRGB(58, 52, 54),
	mantle = 0.92,
	furSize = 0.62,
} :: Style

-- The Berserker's: a cape of black feathers bleeding to crimson, torn into
-- ragged strips at the bottom, a shaggy feather mantle heaped over the left
-- shoulder and a crimson-jewelled star brooch.
ClothCape.BERSERKER = {
	outer = Color3.fromRGB(16, 8, 10),
	lining = Color3.fromRGB(30, 6, 9),
	hem = Color3.fromRGB(150, 10, 22),
	tip = Color3.fromRGB(150, 10, 22),
	fur = Color3.fromRGB(14, 8, 10),
	furShade = Color3.fromRGB(120, 8, 18),
	mantle = 0.88,
	furSize = 0.42,
	back = 0.12,
	armor = true,
	shred = 0.5,
	feathers = true,
	featherTop = Color3.fromRGB(18, 9, 11),
	featherTip = Color3.fromRGB(190, 14, 28),
	lean = 0.3,
	brooch = true,
} :: Style

-- The Gunslinger's: a dusty dark-leather cape, tattered into ragged strips,
-- with a short rough collar over the shoulders.
ClothCape.GUNSLINGER = {
	outer = Color3.fromRGB(40, 29, 24),
	lining = Color3.fromRGB(62, 28, 20),
	hem = Color3.fromRGB(30, 22, 18),
	tip = Color3.fromRGB(26, 19, 16),
	fur = Color3.fromRGB(44, 32, 26),
	furShade = Color3.fromRGB(66, 48, 36),
	mantle = 0.82,
	furSize = 0.32,
	back = 0.08,
	armor = true,
	shred = 0.42,
} :: Style

type Constraint = { a: number, b: number, rest: number }
type Feather = { i: number, j: number, len: number, width: number, parts: { BasePart } }
type Cape = {
	model: Model,
	part: MeshPart?, -- the cloth mesh, or nil when drawn with panels
	mesh: EditableMesh?,
	panels: { BasePart },
	panelCFs: { CFrame },
	torso: BasePart,
	character: Model,
	style: Style,
	pos: { Vector3 },
	prev: { Vector3 },
	pinLocal: { [number]: Vector3 }, -- torso-space pin per pinned particle
	constraints: { Constraint },
	outerIds: { number },
	innerIds: { number },
	colliders: { BasePart },
	feathers: { Feather },
	featherParts: { BasePart },
	featherCFs: { CFrame },
	cut: { number }, -- per column: the first row below its ragged end
	rayParams: RaycastParams,
	floorY: number,
	floorAt: number,
	lastTorso: Vector3,
	collidersAt: number,
}

local capes: { [Model]: Cape } = {}
local meshAllowed: boolean? = nil -- false once EditableMesh turned out to be off
local conn: RBXScriptConnection? = nil

local function idx(r: number, c: number): number
	return (r - 1) * COLS + c
end

-- Rest shape in torso space: an arc across the shoulder blades that widens and
-- falls straight down behind the back.
local function restPoint(torso: BasePart, r: number, c: number, style: Style): Vector3
	local u = (c - 1) / (COLS - 1) * 2 - 1 -- -1 .. 1 across
	local v = (r - 1) / (ROWS - 1) -- 0 at the collar, 1 at the hem
	local half = (TOP_WIDTH + (BOTTOM_WIDTH - TOP_WIDTH) * v) * 0.5 * (if style.armor then 1.15 else 1)
	local top = torso.Size.Y * 0.5 - 0.02
	local back = torso.Size.Z * 0.5 + MARGIN + (style.back or 0)
	-- Straight across the back (the fur mantle hides the collar): pinned
	-- points can't be pushed, so they must never sit inside the body.
	local z = back + 0.12 * v
	return Vector3.new(u * half, top - v * LENGTH, z)
end

-- Where each column of a shredded cape ends: the first row no longer drawn
-- (ROWS + 1 = the full length).
local function cutoffs(style: Style): { number }
	local out = {}
	local rng = Random.new(1337)
	for c = 1, COLS - 1 do
		if style.shred then
			local start = math.floor(style.shred * (ROWS - 1)) + 2
			out[c] = math.clamp(rng:NextInteger(start + 1, ROWS + 1) + (if c % 2 == 0 then 1 else -1), start, ROWS)
		else
			out[c] = ROWS
		end
	end
	return out
end

-- The cloth's colour at row r (fading to style.tip toward the hem).
local function rowColor(style: Style, r: number): Color3
	if not style.tip then return style.outer end
	local v = (r - 1) / (ROWS - 1)
	return style.outer:Lerp(style.tip, math.clamp((v - 0.35) / 0.65, 0, 1) ^ 1.6)
end

local function buildMesh(style: Style): (EditableMesh, { number }, { number })
	local em = AssetService:CreateEditableMesh()
	local outer, inner = {}, {}
	for i = 1, ROWS * COLS do
		outer[i] = em:AddVertex(Vector3.zero)
		inner[i] = em:AddVertex(Vector3.zero)
	end
	local cLining = em:AddColor(style.lining, 1)
	local cHem = em:AddColor(style.hem, 1)
	local cRow = {}
	for r = 1, ROWS do cRow[r] = em:AddColor(rowColor(style, r), 1) end
	local cut = cutoffs(style)
	for r = 1, ROWS - 1 do
		for c = 1, COLS - 1 do
			local a, b, d, e = idx(r, c), idx(r, c + 1), idx(r + 1, c), idx(r + 1, c + 1)
			local hem = r == ROWS - 1 and not style.tip
			-- Shredded: nothing below this column's end, and its last cell a
			-- single torn tooth.
			if r + 1 > cut[c] then continue end
			local tris = if r + 1 == cut[c] and style.shred
				then { if c % 2 == 0 then { a, d, b } else { a, e, b } }
				else { { a, d, b }, { b, d, e } }
			-- Outer side faces away from the body (+Z of the torso).
			for _, tri in ipairs(tris) do
				local f = em:AddTriangle(outer[tri[1]], outer[tri[2]], outer[tri[3]])
				if hem then
					em:SetFaceColors(f, { cHem, cHem, cHem })
				else
					local function rc(v: number) return cRow[math.floor((v - 1) / COLS) + 1] end
					em:SetFaceColors(f, { rc(tri[1]), rc(tri[2]), rc(tri[3]) })
				end
				local g = em:AddTriangle(inner[tri[1]], inner[tri[3]], inner[tri[2]])
				em:SetFaceColors(g, { cLining, cLining, cLining })
			end
		end
	end
	-- Bounds anchors: two degenerate triangles at opposite corners so the
	-- mesh's bounding box is centred on its origin (the MeshPart's CFrame is
	-- then exactly the torso's) and large enough for any drape.
	for s = -1, 1, 2 do
		local p = Vector3.new(7, 7, 7) * s
		local v1, v2, v3 = em:AddVertex(p), em:AddVertex(p), em:AddVertex(p)
		em:AddTriangle(v1, v2, v3)
	end
	return em, outer, inner
end

local function addConstraint(cape: Cape, a: number, b: number)
	table.insert(cape.constraints, { a = a, b = b, rest = (cape.pos[a] - cape.pos[b]).Magnitude })
end

local function collidersOf(character: Model, armor: boolean?): { BasePart }
	local list = {}
	-- Over plate armor the cloth drapes off the armor pieces too (each one's
	-- box: chestplate, belt, pauldrons).
	if armor then
		for _, m in ipairs(character:GetChildren()) do
			if m:IsA("Model") and m.Name ~= "ClothCape" then
				for _, d in ipairs(m:GetDescendants()) do
					if d:IsA("BasePart") and d.Transparency < 1 and d.Size.Magnitude > 1.5 then table.insert(list, d) end
				end
			end
		end
	end
	-- Every body part the cloth could swing into (arms swing back when
	-- running, legs kick up into it, the head when it's thrown forward).
	for _, name in ipairs({
		"Torso", "UpperTorso", "LowerTorso", "Head",
		"Left Leg", "Right Leg", "LeftUpperLeg", "RightUpperLeg", "LeftLowerLeg", "RightLowerLeg",
		"Left Arm", "Right Arm", "LeftUpperArm", "RightUpperArm", "LeftLowerArm", "RightLowerArm",
	}) do
		local p = character:FindFirstChild(name)
		if p and p:IsA("BasePart") then table.insert(list, p) end
	end
	return list
end

-- Push a point out of a box (expanded by MARGIN) along the shallowest axis.
local function pushOutOfBox(p: Vector3, box: BasePart): Vector3
	local cf = box.CFrame
	local l = cf:PointToObjectSpace(p)
	local h = box.Size * 0.5 + Vector3.new(MARGIN, MARGIN, MARGIN)
	local dx, dy, dz = h.X - math.abs(l.X), h.Y - math.abs(l.Y), h.Z - math.abs(l.Z)
	if dx <= 0 or dy <= 0 or dz <= 0 then return p end
	if dz <= dx and dz <= dy then
		l = Vector3.new(l.X, l.Y, if l.Z >= 0 then h.Z else -h.Z)
	elseif dx <= dy then
		l = Vector3.new(if l.X >= 0 then h.X else -h.X, l.Y, l.Z)
	else
		l = Vector3.new(l.X, if l.Y >= 0 then h.Y else -h.Y, l.Z)
	end
	return cf:PointToWorldSpace(l)
end

local placeFeathers: (Cape) -> ()

local function simulate(cape: Cape, dt: number, now: number)
	local torso = cape.torso
	local tcf = torso.CFrame
	local pos, prev = cape.pos, cape.prev

	-- Ground under the character (re-probed a few times a second).
	if now - cape.floorAt > 0.25 then
		cape.floorAt = now
		local hit = Workspace:Raycast(tcf.Position, Vector3.new(0, -12, 0), cape.rayParams)
		cape.floorY = if hit then hit.Position.Y else -math.huge
	end

	-- A slow breeze from in front, so the cape drifts back off the legs.
	local back = tcf.LookVector * -1
	local gust = 0.5 + 0.5 * math.sin(now * 0.9) * math.sin(now * 2.3 + 1.7)
	local wind = back * (3 + 5 * gust) + tcf.RightVector * math.sin(now * 0.7) * 2

	local dt2 = dt * dt
	for i = 1, #pos do
		local pin = cape.pinLocal[i]
		if pin then
			local p = tcf:PointToWorldSpace(pin)
			prev[i] = p
			pos[i] = p
		else
			local p = pos[i]
			local r = math.floor((i - 1) / COLS) + 1
			local k = (r - 1) / (ROWS - 1)
			local vel = (p - prev[i]) * DAMPING
			prev[i] = p
			pos[i] = p + vel + (GRAVITY + wind * k) * dt2
		end
	end

	local cons = cape.constraints
	local floorY = cape.floorY + 0.05
	for _ = 1, ITERATIONS do
		for _, c in ipairs(cons) do
			local pa, pb = pos[c.a], pos[c.b]
			local d = pb - pa
			local len = d.Magnitude
			if len > 1e-6 then
				local diff = (len - c.rest) / len
				local pinA, pinB = cape.pinLocal[c.a] ~= nil, cape.pinLocal[c.b] ~= nil
				if pinA and not pinB then
					pos[c.b] = pb - d * diff
				elseif pinB and not pinA then
					pos[c.a] = pa + d * diff
				elseif not pinA then
					local half = d * (diff * 0.5)
					pos[c.a] = pa + half
					pos[c.b] = pb - half
				end
			end
		end
		for i = 1, #pos do
			if not cape.pinLocal[i] then
				local p = pos[i]
				for _, box in ipairs(cape.colliders) do
					p = pushOutOfBox(p, box)
				end
				if p.Y < floorY then p = Vector3.new(p.X, floorY, p.Z) end
				pos[i] = p
			end
		end
	end

	local mesh, part = cape.mesh, cape.part
	if mesh and part then
		-- Write the sheet into the mesh, in torso space.
		part.CFrame = tcf
		for i = 1, #pos do
			local l = tcf:PointToObjectSpace(pos[i])
			mesh:SetPosition(cape.outerIds[i], l)
			mesh:SetPosition(cape.innerIds[i], l)
		end
		placeFeathers(cape)
		return
	end
	-- Panels: each cell is a thin slab spanning its four particles.
	local n = 0
	for r = 1, ROWS - 1 do
		for c = 1, COLS - 1 do
			n += 1
			local a, b, d, e = pos[idx(r, c)], pos[idx(r, c + 1)], pos[idx(r + 1, c)], pos[idx(r + 1, c + 1)]
			local centre = (a + b + d + e) * 0.25
			local across = (b - a) + (e - d)
			local down = (a - d) + (b - e)
			local right = across.Unit
			local normal = right:Cross(down.Unit)
			if normal.Magnitude < 1e-3 then normal = tcf.LookVector * -1 end
			normal = normal.Unit
			local up = normal:Cross(right)
			cape.panelCFs[n] = CFrame.fromMatrix(centre, right, up, normal)
			local panel = cape.panels[n]
			-- Slightly oversized so neighbouring panels overlap at the seams
			-- (a shredded column's last cell narrower: a torn strip).
			local torn = r + 1 == cape.cut[c] and cape.style.shred ~= nil
			panel.Size = Vector3.new(across.Magnitude * (if torn then 0.25 else 0.5) + 0.06, down.Magnitude * 0.5 + 0.06, 0.06)
		end
	end
	Workspace:BulkMoveTo(cape.panels, cape.panelCFs, Enum.BulkMoveMode.FireCFrameChanged)
	placeFeathers(cape)
end

-- Lay each feather on the cloth: from its particle down toward the one below,
-- flat against the sheet and just off its outer side.
placeFeathers = function(cape: Cape)
	if #cape.feathers == 0 then return end
	local pos = cape.pos
	local centre = cape.torso.Position
	local n = 0
	for _, f in ipairs(cape.feathers) do
		local p, q = pos[f.i], pos[f.j]
		local c = (f.i - 1) % COLS + 1
		local l = pos[if c > 1 then f.i - 1 else f.i]
		local rgt = pos[if c < COLS then f.i + 1 else f.i]
		local down = q - p
		down = if down.Magnitude > 1e-3 then down.Unit else Vector3.new(0, -1, 0)
		local right = rgt - l
		right = if right.Magnitude > 1e-3 then right.Unit else cape.torso.CFrame.RightVector
		local normal = right:Cross(down)
		normal = if normal.Magnitude > 1e-3 then normal.Unit else cape.torso.CFrame.LookVector * -1
		local out = Vector3.new(p.X - centre.X, 0, p.Z - centre.Z)
		if normal:Dot(out) < 0 then normal = -normal end
		-- X thin (the normal), Z up the cloth (a wedge tapers toward -Z: the
		-- point hangs down).
		local up = -down
		local y = up:Cross(normal)
		local base = CFrame.fromMatrix(p + normal * 0.07, normal, y, up)
		local mid = base * CFrame.new(0, 0, -f.len * 0.5)
		n += 1
		cape.featherCFs[n] = mid * CFrame.new(0, f.width * 0.25, 0)
		n += 1
		cape.featherCFs[n] = mid * CFrame.new(0, -f.width * 0.25, 0) * CFrame.Angles(0, 0, math.pi)
	end
	Workspace:BulkMoveTo(cape.featherParts, cape.featherCFs, Enum.BulkMoveMode.FireCFrameChanged)
end

local function step(dt: number)
	dt = math.clamp(dt, 1 / 240, 1 / 30)
	local now = os.clock()
	for character, cape in pairs(capes) do
		if not (character.Parent and cape.model.Parent and cape.torso.Parent) then
			ClothCape.Detach(character)
		else
			-- Body parts can arrive or be replaced after the cape (respawn,
			-- avatar loading): pick them up again now and then.
			if now - cape.collidersAt > 0.5 then
				cape.collidersAt = now
				cape.colliders = collidersOf(character, cape.style.armor)
			end
			-- A dash or blink moves the body further in one frame than the
			-- cloth could follow; carry the cloth along with it so it never
			-- whips through the body to catch up.
			local moved = cape.torso.Position - cape.lastTorso
			cape.lastTorso = cape.torso.Position
			if moved.Magnitude > 2 and moved.Magnitude <= 12 then
				for i = 1, #cape.pos do
					cape.pos[i] += moved
					cape.prev[i] += moved
				end
			end
			-- Teleported (hero re-placed, seat switched): snap back to rest.
			if (cape.pos[1] - cape.torso.Position).Magnitude > 12 then
				for r = 1, ROWS do
					for c = 1, COLS do
						local i = idx(r, c)
						local p = cape.torso.CFrame:PointToWorldSpace(restPoint(cape.torso, r, c, cape.style))
						cape.pos[i], cape.prev[i] = p, p
					end
				end
			end
			simulate(cape, dt, now)
		end
	end
	if next(capes) == nil and conn then
		conn:Disconnect()
		conn = nil
	end
end

function ClothCape.Detach(character: Model)
	local cape = capes[character]
	capes[character] = nil
	if cape then
		cape.model:Destroy()
		if cape.mesh then cape.mesh:Destroy() end
	end
end

-- ── Fur mantle ──────────────────────────────────────────────────────────────
-- A heavy fur collar over both shoulders: soft bulk underneath and pointed
-- tufts bristling outward, open at the chest, drooping over the upper arms.
-- Seeded, so every wearer of a style wears the same mantle (the Sword
-- Master's white, the Fire Knight's black and bigger, over his pauldrons).

-- Rings from the neck (s = 0) to the outer edge (s = 1).
local FUR_RINGS = {
	{ s = 0.1, n = 11, ball = 0.8, spike = 0.5 },
	{ s = 0.4, n = 16, ball = 0.95, spike = 0.6 },
	{ s = 0.7, n = 20, ball = 0.9, spike = 0.55 },
	{ s = 1.0, n = 24, ball = 0.65, spike = 0.5 },
}

-- Point on the mantle in torso space. θ = 0 is the front of the chest (-Z).
-- `m` sizes it (over armor it sits wider and further out; under 1 it hugs
-- the shoulders, never sinking into the body).
local function mantlePoint(torso: BasePart, theta: number, s: number, m: number): Vector3
	local grow = math.max(m - 1, 0)
	local top = torso.Size.Y * 0.5 + grow * 0.35
	local rx = (0.8 + 0.95 * s) * m
	local rz = (torso.Size.Z * 0.5 + 0.05 + 0.4 * s * math.min(m, 1)) * (1 + grow * 2.2)
	local sx, cz = math.sin(theta), math.cos(theta)
	local droop = s * (0.45 * sx * sx + 0.3 * math.abs(cz))
	return Vector3.new(rx * sx, top + 0.3 + 0.2 * (1 - s) - droop, -rz * cz)
end

local function furPart(model: Model, torso: BasePart, kind: string, size: Vector3, cf: CFrame, color: Color3): BasePart
	local p: BasePart
	if kind == "wedge" then
		p = Instance.new("WedgePart")
	else
		p = Instance.new("Part")
	end
	p.Name = "Fur"
	p.Anchored = false
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.Massless = true
	p.CastShadow = false
	p.Material = Enum.Material.Fabric
	p.Color = color
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Size = size
	if kind == "ball" then
		-- A soft ellipsoid (Ball parts must be round).
		local m = Instance.new("SpecialMesh")
		m.MeshType = Enum.MeshType.Sphere
		m.Parent = p
	end
	p.CFrame = torso.CFrame * cf
	local w = Instance.new("WeldConstraint")
	w.Part0 = torso
	w.Part1 = p
	w.Parent = p
	p.Parent = model
	return p
end

-- A pointed tuft along `dir` from `base` (torso space): two wedges whose thin
-- edges meet at the tip, crossed with a second pair on the outer rows.
local function furSpike(model: Model, torso: BasePart, base: Vector3, dir: Vector3, len: number, width: number, roll: number, crossed: boolean, color: Color3)
	local cf = CFrame.lookAt(base, base + dir) * CFrame.Angles(0, 0, roll)
	local rolls = if crossed then { 0, math.pi / 2 } else { 0 }
	for _, r in ipairs(rolls) do
		local c = cf * CFrame.Angles(0, 0, r)
		local size = Vector3.new(0.12, width * 0.5, len)
		furPart(model, torso, "wedge", size, c * CFrame.new(0, width * 0.25, -len * 0.5), color)
		furPart(model, torso, "wedge", size, c * CFrame.new(0, -width * 0.25, -len * 0.5) * CFrame.Angles(0, 0, math.pi), color)
	end
end

-- Keep the face clear: the space in front of and beside the head (torso
-- space), widened by `pad`. Fur behind the head is fine.
local function inFace(torso: BasePart, pt: Vector3, pad: number): boolean
	local top = torso.Size.Y * 0.5
	return pt.Y > top + 0.2 - pad and pt.Z < 0.3 + pad and math.abs(pt.X) < 0.7 + pad
end

local function buildFur(model: Model, torso: BasePart, style: Style)
	local rng = Random.new(20260930)
	local m = style.mantle or 1
	local fs = style.furSize or 1 -- (not `k`: the loop below counts with k)
	local function tint(): Color3
		return style.fur:Lerp(style.furShade, rng:NextNumber(0, 0.45))
	end
	for _, ring in ipairs(FUR_RINGS) do
		for k = 1, ring.n do
			local theta = (k - 0.5) / ring.n * math.pi * 2 + rng:NextNumber(-0.08, 0.08)
			-- Open at the chest.
			local front = math.abs(math.atan2(math.sin(theta), math.cos(theta)))
			if front < 0.95 - 0.35 * ring.s then continue end
			local p = mantlePoint(torso, theta, ring.s, m)
			-- (heaped over the left shoulder: -X is the wearer's left)
			local side = if style.lean then 1 + style.lean * (if p.X < 0 then 1 else -0.45) * math.min(math.abs(p.X), 1) else 1
			if ring.ball > 0 and not inFace(torso, p, ring.ball * 0.45) then
				local b = ring.ball * rng:NextNumber(0.85, 1.15) * (1 + (m - 1) * 0.6) * fs * side
				furPart(model, torso, "ball", Vector3.new(b * 1.1, b * 0.9, b), CFrame.new(p) * CFrame.Angles(0, theta, 0), tint())
			end
			-- Outward from the neck; inner tufts stand up, outer ones hang.
			local radial = Vector3.new(p.X, 0, p.Z)
			radial = if radial.Magnitude > 1e-3 then radial.Unit else Vector3.zAxis
			-- Tufts bristle up and out of the bulk (the outer ones level out).
			for t = 1, 2 do
				local lift = 1.0 - 1.15 * ring.s + rng:NextNumber(-0.35, 0.35) + (t - 1) * 0.4
				local side = Vector3.new(-radial.Z, 0, radial.X) * rng:NextNumber(-0.5, 0.5)
				local dir = (radial + side + Vector3.new(0, lift, 0)).Unit
				local len = ring.spike * rng:NextNumber(0.75, 1.3) * (1 + (m - 1) * 0.6) * fs * side
				local width = 0.4 * rng:NextNumber(0.8, 1.2) * (0.5 + 0.5 * fs)
				local base = p + dir * (ring.ball * 0.25 * fs)
				if inFace(torso, base, 0.1) or inFace(torso, base + dir * len, 0.1) then continue end
				-- (the outer tufts of a crimson-tipped mantle redden)
				local col = if style.feathers and ring.s >= 0.7 and rng:NextNumber() < 0.55
					then style.furShade:Lerp(style.fur, rng:NextNumber(0, 0.3)) else tint()
				furSpike(model, torso, base, dir, len, width, rng:NextNumber(-0.6, 0.6), t == 1 and ring.s >= 0.7, col)
			end
		end
	end
	if style.brooch then
		-- A dark iron star with a crimson jewel, pinning the mantle at the
		-- left collarbone.
		local at = mantlePoint(torso, -0.75, 0.45, m) + Vector3.new(0, -0.15, -0.12)
		local face = CFrame.lookAt(at, at + Vector3.new(at.X, 0, at.Z).Unit)
		for k = 0, 3 do
			local arm = face * CFrame.Angles(0, 0, k * math.pi / 2) * CFrame.new(0, 0.22, 0)
			furPart(model, torso, "wedge", Vector3.new(0.06, 0.38, 0.12), arm, Color3.fromRGB(40, 36, 40))
		end
		local gem = furPart(model, torso, "ball", Vector3.one * 0.2, face * CFrame.new(0, 0, -0.06), Color3.fromRGB(230, 20, 36))
		gem.Material = Enum.Material.Neon
		gem.Name = "BroochGem"
	end
end

-- Hang a cloth cape on `character` (R6 Torso, or UpperTorso on R15). `tag`
-- marks it for ClassLook-style cleanup; `style` defaults to the Sword
-- Master's.
function ClothCape.Attach(character: Model, tag: string?, style: Style?): Model?
	local st: Style = style or ClothCape.SWORD_MASTER
	ClothCape.Detach(character)
	local torso = (character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso")) :: BasePart?
	if not torso then return nil end

	local model = Instance.new("Model")
	model.Name = "ClothCape"
	-- Never copied along with the character (the menu hero is a clone of
	-- it); each copy gets its own simulated cape.
	model.Archivable = false
	if tag then model:SetAttribute(tag, true) end
	buildFur(model, torso, st)

	local function fabric(p: BasePart)
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.Massless = true
		p.CastShadow = true
		p.Material = Enum.Material.Fabric
	end

	-- The cloth mesh when EditableMesh is allowed, panels otherwise.
	local mesh: EditableMesh?, meshPart: MeshPart? = nil, nil
	local outer, inner = {}, {}
	-- (tried once: when the experience doesn't allow EditableMesh, every
	-- try prints Studio's warning, so after the first failure go straight
	-- to panels)
	local ok, em, o, i = false, nil, nil, nil
	if meshAllowed ~= false then
		ok, em, o, i = pcall(buildMesh, st)
		if not ok then meshAllowed = false end
	end
	if ok then
		local okPart, part = pcall(function()
			return AssetService:CreateMeshPartAsync(Content.fromObject(em :: EditableMesh))
		end)
		if okPart and part then
			mesh, meshPart = em :: EditableMesh, part :: MeshPart
			outer, inner = o :: { number }, i :: { number }
		else
			(em :: EditableMesh):Destroy()
		end
	end
	local panels: { BasePart } = {}
	local cut = cutoffs(st)
	if meshPart then
		meshPart.Name = "Cloth"
		fabric(meshPart)
		meshPart.Color = Color3.new(1, 1, 1) -- vertex colours carry the dye
		meshPart.CFrame = torso.CFrame
		meshPart.Parent = model
	else
		for r = 1, ROWS - 1 do
			for _ = 1, COLS - 1 do
				local p = Instance.new("Part")
				p.Name = "ClothPanel"
				fabric(p)
				p.Color = if st.tip then rowColor(st, r + 1) elseif r == ROWS - 1 then st.hem else st.outer
				p.TopSurface = Enum.SurfaceType.Smooth
				p.BottomSurface = Enum.SurfaceType.Smooth
				p.CFrame = torso.CFrame
				p.Parent = model
				table.insert(panels, p)
				-- (below a shredded column's end: not there)
				if r + 1 > cut[#panels - (r - 1) * (COLS - 1)] then p.Transparency = 1 end
			end
		end
	end

	local rayParams = RaycastParams.new()
	rayParams.FilterType = Enum.RaycastFilterType.Exclude
	rayParams.FilterDescendantsInstances = { character }
	rayParams.IgnoreWater = true

	local cape: Cape = {
		model = model,
		part = meshPart,
		mesh = mesh,
		panels = panels,
		panelCFs = table.create(#panels),
		torso = torso,
		character = character,
		style = st,
		pos = {},
		prev = {},
		pinLocal = {},
		constraints = {},
		outerIds = outer,
		innerIds = inner,
		colliders = collidersOf(character, st.armor),
		feathers = {},
		featherParts = {},
		featherCFs = {},
		cut = cut,
		rayParams = rayParams,
		floorY = -math.huge,
		floorAt = -1,
		lastTorso = torso.Position,
		collidersAt = os.clock(),
	}
	for r = 1, ROWS do
		for c = 1, COLS do
			local i = idx(r, c)
			local l = restPoint(torso, r, c, st)
			local p = torso.CFrame:PointToWorldSpace(l)
			cape.pos[i], cape.prev[i] = p, p
			if r == 1 then cape.pinLocal[i] = l end
		end
	end
	-- Structural, shear and bend links.
	for r = 1, ROWS do
		for c = 1, COLS do
			if c < COLS then addConstraint(cape, idx(r, c), idx(r, c + 1)) end
			if r < ROWS then addConstraint(cape, idx(r, c), idx(r + 1, c)) end
			if r < ROWS and c < COLS then
				addConstraint(cape, idx(r, c), idx(r + 1, c + 1))
				addConstraint(cape, idx(r, c + 1), idx(r + 1, c))
			end
			if c + 2 <= COLS then addConstraint(cape, idx(r, c), idx(r, c + 2)) end
			if r + 2 <= ROWS then addConstraint(cape, idx(r, c), idx(r + 2, c)) end
		end
	end

	-- Feathers shingled down the cloth: a row at every other particle row,
	-- staggered, longest at the torn ends (where they become the fringe).
	if st.feathers then
		local rng = Random.new(777)
		local top = st.featherTop or st.outer
		local tipC = st.featherTip or st.hem
		for r = 2, ROWS - 1 do
			if r % 2 == 1 and r < ROWS - 1 then continue end
			for c = 1, COLS do
				-- (the column under it must still be cloth)
				local colCut = math.min(cut[math.min(c, COLS - 1)], cut[math.max(c - 1, 1)])
				if r >= colCut then continue end
				local v = (r - 1) / (ROWS - 1)
				local last = r + 2 >= colCut
				local len = (0.75 + 0.6 * v) * rng:NextNumber(0.85, 1.2) * (if last then 1.7 else 1)
				local width = rng:NextNumber(0.42, 0.6)
				local k = math.clamp((v - 0.25) / 0.75, 0, 1) ^ 1.3
				local col = top:Lerp(tipC, k * rng:NextNumber(0.75, 1))
				local f: Feather = { i = idx(r, c), j = idx(math.min(r + 1, ROWS), c), len = len, width = width, parts = {} }
				for _ = 1, 2 do
					local w = Instance.new("WedgePart")
					w.Name = "Feather"
					fabric(w)
					w.Material = if last and k > 0.6 then Enum.Material.Neon else Enum.Material.SmoothPlastic
					w.Color = if w.Material == Enum.Material.Neon then col:Lerp(Color3.new(0, 0, 0), 0.35) else col
					w.Size = Vector3.new(0.05, width * 0.5, len)
					w.CFrame = torso.CFrame
					w.Parent = model
					table.insert(f.parts, w)
					table.insert(cape.featherParts, w)
				end
				table.insert(cape.feathers, f)
			end
		end
		cape.featherCFs = table.create(#cape.featherParts)
	end

	-- Settle the drape before it's first seen.
	capes[character] = cape
	for _ = 1, 60 do simulate(cape, 1 / 60, os.clock()) end
	model.Parent = character
	model.Destroying:Connect(function()
		if capes[character] == cape then
			capes[character] = nil
			if cape.mesh then cape.mesh:Destroy() end
		end
	end)
	if not conn then
		-- After physics, so the torso is already where this frame's pose put it.
		conn = RunService.Heartbeat:Connect(step)
	end
	return model
end

return ClothCape
