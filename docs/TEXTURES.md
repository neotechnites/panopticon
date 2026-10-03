# Textures

Every texture is drawn by hand. Each home keeps its own in `<home>/textures/`, and nothing else lives there:
the Aseprite sheet (`.ase`), the PNGs the game loads, and Godot's `.import` beside each PNG.

## Layout of a home

    maps/<map>/            the map scene and its rules (.tscn, .tres)
    maps/<map>/textures/   the sheet, its PNGs, their .import
    maps/<map>/models/     .glb (built by tools/modelling) and .glb.import
    maps/<map>/materials/  shaders and material .tres
    maps/<map>/props/      prop scenes placed on the map

`characters/`, `weapons/`, `hub/`, `props/` and `tower/` follow the same folders. The tower has no textures of
its own: it wears hell's. Map notes are in `docs/maps/`.

## How to edit

1. Open the home's sheet in Aseprite (`hell.ase`, `forest.ase`, ...). Each named slice is one texture.
2. Draw inside the slice. Do not move, resize or rename a slice: its name is the PNG's name.
3. Save. `tools/pc_sync.sh` pulls the sheet back from the PC, runs `tools/textures/export_sheets.sh`
   (every slice to `<slice>.png` beside the sheet) and commits the PNGs.
4. Three textures are plain PNGs with no sheet; edit the PNG itself: `lava_albedo.png`,
   `map_base_lava_emissive.png`, `forest_mist_albedo.png`.

A new texture is a new slice in the home's sheet. `python3 tools/textures/audit.py` rewrites the tables
below and fails when a model uses a texture that is in no sheet.

## Textures from photos

The forest and the prisoner each have an alternate sheet built from Ryan's photos (`forest_photo.ase`,
`prisoner_photo.ase`; same slices as the live sheet). The tool only crops, scales, tones and quantises a photo.

1. Drop photos in `~/Desktop/panopticon-renders/textures/photos/<forest|prisoner>/`, named after the slice
   (forest: `bark grass path sun portal_swirl rock lamp_emissive`, also `leaf` = sun, `dirt` = path;
   prisoner: `prisoner2` or `body`, the whole body sheet), e.g. `grass.jpg`.
2. `python3 tools/textures/photo_to_texture.py batch forest` rebuilds `forest_photo.ase`: slices without a
   photo are copied from the hand-drawn sheet. 8x previews land in `photos/<home>/preview/`.
3. `tools/textures/use_sheet.sh forest photo` makes the photo sheet live (the hand sheet is kept as
   `forest_hand.ase`) and exports; `use_sheet.sh forest hand` swaps back. Lossless both ways.
4. Commit the sheets and PNGs, then `bash tools/pc_sync.sh`.

Example: `leaf.jpg dirt.jpg bark.jpg grass.jpg` in `photos/forest/` → `batch forest` → check
`photos/forest/preview/*_8x.png` → `use_sheet.sh forest photo` → commit → `pc_sync.sh`.

One photo: `photo_to_texture.py one <photo> --home forest` (`--size 32|64|128|256`, `--crop x y w h`,
`--tile blend|mirror|off`, `--palette <.pal|.png|.ase>` or `--colors N`, `--dither`, `--levels`, `--contrast`
(default 0.7), `--gamma`, `--rotate`). Defaults: forest 128 px tiled, prisoner 64 px; a texture smaller than its
slice is placed nearest-upscaled (chunkier, same UVs and density), each locked to `tools/textures/palettes/<home>.pal`
(`photo_to_texture.py palette <home>` rewrites it from the live sheet). Runs on the Mac (the PC has no Python).

## The textures

### Hell: `maps/bentham_ring/textures/` (`hell.ase`)

| Texture | Looks like | Worn by |
|---|---|---|
| hell_rock_albedo | near-black rock, dull red blocks and specks | every rock surface of the map, its props, the tower, the hub's hell wedge |
| crack_glow_albedo | bright red-orange ember grain, a 32 px tile | the glowing cell screens and the lava cracks in the floor |
| hell_props_albedo | orange spiral on black | the portal's swirl |
| lava_albedo (PNG) | orange lava with dark red veins | the lava sea and rivers, the hub's lava |
| map_base_lava_emissive (PNG) | the same lava, veins black | the lava's glow |

### Forest: `maps/forest/textures/` (`forest.ase`)

| Texture | Looks like | Worn by |
|---|---|---|
| forest_grass_albedo | mottled green grass | lane grass, verge, edge |
| forest_path_albedo | brown earth with moss flecks | the path, the pit's earth bank |
| forest_sun_albedo | bright blocky leaves | sunlit leaves, and (darkened) leaf walls, shade, ferns |
| forest_bark_albedo | dark vertical bark | trunks, roots, bars, thorns |
| forest_rock_albedo | grey cracked granite | rocks, and (near black) the cells and lamp housings |
| forest_lamp_emissive | warm specks on brown | the cell lamps' glow |
| forest_portal_swirl_albedo | green spiral on black | the portal's swirl |
| forest_mist_albedo (PNG) | soft grey cloud noise | the pit mist shader |

### Marble: `maps/marble/textures/` (`marble.ase`)

| Texture | Looks like | Worn by |
|---|---|---|
| marble_albedo | olive stone atlas: bands, friezes, medallion, column flutes, portal swirl | bands, columns, dome, floor, spikes, lamp glow, portal |
| marble_stone_albedo | olive ashlar courses | walls, plinths, tower shaft and dome, props |
| marble_dark_albedo | near-black stone with an iron column | cell interiors, iron bars |
| marble_field_albedo | olive camouflage flagstones | the field floor |

### Hub: `hub/textures/` (`hub.ase`)

| Texture | Looks like | Worn by |
|---|---|---|
| hub_stone_albedo | four grey stone quarters, light to near black | the hub's own stone |

The hub's three wedges wear the hell, marble and forest textures from those maps' folders.

### Characters: `characters/textures/` (`prisoner.ase`)

Paint the four 64 px regions of `prisoner.ase`: trousers (top left), shoes (top right), skin (bottom left), shirt (bottom right).
Export (`tools/textures/export_sheets.sh`) composes them onto the body: `compose_prisoner.py` tiles each region 1:1
across its UV islands (`prisoner_islands.json`) into `prisoner2_albedo.png`; the raw sheet is `prisoner_sheet.png`.

| Texture | Looks like | Worn by |
|---|---|---|
| prisoner2_albedo | 512 px sheet (2x upscale of the 256; four 256 px regions), four flat swatches: brown, grey, pale skin, mint | the prisoner and guard body; the shirt is coloured per team in the match |

### Weapons: `weapons/textures/` (`rifle.ase`)

| Texture | Looks like | Worn by |
|---|---|---|
| rifle_hell_albedo | wood grain, brass, dark metal, an eye and "No 7" plate | the rifle |

### Props: `props/textures/` (`props.ase`)

| Texture | Looks like | Worn by |
|---|---|---|
| speed_orb_albedo | orange ember with black blots | the speed orb, and its glow |

<!-- generated by tools/textures/audit.py: do not edit below -->

## Recolours: one texture, a colour multiplier in the material

The game multiplies the texture by this colour (linear RGB). The recoloured look is not a file.

