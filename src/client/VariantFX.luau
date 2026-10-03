--!strict
--[[
	VariantFX.luau
	Recolours ability VFX with the caster's equipped VFX variant (VFXPalettes).

	Ability code parents its effects under VariantFX.Root() instead of
	Workspace.Terrain — or VariantFX.RootFor(player) when it knows the caster.
	Every effect added there is restyled with its owner's palette, and again
	if the effect code changes its colour later (tweens, per-frame updates).

	Owner: the RootFor(player) group when used; otherwise the player whose
	character is nearest the effect when it appears (solo: always you).
	Effects added onto a character (emitters, trails, lights) belong to that
	character's player. Server-made effects tagged "OwnedVFX" carry a
	VFXOwner user id.

	Styles
	  ramp  every colour mapped by brightness onto the palette's low→mid→high.
	  ink   (palette.ink) black bodies with a white contour and a small white
	        core: parts/meshes go black and their effect group gets a white
	        Highlight outline; beams and trails go black over a wider white
	        copy; particles use the palette's rimTexture (white core, black
	        body, white rim) or, without it, flash white then turn black.

	Contours cost one Highlight per effect group (all of a player's ability
	VFX share one), because Roblox only draws ~31 Highlights at once.

	A player's palette comes from their "Variant" attribute: the GachaRewards
	id the server sets for the class they're playing.
--]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local CollectionService = game:GetService("CollectionService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local GachaRewards = require(Shared:WaitForChild("GachaRewards"))
local VFXPalettes = require(Shared:WaitForChild("VFXPalettes"))

type Palette = VFXPalettes.Palette

local VariantFX = {}

local localPlayer = Players.LocalPlayer
local root: BasePart? = nil -- the shared anchor effects hang under
local rootModel: Model? = nil
local ownerRoots: { [Player]: BasePart } = {}
local started = false

local BLACK = Color3.new(0, 0, 0)
local WHITE = Color3.new(1, 1, 1)
local BLACK_SEQ = ColorSequence.new(BLACK)
local WHITE_SEQ = ColorSequence.new(WHITE)
-- Particles without the rim texture: a white spark at birth, then black.
local FLASH_SEQ = ColorSequence.new({
	ColorSequenceKeypoint.new(0, WHITE),
	ColorSequenceKeypoint.new(0.12, BLACK),
	ColorSequenceKeypoint.new(1, BLACK),
})
local RIM_WIDTH = 1.35 -- white beam/trail copies are this much wider
-- Built-in round puff with real transparency (fallback until rimTexture is set).
local SOFT_PUFF = "rbxasset://textures/particles/smoke_main.dds"

-- Colour properties per effect class, checked with IsA in order.
local EFFECT_PROPS: { { any } } = {
	{ "ParticleEmitter", { "Color" } },
	{ "Beam", { "Color" } },
	{ "Trail", { "Color" } },
	{ "Light", { "Color" } },
	{ "Highlight", { "FillColor", "OutlineColor" } },
	{ "Fire", { "Color", "SecondaryColor" } },
	{ "Smoke", { "Color" } },
	{ "Sparkles", { "SparkleColor" } },
}
-- Only inside the ability root (never on characters: armor, faces, clothes).
local ROOT_ONLY_PROPS: { { any } } = {
	{ "BasePart", { "Color" } },
	{ "Decal", { "Color3" } }, -- includes Texture
	{ "ImageLabel", { "ImageColor3" } },
}

-- Target value per instance/property, so our own writes don't retrigger.
local written: { [Instance]: { [string]: any } } = setmetatable({}, { __mode = "k" }) :: any
-- Owner resolved per top-level effect (child of the root).
local topOwner: { [Instance]: Player } = setmetatable({}, { __mode = "k" }) :: any
-- Contour Highlights per effect group, with who they belong to (nil = shared).
local contours: { [Highlight]: Player? } = {}

local function paletteOf(plr: Player?): Palette?
	if not plr then return nil end
	local id = plr:GetAttribute("Variant")
	if typeof(id) ~= "string" then return nil end
	local reward = GachaRewards.Get(id)
	return VFXPalettes.Get(reward and reward.palette)
end

local function propsFor(inst: Instance, onCharacter: boolean): { string }?
	for _, entry in ipairs(EFFECT_PROPS) do
		if inst:IsA(entry[1]) then return entry[2] end
	end
	if not onCharacter then
		for _, entry in ipairs(ROOT_ONLY_PROPS) do
			if inst:IsA(entry[1]) then return entry[2] end
		end
	end
	return nil
end

-- Colours read back from instances are quantised, so compare loosely.
local function closeColor(a: Color3, b: Color3): boolean
	return math.abs(a.R - b.R) < 0.01 and math.abs(a.G - b.G) < 0.01 and math.abs(a.B - b.B) < 0.01
end
local function same(a: any, b: any): boolean
	if typeof(a) == "Color3" and typeof(b) == "Color3" then
		return closeColor(a, b)
	end
	if typeof(a) == "ColorSequence" and typeof(b) == "ColorSequence" then
		local ka, kb = a.Keypoints, b.Keypoints
		if #ka ~= #kb then return false end
		for i = 1, #ka do
			if math.abs(ka[i].Time - kb[i].Time) > 0.001 or not closeColor(ka[i].Value, kb[i].Value) then
				return false
			end
		end
		return true
	end
	return false
end

-- ─── Ramp style ─────────────────────────────────────────────────────────────
local function rampValue(p: Palette, v: any): any
	if typeof(v) == "Color3" then return VFXPalettes.MapColor(p, v) end
	if typeof(v) == "ColorSequence" then return VFXPalettes.MapSequence(p, v) end
	return nil
end

-- ─── Ink style ──────────────────────────────────────────────────────────────
local function inkValue(p: Palette, inst: Instance, prop: string): any
	if inst:IsA("ParticleEmitter") then
		return if p.rimTexture then WHITE_SEQ else FLASH_SEQ
	elseif inst:IsA("Beam") or inst:IsA("Trail") then
		return BLACK_SEQ
	elseif inst:IsA("Light") or inst:IsA("Sparkles") then
		return WHITE
	elseif inst:IsA("Highlight") then
		return if prop == "OutlineColor" then WHITE else BLACK
	elseif inst:IsA("Fire") then
		return if prop == "SecondaryColor" then WHITE else BLACK
	end
	return BLACK
end

local function scaleSeq(s: NumberSequence, k: number): NumberSequence
	local keys = {}
	for i, kp in ipairs(s.Keypoints) do
		keys[i] = NumberSequenceKeypoint.new(kp.Time, kp.Value * k, kp.Envelope * k)
	end
	return NumberSequence.new(keys)
end

-- A wider white copy under a black beam/trail, kept in sync with it.
local function addRim(inst: Beam | Trail)
	local rim = inst:Clone() :: any
	written[rim] = {} -- never restyle the rim itself
	rim.Name = inst.Name .. "_InkRim"
	rim.Color = WHITE_SEQ
	rim.Texture = "" -- solid band: many VFX textures have black, not clear, backgrounds
	rim.LightEmission = 0
	rim.LightInfluence = 0
	local src = inst :: any
	local function syncWidth()
		if inst:IsA("Beam") then
			rim.Width0 = src.Width0 * RIM_WIDTH + 0.12
			rim.Width1 = src.Width1 * RIM_WIDTH + 0.12
		end
	end
	if inst:IsA("Beam") then
		syncWidth()
		src.ZOffset += 0.05 -- the black beam draws in front of its rim
	else
		-- Trails have no ZOffset: narrow the black trail inside the white one.
		src.WidthScale = scaleSeq(src.WidthScale, 1 / RIM_WIDTH)
	end
	rim.Parent = inst.Parent

	local MIRROR = { Enabled = true, Transparency = true, Attachment0 = true, Attachment1 = true,
		CurveSize0 = true, CurveSize1 = true, Lifetime = true, TextureSpeed = true, Segments = true }
	inst.Changed:Connect(function(prop)
		if prop == "Width0" or prop == "Width1" then
			syncWidth()
		elseif MIRROR[prop] then
			pcall(function() rim[prop] = src[prop] end)
		elseif prop == "Parent" then
			if inst.Parent then rim.Parent = inst.Parent else rim:Destroy() end
		end
	end)
	inst.Destroying:Connect(function() rim:Destroy() end)
end

local function inkSetup(inst: Instance, p: Palette)
	if inst:IsA("ParticleEmitter") then
		-- Additive light would make black particles vanish.
		inst.LightEmission = 0
		inst.LightInfluence = 0
		-- Always swap the texture: glow textures often have black (not clear)
		-- backgrounds that show up as squares once the glow is off.
		inst.Texture = p.rimTexture or SOFT_PUFF
		inst.FlipbookLayout = Enum.ParticleFlipbookLayout.None
	elseif inst:IsA("Beam") or inst:IsA("Trail") then
		addRim(inst :: any);
		(inst :: any).Texture = "";
		(inst :: any).LightEmission = 0;
		(inst :: any).LightInfluence = 0
	elseif inst:IsA("Light") then
		-- Soft white light so the black shapes read against the floor.
		(inst :: any).Brightness = math.min((inst :: any).Brightness, 1.2)
	end
end

-- ─── Restyling ──────────────────────────────────────────────────────────────
local function restyle(inst: Instance, props: { string }, p: Palette)
	-- Once per instance: re-mapping an already-mapped colour would shift it.
	if written[inst] then return end
	local record: { [string]: any } = {}
	written[inst] = record
	local function valueFor(prop: string, current: any): any
		if p.ink then return inkValue(p, inst, prop) end
		return rampValue(p, current)
	end
	if p.ink then inkSetup(inst, p) end
	for _, prop in ipairs(props) do
		local target = valueFor(prop, (inst :: any)[prop])
		if target ~= nil then
			record[prop] = target;
			(inst :: any)[prop] = target
		end
		-- The effect code may set this colour again later (tweens, loops).
		inst:GetPropertyChangedSignal(prop):Connect(function()
			local current = (inst :: any)[prop]
			if same(current, record[prop]) then return end
			local again = valueFor(prop, current)
			if again ~= nil then
				record[prop] = again;
				(inst :: any)[prop] = again
			end
		end)
	end
end

-- ─── Contours ───────────────────────────────────────────────────────────────
local function contourActive(owner: Player?): boolean
	-- The shared group is outlined for the local player's variant.
	local p = paletteOf(owner or localPlayer)
	return p ~= nil and p.ink == true
end

local function addContour(model: Instance, owner: Player?)
	local h = Instance.new("Highlight")
	h.Name = "InkContour"
	h.FillTransparency = 1
	h.OutlineColor = WHITE
	h.OutlineTransparency = 0
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Adornee = model
	h.Enabled = contourActive(owner)
	written[h] = {} -- not an effect to restyle
	h.Parent = model
	contours[h] = owner
	h.Destroying:Connect(function() contours[h] = nil end)
end

local function refreshContours()
	for h, owner in pairs(contours) do
		h.Enabled = contourActive(owner)
	end
end

-- ─── Ownership ──────────────────────────────────────────────────────────────
local function positionOf(inst: Instance): Vector3?
	local node: Instance? = inst
	while node and node ~= root do
		if node:IsA("BasePart") then return node.Position end
		if node:IsA("Attachment") then return node.WorldPosition end
		node = node.Parent
	end
	return nil
end

local function ownerOf(inst: Instance): Player?
	-- Walk up to the effect's top-level instance (a direct child of the root).
	local top = inst
	while top.Parent and top.Parent ~= root do
		top = top.Parent :: Instance
	end
	local ownerId = top:GetAttribute("VFXOwner")
	if typeof(ownerId) == "number" then
		return Players:GetPlayerByUserId(ownerId)
	end
	local cached = topOwner[top]
	if cached then return cached end

	local players = Players:GetPlayers()
	local owner: Player? = nil
	if #players == 1 then
		owner = players[1]
	else
		local pos = positionOf(inst)
		if not pos then return nil end
		local best = math.huge
		for _, plr in ipairs(players) do
			local char = plr.Character
			if char then
				local d = (char:GetPivot().Position - pos).Magnitude
				if d < best then
					best, owner = d, plr
				end
			end
		end
	end
	if owner then topOwner[top] = owner end
	return owner
end

local function onRootDescendant(inst: Instance)
	if inst:GetAttribute("VFXAnchor") or written[inst] then return end
	local props = propsFor(inst, false)
	if not props then return end
	local p = paletteOf(ownerOf(inst))
	if p then restyle(inst, props, p) end
end

local function watchCharacter(plr: Player, char: Model)
	char.DescendantAdded:Connect(function(inst)
		local p = paletteOf(plr)
		if not p or written[inst] then return end
		-- Not the player's own lighting / outlines / cosmetic cape.
		if inst.Name == "PlayerTorchLight" or inst.Name == "CharacterOutline" or inst:FindFirstAncestor("IceCape") then return end
		local props = propsFor(inst, true)
		if props then restyle(inst, props, p) end
	end)
end

local function watchPlayer(plr: Player)
	if plr.Character then watchCharacter(plr, plr.Character) end
	plr.CharacterAdded:Connect(function(char)
		watchCharacter(plr, char)
	end)
	plr:GetAttributeChangedSignal("Variant"):Connect(refreshContours)
end

-- ─── Roots ──────────────────────────────────────────────────────────────────
-- A Model (so one Highlight can outline the whole group) holding an invisible
-- anchored part at the world origin. Effects hang under that part, not a
-- Folder, because Attachments only work under a BasePart or Terrain; at the
-- origin their Position is their world position, exactly as under Terrain.
local function makeGroup(name: string, parent: Instance, owner: Player?): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = name
	local anchor = Instance.new("Part")
	anchor.Name = "Anchor"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanTouch = false
	anchor.CanQuery = false
	anchor.CastShadow = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.05, 0.05, 0.05)
	anchor.CFrame = CFrame.identity
	anchor:SetAttribute("VFXAnchor", true)
	anchor.Parent = model
	model.PrimaryPart = anchor
	if owner then
		model:SetAttribute("VFXOwner", owner.UserId)
		model:SetAttribute("VFXAnchor", true)
	end
	addContour(model, owner)
	model.Parent = parent
	return model, anchor
