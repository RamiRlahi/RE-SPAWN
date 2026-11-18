# VFX reference timing

Measured frame by frame (1 frame = 1/30 s = 33 ms) from the reference clips. "f0" is the first frame the effect is visible.
The videos live in `assets/vfx/reference/` (git-ignored: they belong to their creators). The Haymaker clip (@fadewhizz) is not measured yet.

## Ice eruption (@itsjustfir3, ground slam)
| Frames | ms | What happens |
|---|---|---|
| before f0 | 0 | No visible wind-up: the burst starts on the impact frame. |
| f0–f1 | 0–66 | **Flash:** a giant white starburst of thin, long spikes (≈3× the final crystal radius) plus a small ring at the base. 2 frames only. |
| f2–f5 | 66–200 | **Bloom:** an overexposed white dome over the impact. Each image is held for 2 frames (animated on twos). |
| f4–f8 | 133–300 | The dome breaks into swirling smoke rings. **Radial crystal spikes** stand on the floor. A **pale frost square** (rotated plane) lights up the ground. |
| f9–f12 | 300–430 | **Crescent rings** sweep sideways around the crystals (thin, white edge, blue body). |
| f13–f30+ | 430–1000+ | The crystals shrink and fade, sparkles rise, and the frost stain lingers for more than 1 s. |

## Ice dash (same clip)
| Frames | ms | What happens |
|---|---|---|
| f0–f3 | 0–130 | A white bloom puff at the start point, held. |
| f4–f11 | 130–400 | A **spiral tunnel** of white swirl rings along the dash path, thinning toward the start. |
| f12–f19 | 400–660 | A white dome flash with spikes at the end point (8 frames). |
| f20–f29 | 660–1000 | It breaks into crystals and sparkles, and fades. |

## Fire polearm (@dearestwindow, Hu Tao-style)
**Spin sweep:**
| Frames | ms | What happens |
|---|---|---|
| −4…−1 | −130…0 | Wind-up pose only, no VFX. |
| f0 | 0 | **The whole floor goes red** (radial glow, ≈2× the weapon reach) on the same frame as a fire crescent with a thin white-hot edge. |
| f1–f3 | 33–100 | The crescent breaks into **fire puffs** along the arc (orange with white-hot cores and dark brown smoke). |
| f4–f9 | 130–300 | The puffs drift and shrink, embers scatter, and the floor glow slowly fades. |
| f10–f13 | 330–430 | **Vanish smear:** horizontal glitch slices (dark and orange streaks) where the character was. |
| f14–f17 | 460–560 | A **white dust ring** on the floor expands and fades. The red floor glow is gone. |

**Side strike:** 1 frame of wind-up. f0 floor glow at full strength plus explosion puffs along the thrust. f1–f7 the puffs grow (white cores). f8–f10 they turn red-orange with dark smoke. f11–f15 slice-smear vanish. The floor glow lasts about 15 frames (500 ms).
**Thrust:** a fire jet plus a **vertical white ring** around the thrust axis that expands and stays for about 8 frames.

## Fire tornado (@brookz34)
- Sustained (lasts ≥ 1.5 s), no single flash frame.
- Layered ribbons: an orange body, white-hot thin strands, and **dark/black strands rotating through it**. The strand pattern changes every frame (fast spin, roughly one full turn every ~10 frames).
- The base sits in a red-orange ground ring and glow. The top flares outward into loose ribbons.

## Rules taken from this
1. Impact = frame 0. The flash or overexposure lasts **2 frames (≈66 ms)**, never longer.
2. The ground stain or glow appears **on frame 0** and outlives the effect (500 ms for fire, 1 s+ for frost).
3. The bloom/dome is held for 2–4 frames (≈100 ms). This is where client hit-stop goes on heavy hits (3 frames ≈ 100 ms).
4. Burst outward over f1–f8 (≈ 250 ms), then a long fade (≈ 300–700 ms) with debris and sparkles.
5. A heavy move ends with a secondary beat: a crescent ring sweep (ice) or a dust ring / slice smear (fire).
