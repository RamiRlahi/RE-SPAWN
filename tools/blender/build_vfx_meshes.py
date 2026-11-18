"""Builds the RE-SPAWN VFX meshes, exports them for Roblox and renders a showcase.
Run: blender -b --factory-startup --python tools/blender/build_vfx_meshes.py -- <render_dir>

Meshes (assets/vfx/meshes/*.fbx, 1 unit = 1 stud before MeshPart sizing). Axes after import into Roblox:
  shock_cone      apex at the origin, opens along LookVector (-Z). u around (tiles), v apex->mouth.   texture: cone_*
  swept_shell     a 200 deg band around the up axis (+Y), slightly cupped. u along the sweep (head at u=1), v inner->outer edge. texture: sweep_*
  tornado         5 helical ribbons around +Y, widening upward. u along each ribbon (tiles 3x), v across. texture: ribbon_*  (spin the part)
  crystal_cluster 10 faceted crystals leaning out from the centre, flat shaded. u across a facet, v base->tip. texture: facet_*
  dash_tunnel     a spiral ribbon along LookVector (-Z), 4 turns. texture: ribbon_* or sweep_*
Roblox cannot scroll UVs on a MeshPart, so motion comes from rotating/scaling the part (tornado spin, cone/shell scale-out).
"""
import bpy, bmesh, os, sys, math
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.normpath(os.path.join(HERE, "..", ".."))
TEX = os.path.join(ROOT, "assets", "vfx", "generated")
MESH_OUT = os.path.join(ROOT, "assets", "vfx", "meshes")
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
RENDER_OUT = argv[0] if argv else os.path.join(HERE, "renders")
os.makedirs(MESH_OUT, exist_ok=True); os.makedirs(RENDER_OUT, exist_ok=True)

for o in list(bpy.data.objects): bpy.data.objects.remove(o)
TAU = 2 * math.pi


def build(name, quads_fn, flat=False):
    """quads_fn yields faces as lists of (Vector, (u, v))."""
    bm = bmesh.new(); uv = bm.loops.layers.uv.new("UVMap")
    for face in quads_fn():
        vs = [bm.verts.new(p) for p, _ in face]
        f = bm.faces.new(vs)
        for loop, (_, t) in zip(f.loops, face): loop[uv].uv = t
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    for p in me.polygons: p.use_smooth = not flat
    ob = bpy.data.objects.new(name, me); bpy.context.scene.collection.objects.link(ob)
    return ob


def grid(P, nu, nv, u_scale=1.0):
    """Quads over a parametric surface P(s, t) -> Vector, s in [0,1] (u), t in [0,1] (v)."""
    for i in range(nu):
        for j in range(nv):
            s0, s1, t0, t1 = i / nu, (i + 1) / nu, j / nv, (j + 1) / nv
            yield [(P(s0, t0), (s0 * u_scale, t0)), (P(s1, t0), (s1 * u_scale, t0)),
                   (P(s1, t1), (s1 * u_scale, t1)), (P(s0, t1), (s0 * u_scale, t1))]


def shock_cone():
    def P(s, t):                       # s around, t apex->mouth along +Y (Blender) = LookVector in Roblox
        r = 0.06 + 0.5 * t ** 0.65
        return Vector((math.cos(s * TAU) * r, t * 1.0, math.sin(s * TAU) * r))
    return grid(P, 40, 10)


def swept_shell():
    span = math.radians(200)
    def P(s, t):                       # s along the sweep, t inner->outer
        a = -span / 2 + s * span
        r = 0.75 + 0.65 * t
        z = -0.10 * (t - 0.5) ** 2 * 4 + 0.06 * math.sin(s * math.pi)    # slight cup + arch
        return Vector((math.cos(a) * r, math.sin(a) * r, z))
    return grid(P, 56, 4)


