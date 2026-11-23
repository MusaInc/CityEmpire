"""Build the CitySwing courier from licensed, authored garment topology.

Blender -b --factory-startup --python tools/blender/build_character.py -- assets/models
Sources and their original UVs live in art/hero/sources; provenance in CREDITS.md.
No voxel fusion or primitive body construction. The source anatomy weights are
transferred through the garments' barycentric fitting records, then retargeted
to the existing gameplay rig. Reproducible .blend + textured GLB output.
"""
import bpy, bmesh, math, json, sys, os
from pathlib import Path
from mathutils import Vector, Matrix
from mathutils.bvhtree import BVHTree
import numpy as np
sys.path.insert(0, str(Path(__file__).resolve().parent))
import female_character as female
from portrait_wrap import finish_skin_material, project as project_portrait
from hero_export import export_playable
from portrait_hd import bake_portrait_hd
from hero_finish import finish_fixed_hero
from hero_realism import finish_realism
from casual_fit import finish_casual_fit
from build_b_footwear import fit_build_b_footwear
from hero_groom import groom_hero, wound_gather
from wardrobe_quality import (HEADPHONE_HAIRS, SKIRTS, fit_camisole_straps,
                              fit_denim_jacket, fit_headphone_band, fit_skirt_correctives,
                              fit_sandals, fit_tucked_waists)
ROOT=Path(__file__).resolve().parents[2]
SRC=ROOT/'art/hero/sources'
OUT=Path(sys.argv[sys.argv.index('--')+1]) if '--' in sys.argv else ROOT/'assets/models'
# Body type (character creation): "a" (assets/models/character.glb) or "b"
# (character_b.glb) - the same rig, garments, hair and kit, a second body
# shape from MakeHuman's macro targets with its own five faces.
BODY=os.environ.get('HERO_BODY','a')
SUF='' if BODY=='a' else '_'+BODY
AUTHORING=Path(sys.argv[sys.argv.index('--')+2]) if '--' in sys.argv and len(sys.argv)>sys.argv.index('--')+2 else ROOT/'art/hero'
TEX=AUTHORING/('textures'+SUF)
TEX.mkdir(parents=True,exist_ok=True);OUT.mkdir(parents=True,exist_ok=True)
BLEND = AUTHORING / ('courier%s.blend' % SUF)
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)

def obj_read(path):
    vs=[];uv=[];fs=[];fu=[];groups=[];group=''
    for line in path.read_text().splitlines():
        a=line.split()
        if not a:continue
        if a[0]=='v':vs.append([float(x) for x in a[1:4]])
        elif a[0]=='vt':uv.append([float(x) for x in a[1:3]])
        elif a[0]=='g':group=' '.join(a[1:])
        elif a[0]=='f':
            f=[x.split('/') for x in a[1:]]
            fs.append([int(x[0])-1 for x in f]);fu.append([int(x[1])-1 if len(x)>1 and x[1] else 0 for x in f]);groups.append(group)
    return np.array(vs),np.array(uv),fs,fu,groups

base,_,_,_,_=obj_read(SRC/'base.obj')
MACRO={'a':[('african-male-young.target',1/3),('asian-male-young.target',1/3),('caucasian-male-young.target',1/3),('universal-male-young-averagemuscle-averageweight.target',.88),('universal-male-young-maxmuscle-averageweight.target',.12)],
       'b':[('african-female-young.target',1/3),('asian-female-young.target',1/3),('caucasian-female-young.target',1/3),('universal-female-young-averagemuscle-minweight.target',.07),('universal-female-young-minmuscle-averageweight.target',.14)]}
ETH_KIND={'a':'male','b':'female'}[BODY]
for n,w in MACRO[BODY]:
    for l in (SRC/n).read_text().splitlines():
        a=l.split()
        if not a or a[0].startswith('#'):continue
        base[int(a[0])]+=np.array(list(map(float,a[1:4])))*w
sk=json.loads((SRC/'default.mhskel').read_text())
raw_weights=json.loads((SRC/'default_weights.mhw').read_text())['weights']
J={'hips':Vector((0,0,.98)),'spine':Vector((0,0,1.04)),'chest':Vector((0,0,1.30)),'neck':Vector((0,0,1.56)),'head':Vector((0,0,1.64))}
P={'hips':None,'spine':'hips','chest':'spine','neck':'chest','head':'neck'}
for side,sx in [('l',-1),('r',1)]:
    a=Vector((sx*math.sin(math.radians(42)),0,-math.cos(math.radians(42))))
    l=Vector((sx*math.sin(math.radians(5)),0,-math.cos(math.radians(5))))
    if BODY == 'b':
        J['neck'] = Vector((0,.002,1.537))
        J['head'] = Vector((0,-.008,1.610))
        J['upper_arm_'+side] = Vector((sx*.166,-.005,1.465))
        J['forearm_'+side] = J['upper_arm_'+side] + a*.266
        J['hand_'+side] = J['forearm_'+side] + a*.242
    else:
        J['upper_arm_'+side] = Vector((sx*.193,0,1.490))
        J['forearm_'+side] = J['upper_arm_'+side] + a*.284
        J['hand_'+side] = J['forearm_'+side] + a*.253
    J['thigh_'+side]=Vector((sx*.1,0,.94))
    J['shin_'+side]=J['thigh_'+side]+l*.45
    J['foot_'+side]=J['shin_'+side]+l*.44
    for b,parent in [('upper_arm','chest'),('forearm','upper_arm_'+side),('hand','forearm_'+side),('thigh','hips'),('shin','thigh_'+side),('foot','shin_'+side)]:P[b+'_'+side]=parent
names=list(P);ni={n:i for i,n in enumerate(names)}
def mapped(n):
    side='r' if n.endswith('.L') else 'l'
    if n.startswith('upperarm'):return 'upper_arm_'+side
    if n.startswith('lowerarm'):return 'forearm_'+side
    if n.startswith(('finger','metacarpal','wrist')):return 'hand_'+side
    if n.startswith('upperleg'):return 'thigh_'+side
    if n.startswith('lowerleg'):return 'shin_'+side
    if n.startswith(('foot','toe')):return 'foot_'+side
    if n.startswith('neck'):return 'neck'
    if n.startswith(('pelvis','root','spine05')):return 'hips'
    if n.startswith(('spine03','spine04')):return 'spine'
    if n.startswith(('spine','clavicle','shoulder','breast')):return 'chest'
    return 'head'
weights=np.zeros((len(base),len(names)))
for n,entries in raw_weights.items():
    for i,w in entries:weights[i,ni[mapped(n)]]+=w
weights/=np.maximum(weights.sum(1)[:,None],1e-8)
def source_joint(b,k='head'):
    return Vector(np.mean(base[sk['joints'][sk['bones'][b][k]]],axis=0))
def coord(v):return Vector((v[0],v[2],v[1]))
trans={}
for side,suf in [('r','.L'),('l','.R')]:
    specs=[('upper_arm','upperarm01','lowerarm01','forearm'),('forearm','lowerarm01','wrist','hand'),('hand','wrist','finger3-1',None),('thigh','upperleg01','lowerleg01','shin'),('shin','lowerleg01','foot','foot')]
    for dst,src,end,tail in specs:
        origin=coord(source_joint(src+suf));axis=coord(source_joint(end+suf))-origin
        target=(J[tail+'_'+side]-J[dst+'_'+side]) if tail else (J['hand_'+side]-J['forearm_'+side]).normalized()*.085
        scale=target.length/axis.length if tail else .1
        trans[dst+'_'+side]=(origin,axis.normalized().rotation_difference(target.normalized()),scale)
    trans['foot_'+side]=(coord(source_joint('foot'+suf)),None,.1)

# The torso's key heights (MakeHuman units) were measured on body A. For
# another body they move with its own skeleton: each key keeps its offset
# from the nearest of body A's spine / neck / head joints, read on this body
# (the crown keeps its offset from the top of the head). Body A: unchanged.
TORSO_KEYS=[-8.45,1.003,3.1,4.35,5.608,6.654,7.62,9.22]
def _torso_keys():
    if BODY=='a':return TORSO_KEYS
    ba,_,_,_,_=obj_read(SRC/'base.obj')
    for n,w in MACRO['a']:
        for l in (SRC/n).read_text().splitlines():
            a=l.split()
            if not a or a[0].startswith('#'):continue
            ba[int(a[0])]+=np.array(list(map(float,a[1:4])))*w
    js=[b for b in sk['bones'] if b.startswith(('root','pelvis','spine','neck','head'))]
    jy=lambda B,b:float(np.mean(B[sk['joints'][sk['bones'][b]['head']]],axis=0)[1])
    out=[]
    for k in TORSO_KEYS:
        if k<0:out.append(k);continue
        if k>9.0:out.append(float(base[:,1].max())-(float(ba[:,1].max())-k));continue
        b=min(js,key=lambda b:abs(jy(ba,b)-k))
        out.append(jy(base,b)+(k-jy(ba,b)))
    print('TORSO KEYS',BODY,[round(x,3) for x in out])
    return out
TK=_torso_keys()
def torso(v):
    x, y, z = v
    levels = ([0,.94,1.200,1.339,1.491,1.584,1.68,1.84] if BODY=='a'
              else female.HEIGHTS)
    h = float(np.interp(y,TK,levels))
    px, depth = x*.1, z*.1
    ax = abs(px)
    waist = math.exp(-((h-1.105)/.103)**2)
    ribs = math.exp(-((h-1.352)/.105)**2)
    crest = math.exp(-((h-1.487)/.084)**2)
    # Neck-to-acromion slope is sculpted across the actual trapezius, with
    # the neck base and clavicle heads remaining full medial volumes.
    shoulder = min(1.0,max(0.0,(ax-.049)/.121))
    shoulder = shoulder*shoulder*(3-2*shoulder)
    if BODY == 'b':
        return female.anatomy(px, depth, h)
    else:
        px *= 1 + .030*math.exp(-((h-1.00)/.125)**2) - .026*waist - .027*crest*shoulder
        h -= .010*shoulder*crest
    depth += .005*waist - .008*ribs
    return Vector((px,depth,h))


def retarget(v,w):
    result = Vector()
    p = coord(v)
    core = torso(v)
    for n,i in ni.items():
        if w[i] < 1e-6:
            continue
        t = core
        if n in trans:
            origin, rotation, scale = trans[n]
            offset = p-origin
            t = J[n]+(rotation@offset if rotation else offset)*scale
            if BODY == 'b':
                if n.startswith('upper_arm'):
                    axis = (J['forearm_'+n[-1]]-J[n]).normalized()
                    t = female.upper_arm(t, J[n], axis)
                elif n.startswith('thigh'):
                    t = female.pelvis_blend(t, v[2]*.1)
        result += t*float(w[i])
    return result

# The clavicle and chest hold the seam of the shoulder as the arm swings.
def _shoulder_weights():
    for side in ('l','r'):
        ua, chest = ni['upper_arm_'+side], ni['chest']
        pivot = J['upper_arm_'+side]
        axis = (J['forearm_'+side]-pivot).normalized()
        for j, w in enumerate(weights):
            if w[ua] < 1e-4:
                continue
            p = retarget(base[j],w)
            if (p.x<0)!=(side=='l') or abs(p.x)<.065 or p.z<1.19:
                continue
            t = (p-pivot).dot(axis)
            reach = .092 if BODY=='b' else .085
            k = max(0,min(1,(t+.014)/(reach+.014)))
            k = k*k*(3-2*k)
            shoulder_tip = max(0,min(1,(abs(p.x)-abs(pivot.x)+.044)/.056))
            arm_target = (w[ua]+w[chest])*k*(.60+.40*shoulder_tip)
            transferred = max(0,w[ua]-arm_target)
            w[ua] -= transferred
            w[chest] += transferred
_shoulder_weights()


def mesh(name,verts,uv,faces,faceuv):
    me=bpy.data.meshes.new(name);me.from_pydata(verts,[],faces);me.update()
    ob=bpy.data.objects.new(name,me);bpy.context.collection.objects.link(ob)
    if len(uv):
        layer=me.uv_layers.new(name='GarmentUV')
        for poly,us in zip(me.polygons,faceuv):
            for li,ui in zip(poly.loop_indices,us):layer.data[li].uv=uv[ui]
    for p in me.polygons:p.use_smooth=True
    return ob

