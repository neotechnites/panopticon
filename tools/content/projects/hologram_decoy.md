# hologram_decoy
kind: short
format: i-added-x
aspect: 9:16
voice: yes

## 1
said: open from the deck behind the runner, he's crouched behind the pillar and throws the hologram out, hold on it running into the open. leave me three seconds of quiet after the shot lands, I'll say something like "so I added a decoy and the guard falls for it every time"
capture: --stage=decoy --shot=s3_pillar --bots=1 --look=social --audio=near
seconds: 5
gap: 3

## 2
said: now the guard's scope, the moment it fires at the hologram and it shatters
capture: --pov=guard --stage=decoy --shot=s3_pillar --bots=1 --look=social --audio=near
seconds: 5
motion: 0.01

## 3
said: last one from the runner, he stands up and just goes, caption it like a player would
capture: --pov=runner --stage=decoy --shot=s3_pillar --bots=1 --look=social --audio=near
in: 5
seconds: 4
caption: free lap
