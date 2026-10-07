--!strict
--[[
	DeathManager.luau
	What happens when a player dies in the dungeon.

	  • No automatic respawn (Players.RespawnTime is pushed out of reach); the
	    client's death screen asks what to do.
	  • Two choices only: REVIVE (once per run: back on your feet where you
	    fell, run intact) or GIVE UP.
	  • Giving up: a red portal opens under the body and clawed hands drag the
	    scattered limbs into it. Then, if anyone is still fighting, you
	    SPECTATE them (and can LEAVE to the menu whenever you like); if no one
	    is, you go straight to the menu.
	  • Fallen players who haven't given up still rise when a living teammate
	    climbs to a higher floor than the party was on.

	Remotes: DeathState (server → dead client), DeathAction (client → server).
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local Debris = game:GetService("Debris")

local Network = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Network"))
local ClassManager = require(script.Parent:WaitForChild("ClassManager"))
local WeaponManager = require(script.Parent:WaitForChild("WeaponManager"))
local RunStats = require(script.Parent:WaitForChild("RunStats"))

local DeathManager = {}

-- Floors are 13 studs apart, the first one's players stand at about Y = 7
-- (see DungeonGenerator's FLOOR_Y_OFFSET / STAIR_HEIGHT).
local FLOOR_STEP = 13
local FLOOR_BASE_Y = 7
local function tierOf(pos: Vector3): number
	return math.max(0, math.floor((pos.Y - FLOOR_BASE_Y) / FLOOR_STEP + 0.5))
end

local reviveTier: { [Player]: number } = {}
-- Each player can REVIVE themselves once per run ("RevivesLeft", set when a
-- run starts for them).
local REVIVES_PER_RUN = 1
local deathPos: { [Player]: Vector3 } = {}
local scatter: (Model) -> ()

local function inDungeon(p: Player): boolean
	return p.Parent ~= nil and p:GetAttribute("InLobby") == false
end

-- Everyone fighting in `p`'s run (its own dungeon: RunManager).
local function runMates(p: Player): { Player }
	local out = {}
	local runId = p:GetAttribute("RunId")
	for _, m in ipairs(Players:GetPlayers()) do
		if m == p or (inDungeon(m) and runId ~= nil and m:GetAttribute("RunId") == runId) then table.insert(out, m) end
	end
	return out
end

local function isAlive(p: Player): boolean
	if p:GetAttribute("IsDead") == true then return false end
	local hum = p.Character and p.Character:FindFirstChildOfClass("Humanoid")
	return hum ~= nil and hum.Health > 0
end

-- Tell every dead party member what they can do now.
local function refresh(player: Player)
	local party = runMates(player)
	local alive = {}
	for _, m in ipairs(party) do
		if inDungeon(m) and isAlive(m) then table.insert(alive, m.UserId) end
	end
	for _, m in ipairs(party) do
		if m:GetAttribute("IsDead") == true then
			if m:GetAttribute("Spectating") == true then
				-- Gave up: watching whoever's left (LEAVE whenever).
				Network.GetRemoteEvent(Network.Remotes.DeathState):FireClient(m, { mode = "spectate", alive = alive })
			elseif m:GetAttribute("GivingUp") ~= true then
				Network.GetRemoteEvent(Network.Remotes.DeathState):FireClient(m, {
					mode = "dead", alive = alive, revives = m:GetAttribute("RevivesLeft") or 0,
				})
			end
		end
	end
end

local function onDied(player: Player)
	if not inDungeon(player) or player:GetAttribute("IsDead") == true then return end
	player:SetAttribute("IsDead", true)
	-- Revived once a teammate climbs past the highest floor the party is on now.
	local top = 0
	for _, m in ipairs(runMates(player)) do
		local root = m.Character and m.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root and inDungeon(m) then top = math.max(top, tierOf(root.Position)) end
	end
	reviveTier[player] = top
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root then deathPos[player] = root.Position end
	if char then scatter(char) end
	refresh(player)
end

local function hook(player: Player, character: Model)
	local hum = character:WaitForChild("Humanoid", 10) :: Humanoid?
	if hum then
		hum.Died:Connect(function() onDied(player) end)
	end
end

local function revive(player: Player, toMenu: boolean?)
	player:SetAttribute("IsDead", nil)
	player:SetAttribute("GivingUp", nil)
	player:SetAttribute("Spectating", nil)
	reviveTier[player] = nil
	Network.GetRemoteEvent(Network.Remotes.DeathState):FireClient(player, { mode = "clear", toMenu = toMenu == true })
end

-- ── Giving up: a hellish portal opens under the body and hands drag the
-- scattered limbs down into it. Server-side, so everyone sees it. Yields
-- until it's over (about 3.5 s).
local LIMB_NAMES = {
	"Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg",
	"UpperTorso", "LowerTorso", "LeftUpperArm", "RightUpperArm", "LeftUpperLeg", "RightUpperLeg",
}
local PORTAL_RED = Color3.fromRGB(255, 40, 20)
local PORTAL_HOT = Color3.fromRGB(255, 170, 60)
local HAND_DARK = Color3.fromRGB(38, 18, 20)

local function fxPart(parent: Instance, props: { [string]: any }): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	for k, v in pairs(props) do (p :: any)[k] = v end
	p.Parent = parent
	return p
end

-- A clawed hand (forearm, palm, four fingers) as one model, pivot at the palm.
local function makeHand(parent: Instance): Model
	local hand = Instance.new("Model")
	hand.Name = "PortalHand"
	local palm = fxPart(hand, { Name = "Palm", Size = Vector3.new(1.2, 0.5, 1.1), Color = HAND_DARK, Material = Enum.Material.SmoothPlastic })
	fxPart(hand, { Size = Vector3.new(0.7, 4, 0.7), CFrame = palm.CFrame * CFrame.new(0, -2.2, 0), Color = HAND_DARK, Material = Enum.Material.SmoothPlastic })
	for i = 1, 4 do
		local x = -0.45 + (i - 1) * 0.3
		fxPart(hand, { Size = Vector3.new(0.2, 0.75, 0.2), CFrame = palm.CFrame * CFrame.new(x, 0.55, 0.25) * CFrame.Angles(math.rad(25), 0, 0),
			Color = HAND_DARK, Material = Enum.Material.SmoothPlastic })
	end
	-- A red rim so the hands read against the glow.
	local hl = Instance.new("Highlight")
	hl.FillTransparency = 1
	hl.OutlineColor = PORTAL_RED
	hl.Parent = hand
	hand.PrimaryPart = palm
	hand.Parent = parent
	return hand
end

local function tweenPivot(model: Model, to: CFrame, t: number, style: Enum.EasingStyle?)
	local v = Instance.new("CFrameValue")
	v.Value = model:GetPivot()
	v.Changed:Connect(function(cf) if model.Parent then model:PivotTo(cf) end end)
	TweenService:Create(v, TweenInfo.new(t, style or Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { Value = to }):Play()
	task.delay(t + 0.05, function() v:Destroy() end)
end

local function portalTakes(character: Model)
	local limbs: { BasePart } = {}
	for _, name in ipairs(LIMB_NAMES) do
		local p = character:FindFirstChild(name)
		if p and p:IsA("BasePart") then table.insert(limbs, p) end
	end
	if #limbs == 0 then return end
	local center = Vector3.zero
	for _, l in ipairs(limbs) do center += l.Position end
	center /= #limbs
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { character }
	local hit = Workspace:Raycast(center + Vector3.new(0, 4, 0), Vector3.new(0, -30, 0), params)
	local floorY = if hit then hit.Position.Y else center.Y - 1
	local base = Vector3.new(center.X, floorY + 0.06, center.Z)

	local folder = Instance.new("Folder")
	folder.Name = "DeathPortal"
	folder.Parent = Workspace
	Debris:AddItem(folder, 6)

	-- The portal: a glowing red disc with a hot core, smoke and embers.
	local flat = CFrame.Angles(0, 0, math.rad(90))
	local rim = fxPart(folder, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.1, 0.5, 0.5), CFrame = CFrame.new(base) * flat,
		Color = PORTAL_RED, Material = Enum.Material.Neon, Transparency = 0.1 })
	local core = fxPart(folder, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.12, 0.3, 0.3), CFrame = CFrame.new(base + Vector3.new(0, 0.02, 0)) * flat,
		Color = PORTAL_HOT, Material = Enum.Material.Neon, Transparency = 0.15 })
	local pit = fxPart(folder, { Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.14, 0.2, 0.2), CFrame = CFrame.new(base + Vector3.new(0, 0.04, 0)) * flat,
		Color = Color3.fromRGB(20, 4, 4), Material = Enum.Material.SmoothPlastic })
	local R = 7.5
	local open = TweenInfo.new(0.5, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
	TweenService:Create(rim, open, { Size = Vector3.new(0.1, R * 2, R * 2) }):Play()
	TweenService:Create(core, open, { Size = Vector3.new(0.12, R * 1.5, R * 1.5) }):Play()
	TweenService:Create(pit, open, { Size = Vector3.new(0.14, R * 0.8, R * 0.8) }):Play()
	local light = Instance.new("PointLight")
	light.Color, light.Range, light.Brightness = PORTAL_RED, 24, 4
	light.Parent = core
	local att = Instance.new("Attachment")
	att.Parent = core
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(150, 20, 20), Color3.fromRGB(40, 5, 5))
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 3), NumberSequenceKeypoint.new(1, 8) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.5), NumberSequenceKeypoint.new(1, 1) })
	smoke.Lifetime = NumberRange.new(1.5, 2.5)
	smoke.Speed = NumberRange.new(2, 5)
	smoke.SpreadAngle = Vector2.new(180, 180)
	smoke.Rate = 25
	smoke.Parent = att
	local embers = Instance.new("ParticleEmitter")
	embers.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	embers.Color = ColorSequence.new(PORTAL_HOT, PORTAL_RED)
	embers.LightEmission = 1
	embers.Size = NumberSequence.new(0.3)
	embers.Lifetime = NumberRange.new(1, 2)
	embers.Speed = NumberRange.new(4, 9)
	embers.SpreadAngle = Vector2.new(40, 40)
	embers.Acceleration = Vector3.new(0, 4, 0)
	embers.Rate = 40
	embers.Parent = att
	-- Slow swirl.
	local swirl = RunService.Heartbeat:Connect(function(dt)
		if core.Parent then core.CFrame = core.CFrame * CFrame.Angles(dt * 2, 0, 0) end
	end)
	task.wait(0.55)

	-- A hand for each limb: it bursts up under the limb, grabs it, and drags it
	-- into the portal.
	for i, limb in ipairs(limbs) do
		task.delay((i - 1) * 0.14, function()
			if not limb.Parent then return end
			limb.Anchored = true
			for _, j in ipairs(limb:GetJoints()) do
				if j:IsA("JointInstance") or j:IsA("WeldConstraint") then
					local other = if (j :: any).Part0 == limb then (j :: any).Part1 else (j :: any).Part0
					-- Keep armor / accessories welded on; drop joints to other limbs.
					if other and table.find(limbs, other) then j:Destroy() end
				end
			end
			local hand = makeHand(folder)
			local lp = limb.Position
			local under = Vector3.new(lp.X, floorY - 4, lp.Z)
			hand:PivotTo(CFrame.new(under))
			tweenPivot(hand, CFrame.new(lp - Vector3.new(0, 0.3, 0)), 0.35, Enum.EasingStyle.Back)
			task.wait(0.4)
			-- Drag to the portal's mouth, then down and in.
			local mouth = base + Vector3.new(math.random(-15, 15) / 10, 0.6, math.random(-15, 15) / 10)
			local grab = limb.CFrame
			local offset = hand:GetPivot():ToObjectSpace(grab)
			local v = Instance.new("CFrameValue")
			v.Value = hand:GetPivot()
			v.Changed:Connect(function(cf)
				if hand.Parent then hand:PivotTo(cf) end
				if limb.Parent then limb.CFrame = cf * offset end
			end)
			TweenService:Create(v, TweenInfo.new(0.55, Enum.EasingStyle.Quad, Enum.EasingDirection.InOut), { Value = CFrame.new(mouth) * CFrame.Angles(0, math.random() * 6, 0) }):Play()
			task.wait(0.6)
			TweenService:Create(v, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
				{ Value = CFrame.new(mouth - Vector3.new(0, 7, 0)) * CFrame.Angles(math.rad(40), 0, 0) }):Play()
			task.wait(0.55)
			v:Destroy()
			hand:Destroy()
			if limb.Parent then limb.Transparency = 1 end
		end)
	end
	task.wait((#limbs - 1) * 0.14 + 1.7)

	-- Close.
	local close = TweenInfo.new(0.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
	for _, p in ipairs({ rim, core, pit }) do
		TweenService:Create(p, close, { Size = Vector3.new(0.1, 0.1, 0.1), Transparency = 1 }):Play()
	end
	smoke.Enabled = false
	embers.Enabled = false
	task.wait(0.45)
	swirl:Disconnect()
end

-- At 0 HP the body comes apart the same way the portal takes it: every joint
-- between limbs is cut and each limb is flung a little outward.
scatter = function(character: Model)
	local limbs: { BasePart } = {}
	for _, name in ipairs(LIMB_NAMES) do
		local p = character:FindFirstChild(name)
		if p and p:IsA("BasePart") then table.insert(limbs, p) end
	end
	local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
	for _, limb in ipairs(limbs) do
		for _, j in ipairs(limb:GetJoints()) do
			local other = (j :: any).Part0 == limb and (j :: any).Part1 or (j :: any).Part0
			if other and (table.find(limbs, other) or other == root) then j:Destroy() end
		end
	end
	local center = if root then root.Position else character:GetPivot().Position
	for _, limb in ipairs(limbs) do
		pcall(function() limb:SetNetworkOwner(nil) end)
		limb.CanCollide = true
		local out = Vector3.new(limb.Position.X - center.X, 0, limb.Position.Z - center.Z)
		out = if out.Magnitude > 0.05 then out.Unit else Vector3.new(math.random() - 0.5, 0, math.random() - 0.5).Unit
		limb:ApplyImpulse((out * 18 + Vector3.new(0, 16, 0)) * limb.AssemblyMass)
		limb:ApplyAngularImpulse(Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * limb.AssemblyMass * 20)
	end
end

-- Revive a fallen teammate on their feet next to `at`, keeping their run.
local function reviveAt(player: Player, at: Vector3, exact: boolean?)
	local classId = player:GetAttribute("SelectedClass")
	revive(player)
	player:LoadCharacter()
	local char = player.Character
	if char then
		local jitter = if exact then Vector3.zero else Vector3.new(math.random(-3, 3), 0, math.random(-3, 3))
		-- Stand on the real floor there (never inside it), held a moment so
		-- the floor has reached the player's game before they can fall.
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		local ignore: { Instance } = {}
		for _, p in ipairs(Players:GetPlayers()) do
			if p.Character then table.insert(ignore, p.Character) end
		end
		params.FilterDescendantsInstances = ignore
		local probe = at + jitter
		local hit = Workspace:Raycast(probe + Vector3.new(0, 8, 0), Vector3.new(0, -40, 0), params)
		local y = if hit then hit.Position.Y + 3.5 else probe.Y + 3
		local standCF = CFrame.new(probe.X, y, probe.Z)
		char:PivotTo(standCF)
		local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			root.Anchored = true
			-- A spectator's game streamed the map round whoever they watched
			-- (often a whole floor away, or the old level): make sure the
			-- floor here has reached them before letting go, or they drop
			-- through it into the void and die again straight away.
			task.spawn(function()
				pcall(function() player:RequestStreamAroundAsync(standCF.Position, 5) end)
				task.wait(0.6)
				if root.Parent then
					root.AssemblyLinearVelocity = Vector3.zero
					root.Anchored = false
				end
				-- Safety net: still falling a few seconds later? Back on the floor.
				for _ = 1, 8 do
					task.wait(0.5)
					if not root.Parent or player.Character ~= char then return end
					if root.Position.Y < standCF.Position.Y - 25 then
						root.AssemblyLinearVelocity = Vector3.zero
						char:PivotTo(standCF)
					end
				end
			end)
		end
		-- A moment to get your bearings (lava, the mob that killed you).
		char:SetAttribute("InvulnerableUntil", os.clock() + 3)
	end
	if typeof(classId) == "string" then
		WeaponManager.EquipWeapon(player, classId)
	end
	refresh(player)
end

-- Off to the title menu (after giving up, or leaving): the run's over for
-- them, so its summary goes up on their screen (RunStats).
local function toMenu(player: Player, result: string)
	RunStats.Finish(player, result)
	revive(player, true)
	player:SetAttribute("InLobby", true)
	player:SetAttribute("SpawnedInMap", false)
	player:LoadCharacter()
	-- Whoever was spectating us needs a new target.
	refresh(player)
end

local function anyoneFighting(player: Player): boolean
	for _, m in ipairs(runMates(player)) do
		if m ~= player and inDungeon(m) and isAlive(m) then return true end
	end
	return false
end

local function onAction(player: Player, action: any, arg: any)
	-- Leaving the run alive (the settings panel's LEAVE RUN): straight back
	-- to the menu. The run goes on for whoever's still in it, and ends (and
	-- resets) once nobody is.
	if action == "quit" then
		if not inDungeon(player) or player:GetAttribute("IsDead") == true then return end
		deathPos[player] = nil
		toMenu(player, "left")
		return
	end
	if player:GetAttribute("IsDead") ~= true then return end
	if action == "revive" or action == "respawn" then
		-- Once per run (not after giving up).
		if player:GetAttribute("GivingUp") == true then return end
		local left = player:GetAttribute("RevivesLeft") or 0
		if left <= 0 then return end
		player:SetAttribute("RevivesLeft", left - 1)
		-- Back on your feet where you fell: same dungeon, level, tomes, Threat.
		local at = deathPos[player]
		if not at then
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
			at = if root then root.Position else nil
		end
		if not at then return end
		deathPos[player] = nil
		reviveAt(player, at, true)
	elseif action == "giveup" or action == "menu" then
		if player:GetAttribute("GivingUp") == true then return end
		player:SetAttribute("GivingUp", true)
		if player.Character then portalTakes(player.Character) end
		if player:GetAttribute("IsDead") ~= true then return end -- revived meanwhile
		if anyoneFighting(player) then
			-- Watch the ones still fighting.
			player:SetAttribute("Spectating", true)
			refresh(player)
		else
			toMenu(player, "fallen")
		end
	elseif action == "leave" then
		if player:GetAttribute("Spectating") ~= true then return end
		toMenu(player, "fallen")
	elseif action == "watch" then
		-- Spectating someone: stream the map round them to this player (with
		-- streaming on, a teammate across the dungeon isn't loaded on their
		-- client, and the camera was left at their own body under the floor).
		if player:GetAttribute("Spectating") ~= true then return end
		local target = if typeof(arg) == "number" then Players:GetPlayerByUserId(arg) else nil
		local mates = runMates(player)
		local root = target and table.find(mates, target) and target.Character
			and target.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
		player.ReplicationFocus = root
	end
end

-- The run's over for `player` from outside (the party extracted, the
-- dungeon collapsed on them): back to the menu with `result` on their summary.
function DeathManager.EndRun(player: Player, result: string)
	if not inDungeon(player) then return end
	deathPos[player] = nil
	toMenu(player, result)
end

-- The Cleric's Divine Ascent: every fallen player in the run who hasn't
-- given up stands back up beside them (party or not: it used to ask the
-- party, so teammates who never sent an invite stayed dead). Returns how
-- many rose.
function DeathManager.ReviveParty(caster: Player, at: Vector3): number
	local n = 0
	for _, m in ipairs(runMates(caster)) do
		if m ~= caster and m:GetAttribute("IsDead") == true and m:GetAttribute("GivingUp") ~= true and inDungeon(m) then
			n += 1
			task.spawn(reviveAt, m, at)
		end
	end
	RunStats.Add(caster, "revives", n)
	return n
end

-- A new level: every fallen player still in the run stands up at `at`
-- (unless they're already giving up).
function DeathManager.ReviveAllAt(at: Vector3, runId: string?)
	for _, p in ipairs(Players:GetPlayers()) do
		if (p:GetAttribute("IsDead") == true or p:GetAttribute("Spectating") == true or p:GetAttribute("GivingUp") == true)
			and inDungeon(p)
			and (runId == nil or p:GetAttribute("RunId") == runId) then
			task.spawn(reviveAt, p, at)
		end
	end
end

function DeathManager.Init()
	Players.RespawnTime = 1e6
	-- A run starting for a player (first entry, PLAY again): their revive.
	ClassManager.OnClassSelected(function(player: Player)
		player:SetAttribute("RevivesLeft", REVIVES_PER_RUN)
	end)
	Network.GetRemoteEvent(Network.Remotes.DeathAction).OnServerEvent:Connect(onAction)
	-- Done spectating (revived, left, run over): the map streams round them again.
	local function watchSpectating(p: Player)
		p:GetAttributeChangedSignal("Spectating"):Connect(function()
			if p:GetAttribute("Spectating") ~= true then p.ReplicationFocus = nil end
		end)
	end
	for _, p in ipairs(Players:GetPlayers()) do watchSpectating(p) end
	Players.PlayerAdded:Connect(watchSpectating)
	local function added(player: Player)
		player.CharacterAdded:Connect(function(c) hook(player, c) end)
		if player.Character then task.spawn(hook, player, player.Character) end
	end
	for _, p in ipairs(Players:GetPlayers()) do added(p) end
	Players.PlayerAdded:Connect(added)
	-- A leaving teammate can turn spectators into a wipe.
	Players.PlayerRemoving:Connect(function()
		task.defer(function()
			for _, p in ipairs(Players:GetPlayers()) do
				if p:GetAttribute("IsDead") == true then refresh(p) end
			end
		end)
	end)
	-- (Fallen players come back only when a boss falls: MobManager calls
	-- ReviveAllAt. No longer when a teammate climbs past their floor.)
	Players.PlayerRemoving:Connect(function(p)
		reviveTier[p] = nil
		deathPos[p] = nil
	end)
	print("[DeathManager] initialized.")
end

return DeathManager
