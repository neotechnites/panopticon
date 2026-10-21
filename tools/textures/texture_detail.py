"""Texture detail metrics: colours, mean, std/mean, correlation length (px), 1 px gradient share."""
import sys,numpy as np
from PIL import Image
def lum(a): return (0.2126*a[...,0]+0.7152*a[...,1]+0.0722*a[...,2])
def corr_len(L):
    L=L-L.mean(); F=np.fft.fft2(L); ac=np.real(np.fft.ifft2(F*np.conj(F))); ac/=ac[0,0]
    # radial mean
    h,w=L.shape; y,x=np.indices((h,w)); y=np.minimum(y,h-y); x=np.minimum(x,w-x); r=np.hypot(x,y).astype(int)
    prof=np.bincount(r.ravel(),ac.ravel())/np.bincount(r.ravel())
    for i,v in enumerate(prof):
        if v<0.5: return i-1+(prof[i-1]-0.5)/(prof[i-1]-v)
    return float('nan')
def hf(L):  # fraction of variance in 1px-neighbour differences
    d=np.abs(np.diff(L,axis=1)).mean()+np.abs(np.diff(L,axis=0)).mean()
    return d/2/(L.std()+1e-9)
if __name__=="__main__":
 for f in sys.argv[1:]:
     a=np.asarray(Image.open(f).convert('RGB')).astype(float)
     L=lum(a); n=len(np.unique(a.reshape(-1,3),axis=0))
     print(f"{f.split('/')[-1]:34s} {a.shape[1]}x{a.shape[0]} cols={n:3d} mean={L.mean():6.1f} std/mean={L.std()/L.mean():.3f} p2={np.percentile(L,2):5.1f} p50={np.median(L):5.1f} corrlen={corr_len(L):5.2f}px gradHF={hf(L):.2f}")
 