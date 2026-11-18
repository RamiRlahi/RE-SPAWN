"""Renders composed impacts from the generated VFX library through the game's isometric camera.
Run: blender -b --factory-startup --python tools/blender/render_vfx_preview.py -- <out_dir> [shot ...]
Shots: fire0 fire5 ice1 ice9 (number = frame after impact at 30 fps, see docs/vfx-reference-timing.md).
1 Blender unit = 1 stud. Roblox (x, y, z) -> Blender (x, -z, y).
"""
import bpy, sys, os, math, random
from mathutils import Vector

HERE = os.path.dirname(os.path.abspath(__file__))
TEX = os.path.normpath(os.path.join(HERE, "..", "..", "assets", "vfx", "generated"))
argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
OUT = argv[0] if argv else os.path.join(HERE, "renders")
SHOTS = argv[1:] or ["fire0", "fire5", "ice1", "ice9"]
os.makedirs(OUT, exist_ok=True)

sc = bpy.context.scene
for eng in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
    try: sc.render.engine = eng; break
    except TypeError: pass
sc.render.resolution_x, sc.render.resolution_y = 1280, 720
sc.view_settings.view_transform = "AgX" if "AgX" in [i.identifier for i in sc.view_settings.bl_rna.properties["view_transform"].enum_items] else "Filmic"
sc.view_settings.look = "None"
for o in list(bpy.data.objects): bpy.data.objects.remove(o)

# ---------------- world, floor, light, camera (IsometricCamera: offset (-24, 52, 24), FOV 42)
world = bpy.data.worlds.new("w"); sc.world = world; world.use_nodes = True
world.node_tree.nodes["Background"].inputs[0].default_value = (0.05, 0.055, 0.07, 1)
world.node_tree.nodes["Background"].inputs[1].default_value = 1.0

def grid_image():
    S = 256; img = bpy.data.images.new("grid", S, S)
    px = []
    for y in range(S):
        for x in range(S):
            line = (x % 64 < 2) or (y % 64 < 2)
            v = 0.19 if line else 0.075
            px += [v, v, v * 1.08, 1]
    img.pixels = px; return img

bpy.ops.mesh.primitive_plane_add(size=240); floor = bpy.context.object
m = bpy.data.materials.new("floor"); m.use_nodes = True; nt = m.node_tree
bsdf = nt.nodes["Principled BSDF"]; bsdf.inputs["Roughness"].default_value = 0.9
tex = nt.nodes.new("ShaderNodeTexImage"); tex.image = grid_image()
mp = nt.nodes.new("ShaderNodeMapping"); mp.inputs["Scale"].default_value = (240 / 16, 240 / 16, 1)   # 4-stud tiles
tc = nt.nodes.new("ShaderNodeTexCoord")
nt.links.new(tc.outputs["UV"], mp.inputs[0]); nt.links.new(mp.outputs[0], tex.inputs[0]); nt.links.new(tex.outputs[0], bsdf.inputs["Base Color"])
floor.data.materials.append(m)

sun = bpy.data.lights.new("sun", "SUN"); sun.energy = 2.2; so = bpy.data.objects.new("sun", sun)
so.rotation_euler = (math.radians(50), 0, math.radians(30)); sc.collection.objects.link(so)

target = Vector((0, 0, 2.5))
cam_d = bpy.data.cameras.new("cam"); cam_d.sensor_fit = "VERTICAL"; cam_d.angle_y = math.radians(42)
cam = bpy.data.objects.new("cam", cam_d); sc.collection.objects.link(cam); sc.camera = cam
cam.location = target + Vector((-24, -24, 52)) * 0.55          # zoomed in ~half for a readable preview (same angle)
cam.rotation_euler = (target - cam.location).to_track_quat("-Z", "Y").to_euler()

# R6-sized stand-in character (5 studs tall)
def block(name, loc, size, col=(0.08, 0.08, 0.09)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc); o = bpy.context.object; o.scale = size; o.name = name
    mm = bpy.data.materials.new(name); mm.use_nodes = True
    mm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (*col, 1); o.data.materials.append(mm)
block("torso", (0, 0, 3), (2, 1, 2)); block("head", (0, 0, 4.6), (1.2, 1.2, 1.2), (0.85, 0.85, 0.85))
for x in (-0.5, 0.5): block("leg", (x, 0, 1), (1, 1, 2), (0.9, 0.9, 0.9))
for x in (-1.5, 1.5): block("arm", (x, 0, 3), (1, 1, 2))

