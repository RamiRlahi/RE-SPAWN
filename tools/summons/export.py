"""Summoner beast GLBs -> src/client/Summons/Models/<Name>.luau

  python -I tools/summons/export.py

Each GLB (glbkit / "Rockborn builder") is one rigidly skinned mesh made of
boxes (36 vertices, 8 corners) and square pyramids (18 vertices, 5 corners:
spikes, horns, beaks, claws), coloured from a palette texture (one flat
colour per shape) with an emissive texture for the glowing ones, on a bone
tree whose bind pose has no rotation, plus one baked animation (the beast's
signature move, 30 fps).

Out comes, in Roblox space (the GLBs face +Z; turned 180 degrees about Y so
they face -Z like every rig here: x -> -x, z -> -z):
  bones  parents first: name, parent index, rest offset from the parent
  parts  per shape: its bone, "B" (Block) or "W" (CornerWedgePart; a pyramid
         is four of them, one per quarter of its base, their apexes meeting
         over the middle), its CFrame relative to the bone (x y z + 3x3),
         size, colour, glow
  anim   the baked move at 15 fps: root translation, per-bone rotations
"""
import os, sys, math, json, struct
from PIL import Image
import io

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', '..')
OUT = os.path.join(ROOT, 'src', 'client', 'Summons', 'Models')
DL = os.path.expanduser('~/Downloads')
NAMES = ['Rockborn', 'Skyfeather', 'Lunari', 'Skyrockorn']
FPS_OUT = 15


def load(path):
    f = open(path, 'rb').read()
    l = struct.unpack('<I', f[12:16])[0]
    j = json.loads(f[20:20 + l])
    off = 20 + l
    bl = struct.unpack('<I', f[off:off + 4])[0]
    b = f[off + 8: off + 8 + bl]

    def acc(i):
        a = j['accessors'][i]
        bv = j['bufferViews'][a['bufferView']]
        o = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
        n = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}[a['type']]
        fmt = {5126: 'f', 5123: 'H', 5125: 'I', 5121: 'B'}[a['componentType']]
        sz = struct.calcsize(fmt)
        stride = bv.get('byteStride', sz * n)
        out = []
        for k in range(a['count']):
            v = struct.unpack_from('<' + fmt * n, b, o + k * stride)
            out.append(v if n > 1 else v[0])
        return out

    def image(i):
        bv = j['bufferViews'][j['images'][i]['bufferView']]
        o = bv.get('byteOffset', 0)
        return Image.open(io.BytesIO(b[o:o + bv['byteLength']])).convert('RGB')
    return j, acc, image


def sub(a, b): return [a[i] - b[i] for i in range(3)]
def add(a, b): return [a[i] + b[i] for i in range(3)]
def mul(a, s): return [x * s for x in a]
def dot(a, b): return sum(a[i] * b[i] for i in range(3))
def cross(a, b): return [a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0]]
def length(a): return math.sqrt(dot(a, a))
def unit(a):
    l = length(a)
    return [x / l for x in a]


def rbx(v):
    """GLB space -> Roblox space (turned to face -Z)"""
    return [-v[0], v[1], -v[2]]


def frame(x_axis, y_axis):
    """Right-handed frame from two perpendicular axes: columns X, Y, Z = X x Y"""
    x = unit(x_axis)
    y = unit(sub(y_axis, mul(x, dot(y_axis, x))))
    z = cross(x, y)
    return x, y, z


def rot_y(deg):
    c, s = round(math.cos(math.radians(deg))), round(math.sin(math.radians(deg)))
    # CFrame.Angles(0, a, 0): columns X = (c, 0, -s), Y = (0, 1, 0), Z = (s, 0, c)
    return [c, 0, -s], [0, 1, 0], [s, 0, c]


def compose(f, g):
    """frame f (columns) times frame g (columns)"""
    fx, fy, fz = f
    out = []
    for col in g:
        out.append(add(add(mul(fx, col[0]), mul(fy, col[1])), mul(fz, col[2])))
    return tuple(out)


def shapes(pos, idx):
    """Triangles grouped into shapes: connected through shared corners."""
    par = list(range(len(pos)))

    def find(x):
        while par[x] != x:
            par[x] = par[par[x]]
            x = par[x]
        return x
    seen = {}
    for t in range(0, len(idx), 3):
        a, b, c = idx[t:t + 3]
        par[find(b)] = find(a)
        par[find(c)] = find(a)
    for i in range(len(pos)):
        k = tuple(round(v, 4) for v in pos[i])
        if k in seen:
            par[find(i)] = find(seen[k])
        else:
            seen[k] = i
    groups = {}
    for t in range(0, len(idx), 3):
        groups.setdefault(find(idx[t]), []).append(tuple(idx[t:t + 3]))
    return list(groups.values())


