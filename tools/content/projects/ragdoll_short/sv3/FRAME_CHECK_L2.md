# FRAME_CHECK L2 (cuts/02_v23.mp4)
Checked at 5 fps (whole cut, 18 frames) and 10 fps over 0.3-1.5 s, against Ryan on v22: "when you show the death animation in a grey void, why the fuck is the character rendered how it is in game???" and "it should be an older build of the game to show the even worse art".
- Character: the 0fe0c9ec runner (544 tris), drawn as that build drew a runner: one flat unshaded orange, no face, no texture, no shading. Not today's prisoner model. PASS
- Animation: the pre-ragdoll Death clip from that build (0.4-1.1 s): he pitches forward and to the side, lands on stiff arms, flattens onto his front and stays down. No ragdoll. PASS
- Void: flat grey, no map, no horizon, no HUD, one continuous fixed lens; nothing spawns in frame. PASS
- Length 3.60 s; he stands 0.4 s before the clip and lies still 2.5 s after it, which is where v22's scared.gif fade (1.2 s, 2.0 s) sits. PASS
- Note: no visible floor shadow under him (the sun throws it behind him, out of the lens).
