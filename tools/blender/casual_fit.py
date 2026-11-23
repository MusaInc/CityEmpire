"""Fit the red leather and grey lounge outfits to the finished Build B rig."""
from mathutils import Vector

from wardrobe_quality import adjust_basis, smooth


def finish_casual_fit(bpy, meshes, rig):
    import bmesh
    from garment_kit import iso_cut

    models = {obj.name: obj for obj in meshes}
    joints = {bone.name[2:]: bone.head_local for bone in rig.data.bones}
    belly = bpy.data.objects['Build B anatomy study'].copy()
    belly.data = belly.data.copy()
    belly.name = 'Fashion_Racer_Midriff'
    bpy.context.collection.objects.link(belly)
    surface = bmesh.new()
    surface.from_mesh(belly.data)
    iso_cut(surface, lambda p: min(p.z - .975, 1.515 - p.z,
                                   .173 - .058 * smooth(1.14, 1.40, p.z) - abs(p.x)))
    for vertex in surface.verts:
        p = vertex.co
        tuck = .21 * (1 - smooth(1.003, 1.047, p.z))
        p.x *= 1 - tuck
        p.y += (.020 - p.y) * tuck
    surface.to_mesh(belly.data)
    surface.free()
    belly.data.materials.clear()
    belly.data.materials.append(bpy.data.materials['hero_skin_body'])
    if len(belly.data.uv_layers) == 1:
        belly.data.uv_layers.new(name='ClothFreedom')
    belly.hide_render = False
    belly.hide_set(True)

    def tuck_strap(p):
        edge = smooth(.057, .105, abs(p.x)) * smooth(1.283, 1.412, p.z)
        return Vector((-p.x * .25 * edge, (.023 - p.y) * .32 * edge, -.011 * edge))

    adjust_basis(models['Topx_Fashion_Racer_Under'], tuck_strap)

    def straight_denim(p):
        side = 'l' if p.x < 0 else 'r'
        ankle, knee = joints['foot_' + side], joints['shin_' + side]
        t = (p.z - ankle.z) / (knee.z - ankle.z)
        axis = ankle.lerp(knee, t)
        drape = 1 - smooth(.24, .63, p.z)
        cuff = .13 * (1 - smooth(.12, .20, p.z))
        return Vector(((p.x-axis.x) * (.38 * drape + cuff), (p.y-axis.y) * .16 * drape, 0))

    adjust_basis(models['Lower_widejeans'], straight_denim)

    def fleece_ease(p):
        torso = 1 - smooth(.157, .245, abs(p.x))
        body = smooth(.973, 1.078, p.z) * (1 - smooth(1.289, 1.466, p.z))
        sleeve = smooth(.196, .301, abs(p.x)) * smooth(1.015, 1.175, p.z)
        return Vector((p.x * .14 * body * torso, (p.y - .022) * (.21 * body * torso + .17 * sleeve), 0))

    for name, obj in models.items():
        if name.startswith(('Top_Fashion_Pullover', 'Topx_Fashion_Pullover_')):
            adjust_basis(obj, fleece_ease)
    hood = models['Topx_Fashion_Pullover_Hood']
    material = hood.data.materials[0].copy()
    material.name = 'hero_fashion_top_fleece_hood'
    hood.data.materials[0] = material
    return belly
