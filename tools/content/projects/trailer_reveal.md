# trailer_reveal
kind: trailer
aspect: 16:9
format: Steam reveal trailer, ROUGH CUT for structure (one take per shot, first usable take kept)
ryan: "Make a ROUGH CUT of PANOPTICON's reveal trailer so Ryan can get a read on the structure. Not final quality -- speed over polish."
rules: 16:9 1920x1080 (SIZE=1920x1080 shot.sh), no HUD except the guard's scope, under 45 s, no voice, no text but the title and end cards, the match theme as the bed, game SFX off.
cards: cuts/title.mp4 and cuts/end.mp4 are PIL stills in ui/fonts/IMFellEnglish-Regular.ttf (ink #E8E0CC on #080706), pushed to the PC; not captured.
flash: cuts/08f.mp4 is cuts/08.mp4 with a white frame drawn 2.80-2.85 s (the finisher kill beat at take 3.70; the game draws its white frame only for a human guard)
delivery: content\trailer_reveal\final\rough_v1.mp4

## 1
said: "guard POV from the tower, runners moving on the ring, scope zooms in, fires" (cold open a); also the hook's scoped hit (kill 2) and the duel's scope tracking (beat 3)
capture: --shot=s3_open_lane --stage=trailer_scope --pov=guard --hud=crosshair --bots=7 --audio=near
seconds: 9
in: 0.9
freeze: waive
# smoke: zoom at 1.7, kills at take 3.35 and 5.20, beat 3 tracks Runner_3 from 6.5, misses at 8.9

## 2
said: "cut back in time ~1 s to a runner POV directly behind another runner, the runner ahead is hit and drops; the POV turns to look up at the tower"
capture: --shot=pack_lead --stage=trailer_victim --pov=runner --bots=5 --look=social --audio=near
seconds: 4.6
in: 1.2
freeze: waive
# pack_sniped POV (index 3, 1.3 deg behind and 0.55 m outside the victim, index 1); hit at take 3.01; 0.3 s later a 0.6 s glance 78 deg right (inward) and 13 up

## 3
said: "runners moving together between cover under fire (third-person)"
capture: --shot=pack_lead --stage=pack_sniped --bots=5 --look=social
seconds: 4
in: 1.0
freeze: waive
# shove short's f02 pack: hit at take ~3.0

## 4
said: "a runner pinned behind cover ... cut on that frame to the runner breaking cover and sprinting" (third person)
capture: --shot=cover_side --stage=trailer_duel --bots=1 --look=social
seconds: 6.5
in: 0.9
freeze: waive
# shot 5 (POV) gets scope_hunt's exposure lift; first take was near black
# CoverS4 pocket 212.6 deg r 52 (the 198.5 rock is behind S3's lip from the tower on main). Lens 205.6/55.2/1.3 -> 212.2/51.6/0.9, fov 56.
# smoke: peek ~2.5-3.95, round into CoverS4 at take 4.06, breaks at 4.98 toward the lens

## 5
said: "the scope holding on that cover; the runner peeks; shot hits stone; the scope shows the reload (bolt cycle / scope kick off target)"
capture: --shot=cover_side --stage=trailer_duel --pov=guard --hud=crosshair --bots=1
seconds: 4
in: 0.9
freeze: waive

## 6
said: "a prisoner shoves another out of cover into the open, who is shot"
capture: --shot=cover_side --stage=trailer_shove --bots=3 --look=social --set=victim=212.6,52;shover=217.5,53.5;runner=200,53;runner_to=199,53;impulse=10.5
seconds: 7.6
in: 0.9
freeze: waive
# smoke: shove at take 6.06, lands 209.1 deg, the hand's round drops him at 6.85 (the tower brain never fired on this ground)

## 7
said: "a runner jumping across the S3/S4 lava cracks or a gap, timed between shots"
capture: --shot=lava_parkour --stage=lavaparkour --bots=4 --look=social
seconds: 4.5
in: 0.9
freeze: waive
# approximated: the S5 lake platforms (shove short's lavaparkour), no shots in it

## 8
said: "a runner reaches the end, picks up the finisher rifle, shoots the guard (the white-frame hit), POV flips into the tower"
capture: --shot=portal --stage=trailer_finish --pov=runner --bots=2 --look=social
seconds: 5.8
in: 0.9
freeze: waive
# smoke: leap off the last lake platform 1.17, arrives 2.38 (armed in the tower room), trigger live at +1.3, kill beat 3.69 (1.2 s), seat ~4.9; the white frame is laid in at the cut

## 9
said: "variety: hell, runners on the ring under the tower"
capture: --map=bentham_ring --shot=pack_lead --stage=trailer_ring --bots=5 --look=social
seconds: 2.5
in: 1.2
freeze: waive

## 10
said: "variety: forest"
capture: --map=forest --shot=pack_lead --stage=trailer_ring --bots=5 --look=social
seconds: 2.5
in: 1.2
freeze: waive

## 11
said: "variety: marble"
capture: --map=marble --shot=pack_lead --stage=trailer_ring --bots=5 --look=social
seconds: 2.5
in: 1.2
freeze: waive

## script
size: 1920x1080
music: voice/match_theme.ogg
music_db: -3
music_fade: 0.3 2.5
captions: none
| line | clip | in | len | fit | speed | text |
| a1 | cuts/01.mp4@0.0:3.0 | | | beat 3.0 | | |
| a2 | cuts/02.mp4@0.6:2.8 | | | beat 2.8 | | |
| a3 | cuts/title.mp4@0:1.5 | | | beat 1.5 | | |
| h1 | cuts/03.mp4@0.2:2.8 | | | beat 2.8 | | |
| h2 | cuts/01.mp4@3.3:2.0 | | | beat 2.0 | | |
| d1 | cuts/04.mp4@0.0:1.6 | | | beat 1.6 | | |
| d2 | cuts/05.mp4@1.3:2.4 | | | beat 2.4 | | |
| d3 | cuts/04.mp4@3.7:2.6 | | | beat 2.6 | | |
| d4 | cuts/01.mp4@5.0:2.6 | | | beat 2.6 | | |
| t1 | cuts/06.mp4@4.1:3.4 | | | beat 3.4 | | |
| t2 | cuts/07.mp4@0.3:3.4 | | | beat 3.4 | | |
| g1 | cuts/08f.mp4@0.2:5.4 | | | beat 5.4 | | |
| v1 | cuts/09.mp4@0.3:1.3 | | | beat 1.3 | | |
| v2 | cuts/10.mp4@0.0:1.3 | | | beat 1.3 | | |
| v3 | cuts/11.mp4@0.3:1.3 | | | beat 1.3 | | |
| e1 | cuts/end.mp4@0:3.6 | | | beat 3.6 | | |
