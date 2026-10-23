--!strict
--[[
	ClassCapes.luau
	Cloth capes (ClothCape, a client-side cloth simulation) on every character
	that wears one, hung by every client and taken off again when the class
	changes or the character goes away:
	  • the Sword Master (Class "swordsman"): his white fur-collared cape;
	  • the Berserker (Class "berserker"): his ragged cape of black feathers
	    bleeding to crimson (his armour's flat plate cape hidden under it);
	  • the Mage (Class "mage"): his long navy cloak lined in violet;
	  • the Fire Knight (Class "heavy_knight"): his crimson cape with a black
	    fur mantle;
	  • the Gunslinger: his duster.
	Each is part of its class's outfit, a summon reward: a player wears it
	only while that armor is equipped (Armor_<class>, from the Wardrobe).
--]]

local Players = game:GetService("Players")

local ClothCape = require(script.Parent:WaitForChild("ClothCape"))

local ClassCapes = {}

-- Every cape is part of a class's outfit (armor, worn from the Wardrobe):
-- a player's character wears it only while that armor is equipped.
local CAPES: { [string]: ClothCape.Style } = {
	swordsman = ClothCape.SWORD_MASTER, berserker = ClothCape.BERSERKER, mage = ClothCape.MAGE,
	gunslinger = ClothCape.GUNSLINGER, heavy_knight = ClothCape.FIRE_KNIGHT,
}

-- The cape style a character should wear now, if any.
local function styleFor(character: Model): ClothCape.Style?
	local class = character:GetAttribute("Class")
	local style = if typeof(class) == "string" then CAPES[class] else nil
	if not style then return nil end
	local owner = Players:GetPlayerFromCharacter(character)
	if owner and owner:GetAttribute(`Armor_{class}`) ~= true then return nil end
	return style
end

local worn: { [Model]: ClothCape.Style } = {}

-- The armour's own plate cape and rags (BerserkerLook) under the cloth one.
local PLATE_CAPE = { Cape = true, CapeRag = true }
local function plateCape(character: Model, hidden: boolean)
	for _, d in ipairs(character:GetChildren()) do
		if d:IsA("BasePart") and PLATE_CAPE[d.Name] then
			d.Transparency = if hidden then 1 else 0
		end
	end
end

local function refresh(character: Model)
	local want = styleFor(character)
	local has = character:FindFirstChild("ClothCape") ~= nil
	if want and (not has or worn[character] ~= want) then
		-- Wait for the body the cape hangs from and collides with.
		if not character:FindFirstChild("Torso") and not character:FindFirstChild("UpperTorso") then return end
		ClothCape.Attach(character, nil, want)
		worn[character] = want
		plateCape(character, want == ClothCape.BERSERKER)
	elseif not want and has then
		ClothCape.Detach(character)
		worn[character] = nil
		plateCape(character, false)
	end
end

local WATCHED = { Torso = true, UpperTorso = true, ["Left Leg"] = true, ["Right Leg"] = true }

local function watchCharacter(character: Model)
	character:GetAttributeChangedSignal("Class"):Connect(function() refresh(character) end)
	character.ChildAdded:Connect(function(child)
		if WATCHED[child.Name] then task.defer(refresh, character) end
		if PLATE_CAPE[child.Name] and worn[character] == ClothCape.BERSERKER and child:IsA("BasePart") then
			child.Transparency = 1
		end
	end)
	character.AncestryChanged:Connect(function(_, parent)
		if not parent then worn[character] = nil end
	end)
	task.defer(refresh, character)
end

local function watchPlayer(player: Player)
	player.CharacterAdded:Connect(watchCharacter)
	-- (the outfit put on / taken off)
	for class in pairs(CAPES) do
		local a = `Armor_{class}`
		player:GetAttributeChangedSignal(a):Connect(function()
			if player.Character then refresh(player.Character) end
		end)
	end
	if player.Character then watchCharacter(player.Character) end
end

function ClassCapes.Init()
	Players.PlayerAdded:Connect(watchPlayer)
	for _, p in ipairs(Players:GetPlayers()) do watchPlayer(p) end
end

return ClassCapes
