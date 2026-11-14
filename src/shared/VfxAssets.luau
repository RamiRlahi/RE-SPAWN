--!strict
-- VfxAssets: uploaded ids for the generated VFX library (assets/vfx/generated, built by tools/vfx/make_library.py).
-- Colors are baked in (white-hot edge, saturated body, dark core): use Color = white, LightEmission 0-0.4,
-- Brightness 2-5. With LightEmission 1 the dark core disappears.
-- Timing reference: docs/vfx-reference-timing.md.
-- `ink` textures are for the "dark" VFX variant (VFXPalettes, ink = true): black bodies, white contour and core.

export type Tex = { id: string, layout: Enum.ParticleFlipbookLayout?, frames: number }

local Grid4 = Enum.ParticleFlipbookLayout.Grid4x4
local Grid2 = Enum.ParticleFlipbookLayout.Grid2x2

local function tex(id: number, layout: Enum.ParticleFlipbookLayout?): Tex
	local frames = if layout == Grid4 then 16 elseif layout == Grid2 then 4 else 1
	return { id = "rbxassetid://" .. id, layout = layout, frames = frames }
end

local VfxAssets = {
	-- flipbooks (ParticleEmitter.FlipbookLayout = layout, FlipbookMode = OneShot)
	Slash = {
		fire = tex(85737562371567, Grid4), ice = tex(105390064358858, Grid4),
		holy = tex(138045017722482, Grid4), void = tex(136138254677823, Grid4),
		ink = tex(101097900856515, Grid4),
	},
	Starburst = { -- the 2-frame impact flash: frame 0 full, frame 1 stretched, then gone
		fire = tex(124778957891898, Grid2), ice = tex(116124712757646, Grid2),
		holy = tex(103909491253410, Grid2), void = tex(108736960280503, Grid2),
		ink = tex(91937940037853, Grid2),
	},
	Ring = {
		fire = tex(122159533258922, Grid4), ice = tex(136796090993461, Grid4),
		holy = tex(121225205120132, Grid4), void = tex(108577760605677, Grid4),
		dust = tex(128344938336380, Grid4), ink = tex(119583197716459, Grid4),
	},
	Puff = { -- torn explosion chunk: hot spots, dark specks, burns out into soot and wisps
		fire = tex(100268429119543, Grid4), ice = tex(77449138097694, Grid4), void = tex(135474960992465, Grid4),
		ink = tex(93867050839297, Grid4),
	},
	Smear = { -- horizontal slice smear for vanishes and dashes (mostly dark)
		fire = tex(87848792446957, Grid2), ice = tex(127315537307334, Grid2), void = tex(89134996800961, Grid2),
		ink = tex(102283554667115, Grid2),
	},
	Shards = { ice = tex(81500625997650, Grid2) }, -- use FlipbookMode Random

	-- single images
	Spark = {
		fire = tex(122113185431406), ice = tex(135228299851226),
		holy = tex(110171279803006), void = tex(126636410582753), ink = tex(139996746871345),
	},
	Stain = { -- ground decals: lie flat on the floor
		scorch = tex(110516639037154), frost = tex(101649129930682), holy = tex(136916385961805),
	},
	Glow = {
		soft = tex(137690613269740), -- white, tint with Color
		wide = tex(87022922342415), -- flat plateau: the frame-0 floor flash (polearm clip)
	},

	-- mesh textures (UV-mapped for assets/vfx/meshes)
	Sweep = {
		fire = tex(88016031448161), ice = tex(127524096722572),
		holy = tex(93535107522650), void = tex(100260678536018), ink = tex(96042285322809),
	},
	Ribbon = { -- torn see-through sheet, flames licking up inside, sharp dark strokes (clip 3 up close)
		fire = tex(125673201559652), ice = tex(121766375847763), void = tex(98026943768330), ink = tex(118392091525801),
	},
	-- the golden Haymaker's mesh textures (tools/blender/build_haymaker.py builds the meshes)
	Hay = {
		shell = tex(139802218322008),   -- hay_dome / hay_arch: glassy, hot rims (u around, v base -> rim)
		torpedo = tex(121995382208212), -- hay_torpedo: gold body, white swirl lines, hot tip
		whirl = tex(74941643073806),    -- hay_whirl: gold blades, hot edges
	},
	Energy = { -- for Beams: yellow-white centre -> orange body -> red-orange edges, tiles along the length (fire vortex ribbons)
		fire = tex(113237224250128), ice = tex(110717495358121), ink = tex(123887379659122),
	},
	Swirl = { -- for the swept_shell crescent: thin swirl streaks (hot inner line, red body, one near-black) - tornado walls
		fire = tex(108818398563039), ice = tex(92034258395145), ink = tex(140258864215292),
	},
	FlameFeather = { -- for Beams: a flame tongue that tiles along the beam; scroll it (TextureSpeed) to lick toward the tip
		fire = tex(76799241893006), ink = tex(85994636811266),
	},
	Cone = {
		fire = tex(129789396861780), ice = tex(105626013421361),
		holy = tex(120775505992999), void = tex(125278046987370), ink = tex(93555159319392),
	},
	Facet = { ice = tex(74962630831879), holy = tex(92432980608906), void = tex(138497103278689) },

	-- meshes from assets/vfx/meshes (imported with Studio's 3D Importer). Checked in Studio:
	--   * Set Transparency to at least 0.02, or the texture's alpha is ignored and the mesh renders solid.
	--   * Each mesh is centred on its part, not on its apex or base.
	--   * shock_cone and dash_tunnel point backwards: the cone's mouth and the tunnel's head are at +Z,
	--     opposite the LookVector. Multiply the CFrame by MeshFlip to aim them forward.
	Mesh = {
		shock_cone = "rbxassetid://123275970789401", -- texture: Cone
		swept_shell = "rbxassetid://106649252909010", -- texture: Sweep (lies flat, +Y up)
		tornado = "rbxassetid://102996136301762", -- texture: Ribbon (stands up along +Y; spin it)
		crystal_cluster = "rbxassetid://137610405880687", -- texture: Facet (stands up along +Y)
		dash_tunnel = "rbxassetid://133294937451535", -- texture: Ribbon or Sweep
		-- the golden Haymaker (tools/blender/build_haymaker.py): punch along the LookVector, centred on their bounds
		hay_fist = "rbxassetid://100415125327956", hay_fist_hull = "rbxassetid://93020626136216",
		hay_torpedo = "rbxassetid://119943798389968", hay_torpedo_hull = "rbxassetid://83458862003119",
		hay_rings = "rbxassetid://117480783142203", hay_dome = "rbxassetid://74478888700448",
		hay_arch = "rbxassetid://140585299943660", hay_ink = "rbxassetid://75901356623828",
		hay_whirl = "rbxassetid://72277467925989",
	},
	MeshFlip = CFrame.Angles(0, math.pi, 0),
}

return VfxAssets
