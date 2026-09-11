class_name AudioVoice
extends RefCounted

## One slot in [AudioDirector]'s voice pool: a player node plus the bookkeeping
## needed to reclaim it.
##
## [b]Why a wrapper and not just the player node.[/b] A voice has to be able to
## be either flat or positional, because the pool is capped as a whole -- a
## burst of UI clicks must not be able to starve the rifle by exhausting a
## separate 2D pool while the 3D pool sits idle. Two typed fields with exactly
## one of them non-null, rather than one [code]Node[/code] field, so every call
## through this file is statically resolved: an untyped [code]player.play()[/code]
## is an unsafe method access and this project compiles those as errors.
##
## [b]Why an expiry clock and not just [method AudioStreamPlayer.is_playing].[/b]
## Under [code]--headless[/code] Godot uses the dummy audio driver, whose
## playback does not advance the way a real device's does; a pool that waits for
## [signal AudioStreamPlayer.finished] there fills up and never drains. Voices
## are therefore reclaimed on whichever comes first: the driver reporting the
## sound over, or the wall clock passing the stream's own length. That makes the
## pool correct on a machine with no sound card, which is where the bot harness
## lives.

## The flat player, when this voice is non-positional. Null otherwise.
var flat: AudioStreamPlayer = null

## The world-placed player, when this voice is positional. Null otherwise.
var spatial: AudioStreamPlayer3D = null

## The event currently occupying this voice. Diagnostic; also what the
## same-frame guard reports.
var event: StringName = &""

## [method Time.get_ticks_msec] at the moment [method start] was called. The
## voice-stealing order is oldest first, and this is the "oldest".
var started_msec: int = 0

## [method Time.get_ticks_msec] after which this voice is considered spent even
## if the driver has not said so.
var expires_msec: int = 0

## True between [method start] and reclamation. The director counts these, not
## the allocated nodes.
var active: bool = false


## True when this voice currently owns a positional player.
func is_positional() -> bool:
	return spatial != null


## Make this voice hold a player of the requested kind, parented to
## [param parent], creating or swapping one as needed.
##
## Swapping frees the wrong-kind node rather than keeping both, because keeping
## both would double the node count of a pool whose entire purpose is to bound
## it. A swap only happens when a voice is stolen for a different kind of sound,
## which at a 24-voice cap is rare.
##
## [param parent] may be a plain [Node]: an [AudioStreamPlayer3D] under a
## non-[Node3D] parent has an identity parent transform, so its
## [member Node3D.global_position] is simply world space, which is exactly what
## a director that lives at the top of a scene wants.
func ensure_kind(parent: Node, want_positional: bool) -> void:
	if want_positional:
		if flat != null:
			flat.queue_free()
			flat = null
		if spatial == null:
			spatial = AudioStreamPlayer3D.new()
			spatial.name = "Voice3D"
			parent.add_child(spatial)
		return
	if spatial != null:
		spatial.queue_free()
		spatial = null
	if flat == null:
		flat = AudioStreamPlayer.new()
		flat.name = "Voice"
		parent.add_child(flat)


## Load [param cue] into whichever player this voice holds.
##
## [param bus_index] is resolved by the director, not here, so a missing bus is
## reported once by the thing that owns the mixing rather than once per voice.
##
## [param gain_db] is added on top of [member AudioCue.volume_db] and defaults to
## 0.0 -- no change. It exists for [method AudioDirector.post_at_gain]: a caller
## that has a magnitude to express for THIS ONE play (an impact speed, a charge
## level) and does not want a family of near-duplicate cues in the bank just to
## express it.
func configure(cue: AudioCue, bus_name: StringName, pitch: float, gain_db: float = 0.0) -> void:
	if spatial != null:
		spatial.stream = cue.stream
		spatial.bus = bus_name
		spatial.volume_db = cue.volume_db + gain_db
		spatial.pitch_scale = pitch
		spatial.max_distance = cue.max_distance
		spatial.unit_size = cue.unit_size
		spatial.attenuation_model = cue.attenuation_model
		spatial.panning_strength = cue.panning_strength
		return
	if flat != null:
		flat.stream = cue.stream
		flat.bus = bus_name
		flat.volume_db = cue.volume_db + gain_db
		flat.pitch_scale = pitch


## Place a positional voice. A no-op on a flat one, which is the whole point of
## the flat/positional split being decided by the cue: the call site can hand a
## position over unconditionally and the cue decides whether it matters.
func set_world_position(world_position: Vector3) -> void:
	if spatial != null:
		spatial.global_position = world_position


## Where a positional voice is. [constant Vector3.ZERO] for a flat one.
func get_world_position() -> Vector3:
	if spatial != null:
		return spatial.global_position
	return Vector3.ZERO


## Begin playback and arm the expiry clock.
func start(from_event: StringName, seconds: float) -> void:
	event = from_event
	started_msec = Time.get_ticks_msec()
	expires_msec = started_msec + int(ceilf(maxf(seconds, 0.0) * 1000.0))
	active = true
	if spatial != null:
		spatial.play()
	elif flat != null:
		flat.play()


## Stop playback and free the slot. Idempotent.
func stop() -> void:
	active = false
	event = &""
	if spatial != null:
		spatial.stop()
	if flat != null:
		flat.stop()


## What the audio driver thinks. Not trusted on its own -- see the class docs.
func is_playing() -> bool:
	if spatial != null:
		return spatial.playing
	if flat != null:
		return flat.playing
	return false


## True when this voice should be handed back to the pool.
##
## [param grace_msec] exists because a player that has been told to play may not
## report [code]playing[/code] on the very same frame; without it a burst posted
## in one frame would reclaim its own voices immediately and the cap would be
## unobservable, which is a bug that hides a bug.
func is_spent(now_msec: int, grace_msec: int) -> bool:
	if not active:
		return true
	if now_msec >= expires_msec:
		return true
	return now_msec - started_msec > grace_msec and not is_playing()


## Free the player node. The voice object is unusable afterwards.
func release() -> void:
	stop()
	if spatial != null:
		spatial.queue_free()
		spatial = null
	if flat != null:
		flat.queue_free()
		flat = null
