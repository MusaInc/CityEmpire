"""Select the fixed playable character and wardrobe for the runtime GLB."""


def playable_mesh(name, body):
    identity, silhouette = ('jules', 'bun') if body == 'b' else ('ade', 'crop')
    if name.startswith('Face_'):
        return name == 'Face_' + identity
    if name.startswith(('Hair_', 'Groom_')):
        _, style, face = name.split('_', 2)
        # Hats use their fitted under-cap hair geometry automatically.
        return face == identity and style in {silhouette, 'buzz', 'crop'}
    if name.startswith('Acc_'):
        return name.endswith('_' + identity)
    return not name.startswith('Build ')


def export_playable(bpy, rig, meshes, destination, body):
    bpy.ops.object.select_all(action='DESELECT')
    hidden = {obj.name: obj.hide_get() for obj in meshes}
    try:
        rig.select_set(True)
        for obj in meshes:
            if playable_mesh(obj.name, body):
                obj.hide_set(False)
                obj.select_set(True)
        bpy.ops.export_scene.gltf(filepath=str(destination), export_format='GLB',
            use_selection=True, export_apply=False, export_yup=True,
            export_materials='EXPORT', export_skins=True, export_animations=False)
    finally:
        bpy.ops.object.select_all(action='DESELECT')
        for obj in meshes:
            obj.hide_set(hidden[obj.name])
