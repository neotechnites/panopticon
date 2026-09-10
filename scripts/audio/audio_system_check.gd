extends SceneTree

## Proves the audio event system works, on a machine with no audio device.
##
## [codeblock]
## godot --headless --path . --script res://scripts/audio/audio_system_check.gd
## [/codeblock]
##
## Exits 0 when everything passes, 1 when anything fails. Every assertion below
## is one of the properties the system is supposed to have, and every one of
## them is a property that could plausibly break without anybody noticing:
##
## [codeblock]
##   the bank is complete and every placeholder is a real AudioStream
##   an event with no cue, and a cue with no stream, are silent no-ops
##   a mapped event resolves to its stream and lands on the right bus
##   positional cues are placed in the world, flat ones are not
##   the voice cap holds under a burst of hundreds of posts in one frame
##   the same sound cannot stack with itself inside one frame
##   a disabled director plays nothing and holds no nodes
##   with no director in the tree, posting is a no-op rather than a crash
##   the listeners turn real Rifle and MatchController signals into events
## [/codeblock]
##
## [b]The director is forced to [constant AudioDirector.Activation.ALWAYS][/b]
## for most of this, because under AUTO it would correctly switch itself off in
## a headless run and there would be no voices to assert on. The AUTO behaviour
## is itself one of the checks.
##
## Work happens in [method _process] rather than [method _initialize]: quitting
## from the latter exits before stdout is flushed, and a report nobody sees is
## worse than no report.

const BANK_PATH: String = "res://scenes/audio/placeholder_bank.tres"
const EXIT_OK: int = 0
const EXIT_FAILED: int = 1

## Small enough that a burst is guaranteed to hit it, large enough that hitting
## it is not the trivial case.
const CAP_UNDER_TEST: int = 6

## Frames to idle after the report before quitting.
##
## Not padding: [method Node.queue_free] is a deferred delete and the audio
## server releases a stopped playback on its next update, so a check that quits
## inside the frame it ran in exits with player nodes and stream playbacks still
## alive and Godot -- correctly -- reports them as leaks. Letting the tree turn
## over a few times first is the difference between a clean exit and a
## transcript full of teardown errors that have nothing to do with the code
## under test.
const FLUSH_FRAMES: int = 8

var _started: bool = false
var _flushed: int = 0
var _passed: int = 0
var _failed: int = 0

## Events seen through [signal AudioDirector.event_played] during one test.
var _heard: Array[StringName] = []


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
		return false
	if _flushed < FLUSH_FRAMES:
		_flushed += 1
		return false
	quit(EXIT_OK if _failed == 0 else EXIT_FAILED)
	return true


func _run() -> void:
	print("PANOPTICON audio system check")
	print("  display     %s" % DisplayServer.get_name())
	print("  audio buses %d" % AudioServer.bus_count)
	print("")

	_check_no_director()
	var bank: AudioBank = _check_bank()
	_check_placeholders(bank)
	_check_buses(bank)
	_check_resolution(bank)
	_check_missing_and_silent(bank)
	_check_placement(bank)
	_check_same_frame_guard(bank)
	_check_voice_cap(bank)
	_check_disabled(bank)
	_check_auto_is_off_headless(bank)
	_check_listeners(bank)

	print("")
	print("%s  passed=%d failed=%d" % ["CLEAN" if _failed == 0 else "DIRTY", _passed, _failed])


# --- Checks -------------------------------------------------------------------

## Posting with nothing in the tree must be a no-op, because that is the state
## every headless bot match runs in.
func _check_no_director() -> void:
	_section("no director in the tree")
	_ok("instance() is null", AudioDirector.instance() == null)
	_ok("post_event() returns false", not AudioDirector.post_event(AudioEvents.RIFLE_FIRED))
	_ok("post_event_at() returns false", not AudioDirector.post_event_at(AudioEvents.RIFLE_FIRED, Vector3(1, 2, 3)))


func _check_bank() -> AudioBank:
	_section("the bank loads")
	var bank: AudioBank = load(BANK_PATH) as AudioBank
	_ok("%s loads as an AudioBank" % BANK_PATH, bank != null)
	if bank == null:
		return AudioBank.new()
	_ok("carries %d cues" % bank.cues.size(), bank.cues.size() == AudioEvents.ALL.size())
	return bank


