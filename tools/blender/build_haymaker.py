"""Builds the golden Haymaker's meshes (after @fadewhizz's Sett-style Haymaker clip), exports them for
Roblox and renders golden versions of the clip's key moments beside the clip frames.
Run: blender -b --factory-startup --python tools/blender/build_haymaker.py -- <render_dir> [<clip_sheet.webp>]

Axes: the punch goes along Blender -Y, which is Roblox -Z (a part's LookVector) after export.
Up is Blender +Z (Roblox +Y). Every mesh is unit-sized; Roblox sizes it.
  hay_fist / hay_fist_hull   a clenched fist + forearm, knuckles at -Y; the hull is the dark inverted outline
  hay_torpedo / _hull        the 9.75 body: centred, back at +Y, sharp tip at -Y; u along (0 back..1 tip)
  hay_rings                  three concentric rings facing -Y (the portal at the fist)
  hay_dome                   a hemisphere shell, pole at -Y (turn it pole-up for the charge dome)
  hay_arch                   a sphere band arching across X over the floor, depth along Y (the break-up arches)
  hay_ink                    a curling, twisting ink ribbon rising up +Z and hooking over toward -Y
  hay_whirl                  a flat disk of 8 swept crescent blades on the floor (XY), spinning about +Z
"""
import bpy, bmesh, os, sys, math, random
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
TEX = os.path.join(ROOT, "assets", "vfx", "generated")
OUT = os.path.join(ROOT, "assets", "vfx", "meshes")
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
RENDER = argv[0] if argv else os.path.join(HERE, "renders")
SHEET = argv[1] if len(argv) > 1 else None
os.makedirs(OUT, exist_ok=True); os.makedirs(RENDER, exist_ok=True)
TAU = 2 * math.pi
for o in list(bpy.data.objects): bpy.data.objects.remove(o)


def sm(e0, e1, x):
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3 - 2 * t)


def build(name, faces_fn, smooth=True):
    bm = bmesh.new(); uv = bm.loops.layers.uv.new("UVMap")
    for face in faces_fn():
        vs = [bm.verts.new(p) for p, _ in face]
        f = bm.faces.new(vs)
        for loop, (_, t) in zip(f.loops, face): loop[uv].uv = t
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    for p in me.polygons: p.use_smooth = smooth
    ob = bpy.data.objects.new(name, me); bpy.context.scene.collection.objects.link(ob)
    return ob


def grid(P, nu, nv, closed_u=False):
    for i in range(nu):
        for j in range(nv):
            s0, s1, t0, t1 = i / nu, (i + 1) / nu, j / nv, (j + 1) / nv
            yield [(P(s0, t0), (s0, t0)), (P(s1, t0), (s1, t0)), (P(s1, t1), (s1, t1)), (P(s0, t1), (s0, t1))]


def flipped_hull(src, name, push):
    """A copy pushed out along its normals with flipped faces: seen from outside it draws only its far side,
    which shows as a dark outline round the original (the inverted-hull outline)."""
    me = src.data.copy(); me.name = name
    bm = bmesh.new(); bm.from_mesh(me)
    bm.normal_update()
    for v in bm.verts: v.co += v.normal * push
    bmesh.ops.reverse_faces(bm, faces=bm.faces)
    bm.to_mesh(me); bm.free()
    ob = bpy.data.objects.new(name, me); bpy.context.scene.collection.objects.link(ob)
    return ob


# ── the fist ───────────────────────────────────────────────────────────────
def make_fist():
    parts = []
    def cube(half, at, rot=(0, 0, 0)):
        bpy.ops.mesh.primitive_cube_add(size=2, location=at, rotation=rot)
        o = bpy.context.object; o.scale = half; parts.append(o)
    cube((0.62, 0.45, 0.5), (0, 0, 0))                                   # palm / back of the hand
    for k, x in enumerate((-0.46, -0.155, 0.155, 0.46)):
        drop = 0.04 if k in (0, 3) else 0.0
        cube((0.15, 0.2, 0.17), (x, -0.55, 0.22 - drop))                 # knuckles (front, top)
        cube((0.14, 0.17, 0.16), (x, -0.5, -0.13 - drop))                # folded fingers below them
    cube((0.36, 0.15, 0.14), (0.05, -0.56, -0.42), (0, 0, math.radians(12)))  # thumb across the front
    bpy.ops.mesh.primitive_cylinder_add(radius=0.42, depth=1.7, location=(0, 1.1, -0.05), rotation=(math.radians(90), 0, 0))
    arm = bpy.context.object; arm.scale = (1.05, 1, 0.88); parts.append(arm)  # forearm trailing back
    for o in parts:
        bev = o.modifiers.new("b", "BEVEL"); bev.width = 0.06; bev.segments = 3
    bpy.ops.object.select_all(action="DESELECT")
    for o in parts: o.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.convert(target="MESH")
    bpy.ops.object.join()
    fist = bpy.context.object; fist.name = "hay_fist"
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    rm = fist.modifiers.new("r", "REMESH"); rm.mode = "VOXEL"; rm.voxel_size = 0.03
    sub = fist.modifiers.new("s", "SMOOTH"); sub.iterations = 6; sub.factor = 0.6
    dec = fist.modifiers.new("d", "DECIMATE"); dec.ratio = 0.12
    bpy.ops.object.convert(target="MESH")
    for p in fist.data.polygons: p.use_smooth = True
    bpy.ops.object.mode_set(mode="EDIT"); bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66)); bpy.ops.object.mode_set(mode="OBJECT")
    # centre it on the fist's middle (the forearm trails off behind)
    return fist