| Texture | Multiplier | Materials |
|---|---|---|
| maps/bentham_ring/textures/hell_rock_albedo.png | (0.036, 0.0296, 0.0361) | map_base_cover_s2.glb: HellEmber; map_base_cover_s4.glb: HellEmber; map_base_s1.glb: HellEmber; map_base_s2.glb: HellEmber; map_base_s3.glb: HellEmber; map_base_s4.glb: HellEmber; map_base_s5.glb: HellEmber |
| maps/bentham_ring/textures/hell_rock_albedo.png | (0.116, 0.0847, 0.13) | map_base_cover_s2.glb: HellShade; map_base_cover_s4.glb: HellShade; map_base_gate.glb: HellShade.001; map_base_lip013.glb: HellShade; map_base_lip066.glb: HellShade; map_base_lip139.glb: HellShade; map_base_lip204.glb: HellShade; map_base_lip286.glb: HellShade; map_base_s1.glb: HellShade; map_base_s2.glb: HellShade; map_base_s3.glb: HellShade; map_base_s4.glb: HellShade; map_base_s5.glb: HellShade; rock_bars.glb: HellShade |
| maps/bentham_ring/textures/hell_rock_albedo.png | (1, 0.471, 0.42) | map_base_gate.glb: HellRock.001; map_base_lip013.glb: HellRock; map_base_lip066.glb: HellRock; map_base_lip139.glb: HellRock; map_base_lip204.glb: HellRock; map_base_lip286.glb: HellRock; map_base_s1.glb: HellRock; map_base_s2.glb: HellRock; map_base_s3.glb: HellRock; map_base_s4.glb: HellRock; map_base_s5.glb: HellRock; rock_bars.glb: HellRock |
| maps/forest/textures/forest_bark_albedo.png | (0.974, 0.978, 0.978) | forest_bush_low.glb: ForestBush_bark; forest_bush_tall.glb: ForestBush_bark; forest_canopy.glb: ForestCanopy_bark; forest_portal.glb: ForestPortal_bark; forest_tree.glb: ForestTree_bark; forest_tree_prop_a.glb: ForestTreeProp_bark; forest_tree_prop_b.glb: ForestTreeProp_bark; forest_tree_prop_c.glb: ForestTreeProp_bark |
| maps/forest/textures/forest_bark_albedo.png | (1, 0.889, 0.801) | forest.glb: forest_root; forest_bars.glb: forest_root |
| maps/forest/textures/forest_bark_albedo.png | (1, 0.9, 0.81) | forest_thorns.glb: ForestThorns_root; forest_tree.glb: ForestTree_root |
| maps/forest/textures/forest_grass_albedo.png | (0.352, 0.402, 0.841) | forest.glb: forest_edge |
| maps/forest/textures/forest_grass_albedo.png | (1, 0.846, 1) | forest.glb: forest_verge |
| maps/forest/textures/forest_path_albedo.png | (0.262, 0.211, 0.475) | forest.glb: forest_earth |
| maps/forest/textures/forest_rock_albedo.png | (0.0144, 0.0135, 0.015) | hub_base.glb: ForestDark; forest.glb: forest_cell; forest.glb: forest_lamp |
| maps/forest/textures/forest_rock_albedo.png | (0.191, 0.359, 0.135) | forest_rock_boulder.glb: ForestGranite_moss; forest_rock_outcrop.glb: ForestGranite_moss; forest_rock_slab.glb: ForestGranite_moss |
| maps/forest/textures/forest_rock_albedo.png | (0.416, 0.44, 0.501) | forest_rock_boulder.glb: ForestGranite_shade; forest_rock_outcrop.glb: ForestGranite_shade; forest_rock_slab.glb: ForestGranite_shade |
| maps/forest/textures/forest_rock_albedo.png | (0.936, 0.961, 0.898) | forest_rock_boulder.glb: ForestGranite_lichen; forest_rock_outcrop.glb: ForestGranite_lichen; forest_rock_slab.glb: ForestGranite_lichen |
| maps/forest/textures/forest_sun_albedo.png | (0.0673, 0.0699, 0.249) | forest_bush_low.glb: ForestBush_shade; forest_bush_tall.glb: ForestBush_shade; forest_thorns.glb: ForestThorns_shade; forest_tree.glb: ForestTree_shade |
| maps/forest/textures/forest_sun_albedo.png | (0.151, 0.194, 0.53) | forest.glb: forest_shade |
| maps/forest/textures/forest_sun_albedo.png | (0.22, 0.333, 0.568) | hub_base.glb: ForestFern; forest.glb: forest_fern |
| maps/forest/textures/forest_sun_albedo.png | (0.249, 0.279, 0.554) | hub_base.glb: ForestLeaf; forest.glb: forest_leaf; forest_bars.glb: forest_leaf |
| maps/forest/textures/forest_sun_albedo.png | (0.273, 0.303, 0.576) | forest_bush_low.glb: ForestBush_leaf; forest_bush_tall.glb: ForestBush_leaf; forest_canopy.glb: ForestCanopy_leaf; forest_portal.glb: ForestPortal_leaf; forest_tree.glb: ForestTree_leaf; forest_tree_prop_a.glb: ForestTreeProp_leaf; forest_tree_prop_b.glb: ForestTreeProp_leaf; forest_tree_prop_c.glb: ForestTreeProp_leaf |
| maps/marble/textures/marble_stone_albedo.png | (0.227, 0.255, 0.315) | hub_base.glb: Marble_shade; marble_arch.glb: Marble_shade; marble_bars.glb: marble_bars_shade; marble_column.glb: Marble_shade; marble_column_broken.glb: Marble_shade; marble_portal.glb: Marble_shade; marble_spikes.glb: MarbleSpikes_shade; marble_spikes_strip.glb: MarbleSpikes_shade |
| maps/marble/textures/marble_stone_albedo.png | (0.673, 0.549, 0.492) | marble_tower.glb: marble_tower_dome; marble_tower.glb: marble_tower_stone |
| maps/marble/textures/marble_stone_albedo.png | (0.794, 0.792, 0.815) | hub_base.glb: Marble_marble2; marble_arch.glb: Marble_marble2; marble_bars.glb: marble_bars_marble2; marble_portal.glb: Marble_marble2; marble_tower.glb: marble_tower_marble2 |
| maps/marble/textures/marble_stone_albedo.png | (0.811, 0.809, 0.837) | marble.glb: marble_plinth |
| maps/marble/textures/marble_stone_albedo.png | (0.829, 0.829, 0.862) | hub_base.glb: Marble_plinth; marble_arch.glb: Marble_plinth; marble_bars.glb: marble_bars_plinth; marble_column.glb: Marble_plinth; marble_column_broken.glb: Marble_plinth; marble_portal.glb: Marble_plinth; marble_spikes.glb: MarbleSpikes_plinth; marble_spikes_strip.glb: MarbleSpikes_plinth; marble_tower.glb: marble_tower_plinth |
| maps/marble/textures/marble_stone_albedo.png | (0.85, 0.85, 0.85) | marble.glb: marble_shade; marble_tower.glb: marble_tower_shade |

## Recolours: one texture, a colour painted per vertex (COLOR_0)

Up to four commonest colours and the share of vertices wearing each; many colours means shading.

