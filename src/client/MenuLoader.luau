--!strict
--[[
	MenuLoader.luau
	Loads the game menu and keeps it loaded.

	The loading screen itself (ReplicatedFirst/Loader: LoadingCover, shown on
	the very first frame by Boot) stays up until the menu's critical assets
	have actually loaded; this drives it:

	  AWAKENING THE WORLD…        the place finishes loading
	  GATHERING THE SKY KINGDOM…  the menu assets arrive (ReplicatedStorage/
	                              Preload/MenuAssets and the packs the scene
	                              borrows from) and the world around the title
	                              shot streams in
	  RAISING THE SKY KINGDOM…    the backdrop is built (MenuBackdrop) and every
	                              menu asset is preloaded: the MenuAssets
	                              folder, every mesh / texture / sound /
	                              animation in the built scene (the castles and
	                              their islands), the sky, the menu UI
	  PREPARING EXPEDITION…       every gameplay asset too (the rest of
	                              ReplicatedStorage: dungeon packs, class gear,
	                              VFX, sounds), first load only; they stay
	                              cached for the session
	  WAKING YOUR HERO…           your avatar finishes loading (your hero
	                              stands in the scene) and is preloaded too

	The menu is revealed only when every one of those assets has reported back
	from ContentProvider:PreloadAsync (loaded, or failed for good), not on a
	timer or the request queue. Each distinct asset is preloaded through a
	small typed stand-in (Decal / SpecialMesh / Sound / Animation), so it loads
	as the right type and one bad instance can't stall the whole preload; each
	step also has a generous hang guard that only trips if Roblox never
	answers, and says so in the output. Last, the finished view keeps drawing
	behind the screen until the content request queue has stayed empty for a
	moment (so every castle mesh is on screen), then the screen fades into the
	menu.

	While you're in the menus, a watchdog checks every second that the scene
	is still whole and its lighting grade intact, and rebuilds or re-applies it
	if not. Entering a run tears the scene down and switches to the dim dungeon
	lighting; coming back loads the menu again (behind the same screen).
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ReplicatedFirst = game:GetService("ReplicatedFirst")
local ContentProvider = game:GetService("ContentProvider")
local RunService = game:GetService("RunService")
local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

local MenuBackdrop = require(script.Parent:WaitForChild("MenuBackdrop"))
-- The loading screen (ReplicatedFirst/Loader). If it's missing (Rojo not yet
-- serving the new mapping), load without a screen rather than hang.
local Cover: any = nil
do
	local loader = ReplicatedFirst:WaitForChild("Loader", 5)
	local mod = loader and loader:WaitForChild("LoadingCover", 5)
	if mod then
		Cover = require(mod :: any)
	else
		warn("[MenuLoader] ReplicatedFirst/Loader is missing (restart `rojo serve` to sync it); loading without the screen.")
		Cover = {
			Show = function() end,
			SetProgress = function(_: number, _: string?) end,
			Hide = function() end,
			IsShown = function() return false end,
		}
	end
end
local Atmosphere: any = nil
pcall(function()
	Atmosphere = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("AtmosphereManager") :: any)
end)

local MenuLoader = {}

local player = Players.LocalPlayer

