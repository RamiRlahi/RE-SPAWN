"""Generates the RE-SPAWN VFX texture library into assets/vfx/generated/.
Run: python tools/vfx/make_library.py [name ...]   (no names = everything)
Timing follows docs/vfx-reference-timing.md: frame 0 is already strong, a 2-frame flash, burst over ~8 frames, long fade.
"""
import sys
import numpy as np
from vfxlib import sm, ramp, noise, fbm, polar, sample_polar, rgba, save, save_sheet

TAU = 2 * np.pi


def wrap(a):
    return (a + np.pi) % TAU - np.pi


# ---------------------------------------------------------------- slash crescent (Grid4x4, 16 frames)
def slash(pal):
    S, N = 256, 16
    r, ang, dx, dy = polar(S, 0.5, 0.58)
    ang = np.where(ang < -np.pi / 2, ang + TAU, ang)
    streak = sample_polar(fbm((128, 512), 64, 3, 3, aniso=(1, 14)), r, ang)      # long strands along the stroke
    streak2 = sample_polar(fbm((128, 512), 96, 9, 2, aniso=(1, 20)), r, ang)
    frames = []
    for k in range(N):
        t = k / (N - 1)
        head = -0.35 + (np.pi + 0.75) * (0.55 + 0.45 * sm(0.0, 0.14, t))   # frame 0 already shows most of the arc
        tail = -0.35 + (np.pi + 0.70) * sm(0.18, 0.92, t)
        tail = min(tail, head - 0.05)
        R0, W = 0.345 + 0.03 * t, 0.115 * (1 - 0.45 * sm(0.35, 1, t))
        a = np.clip((ang - tail) / max(head - tail, 1e-3), 0, 1)
        inside = (ang >= tail) & (ang <= head)
        w = W * np.sin(np.pi * np.clip(a * 0.94 + 0.03, 0, 1)) ** 0.7
        d = (r - R0) / np.maximum(w, 1e-4)                            # -1 inner edge .. +1 outer (cutting) edge
        # frayed brush edge: the inner edge tears into strands much more than the cutting edge
        edge_n = np.where(d < 0, 0.75, 0.30) * (streak - 0.5) + np.where(d < 0, 0.35, 0.1) * (streak2 - 0.5)
        body = np.where(inside, sm(1.0, 0.82, np.abs(d) + edge_n), 0)
        lead = sm(0.45, 1.0, a)
        T = 0.62 + 0.40 * sm(0.30, 0.85, d) * (0.55 + 0.45 * lead)     # white-hot outer edge
        T -= 0.80 * sm(0.20, -0.45, d)                                 # dark inner core (wide enough to survive bloom)
        T -= 0.45 * sm(0.58, 0.70, streak2) * sm(0.6, -0.2, d)         # dark strands through the body
        T += 0.25 * sm(0.62, 0.80, streak) * sm(-0.3, 0.4, d)          # hot strands
        T -= 0.22 * (1 - a) + 0.30 * sm(0.35, 1.0, t)                  # tail and age cool down
        dissolve = sm(0.45, 1.0, t) * 0.9 + (1 - a) * 0.25 * sm(0.2, 0.6, t)
        alpha = body * sm(dissolve - 0.05, dissolve + 0.15, streak * 0.8 + 0.25)
        # two thin hot wisps riding outside / inside the main stroke
        for off, ww, sd in ((0.075, 0.010, 0.55), (-0.07, 0.008, 0.40)):
            win = (ang >= max(tail, head - 1.9)) & (ang <= head - 0.15)
            dw = np.abs(r - (R0 + off)) / ww
            wisp = np.where(win, sm(1, 0.3, dw + 0.5 * (1 - streak)), 0) * (1 - sm(0.5, 0.85, t))
            T = np.where(wisp > alpha, 0.92, T); alpha = np.maximum(alpha, wisp * sd * 1.6)
        frames.append(rgba(ramp(T, pal), alpha))
    save_sheet(frames, f"slash_{pal}_4x4", 4)


