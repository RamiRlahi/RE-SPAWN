--!strict
--[[
	MusicController.luau
<<<<<<< Updated upstream
	Music: one track on the menu screens (title, class select, the campfire),
	another walking the lobby plaza; in a run, a dark dungeon track (the two
	take turns run to run), giving way to the drums of a horde event
	(Horde.luau) while one is on.
=======
	Music outside the dungeon: one soundtrack for the menu screens (title,
	class select, the campfire) and the lobby plaza alike, so walking from one
	to the other it simply carries on (never starting over); in a run, only
	the drums of a horde event (Horde.luau). Back from a run, the soundtrack
	picks up where it was left.
>>>>>>> Stashed changes
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
	dungeon1 = "rbxassetid://1837286563", -- "Dark Fantasy", APM
	dungeon2 = "rbxassetid://1835356065", -- "Demon Dimension", APM
}
-- (each track's own level: the dungeon's is a bed under the fighting)
local GAIN: { [string]: number } = { dungeon1 = 0.7, dungeon2 = 0.7 }
local BASE = 0.5 -- the tracks' own loudness at full Music Volume
local FADE = 1.5

local sounds: { [string]: Sound } = {}
local current: string? = nil

local function volume(name: string): number
	local v = player:GetAttribute("Setting_musicVolume")
	return BASE * (GAIN[name] or 1) * (if typeof(v) == "number" then math.clamp(v, 0, 1) else 0.6)
end

-- Which dungeon track this run gets: the other one from last run.
local dungeonTrack = "dungeon2"
local wasInRun = false

local function want(): string?
	-- (the lobby plaza too: the same track, so it never restarts on the way in)
	if player:GetAttribute("InHub") == true or player:GetAttribute("InLobby") ~= false then return "menu" end
	if typeof(RunScope.Mine("HordeUntil")) == "number" then return "horde" end
	return dungeonTrack
end

local function sync()
	local inRun = player:GetAttribute("InLobby") == false and player:GetAttribute("InHub") ~= true
	if inRun and not wasInRun then
		dungeonTrack = if dungeonTrack == "dungeon1" then "dungeon2" else "dungeon1"
	end
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
		s.Looped = true
		s.Volume = 0
		s.Parent = SoundService
		sounds[name] = s
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
