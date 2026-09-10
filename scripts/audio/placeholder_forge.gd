extends SceneTree

## Generates the placeholder sound bank: one synthesised .wav per event, plus
## the [AudioBank] that maps names onto them.
##
## [b]These are not sound design and are not meant to survive.[/b] They are
## square waves and noise bursts, short and quiet and deliberately cheap
## sounding, and they exist for two reasons: so the event system can be proved
## to work end to end on a machine with no commissioned audio, and so the game
## is legible to play -- a shot you can hear from across the ring is worth more
## to a playtest than silence, even when the shot is a beep.
##
## [b]Running it[/b]
## [codeblock]
## # 1. write assets/audio/placeholder_*.wav
## godot --headless --path . --script res://scripts/audio/placeholder_forge.gd -- --wavs
## # 2. let Godot import what step 1 wrote
## godot --headless --path . --import
## # 3. build scenes/audio/placeholder_bank.tres against the imported streams
## godot --headless --path . --script res://scripts/audio/placeholder_forge.gd -- --bank
## [/codeblock]
## The three steps cannot be collapsed into one: [method @GDScript.load] cannot
## resolve a .wav the editor has not imported, so the bank must be built by a
## second process that starts after the import has run.
##
## [b]Step 3 overwrites the bank.[/b] Once real audio starts arriving, the bank
## is hand-edited (see [AudioBank] for how) and re-running the forge would throw
## those edits away. Run step 1 alone to refresh the placeholders in place;
## their filenames do not change, so an existing bank keeps working.
##
## [b]Why hand-rolled PCM and not an AudioStreamGenerator.[/b] A generator is a
## playback object: it produces samples into a live audio device, which a
## headless run does not have. Writing the RIFF bytes directly needs no device,
## no mixing thread and no frame loop, and produces a file the importer treats
## exactly like one a sound designer delivered -- which is the property that
## makes swapping in the real thing a drag-and-drop rather than a code change.

## 22 kHz mono is deliberately mediocre. These are placeholders and the file
## size is the point: seventeen of them live in version control.
const SAMPLE_RATE: int = 22050

## Where the .wav files go. Named so that a directory listing says what they are.
const OUTPUT_DIR: String = "res://assets/audio"
const FILE_PREFIX: String = "placeholder_"

## Where the generated bank is saved.
const BANK_PATH: String = "res://scenes/audio/placeholder_bank.tres"

## Peak amplitude of a placeholder, before the per-cue [member AudioCue.volume_db]
## trim. Well under full scale: a square wave at unity is painful.
const PEAK: float = 0.28

## Seconds of fade at the tail of every placeholder. Without it a truncated
## square wave clicks, and a click is the one artefact that would make these
## sound like a bug rather than a placeholder.
const TAIL_SECONDS: float = 0.008

const WAVS_FLAG: String = "--wavs"
const BANK_FLAG: String = "--bank"

const EXIT_OK: int = 0
const EXIT_FAILED: int = 1

var _started: bool = false
var _finished: bool = false
var _exit_code: int = EXIT_OK
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _initialize() -> void:
	# Fixed seed: regenerating the placeholders must not produce a different
	# noise burst every time, or every run is a binary diff in version control.
	_rng.seed = 0x50414E4F


func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	if _finished:
		quit(_exit_code)
		return true
	return false


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var do_wavs: bool = args.has(WAVS_FLAG) or not args.has(BANK_FLAG)
	var do_bank: bool = args.has(BANK_FLAG) or not args.has(WAVS_FLAG)

	print("PANOPTICON placeholder audio forge")
	if do_wavs:
		_forge_wavs()
	if do_bank and _exit_code == EXIT_OK:
		_forge_bank()
	_finished = true


# --- Step 1: the .wav files ---------------------------------------------------

func _forge_wavs() -> void:
	if not _ensure_dir(OUTPUT_DIR):
		printerr("Could not create %s" % OUTPUT_DIR)
		_exit_code = EXIT_FAILED
		return
	print("  writing %d placeholders into %s" % [AudioEvents.ALL.size(), OUTPUT_DIR])
	for event: StringName in AudioEvents.ALL:
		if event == AudioEvents.MUSIC_MATCH_THEME:
			# Deliberately left with nothing behind it -- see AudioEvents.
			continue
		var samples: PackedFloat32Array = _render(event)
		var path: String = wav_path(event)
		if not _write_wav(path, samples):
			printerr("  FAIL  %s" % path)
			_exit_code = EXIT_FAILED
			return
		print("  ok    %-46s %5.3fs" % [path.get_file(), float(samples.size()) / float(SAMPLE_RATE)])


