"""Voxel wing GLBs -> src/client/WingModels.luau (bricks per bone, baked flap)."""
import sys, math, os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from glb import load
from collections import defaultdict, Counter

U = 0.06
FPS = 20
STUDS = 2.3  # studs per GLB unit (before the wing's own size)
# The body in rig space (studs): the rig sits on the back of the torso,
# 0.35 up and 0.08 behind it; nothing of a wing may come in front of z = ZMIN
# while it's over the body (|x| < BODY_X, BODY_Y0 < y < BODY_Y1).
BODY_X, BODY_Y0, BODY_Y1, ZMIN = 2.1, -4.0, 2.2, -0.15

def sub(a, b): return (a[0]-b[0], a[1]-b[1], a[2]-b[2])
def add(a, b): return (a[0]+b[0], a[1]+b[1], a[2]+b[2])
def mul(a, s): return (a[0]*s, a[1]*s, a[2]*s)
def dot(a, b): return a[0]*b[0]+a[1]*b[1]+a[2]*b[2]
def cross(a, b): return (a[1]*b[2]-a[2]*b[1], a[2]*b[0]-a[0]*b[2], a[0]*b[1]-a[1]*b[0])
def norm(a):
    l = math.sqrt(dot(a, a)) or 1
    return (a[0]/l, a[1]/l, a[2]/l)
def lin2s(c):
    c = max(0.0, min(1.0, c))
    return round(255 * (12.92*c if c <= 0.0031308 else 1.055*c**(1/2.4)-0.055))

# ── quaternions / rigid transforms (rot 3x3 rows, pos) ──
def qmat(q):
    x, y, z, w = q
    return ((1-2*(y*y+z*z), 2*(x*y-z*w), 2*(x*z+y*w)),
            (2*(x*y+z*w), 1-2*(x*x+z*z), 2*(y*z-x*w)),
            (2*(x*z-y*w), 2*(y*z+x*w), 1-2*(x*x+y*y)))
def mmul(A, B):
    return tuple(tuple(sum(A[i][k]*B[k][j] for k in range(3)) for j in range(3)) for i in range(3))
def mvec(A, v): return (dot(A[0], v), dot(A[1], v), dot(A[2], v))
def xf(parent, local):
    (R1, p1), (R2, p2) = parent, local
    return (mmul(R1, R2), add(p1, mvec(R1, p2)))
def ry(a):
    c, s = math.cos(a), math.sin(a)
    return ((c, 0, s), (0, 1, 0), (-s, 0, c))
def slerp(a, b, t):
    d = sum(x*y for x, y in zip(a, b))
    if d < 0: b = [-x for x in b]; d = -d
    if d > 0.9995:
        r = [x + (y-x)*t for x, y in zip(a, b)]
    else:
        th = math.acos(d); s = math.sin(th)
        r = [(math.sin((1-t)*th)*x + math.sin(t*th)*y)/s for x, y in zip(a, b)]
    l = math.sqrt(sum(x*x for x in r))
    return [x/l for x in r]
def sample(ch, t):
    ts, vs = ch['t'], ch['v']
    if t <= ts[0]: return list(vs[0])
    if t >= ts[-1]: return list(vs[-1])
    for i in range(len(ts)-1):
        if ts[i] <= t <= ts[i+1]:
            k = (t-ts[i])/(ts[i+1]-ts[i]) if ts[i+1] > ts[i] else 0
            if ch['path'] == 'rotation': return slerp(vs[i], vs[i+1], k)
            return [x + (y-x)*k for x, y in zip(vs[i], vs[i+1])]

