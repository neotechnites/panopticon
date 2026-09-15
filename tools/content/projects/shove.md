# shove
kind: short
format: i-added-x
aspect: 9:16
voice: no
shots: mine (Claude's shot list, not Ryan's; his direction is the ryan: line)
ryan: lets make a short about the shove. start it with something like 'I added this to my game and it got 10x better'
hook: the "I added this to my game and it got 10x better" line is Ryan's, spoken or typed over shot 1 in post; nothing is burned into the shots

## 1
said: [mine] ghost POV chasing a running prisoner from behind, closing in, ends on the shove landing
capture: --pov=ghost --stage=ghostchase --shot=s3_chase --bots=7 --look=social --audio=near --seed=20260930
file: 01_ghost_pov
in: 0.8
seconds: 5.5
gap: 0

## 2
said: [mine] third-person side view of the same shove: ghost hits runner, the swap happens, runner becomes ghost, ghost becomes runner; the swap must be visible
capture: --stage=ghostchase --shot=s3_chase --bots=7 --look=social --audio=near --seed=20260930
file: 02_swap_side
in: 1.5
seconds: 4.5
gap: 0

## 3
said: [mine] runner POV getting shoved from behind out of nowhere
capture: --pov=runner --stage=ghostchase --shot=s3_chase --bots=7 --look=social --audio=near --seed=20260930
file: 03_runner_pov
in: 2.0
seconds: 3.5
gap: 0

## 4
said: [mine] wide shot, a pack of runners with a ghost weaving between them and taking one
capture: --stage=ghostpack --shot=s1_pack --bots=7 --look=social --audio=near --seed=20260930
file: 04_pack_wide
in: 0.5
seconds: 5.5
gap: 0

## 5
said: [mine] guard POV from the tower watching the swap happen below through the scope
capture: --pov=guard --stage=ghostchase --shot=s3_chase --bots=7 --look=social --audio=near --seed=20260930
file: 05_guard_watch
in: 1.5
seconds: 3.5
motion: 0.005
gap: 0