## Make [param res_dir] exist. An existing directory is success, which
## [method DirAccess.make_dir_recursive_absolute] does not always say in its
## return value.
func _ensure_dir(res_dir: String) -> bool:
	var absolute: String = ProjectSettings.globalize_path(res_dir)
	if DirAccess.dir_exists_absolute(absolute):
		return true
	return DirAccess.make_dir_recursive_absolute(absolute) == OK


## The file a given event's placeholder is written to.
static func wav_path(event: StringName) -> String:
	return "%s/%s%s.wav" % [OUTPUT_DIR, FILE_PREFIX, String(event).replace(".", "_")]


## Write mono 16-bit PCM as a canonical 44-byte-header RIFF file.
func _write_wav(path: String, samples: PackedFloat32Array) -> bool:
	var file: FileAccess = FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	var data_bytes: int = samples.size() * 2

	file.store_buffer("RIFF".to_ascii_buffer())
	file.store_32(36 + data_bytes)
	file.store_buffer("WAVE".to_ascii_buffer())
	file.store_buffer("fmt ".to_ascii_buffer())
	file.store_32(16)              # PCM chunk size
	file.store_16(1)               # format: PCM
	file.store_16(1)               # channels: mono
	file.store_32(SAMPLE_RATE)
	file.store_32(SAMPLE_RATE * 2) # byte rate: rate * channels * 2
	file.store_16(2)               # block align
	file.store_16(16)              # bits per sample
	file.store_buffer("data".to_ascii_buffer())
	file.store_32(data_bytes)
	for sample: float in samples:
		var clamped: float = clampf(sample, -1.0, 1.0)
		file.store_16(int(roundf(clamped * 32767.0)) & 0xFFFF)
	file.close()
	return true


# --- Step 3: the bank ---------------------------------------------------------

func _forge_bank() -> void:
	var bank: AudioBank = AudioBank.new()
	var missing: int = 0
	for event: StringName in AudioEvents.ALL:
		var cue: AudioCue = _make_cue(event)
		if cue.stream == null and event != AudioEvents.MUSIC_MATCH_THEME:
			printerr("  MISSING stream for %s -- run --wavs and --import first" % event)
			missing += 1
		bank.put_cue(cue)

	if missing > 0:
		_exit_code = EXIT_FAILED
		return

	if not _ensure_dir(BANK_PATH.get_base_dir()):
		printerr("Could not create %s" % BANK_PATH.get_base_dir())
		_exit_code = EXIT_FAILED
		return

	var error: int = ResourceSaver.save(bank, BANK_PATH)
	if error != OK:
		printerr("Could not save %s (%s)" % [BANK_PATH, error_string(error)])
		_exit_code = EXIT_FAILED
		return
	print("  bank  %s  (%d cues, %d silent)" % [BANK_PATH, bank.cues.size(), bank.silent_events().size()])


