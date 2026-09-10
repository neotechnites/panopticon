extends TestCase

## [PanopticonEye]: the promise that the eye hides the guard and tells the
## prisoners nothing.
##
## Since 2026-09-10 the eye is one box, 18 m across and 4.5 m tall, standing on
## the tower platform with the guard inside it and a picture of an eye repeated
## along every face. Most of what could be tested about it is a screenshot and
## belongs on a person's monitor. What is here instead are the properties that
## make it a [b]one-way[/b] mirror, because those are exactly the ones that can be
## destroyed by a plausible-looking edit and will not raise anything when they
## are:
##
## - the whole mechanism is backface culling. Reverse it and the box turns inside
##   out: the guard is walled in and the ring sees straight through to them. That
##   is one enum away at all times and looks fine in a diff;
## - the box only hides the guard while it still encloses the platform they walk
##   on and still stands over their head at the top of a jump. Shrink it and the
##   cover silently stops covering;
## - the old eye was a solid of revolution, so it could not have a front. A box
##   can. Every side must carry the same picture the same way up and the same
##   size, from one material and one texture, or the box acquires a bearing;
## - a mesh nudged off the axis, rotated, or made oblong gives it a bearing too;
## - a line of code that reads the camera, the rifle, the seat or the match hands
##   the prisoners the one thing the game is built on withholding;
## - a collision shape added "so runners cannot clip it" puts the eye on the
##   rifle's hit mask, walls the guard into their own cover, and makes the guard
##   shoot the inside of it.
##
## None of those would fail any other test in this suite, and none of them looks
## wrong in a diff. So they are asserted here. See the class documentation of
## [PanopticonEye] for the design rulings this defends.

const EYE_SCENE_PATH: String = "res://scenes/tower/panopticon_eye.tscn"

## The two files that make up the eye. Both are read as text below, because the
## promise that the eye knows nothing about the guard is a fact about the source
## rather than about any value it happens to hold at runtime.
const EYE_SOURCE_PATHS: Array[String] = [
	"res://scripts/tower/panopticon_eye.gd",
	"res://scripts/tower/eye_profile.gd",
]

## Radius of Tower/Platform in [code]scenes/ring/test_ring.tscn[/code], and so
## the furthest from the axis a guard can stand before they fall off it. The box
## has to reach past this in every direction or the guard can walk out of their
## own cover.
const PLATFORM_RADIUS: float = 8.0

## Where [code]scenes/ring/test_ring.tscn[/code] puts the guard, and what this
## file checks the eye did not move.
const TOWER_SPAWN_POSITION: Vector3 = Vector3(0.0, 0.25, 0.0)

## The guard's eye, and so the height of the middle of the box.
##
## They spawn at y=0.25 and [code]scenes/player/player.tscn[/code] puts Head
## 1.65 m above their feet. This is the number the eye was brought down to on
## 2026-09-10: it used to float at y=16.7 while the guard sat here, and Ryan
## settled that disagreement in this direction.
const GUARD_EYE_Y: float = 1.9

## The top of the guard's head at the apex of a jump: the capsule is 1.8 m tall
## with its feet at the body origin, they spawn 0.25 m up, and the tuned apex is
## 1.11 m. The box has to be taller than this or a jumping guard's scalp appears
## over the top of their own cover.
const GUARD_CROWN_Y: float = 3.16

## The top surface of Tower/Platform. The box's underside must be at or below it,
## or there is a gap along the bottom for the ring to look through.
const PLATFORM_TOP_Y: float = 0.0

var _eye: PanopticonEye


func before_each() -> void:
	_eye = _make_eye()
	add_child(_eye)


func _make_eye() -> PanopticonEye:
	var scene: PackedScene = load(EYE_SCENE_PATH) as PackedScene
	return scene.instantiate() as PanopticonEye


## Every [MeshInstance3D] in the eye, in tree order.
func _surfaces_of(eye: Node3D) -> Array[MeshInstance3D]:
	var found: Array[MeshInstance3D] = []
	for node: Node in _descendants_of(eye):
		var surface: MeshInstance3D = node as MeshInstance3D
		if surface != null:
			found.append(surface)
	return found


