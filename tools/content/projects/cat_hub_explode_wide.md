# cat_hub_explode_wide
kind: short
aspect: 16:9
size: 1920x1080
voice: no

## 1
said: Ryan (task #691): "also give me a horizontal version for twitter" / "without the caption": cat_hub_explode ## 3 as a 1920x1080 take (vertical fov unchanged). Ryan (task #688): "start a version of the clip where it has more breathing room, the walk up to the cat is the same, but we look at it for .5 seconds longer, we pick it up, wait half a second, pet it 6 times, spread across 2 seconds, look over into the pit, wait half a second, pet it twice more over .5 seconds, then throw it and it plays out the same". ## 2 with look_extra 0.5, lead 0.5, 6 pets over 2.0 s, the turn to the pit (measured off the body when the pets end, 0.4 s), 0.5 s, 2 pets over 0.5 s, throw 0.3 s after; blast over the pit (r 43.7), in frame; the cut ends on its last frame. n2 (Ryan: "all the angles you chose make the cats face unreadable ... the issue is the rotational angle"): yaw from the probed suns (75 deg up, from bearings 60 and 240): the cat at 3 deg r 47.6, picked up facing bearing 249 (face front-lit), a 24 deg turn left to 225 (still front-lit), blast over the pit at r 44.1.
capture: --shot=s3_open_lane --stage=cat_hub_explode --map=forest --pov=runner --bots=1 --shimmer=0 --seed=20261021 --set=side=-1;ahead=6;look_extra=0.5;lead=0.5;pets=6;span=2.0;pets2=2;span2=0.5;gap2=0.5;turn_s=0.4;wait2=0.25;cat_deg=3;cat_r=47.6;pet_yaw=250;throw_yaw=225;stop=2.6
expect: pickup Cat1 2.1-2.4; pet prompt; pet n1 +0.45-0.6; pet n6 +2.45-2.6; pet n8 +3.85-4.0; throw Cat1 +4.15-4.3; explode over_pit; explode in_frame +4.65-4.85; boom_end Cat1 +5.7-5.9; alive Runner_1; lens_cover <= 0.5
seconds: 7.39
in: 0.65
file: cat_forest_explode_long_wide