def voxels_for_joint(tl, mats):
    """tl: triangles in the joint's bind frame -> (basis, off, {cell: mat}, studs)"""
    hist = Counter(); rep = {}
    for a, b, c, n, mt in tl:
        cr = cross(sub(b, a), sub(c, a)); area = 0.5*math.sqrt(dot(cr, cr))
        s = n if max(n, key=abs) > 0 else mul(n, -1)
        k = tuple(round(x, 2) for x in s)
        hist[k] += area; rep[k] = s
    ks = [k for k, _ in hist.most_common()]
    ax1 = norm(rep[ks[0]]); ax2 = None
    for k in ks[1:]:
        if abs(dot(rep[k], ax1)) < 0.02: ax2 = norm(rep[k]); break
    ax3 = norm(cross(ax1, ax2))
    basis = [ax1, ax2, ax3]
    X = max(basis, key=lambda v: abs(v[0]))
    Y = max([v for v in basis if v is not X], key=lambda v: abs(v[1]))
    if X[0] < 0: X = mul(X, -1)
    if Y[1] < 0: Y = mul(Y, -1)
    Z = cross(X, Y)
    to = lambda p: (dot(p, X), dot(p, Y), dot(p, Z))
    planes = [Counter(), Counter(), Counter()]
    faces = []
    for a, b, c, n, mt in tl:
        ln = to(n)
        ai = max(range(3), key=lambda k: abs(ln[k]))
        if abs(ln[ai]) < 0.995: continue
        A, B, C = to(a), to(b), to(c)
        cr = cross(sub(B, A), sub(C, A)); area = 0.5*math.sqrt(dot(cr, cr))
        faces.append((A, B, C, ai, 1 if ln[ai] > 0 else -1, mt))
        planes[ai][round((A[ai]/U) % 1, 2) % 1] += area
    off = [planes[k].most_common(1)[0][0]*U if planes[k] else 0 for k in range(3)]
    vox = {}; capcells = set()
    for A, B, C, ai, sg, mt in faces:
        f = (A[ai]-off[ai])/U
        o1, o2 = [k for k in range(3) if k != ai]
        if abs(f - round(f)) > 0.08:
            if ai == 2:  # a stud's cap on the back face
                cx = [(A[k]+B[k]+C[k])/3 for k in range(3)]
                capcells.add((math.floor((cx[0]-off[0])/U), math.floor((cx[1]-off[1])/U), sg))
            continue
        plane = round(f)
        cell = plane - 1 if sg > 0 else plane
        pts = [((P[o1]-off[o1])/U, (P[o2]-off[o2])/U) for P in (A, B, C)]
        (x0, y0), (x1, y1), (x2, y2) = pts
        d = (y1-y2)*(x0-x2)+(x2-x1)*(y0-y2)
        if abs(d) < 1e-12: continue
        for u in range(math.floor(min(p[0] for p in pts)), math.ceil(max(p[0] for p in pts))):
            for v in range(math.floor(min(p[1] for p in pts)), math.ceil(max(p[1] for p in pts))):
                x, y = u+0.5, v+0.5
                l0 = ((y1-y2)*(x-x2)+(x2-x1)*(y-y2))/d
                l1 = ((y2-y0)*(x-x2)+(x0-x2)*(y-y2))/d
                if l0 >= -1e-6 and l1 >= -1e-6 and 1-l0-l1 >= -1e-6:
                    idx3 = [0, 0, 0]; idx3[ai] = cell; idx3[o1] = u; idx3[o2] = v
                    k = tuple(idx3)
                    if k not in vox or (mats[mt]['neon'] and not mats[vox[k]]['neon']):
                        vox[k] = mt
    # a stud on each brick whose back (+Z) face is open and carried one
    studs = []
    for (x, y, sg) in capcells:
        col = [k for k in vox if k[0] == x and k[1] == y]
        if not col: continue
        k = max(col, key=lambda c: c[2]) if sg > 0 else min(col, key=lambda c: c[2])
        studs.append((k, sg))
    return (X, Y, Z), off, vox, studs

def merge(vox):
    """Greedy rectangles per z layer and material -> [(x0,y0,z,x1,y1,mat)]"""
    left = dict(vox); out = []
    for k in sorted(vox, key=lambda c: (c[2], c[1], c[0])):
        if k not in left: continue
        mt = left[k]; x0, y0, z = k
        x1 = x0
        while (x1+1, y0, z) in left and left[(x1+1, y0, z)] == mt: x1 += 1
        y1 = y0
        while all((x, y1+1, z) in left and left[(x, y1+1, z)] == mt for x in range(x0, x1+1)): y1 += 1
        for x in range(x0, x1+1):
            for y in range(y0, y1+1): del left[(x, y, z)]
        out.append((x0, y0, z, x1, y1, mt))
    return out