# ---------------------------------------------------------------- impact starburst flash (Grid2x2: f0 full, f1 stretched, f2 thin, f3 ghost)
def starburst(pal):
    S = 512
    r, ang, dx, dy = polar(S)
    rng = np.random.default_rng(7)
    K = 26
    th = rng.random(K) * TAU
    L = 0.20 + 0.29 * rng.random(K) ** 0.6
    W0 = 0.010 + 0.022 * rng.random(K)
    frames = []
    for k, (lm, wm, am) in enumerate(((1.0, 1.0, 1.0), (1.12, 0.6, 0.85), (1.2, 0.3, 0.45), (1.25, 0.15, 0.15))):
        spikes = np.zeros((S, S), np.float32); T = np.zeros_like(spikes)
        for i in range(K):
            Li, hw = L[i] * lm, W0[i] * wm * np.clip(1 - r / (L[i] * lm), 0, 1) ** 0.9
            dist = np.abs(wrap(ang - th[i])) * r
            m = sm(hw + 0.002, hw * 0.3, dist) * (r < Li)
            spikes = np.maximum(spikes, m)
            T = np.maximum(T, m * (0.70 + 0.30 * (1 - r / Li)))
        core = sm(0.11 * wm + 0.02, 0.0, r)
        ring_r = 0.07 + 0.10 * k
        ring = sm(0.012, 0.0, np.abs(r - ring_r)) * (0.9 if k < 3 else 0.3)
        T = np.maximum(T, np.maximum(core, ring * 0.95))
        alpha = np.clip(np.maximum(spikes, np.maximum(core, ring)), 0, 1) * am
        frames.append(rgba(ramp(T, pal), alpha))
    save_sheet(frames, f"starburst_{pal}_2x2", 2)


# ---------------------------------------------------------------- shockwave ring (Grid4x4)
def ring(pal):
    S, N = 256, 16
    r, ang, dx, dy = polar(S)
    br = sample_polar(fbm((64, 512), 48, 21, 4, aniso=(1, 6)), r, ang)
    seg = sample_polar(fbm((16, 256), 10, 23, 3, aniso=(1, 2)), r, ang)    # coarse: breaks the ring into arcs
    wide = pal == "dust"                                          # dust ring: fat, soft, wispy (polearm f14-17)
    frames = []
    for k in range(N):
        t = k / (N - 1)
        R = 0.06 + 0.40 * (1 - (1 - t) ** 3)
        th = (0.060 if wide else 0.022) * (1 - t) ** 0.7 + 0.004
        d = (r - R) / th                                           # >0 leading edge
        gaps = sm(0.30 + 0.25 * t, 0.50 + 0.25 * t, seg + 0.15 * (br - 0.5))   # gaps open up as it ages
        band = sm(1.0, 0.45, np.abs(d) + 1.4 * (br - 0.5)) * (0.55 + 0.45 * sm(-0.6, 0.6, np.cos(ang - 1.1))) * gaps
        trail = sm(-1.0, -5.0, d) * sm(-14.0, -5.0, d) * 0.40     # smoky dark wake inside the ring
        T = 0.58 + 0.44 * sm(-0.2, 0.7, d) - 0.30 * sm(0.55, 0.75, br) + 0.12 * np.cos(ang - 1.1)
        T = np.where(trail > band, 0.12, T)
        alpha = np.maximum(band, trail * sm(0.3, 0.7, br)) * (1 - sm(0.55, 1.0, t)) * sm(0, 0.06, t + 0.03)
        frames.append(rgba(ramp(T - 0.25 * sm(0.4, 1, t), pal), alpha))
    save_sheet(frames, f"ring_{pal}_4x4", 4)


