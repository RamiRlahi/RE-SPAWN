--!strict
--[[
	WeaponSling.luau
	Where a carried (not held) weapon sits on a character: swords and bows
	slung across the back, the revolver in its holster on the right hip. Used
	by the menu's copies (ClassLook: the heroes seated round the campfire) and
	by the real characters walking the lobby (WeaponManager.StowWeapon).

	  WeaponSling.BackCFrame(tool, handle, gripAt)   the handle's CFrame in Torso space, slung
	  WeaponSling.BackClearance(character, tool, torso, handle, c0)
	                                                 how far out to push it past armor and capes
	  WeaponSling.ScaleTool(tool, handle, k)         shrink a weapon (a giant blade, on the back)
	  WeaponSling.BiggestPart(tool, handle)          its blade (or limb)
	  WeaponSling.HipCFrame(torso)                   the revolver's holster, Torso space
	  WeaponSling.Stow(character, tool, onHip)       carry `tool` (turned into a Model) slung or holstered
--]]

local WeaponSling = {}

-- Where a weapon sits slung across the back, as the handle's CFrame in Torso
-- space: the hilt up behind the right shoulder, the blade running down and
-- across to the left, its flat against the back. Worked out from the weapon
-- itself (its blade is its biggest part; the hilt is the end the hand holds),
-- so any sword fits.
local BACK_GRIP = Vector3.new(0.75, 1.45, 0)   -- the hilt (X, Y; Z is worked out), torso space, +Z = the back
local BACK_ANGLE = math.rad(50)                 -- the blade's tilt from straight down
local BACK_LENGTH = 5.6                         -- bigger weapons are shown smaller on the back
local BACK_CLEAR = 0.55                         -- the nearest point sits this far behind the torso's centre
local BACK_PUSH_MAX = 2.0                       -- never pushed further out than this (past a mantle or cape)
WeaponSling.BACK_LENGTH = BACK_LENGTH

function WeaponSling.BiggestPart(tool: Instance, handle: BasePart): BasePart
	local blade: BasePart = handle
	for _, d in ipairs(tool:GetDescendants()) do
		if d:IsA("BasePart") and d.Size.Magnitude > blade.Size.Magnitude then blade = d end
	end
	return blade
end
local biggestPart = WeaponSling.BiggestPart

