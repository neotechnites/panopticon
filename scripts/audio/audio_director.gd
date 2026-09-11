class_name AudioDirector
extends Node

## Plays events. The only object in PANOPTICON that starts a sound.
##
## Gameplay posts a name from [AudioEvents]; the director looks it up in its
## [AudioBank], decides whether the sound is placed in the world, borrows a
## voice from a fixed pool and plays it. Nothing upstream of this file knows a
## filename, a bus or a volume, and nothing upstream of it can be broken by
## there being no sound card, no bank, or no director at all.
##
## [codeblock]
## AudioDirector.post_event_at(AudioEvents.RIFLE_FIRED, origin)
## AudioDirector.post_event(AudioEvents.RIFLE_RELOAD_FINISHED)
## [/codeblock]
##
## [b]Why static posters and not an autoload.[/b] project.godot is edited by
## several agents at once and an autoload entry is a merge conflict with a
## silent failure mode. Instead the director registers itself in a static field
## on entering the tree, exactly as [SettingsStore] does, and
## [method post_event] is a no-op when that field is null. The consequence is
## the property the bot harness needs: a scene with no
## res://scenes/audio/audio_director.tscn in it is not a scene with broken
## audio, it is a scene with no audio, and it costs nothing to run.
##
## [b]Three ways this stays free when it should be.[/b]
## [codeblock]
##   no director in the scene  -> post_event() returns false, nothing allocated
##   Activation.AUTO, headless -> disabled at _enter_tree, no voices ever built
##   Activation.NEVER          -> same, on any platform
## [/codeblock]
## The harness under tools/harness/ runs thousands of matches with no display
## and no audio device. Under [constant Activation.AUTO] the director notices
## and switches itself off, so those runs pay for nothing and, more importantly,
## cannot emit a single audio error into a transcript that is being parsed for
## results.
##
## [b]The voice pool is a cap, not a suggestion.[/b] At most [member max_voices]
## players exist and at most that many sounds are audible. Over the cap, the
## oldest sounding voice is stolen. Combined with the same-frame guard on
## [member AudioCue.allow_same_frame], the worst case for a frame that posts a
## thousand events is [member max_voices] nodes and one play call per distinct
## event.
##
## Deliberately absent, and not planned: mixing states, reverb zones, occlusion,
## dynamic music, ducking.

## Emitted after a sound actually starts. [param positional] is what the
## director decided, not what the caller asked for. For debug overlays and for
## checks; nothing in the game listens.
signal event_played(event: StringName, positional: bool)

## Emitted the first time an event is posted that the bank has no cue for.
## Once per name per director, so a per-frame post cannot spam.
signal event_unmapped(event: StringName)

## Emitted when [method is_enabled] changes, including at startup.
signal enabled_changed(now_enabled: bool)


## When the system is allowed to make noise.
enum Activation {
	## Enabled unless this looks like a headless or explicitly silenced run.
	## The right setting for a scene that ships.
	AUTO,
	## Enabled regardless. For a verification check that needs voices to exist
	## on a machine with no audio device.
	ALWAYS,
	## Disabled regardless. The kill switch.
	NEVER,
}

## Ceiling on simultaneous sounds, and therefore on player nodes.
const DEFAULT_MAX_VOICES: int = 24

## Assumed duration for a stream that will not report its own length. Long
## enough not to cut a real sound short, short enough that a pool cannot be
## deadlocked by a handful of them.
const FALLBACK_VOICE_SECONDS: float = 2.0

## Floor on how long a voice is held, so a very short sample at a high pitch
## still occupies its slot for a measurable moment.
const MIN_VOICE_SECONDS: float = 0.05

## Milliseconds after [method AudioVoice.start] during which a voice is held
## even if the driver says it is not playing. See [method AudioVoice.is_spent].
const VOICE_GRACE_MSEC: int = 120

## The bus every cue falls back to when its own bus is not in the layout. Index
## 0 always exists.
const FALLBACK_BUS: StringName = &"Master"

## [method DisplayServer.get_name] under [code]--headless[/code].
const HEADLESS_DISPLAY: String = "headless"

## Passed after [code]--[/code] on the command line to force the system off:
## [code]godot --path . -- --no-audio[/code].
const SILENCE_FLAG: String = "--no-audio"

## Where event names come from. Assign the shipping bank in the inspector; a
## director with no bank is legal and silent.
@export var bank: AudioBank = null

## Optional pre-crushed twin of [member bank], served while [method set_crush] is
## on. game_audio.tscn wires the 22.05 kHz 8-bit twin; the SFX bus effects add the rest.
@export var crushed_bank: AudioBank = null