| Model | Material | Texture | Vertex colours |
|---|---|---|---|
| hub/models/hub_base.glb | ForestBark | forest_bark_albedo.png | 1: (0.83, 0.94, 0.96) 100% |
| hub/models/hub_base.glb | ForestFern | forest_sun_albedo.png | 1: (0.99, 0.99, 1) 100% |
| hub/models/hub_base.glb | ForestGrass | forest_grass_albedo.png | 3: (1, 0.97, 1) 82%, (0.41, 0.43, 0.89) 10%, (1, 0.83, 1) 7% |
| hub/models/hub_base.glb | ForestLeaf | forest_sun_albedo.png | 2: (0.68, 0.79, 0.75) 91%, (0.39, 0.48, 0.53) 8% |
| maps/bentham_ring/models/block.glb | HellRock | hell_rock_albedo.png | 2: (1, 0.47, 0.42) 55%, (0.64, 1, 1) 44% |
| maps/bentham_ring/models/boulder.glb | HellRock | hell_rock_albedo.png | 3: (0.12, 0.08, 0.13) 53%, (1, 0.47, 0.42) 28%, (0.04, 0.03, 0.04) 17% |
| maps/bentham_ring/models/portal.glb | HellRock | hell_rock_albedo.png | 2: (1, 0.47, 0.42) 79%, (0.12, 0.08, 0.13) 20% |
| maps/bentham_ring/models/rock_wall.glb | HellRock | hell_rock_albedo.png | 1: (1, 0.47, 0.42) 100% |
| maps/bentham_ring/models/slab.glb | HellRock | hell_rock_albedo.png | 1: (1, 0.47, 0.42) 100% |
| maps/bentham_ring/models/spire.glb | HellRock | hell_rock_albedo.png | 2: (1, 0.47, 0.42) 90%, (0.12, 0.08, 0.13) 9% |
| maps/forest/models/forest.glb | forest_bark | forest_bark_albedo.png | 19: (1, 1, 1) 74%, (0.56, 0.56, 0.56) 3%, (0.99, 0.99, 0.99) 2%, (0.97, 0.97, 0.97) 2% |
| maps/forest/models/forest.glb | forest_cell | forest_rock_albedo.png | 26: (1, 1, 1) 62%, (0.56, 0.56, 0.56) 7%, (0.96, 0.96, 0.96) 3%, (0.98, 0.98, 0.98) 2% |
| maps/forest/models/forest.glb | forest_edge | forest_grass_albedo.png | 7: (1, 1, 1) 80%, (0.85, 0.85, 0.85) 6%, (0.62, 0.62, 0.62) 5%, (0.63, 0.63, 0.63) 3% |
| maps/forest/models/forest.glb | forest_lamp | forest_rock_albedo.png | 28: (1, 1, 1) 65%, (0.56, 0.56, 0.56) 5%, (0.85, 0.85, 0.85) 3%, (0.62, 0.62, 0.62) 3% |
| maps/forest/models/forest.glb | forest_leaf | forest_sun_albedo.png | 28: (1, 1, 1) 46%, (0.56, 0.56, 0.56) 10%, (0.9, 0.9, 0.9) 5%, (0.67, 0.67, 0.67) 4% |
| maps/forest/models/forest.glb | forest_shade | forest_sun_albedo.png | 4: (1, 1, 1) 91%, (0.93, 0.93, 0.93) 4%, (0.9, 0.9, 0.9) 3%, (0.99, 0.99, 0.99) 0% |
| maps/forest/models/forest.glb | forest_sun | forest_sun_albedo.png | 9: (1, 1, 1) 81%, (0.9, 0.9, 0.9) 5%, (0.93, 0.93, 0.93) 5%, (0.99, 0.99, 0.99) 4% |
| maps/forest/models/forest_tree.glb | ForestTree_leaf | forest_sun_albedo.png | 17: (1, 1, 1) 48%, (1.11, 1.11, 1.11) 7%, (1.08, 1.08, 1.08) 6%, (1.05, 1.05, 1.05) 6% |
| maps/forest/models/forest_tree.glb | ForestTree_sun | forest_sun_albedo.png | 8: (1, 1, 1) 81%, (0.75, 0.78, 0.86) 3%, (0.65, 0.69, 0.8) 3%, (0.92, 0.93, 0.95) 2% |
| tower/models/tower.glb | HellRock | hell_rock_albedo.png | 4: (1, 0.47, 0.42) 51%, (0.12, 0.08, 0.13) 44%, (0.64, 1, 1) 3%, (0.04, 0.03, 0.04) 0% |
| tower/models/tower2.glb | HellRock | hell_rock_albedo.png | 4: (1, 0.47, 0.42) 43%, (0.12, 0.08, 0.13) 39%, (0.64, 1, 1) 15%, (0.04, 0.03, 0.04) 1% |
| tower/models/tower_arches.glb | HellRock | hell_rock_albedo.png | 4: (1, 0.47, 0.42) 79%, (0.12, 0.08, 0.13) 18%, (0.64, 1, 1) 2%, (0.04, 0.03, 0.04) 0% |
| tower/models/tower_hollow.glb | HellRock | hell_rock_albedo.png | 4: (1, 0.47, 0.42) 84%, (0.12, 0.08, 0.13) 14%, (0.64, 1, 1) 1%, (0.04, 0.03, 0.04) 0% |
| tower/models/tower_interior.glb | HellRock.001 | hell_rock_albedo.png | 3: (1, 0.47, 0.42) 57%, (0.12, 0.08, 0.13) 21%, (0.64, 1, 1) 20% |

## Flat colours: materials with no texture

| Model | Material | Colour (linear RGB) |
|---|---|---|
| characters/models/runner.glb | runner_body | (0.3, 0.312, 0.33) |
| maps/forest/models/forest.glb | ForestFogMat | (0, 0, 0) |
| maps/forest/models/forest.glb | forest_stem | (1, 1, 1) |
| maps/forest/models/forest.glb | ForestRaysSoftMat | (0, 0, 0) |
| maps/forest/models/forest.glb | ForestRaysSolidMat | (0, 0, 0) |
| tower/models/eye.glb | M_Iris | (0.6, 0.01, 0.008) |
| tower/models/eye.glb | M_Pupil | (0.006, 0.004, 0.006) |
| tower/models/eye.glb | M_Sclera | (0.03, 0.03, 0.038) |

## Every material in every shipped model

