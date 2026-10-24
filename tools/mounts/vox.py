"""Voxel mount GLBs (THREE.GLTFExporter, a node per moving piece, every
vertex in world space on a 1-unit grid, colours per vertex) -> voxels.

  load_pieces(path) -> { piece: { (x, y, z): (r, g, b, glow) } }

A piece is a pivot node ("body", "lFL", "lFL2", "neck", "head", "wingL"...);
its "<name>_mesh" child is solid voxels and "<name>_glow" child glowing ones.
The meshes are shells (only the faces showing): each face names the cell
behind it, so a cell is found from any of its faces.
"""
import os, sys, math
from collections import Counter
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'wings'))
from glb import load


def lin2s(c):
    c = max(0.0, min(1.0, c))
    return round(255 * (12.92 * c if c <= 0.0031308 else 1.055 * c ** (1 / 2.4) - 0.055))


def load_pieces(path):
    j, acc = load(path)
    nodes = j['nodes']
    pieces = {}
    for n in nodes:
        name = n.get('name') or ''
        if 'mesh' not in n:
            continue
        if name.endswith('_mesh'):
            owner, glow = name[:-5], False
        elif name.endswith('_glow'):
            owner, glow = name[:-5], True
        else:
            continue
        cells = pieces.setdefault(owner, {})
        for p in j['meshes'][n['mesh']]['primitives']:
            pos = acc(p['attributes']['POSITION'])
            nor = acc(p['attributes']['NORMAL'])
            col = acc(p['attributes']['COLOR_0']) if 'COLOR_0' in p['attributes'] else None
            idx = acc(p['indices'])
            for t in range(0, len(idx), 3):
                a, b, c = idx[t], idx[t + 1], idx[t + 2]
                cx = [(pos[a][k] + pos[b][k] + pos[c][k]) / 3 for k in range(3)]
                nn = nor[a]
                # the cell behind the face: half a unit in from it
                cell = tuple(math.floor(cx[k] - nn[k] * 0.5 + 0.5) for k in range(3))
                rgb = tuple(lin2s(v) for v in (col[a][:3] if col else (1, 1, 1)))
                old = cells.get(cell)
                # (a cell's faces may be shaded differently: keep the brightest)
                if old is None or (glow and not old[3]) or (old[3] == glow and sum(rgb) > sum(old[:3])):
                    cells[cell] = rgb + (glow,)
    return pieces


def fill(cells):
    """Solid inside: a cell enclosed along all three axes by shell cells."""
    if not cells:
        return dict(cells)
    out = dict(cells)
    xs = [c[0] for c in cells]; ys = [c[1] for c in cells]; zs = [c[2] for c in cells]
    by = {}
    for (x, y, z) in cells:
        by.setdefault(('x', y, z), []).append(x)
        by.setdefault(('y', x, z), []).append(y)
        by.setdefault(('z', x, y), []).append(z)
    for k in by:
        by[k].sort()
    def inside(v, lst):
        return lst and lst[0] < v < lst[-1]
    fillc = (0, 0, 0, False)
    for x in range(min(xs), max(xs) + 1):
        for y in range(min(ys), max(ys) + 1):
            for z in range(min(zs), max(zs) + 1):
                if (x, y, z) in out:
                    continue
                if inside(x, by.get(('x', y, z))) and inside(y, by.get(('y', x, z))) and inside(z, by.get(('z', x, y))):
                    out[(x, y, z)] = None  # hidden: never drawn, only merged through
    return out


def downsample(cells, f):
    """f×f×f blocks -> one voxel: the commonest colour among its shown cells
    (glow wins if a quarter of them glow)."""
    if f == 1:
        return dict(cells)
    blocks = {}
    for c, v in cells.items():
        k = tuple(math.floor(c[i] / f) for i in range(3))
        blocks.setdefault(k, []).append(v)
    out = {}
    for k, vs in blocks.items():
        shown = [v for v in vs if v is not None]
        if len(vs) * 2 < f ** 3 // 2 and not shown:
            continue
        if not shown:
            out[k] = None
            continue
        glows = [v for v in shown if v[3]]
        pool = glows if len(glows) * 4 >= len(shown) else [v for v in shown if not v[3]] or shown
        out[k] = Counter(pool).most_common(1)[0][0]
    return out


def quantize(cells, n):
    """At most n colours per glow/solid: k-means on the colours used."""
    cols = Counter(v for v in cells.values() if v is not None)
    out = {}
    for glow in (False, True):
        pts = [(c, w) for c, w in cols.items() if c[3] == glow]
        if not pts:
            continue
        k = min(n, len(pts))
        cent = [p[0][:3] for p in sorted(pts, key=lambda p: -p[1])[:k]]
        for _ in range(12):
            sums = [[0, 0, 0, 0] for _ in cent]
            for c, w in pts:
                i = min(range(len(cent)), key=lambda i: sum((c[q] - cent[i][q]) ** 2 for q in range(3)))
                for q in range(3):
                    sums[i][q] += c[q] * w
                sums[i][3] += w
            cent = [tuple(round(s[q] / s[3]) for q in range(3)) if s[3] else cent[i] for i, s in enumerate(sums)]
        for c, w in pts:
            i = min(range(len(cent)), key=lambda i: sum((c[q] - cent[i][q]) ** 2 for q in range(3)))
            out[c] = cent[i] + (glow,)
    return {k: (out[v] if v is not None else None) for k, v in cells.items()}


def boxes(cells):
    """Greedy 3D boxes of one colour each; hidden (None) cells join any box."""
    left = {k: v for k, v in cells.items() if v is not None}
    hidden = {k for k, v in cells.items() if v is None}
    used = set()
    out = []
    def ok(c, col):
        return (c in left and left[c] == col and c not in used) or (c in hidden and c not in used)
    for k in sorted(left, key=lambda c: (c[1], c[2], c[0])):
        if k in used:
            continue
        col = left[k]
        x0, y0, z0 = k
        x1 = x0
        while ok((x1 + 1, y0, z0), col): x1 += 1
        z1 = z0
        while all(ok((x, y0, z1 + 1), col) for x in range(x0, x1 + 1)): z1 += 1
        y1 = y0
        while all(ok((x, y1 + 1, z), col) for x in range(x0, x1 + 1) for z in range(z0, z1 + 1)): y1 += 1
        for x in range(x0, x1 + 1):
            for y in range(y0, y1 + 1):
                for z in range(z0, z1 + 1):
                    used.add((x, y, z))
        out.append((x0, y0, z0, x1, y1, z1, col))
    return out


if __name__ == '__main__':
    for path in sys.argv[1:]:
        ps = load_pieces(path)
        allc = {}
        for name, cells in ps.items():
            for c, v in cells.items():
                allc[c] = v
        xs = [c[0] for c in allc]; ys = [c[1] for c in allc]; zs = [c[2] for c in allc]
        print('==', os.path.basename(path), 'cells', len(allc), 'bbox x', min(xs), max(xs), 'y', min(ys), max(ys), 'z', min(zs), max(zs),
              'colours', len(set(allc.values())))
        for f in (1, 2, 3):
            for q in (0, 16, 10):
                tot = 0
                for name, cells in ps.items():
                    c = downsample(fill(cells), f)
                    if q:
                        c = quantize(c, q)
                    tot += len(boxes(c))
                print(f'  /{f} q{q or "-"}: {tot} parts')
