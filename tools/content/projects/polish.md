# polish
kind: short
format: i-added-x (dev voice, "in my game")
aspect: 9:16
voice: TTS placeholder (edge-tts); Ryan records over its timing
ryan: L1 "Here are some things I added to my game to make it feel more polished" / L2 "1. I added waviness to my lava, so that it's more clear that it's a flowing lava river and not just some rocks that are too hot to touch." / L3 "2. While I still don't love the texture for the portal, I added some light and particle effects around it that I think add a ton." / L4 "3. I had these placeholder demon sigils to mark what is effectively a bounce pad," / L5 "but I've replaced it with these cracks into the rock with particle effects and that sort of heat effect you get that makes everything behind it wavy." / L6 "Let me know in the comments what you think."
rules: portrait native, no HUD, nothing spawns in frame, no still frames, never a clip under 1x, game audio off (voice only), picture follows the voice.
openers: four cuts, one per L1 opener: opener_a (shot 1, face from below), opener_b (existing gameplay), opener_c (shot 2, drone lap), opener_d (shot 3, aerial). Everything after L1 is the same in all four.
delivery: content\polish\final\{opener_a,opener_b,opener_c,opener_d}.mp4

## 1
said: "closeup shot of the prisoner's face from below, kinda a funny shot"
capture: --stage=polish_face --shot=s1_cave --bots=1 --look=social
seconds: 4
in: 1.2
frame: 2.0
file: p01_face
# one prisoner on bare S1 deck at 42 deg r 51; lens 0.7 m in front at 0.35 m, fov 44, face 6 deg above centre (fov 70 at 0.9 m held the whole body, face small): a worm's-eye closeup; head bent 14-40 deg over the lens by a spring, glances +/-30 deg; voice slot 3.1 s

## 2
said: "drone shot like we had that one time"
# teaser_lap at its designed pace: 1.0 s held + (in 1.0 + 8.2 + 1) = the path's own 10.2 s; cut opens as the lap leaves the line
capture: --shot=teaser_lap --bots=7 --look=social --delay=1.0
seconds: 8.2
in: 1.0
file: opener_c_drone

## 3
said: "aerial shot of the hell map"
# high in the open shaft over the pit: 315->355 deg, r 37->33, y 58->50, look 12 m past centre at y 19, vfov 70; eased (40% linear) so never still
# motion 0.002: dim frame of like lava tiles measures 0.0025 while the lens orbits 40 deg; not a still
capture: --map=bentham_ring --shot=pit_orbit --stage=polish_aerial --bots=7 --look=social
seconds: 4.5
in: 1.2
frame: 2.0
file: 03_aerial
motion: 0.002

## 4
said: "shot of the lava from about ground height so it's very clear it's waving"
capture: --shot=lava_parkour --stage=polish_lava --bots=1 --look=social
seconds: 9
in: 1.2
file: 04_lava_wave
# S5 lake from its near bank: lens 0.6 m over probed deck at 291.3 deg, drifting r 55.6 -> 51.2 (eased), looking to 309 deg ~8 deg down, fov 58; lava ~2/3 of frame. Bot parked at 30 deg.

## 5
said: "slow zoom shot of the portal"
capture: --shot=portal --stage=polish_portal --bots=1 --look=social
seconds: 7.5
in: 1.2
# portrait, disc centred at 0.45 of the height, lens at eye height (1.7 m)
frame: 5.0
file: 05_portal
# head-on down the pass-through axis (tangent at 345 deg): dolly 19 -> 8 m back, disc centre h 1.6, fov 50 -> 43, eased 0.9-9.0 s; the one prisoner parked at 165 deg

## 6
said: "shot of people bouncing off the demon pads"
# filmed at d15d6eb (the old demon sigils) + tools/capture/stages/polish_sigil.gd, from branch work-polish-sigil (0ca147d); verify held that commit for the take
# shot 7's lens exactly (219.7->220.1 deg r 55.05 h 1.6, look 231.3/53.9/1.4, fov 55); three prisoners run up from 205.6 deg over the 212 pad onto the 227 sigil,
# seeded ~1.15-1.4 s apart; smoke: 227 bounces at 2.42/3.72/5.07 s of the take = 1.02/2.32/3.67 s of the cut, each flight on up toward 242 in frame
capture: --shot=s4_edge --stage=polish_sigil --bots=3 --look=social --seconds=7.5
seconds: 5.5
in: 1.4
# the 227 sigil low-middle
frame: 1.3
file: 06_demon_sigil
motion: 0.004

