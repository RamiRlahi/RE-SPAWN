"""Render spectral ghost sprites (transparent PNGs) for the Fire Knight's throne
portrait. Run: blender -b -P tools/blender/ghost_sprites.py -- <out_dir>
The uploaded results are RewardPreview's GHOSTS (a soft blue halo was added
under each afterwards: a Gaussian blur of its alpha at 55%).
Each ghost is one smooth metaball body (hooded head running into a long,
curling tail, two wisps of arms trailing back), glowing pale spectral blue,
solid at the head and thinning to nothing down the tail, with hollow eyes and
a wailing mouth."""
import bpy, sys, math, os

out_dir = sys.argv[sys.argv.index("--") + 1]
os.makedirs(out_dir, exist_ok=True)


def reset():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    for eng in ("BLENDER_EEVEE_NEXT", "BLENDER_EEVEE"):
        try:
            sc.render.engine = eng
            break
        except TypeError:
            pass
    sc.render.film_transparent = True
    sc.render.resolution_x = 512
    sc.render.resolution_y = 512
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.view_settings.view_transform = "Standard"
    cam_data = bpy.data.cameras.new("Cam")
    cam_data.type = "ORTHO"
    cam_data.ortho_scale = 4.6
    cam = bpy.data.objects.new("Cam", cam_data)
    sc.collection.objects.link(cam)
    cam.location = (0, -10, -0.45)
    cam.rotation_euler = (math.radians(90), 0, 0)
    sc.camera = cam
    return sc


def ghost_material():
    m = bpy.data.materials.new("Ghost")
    m.use_nodes = True
    for attr, v in (("surface_render_method", "BLENDED"), ("blend_method", "BLEND")):
        try:
            setattr(m, attr, v)
            break
        except Exception:
            pass
    nt = m.node_tree
    nt.nodes.clear()
    L = nt.links.new
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    tex = nt.nodes.new("ShaderNodeTexCoord")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    L(tex.outputs["Object"], sep.inputs[0])
    # down the body: solid at the head (z > 0.2), gone at the tail's end
    fade = nt.nodes.new("ShaderNodeMapRange")
    fade.inputs["From Min"].default_value = -2.3
    fade.inputs["From Max"].default_value = 0.2
    L(sep.outputs["Z"], fade.inputs["Value"])
    fpow = nt.nodes.new("ShaderNodeMath")
    fpow.operation = "POWER"
    fpow.inputs[1].default_value = 1.6
    L(fade.outputs["Result"], fpow.inputs[0])
    # streaks of mist through it (stretched noise)
    mapping = nt.nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (2.5, 2.5, 0.6)
    L(tex.outputs["Object"], mapping.inputs["Vector"])
    noise = nt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 2.2
    noise.inputs["Detail"].default_value = 4
    L(mapping.outputs["Vector"], noise.inputs["Vector"])
    streak = nt.nodes.new("ShaderNodeMapRange")
    streak.inputs["From Min"].default_value = 0.3
    streak.inputs["From Max"].default_value = 0.7
    streak.inputs["To Min"].default_value = 0.55
    streak.inputs["To Max"].default_value = 1.0
    L(noise.outputs["Fac"], streak.inputs["Value"])
    # soft edges: the silhouette melts away, the middle holds
    lw = nt.nodes.new("ShaderNodeLayerWeight")
    lw.inputs["Blend"].default_value = 0.5
    soft = nt.nodes.new("ShaderNodeMath")
    soft.operation = "SUBTRACT"
    soft.inputs[0].default_value = 1.0
    L(lw.outputs["Facing"], soft.inputs[1])
    softp = nt.nodes.new("ShaderNodeMath")
    softp.operation = "POWER"
    softp.inputs[1].default_value = 1.1
    L(soft.outputs[0], softp.inputs[0])
    a1 = nt.nodes.new("ShaderNodeMath"); a1.operation = "MULTIPLY"
    L(fpow.outputs[0], a1.inputs[0]); L(streak.outputs["Result"], a1.inputs[1])
    a2 = nt.nodes.new("ShaderNodeMath"); a2.operation = "MULTIPLY"
    L(a1.outputs[0], a2.inputs[0]); L(softp.outputs[0], a2.inputs[1])
    ax = nt.nodes.new("ShaderNodeMath"); ax.operation = "ABSOLUTE"
    L(sep.outputs["X"], ax.inputs[0])
    armf = nt.nodes.new("ShaderNodeMapRange")
    armf.inputs["From Min"].default_value = 1.35
    armf.inputs["From Max"].default_value = 0.55
    L(ax.outputs[0], armf.inputs["Value"])
    a25 = nt.nodes.new("ShaderNodeMath"); a25.operation = "MULTIPLY"
    L(a2.outputs[0], a25.inputs[0]); L(armf.outputs["Result"], a25.inputs[1])
    a3 = nt.nodes.new("ShaderNodeMath"); a3.operation = "MULTIPLY"; a3.use_clamp = True
    a3.inputs[1].default_value = 0.85
    L(a25.outputs[0], a3.inputs[0])
    # colour: white-hot core to spectral blue at the edges
    col = nt.nodes.new("ShaderNodeMix")
    col.data_type = "RGBA"
    col.inputs[6].default_value = (0.78, 0.93, 1.0, 1)
    col.inputs[7].default_value = (0.18, 0.55, 1.0, 1)
    L(lw.outputs["Facing"], col.inputs[0])
    emit = nt.nodes.new("ShaderNodeEmission")
    emit.inputs["Strength"].default_value = 1.4
    L(col.outputs[2], emit.inputs["Color"])
    transp = nt.nodes.new("ShaderNodeBsdfTransparent")
    mixs = nt.nodes.new("ShaderNodeMixShader")
    L(a3.outputs[0], mixs.inputs[0])
    L(transp.outputs[0], mixs.inputs[1])
    L(emit.outputs[0], mixs.inputs[2])
    L(mixs.outputs[0], out.inputs["Surface"])
    return m


