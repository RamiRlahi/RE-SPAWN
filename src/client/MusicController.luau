--!strict
--[[
	MusicController.luau
	Music outside the dungeon: one track on the menu screens (title, class
	select, the campfire), another walking the lobby plaza; in a run, only
	the drums of a horde event (Horde.luau).
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
	menu = "rbxassetid://9046506025",   -- "Imminent Closure (Underscore C)", APM
	lobby = "rbxassetid://108830435742016", -- "Festival Night Tavern"
	horde = "rbxassetid://108019516023646", -- "Intense Epic Battle Drums"
}
local BASE = 0.5 -- the tracks' own loudness at full Music Volume
local FADE = 1.5

local sounds: { [string]: Sound } = {}
local current: string? = nil

local function volume(): number
	local v = player:GetAttribute("Setting_musicVolume")
	return BASE * (if typeof(v) == "number" then math.clamp(v, 0, 1) else 0.6)
end

local function want(): string?
	if player:GetAttribute("InHub") == true then return "lobby" end
	if player:GetAttribute("InLobby") ~= false then return "menu" end
	if typeof(RunScope.Mine("HordeUntil")) == "number" then return "horde" end
	return nil
end

local function sync()
	local w = want()
	if w == current then
		if w and sounds[w] then sounds[w].Volume = volume() end
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
		TweenService:Create(s, TweenInfo.new(FADE), { Volume = volume() }):Play()
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
