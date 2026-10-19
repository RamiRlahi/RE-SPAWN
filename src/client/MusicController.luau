--!strict
--[[
	MusicController.luau
	Music: one soundtrack for the menu screens (title, class select, the
	campfire) and the lobby plaza alike, so walking from one to the other it
	simply carries on (never starting over); in a run, the dungeon playlist
	(Action, Running Faster A, Memento Mori: one after another, each run
	starting on the next), "Boss Battle Burnout" while a boss is alive near
	you, and the drums of a horde event (Horde.luau) while one is on. Back
	from a run, the menu soundtrack picks up where it was left.
	Tracks crossfade; the volume is the Music Volume setting.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunScope = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("RunScope"))
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local player = Players.LocalPlayer

local MusicController = {}

local TRACKS = {
	menu = "rbxassetid://9046506025",   -- "Imminent Closure (Underscore C)", APM: the menus and the lobby
	horde = "rbxassetid://108019516023646", -- "Intense Epic Battle Drums"
	dungeon1 = "rbxassetid://130366303895413", -- "Action"
	dungeon2 = "rbxassetid://1847683499",      -- "Running Faster A"
	dungeon3 = "rbxassetid://138649427280723", -- "Memento Mori"
	boss = "rbxassetid://139997523791273",     -- "Boss Battle Burnout"
}
-- (each track's own level: the dungeon's is a bed under the fighting)
local GAIN: { [string]: number } = { dungeon1 = 0.7, dungeon2 = 0.7, dungeon3 = 0.7 }
local BOSS_NEAR = 160 -- studs: a living boss this close puts the boss track on
local BASE = 0.5 -- the tracks' own loudness at full Music Volume
local FADE = 1.5

local sounds: { [string]: Sound } = {}
local current: string? = nil

local function volume(name: string): number
	local v = player:GetAttribute("Setting_musicVolume")
	return BASE * (GAIN[name] or 1) * (if typeof(v) == "number" then math.clamp(v, 0, 1) else 0.6)
end

-- The dungeon playlist: each track plays through once and the next follows
-- (they don't loop); each run starts on the track after the last run's.
local DUNGEON_TRACKS = { "dungeon1", "dungeon2", "dungeon3" }
local dungeonTurn = 0
local dungeonTrack = DUNGEON_TRACKS[1]
local wasInRun = false

local function nextDungeonTrack()
	dungeonTurn = dungeonTurn % #DUNGEON_TRACKS + 1
	dungeonTrack = DUNGEON_TRACKS[dungeonTurn]
end

-- A living boss near you (the Mobs folder, not the whole workspace).
local function bossNear(): boolean
	local mobs = workspace:FindFirstChild("Mobs")
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not (mobs and root) then return false end
	for _, m in ipairs(mobs:GetChildren()) do
		if m:GetAttribute("IsBoss") == true then
			local hum = m:FindFirstChildOfClass("Humanoid")
			local r = (m:FindFirstChild("HumanoidRootPart") or (m :: any).PrimaryPart) :: BasePart?
			if hum and hum.Health > 0 and r and (r.Position - root.Position).Magnitude < BOSS_NEAR then return true end
		end
	end
	return false
end

local function want(): string?
	-- (the lobby plaza too: the same track, so it never restarts on the way in)
	if player:GetAttribute("InHub") == true or player:GetAttribute("InLobby") ~= false then return "menu" end
	if typeof(RunScope.Mine("HordeUntil")) == "number" then return "horde" end
	if bossNear() then return "boss" end
	return dungeonTrack
end

local function sync()
	local inRun = player:GetAttribute("InLobby") == false and player:GetAttribute("InHub") ~= true
	if inRun and not wasInRun then nextDungeonTrack() end
	wasInRun = inRun
	local w = want()
	if w == current then
		if w and sounds[w] then sounds[w].Volume = volume(w) end
		return
	end
	current = w
	for name, s in pairs(sounds) do
		if name ~= w and s.IsPlaying then
			local t = TweenService:Create(s, TweenInfo.new(FADE), { Volume = 0 })
			t.Completed:Once(function() if current ~= name then s:Pause() end end)
			t:Play()
		end
	end
	if w then
		local s = sounds[w]
		if not s.IsPlaying then s.Volume = 0; s:Resume() end
		TweenService:Create(s, TweenInfo.new(FADE), { Volume = volume(w) }):Play()
	end
end

function MusicController.Init()
	for name, id in pairs(TRACKS) do
		local s = Instance.new("Sound")
		s.Name = "Music_" .. name
		s.SoundId = id
		s.Looped = string.sub(name, 1, 7) ~= "dungeon"
		s.Volume = 0
		s.Parent = SoundService
		sounds[name] = s
		if not s.Looped then
			-- (a dungeon track played through: on to the next, from its start)
			s.Ended:Connect(function()
				if dungeonTrack ~= name then return end
				nextDungeonTrack()
				local nxt = sounds[dungeonTrack]
				if nxt then nxt.TimePosition = 0 end
				if current == name then current = nil end
				sync()
			end)
		end
	end
	for _, a in ipairs({ "InHub", "InLobby", "Setting_musicVolume" }) do
		player:GetAttributeChangedSignal(a):Connect(sync)
	end
	sync()
	-- (a horde starting or ending is on the run's folder: checked now and then)
	task.spawn(function()
		while true do
			task.wait(0.5)
			sync()
		end
	end)
end

return MusicController