-- The handle's CFrame in Torso space. `gripAt` is where the hand holds it
-- (handle space).
function WeaponSling.BackCFrame(tool: Instance, handle: BasePart, gripAt: Vector3): CFrame
	local blade = biggestPart(tool, handle)
	local s = blade.Size
	local axes = { { Vector3.xAxis, s.X }, { Vector3.yAxis, s.Y }, { Vector3.zAxis, s.Z } }
	table.sort(axes, function(a, b) return a[2] > b[2] end)
	local function toHandle(v: Vector3): Vector3
		return handle.CFrame:VectorToObjectSpace(blade.CFrame:VectorToWorldSpace(v))
	end
	local long = toHandle(axes[1][1])
	local center = handle.CFrame:PointToObjectSpace(blade.Position)
	if (center - gripAt):Dot(long) < 0 then long = -long end -- point it hilt → tip
	-- Every visible corner, handle space (to lay it flat against the back).
	local corners: { Vector3 } = {}
	for _, d in ipairs(tool:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 1 then
			local h = d.Size / 2
			for _, c in ipairs({ Vector3.new(1, 1, 1), Vector3.new(1, 1, -1), Vector3.new(1, -1, 1), Vector3.new(1, -1, -1),
				Vector3.new(-1, 1, 1), Vector3.new(-1, 1, -1), Vector3.new(-1, -1, 1), Vector3.new(-1, -1, -1) }) do
				table.insert(corners, handle.CFrame:PointToObjectSpace(d.CFrame:PointToWorldSpace(h * c)))
			end
		end
	end
	-- Hilt → tip runs down and to the left; of the blade's two other axes, the
	-- one that lies thinnest against the back faces it.
	local down = Vector3.new(-math.sin(BACK_ANGLE), -math.cos(BACK_ANGLE), 0)
	local to = CFrame.fromMatrix(Vector3.zero, down, Vector3.zAxis, down:Cross(Vector3.zAxis))
	local best: { r: CFrame, minZ: number, depth: number }? = nil
	for _, i in ipairs({ 2, 3 }) do
		local flat = toHandle(axes[i][1])
		flat = (flat - long * flat:Dot(long)).Unit
		local r = to * CFrame.fromMatrix(Vector3.zero, long, flat, long:Cross(flat)):Inverse()
		local lo, hi = math.huge, -math.huge
		for _, c in ipairs(corners) do
			local z = (r * (c - gripAt)).Z
			lo, hi = math.min(lo, z), math.max(hi, z)
		end
		if not best or hi - lo < best.depth then best = { r = r, minZ = lo, depth = hi - lo } end
	end
	local b = best :: { r: CFrame, minZ: number, depth: number }
	local at = Vector3.new(BACK_GRIP.X, BACK_GRIP.Y, BACK_CLEAR - b.minZ)
	return CFrame.new(at) * b.r * CFrame.new(-gripAt)
end

-- How far the slung weapon must move out (along the back) to clear whatever
-- the character wears over its back (armor plates, capes): the backmost
-- point of anything else on the character within the weapon's outline.
function WeaponSling.BackClearance(character: Model, tool: Instance, torso: BasePart, handle: BasePart, c0: CFrame): number
	local function corners(p: BasePart, cf: CFrame): { Vector3 }
		local h = p.Size / 2
		local out = {}
		for _, c in ipairs({ Vector3.new(1, 1, 1), Vector3.new(1, 1, -1), Vector3.new(1, -1, 1), Vector3.new(1, -1, -1),
			Vector3.new(-1, 1, 1), Vector3.new(-1, 1, -1), Vector3.new(-1, -1, 1), Vector3.new(-1, -1, -1) }) do
			table.insert(out, cf * (h * c))
		end
		return out
	end
	-- the weapon's outline across the back, and how close it comes to it
	local x0, x1, y0, y1, zNear = math.huge, -math.huge, math.huge, -math.huge, math.huge
	for _, d in ipairs(tool:GetDescendants()) do
		if d:IsA("BasePart") and d.Transparency < 1 then
			for _, c in ipairs(corners(d, c0 * handle.CFrame:ToObjectSpace(d.CFrame))) do
				x0, x1, y0, y1 = math.min(x0, c.X), math.max(x1, c.X), math.min(y0, c.Y), math.max(y1, c.Y)
				zNear = math.min(zNear, c.Z)
			end
		end
	end
	local zBack = -math.huge
	for _, d in ipairs(character:GetDescendants()) do
		-- (anchored pieces are simulated, like cloth: they settle wherever the
		-- pose leaves them, so they never decide where the weapon goes)
		if d:IsA("BasePart") and d.Transparency < 1 and d.Name ~= "HumanoidRootPart" and not d.Anchored and not d:IsDescendantOf(tool) then
			for _, c in ipairs(corners(d, torso.CFrame:ToObjectSpace(d.CFrame))) do
				-- (the upper back only: a cape flaring out below would push it off the body)
				if c.Z > 0 and c.Y > -0.2 and c.X >= x0 and c.X <= x1 and c.Y >= y0 and c.Y <= y1 then zBack = math.max(zBack, c.Z) end
			end
		end
	end
	return math.clamp(zBack + 0.08 - zNear, 0, BACK_PUSH_MAX)
end

-- Shrink the whole weapon (parts, joints, meshes) by `k` through a temporary
-- Model, then hand the pieces back to the Tool.
function WeaponSling.ScaleTool(tool: Instance, handle: BasePart, k: number)
	local holder = Instance.new("Model")
	for _, c in ipairs(tool:GetChildren()) do c.Parent = holder end
	holder.PrimaryPart = handle
	holder:ScaleTo(k)
	for _, c in ipairs(holder:GetChildren()) do c.Parent = tool end
	holder:Destroy()
end

-- The revolver in the right-hip holster (barrel down, the grip tilted
-- forward for the draw), as the handle's CFrame in Torso space.
function WeaponSling.HipCFrame(torso: BasePart): CFrame
	local hip = if torso.Name == "Torso" then CFrame.new(1.2, -1.15, 0.02) else CFrame.new(1.05, -0.2, 0.02)
	return hip * CFrame.Angles(math.rad(-90 + 14), 0, 0)
end

-- Carry `tool` on `character`: slung across the back, or holstered on the
-- right hip. The tool's pieces move into a Model named StowedWeapon (a Tool
-- on a character is held in the hand), welded to the torso. Returns it.
function WeaponSling.Stow(character: Model, tool: Tool, onHip: boolean): Model?
	local torso = (character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso")) :: BasePart?
	local handle = (tool:FindFirstChild("Handle") or tool:FindFirstChildWhichIsA("BasePart", true)) :: BasePart?
	if not torso or not handle then
		tool:Destroy()
		return nil
	end
	for _, d in ipairs(tool:GetDescendants()) do
		if d:IsA("LuaSourceContainer") then
			d:Destroy()
		elseif d:IsA("BasePart") then
			d.Anchored = false
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			d.Massless = true
		end
	end
	local c0: CFrame
	if onHip then
		c0 = WeaponSling.HipCFrame(torso)
	else
		-- (shown smaller if it's a giant blade)
		local gripAt = tool.Grip.Position
		local b = biggestPart(tool, handle).Size
		local len = math.max(b.X, b.Y, b.Z)
		if len > BACK_LENGTH then
			local k = BACK_LENGTH / len
			WeaponSling.ScaleTool(tool, handle, k)
			gripAt *= k
		end
		c0 = WeaponSling.BackCFrame(tool, handle, gripAt)
	end
	local m = Instance.new("Model")
	m.Name = "StowedWeapon"
	for _, c in ipairs(tool:GetChildren()) do c.Parent = m end
	tool:Destroy()
	m.PrimaryPart = handle
	m:PivotTo(torso.CFrame * c0)
	local w = Instance.new("Weld")
	w.Name = "StowWeld"
	w.Part0 = torso
	w.Part1 = handle
	w.C0 = c0
	w.Parent = handle
	m.Parent = character
	-- Over the cloak, not through it.
	if not onHip then
		local out = WeaponSling.BackClearance(character, m, torso, handle, c0)
		if out > 0 then w.C0 = CFrame.new(0, 0, out) * c0 end
	end
	return m
end

return WeaponSling
