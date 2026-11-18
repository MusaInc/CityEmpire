# Top-down map of the coasts (coasts.json in the cwd): BOX=x0,z0,x1,z1 MPP=m OUT=png
# python3 plan_map.py [views.txt] (draws the aerial views as red lines).
import json,math,numpy as np,subprocess,sys
d=json.load(open('coasts.json'))
import os; x0,z0,x1,z1=[float(v) for v in os.environ.get("BOX","-1350,-800,1300,2300").split(",")]; mpp=float(os.environ.get("MPP","2"))
W=int((x1-x0)/mpp);H=int((z1-z0)/mpp)
img=np.zeros((H,W,3),np.uint8); img[:]=(30,55,85)
def fill(poly,col):
    from matplotlib.path import Path
def raster(poly,col):
    xs=np.arange(W)*mpp+x0; zs=np.arange(H)*mpp+z0
    X,Z=np.meshgrid(xs,zs)
    inside=np.zeros(X.shape,bool); n=len(poly)
    for i in range(n):
        xa,za=poly[i][:2]; xb,zb=poly[(i+1)%n][:2]
        cond=((za>Z)!=(zb>Z))
        with np.errstate(divide='ignore',invalid='ignore'):
            xi=(xb-xa)*(Z-za)/(zb-za+1e-12)+xa
        inside ^= cond & (X<xi)
    img[inside]=col
for k in ['commercial','westbank','skyport']: raster(d[k],(90,110,80))
for f in d['landforms']: raster(f['poly'],(80,130,70))
cols={0:(200,200,200),1:(240,220,150),2:(120,110,100),3:(255,0,255)}
def line(a,b,c):
    L=max(1,int(math.dist(a,b)/mpp))
    for t in range(L+1):
        x=a[0]+(b[0]-a[0])*t/L; z=a[1]+(b[1]-a[1])*t/L
        i=int((x-x0)/mpp); j=int((z-z0)/mpp)
        if 0<=i<W and 0<=j<H: img[max(0,j-1):j+1,max(0,i-1):i+1]=c
for k in ['commercial','westbank']:
    p=d[k]
    for i in range(len(p)): line(p[i],p[(i+1)%len(p)],(255,255,255))
p=d['skyport']
for i in range(len(p)): line(p[i],p[(i+1)%len(p)],cols[p[i][2]])
for f in d['landforms']:
    p=f['poly']
    for i in range(len(p)): line(p[i],p[(i+1)%len(p)],cols[p[i][2]])
if len(sys.argv)>1:
    for ln in open(sys.argv[1]):
        nm,at,cam=ln.strip().split(':'); c=[float(v) for v in cam.split(',')]
        if nm.endswith('_air'):
            line((c[0],c[2]),(c[3],c[5]),(255,80,80))
open('plan.ppm','wb').write(b'P6 %d %d 255\n'%(W,H)+img.tobytes())
subprocess.run(['convert','plan.ppm','-resize','50%',os.environ.get('OUT','plan.png')])
