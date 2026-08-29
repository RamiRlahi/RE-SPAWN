--[[
	WeaponManager
	Equips class weapons and fixes large-mesh clipping.

	Root cause of the "holding air" bug:
	  The Greatsword's actual mesh is a MeshPart child of Handle (not Handle itself).
	  Roblox's GripWeld only attaches Handle to the hand — the MeshPart has no
	  weld at all so it sits at world origin (invisible at your feet).

	Strategy:
	  1. Call Humanoid:EquipTool() so Roblox's GripWeld is created on Handle.
	  2. Wait a frame for the weld to exist.
	  3. Replace the GripWeld with our offset one (corrects hand position).
	  4. Weld every OTHER BasePart in the tool (the MeshPart sword geometry)
	     to Handle so they follow it correctly.
	  5. CanCollide = false + Massless = true on everything so the big mesh
	     never clips through floors, walls, or other geometry.
--]]

local Players = game:GetService("Players")

-- ─────────────────────────────────────────────────────────────────────────────
-- Configuration
-- gripOffset moves the Handle (and therefore the whole sword) relative to RightHand.
--   CFrame.new(X, Y, Z)         X=left/right  Y=up/down  Z=forward/back
--   * CFrame.Angles(rX, rY, rZ)  rotates the blade (use math.rad() for degrees)
-- ─────────────────────────────────────────────────────────────────────────────
local WEAPON_CONFIG: { [string]: { toolName: string, gripOffset: CFrame } } = {
	heavy_knight = {
		toolName   = "Greatsword",
		-- Adjust Y/Angles until the grip sits comfortably in the palm.
		gripOffset = CFrame.new(0, -2.5, 0) * CFrame.Angles(0, 0, 0),
	},
}

local WeaponManager = {}

-- ── helpers ───────────────────────────────────────────────────────────────────

-- Disable CanCollide and Massless on every BasePart inside a tool.
local function disableCollision(root: Instance)
	if root:IsA("BasePart") then
		(root :: BasePart).CanCollide = false
		(root :: BasePart).Massless   = true
	end
	for _, part in ipairs(root:GetDescendants()) do
		if part:IsA("BasePart") then
			part.CanCollide = false
			part.Massless   = true
		end
	end
end

-- Weld every BasePart in the tool (except Handle) TO the Handle.
-- This is the key fix: the MeshPart that holds the sword geometry
-- is a loose child of Handle with no weld, so it falls to world origin.
local function weldLoosePartsToHandle(tool: Tool, handle: BasePart)
	for _, part in ipairs(tool:GetDescendants()) do
		if part:IsA("BasePart") and part ~= handle then
			-- Skip if already welded to something.
			local alreadyWelded = false
			for _, w in ipairs(part:GetChildren()) do
				if w:IsA("Weld") or w:IsA("WeldConstraint") or w:IsA("Motor6D") then
					alreadyWelded = true
					break
				end
			end
			for _, w in ipairs(handle:GetChildren()) do
				if (w:IsA("Weld") or w:IsA("WeldConstraint"))
					and ((w :: Weld).Part0 == part or (w :: Weld).Part1 == part) then
					alreadyWelded = true
					break
				end
			end

			if not alreadyWelded then
				local wc      = Instance.new("WeldConstraint")
				wc.Part0      = handle
				wc.Part1      = part :: BasePart
				wc.Parent     = handle
				print(`[WeaponManager]   welded loose part '{part.Name}' ({part.ClassName}) to Handle`)
			end
		end
	end
end

-- Replace Roblox's auto-generated GripWeld with our offset-corrected one.
local function replaceGripWeld(handle: BasePart, limb: BasePart, offset: CFrame)
	for _, w in ipairs(handle:GetChildren()) do
		if (w:IsA("Weld") or w:IsA("Motor6D")) and w.Name ~= "PartWeld" then
			print(`[WeaponManager]   removed weld: {w.Name}`)
			w:Destroy()
		end
	end

	local weld  = Instance.new("Weld")
	weld.Name   = "GripWeld"
	weld.Part0  = limb
	weld.Part1  = handle
	weld.C0     = offset
	weld.C1     = CFrame.identity
	weld.Parent = handle
	print(`[WeaponManager]   new GripWeld → Part0={limb.Name}  Part1={handle.Name}`)
end

-- ── main equip ────────────────────────────────────────────────────────────────

function WeaponManager.EquipWeapon(player: Player, classId: string)
	local config = WEAPON_CONFIG[classId]
	if not config then
		print(`[WeaponManager] No weapon config for '{classId}' — skipping.`)
		return
	end

	print(`[WeaponManager] Equipping '{config.toolName}' for {player.Name}`)

	local character = player.Character
	if not character then
		warn("[WeaponManager] No character found.")
		return
	end

	-- 1. Find the Tool
	local tool = character:FindFirstChild(config.toolName)
		or player.Backpack:FindFirstChild(config.toolName)

	if not tool or not tool:IsA("Tool") then
		warn(`[WeaponManager] Tool '{config.toolName}' not found.`)
		return
	end
	print(`[WeaponManager] Tool found in '{tool.Parent and tool.Parent.Name}'`)

	-- 2. Find Handle
	local handle = tool:FindFirstChild("Handle") :: BasePart?
	if not handle or not handle:IsA("BasePart") then
		warn(`[WeaponManager] '{tool.Name}' has no BasePart called 'Handle'.`)
		return
	end

	-- 3. Find Humanoid
	local humanoid = character:FindFirstChildOfClass("Humanoid") :: Humanoid?
	if not humanoid then
		warn("[WeaponManager] No Humanoid found.")
		return
	end

	-- 4. Pre-disable collision on all parts
	disableCollision(tool)

	-- 5. Weld all loose parts (e.g. the sword MeshPart) to Handle NOW,
	--    before equip, so they travel with Handle from the start.
	weldLoosePartsToHandle(tool, handle)

	-- 6. Equip via Humanoid so Roblox creates the GripWeld on Handle
	if tool.Parent ~= character then
		print("[WeaponManager] Calling Humanoid:EquipTool()...")
		humanoid:EquipTool(tool)
	else
		print("[WeaponManager] Tool already in character.")
	end

	-- 7. Replace Roblox's GripWeld with our offset one after a frame
	task.spawn(function()
		task.wait()  -- one frame so EquipTool's GripWeld is created

		local limb = character:FindFirstChild("RightHand")   -- R15
			or character:FindFirstChild("Right Arm") :: BasePart?  -- R6

		if not limb or not limb:IsA("BasePart") then
			warn("[WeaponManager] Could not find hand limb on character.")
			return
		end

		replaceGripWeld(handle, limb, config.gripOffset)
		disableCollision(tool)  -- re-apply in case Roblox toggled any back on

		print("[WeaponManager] Done — sword should now be visible in hand.")
	end)
end

-- ── respawn ───────────────────────────────────────────────────────────────────

function WeaponManager.Init()
	Players.PlayerAdded:Connect(function(player: Player)
		player.CharacterAdded:Connect(function()
			task.wait(1.5)
			local classId = player:GetAttribute("SelectedClass")
			if classId then
				WeaponManager.EquipWeapon(player, classId)
			end
		end)
	end)
end

return WeaponManager
