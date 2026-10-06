#!/usr/bin/env python3
"""Forest sun dapple: the leaf-shadow noise (forest_crown_shadow.gdshader) as a soft, tiling light mask.

1 = full sun, 0 = leaf shade. Tiles every PERIOD metres; blurred so each spot fades over ~0.4 m.
    python3 tools/textures/forest_dapple.py   -> maps/forest/textures/forest_dapple.png
"""
import numpy as np
from PIL import Image

PERIOD = 27.0      # metres per tile: whole lattices for both octaves (1.0 m and 0.45 m cells)
SIZE = 512         # pixels per tile, ~5 cm
GAP = 0.32         # hole threshold: more holes than the shader's 0.3, the lit area its stacked casters let through
SIGMA = 0.156       # metres of Gaussian blur: the soft edge
OUT = "maps/forest/textures/forest_dapple.png"

rng = np.random.default_rng(20261006)


def vnoise(cells: int) -> np.ndarray:
    lat = rng.random((cells, cells))
    t = np.arange(SIZE) * cells / SIZE
    i = np.floor(t).astype(int)
    f = t - i
    u = f * f * (3 - 2 * f)
    i0, i1 = i % cells, (i + 1) % cells
    a = lat[np.ix_(i0, i0)]; b = lat[np.ix_(i0, i1)]
    c = lat[np.ix_(i1, i0)]; d = lat[np.ix_(i1, i1)]
    uy, ux = u[:, None], u[None, :]
    return (a * (1 - ux) + b * ux) * (1 - uy) + (c * (1 - ux) + d * ux) * uy


n = 0.65 * vnoise(int(PERIOD / 1.0)) + 0.35 * vnoise(int(round(PERIOD / 0.45)))
lit = (n < GAP).astype(np.float64)
# Periodic Gaussian blur through the FFT, so the tile stays seamless.
k = np.fft.fftfreq(SIZE, d=PERIOD / SIZE)
g = np.exp(-2 * (np.pi * SIGMA) ** 2 * (k[:, None] ** 2 + k[None, :] ** 2))
soft = np.real(np.fft.ifft2(np.fft.fft2(lit) * g)).clip(0, 1)
Image.fromarray((soft * 255 + 0.5).astype(np.uint8), "L").save(OUT)
print(f"{OUT}: lit fraction {soft.mean():.3f}")