# ---------------------------------------------------------------- fire puff / explosion billow (Grid4x4): white core -> orange -> dark smoke
def puff(pal):
    """Torn explosion chunk (polearm clip f1462-1478): a cluster of sub-blobs with hard cel edges,
    pale-yellow hot spots, dark brown specks, orange-red torn rims; ends as curly wisps + dark bits."""
    S, N = 256, 16
    G = 512
    nA, nB, nC = fbm((G, G), 5, 31, 5), fbm((G, G), 9, 77, 4), fbm((G, G), 16, 91, 3)
    wx, wy = fbm((G, G), 4, 13, 3) - 0.5, fbm((G, G), 4, 14, 3) - 0.5
    rng = np.random.default_rng(5)
    blobs = [(0.0, 0.0, 0.12, 1.0)] + [(rng.normal(0, 0.12), rng.normal(0, 0.09), rng.uniform(0.04, 0.10), rng.uniform(0.8, 1.3)) for _ in range(11)]
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    X, Y = (xx + 0.5) / S - 0.5, (yy + 0.5) / S - 0.5

    def look(n, x, y):
        return n[np.clip(((y + 0.5) * (G - 1)), 0, G - 1).astype(int), np.clip(((x + 0.5) * (G - 1)), 0, G - 1).astype(int)]

    frames = []
    for k in range(N):
        t = k / (N - 1)
        grow = 0.75 + 0.95 * (1 - (1 - t) ** 2.5)
        warp = 0.05 + 0.10 * t                                       # torn edges get curlier as it ages
        x = X + warp * look(wx, X, Y) * 2; y = Y + warp * look(wy, X, Y) * 2 + 0.05 * t   # drift upward
        dens = np.full((S, S), -9.0, np.float32)
        for bx, by, br, gs in blobs:
            rad = br * grow * gs
            dens = np.maximum(dens, 1 - np.sqrt((x - bx * grow) ** 2 + (y - by * grow) ** 2) / rad)
        sc = 1 / (0.7 + 0.5 * t)
        n1, n2, n3 = look(nA, x * sc, y * sc), look(nB, x * sc, y * sc), look(nC, x * sc, y * sc)
        f = dens + 0.55 * (n1 - 0.5) + 0.20 * (n3 - 0.5)               # strong noise: the cluster tears into chunks
        thr = 0.06 + 0.60 * t ** 1.35
        body = sm(thr, thr + 0.04, f)                                 # hard cel edge, erodes into holes
        # hot spots: noise islands deep inside, big early, gone by mid-life
        hot = sm(0.52, 0.70, n2 + 0.35 * (f - thr)) * sm(thr + 0.05, thr + 0.30, f) * (1 - t) ** 1.2
        T = 0.48 + 0.10 * sm(thr, thr + 0.4, f) + 0.50 * hot            # orange-red rim -> orange -> pale yellow spots
        speck = sm(0.70, 0.74, n3) * sm(thr + 0.06, thr + 0.12, f) * sm(0.05, 0.25, t)
        T = T * (1 - speck) + 0.03 * speck                             # dark brown specks inside the fire
        soot = sm(0.46, 0.30, n2) * sm(0.25, 0.6, t) * sm(thr + 0.03, thr + 0.15, f)   # burnt-out patches go dark brown
        T = T * (1 - soot) + 0.05 * soot
        T -= 0.10 * sm(0.5, 1.0, t)
        # curly wisps: thin iso-lines of the noise just outside the body, they take over as the chunk burns out
        near = sm(thr - 0.30, thr - 0.04, f)
        band = sm(0.03, 0.0, np.abs(n1 - 0.5 - 0.08 * np.sin(n2 * 9))) * near * sm(0.2, 0.5, t) * (1 - sm(0.8, 1.0, t))
        alpha = np.maximum(body, band * 0.85)
        T = np.where(band > body, 0.46, T)
        r = np.sqrt(X * X + Y * Y)
        alpha *= (1 - sm(0.85, 1.0, t)) * sm(0.5, 0.42, r)             # never touches the cell border
        frames.append(rgba(ramp(T, pal), alpha))
    save_sheet(frames, f"puff_{pal}_4x4", 4)


def voronoi_edges(S, n, seed, jitter=1.0):
    rng = np.random.default_rng(seed)
    pts = rng.random((n, 2)).astype(np.float32)
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32) / S
    d = np.full((S, S), 9.0, np.float32); d2 = d.copy()
    for px, py in pts:
        for ox in (-1, 0, 1):                                       # tile so the edges wrap
            for oy in (-1, 0, 1):
                q = (xx - px - ox) ** 2 + (yy - py - oy) ** 2
                d2 = np.where(q < d, d, np.minimum(d2, q)); d = np.minimum(d, q)
    return np.sqrt(d2) - np.sqrt(d)                                  # ~0 on cell edges


# ---------------------------------------------------------------- ground stains (single 512 images, lie flat on the floor)
def scorch():
    S = 512
    r, ang, dx, dy = polar(S)
    rag = sample_polar(fbm((32, 512), 12, 41, 4), r, ang, 1.0)
    R = 0.40 * (0.80 + 0.40 * rag)
    n = fbm((S, S), 10, 43, 5)
    cracks = sm(0.012, 0.0, voronoi_edges(S, 38, 44)) * sm(0.15, 0.45, r / R) * sm(1.0, 0.7, r / R)
    alpha = sm(1.0, 0.55, r / R + 0.35 * (n - 0.5)) * 0.95
    char = np.dstack([0.06 + 0.10 * n, 0.03 + 0.05 * n, 0.02 + 0.03 * n])
    ember = ramp(0.55 + 0.35 * sm(0.9, 0.3, r / R) * n, "fire")
    rim = sm(0.6, 0.95, r / R) * sm(1.05, 0.9, r / R) * sm(0.5, 0.75, n)  # glowing ember rim spots
    e = np.clip(np.maximum(cracks * 0.9, rim * 0.8), 0, 1)[..., None]
    save(rgba(char * (1 - e) + ember * e, np.maximum(alpha, e[..., 0] * alpha)), "stain_scorch")


