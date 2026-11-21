"""Lower-body garments, trainer details and textile bakes for both builds."""

_TEXTILE_TILES = {}
_TEXTILE_COORDS = {
    'jeans': (0, 1), 'joggers': (1, 1), 'shorts': (0, 0), 'trainer': (1, 0),
}


def textile_grain(style, P, N):
    """Blend planar textile swatches into the garment's packed material."""
    if not _TEXTILE_TILES:
        source = image_load(SRC/'fabric-swatch-atlas.jpg')
        w, h = source.size
        rgba = np.empty(w*h*4, np.float32)
        source.pixels.foreach_get(rgba)
        grey = rgba.reshape(h, w, 4)[..., 0]
        for name, (u, v) in _TEXTILE_COORDS.items():
            tile = grey[v*h//2+10:(v+1)*h//2-10, u*w//2+10:(u+1)*w//2-10].copy()
            _TEXTILE_TILES[name] = np.clip((tile-tile.mean())/max(.016, tile.std()), -2.3, 2.3)
        bpy.data.images.remove(source)
    tile = _TEXTILE_TILES[style]
    scale = {'jeans': 5.0, 'joggers': 5.5, 'shorts': 5.0, 'trainer': 5.7}[style]
    def sample(u, v):
        col = np.abs(np.mod(u*scale, 2)-1)*(tile.shape[1]-1)
        row = np.abs(np.mod(v*scale, 2)-1)*(tile.shape[0]-1)
        u0, v0 = col.astype(int), row.astype(int)
        u1 = np.minimum(u0+1, tile.shape[1]-1)
        v1 = np.minimum(v0+1, tile.shape[0]-1)
        a, b = col-u0, row-v0
        return (tile[v0,u0]*(1-a)+tile[v0,u1]*a)*(1-b)+(tile[v1,u0]*(1-a)+tile[v1,u1]*a)*b
    x, y, z = P.T
    blend = np.abs(N)**3
    blend /= np.maximum(blend.sum(1), 1e-5)[:,None]
    return .035*(blend[:,0]*sample(y,z) + blend[:,1]*sample(x,z) + blend[:,2]*sample(x,y))


def chinos_from_block(block):
    """The two cuts share the waist, seat and weights. Taper only below the hip."""
    cut = block.copy()
    cut.data = block.data.copy()
    cut.name = 'Courier_Chinos'
    bpy.context.collection.objects.link(cut)
    for v in cut.data.vertices:
        p = v.co
        side = 'l' if p.x < 0 else 'r'
        z = p.z
        knee = J['shin_' + side]
        hip = J['thigh_' + side]
        foot = J['foot_' + side]
        axis = knee.lerp(foot, (knee.z - z) / (knee.z - foot.z)) if z < knee.z else hip.lerp(knee, (hip.z - z) / (hip.z - knee.z))
        ease = max(0.0, min(1.0, (.88 - z) / .18))
        p.x = axis.x + (p.x - axis.x) * (1.0 - .16 * ease)
        p.y *= 1.0 - .10 * ease
        p.z -= .004 * ease
    pack_uvs(cut)

    def height(P, N):
        x, y, z = P.T
        axis = np.interp(z, [J['foot_r'].z, J['shin_r'].z, J['thigh_r'].z],
                         [J['foot_r'].x, J['shin_r'].x, J['thigh_r'].x])
        dx = np.abs(x) - axis
        length = np.clip((.96-z)/.07,0,1)*np.clip((z-.084)/.05,0,1)
        side = np.clip((np.abs(dx) - .035) / .035, 0, 1)
        h = length * side * seam_height(y, z, stitch_off=.0028)
        h += np.clip(N[:,1],0,1) * length * .00065 * np.exp(-(dx/.012)**2)
        ankle = z-.153-.36*dx
        h += .00047*np.exp(-(ankle/.009)**2)-.00025*np.exp(-((ankle-.016)/.014)**2)
        knee = z-.51+.25*dx
        h += (.00055*np.exp(-(knee/.012)**2)-.00028*np.exp(-((knee-.018)/.014)**2)) * np.clip(-N[:,1],0,1)
        pockets = (z > .81) & (z < 1.001) & (y > .035)
        h[pockets] += seam_height((z + np.abs(x)*.8 - 1.04)[pockets], x[pockets], stitch_len=.003)
        fly = (z > .88) & (z < PANTS_TOP) & (y > .038)
        h[fly] += seam_height((x-.018)[fly], z[fly], stitch_off=.0035)
        h += seam_height(z-.095, dx, stitch_off=0, groove=.0001)
        return h.astype(np.float32)

    def albedo(P, N, H):
        n = np.clip(.90 + H*52 + .012*np.sin(P[:,0]*71+P[:,2]*129), .76, .97)
        return np.stack([n, n*.992, n*.973], 1)

    normal, colour = bake_detail(cut, 'chino_twill', 768, height, albedo)
    mat = material('hero_chino', (.24, .26, .28), .82, colour, normal)
    mat.node_tree.nodes['Normal Map'].inputs['Strength'].default_value = .78
    cut.data.materials.clear()
    finish(cut, [mat], rim=.0025)
    return cut


def finish_trainer(shoes):
    """Bake unbranded mono-mesh, toe overlay, counter and the stitched welt."""
    def coordinates(P):
        x, y, z = P.T
        local_x = np.abs(x) - J['foot_r'].x
        toe = .115 - .9 * local_x**2
        toe_seam = (y - toe + .52 * np.abs(local_x))
        heel_seam = y + .026 + .29 * np.abs(local_x)
        upper = (z > .037).astype(float)
        return local_x, y, z, toe_seam, heel_seam, upper

    def height(P, N):
        x, y, z, toe, heel, upper = coordinates(P)
        h = upper * (seam_height(toe, x, stitch_off=.0024, stitch_h=.00025)
                     + seam_height(heel, z, stitch_off=.0025, stitch_h=.00024))
        h += seam_height(z-.037, y, groove=.00033, stitch_off=.0015, stitch_h=.00027)
        h += .00021 * np.sin(y*548+x*242) * np.sin(z*610-x*213) * upper
        return h

    def albedo(P, N, H):
        x, y, z, toe, heel, upper = coordinates(P)
        toe_piece = np.clip((toe+.006)*170,0,1)
        heel_piece = np.clip((.004-heel)*160,0,1)
        foxing = np.exp(-((z-.027)/.008)**2)
        knit = np.sin(x*745+y*379)*np.sin(z*716+y*239)
        grain = textile_grain('trainer', P, N)
        tone = np.clip(.84 + .06*toe_piece - .10*heel_piece + .10*foxing + (.014*knit+grain)*upper + H*48, .63, .98)
        return np.stack([tone, tone*.99, tone*.968], 1)

    normal, albedo_map = bake_detail(shoes, 'trainer_panels', 1024, height, albedo)
    mat = material('hero_trainer_panels', (.8, .8, .8), .62, albedo_map, normal)
    mat.node_tree.nodes['Normal Map'].inputs['Strength'].default_value = .8
    shoes.data.materials.clear()
    shoes.data.materials.append(mat)


def stitch_panel(name, garment, outline, material_, clearance=.0042, front=True):
    """Lay a sewn panel against the garment and inherit its deform weights.

    The outline runs from the closed bottom of the pocket to its free top.
    Return a single curved fabric piece with a solid cut edge.
    """
    tree = tree_of(garment)
    direction = Vector((0, 1 if front else -1, 0))
    points, uvs = [], []
    for index, (left, right, depth, z) in enumerate(outline):
        row = []
        for j in range(11):
            t = j / 10
            x = left + (right-left)*t
            hit, _, _, _ = tree.ray_cast(Vector((x, .40 * direction.y, z)), -direction)
            if hit is None:
                return None
            crown = depth * math.sin(math.pi*t)
            row.append(hit + direction * (clearance + crown))
        points.append(row)
        uvs.append([(j/10, .755 + .24*index/(len(outline)-1)) for j in range(11)])
    ob = grid_mesh(name, points, uvs)
    face_out(ob, lambda _: direction)
    weights_from(ob, garment)
    finish(ob, [material_], rim=.0018)
    return ob


def lower_cut(block, style):
    """Three separately fitted cuts, with a common waist and articulated knees."""
    cut = block.copy()
    cut.data = block.data.copy()
    cut.name = 'Lower_' + style
    bpy.context.collection.objects.link(cut)

    def shorts_hem(x, y):
        knee_x = J['shin_r'].x
        local = (abs(x)-knee_x)/.104
        return .594 - .012*np.clip(local,-1,1) + .011*np.clip(y/.115,-1,1)

    if style == 'shorts':
        bm = bmesh.new()
        bm.from_mesh(cut.data)
        iso_cut(bm, lambda co: co.z-float(shorts_hem(co.x,co.y)))
        bm.to_mesh(cut.data)
        bm.free()
        cut.data.update()
    for vertex in cut.data.vertices:
        p = vertex.co
        z = p.z
        knee = J['shin_l' if p.x < 0 else 'shin_r']
        ankle = J['foot_l' if p.x < 0 else 'foot_r']
        hip = J['thigh_l' if p.x < 0 else 'thigh_r']
        if z < knee.z:
            axis = ankle.lerp(knee, (z-ankle.z)/(knee.z-ankle.z))
        else:
            axis = knee.lerp(hip, (z-knee.z)/(hip.z-knee.z))
        t = max(0, min(1, (.92-z)/.23))
        edge = max(0, min(1, (.20-z)/.11))
        taper = max(0, min(1, (.72-z)/.29))
        knee_volume = math.exp(-((z-knee.z-.025)/.105)**2)
        delta = abs(p.x)-abs(axis.x)
        knee_fold = (math.exp(-((z-.522-.28*delta)/.026)**2)
                     - .44*math.exp(-((z-.481+.19*delta)/.031)**2))
        front = max(0, min(1, (p.y+.015)/.10))
        fold = front*knee_fold
        if style == 'jeans':
            sx, sy = 1-.15*t+.055*knee_volume, 1-.06*t
            bend = .0036*t*fold
        elif style == 'joggers':
            sx, sy = 1+.025*t+.055*knee_volume-.16*edge, 1+.055*t-.19*edge
            ankle_fold = math.exp(-((z-.164-.41*delta)/.024)**2)
            bend = .0033*fold+.0053*front*ankle_fold
        else:
            hem_taper = max(0, min(1, (.71-z)/.105))
            sx, sy = 1+.035*t-.13*hem_taper, 1+.025*t-.055*hem_taper
            bend = .0029*front*math.exp(-((z-.691+.28*delta)/.031)**2)
        p.x = axis.x + (p.x-axis.x)*sx
        p.y = p.y*sy + bend
        if style == 'shorts':
            inner = math.exp(-(p.x/.092)**2-(p.y/.074)**2-((z-.818)/.071)**2)
            p.z += .0088*inner
        elif z < .41:
            p.x += math.copysign(.004*taper*math.exp(-((z-.289)/.082)**2),p.x)
    if style == 'shorts':
        enforce_skin_clearance(cut, lambda co: co.z < .695, .0095, .024)
    pack_uvs(cut)

    def coordinates(P):
        x, y, z = P.T
        dx = np.abs(x) - np.interp(z, [J['foot_r'].z, J['shin_r'].z, J['thigh_r'].z],
                                   [J['foot_r'].x, J['shin_r'].x, J['thigh_r'].x])
        return x, y, z, dx

    def height(P, N):
        x, y, z, dx = coordinates(P)
        hem = shorts_hem(x,y) if style == 'shorts' else .106
        taper = np.clip((.965-z)/.07,0,1) * np.clip((z-hem)/.06,0,1)
        outer = np.clip(np.abs(dx)/.06-.25, 0, 1)
        sewn = seam_height(y-.010, z, stitch_off=.0042 if style == 'jeans' else .003)
        pocket = seam_height(z-.94+np.abs(x)*.48, x, stitch_off=.003)
        pocket *= (y>.045) * (np.abs(x)>.075) * (z>.82)
        fly = seam_height(x-.017, z, stitch_off=.0038) * (y>.060) * (z>.865)
        knee = z-.513-.37*dx
        folds = .00055*np.exp(-(knee/.013)**2) - .00040*np.exp(-((knee-.019)/.015)**2)
        folds *= np.exp(-(dx/.076)**2) * np.clip(N[:,1],0,1)
        tension = z-.809-.44*dx
        folds += .00036*np.exp(-(tension/.015)**2-(dx/.072)**2)*np.clip(N[:,1],0,1)
        if style == 'joggers':
            ankle = z-.163-.48*dx+.09*y
            folds += .00058*np.exp(-(ankle/.01)**2)-.00031*np.exp(-((ankle-.017)/.012)**2)
        return taper*outer*sewn+pocket+fly+folds+seam_height(z-hem-.013,dx,stitch_off=.003)

    def colour(P, N, H):
        x, y, z, dx = coordinates(P)
        tone = .90 + np.clip(H*68,-.14,.1)
        if style == 'jeans':
            wear = np.exp(-((z-.64)/.22)**2 - (dx/.052)**2) * np.clip(N[:, 1], 0, 1)
            tone = tone*.82 + .178*wear
        elif style == 'joggers':
            tone += .008*np.sin(z*49+x*53)*np.sin(y*77+z*55)
        tone += .62*textile_grain(style, P, N)
        value = np.clip(tone, .61, .995)
        return np.stack([value, value*.99, value*.974], axis=1)

    normal, albedo = bake_detail(cut, style, 768, height, colour)
    mat = material('hero_' + style, (.23, .25, .29), .85, albedo, normal)
    mat.node_tree.nodes['Normal Map'].inputs['Strength'].default_value = .63
    cut.data.materials.clear()
    result = [cut]
    if style == 'jeans':
        # Five-pocket denim: shaped on the seat, with a double topstitch atlas.
        denim_trim = material('hero_denim_trim', (.22, .24, .27), .88, TRIM_A, TRIM_N)
        denim_trim.node_tree.nodes['Normal Map'].inputs['Strength'].default_value = .64
        pockets = []
        for side in (-1, 1):
            rows = [(.063,.118,.000,.813),(.052,.130,.0019,.823),
                    (.047,.136,.0036,.837),(.043,.139,.0045,.853),
                    (.042,.141,.0048,.870),(.041,.140,.0037,.888),(.041,.137,.0021,.901)]
            outline = [(l, r, d, z) if side == 1 else (-r, -l, d, z)
                       for l, r, d, z in rows]
            # Back panels are projected toward +Y from the rear.
            panel = stitch_panel('DenimPocket', cut, outline, denim_trim, front=False)
            if panel is not None:
                pockets.append(panel)
        if pockets:
            result.append(join_as('Lower_jeans_Pockets', pockets))
    finish(cut, [mat], rim=.003 if style != 'joggers' else .0035)
    return result


def add_short_skin():
    """Skin from inside each hem down into the shoe opening."""
    leg_faces = [i for i in body if all(.060 < RB[j].z < .692 for j in bf[i])]
    skin, _ = part('Lower_shorts_Legs', leg_faces, RB, weights)
    skin.data.materials.append(armskin)
    add(skin, False)


def trainer_laces(shoes):
    """Model crossed flat laces on both shoe lasts, skinned to each foot."""
    hull = tree_of(shoes)
    lace = material('hero_lace', (.78, .77, .74), .86)
    parts = []
    for side in ('l', 'r'):
        axis = J['foot_' + side].x
        for row in range(4):
            for cross in (-1, 1):
                points, texcoords = [], []
                for i in range(7):
                    t = i/6
                    x = axis + cross * (.025 - .050*t)
                    y = .050 + row*.014 + (t if cross>0 else 1-t)*.013
                    hit, _, _, _ = hull.ray_cast(Vector((x,y,.35)), Vector((0,0,-1)))
                    if hit is None:
                        break
                    if hit.z < .055:
                        break
                    lift = .0040 + .0022*math.sin(math.pi*t) + (.001 if cross>0 else 0)
                    points.append([hit + Vector((0, - .0018, lift)), hit + Vector((0, .0018, lift))])
                    texcoords.append([(t, 0), (t, 1)])
                if len(points) != 7:
                    continue
                ob = grid_mesh('Flat lace', points, texcoords)
                face_out(ob, lambda _: Vector((0,0,1)))
                weights_from(ob, shoes)
                finish(ob, [lace], rim=.0012)
                parts.append(ob)
    if parts:
        return join_as('Courier_TrainerLaces', parts)
    return None


def trainer_construction(upper):
    """Separate rubber tread, foam, tongue, and eyestays on the fitted lasts."""
    hull = tree_of(upper)
    foam = material('hero_midsole', (.77,.75,.70), .73)
    rubber = material('hero_outsole', (.062,.059,.053), .89)
    tongue_mat = material('hero_trainer_tongue', (.60,.61,.60), .87, normal=TRIM_N)
    eyelet_mat = material('hero_trainer_eyelet', (.69,.70,.69), .70, normal=TRIM_N)

    def fasten(ob, side):
        vg = ob.vertex_groups.new(name='b_foot_'+side)
        vg.add(list(range(len(ob.data.vertices))),1.0,'REPLACE')

    soles = []
    panels = []
    for side in ('l','r'):
        x = J['foot_'+side].x
        centre = Vector((x,.063,0))
        outline = []
        for j in range(56):
            angle = math.tau*j/56
            direction = Vector((math.sin(angle),math.cos(angle),0))
            radii = []
            for z in (.013,.024,.034,.043):
                origin = centre+Vector((0,0,z))
                hit, _, _, _ = hull.ray_cast(origin+direction*.24, -direction)
                if hit is not None and (hit.x<0)==(x<0):
                    distance = (hit-origin).dot(direction)
                    if 0 < distance < .17:
                        radii.append(distance)
            outline.append(max(radii) if radii else .047)
        smooth = fourier_smooth(outline, 13)
        # Toe spring is built into the last. The heel and forefoot retain
        # their original ground contact heights for the gait solver.
        rows, uv = [], []
        for z, flare in ((-.0025,-.0035),(.0035,-.0012),(.0110,.0009),
                         (.0190,.0022),(.0285,.0031),(.0355,.0010)):
            row, texcoords = [], []
            for j, r in enumerate(list(smooth)+[smooth[0]]):
                angle = j*math.tau/56
                co = centre+Vector((math.sin(angle)*(r+flare),math.cos(angle)*(r+flare), z))
                spring = max(0.0,(co.y-.156)/.075)
                co.z += .013*spring*spring
                if z < .012:
                    co.x += math.sin(angle)*.0010*(j%4==1)
                    co.y += math.cos(angle)*.0010*(j%4==1)
                row.append(co)
                texcoords.append((j/56,(z+.0025)/.039))
            rows.append(row)
            uv.append(texcoords)
        sole = grid_mesh('Moulded sole',rows,uv)
        face_out(sole,lambda c: Vector((c.x-centre.x,c.y-centre.y,0)))
        sole.data.materials.append(foam)
        sole.data.materials.append(rubber)
        for poly in sole.data.polygons:
            poly.material_index = 1 if poly.index // 56 < 2 else 0
        # Close the sole underside. The hidden upper contact is embedded in
        # the mesh skin and the rolled edge overhangs the cut upper by 1 mm.
        down = [centre+Vector((0,0,-.0026))] + rows[0][:-1]
        count = len(down)-1
        triangles = [(0,1+j,1+(j+1)%count) for j in range(count)]
        footbed = mesh('Rubber outsole',down,[],triangles,[])
        face_out(footbed,lambda _: Vector((0,0,-1)))
        footbed.data.materials.append(rubber)
        fasten(sole,side)
        fasten(footbed,side)
        soles.extend([sole,footbed])

        def upper_piece(name, lo, hi, direction=None):
            rows, uv = [], []
            for i in range(11):
                t = i/10
                y = lo+(hi-lo)*t
                row = []
                for j in range(7):
                    u = j/6
                    across = (u-.5)*(.045-.012*t**5)
                    if direction is not None:
                        across = direction*(.017+.014*u+.008*t)
                    hit,_,_,_ = hull.ray_cast(Vector((x+across,y,.27)),Vector((0,0,-1)))
                    if hit is None or hit.z < .044:
                        break
                    loft = .0017+.0021*math.sin(math.pi*u)*math.sin(math.pi*t)
                    row.append(hit+Vector((0,0,loft)))
                if len(row)==7:
                    rows.append(row)
                    uv.append([(j/6,.76+.22*t) for j in range(7)])
            if len(rows)<3:
                return None
            ob = grid_mesh(name,rows,uv)
            face_out(ob,lambda _: Vector((0,0,1)))
            weights_from(ob,upper)
            finish(ob,[tongue_mat if direction is None else eyelet_mat],rim=.0016)
            return ob
        for part_ in [upper_piece('Padded tongue',.047,.139),
                      upper_piece('Eyestay',.048,.119,-1),
                      upper_piece('Eyestay',.048,.119,1)]:
            if part_ is not None:
                panels.append(part_)
    # Cut the former monolithic sole away, with the cut edge inside the foam.
    bm = bmesh.new()
    bm.from_mesh(upper.data)
    _bisect(bm,(0,0,.0315),(0,0,1),lambda co: co.z<.03149)
    bm.to_mesh(upper.data)
    bm.free()
    upper.data.update()
    result = [join_as('Courier_Soles',soles)]
    if panels:
        result.append(join_as('Courier_TrainerTongues',panels))
    return result


def cargo_pocket(pants, side):
    """Raised box pocket with a separately sewn flap over the opening."""
    sign = -1 if side=='l' else 1
    hull = tree_of(pants)
    cloth = bpy.data.materials.get('hero_cargo_pocket') or material('hero_cargo_pocket',(.23,.24,.25),.86,TRIM_A,TRIM_N)
    parts = []
    for is_flap in (False, True):
        points, uv = [], []
        for j in range(7):
            t = j/6
            z = (.748+.042*t) if is_flap else (.620+.151*t)
            width = (.071 if is_flap else .065) * (.91+.09*math.sin(math.pi*t))
            row = []
            for k in range(13):
                u = k/12
                y = .004+(u*2-1)*width
                hit,_,_,_ = hull.ray_cast(Vector((sign*.4,y,z)),Vector((-sign,0,0)))
                for shrink in (.82,.67,.51):
                    if hit is not None:
                        break
                    hit,_,_,_ = hull.ray_cast(Vector((sign*.4,y*shrink,z)),Vector((-sign,0,0)))
                if hit is None:
                    return None
                crown = math.sin(math.pi*u)**.52
                sewn = (.0046+.014*crown*(.82+.18*t)) if not is_flap else (.0065+.017*crown)
                if is_flap:
                    hit.z += .012*(abs(u-.5)*2)**3*(1-t)
                row.append(hit+Vector((sign*sewn,0,0)))
            points.append(row)
            uv.append([(k/12*.65,.759+.231*t) for k in range(13)])
        ob = grid_mesh('Cargo flap' if is_flap else 'Box pocket',points,uv)
        face_out(ob,lambda _: Vector((sign,0,0)))
        weights_from(ob,pants)
        finish(ob,[cloth],rim=.0021 if is_flap else .0029)
        parts.append(ob)
    return join_as('Cargo_gusset_'+side,parts)
