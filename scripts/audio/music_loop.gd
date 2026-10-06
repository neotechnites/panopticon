extends AudioStreamPlayer

## Loops its stream. A local track in UNLICENSED_DIR (gitignored) replaces it when present,
## chosen by [member track_file] or else by the match's map id; missing files keep the default.

const UNLICENSED_DIR: String = "res://audio/music/unlicensed/"
const MAP_TRACKS: Dictionary = {
	&"bentham_ring": "spicy_miso.mp3",
	&"marble": "xp1406.mp3",
	&"forest": "regeneration.mp3",
}

@export var track_file: String = ""


func _ready() -> void:
	var local: AudioStream = _local_track()
	if local != null:
		stream = local
	if stream is AudioStreamOggVorbis:
		(stream as AudioStreamOggVorbis).loop = true
	elif stream is AudioStreamMP3:
		(stream as AudioStreamMP3).loop = true
	if not playing or local != null:
		play()


func _local_track() -> AudioStream:
	var file: String = track_file
	if file.is_empty():
		var controller: MatchController = get_node_or_null(^"../MatchController") as MatchController
		if controller == null or controller.get_rules() == null:
			return null
		file = MAP_TRACKS.get(controller.get_rules().map_id, "")
	if file.is_empty() or not ResourceLoader.exists(UNLICENSED_DIR + file):
		return null
	return load(UNLICENSED_DIR + file) as AudioStream