fist = make_fist()
fist_hull = flipped_hull(fist, "hay_fist_hull", 0.07)


# ── the torpedo ────────────────────────────────────────────────────────────
def torpedo_P(scale):
    def P(s, t):
        r = 0.16 * math.sqrt(min(s / 0.18, 1.0)) * (1 - s) ** 0.55 * scale
        a = t * TAU
        return Vector((math.cos(a) * r, 0.5 - s, math.sin(a) * r * 0.72))
    return P


torpedo = build("hay_torpedo", lambda: grid(torpedo_P(1.0), 48, 20))
torpedo_hull = build("hay_torpedo_hull", lambda: grid(torpedo_P(1.18), 48, 20))
# (the grid winds inward: the body is turned to face out; the hull keeps facing in, so it draws as an outline)
bm = bmesh.new(); bm.from_mesh(torpedo.data); bmesh.ops.reverse_faces(bm, faces=bm.faces); bm.to_mesh(torpedo.data); bm.free()


# ── rings, dome, arch, ink, whirl ───────────────────────────────────────────
def rings_faces():
    for R, w, y in ((1.0, 0.035, 0.0), (0.72, 0.03, -0.1), (0.46, 0.025, -0.2)):
        def P(s, t, R=R, w=w, y=y):
            a, b = s * TAU, t * TAU
            rr = R + math.cos(b) * w
            return Vector((math.cos(a) * rr, y + math.sin(b) * w, math.sin(a) * rr))
        yield from grid(P, 64, 6)


def dome_P(s, t):
    az, el = s * TAU, t * math.pi / 2
    return Vector((math.cos(az) * math.cos(el), -math.sin(el), math.sin(az) * math.cos(el)))


def arch_P(s, t):
    a = math.pi * s                      # floor (x=+1) up over the top to the floor (x=-1)
    y = (t - 0.5) * 0.7
    k = math.sqrt(max(1 - (y / 1.0) ** 2, 0))
    return Vector((math.cos(a) * k, y, math.sin(a) * k))


def ink_P(s, t):
    c = Vector((0.22 * math.sin(s * 2.6), -0.7 * s * s, math.sin(s * math.pi * 0.7) * 1.0))
    tan = Vector((0.22 * 2.6 * math.cos(s * 2.6), -1.4 * s, math.cos(s * math.pi * 0.7) * math.pi * 0.7)).normalized()
    side0 = tan.cross(Vector((0, 1, 0)))
    side0 = side0.normalized() if side0.length > 1e-4 else Vector((1, 0, 0))
    side = Matrix.Rotation(s * math.pi * 1.2, 3, tan) @ side0
    w = 0.22 * (1 - s) ** 0.7 + 0.015
    return c + side * (t - 0.5) * 2 * w


def whirl_faces():
    for k in range(8):
        a0 = k * TAU / 8
        def P(s, t, a0=a0):
            r = 0.3 + 0.7 * s
            a = a0 + s * 1.1
            w = 0.2 * (1 - s) ** 0.8 * sm(0, 0.12, s) + 0.005
            rad = Vector((math.cos(a), math.sin(a), 0)); tan = Vector((-math.sin(a), math.cos(a), 0))
            return rad * r + tan * (t - 0.5) * 2 * w + Vector((0, 0, 0.002 * k))
        yield from grid(P, 16, 2)


rings = build("hay_rings", rings_faces)
dome = build("hay_dome", lambda: grid(dome_P, 48, 12))
arch = build("hay_arch", lambda: grid(arch_P, 40, 8))
ink = build("hay_ink", lambda: grid(ink_P, 40, 2))
whirl = build("hay_whirl", whirl_faces, smooth=False)

