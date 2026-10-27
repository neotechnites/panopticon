# Marble textures: the pipeline

The stone tiles are built ONCE, from `raw/`, by the chain forest and hell got. `raw/` is the
input and is never written again; the live PNGs beside this file are the output; `marble.ase`
is packed from the live PNGs by `tools/textures/make_sheet.lua`; `marble_hand.ase` is Ryan's
hand sheet, untouched.

## Source (raw/)

Every `*_albedo.png` as of commit `a46ab157^` (6ca9f2de, 2026-10-20): the per-tile matte
RECOLOUR state Ryan approved ("the colours are not the problem"). Copied with
`git show a46ab157^:maps/marble/textures/<name>.png`. `raw/.gdignore` keeps Godot off it.

## The chain (tools/textures/n64_chain.py), run 2026-10-24

    python tools/textures/n64_chain.py --value-mul 0.6 maps/marble/textures \
        marble_brick_albedo marble_stone_albedo marble_floor_albedo marble_pit_albedo \
        marble_column_albedo marble_triangle_albedo marble_tower_albedo \
        marble_tower_column_albedo marble_tower_floor_albedo marble_tower_stone_albedo

Per tile, in this order (forest texture_log 18-24; hell 100-102 for the optional extras):

1. HSV value stretched from the tile's own min..max to 0.38..1.0
2. contrast -30% about 0.5 (value only; hue and saturation kept)
3. `--value-mul 0.6` (hell's number, row 101/102); `--sat pull,mul` (hell 0.15,1.35) OFF
4. 1 px gaussian blur, wrapped (the tiles repeat)
5. one 32-colour median-cut palette shared across the whole set (each tile weighs alike), no dither
6. alpha from raw/ carried through; RGBA saved

No grout detection, no grout fill or re-sink, no course detection, no detail rescale, no
mean-restoring loop: the chain is the forest chain and nothing else.

## Per tile

| tile | raw (recolour a46ab157^) luma mean / std | out luma mean / std / p5-p95 |
|---|---|---|
| marble_brick_albedo 256x256 | 29.6 / 7.1 | 92.4 / 5.7 / 84-101 |
| marble_stone_albedo 64x64 | 30.3 / 1.4 | 100.9 / 6.1 / 91-111 |
| marble_floor_albedo 64x64 | 33.2 / 11.5 | 108.1 / 13.2 / 81-125 |
| marble_pit_albedo 256x256 | 27.7 / 6.8 | 96.5 / 6.9 / 84-107 |
| marble_column_albedo 128x128 | 30.1 / 5.0 | 106.6 / 10.6 / 81-116 |
| marble_triangle_albedo 128x20 | 19.2 / 15.4 | 82.6 / 27.1 / 56-125 |
| marble_tower_albedo 256x256 | 59.8 / 12.0 | 92.7 / 5.8 / 84-101 |
| marble_tower_column_albedo 128x128 | 60.5 / 8.6 | 105.8 / 10.4 / 81-116 |
| marble_tower_floor_albedo 64x64 | 65.0 / 19.6 | 107.3 / 12.8 / 81-125 |
| marble_tower_stone_albedo 64x64 | 67.9 / 2.7 | 100.0 / 6.3 / 88-109 |

For reference the live forest tiles sit at luma 115-154 (bark 144, path 132, rock 154) and
hell's rock at 31 (x its red tint 25): marble's stone lands between them.

Untouched: `marble_portal_swirl_albedo.png` (no map's chain filters its swirl),
`marble_albedo.png` and `marble_dark_albedo.png` (orphan drawings no model wears; = raw/).

## Why value-mul 0.6

Without it (value-mul 1.0) the tiles come out at luma 155-181, above forest's band, and on screen
under the hell lighting system (key 0.55, ambient 0.45) the map averaged luma 79 / p95 142 against
forest 26 / 72 and hell 20 / 38: too bright. Hell met the same problem and answered it with value
x0.6 (texture_log 101); the same number puts marble's frames at luma ~48 / p95 ~88, V mean 52
between forest's 29 and hell's 90. Proof sheets: C:\Users\ddd\Desktop\panopticon-renders\_work\proofs\marble\process.

## 2026-10-26: Ryan's new brick

Ryan repainted the brick (saved in the old 650x780 sheet layout at (300,300) 256x256; that file is kept as
`raw/marble_ryan_sheet_2026-10-26.ase`). The tile is the new `raw/marble_brick_albedo.png`; the previous raw
(the recolour) is `raw/archive/marble_brick_albedo_recolour_2026-10-24.png`. The chain was re-run on the whole
set with the same arguments (the 32-colour palette is shared, so every live tile re-quantised), and
`marble.ase` repacked from the live PNGs.
