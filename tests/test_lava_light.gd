extends TestCase

## Hell's lava light: [LavaLightWave].


## The swell keeps every light inside its energy swing and its bob.
func test_wave_swings_energy_inside_its_bounds() -> void:
	var wave: LavaLightWave = LavaLightWave.new()
	var light: OmniLight3D = OmniLight3D.new()
	light.light_energy = 2.0
	light.position = Vector3(30.0, 24.2, 40.0)
	wave.add_child(light)
	add_child(wave)
	var seen: PackedFloat32Array = PackedFloat32Array()
	for _i: int in 6:
		wave._process(0.0)
		seen.append(light.light_energy)
		OS.delay_msec(120)
	for energy: float in seen:
		assert_between(energy, 2.0 * (1.0 - wave.energy_swing), 2.0 * (1.0 + wave.energy_swing), "energy inside the swing")
	assert_between(light.position.y, 24.2 - 1e-4, 24.2 + 2.0 * wave.bob_metres + 1e-4, "the bob never dips below rest")