def garment(folder,name):
    path=SRC/folder;mh=next(path.glob('*.mhclo'));lines=mh.read_text().splitlines()
    objname=next(l.split()[1] for l in lines if l.startswith('obj_file '))
    _,uv,faces,fu,_=obj_read(path/objname)
    start=next(i for i,l in enumerate(lines) if l.startswith('verts '))+1
    vs=[];ws=[]
    scales={}
    for l in lines[:start]:
        a=l.split()
        if a and a[0] in ['x_scale','y_scale','z_scale']:
            axis={'x_scale':0,'y_scale':1,'z_scale':2}[a[0]]
            scales[axis]=abs(base[int(a[1]),axis]-base[int(a[2]),axis])/float(a[3])
    for l in lines[start:]:
        a=l.split()
        if not a or a[0].startswith('#'):continue
        if not a[0].lstrip('-').isdigit():break
        if len(a)==1:v=base[int(a[0])];w=weights[int(a[0])].copy()
        elif len(a)==9:
            ids=list(map(int,a[:3]));b=np.array(list(map(float,a[3:6])))
            v=(base[ids]*b[:,None]).sum(0)+np.array(list(map(float,a[6:9])))*np.array([scales.get(i,1) for i in range(3)])
            w=np.maximum((weights[ids]*b[:,None]).sum(0),0)
        else:break
        w/=max(w.sum(),1e-8);ws.append(w);vs.append(retarget(v,w))
    assert len(vs)>max(max(f) for f in faces),(name,len(vs))
    ob=mesh(name,vs,uv,[list(reversed(f)) for f in faces],[list(reversed(f)) for f in fu])
    for n,i in ni.items():
        vg=ob.vertex_groups.new(name='b_'+n)
        for vi,w in enumerate(ws):
            if w[i]>.001:vg.add([vi],float(w[i]),'REPLACE')
    return ob

def active(ob):
    bpy.ops.object.select_all(action='DESELECT');ob.select_set(True);bpy.context.view_layer.objects.active=ob

def apply(ob,mod):
    active(ob);bpy.ops.object.modifier_apply(modifier=mod.name)

def subdiv(ob,level):
    m=ob.modifiers.new('Tailored surface','SUBSURF');m.levels=level;apply(ob,m)

def simplify_surface(ob, ratio):
    reduction = ob.modifiers.new('Mobile surface topology', 'DECIMATE')
    reduction.ratio = ratio
    apply(ob, reduction)


def image_load(path):
    im=bpy.data.images.load(str(path),check_existing=True);return im

def material(name,color,rough=.75,tex=None,normal=None):
    m=bpy.data.materials.new(name);m.use_nodes=True;n=m.node_tree.nodes;l=m.node_tree.links;p=n.get('Principled BSDF')
    p.inputs['Base Color'].default_value=(*color,1);p.inputs['Roughness'].default_value=rough
    if tex:
        t=n.new('ShaderNodeTexImage');t.image=image_load(tex);l.new(t.outputs['Color'],p.inputs['Base Color'])
    if normal:
        t=n.new('ShaderNodeTexImage');t.image=image_load(normal);t.image.colorspace_settings.name='Non-Color'
        nm=n.new('ShaderNodeNormalMap');nm.inputs['Strength'].default_value=.42;l.new(t.outputs['Color'],nm.inputs['Color']);l.new(nm.outputs['Normal'],p.inputs['Normal'])
    return m

def recolor_texture(src,name,color,white=False):
    im=image_load(src);w,h=im.size;data=np.empty(w*h*4,dtype=np.float32);im.pixels.foreach_get(data);a=data.reshape(h,w,4)
    lum=a[:,:,:3].mean(2)
    if white:
        # Retain the authored seams, lace shadows and sole boundary; neutralise old branding colours.
        value=np.clip(lum*.55+.42,.20,.91);rgb=value[:,:,None]*np.array(color)
    else:
        value=np.clip(lum/(np.percentile(lum,70)+.001),.32,1.45);rgb=value[:,:,None]*np.array(color)
    a[:,:,:3]=rgb;a[:,:,3]=1
    out=bpy.data.images.new(name,w,h,alpha=False);out.pixels.foreach_set(a.ravel());out.filepath_raw=str(TEX/(name+'.png'));out.file_format='PNG';out.save();return TEX/(name+'.png')

pants=garment('cortu_cargo_pants','Courier_Cargo')
shoes=garment('punkduck_running_shoes_01','Courier_Trainers')
gloves=garment('toigo_gloves_short','Courier_Gloves')
# Pose-corrective glove shapes retain the authored fingers and UVs.
gloves.shape_key_add(name='Basis')
for side,sx in [('l',-1),('r',1)]:
    key=gloves.shape_key_add(name='Grip_'+side)
    direction=(J['hand_'+side]-J['forearm_'+side]).normalized()
    pivot=J['hand_'+side]+direction*.055
    for v,k in zip(gloves.data.vertices,key.data):
        if v.co.x*sx<0:continue
        d=v.co-pivot;length=d.dot(direction)
        if length<=0:continue
        angle=min(2.3,length/.075*2.3)
        radius=.075/2.3
        sideways=d-direction*length
        k.co=pivot+sideways+direction*(math.sin(angle)*radius)+Vector((0,1,0))*(1-math.cos(angle))*radius
# Add enough topology for knee/elbow deformation without a remesher.
subdiv(pants,2)
subdiv(shoes,1)
m=shoes.modifiers.new("Trainer mobile topology","DECIMATE");m.ratio=.55;apply(shoes,m)
for v in shoes.data.vertices:
    v.co.z+=.035
# A clean, level waistband (the hoodie used to hide the authored one); the
# top tucks in under it.
bm=bmesh.new();bm.from_mesh(pants.data)
# Mid-rise: the waistband sits at 1.035 m (just under the navel), or as high
# as the authored trousers reach.
PANTS_TOP=min(1.035,max(v.co.z for v in bm.verts)-.004)
print('PANTS_TOP',round(PANTS_TOP,4),'authored top',round(max(v.co.z for v in bm.verts),4),flush=True)
bmesh.ops.bisect_plane(bm,geom=bm.verts[:]+bm.edges[:]+bm.faces[:],plane_co=(0,0,PANTS_TOP),plane_no=(0,0,1))
bmesh.ops.delete(bm,geom=[v for v in bm.verts if v.co.z>PANTS_TOP+1e-5],context='VERTS')
# The authored trousers' own waistband details (loops, pocket corners) stand
# out at the hips once the rise is higher: clamp the top 7 cm to a smooth
# low-pass of the trousers' own profile (a finished band goes on top).
_band=[v for v in bm.verts if v.co.z>PANTS_TOP-.07]
if _band:
    _cy=sum(v.co.y for v in _band)/len(_band);NB=48
    _bins=[[] for _ in range(NB)]
    for v in _band:
        a=math.atan2(v.co.x,v.co.y-_cy)%math.tau;_bins[int(a/math.tau*NB)%NB].append(math.hypot(v.co.x,v.co.y-_cy))
    _med=[float(np.percentile(b,40)) if b else 0 for b in _bins]
    for k in range(NB):
        if not _med[k]:_med[k]=max(_med)
    _f=np.fft.rfft(np.array(_med));_f[7:]=0;_lp=np.fft.irfft(_f,NB)
    for v in _band:
        a=math.atan2(v.co.x,v.co.y-_cy)%math.tau;r=math.hypot(v.co.x,v.co.y-_cy)
        lim=float(np.interp(a/math.tau*NB,range(NB+1),list(_lp)+[_lp[0]]))+.004
        if r>lim:
            k=lim/r;v.co.x*=k;v.co.y=_cy+(v.co.y-_cy)*k
bm.to_mesh(pants.data);bm.free();pants.data.update()
for v in pants.data.vertices:
    if v.co.z<.23:
        n='foot_l' if v.co.x<0 else 'foot_r';ank=J[n]
        t=max(0,min(1,(.23-v.co.z)/.20));v.co.x=ank.x+(v.co.x-ank.x)*(1-.28*t)
        v.co.y*=1-.18*t
        v.co.z+=.045*t  # the hem ends inside the trainer's collar, never above it
ptex=recolor_texture(SRC/'cortu_cargo_pants'/'cargo_pants_diff.png','cargo_albedo',(.21,.225,.24)) if (SRC/'cortu_cargo_pants'/'cargo_pants_diff.png').exists() else None
pmat=material('hero_cargo',(.046,.051,.054),.86,ptex,SRC/'cortu_cargo_pants'/'cargo_pants_norm.png')
gmat=material('hero_glove',(.023,.026,.029),.58)
for ob,mat in [(pants,pmat),(gloves,gmat)]:ob.data.materials.clear();ob.data.materials.append(mat)

# ------------------------------------------------------------------ body parts
# The anatomy itself (MakeHuman hm08 body, morphed above) is the source for
# the skin-tight tops, the bare forearms and the heads: cut by skin weight and
# height, retargeted to the gameplay rig with the same weights, so a garment
# made from the skin fits it exactly and deforms with it.
bv,bu,bf,bfu,bg=obj_read(SRC/'base.obj')
GROUP_FACES={}
for i,g in enumerate(bg):GROUP_FACES.setdefault(g,[]).append(i)
RB=[retarget(base[j],weights[j]) for j in range(len(base))]
# The base of the neck moves with the chest, not the head: blend the neck
# bone's share toward the chest below 1.58 m (a tee's neckline or an open
# collar then never has the throat pushing through it when the head turns).
for j in range(len(base)):
    z=RB[j].z
    if 1.44<z<1.58 and abs(RB[j].x)<.13:
        k=min(1.0,(1.58-z)/.08)*.75
        moved=weights[j,ni['neck']]*k
        weights[j,ni['neck']]-=moved;weights[j,ni['chest']]+=moved
# Hands: 6% smaller about the wrist, fingers 10% shorter past the knuckles
# (MakeHuman's hand on this rig read large with long fingers). Blended in by
# hand weight from 0.35 (where the forearm skin ends: the join stays exact).
for j in range(len(base)):
    hw=float(weights[j,ni['hand_l']]+weights[j,ni['hand_r']])
    if hw<=.35:continue
    side='l' if RB[j].x<0 else 'r'
    W_=J['hand_'+side];ax=(J['hand_'+side]-J['forearm_'+side]).normalized()
    k=min(1.0,(hw-.35)/.45);k=k*k*(3-2*k)
    d=RB[j]-W_;along=d.dot(ax)
    if along>.085:along2=.085+(along-.085)*.9
    else:along2=along
    # Keep the broader palm and knuckle arch, slim only the tapered fingers.
    across = d - ax*along
    finger = max(0., min(1., (along-.065)/.065))
    d2 = ax*along2*.97 + across*(.98 - .065*finger)
    RB[j]=W_+(d+(d2-d)*k)
    if BODY == 'b':
        female.hand_planes(RB[j], W_, ax, k)
def wsum(j,*bones):return float(sum(weights[j,ni[b]] for b in bones))
def part(name,faces,positions,wts,flip=True):
    ids=sorted({j for i in faces for j in bf[i]});rm={j:k for k,j in enumerate(ids)}
    fs=[[rm[j] for j in (reversed(bf[i]) if flip else bf[i])] for i in faces]
    fu=[list(reversed(bfu[i])) if flip else list(bfu[i]) for i in faces]
    ob=mesh(name,[positions[j] for j in ids],bu,fs,fu)
    for n,i in ni.items():
        vg=ob.vertex_groups.new(name='b_'+n)
        for k,j in enumerate(ids):
            if wts[j,i]>.001:vg.add([k],float(wts[j,i]),'REPLACE')
    return ob,ids
def push(ob,d,zmask=None):
    bm=bmesh.new();bm.from_mesh(ob.data);bm.normal_update()
    for v in bm.verts:
        k=1.0 if zmask is None else zmask(v.co)
        v.co+=v.normal*d*k
    bm.to_mesh(ob.data);bm.free();ob.data.update()
def arm_t(j):
    # 0 at the shoulder joint, 1 at the elbow, >1 down the forearm.
    p=RB[j];side='l' if p.x<0 else 'r'
    a=J['upper_arm_'+side];e=J['forearm_'+side];ax=e-a
    return (p-a).dot(ax)/ax.length_squared
ARM=('upper_arm_l','upper_arm_r','forearm_l','forearm_r')
def armish(j):return wsum(j,*ARM)>.5
body=GROUP_FACES['body']

