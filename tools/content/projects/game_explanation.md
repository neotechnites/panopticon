# game_explanation
kind: short

## 1
said: sniper pov / sniper pov, same shot
capture: --shot=s3_open_lane --stage=hell_explainer --pov=guard --bots=3 --shimmer=0 --look=social --rifle=projectile --seed=20261017 --set=start=31,22,4.8;drop_at=5.9;lower=4.0,5.3;track_to=5.2
tape: game_explanation_v9
hud: crosshair
expect: hit Runner_1 6.17-6.37; in_frame Runner_1 +0.0-0.05; out Runner_1 +0.0-0.3; lens_clear; lens_cover <= 0.5
seconds: 5.4
in: 4.7
refilm: v9

## 2
said: same shot, cut to the runner pov on "shove", walk up, shove, he gets shot in the air, run on
capture: --shot=s3_open_lane --stage=hell_explainer --pov=runner --bots=3 --shimmer=0 --look=social --rifle=projectile --seed=20261017 --set=start=31,22,4.8;drop_at=5.9;lower=4.0,5.3;track_to=5.2
tape: game_explanation_v9
expect: hit Runner_1 6.17-6.37; out Runner_1 +0.0-0.3; shove Runner_2 10.15-10.35; in_frame Runner_2 10.6-10.75; out Runner_2 10.6-10.75; alive Runner_3; lens_clear; lens_cover <= 0.5
seconds: 12.2
in: 1.2
motion: 0.011
refilm: v9

## 3
said: different shot, get up to the portal, go through, shove him, they go flying
capture: --shot=s3_open_lane --stage=finale --pov=runner --bots=3 --shimmer=0 --seed=20261012 --set=lead=6.0;stand=3.0;pace=0.32;beat=1.3
expect: shove Runner_0 3.48-3.78; arrive Runner_1 2.0-2.25; tower_out Runner_0 +1.2-1.4; alive Runner_1; lens_clear; lens_cover <= 0.5
seconds: 4.2
in: 2.15
refilm: v10

## script v9
pad: 0.2
| line | clip | in | len | fit | speed | text | card |
| L1 | cuts/01_v9.mp4 | 0 | 5.4 | line | | In my game, one of your friends is a sniper in a tower and | |
| L2 | cuts/01_v9.mp4 | 2.615 | 2.785 | line | | everyone else has to get past him. | |
| L3 | cuts/02_v9.mp4 | 7.9 | 4.3 | line | | shove the guy in front of you into his sights and run. | |
| L4 | cuts/03_v9.mp4 | 0.085 | 4.115 | line | | Make it to the tower first, throw him out, and now you're the sniper. | |
| L5 | title | | 3.505 | line | | If you want to be the first to play it and help me make it better, there's a beta sign -up in my bio. | beta signup in bio |

## script v10
from: v9
notes: when you say youre the sniper, it should be the color shirt of the pov person, not purple, becuase purple is the color we just pushed. and you need to add my recording at the end
pad: 0.2
| line | clip | in | len | fit | speed | text | card |
| L1 | cuts/01_v9.mp4 | 0 | 5.4 | line | | In my game, one of your friends is a sniper in a tower and | |
| L2 | cuts/01_v9.mp4 | 2.615 | 2.785 | line | | everyone else has to get past him. | |
| L3 | cuts/02_v9.mp4 | 7.9 | 4.3 | line | | shove the guy in front of you into his sights and run. | |
| L4 | cuts/03_v10.mp4 | 0.085 | 4.115 | line | | Make it to the tower first, throw him out, and now you're the sniper. | |
| L5 | title | | 3.505 | line | | If you want to be the first to play it and help me make it better, there's a beta sign -up in my bio. | beta signup in bio |

## script v11
from: v10
notes: wait no, nothing to do with the mac, when i listen to it in audacity, it sounds deep and clear, in the short it sounds fine, but sounds like im in a room ... ok, fix it
notes: when you say youre the sniper, it should be the color shirt of the pov person, not purple, becuase purple is the color we just pushed. and you need to add my recording at the end
pad: 0.2
| line | clip | in | len | fit | speed | text | card |
| L1 | cuts/01_v9.mp4 | 0 | 5.4 | line | | In my game, one of your friends is a sniper in a tower and | |
| L2 | cuts/01_v9.mp4 | 2.615 | 2.785 | line | | everyone else has to get past him. | |
| L3 | cuts/02_v9.mp4 | 7.9 | 4.3 | line | | shove the guy in front of you into his sights and run. | |
| L4 | cuts/03_v10.mp4 | 0.085 | 4.115 | line | | Make it to the tower first, throw him out, and now you're the sniper. | |
| L5 | title | | 3.505 | line | | If you want to be the first to play it and help me make it better, there's a beta sign -up in my bio. | beta signup in bio |

## script v12
from: v11
notes: it would be fine but a lot of the last things i say are cut off, especially bio
notes: wait no, nothing to do with the mac, when i listen to it in audacity, it sounds deep and clear, in the short it sounds fine, but sounds like im in a room ... ok, fix it
notes: when you say youre the sniper, it should be the color shirt of the pov person, not purple, becuase purple is the color we just pushed. and you need to add my recording at the end
pad: 0.2
| line | clip | in | len | fit | speed | text | card |
| L1 | cuts/01_v9.mp4 | 0 | 5.4 | line | | In my game, one of your friends is a sniper in a tower and | |
| L2 | cuts/01_v9.mp4 | 2.615 | 2.785 | line | | everyone else has to get past him. | |
| L3 | cuts/02_v9.mp4 | 7.9 | 4.3 | line | | shove the guy in front of you into his sights and run. | |
| L4 | cuts/03_v10.mp4 | 0.085 | 4.115 | line | | Make it to the tower first, throw him out, and now you're the sniper. | |
| L5 | title | | 3.505 | line | | If you want to be the first to play it and help me make it better, there's a beta sign -up in my bio. | beta signup in bio |

## script v13
from: v12
notes: v12 is good. we just need a song / use rude buster
notes: it would be fine but a lot of the last things i say are cut off, especially bio
notes: wait no, nothing to do with the mac, when i listen to it in audacity, it sounds deep and clear, in the short it sounds fine, but sounds like im in a room ... ok, fix it
notes: when you say youre the sniper, it should be the color shirt of the pov person, not purple, becuase purple is the color we just pushed. and you need to add my recording at the end
pad: 0.2
music: voice/rude_buster.mp3
music_db: -16.2   # first 14.75 s of the track measure -11.8 LUFS; -16.2 dB puts the bed at -28 under the -16 voice
music_fade: 0.3 0.5   # starts at 0:00, the track has no intro
| line | clip | in | len | fit | speed | text | card |
| L1 | cuts/01_v9.mp4 | 0 | 5.4 | line | | In my game, one of your friends is a sniper in a tower and | |
| L2 | cuts/01_v9.mp4 | 2.615 | 2.785 | line | | everyone else has to get past him. | |
| L3 | cuts/02_v9.mp4 | 7.9 | 4.3 | line | | shove the guy in front of you into his sights and run. | |
| L4 | cuts/03_v10.mp4 | 0.085 | 4.115 | line | | Make it to the tower first, throw him out, and now you're the sniper. | |
| L5 | title | | 3.505 | line | | If you want to be the first to play it and help me make it better, there's a beta sign -up in my bio. | beta signup in bio |
