extends NetPowerRig
## Playtest regression: a hologram a machine only mirrors is drawn running on the floor, not standing in the air pose.

const HOLOGRAM: int = MatchRules.RunnerAbility.HOLOGRAM
## Ticks a mirrored hologram is given to be placed twice, and the ticks its drawn pose is then read for.
const WARM_TICKS: int = 12
const WATCH_TICKS: int = 20


## [param seat]'s hologram as each machine in [param mirrors] draws it, watched while the host's runs.
func _watch_a_mirrored_hologram(seat: int, mirrors: Array, names: PackedStringArray) -> void:
	var built: bool = await until(func() -> bool:
		if power_of(host_links, seat).get_decoy() == null:
			return false
		for links: Array[PlayerNetLink] in mirrors:
			if power_of(links, seat).get_hologram() == null:
				return false
		return true)
	if not assert_true(built, "the hologram exists on the host and on every machine that mirrors it"):
		return
	await step_ticks(WARM_TICKS)
	var missed: PackedInt32Array = PackedInt32Array()
	missed.resize(mirrors.size())
	var watched: int = 0
	for _tick: int in WATCH_TICKS:
		await step_ticks(1)
		var real: PlayerController = power_of(host_links, seat).get_decoy()
		if real == null or real.get_horizontal_speed() < 2.0:
			break
		watched += 1
		for index: int in mirrors.size():
			var links: Array[PlayerNetLink] = mirrors[index]
			var view: HologramView = power_of(links, seat).get_hologram()
			var runs: bool = view != null and view.get_clip() == HologramView.RUN_CLIP \
				and Vector2(view.get_velocity().x, view.get_velocity().z).length() > 2.0
			if not runs:
				missed[index] += 1
	assert_gt(float(watched), 10.0, "the host's hologram ran while it was watched")
	for index: int in mirrors.size():
		assert_eq_int(missed[index], 0, "ticks on which %s did not draw the hologram running on the floor" % names[index])


func test_a_clients_hologram_is_drawn_running_on_the_machines_that_mirror_it() -> void:
	if not await stand_up():
		return
	a_keys.tap_slot(HOLOGRAM)
	await _watch_a_mirrored_hologram(A_SEAT, [a_links, b_links], PackedStringArray(["the client that sent it", "the third machine"]))


func test_the_hosts_hologram_is_drawn_running_on_both_clients() -> void:
	if not await stand_up():
		return
	host_keys.tap_slot(HOLOGRAM)
	await _watch_a_mirrored_hologram(HOST_SEAT, [a_links, b_links], PackedStringArray(["client A", "client B"]))


func test_a_clients_hologram_is_drawn_running_at_40_ms() -> void:
	if not await stand_up(0.0, 40):
		return
	a_keys.tap_slot(HOLOGRAM)
	await _watch_a_mirrored_hologram(A_SEAT, [a_links, b_links], PackedStringArray(["the client that sent it", "the third machine"]))
