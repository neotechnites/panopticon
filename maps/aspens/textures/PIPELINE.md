# Aspens textures: the pipeline

Placeholders, drawn by `tools/textures/aspens_placeholders.py` (no photo, no image model); Ryan replaces them.
`raw/` is the drawn input and is written only by that script; the live PNGs beside this file are the output;
`aspens.ase` is packed from the live PNGs by `tools/textures/make_sheet.lua`, one slice per tile.

    python3 tools/textures/aspens_placeholders.py

Per tile: raw -> 1 px gaussian, wrapped -> a 16-colour median cut whose darkest entry is the tile's own
darkest pixel (the knots stay black). A tile's alpha is kept exactly as drawn. That is `n64_chain.py`'s soft steps; its value stretch and contrast
cut are not run, because the colours are measured from Ryan's references (`docs/maps/aspens.md`).

| tile | size | drawn as | worn by |
|---|---|---|---|
| aspens_grass_albedo | 256 x 256 | olive grass in three tones, upright blades, dry tufts | the ground (vertex colour turns patches green) |
| aspens_bark_albedo | 32 x 256 | white bark banded across in three tones, thin drooping scars, flat black eyes under a brow | trunks, limbs (vertex colour, near black), the stump's side; whole turns of the tile round a trunk |
| aspens_leaf_albedo | 128 x 128, alpha | four clusters of small round leaves in the photo's five yellows, cut away between them | every leaf card |
| aspens_tuft_albedo | 128 x 128, alpha | four dry grass tufts, blades fanning from the foot | every tuft card (vertex colour turns some green) |
| aspens_wood_albedo | 128 x 128 | pale growth rings round a pith, radial checks | the stump's cut face |

All at 0.05 m per texel; filtered bilinear with mips by `tools/import/mipmap_textures.gd`.
