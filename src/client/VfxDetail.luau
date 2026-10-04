--!strict
--[[
	VfxDetail.luau
	A calmer screen: every class's skill effects are toned down as they
	appear, always, so the fight underneath stays readable.

	  • parts drawn fainter, and the giant flash spheres (big neon blasts)
	    much fainter
	  • particles fewer, fainter and smaller; dark smoke (which hides the mobs
	    you're fighting) faded hard
	  • beams and trails fainter, lights dimmer, and only so many effect
	    lights alive at once (FxBudget): past that they're switched off
	  • the effects worn on characters (auras, swing trails): their particles
	    and trails only, never bodies, armour or capes

	Heavier still with the Classic Camera (effects sit right in your face) or
	Low Detail VFX. Enemy attacks (mobs, bosses, the dragon, enemy
	projectiles) are never touched: they must stay readable. Nor are mobs,
	the dungeon or the menus.
--]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local FxBudget = require(script.Parent:WaitForChild("FxBudget"))

local VfxDetail = {}

local player = Players.LocalPlayer

type Level = { part: number, flash: number, rate: number, pfade: number, psize: number, smoke: number, beam: number, light: number }
local NORMAL: Level = { part = 0.3, flash = 0.6, rate = 0.55, pfade = 0.35, psize = 0.85, smoke = 0.75, beam = 0.35, light = 0.6 }
local LOW: Level = { part = 0.5, flash = 0.75, rate = 0.3, pfade = 0.55, psize = 0.75, smoke = 0.88, beam = 0.55, light = 0.4 }
local FLASH_SIZE = 8 -- a neon part bigger than this across is a blast flash

-- (where effects are never touched)
local KEEP = {
	Mobs = true, MobFX = true, BossFX = true, DragonFX = true, DragonClientFX = true,
	GeneratedDungeon = true, MenuBackdrop = true, HubSky = true, Lobby = true, LocalSettingsPanel = true, Allies = true,
	RoomEmblems = true, SpawnPoint = true, dust = true,
	SkeletonAimLine = true, DeathPortal = true, -- (enemy warnings, the give-up portal)
}

local function level(): Level
	local heavy = player:GetAttribute("Setting_classicCamera") == true or player:GetAttribute("Setting_lowDetailVFX") == true
		or player:GetAttribute("PerfMode") == true
	return if heavy then LOW else NORMAL
end

-- "effect" (a skill effect in the world), "worn" (an effect on a character:
-- its particles and trails only) or nil (leave it).
local function kindOf(inst: Instance): string?
	local top = inst
	while top.Parent and top.Parent ~= Workspace do
		top = top.Parent
		if top == game then return nil end
	end
	if top.Parent ~= Workspace then return nil end
	if KEEP[top.Name] then return nil end
	if top:IsA("Camera") then return nil end
	local p = inst:FindFirstAncestorWhichIsA("BasePart")
	if inst:HasTag("EnemyProjectile") or (p and p:HasTag("EnemyProjectile")) then return nil end
	if top:IsA("Model") and top:FindFirstChildOfClass("Humanoid") then
		-- a character: only what it gives off (and not its torch's glow, nor
		-- the Armory gear it wears: that's for showing off)
		if not Players:GetPlayerFromCharacter(top) then return nil end
		local holder = inst.Parent
		if inst.Name == "GearSparkle" or inst.Name == "GearFx" or (holder and string.sub(holder.Name, 1, 8) == "GearAura") then return nil end
		if inst:IsA("ParticleEmitter") or inst:IsA("Beam") or inst:IsA("Trail") then return "worn" end
		return nil
	end
	-- Only what's plainly an effect: a loose part dropped in the world, or an
	-- effects folder / model (ClassFX, SwordFX, ...VFX, ...Effect). (Never the
	-- scenery streaming in: the church, the islands, the waterfalls.)
	if top:IsA("BasePart") then return "effect" end
	local name = string.lower(top.Name)
	if string.find(name, "fx", 1, true) or string.find(name, "effect", 1, true) then return "effect" end
	return nil
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

-- Smoke: a dark emitter (its colours' average brightness low).
local function isSmoke(e: ParticleEmitter): boolean
	local sum, n = 0, 0
	for _, kp in ipairs(e.Color.Keypoints) do
		local c = kp.Value
		sum += (c.R + c.G + c.B) / 3
		n += 1
	end
	return n > 0 and sum / n < 0.25 and e.LightEmission < 0.5
end

local function tone(inst: Instance, L: Level)
	if inst:GetAttribute("VfxToned") then return end
	if inst:IsA("BasePart") then
		-- (tween-proof: the client-side fade multiplies whatever it's set to)
		if inst.Transparency < 1 then
			local big = math.max(inst.Size.X, inst.Size.Y, inst.Size.Z)
			local k = if inst.Material == Enum.Material.Neon and big > FLASH_SIZE then L.flash else L.part
			inst.LocalTransparencyModifier = math.max(inst.LocalTransparencyModifier, k)
		end
	elseif inst:IsA("ParticleEmitter") then
		local smoke = isSmoke(inst)
		inst.Rate *= if smoke then L.rate * 0.6 else L.rate
		inst.Transparency = fadeSeq(inst.Transparency, if smoke then L.smoke else L.pfade)
		inst.Size = scaleSeq(inst.Size, if smoke then L.psize * 0.85 else L.psize)
	elseif inst:IsA("Beam") or inst:IsA("Trail") then
		inst.Transparency = fadeSeq(inst.Transparency, L.beam)
	elseif inst:IsA("Light") then
		inst.Brightness *= L.light
		-- (only so many effect lights at once, from any class: past that, off)
		FxBudget.TrackLight(inst)
	else
		return
	end
	inst:SetAttribute("VfxToned", true)
end

function VfxDetail.Init()
	Workspace.DescendantAdded:Connect(function(inst)
		if not (inst:IsA("BasePart") or inst:IsA("ParticleEmitter") or inst:IsA("Beam") or inst:IsA("Trail") or inst:IsA("Light")) then return end
		-- (after the spawning code finishes setting it up)
		task.defer(function()
			if not inst.Parent then return end
			local kind = kindOf(inst)
			if kind then pcall(tone, inst, level()) end
		end)
	end)
end

return VfxDetail