## When this director is allowed to play. See [enum Activation].
##
## The setter defers to [method _enter_tree] while the node is outside the tree:
## a property initialiser and a scene-load property write both run before the
## other members of this script have been initialised, and re-evaluating
## enablement against a half-built object is how a setter turns into a crash on
## load.
@export var activation: Activation = Activation.AUTO:
	set(value):
		activation = value
		if is_inside_tree():
			_refresh_enabled()

## Ceiling on simultaneous voices.
@export_range(1, 128, 1) var max_voices: int = DEFAULT_MAX_VOICES

## Print a warning the first time an event with no cue is posted. Off by
## default: an unmapped event is the expected state of a project whose audio has
## not been commissioned, and a headless transcript must stay clean. Listen to
## [signal event_unmapped] instead when you want to know.
@export var warn_on_unmapped: bool = false

## The director that static posts reach. Null when no director is in the tree,
## which is the normal state of a bot-harness run.
static var _instance: AudioDirector = null
static var _crush: bool = false

var _voices: Array[AudioVoice] = []
var _enabled: bool = false

## Last [method Engine.get_process_frames] each event was played on. The
## same-frame guard.
var _last_frame: Dictionary[StringName, int] = {}

## Last [method Time.get_ticks_msec] each event was played at. The retrigger
## clock.
var _last_msec: Dictionary[StringName, int] = {}

## Event names already reported through [signal event_unmapped].
var _reported_unmapped: Dictionary[StringName, bool] = {}

## Bus names already reported as missing from the layout.
var _reported_bus: Dictionary[StringName, bool] = {}


# --- Static front door --------------------------------------------------------

## The director in the tree, or null.
##
## Callers do not normally need this: [method post_event] already tolerates
## null. It is here for a check that wants to inspect the pool.
static func instance() -> AudioDirector:
	return _instance


## Play [param event] with no position. Returns true when a sound started.
##
## Safe with no director, no bank, no cue, no stream and no audio device. Every
## one of those returns false and does nothing else.
static func post_event(event: StringName) -> bool:
	if _instance == null:
		return false
	return _instance.post(event)


## Play [param event] at [param world_position]. Whether the position is
## honoured is the cue's decision -- see [member AudioCue.positional] -- so a
## call site that knows where something happened can always say so.
static func post_event_at(event: StringName, world_position: Vector3) -> bool:
	if _instance == null:
		return false
	return _instance.post_at(event, world_position)


## Static form of [method post_at_gain].
static func post_event_at_gain(event: StringName, world_position: Vector3, gain_db: float) -> bool:
	if _instance == null:
		return false
	return _instance.post_at_gain(event, world_position, gain_db)


# --- Lifecycle ----------------------------------------------------------------

func _enter_tree() -> void:
	# First director in wins. A second one in the same tree is a scene-assembly
	# mistake; it still works as an object, it simply is not the one the static
	# posts reach, and saying so once is more useful than either crashing or
	# silently swapping the target out from under the first.
	if _instance == null:
		_instance = self
	elif _instance != self:
		push_warning("AudioDirector: a director is already registered; %s will not receive static posts." % get_path())
	_refresh_enabled()


func _exit_tree() -> void:
	_release_all()
	if _instance == self:
		_instance = null


## Reclaims spent voices, and switches itself off once nothing is sounding.
##
## The pool is kept across the silence -- reallocating a handful of player nodes
## every time the ring goes quiet would be churn for nothing -- but the per-frame
## tick is not: a director that has played one sound and gone quiet costs the
## same as one that has never played anything. [method _play] turns it back on.
func _process(_delta: float) -> void:
	_reclaim()
	if get_active_voice_count() == 0:
		set_process(false)


# --- Posting ------------------------------------------------------------------

## Play [param event] flat. See [method post_event].
## Enable every effect on the SFX bus (the PS1 crush) and, where a director
## has a [member crushed_bank], serve that instead of [member bank].
static func set_crush(on: bool) -> void:
	_crush = on
	var bus: int = AudioServer.get_bus_index(&"SFX")
	if bus < 0:
		return
	for i in AudioServer.get_bus_effect_count(bus):
		AudioServer.set_bus_effect_enabled(bus, i, on)


## True when every effect on the SFX bus is enabled (and there is at least one).
static func is_bus_crushed() -> bool:
	var bus: int = AudioServer.get_bus_index(&"SFX")
	if bus < 0 or AudioServer.get_bus_effect_count(bus) == 0:
		return false
	for i in AudioServer.get_bus_effect_count(bus):
		if not AudioServer.is_bus_effect_enabled(bus, i):
			return false
	return true


static func is_crush() -> bool:
	return _crush


## The bank posts are served from right now.
func active_bank() -> AudioBank:
	if _crush and crushed_bank != null:
		return crushed_bank
	return bank


