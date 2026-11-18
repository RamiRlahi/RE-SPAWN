"""Generates assets/vfx/generated/slash_crescent_4x4.png (16-frame Grid4x4 flipbook). Run: python3 tools/vfx/make_slash_crescent.py"""
import numpy as np
from PIL import Image
S = 256
yy, xx = np.mgrid[0:S, 0:S].astype(np.float32)
dx, dy = (xx-S*0.5)/S, (yy-S*0.56)/S
r = np.sqrt(dx*dx+dy*dy)
ang = np.arctan2(-dy, dx)
ang = np.where(ang < -np.pi/2, ang+2*np.pi, ang)        # range [-pi/2, 3pi/2): the upper arc is continuous
def sm(e0, e1, x):
    t = np.clip((np.asarray(x)-e0)/(e1-e0), 0, 1); return t*t*(3-2*t)
def lines(freq, seed):                                    # radial grain = brush bristles along the stroke
    g = np.random.default_rng(seed).random(1024).astype(np.float32)
    i = (r*freq) % 1023; i0 = i.astype(int); f = i-i0
    return g[i0]*(1-f)+g[i0+1]*f
b1, b2, b3 = lines(900, 1), lines(2200, 2), lines(400, 3)
def stroke(R0, W, head, tail, d_noise):
    a = np.clip((ang-tail)/max(head-tail, 1e-3), 0, 1)
    inside = (ang >= tail) & (ang <= head)
    w = W*np.sin(np.pi*np.clip(a*0.92+0.04, 0, 1))**0.8   # fat belly, needle tips
    d = (r-R0)/np.maximum(w, 1e-4)                        # signed: <0 inside edge, >0 outside edge
    m = np.where(inside, 1-sm(0.7, 1.0, np.abs(d)+d_noise), 0)
    return m, d, a, inside
N, frames = 16, []
for k in range(N):
    t = k/(N-1)
    head = -0.35 + (np.pi+0.75)*sm(0.0, 0.4, t)           # sweeps right -> over the top -> left
    tail = -0.35 + (np.pi+0.65)*sm(0.22, 0.95, t)         # tail chases it: stroke thins to nothing
    tail = min(tail, head-0.02)
    thin = 1-0.55*sm(0.5, 1.0, t)
    main, d, a, ins = stroke(0.36, 0.10*thin, head, tail, 0.35*(1-b1))
    wisp1, *_ = stroke(0.43, 0.022*thin, head-0.25, max(tail, head-1.6), 0.6*(1-b2))
    wisp2, *_ = stroke(0.29, 0.016*thin, head-0.45, max(tail, head-1.2), 0.6*(1-b3))
    lead = sm(0.55, 1.0, a)                                # bright leading edge, dimmer tail
    outer = np.where(ins, sm(-0.1, 0.55, d), 0)            # outer edge is the hot cutting edge
    hot = main*(0.5+0.5*outer)*(0.55+0.45*lead)*(0.88+0.12*b1)
    dark = main*(1-sm(-0.9, -0.1, d))*0.55                 # inner side darkens: the dark-core contrast
    wisps = np.clip(wisp1*0.8+wisp2*0.6, 0, 1)
    flash = sm(0.12, 0.25, t)*(1-sm(0.25, 0.5, t))
    fade = 1-sm(0.75, 1.0, t)
    alpha = np.clip(main*0.95 + wisps*0.8, 0, 1)*fade
    lum = np.clip(hot*1.7 + wisps*0.9 + flash*hot*0.6 - dark*0.8, 0, 1)**0.7
    rgb = np.repeat(lum[..., None], 3, -1)   # neutral: Roblox tints it with Color
    frames.append(np.dstack([rgb*255, alpha*255]).astype(np.uint8))
sheet = np.zeros((S*4, S*4, 4), np.uint8)
for k, f in enumerate(frames):
    sheet[(k//4)*S:(k//4+1)*S, (k%4)*S:(k%4+1)*S] = f
Image.fromarray(sheet, "RGBA").save("/home/user/RE-SPAWN/assets/vfx/generated/slash_crescent_4x4.png")
