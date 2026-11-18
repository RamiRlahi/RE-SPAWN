"""Preview a 4x4 VFX flipbook in Blender, the way Roblox plays it.

Run it inside Blender (Scripting tab -> Open -> Run Script), or:
    blender --python tools/blender/preview_flipbook.py -- assets/vfx/generated/slash_crescent_4x4.png

It builds a dark floor, two cards playing the flipbook (tinted ice-blue and
fire-orange, glowing like LightEmission = 1), a camera and bloom, then
plays the animation in a loop. Press Space in the viewport to pause.
"""
import os
import sys

import bpy

GRID = 4            # Grid4x4
FPS = 30
HOLD = 2            # Blender frames per flipbook frame (16 frames over ~1 s at 30 fps)
TINTS = {"Ice": (0.55, 0.85, 1.0), "Fire": (1.0, 0.45, 0.12)}


def flipbook_path() -> str:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if argv:
        return os.path.abspath(argv[0])
    here = os.path.dirname(os.path.abspath(__file__)) if "__file__" in globals() else ""
    guess = os.path.normpath(os.path.join(here, "..", "..", "assets", "vfx", "generated", "slash_crescent_4x4.png"))
    if os.path.exists(guess):
        return guess
    blend_dir = bpy.path.abspath("//")
    return os.path.join(blend_dir, "slash_crescent_4x4.png")


def reset_scene():
    scene = bpy.context.scene
    for obj in list(scene.objects):          # clear the scene without touching the UI
        bpy.data.objects.remove(obj, do_unlink=True)
    scene.render.fps = FPS
    scene.frame_start = 1
    scene.frame_end = GRID * GRID * HOLD + 10   # a short gap before it loops
    scene.render.engine = "BLENDER_EEVEE_NEXT" if "BLENDER_EEVEE_NEXT" in {e.identifier for e in bpy.types.RenderSettings.bl_rna.properties["engine"].enum_items} else "BLENDER_EEVEE"
    eevee = scene.eevee
    if hasattr(eevee, "use_bloom"):          # Blender < 4.2
        eevee.use_bloom = True
        eevee.bloom_intensity = 0.08
    world = bpy.data.worlds.new("Dark")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs[0].default_value = (0.02, 0.025, 0.035, 1)
    scene.world = world
    try:
        scene.view_settings.view_transform = "AgX"
    except TypeError:
        scene.view_settings.view_transform = "Filmic"
    return scene


def add_glare(scene):
    """Bloom through the compositor (Eevee lost its own bloom in Blender 4.2)."""
    if hasattr(scene, "compositing_node_group"):          # Blender 5.x: the compositor is a node group
        tree = bpy.data.node_groups.new("FlipbookBloom", "CompositorNodeTree")
        tree.interface.new_socket("Image", in_out="OUTPUT", socket_type="NodeSocketColor")
        out = tree.nodes.new("NodeGroupOutput")
        scene.compositing_node_group = tree
        out_socket = out.inputs[0]
    else:                                                   # Blender 3.x / 4.x
        scene.use_nodes = True
        tree = scene.node_tree
        out = tree.nodes.get("Composite") or tree.nodes.new("CompositorNodeComposite")
        out_socket = out.inputs["Image"]
    rl = tree.nodes.get("Render Layers") or tree.nodes.new("CompositorNodeRLayers")
    glare = tree.nodes.new("CompositorNodeGlare")
    settings = {"glare_type": "FOG_GLOW", "quality": "HIGH", "threshold": 0.8}
    for key, value in settings.items():                     # properties before 4.4, input sockets after
        if hasattr(glare, key):
            setattr(glare, key, value)
    for name, value in (("Type", "Fog Glow"), ("Quality", "High"), ("Threshold", 0.8)):
        sock = glare.inputs.get(name)
        if sock is not None:
            try:
                sock.default_value = value
            except (TypeError, ValueError):
                pass
    tree.links.new(rl.outputs["Image"], glare.inputs["Image"])
    tree.links.new(glare.outputs["Image"], out_socket)
    for area in bpy.context.screen.areas if bpy.context.screen else []:
        if area.type == "VIEW_3D":
            for space in area.spaces:
                if space.type == "VIEW_3D":
                    space.shading.type = "RENDERED"
                    if hasattr(space.shading, "use_compositor"):
                        space.shading.use_compositor = "ALWAYS"


def floor():
    bpy.ops.mesh.primitive_plane_add(size=40, location=(0, 0, 0))
    mat = bpy.data.materials.new("Floor")
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = (0.05, 0.055, 0.07, 1)
    bsdf.inputs["Roughness"].default_value = 0.8
    bpy.context.object.data.materials.append(mat)