def frost():
    S = 512
    r, ang, dx, dy = polar(S)
    rng = np.random.default_rng(51)
    rot = 0.4
    x, y = dx * np.cos(rot) - dy * np.sin(rot), dx * np.sin(rot) + dy * np.cos(rot)
    sq = (np.abs(x) ** 3.2 + np.abs(y) ** 3.2) ** (1 / 3.2)            # rounded rotated square like the reference
    n = fbm((S, S), 9, 53, 5)
    edges = sm(0.010, 0.0, voronoi_edges(S, 46, 54))
    fill = sm(0.37, 0.25, sq + 0.12 * (n - 0.5))
    # needle frost spikes beyond the square
    K = 40; th = rng.random(K) * TAU; L = 0.30 + 0.17 * rng.random(K)
    needles = np.zeros((S, S), np.float32)
    for i in range(K):
        hw = 0.006 * np.clip(1 - r / L[i], 0, 1)
        needles = np.maximum(needles, sm(hw + 0.0015, 0, np.abs(wrap(ang - th[i])) * r) * (r < L[i]) * (r > 0.12))
    T = 0.55 + 0.25 * n + 0.35 * edges * fill + 0.4 * needles
    alpha = np.clip(fill * (0.38 + 0.25 * n) + edges * fill * 0.55 + needles * 0.85 + sm(0.36, 0.30, sq) * sm(0.2, 0.36, sq) * 0.35, 0, 1)
    save(rgba(ramp(T, "ice"), alpha), "stain_frost")


def holy():
    S = 512
    r, ang, dx, dy = polar(S)
    ring1 = sm(0.008, 0.0, np.abs(r - 0.42)); ring2 = sm(0.005, 0.0, np.abs(r - 0.34))
    ticks = (sm(0.012, 0.0, np.abs(wrap(ang * 18) / 18) * r) * (r > 0.35) * (r < 0.41))
    star = np.zeros_like(r)
    for k in range(6):                                                # hexagram lines
        a0 = k * TAU / 6
        nx, ny = np.cos(a0), np.sin(a0)
        star = np.maximum(star, sm(0.005, 0.0, np.abs(dx * nx - dy * ny - 0.17)) * (r < 0.34))
    glow = sm(0.45, 0.0, r) * 0.35
    lines = np.clip(ring1 + ring2 + ticks + star * 0.8, 0, 1)
    T = 0.62 + 0.38 * lines
    save(rgba(ramp(T, "holy"), np.maximum(lines, glow)), "stain_holy")


def glow():
    S = 256
    r, *_ = polar(S)
    a = np.exp(-(r / 0.20) ** 2) * sm(0.5, 0.35, r)
    save(rgba(np.ones((S, S, 3), np.float32), a), "glow_soft")
    # flat plateau: the polearm clip tints the whole floor evenly (measured +0.35 R / +0.11 G / +0.04 B on frame 0)
    a = np.exp(-(r / 0.36) ** 5) * sm(0.5, 0.44, r)
    save(rgba(np.ones((S, S, 3), np.float32), a), "glow_wide")