def export(path):
    j, acc = load(path)
    nodes = j['nodes']
    skin = j['skins'][0]; joints = skin['joints']
    ibm = acc(skin['inverseBindMatrices'])
    size = (nodes[0].get('scale') or [1])[0]
    mats = []
    for m in j['materials']:
        pb = m['pbrMetallicRoughness']; bc = pb.get('baseColorFactor', [1, 1, 1, 1])
        em = m.get('emissiveFactor')
        mats.append({'c': [lin2s(x) for x in bc[:3]], 'neon': bool(em and max(em) > 0.05),
                     'alpha': round(1 - bc[3], 2) if m.get('alphaMode') == 'BLEND' else 0})
    tris = defaultdict(list)
    for prim in j['meshes'][0]['primitives']:
        pos = acc(prim['attributes']['POSITION']); jo = acc(prim['attributes']['JOINTS_0'])
        wt = acc(prim['attributes']['WEIGHTS_0']); idx = acc(prim['indices'])
        for t in range(0, len(idx), 3):
            a, b, c = idx[t], idx[t+1], idx[t+2]
            J = jo[a][max(range(4), key=lambda k: wt[a][k])]
            n = norm(cross(sub(pos[b], pos[a]), sub(pos[c], pos[a])))
            tris[joints[J]].append((pos[a], pos[b], pos[c], n, prim['material']))
    # bind position of each joint (ibm translations: pure translation, scale ignored)
    bindpos = {joints[k]: (-ibm[k][12], -ibm[k][13], -ibm[k][14]) for k in range(len(joints))}
    pieces = {}
    for node, tl in tris.items():
        bp = bindpos[node]
        tl = [(sub(a, bp), sub(b, bp), sub(c, bp), n, mt) for a, b, c, n, mt in tl]
        basis, off, vox, studs = voxels_for_joint(tl, mats)
        X, Y, Z = basis
        def at(i, jj, k):  # grid coords -> joint frame
            return add(add(mul(X, off[0] + i*U), mul(Y, off[1] + jj*U)), mul(Z, off[2] + k*U))
        boxes = []
        for x0, y0, z, x1, y1, mt in merge(vox):
            c = at((x0+x1+1)/2, (y0+y1+1)/2, z+0.5)
            boxes.append((c, ((x1-x0+1)*U, (y1-y0+1)*U, U), mt))
        st = [(at(k[0]+0.5, k[1]+0.5, k[2]+0.5 + sg*0.5), sg, vox[k]) for k, sg in studs]
        corners = [at(i+dx, jj+dy, k+dz) for (i, jj, k) in vox for dx in (0, 1) for dy in (0, 1) for dz in (0, 1)]
        pieces[node] = {'basis': basis, 'boxes': boxes, 'studs': st, 'corners': corners, 'n': len(vox),
                        'centers': [at(i+0.5, jj+0.5, k+0.5) for (i, jj, k) in vox]}
    # ── node tree, rest pose, animation ──
    parent = {}
    for i, n in enumerate(nodes):
        for c in n.get('children', []): parent[c] = i
    anims = []
    for a in j.get('animations', []):
        for ch in a['channels']:
            s = a['samplers'][ch['sampler']]
            anims.append({'node': ch['target']['node'], 'path': ch['target']['path'], 't': acc(s['input']), 'v': acc(s['output'])})
    L = max((ch['t'][-1] for ch in anims), default=1)
    N = max(2, round(L*FPS)+1)
    animated = sorted(set(ch['node'] for ch in anims))
    rootIdx = next(i for i, n in enumerate(nodes) if n.get('name') == 'Root')
    sideRoots = {c: (1 if nodes[c]['name'].endswith('_R') else -1) for c in nodes[rootIdx].get('children', [])}
    EXTRA = ('Rift', 'Moon', 'Eclipse', 'Corona', 'Orbit', 'Halo', 'Galaxy', 'Planet', 'Crescent', 'Float')
    extras = {c for c in sideRoots if nodes[c]['name'].startswith(EXTRA)}
    wingRoots = [c for c in sideRoots if c not in extras]
    def subtree(i):
        out = {i}
        for c in nodes[i].get('children', []): out |= subtree(c)
        return out
    subs = {r: subtree(r) for r in sideRoots}
    dz = {}  # extras pushed back to lie on the back, never inside the body
    push = {}
    def local(i, t, yaw):
        n = nodes[i]
        T = list(n.get('translation', [0, 0, 0])); Q = list(n.get('rotation', [0, 0, 0, 1]))
        for ch in anims:
            if ch['node'] == i:
                if ch['path'] == 'rotation': Q = sample(ch, t)
                elif ch['path'] == 'translation': T = sample(ch, t)
        R = qmat(Q)
        if i in yaw and yaw[i]:
            R = mmul(ry(-sideRoots[i]*yaw[i]), R)
        if i in dz: T[2] += dz[i]
        if i in push: T[2] += push[i]
        return (R, tuple(T))
    def world(t, yaw):
        W = {}
        def go(i):
            if i in W: return W[i]
            l = local(i, t, yaw) if i != 0 else (((1, 0, 0), (0, 1, 0), (0, 0, 1)), (0, 0, 0))
            W[i] = xf(go(parent[i]), l) if i in parent else l
            return W[i]
        for i in range(len(nodes)): go(i)
        return W
    times = [k*L/(N-1) for k in range(N)]
    S = STUDS*size
    def worst(W, nodeset, zmin=ZMIN):
        v = 0
        for node in nodeset:
            pc = pieces.get(node)
            if not pc or node == rootIdx: continue
            R, p = W[node]
            for c in pc['corners']:
                w = mul(add(p, mvec(R, c)), S)
                if abs(w[0]) < BODY_X and BODY_Y0 < w[1] < BODY_Y1 and w[2] < zmin:
                    v = max(v, zmin - w[2])
        return v
    for r in extras:
        need = 0
        for t in times[::2]:
            need = max(need, worst(world(t, {}), subs[r], 0.0))
        if need > 0: dz[r] = need / S
    v0 = max(worst(world(t, {}), set(pieces)) for t in times)
    # each wing swept back, frame by frame, just as far as it must be (and
    # what the sweep can't clear -- the root, swinging in round the spine --
    # set back off the body)
    def smooth(seq):
        n = len(seq) - 1  # (the last frame is the first again)
        cyc = seq[:n]
        mx = [max(cyc[(k + d) % n] for d in range(-2, 3)) for k in range(n)]
        sm = [sum(mx[(k + d) % n] for d in range(-2, 3)) / 5 for k in range(n)]
        sm = [max(x, y) for x, y in zip(sm, cyc)]
        return sm + [sm[0]]
    yaws, pushes = {}, {}
    for r in wingRoots:
        ya, pu = [], []
        for t in times:
            best = None
            for a in range(0, 64, 3):
                w = worst(world(t, {r: math.radians(a)}), subs[r])
                if best is None or w < best[1] - 1e-4: best = (a, w)
                if w == 0: break
            ya.append(best[0]); pu.append(best[1] / S + (0.004 if best[1] > 0 else 0))
        yaws[r] = [math.radians(x) for x in smooth(ya)]
        pushes[r] = smooth(pu)
    tuck = max((max(v) for v in yaws.values()), default=0)
    # frames of every animated node (and the swept wings), local, studs
    framed = sorted(set(animated) | set(wingRoots) | set(dz))
    frames = {}
    for i in framed:
        fr = []
        for k, t in enumerate(times):
            push.clear()
            if i in pushes: push[i] = pushes[i][k]
            R, p = local(i, t, {i: yaws[i][k]} if i in yaws else {})
            fr.append((mul(p, S), R))
        frames[i] = fr
    left = 0
    for k, t in enumerate(times):
        push.clear(); push.update({r: pushes[r][k] for r in pushes})
        left = max(left, worst(world(t, {r: yaws[r][k] for r in yaws}), set(pieces)))
    push.clear()
    print('   max push (studs)', round(max((max(v) for v in pushes.values()), default=0) * S, 2))
    print('   left after sweep', round(left, 3), 'extras pushed', {nodes[r]['name']: round(v * S, 2) for r, v in dz.items()})
    # wingtips and the main piece of each side, for particles
    W0 = world(0, {r: yaws[r][0] for r in yaws})
    sides = {}
    for node, pc in pieces.items():
        if node == rootIdx: continue
        R, p = W0[node]
        side = 1 if sum(add(p, mvec(R, c))[0] for c in pc['centers']) > 0 else -1
        far = max(pc['centers'], key=lambda c: abs(add(p, mvec(R, c))[0]))
        reach = abs(add(p, mvec(R, far))[0])
        s = sides.setdefault(side, {'tip': None, 'reach': -1, 'main': None, 'mainN': -1})
        if reach > s['reach']: s.update(tip=(node, mul(far, S)), reach=reach)
        if pc['n'] > s['mainN']:
            cs = pc['centers']
            mn = [min(c[k] for c in cs) for k in range(3)]; mx = [max(c[k] for c in cs) for k in range(3)]
            s.update(main=(node, mul([(mn[k]+mx[k])/2 for k in range(3)], S), mul([mx[k]-mn[k]+U for k in range(3)], S)), mainN=pc['n'])
    return {'nodes': nodes, 'parent': parent, 'pieces': pieces, 'mats': mats, 'S': S, 'L': L, 'N': N,
            'frames': frames, 'tuck': tuck, 'v0': v0, 'sides': sides}

