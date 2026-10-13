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
said: v2: guard scope POV in hell (current build) tracking 3 runners; the shot lands on a runner as the third comment appears. One match, 1 guard + 3 runners, taped. v5: in 1.17 -> 1.67, the scope up on the first frame; motion floor 0.012, a held scope tracking runners (0.0158 measured).
capture: --shot=s3_open_lane --stage=haters_hell --pov=guard --bots=3 --shimmer=0 --look=social --rifle=projectile --seed=20261012
tape: haters_v3
hud: crosshair
seconds: 5.0
in: 1.67
motion: 0.012
refilm: v5

## 4
said: v2: the SAME moment of the SAME game from the runner beside the one who gets shot; he looks up at the tower, then shoves another runner into the pit.
capture: --shot=s3_open_lane --stage=haters_hell --pov=runner --bots=3 --shimmer=0 --look=social --rifle=projectile --seed=20261012
tape: haters_v3
seconds: 5.2
in: 3.7
refilm: v3

## 5
said: v4: runners in the forest and a shove off the edge, a little longer than v3's shove. haters.gd (the old haters_short forest stage) at 3 runners + the guard; the shove lands at ~4.5 s. v5: refilmed with haters.gd committed (v4's take ran without it: no shove).
capture: --shot=s3_open_lane --stage=haters --map=forest --pov=runner --bots=3 --shimmer=0 --look=social --seed=20261012
seconds: 5.5
in: 1.0
refilm: v5

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

## script v3
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
| b0 | cuts/03_v3.mp4 | 0 | | beat 1.2 | | | |
| b1 | cuts/03_v3.mp4 | cont | | beat 1.0 | | this is just halo reach duck hunt | |
| b2 | cuts/03_v3.mp4 | cont | | beat 1.0 | | you just wish you were crawl | |
| b3 | cuts/03_v3.mp4 | cont | | beat 0.8 | | Youre art looks like its from the n64/ps1 | |
| r0 | cuts/04_v3.mp4 | 0 | | beat 0.8 | | | |
| r1 | cuts/04_v3.mp4 | cont | | beat 2.0 | | Yeah... | |
| r2 | cuts/04_v3.mp4 | cont | | beat 2.3 | | Thats kinda the point... | |

## script v4
notes: haters v3 is better, the shove shot though, has them running into a wall. also, for the shove, lets do that part in the forest and make it run a little longer. so it cuts from about the seven second mark, to a shot of runners in a forest and a shove off the edge. also, give more space to read the three quotes
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
| b0 | cuts/03_v4.mp4 | 0 | | beat 1.2 | | | |
| b1 | cuts/03_v4.mp4 | cont | | beat 1.2 | | this is just halo reach duck hunt | |
| b2 | cuts/03_v4.mp4 | cont | | beat 1.2 | | you just wish you were crawl | |
| b3 | cuts/03_v4.mp4 | cont | | beat 1.4 | | Youre art looks like its from the n64/ps1 | |
| r0 | cuts/04_v3.mp4 | 0 | | beat 0.6 | | | |
| r1 | cuts/04_v3.mp4 | cont | | beat 0.9 | | Yeah... | |
| r2 | cuts/04_v3.mp4 | cont | | beat 0.7 | | Thats kinda the point... | |
| f0 | cuts/05.mp4 | 0 | | beat 5.0 | | | |

## script v5
notes: haters v3 is better, the shove shot though, has them running into a wall. also, for the shove, lets do that part in the forest and make it run a little longer. so it cuts from about the seven second mark, to a shot of runners in a forest and a shove off the edge. also, give more space to read the three quotes
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
| b0 | cuts/03_v5.mp4 | 0 | | beat 1.2 | | | |
| b1 | cuts/03_v5.mp4 | cont | | beat 1.2 | | this is just halo reach duck hunt | |
| b2 | cuts/03_v5.mp4 | cont | | beat 1.2 | | you just wish you were crawl | |
| b3 | cuts/03_v5.mp4 | cont | | beat 1.4 | | Youre art looks like its from the n64/ps1 | |
| r0 | cuts/04_v3.mp4 | 0 | | beat 0.6 | | | |
| r1 | cuts/04_v3.mp4 | cont | | beat 0.9 | | Yeah... | |
| r2 | cuts/04_v3.mp4 | cont | | beat 0.7 | | Thats kinda the point... | |
| f0 | cuts/05_v5.mp4 | 0 | | beat 5.5 | | | |
