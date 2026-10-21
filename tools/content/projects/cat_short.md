# cat_short
kind: short
aspect: 9:16
voice: no

## 1
said: "i want you to run the short pipeline on the pickup ad throw the cat short, the "can i be considered a cozy game now" is just a caption on the screen." (2026-10-20 22:17, task #687); idea #41 (10-19): "a cute cat in the hub you can pick up and throw ... at the end he chucks the cat and it cuts". POV in the hub, human layer on: walk up to Cat1 (bearing 154 r 30, probed flat and clear 20 m back along the walk, 28.8-30 m ahead toward the tower), shove = pick it up (held under the face), a 1.7 s look at it, an 18 deg turn with the eyes lifted 6 deg, shove = huck it at the tower; the cut ends 0.45 s after the throw.
capture: --shot=s3_open_lane --stage=cat_cozy --bots=1 --seed=20261020
tape: cat_short_v1
expect: pickup Cat1 2.5-3.0; throw Cat1 +2.3-2.7; lens_clear; lens_cover <= 0.5
seconds: 4.5
in: 1.2
motion: 0.012

## script v1
# TikTok/IG: the caption from the first frame to the cut, the end card with beta_link.wav (Ryan's card voice, house loudness).
captions: stack
captions_size: 96
captions_plain: c1
captions_reset: end
pad: 0.2
| line | clip | in | len | fit | speed | text | card |
| c1 | cuts/01.mp4 | 0 | 4.5 | beat 4.5 | | can i be considered a cozy game now? | |
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
| c1 | cuts/01.mp4 | 0 | 4.5 | beat 4.5 | | can i be considered a cozy game now? | |
| end | title | | | line | | beta sign up on my channel | beta signup on my channel |
