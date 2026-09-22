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
placeholder: external\comment_placeholder.png, made by
  `python3 tools/content/pc/card.py --placeholder comment_placeholder.png 1080 400 24`
  -- a blank white rounded rectangle, nothing on it. The card column of the
  `## script` table does the rest: 900 wide, centred, middle at 35% of the
  height, black drop shadow at 60% over a 24 px blur offset 0/12. Ryan's
  screenshot replaces that one file at that one path; the same rule scales it.
## 2
said: "pov footage of sniper gameplay"
capture: --shot=s3_open_lane --stage=scope_hunt --pov=guard --bots=7 --seed=20260922
hud: crosshair
seconds: 8
in: 1.5
takes: 1
motion: 0.015
frame: 1.26667
file: 02_pov_hitscan
## 3
said: "warzone footage of sniper shots where fall off happens"
capture: tools/content/fetch.sh, SOURCES.md
## 4
said: "fortnite footage same stuff"
capture: tools/content/fetch.sh, SOURCES.md
## 5
said: "footage of the new feature being used"
capture: --shot=s3_open_lane --stage=projectile_lead --pov=guard --bots=6 --look=social --audio=near --seed=20261020
hud: crosshair
seconds: 9
in: 1.2
takes: 1
motion: 0.006
frame: 3.52
file: 05_pov_projectile

## bullet_test (feature check, not a shot)
capture: --pov=guard --hud=crosshair --stage=guard_alone --shot=s3_open_lane --bots=4 --set=speed=100;degs=170,159,148 --look=social --audio=near --seed=20260930
seconds: 3
file: frames\bullet_test

## script
# The rough v1 cut (2026-09-21): a TTS placeholder voice so Ryan can get the gist.
# Voice-first as the shove cut was: every slot is the voice line + 0.2 s and the
# picture is trimmed or slowed to match -- never frozen, so where the clips are
# shorter than the voice they play slow rather than stop.
#   l1+l2  one continuous 9.0 s bed, 01a_pack then 01a_hook, at 0.710x across
#          both lines; the comment card slides in over it with no cut.
#   l3     8.0 s of POV slowed to fill 8.80 s, so the last kill plays on rather
#          than holding, and then it cuts to l4.
#   l4/l5  warzone_a and fortnite_b as delivered, slowed to fill their lines.
#   l6     the picture start is trimmed to 4.18 s so the hit (source 5.97 s)
#          lands on "that" and the runner is down (6.45 s) before "Tell"; the
#          2.55 s of live action after the kill fills the rest at 0.52x.
voice: en-US-AndrewNeural +5%
pad: 0.2
game: 0.25
copy_720: yes
captions: pop
captions_font: Impact
captions_size: 64
captions_y: 0.72
| line | clip | in | len | fit | speed | text | card |
| l1 | cuts/01a_pack.mp4,cuts/01a_hook.mp4 | 0 |  | line | 0.7096 | Last week, I put up my first short to promote my game, and, was lucky enough that out of the few comments I got, a couple were feedback. |  |
| l2 | cuts/01a_pack.mp4,cuts/01a_hook.mp4 | cont |  | slow |  | This guy specifically recommended changing the sniper from a hitscan weapon to a projectile weapon, | external/comment_placeholder.png w=900 y=0.35 in=0.35 out=0.30 |
| l3 | cuts/02_pov_hitscan.mp4 | 0 |  | slow |  | and while I liked the idea of hitscan at first, I did need ways to make it harder for the sniper than it currently is, and so I think this is a great idea to try and achieve that. |  |
| l4 | external/warzone_a.mp4 | 0 |  | slow |  | The two games I like the most for this feeling are, one, Call of Duty, specifically in early Warzone, hitting a long shot felt incredible, |  |
| l5 | external/fortnite_b.mp4 | 0 |  | slow |  | and two, Fortnite. What I especially like about Fortnite is how clear it is why you missed and how to lead out or aim up to fix it. |  |
| l6 | cuts/05_pov_projectile_a.mp4@4.18:2.27,cuts/05_pov_projectile_a.mp4@6.45 |  |  | line | 1,fill | So, I went ahead and implemented that. Tell me in the comments what you think: is this a good addition? Or is hitscan still the better move? |  |

## dailies
# The review page, in script order: tools/content/dailies.sh projectile.
# id | src (relative to content\projectile\, empty = pending) | line (L<n> in
# "## script -> clip") | desc (one line). Poster is frames\<id>.png.
| id | src | line | desc |
| 01a_pack | cuts/01a_pack.mp4 | L1 | Shove short, 3.7-9.7 s: the pack sniped off the deck, then the last runner alone. No captions, no music. |
| 01a_hook | cuts/01a_hook.mp4 | L1 | Shove short, 0-3 s: the opening hook, the shove off the parkour into the lava. No captions, no music. |
| 01b |  | L2 | The comment card, placeholder: a blank white 1080x400 rounded rectangle, 900 wide on the canvas at 35% height with a drop shadow, sliding in from the right on L2's first word and out to the left on its last. Drop Ryan's screenshot in at external\comment_placeholder.png and re-run assemble: same size rule (900 wide, aspect kept), one file, no other change. |
| 02_pov_hitscan | final/02_pov_hitscan.mp4 | L3 | Guard POV, hitscan, crosshair only: seven prisoners running the lap on their own live brains, three of them dropped at 1.25, 3.70 and 6.20 s into the cut. Refilmed after Ryan's note on the first dailies. |
| warzone_a | external/warzone_a.mp4 | L4 | Warzone AX-50 at 241 m over the Verdansk rooftops: crosshair held above the roofline, DOWNED ~0.4 s after the kick. 720p source, softest of the set. |
| warzone_c | external/warzone_c.mp4 | L4 | Warzone HDR at ~898 m: the crosshair sits plainly above the target's head, a tracer streaks out, DOWNED at 6.85 s. Clearest drop of the warzone set; 24 fps. |
| fortnite_a | external/fortnite_a.mp4 | L5 | Fortnite: the white tracer streaks visibly past the target's head. The miss and its reason in one frame. |
| fortnite_b | external/fortnite_b.mp4 | L5 | Fortnite: leading a moving target, the "how to fix it" half. The hit lands on the clip's last frame. |
| fortnite_c | external/fortnite_c.mp4 | L5 | Fortnite heavy-vs-bolt drop test: the arc demonstrated deliberately rather than incidentally. Longest of the set. |
| 05_pov_projectile_a | cuts/05_pov_projectile_a.mp4 | L6 | Guard POV, projectile round at 200 m/s: a miss into the map at 4.6 s, then the lead and the hit on a crossing runner at 8.0 s. Seed 20260930; the delivered take. |
| 05_pov_projectile_b | cuts/05_pov_projectile_b.mp4 | L6 | The same beat at seed 20261005: same two squeezes, the runner a degree further round. The alternate take. |
| bullet_test | frames/bullet_test.mp4 | - | Feature check, not a shot: three runners at fixed bearings, the 200 m/s round in flight. Does the bullet read on screen. |

## Ryan 2026-09-21 on the first dailies
"warzone a and fortnite b is what well use. the projectile in the last clip looks stupid, it covers the entire view for the first frame, and for this clip, and the 02 pov hitscan, the people hes shooting at are retarded. they need to look like real players"
-> shot 3 = warzone_a, shot 4 = fortnite_b (locked). Bullet visual: must not fill the view at the muzzle. Shots 2 and 5: refilm with runners that look like real players.
