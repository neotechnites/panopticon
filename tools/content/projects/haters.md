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
seconds: 5.8
in: 1.67
motion: 0.012
refilm: v6

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

## 6
said: v6: runners in the forest and a shove off the edge, ONE camera: the POV runner (3 runners + the guard) shoves the runner beside him into the ravine at ~4.5 s and watches him fall; nobody is shot, the POV never dies. haters_forest.gd. The victim keeps pace ahead-inside so he is in view; the turn onto him is steered, not snapped.
capture: --shot=s3_open_lane --stage=haters_forest --map=forest --pov=runner --bots=3 --shimmer=0 --look=social --seed=20261012
seconds: 5.5
in: 1.0
refilm: v6

## 7
said: v6 take 2 of shot 6: after the shove the POV's head comes round (eased, right 40, down 8) onto the drop so the fall is in frame. haters_forest.gd.
capture: --shot=s3_open_lane --stage=haters_forest --map=forest --pov=runner --bots=3 --shimmer=0 --look=social --seed=20261012
seconds: 5.5
in: 1.0

## 8
said: v7 refilm of shot 7: the POV steered from the first step (v6's head snapped onto each new lane leg, read as the camera jumping); the shove and the fall in view, the cut ends 0.5-1 s after the fall. haters_forest.gd.
capture: --shot=s3_open_lane --stage=haters_forest --map=forest --pov=runner --bots=3 --shimmer=0 --look=social --seed=20261012
seconds: 6.5
in: 1.0

## 9
said: v8 refilm of shot 8: the shover's lane ends at 330 (v7's ended at 334 and the shove hit at the 338.3 boulder, so the victim never fell); the shove lands in the 333.4-338.3 gap, the fall in frame, the cut ends 0.5-1 s after it. haters_forest.gd.
capture: --shot=s3_open_lane --stage=haters_forest --map=forest --pov=runner --bots=3 --shimmer=0 --look=social --seed=20261012
seconds: 7.0
in: 1.0

## 10
said: v8 take 2 of shot 9: shot 9's shove (333.8 deg) only pushed the victim along the lip; impulse 32, up 7 so he goes over.
capture: --shot=s3_open_lane --stage=haters_forest --map=forest --pov=runner --bots=3 --shimmer=0 --look=social --seed=20261012 --set=impulse=32;up=7
seconds: 7.0
in: 1.0

## 11
said: v9: ONE forest spot by probe: the clean edge at 341-344.5 deg (no lip, boulder or rail); the POV runs the trunk-free lane 326-343 behind the victim, comes alongside on the pit side and shoves him over at ~343.5, looks down at the fall. haters_forest_edge.gd.
capture: --shot=s3_open_lane --stage=haters_forest_edge --map=forest --pov=runner --bots=3 --shimmer=0 --look=social --seed=20261012
seconds: 7.0
in: 1.0

## 12
said: v9 take 2 of shot 11: shot 11's shove landed at 350.8 in the bars after 1.7 s of run; pace 0.75 (victim 0.85 of it) so the POV runs ~2.5 s and the shove lands ~344, short of the portal and the bars.
capture: --shot=s3_open_lane --stage=haters_forest_edge --map=forest --pov=runner --bots=3 --shimmer=0 --look=social --seed=20261012 --set=pace=0.75
seconds: 7.0
in: 1.0

## 13
said: v10 (Ryan: "a shot of runners in a forest and a shove off the edge"): built like trailer shot 8 from the head's forest probe; POV runs the clear lane from 70 deg, closes on the pit-side runner and shoves him over the lip at ~84, eyes follow him down; cut from 0.4 s before the POV moves to 0.7 s after he drops below the rim. haters_forest_shove.gd.
capture: --shot=s3_open_lane --stage=haters_forest_shove --map=forest --pov=runner --bots=3 --shimmer=0 --seed=20261012
tape: forest_shove
expect: shove Runner_2 2.0-2.6; airborne Runner_2 +0.0-0.2; below_rim Runner_2 +0.5-1.1; end +1.2-1.8; alive Runner_1; max_yaw 300
seconds: 3.0
in: 0.8

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

## script v6
notes: for haters, literally what the fuck is the last scene. why do you keep giving me fucking scenes where the pov player dies and the camera just says there. also, you cut to fast after the 3rd quote drops, you put "thats kinda the point" on the screen too soon, and you cut away from hell to sson. oh cool i see you just did v5 and it just replaces the last clip with a fucking forest clip i have already said is fucking unusable because of all the fucking cuts
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
| b0 | cuts/03_v6.mp4 | 0 | | beat 1.2 | | | |
| b1 | cuts/03_v6.mp4 | cont | | beat 1.2 | | this is just halo reach duck hunt | |
| b2 | cuts/03_v6.mp4 | cont | | beat 1.2 | | you just wish you were crawl | |
| b3 | cuts/03_v6.mp4 | cont | | beat 2.0 | | Youre art looks like its from the n64/ps1 | |
| r0 | cuts/04_v3.mp4 | 0 | | beat 0.6 | | | |
| r1 | cuts/04_v3.mp4 | cont | | beat 2.2 | | Yeah... | |
| r2 | cuts/04_v3.mp4 | cont | | beat 2.0 | | Thats kinda the point... | |
| f0 | cuts/07.mp4 | 0 | | beat 5.5 | | | |

