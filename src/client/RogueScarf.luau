--!strict
--[[
	RogueScarf.luau
	The Rogue's scarf, on every Rogue, built and simulated by every client: a
	deep red scarf pulled up over the mouth and wound round the neck, and
	three long frayed tails knotted at the back that blow in the wind.

	Each tail is a Verlet chain: its first point pinned at the knot, the rest
	falling under gravity, pushed by a breeze that gusts and turns, and by the
	air the Rogue moves through (running, the dash, the Shadow Step: the tails
	stream out behind). They're kept off the back of the torso. Each link is a
	flat cloth strip drawn between two points, narrowing toward the end.

	The parts live inside the character, so the Rogue's invisibility fades
	them with the rest of the body. Scarves far from the camera aren't stepped.
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local RogueScarf = {}

local CLOTH = Color3.fromRGB(128, 18, 24)  -- deep red
local FOLD = Color3.fromRGB(104, 14, 20)   -- the layers wrapped over it
local FRINGE = Color3.fromRGB(78, 10, 15)  -- the frayed ends
local GRAVITY = Vector3.new(0, -32, 0)
local DAMPING = 0.96
local ITERATIONS = 4
local AIR = 1.6          -- how hard moving air pushes the cloth
local CULL_DIST = 150

type Tail = {
	pos: { Vector3 },
	prev: { Vector3 },
	seg: number,          -- rest length of each link
	strips: { BasePart },
	side: number,         -- -1 left, 1 right (where it's knotted)
	width: number,
}
type Scarf = { char: Model, model: Model, head: BasePart, torso: BasePart, root: BasePart, tails: { Tail }, phase: number }

local scarves: { [Model]: Scarf } = {}
-- Characters that aren't players' but wear one (the class-select preview).
local tracked: { [Model]: boolean } = {}

local function isRogueChar(char: Model): boolean
	if tracked[char] then return true end
	if char:GetAttribute("Class") == "rogue" then return true end
	local p = Players:GetPlayerFromCharacter(char)
	return p ~= nil and p:GetAttribute("SelectedClass") == "rogue" and p:GetAttribute("InLobby") == false
end

local function strip(parent: Instance, color: Color3): BasePart
	local p = Instance.new("Part")
	p.Name = "ScarfTail"
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow = true, false, false, false, false
	p.Material = Enum.Material.Fabric
	p.Color = color
	p.Size = Vector3.new(0.4, 0.06, 0.4)
	p.Parent = parent
	return p
end

-- Where the tails are knotted: the back of the neck, on top of the torso.
-- (Everything hangs off the torso, never the head: avatar heads and hair
-- come in every size.)
local function knot(s: Scarf, side: number): Vector3
	local t = s.torso
	return (t.CFrame * CFrame.new(side * 0.18, t.Size.Y / 2 - 0.05, t.Size.Z / 2 + 0.05)).Position
end

-- How big the head looks (a classic R6 head is a 2x1x1 part drawn smaller
-- by its mesh; an R15 head's part is its real size).
local function headLook(head: BasePart): Vector3
	if head:IsA("MeshPart") then return head.Size end
	return Vector3.one * 1.22 * head.Size.Y
end

local function band(model: Model, base: BasePart, name: string, d: number, h: number, cf: CFrame, color: Color3): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Shape = Enum.PartType.Cylinder
	p.CanCollide, p.CanQuery, p.CanTouch, p.CastShadow, p.Massless = false, false, false, false, true
	p.Material = Enum.Material.Fabric
	p.Color = color
	p.Size = Vector3.new(h, d, d)
	p.CFrame = cf * CFrame.Angles(0, 0, math.rad(90)) -- (the cylinder's axis standing up)
	local w = Instance.new("WeldConstraint")
	w.Part0, w.Part1 = base, p
	w.Parent = p
	p.Parent = model
	return p
end

local function build(char: Model): Scarf?
	local head = char:FindFirstChild("Head") :: BasePart?
	local torso = (char:FindFirstChild("UpperTorso") or char:FindFirstChild("Torso")) :: BasePart?
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (head and torso and root) then return nil end
	local model = Instance.new("Model")
	model.Name = "RogueScarf"
	model.Parent = char
	-- Pulled up over the mouth and chin (just bigger than the head, so it
	-- wraps it rather than sits on it), a looser layer under it, and the
	-- band round the neck on the shoulders.
	local v = headLook(head)
	local d = math.max(v.X, v.Z)
	band(model, head, "ScarfMouth", d * 1.07, v.Y * 0.34, head.CFrame * CFrame.new(0, -v.Y * 0.24, 0), CLOTH)
	band(model, head, "ScarfFold", d * 1.12, v.Y * 0.16, head.CFrame * CFrame.new(0, -v.Y * 0.4, 0.02) * CFrame.Angles(math.rad(6), 0, 0), FOLD)
	band(model, torso, "ScarfNeck", math.clamp(torso.Size.X * 0.62, 1, 1.4), 0.36,
		torso.CFrame * CFrame.new(0, torso.Size.Y / 2 + 0.08, 0.04) * CFrame.Angles(math.rad(-8), 0, 0), CLOTH)

	local s: Scarf = { char = char, model = model, head = head, torso = torso, root = root, tails = {}, phase = math.random() * 10 }
	-- Three tails of different lengths, frayed at the ends.
	local specs = {
		{ side = -1, len = 3.9, n = 9, width = 0.56 },
		{ side = 0.4, len = 3.1, n = 8, width = 0.46 },
		{ side = 1, len = 2.3, n = 6, width = 0.36 },
	}
	for i, spec in ipairs(specs) do
		local t: Tail = { pos = {}, prev = {}, seg = spec.len / (spec.n - 1), strips = {}, side = spec.side, width = spec.width }
		local start = knot(s, spec.side)
		local down = -torso.CFrame.UpVector * 0.85 + torso.CFrame.LookVector * -0.5
		for k = 1, spec.n do
			local p = start + down.Unit * t.seg * (k - 1)
			t.pos[k] = p
			t.prev[k] = p
		end
		for k = 1, spec.n - 1 do
			table.insert(t.strips, strip(model, if k >= spec.n - 2 then FRINGE else CLOTH))
		end
		s.tails[i] = t
	end
	return s
end

-- Keep a point off the back of the torso (and out of it).
local function offBack(torso: BasePart, p: Vector3): Vector3
	local l = torso.CFrame:PointToObjectSpace(p)
	local hx, hy = torso.Size.X / 2 + 0.1, torso.Size.Y / 2 + 0.2
	local back = torso.Size.Z / 2 + 0.12
	if math.abs(l.X) < hx and l.Y < hy and l.Y > -hy - 1.6 and l.Z < back then
		l = Vector3.new(l.X, l.Y, back)
		return torso.CFrame:PointToWorldSpace(l)
	end
	return p
end

local function simulate(s: Scarf, dt: number, now: number)
	dt = math.min(dt, 1 / 30)
	local vel = s.root.AssemblyLinearVelocity
	-- The breeze: a slow turning drift that gusts now and then.
	local ang = now * 0.3 + s.phase
	local gust = 1 + 0.8 * math.max(math.sin(now * 1.7 + s.phase), 0) ^ 3
	local breeze = Vector3.new(math.cos(ang), 0.15, math.sin(ang)) * 5 * gust
	-- The air the Rogue moves through blows the other way.
	local airflow = (breeze - vel) * AIR
	for _, t in ipairs(s.tails) do
		local n = #t.pos
		t.pos[1] = knot(s, t.side)
		t.prev[1] = t.pos[1]
		for k = 2, n do
			local p, q = t.pos[k], t.prev[k]
			-- (the far end catches more of the wind, and flutters)
			local reach = k / n
			local flutter = Vector3.new(0, math.sin(now * 13 + k * 0.9 + t.side) * 6, 0) * reach
			local acc = GRAVITY + (airflow + flutter) * reach
			local nextP = p + (p - q) * DAMPING + acc * dt * dt
			t.prev[k] = p
			t.pos[k] = nextP
		end
		for _ = 1, ITERATIONS do
			for k = 1, n - 1 do
				local a, b = t.pos[k], t.pos[k + 1]
				local d = b - a
				local len = d.Magnitude
				if len > 1e-4 then
					local fix = d * ((len - t.seg) / len)
					if k == 1 then
						t.pos[k + 1] = b - fix
					else
						t.pos[k] = a + fix * 0.5
						t.pos[k + 1] = b - fix * 0.5
					end
				end
			end
			for k = 2, n do t.pos[k] = offBack(s.torso, t.pos[k]) end
		end
		-- Draw: one flat strip per link, its face to the back.
		local look = s.torso.CFrame.LookVector
		for k = 1, n - 1 do
			local a, b = t.pos[k], t.pos[k + 1]
			local d = b - a
			local len = d.Magnitude
			if len < 1e-3 then continue end
			local w = t.width * (1 - 0.45 * (k - 1) / (n - 1))
			if k >= n - 2 then w *= if k == n - 1 then 0.45 else 0.75 end -- (frayed)
			local up = if math.abs(d.Unit:Dot(look)) > 0.95 then s.torso.CFrame.UpVector else look
			local st = t.strips[k]
			st.Size = Vector3.new(w, 0.06, len + 0.08)
			st.CFrame = CFrame.lookAt((a + b) / 2, b, up)
		end
	end
end

local function remove(char: Model)
	local s = scarves[char]
	if not s then return end
	scarves[char] = nil
	s.model:Destroy()
end

-- Who should wear one: dress new Rogues, undress everyone else.
local function refresh()
	for char in pairs(scarves) do
		if not char.Parent or not isRogueChar(char) then remove(char) end
	end
	local chars: { Model } = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then table.insert(chars, p.Character) end
	end
	for m in pairs(tracked) do
		if m.Parent then table.insert(chars, m) else tracked[m] = nil end
	end
	for _, char in ipairs(chars) do
		if char.Parent and not scarves[char] and isRogueChar(char) then
			local hum = char:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health > 0 then
				local s = build(char)
				if s then scarves[char] = s end
			end
		end
	end
end

-- Put a scarf on (or take it off) a character that isn't a player's: the
-- class-select preview.
function RogueScarf.Track(char: Model, on: boolean)
	if on then
		tracked[char] = true
	else
		tracked[char] = nil
		remove(char)
	end
end

function RogueScarf.Init()
	task.spawn(function()
		while true do
			pcall(refresh)
			task.wait(0.5)
		end
	end)
	RunService.RenderStepped:Connect(function(dt)
		local cam = Workspace.CurrentCamera
		local camPos = if cam then cam.CFrame.Position else Vector3.zero
		local now = os.clock()
		for char, s in pairs(scarves) do
			if not (s.head.Parent and s.torso.Parent and s.root.Parent) then
				remove(char)
				continue
			end
			if (s.root.Position - camPos).Magnitude > CULL_DIST then continue end
			local ok, err = pcall(simulate, s, dt, now)
			if not ok then
				warn("[RogueScarf]", err)
				remove(char)
			end
		end
	end)
end

return RogueScarf
