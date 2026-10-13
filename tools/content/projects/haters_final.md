# haters_final
kind: short
aspect: 9:16

Ryan: comments pop up over the guard's scope in hell, then a cut to a runner's eyes in the same moment: "Yeah..." / "Thats kinda the point...", then runners in a forest and a shove off the edge. No voice, no game audio; Squeaky Clean Sprint from its start. One-shot run from haters.md's proven entries.

## 1
said: guard scope POV in hell (haters shot 3, tape haters_v3), the scope up on the first frame; the shot lands on a runner as the third comment appears (hit 4.77 s in the take, 3.10 s in the cut).
capture: --shot=s3_open_lane --stage=haters_hell --pov=guard --bots=3 --shimmer=0 --look=social --rifle=projectile --seed=20261012
tape: haters_v3
hud: crosshair
expect: hit Runner_2 4.70-4.85; in_frame Runner_2 +0.0-0.05; lens_clear; lens_cover <= 0.4
seconds: 5.1
in: 1.67
motion: 0.012

## 2
said: the SAME tape from the runner beside the shot runner (haters shot 4): the neighbour goes out at the hit, the POV lives, the window ends before the pillar (v9/v10's in 3.7, 3.25 s).
capture: --shot=s3_open_lane --stage=haters_hell --pov=runner --bots=3 --shimmer=0 --look=social --rifle=projectile --seed=20261012
tape: haters_v3
expect: hit Runner_2 4.70-4.85; out Runner_2 +0.0-0.3; alive Runner_3; lens_clear; lens_cover <= 0.4
seconds: 3.25
in: 3.7

## 3
said: runners in a forest and a shove off the edge (haters shot 13) with a longer run-up: POV from 65.0 deg r 50.6 (clears row 68's obstacle at r 48.5-50.0), lanes in to r 49.6 by ~72, chases from 80; cut from 0.3 s before go to the end flag (below_rim + 0.7). Mac smoke: go 1.20, shove 2.82 at 85.1 deg, end 4.33.
capture: --shot=s3_open_lane --stage=haters_forest_shove --map=forest --pov=runner --bots=3 --shimmer=0 --seed=20261012 --set=pov_at=65.0,50.6;lane_mid=69.0;lane_r=49.6;victim_speed=0.65
expect: shove Runner_2 2.8-4.2; airborne Runner_2 +0.0-0.3; below_rim Runner_2 +0.5-1.2; go Runner_1; alive Runner_1; max_yaw 300; end +1.2-1.9; lens_clear; lens_cover <= 0.4
seconds: 3.43
in: 0.9

## script v1
captions: stack
captions_size: 72
captions_band: 0.05 0.45
captions_fade: 0
captions_plain: r1 r2
captions_reset: r0
music: ../haters/voice/squeaky_clean_sprint.mp3
music_db: 2   # the track's first 15.5 s measure -16.0 LUFS; +2 dB puts it at -14
music_fade: 0.01 1
| line | clip | in | len | fit | speed | text | card |
| b0 | cuts/01.mp4 | 0 | | beat 0.5 | | | |
| b1 | cuts/01.mp4 | cont | | beat 1.2 | | this is just halo reach duck hunt | |
| b2 | cuts/01.mp4 | cont | | beat 1.4 | | you just wish you were crawl | |
| b3 | cuts/01.mp4 | cont | | beat 2.0 | | Youre art looks like its from the n64/ps1 | |
| r0 | cuts/02.mp4 | 0 | | beat 0.6 | | | |
| r1 | cuts/02.mp4 | cont | | beat 2.2 | | Yeah... | |
| r2 | cuts/02.mp4 | cont | | beat 0.45 | | Thats kinda the point... | |
| f0 | cuts/03.mp4 | 0 | | beat 3.43 | | | |

## script v2
captions: stack
captions_size: 72
captions_band: 0.05 0.45
captions_fade: 0
captions_plain: r1 r2
captions_reset: r0
music: ../haters/voice/squeaky_clean_sprint.mp3
music_db: 2   # the track's first 15.5 s measure -16.0 LUFS; +2 dB puts it at -14
music_fade: 0.01 1
| line | clip | in | len | fit | speed | text | card |
| b0 | cuts/01.mp4 | 0 | | beat 0.5 | | | |
| b1 | cuts/01.mp4 | cont | | beat 1.2 | | this is just halo reach duck hunt | |
| b2 | cuts/01.mp4 | cont | | beat 1.4 | | you just wish you were crawl | |
| b3 | cuts/01.mp4 | cont | | beat 2.0 | | Youre art looks like its from the n64/ps1 | |
| r0 | cuts/02.mp4 | 0 | | beat 0.6 | | | |
| r1 | cuts/02.mp4 | cont | | beat 2.2 | | Yeah... | |
| r2 | cuts/02.mp4 | cont | | beat 0.45 | | Thats kinda the point... | |
| f0 | cuts/03.mp4 | 0.8 | | beat 2.63 | | | |
