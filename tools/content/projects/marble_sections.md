# marble_sections
kind: trailer
aspect: 16:9
size: 1920x1080
format: proof takes for the marble four-section blockout (branch marble-four-sections); the trailer's four marble cameras as before/after pairs, then the sections down a runner's eyes.
## 5hr
said: before/after of trailer_reveal 5hr with the four sections: v60 refilm of 5h: the marble scope shot, Movie Maker so the round's flight does not stall (v59 913-995; Ryan note 1)
capture: --map=marble --shot=pack_lead --stage=trailer_marble_track --bots=3 --pov=guard --hud=crosshair --rifle=projectile --set=fire=2.6 --seed=20261001 --tape=res://tools/content/projects/trailer_reveal/tapes/marble_hit.json
seconds: 3.15
in: 1.8666
freeze: waive
expect: hit Runner_1 2.94-3.00
at: 6d3bcfe1

## 10ar
said: before/after of trailer_reveal 10ar with the four sections: v60 refilm of 10a: the marble runner (v59 1717-1851)
capture: --map=marble --shot=pack_lead --stage=trailer_marble_column --bots=2 --pov=runner --rifle=projectile --set=late=1;lead=1.0;now=1;back_fire=0.1;kick=0.1;back_pace=0.5;follow=0.4;run_after=0.9;settle_omega=45;max_rate=55 --seed=20261001 --tape=res://tools/content/projects/trailer_reveal/tapes/marble_column.json
seconds: 4.0
in: 0.75
freeze: waive
expect: shove Runner_2 2.97-3.03
at: 6d3bcfe1

## 10br
said: before/after of trailer_reveal 10br with the four sections: v60 refilm of 10b: the scope as the victim is hit (v59 1852-2009)
capture: --map=marble --shot=pack_lead --stage=trailer_marble_column --bots=2 --pov=guard --hud=crosshair --rifle=projectile --set=late=1;lead=1.0;now=1;back_fire=0.1;kick=0.1;back_pace=0.5;follow=0.4;run_after=0.9;settle_omega=45;max_rate=55 --seed=20261001 --tape=res://tools/content/projects/trailer_reveal/tapes/marble_column.json
seconds: 4.4
in: 1.75
freeze: waive
expect: shove Runner_2 2.97-3.03; hit Runner_1 4.94-5.00
at: 6d3bcfe1

## 12sr
said: before/after of trailer_reveal 12sr with the four sections: v60 refilm of 12s: the marble half of the portal run, the first-person shove, the guard thrown with his rifle (v59 2094-2316; Ryan notes 5, 6)
capture: --map=marble --shot=portal --stage=trailer_finale_marble --bots=2 --pov=runner --rifle=projectile --set=wait=0.25;from=311,52.4 --seed=20261001 --tape=res://tools/content/projects/trailer_reveal/tapes/finale_fp.json
seconds: 5.55
in: 1.1666
freeze: waive
expect: stage arrived 3.57-3.63; stage kill 4.45-4.51
at: 6d3bcfe1

## 1
said: Section A: a runner shoves the activator behind the wall; the runner ahead on the trapdoor drops
capture: --map=marble --shot=pack_lead --stage=marble_sections --pov=runner --bots=3 --seed=20261001 --set=beat=a
seconds: 10
in: 0.9
freeze: waive
expect: out Runner_2 4.0-4.9

## 2
said: Section B: the rifle hits the wall-top activator ahead of the runner; he sees the hit, never the tower
capture: --map=marble --shot=pack_lead --stage=marble_sections --pov=runner --bots=3 --seed=20261001 --set=beat=b
seconds: 10
in: 0.9
freeze: waive
expect: hit PlateHitbox 3.45-3.70; alive Runner_1

## 3
said: Section C: a runner walks the buttresses
capture: --map=marble --shot=pack_lead --stage=marble_sections --pov=runner --bots=3 --seed=20261001 --set=beat=c
seconds: 10
in: 0.9
freeze: waive
expect: alive Runner_1

## 4
said: Section D: a runner walks and hops through the column forest
capture: --map=marble --shot=pack_lead --stage=marble_sections --pov=runner --bots=3 --seed=20261001 --set=beat=d
seconds: 10
in: 0.9
freeze: waive
expect: alive Runner_1