def split_by_uv(tris, uv):
    """Two shapes touching at a corner were joined: tell them apart by colour."""
    out = {}
    for tri in tris:
        k = tuple(round(v, 3) for v in uv[tri[0]])
        out.setdefault(k, []).append(tri)
    return list(out.values())


def box_of(tris, pos):
    corners = list({tuple(round(v, 5) for v in pos[i]) for t in tris for i in t})
    center = [sum(c[k] for c in corners) / len(corners) for k in range(3)]
    # each face is two right triangles: their two shorter sides are box edges
    dirs = []
    for t in tris:
        p = [pos[i] for i in t]
        e = [sub(p[1], p[0]), sub(p[2], p[1]), sub(p[0], p[2])]
        e.sort(key=length)
        for v in e[:2]:
            if length(v) < 1e-6:
                continue
            u = unit(v)
            for d in dirs:
                if abs(dot(d[0], u)) > 0.999:
                    d[1] = max(d[1], length(v))
                    break
            else:
                dirs.append([u, length(v)])
    dirs.sort(key=lambda d: -abs(d[0][1]))  # the most upright first, as Y
    y_axis, x_axis = dirs[0][0], dirs[1][0]
    if y_axis[1] < 0:
        y_axis = mul(y_axis, -1)
    X, Y, Z = frame(x_axis, y_axis)
    size = []
    for ax in (X, Y, Z):
        proj = [dot(sub(c, center), ax) for c in corners]
        size.append(max(proj) - min(proj))
    return center, (X, Y, Z), size


def pyramid_of(tris, pos):
    U = list({tuple(round(v, 5) for v in pos[i]) for t in tris for i in t})
    for apex in U:
        rest = [q for q in U if q != apex]
        n = cross(sub(rest[1], rest[0]), sub(rest[2], rest[0]))
        if length(n) > 1e-9 and abs(dot(unit(n), sub(rest[3], rest[0]))) < 1e-3:
            break
    c = [sum(q[k] for q in rest) / 4 for k in range(3)]
    n = unit(n)
    h = dot(sub(apex, c), n)
    if h < 0:
        n, h = mul(n, -1), -h
    # base edges: from one corner to its two neighbours (not the far one)
    r0 = rest[0]
    others = sorted(rest[1:], key=lambda q: length(sub(q, r0)))
    e1, e2 = sub(others[0], r0), sub(others[1], r0)
    X, Y, Z = frame(e1, n)
    a = abs(dot(e1, X)) / 2
    b = abs(dot(e2, Z)) / 2
    wedges = []
    # a quarter of the base each; the CornerWedge's apex is over its local
    # (+X, -Z) corner, which must sit over the pyramid's middle
    for sx in (-1, 1):
        for sz in (-1, 1):
            for deg in (0, 90, 180, 270):
                R = rot_y(deg)
                img = add(mul(R[0], 1), mul(R[2], -1))  # local (1, 0, -1)
                if round(img[0]) == -sx and round(img[2]) == -sz:
                    break
            swapped = deg in (90, 270)
            size = [b if swapped else a, h, a if swapped else b]
            local_c = [sx * a / 2, h / 2, sz * b / 2]
            world_c = add(c, add(add(mul(X, local_c[0]), mul(Y, local_c[1])), mul(Z, local_c[2])))
            wedges.append((world_c, compose((X, Y, Z), R), size))
    return wedges


def fmt(x):
    s = ('%.3f' % x).rstrip('0').rstrip('.')
    return '0' if s in ('-0', '') else s


