"""Shared helpers for the RE-SPAWN VFX texture generators (numpy + PIL).

Every stroke texture is built from three layers, as in the reference clips:
  hot  - a thin white-hot edge (reads as overexposed),
  body - a saturated colored body,
  core - a dark inner core / dark streaks (only visible with LightEmission < 1).
Colors are baked in per palette, so in Roblox use Color = white, LightEmission 0-0.4 and Brightness 2-5.
"""
import os
import numpy as np
from PIL import Image

OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "vfx", "generated")

# ramp stops: t=0 dark core, 0.35 deep, 0.65 saturated body, 0.88 hot, 1 white
PALETTES = {
    "fire": [(0.00, (0.10, 0.03, 0.02)), (0.30, (0.62, 0.08, 0.02)), (0.60, (1.00, 0.36, 0.04)),
             (0.82, (1.00, 0.72, 0.25)), (1.00, (1.00, 0.98, 0.90))],
    "ice":  [(0.00, (0.02, 0.05, 0.16)), (0.30, (0.06, 0.24, 0.80)), (0.60, (0.25, 0.62, 1.00)),
             (0.82, (0.66, 0.90, 1.00)), (1.00, (0.97, 1.00, 1.00))],
    "holy": [(0.00, (0.16, 0.08, 0.02)), (0.30, (0.70, 0.40, 0.05)), (0.60, (1.00, 0.78, 0.25)),
             (0.82, (1.00, 0.93, 0.62)), (1.00, (1.00, 1.00, 0.95))],
    # the "dark" VFX variant (VFXPalettes.dark, ink = true): black bodies, a white contour, a small white core
    "ink":  [(0.00, (0.00, 0.00, 0.00)), (0.30, (0.01, 0.01, 0.01)), (0.60, (0.05, 0.05, 0.05)),
             (0.80, (0.55, 0.55, 0.55)), (1.00, (1.00, 1.00, 1.00))],
    # the golden Haymaker: deep red edges -> orange -> bright gold body -> pale yellow -> white-hot
    "gold": [(0.00, (0.22, 0.05, 0.02)), (0.30, (0.85, 0.30, 0.04)), (0.60, (1.00, 0.70, 0.12)),
             (0.82, (1.00, 0.90, 0.48)), (1.00, (1.00, 0.99, 0.92))],
    "dust": [(0.00, (0.20, 0.19, 0.19)), (0.30, (0.45, 0.43, 0.42)), (0.60, (0.72, 0.70, 0.69)),
             (0.82, (0.88, 0.87, 0.86)), (1.00, (1.00, 1.00, 1.00))],
    "void": [(0.00, (0.04, 0.00, 0.08)), (0.30, (0.30, 0.04, 0.55)), (0.60, (0.62, 0.22, 1.00)),
             (0.82, (0.86, 0.66, 1.00)), (1.00, (1.00, 0.96, 1.00))],
}


def sm(e0, e1, x):
    t = np.clip((np.asarray(x, np.float32) - e0) / (e1 - e0), 0, 1)
    return t * t * (3 - 2 * t)


def ramp(t, pal):
    stops = PALETTES[pal]
    t = np.clip(t, 0, 1)
    out = np.zeros(t.shape + (3,), np.float32)
    for (t0, c0), (t1, c1) in zip(stops[:-1], stops[1:]):
        m = (t >= t0) & (t <= t1)
        f = ((t - t0) / (t1 - t0))[..., None]
        out = np.where(m[..., None], np.array(c0) * (1 - f) + np.array(c1) * f, out)
    return out


def noise(shape, cells, seed, aniso=(1, 1)):
    """Smooth value noise in [0,1]; aniso stretches the cells (e.g. (1,8) = streaks along axis 1)."""
    rng = np.random.default_rng(seed)
    gy, gx = max(2, int(cells / aniso[0])), max(2, int(cells / aniso[1]))
    g = (rng.random((gy, gx)) * 255).astype(np.uint8)
    im = Image.fromarray(g).resize((shape[1], shape[0]), Image.BICUBIC)
    return np.asarray(im, np.float32) / 255


def fbm(shape, cells, seed, octaves=4, aniso=(1, 1)):
    acc, amp, tot = 0, 1.0, 0
    for o in range(octaves):
        acc = acc + amp * noise(shape, cells * 2 ** o, seed + o * 17, aniso)
        tot += amp; amp *= 0.5
    return acc / tot


def polar(S, cx=0.5, cy=0.5):
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    dx, dy = (xx + 0.5) / S - cx, (yy + 0.5) / S - cy
    return np.sqrt(dx * dx + dy * dy), np.arctan2(-dy, dx), dx, dy


def sample_polar(tex, r, ang, rmax=0.75):
    """Look up a (H,W) texture with u = angle, v = radius; tiles seamlessly in angle."""
    H, W = tex.shape
    u = ((ang / (2 * np.pi)) % 1.0) * (W - 1)
    v = np.clip(r / rmax, 0, 1) * (H - 1)
    return tex[v.astype(int), u.astype(int)]


def rgba(rgb, a):
    return np.dstack([np.clip(rgb, 0, 1), np.clip(a, 0, 1)])


def save_sheet(frames, name, grid):
    S = frames[0].shape[0]
    sheet = np.zeros((S * grid, S * grid, 4), np.float32)
    for k, f in enumerate(frames[: grid * grid]):
        sheet[(k // grid) * S:(k // grid + 1) * S, (k % grid) * S:(k % grid + 1) * S] = f
    save(sheet, name)


def save(img, name):
    os.makedirs(OUT, exist_ok=True)
    # straight alpha: bleed edge colors into transparent pixels so texture filtering never pulls in black fringes
    from PIL import ImageFilter
    img = np.clip(img, 0, 1).copy()
    a = img[..., 3:]
    fill = np.zeros_like(img[..., :3]); wsum = np.zeros_like(a)
    for rad in (2, 6, 16):
        pm = Image.fromarray(((img[..., :3] * a) * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(rad))
        aw = Image.fromarray((a[..., 0] * 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(rad))
        pmv, awv = np.asarray(pm, np.float32) / 255, np.asarray(aw, np.float32)[..., None] / 255
        take = (wsum < 1e-4) & (awv > 1e-3)
        fill = np.where(take, pmv / np.maximum(awv, 1e-3), fill); wsum = np.where(take, 1.0, wsum)
    img[..., :3] = np.where(a > 0.02, img[..., :3], fill)
    Image.fromarray((np.clip(img, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA").save(os.path.join(OUT, name + ".png"))
    return os.path.join(OUT, name + ".png")