MESHES = [fist, fist_hull, torpedo, torpedo_hull, rings, dome, arch, ink, whirl]
for ob in MESHES:
    bpy.ops.object.select_all(action="DESELECT"); ob.select_set(True); bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.fbx(filepath=os.path.join(OUT, ob.name + ".fbx"), use_selection=True, axis_forward="-Z", axis_up="Y",
                             apply_scale_options="FBX_SCALE_UNITS", mesh_smooth_type="FACE", bake_space_transform=True)
    print("EXPORTED", ob.name, len(ob.data.polygons))

# ── preview: golden versions of the clip's moments ──────────────────────────
sc = bpy.context.scene
for eng in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
    try: sc.render.engine = eng; break
    except TypeError: pass
sc.render.resolution_x, sc.render.resolution_y = 600, 278
sc.view_settings.view_transform = "Standard"
world = bpy.data.worlds.new("w"); sc.world = world; world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.05, 0.04, 0.05, 1)
bpy.ops.mesh.primitive_plane_add(size=300); floor = bpy.context.object
fm = bpy.data.materials.new("floor"); fm.use_nodes = True
fm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.06, 0.045, 0.05, 1); floor.data.materials.append(fm)
sun = bpy.data.lights.new("sun", "SUN"); sun.energy = 2.0; so = bpy.data.objects.new("sun", sun); so.rotation_euler = (0.8, 0, 0.6); sc.collection.objects.link(so)


def mat_tex(name, tex, strength, tint=(1, 1, 1)):
    m = bpy.data.materials.new(name); m.use_nodes = True; nt = m.node_tree; nt.nodes.clear()
    if hasattr(m, "surface_render_method"): m.surface_render_method = "BLENDED"
    m.use_backface_culling = False
    out = nt.nodes.new("ShaderNodeOutputMaterial"); tx = nt.nodes.new("ShaderNodeTexImage")
    tx.image = bpy.data.images.load(os.path.join(TEX, tex + ".png"), check_existing=True); tx.image.alpha_mode = "STRAIGHT"
    mul = nt.nodes.new("ShaderNodeMix"); mul.data_type = "RGBA"; mul.blend_type = "MULTIPLY"; mul.inputs["Factor"].default_value = 1
    mul.inputs[7].default_value = (*tint, 1)
    em = nt.nodes.new("ShaderNodeEmission"); em.inputs["Strength"].default_value = strength
    tr = nt.nodes.new("ShaderNodeBsdfTransparent"); mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(tx.outputs["Color"], mul.inputs[6]); nt.links.new(mul.outputs[2], em.inputs["Color"])
    nt.links.new(tx.outputs["Alpha"], mix.inputs[0]); nt.links.new(tr.outputs[0], mix.inputs[1]); nt.links.new(em.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs[0])
    return m


def mat_flat(name, color, strength, cull=False):
    m = bpy.data.materials.new(name); m.use_nodes = True; nt = m.node_tree; nt.nodes.clear()
    m.use_backface_culling = cull
    out = nt.nodes.new("ShaderNodeOutputMaterial"); em = nt.nodes.new("ShaderNodeEmission")
    em.inputs["Color"].default_value = (*color, 1); em.inputs["Strength"].default_value = strength
    nt.links.new(em.outputs[0], out.inputs[0])
    return m


GOLD, HOT, DEEP = (1.0, 0.7, 0.12), (1.0, 0.95, 0.7), (0.2, 0.05, 0.02)
M = {
    "fist": mat_flat("fist", GOLD, 3.0), "hull": mat_flat("hull", DEEP, 1.0, cull=True),
    "torpedo": mat_tex("torp", "haytorpedo_gold", 2.6), "shell": mat_tex("shell", "hayshell_gold", 2.6),
    "whirl": mat_tex("whirl", "haywhirl_gold", 2.8), "rings": mat_flat("rings", HOT, 4.0),
    "ink": mat_flat("ink", (0.08, 0.025, 0.015), 0.6), "lane": mat_flat("lane", GOLD, 4.0),
}
for ob, key in ((fist, "fist"), (fist_hull, "hull"), (torpedo, "torpedo"), (torpedo_hull, "hull"), (rings, "rings"),
                (dome, "shell"), (arch, "shell"), (ink, "ink"), (whirl, "whirl")):
    ob.data.materials.clear(); ob.data.materials.append(M[key]); ob.hide_render = True; ob.visible_shadow = False

# R6 stand-in, the lane along -Y
def block(loc, size, col):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc); o = bpy.context.object; o.scale = size
    mm = bpy.data.materials.new("b"); mm.use_nodes = True
    mm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*col, 1); o.data.materials.append(mm)
block((0, 0, 3), (2, 1, 2), (0.05, 0.05, 0.06)); block((0, 0, 4.6), (1.2, 1.2, 1.2), (0.8, 0.8, 0.8))
for x in (-0.5, 0.5): block((x, 0, 1), (1, 1, 2), (0.85, 0.85, 0.85))

