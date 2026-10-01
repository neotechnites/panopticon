# trailer_reveal
kind: trailer
aspect: 16:9
format: Steam reveal trailer, ROUGH CUT for structure (one take per shot, first usable take kept)
ryan: "Make a ROUGH CUT of PANOPTICON's reveal trailer so Ryan can get a read on the structure. Not final quality -- speed over polish."
rules: 16:9 1920x1080 (SIZE=1920x1080 shot.sh), no HUD except the guard's scope, under 45 s, no voice, no text but the title and end cards, SR20DET as the bed, game SFX off.
v2 notes (Ryan on rough_v1): the guard stands at the tower's window, not deep inside; all runners run the course direction; the runner shot is the SAME event as the guard shot (same stage, same seed, two POVs), cut back ~1 s to the man directly behind the victim; clear line of sight when he looks up at the tower; title drops in HARD on the music's drop; music https://www.youtube.com/watch?v=OBPV0lsorwU; real-looking gameplay only (walkable deck and real cover, nobody on lava, nobody looking backwards); max 4 players a shot (1 guard + 3); spread across hell, forest and marble. Added: "EVERY shot is first-person POV -- either the guard's scope/tower view or a prisoner's first-person view. No third-person ... Title/end cards are the only non-POV frames."
music: external\src\music_v2_OBPV0lsorwU.mp4 -> voice\sr20det.ogg (SOURCES.md). The drop: 0.35 s of silence from 5.36 s, the hit at 5.703 s (sample onset); ~158 bpm after it.
cards: cuts/title_hard.mp4 is v1's title frame looped from frame 0 (v1's title.mp4 opened on two black frames); cuts/end.mp4 is v1's.
delivery: content\trailer_reveal\final\rough_v2.mp4

## 1
said: "guard POV from the tower, runners moving on the ring, scope zooms in, fires" -- v2: "the guard stands where a PLAYER stands -- at the tower's edge/window"
capture: --shot=s3_open_lane --stage=trailer_open --pov=guard --hud=crosshair --bots=3 --seed=20261001
seconds: 4.0
in: 0.9
freeze: waive
# hell S2 inner lane; guard at the 115 deg window; zoom at take 1.9, the kill at take 3.60 (victim 114.3 deg r 49.3)

## 2
said: "cut back in time ~1 s to a runner POV directly behind another runner, the runner ahead is hit and drops; the POV turns to look up at the tower" -- v2: the SAME scenario as shot 1, clear line to the tower
capture: --shot=s3_open_lane --stage=trailer_open --pov=runner --bots=3 --look=social --seed=20261001
seconds: 5.0
in: 0.9
freeze: waive
# the same take as shot 1 down Runner_3's eyes (2.9 deg, 2.5 m directly behind the victim); hit at take 3.60, the look up 86 deg right 8 up from 3.92
