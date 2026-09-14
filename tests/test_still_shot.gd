extends TestCase

## tools/shot.gd poses its camera once the camera is in the tree.

func test_camera_stands_at_the_requested_pose() -> void:
	var pos: Vector3 = Vector3(12.0, 3.5, -40.0)
	var look: Vector3 = Vector3(-6.0, 1.0, 9.0)
	var camera: Camera3D = StillShot.build_camera(self, pos, look)
	assert_true(camera.is_inside_tree(), "the camera is in the tree")
	assert_vec3_almost_eq(camera.global_position, pos, 0.001, "camera stands where asked")
	var forward: Vector3 = -camera.global_transform.basis.z
	assert_vec3_almost_eq(forward, (look - pos).normalized(), 0.001, "camera faces the look point")
	assert_almost_eq(camera.fov, 100.0, 0.001, "camera fov is 100")
