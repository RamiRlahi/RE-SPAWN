--[[
	WeaponGrip.luau
	Roblox always attaches an equipped Tool to the right hand via a "RightGrip"
	weld. ToLeftHand moves that grip onto the left hand instead (used for the
	Ranger's bow), keeping the tool's own Grip offsets. Shared so the server's
	real equip and the class-selection preview hold weapons the same way.
--]]

local WeaponGrip = {}

-- Extra rotation/offset applied on the left hand, in case the mirrored grip
-- needs flipping for a particular mesh (e.g. CFrame.Angles(0, math.pi, 0)).
WeaponGrip.LEFT_HAND_ADJUST = CFrame.identity

function WeaponGrip.ToLeftHand(character: Model, tool: Instance)
	local rightLimb = character:FindFirstChild("Right Arm") or character:FindFirstChild("RightHand")
	local leftLimb = (character:FindFirstChild("Left Arm") or character:FindFirstChild("LeftHand")) :: BasePart?
	local handle = tool:FindFirstChild("Handle") or tool:FindFirstChildWhichIsA("BasePart")
	if not rightLimb or not leftLimb or not (handle and handle:IsA("BasePart")) then return end

	-- The humanoid creates RightGrip a moment after EquipTool.
	local rightGrip = rightLimb:WaitForChild("RightGrip", 2)
	if not (rightGrip and (rightGrip:IsA("Weld") or rightGrip:IsA("Motor6D"))) then return end

	local old = leftLimb:FindFirstChild("LeftGrip")
	if old then old:Destroy() end
	local leftGrip = Instance.new("Weld")
	leftGrip.Name = "LeftGrip"
	leftGrip.Part0 = leftLimb
	leftGrip.Part1 = handle
	leftGrip.C0 = (rightGrip :: Weld).C0 * WeaponGrip.LEFT_HAND_ADJUST
	leftGrip.C1 = (rightGrip :: Weld).C1
	leftGrip.Parent = leftLimb
	rightGrip:Destroy()
end

return WeaponGrip