def void_material():
    m = bpy.data.materials.new("Void")
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.clear()
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    e = nt.nodes.new("ShaderNodeEmission")
    e.inputs["Color"].default_value = (0.0, 0.01, 0.04, 1)
    nt.links.new(e.outputs[0], out.inputs["Surface"])
    return m


def build_ghost(curl, phase, reach, mouth, tilt):
    mb = bpy.data.metaballs.new("Body")
    mb.resolution = 0.06
    mb.render_resolution = 0.04
    mb.threshold = 0.6
    obj = bpy.data.objects.new("Body", mb)
    bpy.context.scene.collection.objects.link(obj)

    def ball(x, z, r, stiff=2.0, y=0.0, kind="BALL", sx=1, sy=1, sz=1):
        e = mb.elements.new(type=kind)
        e.co = (x, y, z)
        e.radius = r
        e.stiffness = stiff
        if kind == "ELLIPSOID":
            e.size_x, e.size_y, e.size_z = sx, sy, sz
        return e

    # the hood / head
    ball(0, 0.55, 0.78, 2.4, kind="ELLIPSOID", sx=0.8, sy=0.75, sz=1.0)
    # the tail: a run of shrinking balls down an S curve
    n = 14
    for i in range(1, n + 1):
        t = i / n
        z = 0.4 - t * 2.6
        x = math.sin(t * math.pi * 1.4 + phase) * curl * t
        ball(x, z, 0.62 * (1 - t) ** 0.8 + 0.08, 2.0)
    # the arms: wisps trailing back and out
    for side in (-1, 1):
        for i in range(1, 8):
            t = i / 7
            x = side * (0.45 + t * 0.8 * reach)
            z = 0.05 - t * 0.7 + math.sin(t * 3.0) * 0.15
            ball(x, z, 0.26 * (1 - t) + 0.13, 1.8)
    bpy.context.view_layer.objects.active = obj
    obj.select_set(True)
    bpy.ops.object.convert(target="MESH")
    body = bpy.context.object
    for p in body.data.polygons:
        p.use_smooth = True
    body.data.materials.append(ghost_material())
    body.rotation_euler = (0, math.radians(tilt), 0)

    void = void_material()
    # hollow, slanted eyes and a long wailing mouth, pressed into the face
    for side in (-1, 1):
        bpy.ops.mesh.primitive_uv_sphere_add(radius=0.14, location=(side * 0.21, -0.62, 0.72))
        e = bpy.context.object
        e.scale = (0.9, 0.45, 1.25)
        e.rotation_euler = (0, math.radians(side * -18), 0)
        e.data.materials.append(void)
        e.parent = body
    bpy.ops.mesh.primitive_uv_sphere_add(radius=0.1, location=(0, -0.62, 0.32))
    m = bpy.context.object
    m.scale = (0.85, 0.45, 1.8 * mouth)
    m.data.materials.append(void)
    m.parent = body


VARIANTS = [
    # name, curl, phase, reach, mouth, tilt
    ("ghost_a", 0.55, 0.0, 1.0, 1.0, -8),
    ("ghost_b", 0.7, 2.2, 1.15, 1.35, 10),
    ("ghost_c", 0.4, 1.0, 0.75, 0.8, 0),
]
for name, curl, phase, reach, mouth, tilt in VARIANTS:
    sc = reset()
    build_ghost(curl, phase, reach, mouth, tilt)
    sc.render.filepath = os.path.join(out_dir, name + ".png")
    bpy.ops.render.render(write_still=True)
    print("rendered", sc.render.filepath)
