--!strict
--[[
	ClassLook.luau
	Dresses any character model in a class's look: the class weapon in hand
	and, when `armor` is set (the player owns and wears it), the class armor.
	Used on client-only copies (the hero in the menu, the party around the
	campfire), so the weapon is welded straight into the hand rather than
	equipped through the Humanoid. Everything added is tagged ClassLook and
	removed by Clear.
--]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ClassData = require(Shared:WaitForChild("ClassData"))
local ClassArmor = require(Shared:WaitForChild("ClassArmor"))
local IceCape = require(Shared:WaitForChild("IceCape"))
local WeaponGrip = require(Shared:WaitForChild("WeaponGrip"))
local RevolverModel = require(Shared:WaitForChild("RevolverModel"))
local SwordModel = require(Shared:WaitForChild("SwordModel"))
local BerserkerLook = require(Shared:WaitForChild("BerserkerLook"))
local ClothCape = require(script.Parent:WaitForChild("ClothCape"))

local ClassLook = {}

local TAG = "ClassLook"
ClassLook.Tag = TAG

-- Weapons per class (matches WeaponManager's loadouts). The revolver and the
-- longsword are built in code; the others are Tools in ReplicatedStorage.
local WEAPONS: { [string]: string } = {
	heavy_knight = "Greatsword",
	ranger = "Bow",
	gunslinger = "Revolver",
	swordsman = "Longsword",
}

local function findTool(name: string): Tool?
	local found = ReplicatedStorage:FindFirstChild(name) or ReplicatedStorage:FindFirstChild(name, true)
	if found and found:IsA("Tool") then return found end
	if found then
		local inner = found:FindFirstChildWhichIsA("Tool", true)
		if inner then return inner end
	end
	-- Case-insensitive, Tools only (a Folder can share a weapon's name).
	local lower = string.lower(name)
	for _, d in ipairs(ReplicatedStorage:GetDescendants()) do
		if d:IsA("Tool") and string.lower(d.Name) == lower then return d end
	end
	return nil
end

local function buildWeapon(classId: string): Tool?
	if classId == "gunslinger" then return RevolverModel.Build() end
	if classId == "swordsman" then return SwordModel.Build() end
	if classId == "berserker" then return BerserkerLook.BuildGreatsword() end
	local name = WEAPONS[classId]
	local template = name and findTool(name)
	return if template then template:Clone() else nil
end

-- Remove everything a previous Apply added.
function ClassLook.Clear(character: Model)
	for _, d in ipairs(character:GetDescendants()) do
		if d:GetAttribute(TAG) and d.Parent then d:Destroy() end
	end
end

export type Options = {
	armor: boolean?,                          -- also wear the class armor
	grip: ((classId: string, grip: CFrame) -> CFrame)?, -- adjust how the weapon sits in the hand
	handTilt: CFrame?,                        -- turn the weapon about the hand (pivot at the grip)
	plant: CFrame?,                           -- stand the weapon here (Torso space, blade down) instead of in the hand
	plantScale: number?,                      -- resize the planted weapon
	onBack: boolean?,                         -- sling the weapon across the back instead (seated heroes)
}

-- Swords: slung across the back when their hero sits down.
ClassLook.SWORD_CLASSES = { heavy_knight = true, swordsman = true, berserker = true } :: { [string]: boolean }

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

local function biggestPart(tool: Tool, handle: BasePart): BasePart
	local blade: BasePart = handle
	for _, d in ipairs(tool:GetDescendants()) do
		if d:IsA("BasePart") and d.Size.Magnitude > blade.Size.Magnitude then blade = d end
	end
	return blade
end

-- The handle's CFrame in Torso space. `gripAt` is where the hand holds it
-- (handle space).
local function backCFrame(tool: Tool, handle: BasePart, gripAt: Vector3): CFrame
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
local function backClearance(character: Model, tool: Tool, torso: BasePart, handle: BasePart, c0: CFrame): number
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
local function scaleTool(tool: Tool, handle: BasePart, k: number)
	local holder = Instance.new("Model")
	for _, c in ipairs(tool:GetChildren()) do c.Parent = holder end
	holder.PrimaryPart = handle
	holder:ScaleTo(k)
	for _, c in ipairs(holder:GetChildren()) do c.Parent = tool end
	holder:Destroy()
end

-- Handle-space turn that points the blade straight down (-Y). The game's
-- sword asset runs its blade along the Handle's +Y, the built one along -Z.
local function bladeDown(tool: Tool): CFrame
	if tool:GetAttribute("BladeAxis") == "-Z" then return CFrame.Angles(math.rad(-90), 0, 0) end
	return CFrame.Angles(math.pi, 0, 0)
end

-- Dress `character` as `classId` (clears any previous look first).
function ClassLook.Apply(character: Model, classId: string, opts: Options?)
	ClassLook.Clear(character)
	if not ClassData.IsPlayable(classId) then return end
	local o = opts or {}
	local backWeld: Weld? = nil -- a slung weapon, eased out past the armor once it's on

	local tool = buildWeapon(classId)
	local right = (character:FindFirstChild("Right Arm") or character:FindFirstChild("RightHand")) :: BasePart?
	local left = (character:FindFirstChild("Left Arm") or character:FindFirstChild("LeftHand")) :: BasePart?
	if tool and right and left then
		local handle = (tool:FindFirstChild("Handle") or tool:FindFirstChildWhichIsA("BasePart")) :: BasePart?
		if handle then
			tool.Name = "Look_" .. classId
			tool:SetAttribute(TAG, true)
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
			-- Loose parts ride on the handle.
			for _, d in ipairs(tool:GetDescendants()) do
				if d:IsA("BasePart") and d ~= handle and not d:FindFirstChildWhichIsA("JointInstance") and not d:FindFirstChildWhichIsA("WeldConstraint") then
					local wc = Instance.new("WeldConstraint")
					wc.Part0 = handle
					wc.Part1 = d
					wc.Parent = d
				end
			end
			local grip = tool.Grip
			if o.grip then grip = o.grip(classId, grip) end
			-- Where Roblox would put an equipped tool: the right grip
			-- attachment. The Ranger holds the bow in the left hand, as in-game.
			-- (R6: the fixed offset Roblox's own RightGrip uses; the rig's
			-- RightGripAttachment is oriented differently and turns the blade
			-- back along the arm.)
			local att = right:FindFirstChild("RightGripAttachment")
			local c0 = if right.Name == "Right Arm" or not (att and att:IsA("Attachment"))
				then CFrame.new(0, -1, 0, 1, 0, 0, 0, 0, 1, 0, -1, 0)
				else att.CFrame
			local hand = right
			if classId == "ranger" then
				hand = left
				c0 *= WeaponGrip.LEFT_HAND_ADJUST
			end
			if o.handTilt then c0 *= o.handTilt end
			local grip0: CFrame = grip
			local torso = (character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso")) :: BasePart?
			if o.onBack and torso then
				-- Slung across the back (shown smaller if it's a giant blade).
				local gripAt = grip.Position
				local len = math.max(biggestPart(tool, handle).Size.X, biggestPart(tool, handle).Size.Y, biggestPart(tool, handle).Size.Z)
				if len > BACK_LENGTH then
					local k = BACK_LENGTH / len
					scaleTool(tool, handle, k)
					gripAt *= k
				end
				hand = torso
				c0 = backCFrame(tool, handle, gripAt)
				grip0 = CFrame.identity
			elseif o.plant and torso then
				-- Planted in front of the body, hands resting on it: held by
				-- the torso so the blade stays upright whatever the arms do.
				if o.plantScale and o.plantScale ~= 1 then
					-- Scale the whole weapon (parts, joints, meshes) through a
					-- temporary Model, then hand the pieces back to the Tool.
					local holder = Instance.new("Model")
					for _, c in ipairs(tool:GetChildren()) do c.Parent = holder end
					holder.PrimaryPart = handle
					holder:ScaleTo(o.plantScale)
					for _, c in ipairs(holder:GetChildren()) do c.Parent = tool end
					holder:Destroy()
				end
				hand = torso
				c0 = o.plant
				grip0 = bladeDown(tool):Inverse()
			end
			tool.Parent = character
			-- Hold it the way an equipped tool is held in-game: Roblox's
			-- default "toolnone" arm pose (the copy has no Animate script).
			if not o.handTilt and not o.plant and not o.onBack then
				local hum = character:FindFirstChildOfClass("Humanoid")
				local animator = hum and hum:FindFirstChildOfClass("Animator")
				if animator and hum.RigType == Enum.HumanoidRigType.R6 then
					local anim = Instance.new("Animation")
					anim.AnimationId = "rbxassetid://182393478"
					local ok, track = pcall(function() return animator:LoadAnimation(anim) end)
					if ok and track then
						track.Priority = Enum.AnimationPriority.Movement
						track.Looped = true
						track:Play(0.1)
						tool.Destroying:Connect(function() track:Stop(0.1) end)
					end
				end
			end
			local w = Instance.new("Weld")
			w.Name = "LookGrip"
			w:SetAttribute(TAG, true)
			w.Part0 = hand
			w.Part1 = handle
			w.C0 = c0
			w.C1 = grip0
			w.Parent = hand
			if o.onBack and hand.Name ~= "Right Arm" and hand.Name ~= "RightHand" then backWeld = w end
		else
			tool:Destroy()
		end
	elseif tool then
		tool:Destroy()
	end

	-- The Swordsman's long cloth cape (part of his look, not the armor).
	if classId == "swordsman" then
		local cape = ClothCape.Attach(character, TAG)
		if cape then cape:SetAttribute(TAG, true) end
	end

	if o.armor then
		ClassArmor.Equip(character, classId, TAG)
		if classId == "ice_mage" then IceCape.Attach(character, TAG) end
		-- The Fire Knight's outfit is his crimson cloth cape with black fur.
		if classId == "heavy_knight" then
			local cape = ClothCape.Attach(character, TAG, ClothCape.FIRE_KNIGHT)
			if cape then cape:SetAttribute(TAG, true) end
		elseif classId == "gunslinger" then
			local cape = ClothCape.Attach(character, TAG, ClothCape.GUNSLINGER)
			if cape then cape:SetAttribute(TAG, true) end
		end
	end

	-- The Berserker's ragged feather cape (part of his look, like in game),
	-- over his armour's flat plate cape.
	if classId == "berserker" then
		local cape = ClothCape.Attach(character, TAG, ClothCape.BERSERKER)
		if cape then cape:SetAttribute(TAG, true) end
		for _, d in ipairs(character:GetChildren()) do
			if d:IsA("BasePart") and (d.Name == "Cape" or d.Name == "CapeRag") then d.Transparency = 1 end
		end
	end

	-- Over the cloak, not through it.
	local bw = backWeld
	local torso = (character:FindFirstChild("Torso") or character:FindFirstChild("UpperTorso")) :: BasePart?
	if bw and torso and bw.Part1 then
		local tool = bw.Part1:FindFirstAncestorOfClass("Tool")
		if tool then
			local out = backClearance(character, tool, torso, bw.Part1 :: BasePart, bw.C0)
			if out > 0 then bw.C0 = CFrame.new(0, 0, out) * bw.C0 end
		end
	end
end

return ClassLook