instances = []
def show(src, loc, scale, rot=(0, 0, 0)):
    o = src.copy(); o.data = src.data; o.hide_render = False
    o.location, o.scale, o.rotation_euler = loc, scale, rot
    sc.collection.objects.link(o); instances.append(o); return o

def clear():
    for o in instances: bpy.data.objects.remove(o)
    instances.clear()

LANE = 24
def lane_lines(alpha_len=1.0):
    for i in (-1, 0, 1):
        bpy.ops.mesh.primitive_plane_add(size=1); p = bpy.context.object
        L = LANE * alpha_len
        p.scale = (0.25 if i else 0.5, L, 1); p.location = (i * 1.8, -L / 2 - 1, 0.05)
        p.data.materials.append(M["lane"]); instances.append(p)

cam_d = bpy.data.cameras.new("cam"); cam_d.lens = 16
cam = bpy.data.objects.new("cam", cam_d); sc.collection.objects.link(cam); sc.camera = cam
cam.location = Vector((7, -21, 7)); target = Vector((0, -3, 3))
cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()

SHOTS = {}
def shot(name, fn):
    clear(); fn()
    sc.render.filepath = os.path.join(RENDER, f"hay_{name}.png"); bpy.ops.render.render(write_still=True)
    SHOTS[name] = sc.render.filepath

# 9.45: the charge: dome over him, the whirl disk, the lane lines
shot("0945", lambda: (show(dome, (0, 0, 0), (4.5, 4.5, 4.5), (math.radians(-90), 0, 0)),
                      show(whirl, (0, 0, 0.1), (5, 5, 5)), lane_lines(1.0)))
# 9.65: the fist shooting out of him
shot("0965", lambda: (show(fist, (0, -6, 3.2), (3.4, 3.4, 3.4)), show(fist_hull, (0, -6, 3.2), (3.4, 3.4, 3.4)), lane_lines(1.0)))
# 9.75: the torpedo down the lane, the rings at the fist
shot("0975", lambda: (show(torpedo, (0, -12, 2.6), (14, 22, 14)), show(torpedo_hull, (0, -12, 2.6), (14, 22, 14)),
                      show(rings, (0, -1.5, 2.8), (4.2, 4.2, 4.2)), lane_lines(1.0)))
# 10.05: the dome shell bulging forward round the impact
shot("1005", lambda: (show(dome, (0, -3, 2.5), (5.5, 4.5, 5.5)), show(rings, (0, -2, 2.8), (3.6, 3.6, 3.6)), lane_lines(1.0)))
# 10.45: the arches across the lane, ink curling over
def breakup():
    random.seed(4)
    for i in range(6):
        y = -2.5 - i * 2.4
        s = 3.0 + random.uniform(0, 1.4)
        x = random.uniform(-1.5, 1.5)
        show(arch, (x, y, 0), (s, s * 0.6, s * 1.1), (0, 0, math.radians(random.uniform(-25, 25))))
    for i in range(3):
        sg = 1 if i % 2 else -1
        show(ink, (sg * 2.2, -3 - i * 4, 0), (5, 5, 5), (0, 0, math.radians(-30 * sg)))
    lane_lines(1.0)
shot("1045", breakup)
print("RENDERED", list(SHOTS))

# side by side with the clip's frames (6 rows of 2 cells, 600x278 each, in 0.1 s steps from 9.45)
if SHEET and os.path.exists(SHEET):
    import numpy as np
    clipimg = bpy.data.images.load(SHEET)
    W, H = clipimg.size
    px = np.array(clipimg.pixels[:]).reshape(H, W, 4)[::-1]
    cw, ch = W // 2, H // 6
    cells = {"0945": (0, 0), "0965": (1, 0), "0975": (1, 1), "1005": (3, 0), "1045": (5, 0)}
    out = np.zeros((ch * len(cells), cw * 2, 4)); out[..., 3] = 1
    for i, (name, (r, cc)) in enumerate(cells.items()):
        out[i * ch:(i + 1) * ch, :cw] = px[r * ch:(r + 1) * ch, cc * cw:(cc + 1) * cw]
        ren = bpy.data.images.load(SHOTS[name]); rw, rh = ren.size
        rp = np.array(ren.pixels[:]).reshape(rh, rw, 4)[::-1]
        out[i * ch:i * ch + min(ch, rh), cw:cw + min(cw, rw)] = rp[:min(ch, rh), :min(cw, rw)]
    img = bpy.data.images.new("cmp", cw * 2, ch * len(cells)); img.pixels = out[::-1].ravel().tolist()
    img.filepath_raw = os.path.join(RENDER, "hay_compare.png"); img.file_format = "PNG"; img.save()
    print("COMPARE", img.filepath_raw)
