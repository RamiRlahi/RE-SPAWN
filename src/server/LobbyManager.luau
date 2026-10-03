--!strict
--[[
	LobbyManager.luau
	The lobby: a floating plaza where everyone in the server walks around as
	their class between runs, meets up and parties up (invite someone by
	walking up to them), and picks a map at one of its gates.

	  Title → class select → the LOBBY (walk) → step through a map's gate →
	  the campfire platform (ready up) → the portal → your party's own run.

	  • Confirming a class (ClassManager's gate) puts you in the lobby
	    ("InHub"), weapon in hand.
	  • The DUNGEON gate (or the QUESTS board) opens the map picker; picking a
	    map sends your party to the campfire with it: only the leader picks; a
	    member who picks joins the leader's campfire if they're already there.
	  • The GACHA tent opens the summon page.
	  The plaza itself is built by LobbyBuilder (after the concept art).
	  • BACK at the campfire returns you to the lobby.

	Remotes: LobbyState (server → client: { mode = "hub" | "campfire", mapId,
	notice }), LobbyAction (client → server: { kind = "toHub" }).
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Network = require(Shared:WaitForChild("Network"))
local MapData = require(Shared:WaitForChild("MapData"))
local LobbyBuilder = require(script.Parent:WaitForChild("LobbyBuilder"))
local ClassData = require(Shared:WaitForChild("ClassData"))

local ClassManager = require(script.Parent:WaitForChild("ClassManager"))
local PartyManager = require(script.Parent:WaitForChild("PartyManager"))
local CampfireManager = require(script.Parent:WaitForChild("CampfireManager"))
local WeaponManager = require(script.Parent:WaitForChild("WeaponManager"))

local LobbyManager = {}

-- ── The plaza ───────────────────────────────────────────────────────────────
local HUB = MapData.LOBBY_CENTER         -- the plaza's centre (far west of every run's slot)
local FALL_Y = HUB.Y - 60                -- below this you're put back in the plaza

local hub: Model? = nil
local spawnCF = CFrame.new(HUB + Vector3.new(0, 4, 30))

local onGate: (Player, string) -> ()

-- ── Moving players ──────────────────────────────────────────────────────────
local function state(player: Player, payload: any)
	Network.GetRemoteEvent(Network.Remotes.LobbyState):FireClient(player, payload)
end

local function placeInHub(player: Player)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	if not char or not root or not hum then return end
	local jitter = Vector3.new(math.random(-8, 8), 0, math.random(-4, 4))
	-- (streaming: have the plaza around them before they land there)
	pcall(function() player:RequestStreamAroundAsync(spawnCF.Position, 5) end)
	-- (held there a moment, so the floor has reached their game before
	-- they can fall: their own physics would drop them through the void)
	root.Anchored = true
	char:PivotTo(spawnCF + jitter) -- (facing up the stairs into the plaza)
	root.AssemblyLinearVelocity = Vector3.zero
	task.delay(1.5, function()
		if root.Parent and player:GetAttribute("InHub") == true then root.Anchored = false end
	end)
	hum.WalkSpeed = 16
	hum.JumpPower = 50
	hum.JumpHeight = 7.2
	hum.UseJumpPower = false
end

-- Your class weapon, carried (on the back, or the Gunslinger's on his hip).
local function carryWeapon(player: Player)
	local classId = player:GetAttribute("SelectedClass")
	if typeof(classId) == "string" then
		local ok, err = pcall(WeaponManager.StowWeapon, player, classId)
		if not ok then warn("[LobbyManager] carrying the weapon:", err) end
	end
end

-- Into the lobby: walking about as your class.
function LobbyManager.ToHub(player: Player)
	player:SetAttribute("InHub", true)
	player:SetAttribute("AtCampfire", nil)
	carryWeapon(player)
	placeInHub(player)
	state(player, { mode = "hub" })
end

-- To the campfire on `mapId` (the party's ready-up before the run).
local function toCampfire(player: Player, mapId: string): boolean
	local classId = player:GetAttribute("SelectedClass")
	if typeof(classId) ~= "string" or not ClassData.GetClass(classId) then return false end
	player:SetAttribute("LobbyMap", mapId)
	if not CampfireManager.Seat(player, classId) then return false end
	player:SetAttribute("InHub", nil)
	state(player, { mode = "campfire", mapId = mapId })
	return true
end

onGate = function(player: Player, mapId: string)
	if player:GetAttribute("InHub") ~= true or not MapData.Get(mapId) then return end
	local map = MapData.Get(mapId)
	if map and map.unlockFloor and (player:GetAttribute("BestFloor") or 0) < map.unlockFloor then
		state(player, { mode = "hub", notice = `{map.name}: reach floor {map.unlockFloor} in any dungeon to open it.` })
		return
	end
	local leader = PartyManager.Leader(player)
	if leader ~= player then
		-- A member: they go where their leader went.
		local led = leader:GetAttribute("LobbyMap")
		if leader:GetAttribute("AtCampfire") == true and typeof(led) == "string" then
			toCampfire(player, led)
		else
			state(player, { mode = "hub", notice = `Only {leader.DisplayName} (your party leader) can choose the map.` })
		end
		return
	end
	-- The leader: everyone in the party walking the lobby comes along.
	for _, m in ipairs(PartyManager.Members(player)) do
		if m.Parent and (m == player or m:GetAttribute("InHub") == true) then
			toCampfire(m, mapId)
		elseif m.Parent and m ~= player then
			m:SetAttribute("LobbyMap", mapId) -- (they'll find the way to the leader's fire)
		end
	end
end

-- Where characters wait while their player is in the menus (title, class
-- select, the campfire): a hidden ledge below the plaza. (There used to be a
-- dungeon at the world's origin to land on; now runs are built on demand, so
-- without this a fresh character fell into the void.)
local HOLD = HUB + Vector3.new(0, -140, 0)
local function buildHold()
	if Workspace:FindFirstChild("MenuHold") then return end
	local sp = Instance.new("SpawnLocation")
	sp.Name = "MenuHold"
	sp.Anchored = true
	sp.Size = Vector3.new(24, 1, 24)
	sp.CFrame = CFrame.new(HOLD)
	sp.Transparency = 1
	sp.CanCollide = true
	sp.Neutral = true
	sp.Duration = 0 -- (no spawn forcefield)
	local decal = sp:FindFirstChildOfClass("Decal")
	if decal then decal:Destroy() end
	sp.Parent = Workspace
end

-- ── Wiring ──────────────────────────────────────────────────────────────────
function LobbyManager.Init()
	local function inHub(plr: Player): boolean return plr:GetAttribute("InHub") == true end
	local built, sp = LobbyBuilder.Build(Workspace, HUB, MapData.Maps, {
		dungeon = function(plr) if inHub(plr) then state(plr, { mode = "pick" }) end end,
		quests = function(plr) if inHub(plr) then state(plr, { mode = "pick" }) end end,
		gacha = function(plr) if inHub(plr) then state(plr, { mode = "gacha" }) end end,
	})
	hub = built
	spawnCF = sp
	buildHold()
	-- Confirming a class sends you into the lobby (not straight to a fire).
	ClassManager.SetGate(function(player: Player, classId: string): boolean
		if not ClassData.GetClass(classId) then return false end
		LobbyManager.ToHub(player)
		return true
	end)
	Network.GetRemoteEvent(Network.Remotes.LobbyAction).OnServerEvent:Connect(function(player: Player, payload: any)
		if typeof(payload) ~= "table" then return end
		if payload.kind == "toHub" and player:GetAttribute("InLobby") ~= false then
			CampfireManager.Unseat(player)
			LobbyManager.ToHub(player)
		elseif payload.kind == "pick" and typeof(payload.mapId) == "string" then
			onGate(player, payload.mapId)
		end
	end)
	-- A respawn while in the lobby: back on the plaza (not frozen at the church).
	local function watch(p: Player)
		local function onCharacter(char: Model)
			if p:GetAttribute("InHub") == true then
				task.wait(0.2)
				placeInHub(p)
				if p.Character == char then carryWeapon(p) end
			elseif p:GetAttribute("InLobby") ~= false then
				-- In the menus: parked on the hold, still (a fresh character
				-- otherwise drops from the default spawn into the void).
				local root = char:WaitForChild("HumanoidRootPart", 10) :: BasePart?
				if root and p:GetAttribute("InLobby") ~= false and p:GetAttribute("InHub") ~= true then
					root.Anchored = true
					char:PivotTo(CFrame.new(HOLD + Vector3.new(0, 4, 0)))
				end
			end
		end
		p.CharacterAdded:Connect(onCharacter)
		if p.Character then task.spawn(onCharacter, p.Character) end
		-- Off to a run, or back to the title menu: out of the lobby.
		p:GetAttributeChangedSignal("InLobby"):Connect(function()
			if p:GetAttribute("InLobby") == false then p:SetAttribute("InHub", nil) end
		end)
	end
	for _, p in ipairs(Players:GetPlayers()) do watch(p) end
	Players.PlayerAdded:Connect(watch)
	-- Fell off the plaza: back on it.
	task.spawn(function()
		while true do
			task.wait(0.5)
			for _, p in ipairs(Players:GetPlayers()) do
				local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
				if p:GetAttribute("InHub") == true and root and root.Position.Y < FALL_Y then placeInHub(p) end
			end
		end
	end)
	print("[LobbyManager] initialized.")
end

return LobbyManager
