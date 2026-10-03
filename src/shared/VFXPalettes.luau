--!strict
--[[
	VFXPalettes
	Colour schemes that VFX variants apply to ability effects. Every colour is
	mapped by its brightness onto a low → mid → high ramp, so bright cores stay
	bright, dark smoke stays dark, and only the hue family changes.

	  contrast  >1 pushes colours towards the ends of the ramp
	  bias      shifts everything darker (<0) or brighter (>0)

	ink = true switches to an ink style instead of the ramp (see VariantFX):
	effects turn black with a white contour and only a small white core.
	  rimTexture  particle texture with a white core, black body and white
	              rim (assets/vfx/dark_particle.png, uploaded to Roblox). Until
	              it's set, particles just flash white and turn black.
--]]

export type Palette = {
	low: Color3,
	mid: Color3,
	high: Color3,
	contrast: number,
	bias: number,
	ink: boolean?,
	rimTexture: string?,
}

local VFXPalettes = {}

VFXPalettes.Palettes = {
	dark = {
		low = Color3.fromRGB(0, 0, 0),
		mid = Color3.fromRGB(120, 120, 120),
		high = Color3.fromRGB(255, 255, 255),
		contrast = 1.7,
		bias = -0.04,
		ink = true,
		-- Upload assets/vfx/dark_particle.png and paste its id here, e.g.
		-- "rbxassetid://123456789".
		rimTexture = nil,
	},
} :: { [string]: Palette }

function VFXPalettes.Get(id: string?): Palette?
	return if id then VFXPalettes.Palettes[id] else nil
end

-- Perceived brightness of an emissive colour: half luminance, half the
-- brightest channel, so saturated reds/blues still read as bright.
local function brightness(c: Color3): number
	local lum = 0.299 * c.R + 0.587 * c.G + 0.114 * c.B
	return 0.5 * lum + 0.5 * math.max(c.R, c.G, c.B)
end

function VFXPalettes.MapColor(p: Palette, c: Color3): Color3
	local t = math.clamp((brightness(c) - 0.5) * p.contrast + 0.5 + p.bias, 0, 1)
	if t < 0.5 then
		return p.low:Lerp(p.mid, t / 0.5)
	end
	return p.mid:Lerp(p.high, (t - 0.5) / 0.5)
end

function VFXPalettes.MapSequence(p: Palette, s: ColorSequence): ColorSequence
	local keys = {}
	for i, k in ipairs(s.Keypoints) do
		keys[i] = ColorSequenceKeypoint.new(k.Time, VFXPalettes.MapColor(p, k.Value))
	end
	return ColorSequence.new(keys)
end

return VFXPalettes
