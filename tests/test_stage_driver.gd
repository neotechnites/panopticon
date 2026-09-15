extends TestCase

## The b-roll stage driver's primitives do what a stage file says they do:
## a body placed at ring-polar coordinates is there, a timed beat fires on the
## driver's clock, a leap lands where it was aimed, the macros expand to the
## primitives, the safe zone maths holds, and two bodies seeded apart do not
## move in lockstep. Nothing here touches a match; the driver is capture-only.

const DRIVER := preload("res://tools/capture/stage_driver.gd")
const LIB := preload("res://tools/capture/stages/lib.gd")

var _floor_body: StaticBody3D


func before_each() -> void:
	_floor_body = TestFixtures.make_floor(DRIVER.DECK_Y)
	add_child(_floor_body)


func _body(at: Vector3) -> PlayerController:
	var body: PlayerController = TestFixtures.make_bot_player(TestFixtures.movement_profile())
	body.position = at
	add_child(body)
	return body


func _drive(body: PlayerController, steps: Array) -> Node:
	var driver: Node = DRIVER.new()
	add_child(driver)
	driver.install(body, null, steps)
	return driver


func test_place_puts_the_body_on_the_ring_polar_point() -> void:
	var body: PlayerController = _body(Vector3(0.0, DRIVER.DECK_Y + 0.1, 0.0))
	var driver: Node = _drive(body, [{"do": "place", "deg": 195.0, "r": 52.0, "h": 0.1}, {"do": "hold", "seconds": 0.2}])
	await step_ticks(3)
	var want: Vector3 = LIB.ring_point(195.0, 52.0, 0.1)
	assert_almost_eq(LIB.bearing_of(body.global_position), 195.0, 0.2, "the body stands at the bearing asked for")
	assert_almost_eq(LIB.radius_of(body.global_position), 52.0, 0.1, "at the radius asked for")
	assert_lt(absf(body.global_position.x - want.x), 0.1, "x from the ring's own convention (x = cos * r)")
	assert_false(driver.is_done(), "and the hold is still running")


func test_until_is_a_timed_beat_on_the_driver_clock() -> void:
	var body: PlayerController = _body(LIB.ring_point(20.0, 52.0, 0.1))
	var driver: Node = _drive(body, [{"do": "until", "t": 0.5}])
	await step_ticks(int(0.5 * SIM_HZ) - 3)
	assert_false(driver.is_done(), "half a second in, the beat has not fired")
	await step_ticks(6)
	assert_true(driver.is_done(), "the beat fires when the clock reads t")
	assert_almost_eq(driver.clock(), 0.55, 0.05, "the clock counts seconds since install")


func test_a_leap_lands_where_it_was_aimed() -> void:
	var from: Vector3 = LIB.ring_point(30.0, 52.0, 0.1)
	var to: Vector3 = LIB.ring_point(30.0 + rad_to_deg(6.0 / 52.0), 52.0, 0.0)
	var body: PlayerController = _body(from)
	var driver: Node = _drive(body, [
		{"do": "hold", "seconds": 0.2},
		{"do": "leap", "to": to, "speed": 8.0},
		{"do": "land"},
		{"do": "hold", "seconds": 5.0},
	])
	await step_seconds(2.0)
	assert_false(driver.is_done(), "it is holding after the landing")
	var flat: float = Vector2(body.global_position.x - to.x, body.global_position.z - to.z).length()
	assert_lt(flat, 0.8, "the body came down within a step of the target (%.2f m off)" % flat)
	assert_true(body.is_on_floor(), "and is on the floor")


func test_a_hold_with_crouch_crouches_the_body() -> void:
	var body: PlayerController = _body(LIB.ring_point(40.0, 52.0, 0.1))
	_drive(body, [{"do": "hold", "seconds": 5.0, "crouch": true}])
	await step_ticks(20)
	assert_true(body.is_crouching() or body.is_sliding(), "the slide key is held for the whole hold")


func test_the_macros_expand_to_primitives() -> void:
	var looked: Array = DRIVER.expand([{"do": "look_back", "degrees": -140.0, "seconds": 0.42, "hold": 0.3, "back": 0.6}])
	assert_eq_int(looked.size(), 3, "look_back is a turn, a hold and a turn back")
	assert_eq_string(String(looked[0]["do"]), "turn", "over the shoulder first")
	assert_almost_eq(float(looked[2]["degrees"]), 140.0, 0.001, "and back by the same angle")
	var flinched: Array = DRIVER.expand([{"do": "flinch"}])
	assert_gt(float(flinched.size()), 4.0, "a flinch is several glances and a hold")
	for step: Dictionary in flinched:
		assert_true(String(step["do"]) in ["glance", "hold"], "made only of glance and hold (%s)" % step["do"])


func test_the_safe_zone_maths() -> void:
	var zone := {"from": 181.0, "to": 208.5, "r_min": 47.6, "r_max": 56.5}
	assert_true(DRIVER._inside(LIB.ring_point(195.0, 52.0, 0.0), zone, 0.0), "the middle of the melee ground is inside")
	assert_false(DRIVER._inside(LIB.ring_point(178.0, 52.0, 0.0), zone, 0.0), "the S3 pad at 177 is outside")
	assert_false(DRIVER._inside(LIB.ring_point(195.0, 46.5, 0.0), zone, 0.0), "over the rim is outside")
	assert_false(DRIVER._inside(LIB.ring_point(195.0, 48.0, 0.0), zone, 0.8), "and the margin pulls the edge in")


func test_two_bodies_seeded_apart_do_not_fidget_in_lockstep() -> void:
	var a: PlayerController = _body(LIB.ring_point(50.0, 52.0, 0.1))
	var b: PlayerController = _body(LIB.ring_point(60.0, 52.0, 0.1))
	var da: Node = _drive(a, [{"do": "human", "on": true}, {"do": "hold", "seconds": 6.0, "fidget": true}])
	var db: Node = _drive(b, [{"do": "human", "on": true}, {"do": "hold", "seconds": 6.0, "fidget": true}])
	da.seed_with(20260930, 0)
	db.seed_with(20260930, 1)
	var same: int = 0
	var samples: int = 0
	for _i: int in 40:
		await step_ticks(3)
		samples += 1
		if is_equal_approx(a.get_intent().move_direction.x, b.get_intent().move_direction.x):
			same += 1
	assert_lt(float(same), float(samples), "the strafe taps differ between the two bodies (%d of %d samples alike)" % [same, samples])