func post(event: StringName) -> bool:
	return _play(event, false, Vector3.ZERO)


## Play [param event] at [param world_position] if its cue is positional, flat
## otherwise. See [method post_event_at].
func post_at(event: StringName, world_position: Vector3) -> bool:
	return _play(event, true, world_position)


## Like [method post_at], but [param gain_db] is added to the cue's own
## [member AudioCue.volume_db] for this one play. For a caller that has a
## magnitude to express -- [MovementAudioListener] uses it to make a heavy
## landing louder than a light one off the same [constant AudioEvents.MOVEMENT_LAND]
## cue, rather than needing one cue per impact tier.
func post_at_gain(event: StringName, world_position: Vector3, gain_db: float) -> bool:
	return _play(event, true, world_position, gain_db)


func _play(event: StringName, have_position: bool, world_position: Vector3, gain_db: float = 0.0) -> bool:
	if not _enabled:
		return false
	var active: AudioBank = active_bank()
	if active == null:
		return false

	var cue: AudioCue = active.get_cue(event)
	if cue == null:
		_report_unmapped(event)
		return false
	if not cue.is_playable():
		# A cue with no stream is a documented silence, not a gap. Nothing is
		# reported: this is the shipping state of most of the bank.
		return false
	if not _passes_limits(event, cue):
		return false

	var positional: bool = cue.positional and have_position
	var voice: AudioVoice = _take_voice(positional)
	if voice == null:
		return false

	var pitch: float = cue.roll_pitch()
	voice.configure(cue, _resolve_bus(cue.bus), pitch, gain_db)
	if positional:
		voice.set_world_position(world_position)
	voice.start(event, cue.voice_seconds(pitch))

	_last_frame[event] = Engine.get_process_frames()
	_last_msec[event] = Time.get_ticks_msec()
	set_process(true)
	event_played.emit(event, positional)
	return true


## The two anti-stacking rules, in order of cheapness.
func _passes_limits(event: StringName, cue: AudioCue) -> bool:
	if not cue.allow_same_frame:
		var frame: int = Engine.get_process_frames()
		if _last_frame.get(event, -1) == frame:
			return false
	if cue.min_retrigger_seconds > 0.0:
		var now: int = Time.get_ticks_msec()
		var last: int = _last_msec.get(event, -1000000)
		if now - last < int(cue.min_retrigger_seconds * 1000.0):
			return false
	return true


# --- Voices -------------------------------------------------------------------

## A voice of the requested kind, or null if the pool refuses.
##
## Order: reclaim what is finished, reuse a free slot, grow the pool if it is
## under the cap, and only then steal. Stealing takes the oldest sounding voice,
## which is the one with the least of itself left to lose.
func _take_voice(positional: bool) -> AudioVoice:
	_reclaim()

	for voice: AudioVoice in _voices:
		if not voice.active:
			voice.ensure_kind(self, positional)
			return voice

	if _voices.size() < max_voices:
		var fresh: AudioVoice = AudioVoice.new()
		fresh.ensure_kind(self, positional)
		_voices.append(fresh)
		return fresh

	var oldest: AudioVoice = null
	for voice: AudioVoice in _voices:
		if oldest == null or voice.started_msec < oldest.started_msec:
			oldest = voice
	if oldest == null:
		return null
	oldest.stop()
	oldest.ensure_kind(self, positional)
	return oldest


## Mark finished voices free. Cheap enough to run on every post as well as every
## frame, which is what keeps a single-frame burst from stealing voices that
## were already over.
func _reclaim() -> void:
	var now: int = Time.get_ticks_msec()
	for voice: AudioVoice in _voices:
		if voice.active and voice.is_spent(now, VOICE_GRACE_MSEC):
			voice.stop()


## Silence everything without giving up the pool.
func stop_all() -> void:
	for voice: AudioVoice in _voices:
		voice.stop()


func _release_all() -> void:
	for voice: AudioVoice in _voices:
		voice.release()
	_voices.clear()
	set_process(false)


# --- Enablement ---------------------------------------------------------------

## True when a post can currently start a sound.
func is_enabled() -> bool:
	return _enabled


## Force the system on or off at runtime. Equivalent to setting
## [member activation] to [constant Activation.ALWAYS] or
## [constant Activation.NEVER]; the AUTO decision is not recoverable through
## this, set [member activation] directly for that.
func set_enabled(value: bool) -> void:
	activation = Activation.ALWAYS if value else Activation.NEVER


