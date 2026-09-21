# projectile
kind: short
format: comment-reply (dev voice, "in my game")
aspect: 9:16
voice: Ryan (phone or Audacity take; align by words as in shove)
length: script is 156 words, ~40 s of voice at Ryan's pace, ~50 s cut
ryan: "1. just some section from the first short. Then, put the guys comment up on screen. 2. pov footage of sniper gameplay. 3. warzone footage of sniper shots where fall off happnens. 4. fortnite footage same stuff. 5. footage of the new feature being used." / "i want it to look like sniping in fortnite where you can actually see the bullet as it travels"
rules: portrait native for game captures, no HUD except the crosshair on guard POV, nothing spawns in frame, no still frames, picture follows the voice. External footage stays full frame inside the portrait canvas; sources logged in SOURCES.md.
delivery: content\projectile\{final,cuts,voice,external,frames}

## script -> clip
L1 "Last week, I put up my first short to promote my game, and, was lucky enough that out of the few comments i got, a couple were feedback."
   -> shot 1a: a section of the shove short (rough_v11, no captions)
L2 "This guy specifically recommended have changin the sniper from a hitscan weapon to a projectile weapon,"
   -> shot 1b: the comment on screen (screenshot from Ryan; the comment is not on YouTube, so TikTok or Instagram)
L3 "and while i liked the idea of hitscan at first, I did need ways to make it harder for the sniper than it currently is, and so i think this is a great idea to try and achieve that."
   -> shot 2: guard POV, hitscan, crosshair only, human aiming, several kills
L4 "The two games i like the most for this feeling are 1. Call of duty, specifically in early warzone, hitting a long shot felt incredible,"
   -> shot 3: Warzone (2020-21 Verdansk) sniper long shots with drop
L5 "and 2. fortnite. what i especially like about fortnite is how clear it is why you missed and how to lead out or aim up to fix it."
   -> shot 4: Fortnite sniper: a visible miss (bullet seen passing), then the corrected hit
L6 "So, i went ahead and implemented that, tell me in the comments what you think, is this a good addition? or is hitscan still the better move?"
   -> shot 5: guard POV with the projectile lever on and the visible bullet: lead, drop, a miss and a hit

## 1a
said: "just some section from the first short"
capture: none; cut from content\shove\final\rough_v11_nomusic.mp4
## 1b
said: "put the guys comment up on screen"
capture: none; Ryan's screenshot, full width on the portrait canvas over 1a's last frame? no: over live footage, never a still
## 2
said: "pov footage of sniper gameplay"
capture: --shot=s3_open_lane --stage=scope_hunt --pov=guard --bots=7
hud: crosshair
seconds: 8
in: 1.5
takes: 1
file: 02_pov_hitscan
## 3
said: "warzone footage of sniper shots where fall off happens"
capture: tools/content/fetch.sh, SOURCES.md
## 4
said: "fortnite footage same stuff"
capture: tools/content/fetch.sh, SOURCES.md
## 5
said: "footage of the new feature being used"
capture: --shot=s3_open_lane --stage=projectile_lead --pov=guard --bots=4 --look=social --audio=near --seed=20261005
hud: crosshair
seconds: 9
in: 1.2
takes: 1
motion: 0.006
frame: 3.52
file: 05_pov_projectile

## bullet_test (feature check, not a shot)
capture: --pov=guard --hud=crosshair --stage=guard_alone --shot=s3_open_lane --bots=4 --set=speed=200;degs=170,159,148 --look=social --audio=near --seed=20260930
seconds: 3
file: frames\bullet_test
