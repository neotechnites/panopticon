"""Marble tiles through the forest soft chain (texture_log 18-24) at the forest leaf/bark detail: usage marble_forest_filter.py <out dir>."""
import sys,os,numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter,uniform_filter1d,binary_dilation
sys.path.insert(0,os.path.dirname(__file__)); from texture_detail import corr_len,lum
SRC=os.path.expanduser('~/Desktop/panopticon-renders/_work/marble_tex_orig'); DST=sys.argv[1]
NAMES=['brick','column','floor','pit','stone','tower','tower_column','tower_floor','tower_stone']
FEAT=4.0      # px: forest leaf 5.5 / bark 3.0 correlation length, both at ~0.05 m a texel like marble
REL_STD=0.07  # forest leaf 0.073, bark 0.106, path 0.045: stone variation after the chain
GROUT=0.25    # grout ends this much under the stone's tone (was near black)
DEV=0.62*0.7  # forest chain: levels 0.38/1.0 then contrast -30%, about the tile's own mean
NCOL=32
def lin(s): return np.where(s<=0.04045,s/12.92,((s+0.055)/1.055)**2.4)
def srgb(l): l=np.clip(l,0,1); return np.where(l<=0.0031308,l*12.92,1.055*l**(1/2.4)-0.055)
def blur(x,s): return gaussian_filter(x,s,mode='wrap') if s>0 else x
def B(a,s): return np.stack([blur(a[...,c],s) for c in range(3)],-1)
def dips(m,t=1.5):
    return m<np.median(m)-t*1.4826*np.median(np.abs(m-np.median(m)))
def courses(L):
    """Brick layout: course rows whose mean dips, then head joints whose column mean dips within each course."""
    out=np.zeros(L.shape,bool); r=dips(L.mean(1),2.5)
    if r.sum()==0 or r.sum()>L.shape[0]*0.25: return out
    out[r]=True; idx=np.r_[np.where(r)[0],np.where(r)[0][0]+L.shape[0]]
    for a,b in zip(idx[:-1],idx[1:]):
        if b-a<4: continue
        rows=np.arange(a+1,b)%L.shape[0]; out[np.ix_(rows,np.where(dips(L[rows].mean(0),2.5))[0])]=True
    return out
outs={};info={}
for n in NAMES:
    a=np.asarray(Image.open(f'{SRC}/marble_{n}_albedo.png').convert('RGB')).astype(float)/255
    m0=lin(a).reshape(-1,3).mean(0); L=lum(a); sd=L.std()
    # grout: long dark runs (row/column means over 9 px) or dark blobs >=2 px; speckle averages out
    h=uniform_filter1d(L,9,axis=1,mode='wrap'); v=uniform_filter1d(L,9,axis=0,mode='wrap'); g=blur(L,1.0)
    base=blur(L,6.0)
    mask=(h<base-0.9*sd)|(v<base-0.9*sd)|(g<base-1.6*sd)
    mask&=L<base                                     # only the dark pixels of the run
    mask|=courses(L)
    # stone body: grout filled with the tone around it, speckle blurred to the forest's feature size
    w=(~mask).astype(float); fill=B(a*w[...,None],3)/np.maximum(blur(w,3),1e-6)[...,None]
    body0=np.where(mask[...,None],fill,a)
    lo,hi=0.0,6.0
    for _ in range(16):
        s=(lo+hi)/2
        if corr_len(lum(B(body0,s)))<FEAT: lo=s
        else: hi=s
    body=B(body0,s); mu=body.reshape(-1,3).mean(0); bl=lum(body)
    k=(REL_STD*lum(mu)/DEV)/max(bl.std(),1e-6)
    pre=mu+(body-mu)*k
    pre=np.where(mask[...,None],pre*(1-GROUT/DEV),pre)   # grout pre-chain depth -> GROUT after it
    c=mu+(pre-mu)*DEV                                     # the forest chain
    c=B(c,1.0)                                            # its 1 px blur
    l=lin(np.clip(c,0,1)); l*=m0/l.reshape(-1,3).mean(0)  # v4's linear mean kept: lighting untouched
    outs[n]=srgb(l); info[n]=(s,mask.mean())
# shared 32-colour palette, every tile weighted alike
samp=np.concatenate([np.resize((outs[n]*255+0.5).astype(np.uint8).reshape(-1,3),(16384,3)) for n in NAMES])[:,None,:]
pal=Image.fromarray(samp).quantize(NCOL,method=Image.Quantize.MEDIANCUT,dither=Image.Dither.NONE)
for n in NAMES:
    o=lin(np.asarray(Image.open(f'{SRC}/marble_{n}_albedo.png').convert('RGB'))/255).reshape(-1,3).mean(0)
    gain=np.ones(3)
    for _ in range(8):   # palette snapping drifts the mean: nudge the input until v4's mean comes back
        x=srgb(lin(outs[n])*gain)
        im=Image.fromarray((x*255+0.5).astype(np.uint8)).quantize(palette=pal,dither=Image.Dither.NONE).convert('RGB')
        q=lin(np.asarray(im)/255).reshape(-1,3).mean(0); gain*=o/q
    im.save(f'{DST}/marble_{n}_albedo.png')
    print(f'{n:13s} blur={info[n][0]:.2f} grout={info[n][1]*100:4.1f}% drift={(q/o-1).round(3)}')
