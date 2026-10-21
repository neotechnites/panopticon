# cat_short
kind: short
aspect: 9:16
voice: no

## 1
said: "i want you to run the short pipeline on the pickup ad throw the cat short, the "can i be considered a cozy game now" is just a caption on the screen." (2026-10-20 22:17, task #687); idea #41 (10-19): "a cute cat in the hub you can pick up and throw ... at the end he chucks the cat and it cuts". POV in the hub, human layer on: walk up to Cat1 (bearing 154 r 30, probed flat and clear 20 m back along the walk, 28.8-30 m ahead toward the tower), shove = pick it up (held under the face), a 0.5 s shuffle and a 12 deg look left over it, a 30 deg turn right with the eyes lifted 6 deg, shove = huck it at the tower; the cut ends 0.45 s after the throw. Take 1 (a still 1.7 s hold) failed the gate (freeze 1.0 s, no duplicate frames); retaped as cat_short_v1b.
capture: --shot=s3_open_lane --stage=cat_cozy --bots=1 --seed=20261020
tape: cat_short_v1b
expect: pickup Cat1 2.5-3.0; throw Cat1 +1.8-2.2; lens_clear; lens_cover <= 0.5
seconds: 4.0
in: 1.2
motion: 0.012

## 2
said: Ryan (22:45, task #687): "ok, can you do it in the hell map now instead of the hub?" ## 1's choreography on bentham_ring: a cat.tscn spawned at 42 deg r 50 (probe_ring --clear: 0-71 deg pad- and trap-free; --heights: deck +-0.08 m at 40-50 deg r 47-55; at 45 deg the walk stuck on an unprobed collider at r 52.6, so 42), the runner POV walks in from r 56, picks it up, shuffles and looks over it, hucks it over the pit at the tower; the cut ends 0.45 s after the throw. lens_clear is off this entry: the held cat sits 0.34 m from the lens by design.
capture: --shot=s3_open_lane --stage=cat_cozy --pov=runner --bots=1 --shimmer=0 --look=social --seed=20261020 --set=at=42:50;back=6.0
tape: cat_short_v3
expect: pickup Cat1 2.4-2.8; throw Cat1 +1.8-2.2; alive Runner_1; lens_cover <= 0.5
seconds: 3.8
in: 1.2

## script v1
# TikTok/IG: the caption from the first frame to the cut, the end card with beta_link.wav (Ryan's card voice, house loudness).
captions: stack
captions_size: 96
captions_plain: c1
captions_reset: end
pad: 0.2
| line | clip | in | len | fit | speed | text | card |
| c1 | cuts/01.mp4 | 0 | 4.0 | beat 4.0 | | can i be considered a cozy game now? | |
| end | title | | | line | | beta link in bio | beta signup in bio |

## script v2
from: v1
# YouTube: v1 with the YouTube end card line, beta_link_youtube.wav.
captions: stack
captions_size: 96
captions_plain: c1
captions_reset: end
pad: 0.2
| line | clip | in | len | fit | speed | text | card |
| c1 | cuts/01.mp4 | 0 | 4.0 | beat 4.0 | | can i be considered a cozy game now? | |
| end | title | | | line | | beta sign up on my channel | beta signup on my channel |

## script v3
from: v2
notes: Ryan (22:40, task #687): "get rid of the audio for beta link in bio on the cat short"; Ryan (22:45): "ok, can you do it in the hell map now instead of the hub?"
# YouTube: the hell take (## 2), the card silent; voice/silence.wav is a silent bed so the cut has a (silent) track.
music: voice/silence.wav
music_db: 0
music_fade: 0.02 0.02
captions: stack
captions_size: 96
captions_plain: c1
captions_reset: end
pad: 0.2
| line | clip | in | len | fit | speed | text | card |
| c1 | cuts/02.mp4 | 0 | 3.8 | beat 3.8 | | can i be considered a cozy game now? | |
| end | title | | 1.2 | | | beta signup on my channel | |

## script v4
from: v3
# TikTok/IG: v3 with the TikTok/IG card line.
music: voice/silence.wav
music_db: 0
music_fade: 0.02 0.02
captions: stack
captions_size: 96
captions_plain: c1
captions_reset: end
pad: 0.2
| line | clip | in | len | fit | speed | text | card |
| c1 | cuts/02.mp4 | 0 | 3.8 | beat 3.8 | | can i be considered a cozy game now? | |
| end | title | | 1.2 | | | beta signup in bio | |
