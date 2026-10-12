# portal_spin
kind: short
format: comment-reply (dev voice, "in my game")
aspect: 9:16
voice: edge-tts placeholder per line (en-US-AndrewNeural +5%, the forest/shove voice); Ryan records later
map: bentham_ring (hell): the portal reads against the dark rock and the lava wave it borrows from is in the same frame
capture: real time (ddagrab) in the console session, viewport 810x1440 (the PC's 1440 px screen is the tallest portrait it can hold), scaled to 1080x1920; same 9:16 composition, vertical fov
delivery: content\portal_spin\final\portal_spin_v1.mp4

## script -> clip (Ryan, verbatim)
L1 "Do you think this change to my game is an improvement or should i scrap it?" {slow zoom on the portal, ALREADY SPINNING (current main)}
L2 "This guy on my last two shorts asked the same thing, make the portal spin" {sniper-POV gameplay in the background, with a YouTube-style comment card on screen. Handle and text are a PLACEHOLDER ("@commenter — make the portal spin"), clearly marked.}
L3 "And you know what? I think thats a great idea" {same shot; the comment card goes away}
L4 "This was simple, i already had the portal waving using a modified version of what i used to make the lava wave" {the portal waving WITHOUT spinning, filmed from ed473b24~1; the lava wave can show too}
L5 "All I had to do was add a few lines to that shader that rotate the texture around its centre a little more every frame, so the whole swirl turns." {Godot-editor-style footage: the portal texture with the spin off, then turned on, holding a beat after it starts.}
L6 "What do you think? should i keep this in or not?" {more shots of the spinning portal in game}
L7 "Let me know what else you think i should add in the comments and it just might make it into the final game!" {runner-POV gameplay}

## shots (stage tools/capture/stages/portal_spin.gd unless named; run_clip --map=bentham_ring)
# s1 zoom   L1  --shot=portal --stage=portal_spin --set=mode=zoom            main
# s2 scope  L2+L3 --shot=s3_open_lane --stage=scope_hunt --pov=guard --hud=crosshair --bots=7   main
# s3 wave   L4  --shot=portal --stage=portal_spin --set=mode=wave            8120d577 (= ed473b24~1, no spin)
# s4 dial   L5  --shot=portal --stage=portal_spin --set=mode=dial;spin_at=T  main: grey editor-like view, the spin dial 0 -> 0.8 rad/s live at T
# s5 orbit  L6  --shot=portal --stage=portal_spin --set=mode=orbit           main
# s6 runner L7  --shot=lava_parkour --stage=lavaparkour --pov=runner --bots=4 main
# L5 is split in two rows (l5a/l5b) so the shader-code card shows on "add a few lines to that shader" and is gone before the spin turns on.

## script
voice: en-US-AndrewNeural +5%
music: voice/windmill_isle_day.mp3
music_db: -18
music_fade: 1.0 1.5
pad: 0.2
captions: pop
captions_font: Impact
captions_size: 64
captions_y: 0.72
| line | clip | in | len | fit | speed | text | card |
| l1 | cuts/s1_zoom.mp4 | 0 |  | line |  | Do you think this change to my game is an improvement, or should I scrap it? |  |
| l2 | cuts/s2_scope.mp4 | 0 |  | line |  | This guy on my last two shorts asked the same thing: make the portal spin. | external/comment_placeholder.png w=900 y=0.33 in=0.35 out=0.30 |
| l3 | cuts/s2_scope.mp4 | cont |  | line |  | And you know what? I think that's a great idea. |  |
| l4 | cuts/s3_wave.mp4 | 0 |  | line |  | This was simple. I already had the portal waving, using a modified version of what I used to make the lava wave. |  |
| l5a | cuts/s4_dial.mp4 | 0 |  | line |  | All I had to do was add a few lines to that shader | external/shader_lines.png w=980 y=0.2 in=0.25 out=0.25 |
| l5b | cuts/s4_dial.mp4 | cont |  | line |  | that rotate the texture around its centre a little more every frame, so the whole swirl turns. |  |
| l6 | cuts/s5_orbit.mp4 | 0 |  | line |  | What do you think? Should I keep this in or not? |  |
| l7 | cuts/s6_runner.mp4 | 0 |  | line |  | Let me know what else you think I should add in the comments, and it just might make it into the final game! |  |
