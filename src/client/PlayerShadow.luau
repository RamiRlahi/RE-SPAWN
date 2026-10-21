--!strict
-- ─────────────────────────────────────────────────────────────────────────────
-- PlayerShadow.luau
-- A classic ARPG blob shadow under every player character (like Hades /
-- Diablo). A dark semi-transparent ellipse projected onto the floor beneath
-- the character, raycasting each frame to follow the terrain. It shrinks and
-- fades when airborne so jumps and slams feel weightier.
-- ─────────────────────────────────────────────────────────────────────────────

local Workspace  = game:GetService("Workspace")
local RunService = game:GetService("RunService")
local Players    = game:GetService("Players")

local PlayerShadow = {}

-- ── Tunables ─────────────────────────────────────────────────────────────────
local SHADOW_DIAMETER = 3.6   -- studs: diameter of the circular blob shadow
local SHADOW_HEIGHT   = 0.05  -- studs: paper-thin so it sits on the floor
local BASE_ALPHA      = 0.55  -- 0 = opaque, 1 = invisible (how dark the blob is)
local MAX_RAY_DIST    = 60    -- studs: how far down we look for a floor
local FADE_START      = 2.0   -- studs above floor: shadow at full intensity
local FADE_END        = 18.0  -- studs above floor: shadow fully faded out
local SHADOW_COLOR    = Color3.fromRGB(5, 5, 8)

-- ── State ────────────────────────────────────────────────────────────────────
type ShadowInfo = {
	part: Part,
	character: Model,
}

local shadows: { [Player]: ShadowInfo } = {}
local renderConn: RBXScriptConnection? = nil
local rayParams: RaycastParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
rayParams.IgnoreWater = true

-- ── Create the blob ──────────────────────────────────────────────────────────
local function createShadowPart(): Part
	local p = Instance.new("Part")
	p.Name          = "PlayerShadow"
	p.Shape         = Enum.PartType.Cylinder   -- a cylinder on its side = flat circular blob
	p.Size          = Vector3.new(SHADOW_HEIGHT, SHADOW_DIAMETER, SHADOW_DIAMETER)
	p.Color         = SHADOW_COLOR
	p.Material      = Enum.Material.SmoothPlastic
	p.Transparency  = BASE_ALPHA
	p.Anchored      = true
	p.CanCollide    = false
	p.CanTouch      = false
	p.CanQuery      = false
	p.CastShadow    = false
	p.Locked        = true
	-- Cylinder default axis is X; rotate so the flat face points up
	p.CFrame        = CFrame.new(0, -100, 0) * CFrame.Angles(0, 0, math.rad(90))
	p.Parent        = Workspace
	return p
end

-- ── Attach / detach ──────────────────────────────────────────────────────────
local function attachShadow(plr: Player, char: Model)
	-- Remove any stale one first
	local old = shadows[plr]
	if old and old.part and old.part.Parent then old.part:Destroy() end

	local shadowPart = createShadowPart()
	shadows[plr] = { part = shadowPart, character = char }
end

local function detachShadow(plr: Player)
	local info = shadows[plr]
	if info then
		if info.part and info.part.Parent then info.part:Destroy() end
		shadows[plr] = nil
	end
end

-- ── Per-frame update ─────────────────────────────────────────────────────────
local function updateShadows()
	for plr, info in pairs(shadows) do
		local char = info.character
		local part = info.part
		if not char or not char.Parent or not part or not part.Parent then
			detachShadow(plr)
			continue
		end

		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not root then continue end

		-- Build a filter list: the character itself, plus the shadow part
		rayParams.FilterDescendantsInstances = { char, part }

		local origin = root.Position
		local result = Workspace:Raycast(origin, Vector3.new(0, -MAX_RAY_DIST, 0), rayParams)

		if result then
			local floorPos = result.Position
			local floorNormal = result.Normal
			local heightAbove = (origin.Y - floorPos.Y)

			-- Fade + shrink based on height
			local t = math.clamp((heightAbove - FADE_START) / (FADE_END - FADE_START), 0, 1)
			local scale = 1 - t * 0.5  -- shrinks to 50% at max height
			local alpha = BASE_ALPHA + t * (1 - BASE_ALPHA)  -- fades toward invisible

			part.Size = Vector3.new(SHADOW_HEIGHT, SHADOW_DIAMETER * scale, SHADOW_DIAMETER * scale)
			part.Transparency = alpha

			-- Place the ellipse just above the floor, aligned to the surface
			-- The cylinder's long axis is X, so after a 90° Z rotation it
			-- points up.  We build a CFrame whose Y = floorNormal and position
			-- it slightly above the hit.
			local up = floorNormal
			-- Pick a right vector that isn't parallel to the normal
			local ref = if math.abs(up:Dot(Vector3.new(1, 0, 0))) < 0.99
				then Vector3.new(1, 0, 0)
				else Vector3.new(0, 0, 1)
			local forward = up:Cross(ref).Unit
			local right = forward:Cross(up).Unit

			part.CFrame = CFrame.fromMatrix(
				floorPos + up * 0.04,   -- tiny lift to avoid z-fight
				right,                  -- X axis
				up,                     -- Y axis (the normal)
				-forward                -- Z axis
			) * CFrame.Angles(0, 0, math.rad(90))  -- rotate cylinder flat
		else
			-- No floor found: hide it
			part.Transparency = 1
		end
	end
end

-- ── Setup helpers ────────────────────────────────────────────────────────────
local function setupPlayer(plr: Player)
	if plr.Character then
		attachShadow(plr, plr.Character)
	end
	plr.CharacterAdded:Connect(function(char)
		-- wait a frame so the root is ready
		task.defer(function()
			attachShadow(plr, char)
		end)
	end)
	plr.CharacterRemoving:Connect(function()
		detachShadow(plr)
	end)
end

-- ── Public API ───────────────────────────────────────────────────────────────
function PlayerShadow.Init()
	-- Hook existing players
	for _, plr in ipairs(Players:GetPlayers()) do
		setupPlayer(plr)
	end
	Players.PlayerAdded:Connect(setupPlayer)
	Players.PlayerRemoving:Connect(detachShadow)

	-- Start the render loop
	if renderConn then renderConn:Disconnect() end
	renderConn = RunService.RenderStepped:Connect(updateShadows)

	print("[PlayerShadow] Blob shadows active.")
end

function PlayerShadow.Stop()
	if renderConn then
		renderConn:Disconnect()
		renderConn = nil
	end
	for plr in pairs(shadows) do
		detachShadow(plr)
	end
end

return PlayerShadow