# ---------------- bloom (compositor glare); API differs between Blender versions, so try both
def setup_bloom():
    try:
        if hasattr(sc, "compositing_node_group"):
            ng = bpy.data.node_groups.new("comp", "CompositorNodeTree"); sc.compositing_node_group = ng
            rl = ng.nodes.new("CompositorNodeRLayers"); out = ng.nodes.new("NodeGroupOutput")
            ng.interface.new_socket("Image", in_out="OUTPUT", socket_type="NodeSocketColor")
        else:
            sc.use_nodes = True; ng = sc.node_tree; ng.nodes.clear()
            rl = ng.nodes.new("CompositorNodeRLayers"); out = ng.nodes.new("CompositorNodeComposite")
        ng.links.new(rl.outputs["Image"], out.inputs[0])            # plain pass-through first: never a black frame
        gl = ng.nodes.new("CompositorNodeGlare")
        if "Type" in gl.inputs:                                      # Blender 5.x: settings are input sockets
            gl.inputs["Type"].default_value = "Bloom"
            for sock_name, val in (("Threshold", 0.85), ("Strength", 0.8), ("Size", 0.65), ("Quality", "High")):
                if sock_name in gl.inputs: gl.inputs[sock_name].default_value = val
        else:
            gl.glare_type = "BLOOM"; gl.threshold = 0.85; gl.size = 7
        ng.links.new(rl.outputs["Image"], gl.inputs[0]); ng.links.new(gl.outputs[0], out.inputs[0])
        return "ok"
    except Exception as e:
        return f"bloom failed: {e}"
print("BLOOM", setup_bloom())

# ---------------- textured cards
_mats = {}
def card_mat(name, cell, grid, mode, strength, tint):
    key = (name, cell, grid, mode, round(strength, 2), tint)
    if key in _mats: return _mats[key]
    img = bpy.data.images.load(os.path.join(TEX, name + ".png"), check_existing=True)
    img.alpha_mode = "STRAIGHT"
    m = bpy.data.materials.new(f"{name}_{cell}"); m.use_nodes = True; nt = m.node_tree; nt.nodes.clear()
    if hasattr(m, "surface_render_method"): m.surface_render_method = "BLENDED"
    else: m.blend_method = "BLEND"
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    tc = nt.nodes.new("ShaderNodeTexCoord"); mp = nt.nodes.new("ShaderNodeMapping")
    col, row = cell % grid, cell // grid
    mp.inputs["Scale"].default_value = (1 / grid, 1 / grid, 1)
    mp.inputs["Location"].default_value = (col / grid, (grid - 1 - row) / grid, 0)
    tx = nt.nodes.new("ShaderNodeTexImage"); tx.image = img; tx.extension = "CLIP"
    nt.links.new(tc.outputs["UV"], mp.inputs[0]); nt.links.new(mp.outputs[0], tx.inputs[0])
    tintn = nt.nodes.new("ShaderNodeMix"); tintn.data_type = "RGBA"; tintn.blend_type = "MULTIPLY"
    tintn.inputs["Factor"].default_value = 1.0; tintn.inputs[7].default_value = (*tint, 1)
    nt.links.new(tx.outputs["Color"], tintn.inputs[6])
    em = nt.nodes.new("ShaderNodeEmission"); em.inputs["Strength"].default_value = strength
    nt.links.new(tintn.outputs[2], em.inputs["Color"])
    tr = nt.nodes.new("ShaderNodeBsdfTransparent")
    if mode == "add":       # Roblox LightEmission 1
        mul = nt.nodes.new("ShaderNodeMath"); mul.operation = "MULTIPLY"; mul.inputs[1].default_value = strength
        nt.links.new(tx.outputs["Alpha"], mul.inputs[0]); nt.links.new(mul.outputs[0], em.inputs["Strength"])
        add = nt.nodes.new("ShaderNodeAddShader")
        nt.links.new(tr.outputs[0], add.inputs[0]); nt.links.new(em.outputs[0], add.inputs[1]); nt.links.new(add.outputs[0], out.inputs[0])
    else:                   # Roblox LightEmission 0 + Brightness: dark core stays dark
        mix = nt.nodes.new("ShaderNodeMixShader")
        nt.links.new(tx.outputs["Alpha"], mix.inputs[0]); nt.links.new(tr.outputs[0], mix.inputs[1]); nt.links.new(em.outputs[0], mix.inputs[2]); nt.links.new(mix.outputs[0], out.inputs[0])
    _mats[key] = m; return m

def card(name, cell=0, grid=1, loc=(0, 0, 0), size=4, aspect=1.0, face="camera", rot=0.0, tilt=0.0,
         mode="blend", strength=3.0, tint=(1, 1, 1), z_bias=0.0):
    bpy.ops.mesh.primitive_plane_add(size=1, location=loc); o = bpy.context.object
    o.scale = (size * aspect, size, 1)
    loc = Vector(loc)
    if face == "camera":
        q = (cam.location - loc).to_track_quat("Z", "Y"); o.rotation_euler = q.to_euler()
        o.rotation_euler.rotate_axis("Z", rot)
    elif face == "floor":
        o.location.z = 0.02 + z_bias; o.rotation_euler = (math.radians(tilt), 0, rot)
    elif face == "upright":   # cylindrical billboard: stands on the floor, turns toward the camera
        d = cam.location - loc; o.rotation_euler = (math.radians(90), 0, math.atan2(d.y, d.x) - math.pi / 2)
    o.data.materials.append(card_mat(name, cell, grid, mode, strength, tint))
    return o

def clear_cards():
    for o in list(bpy.data.objects):
        if o.type == "MESH" and o.name.startswith("Plane") and o is not floor: bpy.data.objects.remove(o)

