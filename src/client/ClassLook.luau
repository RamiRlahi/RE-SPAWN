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
local WeaponSling = require(Shared:WaitForChild("WeaponSling"))
local GearLook = require(Shared:WaitForChild("GearLook"))
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
	finish: string?,                          -- an Armory weapon finish (GearData id) on the weapon
	aura: string?,                            -- an Armory aura on the character
}

-- Swords: slung across the back when their hero sits down.
ClassLook.SWORD_CLASSES = { heavy_knight = true, swordsman = true, berserker = true } :: { [string]: boolean }

-- (Where it sits slung across the back: WeaponSling, shared with the lobby's
-- real characters.)
local BACK_LENGTH = WeaponSling.BACK_LENGTH
local biggestPart = WeaponSling.BiggestPart
local backCFrame = WeaponSling.BackCFrame
local backClearance = WeaponSling.BackClearance
local scaleTool = WeaponSling.ScaleTool

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
			-- (their Armory weapon finish)
			if o.finish then pcall(GearLook.Weapon, tool, o.finish) end
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

	-- (their Armory aura)
	if o.aura then pcall(GearLook.Aura, character, o.aura) end

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
