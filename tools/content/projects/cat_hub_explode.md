# cat_hub_explode
kind: short
aspect: 9:16
voice: no

## 1
said: Ryan (2026-10-21, task #688): "ok now get a clip in the hub, of a player who spawns in, grabs a cat, pets it like 4 times over the course of a second, waits half a second, then throws it, the video ends when the explosion does". POV from HubSpawns/Spawn1 (32.82, 0.25, -3.45, facing -x), walk 10.9 m straight to Cat6 (19.70, 0.35, -3.47, dead ahead), shove = pick it up, E x4 over 1.0 s (hearts), 0.5 s, shove = throw at -x; HubCat explodes 0.5 s later in frame; the cut runs from the spawn to the blast's last frame. Game audio kept; no captions, music or card.
capture: --shot=s3_open_lane --stage=cat_hub_explode --bots=1 --seed=20261021
expect: pickup Cat6 2.2-2.6; pet n1 +0.15-0.3; pet n4 +1.15-1.3; throw Cat6 +1.6-1.8; explode in_frame +2.1-2.4; boom_end Cat6 +3.1-3.5; pet hearts_in_frame1; lens_cover <= 0.5
seconds: 5.05
in: 0.6
file: cat_hub_explode