## One cue, with the placeholder stream attached and the mixing decisions that
## belong to this event.
##
## Everything set here is overridable in the inspector afterwards; these are the
## starting values, chosen so the game is legible rather than mixed.
func _make_cue(event: StringName) -> AudioCue:
	var cue: AudioCue = AudioCue.new()
	cue.event = event
	cue.resource_name = String(event)
	cue.positional = AudioEvents.POSITIONAL.has(event)
	if event != AudioEvents.MUSIC_MATCH_THEME:
		cue.stream = load(wav_path(event)) as AudioStream

	match event:
		AudioEvents.RIFLE_FIRED:
			# Loud, far-carrying and pitch-varied: this is the broadcast the
			# whole design hangs on. 250 m of range against a ~120 m ring means
			# a runner on the far side of the ring still hears it clearly.
			cue.volume_db = -8.0
			cue.max_distance = 250.0
			cue.unit_size = 30.0
			cue.pitch_jitter = 0.03
		AudioEvents.RIFLE_HIT:
			cue.volume_db = -11.0
			cue.max_distance = 140.0
			cue.unit_size = 16.0
			cue.pitch_jitter = 0.05
		AudioEvents.RIFLE_MISSED:
			cue.volume_db = -15.0
			cue.max_distance = 100.0
			cue.unit_size = 12.0
			cue.pitch_jitter = 0.08
		AudioEvents.RIFLE_RELOAD_STARTED:
			cue.volume_db = -17.0
		AudioEvents.RIFLE_RELOAD_FINISHED:
			# The single most important sound for the player in the tower: the
			# weapon is answerable again. Trimmed hotter than its neighbours.
			cue.volume_db = -12.0
		AudioEvents.MATCH_WON:
			cue.volume_db = -11.0
		AudioEvents.MATCH_STARTED, AudioEvents.RACE_STARTED, AudioEvents.ROUND_STARTED, \
		AudioEvents.SEAT_CHANGED, AudioEvents.ROUND_RESOLVED, AudioEvents.RUNNER_CONVERTED:
			cue.volume_db = -15.0
		AudioEvents.UI_CLICK:
			cue.volume_db = -20.0
			cue.min_retrigger_seconds = 0.04
		AudioEvents.UI_FOCUS:
			# A mouse dragged down a column of buttons emits one of these per
			# button. The clock is what stops that being a machine gun.
			cue.volume_db = -26.0
			cue.min_retrigger_seconds = 0.08
		AudioEvents.UI_BACK, AudioEvents.UI_MENU_OPENED, AudioEvents.UI_MENU_CLOSED:
			cue.volume_db = -20.0
			cue.min_retrigger_seconds = 0.04
		AudioEvents.MUSIC_MATCH_THEME:
			cue.bus = &"Music"
			cue.volume_db = -12.0
	return cue


# --- Synthesis ----------------------------------------------------------------
#
# One branch per event. Verbose rather than table-driven on purpose: each of
# these is a one-line description of what the placeholder is trying to say, and
# the whole file is throwaway the day real audio lands.

func _render(event: StringName) -> PackedFloat32Array:
	match event:
		AudioEvents.RIFLE_FIRED:
			# A crack: noise transient over a fast fall from 900 Hz to 110 Hz.
			var crack: PackedFloat32Array = _noise(0.05, 1.0, 3.0)
			var body: PackedFloat32Array = _sweep(900.0, 110.0, 0.20, 0.7, 2.2, false)
			return _mix(crack, body)
		AudioEvents.RIFLE_HIT:
			# Up two steps: something landed.
			return _sequence(PackedFloat32Array([1200.0, 1900.0]), 0.055, 0.9, true, 3.0)
		AudioEvents.RIFLE_MISSED:
			# Dull, dark, unsatisfying. It is supposed to be.
			return _mix(_noise(0.10, 0.45, 5.0), _tone(140.0, 0.10, 0.35, false, 4.0))
		AudioEvents.RIFLE_RELOAD_STARTED:
			return _tone(320.0, 0.08, 0.8, true, 2.5)
		AudioEvents.RIFLE_RELOAD_FINISHED:
			# Two rising blips. The tower is answerable again.
			return _sequence(PackedFloat32Array([560.0, 840.0]), 0.06, 1.0, true, 2.0)
		AudioEvents.MATCH_STARTED:
			return _sequence(PackedFloat32Array([440.0, 554.0, 659.0]), 0.09, 0.9, true, 1.6)
		AudioEvents.RACE_STARTED:
			return _sequence(PackedFloat32Array([523.0, 784.0]), 0.10, 0.9, true, 1.6)
		AudioEvents.ROUND_STARTED:
			return _sequence(PackedFloat32Array([392.0, 392.0]), 0.07, 0.9, true, 2.4)
		AudioEvents.SEAT_CHANGED:
			# A long climb: the tower has changed hands.
			return _sweep(220.0, 880.0, 0.26, 0.85, 1.2, true)
		AudioEvents.ROUND_RESOLVED:
			return _sequence(PackedFloat32Array([330.0, 262.0]), 0.08, 0.85, true, 2.0)
		AudioEvents.RUNNER_CONVERTED:
			# Down: one fewer on the ring.
			return _sequence(PackedFloat32Array([880.0, 440.0]), 0.06, 0.9, true, 2.6)
		AudioEvents.MATCH_WON:
			return _sequence(PackedFloat32Array([523.0, 659.0, 784.0, 1046.0]), 0.10, 1.0, true, 1.4)
		AudioEvents.UI_CLICK:
			return _tone(1000.0, 0.035, 0.7, true, 3.5)
		AudioEvents.UI_FOCUS:
			return _tone(1600.0, 0.025, 0.45, false, 3.5)
		AudioEvents.UI_BACK:
			return _tone(600.0, 0.045, 0.7, true, 3.0)
		AudioEvents.UI_MENU_OPENED:
			return _sweep(400.0, 900.0, 0.07, 0.6, 2.0, true)
		AudioEvents.UI_MENU_CLOSED:
			return _sweep(900.0, 400.0, 0.07, 0.6, 2.0, true)
	# An event that has been added to AudioEvents but not given a recipe still
	# gets a file, so the bank stays complete and the gap is audible rather than
	# silent.
	return _tone(2000.0, 0.04, 0.5, true, 3.0)