# ---------------------------------------------------------------- ice crystal shards (Grid2x2, use FlipbookMode Random)
def shards():
    S = 512
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32) / S
    rng = np.random.default_rng(61)
    frames = []
    for k in range(4):
        img_T = np.zeros((S, S), np.float32); img_a = np.zeros((S, S), np.float32)
        for j in range(3 if k else 1):                               # one big shard (+ smaller ones in variants)
            cx = 0.5 + (0 if j == 0 else rng.uniform(-0.25, 0.25))
            h = 0.85 if j == 0 else rng.uniform(0.35, 0.55)
            w = (0.11 + 0.05 * k) if j == 0 else rng.uniform(0.05, 0.09)
            tilt = rng.uniform(-0.25, 0.25) if j else (k - 1.5) * 0.06
            base, tip = 0.95, 0.95 - h
            x = xx - cx - tilt * (base - yy)
            v = np.clip((base - yy) / h, 0, 1)                         # 0 base .. 1 tip
            half = w * np.where(v < 0.7, 0.75 + 0.25 * v / 0.7, (1 - v) / 0.3)   # kite: widest at 70 %
            inside = (yy <= base) & (yy >= tip) & (np.abs(x) < half)
            ex = np.abs(x) / np.maximum(half, 1e-4)
            facet = np.where(x < 0, 0.80, 0.52) + 0.15 * v            # lit left facet, darker right facet
            T = np.where(ex > 0.82, 1.0, facet) - 0.25 * sm(0.0, 0.25, (1 - ex)) * (x > 0) * 0.5
            T = np.where(np.abs(x) < 0.004, 0.95, T)                    # bright ridge line
            a = inside * np.where(ex > 0.82, 1.0, 0.82 - 0.2 * (1 - v))
            take = a > img_a
            img_T = np.where(take, T, img_T); img_a = np.where(take, a, img_a)
        frames.append(rgba(ramp(img_T, "ice"), img_a))
    save_sheet(frames, "shards_ice_2x2", 2)


def spark(pal):
    S = 256
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    x, y = (xx + 0.5) / S - 0.5, (yy + 0.5) / S - 0.5
    e = np.sqrt((x / 0.46) ** 2 + (y / 0.035) ** 2)
    tail = sm(-0.5, 0.35, x)                                          # head on the right (+X = velocity)
    T = 0.55 + 0.45 * sm(0.7, 0.1, e) * tail
    a = sm(1.0, 0.3, e) * (0.25 + 0.75 * tail)
    save(rgba(ramp(T, pal), a), f"spark_{pal}")


# ---------------------------------------------------------------- slice smear (Grid2x2): horizontal glitch slices, dark + hot
def smear(pal):
    S = 512
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32) / S
    rng = np.random.default_rng(71)
    bands = [(rng.uniform(0.3, 0.7), rng.uniform(0.004, 0.025), rng.uniform(0.15, 0.48), rng.uniform(-0.1, 0.1), rng.random() < 0.70) for _ in range(16)]   # mostly dark slices (polearm f10-13)
    frames = []
    for k in range(4):
        T = np.zeros((S, S), np.float32); A = np.zeros((S, S), np.float32)
        for cy, h, half, cx, dark in bands:
            cy2, half2 = cy + (cy - 0.5) * 0.25 * k, half * (1 + 0.35 * k)
            m = sm(h, h * 0.4, np.abs(yy - cy2)) * sm(half2, half2 * 0.5, np.abs(xx - 0.5 - cx))
            m *= (1 - 0.3 * k)
            take = m > A
            T = np.where(take, 0.05 if dark else 0.75 + 0.25 * sm(half2 * 0.6, 0, np.abs(xx - 0.5 - cx)), T)
            A = np.maximum(A, m)
        frames.append(rgba(ramp(T, pal), A))
    save_sheet(frames, f"smear_{pal}_2x2", 2)


# ---------------------------------------------------------------- mesh textures (UV-mapped; the meshes are built in tools/blender/build_vfx_meshes.py)
def strip_layers(u, v, w, streak, streak2, pal, dark_strands=0.45, hot_strands=0.25, fray=0.35, hot_edge=(0.30, 0.85)):
    """Three-layer stroke laid out in UV space: u along the stroke (head at u=1), v across (v=1 = hot cutting edge)."""
    d = (v - 0.5) * 2 / np.maximum(w, 1e-4)
    edge_n = np.where(d < 0, fray * 2, fray) * (streak - 0.5)
    body = sm(1.0, 0.80, np.abs(d) + edge_n)
    T = 0.62 + 0.40 * sm(hot_edge[0], hot_edge[1], d)
    T -= 0.80 * sm(-0.35, -0.80, d)                                   # narrow dark core along the inner edge
    T -= dark_strands * sm(0.58, 0.70, streak2) * sm(0.6, -0.2, d)
    T += hot_strands * sm(0.62, 0.80, streak) * sm(-0.3, 0.4, d)
    return body, T


def sweep(pal):
    """Swept-shell texture: a 3D slash band. 1024x256, u along the sweep, v across."""
    H, W = 256, 1024
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    u, v = (xx + 0.5) / W, 1 - (yy + 0.5) / H
    streak = fbm((H, W), 64, 3, 3, aniso=(1, 16)); streak2 = fbm((H, W), 96, 9, 2, aniso=(1, 22))
    w = np.sin(np.pi * np.clip(u * 0.96 + 0.02, 0, 1)) ** 0.6 * (0.55 + 0.45 * u)     # fat near the head
    body, T = strip_layers(u, v, w, streak, streak2, pal)
    T -= 0.25 * (1 - u)                                                              # tail is cooler
    alpha = body * sm(0.0, 0.12, u) * sm(1.0, 0.97, u) * sm(0.05, 0.4, streak * 0.6 + u * 0.7)
    save(rgba(ramp(T, pal), alpha), f"sweep_{pal}")


