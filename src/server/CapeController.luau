--[[
	CapeController (Server-Side Module)

	Creates a multi-segment physics cape attached to the character''s back.
	Each segment is connected by BallSocketConstraints � Roblox physics handles
	the natural draping and swing. A VectorForce updated per Heartbeat makes the
	cape trail behind the character as they move, giving a wind/flow effect.
--]]

local RunService = game:GetService("RunService")

local CapeController = {}

-- Visual Settings
local SEGMENT_COUNT     = 6
local SEGMENT_WIDTH     = 1.65
local SEGMENT_HEIGHT    = 0.45
local SEGMENT_THICKNESS = 0.055

local SEGMENT_COLORS = {
	Color3.fromRGB(55, 10,  10),
	Color3.fromRGB(65, 12,  12),
	Color3.fromRGB(75, 14,  14),
	Color3.fromRGB(85, 15,  15),
	Color3.fromRGB(75, 12,  12),
	Color3.fromRGB(60,  8,   8),
}

-- Physics Settings
local WIND_STRENGTH     = 16
local SWING_LIMIT       = 40
local TWIST_LIMIT       = 18

local ANCHOR_OFFSET = CFrame.new(0, 0.6, 0.92)

-- Builds one cape segment, returning the part, its bottom attachment, and the VectorForce
local function makeSegment(i: number, prevBottomAtt: Attachment): (Part, Attachment, VectorForce)
	local t = (i - 1) / math.max(SEGMENT_COUNT - 1, 1)

	local seg = Instance.new("Part")
	seg.Name          = "CapeSeg_" .. i
	seg.Anchored      = false
	seg.CanCollide    = false
	seg.CanTouch      = false
	seg.CanQuery      = false
	seg.CastShadow    = true
	seg.Massless      = true   -- IMPORTANT: prevents VectorForce from pushing the character
	seg.Material      = Enum.Material.SmoothPlastic
	seg.Color         = SEGMENT_COLORS[i] or SEGMENT_COLORS[#SEGMENT_COLORS]
	seg.Size          = Vector3.new(
		SEGMENT_WIDTH * (1 - t * 0.28),
		SEGMENT_HEIGHT,
		SEGMENT_THICKNESS
	)
	-- Massless parts use their parent assembly's physics; no custom density needed

	-- Place so top edge aligns with previous bottom attachment world position
	local topWorldPos = prevBottomAtt.WorldPosition
	seg.CFrame = CFrame.new(topWorldPos) * CFrame.new(0, -SEGMENT_HEIGHT / 2, 0)

	-- Top attachment
	local topAtt = Instance.new("Attachment")
	topAtt.Name     = "TopAtt"
	topAtt.Position = Vector3.new(0, SEGMENT_HEIGHT / 2, 0)
	topAtt.Parent   = seg

	-- BallSocketConstraint: previous bottom -> this top
	local bsc = Instance.new("BallSocketConstraint")
	bsc.Attachment0        = prevBottomAtt
	bsc.Attachment1        = topAtt
	bsc.LimitsEnabled      = true
	bsc.UpperAngle         = SWING_LIMIT
	bsc.TwistLimitsEnabled = true
	bsc.TwistUpperAngle    = TWIST_LIMIT
	bsc.TwistLowerAngle    = -TWIST_LIMIT
	bsc.Parent             = seg

	-- Bottom attachment (for next segment)
	local botAtt = Instance.new("Attachment")
	botAtt.Name     = "BotAtt"
	botAtt.Position = Vector3.new(0, -SEGMENT_HEIGHT / 2, 0)
	botAtt.Parent   = seg

	-- Wind force
	local windAtt = Instance.new("Attachment")
	windAtt.Parent = seg

	local vf = Instance.new("VectorForce")
	vf.Attachment0         = windAtt
	vf.ApplyAtCenterOfMass = true
	vf.RelativeTo          = Enum.ActuatorRelativeTo.World
	vf.Force               = Vector3.zero
	vf.Parent              = seg

	return seg, botAtt, vf
end

function CapeController.AttachCape(character: Model)
	local torso = character:FindFirstChild("Torso") :: BasePart?
	if not torso then return end

	-- Remove existing cape
	for _, child in ipairs(character:GetChildren()) do
		if child.Name == "CapeModel" then child:Destroy() end
	end
	local oldAnchor = torso:FindFirstChild("CapeAnchor")
	if oldAnchor then oldAnchor:Destroy() end

	local capeModel = Instance.new("Model")
	capeModel.Name = "CapeModel"

	-- Torso anchor attachment
	local anchorAtt = Instance.new("Attachment")
	anchorAtt.Name   = "CapeAnchor"
	anchorAtt.CFrame = ANCHOR_OFFSET
	anchorAtt.Parent = torso

	local prevBottomAtt: Attachment = anchorAtt
	local windForces: { { vf: VectorForce, index: number } } = {}

	for i = 1, SEGMENT_COUNT do
		local seg, botAtt, vf = makeSegment(i, prevBottomAtt)
		seg.Parent    = capeModel
		prevBottomAtt = botAtt
		table.insert(windForces, { vf = vf, index = i })
	end

	capeModel.Parent = character

	-- Wind update loop: trail force always points behind the character
	local conn: RBXScriptConnection
	conn = RunService.Heartbeat:Connect(function()
		if not character.Parent or not torso.Parent then
			conn:Disconnect()
			return
		end

		local backDir = -torso.CFrame.LookVector

		for _, data in ipairs(windForces) do
			if data.vf.Parent then
				local weight = (data.index / SEGMENT_COUNT) ^ 1.5
				data.vf.Force = backDir * WIND_STRENGTH * weight
			end
		end
	end)

	-- Auto-cleanup on character removal
	character.AncestryChanged:Connect(function()
		if not character.Parent then
			conn:Disconnect()
		end
	end)
end

function CapeController.RemoveCape(character: Model)
	for _, child in ipairs(character:GetChildren()) do
		if child.Name == "CapeModel" then child:Destroy() end
	end
	local torso = character:FindFirstChild("Torso")
	if torso then
		local anchor = torso:FindFirstChild("CapeAnchor")
		if anchor then anchor:Destroy() end
	end
end

return CapeController
