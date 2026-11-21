"""Bake anatomical finger flexion from the original full MakeHuman hand rig."""


def hand_grips(hand, vertex_ids):
    hand.shape_key_add(name='Basis')
    for side, suffix in [('l', '.R'), ('r', '.L')]:
        key = hand.shape_key_add(name='Grip_' + side)
        hand_name = 'hand_' + side
        origin, orient, scale = trans[hand_name]
        wrist = J[hand_name]
        palm_axis = (wrist - J['forearm_' + side]).normalized()
        palm_normal = Vector((0, 1, 0))

        def joint(bone, end='head'):
            relative = orient @ (coord(source_joint(bone, end)) - origin) * scale
            along = relative.dot(palm_axis)
            finger = max(0.0,min(1.0,(along-.065)/.065))
            length = along - max(0.0,along-.085)*.1
            return wrist + palm_axis*(length*.97)+(relative-palm_axis*along)*(.98-.065*finger)

        vertices = {source: i for i, source in enumerate(vertex_ids)}
        displacement = {}
        for finger, flex in enumerate(((.29, .41, .36), (.69, 1.1, .73), (.78, 1.18, .78),
                                       (.87, 1.22, .82), (.94, 1.27, .86)), start=1):
            cumulative = Matrix.Identity(4)
            for segment, angle in enumerate(flex, start=1):
                bone = 'finger%d-%d%s' % (finger, segment, suffix)
                pivot = joint(bone)
                direction = (joint(bone, 'tail') - pivot).normalized()
                inward = palm_normal if finger != 1 else (wrist + palm_axis * .08 - pivot).normalized()
                axis = direction.cross(inward).normalized()
                cumulative = (cumulative @ Matrix.Translation(pivot)
                              @ Matrix.Rotation(angle, 4, axis) @ Matrix.Translation(-pivot))
                for source, weight in raw_weights[bone]:
                    i = vertices.get(source)
                    if i is None:
                        continue
                    p = hand.data.vertices[i].co
                    displacement[i] = displacement.get(i, Vector()) + (cumulative @ p - p) * weight
        for i, delta in displacement.items():
            key.data[i].co += delta



def bend_corrective(ob, kind):
    """Add a localized volume-and-fold correction at each limb bend."""
    ob.shape_key_add(name='Basis')
    for side in ('l','r'):
        name = 'Bend_' + kind + '_' + side
        key = ob.shape_key_add(name=name)
        pivot = J[('shin_' if kind=='Knee' else 'forearm_')+side]
        axis = (pivot-J[('thigh_' if kind=='Knee' else 'upper_arm_')+side]).normalized()
        for vert in ob.data.vertices:
            pos = vert.co
            if (pos.x<0)!=(side=='l'):
                continue
            offset = pos-pivot
            along = offset.dot(axis)
            radial = offset-axis*along
            if abs(along)>.105 or radial.length>.115:
                continue
            mask = math.exp(-(along/.058)**2)
            outside = max(0.0,min(1.0,radial.y/.056))
            crease = math.exp(-((along+.022)/.012)**2)
            back = max(0.0,min(1.0,-radial.y/.047))
            fullness = .0045*mask+.0038*mask*outside-.0023*back*crease
            key.data[vert.index].co += radial.normalized()*fullness
