"""Composite generated textures over a dark floor color for a quick look. Run: python tools/vfx/preview_sheets.py out.jpg name1 name2 ..."""
import sys, os
import numpy as np
from PIL import Image, ImageDraw
from vfxlib import OUT
out, names = sys.argv[1], sys.argv[2:]
tiles = []
for n in names:
    im = np.asarray(Image.open(os.path.join(OUT, n + ".png")).convert("RGBA").resize((512, 512), Image.LANCZOS), np.float32) / 255
    bg = np.ones_like(im[..., :3]) * np.array([0.16, 0.17, 0.20])
    # checker hint like the dungeon floor grid
    yy, xx = np.mgrid[0:512, 0:512]
    bg *= np.where(((xx // 32) + (yy // 32)) % 2 == 0, 1.0, 0.85)[..., None]
    a = im[..., 3:]
    comp = bg * (1 - a) + im[..., :3] * a
    t = Image.fromarray((comp * 255).astype(np.uint8)); ImageDraw.Draw(t).text((6, 4), n, fill=(255, 255, 0))
    tiles.append(t)
cols = min(4, len(tiles)); rows = (len(tiles) + cols - 1) // cols
sheet = Image.new("RGB", (cols * 512, rows * 512))
for i, t in enumerate(tiles):
    sheet.paste(t, ((i % cols) * 512, (i // cols) * 512))
sheet.save(out, quality=90)