# Skin-tight tops: mock neck to the waistband, long sleeves to the glove
# cuff or short sleeves to mid-bicep. 4 mm off the skin (compression knit),
# a turned hem, contrast side panels and a raglan shoulder stripe.
# Sleeve cuts as arm_t limits (0 shoulder, 1 elbow): long to the glove,
# three-quarter just below the elbow, short mid-bicep, sleeveless none.
CUTS={'Long':9.0,'Tq':1.38,'Short':.56,'Vest':-1.0}
def top_faces(cut):
    lim=CUTS[cut];out=[]
    for i in body:
        ok=True
        for j in bf[i]:
            p=RB[j]
            if p.z<.9 or p.z>1.605 or wsum(j,'hand_l','hand_r')>.45 or wsum(j,'thigh_l','thigh_r')>.35:ok=False;break
            if armish(j) and arm_t(j)>lim+.22:ok=False;break
        if ok:out.append(i)
    return out
panelmat=material('hero_top_panel',(.07,.075,.085),.55)
# Knit rib normal map (tangent space, tileable): fine vertical ribs.
if True:
    n=512;y,x=np.mgrid[0:n,0:n]/n
    g=np.random.default_rng(3).random((n,n)).astype(np.float32)
    g=(g+np.roll(g,1,0)+np.roll(g,1,1))/3
    nx=(np.roll(g,1,1)-g)*.9;ny=(np.roll(g,1,0)-g)*.9
    img=np.zeros((n,n,4),dtype=np.float32);img[:,:,0]=.5+nx*.5;img[:,:,1]=.5+ny*.5;img[:,:,2]=1;img[:,:,3]=1
    im=bpy.data.images.new('top_knit_normal',n,n,alpha=False);im.pixels.foreach_set(img.ravel());im.filepath_raw=str(TEX/'top_knit_normal.png');im.file_format='PNG';im.save()
    # Heathered knit albedo (near white: it modulates the shop colour).
    rng=np.random.default_rng(7)
    def noise_img(name,n,lo,hi,blur,extra=None):
        a=rng.random((n,n)).astype(np.float32)
        for _ in range(blur):a=(a+np.roll(a,1,0)+np.roll(a,-1,0)+np.roll(a,1,1)+np.roll(a,-1,1))/5
        a=(a-a.min())/(a.max()-a.min()+1e-6)
        v=lo+(hi-lo)*a
        rgb=np.stack([v,v,v],-1) if extra is None else extra(v)
        img=np.concatenate([rgb,np.ones((n,n,1),dtype=np.float32)],-1)
        im=bpy.data.images.new(name,n,n,alpha=False);im.pixels.foreach_set(img.ravel());im.filepath_raw=str(TEX/(name+'.png'));im.file_format='PNG';im.save()
        return TEX/(name+'.png')
    knit=noise_img('top_knit_albedo',512,.86,1.0,1)
    topmat=material('hero_top',(.16,.17,.19),.62,knit,TEX/'top_knit_normal.png')
    # Skin: fine mottling with a faint warm/cool drift (no painted features).
    skin_tex=noise_img('skin_albedo',512,.9,1.0,2,lambda v:np.stack([v*1.0,v*.985+.01,v*.975+.015],-1))
tops=[]
for cut in ['Long','Tq','Short','Vest']:
    nm='Top_'+cut
    ob,_=part(nm,top_faces(cut),RB,weights)
    push(ob,.004)
    # Clean cuts instead of whole-triangle edges: a level waist hem, sleeve
    # hems square to the arm, straight side seams for the contrast panels.
    lim=CUTS[cut]
    bm=bmesh.new();bm.from_mesh(ob.data)
    def cut_plane(co,no,kill):
        bmesh.ops.bisect_plane(bm,geom=bm.verts[:]+bm.edges[:]+bm.faces[:],plane_co=co,plane_no=no)
        bmesh.ops.delete(bm,geom=[v for v in bm.verts if kill(v.co)],context='VERTS')
    cut_plane((0,0,.95),(0,0,1),lambda co:co.z<.95-1e-5)
    if lim<9:
        for side,sx in [('l',-1),('r',1)]:
            a=J['upper_arm_'+side];e=J['forearm_'+side];h=J['hand_'+side]
            if lim<=1.0:
                pt=a+(e-a)*max(lim,0.0);ax=(e-a).normalized()
            else:
                pt=e+(h-e)*(lim-1.0);ax=(h-e).normalized()
            if lim<0:pt=a+Vector((-sx*.012,0,0))
            def beyond(co,pt=pt,ax=ax,a=a):
                along=(co-pt).dot(ax)
                off=(co-a)-ax*(co-a).dot(ax)   # distance from the arm's own axis
                return along>1e-5 and off.length<.075
            cut_plane(tuple(pt),tuple(ax),beyond)
    # Panel seams cut exactly (inner and outer side seams, and the level top
    # under the arm), so the contrast panel has straight edges, not a
    # staircase of whole triangles.
    for sx in [-1,1]:
        for px in (.135,.205):
            bmesh.ops.bisect_plane(bm,geom=bm.verts[:]+bm.edges[:]+bm.faces[:],plane_co=(sx*px,0,0),plane_no=(1,0,0))
    bmesh.ops.bisect_plane(bm,geom=bm.verts[:]+bm.edges[:]+bm.faces[:],plane_co=(0,0,1.40),plane_no=(0,0,1))
    bm.to_mesh(ob.data);bm.free();ob.data.update()
    ob.data.materials.append(topmat);ob.data.materials.append(panelmat)
    for poly in ob.data.polygons:
        c=poly.center
        poly.material_index=1 if (abs(c.x)>.135 and abs(c.x)<.205 and c.z<1.40) else 0
    so=ob.modifiers.new('Hem','SOLIDIFY');so.thickness=.003;so.offset=-1;so.use_rim_only=True;apply(ob,so)
    tops.append(ob)
top_long,top_tq,top_short,top_vest=tops
# Mock-neck band: a knitted collar fitted round the neck (rows sampled on the
# skin, 5 mm off it), so both tops end in a clean edge over the face's seam.
neck_faces=[i for i in body if all(1.45<RB[j].z<1.68 for j in bf[i])]
ntree=BVHTree.FromPolygons([RB[j] for j in range(len(RB))],[list(reversed(bf[i])) for i in neck_faces])
nc=J['neck'];rows=[1.548,1.575,1.6,1.614];ring=36;cvs=[]
for z in rows:
    for k in range(ring):
        a=math.tau*k/ring;d=Vector((math.sin(a),math.cos(a),0))
        o=Vector((nc.x,nc.y-.005,z))+d*.3
        hit=ntree.ray_cast(o,-d)
        q=hit[0] if hit[0] is not None else Vector((nc.x,nc.y,z))+d*.06
        cvs.append(q+d*(.006 if z<1.61 else .0045))
cfs=[]
for r in range(len(rows)-1):
    for k in range(ring):
        a=r*ring+k;b_=r*ring+(k+1)%ring;cfs.append([a,b_,b_+ring,a+ring])
collar=mesh('Top_Collar',cvs,[],cfs,[]);collar.data.materials.append(material('hero_top_collar',(.16,.17,.19),.62))
vgn=collar.vertex_groups.new(name='b_neck');vgc=collar.vertex_groups.new(name='b_chest')
for v in collar.data.vertices:
    w=max(0.0,min(1.0,(v.co.z-1.54)/.07));vgn.add([v.index],.35+.6*w,'REPLACE');vgc.add([v.index],.65-.6*w,'REPLACE')
so=collar.modifiers.new('Knit','SOLIDIFY');so.thickness=.003;so.offset=-1;apply(collar,so)
subdiv(collar,1)
# Bare forearms for the short sleeve: skin from under the sleeve to under
# the glove cuff (overlapping both, so no seam opens when the arm bends).
armskin=material('hero_skin_body',(.5,.34,.25),.5,skin_tex)
skin_arms=[]
for cut in ['Tq','Short','Vest']:
    lim=CUTS[cut]-.1
    af=[i for i in body if all(armish(j) and arm_t(j)>lim and wsum(j,'hand_l','hand_r')<.35 for j in bf[i])]
    if cut=='Vest':
        # Bare shoulders too: the arm's skin plus the shoulder cap round to the top.
        af=[i for i in body if all((armish(j) or (abs(RB[j].x)>.15 and RB[j].z>1.36)) and wsum(j,'hand_l','hand_r')<.35 for j in bf[i])]
    ob,_=part('Skin_Arms_'+cut,af,RB,weights);ob.data.materials.append(armskin);skin_arms.append(ob)
# Wrists under shirt cuffs: the forearm skin from inside the cuff to the hand
# (the cuff stands 1.1 cm off the wrist, so it must not open onto nothing).
af=[i for i in body if all(armish(j) and arm_t(j)>1.62 and wsum(j,'hand_l','hand_r')<.35 for j in bf[i])]
ob,_=part('Skin_Arms_Shirt',af,RB,weights);ob.data.materials.append(armskin);skin_arms.append(ob)
# Bare hands: the anatomical hand skin (knuckles, nails' shape, thumb web)
# from the hand weight 0.35 line down, exactly where the forearm skin ends.
# Grip shapes curl the fingers for the rig (as the glove's do).
hf_=[i for i in body if any(wsum(j,'hand_l','hand_r')>=.35 for j in bf[i]) and all(armish(j) or wsum(j,'hand_l','hand_r')>.2 for j in bf[i])]
hands, hand_vertex_ids = part('Skin_Hands', hf_, RB, weights)
hands.data.materials.append(armskin)
exec(compile((ROOT/'tools/blender/hand_pose.py').read_text(), 'hand_pose.py', 'exec'))
hand_grips(hands, hand_vertex_ids)
skin_arms.append(hands)
# Ankle liners: the skin round each ankle, from inside the trainer to well
# under the trouser hem, in a dark knit. Invisible when everything fits; when
# the ankle flexes it fills the gap instead of showing the sky through it.
liner_faces=[i for i in body if all(.045<RB[j].z<.24 and wsum(j,'hand_l','hand_r')<.1 for j in bf[i])]
liner,_=part('Ankle_Liner',liner_faces,RB,weights);push(liner,.003)
for vertex in liner.data.vertices:
    p = vertex.co
    foot = J['foot_l' if p.x < 0 else 'foot_r']
    taper = .12 * max(0.0, min(1.0, (.128 - p.z) / .066))
    p.x = foot.x + (p.x - foot.x) * (1 - taper)
    p.y *= 1 - taper
liner.data.materials.append(material('hero_liner',(.03,.032,.036),.9));skin_arms.append(liner)

# ------------------------------------------------------------------ faces
# Five faces from MakeHuman's facial targets (art/hero/sources/face_targets,
# CC0), applied to the head only (faded out down the neck, under the mock
# collar, so every face meets the same tops). Skin tone, hair and eye colour
# are tints set in the game (Shop "hero" items); the shapes are here.
FT={}
for f in (SRC/'face_targets').glob('*.target'):
    d={}
    for l in f.read_text().splitlines():
        a=l.split()
        if not a or a[0].startswith('#'):continue
        d[int(a[0])]=np.array(list(map(float,a[1:4])))
    FT[f.stem]=d
ETH={}
for n in ['african','asian','caucasian']:
    d={}
    for l in (SRC/(n+'-%s-young.target'%ETH_KIND)).read_text().splitlines():
        a=l.split()
        if not a or a[0].startswith('#'):continue
        d[int(a[0])]=np.array(list(map(float,a[1:4])))
    ETH[n]=d