## [param seconds] of a single frequency. [param square] picks the waveform;
## [param decay] is the exponent of the amplitude fall, higher being snappier.
func _tone(frequency: float, seconds: float, gain: float, square: bool, decay: float) -> PackedFloat32Array:
	var count: int = int(seconds * SAMPLE_RATE)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	for i: int in count:
		var t: float = float(i) / float(SAMPLE_RATE)
		var phase: float = TAU * frequency * t
		var wave: float = signf(sin(phase)) if square else sin(phase)
		out[i] = wave * gain * PEAK * _envelope(t, seconds, decay)
	return out


## A linear frequency ramp from [param from_hz] to [param to_hz].
func _sweep(from_hz: float, to_hz: float, seconds: float, gain: float, decay: float, square: bool) -> PackedFloat32Array:
	var count: int = int(seconds * SAMPLE_RATE)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	var phase: float = 0.0
	for i: int in count:
		var t: float = float(i) / float(SAMPLE_RATE)
		var frequency: float = lerpf(from_hz, to_hz, t / maxf(seconds, 0.0001))
		# Integrate the frequency rather than evaluating sin(TAU*f*t): the naive
		# form has a discontinuity wherever f changes and audibly buzzes.
		phase += TAU * frequency / float(SAMPLE_RATE)
		var wave: float = signf(sin(phase)) if square else sin(phase)
		out[i] = wave * gain * PEAK * _envelope(t, seconds, decay)
	return out


## White noise under the same envelope. Seeded, so the file is reproducible.
func _noise(seconds: float, gain: float, decay: float) -> PackedFloat32Array:
	var count: int = int(seconds * SAMPLE_RATE)
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	for i: int in count:
		var t: float = float(i) / float(SAMPLE_RATE)
		out[i] = _rng.randf_range(-1.0, 1.0) * gain * PEAK * _envelope(t, seconds, decay)
	return out


## [param frequencies] played one after another, [param seconds] each.
func _sequence(frequencies: PackedFloat32Array, seconds: float, gain: float, square: bool, decay: float) -> PackedFloat32Array:
	var out: PackedFloat32Array = PackedFloat32Array()
	for frequency: float in frequencies:
		out.append_array(_tone(frequency, seconds, gain, square, decay))
	return out


## Sum two buffers, keeping the longer length. Not normalised: the callers above
## are hand-balanced to stay inside [constant PEAK].
func _mix(a: PackedFloat32Array, b: PackedFloat32Array) -> PackedFloat32Array:
	var count: int = maxi(a.size(), b.size())
	var out: PackedFloat32Array = PackedFloat32Array()
	out.resize(count)
	for i: int in count:
		var left: float = a[i] if i < a.size() else 0.0
		var right: float = b[i] if i < b.size() else 0.0
		out[i] = clampf(left + right, -1.0, 1.0)
	return out


## A 3 ms attack, an exponential decay, and a forced fade over the last
## [constant TAIL_SECONDS] so nothing ends on a discontinuity.
func _envelope(t: float, total: float, decay: float) -> float:
	if total <= 0.0:
		return 0.0
	var attack: float = minf(t / 0.003, 1.0)
	var remaining: float = clampf(1.0 - t / total, 0.0, 1.0)
	var body: float = pow(remaining, decay)
	var tail: float = clampf((total - t) / TAIL_SECONDS, 0.0, 1.0)
	return attack * body * tail
