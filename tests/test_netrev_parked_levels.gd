extends NetPowerRig

## Review proof: a parked client's HELD keys stand on the host after they are let go.


func test_rv_keys_released_while_parked_are_released_on_host() -> void:
	if not await stand_up():
		return
	await step_ticks(30)
	var mine: PlayerController = body_of(a_links, A_SEAT)
	var copy: PlayerController = body_of(host_links, A_SEAT)
	a_keys.held.move_direction = Vector2(0.0, 1.0)
	a_keys.held.fire_held = true
	await step_ticks(20)
	# The client's copy is parked (it has not heard of the wake yet); the player lets go of everything.
	mine.set_held(true)
	a_keys.held.move_direction = Vector2.ZERO
	a_keys.held.fire_held = false
	await step_ticks(15)
	var from: Vector3 = copy.global_position
	var fire_ticks: int = 0
	for _i: int in 30:
		await step_ticks(1)
		if copy.get_intent().fire_held:
			fire_ticks += 1
	var ran: float = copy.global_position.distance_to(from)
	print("PROOF parked-levels: 15..45 ticks after the keys were released the host's copy ran %.2f m and read fire held on %d of 30 ticks" % [ran, fire_ticks])
	assert_true(ran < 0.2, "released keys stop the host's copy: it ran %.2f m" % ran)
	assert_eq_int(fire_ticks, 0, "a released trigger is released on the host")
