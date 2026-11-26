"""Blender patterns for WorldState's fitted separates and one-piece outfits.

This file is loaded by the character builder after its body, fitting tools,
wardrobe materials and skinning weights have been built.
"""

from wardrobe_quality import smooth


FASHION_FABRICS = {
    'jersey': (.83, 'joggers', .82),
    'rib': (.88, 'joggers', .93),
    'cotton': (.78, 'shorts', .59),
    'denim': (.84, 'jeans', .78),
    'satin': (.43, 'joggers', .30),
    'crepe': (.71, 'shorts', .56),
    'linen': (.89, 'shorts', .83),
    'leather': (.49, 'shorts', .24),
}


def fashion_material(ob, slot, fabric, hem, sleeve):
    """Bake the seam and textile scale for each cut's packed UVs."""
    rough, swatch, grain = FASHION_FABRICS[fabric]
    pack_uvs(ob)
    sewing = seams_fn(lambda _: hem, sleeve)
    def relief(pos, normal):
        z = pos[:,2]
        grain = .000081 * leather_grain(pos) if fabric == 'leather' else 0
        return sewing(pos,normal)+seam_height(z-hem-.011,pos[:,0],stitch_off=.0026)*np.clip((hem+.044-z)/.03,0,1)+grain
    def albedo(pos, normal, value):
        tone = .94 + grain*textile_grain(swatch,pos,normal) + np.clip(value*25,-.10,.04)
        tone = np.clip(tone,.76,.995)
        return np.stack((tone,tone*.992,tone*.977),1)
    key = ob.name.lower()
    normal, colour = bake_detail(ob,key,512,relief,albedo)
    mat = material('hero_fashion_'+slot+'_'+fabric+'_'+key,(.18,.18,.19),rough,colour,normal)
    mat.node_tree.nodes['Normal Map'].inputs['Strength'].default_value = .65 if fabric=='satin' else .82
    return mat


def fashion_skin(name, lo, hi, upper):
    allowed = []
    face_area = set(face_faces)
    for i in body:
        if i in face_area:
            continue
        if all(lo < RB[j].z < hi and (wsum(j,'hand_l','hand_r') < .35 if upper else not armish(j))
               for j in bf[i]):
            allowed.append(i)
    ob,_ = part(name,allowed,RB,weights)
    ob.data.materials.append(armskin)
    return ob