## 7
said: L5 "roughly ground level shot showing the cracks and effects" / L6 "same shot, but at this point people come and bounce off it"
capture: --shot=s4_edge --stage=polish_crack --bots=3 --look=social
seconds: 10
in: 1.2
# crack low-middle, haze against the 238-242 rock
frame: 7.6
file: 07_lava_crack
motion: 0.004
# lens 1.6 m over the deck (1.4 over the crack's slab; 0.8 hid the crack behind the slab lip), 7 m behind the 227 crack on its launch line (ring 219.7->220.1 deg r 55.05, look 231.3/53.9/1.4, fov 55), a 0.4 m push over the take: crack alone to ~7 s,
# then three off the 212 crack land on it; its 227 launches at 7.28/8.19/8.77 s of the cut (smoke), each flight recedes ~1.2 s up the frame. motion: a near-fixed lens on embers and haze.

## 8
said: Ryan on shot 1 (opener_a picked): "it's the right angle, but they don't need to move around, maybe just breathe a tiny bit, and make it way closer to the face."
capture: --stage=polish_face --shot=s1_cave --bots=1 --look=social --set=near=0.6
seconds: 4
in: 1.2
frame: crop
file: p08_face_close
motion: 0.002
freeze: waive
# shot 1's worm's-eye sight line, lens fixed 0.6 m off the head centre (0.13 m up the Head bone, which sits at the neck; 0.45 m on the bone origin framed only the neck) at fov 44 so the head fills the frame; head held bowed 30 deg, no sway or acting; only the rig's idle breath moves (3 deg spine, 3.2 s), so a fixed lens on a near-still body fails the motion/freeze gate by nature: waived

## 9
said: Ryan on shot 7: "when they bounce on the demon pads they run up one by one and run into it; when they bounce on the crack they jump directly onto it and look like they're just flying." -- staged as shot 6: one by one at a run, launched by running onto the crack; one take, cut on L6's first word
capture: --shot=s4_edge --stage=polish_crack_run --bots=3 --look=social
seconds: 10
in: 1.2
frame: native 9:16, crack low-middle, haze against the 238-242 rock
file: 09_lava_crack_run
motion: 0.004
# shot 7's lens (polish_sigil's bodies): three run up the lane one by one onto the real 212 crack, thrown onto 227 and off it;
# 227 launches at 7.29/8.04/8.84 s of the cut (smoke, seed 20260930), crack alone before. motion: a near-fixed lens.

## 10
said: Ryan: "instead of the shot of the crack being at S4, let's try it at S3, with the shot a little higher so you can see the cracks better, and have it pan." -- S3's crack network (LavaCrack r00..r16), lens ~2.5-3 m over the deck, a slow pan across the cracks on L5, then on L6 runners arrive at a run one by one and launch off a crack in frame; one take, cut on L6's first word
capture: --shot=s4_edge --stage=polish_crack_s3 --bots=3 --look=social
seconds: 10
in: 1.2
frame: native 9:16, the grid from 2.8 m, the 160 crack low-middle after the pan
file: 10_lava_crack_s3
# lens ring 154.3->154.7 deg r 54.6 h 2.8, fov 62; look pans eased 166/57.5/-0.5 -> 163/52.3/0.4 over cut 0-7 s;
# three run the clear r 52.4 lane one by one onto LavaCrack_r04_c1_160deg; launches at 7.28/8.08/8.72 s of the cut (smoke, seed 20260930).

## script -> clip
L1 "Here are some things I added to my game to make it feel more polished" -> opener a/b/c/d (shot 1, shove hook, shot 2, shot 3)
L2 "1. I added waviness to my lava..." -> shot 4
L3 "2. While I still don't love the texture for the portal..." -> shot 5
L4 "3. I had these placeholder demon sigils to mark what is effectively a bounce pad," -> shot 6 (at d15d6eb)
L5 "but I've replaced it with these cracks into the rock..." -> shot 7, 0-7.24 s
L6 "Let me know in the comments what you think." -> shot 7 continued (first launch 7.28 s)

