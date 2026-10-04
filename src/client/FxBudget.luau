--!strict
--[[
	FxBudget.luau
	One budget for every effect the client draws, so no build (a Gunslinger
	with a stack of Projectile and Ricochet tomes, a party of four casting at
	once) can spam the frame rate away.

	  FxBudget.Allow(key, perSecond, burst?) → boolean
	      a token bucket per kind of effect: at most `perSecond` a second,
	      `burst` at once (default perSecond / 4). Say no: the effect is
	      skipped (the damage still happens; only its picture is dropped).
	  FxBudget.Light() → boolean
	      may another short-lived effect light be made? (lights are the
	      priciest effect: only MAX_LIGHTS at once). VfxDetail also enforces
	      this on every effect light that appears, from any class.
	  FxBudget.Pressure() → 0..1
	      how hard the frame rate is struggling (0 above ~50 fps, 1 at ~25):
	      every budget shrinks with it, so a slow machine draws fewer.

	Effects to spend the budget on: the hot paths (hit impacts, ricochet hops,
	damage numbers, the Gunslinger's shots). Things you must see (a boss's
	attack, an enemy projectile, a warning) never ask: they're always drawn.
--]]

local RunService = game:GetService("RunService")

local FxBudget = {}

local MAX_LIGHTS = 10 -- short-lived effect lights alive at once (fewer under pressure)

-- ── Frame pressure ──────────────────────────────────────────────────────────
local frameTime = 1 / 60
local pressure = 0
RunService.Heartbeat:Connect(function(dt)
	frameTime += (math.min(dt, 0.25) - frameTime) * 0.1 -- smoothed
	-- 50 fps → 0, 25 fps → 1
	pressure = math.clamp((frameTime - 1 / 50) / (1 / 25 - 1 / 50), 0, 1)
end)

function FxBudget.Pressure(): number
	return pressure
end

-- The share of each budget still on offer (a quarter at full pressure).
local function scale(): number
	return 1 - 0.75 * pressure
end

-- ── Token buckets ───────────────────────────────────────────────────────────
type Bucket = { tokens: number, at: number }
local buckets: { [string]: Bucket } = {}

function FxBudget.Allow(key: string, perSecond: number, burst: number?): boolean
	local now = os.clock()
	local k = scale()
	local cap = math.max(1, (burst or math.max(2, perSecond / 4)) * k)
	local b = buckets[key]
	if not b then
		b = { tokens = cap, at = now }
		buckets[key] = b
	end
	b.tokens = math.min(cap, b.tokens + (now - b.at) * perSecond * k)
	b.at = now
	if b.tokens < 1 then return false end
	b.tokens -= 1
	return true
end

-- ── Effect lights ───────────────────────────────────────────────────────────
local lights: { [Instance]: boolean } = {}
local lightCount = 0

local function maxLights(): number
	return math.max(3, math.floor(MAX_LIGHTS * scale() + 0.5))
end

-- May another effect light be made right now?
function FxBudget.Light(): boolean
	return lightCount < maxLights()
end

-- Count `light` against the budget until it's gone; false (and it's switched
-- off) when the budget is already spent.
function FxBudget.TrackLight(light: Light): boolean
	if lights[light] then return true end
	if lightCount >= maxLights() then
		light.Enabled = false
		return false
	end
	lights[light] = true
	lightCount += 1
	local conn: RBXScriptConnection? = nil
	conn = light.AncestryChanged:Connect(function()
		if light:IsDescendantOf(game) then return end
		if lights[light] then
			lights[light] = nil
			lightCount -= 1
		end
		if conn then conn:Disconnect() end
	end)
	return true
end

return FxBudget