def f(x): return ('%.3f' % x).rstrip('0').rstrip('.').replace('-0', '-0') if abs(x) > 5e-4 else '0'

def luau(name, e):
    S = e['S']; nodes = e['nodes']
    out = [f'\t{name} = {{']
    out.append('\t\tlength = %s, frames = %d,' % (f(e['L']), e['N']))
    out.append('\t\tmats = { ' + ', '.join('{ %d, %d, %d, %s, %s }' % (*m['c'], 'true' if m['neon'] else 'false', f(m['alpha'])) for m in e['mats']) + ' },')
    # nodes: { parent, x, y, z } (rest translation, studs); 1-based, 0 = none
    out.append('\t\tnodes = {')
    for i, n in enumerate(nodes):
        if 'mesh' in n: p = 0
        t = mul(n.get('translation', [0, 0, 0]), S) if i != 0 else (0, 0, 0)
        out.append('\t\t\t{ %d, %s, %s, %s, "%s" },' % (e['parent'][i] + 1 if i in e['parent'] else 0, f(t[0]), f(t[1]), f(t[2]), n.get('name')))
    out.append('\t\t},')
    # animated local frames: node = { x, y, z, r00..r22 per frame }
    out.append('\t\tanim = {')
    for i, fr in e['frames'].items():
        nums = []
        for p, R in fr:
            nums += [p[0], p[1], p[2]] + [R[a][b] for a in range(3) for b in range(3)]
        out.append('\t\t\t[%d] = { %s },' % (i + 1, ', '.join(f(x) for x in nums)))
    out.append('\t\t},')
    # bricks of each bone: { r00..r22 }, boxes { x, y, z, sx, sy, sz, mat }, studs { x, y, z, side, mat }
    out.append('\t\tbones = {')
    for node, pc in e['pieces'].items():
        X, Y, Z = pc['basis']
        R = [X[0], Y[0], Z[0], X[1], Y[1], Z[1], X[2], Y[2], Z[2]]
        bx = []
        for c, sz, mt in pc['boxes']:
            bx += [c[0]*S, c[1]*S, c[2]*S, sz[0]*S, sz[1]*S, sz[2]*S, mt + 1]
        st = []
        for c, sg, mt in pc['studs']:
            st += [c[0]*S, c[1]*S, c[2]*S, sg, mt + 1]
        out.append('\t\t\t[%d] = { rot = { %s },' % (node + 1, ', '.join(f(x) for x in R)))
        out.append('\t\t\t\tboxes = { %s },' % ', '.join(f(x) if isinstance(x, float) else str(x) for x in bx))
        out.append('\t\t\t\tstuds = { %s } },' % ', '.join(f(x) if isinstance(x, float) else str(x) for x in st))
    out.append('\t\t},')
    sd = []
    for side in (1, -1):
        s = e['sides'].get(side)
        if not s: continue
        tn, tp = s['tip']; mn, mc, ms = s['main']
        sd.append('{ side = %d, tip = { %d, %s, %s, %s }, main = { %d, %s, %s, %s, %s, %s, %s } }' % (
            side, tn + 1, f(tp[0]), f(tp[1]), f(tp[2]), mn + 1, f(mc[0]), f(mc[1]), f(mc[2]), f(ms[0]), f(ms[1]), f(ms[2])))
    out.append('\t\tsides = { ' + ', '.join(sd) + ' },')
    out.append('\t},')
    return '\n'.join(out)