## script v7
notes: youre right its not cuts, its the fucking runner moving camera positions instantaneously
notes: for haters, literally what the fuck is the last scene. why do you keep giving me fucking scenes where the pov player dies and the camera just says there. also, you cut to fast after the 3rd quote drops, you put "thats kinda the point" on the screen too soon, and you cut away from hell to sson. oh cool i see you just did v5 and it just replaces the last clip with a fucking forest clip i have already said is fucking unusable because of all the fucking cuts
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
| b0 | cuts/03_v6.mp4 | 0 | | beat 1.2 | | | |
| b1 | cuts/03_v6.mp4 | cont | | beat 1.2 | | this is just halo reach duck hunt | |
| b2 | cuts/03_v6.mp4 | cont | | beat 1.2 | | you just wish you were crawl | |
| b3 | cuts/03_v6.mp4 | cont | | beat 2.0 | | Youre art looks like its from the n64/ps1 | |
| r0 | cuts/04_v3.mp4 | 0 | | beat 0.6 | | | |
| r1 | cuts/04_v3.mp4 | cont | | beat 2.2 | | Yeah... | |
| r2 | cuts/04_v3.mp4 | cont | | beat 0.45 | | Thats kinda the point... | |
| f0 | cuts/08.mp4 | 0 | | beat 5.5 | | | |

## script v8
notes: youre right its not cuts, its the fucking runner moving camera positions instantaneously
notes: for haters, literally what the fuck is the last scene. why do you keep giving me fucking scenes where the pov player dies and the camera just says there. also, you cut to fast after the 3rd quote drops, you put "thats kinda the point" on the screen too soon, and you cut away from hell to sson. oh cool i see you just did v5 and it just replaces the last clip with a fucking forest clip i have already said is fucking unusable because of all the fucking cuts
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
| b0 | cuts/03_v6.mp4 | 0 | | beat 1.2 | | | |
| b1 | cuts/03_v6.mp4 | cont | | beat 1.2 | | this is just halo reach duck hunt | |
| b2 | cuts/03_v6.mp4 | cont | | beat 1.2 | | you just wish you were crawl | |
| b3 | cuts/03_v6.mp4 | cont | | beat 2.0 | | Youre art looks like its from the n64/ps1 | |
| r0 | cuts/04_v3.mp4 | 0 | | beat 0.6 | | | |
| r1 | cuts/04_v3.mp4 | cont | | beat 2.2 | | Yeah... | |
| r2 | cuts/04_v3.mp4 | cont | | beat 0.45 | | Thats kinda the point... | |
| f0 | cuts/10.mp4 | 0 | | beat 5.5 | | | |


## script v9
notes: youre right its not cuts, its the fucking runner moving camera positions instantaneously
notes: for haters, literally what the fuck is the last scene. why do you keep giving me fucking scenes where the pov player dies and the camera just says there. also, you cut to fast after the 3rd quote drops, you put "thats kinda the point" on the screen too soon, and you cut away from hell to sson. oh cool i see you just did v5 and it just replaces the last clip with a fucking forest clip i have already said is fucking unusable because of all the fucking cuts
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
| b0 | cuts/03_v6.mp4 | 0 | | beat 1.2 | | | |
| b1 | cuts/03_v6.mp4 | cont | | beat 1.2 | | this is just halo reach duck hunt | |
| b2 | cuts/03_v6.mp4 | cont | | beat 1.2 | | you just wish you were crawl | |
| b3 | cuts/03_v6.mp4 | cont | | beat 2.0 | | Youre art looks like its from the n64/ps1 | |
| r0 | cuts/04_v3.mp4 | 0 | | beat 0.6 | | | |
| r1 | cuts/04_v3.mp4 | cont | | beat 2.2 | | Yeah... | |
| r2 | cuts/04_v3.mp4 | cont | | beat 0.45 | | Thats kinda the point... | |
| f0 | cuts/11.mp4 | 0 | | beat 3.2 | | | |


## script v10
notes: youre right its not cuts, its the fucking runner moving camera positions instantaneously
notes: for haters, literally what the fuck is the last scene. why do you keep giving me fucking scenes where the pov player dies and the camera just says there. also, you cut to fast after the 3rd quote drops, you put "thats kinda the point" on the screen too soon, and you cut away from hell to sson. oh cool i see you just did v5 and it just replaces the last clip with a fucking forest clip i have already said is fucking unusable because of all the fucking cuts
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
| b0 | cuts/03_v6.mp4 | 0 | | beat 1.2 | | | |
| b1 | cuts/03_v6.mp4 | cont | | beat 1.2 | | this is just halo reach duck hunt | |
| b2 | cuts/03_v6.mp4 | cont | | beat 1.2 | | you just wish you were crawl | |
| b3 | cuts/03_v6.mp4 | cont | | beat 2.0 | | Youre art looks like its from the n64/ps1 | |
| r0 | cuts/04_v3.mp4 | 0 | | beat 0.6 | | | |
| r1 | cuts/04_v3.mp4 | cont | | beat 2.2 | | Yeah... | |
| r2 | cuts/04_v3.mp4 | cont | | beat 0.45 | | Thats kinda the point... | |
| f0 | cuts/13.mp4 | 0 | | beat 3.0 | | | |
