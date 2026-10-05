--!strict
--[[
	FontStyle.luau
	Every word in the game in the Arcade font, except the map's: the minimap
	in the corner and the full map's drawing keep theirs. That's the screens
	(PlayerGui) and the words out in the world (nameplates, signs, boards,
	damage numbers). Text made later is styled as it appears, and kept Arcade
	if a script gives it another font. (Roblox's own chat bubbles and menus
	aren't the game's, and stay as they are.)
--]]

local Players = game:GetService("Players")
local Workspace = game:GetService("Workspace")

local FontStyle = {}

local ARCADE = Font.fromEnum(Enum.Font.Arcade)

-- The map's own words.
local function onMap(inst: Instance): boolean
	local sg = inst:FindFirstAncestorWhichIsA("ScreenGui")
	if not sg then return false end
	if sg.Name == "DungeonMinimapGui" then return true end
	-- (the full map: its drawing, not the tome list beside it)
	return sg.Name == "DungeonFullMapGui" and inst:FindFirstAncestor("Canvas") ~= nil
end

local watched: { [Instance]: boolean } = setmetatable({}, { __mode = "k" }) :: any

local function style(inst: Instance)
	if not (inst:IsA("TextLabel") or inst:IsA("TextButton") or inst:IsA("TextBox")) then return end
	local t = inst :: any
	local function apply()
		if onMap(inst) then return end
		if t.FontFace.Family ~= ARCADE.Family then t.Font = Enum.Font.Arcade end
	end
	apply()
	if not watched[inst] then
		watched[inst] = true
		t:GetPropertyChangedSignal("FontFace"):Connect(apply)
	end
end

local function cover(root: Instance)
	for _, d in ipairs(root:GetDescendants()) do style(d) end
	root.DescendantAdded:Connect(function(d)
		-- (most of what appears in the world is parts and effects: quick out)
		if d:IsA("GuiObject") then style(d) end
	end)
end

function FontStyle.Init()
	cover(Players.LocalPlayer:WaitForChild("PlayerGui"))
	cover(Workspace)
end

return FontStyle