func _check_placeholders(bank: AudioBank) -> void:
	_section("the placeholder .wav files are real AudioStreams")
	var loaded: int = 0
	var total_seconds: float = 0.0
	for event: StringName in AudioEvents.ALL:
		if event == AudioEvents.MUSIC_MATCH_THEME:
			continue
		var cue: AudioCue = bank.get_cue(event)
		if cue == null or cue.stream == null:
			_ok("%s has a stream" % event, false)
			continue
		var wav: AudioStreamWAV = cue.stream as AudioStreamWAV
		if wav == null or wav.get_length() <= 0.0:
			_ok("%s is an AudioStreamWAV with length" % event, false)
			continue
		loaded += 1
		total_seconds += wav.get_length()
	_ok("%d/%d placeholders loaded, %.2fs total" % [loaded, AudioEvents.ALL.size() - 1, total_seconds],
		loaded == AudioEvents.ALL.size() - 1)


func _check_buses(bank: AudioBank) -> void:
	_section("buses resolve")
	_ok("Master exists", AudioServer.get_bus_index(&"Master") >= 0)
	_ok("Effects exists", AudioServer.get_bus_index(&"Effects") >= 0)
	_ok("Music exists", AudioServer.get_bus_index(&"Music") >= 0)
	var music: AudioCue = bank.get_cue(AudioEvents.MUSIC_MATCH_THEME)
	_ok("music.match_theme is routed to Music", music != null and music.bus == &"Music")


## A mapped event must resolve to its stream and reach the bus its cue names.
func _check_resolution(bank: AudioBank) -> void:
	_section("a mapped event resolves to its stream and its bus")
	var director: AudioDirector = _make_director(bank, 8)

	var cue: AudioCue = bank.get_cue(AudioEvents.RIFLE_FIRED)
	_ok("bank maps weapon.rifle.fired", cue != null)
	_ok("...to a stream", cue != null and cue.stream != null)
	_ok("...whose path is a placeholder", cue != null and cue.stream != null
		and cue.stream.resource_path.contains("placeholder_weapon_rifle_fired"))
	_ok("...on the Effects bus", cue != null and cue.bus == &"Effects")

	var played: bool = director.post_at(AudioEvents.RIFLE_FIRED, Vector3(10.0, 2.0, -30.0))
	_ok("posting it starts a voice", played)
	_ok("the voice is on Effects", director.get_active_bus(0) == &"Effects")

	_section("an event with nothing behind it is a silent no-op")
	_ok("an unmapped name returns false", not director.post(&"weapon.rifle.does_not_exist"))
	_ok("a cue with no stream returns false", not director.post(AudioEvents.MUSIC_MATCH_THEME))
	_ok("neither started a voice", director.get_active_voice_count() == 1)

	_drop(director)


func _check_missing_and_silent(bank: AudioBank) -> void:
	_section("the bank covers every declared event")
	var missing: Array[StringName] = bank.missing_events()
	_ok("no missing events (%s)" % ("none" if missing.is_empty() else ", ".join(missing)), missing.is_empty())
	var silent: Array[StringName] = bank.silent_events()
	_ok("only music.match_theme is silent (%s)" % ", ".join(silent),
		silent.size() == 1 and silent[0] == AudioEvents.MUSIC_MATCH_THEME)


## The design rests on a shot coming from where it was fired, and on the reload
## not being placed anywhere at all.
func _check_placement(bank: AudioBank) -> void:
	_section("positional and non-positional events are distinguished")
	var director: AudioDirector = _make_director(bank, 8)
	var where: Vector3 = Vector3(41.5, 3.0, -17.25)

	director.post_at(AudioEvents.RIFLE_FIRED, where)
	_ok("weapon.rifle.fired is positional", director.get_active_positional_count() == 1)
	var points: PackedVector3Array = director.get_active_positions()
	_ok("...at the position it was given (%s)" % points[0], points.size() == 1 and points[0].is_equal_approx(where))

	director.post(AudioEvents.RIFLE_RELOAD_FINISHED)
	_ok("weapon.rifle.reload_finished is flat", director.get_active_flat_count() == 1)

	# A positional cue posted WITHOUT a position must not be placed at the world
	# origin; a sound in the wrong place is worse than a sound in no place.
	director.clear_rate_limits()
	director.post(AudioEvents.RIFLE_HIT)
	_ok("a positional cue posted with no position plays flat", director.get_active_flat_count() == 2)

	# ...and a flat cue posted WITH one stays flat: the cue decides, not the
	# call site.
	director.clear_rate_limits()
	director.post_at(AudioEvents.RIFLE_RELOAD_STARTED, where)
	_ok("a flat cue posted with a position stays flat", director.get_active_positional_count() == 1)

	_drop(director)