func _descendants_of(node: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child: Node in node.get_children():
		found.append(child)
		found.append_array(_descendants_of(child))
	return found


## Where a surface actually sits in the world, box and all.
func _world_bounds_of(surface: MeshInstance3D) -> AABB:
	return surface.global_transform * surface.mesh.get_aabb()


# --- The one-way mirror -------------------------------------------------------

## The mechanism, asserted directly.
##
## Everything about this eye rests on one enum. The box is a closed surface with
## its triangles facing outward: drawn [constant BaseMaterial3D.CULL_BACK] the
## ring sees an opaque wall and the guard, who is inside, sees every face thrown
## away before it is shaded. Drawn [constant BaseMaterial3D.CULL_FRONT] it is
## exactly backwards -- the guard is boxed into a black room and the prisoners
## look straight through the walls at them. That is the whole mechanic inverted
## by one line in the inspector, and nothing else in the suite would notice.
##
## So: the material culls back faces, and the guard's eye is genuinely inside the
## box rather than merely near it, because culling only hides the surface from
## somebody who is actually within the solid.
func test_the_guard_is_inside_the_mirror_and_sees_out_of_it() -> void:
	var surfaces: Array[MeshInstance3D] = _surfaces_of(_eye)
	if not assert_eq_int(surfaces.size(), 1, "the eye should be one closed box"):
		return

	for surface: MeshInstance3D in surfaces:
		var material: StandardMaterial3D = surface.get_surface_override_material(0) as StandardMaterial3D
		if not assert_not_null(material, "%s should have a material" % surface.name):
			continue
		assert_eq_int(material.cull_mode, BaseMaterial3D.CULL_BACK,
			"%s must cull BACK faces: FRONT walls the guard in and shows the ring straight through" % surface.name)

	var bounds: AABB = _world_bounds_of(surfaces[0])
	var guard_eye: Vector3 = Vector3(TOWER_SPAWN_POSITION.x, GUARD_EYE_Y, TOWER_SPAWN_POSITION.z)
	assert_true(bounds.has_point(guard_eye),
		"the guard's eye at y=%.2f should be inside the box, or culling hides nothing from them" % GUARD_EYE_Y)


## The cover actually covers, at every size the profile allows.
##
## The box hides the guard only while it still encloses the ground they can walk
## on and still stands over their head. Both of those stop being true quietly if
## the box shrinks, and a guard whose scalp shows over their own cover, or who
## can stroll out through the side of it, has lost the entire premise without
## anything erroring.
##
## The footprint is checked against the platform's radius rather than its
## diameter deliberately: the platform is a disc and the box is a square around
## it, so it is the half-width that has to clear r=8 -- in every direction, which
## is why the plan has to be square as well as big.
func test_the_box_covers_the_shooter() -> void:
	var bounds: Vector2 = _size_scale_range()
	assert_gt(bounds.x, 0.0, "size_scale should expose a range")

	for size_scale: float in [bounds.x, 1.0, bounds.y]:
		var profile: EyeProfile = EyeProfile.new()
		profile.size_scale = size_scale
		profile.eye_texture = _eye.profile.eye_texture
		var eye: PanopticonEye = _make_eye()
		eye.profile = profile
		add_child(eye)

		assert_almost_eq(eye.scale.x, size_scale, 0.0001, "the rig should take the profile's size")

		for surface: MeshInstance3D in _surfaces_of(eye):
			var box: AABB = _world_bounds_of(surface)
			assert_ge(0.5 * box.size.x, PLATFORM_RADIUS,
				"at size_scale %.2f the box reaches only %.2f m from the axis in X; the guard can walk out of cover at %.2f" % [
					size_scale, 0.5 * box.size.x, PLATFORM_RADIUS,
				])
			assert_ge(0.5 * box.size.z, PLATFORM_RADIUS,
				"at size_scale %.2f the box reaches only %.2f m from the axis in Z" % [
					size_scale, 0.5 * box.size.z,
				])
			assert_gt(box.position.y + box.size.y, GUARD_CROWN_Y,
				"at size_scale %.2f the box tops out at y=%.2f, under a jumping guard's crown" % [
					size_scale, box.position.y + box.size.y,
				])
			assert_le(box.position.y, PLATFORM_TOP_Y,
				"at size_scale %.2f the box's underside is at y=%.2f, leaving a gap to see under" % [
					size_scale, box.position.y,
				])


func _size_scale_range() -> Vector2:
	for property: Dictionary in EyeProfile.new().get_property_list():
		if String(property["name"]) == "size_scale":
			var bounds: PackedStringArray = String(property["hint_string"]).split(",")
			if bounds.size() >= 2:
				return Vector2(bounds[0].to_float(), bounds[1].to_float())
	return Vector2.ZERO


# --- The form cannot point anywhere -------------------------------------------

## The box has no long side, no tilt and no offset.
##
## The eye used to be a sphere and a cylinder -- solids of revolution, identical
## from every bearing, incapable of indicating a direction whatever a later
## [method Node._process] did to them. Ryan asked for a box instead, so that
## argument is gone and the geometry has to earn the same result another way: one
## closed box, square in plan, on the tower's own axis, unrotated. Square in plan
## matters as much as unrotated does -- an oblong has a broad side and a narrow
## side, and a prisoner who can tell which one they are standing in front of
## knows something about the tower's layout.
func test_the_form_is_a_box_with_no_readable_side() -> void:
	var surfaces: Array[MeshInstance3D] = _surfaces_of(_eye)
	if not assert_eq_int(surfaces.size(), 1, "the eye should be one box, and nothing else"):
		return

	var face: MeshInstance3D = surfaces[0]
	var box: BoxMesh = face.mesh as BoxMesh
	if not assert_not_null(box, "the eye should be a BoxMesh -- one closed solid, opaque from every angle"):
		return

	assert_almost_eq(box.size.x, box.size.z, 0.0001,
		"the box should be square in plan, or it has a broad side and a narrow one")

	assert_almost_eq(face.position.x, 0.0, 0.0001, "the box should sit on the tower's axis in X")
	assert_almost_eq(face.position.z, 0.0, 0.0001, "the box should sit on the tower's axis in Z")

	var turn: Quaternion = face.transform.basis.get_rotation_quaternion()
	assert_almost_eq(turn.angle_to(Quaternion.IDENTITY), 0.0, 0.0001,
		"the box should be unrotated -- a turned box is a box that has been pointed")

	var scaling: Vector3 = face.transform.basis.get_scale()
	assert_almost_eq(scaling.x, scaling.z, 0.0001,
		"the box should be scaled equally in X and Z, or it is oblong after all")


## Every side is the same picture, the same way up, at the same size.
##
## This is the assertion that replaces "it is a solid of revolution", and it is
## the load-bearing one. [BoxMesh] lays its six faces out as a three-by-two UV
## atlas, so a texture applied naively puts a [i]different sixth of the image[/i]
## on each face -- six sides that are all different, which is the exact opposite
## of what is wanted and looks perfectly reasonable in the inspector.
## [method PanopticonEye.uv_tiling_for] scales UV1 by that atlas shape, times the
## face's own aspect, so each cell maps onto whole upright copies of the picture
## and every copy comes out square.
##
## One material and one texture for the whole box is the other half: two
## materials could be tuned apart, and a second texture is a second picture.
func test_every_side_carries_the_same_picture() -> void:
	var surfaces: Array[MeshInstance3D] = _surfaces_of(_eye)
	var materials: Array[Material] = []
	for surface: MeshInstance3D in surfaces:
		assert_eq_int(surface.mesh.get_surface_count(), 1,
			"%s should be one surface, or its faces can be given different materials" % surface.name)
		for index: int in surface.mesh.get_surface_count():
			var found: Material = surface.get_surface_override_material(index)
			if not materials.has(found):
				materials.append(found)

	assert_eq_int(materials.size(), 1,
		"the whole eye should draw with exactly one material, or its sides can drift apart")
	if materials.is_empty():
		return

	var material: StandardMaterial3D = materials[0] as StandardMaterial3D
	if not assert_not_null(material, "the box should have a StandardMaterial3D"):
		return

	assert_not_null(material.albedo_texture, "the box should carry the eye picture on it")
	var box: BoxMesh = surfaces[0].mesh as BoxMesh
	assert_vec3_almost_eq(material.uv1_scale, PanopticonEye.uv_tiling_for(box.size), 0.0001,
		"UV1 must be scaled by the box atlas, or each face shows a different sixth of the picture")
	assert_vec3_almost_eq(material.uv1_offset, Vector3.ZERO, 0.0001,
		"a UV offset would slide the picture along by a different amount on each face")
	assert_true(material.texture_repeat,
		"the tiled UVs need repeat, or all but one copy clamps to a smear of one edge")


## The picture comes out square on the vertical faces, at any proportions.
##
## The tiling exists so that a face four times wider than it is tall shows four
## eyes rather than one eye stretched four times wide. That is a property of the
## arithmetic, not of the numbers currently in the scene, so it is asserted
## against the arithmetic: for a range of box shapes, one repeat of the picture
## must be as wide on the wall as it is high.
func test_the_picture_never_comes_out_stretched() -> void:
	for shape: Vector3 in [Vector3(18.0, 4.5, 18.0), Vector3(8.0, 8.0, 8.0), Vector3(30.0, 3.0, 30.0)]:
		var tiling: Vector3 = PanopticonEye.uv_tiling_for(shape)
		# Repeats across a vertical face, and up it. UV_ATLAS is how much of the
		# texture one face spans before any scaling.
		var across: float = tiling.x / PanopticonEye.UV_ATLAS.x
		var up: float = tiling.y / PanopticonEye.UV_ATLAS.y
		assert_almost_eq(shape.x / across, shape.y / up, 0.0001,
			"on an %.1f x %.1f face one copy of the picture should be square" % [shape.x, shape.y])


## The eye has no way of knowing where the guard is looking, because it has no
## way of referring to the guard at all.
##
## This is a fact about the source rather than about any value, so it is asserted
## against the source. The prose in those files discusses cameras, rifles, seats
## and the match at length -- that is the whole point of the prose -- so comments
## are stripped before the scan and only executable text is searched.
##
## A rotation is forbidden on the same grounds. All four sides are identical, so
## turning the box could not actually leak anything today; but a box that turns
## is one texture edit away from a box that points, and there is no reason for
## the eye to move at all.
func test_the_eye_cannot_see_the_guard() -> void:
	var forbidden: Array[String] = [
		"camera", "rifle", "weapon", "seat", "matchcontroller", "runner", "player",
		"aim", "get_viewport", "get_tree", "look_at", "rotat", "signal", "match_",
	]

	for path: String in EYE_SOURCE_PATHS:
		var source: String = FileAccess.get_file_as_string(path)
		if not assert_gt(float(source.length()), 0.0, "%s should be readable" % path):
			continue

		var code: String = ""
		for line: String in source.split("\n"):
			var comment: int = line.find("#")
			code += (line if comment < 0 else line.substr(0, comment)) + "\n"
		code = code.to_lower()

		for word: String in forbidden:
			assert_false(code.contains(word),
				"%s mentions '%s' in code: the eye must not be able to refer to the guard" % [path, word])


## Nothing in the eye moves, ever -- not the rig, not the box -- so a prisoner
## watching it for a whole round sees the same wall they saw at spawn.
func test_nothing_in_the_eye_ever_moves() -> void:
	var surfaces: Array[MeshInstance3D] = _surfaces_of(_eye)
	var before: Array[Transform3D] = []
	for surface: MeshInstance3D in surfaces:
		before.append(surface.global_transform)
	var rig_before: Transform3D = _eye.global_transform

	await step_seconds(2.0)

	assert_false(_eye.is_processing(), "the eye should not process at all -- there is nothing to animate")
	assert_true(_eye.global_transform.is_equal_approx(rig_before), "the eye rig should not have moved")
	for index: int in surfaces.size():
		assert_true(
			surfaces[index].global_transform.is_equal_approx(before[index]),
			"%s should not have moved" % surfaces[index].name,
		)


## Opaque, unshaded, and depth-tested.
##
## Transparency would let a prisoner see the guard through their own cover, which
## is the failure the whole node exists to prevent. Shading is the one that is
## specific to a box: the arena's sun would put a highlight on whichever face it
## favours and leave the opposite one dim, so the four sides would stop matching
## -- a tell arrived at by lighting rather than by anybody meaning it, and one
## that changes through the day. No depth test draws the box over the whole ring
## from anywhere on the map. Culling has its own test above.
func test_the_eye_is_opaque_and_unshaded() -> void:
	for surface: MeshInstance3D in _surfaces_of(_eye):
		var material: StandardMaterial3D = surface.get_surface_override_material(0) as StandardMaterial3D
		if not assert_not_null(material, "%s should have a material" % surface.name):
			continue
		assert_eq_int(material.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED,
			"%s must be unshaded, or the sun tells one side of the box from another" % surface.name)
		assert_eq_int(material.transparency, BaseMaterial3D.TRANSPARENCY_DISABLED,
			"%s must be opaque, or prisoners can see the guard through it" % surface.name)
		assert_almost_eq(material.albedo_color.a, 1.0, 0.0001,
			"%s must be fully opaque, or prisoners can see the guard through it" % surface.name)
		assert_false(material.no_depth_test,
			"%s must depth-test, or it draws over the ring" % surface.name)


# --- Scenery, not a mechanic --------------------------------------------------

## The eye has no gameplay and must not acquire any by accident.
##
## A collision shape is the way it would happen, and now that the box is wrapped
## round the guard it would do three separate kinds of damage at once: the rifle
## raycasts against the world, so the guard's own shots would stop dead on the
## inside of their cover; the guard would be sealed into an 18 m room they cannot
## leave; and runners would collide with a wall that is supposed to be scenery.
func test_the_eye_is_inert() -> void:
	for node: Node in _descendants_of(_eye):
		assert_null(node as CollisionObject3D,
			"%s: the eye must have no physics body, or the guard shoots and is trapped by their own cover" % node.name)
		assert_null(node as CollisionShape3D, "%s: the eye must have no collision shape" % node.name)
		assert_null(node as Camera3D, "%s: the eye must not own a viewpoint" % node.name)
		assert_null(node as Light3D,
			"%s: the eye must not cast light -- a lit patch on the deck is a signal" % node.name)
		assert_null(node.get_script() as Script,
			"%s: only the rig root carries a script" % node.name)


# --- The profile is the source of truth ---------------------------------------

## What the resource says is what the eye is, and it lands on the material the
## mesh actually draws with.
##
## The second half of that matters more than it looks. The material is
## local-to-scene, so each instance gets a duplicate; if the duplication ever
## stopped remapping the export on the rig, the picture below would still be
## written, to an object nothing renders, and the eye would quietly go back to
## its authored blank with the profile appearing to work.
func test_the_profile_reaches_the_rendered_material() -> void:
	var picture: Texture2D = PlaceholderTexture2D.new()
	var profile: EyeProfile = EyeProfile.new()
	profile.eye_texture = picture

	var eye: PanopticonEye = _make_eye()
	eye.profile = profile
	add_child(eye)

	var box: MeshInstance3D = eye.get_node("Box") as MeshInstance3D
	if not assert_not_null(box, "the eye should have a Box"):
		return
	assert_same(box.get_surface_override_material(0), eye.face_material,
		"the rendered material should be the one the script writes to")

	var material: StandardMaterial3D = box.get_surface_override_material(0) as StandardMaterial3D
	assert_same(material.albedo_texture, picture, "the picture should come from the profile")
	assert_vec3_almost_eq(material.uv1_scale, PanopticonEye.uv_tiling_for((box.mesh as BoxMesh).size), 0.0001,
		"the script should re-derive the tiling from the box, whatever the scene was saved with")


## Two eyes in one world do not share a material, so tuning one cannot reach the
## other -- and, in this suite, a test that repictures the eye cannot leak into
## the arena every other test loads.
func test_each_eye_owns_its_own_material() -> void:
	var other: PanopticonEye = _make_eye()
	add_child(other)
	assert_false(_eye.face_material == other.face_material, "each eye should own its face material")


# --- Where it stands ----------------------------------------------------------

## The eye is on the tower in the arena, on the tower's own axis, centred at the
## guard's eye height, with the guard's spawn inside it -- and it did not disturb
## the marker [MatchController] puts the guard on.
func test_the_eye_stands_on_the_tower_in_the_arena() -> void:
	var arena: Node3D = TestFixtures.make_arena()
	add_child(arena)

	var eye: PanopticonEye = arena.get_node_or_null(^"Tower/Eye") as PanopticonEye
	if not assert_not_null(eye, "the arena's tower should carry an Eye"):
		return
	assert_almost_eq(eye.global_position.x, 0.0, 0.0001, "the eye should be on the arena's axis in X")
	assert_almost_eq(eye.global_position.z, 0.0, 0.0001, "the eye should be on the arena's axis in Z")

	var box: MeshInstance3D = eye.get_node_or_null(^"Box") as MeshInstance3D
	if not assert_not_null(box, "the eye should carry a Box"):
		return
	assert_almost_eq(box.global_position.y, GUARD_EYE_Y, 0.0001,
		"the box should be centred on the guard's own eye height")

	var spawn: Marker3D = arena.get_node_or_null(TestFixtures.TOWER_SPAWN_PATH) as Marker3D
	if not assert_not_null(spawn, "TowerSpawn should still resolve"):
		return
	assert_vec3_almost_eq(spawn.global_position, TOWER_SPAWN_POSITION, 0.0001,
		"the eye must not have moved the guard's spawn")

	var bounds: AABB = _world_bounds_of(box)
	assert_true(bounds.has_point(spawn.global_position + Vector3.UP * 1.65),
		"the guard spawns with their eye inside the box, or the cover is not over them")