FACES=[
    ('kai',{'african':0,'asian':0,'caucasian':0},{'cheek_l-cheek-bones-incr':.5,'cheek_r-cheek-bones-incr':.5,'chin_chin-prominent-incr':.35,'nose_nose-point-width-decr':.3,'eyebrows_eyebrows-angle-up':.3,'head_head-square':.25},'buzz'),
    ('ade',{'african':.6,'asian':-.3,'caucasian':-.3},{'head_head-square':.45,'chin_chin-width-incr':.35,'chin_chin-prominent-incr':.3,'mouth_mouth-lowerlip-volume-incr':.2,'nose_nose-nostrils-width-incr':.3,'forehead_forehead-scale-vert-decr':.3,
        'cheek_l-cheek-bones-incr':.4,'cheek_r-cheek-bones-incr':.4,'eyebrows_eyebrows-angle-down':.25,'head_head-fat-decr':.3,
        'nose_nose-scale-depth-incr':.3,'mouth_mouth-upperlip-volume-incr':.15,'head_head-age-decr':.2},'crop'),
    ('ren',{'african':-.3,'asian':.6,'caucasian':-.3},{'head_head-round':.35,'cheek_l-cheek-inner-incr':.4,'cheek_r-cheek-inner-incr':.4,'nose_nose-scale-vert-decr':.3,'eyebrows_eyebrows-trans-down':.3,'chin_chin-height-decr':.25},'crop'),
    ('theo',{'african':-.3,'asian':-.3,'caucasian':.6},{'head_head-oval':.45,'nose_nose-hump-incr':.45,'nose_nose-scale-vert-incr':.3,'chin_chin-height-incr':.35,'chin_chin-prominent-incr':.3,'mouth_mouth-scale-horiz-decr':.2},'buzz'),
    ('malik',{'african':.25,'asian':-.15,'caucasian':-.1},{'head_head-diamond':.45,'cheek_l-cheek-bones-incr':.6,'cheek_r-cheek-bones-incr':.6,'nose_nose-curve-convex':.35,'forehead_forehead-temple-incr':.4,'mouth_mouth-upperlip-volume-incr':.3},'crop'),
]
# Expression: each face carries a resting expression of its own, so the
# character isn't a neutral mask: an asymmetric relaxed smile (mouth corners
# up and back, cheeks lifted a touch), one brow a little raised. (MH units, dm.)
# Body type b's faces (character creation): its own five, each with a
# default hairstyle of its own.
FACES_B=[
    ('rio',{'african':.6,'asian':-.3,'caucasian':-.3},{'cheek_l-cheek-bones-incr':.45,'cheek_r-cheek-bones-incr':.45,'mouth_mouth-upperlip-volume-incr':.3,'mouth_mouth-lowerlip-volume-incr':.3,'nose_nose-point-width-decr':.25,'head_head-oval':.35,'chin_chin-width-decr':.3,'head_head-age-decr':.2},'curls'),
    ('sam',{'african':-.3,'asian':-.3,'caucasian':.6},{'head_head-oval':.4,'nose_nose-scale-horiz-decr':.3,'nose_nose-point-width-decr':.3,'mouth_mouth-upperlip-volume-incr':.2,'chin_chin-width-decr':.35,'cheek_l-cheek-bones-incr':.3,'cheek_r-cheek-bones-incr':.3,'eyebrows_eyebrows-trans-up':.2},'pixie'),
    ('noa',{'african':-.3,'asian':.6,'caucasian':-.3},{'head_head-round':.25,'cheek_l-cheek-inner-incr':.3,'cheek_r-cheek-inner-incr':.3,'nose_nose-scale-vert-decr':.25,'mouth_mouth-lowerlip-volume-incr':.25,'chin_chin-height-decr':.2,'head_head-age-decr':.25},'ponytail'),
    ('remy',{'african':.25,'asian':-.15,'caucasian':-.1},{'head_head-diamond':.3,'cheek_l-cheek-bones-incr':.55,'cheek_r-cheek-bones-incr':.55,'nose_nose-curve-convex':.2,'mouth_mouth-upperlip-volume-incr':.3,'chin_chin-prominent-incr':.15},'pixie'),
    ('jules',{'african':-.21,'asian':.03,'caucasian':.18},{
        'head_head-oval':.47,'head_head-diamond':.23,'cheek_l-cheek-bones-incr':.64,'cheek_r-cheek-bones-incr':.64,
        'nose_nose-hump-decr':.38,'nose_nose-point-width-decr':.25,'nose_nose-scale-vert-incr':.13,
        'chin_chin-width-decr':.38,'chin_chin-prominent-incr':.18,
        'mouth_mouth-upperlip-volume-incr':.39,'mouth_mouth-lowerlip-volume-incr':.41,
        'eyebrows_eyebrows-angle-up':.17},'bun'),
]
if BODY=='b':FACES=FACES_B
EXPRESSION={'rio':(.4,.15,('l',.2)),'sam':(.35,.2,('r',.15)),'noa':(.45,.15,('r',.1)),'remy':(.3,.25,('l',.2)),'jules':(.38,.12,('l',.15)),
    'kai':(.45,.3,('r',.25)),'ade':(.3,.1,('l',.15)),'ren':(.35,.3,('r',.15)),'theo':(.18,.42,('l',.3)),'malik':(.38,.22,('r',.3))}
def express(b,fid):
    tongue=np.array(sorted({j for i in GROUP_FACES['helper-tongue'] for j in bf[i]}))
    m=b[tongue].mean(0)
    smile_l,smile_r,(bside,braise)=EXPRESSION.get(fid,(0,0,('l',0)))
    near=np.where((np.abs(b[:,1]-m[1])<.18)&(b[:,2]>m[2]+.15)&(np.abs(b[:,0])<.45))[0]
    near=np.array([j for j in near if j not in set(tongue)])
    for sx,amt in ((-1,smile_r),(1,smile_l)):   # MH +x is the figure's left
        cand=near[(b[near,0]*sx>0)&(np.abs(b[near,1]-m[1])<.06)]
        if not len(cand):continue
        corner=b[cand[np.argmax(np.abs(b[cand,0]))]]
        d=np.linalg.norm(b-corner,axis=1);w=np.clip(1-d/.22,0,1)**2
        b[:,1]+=w*.032*amt;b[:,2]-=w*.016*amt;b[:,0]+=sx*w*.008*amt
        # the cheek above it rises a little with the smile
        ck=corner+np.array([sx*.18,.35,-.05]);d=np.linalg.norm(b-ck,axis=1);w=np.clip(1-d/.3,0,1)**2
        b[:,1]+=w*.018*amt
    # one brow raised
    ev=[b[j] for i in GROUP_FACES['helper-%s-eye'%('l' if bside=='l' else 'r')] for j in bf[i]]
    ec=np.mean(ev,0);bc=ec+np.array([0,.22,.05])
    d=np.linalg.norm(b-bc,axis=1);w=np.clip(1-d/.3,0,1)**2
    b[:,1]+=w*.03*braise
    return b
def brow_curve(ec):
    """Brow path for the eye centre ec: inner head 1.25 cm off the centre
    line, peak at 75%, tail 2.4 cm past the eye centre; (x, z) and width."""
    sx=-1 if ec.x<0 else 1
    x0=sx*.0125;x1=ec.x+sx*.024
    def line(u):
        x=x0+(x1-x0)*u
        arch=math.sin(math.pi*.5*min(1.0,u/.75))*(1 if u<.75 else 1-(u-.75)*1.8)
        return x,ec.z+.0165+.005*arch-.001*u
    def width(u):
        return .0064*(1-u)**.55+.0013
    if BODY == 'b':
        def feminine_line(u):
            return x0 + (x1 - x0) * u, ec.z + .0157 + .0072 * math.sin(math.pi * u**1.36) - .0026 * u
        def tapered_width(u):
            return .0048 * (1-u)**.75 + .0008
        return sx, feminine_line, tapered_width
    return sx,line,width
def face_base(eth,tg,fid=None):
    b=base.copy()
    fade=np.clip((b[:,1]-6.15)/.5,0,1)  # head only; zero below the collar
    for n,w in eth.items():
        for i,dl in ETH[n].items():b[i]+=dl*w*fade[i]
    for n,w in tg.items():
        if n not in FT:print('MISSING TARGET',n);continue
        for i,dl in FT[n].items():b[i]+=dl*w*fade[i]
    # Keep each face's shape, not a moved or rescaled head: remove the mean
    # shift and match the canonical head's height, about its centre.
    sel=fade>=.999
    shift=(b[sel]-base[sel]).mean(0)
    b-=shift[None,:]*fade[:,None]
    c=base[sel].mean(0)
    k=(base[sel,1].max()-base[sel,1].min())/max(b[sel,1].max()-b[sel,1].min(),1e-6)
    b=b+((c+(b-c)*k)-b)*fade[:,None]
    if fid:b=express(b,fid)
    return b
head_faces=[i for i in body if all(base[j,1]>6.3 for j in bf[i])]
# The face mesh carries the whole neck down to the upper chest (an open
# collar shows skin; built from each face's own morphed positions, so it
# meets the head with no seam). Hair and masks still use head_faces.
_hfs=set(head_faces)
face_faces=head_faces+[i for i in body if i not in _hfs and all(RB[j].z>1.46 and abs(RB[j].x)<.13 and not armish(j) for j in bf[i])]
face_meshes={}
hairmat=material('hero_hair',(.05,.04,.035),.75)
browmat=material('hero_brow',(.1,.075,.06),.7)   # (near-black read as painted bars)
HAIR_STYLES=['buzz','crop','fade','curls','pixie','ponytail','bun']
exec(compile((ROOT/'tools/blender/accessories.py').read_text(),'accessories.py','exec'))
# Garment kit helpers (UV raster bakes) are needed for hair textures here;
# empire_wardrobe.py loads the kit again for the garments.
_btree=None;NECK_Y=0.0;FRONT=1.0
exec(compile((ROOT/'tools/blender/garment_kit.py').read_text(),'garment_kit.py','exec'))
exec(compile((ROOT/'tools/blender/character_detail.py').read_text(),'character_detail.py','exec'))
LOCK_MATERIAL = make_lock_material()
EYE_MATERIAL = eye_material()
LID_MATERIAL = material('hero_lid_rim', (.29,.19,.16), .52)
HAIR_MATS={}
def hair_material(style,hair_ob,ecz,ecy):
    """One strand texture set per hairstyle (512 normal + albedo), baked on the
    first face and shared by all five (same body UV layout). Strands radiate
    from the crown (meridians), with clump and break-up octaves; curls are a
    coil pattern. Height in metres."""
    if style in HAIR_MATS:return HAIR_MATS[style]
    C=np.array([0,ecy-.095,ecz+.11])
    def height(P,N):
        v=P-C;phi=np.arctan2(v[:,0],v[:,1]);d=np.linalg.norm(v,axis=1)
        if style=='curls':
            q=P*900
            return (.0007*np.sin(q[:,0])*np.sin(q[:,1]+1.1)*np.sin(q[:,2]+2.3)+.0003*np.sin(phi*120+d*300)).astype(np.float32)
        h=(.00022*np.sin(phi*430+3*np.sin(d*90))+.00035*np.sin(phi*170+2*np.sin(d*55)+1.3)
           +.0006*np.sin(phi*48+np.sin(d*38)*2.2)*(.6+.4*np.sin(d*70)))
        return h.astype(np.float32)
    def albedo(P,N,H):
        a=.76+np.clip(H,-.0012,.0012)*100
        return np.repeat(np.clip(a,.55,1.0)[:,None],3,1).astype(np.float32)
    n_,a_=bake_detail(hair_ob,'hair_'+style,512,height,albedo)
    m=material('hero_hair_'+style,(.05,.04,.035),.76,a_,n_)
    m.node_tree.nodes['Normal Map'].inputs['Strength'].default_value=1.0
    HAIR_MATS[style]=m
    return m