def fade(T, start, end):
    return max(0.0, min(1.0, 1 - (T - start) / max(end - start, 1e-3)))

# ---------------- compositions
def fire(T):
    random.seed(3)
    # measured on the polearm clip: an even additive floor tint of about +0.35 R / +0.11 G / +0.04 B on frame 0, gone by ~f15
    # an even pink-red floor tint on frame 0 (polearm clip), gone by ~f12. Redder than the measured delta because our floor is darker.
    card("glow_wide", loc=(0, 0, 0), size=34, face="floor", mode="add", strength=0.55 * fade(T, 3, 12), tint=(1.0, 0.16, 0.14), z_bias=0.005)
    card("glow_soft", loc=(0, 0, 0), size=18, face="floor", mode="add", strength=0.9 * fade(T, 0, 10), tint=(1.0, 0.22, 0.08), z_bias=0.01)
    if 10 <= T <= 13: card("smear_fire_2x2", T - 10, 2, loc=(0, -0.6, 2.8), size=13, aspect=1.3, strength=2.5)
    if T >= 12: card("ring_dust_4x4", min(15, (T - 12) * 2), 4, loc=(0, 0, 0), size=11, face="floor", strength=1.4, z_bias=0.04)
    card("stain_scorch", loc=(0.5, 0.8, 0), size=11, face="floor", rot=0.6, strength=1.0, z_bias=0.02)
    if T <= 3: card("starburst_fire_2x2", T, 2, loc=(0.6, -0.3, 3.2), size=17, mode="add", strength=4.0)
    # the sweep lies flat around the character at hip height (crescent centre is at 58 % of the cell height)
    if T <= 15: card("slash_fire_4x4", T, 4, loc=(0, -1.3, 2.2), size=16, face="floor", tilt=12, rot=math.pi, strength=3.0, z_bias=2.2)
    for i in range(14):                                       # many small puffs trail the arc, gone by ~f10
        a = math.radians(345 - i * 13); rr = 5.6 + random.uniform(-0.8, 0.8)   # along the crescent, in front, following the sweep
        t0 = 0.5 + i * 0.18
        idx = int((T - t0) * 2.0)
        if T >= t0 and idx <= 15:
            card("puff_fire_4x4", idx, 4, loc=(math.cos(a) * rr, math.sin(a) * rr, 1.6 + random.uniform(-0.6, 1.4)), size=random.uniform(3.5, 5.0), strength=3.2, rot=random.uniform(-0.6, 0.6))
    if T >= 1: card("ring_fire_4x4", min(15, T), 4, loc=(0, 0, 0), size=20, face="floor", mode="blend", strength=3.0, z_bias=0.03)
    for i in range(14):
        a = random.uniform(0, 2 * math.pi); d = 2 + T * random.uniform(0.6, 1.3)
        if T >= 1: card("spark_fire", loc=(math.cos(a) * d, math.sin(a) * d, 2 + random.uniform(0, 3)), size=0.5, aspect=5, rot=a, mode="add", strength=6)

def ice(T):
    random.seed(5)
    card("glow_soft", loc=(0, 0, 0), size=24, face="floor", mode="add", strength=1.5 * fade(T, 0, 30), tint=(0.25, 0.55, 1.0), z_bias=0.01)
    card("stain_frost", loc=(0, 0, 0), size=13, face="floor", rot=0.3, strength=1.6 * (0.6 + 0.4 * fade(T, 4, 40)), z_bias=0.02)
    if T <= 3: card("starburst_ice_2x2", T, 2, loc=(0, 0, 3.5), size=24, mode="add", strength=5.0)
    if 2 <= T <= 8: card("puff_ice_4x4", min(15, (T - 2) * 2), 4, loc=(0, 0, 3.5), size=10, mode="add", strength=2.5)
    grow = min(1.0, 0.45 + 0.2 * T) * (1 - 0.4 * max(0, T - 14) / 16)
    if T >= 1:
        for i in range(10):
            a = i / 10 * 2 * math.pi + random.uniform(-0.2, 0.2); rr = random.uniform(2.4, 4.8)
            h = random.uniform(3.5, 6.5) * grow
            card("shards_ice_2x2", random.randint(0, 3), 2, loc=(math.cos(a) * rr, math.sin(a) * rr, h / 2 - 0.1), size=h, aspect=0.75, face="upright", strength=2.2)
    if T >= 1: card("ring_ice_4x4", min(15, T), 4, loc=(0, 0, 0), size=22, face="floor", mode="add", strength=3.0, z_bias=0.03)
    if T >= 8: card("slash_ice_4x4", min(15, (T - 8) * 2), 4, loc=(0, 0, 1.5), size=17, face="floor", tilt=-8, rot=2.4, strength=4.0)

for shot in SHOTS:
    clear_cards()
    kind, T = shot.rstrip("0123456789"), int(shot.lstrip("abcdefghijklmnopqrstuvwxyz"))
    (fire if kind == "fire" else ice)(T)
    sc.render.filepath = os.path.join(OUT, f"{shot}.png")
    bpy.ops.render.render(write_still=True)
    print("RENDERED", sc.render.filepath)
