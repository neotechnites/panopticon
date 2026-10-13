# haters
kind: short
aspect: 9:16

Ryan: comments pop up over extremely early gameplay (the sniper POV shooting pills), then a cut to hell from a runner's eyes: "Yeah..." / "Thats kinda the point...". No voice, no game audio; Squeaky Clean Sprint from its start.

## 1
said: These pop up on screen as extremely early gameplay footage plays, footage from the snipers pov shooting at pills, that level of early.
ref: haters-v2-era-c4943a47
era: c4943a47 (2026-09-09, pills) plus its own tools/capture/run_clip.gd: the tower player on the platform, scoped (fov 28), three hits, the hand on the mouse.
capture: --shot=tower --fov=28 --cross=44
hud: crosshair
seconds: 7.8
in: 0.3

## 2
said: Cut to gameplay in the of the runners in hell with these popping up on screen: Yeah... Thats kinda the point...
capture: --shot=s3_open_lane --pov=runner --bots=7 --shimmer=0 --look=social --seed=20260922
seconds: 7.8
in: 3.0

## 3
said: v2: guard scope POV in hell (current build) tracking 3 runners; the shot lands on a runner as the third comment appears. One match, 1 guard + 3 runners, taped.
capture: --shot=s3_open_lane --stage=haters_hell --pov=guard --bots=3 --shimmer=0 --look=social --rifle=projectile --seed=20261012
tape: haters_v2
hud: crosshair
seconds: 4.1
in: 1.56

## 4
said: v2: the SAME moment of the SAME game from the runner beside the one who gets shot; he looks up at the tower, then shoves another runner into the pit.
capture: --shot=s3_open_lane --stage=haters_hell --pov=runner --bots=3 --shimmer=0 --look=social --rifle=projectile --seed=20261012
tape: haters_v2
seconds: 5.2
in: 4.36

## script v1
captions: stack
captions_size: 64
captions_band: 0.62 0.95
captions_plain: r1 r2
captions_reset: r0
music: voice/squeaky_clean_sprint.mp3
music_db: 2   # the track's first 15.5 s measure -16.0 LUFS; +2 dB puts it at -14
music_fade: 0.01 1
| line | clip | in | len | fit | speed | text | card |
| b0 | cuts/01.mp4 | 0 | | beat 0.6 | | | |
| b1 | cuts/01.mp4 | cont | | beat 2.0 | | this is just halo reach duck hunt | |
| b2 | cuts/01.mp4 | cont | | beat 2.0 | | you just wish you were crawl | |
| b3 | cuts/01.mp4 | cont | | beat 3.0 | | Youre art looks like its from the n64/ps1 | |
| r0 | cuts/02.mp4 | 0 | | beat 1.0 | | | |
| r1 | cuts/02.mp4 | cont | | beat 1.75 | | Yeah... | |
| r2 | cuts/02.mp4 | cont | | beat 4.75 | | Thats kinda the point... | |

## script v2
captions: stack
captions_size: 72
captions_band: 0.05 0.45
captions_fade: 0
captions_plain: r1 r2
captions_reset: r0
music: voice/squeaky_clean_sprint.mp3
music_db: 2   # the track's first 15.5 s measure -16.0 LUFS; +2 dB puts it at -14
music_fade: 0.01 1
| line | clip | in | len | fit | speed | text | card |
| b0 | cuts/03.mp4 | 0 | | beat 1.2 | | | |
| b1 | cuts/03.mp4 | cont | | beat 1.0 | | this is just halo reach duck hunt | |
| b2 | cuts/03.mp4 | cont | | beat 1.0 | | you just wish you were crawl | |
| b3 | cuts/03.mp4 | cont | | beat 0.8 | | Youre art looks like its from the n64/ps1 | |
| r0 | cuts/04.mp4 | 0 | | beat 0.8 | | | |
| r1 | cuts/04.mp4 | cont | | beat 2.0 | | Yeah... | |
| r2 | cuts/04.mp4 | cont | | beat 2.3 | | Thats kinda the point... | |
