--!strict
--[[
	PerfMode.luau
	The automatic performance mode. If the frame rate stays low (under ~35 fps
	for a few seconds), this client switches to performance mode for the rest
	of the session (the player attribute "PerfMode"):

	  • world shadows off (UIManager's applyGraphics reads PerfMode)
	  • every class's skill effects at the Low Detail level (VfxDetail)
	  • the dungeon's scenery effects stopped: brazier fires, embers, window
	    dust and light shafts (the props themselves stay)

	The Low Detail VFX setting also stops the scenery effects, so a player
	can ask for all of this up front.
--]]

local Players = game:GetService("Players")
local Lighting = game:GetService("Lighting")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local FxBudget = require(script.Parent:WaitForChild("FxBudget"))

local PerfMode = {}

local player = Players.LocalPlayer

local LOW_PRESSURE = 0.55 -- FxBudget.Pressure() above this is "struggling" (~35 fps)
local LOW_FOR = 4         -- seconds struggling before switching

local function wanted(): boolean
	return player:GetAttribute("PerfMode") == true or player:GetAttribute("Setting_lowDetailVFX") == true
end

-- Scenery effects: everything that glows, burns or drifts in a dungeon.
local function isScenery(inst: Instance): boolean
	return inst:IsA("ParticleEmitter") or inst:IsA("Fire") or inst:IsA("Beam") or inst:IsA("Smoke") or inst:IsA("Sparkles")
end

local function setScenery(inst: Instance, on: boolean)
	if not isScenery(inst) then return end
	-- (remember what the generator wanted, to put it back)
	if inst:GetAttribute("SceneryOn") == nil then inst:SetAttribute("SceneryOn", (inst :: any).Enabled) end
	local want = on and inst:GetAttribute("SceneryOn") == true
	if (inst :: any).Enabled ~= want then (inst :: any).Enabled = want end
end

local function dungeons(): { Instance }
	local out = {}
	for _, c in ipairs(Workspace:GetChildren()) do
		if c.Name == "GeneratedDungeon" then table.insert(out, c) end
	end
	return out
end

local applied = false
local function apply()
	local low = wanted()
	if low == applied then return end
	applied = low
	if low then Lighting.GlobalShadows = false end
	for _, d in ipairs(dungeons()) do
		for _, inst in ipairs(d:GetDescendants()) do setScenery(inst, not low) end
	end
end

function PerfMode.Init()
	-- New dungeons (and rooms streaming in) follow the current mode.
	Workspace.ChildAdded:Connect(function(c)
		if c.Name ~= "GeneratedDungeon" then return end
		c.DescendantAdded:Connect(function(inst)
			if applied and isScenery(inst) then task.defer(setScenery, inst, false) end
		end)
		if applied then
			task.defer(function()
				for _, inst in ipairs(c:GetDescendants()) do setScenery(inst, false) end
			end)
		end
	end)
	for _, c in ipairs(dungeons()) do
		c.DescendantAdded:Connect(function(inst)
			if applied and isScenery(inst) then task.defer(setScenery, inst, false) end
		end)
	end
	player:GetAttributeChangedSignal("PerfMode"):Connect(apply)
	player:GetAttributeChangedSignal("Setting_lowDetailVFX"):Connect(apply)
	apply()

	-- Watch the frame rate; once it has struggled for LOW_FOR seconds, switch.
	local struggling = 0
	local started = os.clock()
	local conn: RBXScriptConnection? = nil
	conn = RunService.Heartbeat:Connect(function(dt)
		-- (only while playing: not loading in, nor on the menu screens)
		local playing = player:GetAttribute("InLobby") == false or player:GetAttribute("InHub") == true
		if not playing or os.clock() - started < 20 then
			struggling = 0
		elseif FxBudget.Pressure() > LOW_PRESSURE then
			struggling += dt
			if struggling >= LOW_FOR then
				player:SetAttribute("PerfMode", true)
				if conn then conn:Disconnect() end
			end
		else
			struggling = math.max(0, struggling - dt * 2)
		end
	end)
end

return PerfMode