def export(name):
    path = os.path.join(DL, name + '.glb')
    j, acc, image = load(path)
    nodes = j['nodes']
    skin = j['skins'][0]
    joints = skin['joints']
    parent = {}
    for i, n in enumerate(nodes):
        for c in n.get('children', []):
            parent[c] = i
    # bones in parents-first order, from the skeleton root
    order = []

    def walk(i):
        order.append(i)
        for c in nodes[i].get('children', []):
            if c in joints:
                walk(c)
    walk(joints[0])
    bindex = {ni: k for k, ni in enumerate(order)}
    world = {}
    for ni in order:
        t = nodes[ni].get('translation', [0, 0, 0])
        p = parent.get(ni)
        world[ni] = add(world[p], t) if p in world else list(t)

    prim = j['meshes'][0]['primitives'][0]
    pos = acc(prim['attributes']['POSITION'])
    uv = acc(prim['attributes']['TEXCOORD_0'])
    jo = acc(prim['attributes']['JOINTS_0'])
    idx = acc(prim['indices'])
    mat = j['materials'][prim['material']]
    base = image(j['textures'][mat['pbrMetallicRoughness']['baseColorTexture']['index']]['source'])
    emis = image(j['textures'][mat['emissiveTexture']['index']]['source'])

    def sample(img, u, v):
        x = min(img.width - 1, max(0, int(u * img.width)))
        y = min(img.height - 1, max(0, int(v * img.height)))
        return img.getpixel((x, y))

    parts = []
    for group in shapes(pos, idx):
        for tris in split_by_uv(group, uv):
            v0 = tris[0][0]
            bone = joints[jo[v0][0]]
            u, v = uv[v0]
            col = sample(base, u, v)
            e = sample(emis, u, v)
            glow = max(e) > 40
            if glow:
                col = e
            corners = len({tuple(round(x, 4) for x in pos[i]) for t in tris for i in t})
            bw = world[bone]
            if corners == 8:
                pieces = [box_of(tris, pos) + ('B',)]
            elif corners == 5:
                pieces = [w + ('W',) for w in pyramid_of(tris, pos)]
            else:
                raise SystemExit('%s: a shape with %d corners' % (name, corners))
            for (c, R, size, kind) in pieces:
                c = rbx(sub(c, bw))
                R = [rbx(col_) for col_ in R]
                parts.append((bindex[bone], kind, c, R, size, col, glow))

    # the baked move
    anim = j['animations'][0]
    tracks = {}
    length_s = 0
    for ch in anim['channels']:
        s = anim['samplers'][ch['sampler']]
        times = acc(s['input'])
        vals = acc(s['output'])
        length_s = max(length_s, times[-1])
        tracks.setdefault(ch['target']['node'], {})[ch['target']['path']] = (times, vals)

    def at(times, vals, t):
        if t <= times[0]:
            return vals[0]
        for k in range(1, len(times)):
            if t <= times[k]:
                a = (t - times[k - 1]) / (times[k] - times[k - 1])
                return tuple(vals[k - 1][q] + (vals[k][q] - vals[k - 1][q]) * a for q in range(len(vals[k])))
        return vals[-1]
    frames = int(round(length_s * FPS_OUT)) + 1

    L = []
    L.append('-- Generated by tools/summons/export.py from %s.glb (do not edit by hand).' % name)
    L.append('-- Roblox space, facing -Z; studs. Parts: { bone, kind, x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22, sx, sy, sz, r, g, b, glow }')
    L.append('-- (kind "B" Block, "W" CornerWedgePart; the CFrame is relative to the bone; rows of the rotation matrix)')
    L.append('return {')
    L.append('\tname = "%s",' % name)
    L.append('\tbones = {')
    for ni in order:
        p = parent.get(ni)
        t = rbx(nodes[ni].get('translation', [0, 0, 0]))
        L.append('\t\t{ "%s", %s, %s, %s, %s },' % (nodes[ni]['name'], bindex[p] + 1 if p in bindex else 0, fmt(t[0]), fmt(t[1]), fmt(t[2])))
    L.append('\t},')
    L.append('\tparts = {')
    for (b, kind, c, R, size, col, glow) in parts:
        X, Y, Z = R
        rows = [X[0], Y[0], Z[0], X[1], Y[1], Z[1], X[2], Y[2], Z[2]]
        L.append('\t\t{ %d, "%s", %s, %s, %d, %d, %d, %s },' % (
            b + 1, kind, ', '.join(fmt(x) for x in c), ', '.join(fmt(x) for x in rows + list(size)),
            col[0], col[1], col[2], 'true' if glow else 'false'))
    L.append('\t},')
    L.append('\tanim = {')
    L.append('\t\tname = "%s", fps = %d, length = %s, frames = %d,' % (anim['name'], FPS_OUT, fmt(length_s), frames))
    L.append('\t\ttracks = {')
    for ni in order:
        tr = tracks.get(ni)
        if not tr:
            continue
        row = []
        for f in range(frames):
            t = f / FPS_OUT
            if 'rotation' in tr:
                q = at(*tr['rotation'], t)
                ql = math.sqrt(sum(x * x for x in q))
                q = [q[0] / ql, q[1] / ql, q[2] / ql, q[3] / ql]
                q = [-q[0], q[1], -q[2], q[3]]  # the turn about Y
            else:
                q = [0, 0, 0, 1]
            if 'translation' in tr:
                tt = rbx(at(*tr['translation'], t))
                row.append('%s,%s,%s,%s,%s,%s,%s' % tuple(fmt(x) for x in q + tt))
            else:
                row.append('%s,%s,%s,%s' % tuple(fmt(x) for x in q))
        kind = 'qt' if 'translation' in tr else 'q'
        L.append('\t\t\t["%s"] = { "%s", %s },' % (nodes[ni]['name'], kind, ', '.join(row)))
    L.append('\t\t},')
    L.append('\t},')
    L.append('}')
    os.makedirs(OUT, exist_ok=True)
    open(os.path.join(OUT, name + '.luau'), 'w', encoding='utf-8', newline='\n').write('\n'.join(L) + '\n')
    return len(parts), frames


if __name__ == '__main__':
    for n in NAMES:
        print(n, export(n))
