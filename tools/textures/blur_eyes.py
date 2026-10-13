#!/usr/bin/env python3
"""Softens the two dark eye patches of prisoner2_albedo.png: gaussian blur feathered into the skin, nothing else touched.
Patches = dark pixels in the head island's eye rows (centres x +-0.080, z 1.622 -> px ~250,80 and ~270,80)."""
import os, sys
import numpy as np
from PIL import Image
from scipy import ndimage as ndi

ALBEDO = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "characters/textures/prisoner2_albedo.png")
BOX = (236, 70, 290, 92)   # x0, y0, x1, y1 around the eyes, clear of the nose and mouth patches
SIGMA, GROW, FEATHER = 2.2, 3, 1.5


def blur_eyes(img):
    a = img.astype(float)
    op = (a[..., 3] > 0).astype(float)
    x0, y0, x1, y1 = BOX
    dark = np.zeros(op.shape, bool)
    dark[y0:y1, x0:x1] = (a[y0:y1, x0:x1, 0] < 160) & (op[y0:y1, x0:x1] > 0)
    w = ndi.gaussian_filter(ndi.binary_dilation(dark, iterations=GROW).astype(float), FEATHER) * op
    norm = ndi.gaussian_filter(op, SIGMA)
    out = a.copy()
    for c in range(3):
        out[..., c] = ndi.gaussian_filter(a[..., c] * op, SIGMA) / np.maximum(norm, 1e-6)
    res = a.copy()
    res[..., :3] = a[..., :3] * (1 - w[..., None]) + out[..., :3] * w[..., None]
    return np.rint(res).astype(np.uint8)


if __name__ == "__main__":
    p = sys.argv[1] if len(sys.argv) > 1 else ALBEDO
    Image.fromarray(blur_eyes(np.array(Image.open(p).convert("RGBA")))).save(p)