def flipbook_material(name, image, tint):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    if hasattr(mat, "surface_render_method"):
        mat.surface_render_method = "BLENDED"
    if hasattr(mat, "blend_method"):
        mat.blend_method = "BLEND"
    nt = mat.node_tree
    nt.nodes.clear()
    uv = nt.nodes.new("ShaderNodeTexCoord")
    mapping = nt.nodes.new("ShaderNodeMapping")
    mapping.inputs["Scale"].default_value = (1 / GRID, 1 / GRID, 1)
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = image
    tex.interpolation = "Linear"
    tex.extension = "CLIP"
    tint_node = nt.nodes.new("ShaderNodeMixRGB")
    tint_node.blend_type = "MULTIPLY"
    tint_node.inputs["Fac"].default_value = 1
    tint_node.inputs["Color2"].default_value = (*tint, 1)
    emit = nt.nodes.new("ShaderNodeEmission")
    emit.inputs["Strength"].default_value = 1.8
    clear = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    L = nt.links.new
    L(uv.outputs["UV"], mapping.inputs["Vector"])
    L(mapping.outputs["Vector"], tex.inputs["Vector"])
    L(tex.outputs["Color"], tint_node.inputs["Color1"])
    L(tint_node.outputs["Color"], emit.inputs["Color"])
    L(tex.outputs["Alpha"], mix.inputs["Fac"])
    L(clear.outputs[0], mix.inputs[1])
    L(emit.outputs[0], mix.inputs[2])
    L(mix.outputs[0], out.inputs["Surface"])

    # Step through the grid: frame k sits at column k % 4, row k // 4 counted from the top.
    loc = mapping.inputs["Location"]
    total = GRID * GRID
    for k in range(total + 1):
        cell = min(k, total - 1)
        col, row = cell % GRID, cell // GRID
        loc.default_value = (col / GRID, (GRID - 1 - row) / GRID, 0)
        loc.keyframe_insert("default_value", frame=1 + k * HOLD)
    # Hidden after the last cell (an empty corner of nothing) until the loop restarts.
    loc.default_value = (5, 5, 0)
    loc.keyframe_insert("default_value", frame=1 + total * HOLD)
    action = nt.animation_data.action
    curves = action.fcurves if hasattr(action, "fcurves") else [c for layer in action.layers for strip in layer.strips for bag in strip.channelbags for c in bag.fcurves]
    for fc in curves:
        for kp in fc.keyframe_points:
            kp.interpolation = "CONSTANT"
    return mat


def card(name, image, tint, x):
    bpy.ops.mesh.primitive_plane_add(size=6, location=(x, 0, 3.2), rotation=(1.5708, 0, 0))
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(flipbook_material(name, image, tint))
    # a soft ground glow under the card, like the references' floor stain
    bpy.ops.mesh.primitive_circle_add(radius=3, fill_type="NGON", location=(x, 0, 0.01))
    glow = bpy.context.object
    m = bpy.data.materials.new(name + "Stain")
    m.use_nodes = True
    if hasattr(m, "surface_render_method"):
        m.surface_render_method = "BLENDED"
    if hasattr(m, "blend_method"):
        m.blend_method = "BLEND"
    nt = m.node_tree
    nt.nodes.clear()
    grad = nt.nodes.new("ShaderNodeTexGradient")
    grad.gradient_type = "SPHERICAL"
    tc = nt.nodes.new("ShaderNodeTexCoord")
    mp = nt.nodes.new("ShaderNodeMapping")
    mp.inputs["Scale"].default_value = (0.33, 0.33, 0.33)
    emit = nt.nodes.new("ShaderNodeEmission")
    emit.inputs["Color"].default_value = (*tint, 1)
    emit.inputs["Strength"].default_value = 0.35
    clear = nt.nodes.new("ShaderNodeBsdfTransparent")
    mix = nt.nodes.new("ShaderNodeMixShader")
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    nt.links.new(tc.outputs["Object"], mp.inputs["Vector"])
    nt.links.new(mp.outputs["Vector"], grad.inputs["Vector"])
    falloff = nt.nodes.new("ShaderNodeMath")              # squared: a soft glow, not a disc
    falloff.operation = "POWER"
    falloff.inputs[1].default_value = 3.0
    nt.links.new(grad.outputs["Fac"], falloff.inputs[0])
    nt.links.new(falloff.outputs[0], mix.inputs["Fac"])
    nt.links.new(clear.outputs[0], mix.inputs[1])
    nt.links.new(emit.outputs[0], mix.inputs[2])
    nt.links.new(mix.outputs[0], out.inputs["Surface"])
    glow.data.materials.append(m)


def camera():
    bpy.ops.object.camera_add(location=(0, -21, 5.5), rotation=(1.47, 0, 0))
    bpy.context.scene.camera = bpy.context.object
    bpy.ops.object.light_add(type="AREA", location=(0, -4, 10))
    bpy.context.object.data.energy = 300


def main():
    path = flipbook_path()
    if not os.path.exists(path):
        raise FileNotFoundError(f"Flipbook not found: {path}. Pass it after '--'.")
    scene = reset_scene()
    image = bpy.data.images.load(path)
    image.alpha_mode = "STRAIGHT"
    floor()
    for i, (name, tint) in enumerate(TINTS.items()):
        card(name, image, tint, -3.5 + i * 7)
    camera()
    add_glare(scene)
    scene.frame_set(1)
    if not bpy.app.background:
        bpy.ops.screen.animation_play()
    print("Flipbook preview ready:", path)


main()
