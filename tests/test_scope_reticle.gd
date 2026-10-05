extends TestCase

## [ScopeReticle]: the crosshair sits on the shot line at every resolution, and each holdover
## mark sits where a real [WeaponProjectile] fired through the rifle lands at that distance.

const FLOOR_TOP: float = 2000.0
const EYE: Vector3 = Vector3(0.0, FLOOR_TOP + 1.6, 0.0)
const RESOLUTIONS: Array[Vector2i] = [Vector2i(1280, 720), Vector2i(1920, 1080), Vector2i(2560, 1080)]
const SCOPED_FOV: float = 40.0
const YAW_DEGREES: float = 30.0
const SHOT_SPEED: float = 120.0
const DROP: float = 22.0
const CENTRE_DISTANCE: float = 60.0
const WALL_HALF_DEPTH: float = 0.5
const PIXEL_TOLERANCE: float = 1.5
const MAX_FLIGHT_TICKS: int = 600

var _world: Node3D
var _view: SubViewport
var _camera: Camera3D
var _reticle: ScopeReticle
var _rifle: Rifle
var _profile: WeaponProfile
var _rules: MatchRules
var _landed: bool = false
var _impact: Vector3 = Vector3.ZERO


func before_each() -> void:
	_world = Node3D.new()
	add_child(_world)

	_view = SubViewport.new()
	_view.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_view)
	_camera = Camera3D.new()
	_camera.fov = SCOPED_FOV
	_view.add_child(_camera)
	_camera.global_transform = Transform3D(Basis(Vector3.UP, deg_to_rad(YAW_DEGREES)), EYE)
	_camera.current = true

	_profile = TestFixtures.weapon_profile()
	_profile.projectile_gravity = DROP
	_rules = TestFixtures.match_rules()
	_rules.guard_projectile_speed = SHOT_SPEED
	_rifle = (load(TestFixtures.RIFLE_SCENE_PATH) as PackedScene).instantiate() as Rifle
	TestFixtures.silence_human_input(_rifle)
	_rifle.profile = _profile
	_rifle.rules = _rules
	add_child(_rifle)
	_rifle.set_physics_process(false)
	_rifle.tracer_parent = _world
	_rifle.aim_source = _camera
	_rifle.target_hit.connect(_on_landed)
	_rifle.missed.connect(_on_missed)

	_reticle = ScopeReticle.new()
	_view.add_child(_reticle)
	_reticle.set_anchors_preset(Control.PRESET_FULL_RECT)
	_reticle.ads = _rifle.get_node(^"Ads") as RifleAds
	await step_ticks(1)


func after_each() -> void:
	if is_instance_valid(_rifle):
		_rifle.clear_projectiles()
		_rifle.queue_free()
	for node: Node in [_world, _view]:
		if is_instance_valid(node):
			node.queue_free()


func test_the_crosshair_sits_on_the_shot_line_at_every_resolution() -> void:
	_profile.projectile_gravity = 0.0
	var wall: StaticBody3D = _add_wall(CENTRE_DISTANCE)
	await step_ticks(1)
	for resolution: Vector2i in RESOLUTIONS:
		_set_resolution(resolution)
		var impact: Vector3 = _fire_and_land()
		_reticle.refresh()
		var expected: Vector2 = _camera.unproject_position(impact)
		var drawn: Vector2 = _reticle.get_screen_centre()
		check(
			drawn.distance_to(expected) <= PIXEL_TOLERANCE,
			"at %s the reticle centre %s must be where the shot lands, %s" % [resolution, drawn, expected]
		)
	wall.queue_free()


func test_each_holdover_mark_sits_where_the_round_lands() -> void:
	for resolution: Vector2i in RESOLUTIONS:
		_set_resolution(resolution)
		_reticle.refresh()
		var count: int = _reticle.get_mark_count()
		assert_ge(count, 3, "at %s at least three holdover marks fit in the scope" % [resolution])
		var marks: PackedVector2Array = PackedVector2Array()
		var distances: PackedFloat32Array = PackedFloat32Array()
		for i: int in range(count):
			marks.append(_reticle.get_mark_screen_position(i))
			distances.append(_reticle.get_mark_distance(i))
		for i: int in range(count):
			var wall: StaticBody3D = _add_wall(distances[i])
			await step_ticks(1)
			var impact: Vector3 = _fire_and_land()
			wall.queue_free()
			await step_ticks(1)
			var expected: Vector2 = _camera.unproject_position(impact)
			check(
				marks[i].distance_to(expected) <= PIXEL_TOLERANCE,
				"at %s the %d m mark %s must be where the round lands, %s" % [resolution, int(distances[i]), marks[i], expected]
			)


func test_no_marks_without_drop_or_without_a_travelling_round() -> void:
	_profile.projectile_gravity = 0.0
	_reticle.refresh()
	assert_eq_int(_reticle.get_mark_count(), 0, "a round that does not fall gets no holdover marks")
	_profile.projectile_gravity = DROP
	_rules.guard_projectile_speed = 0.0
	_reticle.refresh()
	assert_eq_int(_reticle.get_mark_count(), 0, "a hitscan shot gets no holdover marks")
	_rules.guard_projectile_speed = SHOT_SPEED
	_reticle.holdover_marks = false
	_reticle.refresh()
	assert_eq_int(_reticle.get_mark_count(), 0, "marks switched off draws none")


func test_the_vignette_shows_and_hides_the_reticle_with_itself() -> void:
	var vignette: ScopeVignette = _rifle.get_node(^"ScopeVignette") as ScopeVignette
	assert_not_null(vignette.reticle, "the scope overlay must carry its reticle")
	assert_same(vignette.reticle.ads, vignette.ads, "the reticle reads the rifle the vignette does")
	assert_false(vignette.reticle.visible, "no reticle at hipfire")


# --- Helpers ------------------------------------------------------------------

func _set_resolution(resolution: Vector2i) -> void:
	_view.size = resolution
	_reticle.size = Vector2(resolution)


## A wall square to the aim, its face [param distance] metres down the shot line.
func _add_wall(distance: float) -> StaticBody3D:
	var aim: Vector3 = -_camera.global_transform.basis.z
	var wall: StaticBody3D = TestFixtures.make_box_body(
		Vector3(80.0, 80.0, WALL_HALF_DEPTH * 2.0), Vector3.ZERO, "Wall"
	)
	_world.add_child(wall)
	wall.global_transform = Transform3D(
		_camera.global_transform.basis, EYE + aim * (distance + WALL_HALF_DEPTH)
	)
	return wall


func _fire_and_land() -> Vector3:
	_rifle.reset_reload_to_base()
	_rifle.tick(_rifle.get_time_to_ready() + 0.001)
	_landed = false
	assert_true(_rifle.try_fire(), "the rifle takes the shot")
	var ticks: int = 0
	while not _landed and ticks < MAX_FLIGHT_TICKS:
		_rifle.tick(SIM_DELTA)
		ticks += 1
	assert_true(_landed, "the round reached the wall")
	return _impact


func _on_landed(_collider: Node3D, at: Vector3, _normal: Vector3) -> void:
	_landed = true
	_impact = at


func _on_missed(at: Vector3) -> void:
	_landed = true
	_impact = at
