class_name AudioCue
extends Resource

## One event name, and everything the engine needs to make a noise for it.
##
## A cue is the whole answer to "what does [code]weapon.rifle.fired[/code] sound
## like": which stream, which bus, how loud, how far it carries, whether it is
## placed in the world, and how often it is allowed to retrigger. Cues live in
## an [AudioBank]; nothing else in the project holds one.
##
## [b]This is the swap point.[/b] Replacing a placeholder with real audio is
## editing [member stream] on one cue -- open the bank, drop the file in, done.
## No code changes, no scene changes, and no gameplay file has ever known the
## name of the file it just replaced.
##
## Every field has a working default, so a cue with nothing but an
## [member event] and a [member stream] set is playable.

## The name gameplay posts. One of the constants in [AudioEvents], though a bank
## may carry cues for names that file has not heard of.
@export var event: StringName = &""

## What actually plays. [b]Leave it null and the cue is a documented silence[/b]:
## [method AudioDirector.post] returns false, allocates nothing and does not
## complain. That is the intended state for an event whose sound has not been
## commissioned, which today is most of them.
@export var stream: AudioStream = null

## The bus this plays on, resolved by name at play time against
## res://default_bus_layout.tres. [code]Effects[/code] and [code]Music[/code]
## both route into [code]Master[/code], so the master slider scales them rather
## than competing. A name the layout does not contain falls back to
## [code]Master[/code] rather than failing to play.
@export var bus: StringName = &"Effects"

## Trim, in decibels. Placeholders sit well below unity because they are
## synthesised tones and tones are fatiguing; real audio will mostly want
## something nearer 0.
@export_range(-60.0, 12.0, 0.1) var volume_db: float = -14.0

## Playback rate, and therefore pitch. 1.0 is the file as recorded.
@export_range(0.01, 4.0, 0.01) var pitch_scale: float = 1.0

## Random pitch spread applied per play, as a fraction of [member pitch_scale].
## 0.05 means +/- 5%. The cheapest possible defence against the machine-gun
## effect of an identical sample retriggering; costs nothing and needs no
## variant files.
@export_range(0.0, 0.5, 0.01) var pitch_jitter: float = 0.0

# --- Placement ----------------------------------------------------------------

## True to play through an [AudioStreamPlayer3D] at the position the caller
## supplied, false to play through a flat [AudioStreamPlayer].
##
## The cue decides this, not the call site: whether a sound belongs in the world
## is a mixing decision. A positional cue posted without a position (via
## [method AudioDirector.post] rather than [method AudioDirector.post_at]) plays
## flat rather than at the origin, because a sound at the world origin is a
## worse lie than a sound with no place.
@export var positional: bool = false

## Metres at which a positional cue is inaudible. The ring is roughly 120 m
## across, so the default deliberately exceeds it: a shot fired from the tower
## must be audible to a runner on the far lane, or the shot stops being a
## broadcast and the design stops working.
@export_range(1.0, 1000.0, 1.0) var max_distance: float = 200.0

## Metres over which a positional cue falls to roughly half. Larger values carry
## further before rolling off.
@export_range(0.1, 200.0, 0.1) var unit_size: float = 24.0

## How loudness falls with distance. Inverse-distance is the physical one and
## the right default for gunfire across an open ring.
@export var attenuation_model: AudioStreamPlayer3D.AttenuationModel = AudioStreamPlayer3D.ATTENUATION_INVERSE_DISTANCE

## How hard the stereo image swings with angle. Below 1.0 keeps a distant shot
## from vanishing into one ear.
@export_range(0.0, 3.0, 0.05) var panning_strength: float = 1.0

# --- Limits -------------------------------------------------------------------

## When false, a second post of this same event within a single frame is
## dropped. Two identical samples started on the same frame do not sound twice
## as loud, they sound like one sample 6 dB louder with a comb filter on it, and
## they cost two voices to do it.
##
## Set true only for a cue that is genuinely meant to layer.
@export var allow_same_frame: bool = false

## Minimum seconds between two plays of this event. 0.0 disables the limit.
## Distinct from [member allow_same_frame], which is a per-frame rule; this one
## is a clock, and is what stops a mouse dragged down a column of buttons from
## firing [constant AudioEvents.UI_FOCUS] thirty times.
@export_range(0.0, 5.0, 0.01) var min_retrigger_seconds: float = 0.0


## Seconds this cue will occupy a voice for, accounting for pitch. Used by
## [AudioDirector] to reclaim voices without depending on the audio driver
## reporting completion -- which a headless run's dummy driver does not reliably
## do, and which is the difference between a voice pool and a leak.
##
## Returns a conservative fallback when the stream cannot say how long it is.
func voice_seconds(effective_pitch: float) -> float:
	if stream == null:
		return 0.0
	var length: float = stream.get_length()
	if length <= 0.0:
		return AudioDirector.FALLBACK_VOICE_SECONDS
	var pitch: float = maxf(effective_pitch, 0.01)
	return maxf(length / pitch, AudioDirector.MIN_VOICE_SECONDS)


## [member pitch_scale] with [member pitch_jitter] applied.
func roll_pitch() -> float:
	if pitch_jitter <= 0.0:
		return pitch_scale
	return maxf(pitch_scale * randf_range(1.0 - pitch_jitter, 1.0 + pitch_jitter), 0.01)


## True when this cue can actually make a sound. A cue that cannot is not an
## error; see [member stream].
func is_playable() -> bool:
	return stream != null


func _to_string() -> String:
	var where: String = "3D" if positional else "flat"
	var what: String = "<no stream>" if stream == null else stream.resource_path
	return "AudioCue(%s %s bus=%s %s)" % [event, where, bus, what]