## script
# The four opener cuts differ only in l1's clip: opener_a cuts/01.mp4 in 0; opener_b
# cuts/00b_gameplay.mp4 in 0 (shove final 00_hook, 3.0 s); opener_c cuts/02.mp4 in 1.0;
# opener_d cuts/03.mp4 in 0. assemble with the l1 row swapped, --tag opener_<x>.
# final_d (Ryan's pick, 2026-09-29) is this table as written: opener d (03) and the S3 crack (10); was 09 (S4) before Ryan's S3 note.
# Ryan's voice: his per-line wavs as voice\l1..l6.wav, then assemble.sh polish --tag final_d, then scripts\tiktok.ps1.
# Ryan's voice landed 2026-09-29 from Documents\Panopticon\SOcials\Audio Clips\Short 3\voice_over.aup4 (5 clips; l4+l5 one take split at 5.07 s; l6 keeps his "Were these good additions?"); TTS in voice\tts_bak.
# opener_a2 (Ryan's notes): l1 cuts/08.mp4, l5/l6 cuts/09.mp4 (first launch 7.28 s).
# l5+l6 are one take: the first launch (7.28 s) lands on L6's first word (7.24 s).
voice: en-US-AndrewNeural +5%
pad: 0.2
game: 0
copy_720: yes
music: music/stardust_speedway_act2.m4a
music_db: -23.5
music_fade: 1 1.5
captions: pop
captions_font: Impact
captions_size: 64
captions_y: 0.72
| line | clip | in | len | fit | speed | text |
| l1 | cuts/03.mp4 | 0 |  | line |  | Here are some things I added to my game to make it feel more polished. |
| l2 | cuts/04.mp4 | 0 |  | line |  | One, I added waviness to my lava, so that it's more clear that it's a flowing lava river, and not just some rocks that are too hot to touch. |
| l3 | cuts/05.mp4 | 0.5 |  | line |  | Two, while I still don't love the texture for the portal, I added some light and particle effects around it that I think add a ton. |
| l4 | cuts/06.mp4 | 0 |  | line |  | Three, I had these placeholder demon sigils to mark what is effectively a bounce pad, |
| l5 | cuts/10.mp4 | 0 |  | line |  | but I've replaced it with these cracks into the rock, with particle effects, and that sort of heat effect you get that makes everything behind it wavy. |
| l6 | cuts/10.mp4 | cont |  | line |  | Let me know in the comments what you think. |

## dailies
| id | src | line | desc |
| opener_a | final/opener_a.mp4 | - | The full short, opener a: the prisoner's face from below. |
| opener_b | final/opener_b.mp4 | - | The full short, opener b: the shove short's hook (existing gameplay). |
| opener_c | final/opener_c.mp4 | - | The full short, opener c: the teaser_lap drone. |
| opener_d | final/opener_d.mp4 | - | The full short, opener d: aerial over the pit. |
| 01 | cuts/01.mp4 | L1 | Worm's-eye closeup: a prisoner peering down into the lens. |
| 00b | cuts/00b_gameplay.mp4 | L1 | Shove short hook, 3.0 s: the shove off the parkour into the lava. |
| 02 | cuts/02.mp4 | L1 | teaser_lap drone at its own pace; the cut uses 1.0-4.1 s. |
| 03 | cuts/03.mp4 | L1 | High in the pit shaft, a sinking 40 deg orbit over the ring. |
| 04 | cuts/04.mp4 | L2 | S5 lava lake from ~0.6 m over the bank, drifting along the swell. |
| 05 | cuts/05.mp4 | L3 | Slow push in on the portal, its light and particles. |
| 06 | cuts/06.mp4 | L4 | The old S4 demon sigil at 227 deg (commit d15d6eb): three prisoners bounce off it at 1.02, 2.32, 3.67 s. |
| 07 | cuts/07.mp4 | L5 | The same lens on the new 227 crack: embers and heat shimmer, then three launches at 7.28, 8.18, 8.77 s. |
| opener_a2 | final/opener_a2.mp4 | - | The full short, opener a after Ryan's notes: face close and still (08), runners one by one onto the crack (09). |
| 08 | cuts/08.mp4 | L1 | Shot 1 refilmed: the same worm's-eye angle, the head filling the frame, only breathing. |
| 09 | cuts/09.mp4 | L5 | Shot 7 refilmed as shot 6 was staged: runners one by one off the 212 pad onto the 227 crack, launches at 7.28, 8.03, 8.83 s. Knee fix in. |
| final_d | final/final_d.mp4 | - | Ryan's pick: opener d (aerial) with the S3 crack shot (10). The cut his voice goes on. |
| final_d_tiktok | final/final_d_tiktok.mp4 | - | final_d re-encoded as the projectile TikTok upload: 1080x1920 30 fps H.264 High 4.1 ~7.5 Mbps, AAC 192k 44.1 kHz, faststart. |
| 10 | cuts/10.mp4 | L5 | S3 crack grid, lens ~2.5-3 m, a slow pan across the fissures, then runners launch off a crack at 7.28, 8.08, 8.72 s. Knee fix in. |
| final_d_music | final/final_d_music.mp4 | - | final_d with Stardust Speedway Zone Act 2 (Tee Lopes) under the voice; -14 LUFS, about -1.6 dBTP. |
| final_d_music_tiktok | final/final_d_music_tiktok.mp4 | - | final_d_music as the TikTok upload encode. |
| final_d_nomusic | final/final_d_nomusic.mp4 | - | final_d voice only, normalised to -14 LUFS, about -1.5 dBTP. |
| final_d_nomusic_tiktok | final/final_d_nomusic_tiktok.mp4 | - | final_d_nomusic as the TikTok upload encode. |