| Model | Material | Texture | Sheet / slice | Multiplier | Glow texture |
|---|---|---|---|---|---|
| characters/models/prisoner2.glb | Prisoner2Skin | characters/textures/prisoner2_albedo.png | prisoner.ase / prisoner2_albedo | - | - |
| characters/models/prisoner2.glb | Shirt | characters/textures/prisoner2_albedo.png | prisoner.ase / prisoner2_albedo | - | - |
| characters/models/runner.glb | runner_body | none | - | (0.3, 0.312, 0.33) | - |
| hub/models/hub_base.glb | HellRock | maps/bentham_ring/textures/hell_rock_albedo.png | hell.ase / hell_rock_albedo | - | - |
| hub/models/hub_base.glb | Lava | maps/bentham_ring/textures/lava_albedo.png | standalone PNG | - | lava_albedo.png |
| hub/models/hub_base.glb | HubStone | hub/textures/hub_stone_albedo.png | hub.ase / hub_stone_albedo | - | - |
| hub/models/hub_base.glb | Marble | maps/marble/textures/marble_albedo.png | marble.ase / marble_albedo | - | - |
| hub/models/hub_base.glb | ForestBark | maps/forest/textures/forest_bark_albedo.png | forest.ase / forest_bark_albedo | - | - |
| hub/models/hub_base.glb | ForestDark | maps/forest/textures/forest_rock_albedo.png | forest.ase / forest_rock_albedo | (0.0144, 0.0135, 0.015) | - |
| hub/models/hub_base.glb | ForestFern | maps/forest/textures/forest_sun_albedo.png | forest.ase / forest_sun_albedo | (0.22, 0.333, 0.568) | - |
| hub/models/hub_base.glb | ForestGrass | maps/forest/textures/forest_grass_albedo.png | forest.ase / forest_grass_albedo | - | - |
| hub/models/hub_base.glb | ForestLeaf | maps/forest/textures/forest_sun_albedo.png | forest.ase / forest_sun_albedo | (0.249, 0.279, 0.554) | - |
| hub/models/hub_base.glb | ForestPath | maps/forest/textures/forest_path_albedo.png | forest.ase / forest_path_albedo | - | - |
| hub/models/hub_base.glb | Marble_marble | maps/marble/textures/marble_stone_albedo.png | marble.ase / marble_stone_albedo | - | - |
| hub/models/hub_base.glb | Marble_marble2 | maps/marble/textures/marble_stone_albedo.png | marble.ase / marble_stone_albedo | (0.794, 0.792, 0.815) | - |
| hub/models/hub_base.glb | Marble_plinth | maps/marble/textures/marble_stone_albedo.png | marble.ase / marble_stone_albedo | (0.828, 0.829, 0.862) | - |
| hub/models/hub_base.glb | Marble_shade | maps/marble/textures/marble_stone_albedo.png | marble.ase / marble_stone_albedo | (0.227, 0.255, 0.315) | - |
| hub/models/hub_base.glb | MarbleDark | maps/marble/textures/marble_dark_albedo.png | marble.ase / marble_dark_albedo | - | - |
| maps/bentham_ring/models/block.glb | HellRock | maps/bentham_ring/textures/hell_rock_albedo.png | hell.ase / hell_rock_albedo | - | - |
| maps/bentham_ring/models/boulder.glb | HellRock | maps/bentham_ring/textures/hell_rock_albedo.png | hell.ase / hell_rock_albedo | - | - |
| maps/bentham_ring/models/map_base_cover_s2.glb | HellEmber | maps/bentham_ring/textures/hell_rock_albedo.png | hell.ase / hell_rock_albedo | (0.036, 0.0296, 0.0361) | - |
| maps/bentham_ring/models/map_base_cover_s2.glb | HellShade | maps/bentham_ring/textures/hell_rock_albedo.png | hell.ase / hell_rock_albedo | (0.116, 0.0847, 0.13) | - |
| maps/bentham_ring/models/map_base_cover_s4.glb | HellEmber | maps/bentham_ring/textures/hell_rock_albedo.png | hell.ase / hell_rock_albedo | (0.036, 0.0296, 0.0361) | - |
| maps/bentham_ring/models/map_base_cover_s4.glb | HellShade | maps/bentham_ring/textures/hell_rock_albedo.png | hell.ase / hell_rock_albedo | (0.116, 0.0847, 0.13) | - |
| maps/bentham_ring/models/map_base_gate.glb | HellRock.001 | maps/bentham_ring/textures/hell_rock_albedo.png | hell.ase / hell_rock_albedo | (1, 0.472, 0.42) | - |
| maps/bentham_ring/models/map_base_gate.glb | HellShade.001 | maps/bentham_ring/textures/hell_rock_albedo.png | hell.ase / hell_rock_albedo | (0.116, 0.0847, 0.13) | - |
| maps/bentham_ring/models/map_base_lip013.glb | HellRock | maps/bentham_ring/textures/hell_rock_albedo.png | hell.ase / hell_rock_albedo | (1, 0.472, 0.42) | - |
| maps/bentham_ring/models/map_base_lip013.glb | HellShade | maps/bentham_ring/textures/hell_rock_albedo.png | hell.ase / hell_rock_albedo | (0.116, 0.0847, 0.13) | - |
| maps/bentham_ring/models/map_base_lip066.glb | HellRock | maps/bentham_ring/textures/hell_rock_albedo.png | hell.ase / hell_rock_albedo | (1, 0.472, 0.42) | - |
| maps/bentham_ring/models/map_base_lip066.glb | HellShade | maps/bentham_ring/textures/hell_rock_albedo.png | hell.ase / hell_rock_albedo | (0.116, 0.0847, 0.13) | - |
| maps/bentham_ring/models/map_base_lip139.glb | HellRock | maps/bentham_ring/textures/hell_rock_albedo.png | hell.ase / hell_rock_albedo | (1, 0.472, 0.42) | - |
| maps/bentham_ring/models/map_base_lip139.glb | HellShade | maps/bentham_ring/textures/hell_rock_albedo.png | hell.ase / hell_rock_albedo | (0.116, 0.0847, 0.13) | - |
| maps/bentham_ring/models/map_base_lip204.glb | HellRock | maps/bentham_ring/textures/hell_rock_albedo.png | hell.ase / hell_rock_albedo | (1, 0.472, 0.42) | - |
| maps/bentham_ring/models/map_base_lip204.glb | HellShade | maps/bentham_ring/textures/hell_rock_albedo.png | hell.ase / hell_rock_albedo | (0.116, 0.0847, 0.13) | - |
| maps/bentham_ring/models/map_base_lip286.glb | HellRock | maps/bentham_ring/textures/hell_rock_albedo.png | hell.ase / hell_rock_albedo | (1, 0.472, 0.42) | - |
| maps/bentham_ring/models/map_base_lip286.glb | HellShade | maps/bentham_ring/textures/hell_rock_albedo.png | hell.ase / hell_rock_albedo | (0.116, 0.0847, 0.13) | - |
| maps/bentham_ring/models/map_base_s1.glb | HellEmber | maps/bentham_ring/textures/hell_rock_albedo.png | hell.ase / hell_rock_albedo | (0.036, 0.0296, 0.0361) | - |
| maps/bentham_ring/models/map_base_s1.glb | HellGlow | maps/bentham_ring/textures/crack_glow_albedo.png | hell.ase / crack_glow_albedo | - | crack_glow_albedo.png |
| maps/bentham_ring/models/map_base_s1.glb | LavaSea | maps/bentham_ring/textures/lava_albedo.png | standalone PNG | - | map_base_lava_emissive.png |
| maps/bentham_ring/models/map_base_s1.glb | HellRock | maps/bentham_ring/textures/hell_rock_albedo.png | hell.ase / hell_rock_albedo | (1, 0.472, 0.42) | - |
| maps/bentham_ring/models/map_base_s1.glb | HellShade | maps/bentham_ring/textures/hell_rock_albedo.png | hell.ase / hell_rock_albedo | (0.116, 0.0847, 0.13) | - |
| maps/bentham_ring/models/map_base_s2.glb | HellEmber | maps/bentham_ring/textures/hell_rock_albedo.png | hell.ase / hell_rock_albedo | (0.036, 0.0296, 0.0361) | - |
| maps/bentham_ring/models/map_base_s2.glb | HellGlow | maps/bentham_ring/textures/crack_glow_albedo.png | hell.ase / crack_glow_albedo | - | crack_glow_albedo.png |
| maps/bentham_ring/models/map_base_s2.glb | LavaSea | maps/bentham_ring/textures/lava_albedo.png | standalone PNG | - | map_base_lava_emissive.png |
| maps/bentham_ring/models/map_base_s2.glb | LavaRiver | maps/bentham_ring/textures/lava_albedo.png | standalone PNG | - | map_base_lava_emissive.png |
| maps/bentham_ring/models/map_base_s2.glb | HellRock | maps/bentham_ring/textures/hell_rock_albedo.png | hell.ase / hell_rock_albedo | (1, 0.472, 0.42) | - |
| maps/bentham_ring/models/map_base_s2.glb | HellShade | maps/bentham_ring/textures/hell_rock_albedo.png | hell.ase / hell_rock_albedo | (0.116, 0.0847, 0.13) | - |
| maps/bentham_ring/models/map_base_s3.glb | LavaCrack | maps/bentham_ring/textures/crack_glow_albedo.png | hell.ase / crack_glow_albedo | - | crack_glow_albedo.png |
| maps/bentham_ring/models/map_base_s3.glb | HellEmber | maps/bentham_ring/textures/hell_rock_albedo.png | hell.ase / hell_rock_albedo | (0.036, 0.0296, 0.0361) | - |
| maps/bentham_ring/models/map_base_s3.glb | HellGlow | maps/bentham_ring/textures/crack_glow_albedo.png | hell.ase / crack_glow_albedo | - | crack_glow_albedo.png |
| maps/bentham_ring/models/map_base_s3.glb | LavaSea | maps/bentham_ring/textures/lava_albedo.png | standalone PNG | - | map_base_lava_emissive.png |
| maps/bentham_ring/models/map_base_s3.glb | HellRock | maps/bentham_ring/textures/hell_rock_albedo.png | hell.ase / hell_rock_albedo | (1, 0.472, 0.42) | - |
| maps/bentham_ring/models/map_base_s3.glb | HellShade | maps/bentham_ring/textures/hell_rock_albedo.png | hell.ase / hell_rock_albedo | (0.116, 0.0847, 0.13) | - |
| maps/bentham_ring/models/map_base_s4.glb | LavaCrack | maps/bentham_ring/textures/crack_glow_albedo.png | hell.ase / crack_glow_albedo | - | crack_glow_albedo.png |
| maps/bentham_ring/models/map_base_s4.glb | HellEmber | maps/bentham_ring/textures/hell_rock_albedo.png | hell.ase / hell_rock_albedo | (0.036, 0.0296, 0.0361) | - |
| maps/bentham_ring/models/map_base_s4.glb | HellGlow | maps/bentham_ring/textures/crack_glow_albedo.png | hell.ase / crack_glow_albedo | - | crack_glow_albedo.png |
| maps/bentham_ring/models/map_base_s4.glb | LavaSea | maps/bentham_ring/textures/lava_albedo.png | standalone PNG | - | map_base_lava_emissive.png |
| maps/bentham_ring/models/map_base_s4.glb | LavaRiver | maps/bentham_ring/textures/lava_albedo.png | standalone PNG | - | map_base_lava_emissive.png |
| maps/bentham_ring/models/map_base_s4.glb | HellRock | maps/bentham_ring/textures/hell_rock_albedo.png | hell.ase / hell_rock_albedo | (1, 0.472, 0.42) | - |
| maps/bentham_ring/models/map_base_s4.glb | HellShade | maps/bentham_ring/textures/hell_rock_albedo.png | hell.ase / hell_rock_albedo | (0.116, 0.0847, 0.13) | - |
| maps/bentham_ring/models/map_base_s5.glb | HellEmber | maps/bentham_ring/textures/hell_rock_albedo.png | hell.ase / hell_rock_albedo | (0.036, 0.0296, 0.0361) | - |
| maps/bentham_ring/models/map_base_s5.glb | HellGlow | maps/bentham_ring/textures/crack_glow_albedo.png | hell.ase / crack_glow_albedo | - | crack_glow_albedo.png |
| maps/bentham_ring/models/map_base_s5.glb | LavaSea | maps/bentham_ring/textures/lava_albedo.png | standalone PNG | - | map_base_lava_emissive.png |
| maps/bentham_ring/models/map_base_s5.glb | LavaRiver | maps/bentham_ring/textures/lava_albedo.png | standalone PNG | - | map_base_lava_emissive.png |
| maps/bentham_ring/models/map_base_s5.glb | HellRock | maps/bentham_ring/textures/hell_rock_albedo.png | hell.ase / hell_rock_albedo | (1, 0.472, 0.42) | - |
| maps/bentham_ring/models/map_base_s5.glb | HellShade | maps/bentham_ring/textures/hell_rock_albedo.png | hell.ase / hell_rock_albedo | (0.116, 0.0847, 0.13) | - |
| maps/bentham_ring/models/portal.glb | HellRock | maps/bentham_ring/textures/hell_rock_albedo.png | hell.ase / hell_rock_albedo | - | - |
| maps/bentham_ring/models/portal.glb | PortalGlow | maps/bentham_ring/textures/hell_props_albedo.png | hell.ase / hell_props_albedo | - | hell_props_albedo.png |
| maps/bentham_ring/models/rock_bars.glb | HellRock | maps/bentham_ring/textures/hell_rock_albedo.png | hell.ase / hell_rock_albedo | (1, 0.472, 0.42) | - |
| maps/bentham_ring/models/rock_bars.glb | HellShade | maps/bentham_ring/textures/hell_rock_albedo.png | hell.ase / hell_rock_albedo | (0.116, 0.0847, 0.13) | - |
| maps/bentham_ring/models/rock_wall.glb | HellRock | maps/bentham_ring/textures/hell_rock_albedo.png | hell.ase / hell_rock_albedo | - | - |
| maps/bentham_ring/models/slab.glb | HellRock | maps/bentham_ring/textures/hell_rock_albedo.png | hell.ase / hell_rock_albedo | - | - |
| maps/bentham_ring/models/spire.glb | HellRock | maps/bentham_ring/textures/hell_rock_albedo.png | hell.ase / hell_rock_albedo | - | - |
| maps/forest/models/forest.glb | ForestFogMat | none | - | (0, 0, 0) | - |
| maps/forest/models/forest.glb | forest_bark | maps/forest/textures/forest_bark_albedo.png | forest.ase / forest_bark_albedo | - | - |
| maps/forest/models/forest.glb | forest_cell | maps/forest/textures/forest_rock_albedo.png | forest.ase / forest_rock_albedo | (0.0144, 0.0135, 0.015) | - |
| maps/forest/models/forest.glb | forest_earth | maps/forest/textures/forest_path_albedo.png | forest.ase / forest_path_albedo | (0.262, 0.211, 0.475) | - |
| maps/forest/models/forest.glb | forest_edge | maps/forest/textures/forest_grass_albedo.png | forest.ase / forest_grass_albedo | (0.352, 0.402, 0.841) | - |
| maps/forest/models/forest.glb | forest_fern | maps/forest/textures/forest_sun_albedo.png | forest.ase / forest_sun_albedo | (0.22, 0.333, 0.568) | - |
| maps/forest/models/forest.glb | forest_grass | maps/forest/textures/forest_grass_albedo.png | forest.ase / forest_grass_albedo | - | - |
| maps/forest/models/forest.glb | forest_lamp | maps/forest/textures/forest_rock_albedo.png | forest.ase / forest_rock_albedo | (0.0144, 0.0135, 0.015) | forest_lamp_emissive.png |
| maps/forest/models/forest.glb | forest_leaf | maps/forest/textures/forest_sun_albedo.png | forest.ase / forest_sun_albedo | (0.249, 0.279, 0.554) | - |
| maps/forest/models/forest.glb | forest_path | maps/forest/textures/forest_path_albedo.png | forest.ase / forest_path_albedo | - | - |
| maps/forest/models/forest.glb | forest_root | maps/forest/textures/forest_bark_albedo.png | forest.ase / forest_bark_albedo | (1, 0.889, 0.801) | - |
| maps/forest/models/forest.glb | forest_shade | maps/forest/textures/forest_sun_albedo.png | forest.ase / forest_sun_albedo | (0.151, 0.194, 0.53) | - |
| maps/forest/models/forest.glb | forest_stem | none | - | - | - |
| maps/forest/models/forest.glb | forest_sun | maps/forest/textures/forest_sun_albedo.png | forest.ase / forest_sun_albedo | - | - |
| maps/forest/models/forest.glb | forest_verge | maps/forest/textures/forest_grass_albedo.png | forest.ase / forest_grass_albedo | (1, 0.846, 1) | - |
| maps/forest/models/forest.glb | ForestRaysSoftMat | none | - | (0, 0, 0) | - |
| maps/forest/models/forest.glb | ForestRaysSolidMat | none | - | (0, 0, 0) | - |
| maps/forest/models/forest_bars.glb | forest_bark | maps/forest/textures/forest_bark_albedo.png | forest.ase / forest_bark_albedo | - | - |
| maps/forest/models/forest_bars.glb | forest_leaf | maps/forest/textures/forest_sun_albedo.png | forest.ase / forest_sun_albedo | (0.249, 0.279, 0.554) | - |
| maps/forest/models/forest_bars.glb | forest_root | maps/forest/textures/forest_bark_albedo.png | forest.ase / forest_bark_albedo | (1, 0.889, 0.801) | - |
| maps/forest/models/forest_bush_low.glb | ForestBush_bark | maps/forest/textures/forest_bark_albedo.png | forest.ase / forest_bark_albedo | (0.974, 0.978, 0.978) | - |
| maps/forest/models/forest_bush_low.glb | ForestBush_leaf | maps/forest/textures/forest_sun_albedo.png | forest.ase / forest_sun_albedo | (0.273, 0.303, 0.576) | - |
| maps/forest/models/forest_bush_low.glb | ForestBush_shade | maps/forest/textures/forest_sun_albedo.png | forest.ase / forest_sun_albedo | (0.0673, 0.0699, 0.249) | - |
| maps/forest/models/forest_bush_low.glb | ForestBush_sun | maps/forest/textures/forest_sun_albedo.png | forest.ase / forest_sun_albedo | - | - |
| maps/forest/models/forest_bush_tall.glb | ForestBush_bark | maps/forest/textures/forest_bark_albedo.png | forest.ase / forest_bark_albedo | (0.974, 0.978, 0.978) | - |
| maps/forest/models/forest_bush_tall.glb | ForestBush_leaf | maps/forest/textures/forest_sun_albedo.png | forest.ase / forest_sun_albedo | (0.273, 0.303, 0.576) | - |
| maps/forest/models/forest_bush_tall.glb | ForestBush_shade | maps/forest/textures/forest_sun_albedo.png | forest.ase / forest_sun_albedo | (0.0673, 0.0699, 0.249) | - |
| maps/forest/models/forest_bush_tall.glb | ForestBush_sun | maps/forest/textures/forest_sun_albedo.png | forest.ase / forest_sun_albedo | - | - |
| maps/forest/models/forest_canopy.glb | ForestCanopy_bark | maps/forest/textures/forest_bark_albedo.png | forest.ase / forest_bark_albedo | (0.974, 0.978, 0.978) | - |
| maps/forest/models/forest_canopy.glb | ForestCanopy_leaf | maps/forest/textures/forest_sun_albedo.png | forest.ase / forest_sun_albedo | (0.273, 0.303, 0.576) | - |
| maps/forest/models/forest_portal.glb | ForestPortal_bark | maps/forest/textures/forest_bark_albedo.png | forest.ase / forest_bark_albedo | (0.974, 0.978, 0.978) | - |
| maps/forest/models/forest_portal.glb | ForestPortalSwirl | maps/forest/textures/forest_portal_swirl_albedo.png | forest.ase / forest_portal_swirl_albedo | - | forest_portal_swirl_albedo.png |
| maps/forest/models/forest_portal.glb | ForestPortal_leaf | maps/forest/textures/forest_sun_albedo.png | forest.ase / forest_sun_albedo | (0.273, 0.303, 0.576) | - |
| maps/forest/models/forest_rock_boulder.glb | ForestGranite_granite | maps/forest/textures/forest_rock_albedo.png | forest.ase / forest_rock_albedo | - | - |
| maps/forest/models/forest_rock_boulder.glb | ForestGranite_lichen | maps/forest/textures/forest_rock_albedo.png | forest.ase / forest_rock_albedo | (0.937, 0.961, 0.898) | - |
| maps/forest/models/forest_rock_boulder.glb | ForestGranite_moss | maps/forest/textures/forest_rock_albedo.png | forest.ase / forest_rock_albedo | (0.191, 0.359, 0.135) | - |
| maps/forest/models/forest_rock_boulder.glb | ForestGranite_shade | maps/forest/textures/forest_rock_albedo.png | forest.ase / forest_rock_albedo | (0.416, 0.44, 0.501) | - |
| maps/forest/models/forest_rock_outcrop.glb | ForestGranite_granite | maps/forest/textures/forest_rock_albedo.png | forest.ase / forest_rock_albedo | - | - |
| maps/forest/models/forest_rock_outcrop.glb | ForestGranite_lichen | maps/forest/textures/forest_rock_albedo.png | forest.ase / forest_rock_albedo | (0.937, 0.961, 0.898) | - |
| maps/forest/models/forest_rock_outcrop.glb | ForestGranite_moss | maps/forest/textures/forest_rock_albedo.png | forest.ase / forest_rock_albedo | (0.191, 0.359, 0.135) | - |
| maps/forest/models/forest_rock_outcrop.glb | ForestGranite_shade | maps/forest/textures/forest_rock_albedo.png | forest.ase / forest_rock_albedo | (0.416, 0.44, 0.501) | - |
| maps/forest/models/forest_rock_slab.glb | ForestGranite_granite | maps/forest/textures/forest_rock_albedo.png | forest.ase / forest_rock_albedo | - | - |
| maps/forest/models/forest_rock_slab.glb | ForestGranite_lichen | maps/forest/textures/forest_rock_albedo.png | forest.ase / forest_rock_albedo | (0.937, 0.961, 0.898) | - |
| maps/forest/models/forest_rock_slab.glb | ForestGranite_moss | maps/forest/textures/forest_rock_albedo.png | forest.ase / forest_rock_albedo | (0.191, 0.359, 0.135) | - |
| maps/forest/models/forest_rock_slab.glb | ForestGranite_shade | maps/forest/textures/forest_rock_albedo.png | forest.ase / forest_rock_albedo | (0.416, 0.44, 0.501) | - |
| maps/forest/models/forest_thorns.glb | ForestThorns_root | maps/forest/textures/forest_bark_albedo.png | forest.ase / forest_bark_albedo | (1, 0.9, 0.81) | - |
| maps/forest/models/forest_thorns.glb | ForestThorns_shade | maps/forest/textures/forest_sun_albedo.png | forest.ase / forest_sun_albedo | (0.0673, 0.0699, 0.249) | - |
| maps/forest/models/forest_tree.glb | ForestTree_bark | maps/forest/textures/forest_bark_albedo.png | forest.ase / forest_bark_albedo | (0.974, 0.978, 0.978) | - |
| maps/forest/models/forest_tree.glb | ForestTree_leaf | maps/forest/textures/forest_sun_albedo.png | forest.ase / forest_sun_albedo | (0.273, 0.303, 0.576) | - |
| maps/forest/models/forest_tree.glb | ForestTree_root | maps/forest/textures/forest_bark_albedo.png | forest.ase / forest_bark_albedo | (1, 0.9, 0.81) | - |
| maps/forest/models/forest_tree.glb | ForestTree_shade | maps/forest/textures/forest_sun_albedo.png | forest.ase / forest_sun_albedo | (0.0673, 0.0699, 0.249) | - |
| maps/forest/models/forest_tree.glb | ForestTree_sun | maps/forest/textures/forest_sun_albedo.png | forest.ase / forest_sun_albedo | - | - |
| maps/forest/models/forest_tree_prop_a.glb | ForestTreeProp_bark | maps/forest/textures/forest_bark_albedo.png | forest.ase / forest_bark_albedo | (0.974, 0.978, 0.978) | - |
| maps/forest/models/forest_tree_prop_a.glb | ForestTreeProp_leaf | maps/forest/textures/forest_sun_albedo.png | forest.ase / forest_sun_albedo | (0.273, 0.303, 0.576) | - |
| maps/forest/models/forest_tree_prop_b.glb | ForestTreeProp_bark | maps/forest/textures/forest_bark_albedo.png | forest.ase / forest_bark_albedo | (0.974, 0.978, 0.978) | - |
| maps/forest/models/forest_tree_prop_b.glb | ForestTreeProp_leaf | maps/forest/textures/forest_sun_albedo.png | forest.ase / forest_sun_albedo | (0.273, 0.303, 0.576) | - |
| maps/forest/models/forest_tree_prop_c.glb | ForestTreeProp_bark | maps/forest/textures/forest_bark_albedo.png | forest.ase / forest_bark_albedo | (0.974, 0.978, 0.978) | - |
| maps/forest/models/forest_tree_prop_c.glb | ForestTreeProp_leaf | maps/forest/textures/forest_sun_albedo.png | forest.ase / forest_sun_albedo | (0.273, 0.303, 0.576) | - |
| maps/marble/models/marble.glb | marble_band | maps/marble/textures/marble_albedo.png | marble.ase / marble_albedo | - | - |
| maps/marble/models/marble.glb | marble_cellin | maps/marble/textures/marble_dark_albedo.png | marble.ase / marble_dark_albedo | - | - |
| maps/marble/models/marble.glb | marble_column | maps/marble/textures/marble_albedo.png | marble.ase / marble_albedo | - | - |
| maps/marble/models/marble.glb | marble_dome | maps/marble/textures/marble_albedo.png | marble.ase / marble_albedo | - | - |
| maps/marble/models/marble.glb | marble_field | maps/marble/textures/marble_field_albedo.png | marble.ase / marble_field_albedo | - | - |
| maps/marble/models/marble.glb | marble_floor | maps/marble/textures/marble_albedo.png | marble.ase / marble_albedo | - | - |
| maps/marble/models/marble.glb | marble_frieze | maps/marble/textures/marble_albedo.png | marble.ase / marble_albedo | - | - |
| maps/marble/models/marble.glb | marble_iron | maps/marble/textures/marble_dark_albedo.png | marble.ase / marble_dark_albedo | - | - |
| maps/marble/models/marble.glb | marble_marble | maps/marble/textures/marble_stone_albedo.png | marble.ase / marble_stone_albedo | - | - |
| maps/marble/models/marble.glb | marble_plinth | maps/marble/textures/marble_stone_albedo.png | marble.ase / marble_stone_albedo | (0.811, 0.809, 0.837) | - |
| maps/marble/models/marble.glb | marble_shade | maps/marble/textures/marble_stone_albedo.png | marble.ase / marble_stone_albedo | (0.85, 0.85, 0.85) | - |
| maps/marble/models/marble.glb | marble_spike | maps/marble/textures/marble_albedo.png | marble.ase / marble_albedo | - | - |
| maps/marble/models/marble_arch.glb | Marble | maps/marble/textures/marble_albedo.png | marble.ase / marble_albedo | - | - |
| maps/marble/models/marble_arch.glb | Marble_marble | maps/marble/textures/marble_stone_albedo.png | marble.ase / marble_stone_albedo | - | - |
| maps/marble/models/marble_arch.glb | Marble_marble2 | maps/marble/textures/marble_stone_albedo.png | marble.ase / marble_stone_albedo | (0.794, 0.792, 0.815) | - |
| maps/marble/models/marble_arch.glb | Marble_plinth | maps/marble/textures/marble_stone_albedo.png | marble.ase / marble_stone_albedo | (0.828, 0.829, 0.862) | - |
| maps/marble/models/marble_arch.glb | Marble_shade | maps/marble/textures/marble_stone_albedo.png | marble.ase / marble_stone_albedo | (0.227, 0.255, 0.315) | - |
| maps/marble/models/marble_bars.glb | marble_bars_band | maps/marble/textures/marble_albedo.png | marble.ase / marble_albedo | - | - |
| maps/marble/models/marble_bars.glb | marble_bars_column | maps/marble/textures/marble_albedo.png | marble.ase / marble_albedo | - | - |
| maps/marble/models/marble_bars.glb | marble_bars_iron | maps/marble/textures/marble_dark_albedo.png | marble.ase / marble_dark_albedo | - | - |
| maps/marble/models/marble_bars.glb | marble_bars_marble | maps/marble/textures/marble_stone_albedo.png | marble.ase / marble_stone_albedo | - | - |
| maps/marble/models/marble_bars.glb | marble_bars_marble2 | maps/marble/textures/marble_stone_albedo.png | marble.ase / marble_stone_albedo | (0.794, 0.792, 0.815) | - |
| maps/marble/models/marble_bars.glb | marble_bars_plinth | maps/marble/textures/marble_stone_albedo.png | marble.ase / marble_stone_albedo | (0.828, 0.829, 0.862) | - |
| maps/marble/models/marble_bars.glb | marble_bars_shade | maps/marble/textures/marble_stone_albedo.png | marble.ase / marble_stone_albedo | (0.227, 0.255, 0.315) | - |
| maps/marble/models/marble_column.glb | Marble | maps/marble/textures/marble_albedo.png | marble.ase / marble_albedo | - | - |
| maps/marble/models/marble_column.glb | Marble_plinth | maps/marble/textures/marble_stone_albedo.png | marble.ase / marble_stone_albedo | (0.828, 0.829, 0.862) | - |
| maps/marble/models/marble_column.glb | Marble_shade | maps/marble/textures/marble_stone_albedo.png | marble.ase / marble_stone_albedo | (0.227, 0.255, 0.315) | - |
| maps/marble/models/marble_column_broken.glb | Marble | maps/marble/textures/marble_albedo.png | marble.ase / marble_albedo | - | - |
| maps/marble/models/marble_column_broken.glb | Marble_plinth | maps/marble/textures/marble_stone_albedo.png | marble.ase / marble_stone_albedo | (0.828, 0.829, 0.862) | - |
| maps/marble/models/marble_column_broken.glb | Marble_shade | maps/marble/textures/marble_stone_albedo.png | marble.ase / marble_stone_albedo | (0.227, 0.255, 0.315) | - |
| maps/marble/models/marble_portal.glb | Marble | maps/marble/textures/marble_albedo.png | marble.ase / marble_albedo | - | - |
| maps/marble/models/marble_portal.glb | Marble_marble | maps/marble/textures/marble_stone_albedo.png | marble.ase / marble_stone_albedo | - | - |
| maps/marble/models/marble_portal.glb | Marble_marble2 | maps/marble/textures/marble_stone_albedo.png | marble.ase / marble_stone_albedo | (0.794, 0.792, 0.815) | - |
| maps/marble/models/marble_portal.glb | Marble_plinth | maps/marble/textures/marble_stone_albedo.png | marble.ase / marble_stone_albedo | (0.828, 0.829, 0.862) | - |
| maps/marble/models/marble_portal.glb | Marble_shade | maps/marble/textures/marble_stone_albedo.png | marble.ase / marble_stone_albedo | (0.227, 0.255, 0.315) | - |
| maps/marble/models/marble_portal.glb | MarbleGlow | maps/marble/textures/marble_albedo.png | marble.ase / marble_albedo | - | marble_albedo.png |
| maps/marble/models/marble_spikes.glb | MarbleSpikes | maps/marble/textures/marble_albedo.png | marble.ase / marble_albedo | - | - |
| maps/marble/models/marble_spikes.glb | MarbleSpikes_plinth | maps/marble/textures/marble_stone_albedo.png | marble.ase / marble_stone_albedo | (0.828, 0.829, 0.862) | - |
| maps/marble/models/marble_spikes.glb | MarbleSpikes_shade | maps/marble/textures/marble_stone_albedo.png | marble.ase / marble_stone_albedo | (0.227, 0.255, 0.315) | - |
| maps/marble/models/marble_spikes_strip.glb | MarbleSpikes | maps/marble/textures/marble_albedo.png | marble.ase / marble_albedo | - | - |
| maps/marble/models/marble_spikes_strip.glb | MarbleSpikes_plinth | maps/marble/textures/marble_stone_albedo.png | marble.ase / marble_stone_albedo | (0.828, 0.829, 0.862) | - |
| maps/marble/models/marble_spikes_strip.glb | MarbleSpikes_shade | maps/marble/textures/marble_stone_albedo.png | marble.ase / marble_stone_albedo | (0.227, 0.255, 0.315) | - |
| maps/marble/models/marble_tower.glb | marble_tower_band | maps/marble/textures/marble_albedo.png | marble.ase / marble_albedo | - | - |
| maps/marble/models/marble_tower.glb | marble_tower_coffer | maps/marble/textures/marble_albedo.png | marble.ase / marble_albedo | - | - |
| maps/marble/models/marble_tower.glb | marble_tower_column | maps/marble/textures/marble_albedo.png | marble.ase / marble_albedo | - | - |
| maps/marble/models/marble_tower.glb | marble_tower_dome | maps/marble/textures/marble_stone_albedo.png | marble.ase / marble_stone_albedo | (0.673, 0.549, 0.492) | - |
| maps/marble/models/marble_tower.glb | marble_tower_lamp_glow | maps/marble/textures/marble_albedo.png | marble.ase / marble_albedo | - | marble_albedo.png |
| maps/marble/models/marble_tower.glb | marble_tower_floor | maps/marble/textures/marble_albedo.png | marble.ase / marble_albedo | - | - |
| maps/marble/models/marble_tower.glb | marble_tower_iron | maps/marble/textures/marble_dark_albedo.png | marble.ase / marble_dark_albedo | - | - |
| maps/marble/models/marble_tower.glb | marble_tower_marble2 | maps/marble/textures/marble_stone_albedo.png | marble.ase / marble_stone_albedo | (0.794, 0.792, 0.815) | - |
| maps/marble/models/marble_tower.glb | marble_tower_medallion | maps/marble/textures/marble_albedo.png | marble.ase / marble_albedo | - | - |
| maps/marble/models/marble_tower.glb | marble_tower_plinth | maps/marble/textures/marble_stone_albedo.png | marble.ase / marble_stone_albedo | (0.828, 0.829, 0.862) | - |
| maps/marble/models/marble_tower.glb | marble_tower_shade | maps/marble/textures/marble_stone_albedo.png | marble.ase / marble_stone_albedo | (0.85, 0.85, 0.85) | - |
| maps/marble/models/marble_tower.glb | marble_tower_stone | maps/marble/textures/marble_stone_albedo.png | marble.ase / marble_stone_albedo | (0.673, 0.549, 0.492) | - |
| props/models/speed_orb.glb | SpeedOrb | props/textures/speed_orb_albedo.png | props.ase / speed_orb_albedo | - | speed_orb_albedo.png |
| tower/models/eye.glb | M_Iris | none | - | (0.6, 0.01, 0.008) | - |
| tower/models/eye.glb | M_Pupil | none | - | (0.006, 0.004, 0.006) | - |
| tower/models/eye.glb | M_Sclera | none | - | (0.03, 0.03, 0.038) | - |
| tower/models/tower.glb | HellRock | maps/bentham_ring/textures/hell_rock_albedo.png | hell.ase / hell_rock_albedo | - | - |
| tower/models/tower2.glb | HellRock | maps/bentham_ring/textures/hell_rock_albedo.png | hell.ase / hell_rock_albedo | - | - |
| tower/models/tower_arches.glb | HellRock | maps/bentham_ring/textures/hell_rock_albedo.png | hell.ase / hell_rock_albedo | - | - |
| tower/models/tower_hollow.glb | HellRock | maps/bentham_ring/textures/hell_rock_albedo.png | hell.ase / hell_rock_albedo | - | - |
| tower/models/tower_interior.glb | HellRock.001 | maps/bentham_ring/textures/hell_rock_albedo.png | hell.ase / hell_rock_albedo | - | - |
| weapons/models/rifle.glb | RifleWarden | weapons/textures/rifle_hell_albedo.png | rifle.ase / rifle_hell_albedo | - | - |
| weapons/models/rifle_lowpoly.glb | RifleWarden | weapons/textures/rifle_hell_albedo.png | rifle.ase / rifle_hell_albedo | - | - |

## Check

- Materials: 196 in 55 models; 188 textured, 8 flat colour.
- Textured materials with a multiplier other than white: 105 (24 distinct texture x multiplier).
- Live textures: 21; missing or in no sheet (the three standalone PNGs aside): 0.
- Drawn PNGs nothing uses: none.
