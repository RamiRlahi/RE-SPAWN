--!strict
--[[
	VfxDetail.luau
	Lighter skill effects for a calmer screen: on with the Classic Camera
	(third-person, where effects sit right in your face) or Low Detail VFX.

	Every skill effect spawned in the world (the class effect folders, the
	effects parented straight to the Workspace / Terrain) is toned down as it
	appears: its parts drawn fainter, particles fewer, fainter and smaller,
	beams and trails fainter, lights dimmer. Enemy attacks (MobFX, BossFX, the
	dragon, enemy projectiles) are left alone: they must stay readable. So are
	characters, mobs and the dungeon itself.
--]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local VfxDetail = {}

local player = Players.LocalPlayer

local PART_FADE = 0.45       -- parts: this much more see-through
local PARTICLE_RATE = 0.4    -- emitters: this share of their rate
local PARTICLE_FADE = 0.45   -- and fainter by this much
local PARTICLE_SIZE = 0.8
local BEAM_FADE = 0.45
local LIGHT_DIM = 0.5

-- (where effects are never touched)
local KEEP = {
	Mobs = true, MobFX = true, BossFX = true, DragonFX = true, DragonClientFX = true,
	GeneratedDungeon = true, MenuBackdrop = true, LocalSettingsPanel = true, Allies = true,
	RoomEmblems = true, SpawnPoint = true,
}

local function enabled(): boolean
	return player:GetAttribute("Setting_classicCamera") == true or player:GetAttribute("Setting_lowDetailVFX") == true
end

local function isEffect(inst: Instance): boolean
	-- the Workspace child it lives under
	local top = inst
	while top.Parent and top.Parent ~= Workspace do
		top = top.Parent
		if top == game then return false end
	end
	if top.Parent ~= Workspace then return false end
	if KEEP[top.Name] then return false end
	if top:IsA("Model") and top:FindFirstChildOfClass("Humanoid") then return false end -- characters
	if top:IsA("Camera") then return false end
	for _, tag in ipairs({ "EnemyProjectile" }) do
		local p = inst:FindFirstAncestorWhichIsA("BasePart")
		if inst:HasTag(tag) or (p and p:HasTag(tag)) then return false end
	end
	return true
end

local function fadeSeq(seq: NumberSequence, k: number): NumberSequence
	local pts = {}
	for _, kp in ipairs(seq.Keypoints) do
		table.insert(pts, NumberSequenceKeypoint.new(kp.Time, 1 - (1 - kp.Value) * (1 - k), kp.Envelope))
	end
	return NumberSequence.new(pts)
end

local function scaleSeq(seq: NumberSequence, k: number): NumberSequence
	local pts = {}
	for _, kp in ipairs(seq.Keypoints) do
		table.insert(pts, NumberSequenceKeypoint.new(kp.Time, kp.Value * k, kp.Envelope * k))
	end
	return NumberSequence.new(pts)
end

local function tone(inst: Instance)
	if inst:GetAttribute("VfxToned") then return end
	if inst:IsA("BasePart") then
		-- (tween-proof: the client-side fade multiplies whatever it's set to)
		if inst.Transparency < 1 then
			inst.LocalTransparencyModifier = math.max(inst.LocalTransparencyModifier, PART_FADE)
		end
	elseif inst:IsA("ParticleEmitter") then
		inst.Rate *= PARTICLE_RATE
		inst.Transparency = fadeSeq(inst.Transparency, PARTICLE_FADE)
		inst.Size = scaleSeq(inst.Size, PARTICLE_SIZE)
	elseif inst:IsA("Beam") or inst:IsA("Trail") then
		inst.Transparency = fadeSeq(inst.Transparency, BEAM_FADE)
	elseif inst:IsA("Light") then
		inst.Brightness *= LIGHT_DIM
	else
		return
	end
	inst:SetAttribute("VfxToned", true)
end

function VfxDetail.Init()
	Workspace.DescendantAdded:Connect(function(inst)
		if not enabled() then return end
		if not (inst:IsA("BasePart") or inst:IsA("ParticleEmitter") or inst:IsA("Beam") or inst:IsA("Trail") or inst:IsA("Light")) then return end
		-- (after the spawning code finishes setting it up)
		task.defer(function()
			if inst.Parent and isEffect(inst) then pcall(tone, inst) end
		end)
	end)
end

return VfxDetail
