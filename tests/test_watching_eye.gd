extends TestCase

## [WatchingEye]: the eyeball over the tower that follows whoever is looking at
## it, and the promise that following them tells them nothing.
##
## Ryan, 2026-09-10: [i]"take that eye model you made, and stick it between the
## box of eyes, and the light source, and have the view of each player other than
## the shooter, look like the eye is always following it."[/i] The game is called
## PANOPTICON, so this is the one piece of art in it that has to be exactly right.
##
## Two of these tests are the interesting ones and they pull in opposite
## directions:
##
## - [method test_the_eye_looks_at_whoever_is_looking] and
##   [method test_it_follows_the_local_viewport_camera] assert that it [b]does[/b]
##   move, at each viewer individually, driven by the local viewport's own camera;
## - [method test_the_eye_cannot_see_the_guard] asserts that the only thing it can
##   possibly be moved by is the position of that camera. Not its direction, and
##   nothing about the guard at all.
##
## Between them they pin the distinction the whole feature rests on: an eye that
## tracks the [b]viewer[/b] leaks nothing, because its bearing is a fact the
## viewer already held; an eye that tracked anything the guard does would hand the
## prisoners the entire game. Those two are one plausible-looking diff apart, so
## the source scan below is not decoration.
##
## The rest guard against the ways this breaks silently: a gaze axis pointed the
## wrong way (the model's pupil is +Z, not Godot's -Z, so [method Node3D.look_at]
## produces an eye that pointedly ignores everyone and looks deliberate from the
## ring); a shooter exclusion done by asking [MatchController] instead of by
## geometry; a smoothing term that lags on slow machines; and an eyeball that
## drifts out of the gap it is supposed to hang in, or fails to ride the tower
## when somebody raises it.
##
## What is not here is whether it [i]looks[/i] like an eye, which is a screenshot
## and belongs on a person's monitor. Nobody has seen this running.

const EYE_SCENE_PATH: String = "res://scenes/tower/watching_eye.tscn"
const PROFILE_PATH: String = "res://scenes/tower/default_watching_eye_profile.tres"

## The two files that make up the watching eye. Read as text below, because "it
## cannot refer to the guard" is a fact about the source rather than about any
## value it happens to hold at runtime.
const EYE_SOURCE_PATHS: Array[String] = [
	"res://scripts/tower/watching_eye.gd",
	"res://scripts/tower/watching_eye_profile.gd",
]

## Somewhere out on the deck: the running channel is r=41.75 to r=46.75, so this
## is a prisoner in the middle of it, at head height.
const PRISONER_POINT: Vector3 = Vector3(44.0, 1.65, 0.0)

## The guard's own eye, from [code]tests/test_tower.gd[/code]: they spawn at
## y=0.25 and their head is 1.65 m above their feet.
const GUARD_EYE: Vector3 = Vector3(0.0, 1.9, 0.0)

var _eye: WatchingEye


func before_each() -> void:
	_eye = _make_eye(0.0)
	add_child(_eye)


## An eye with its own profile, so that nothing here can write on the shipped
## [code].tres[/code] and leak into the rest of the suite.
##
## [param track_rate] is 0.0 by default, which snaps the gaze in one call: every
## test but the smoothing one wants to assert where the eye ends up, not how it
## got there. The profile has to be set before the node enters the tree, because
## [method WatchingEye._ready] places and sizes itself from it.
func _make_eye(track_rate: float) -> WatchingEye:
	var scene: PackedScene = load(EYE_SCENE_PATH) as PackedScene
	var eye: WatchingEye = scene.instantiate() as WatchingEye
	var profile: WatchingEyeProfile = WatchingEyeProfile.new()
	profile.track_rate = track_rate
	eye.profile = profile
	return eye


## Advance [param count] rendered frames.
##
## [b]Not[/b] [method TestCase.step_ticks]. The gaze is presentation and runs on
## [method Node._process], and the runner compresses time by raising the physics
## rate and the time scale together -- so a handful of physics ticks can and does
## execute without a single idle frame in between, and a test that waited on
## [signal SceneTree.physics_frame] here sees an eye that has never once been
## given the chance to turn.
func _step_frames(count: int) -> void:
	var tree: SceneTree = get_tree()
	for _frame: int in count:
		await tree.process_frame


