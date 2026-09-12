extends AudioStreamPlayer

## Placeholder music: loops whatever stream it was given.

func _ready() -> void:
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	if not playing:
		play()