end

-- Where ability VFX go (use it wherever the code used Workspace.Terrain).
-- Anything parented here gets its owner's palette.
function VariantFX.Root(): BasePart
	if root and root.Parent and rootModel and rootModel.Parent then return root end
	local model, anchor = makeGroup("AbilityVFX", Workspace.Terrain, nil)
	rootModel, root = model, anchor
	table.clear(ownerRoots)
	anchor.DescendantAdded:Connect(onRootDescendant)
	return anchor
end

-- Like Root(), but for effects whose caster is known exactly.
function VariantFX.RootFor(plr: Player?): BasePart
	local r = VariantFX.Root()
	if not plr then return r end
	local existing = ownerRoots[plr]
	if existing and existing:IsDescendantOf(r) then return existing end
	local _, anchor = makeGroup(`Owner_{plr.UserId}`, r, plr)
	ownerRoots[plr] = anchor
	return anchor
end

-- Restyle a whole effect tree with a player's palette right now (for effects
-- that live outside the root). No-op without a variant.
function VariantFX.Apply(inst: Instance, plr: Player?)
	local p = paletteOf(plr)
	if not p then return end
	for _, d in ipairs(inst:GetDescendants()) do
		local props = propsFor(d, false)
		if props then restyle(d, props, p) end
	end
