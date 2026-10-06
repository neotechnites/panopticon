extends TestCase

## Hell's lava light: [LavaHazeField] (the crack's haze over a lava body) and [LavaLightWave].


## One surface, four triangles a crossed panel and two a face-on one, through one material per scale.
func test_haze_field_is_one_surface_of_crack_panels_sharing_a_material_per_scale() -> void:
	var crossed: LavaHazeField = _field(true, 2.5)
	var flat: LavaHazeField = _field(false, 2.5)
	assert_eq_int(crossed.mesh.get_surface_count(), 1, "one surface for the whole field")
	assert_eq_int(crossed.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() / 3, 12, "three crossed panels, 4 tris each")
	assert_eq_int(flat.mesh.surface_get_arrays(0)[Mesh.ARRAY_INDEX].size() / 3, 6, "three face-on panels, 2 tris each")
	assert_same(crossed.material_override, flat.material_override, "the same material at the same scale")
	var height: float = (crossed.material_override as ShaderMaterial).get_shader_parameter(&"haze_height_metres")
	assert_almost_eq(height, LavaHaze.HEIGHT_METRES * 2.5, 1e-4, "its rise height scaled with the panel")
	assert_same(LavaHazeField.material_for(1.0), load("res://maps/bentham_ring/materials/lava_haze_material.tres"), "scale 1 is the crack's own")
	assert_true(crossed.is_in_group(&"lava_haze"), "and it registers as haze")


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
	assert_le(absf(light.position.y - 24.2), wave.bob_metres + 1e-4, "the bob stays inside its metres")


func _field(crossed: bool, scale_by: float) -> LavaHazeField:
	var field: LavaHazeField = LavaHazeField.new()
	field.crossed = crossed
	field.panel_scale = scale_by
	field.panels = PackedVector4Array([Vector4(0, 0, 0, 0), Vector4(5, 0, 0, 0.5), Vector4(0, 0, 5, 1.0)])
	add_child(field)
	return field
