import json, struct, sys
from collections import Counter

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
    return j, acc

if __name__ == '__main__':
    j, acc = load(sys.argv[1])
    m = j['meshes'][0]
    for p in m['primitives']:
        pos = acc(p['attributes']['POSITION'])
        jo = acc(p['attributes']['JOINTS_0'])
        idx = acc(p['indices'])
        mat = j['materials'][p['material']]['name']
        # union-find over triangles sharing a vertex position
        par = {}
        def find(x):
            while par.setdefault(x, x) != x:
                par[x] = par[par[x]]; x = par[x]
            return x
        key = lambda i: tuple(round(c, 4) for c in pos[i])
        for t in range(0, len(idx), 3):
            a, b2, c = (key(idx[t + q]) for q in range(3))
            par[find(b2)] = find(a); par[find(c)] = find(a)
        groups = {}
        for i in set(idx):
            groups.setdefault(find(key(i)), []).append(i)
        sizes = Counter()
        for g in groups.values():
            xs = [pos[i] for i in g]
            mn = [min(v[k] for v in xs) for k in range(3)]
            mx = [max(v[k] for v in xs) for k in range(3)]
            sizes[(len(g), tuple(round(mx[k] - mn[k], 3) for k in range(3)))] += 1
        print(mat, len(idx) // 3, 'tris', len(groups), 'groups', sizes.most_common(6))
    print([a.get('name') for a in j.get('animations', [])], [ (c['target']) for a in j.get('animations', []) for c in a['channels']][:12])