def make_hair(fid,style,pos,ecz,ecy):
    """One hairstyle on one face's scalp (see the FACES loop)."""
    short_=style in ('buzz','crop','fade','curls')
    def margin(q):
        hl=.035 if style=='pixie' else .045   # forehead hairline above the eyes
        if short_:
            # a natural hairline: slight recession at the temples, small irregularity
            hl+=.008*min(1.0,max(0.0,abs(q.x)-.022)/.035)**2+.0009*math.sin(q.x*95+.7)
            # (crop/fade: a softly uneven front line - small peaks and dips, not a ruler edge)
            if style in ('crop','fade'):hl+=.0014*math.sin(q.x*157+1.9)+.0005*math.sin(q.x*311+.4)
        if BODY == 'b' and style in ('pixie','ponytail','bun','curls'):
            # Broken part and baby-hair line from the forehead across each temple.
            part = .017 if style == 'pixie' else -.012
            irregularity = .0012 * math.sin(q.x * 204 + .6) + .0009 * math.sin(q.x * 361)
            if style == 'pixie':
                hl -= .010 * math.exp(-((q.x + .021) / .026)**2)
            hl += .004 * math.exp(-((q.x - part) / .013)**2) + irregularity
        top=q.z-(ecz+hl)
        k=.005 if style not in ('crop','fade') else .011   # rounding of the hairline's corners (temples, sideburns, nape)
        smin=lambda *a:-k*math.log(sum(math.exp(-x/k) for x in a))
        smax=lambda *a:k*math.log(sum(math.exp(x/k) for x in a))
        # Short cuts turn into the nape above the collar.
        back=smin(ecy-.085-q.y,q.z-(ecz-(.048 if style in ('crop','fade') else .07)))
        temple=smin(abs(q.x)-.055,ecy-.03-q.y,q.z-(ecz+(-.012 if style=='pixie' else .012)))
        extent = smax(top,back,temple)
        ear = math.sqrt(((q.y-(ecy-.059))/.034)**2 + ((q.z-(ecz-.019))/.035)**2)
        if abs(q.x) > .059:
            extent = min(extent, (ear - 1.0) * .028)
        return extent
    hf=[i for i in head_faces if any(margin(pos[j])>-.012 for j in bf[i])]
    hair,_=part('Hair_%s_%s'%(style,fid),hf,pos,weights)
    subdiv(hair,1)
    bm=bmesh.new();bm.from_mesh(hair.data)
    # Cut exactly along the hairline (the margin's zero line): split every edge
    # where it crosses, join the splits across faces, drop the outside. Plane
    # cuts plus whole-vertex deletion left a saw-tooth and square sideburns.
    vals={v:margin(v.co) for v in bm.verts}
    news=[]
    for e in [e for e in bm.edges if (vals[e.verts[0]]<0)!=(vals[e.verts[1]]<0)]:
        a_,b_=e.verts;fa,fb=vals[a_],vals[b_]
        ne,nv=bmesh.utils.edge_split(e,a_,fa/(fa-fb))
        vals[nv]=0.0;news.append(nv)
    bmesh.ops.connect_verts(bm,verts=news)
    bmesh.ops.delete(bm,geom=[v for v in bm.verts if vals.get(v,margin(v.co))<-1e-7],context='VERTS')
    bm.normal_update()
    top=max(v.co.z for v in bm.verts)
    hc=Vector((0,sum(v.co.y for v in bm.verts)/len(bm.verts),0))
    for v in bm.verts:
        # (crop/fade: the thickness grows over 3 cm in from the edge - over
        # 1 cm the front edge stood off the forehead like a visor)
        fadein=max(0.0,min(1.0,margin(v.co)/(.03 if style in ('crop','fade') else .01)))
        fadein=fadein*fadein*(3-2*fadein)
        up=max(0.0,min(1.0,(v.co.z-(top-.08))/.06))   # 0 round the sides, 1 on top
        up_f=max(0.0,min(1.0,(v.co.z-(top-.055))/.03))   # the fade's top block starts higher, sharper
        # Sides and back hug the scalp (short, faded); the volume is on top.
        side=max(0.0,min(1.0,(v.co.z-(ecz+.035))/.045))
        lift={'buzz':.0009,'crop':.00065+.0011*side+.0037*up,'fade':.00052+.010*up_f**1.65,'curls':.004+.012*up,
              'pixie':.0023+.0065*up,'ponytail':.0035,'bun':.0035}[style]
        if style=='curls':
            p_=v.co*170.0
            lift+=.0045*(math.sin(p_.x)*math.sin(p_.y+1.3)*math.sin(p_.z+.7)+.4)
        if style=='pixie' and v.co.y>ecy-.04 and v.co.z<ecz+.07:
            lift+=.006   # the fringe stands off the forehead
        if style in ('crop','fade','pixie','buzz'):
            # sculpted clumps radiating from the crown (break the helmet surface and silhouette)
            cr=v.co-Vector((0,ecy-.095,top-.01));phi=math.atan2(cr.x,cr.y);dd=cr.length
            amp={'crop':.0042*up+.0005,'fade':.0032*up_f+.0003,'pixie':.002,'buzz':.0004}[style]
            lift+=amp*(.55+.45*math.sin(phi*23+math.sin(dd*45)*1.6)*math.sin(dd*80+phi*4))
            if style in ('crop','fade'):
                # forward-swept clumps (longer along the sweep, offset row to
                # row) and a finer break-up: a textured top, a ragged outline
                fw=v.co.y-(ecy-.095)
                edge_=max(0.0,min(1.0,(margin(v.co)-.006)/.015))
                lift+=(.0026*up+.0004)*edge_*max(0.0,math.sin(v.co.x*260+math.sin(fw*60)*2.2)*math.sin(fw*95+v.co.x*40))
                swept = v.co.x + .40*fw + .0026*math.sin(fw*54)
                lift += .0029*up*edge_*max(0,math.sin(swept*220+math.sin(fw*92)*.8))**2
                lift += .0006*up*math.sin(v.co.x*610+fw*330)*math.sin(fw*540-v.co.x*200)
        v.co+=v.normal*(.00006+lift*fadein)
    bm.to_mesh(hair.data);bm.free();hair.data.update()
    simplify_surface(hair, .61)
    so=hair.modifiers.new('Edge','SOLIDIFY');so.thickness=.0007;so.offset=-1;so.use_rim_only=True;apply(hair,so)
    hair.data.materials.append(hair_material(style,hair,ecz,ecy))
    cards = groom_locks(hair, fid, style, margin, ecz, ecy, LOCK_MATERIAL)
    # Per-corner density lets scalp shading transition gradually into the roots.
    layer = hair.data.uv_layers.new(name='GroomDensity')
    for loop in hair.data.loops:
        p = hair.data.vertices[loop.vertex_index].co
        edge = max(0.0, min(1.0, margin(p) / (.009 if short_ else .004)))
        if style in ('buzz', 'crop', 'fade'):
            fade = max(0.0, min(1.0, (p.z - top + .11) / (.065 if style == 'fade' else .060)))
            edge *= .18 + .82 * fade if style != 'buzz' else .52
        layer.data[loop.index].uv = (0.0, edge)
    hair.data.uv_layers.active_index = 0
    extras=[]
    if style in ('ponytail','bun'):
        vs=[v.co for v in hair.data.vertices]
        back=lambda z:min((q.y for q in vs if abs(q.z-z)<.008 and abs(q.x)<.02),default=hc.y-.09)
        if style=='bun':
            reference = BODY == 'b' and fid == 'jules'
            if reference:
                crown = max(vs, key=lambda q: q.z)
                anchor = min(vs, key=lambda q: (q - crown - Vector((-.008, -.032, -.006))).length_squared)
                c = anchor + Vector((0, -.009, .022))
                tie_c = anchor + Vector((0, -.003, .005))
                tie_r = .024
                from build_b_surface import length_material
                lock_material = length_material(hair.data.materials[0], TEX, 'hair_lengths_b')
                extras.append(wound_gather(c, .046, lock_material))
            else:
                z = ecz + .07
                c = Vector((0, back(z) - .022, z))
                tie_c = c + Vector((0, .026, -.004))
                tie_r = .03
                bpy.ops.mesh.primitive_uv_sphere_add(segments=20,ring_count=12,radius=.036,location=c)
                o_=bpy.context.object;o_.scale=(1.15,.9,.95)
                for p_ in o_.data.polygons:p_.use_smooth=True
                # wrapped look: faint rings across the bun
                for v in o_.data.vertices:v.co*=1+.06*math.sin(v.co.z*90)
                active(o_);bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
                extras.append(o_)
        else:
            z=ecz+.05;yb=back(z)
            path=[Vector((0,yb+.006,z)),Vector((0,yb-.028,z-.012)),Vector((0,yb-.05,z-.06)),Vector((0,yb-.056,z-.13)),
                  Vector((0,yb-.05,z-.2)),Vector((0,yb-.036,z-.26))]
            rad=[.024,.03,.029,.024,.016,.005]
            bm2=bmesh.new();loops=[];segs=14
            for k,c in enumerate(path):
                t=(path[min(k+1,len(path)-1)]-path[max(k-1,0)]).normalized()
                f=Vector((1,0,0));sd=t.cross(f).normalized()
                loops.append([bm2.verts.new(c+f*math.cos(a)*rad[k]*1.05+sd*math.sin(a)*rad[k]*.85) for a in [i*math.tau/segs for i in range(segs)]])
            for r0,r1 in zip(loops,loops[1:]):
                for k in range(segs):bm2.faces.new((r0[k],r0[(k+1)%segs],r1[(k+1)%segs],r1[k]))
            bm2.faces.new(loops[0]);bm2.faces.new(list(reversed(loops[-1])))
            bmesh.ops.recalc_face_normals(bm2,faces=bm2.faces)
            me=bpy.data.meshes.new('tail');bm2.to_mesh(me);bm2.free()
            o_=bpy.data.objects.new('tail',me);bpy.context.collection.objects.link(o_)
            for p_ in o_.data.polygons:p_.use_smooth=True
            extras.append(o_);tie_c=path[0]+Vector((0,-.012,-.004));tie_r=.021
        tie_rotation = .26 if style == 'bun' and BODY == 'b' and fid == 'jules' else math.pi/2 - .5
        bpy.ops.mesh.primitive_torus_add(major_radius=tie_r,minor_radius=.0045,major_segments=20,minor_segments=6,location=tie_c,rotation=(tie_rotation,0,0))
        tie=bpy.context.object;active(tie);bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
        tie.data.materials.append(material('hero_hair_tie',(.03,.03,.035),.5))
        for o_ in extras:
            if not o_.data.materials:
                o_.data.materials.append(hair.data.materials[0])
        extras.append(tie)
        uvl=hair.data.uv_layers.active
        if uvl is not None:
            for o_ in extras:
                while len(o_.data.uv_layers)<len(hair.data.uv_layers):o_.data.uv_layers.new()
                for k_,L in enumerate(hair.data.uv_layers):
                    if k_ == 0 and o_.name == 'Wound bun':
                        o_.data.uv_layers[0].name = L.name
                        continue
                    o_.data.uv_layers[k_].name=L.name
                    src=L.data[hair.data.polygons[0].loop_indices[0]].uv.copy()
                    # A tiny patch round that UV, laid out from position:
                    # one flat UV would leave no tangents for the normal map
                    # (NaN normals = black speckles).
                    for poly in o_.data.polygons:
                        for li in poly.loop_indices:
                            co=o_.data.vertices[o_.data.loops[li].vertex_index].co
                            if L.name == 'GroomDensity':
                                o_.data.uv_layers[k_].data[li].uv = (0, 1)
                            else:
                                o_.data.uv_layers[k_].data[li].uv=(src.x+(co.x+.6*co.y)*.04,src.y+co.z*.04)
        for o_ in extras:
            vg=o_.vertex_groups.new(name='b_head');vg.add(list(range(len(o_.data.vertices))),1,'REPLACE')
        bpy.ops.object.select_all(action='DESELECT')
        for o_ in extras:o_.select_set(True)
        hair.select_set(True);bpy.context.view_layer.objects.active=hair;bpy.ops.object.join()
    return hair, cards