## Re-evaluate [constant Activation.AUTO] against the current environment.
## Called on entering the tree and whenever [member activation] is written.
func _refresh_enabled() -> void:
	var was: bool = _enabled
	_enabled = _should_be_enabled()
	if _enabled == was:
		return
	if not _enabled:
		# Free the nodes rather than just silencing them: a director switched
		# off mid-run should cost what a director that was never on costs.
		_release_all()
	enabled_changed.emit(_enabled)


func _should_be_enabled() -> bool:
	match activation:
		Activation.ALWAYS:
			return true
		Activation.NEVER:
			return false
	return not is_silent_environment()


## True when this process has no business making noise: a headless run, or one
## launched with [constant SILENCE_FLAG].
##
## Checked rather than assumed because the bot harness and the verification
## scripts both run through [code]--headless[/code], where the audio driver is a
## dummy: playing into it is not an error, but it is work done for nobody, and
## every voice is a node the harness has to tick.
static func is_silent_environment() -> bool:
	if OS.get_cmdline_user_args().has(SILENCE_FLAG):
		return true
	return DisplayServer.get_name() == HEADLESS_DISPLAY


# --- Buses --------------------------------------------------------------------

## [param bus] if the layout has it, [constant FALLBACK_BUS] if it does not.
##
## Assigning a bus name the layout does not contain is an engine error, and a
## project that has lost its default_bus_layout.tres should go quiet on Master
## rather than fill a log. Reported once per name.
func _resolve_bus(bus: StringName) -> StringName:
	if AudioServer.get_bus_index(bus) >= 0:
		return bus
	if not _reported_bus.has(bus):
		_reported_bus[bus] = true
		push_warning("AudioDirector: no audio bus named '%s'; falling back to '%s'." % [bus, FALLBACK_BUS])
	return FALLBACK_BUS


func _report_unmapped(event: StringName) -> void:
	if _reported_unmapped.has(event):
		return
	_reported_unmapped[event] = true
	event_unmapped.emit(event)
	if warn_on_unmapped:
		push_warning("AudioDirector: no cue for event '%s'." % event)


# --- Introspection ------------------------------------------------------------
#
# Everything below exists so a headless check can assert on the pool without a
# viewport, a listener or a sound card. None of it is used by the game.

## Player nodes currently allocated. Never exceeds [member max_voices].
func get_voice_count() -> int:
	return _voices.size()


## Voices currently sounding.
func get_active_voice_count() -> int:
	var count: int = 0
	for voice: AudioVoice in _voices:
		if voice.active:
			count += 1
	return count


## Sounding voices that are placed in the world.
func get_active_positional_count() -> int:
	var count: int = 0
	for voice: AudioVoice in _voices:
		if voice.active and voice.is_positional():
			count += 1
	return count


## Sounding voices that are not placed in the world.
func get_active_flat_count() -> int:
	return get_active_voice_count() - get_active_positional_count()


## The events currently sounding, in pool order.
func get_active_events() -> Array[StringName]:
	var events: Array[StringName] = []
	for voice: AudioVoice in _voices:
		if voice.active:
			events.append(voice.event)
	return events


## Where the sounding positional voices are.
func get_active_positions() -> PackedVector3Array:
	var points: PackedVector3Array = PackedVector3Array()
	for voice: AudioVoice in _voices:
		if voice.active and voice.is_positional():
			points.append(voice.get_world_position())
	return points


## The bus a sounding voice was routed to, or an empty name if [param index] is
## not a sounding voice. Index is into the sounding voices, in pool order.
func get_active_bus(index: int) -> StringName:
	var seen: int = 0
	for voice: AudioVoice in _voices:
		if not voice.active:
			continue
		if seen == index:
			if voice.spatial != null:
				return voice.spatial.bus
			if voice.flat != null:
				return voice.flat.bus
			return &""
		seen += 1
	return &""


## The configured [code]volume_db[/code] of a sounding voice -- the cue's own
## trim plus whatever [method post_at_gain] added -- or 0.0 if [param index] is
## not a sounding voice. Index is into the sounding voices, in pool order, same
## as [method get_active_bus]. For a check that wants to see a gain-scaled post
## actually land on the node.
func get_active_volume_db(index: int) -> float:
	var seen: int = 0
	for voice: AudioVoice in _voices:
		if not voice.active:
			continue
		if seen == index:
			if voice.spatial != null:
				return voice.spatial.volume_db
			if voice.flat != null:
				return voice.flat.volume_db
			return 0.0
		seen += 1
	return 0.0


## Clear the same-frame and retrigger history. For a check that wants to post
## the same event twice without waiting a frame.
func clear_rate_limits() -> void:
	_last_frame.clear()
	_last_msec.clear()


func _to_string() -> String:
	var state: String = "enabled" if _enabled else "disabled"
	return "AudioDirector(%s, %d/%d voices)" % [state, get_active_voice_count(), max_voices]