end

-- A single colour through a player's palette (unchanged without a variant),
-- for things that aren't effect instances, e.g. screen grades.
function VariantFX.ColorFor(plr: Player?, c: Color3): Color3
	local p = paletteOf(plr)
	if not p then return c end
	if p.ink then
		-- Ink: grades go neutral so the scene reads black & white.
		return WHITE
	end
	return VFXPalettes.MapColor(p, c)
end

-- The player whose character is nearest a world position.
function VariantFX.OwnerNear(pos: Vector3): Player?
	local best, owner = math.huge, nil
	for _, plr in ipairs(Players:GetPlayers()) do
		local char = plr.Character
		if char then
			local d = (char:GetPivot().Position - pos).Magnitude
			if d < best then best, owner = d, plr end
		end
	end
	return owner
end

-- Server-made effects tagged "OwnedVFX" with a VFXOwner user id.
local function onOwnedVFX(inst: Instance)
	local ownerId = inst:GetAttribute("VFXOwner")
	local owner = if typeof(ownerId) == "number" then Players:GetPlayerByUserId(ownerId) else nil
	local p = paletteOf(owner)
	if not p then return end
	VariantFX.Apply(inst, owner)
	local props = propsFor(inst, false)
	if props then restyle(inst, props, p) end
	inst.DescendantAdded:Connect(function(d)
		local dp = propsFor(d, false)
		local pal = paletteOf(owner)
		if dp and pal then restyle(d, dp, pal) end
	end)
	if p.ink and (inst:IsA("Model") or inst:IsA("BasePart")) then
		addContour(inst, owner)
	end
end

function VariantFX.Init()
	if started then return end
	started = true
	VariantFX.Root()
	for _, inst in ipairs(CollectionService:GetTagged("OwnedVFX")) do
		onOwnedVFX(inst)
	end
	CollectionService:GetInstanceAddedSignal("OwnedVFX"):Connect(onOwnedVFX)
	for _, plr in ipairs(Players:GetPlayers()) do
		watchPlayer(plr)
	end
	Players.PlayerAdded:Connect(watchPlayer)
	Players.PlayerRemoving:Connect(function(plr)
		local anchor = ownerRoots[plr]
		if anchor and anchor.Parent then anchor.Parent:Destroy() end
		ownerRoots[plr] = nil
	end)
end

return VariantFX