def trim_torso_skin(ob):
    """Keep the skin needed at openings and leave the covered waist out."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    iso_cut(bm, lambda p: max(p.z-1.067, abs(p.x)-.192))
    bm.to_mesh(ob.data)
    bm.free()
    ob.data.update()


def fit_layered_insert(ob, jacket):
    """Cut the inner panel to the open front with overlap along the placket."""
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    def opening(p):
        spread = .024 + .057*max(0,min(1,(p.z-1.23)/.23))
        spread = spread*.75 if jacket else spread
        return min(p.y-.055, spread+.030-abs(p.x))
    iso_cut(bm,opening)
    bm.to_mesh(ob.data)
    bm.free()
    ob.data.update()


def fit_cardigan_hem(ob):
    """Give the knit hem enough ease to cover a high skirt waistband."""
    for v in ob.data.vertices:
        p = v.co
        waist = math.exp(-((p.z-1.030)/.059)**2)
        if abs(p.x) < .209 and p.z < 1.17:
            p.x *= 1+.094*waist
            p.y += (p.y-.030)*.33*waist
    ob.data.update()


def women_top(name, fabric, hem, neck, sleeve, shell_layer='shirt',
              shape='ordinary', tuck=False, drape=.003):
    """Cut real armholes and necklines, then transfer seam and trim weights."""
    if BODY == 'b' and shape != 'cami':
        neck = (neck[0] - .020, neck[1] - .012)
    R,Z = neck_ring_fit(neck[0],neck[1],.0044)
    sleeveless = sleeve is None
    ob = tailored_top(name,hem,neck[0],1.0,(R(math.pi/2),R(0),R(math.pi)),shell_layer,
                     sleeve_end=sleeve, neck_cy=NECK_CY, neck_curve=Z,
                     taper_front=.16,taper_side=.24,shoulder_ease=.0033,
                     sleeve_ease=(.010,.012),sleeve_taper=.115)
    if not sleeveless:
        snap_neckline(ob,R=R,Z0=Z,reach=.026)
    if sleeveless or shape in ('open','cami','jacket','racer'):
        bm = bmesh.new()
        bm.from_mesh(ob.data)

        def opening(co):
            x, y, z = co
            if sleeveless:
                shoulder = max(0,min(1,(z-1.364)/.145))
                side = (.161+.016*math.exp(-((z-1.30)/.10)**2))-(.051 if shape!='vest' else .027)*shoulder
                result = side-abs(x)
            else:
                result = 1.0
            if shape=='cami':
                result = min(result,1.435-.066*(abs(x)/.175)**1.7-z)
            if shape == 'one_shoulder':
                result = min(result, 1.430 - .76*x - z)
            if shape == 'square_neck':
                result = min(result, max(abs(x) - .068, 1.398-z, .009-(y-NECK_CY)*FRONT))
            if shape in ('open','jacket','racer'):
                gap = .024 + .057*max(0,min(1,(z-1.23)/.23))
                if shape=='racer':
                    gap = .054 + .024 * np.clip((z - 1.21) / .28, 0, 1)
                if shape=='jacket':
                    gap *= .75
                result = min(result,max(abs(x)-gap,.037-(y-NECK_CY)*FRONT))
            return result

        iso_cut(bm,opening)
        bm.to_mesh(ob.data)
        bm.free()
        ob.data.update()
    if tuck:
        tuck_into(ob,pants,PANTS_TOP,.006)
        follow_layer(ob,pants,PANTS_TOP+.023,.04,k_max=.84)
    else:
        if hem < PANTS_TOP+.03:
            clear_layer(ob,pants,.010,zmax=PANTS_TOP+.038)
        def relief(co):
            return math.exp(-((co.z-hem-.09)/.14)**2)*min(1,abs(co.x)/.13)
        def wave(co):
            return math.sin(co.x*41+co.z*13)*.7+.30*math.sin(co.y*56-co.z*17)
        fold_relief(ob,[(relief,wave,drape)])
    if sleeveless:
        clear_body(ob,.005)
    mat = fashion_material(ob,'top',fabric,hem,sleeve)
    finish(ob,[mat],rim=.0022 if fabric in ('satin','crepe') else .0030)
    simplify_surface(ob,.63)
    return ob


def shoulder_straps(body_piece, name):
    """Soft folded straps running over the real acromion."""
    skin = _btree
    mat = body_piece.data.materials[0]
    out = []
    for side in (-1,1):
        points, uv = [], []
        for i in range(19):
            t = i/18
            y = .102 - .192*t
            guessed = 1.405 + .113 * math.sin(math.pi*t)**.84
            nominal_x = side*(.079+.020*math.sin(math.pi*t))
            row = []
            for width in (-.006,.006):
                x = nominal_x+width
                hit,_,_,_ = skin.ray_cast(Vector((x,y,1.66)),Vector((0,0,-1)))
                z = guessed
                if hit is not None and abs(hit.z-guessed)<.032:
                    z = max(z,hit.z+.006)
                row.append(Vector((x,y+(.006 if t<.5 else -.006),z)))
            points.append(row)
            uv.append([(.041*t,.765),(.041*t,.976)])
        strap = grid_mesh('Cami strap',points,uv)
        face_out(strap,lambda _:Vector((0,0,1)))
        reweight(strap)
        finish(strap,[mat],rim=.0024)
        out.append(strap)
    return join_as(name,out)


def skirt_pattern(name, slot, fabric, waist, hem, flare, panel_split=False, slit_angle=-.52, waist_ease=.016):
    """Fit the skirt where it meets the hip, keeping a free hem and slit."""
    tf,_ = frames()
    rows,uv = [],[]
    columns = 65
    for j in range(15):
        t = j/14
        z0 = waist+(hem-waist)*t
        sample_z = max(.885,z0)
        cy = float(np.interp(sample_z,tf.zs,tf.cy))
        row, texcoords = [], []
        for i in range(columns):
            u = i/(columns-1)
            slit = (.081 if panel_split else .0)*max(0,(t-.59)/.41)
            a = slit + (math.tau - 2 * slit) * u + (slit_angle if panel_split else 0.0)
            hip = tf.sample(tf.hull,(sample_z-tf.Z0)/tf.DZ,a)
            # Crown the cloth at the seat. The free hem has long gored folds.
            ease = waist_ease + (.016-waist_ease)*min(1,t*6) + flare*t**1.31
            folds = (.003+.014*flare/.15)*t*t*math.cos(a*7+.4*math.sin(a*3))
            r = hip+ease+folds
            z = z0 + t*t*(.008*math.sin(a*4+.2)+.004*math.cos(a*9))
            row.append(Vector((math.sin(a)*r,cy+FRONT*math.cos(a)*r,z)))
            texcoords.append((u,t))
        rows.append(row)
        uv.append(texcoords)
    skirt = grid_mesh(name,rows,uv)
    face_out(skirt,lambda p:Vector((p.x,p.y-.01,0)))
    mat = fashion_material(skirt,slot,fabric,hem,None)
    finish(skirt,[mat],rim=.0030)
    fit_skirt_motion(skirt,waist,hem)
    return skirt


def fit_skirt_motion(skirt, waist, hem):
    """Give the panels thigh clearance and blend leg weight into the hip seam."""
    skirt.shape_key_clear()
    groups = {}
    for bone in ('hips','thigh_l','thigh_r'):
        name = 'b_'+bone
        groups[bone] = skirt.vertex_groups.get(name) or skirt.vertex_groups.new(name=name)
    short = hem > .52
    for v in skirt.data.vertices:
        p = v.co
        depth = p.y-.015
        # A round section cuts across the fronts of the individual thighs.
        # Add width between the front crease and the existing side seam.
        # Room for the thighs that grows from the hip and HOLDS to the hem (an
        # A-line). It was a bump peaking at mid-thigh (z .78) and fading by
        # the hem, so short skirts bowed out and came back in – a balloon
        # (2026-11-26).
        seat = smooth(.93, .76, p.z)
        panel = min(1, abs(depth)/.079)
        p.y += math.copysign(seat*panel*(.026 if depth*FRONT>0 else .010),depth)
        side = max(0,min(1,(abs(p.x)-.025)/.112))
        below_hip = max(0,min(1,(.966-p.z)/.232))
        share = (.36 if short else .23)*below_hip*side
        groups['hips'].add([v.index],1-share,'REPLACE')
        if share > .0001:
            groups['thigh_l' if p.x<0 else 'thigh_r'].add([v.index],share,'REPLACE')
    skirt.data.update()
    skirt.shape_key_add(name='Basis')
    for name_,direction in [('Hem_Front',1),('Hem_Back',-1)]:
        morph = skirt.shape_key_add(name=name_)
        for v in skirt.data.vertices:
            p = v.co
            drop = max(0,waist-p.z)
            along = max(0,min(1,((p.y-.015)*direction+.012)/.112))
            # Follow the upper thigh first, with a later release at the hem.
            reach = min(drop,.38)*(.91 if direction==1 else .66)
            if not short:
                reach += max(0,drop-.38)*(.28 if direction==1 else .13)
            morph.data[v.index].co.y += direction*reach*along**.64
            morph.data[v.index].co.z += (.038 if direction==1 else .013)*along*min(1,drop/.44)**2


def fitted_bottom(style):
    base_name = {'fitjeans':'jeans','tailoredshorts':'shorts','leggings':'joggers','widejeans':'jeans','bikershorts':'shorts'}[style]
    base = next(ob for ob in wardrobe if ob.name=='Lower_'+base_name)
    cloth = base.copy()
    cloth.data = base.data.copy()
    cloth.name = 'Lower_'+style
    bpy.context.collection.objects.link(cloth)
    for vertex in cloth.data.vertices:
        c = vertex.co
        side = 'l' if c.x<0 else 'r'
        foot,knee,hip = (J[n+'_'+side] for n in ('foot','shin','thigh'))
        if c.z<knee.z:
            axis = foot.lerp(knee,(c.z-foot.z)/(knee.z-foot.z))
        else:
            axis = knee.lerp(hip,(c.z-knee.z)/(hip.z-knee.z))
        taper = max(0,min(1,(.94-c.z)/.23))
        value = {'leggings': .16, 'fitjeans': .075, 'tailoredshorts': .035,
                 'widejeans': -.24, 'bikershorts': .26}[style]
        if style == 'widejeans':
            c.z -= .040 * (1 - smooth(.12, .36, c.z))
        elif style == 'bikershorts':
            c.z += .015 * (1 - smooth(.57, .76, c.z))
        gain = 1-value*taper
        c.x = axis.x+(c.x-axis.x)*gain
        c.y = axis.y+(c.y-axis.y)*gain
    enforce_skin_clearance(cloth,lambda c:c.z<.92,.007 if style=='leggings' else .012,.031)
    pack_uvs(cloth)
    fabric = 'denim' if style in ('fitjeans', 'widejeans') else 'linen' if style=='tailoredshorts' else 'rib'
    bottom = min(v.co.z for v in cloth.data.vertices)
    mat = fashion_material(cloth,'bottom',fabric,bottom,None)
    cloth.data.materials.clear()
    cloth.data.materials.append(mat)
    return cloth


def shoe_segment(name, side, profiles):
    """Oval sections along the shoe last, with a cross section for the toe."""
    centre = J['foot_'+side].x
    sign = -1 if side=='l' else 1
    points,uv = [],[]
    for j,(y,width,z_bottom,z_top) in enumerate(profiles):
        along = max(0,min(1,(y+.043)/.22))
        row = []
        for k in range(25):
            a = math.tau*k/24
            z = (z_top+z_bottom)/2 + (z_top-z_bottom)/2 * math.cos(a)
            row.append(Vector((centre-sign*.015*along+width*math.sin(a),y,z)))
        points.append(row)
        uv.append([(k/24,j/max(1,len(profiles)-1)) for k in range(25)])
    ob = grid_mesh(name,points,uv)
    bm = bmesh.new()
    bm.from_mesh(ob.data)
    bmesh.ops.remove_doubles(bm,verts=bm.verts[:],dist=.00003)
    bmesh.ops.holes_fill(bm,edges=[edge for edge in bm.edges if edge.is_boundary])
    bmesh.ops.recalc_face_normals(bm,faces=bm.faces[:])
    bm.to_mesh(ob.data)
    bm.free()
    ob.data.update()
    wg = ob.vertex_groups.new(name='b_foot_'+side)
    wg.add(list(range(len(ob.data.vertices))),1,'REPLACE')
    mid = sum((v.co for v in ob.data.vertices),Vector())/len(ob.data.vertices)
    face_out(ob,lambda p: (p-mid))
    return ob


def fashion_shoes(style):
    upper = material('hero_fashion_shoe_'+style,(.29,.27,.24),.42 if style in ('heels','boots') else .78,normal=TRIM_N)
    sole = material('hero_fashion_sole_'+style,(.115,.104,.090),.79)
    parts = []
    for side in ('l','r'):
        platform = [(-.055,.008,.013,.027),(-.043,.038,.003,.025),(.025,.043,.001,.024),
                    (.115,.052,.002,.021),(.183,.037,.003,.022),(.210,.006,.012,.022)]
        if style=='sandals':
            platform = [(-.046,.008,.010,.016),(-.036,.034,.002,.017),(.025,.041,.002,.017),
                        (.106,.049,.002,.017),(.152,.039,.003,.016),(.175,.005,.009,.016)]
        elif style=='heels':
            platform = [(-.053,.013,.052,.071),(-.042,.032,.047,.069),(.023,.032,.030,.054),
                        (.091,.046,.004,.032),(.149,.045,.002,.026),(.201,.008,.003,.018)]
        base = shoe_segment('Sole',side,platform)
        base.data.materials.append(sole)
        parts.append(base)
        if style=='sandals':
            for y,width,height in ((.026,.039,.071),(.088,.044,.047),(.127,.044,.034)):
                sign = -1 if side=='l' else 1
                centre = J['foot_'+side].x-sign*.012*min(1,y/.16)
                points = [[Vector((centre+width*math.cos(a),j,.014+(height-.014)*math.sin(a)**.73))
                           for a in (math.pi*i/12 for i in range(13))]
                          for j in (y-.008,y+.008)]
                piece = grid_mesh('Leather strap',points,[[(i/12,k) for i in range(13)] for k in (0,1)])
                face_out(piece, lambda p: Vector((p.x-centre,0,p.z-.014)))
                weights_from(piece,base)
                finish(piece,[upper],rim=.0023)
                parts.append(piece)
            continue
        if style=='boots':
            arch = [(-.047,.017,.026,.110),(-.035,.042,.025,.180),(.009,.046,.025,.186),
                    (.041,.046,.025,.163),(.067,.047,.025,.104),(.131,.052,.024,.059),(.180,.042,.022,.054),(.202,.008,.022,.033)]
        elif style=='heels':
            arch = [(-.051,.006,.057,.079),(-.036,.029,.050,.094),(.007,.027,.041,.089),
                    (.051,.034,.025,.067),(.108,.041,.013,.063),(.166,.037,.012,.039),(.199,.006,.013,.026)]
            heel = shoe_segment('Block heel',side,
                         [(-.052,.009,.003,.055),(-.042,.023,.002,.065),(-.013,.026,.002,.064),(.001,.012,.018,.052)])
            heel.data.materials.append(sole)
            parts.append(heel)
        else:
            arch = [(-.054,.008,.022,.075),(-.041,.038,.019,.101),(.019,.045,.020,.111),
                    (.065,.046,.017,.093),(.124,.051,.016,.072),(.185,.038,.016,.053),(.208,.006,.018,.032)]
        shoe = shoe_segment('Upper',side,arch)
        shoe.data.materials.append(upper)
        parts.append(shoe)
        if style=='streettrainers':
            accent = bpy.data.materials.get('hero_fashion_shoe_accent_'+style) or material(
                'hero_fashion_shoe_accent_'+style,(.36,.34,.31),.63)
            shoe.data.materials.append(accent)
            for poly in shoe.data.polygons:
                if .063<poly.center.y<.15 and poly.center.z>.054:
                    poly.material_index = 1
            hull = tree_of(shoe)
            centre = J['foot_'+side].x
            lace = bpy.data.materials.get('hero_streettrainer_lace') or material('hero_streettrainer_lace',(.68,.67,.62),.86)
            for i in range(5):
                points,uv = [],[]
                for j in range(8):
                    t = j/7
                    x = centre + (t-.5)*.055
                    y = .058+.013*i+.009*t*(1 if i%2 else -1)
                    hit,_,_,_ = hull.ray_cast(Vector((x,y,.21)),Vector((0,0,-1)))
                    if hit is None:
                        break
                    points.append([hit+Vector((0,-.0016,.0018)),hit+Vector((0,.0016,.0018))])
                    uv.append([(t,0),(t,1)])
                if len(points)==8:
                    ribbon = grid_mesh('Flat lace',points,uv)
                    face_out(ribbon,lambda _:Vector((0,0,1)))
                    weights_from(ribbon,shoe)
                    finish(ribbon,[lace],rim=.0011)
                    parts.append(ribbon)
    return join_as('Footwear_'+style,parts)


def refit_vest():
    skin = fashion_skin('Fashion_Torso_Skin',.975,1.60,True)
    if BODY=='b':
        exposed = skin.copy()
        exposed.data = skin.data.copy()
        exposed.name = 'Fashion_Crop_Skin'
        bpy.context.collection.objects.link(exposed)
        add(exposed,False)
    trim_torso_skin(skin)
    add(skin,False)
    # This is the existing fitted top option, rebuilt with finished armholes.
    vest = women_top('New_Vest', 'jersey',PANTS_TOP-.037,(1.548,1.475),None,'shirt','vest',True)
    global top_vest
    tops.remove(top_vest)
    bpy.data.objects.remove(top_vest,do_unlink=True)
    vest.name = 'Top_Vest'
    vest.data.name = vest.name
    top_vest = vest
    tops.append(vest)
    old_vest_skin = next(obj for obj in skin_arms if obj.name=='Skin_Arms_Vest')
    skin_arms.remove(old_vest_skin)
    bpy.data.objects.remove(old_vest_skin,do_unlink=True)


def build_fashion():
    add(fashion_skin('Fashion_Legs',.055,.81,False),False)
    for name, low in (('Fashion_Biker_Legs', .055), ('Fashion_Biker_Barefeet', -.019)):
        leg = fashion_skin(name, low, .744, False)
        for vertex in leg.data.vertices:
            point = vertex.co
            side = 'l' if point.x < 0 else 'r'
            blend = .29 * smooth(.645, .740, point.z)
            knee, hip = J['shin_' + side], J['thigh_' + side]
            axis = knee.lerp(hip, (point.z - knee.z) / (hip.z - knee.z))
            point.x += (axis.x - point.x) * blend
            point.y += (axis.y - point.y) * blend
        add(leg, False)
    socks = fashion_skin('Fashion_Lounge_Socks', .045, .160, False)
    for vertex in socks.data.vertices:
        p = vertex.co
        side = 'l' if p.x < 0 else 'r'
        ankle, knee = J['foot_' + side], J['shin_' + side]
        axis = ankle.lerp(knee, (p.z - ankle.z) / (knee.z - ankle.z))
        p += Vector((p.x - axis.x, p.y - axis.y, 0)).normalized() * .003
    socks.data.materials.clear()
    socks.data.materials.append(material('hero_lounge_sock', (.79, .77, .73), .86, normal=TRIM_N))
    add(socks, False)
    add(fashion_skin('Fashion_Feet',-.019,.141,False),False)
    add(fashion_skin('Fashion_Barefoot_Legs',-.019,.81,False),False)
    add(fashion_skin('Fashion_Cropped_Ankles',.023,.34,False),False)
    add(fashion_skin('Fashion_Cropped_Barefeet',-.019,.34,False),False)
    base = next(ob for ob in wardrobe if ob.name=='Lower_shorts')
    slip = base.copy()
    slip.data = base.data.copy()
    slip.name = 'Fashion_Slip'
    bpy.context.collection.objects.link(slip)
    bm = bmesh.new()
    bm.from_mesh(slip.data)
    _bisect(bm,(0,0,.808),(0,0,1),lambda v:v.z<.80799)
    bm.to_mesh(slip.data)
    bm.free()
    slip.data.update()
    slip.data.materials.clear()
    slip.data.materials.append(material('hero_slip',(.034,.035,.039),.89))
    add(slip,False)
    top_specs = {
        'Crop': ('jersey',1.141,(1.566,1.523),.30,'shirt','ordinary',False,.0029),
        'Tank': ('rib',PANTS_TOP-.027,(1.545,1.466),None,'shirt','ordinary',True,.002),
        'Vest': ('crepe',PANTS_TOP-.021,(1.544,1.464),None,'shirt','vest',False,.0024),
        'Camisole': ('satin',PANTS_TOP-.031,(1.524,1.449),None,'shirt','cami',True,.0024),
        'Blouse': ('linen',PANTS_TOP-.027,(1.575,1.499),.76,'shirt','ordinary',True,.0056),
        'Bodysuit': ('jersey',PANTS_TOP-.029,(1.550,1.502),.94,'skin','ordinary',True,.0008),
        'Cardigan': ('rib',PANTS_TOP-.069,(1.548,1.486),.97,'knit','open',False,.0053),
        'Jacket': ('denim',PANTS_TOP+.042,(1.559,1.498),.95,'jacket','jacket',False,.0037),
        'Fitteddress': ('crepe',PANTS_TOP-.025,(1.535,1.480),None,'shirt','ordinary',True,.0022),
        'Loosedress': ('linen',PANTS_TOP-.032,(1.550,1.474),.35,'knit','ordinary',False,.006),
        'Onedress': ('satin',PANTS_TOP-.024,(1.554,1.510),None,'shirt','one_shoulder',True,.003),
        'Squareneck': ('satin',PANTS_TOP-.012,(1.539,1.509),None,'shirt','square_neck',True,.0025),
    }
    dress_hem = {'Fitteddress': (.616, .033), 'Loosedress': (.464, .115), 'Onedress': (.641, .046)}
    for cut,spec in top_specs.items():
        top = women_top('Top_Fashion_'+cut,*spec)
        if cut in dress_hem:
            # Keep both halves of the dress on the same waist through hip flex.
            from build_b_fit import blend_weights
            for vertex in top.data.vertices:
                pin = 1 - smooth(PANTS_TOP + .015, PANTS_TOP + .080, vertex.co.z)
                if pin > 0:
                    blend_weights(top, vertex, {'hips': 1}, pin)
        if cut=='Cardigan':
            fit_cardigan_hem(top)
        add(top,False)
        prefix = 'Topx_Fashion_'+cut+'_'
        if cut=='Camisole':
            add(shoulder_straps(top,prefix+'Straps'),False)
        if cut in ('Cardigan','Jacket'):
            under = women_top(prefix+'Under','jersey',PANTS_TOP-.035,(1.542,1.473),None,'skin','ordinary',True)
            fit_layered_insert(under,cut=='Jacket')
            weights_from(under, top, lambda p: .78 if p.z > 1.33 else .63)
            add(under,False)
        if cut in ('Vest','Cardigan','Jacket'):
            tree = tree_of(top)
            buttons_ = []
            for z in (1.355,1.276,1.197,1.122):
                x = .035 if cut!='Vest' else .009
                hit,_,_,_ = tree.ray_cast(Vector((x,NECK_CY+FRONT*.35,z)),Vector((0,-FRONT,0)))
                if hit is None or front_of(hit)<.033:
                    continue
                ob = button_mesh('Button',hit+Vector((0,FRONT*.0024,0)),Vector((0,FRONT,0)),
                                 r=.0063 if cut=='Vest' else .0081,h=.0026,mat=dark_button_mat)
                weights_from(ob,top)
                buttons_.append(ob)
            if buttons_:
                add(join_as(prefix+'Buttons',buttons_),False)
        if cut in dress_hem:
            hem, flare = dress_hem[cut]
            add(skirt_pattern(prefix + 'Skirt', 'top', spec[0], PANTS_TOP + .015, hem, flare,
                              panel_split=cut == 'Loosedress'), False)

    for style,fabric,hem,flare in [('miniskirt','denim',.638,.047),('midiskirt','crepe',.381,.060),
                                   ('maxiskirt','satin',.109,.138)]:
        midi = style == 'midiskirt'
        add(skirt_pattern('Lower_'+style,'bottom',fabric,PANTS_TOP+.016,hem,flare,
                          panel_split=style!='miniskirt', slit_angle=-.13 if midi else -.52,
                          waist_ease=.006 if midi else .016),False)
    for style in ('leggings','fitjeans','tailoredshorts','widejeans','bikershorts'):
        add(fitted_bottom(style),False)
    for style in ('heels','boots','sandals','streettrainers'):
        add(fashion_shoes(style),False)
    # A sewn, fitted leather jacket for the turnaround's everyday look.
    moto, radius, collar = everyday_top('Top_Fashion_Moto', 'hero_fashion_top_leather',
        'jacket', 9.0, .968, (1.611, 1.580), .0048, hem=PANTS_TOP + .013,
        tail=.045, sleeve_ease=(.010, .011),
        cuff=(.86, .968, lambda side, angle: cuff_radius(side, angle) + .001),
        rough=.49, textile='leather', texture_name='top_fashion_moto')
    add(rib_band('Topx_Fashion_Moto_Collar', radius, collar, .034, moto, lean=.0016), False)
    zipper_trim(moto, 'Fashion_Moto', collar(0) + .026, PANTS_TOP - .038, .007)
    simplify_surface(moto, .63)


def casual_reference_outfits():
    racer = women_top('Top_Fashion_Racer', 'leather', 1.103, (1.574, 1.489),
                      .968, 'jacket', 'racer', False, .0064)
    add(racer, False)
    crop = women_top('Topx_Fashion_Racer_Under', 'jersey', 1.150, (1.532, 1.455),
                     None, 'skin', 'square_neck', True, .0018)
    crop.data.materials[0].name = 'hero_racer_cotton'
    add(crop, False)
    shell = tree_of(racer)
    flaps = []
    for side in (-1, 1):
        points = []
        for row, (z, half) in enumerate(((1.356, .026), (1.334, .019), (1.325, .012))):
            line = []
            for column in (-1, 1):
                x = side * .117 + column * half
                hit = shell.ray_cast(Vector((x, .24, z)), Vector((0, -1, 0)))[0]
                if hit is None:
                    line = []
                    break
                line.append(hit + Vector((0, .0037, 0)))
            if not line:
                break
            points.append(line)
        if len(points) == 3:
            flap = grid_mesh('Leather pocket flap', points, [[(0, i/2), (1, i/2)] for i in range(3)])
            face_out(flap, lambda _: Vector((0, 1, 0)))
            weights_from(flap, racer)
            finish(flap, [racer.data.materials[0]], rim=.0018)
            flaps.append(flap)
    if flaps:
        add(join_as('Topx_Fashion_Racer_Pockets', flaps), False)

    jumper, radius, height = everyday_top(
        'Top_Fashion_Pullover', 'hero_fashion_top_fleece', 'knit', 9.0, .963,
        (1.591, 1.535), .011, hem=PANTS_TOP - .025, tail=.043,
        sleeve_ease=(.021, .021), cuff=(.86,.963,lambda side,a: cuff_radius(side,a)+.006),
        rough=.86)
    hood = folded_hood(jumper, radius, height)
    hood.name = 'Topx_Fashion_Pullover_Hood'
    add(hood, False)
    cuffs = []
    for side in ('l', 'r'):
        cuff, _ = shirt_cuff(side,.927,1.006,mat=rib_trim,
            radius=lambda sd,a: cuff_radius(sd,a)+.003, trim_row='rib', btn=False)
        weights_from(cuff, jumper)
        cuffs.append(cuff)
    add(join_as('Topx_Fashion_Pullover_Cuffs', cuffs), False)
    shell = tree_of(jumper)
    cords = []
    cord_mat = material('hero_fashion_top_drawcord', (.24, .24, .25), .88)
    for side in (-1, 1):
        rows, uvs = [], []
        for i in range(11):
            t = i / 10
            z = 1.485 - (.123 if side > 0 else .151) * t
            x = side * (.023 + .031 * t + .004 * math.sin(t * math.pi))
            hit = shell.ray_cast(Vector((x, .25, z)), Vector((0, -1, 0)))[0]
            if hit is None:
                continue
            centre = hit + Vector((0, .0048 + .004 * math.sin(t * math.pi), 0))
            angles = [math.tau * j / 6 for j in range(7)]
            rows.append([centre + Vector((.0021 * math.cos(a), .0021 * math.sin(a), 0)) for a in angles])
            uvs.append([(j/6, t) for j in range(7)])
        if len(rows) < 4:
            continue
        cord = grid_mesh('Fleece hood drawcord', rows, uvs)
        face_out(cord, lambda p: Vector((p.x - side*.04, 1, 0)))
        weights_from(cord, jumper)
        finish(cord, [cord_mat], rim=0)
        cords.append(cord)
    if cords:
        add(join_as('Topx_Fashion_Pullover_Drawcords', cords), False)
    rows, uv = [], []
    for i in range(6):
        t = i / 5
        z = 1.009 + .121 * t
        half = .095 - .035 * t
        row = []
        for k in range(11):
            u = k / 10
            x = (u * 2 - 1) * half
            hit = shell.ray_cast(Vector((x, .27, z)), Vector((0,-1,0)))[0]
            if hit is None:
                break
            row.append(hit + Vector((0, .0027 + .006 * math.sin(t * math.pi) * math.sin(u * math.pi), 0)))
        if len(row) != 11:
            continue
        rows.append(row)
        uv.append([(k / 10, t) for k in range(11)])
    if len(rows) >= 3:
        pocket = grid_mesh('Topx_Fashion_Pullover_Pocket', rows, uv)
        face_out(pocket, lambda _: Vector((0, 1, 0)))
        weights_from(pocket, jumper)
        mat = fashion_material(pocket, 'top', 'jersey', 1.01, None)
        finish(pocket, [mat], rim=.0022)
        add(pocket, False)
    simplify_surface(jumper, .67)
