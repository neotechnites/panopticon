extends NetPowerRig

## Review suspect: where a mirror raises a running player's shield against where the host raised it.

const SHIELD: int = MatchRules.RunnerAbility.BUBBLE_SHIELD


func _shield_of(links: Array[PlayerNetLink], seat: int) -> Node3D:
	return body_of(links, seat).get_parent().get_node_or_null("BubbleShield") as Node3D


func test_a_running_players_shield_stands_where_the_host_raised_it() -> void:
	if not await stand_up(0.0, 1):
		return
	TestFixtures.set_power_duration(5.0)
	await step_ticks(10)
	a_keys.held.move_direction = Vector2(0.0, 1.0)
	await step_ticks(45)
	a_keys.tap_power(SHIELD)
	if not await until(func() -> bool: return all_draw(A_SEAT, SHIELD)):
		fail("the shield never went up everywhere: %s" % str(drawn(A_SEAT)))
		return
	await step_ticks(10)
	var on_host: Node3D = _shield_of(host_links, A_SEAT)
	var on_a: Node3D = _shield_of(a_links, A_SEAT)
	var on_b: Node3D = _shield_of(b_links, A_SEAT)
	if on_host == null or on_a == null or on_b == null:
		fail("a shield is missing: host %s A %s B %s" % [str(on_host), str(on_a), str(on_b)])
		return
	var speed: float = body_of(host_links, A_SEAT).velocity.length()
	var b_off: float = on_b.global_position.distance_to(on_host.global_position)
	var a_off: float = on_a.global_position.distance_to(on_host.global_position)
	print("PROOF shield-place: at %.1f m/s the watcher's shield stands %.2f m from the host's, the presser's own %.2f m (radius %.1f m)" % [
		speed, b_off, a_off, RunnerPower.SHIELD_RADIUS])
	assert_lt(b_off, 0.05, "the watcher's shield stands where the host raised it")
	assert_lt(a_off, 0.05, "and so does the presser's own")