def tornado():
    """Clip 3: many overlapping, uneven ribbons, not a tidy helix. Each ribbon has its own phase, pitch,
    radius, height, width and wobble, so the silhouette stays chaotic while the part spins."""
    import random
    random.seed(21)
    def faces():
        for k in range(10):
            phase, turns = random.uniform(0, TAU), random.uniform(1.3, 2.6)
            r0, r1, H = random.uniform(0.10, 0.32), random.uniform(0.55, 1.05), random.uniform(1.2, 2.0)
            w0, w1 = random.uniform(0.10, 0.18), random.uniform(0.22, 0.42)
            wob, wph, z0 = random.uniform(0.04, 0.12), random.uniform(0, TAU), random.uniform(-0.05, 0.25)
            def P(s, t, phase=phase, turns=turns, r0=r0, r1=r1, H=H, w0=w0, w1=w1, wob=wob, wph=wph, z0=z0):
                a = phase + s * turns * TAU
                r = r0 + (r1 - r0) * s ** 1.4 + wob * math.sin(3 * a + wph)
                w = w0 + (w1 - w0) * s
                lean = (t - 0.5) * w
                rr = r + lean * 0.45                     # ribbons lean outward as they climb
                return Vector((math.cos(a) * rr, math.sin(a) * rr, z0 + s * H + lean))
            yield from grid(P, 90, 2, u_scale=2.0)
    return faces()


def crystal_cluster():
    import random
    random.seed(9)
    specs = [(0.0, 0.0, 0.0, 0.16, 1.25)]
    for i in range(9):
        a = i / 9 * TAU + random.uniform(-0.2, 0.2)
        specs.append((math.cos(a) * random.uniform(0.25, 0.45), math.sin(a) * random.uniform(0.25, 0.45),
                      math.radians(random.uniform(22, 48)), random.uniform(0.07, 0.12), random.uniform(0.45, 0.9)))
    def faces():
        for x, y, lean, rb, h in specs:
            out = Vector((x, y, 0)).normalized() if (x or y) else Vector((1, 0, 0))
            axis = (Vector((0, 0, 1)) * math.cos(lean) + out * math.sin(lean)).normalized()
            side = axis.cross(Vector((0, 0, 1))) if lean else Vector((1, 0, 0))
            side = side.normalized() if side.length > 1e-4 else Vector((1, 0, 0))
            fwd = axis.cross(side).normalized()
            base = Vector((x, y, -0.05)); body = h * 0.72
            ring = lambda hh, rad: [base + axis * hh + (side * math.cos(i / 6 * TAU) + fwd * math.sin(i / 6 * TAU)) * rad for i in range(6)]
            lo, hi, tip = ring(0, rb), ring(body, rb * 1.05), base + axis * h
            for i in range(6):
                j = (i + 1) % 6
                yield [(lo[i], (0, 0)), (lo[j], (1, 0)), (hi[j], (1, 0.7)), (hi[i], (0, 0.7))]
                yield [(hi[i], (0, 0.7)), (hi[j], (1, 0.7)), (tip, (0.5, 1.0))]
    return faces()


def dash_tunnel():
    def P(s, t):                       # spiral along +Y (= LookVector), 4 turns
        a = s * 4 * TAU
        r = 0.42 + 0.08 * math.sin(s * math.pi)
        w = 0.28 * (0.3 + 0.7 * s)                     # wide swirl bands, thinning toward the start of the dash
        return Vector((math.cos(a) * r, s * 1.0 + (t - 0.5) * w, math.sin(a) * r))
    return grid(P, 200, 2, u_scale=4.0)


MESHES = {
    "shock_cone": (shock_cone, False), "swept_shell": (swept_shell, False), "tornado": (tornado, False),
    "crystal_cluster": (crystal_cluster, True), "dash_tunnel": (dash_tunnel, False),
}
objs = {}
for name, (fn, flat) in MESHES.items():
    ob = build(name, fn, flat); objs[name] = ob
    bpy.ops.object.select_all(action="DESELECT"); ob.select_set(True); bpy.context.view_layer.objects.active = ob
    bpy.ops.export_scene.fbx(filepath=os.path.join(MESH_OUT, name + ".fbx"), use_selection=True, axis_forward="-Z", axis_up="Y",
                             apply_scale_options="FBX_SCALE_UNITS", mesh_smooth_type="FACE", use_mesh_modifiers=True, bake_space_transform=True)
    print("EXPORTED", name, len(ob.data.polygons), "faces")

