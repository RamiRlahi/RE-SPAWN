--!strict
--[[
	SafeMove.luau
	Keeps fast movement (dashes, rolls, Blade Storm teleports) from sinking the
	player into the floor or walls.

	  • ClampDash(root, dir, dist)  shortens a dash so it stops short of walls,
	                                stairs and props in the way.
	  • ClampToFloor(root, dir, dist) shortens it so it stops before a
	                                ledge or pit (never dashes off the floor).
	  • HasFloor(root)              is there floor under the character at all.
	  • StandHeight(root)           how high the root sits above the floor now.
	  • SnapToFloor(root, height)   after a move, lifts the root back onto the
	                                floor if it ended up below it.
	  • Init()                      a watchdog: if the character is stuck
	                                inside solid geometry, pop it out on top;
	                                and a per-frame floor guard (below).

	Floor guard: every frame, a ray from the head down past the feet finds
	the floor under the character. Whenever the character has sunk into it
	(a dash crossing a seam between floor tiles, a teleport landing on a
	step, a fast move clipping an edge) it's lifted straight back onto it.
	While moving fast, a missing floor (a seam) doesn't let it drop either.
	And if it ever falls out of the level entirely, it's put back where it
	last stood.
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local player = Players.LocalPlayer

local SafeMove = {}

local function params(char: Model?): RaycastParams
	local p = RaycastParams.new()
	p.FilterType = Enum.RaycastFilterType.Exclude
	local ignore: { Instance } = {}
	if char then table.insert(ignore, char) end
	for _, name in ipairs({ "Mobs", "Allies", "IceClones", "ClassFX", "BossFX", "RoomEmblems" }) do
		local f = Workspace:FindFirstChild(name)
		if f then table.insert(ignore, f) end
	end
	for _, plr in ipairs(Players:GetPlayers()) do
		if plr.Character then table.insert(ignore, plr.Character) end
	end
	p.FilterDescendantsInstances = ignore
	p.RespectCanCollide = true
	return p
end

-- How far a dash of `dist` along `dir` can go before hitting something solid
-- at body height (keeps a small gap).
function SafeMove.ClampDash(root: BasePart, dir: Vector3, dist: number): number
	local flat = Vector3.new(dir.X, 0, dir.Z)
	if flat.Magnitude < 0.01 then return dist end
	flat = flat.Unit
	local p = params(root.Parent :: Model)
	local best = dist
	-- Chest and knee height, so low steps and props stop the dash too.
	for _, h in ipairs({ 0.4, -1.4 }) do
		local hit = Workspace:Spherecast(root.Position + Vector3.new(0, h, 0), 1.1, flat * dist, p)
		if hit then best = math.min(best, math.max(0, hit.Distance - 1.2)) end
	end
	return best
end

-- How far along `dir` there is still floor to stand on (no dashing off a
-- ledge or into a pit). Samples the path every stud and a half; stops at the
-- last point that has floor no more than a small step below the current one.
function SafeMove.ClampToFloor(root: BasePart, dir: Vector3, dist: number): number
	local flat = Vector3.new(dir.X, 0, dir.Z)
	if flat.Magnitude < 0.01 or dist <= 0 then return dist end
	flat = flat.Unit
	local p = params(root.Parent :: Model)
	local here = Workspace:Raycast(root.Position + Vector3.new(0, 1, 0), Vector3.new(0, -30, 0), p)
	if not here then return 0 end
	local floorY = here.Position.Y
	local ok = 0
	local step = 1.5
	local d = step
	while d <= dist + 0.01 do
		local at = root.Position + flat * math.min(d, dist)
		local hit = Workspace:Raycast(at + Vector3.new(0, 3, 0), Vector3.new(0, -12, 0), p)
		if not hit or hit.Position.Y < floorY - 3 then break end
		ok = math.min(d, dist)
		d += step
	end
	-- (a little back from the edge, so the body doesn't hang over it)
	return if ok >= dist then dist else math.max(0, ok - 1)
end

-- Is there any floor under the character (within a fall's reach)?
function SafeMove.HasFloor(root: BasePart): boolean
	return Workspace:Raycast(root.Position + Vector3.new(0, 1, 0), Vector3.new(0, -30, 0), params(root.Parent :: Model)) ~= nil
end

local function groundY(root: BasePart, at: Vector3): number?
	local hit = Workspace:Raycast(at + Vector3.new(0, 6, 0), Vector3.new(0, -30, 0), params(root.Parent :: Model))
	return if hit then hit.Position.Y else nil
end

function SafeMove.StandHeight(root: BasePart): number
	local g = groundY(root, root.Position)
	return if g then math.clamp(root.Position.Y - g, 2, 5) else 3
end

function SafeMove.SnapToFloor(root: BasePart, height: number)
	local g = groundY(root, root.Position)
	if not g then return end
	local want = g + height
	if root.Position.Y < want - 0.5 then
		root.CFrame = root.CFrame + Vector3.new(0, want - root.Position.Y, 0)
		root.AssemblyLinearVelocity = Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z)
	end
end

-- ── Floor guard ──────────────────────────────────────────────────────────────
local FAST = 55 -- studs/s across the ground: only real dashes (sprinting / skating stay under it)
local TELEPORT = 6 -- studs moved in one frame
-- How far below standing height counts as sunk into the floor. Deeper than
-- any stair step (walking up stairs dips the root a little below the next
-- step; lifting that made you jitter upwards on stairs).
local SINK_FAST = 1.6 -- dashing
local SINK_SLOW = 2.2 -- otherwise
local SEAM_GRACE = 0.15 -- a dash only floats over a missing floor this soon after touching one
local FELL_OUT = 40 -- this far below where it last stood, with no floor under it

local guardParams: RaycastParams? = nil
local guardParamsAt = -math.huge
local lastPos: Vector3? = nil
local lastSafe: CFrame? = nil
-- After a teleport (new level, revive, portal) the new floor may not have
-- reached this client yet: held still where we arrived (anchored here, not
-- pushed up every frame, which jittered) until it has.
local LANDING_GRACE = 8
local landingUntil = 0
local heldRoot: BasePart? = nil
local lastGrounded = 0

local function release()
	if heldRoot and heldRoot.Parent then heldRoot.Anchored = false end
	heldRoot = nil
end

-- Root height above the floor when standing.
local function standOf(hum: Humanoid, root: BasePart): number
	if hum.RigType == Enum.HumanoidRigType.R6 then
		return 3 + hum.HipHeight
	end
	return hum.HipHeight + root.Size.Y * 0.5
end

local function floorGuard()
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local now = os.clock()
	if heldRoot and (heldRoot ~= root or now >= landingUntil) then release() end
	if not (char and root and hum) or (root.Anchored and heldRoot ~= root) or hum.Health <= 0 or hum.Sit then
		lastPos = nil
		return
	end
	if not guardParams or now - guardParamsAt > 1 then
		guardParams = params(char)
		guardParamsAt = now
	end

	local pos = root.Position
	local vel = root.AssemblyLinearVelocity
	local moved = if lastPos then (pos - lastPos).Magnitude else 0
	lastPos = pos
	local fast = Vector3.new(vel.X, 0, vel.Z).Magnitude > FAST or moved > TELEPORT
	-- Sent somewhere new (portal, respawn point, Blade Storm): where it last
	-- stood no longer means anything.
	if moved > TELEPORT * 4 then
		-- (the spot we were sent to is the fallback if we ever fall out)
		lastSafe = root.CFrame
		landingUntil = now + LANDING_GRACE
	end
	if now < landingUntil then
		local below = Workspace:Raycast(pos, Vector3.new(0, -40, 0), guardParams)
		if not below then
			if not heldRoot then
				root.AssemblyLinearVelocity = Vector3.zero
				root.Anchored = true
				heldRoot = root
			end
			lastPos = root.Position
			return
		end
		landingUntil = 0 -- the floor is here
		release()
	end
	local stand = standOf(hum, root)

	-- From the top of the head down past the feet.
	local hit = Workspace:Raycast(pos + Vector3.new(0, 3, 0), Vector3.new(0, -(3 + stand + 2.5), 0), guardParams)
	if hit and hit.Normal.Y > 0.5 then
		local want = hit.Position.Y + stand
		local sunk = want - pos.Y
		if sunk > -0.6 then lastGrounded = now end
		if sunk > (if fast then SINK_FAST else SINK_SLOW) then
			-- Into the floor: straight back up onto it.
			root.CFrame += Vector3.new(0, sunk, 0)
			root.AssemblyLinearVelocity = Vector3.new(vel.X, math.max(vel.Y, 0), vel.Z)
			lastPos = root.Position
		elseif not fast and sunk > -0.6 then
			lastSafe = root.CFrame -- standing on it
		end
	elseif fast and vel.Y < 0 and now - lastGrounded < SEAM_GRACE
		and hum:GetState() ~= Enum.HumanoidStateType.Jumping and hum:GetState() ~= Enum.HumanoidStateType.Freefall then
		-- Mid-dash over a seam between floor tiles: hold height rather than
		-- drop into it. (Only right after touching the floor, never mid-jump:
		-- that held you in the air for as long as you kept moving fast.)
		root.AssemblyLinearVelocity = Vector3.new(vel.X, 0, vel.Z)
	elseif lastSafe and pos.Y < lastSafe.Position.Y - FELL_OUT
		and not Workspace:Raycast(pos, Vector3.new(0, -500, 0), guardParams)
	then
		-- Fell out of the level (nothing at all below): back to where it
		-- last stood.
		root.CFrame = lastSafe + Vector3.new(0, 0.5, 0)
		root.AssemblyLinearVelocity = Vector3.zero
		lastPos = root.Position
	end
end

-- Watchdog: stuck inside solid parts for a moment → put back on top.
function SafeMove.Init()
	player.CharacterAdded:Connect(function()
		release()
		lastPos, lastSafe = nil, nil
		landingUntil = 0
	end)
	RunService.Heartbeat:Connect(floorGuard)

	local stuckTicks = 0
	local lastCheck: Vector3? = nil
	task.spawn(function()
		while true do
			task.wait(0.35)
			local char = player.Character
			local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
			local hum = char and char:FindFirstChildOfClass("Humanoid")
			if not root or not hum or hum.Health <= 0 or root.Anchored then
				stuckTicks = 0
				lastCheck = nil
				continue
			end
			-- Stuck means overlapping solid geometry AND not getting anywhere.
			-- (Climbing stairs overlaps the stair mesh while moving fine; popping
			-- the player up there made them jitter upwards.)
			local movedSince = if lastCheck then (root.Position - lastCheck).Magnitude else math.huge
			lastCheck = root.Position
			if movedSince > 0.6 or hum.MoveDirection.Magnitude < 0.1 then
				stuckTicks = 0
				continue
			end
			local op = OverlapParams.new()
			op.FilterType = Enum.RaycastFilterType.Exclude
			op.FilterDescendantsInstances = { char :: Instance }
			op.RespectCanCollide = true
			local inside = Workspace:GetPartBoundsInBox(root.CFrame, Vector3.new(1.2, 1.2, 0.6), op)
			-- Solid level geometry overlapping the torso (mobs don't count).
			local mobs = Workspace:FindFirstChild("Mobs")
			local solid = false
			for _, pt in ipairs(inside) do
				if pt.CanCollide and not pt:IsA("Terrain") and not (mobs and pt:IsDescendantOf(mobs)) then
					solid = true
					break
				end
			end
			stuckTicks = if solid then stuckTicks + 1 else 0
			if stuckTicks >= 2 then
				stuckTicks = 0
				-- Find the top surface above/around us and stand on it.
				local p = params(char)
				local hit = Workspace:Raycast(root.Position + Vector3.new(0, 18, 0), Vector3.new(0, -40, 0), p)
				if hit then
					root.CFrame = CFrame.new(root.Position.X, hit.Position.Y + 3.2, root.Position.Z) * root.CFrame.Rotation
					root.AssemblyLinearVelocity = Vector3.zero
				end
			end
		end
	end)
end

return SafeMove
