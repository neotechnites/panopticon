class_name AudioBank
extends Resource

## The map from event name to sound. [b]The only thing in PANOPTICON that knows
## a filename.[/b]
##
## A bank is a saved [Resource] holding a list of [AudioCue]s. [AudioDirector]
## looks names up in it and plays what it finds; gameplay code never touches
## one. The shipping bank is res://scenes/audio/placeholder_bank.tres.
##
## [b]Swapping in real audio[/b]
##
## [codeblock]
##   1. Put the file in res://assets/audio/ and let Godot import it.
##   2. Open scenes/audio/placeholder_bank.tres in the inspector.
##   3. Find the cue whose "event" is the one you are replacing.
##   4. Drag the new file onto that cue's "stream". Save.
## [/codeblock]
##
## Nothing else changes. No script is edited, no scene is touched, and the
## placeholder .wav can be deleted once every cue that referenced it has been
## repointed. Adding a wholly new sound is one more cue plus one more constant
## in [AudioEvents] plus a line in whichever listener knows when it happens.
##
## [b]Why the lookup is built lazily.[/b] A [Resource] has no [code]_ready[/code]
## and may be constructed by the inspector, by [method @GDScript.load], or by a
## test with [code]AudioBank.new()[/code], and it may be edited after any of
## them. Building the index on first use and letting [method rebuild_index]
## force it is the only version of this that is correct in all four cases.

## Every cue this bank carries. Order is presentation only; lookup is by
## [member AudioCue.event].
@export var cues: Array[AudioCue] = []

## Lazily built name -> cue map. Not exported: it is derived from [member cues]
## and saving it would let the two disagree.
var _index: Dictionary[StringName, AudioCue] = {}
var _indexed: bool = false


## The cue for [param event], or null when the bank has no entry for it.
##
## Null is a normal answer, not a failure: see [member AudioCue.stream].
func get_cue(event: StringName) -> AudioCue:
	if not _indexed:
		rebuild_index()
	return _index.get(event, null) as AudioCue


## True when the bank has a cue for [param event], whether or not that cue has a
## stream behind it.
func has_event(event: StringName) -> bool:
	return get_cue(event) != null


## True when the bank has a cue for [param event] [i]and[/i] that cue can make a
## sound. This is the question worth asking before reporting a gap.
func can_play(event: StringName) -> bool:
	var cue: AudioCue = get_cue(event)
	return cue != null and cue.is_playable()


## Every event name in the bank, in [member cues] order.
func event_names() -> Array[StringName]:
	var names: Array[StringName] = []
	for cue: AudioCue in cues:
		if cue != null and cue.event != &"":
			names.append(cue.event)
	return names


## The [constant AudioEvents.ALL] entries this bank has no cue for. Empty means
## complete. A verification check asserts on this; a completeness gap is a
## content gap, not a crash.
func missing_events() -> Array[StringName]:
	var missing: Array[StringName] = []
	for event: StringName in AudioEvents.ALL:
		if not has_event(event):
			missing.append(event)
	return missing


## The cues that are present but silent -- an event that is wired end to end and
## simply has nothing to play yet. This is the report that says how much audio
## still needs commissioning.
func silent_events() -> Array[StringName]:
	var silent: Array[StringName] = []
	for cue: AudioCue in cues:
		if cue != null and cue.event != &"" and not cue.is_playable():
			silent.append(cue.event)
	return silent


## Add or replace the cue for [code]cue.event[/code]. Used by the placeholder
## forge and by tests; the inspector edits [member cues] directly.
func put_cue(cue: AudioCue) -> void:
	if cue == null or cue.event == &"":
		return
	for i: int in cues.size():
		if cues[i] != null and cues[i].event == cue.event:
			cues[i] = cue
			rebuild_index()
			return
	cues.append(cue)
	rebuild_index()


## Rebuild the name lookup from [member cues]. Call after mutating the array by
## hand; [method get_cue] calls it once on its own before the first read.
##
## A duplicate event name keeps the [i]first[/i] cue, so a bank that has been
## hand-edited into an ambiguous state behaves the same on every run instead of
## depending on dictionary insertion luck.
func rebuild_index() -> void:
	_index.clear()
	for cue: AudioCue in cues:
		if cue == null or cue.event == &"":
			continue
		if not _index.has(cue.event):
			_index[cue.event] = cue
	_indexed = true


func _to_string() -> String:
	return "AudioBank(%d cues, %d silent)" % [cues.size(), silent_events().size()]