-- Packs the menu scene borrows from (statues, the planted sword's asset) and
-- the menu-only models it's built from.
local REQUIRED_PACKS = { "dungeon assets", "map2assets" }
local SCENE_MODELS = { "floating island", "waterfall" }
-- Not assets: never preloaded.
local NOT_ASSETS = { Preload = true, Shared = true, Remotes = true }

-- Only trips if Roblox never answers a preload; logged when it does.
local HANG_GUARD = 45
-- Most the final settle waits for the request queue to drain.
local SETTLE_CAP = 8

local loading = false
local inDungeon = false
local gameplayLoaded = false

local function inLobby(): boolean
	return player:GetAttribute("InLobby") ~= false
end

-- ── Collecting content ────────────────────────────────────────────────────
-- The content each class the menu uses carries, by kind. PreloadAsync only
-- loads an id properly through an instance of the right type (a bare id
-- string is fetched as an image, so meshes, sounds and animations "fail"),
-- and the scene's own instances can carry empty ids that stall it. So every
-- id is preloaded through a small typed stand-in: a Decal for images, a
-- SpecialMesh for meshes, a Sound, or an Animation.
type Kind = "image" | "mesh" | "sound" | "anim"
local CONTENT_PROPS: { { any } } = {
	{ "MeshPart", { MeshId = "mesh", TextureID = "image" } },
	{ "SpecialMesh", { MeshId = "mesh", TextureId = "image" } },
	{ "Decal", { Texture = "image" } }, -- also Texture
	{ "ImageLabel", { Image = "image" } },
	{ "ImageButton", { Image = "image" } },
	{ "ParticleEmitter", { Texture = "image" } },
	{ "Beam", { Texture = "image" } },
	{ "Trail", { Texture = "image" } },
	{ "Sound", { SoundId = "sound" } },
	{ "Animation", { AnimationId = "anim" } },
	{ "Sky", { SkyboxBk = "image", SkyboxDn = "image", SkyboxFt = "image", SkyboxLf = "image", SkyboxRt = "image",
		SkyboxUp = "image", SunTextureId = "image", MoonTextureId = "image" } },
	{ "Shirt", { ShirtTemplate = "image" } },
	{ "Pants", { PantsTemplate = "image" } },
	{ "ShirtGraphic", { Graphic = "image" } },
}

type Content = { items: { Instance }, ids: number }

local function standIn(kind: Kind, id: string): Instance
	if kind == "mesh" then
		local m = Instance.new("SpecialMesh")
		m.MeshType = Enum.MeshType.FileMesh
		m.MeshId = id
		return m
	elseif kind == "sound" then
		local s = Instance.new("Sound")
		s.SoundId = id
		return s
	elseif kind == "anim" then
		local a = Instance.new("Animation")
		a.AnimationId = id
		return a
	end
	local d = Instance.new("Decal")
	d.Texture = id
	return d
end

-- Everything under `roots` as typed stand-ins (one per distinct id), plus
-- the instances whose content can't be read as an id (unions, PBR surfaces),
-- except under `idsOnly` roots (copies of models whose originals are already
-- listed). `yieldEvery` keeps huge trees from hitching.
local function collect(roots: { Instance }, yieldEvery: number?, idsOnly: { Instance }?): Content
	local items: { Instance } = {}
	local seen: { [any]: boolean } = {}
	local ids = 0
	local function addId(kind: Kind, v: any)
		if typeof(v) == "string" and v ~= "" and v ~= "rbxassetid://0" and not seen[v] then
			seen[v] = true
			ids += 1
			table.insert(items, standIn(kind, v))
		end
	end
	local count = 0
	local skipInstances = false
	local function visit(d: Instance)
		count += 1
		if yieldEvery and count % yieldEvery == 0 then task.wait() end
		if d:IsA("PartOperation") or d:IsA("SurfaceAppearance") then
			if not skipInstances and not seen[d] then
				seen[d] = true
				table.insert(items, d)
			end
			return
		end
		if d:IsA("CharacterMesh") then
			if d.MeshId > 0 then addId("mesh", `rbxassetid://{d.MeshId}`) end
			if d.BaseTextureId > 0 then addId("image", `rbxassetid://{d.BaseTextureId}`) end
			if d.OverlayTextureId > 0 then addId("image", `rbxassetid://{d.OverlayTextureId}`) end
			return
		end
		for _, entry in ipairs(CONTENT_PROPS) do
			if d:IsA(entry[1]) then
				for prop, kind in pairs(entry[2]) do
					local ok, v = pcall(function() return (d :: any)[prop] end)
					if ok then addId(kind, v) end
				end
				return
			end
		end
	end
	for _, root in ipairs(roots) do
		skipInstances = idsOnly ~= nil and table.find(idsOnly, root) ~= nil
		visit(root)
		for _, d in ipairs(root:GetDescendants()) do visit(d) end
	end
	return { items = items, ids = ids }
end

-- Run a (yielding) preload, waiting until it finishes. The guard only trips
-- if Roblox never answers; it's logged so it can be looked into.
local function guarded(what: string, fn: () -> ())
	local finished = false
	task.spawn(function()
		pcall(fn)
		finished = true
	end)
	local t0 = os.clock()
	while not finished do
		if os.clock() - t0 > HANG_GUARD then
			warn(`[MenuLoader] Preloading {what} never finished; showing the menu anyway.`)
			return
		end
		task.wait()
	end
end

-- Preload `content` completely, reporting progress between `from` and `to`.
-- Batches load side by side; the step ends when every one has reported.
local function preload(content: Content, from: number, to: number, status: string, what: string?)
	local label = what or "menu"
	local items = content.items
	local total = math.max(#items, 1)
	local done = 0
	local failed: { string } = {}
	local function report()
		Cover.SetProgress(from + (to - from) * math.min(done / total, 1), status)
	end
	report()
	local BATCH = 40
	local pending = 0
	for i = 1, #items, BATCH do
		local batch = table.move(items, i, math.min(i + BATCH - 1, #items), 1, {})
		pending += 1
		task.spawn(function()
			guarded(`{#batch} {label} assets`, function()
				ContentProvider:PreloadAsync(batch, function(id, fetch)
					if fetch ~= Enum.AssetFetchStatus.Success then table.insert(failed, id) end
				end)
			end)
			done += #batch
			report()
			pending -= 1
		end)
	end
	while pending > 0 do task.wait() end
	if #failed > 0 then
		warn(`[MenuLoader] {#failed} {label} asset(s) failed to load (moderated or deleted?): {table.concat(failed, ", ", 1, math.min(#failed, 6))}`)
	end
	Cover.SetProgress(to, status)
end

-- Wait for `name` in ReplicatedStorage (or the menu's scene models).
local function arrive(name: string, isSceneModel: boolean)
	local t0 = os.clock()
	while os.clock() - t0 < HANG_GUARD do
		if isSceneModel then
			if MenuBackdrop.SceneModel(name) then return end
		elseif ReplicatedStorage:FindFirstChild(name) then
			return
		end
		task.wait(0.1)
	end
	warn(`[MenuLoader] "{name}" never arrived; the menu is built without it.`)
end

-- ── Loading ───────────────────────────────────────────────────────────────
function MenuLoader.Load()
	if loading then return end
	loading = true
	Cover.Show() -- already up on join (Boot); shown again after a run
	task.spawn(function()
		local ok, err = pcall(function()
			Cover.SetProgress(0.03, "AWAKENING THE WORLD…")
			if not game:IsLoaded() then game.Loaded:Wait() end
			Cover.SetProgress(0.1)

			-- The assets the scene is built from, and the world around the
			-- title shot (streaming would otherwise pop it in late).
			Cover.SetProgress(0.1, "GATHERING THE SKY KINGDOM…")
			local steps = #REQUIRED_PACKS + #SCENE_MODELS + 1
			local n = 0
			local function step()
				n += 1
				Cover.SetProgress(0.1 + 0.08 * n / steps)
			end
			local preloadFolder = ReplicatedStorage:WaitForChild("Preload", HANG_GUARD)
			if preloadFolder then preloadFolder:WaitForChild("MenuAssets", HANG_GUARD) end
			step()
			for _, name in ipairs(SCENE_MODELS) do
				arrive(name, true)
				step()
			end
			for _, name in ipairs(REQUIRED_PACKS) do
				arrive(name, false)
				step()
			end
			if not inLobby() then return end

			Cover.SetProgress(0.18, "RAISING THE SKY KINGDOM…")
			task.wait() -- let the screen draw first
			if Atmosphere then Atmosphere.ApplyLobbyLighting() end
			inDungeon = false
			MenuBackdrop.Build()
			local vista = MenuBackdrop.Vista()
			if vista then
				pcall(function()
					player:RequestStreamAroundAsync(vista.Position + vista.LookVector * 150, 10)
				end)
			end
			Cover.SetProgress(0.22)

			-- Every critical asset, loaded before the menu shows.
			local roots: { Instance } = {}
			local menuAssets = preloadFolder and preloadFolder:FindFirstChild("MenuAssets")
			if menuAssets then table.insert(roots, menuAssets) end
			for _, name in ipairs(SCENE_MODELS) do
				local m = MenuBackdrop.SceneModel(name) -- the originals (if not in MenuAssets yet)
				if m and not (menuAssets and m:IsDescendantOf(menuAssets)) then table.insert(roots, m) end
			end
			-- The built scene is copies of those: its ids only, not every union again.
			local scene = MenuBackdrop.Folder()
			if scene then table.insert(roots, scene) end
			local sky = Lighting:FindFirstChildOfClass("Sky")
			if sky then table.insert(roots, sky) end
			local lobby = Workspace:FindFirstChild("SpawnPoint") -- the lobby islands in view
			if lobby then table.insert(roots, lobby) end
			local lobbyGui = player:WaitForChild("PlayerGui"):WaitForChild("LobbyScreenGui", 10)
			if lobbyGui then table.insert(roots, lobbyGui) end
			preload(collect(roots, 4000, if scene then { scene } else nil), 0.22, 0.5, "RAISING THE SKY KINGDOM…")

			-- Every gameplay asset too, before the menu shows (first time
			-- only: they stay cached for the session). The scene keeps
			-- drawing behind the screen meanwhile.
			if not gameplayLoaded then
				Cover.SetProgress(0.5, "PREPARING EXPEDITION…")
				local gameplay: { Instance } = {}
				for _, c in ipairs(ReplicatedStorage:GetChildren()) do
					if not NOT_ASSETS[c.Name] and not c:IsA("LuaSourceContainer") then
						table.insert(gameplay, c)
					end
				end
				local content = collect(gameplay, 1500)
				preload(content, 0.5, 0.86, "PREPARING EXPEDITION…", "gameplay")
				gameplayLoaded = true
				print(`[MenuLoader] Gameplay assets preloaded before the menu ({content.ids} assets).`)
			end

			-- Your avatar (your hero stands in the scene), fully loaded.
			Cover.SetProgress(0.86, "WAKING YOUR HERO…")
			local t0 = os.clock()
			while (not player.Character or not player:HasAppearanceLoaded()) and os.clock() - t0 < HANG_GUARD do
				task.wait(0.1)
			end
			local heroRoots: { Instance } = {}
			if player.Character then table.insert(heroRoots, player.Character) end
			preload(collect(heroRoots), 0.86, 0.97, "WAKING YOUR HERO…")

			-- Settle: keep drawing the finished view behind the screen until
			-- every content request has come back (meshes, textures, the
			-- castles' islands) and the scene has rendered for a moment, so
			-- the first thing seen is the whole sky kingdom. Not a timer on
			-- its own: it waits for the request queue to stay empty; the cap
			-- only covers a window that isn't rendering.
			local frames, quiet = 0, 0
			local c = RunService.RenderStepped:Connect(function()
				frames += 1
				quiet = if ContentProvider.RequestQueueSize == 0 then quiet + 1 else 0
			end)
			local t1 = os.clock()
			while os.clock() - t1 < SETTLE_CAP do
				if quiet >= 20 and frames >= 45 and os.clock() - t1 >= 0.8 then break end
				if frames == 0 and os.clock() - t1 > 2 then break end -- not rendering
				Cover.SetProgress(0.97 + 0.03 * math.min((os.clock() - t1) / 1.2, 1))
				task.wait()
			end
			c:Disconnect()
			Cover.SetProgress(1, "READY")
		end)
		if not ok then warn("[MenuLoader] Loading the menu failed: " .. tostring(err)) end
		if inLobby() then MenuBackdrop.Reveal() end
		loading = false
		Cover.Hide()
	end)
end

-- ── Keeping it loaded ─────────────────────────────────────────────────────
local function enterDungeon()
	if inDungeon then return end
	inDungeon = true
	MenuBackdrop.Destroy()
	MenuBackdrop.DestroyHubSky()
	if Atmosphere then
		-- (the light of the map the party picked)
		local mapId = player:GetAttribute("LobbyMap")
		Atmosphere.ApplyDungeonLighting(if typeof(mapId) == "string" then mapId else nil)
	end
end

local function watchdog()
	while true do
		task.wait(1)
		if loading or not inLobby() then continue end
		if not MenuBackdrop.IsHealthy() then
			warn("[MenuLoader] The menu scene went missing; rebuilding it.")
			MenuLoader.Load()
		else
			MenuBackdrop.EnsureGrade()
		end
	end
end

function MenuLoader.Init()
	player:GetAttributeChangedSignal("InLobby"):Connect(function()
		if inLobby() then
			if inDungeon or not MenuBackdrop.IsHealthy() then MenuLoader.Load() end
		else
			enterDungeon()
		end
	end)
	if inLobby() then
		MenuLoader.Load()
	else
		enterDungeon()
		Cover.Hide()
	end
	task.spawn(watchdog)
end

return MenuLoader