## A point on the deck at [param bearing] radians, at a prisoner's head height.
static func _deck_point(radius: float, bearing: float) -> Vector3:
	return Vector3(radius * cos(bearing), 1.65, radius * sin(bearing))


func _descendants_of(node: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child: Node in node.get_children():
		found.append(child)
		found.append_array(_descendants_of(child))
	return found


## Executable text only: the prose in these files discusses cameras, rifles,
## seats and the match at length -- that is the point of the prose -- so comments
## are stripped before anything is searched for.
func _code_of(path: String) -> String:
	var source: String = FileAccess.get_file_as_string(path)
	var code: String = ""
	for line: String in source.split("\n"):
		var comment: int = line.find("#")
		code += (line if comment < 0 else line.substr(0, comment)) + "\n"
	return code.to_lower()


# --- It follows you -----------------------------------------------------------

## The pupil points at the viewer, from anywhere on the deck.
##
## Asserted against the direction the eye reports it wants ([method
## WatchingEye.gaze_direction_for]) and against where the pupil actually ends up
## ([method WatchingEye.gaze_direction]), because those are two different things
## and only the second one is what a prisoner sees. A basis built with the wrong
## handedness, or with the model's +Z gaze axis confused for Godot's -Z, passes
## the first and fails the second.
func test_the_eye_looks_at_whoever_is_looking() -> void:
	var viewers: Array[Vector3] = [
		PRISONER_POINT,
		Vector3(-44.0, 1.65, 0.0),
		Vector3(0.0, 1.65, 44.0),
		Vector3(31.1, 1.65, -31.1),
		Vector3(36.0, -11.0, 0.0),
		Vector3(0.0, 30.0, 40.0),
	]

	for viewer: Vector3 in viewers:
		var wanted: Vector3 = (viewer - _eye.global_position).normalized()
		assert_vec3_almost_eq(_eye.gaze_direction_for(viewer), wanted, 0.0001,
			"the eye should want to look straight at a viewer at %v" % viewer)

		_eye.turn_toward(_eye.gaze_direction_for(viewer), 0.0)
		assert_vec3_almost_eq(_eye.gaze_direction(), wanted, 0.0001,
			"the pupil should end up pointing at a viewer at %v" % viewer)


## The eyeball is right way round.
##
## [code]eye.glb[/code] puts its iris and pupil at +Z, which is the opposite of
## the -Z that [method Node3D.look_at] and [method Basis.looking_at] assume. Get
## that wrong and the eye turns its back on every viewer -- which reads from the
## ring as a deliberate choice rather than as a bug, and would survive review.
## So: the model's gaze axis, carried through the basis, must come out as the
## direction asked for, including at both poles where the reference up vector has
## to be swapped.
func test_the_basis_points_the_models_own_gaze_axis() -> void:
	var directions: Array[Vector3] = [
		Vector3.BACK, Vector3.FORWARD, Vector3.RIGHT, Vector3.LEFT,
		Vector3.UP, Vector3.DOWN, Vector3(1.0, 1.0, 1.0), Vector3(-3.0, 0.4, 2.0),
	]

	for direction: Vector3 in directions:
		var basis: Basis = WatchingEye.gaze_basis_for(direction)
		assert_vec3_almost_eq(basis * WatchingEye.MODEL_GAZE_AXIS, direction.normalized(), 0.0001,
			"the model's own gaze axis should end up along %v" % direction)
		assert_almost_eq(basis.determinant(), 1.0, 0.0001,
			"the basis for %v should be right-handed and unscaled, or the eye is mirrored" % direction)


## It follows the local viewport's camera, which is what makes it per-viewer.
##
## This is the whole mechanism in one assertion. Nothing tells the eye who is
## watching; it asks the viewport for the camera that is current [b]in this
## process[/b], and on every other machine in the game that same call answers with
## somebody else. There is no list of players here, no averaging, and no chosen
## one.
func test_it_follows_the_local_viewport_camera() -> void:
	var viewer: Camera3D = Camera3D.new()
	viewer.position = PRISONER_POINT
	add_child(viewer)
	viewer.make_current()

	assert_vec3_almost_eq(_eye.viewer_position(), PRISONER_POINT, 0.0001,
		"the eye should take its viewer from the local viewport's current camera")

	await _step_frames(4)
	assert_vec3_almost_eq(_eye.gaze_direction(), (PRISONER_POINT - _eye.global_position).normalized(), 0.01,
		"the eye should be looking at the local camera without being told to")

	var moved: Vector3 = Vector3(0.0, 1.65, -44.0)
	viewer.position = moved
	await _step_frames(4)
	assert_vec3_almost_eq(_eye.gaze_direction(), (moved - _eye.global_position).normalized(), 0.01,
		"the eye should follow the camera when it moves, not snapshot it")


## With no camera at all -- a headless run, or a frame before anything is current
## -- the eye rests rather than pointing at the world origin.
func test_with_no_viewer_it_rests() -> void:
	assert_vec3_almost_eq(_eye.viewer_position(), _eye.global_position, 0.0001,
		"with no camera the eye should fall back to its own centre")
	assert_vec3_almost_eq(_eye.gaze_direction_for(_eye.global_position), Vector3.UP, 0.0001,
		"with no viewer the eye should rest looking up at the light")


# --- The shooter is excluded --------------------------------------------------

## The guard is not watched, and no match state was consulted to work that out.
##
## The exclusion is positional: a camera inside the tower's own column of space is
## the guard, because nobody else can ever be there. That is answered from the
## viewer's own coordinates alone, so it cannot be turned into a channel -- and it
## is automatically correct for whoever holds the seat, without this file ever
## having heard of a seat.
func test_the_guard_is_not_watched() -> void:
	var rested: Vector3 = _eye.gaze_direction_for(GUARD_EYE)
	assert_vec3_almost_eq(rested, Vector3.UP, 0.0001,
		"the eye should rest looking up at the light rather than down at the guard")

	var at_the_guard: Vector3 = (GUARD_EYE - _eye.global_position).normalized()
	assert_lt(rested.dot(at_the_guard), 0.0,
		"the eye must not be pointing anywhere near the guard")

	_eye.turn_toward(rested, 0.0)
	assert_vec3_almost_eq(_eye.gaze_direction(), Vector3.UP, 0.0001,
		"the pupil should actually be aimed at the light, not merely intend to be")

	# A guard at the apex of a jump, and a guard at the rim of the 8 m platform,
	# are both still inside their own column.
	for inside: Vector3 in [Vector3(0.0, 3.16, 0.0), Vector3(7.9, 1.9, 0.0), Vector3(0.0, 0.25, -7.9)]:
		assert_vec3_almost_eq(_eye.gaze_direction_for(inside), Vector3.UP, 0.0001,
			"a viewer at %v is on the tower and must not be watched" % inside)


## The excluded column is the tower and nothing else.
##
## Asserted against the arithmetic rather than against the shipped numbers, so it
## still means something after somebody tunes the profile. The case that matters
## is the bottom: the courtyard floor is 12.5 m below the deck and spans r=0..35,
## so a body directly under the tower down there is inside the radius and must
## still be watched -- it is a prisoner who fell, not the guard.
func test_the_excluded_column_is_the_tower_and_only_the_tower() -> void:
	var profile: WatchingEyeProfile = WatchingEyeProfile.new()
	var radius: float = profile.tower_radius_metres
	var low: float = profile.tower_band_low_metres
	var high: float = profile.tower_band_high_metres

	assert_ge(radius, 9.0, "the column should cover the whole of the guard's stand")
	assert_lt(radius, 35.0, "the column must not reach the inner kerb, or prisoners stop being watched")
	assert_lt(low, -1.0, "the column should reach under the platform slab")
	assert_gt(high, 3.16, "the column should clear a jumping guard's crown")

	for on_tower: Vector3 in [Vector3.ZERO, Vector3(0.0, 3.16, 0.0), Vector3(8.9, 0.25, 0.0), Vector3(0.0, 20.0, 0.0)]:
		assert_true(WatchingEye.is_on_the_tower(on_tower, radius, low, high),
			"%v is on the tower" % on_tower)

	var elsewhere: Array[Vector3] = [
		Vector3(44.0, 1.65, 0.0),
		Vector3(0.0, 1.65, -44.0),
		Vector3(0.0, -12.5, 0.0),
		Vector3(4.0, -12.5, 4.0),
		Vector3(0.0, 40.0, 0.0),
	]
	for outside: Vector3 in elsewhere:
		assert_false(WatchingEye.is_on_the_tower(outside, radius, low, high),
			"%v is not on the tower and must still be watched" % outside)


# --- It cannot leak the guard's aim -------------------------------------------

## The eye has no way of knowing anything about the guard, because it has no way
## of referring to the guard at all.
##
## This is the assertion that keeps the feature and the canon apart, and it is a
## fact about the source, so it is asserted against the source. The eye is allowed
## exactly one input -- [method Viewport.get_camera_3d], the local viewport's own
## camera -- and everything else on this list is a way of reaching a second one.
##
## [code]multiplayer[/code] and [code]rpc[/code] are on the list for a different
## reason from the rest: the gaze must stay a local, cosmetic quantity. The moment
## an orientation derived from one machine's camera is sent to another machine, an
## eye that leaks nothing becomes an eye that broadcasts where a player is
## standing -- and it would still pass every other test here.
func test_the_eye_cannot_see_the_guard() -> void:
	var forbidden: Array[String] = [
		"rifle", "weapon", "seat", "matchcontroller", "match_", "aim", "fire",
		"shoot", "trigger", "rpc", "multiplayer", "synchron", "get_tree", "signal",
	]

	for path: String in EYE_SOURCE_PATHS:
		var code: String = _code_of(path)
		if not assert_gt(float(code.length()), 0.0, "%s should be readable" % path):
			continue
		for word: String in forbidden:
			assert_false(code.contains(word),
				"%s mentions '%s' in code: the eye must not be able to refer to the guard" % [path, word])

	var eye_code: String = _code_of(EYE_SOURCE_PATHS[0])
	assert_true(eye_code.contains("get_camera_3d"),
		"the eye should take its viewer from the local viewport's camera, and from nothing else")
	assert_eq_int(eye_code.count("get_camera_3d"), 1,
		"there should be exactly one place the eye learns who is watching")


## The gaze depends on where the viewer is, and not at all on where they are
## looking.
##
## The distinction is the entire no-leak argument, and it is invisible in a diff:
## a version that read the camera's [b]direction[/b] as well would look almost
## identical here and would be a channel the moment the same code was pointed at
## the guard's camera. So it is asserted directly -- one viewer point, every
## orientation, one answer.
func test_the_gaze_reads_a_position_and_never_a_direction() -> void:
	var wanted: Vector3 = _eye.gaze_direction_for(PRISONER_POINT)

	var viewer: Camera3D = Camera3D.new()
	viewer.position = PRISONER_POINT
	add_child(viewer)

	for turn: float in [0.0, 0.5 * PI, PI, -0.75 * PI]:
		viewer.rotation = Vector3(0.3, turn, 0.0)
		assert_vec3_almost_eq(_eye.gaze_direction_for(viewer.global_position), wanted, 0.0001,
			"where the viewer is facing must make no difference to the eye")


## The eyeball is the only thing in the tower that turns.
##
## The box of eyes that used to stand here was deleted on Ryan's instruction --
## "you can remove the box of eyes obfuscating the shooter" -- because the guard
## is being put inside a hollow chamber and walls hide better than a mirror. Its
## own assertions went with it. What survives is the boundary those assertions
## were really protecting: nothing else in the tower may acquire a bearing that
## points, because a thing on the axis that turns towards a prisoner and a thing
## on the axis that turns towards the guard's target look identical from the
## deck. So: the watching eye is the only [WatchingEye] there is, and no other
## node in the tower is one.
func test_the_eyeball_is_the_only_thing_that_turns() -> void:
	var arena: Node3D = TestFixtures.make_arena()
	add_child(arena)

	var tower: Node3D = arena.get_node_or_null(^"Tower") as Node3D
	if not assert_not_null(tower, "the arena should carry a Tower"):
		return

	var watchers: int = 0
	for node: Node in _descendants_of(tower):
		if node as WatchingEye != null:
			watchers += 1
	assert_eq_int(watchers, 1, "exactly one node in the tower may track a viewer")

	for node: Node in _descendants_of(_eye):
		assert_null(node as Camera3D, "%s: the eyeball must not carry a camera" % node.name)


# --- How it turns -------------------------------------------------------------

## The gaze is smoothed, and the smoothing is the same on a slow machine as on a
## fast one.
##
## An eye welded to your face is a cursor; an eye that swings onto you is being
## watched. The smoothing is therefore wanted -- but the obvious way to write it,
## [code]lerp(a, b, rate * delta)[/code], produces a gaze that lags visibly
## further behind at 30 fps than at 240, which is a difference between players
## nobody chose. The exponential form does not, so the same simulated second in
## one step and in sixty must land in the same place.
func test_the_gaze_is_smoothed_at_the_same_speed_on_every_machine() -> void:
	var target: Vector3 = (PRISONER_POINT - _eye.global_position).normalized()

	var coarse: WatchingEye = _make_eye(6.0)
	add_child(coarse)
	coarse.turn_toward(target, 0.2)
	var partway: Vector3 = coarse.gaze_direction()

	assert_lt(partway.dot(target), 0.99, "a fifth of a second at rate 6 should not have finished the turn")
	assert_gt(partway.dot(target), 0.5, "a fifth of a second at rate 6 should be over half way there")

	var fine: WatchingEye = _make_eye(6.0)
	add_child(fine)
	for _tick: int in 12:
		fine.turn_toward(target, 1.0 / 60.0)

	assert_vec3_almost_eq(fine.gaze_direction(), partway, 0.01,
		"a fifth of a second of turning should land in the same place whatever the frame rate")

	var snapping: WatchingEye = _make_eye(0.0)
	add_child(snapping)
	snapping.turn_toward(target, 1.0 / 60.0)
	assert_vec3_almost_eq(snapping.gaze_direction(), target, 0.0001,
		"track_rate 0 should snap, so the smoothing can be turned off")


## The gaze settles onto its target and never once goes past it.
##
## Ryan chose the lag over a carved socket and a swivel limit, so the lag has to
## be the good kind. A spring, or any weight that can exceed 1, would let the eye
## sail past the viewer and rock back -- which reads as a servo with slack rather
## than as something that decided to look, and which no other test here would
## notice because the eye would still end up pointing at the right place.
##
## So five simulated seconds are driven at the shipped rate and the remaining
## angle is watched every single step: it must shrink monotonically, and it must
## actually arrive rather than trail forever.
func test_the_gaze_settles_and_never_overshoots() -> void:
	var eye: WatchingEye = _make_eye(WatchingEyeProfile.new().track_rate)
	add_child(eye)

	var target: Vector3 = (PRISONER_POINT - eye.global_position).normalized()
	var previous: float = eye.gaze_direction().angle_to(target)
	assert_gt(previous, 0.5, "the eye should start well away from the target, or this proves nothing")

	var worst: float = 0.0
	for _tick: int in 300:
		eye.turn_toward(target, 1.0 / 60.0)
		var remaining: float = eye.gaze_direction().angle_to(target)
		worst = maxf(worst, remaining - previous)
		previous = remaining

	assert_le(worst, 0.0001,
		"the gaze must close on its target monotonically -- it must never overshoot, ring or wobble")
	assert_le(previous, 0.001,
		"after five seconds the gaze should have settled on the target, not still be trailing it")


## A sprinting prisoner is followed at a visible, bounded lag.
##
## This is the assertion that stands in for what Ryan actually saw. The eye is
## settled onto a viewer, the viewer then runs the deck at sprint pace, and what
## is measured is how far behind the pupil sits once the lag has reached its
## steady state. It has to be enough that the ball is visibly mid-turn the whole
## time somebody is running -- which is the only depth cue a sphere has -- and
## small enough that the eye is plainly still following them.
##
## The steady-state lag is [code]w / rate[/code] radians for a viewer sweeping at
## [code]w[/code] rad/s, so this is really an assertion about the shipped
## [member WatchingEyeProfile.track_rate] being in a sane band, expressed in the
## terms the player experiences it in.
func test_a_sprinting_viewer_is_followed_at_a_visible_lag() -> void:
	var eye: WatchingEye = _make_eye(WatchingEyeProfile.new().track_rate)
	add_child(eye)

	var radius: float = 44.0
	var sweep: float = 11.0 / radius
	var bearing: float = 0.0
	for _settle: int in 300:
		eye.turn_toward(eye.gaze_direction_for(_deck_point(radius, bearing)), 1.0 / 60.0)

	var trailing: float = 0.0
	for _tick: int in 300:
		bearing += sweep / 60.0
		var here: Vector3 = _deck_point(radius, bearing)
		eye.turn_toward(eye.gaze_direction_for(here), 1.0 / 60.0)
		trailing = eye.gaze_direction().angle_to(eye.gaze_direction_for(here))

	assert_gt(rad_to_deg(trailing), 2.0,
		"the gaze should visibly trail a sprinting viewer, or the ball reads as a flat decal again")
	assert_lt(rad_to_deg(trailing), 15.0,
		"the gaze should still be following them, not left behind")


## The shipped resource is the laggy one, and the knob still reaches instant.
##
## Two separate promises. The eye Ryan actually gets has to follow with a delay --
## a shipped rate high enough to read as a snap would put the flat-decal problem
## straight back -- and 0.0 has to remain a true instant snap so he can turn the
## whole effect off and see the difference.
func test_the_shipped_eye_follows_with_a_delay_and_can_be_turned_off() -> void:
	var shipped: WatchingEyeProfile = load(PROFILE_PATH) as WatchingEyeProfile
	if not assert_not_null(shipped, "the shipped watching eye profile should load"):
		return
	assert_gt(shipped.track_rate, 0.0, "the shipped eye must follow with a lag, not snap")
	assert_lt(shipped.track_rate, 4.0,
		"the shipped lag must be slow enough to be seen -- an eye already turned reads as a decal")
	assert_almost_eq(shipped.track_rate, WatchingEyeProfile.new().track_rate, 0.0001,
		"the shipped resource and the class default should not disagree about the lag")

	var instant: WatchingEye = _make_eye(0.0)
	add_child(instant)
	var target: Vector3 = (PRISONER_POINT - instant.global_position).normalized()
	instant.turn_toward(target, 1.0 / 60.0)
	assert_vec3_almost_eq(instant.gaze_direction(), target, 0.0001,
		"track_rate 0 must still be an instant snap, so the lag can be turned off")


# --- Scenery, not a mechanic --------------------------------------------------

## The eyeball has no gameplay and must not acquire any.
##
## The list the tower has always been held to, for the same reasons: a collision
## shape would put it on the rifle's hit mask and stop the guard's own shots from
## leaving the tower; a light on it would put a patch on the deck that moves with
## the local viewer, which is the shape of a tell even though it could not
## actually signal anything. Shadow casting is off for that last reason too -- the
## iris stands proud of the sclera, so a shadow-casting eyeball would drop a
## lumpy, turning disc across the box below it.
func test_the_eye_is_inert() -> void:
	for node: Node in _descendants_of(_eye):
		assert_null(node as CollisionObject3D, "%s: the eye must have no physics body" % node.name)
		assert_null(node as CollisionShape3D, "%s: the eye must have no collision shape" % node.name)
		assert_null(node as Camera3D, "%s: the eye must not own a viewpoint" % node.name)
		assert_null(node as Light3D, "%s: the eye must not cast light" % node.name)

		var surface: GeometryInstance3D = node as GeometryInstance3D
		if surface != null:
			assert_eq_int(surface.cast_shadow, GeometryInstance3D.SHADOW_CASTING_SETTING_OFF,
				"%s: the eyeball must not cast a shadow onto the deck" % node.name)


## What the resource says is what the eye is: it places itself and sizes itself
## from the profile, in its parent's space.
func test_the_profile_is_the_source_of_truth() -> void:
	var profile: WatchingEyeProfile = WatchingEyeProfile.new()
	profile.radius_metres = 3.5
	profile.height_metres = 11.0
	profile.track_rate = 0.0

	var eye: WatchingEye = (load(EYE_SCENE_PATH) as PackedScene).instantiate() as WatchingEye
	eye.profile = profile
	add_child(eye)

	assert_vec3_almost_eq(eye.position, Vector3(0.0, 11.0, 0.0), 0.0001,
		"the eye should place itself at the profile's height, in its parent's space")

	var model: Node3D = eye.get_node_or_null(eye.model_path) as Node3D
	if not assert_not_null(model, "the eye should carry a model"):
		return
	assert_vec3_almost_eq(model.scale, Vector3.ONE * 3.5, 0.0001,
		"the eyeball should take its radius from the profile")

	var rig: Node3D = eye.get_node_or_null(eye.gaze_path) as Node3D
	if not assert_not_null(rig, "the eye should carry a gaze node"):
		return
	assert_vec3_almost_eq(rig.scale, Vector3.ONE, 0.0001,
		"the gaze node must stay unscaled -- the basis written to it every frame would wipe a scale")
	assert_vec3_almost_eq(eye.scale, Vector3.ONE, 0.0001,
		"the rig root must stay unscaled, or the tower column stops being measured in metres")


# --- Where it hangs -----------------------------------------------------------

## It is in the arena, on the tower, above the guard and under the light --
## and it rides the tower if somebody raises it.
##
## The last of those is the point of parenting it under Tower rather than placing
## it in world coordinates. Another agent is rebuilding the ring; the eyeball has
## to come along, and so this asserts against the box and the light as they
## actually are in the scene rather than against numbers copied out of it.
func test_it_hangs_between_the_box_and_the_light_and_rides_the_tower() -> void:
	var arena: Node3D = TestFixtures.make_arena()
	add_child(arena)

	var watcher: WatchingEye = arena.get_node_or_null(^"Tower/Watcher") as WatchingEye
	if not assert_not_null(watcher, "the arena's tower should carry a Watcher"):
		return

	assert_almost_eq(watcher.global_position.x, 0.0, 0.0001, "the eyeball should be on the tower's axis in X")
	assert_almost_eq(watcher.global_position.z, 0.0, 0.0001, "the eyeball should be on the tower's axis in Z")

	# The box of eyes it used to be measured against is gone, so the floor of the
	# gap is now the guard themselves: a spawned body's crown at the apex of a
	# jump. An eyeball hanging lower than that is an eyeball the guard's head
	# goes through.
	var spawn: Marker3D = arena.get_node_or_null(TestFixtures.TOWER_SPAWN_PATH) as Marker3D
	if not assert_not_null(spawn, "the arena should carry a TowerSpawn"):
		return
	var crown: float = spawn.global_position.y + 1.8 + 1.11

	# KeyLight, not TowerLight. TowerLight overwrites its own height from
	# TowerLightProfile.height_metres on ready, and that number is currently 2.2 --
	# the omni was shrunk into a local glow and now sits INSIDE the eye box
	# (y=-0.35..4.15), so it is no longer the light anything is "under". KeyLight is
	# the light above the tower, at y=20, and it is the one the gap is measured to.
	var light: Node3D = arena.get_node_or_null(^"Tower/KeyLight") as Node3D
	if not assert_not_null(light, "the arena's tower should still carry the light above it"):
		return

	var radius: float = watcher.profile.radius_metres
	assert_gt(watcher.global_position.y - radius, crown,
		"the eyeball should hang clear over the guard rather than sink onto them")
	assert_lt(watcher.global_position.y + radius, light.global_position.y,
		"the eyeball should stay under the light it is supposed to hang below")

	assert_almost_eq(watcher.position.y, watcher.profile.height_metres, 0.0001,
		"the eyeball should be placed in the tower's space, not the world's")

	var tower: Node3D = arena.get_node_or_null(^"Tower") as Node3D
	if not assert_not_null(tower, "the arena should have a Tower"):
		return
	var before: Vector3 = watcher.global_position
	tower.position += Vector3(3.0, 9.0, -2.0)
	assert_vec3_almost_eq(watcher.global_position, before + Vector3(3.0, 9.0, -2.0), 0.0001,
		"the eyeball should ride the tower, or a raised ring leaves it behind in mid-air")