func _check_same_frame_guard(bank: AudioBank) -> void:
	_section("identical sounds do not stack inside one frame")
	var director: AudioDirector = _make_director(bank, 8)
	var first: bool = director.post(AudioEvents.UI_CLICK)
	var second: bool = director.post(AudioEvents.UI_CLICK)
	var third: bool = director.post(AudioEvents.UI_CLICK)
	_ok("the first post plays", first)
	_ok("the second is dropped", not second)
	_ok("the third is dropped", not third)
	_ok("one voice, not three", director.get_active_voice_count() == 1)
	_drop(director)


func _check_voice_cap(bank: AudioBank) -> void:
	_section("the voice cap holds under a burst")
	var director: AudioDirector = _make_director(bank, CAP_UNDER_TEST)
	var posts: int = 0
	var started: int = 0
	for pass_index: int in 20:
		for event: StringName in AudioEvents.ALL:
			posts += 1
			# Positions spread over the ring, so the burst exercises the 3D path
			# and the flat path through the same capped pool.
			if AudioEvents.POSITIONAL.has(event):
				if director.post_at(event, Vector3(float(posts), 1.0, float(pass_index))):
					started += 1
			elif director.post(event):
				started += 1
	print("      %d posts -> %d plays" % [posts, started])
	_ok("allocated voices never exceeded the cap (%d <= %d)" % [director.get_voice_count(), CAP_UNDER_TEST],
		director.get_voice_count() <= CAP_UNDER_TEST)
	_ok("sounding voices never exceeded the cap (%d <= %d)" % [director.get_active_voice_count(), CAP_UNDER_TEST],
		director.get_active_voice_count() <= CAP_UNDER_TEST)
	_ok("the burst was throttled (%d plays from %d posts)" % [started, posts], started < posts)
	_drop(director)


func _check_disabled(bank: AudioBank) -> void:
	_section("the system can be disabled entirely")
	var director: AudioDirector = _make_director(bank, 8)
	director.post(AudioEvents.MATCH_STARTED)
	_ok("enabled, it plays", director.get_active_voice_count() == 1)

	director.set_enabled(false)
	_ok("disabled, is_enabled() is false", not director.is_enabled())
	_ok("...it holds no voices", director.get_voice_count() == 0)
	director.clear_rate_limits()
	_ok("...post() returns false", not director.post(AudioEvents.MATCH_STARTED))
	_ok("...post_at() returns false", not director.post_at(AudioEvents.RIFLE_FIRED, Vector3.ZERO))
	_ok("...the static front door returns false too", not AudioDirector.post_event(AudioEvents.MATCH_STARTED))
	_ok("...and nothing was allocated", director.get_voice_count() == 0)

	director.set_enabled(true)
	director.clear_rate_limits()
	_ok("re-enabled, it plays again", director.post(AudioEvents.MATCH_STARTED))
	_drop(director)


## The property the bot harness depends on: left on AUTO, the director notices
## it is running headless and switches itself off, so thousands of matches cost
## nothing and cannot emit an audio error into a parsed transcript.
func _check_auto_is_off_headless(bank: AudioBank) -> void:
	_section("AUTO switches itself off in a headless run")
	_ok("is_silent_environment() is true here", AudioDirector.is_silent_environment())
	var director: AudioDirector = AudioDirector.new()
	director.bank = bank
	director.activation = AudioDirector.Activation.AUTO
	root.add_child(director)
	_ok("the director is disabled", not director.is_enabled())
	_ok("posting does nothing", not director.post(AudioEvents.RIFLE_FIRED))
	_ok("no voices were allocated", director.get_voice_count() == 0)
	_drop(director)