canon=None
anatomy_study = None
for fid,eth,tg,style in FACES:
    fb=face_base(eth,tg,fid)
    pos=[retarget(fb[j],weights[j]) for j in range(len(fb))]
    sculpt_head(pos, fid)
    if BODY == 'b':
        socket_ids = [{j for i in GROUP_FACES['helper-%s-eye'%side] for j in bf[i]} for side in ('l','r')]
        lash_ids = {j for side in ('l','r') for band in (1,2)
                    for i in GROUP_FACES['helper-%s-eyelashes-%s'%(side,band)] for j in bf[i]}
        female.face_planes(pos, {j for i in head_faces for j in bf[i]} | lash_ids, socket_ids,
                           {j for i in GROUP_FACES['helper-tongue'] for j in bf[i]}, fid == 'jules')
    face,ids=part('Face_'+fid,face_faces,pos,weights)
    # Lips: around the mouth, in front of the tongue.
    tongue=[pos[j] for i in GROUP_FACES['helper-tongue'] for j in bf[i]]
    mc=sum(tongue,Vector())/len(tongue)
    if canon is None:canon=(fb,pos,mc)
    if BODY == 'b' and fid == 'jules':
        # Keep the authored quad loops through lips, nostrils and lids.
        # Shape the finer cage before baking so geometry and texels agree.
        subdiv(face, 2)
        eyes = [sum((pos[i] for i in ids), Vector()) / len(ids) for ids in socket_ids]
        female.sculpt_portrait(face.data, eyes, mc)
        head_ids = {j for i in face_faces for j in bf[i]}
        study_vertices = [p if i in head_ids else RB[i] for i, p in enumerate(pos)]
        anatomy_study, _ = part('Build B anatomy study', body, study_vertices, weights)
        subdiv(anatomy_study, 1)
        female.sculpt_portrait(anatomy_study.data, eyes, mc)
        anatomy_study.data.materials.append(material('Neutral sculpt clay', (.27, .28, .30), .68))
        anatomy_study.hide_render = True
        anatomy_study.hide_set(True)
    if BODY == 'a' and fid == 'ade':
        subdiv(face, 1)
        eyes = []
        for side in ('l', 'r'):
            orbit = {j for i in GROUP_FACES['helper-%s-eye'%side] for j in bf[i]}
            eyes.append(sum((pos[i] for i in orbit), Vector()) / len(orbit))
        female.sculpt_portrait(face.data, eyes, mc, lip_volume=.53)
    # Face albedo, per face (1024, the face's own packed UVs): skin mottling;
    # lips from a smooth mask (the per-polygon lip material had a stair-step
    # edge) in the rig's lip ratio of the skin tone; a scalp shadow under the
    # hairline (so the hair edge reads as roots, not a cut); a soft shadow
    # under the brows; a little warmth in the cheeks and depth under the eyes.
    pack_uvs(face)
    _ev=[pos[j] for i in GROUP_FACES['helper-l-eye']+GROUP_FACES['helper-r-eye'] for j in bf[i]]
    _ez=sum(v.z for v in _ev)/len(_ev);_ey=sum(v.y for v in _ev)/len(_ev);_ex=max(abs(v.x) for v in _ev)-.012
    face_resolution = 1024 if fid in ('jules', 'ade') else 768
    P_,N_,M_=raster_uv(face,face_resolution)
    X,Y,Z=P_[M_,0],P_[M_,1],P_[M_,2]
    nx,ny,nz = N_[M_].T
    mott = (.93 + .009*np.sin(X*128+Z*154)*np.sin(Y*149-Z*86)
            + .011*np.sin(X*431+Y*379)*np.sin(Z*373+1)
            + .008*np.sin(X*1477+Z*1517)*np.sin(Y*1630+2))
    col = np.stack([mott * 1.035, mott, mott * .982], 1)
    tip = np.exp(-((X/.022)**2 + ((Z-(_ez-.034))/.019)**2)) * np.clip(ny, 0, 1)
    ear = np.exp(-(((np.abs(X)-.075)/.024)**2+((Z-(_ez-.021))/.042)**2)) * np.clip(np.abs(nx)*2-.45,0,1)
    warmth = np.clip(tip + .72*ear, 0, 1)
    col *= 1 + warmth[:,None] * np.array([.042,-.052,-.082])
    nasal = np.exp(-((np.abs(X)-.0134)/.0047)**2 - ((Z-(_ez-.042))/.0048)**2)
    col *= (1 - .24*nasal*np.clip(ny+.2,0,1))[:,None]
    ear_cavity = ear * np.clip(-ny, 0, 1) * np.exp(-((Z-(_ez-.013))/.018)**2)
    col *= (1 - .16*ear_cavity)[:,None]
    # Slightly cooler jaw; backlit cartilage and lips keep their own pigment.
    jaw = np.exp(-(((Z-(mc.z-.018))/.033)**2+((Y-mc.y+.002)/.073)**2))
    if BODY == 'a':
        col *= 1 + jaw[:,None] * np.array([-.092,-.055,-.018])
        if fid == 'ade':
            female.warm_skin(col, X, Y, Z, nx, ny, _ez, _ey)
    else:
        female.warm_skin(col, X, Y, Z, nx, ny, _ez, _ey)

    lip_u = X/.026
    seam_z = mc.z-.0007 + .0018*np.minimum(lip_u**2,1)
    cupid = .0018*np.exp(-((np.abs(lip_u)-.27)/.20)**2)
    lip_h = np.where(Z > seam_z, .0059+cupid, .0082)
    lm = np.clip(1-lip_u**2-((Z-seam_z)/lip_h)**2,0,1)
    lm = np.clip(lm*1.85,0,1)**1.2*np.clip((Y-(mc.y+.006))/.006,0,1)
    lip_tone = [-.083,-.214,-.221] if BODY == 'b' else [-.101,-.252,-.265]
    col *= 1 + lm[:,None]*np.array(lip_tone)
    # the lips' parting: a thin soft dark line, not a dark mouth
    pl=np.clip(1-np.abs(Z-seam_z)/.0011,0,1)*np.clip(1-(X/.024)**2,0,1)*np.clip((Y-(mc.y+.006))/.004,0,1)
    col*=(1-.32*pl)[:,None]
    # a soft highlight along the upper lip's top (volume, a Cupid's bow)
    hl_=np.clip(1-((X/.017)**2+((Z-(mc.z+.0055))/.0024)**2),0,1)*np.clip((Y-(mc.y+.008))/.004,0,1)
    col*=(1+.07*hl_)[:,None]
    for side_ in ('l','r'):
        _e=[pos[j] for i in GROUP_FACES['helper-%s-eye'%side_] for j in bf[i]];_ec=sum(_e,Vector())/len(_e)
        _,bl,bw=brow_curve(_ec)
        us=np.linspace(0,1,40);pts=np.array([bl(u) for u in us]);ws=np.array([bw(u) for u in us])
        d=np.full(len(X),9.0);wn=np.zeros(len(X))
        for (px,pz),w in zip(pts,ws):
            dd=np.hypot(X-px,Z-pz);m=dd<d;d[m]=dd[m];wn[m]=w
        bm_=np.exp(-2.8*(d/(wn*.72+.0007))**2)*(Y>_ec.y-.01)
        col*=(1-.46*bm_)[:,None]   # (.42 read as painted brows under the hairs)
        # upper-lid crease: a faint shadow arc above the eye
        cr_=np.clip(1-(((X-_ec.x)/.015)**2+((Z-(_ec.z+.0075))/.0028)**2),0,1)*(Y>_ec.y-.006)
        col*=(1-.12*cr_)[:,None]
        sx_=-1 if _ec.x<0 else 1
        ck=np.clip(1-(((X-sx_*(_ex+.012))/.03)**2+((Z-(_ez-.03))/.022)**2),0,1)*np.clip((Y-_ey)/.02+.5,0,1)
        col*=(1+np.array([.035,-.01,-.015])*ck[:,None])
        ue=np.clip(1-(((X-sx_*_ex)/.017)**2+((Z-(_ez-.012))/.006)**2),0,1)
        col*=(1-.07*ue)[:,None]
    if BODY == 'b' and fid == 'jules':
        reference = image_load(SRC / 'jules-portrait-reference.jpeg')
        rw, rh = reference.size
        sample = np.empty(rw * rh * 4, np.float32)
        reference.pixels.foreach_get(sample)
        eye_x = sum(abs(p.x) for p in eyes) / 2
        col = project_portrait(col, P_[M_], N_[M_], (eye_x, _ey, _ez), mc,
                              sample.reshape(rh, rw, 4)[..., :3])
        bpy.data.images.remove(reference)
    A_=np.ones((face_resolution,face_resolution,3),np.float32);A_[M_]=col
    _fa=_save('face_%s_albedo'%fid,_dilate(A_,M_,12))
    def face_relief(P, N):
        x,y,z = P.T
        lip = np.exp(-(x/.028)**2-((z-mc.z)/.010)**2)*np.clip((y-mc.y-.004)/.007,0,1)
        philtrum = np.exp(-((np.abs(x)-.004)/.0028)**2-((z-mc.z-.013)/.012)**2)
        relief = .000095*np.sin(x*1371+z*54)*lip + .00038*philtrum*np.clip(N[:,1],0,1)
        if fid in ('jules', 'ade'):
            relief += .000042 * np.sin(x*3914+y*3455+z*902) * np.sin(z*3091-x*1644)
        return relief
    face_normal, _ = bake_detail(face,'face_'+fid,face_resolution if fid in ('jules', 'ade') else 512,face_relief)
    fmat=material('hero_skin_face_'+fid,(.5,.34,.25),.50 if BODY=='b' and fid=='jules' else .56,_fa,face_normal)
    fmat.node_tree.nodes['Normal Map'].inputs['Strength'].default_value = .62
    if fid not in ('jules', 'ade'):
        subdiv(face, 1)
        simplify_surface(face, .36 if BODY == 'a' else .68)
    face.data.materials.append(fmat)
    parts_=[face]
    lashes, eye_centres, eye_radii = [], [], []
    # Anatomical spheres with a continuous sclera, iris and pupil atlas.
    for side in ['l','r']:
        ef=GROUP_FACES['helper-%s-eye'%side]
        eye,eids=part('Eye_%s_%s'%(side,fid),ef,pos,weights)
        subdiv(eye,1)
        origin = sum((v.co for v in eye.data.vertices), Vector())/len(eye.data.vertices)
        for v in eye.data.vertices:
            d = (v.co-origin).normalized()
            projection = .0007 if BODY == 'b' else .0018
            v.co.y += projection * max(d.y,0.0)**12 - (.0007 if BODY == 'b' else 0.0)
        map_eye(eye)
        eye.data.materials.append(EYE_MATERIAL)
        c=sum((v.co for v in eye.data.vertices),Vector())/len(eye.data.vertices)
        eye_centres.append(c)
        eye_radii.append(max((v.co-c).length for v in eye.data.vertices))
        parts_.append(eye)
        # Eyelid helper landmarks drive closure; the eyelid itself supplies
        # the visible edge. A separate opaque lash strip obscures the tearline.
        lf = GROUP_FACES['helper-%s-eyelashes-1'%side] + GROUP_FACES['helper-%s-eyelashes-2'%side]
        lashes.append([pos[j] for j in sorted({j for i in lf for j in bf[i]})])
    # Brows: tapered strand clumps laid on the brow ridge (the old flat strips
    # read as painted bars and met in the middle). Inner strands point up and
    # out, the body runs outward, the tail tapers down; a 2.5 cm gap between.
    tree=BVHTree.FromPolygons([v.co for v in face.data.vertices],[list(p.vertices) for p in face.data.polygons])
    for side, centre, radius, tips in zip(('l','r'), eye_centres, eye_radii, lashes):
        parts_.extend(eye_lid_rims(tree, centre, radius, tips, 'Lid_'+side+'_'+fid))
    brng=np.random.default_rng(stable_seed(fid, 'brows'))
    for side,sx in [('l',-1),('r',1)]:
        ev=[pos[j] for i in GROUP_FACES['helper-%s-eye'%side] for j in bf[i]]
        ec=sum(ev,Vector())/len(ev)
        sx=-1 if ec.x<0 else 1
        _,brow_line,width=brow_curve(ec)
        def on_face(x,z,lift=.0005):
            hit=tree.ray_cast(Vector((x,ec.y+.2,z)),Vector((0,-1,0)))
            return (hit[0]+hit[1]*lift) if hit[0] is not None else Vector((x,ec.y+.012,z))
        vs=[];fs=[]
        for k in range(83):
            u=min(.998, max(.003, (k+.35+brng.uniform(-.35,.35))/83))**1.12
            v=float(brng.uniform(-.38,.38))
            bx,bz=brow_line(u);w=width(u)
            ang=math.radians(72-75*min(1.0,u/.45)) if u<.75 else math.radians(-3-18*(u-.75)/.25)
            ln=(.0057+.0023*min(1.0,u/.4))*(1-.31*u**3)
            d2=(sx*math.cos(ang),math.sin(ang))
            sx0,sz0=bx-d2[0]*ln*.45,bz+v*w-d2[1]*ln*.45
            sw=brng.uniform(.00012,.00023)*(1-.36*u)
            b0=len(vs)
            for t_ in range(4):
                tt=t_/3
                px,pz=sx0+d2[0]*ln*tt,sz0+d2[1]*ln*tt
                c=on_face(px,pz,.00024+.00034*math.sin(math.pi*tt)+k*.0000012)
                ww=sw*(1-.85*tt)
                nx,nz=-d2[1],d2[0]
                vs.append(on_face(px+nx*ww,pz+nz*ww,.00024+.00034*math.sin(math.pi*tt)+k*.0000012))
                vs.append(on_face(px-nx*ww,pz-nz*ww,.00024+.00034*math.sin(math.pi*tt)+k*.0000012))
            for t_ in range(3):
                a_=b0+2*t_
                fs.append([a_,a_+2,a_+3,a_+1] if sx>0 else [a_,a_+1,a_+3,a_+2])
        brow=mesh('Brow_%s_%s'%(side,fid),vs,[],fs,[])
        face_out(brow, lambda _: Vector((0,1,0)))
        brow.data.materials.append(browmat)
        for p_ in brow.data.polygons:p_.use_smooth=True
        vg=brow.vertex_groups.new(name='b_head');vg.add(list(range(len(vs))),1,'REPLACE');parts_.append(brow)
    # Hair: cut from the scalp itself above a hairline and lifted off it,
    # one mesh per style per face (so each fits its own head). Styles:
    #   buzz/crop/fade/curls  short cuts, different volume on top
    #   pixie                 a soft crop with a fringe and sideburns
    #   bob                   a curtain that falls straight to the jaw
    #   ponytail/bun          tight on the scalp, gathered at the back
    # (MakeHuman's hair helper is long draped cards, not a cap.)
    ev2=[pos[j] for i in GROUP_FACES['helper-l-eye']+GROUP_FACES['helper-r-eye'] for j in bf[i]]
    ecz=sum((v.z for v in ev2))/len(ev2);ecy=sum((v.y for v in ev2))/len(ev2)
    hair_meshes, groom_meshes = zip(*(make_hair(fid, style_, pos, ecz, ecy) for style_ in HAIR_STYLES))
    if BODY == 'b' and fid == 'jules':
        parts_.extend(female.hoops(face, ecz, ecy))
    # One object per face (skin, lips, eyes, lashes, brows); hair apart.
    bpy.ops.object.select_all(action='DESELECT')
    for o in parts_:o.select_set(True)
    bpy.context.view_layer.objects.active=face;bpy.ops.object.join()
    blink_shape(face, lashes, (eye_centres, eye_radii), fmat)
    acc_meshes=make_accessories(fid,pos,face,ecz,ecy,dict(zip(HAIR_STYLES,hair_meshes)))
    face_meshes[fid]=[face, *hair_meshes, *groom_meshes, *acc_meshes]