if __name__ == '__main__':
    src = r"C:/Users/rami/Downloads"
    # look -> its model in Downloads (the newest copy where there were several)
    FILES = {'raven': 'raven', 'bat': 'bat', 'leaf': 'leaf', 'frost': 'frost', 'storm': 'storm', 'moon': 'moon',
             'venom': 'venom', 'void': 'void', 'dragon': 'dragon', 'cosmic': 'cosmic',
             'celestial': 'celestial_wings_voxel (1)', 'eclipse': 'eclipse_wings_voxel (2)'}
    names = list(FILES)
    parts = []
    for nm in names:
        fn = FILES[nm] if FILES[nm].endswith(')') else f'{FILES[nm]}_wings_voxel'
        e = export(os.path.join(src, fn + '.glb'))
        nb = sum(len(p['boxes']) for p in e['pieces'].values()); ns = sum(len(p['studs']) for p in e['pieces'].values())
        print(nm, 'boxes', nb, 'studs', ns, 'len', e['L'], 'clip', round(e['v0'], 3), 'tuck', round(math.degrees(e['tuck'])), 'S', e['S'])
        parts.append(luau(nm, e))
    d = r"C:/Users/rami/Desktop/RE-SPAWN/src/client/WingModels"
    os.makedirs(d, exist_ok=True)
    old = r"C:/Users/rami/Desktop/RE-SPAWN/src/client/WingModels.luau"
    if os.path.exists(old): os.remove(old)
    for nm, body in zip(names, parts):
        NL = chr(10)
        body = body.split(NL, 1)[1].rsplit(NL, 1)[0]  # (drop "name = {" and its "},")
        body = NL.join(l[1:] for l in body.split(NL))
        open(os.path.join(d, nm + '.luau'), 'w', encoding='utf-8', newline=NL).write(
            '-- Generated from ' + nm + '_wings_voxel.glb (see WingModels/init.luau)' + NL + 'return {' + NL + body + NL + '}' + NL)
    init = """--[[
	WingModels (generated from the voxel wing models, *_wings_voxel.glb)
	WingModels.Get(look) → the wing set's data, or nil if it has no model.
	Each wing set is bricks on bones, flapped by the model's own animation:

	  length, frames   the flap loop (seconds) and its frames, evenly spaced
	  mats             { r, g, b, neon, transparency }
	  nodes            { parent (0 = none), x, y, z, name }: each bone's rest place
	                   on its parent (studs); 1 is the model, the rig's origin
	  anim[bone]       its place on its parent every frame: x, y, z and the
	                   3x3 rotation (rows), 12 numbers a frame (the flap is
	                   swept back, and set off the back, far enough never to
	                   pass through the body)
	  bones[bone]      rot (3x3 rows) of its bricks; boxes { x, y, z, sx, sy,
	                   sz, mat } and studs { x, y, z, side (+1 = the back),
	                   mat } in the bone's own space (studs)
	  sides            per wing: tip { bone, x, y, z } and its biggest bone,
	                   main { bone, centre xyz, size xyz }, for particles
--]]

local WingModels = {}
local cache = {}

function WingModels.Get(look: string): any
	if cache[look] == nil then
		local m = script:FindFirstChild(look)
		cache[look] = if m and m:IsA("ModuleScript") then require(m) :: any else false
	end
	return cache[look] or nil
end

return WingModels
"""
    open(os.path.join(d, 'init.luau'), 'w', encoding='utf-8', newline=chr(10)).write(init)
    print('wrote', d, sorted(os.listdir(d)))