def ribbon(pal):
    """Tornado ribbon (clip 3): orange body, white-hot strands, heavy dark strands. Tiles in u."""
    H, W = 256, 1024
    yy, xx = np.mgrid[0:H, 0:W].astype(np.float32)
    u, v = (xx + 0.5) / W, 1 - (yy + 0.5) / H
    def tile_fbm(cells, seed, aniso):       # tile in u by blending with a shifted copy
        n = fbm((H, W * 2), cells, seed, 3, aniso=aniso)
        return n[:, :W] * (1 - u) + n[:, W:] * u
    streak, streak2 = tile_fbm(48, 11, (1, 18)), tile_fbm(80, 12, (1, 24))
    w = 0.80 + 0.20 * tile_fbm(6, 13, (1, 1))
    body, T = strip_layers(u, v, w, streak, streak2, pal, dark_strands=0.75, hot_strands=0.35, fray=0.55, hot_edge=(0.70, 0.95))
    holes = sm(0.30, 0.42, tile_fbm(10, 14, (1, 4)))                                  # gaps between ribbon sections
    save(rgba(ramp(T, pal), body * holes), f"ribbon_{pal}")


def cone(pal):
    """Shock cone: u around (tiles), v along the cone; v=1 is the open mouth with a hot rim, fades to the apex."""
    S = 512
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    u, v = (xx + 0.5) / S, 1 - (yy + 0.5) / S
    n = fbm((S, S * 2), 40, 17, 3, aniso=(14, 1)); streak = n[:, :S] * (1 - u) + n[:, S:] * u   # lines along v
    rim = sm(0.80, 0.97, v) * sm(1.0, 0.985, v)
    T = 0.45 + 0.25 * streak + 0.45 * rim - 0.35 * sm(0.4, 0.0, v)
    alpha = np.clip(sm(0.05, 0.75, v) * sm(0.52, 0.78, streak + 0.22 * v) * 0.85 + rim, 0, 1) * sm(1.0, 0.99, v)
    save(rgba(ramp(T, pal), alpha), f"cone_{pal}")


def facet(pal):
    """Crystal facet: v up the crystal (deep at the base -> white tip), white rims on both u edges."""
    S = 256
    yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
    u, v = (xx + 0.5) / S, 1 - (yy + 0.5) / S
    n = fbm((S, S), 8, 61, 3)
    rim = np.maximum(sm(0.10, 0.0, u), sm(0.90, 1.0, u))
    crack = sm(0.012, 0.0, np.abs(u - 0.35 - 0.2 * v - 0.05 * (n - 0.5)))             # one internal fracture line
    T = 0.40 + 0.40 * v + 0.15 * n + 0.45 * rim + 0.3 * crack
    alpha = 0.78 + 0.22 * np.maximum(rim, crack)
    save(rgba(ramp(T, pal), alpha), f"facet_{pal}")


JOBS = {
    "sweep": lambda: [sweep(p) for p in ("fire", "ice", "holy", "void")],
    "ribbon": lambda: [ribbon(p) for p in ("fire", "ice", "void")],
    "cone": lambda: [cone(p) for p in ("fire", "ice", "holy", "void")],
    "facet": lambda: [facet(p) for p in ("ice", "void", "holy")],
    "slash": lambda: [slash(p) for p in ("fire", "ice", "holy", "void")],
    "starburst": lambda: [starburst(p) for p in ("fire", "ice", "holy", "void")],
    "ring": lambda: [ring(p) for p in ("fire", "ice", "holy", "void", "dust")],
    "puff": lambda: [puff(p) for p in ("fire", "ice", "void")],
    "stains": lambda: (scorch(), frost(), holy(), glow()),
    "shards": shards,
    "spark": lambda: [spark(p) for p in ("fire", "ice", "holy", "void")],
    "smear": lambda: [smear(p) for p in ("fire", "ice", "void")],
}
if __name__ == "__main__":
    for name in (sys.argv[1:] or JOBS):
        JOBS[name](); print("built", name)
