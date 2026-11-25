# Aspens textures: the pipeline

Placeholders, drawn by `tools/textures/aspens_placeholders.py` (no photo, no image model); Ryan replaces them.
`raw/` is the drawn input and is written only by that script; the live PNGs beside this file are the output;
`aspens.ase` is packed from the live PNGs by `tools/textures/make_sheet.lua`, one slice per tile.

    python3 tools/textures/aspens_placeholders.py

Per tile: raw -> 1 px gaussian, wrapped -> a 16-colour median cut whose darkest entry is the tile's own
darkest pixel (the knots stay black). That is `n64_chain.py`'s soft steps; its value stretch and contrast
cut are not run, because the colours are measured from Ryan's references (`docs/maps/aspens.md`).

| tile | size | drawn as | worn by |
|---|---|---|---|
| aspens_grass_albedo | 256 x 256 | olive grass in three tones, upright blades, dry tufts | the ground (vertex colour turns patches green) |
| aspens_bark_albedo | 32 x 256 | white bark in three tones, thin dark scars, black knots under a brow | trunks, limbs (vertex colour, near black), the stump's side; one turn of a trunk is the tile's width |
| aspens_leaf_albedo | 256 x 256 | round yellow leaves in four tones | every leaf mass |
| aspens_wood_albedo | 128 x 128 | pale growth rings round a pith, radial checks | the stump's cut face |

All at 0.05 m per texel; filtered bilinear with mips by `tools/import/mipmap_textures.gd`.