# ---------------------------------------------------------------- showcase render (game camera angle, textured)
sc = bpy.context.scene
for eng in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
    try: sc.render.engine = eng; break
    except TypeError: pass
sc.render.resolution_x, sc.render.resolution_y = 1600, 900
sc.view_settings.view_transform = "Standard"     # AgX desaturates emissive colors toward pastel; Standard is closer to Roblox
world = bpy.data.worlds.new("w"); sc.world = world; world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.05, 0.055, 0.07, 1)
bpy.ops.mesh.primitive_plane_add(size=200); floor = bpy.context.object
fm = bpy.data.materials.new("floor"); fm.use_nodes = True
fm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.03, 0.03, 0.035, 1); floor.data.materials.append(fm)
sun = bpy.data.lights.new("sun", "SUN"); sun.energy = 2.0; so = bpy.data.objects.new("sun", sun); so.rotation_euler = (0.9, 0, 0.5); sc.collection.objects.link(so)


def tex_mat(name, tex, strength, mode="blend"):
    m = bpy.data.materials.new(name); m.use_nodes = True; nt = m.node_tree; nt.nodes.clear()
    if hasattr(m, "surface_render_method"): m.surface_render_method = "BLENDED"
    m.use_backface_culling = False
    out = nt.nodes.new("ShaderNodeOutputMaterial"); tx = nt.nodes.new("ShaderNodeTexImage")
    tx.image = bpy.data.images.load(os.path.join(TEX, tex + ".png"), check_existing=True); tx.image.alpha_mode = "STRAIGHT"
    em = nt.nodes.new("ShaderNodeEmission"); em.inputs["Strength"].default_value = strength
    tr = nt.nodes.new("ShaderNodeBsdfTransparent"); mix = nt.nodes.new("ShaderNodeMixShader")
    nt.links.new(tx.outputs["Color"], em.inputs["Color"]); nt.links.new(tx.outputs["Alpha"], mix.inputs[0])
    nt.links.new(tr.outputs[0], mix.inputs[1]); nt.links.new(em.outputs[0], mix.inputs[2]); nt.links.new(mix.outputs[0], out.inputs[0])
    return m


def place(name, tex, loc, scale, rot=(0, 0, 0), strength=2.5):
    o = objs[name]; o.location = loc; o.scale = scale; o.rotation_euler = rot
    o.visible_shadow = False                      # effect meshes cast no shadow (CastShadow = false in Roblox)
    o.data.materials.clear(); o.data.materials.append(tex_mat(name + tex, tex, strength))

# a row of five, 14 studs apart, sized like in-game effects (studs)
place("tornado", "ribbon_fire", (-28, 0, 0), (5, 5, 6), strength=1.6)
place("crystal_cluster", "facet_ice", (-14, 0, 0), (5, 5, 5), strength=1.3)
place("swept_shell", "sweep_fire", (0, 0, 2.2), (4.5, 4.5, 4.5), rot=(0, 0, -math.pi / 2), strength=1.8)
place("shock_cone", "cone_ice", (14, -3, 2.5), (3.5, 7, 3.5), rot=(0, 0, math.pi), strength=1.6)
place("dash_tunnel", "ribbon_ice", (28, -4, 2.5), (3, 9, 3), rot=(0, 0, math.pi), strength=1.6)

cam_d = bpy.data.cameras.new("cam"); cam_d.sensor_fit = "VERTICAL"; cam_d.angle_y = math.radians(42)
cam = bpy.data.objects.new("cam", cam_d); sc.collection.objects.link(cam); sc.camera = cam
for shot, offset, target in (("meshes_game_cam", Vector((-24, -24, 52)) * 0.95, Vector((0, 0, 2))),
                             ("meshes_low_angle", Vector((0, -46, 14)), Vector((0, 0, 3)))):
    cam.location = target + offset
    cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()
    sc.render.filepath = os.path.join(RENDER_OUT, shot + ".png")
    bpy.ops.render.render(write_still=True); print("RENDERED", sc.render.filepath)
