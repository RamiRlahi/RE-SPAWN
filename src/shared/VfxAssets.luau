--!strict
-- VfxAssets: uploaded ids for the generated VFX library (assets/vfx/generated, built by tools/vfx/make_library.py).
-- Colors are baked in (white-hot edge, saturated body, dark core): use Color = white, LightEmission 0-0.4,
-- Brightness 2-5. With LightEmission 1 the dark core disappears.
-- Timing reference: docs/vfx-reference-timing.md.

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
	},
	Starburst = { -- the 2-frame impact flash: frame 0 full, frame 1 stretched, then gone
		fire = tex(124778957891898, Grid2), ice = tex(116124712757646, Grid2),
		holy = tex(103909491253410, Grid2), void = tex(108736960280503, Grid2),
	},
	Ring = {
		fire = tex(122159533258922, Grid4), ice = tex(136796090993461, Grid4),
		holy = tex(121225205120132, Grid4), void = tex(108577760605677, Grid4),
		dust = tex(128344938336380, Grid4),
	},
	Puff = { -- torn explosion chunk: hot spots, dark specks, burns out into soot and wisps
		fire = tex(100268429119543, Grid4), ice = tex(77449138097694, Grid4), void = tex(135474960992465, Grid4),
	},
	Smear = { -- horizontal slice smear for vanishes and dashes (mostly dark)
		fire = tex(87848792446957, Grid2), ice = tex(127315537307334, Grid2), void = tex(89134996800961, Grid2),
	},
	Shards = { ice = tex(81500625997650, Grid2) }, -- use FlipbookMode Random

	-- single images
	Spark = {
		fire = tex(122113185431406), ice = tex(135228299851226),
		holy = tex(110171279803006), void = tex(126636410582753),
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
		holy = tex(93535107522650), void = tex(100260678536018),
	},
	Ribbon = { fire = tex(94942398948049), ice = tex(135154483444429), void = tex(138112570297321) },
	Cone = {
		fire = tex(92609590491142), ice = tex(137532364339685),
		holy = tex(102145269831602), void = tex(128581102431897),
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
	},
	MeshFlip = CFrame.Angles(0, math.pi, 0),
}

return VfxAssets
