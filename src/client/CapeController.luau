--[[
	CapeController.luau
	Animates the Ice Mage's cape (server IceCape) on every character, locally.

	Each "CapeJoint" Motor6D is bent by a spring toward a target driven by the
	character's motion in torso space:
	  • forward speed   → the cape billows back (lower rows curl further)
	  • falling / jumps → the cape lifts
	  • sideways motion → it sways the other way
	  • always          → a travelling wind flutter, stronger at speed
--]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local CapeController = {}

type CapeState = {
	joints: { Motor6D },
	angles: { Vector3 },     -- current (x, z) bend per joint, in radians (y unused)
	velocities: { Vector3 },
}

local capes: { [Model]: CapeState } = {}

local function collectJoints(cape: Model): { Motor6D }
	local list = {}
	for _, d in ipairs(cape:GetDescendants()) do
		if d:IsA("Motor6D") and d.Name == "CapeJoint" and d.Part1 then
			table.insert(list, d)
		end
	end
	table.sort(list, function(a, b)
		return ((a.Part1 :: BasePart):GetAttribute("CapeRow") or 0) < ((b.Part1 :: BasePart):GetAttribute("CapeRow") or 0)
	end)
	return list
end

local STIFFNESS = 60
local DAMPING = 11

local function step(dt: number)
	dt = math.min(dt, 1 / 20)
	local t = os.clock()
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		local cape = char and char:FindFirstChild("IceCape")
		if not (char and cape and cape:IsA("Model")) then continue end
		local state = capes[char]
		if not state or #state.joints == 0 or not state.joints[1].Parent then
			local joints = collectJoints(cape)
			if #joints == 0 then continue end
			state = { joints = joints, angles = {}, velocities = {} }
			for i = 1, #joints do
				state.angles[i] = Vector3.zero
				state.velocities[i] = Vector3.zero
			end
			capes[char] = state
		end

		local torso = (char:FindFirstChild("Torso") or char:FindFirstChild("UpperTorso")) :: BasePart?
		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if not torso or not root then continue end
		local vel = root.AssemblyLinearVelocity
		local localVel = torso.CFrame:VectorToObjectSpace(vel)
		local forward = math.max(0, -localVel.Z) -- torso faces -Z
		local speedK = math.clamp(forward / 26, 0, 1)
		local fallK = math.clamp(-vel.Y / 40, 0, 1)
		local riseK = math.clamp(vel.Y / 40, 0, 1)
		local lateral = math.clamp(localVel.X / 20, -1, 1)

		local n = #state.joints
		for i, joint in ipairs(state.joints) do
			local k = (i - 1) / math.max(n - 1, 1) -- 0 at the collar, 1 at the hem
			-- Billow: negative X swings the cape out behind (+Z is the back).
			local billow = speedK * (0.35 + k * 0.5) + fallK * (0.45 + k * 0.4) - riseK * 0.15 * k
			local flutterAmp = 0.03 + 0.1 * speedK + 0.05 * fallK
			local flutter = math.sin(t * (7 + speedK * 6) - i * 0.9) * flutterAmp * (0.4 + k)
			local breeze = math.sin(t * 1.3 + i * 0.5) * 0.025
			local targetX = -(0.08 + billow + flutter + breeze) / math.max(n * 0.35, 1)
			local targetZ = -lateral * 0.12 * (0.4 + k) + math.sin(t * 2.1 + i) * 0.015 * (1 + speedK)

			local target = Vector3.new(targetX, 0, targetZ)
			local a = state.angles[i]
			local v = state.velocities[i]
			-- Damped spring toward the target bend: gives weight and follow-through.
			v += ((target - a) * STIFFNESS - v * DAMPING) * dt
			a += v * dt
			state.angles[i], state.velocities[i] = a, v
			joint.Transform = CFrame.Angles(a.X, 0, a.Z)
		end
	end
	for char in pairs(capes) do
		if not char.Parent then capes[char] = nil end
	end
end

function CapeController.Init()
	RunService.Stepped:Connect(function(_, dt)
		step(dt)
	end)
end

return CapeController
