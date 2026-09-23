extends CPUParticles3D

## Nether-portal motes: this emitter swirls across the opening, Drawn is pulled in from round the frame.
## Each portal scene sets [member color] here; ready hands it to the child emitters.

func _ready() -> void:
	for child: Node in get_children():
		var emitter := child as CPUParticles3D
		if emitter != null:
			emitter.color = color
