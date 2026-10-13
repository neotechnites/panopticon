# haters_final
kind: short
aspect: 9:16

Ryan: comments pop up over the guard's scope in hell, then a cut to a runner's eyes in the same moment: "Yeah..." / "Thats kinda the point...", then runners in a forest and a shove off the edge. No voice, no game audio; Squeaky Clean Sprint from its start. One-shot run from haters.md's proven entries.

## 1
said: guard POV in hell: v3 opens unscoped, the hand on the lead runner (track_seconds 2.0 from 0.8), the scope up at 3.2, the shot lands on a runner as the third comment appears (hit 7.78 s in the take, 6.78 in the cut). Runners start at 44.1 (the hit at v2's 123 deg) on lanes off the lip post at 61.4 deg.
capture: --shot=s3_open_lane --stage=haters_hell --pov=guard --bots=3 --shimmer=0 --look=social --rifle=projectile --seed=20261012 --set=start=44.1;radii=48.9,48.6,48.6;track_seconds=2.0;zoom_at=3.2;fire_at=7.43
tape: haters_final_v3
hud: crosshair
expect: hit Runner_2 7.70-7.85; in_frame Runner_2 +0.0-0.05; lens_clear; lens_cover <= 0.5
seconds: 9.3
in: 1.0
motion: 0.012
refilm: v3

## 2
said: the SAME tape from the runner beside the shot runner: the neighbour goes out at the hit, the POV lives; v3's window starts 1.62 s before the hit and ends 2.18 s after it, before the pillar (as v2's end).
capture: --shot=s3_open_lane --stage=haters_hell --pov=runner --bots=3 --shimmer=0 --look=social --rifle=projectile --seed=20261012 --set=start=44.1;radii=48.9,48.6,48.6;track_seconds=2.0;zoom_at=3.2;fire_at=7.43
tape: haters_final_v3
expect: hit Runner_2 7.70-7.85; out Runner_2 +0.0-0.3; alive Runner_3; lens_clear; lens_cover <= 0.5
seconds: 3.8
in: 6.16
refilm: v3

## 3
said: runners in a forest and a shove off the edge; v3: POV from 65.0 deg r 51.0, after the shove watches the victim 0.8 s, then runs on along the lane to 110 deg r 52.0 (the floor map blocks r 48-51 at 94 deg) and the end flag. Mac smoke: go 1.20, shove 2.75, end 5.73.
capture: --shot=s3_open_lane --stage=haters_forest_shove --map=forest --pov=runner --bots=3 --shimmer=0 --seed=20261012 --set=pov_at=65.0,51.0;lane_mid=69.0;lane_r=49.6;victim_speed=0.65;watch=0.8;run_on=3.0;run_to=110.0;run_r=52.0
expect: shove Runner_2 2.6-4.2; airborne Runner_2 +0.0-0.3; below_rim Runner_2 +0.5-1.2; go Runner_1; alive Runner_1; max_yaw 300; end +2.6-3.4; lens_clear; lens_cover <= 0.5
seconds: 4.83
in: 0.9
refilm: v3

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

## script v3
captions: stack
captions_size: 72
captions_band: 0.05 0.45
captions_at: b1 0.05; b2 0.33; b3 0.62; r1 0.55 110; r2 0.70
captions_fade: 0
captions_plain: r1 r2
captions_reset: r0
music: ../haters/voice/squeaky_clean_sprint.mp3
music_db: 2   # the track's first 15.5 s measure -16.0 LUFS; +2 dB puts it at -14
music_fade: 0.01 1
| line | clip | in | len | fit | speed | text | card |
| b0 | cuts/01_v3.mp4 | 0 | | beat 3.2 | | | |
| b1 | cuts/01_v3.mp4 | cont | | beat 1.8 | | this is just halo reach duck hunt | |
| b2 | cuts/01_v3.mp4 | cont | | beat 1.8 | | youre just copying an old game mode | |
| b3 | cuts/01_v3.mp4 | cont | | beat 2.5 | | Youre art looks like its from the n64/ps1 | |
| r0 | cuts/02_v3.mp4 | 0 | | beat 0.9 | | | |
| r1 | cuts/02_v3.mp4 | cont | | beat 2.4 | | Yeah... | |
| r2 | cuts/02_v3.mp4 | cont | | beat 0.5 | | Thats kinda the point... | |
| f0 | cuts/03_v3.mp4 | 0 | | beat 4.83 | | | |
