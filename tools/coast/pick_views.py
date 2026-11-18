# Picks coast audit views from coasts.json (tools/coast/coast_dump.gd): per island,
# every ~350 m of coast an aerial, a sea-level and a promenade view. Prints views.
import json,math,sys
d=json.load(open('coasts.json'))
def inside(p,poly):
    x,z=p;c=False;n=len(poly)
    for i in range(n):
        x1,z1=poly[i][:2];x2,z2=poly[(i+1)%n][:2]
        if (z1>z)!=(z2>z) and x<(x2-x1)*(z-z1)/(z2-z1)+x1: c=not c
    return c
def walk(poly,step,off=0):
    n=len(poly);L=[0]
    for i in range(n): L.append(L[-1]+math.dist(poly[i][:2],poly[(i+1)%n][:2]))
    out=[];s=off
    while s<L[-1]:
        i=max(j for j in range(n) if L[j]<=s); t=(s-L[i])/max(L[i+1]-L[i],1e-6)
        a=poly[i][:2];b=poly[(i+1)%n][:2]
        p=(a[0]+(b[0]-a[0])*t,a[1]+(b[1]-a[1])*t)
        tx,tz=(b[0]-a[0]),(b[1]-a[1]);l=math.hypot(tx,tz);tx/=l;tz/=l
        nx,nz=tz,-tx
        if inside((p[0]+nx*2,p[1]+nz*2),poly): nx,nz=-nx,-nz
        h=0
        if 'h' in d.get('_h',{}): pass
        out.append((p,(nx,nz),(tx,tz),i))
        s+=step
    return out
views=[]
allpolys=[d['commercial'],d['westbank'],d['skyport']]
def onland(p): return any(inside(p,q) for q in allpolys) or any(inside(p,f['poly']) for f in d['landforms'])
for key,tag,step,off in [('commercial','c',380,60),('westbank','w',330,40),('skyport','s',400,80)]:
    poly=d[key]
    for k,(p,n,t,i) in enumerate(walk(poly,step,off)):
        hh=d.get(key+'_h')
        h=hh[i] if hh else 1.0
        # aerial oblique: 150 m out to sea, 75 m up (+terrain), looking at the shore
        D=150
        cam=(p[0]+n[0]*D+t[0]*40,75+h,p[1]+n[1]*D+t[1]*40)
        look=(p[0]-n[0]*25,max(h*0.6,0),p[1]-n[1]*25)
        at=(p[0]-n[0]*30,p[1]-n[1]*30)
        views.append(f"{tag}{k:02d}_air:{at[0]:.0f},{at[1]:.0f}:"+",".join(f"{v:.1f}" for v in cam+look))
        # boat level: 45 m out, 2.5 m above the sea, looking along the shore
        cam=(p[0]+n[0]*45-t[0]*40,1.5,p[1]+n[1]*45-t[1]*40)
        look=(p[0]+t[0]*50,1.0+h*0.4,p[1]+t[1]*50)
        views.append(f"{tag}{k:02d}_sea:{at[0]:.0f},{at[1]:.0f}:"+",".join(f"{v:.1f}" for v in cam+look))
        cam=(p[0]-n[0]*5,h+2.0,p[1]-n[1]*5)
        look=(p[0]+t[0]*40+n[0]*14,h-1.5,p[1]+t[1]*40+n[1]*14)
        views.append(f"{tag}{k:02d}_walk:{p[0]-n[0]*30-t[0]*20:.0f},{p[1]-n[1]*30-t[1]*20:.0f}:"+",".join(f"{v:.1f}" for v in cam+look))
print(len(views),file=sys.stderr)
print("\n".join(views))