# ------------------------------------------------------------------ masks
# Fitted to the canonical (first) face, 9-12 mm off it so every face fits.
fb,cpos,mouth=canon
head_ids=sorted({j for i in head_faces for j in bf[i]})
le=[cpos[j] for i in GROUP_FACES['helper-l-eye'] for j in bf[i]];re_=[cpos[j] for i in GROUP_FACES['helper-r-eye'] for j in bf[i]]
eye_l=sum(le,Vector())/len(le);eye_r=sum(re_,Vector())/len(re_);eye_z=(eye_l.z+eye_r.z)/2
masks=[]
def hull_mask(name,pts,offset,cut=None,mat=None,planes=()):
    hc=sum(pts,Vector())/len(pts)
    bm=bmesh.new()
    for p_ in pts:bm.verts.new(p_+(p_-Vector((0,hc.y-.02,p_.z if False else hc.z))).normalized()*0)
    bmesh.ops.convex_hull(bm,input=bm.verts[:],use_existing_faces=False)
    bmesh.ops.recalc_face_normals(bm,faces=bm.faces)
    # Subdivide first so cut edges are fine, then cut exactly on the planes.
    bmesh.ops.subdivide_edges(bm,edges=bm.edges[:],cuts=1,use_grid_fill=True)
    for co,no in planes:
        bmesh.ops.bisect_plane(bm,geom=bm.verts[:]+bm.edges[:]+bm.faces[:],plane_co=co,plane_no=no)
    if cut:
        bmesh.ops.delete(bm,geom=[f for f in bm.faces if cut(f.calc_center_median(),f.normal)],context='FACES')
    me=bpy.data.meshes.new(name);bm.to_mesh(me);bm.free()
    ob=bpy.data.objects.new(name,me);bpy.context.collection.objects.link(ob)
    push(ob,offset)
    for p_ in ob.data.polygons:p_.use_smooth=True
    active(ob);bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.uv.smart_project(island_margin=.02);bpy.ops.object.mode_set(mode='OBJECT')
    so=ob.modifiers.new('Edge','SOLIDIFY');so.thickness=.0025;so.offset=-1;so.use_rim_only=True;apply(ob,so)
    vh=ob.vertex_groups.new(name='b_head');vn=ob.vertex_groups.new(name='b_neck')
    for v in ob.data.vertices:
        w=max(0,min(1,(v.co.z-1.57)/.09));vh.add([v.index],w,'REPLACE');vn.add([v.index],1-w,'REPLACE')
    ob.data.materials.append(mat);masks.append(ob);return ob
headpts=[cpos[j] for j in head_ids]
# Courier: the signature full mask (textile envelope) and smoked lens.
cour=[]
for q in headpts:
    q=q.copy()
    if q.y>.13:q.y=.13
    q.z-=.018
    if q.z<1.65:
        q.x*=.55+.45*max(0,(q.z-1.54)/.11)
        q.z-=max(0,(1.62-q.z))*.32
    cour.append(q)
hull_mask('Mask_courier',cour,.004,None,material('hero_mask_courier',(.018,.022,.027),.8))
mtree_ob=masks[-1]
mtree=BVHTree.FromPolygons([v.co for v in mtree_ob.data.vertices],[list(p.vertices) for p in mtree_ob.data.polygons])
vs=[]
for row in range(3):
    for col in range(9):
        x=-.076+col*.019
        z=eye_z+(row-1)*.014-abs(x)*.075
        hit=mtree.ray_cast(Vector((x,1,z)),Vector((0,-1,0)))
        y=(hit[0].y if hit[0] is not None else .12)+.002
        vs.append((x,y,z))
fs=[[r*9+c,r*9+c+9,r*9+c+10,r*9+c+1] for r in range(2) for c in range(8)]
lens=mesh('Mask_courier_lens',vs,[],fs,[]);lens.data.materials.append(material('hero_lens',(.008,.013,.017),.24))
vg=lens.vertex_groups.new(name='b_head');vg.add(list(range(len(vs))),1,'REPLACE');masks.append(lens)
# Runner: a gaiter pulled up over the nose (lower face and neck).
lower=[p_ for p_ in headpts if p_.z<eye_z-.014]
hull_mask('Mask_runner',lower,.007,lambda c,n:c.z>eye_z-.016,material('hero_mask_runner',(.06,.065,.075),.85),
    [((0,0,eye_z-.016),(0,0,1))])
# Bandana: a square scarf tied over the nose, its point hanging below the
# chin. Fitted round the face like the gaiter (so no lips or nose poke
# through on any face), plus the drape's point in front of the throat.
chin_z=mouth.z-.042   # the chin's underside, from the mouth (the head mesh runs on down the neck)
band=[p_ for p_ in headpts if chin_z<p_.z<eye_z-.02]
front=max(p_.y for p_ in band)
band+=[Vector((0,front-.012,chin_z-.05)),Vector((-.028,front-.03,chin_z-.026)),Vector((.028,front-.03,chin_z-.026))]
hull_mask('Mask_bandana',band,.008,lambda c,n:c.z>eye_z-.022 or (n.y<-.3 and c.z<chin_z+.01),material('hero_bandana',(.6,.1,.09),.85),
    [((0,0,eye_z-.022),(0,0,1))])
kn=[]
for k,(d,r) in enumerate([((0,-.012,0),.017),((-.016,-.03,-.03),.009),((.012,-.034,-.045),.009)]):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=10,ring_count=7,radius=r,location=Vector((0,min(p_.y for p_ in band)-.002,eye_z-.03))+Vector(d))
    o_=bpy.context.object;o_.scale=(1.1,.75,1.4 if k else 1.0);active(o_);bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    kn.append(o_)
bpy.ops.object.select_all(action='DESELECT')
for o_ in kn:o_.select_set(True)
bpy.context.view_layer.objects.active=kn[0];bpy.ops.object.join();knot=kn[0];knot.name='Mask_bandana_knot'
for p_ in knot.data.polygons:p_.use_smooth=True
knot.data.materials.append(material('hero_bandana_knot',(.6,.1,.09),.85))
vg=knot.vertex_groups.new(name='b_head');vg.add(list(range(len(knot.data.vertices))),1,'REPLACE');masks.append(knot)
# Balaclava: the whole head with an eye window.
hull_mask('Mask_balaclava',headpts,.008,lambda c,n:abs(c.x)<.07 and abs(c.z-eye_z)<.016 and n.y>.4,material('hero_mask_balaclava',(.03,.03,.035),.9),
    [((0,0,eye_z+.016),(0,0,1)),((0,0,eye_z-.016),(0,0,1)),((.07,0,0),(1,0,0)),((-.07,0,0),(1,0,0))])
# Domino: a thin band laid on the face round the eyes, with round eye holes.
dom_faces=[i for i in head_faces if all(abs(cpos[j].z-eye_z)<.024 and cpos[j].y>eye_l.y-.04 for j in bf[i])]
dom,_=part('Mask_domino',dom_faces,cpos,weights)
subdiv(dom,1)
bm=bmesh.new();bm.from_mesh(dom.data)
bmesh.ops.delete(bm,geom=[v for v in bm.verts if (Vector((v.co.x,0,v.co.z))-Vector((eye_l.x,0,eye_l.z))).length<.0145
    or (Vector((v.co.x,0,v.co.z))-Vector((eye_r.x,0,eye_r.z))).length<.0145],context='VERTS')
bm.normal_update()
for v in bm.verts:v.co+=v.normal*.0035
bm.to_mesh(dom.data);bm.free()
for v in dom.data.vertices:
    for g in list(v.groups):pass
so=dom.modifiers.new('Edge','SOLIDIFY');so.thickness=.002;so.offset=-1;apply(dom,so)
for p_ in dom.data.polygons:p_.use_smooth=True
active(dom);bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.uv.smart_project(island_margin=.02);bpy.ops.object.mode_set(mode='OBJECT')
dom.data.materials.append(material('hero_mask_domino',(.02,.02,.025),.4));masks.append(dom)
# Respirator: a moulded shell over mouth and nose, two filters.
resp=[p_ for p_ in headpts if p_.z<eye_z-.022 and p_.z>mouth.z-.05 and p_.y>mouth.y-.045]
rm_=hull_mask('Mask_respirator',resp,.012,lambda c,n:n.y<-.1,material('hero_mask_respirator',(.12,.125,.13),.4))
fmat=material('hero_mask_filter',(.85,.42,.08),.5)
for sx in [-1,1]:
    c=Vector((sx*.045,mouth.y+.02,mouth.z-.004))
    bpy.ops.mesh.primitive_cylinder_add(vertices=14,radius=.019,depth=.022,location=c,rotation=(math.pi/2,0,sx*.55))
    f_=bpy.context.object;f_.name='Mask_respirator_filter_'+('l' if sx<0 else 'r')
    f_.data.materials.append(fmat)
    vg=f_.vertex_groups.new(name='b_head');vg.add(list(range(len(f_.data.vertices))),1,'REPLACE')
    active(f_);bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
    masks.append(f_)

exec(compile((ROOT/'tools/blender/empire_wardrobe.py').read_text(),'empire_wardrobe.py','exec'))
# Bare forearms under the short sleeves of the tee and polo.
for cut in ['Tee','Polo']:
    # Skin extends inside the actual sleeve opening by 2.5cm. Trims and
    # exposed skin use the same arm weights all the way to the hand seam.
    def inside_sleeve(j):
        p = RB[j]
        arm = frames()[1]['l' if p.x < 0 else 'r']
        t, _, radius = arm.polar(p)
        return t > SHORT_T - .047 and radius < .105 and wsum(j, 'hand_l', 'hand_r') < .35
    arm_faces = [i for i in body if all(inside_sleeve(j) for j in bf[i])]
    arm_skin, _ = part('Skin_Arms_' + cut, arm_faces, RB, weights)
    arm_skin.data.materials.append(armskin)
    skin_arms.append(arm_skin)
for cut in ('Jumper', 'Hoodie', 'Bomber', 'Long') + (('Blazer',) if BODY == 'a' else ()):
    wrist_skin = next(o for o in skin_arms if o.name == 'Skin_Arms_Shirt')
    copy = wrist_skin.copy()
    copy.data = wrist_skin.data.copy()
    copy.name = 'Skin_Arms_' + cut
    bpy.context.collection.objects.link(copy)
    skin_arms.append(copy)