## The listeners, against the real [Rifle] and [MatchController] signals.
##
## Both are built detached from the tree on purpose: neither runs its
## [method Node._ready] that way, so neither complains about the profile and the
## arena it has not been given, and the signals -- which is all this is testing
## -- are on the object regardless. If either script ever renames or re-signs
## one of these signals, this check stops compiling or stops hearing it.
func _check_listeners(bank: AudioBank) -> void:
	_section("the listeners turn real signals into events")
	var director: AudioDirector = _make_director(bank, 32)
	_heard.clear()
	director.event_played.connect(_on_event_played)

	var rifle: Rifle = Rifle.new()
	var controller: MatchController = MatchController.new()
	var listener: MatchAudioListener = MatchAudioListener.new()
	listener.director = director
	listener.rifle = rifle
	listener.controller = controller
	listener.auto_discover = false
	root.add_child(listener)
	listener._connect_all()

	var origin: Vector3 = Vector3(0.0, 12.0, 0.0)
	var impact: Vector3 = Vector3(-33.0, 1.0, 44.0)
	rifle.fired.emit(origin, impact)
	rifle.target_hit.emit(null, impact, Vector3.UP)
	rifle.missed.emit(impact)
	rifle.reload_started.emit(3.5)
	rifle.reload_finished.emit()
	controller.match_started.emit(4)
	controller.race_started.emit()
	controller.round_started.emit()
	controller.seat_changed.emit(null, 1)
	controller.round_resolved.emit(MatchController.Outcome.WIN)
	controller.runner_removed.emit(2)
	controller.match_won.emit(null)

	var expected: Array[StringName] = [
		AudioEvents.RIFLE_FIRED, AudioEvents.RIFLE_HIT, AudioEvents.RIFLE_MISSED,
		AudioEvents.RIFLE_RELOAD_STARTED, AudioEvents.RIFLE_RELOAD_FINISHED,
		AudioEvents.MATCH_STARTED, AudioEvents.RACE_STARTED, AudioEvents.ROUND_STARTED,
		AudioEvents.SEAT_CHANGED, AudioEvents.ROUND_RESOLVED, AudioEvents.RUNNER_CONVERTED,
		AudioEvents.MATCH_WON,
	]
	for event: StringName in expected:
		_ok("heard %s" % event, _heard.has(event))
	_ok("the three shot events were placed in the world", director.get_active_positional_count() == 3)
	var points: PackedVector3Array = director.get_active_positions()
	_ok("the report came from the shooter's position (%s)" % origin, points.has(origin))
	_ok("the impact came from the impact point (%s)" % impact, points.has(impact))

	# The UI listener, against a button it did not exist when the tree was built.
	var screen: Control = Control.new()
	root.add_child(screen)
	var ui: UIAudioListener = UIAudioListener.new()
	ui.director = director
	ui.root = screen
	screen.add_child(ui)
	var button: Button = Button.new()
	screen.add_child(button)
	button.pressed.emit()
	_ok("heard ui.click from a button added after the listener", _heard.has(AudioEvents.UI_CLICK))

	director.event_played.disconnect(_on_event_played)
	_drop(director)
	_drop(screen)
	listener.free()
	rifle.free()
	controller.free()


func _on_event_played(event: StringName, _positional: bool) -> void:
	_heard.append(event)


# --- Plumbing -----------------------------------------------------------------

## A director in the tree, forced on, with a known cap.
func _make_director(bank: AudioBank, cap: int) -> AudioDirector:
	var director: AudioDirector = AudioDirector.new()
	director.bank = bank
	director.max_voices = cap
	root.add_child(director)
	# After the tree, so the setter actually re-evaluates: see AudioDirector.
	director.activation = AudioDirector.Activation.ALWAYS
	return director


## Remove and free immediately rather than [method Node.queue_free], so the
## static registration is released before the next check builds its own
## director.
func _drop(node: Node) -> void:
	root.remove_child(node)
	node.free()


func _section(title: String) -> void:
	print("  %s" % title)


func _ok(what: String, passed: bool) -> void:
	if passed:
		_passed += 1
		print("    ok    %s" % what)
	else:
		_failed += 1
		print("    FAIL  %s" % what)