exec(compile((ROOT/'tools/blender/fashion_wardrobe.py').read_text(),'fashion_wardrobe.py','exec'))
refit_vest()
if BODY=='b':
    build_fashion()
    casual_reference_outfits()
all_meshes=[top_long,top_tq,top_short,top_vest,collar]+skin_arms+[pants,shoes,gloves]+[o for ps in face_meshes.values() for o in ps]+masks+wardrobe
for ob in [pants]:
    solid=ob.modifiers.new('Bound cloth edges','SOLIDIFY');solid.thickness=.0025;solid.offset=-1;solid.use_rim_only=True;apply(ob,solid)

for side in ('l','r'):
    pocket = cargo_pocket(pants,side)
    if pocket is not None:
        all_meshes.append(pocket)

for ob in all_meshes:
    if ob.name in ('Courier_Cargo','Courier_Chinos','Lower_jeans','Lower_joggers','Lower_fitjeans','Lower_leggings','Lower_widejeans','Lower_bikershorts'):
        bend_corrective(ob,'Knee')
    elif ob.name in ('Top_Shirt','Top_Hoodie','Top_Bomber','Top_Jumper','Top_Blazer','Top_Fashion_Racer','Top_Fashion_Pullover'):
        bend_corrective(ob,'Elbow')
    if BODY=='b' and (ob.name in ('Top_Vest','Skin_Arms_Vest','Top_Hoodie','Top_Bomber','Top_Blazer',
                                  'Top_Tee','Top_Shirt','Top_Jumper','Topx_Hoodie_Fold','Top_Polo','Fashion_Torso_Skin',
                                  'Fashion_Crop_Skin')
                      or ob.name.startswith(('Top_Fashion_','Topx_Fashion_')) and 'Skirt' not in ob.name):
        bend_corrective(ob,'Shoulder')

fit_tucked_waists(bpy.data.objects)
for fid in face_meshes:
    fit_headphone_band(bpy.data.objects['Acc_headphones_' + fid], face_meshes[fid][0],
                       {style: bpy.data.objects['Hair_%s_%s' % (style, fid)] for style in HEADPHONE_HAIRS})
if BODY == 'b':
    fit_sandals(bpy.data.objects['Footwear_sandals'], bpy.data.objects['Fashion_Feet'],
                bpy.data.objects['Fashion_Barefoot_Legs'])
    fit_denim_jacket(bpy.data.objects['Top_Fashion_Jacket'])
    fit_camisole_straps(bpy.data.objects['Topx_Fashion_Camisole_Straps'],
                       bpy.data.objects['Top_Fashion_Camisole'], bpy.data.objects['Fashion_Crop_Skin'])
    for cut, hem in SKIRTS.items():
        fit_skirt_correctives(bpy.data.objects[cut], J, hem,
                             [bpy.data.objects[name] for name in ('Fashion_Legs', 'Fashion_Slip')])
    all_meshes.append(female.finish_wardrobe(all_meshes, J, TEX))
    fit_build_b_footwear(all_meshes, J)
groom_hero(all_meshes, TEX, BODY)

# Rig: same rest joints and names as CharacterRig; gameplay animation remains
# the source of truth. Four normalized influences per vertex, no bone heat.
arm=bpy.data.armatures.new('CourierSkeleton');rig=bpy.data.objects.new('CourierRig',arm);bpy.context.collection.objects.link(rig);active(rig);bpy.ops.object.mode_set(mode='EDIT')
for n in names:
    b=arm.edit_bones.new('b_'+n);b.head=J[n]
    children=[c for c,p in P.items() if p==n]
    if n.startswith('hand'):b.tail=J[n]+(J[n]-J[P[n]]).normalized()*.12
    elif n.startswith('foot'):b.tail=J[n]+Vector((0,.16,0))
    elif children:b.tail=J[children[0]]
    else:b.tail=J[n]+Vector((0,0,.15))
    if (b.tail-b.head).length<.02:b.tail=b.head+Vector((0,0,.06))
    if P[n]:b.parent=arm.edit_bones['b_'+P[n]]
bpy.ops.object.mode_set(mode='OBJECT')
for ob in all_meshes:
    active(ob)
    bpy.ops.object.vertex_group_limit_total(limit=4)
    bpy.ops.object.vertex_group_normalize_all(lock_active=False)
    mod=ob.modifiers.new('Gameplay skin','ARMATURE');mod.object=rig;ob.parent=rig
    # UV2.x is cloth freedom, UV2.y carries the outsole or groom density mask.
    density = ob.data.uv_layers.get('GroomDensity')
    groom_motion = ob.data.uv_layers.get('GroomMotion')
    uv2 = density or groom_motion or ob.data.uv_layers.get('ClothFreedom') or ob.data.uv_layers.new(name='ClothFreedom')
    for face in ob.data.polygons:
        for li in face.loop_indices:
            p=ob.data.vertices[ob.data.loops[li].vertex_index].co
            freedom=0
            if (ob in tops or ob in loose_tops or ob.name=='Topx_Bomber_Trims') and abs(p.x)<.24:freedom=max(0,min(.15,(1.12-p.z)*.85))
            sole=1-max(0,min(1,(p.z-.027)/.012)) if ob==shoes else 0
            if density is not None:
                sole = density.data[li].uv.y
                if ob.name.startswith(('Hair_ponytail', 'Hair_bun')):
                    freedom = density.data[li].uv.x
            if groom_motion is not None:
                freedom = groom_motion.data[li].uv.x
                sole = groom_motion.data[li].uv.y
            uv2.data[li].uv=(freedom,sole)
    # Some authored meshes have no UVs (signature/pockets); unwrap those.
    if len(ob.data.uv_layers)==1:
        ob.data.uv_layers.new(name='SurfaceUV');ob.data.uv_layers.active_index=1
        bpy.ops.object.mode_set(mode='EDIT');bpy.ops.mesh.select_all(action='SELECT');bpy.ops.uv.smart_project(island_margin=.03);bpy.ops.object.mode_set(mode='OBJECT')
        # Export ordering must remain SurfaceUV then ClothFreedom.
        cloth=[tuple(d.uv) for d in ob.data.uv_layers[0].data];surface=[tuple(d.uv) for d in ob.data.uv_layers[1].data]
        for i,d in enumerate(ob.data.uv_layers[0].data):d.uv=surface[i]
        for i,d in enumerate(ob.data.uv_layers[1].data):d.uv=cloth[i]
    ob.data.uv_layers[0].name='SurfaceUV';ob.data.uv_layers[1].name='ClothFreedom'
    ob.data.uv_layers.active_index=0

# Bake per-garment ambient occlusion into actual UV textures. The source normal
# map is retained; the procedural microfabric is baked, never evaluated per pixel.
scene=bpy.context.scene;scene.render.engine='CYCLES';scene.cycles.samples=8;scene.cycles.bake_type='AO'
scene.render.bake.margin=8
BAKE=[top_long,pants,shoes,gloves,shirt]+[face_meshes[f][0] for f in face_meshes]+[m_ for m_ in masks if m_.name in ('Mask_courier','Mask_runner','Mask_balaclava','Mask_domino','Mask_respirator')]
for ob in BAKE:
    size=512 if ob in (top_long,pants,shoes,gloves,shirt) else 384
    active(ob);mat=ob.data.materials[0];nodes=mat.node_tree.nodes
    im=bpy.data.images.new(ob.name+'_ao',size,size,alpha=False);im.colorspace_settings.name='Non-Color'
    target=nodes.new('ShaderNodeTexImage');target.image=im;nodes.active=target
    # All other objects are hidden from baking: avoid frozen limb shadows.
    for other in all_meshes:other.hide_render=other!=ob
    bpy.ops.object.bake(type='AO')
    data=np.empty(size*size*4,dtype=np.float32);im.pixels.foreach_get(data);pixels=data.reshape(-1,4)
    # Packed ORM: occlusion red, roughness green, metallic blue.
    rough=float(nodes['Principled BSDF'].inputs['Roughness'].default_value)
    occlusion = pixels[:,0].copy()
    pixels[:,1]=np.clip(rough + (occlusion-.85)*.09,.12,1)
    pixels[:,2]=0
    pixels[:,3]=1
    im.pixels.foreach_set(data)
    im.filepath_raw=str(TEX/(mat.name+'_orm.png'));im.file_format='PNG';im.save()
    separate=nodes.new('ShaderNodeSeparateColor');mat.node_tree.links.new(target.outputs['Color'],separate.inputs[0])
    mat.node_tree.links.new(separate.outputs['Green'],nodes['Principled BSDF'].inputs['Roughness'])
    # glTF's dedicated occlusion socket preserves AO without baking it into albedo.
    group=bpy.data.node_groups.get('glTF Material Output')
    if not group:
        group=bpy.data.node_groups.new('glTF Material Output','ShaderNodeTree');group.interface.new_socket(name='Occlusion',in_out='INPUT',socket_type='NodeSocketFloat')
    g=nodes.new('ShaderNodeGroup');g.node_tree=group;mat.node_tree.links.new(target.outputs['Color'],g.inputs['Occlusion'])
for ob in all_meshes:ob.hide_render=False
if BODY == 'b':
    female.fit_silhouette(all_meshes, rig, anatomy_study)
    female.optimize_portrait(bpy.data.objects['Face_jules'])
    all_meshes.append(finish_casual_fit(bpy, all_meshes, rig))
identity = 'jules' if BODY == 'b' else 'ade'
finish_skin_material(bpy.data.objects['Face_' + identity], identity, TEX)
bake_portrait_hd(bpy.data.objects['Face_' + identity], identity, TEX)
finish_fixed_hero(bpy, rig, all_meshes, identity)
finish_realism(rig, all_meshes, identity, TEX)
# Retain editable meshes, original garment UVs, weights and material nodes.
for im in bpy.data.images:
    if im.source=='FILE':im.pack()
export_playable(bpy, rig, all_meshes, OUT / ('character%s.glb' % SUF), BODY)
# Open the authoring file on a single complete outfit. Variant objects stay
# in the file and retain their editable geometry, weights and material nodes.
preview_fid, preview_hair = ('ade', 'crop') if BODY == 'a' else ('jules', 'bun')
show = {'Face_' + preview_fid, 'Hair_%s_%s' % (preview_hair, preview_fid),
        'Groom_%s_%s' % (preview_hair, preview_fid), 'Skin_Hands', 'Skin_Arms_Polo',
        'Top_Polo', 'Topx_Polo_Trim', 'Courier_Cargo', 'Cargo_gusset_l',
        'Cargo_gusset_r', 'Ankle_Liner', 'Courier_Trainers', 'Courier_Soles',
        'Courier_TrainerTongues', 'Courier_TrainerLaces'}
if BODY == 'b':
    show = {'Face_jules', 'Hair_bun_jules', 'Groom_bun_jules', 'Skin_Hands',
            'Fashion_Legs', 'Fashion_Slip', 'Top_Fashion_Moto',
            'Topx_Fashion_Moto_Collar', 'Topx_Fashion_Moto_Zip', 'Lower_midiskirt',
            'Footwear_streettrainers'}
bpy.ops.object.select_all(action='DESELECT')
for ob in all_meshes:
    ob.hide_set(ob.name not in show)
for screen in bpy.data.screens:
    for area in screen.areas:
        if area.type == 'VIEW_3D':
            view = area.spaces.active.region_3d
            view.view_location = (0, 0, .94)
            view.view_distance = 3.3
            view.view_rotation = Vector((1, 3, .35)).to_track_quat('Z', 'Y')
bpy.ops.wm.save_as_mainfile(filepath=str(BLEND), compress=True)
triangles=sum(sum(len(p.vertices)-2 for p in ob.data.polygons) for ob in all_meshes)
(AUTHORING/('build_report%s.json'%SUF)).write_text(json.dumps({'triangles':triangles,'meshes':{o.name:len(o.data.vertices) for o in all_meshes},'bones':len(names),'max_influences':4},indent=2))
# Shared garment-kit textures the game loads directly (not via the GLB).
import shutil
pore_normal()
for n in ['fabric_weave_normal.png','skin_pore_normal.png']:
    shutil.copy(TEX/n,OUT/n)
print('COURIER EXPORTED',triangles,'triangles',flush=True)
