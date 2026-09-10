extends TestCase

## [PanopticonEye]: the promise that the eye tells the prisoners nothing.
##
## The eye is scenery -- since 2026-09-10 it is one box, 8 m on a side, with a
## picture of an eye on every face, the tower and then the red ball that stood
## here having both been removed as art nobody asked for. Most of what could be
## tested about it is a screenshot and belongs on a person's monitor. What is
## here instead are the properties that make it a [b]one-way[/b] eye, because
## those are exactly the ones that can be destroyed by a plausible-looking edit
## and will not raise anything when they are:
##
## - the old eye was a solid of revolution, so it could not have a front. A box
##   can. Every one of its sides must therefore carry the same picture the same
##   way up, from one material and one texture, or the box acquires a bearing;
## - a mesh nudged off the axis, rotated, or made oblong gives it a bearing too;
## - a line of code that reads the camera, the rifle, the seat or the match hands
##   the prisoners the one thing the game is built on withholding;
## - a material set to transparent, front-face-culled, or shaded, lets a prisoner
##   see into the eye or lets the sun tell one of its sides from another;
## - a collision shape added "so runners cannot clip it" puts the eye on the
##   rifle's hit mask and the guard starts shooting their own tower;
## - anything that reaches down into the volume the guard moves through puts a
##   surface between them and the ring.
##
## None of those would fail any other test in this suite, and none of them looks
## wrong in a diff. So they are asserted here. See the class documentation of
## [PanopticonEye] for the design ruling this defends
## ([code]panopticon.open.guard_vision[/code], resolved 2026-09-09).

const EYE_SCENE_PATH: String = "res://scenes/tower/panopticon_eye.tscn"

## The two files that make up the eye. Both are read as text below, because the
## promise that the eye knows nothing about the guard is a fact about the source
## rather than about any value it happens to hold at runtime.
const EYE_SOURCE_PATHS: Array[String] = [
	"res://scripts/tower/panopticon_eye.gd",
	"res://scripts/tower/eye_profile.gd",
]

## Radius of Tower/Platform in [code]scenes/ring/test_ring.tscn[/code], and so
## the furthest from the axis a guard can stand before they fall off it.
const PLATFORM_RADIUS: float = 8.0

## Highest a guard's camera can reach above the platform: they spawn at y=0.25,
## their head sits 1.65 m above their feet, and the tuned jump apex is 1.11 m.
## Rounded up, generously.
const GUARD_REACH_Y: float = 3.0

## Where [code]scenes/ring/test_ring.tscn[/code] puts the guard, and what this
## file checks the eye did not move.
const TOWER_SPAWN_POSITION: Vector3 = Vector3(0.0, 0.25, 0.0)

## Height of the middle of the box above the deck.
##
## This number is load-bearing in a place that has nothing to do with the eye:
## the Cover and InnerKerb heights in [code]scenes/ring/test_ring.tscn[/code] are
## both derived, in their own editor_descriptions, from "the tower eye at
## y=16.7". The guard's actual camera is at y=1.9, which does not agree with it,
## and that disagreement is unresolved and Ryan's to settle. It is pinned here so
## that nothing drifts silently while it is open.
const APERTURE_Y: float = 16.7

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


# --- The form cannot point anywhere -------------------------------------------

## The structural half of the no-leak promise, part one: the box has no long
## side, no tilt and no offset.
##
## The eye used to be a sphere and a cylinder -- solids of revolution, identical
## from every bearing, incapable of indicating a direction whatever a later
## [method Node._process] did to them. Ryan asked for a box instead, so that
## particular argument is gone and the geometry has to earn the same result a
## different way: one closed box, square in plan, sitting on the tower's own axis
## with no rotation on it. Square in plan matters as much as unrotated does -- an
## oblong has a broad side and a narrow side, and a prisoner who can tell which
## one they are standing in front of knows something about the tower's layout.
func test_the_form_is_a_box_with_no_readable_side() -> void:
	var surfaces: Array[MeshInstance3D] = _surfaces_of(_eye)
	assert_eq_int(surfaces.size(), 1, "the eye should be one box, and nothing else")
	if surfaces.is_empty():
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


## The structural half, part two: every side is the same picture, the same way
## up.
##
## This is the assertion that replaces "it is a solid of revolution", and it is
## the load-bearing one. [BoxMesh] lays its six faces out as a three-by-two UV
## atlas, so a texture applied naively puts a [i]different sixth of the image[/i]
## on each face -- six sides that are all different, which is the exact opposite
## of what is wanted and looks perfectly reasonable in the inspector.
## [constant PanopticonEye.UV_TILING] scales UV1 by that atlas shape so each cell
## maps back onto the whole texture and every face draws a full upright copy.
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
			var material: Material = surface.get_surface_override_material(index)
			if not materials.has(material):
				materials.append(material)

	assert_eq_int(materials.size(), 1,
		"the whole eye should draw with exactly one material, or its sides can drift apart")
	if materials.is_empty():
		return

	var material: StandardMaterial3D = materials[0] as StandardMaterial3D
	if not assert_not_null(material, "the box should have a StandardMaterial3D"):
		return

	assert_not_null(material.albedo_texture, "the box should carry the eye picture on it")
	assert_vec3_almost_eq(material.uv1_scale, PanopticonEye.UV_TILING, 0.0001,
		"UV1 must be scaled by the box atlas, or each face shows a different sixth of the picture")
	assert_vec3_almost_eq(material.uv1_offset, Vector3.ZERO, 0.0001,
		"a UV offset would slide the picture off centre by a different amount on each face")
	assert_true(material.texture_repeat,
		"the tiled UVs need repeat, or five of the six faces clamp to a smear of one edge")


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


## The behavioural half. Nothing in the eye moves, ever -- not the rig, not the
## box -- so a prisoner watching it for a whole round sees the same silhouette
## they saw at spawn.
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


# --- The eye is one-way -------------------------------------------------------

## Opaque, unshaded, and culled the right way round.
##
## Transparency would let a prisoner see into the eye. Reversed or disabled
## culling draws the inside of the box as well as the outside, and no depth test
## draws it over the whole ring from anywhere on the map. Shading is the one that
## is specific to a box: the arena's sun would put a highlight on whichever face
## it favours and leave the opposite one dim, so the four sides would stop
## matching -- a tell arrived at by lighting rather than by anybody meaning it,
## and one that changes through the day.
func test_the_eye_is_opaque_unshaded_and_culled_the_right_way_round() -> void:
	for surface: MeshInstance3D in _surfaces_of(_eye):
		var material: StandardMaterial3D = surface.get_surface_override_material(0) as StandardMaterial3D
		if not assert_not_null(material, "%s should have a material" % surface.name):
			continue
		assert_eq_int(material.shading_mode, BaseMaterial3D.SHADING_MODE_UNSHADED,
			"%s must be unshaded, or the sun tells one side of the box from another" % surface.name)
		assert_eq_int(material.cull_mode, BaseMaterial3D.CULL_BACK,
			"%s must be backface-culled, or the eye draws its own inside" % surface.name)
		assert_eq_int(material.transparency, BaseMaterial3D.TRANSPARENCY_DISABLED,
			"%s must be opaque, or prisoners can see into the eye" % surface.name)
		assert_almost_eq(material.albedo_color.a, 1.0, 0.0001,
			"%s must be fully opaque, or prisoners can see into the eye" % surface.name)
		assert_false(material.no_depth_test,
			"%s must depth-test, or it draws over the ring" % surface.name)


## No surface of the eye is ever between the guard and the ring.
##
## The old tower proved this with a seal -- a shell the guard stood inside, kept
## invisible to them by backface culling. There is no shell any more, so the
## property is proved the blunt way instead: the whole box is above everywhere
## the guard's camera can get, by metres, at every size the profile allows. There
## is nothing to cull, because there is nothing there.
func test_the_eye_is_entirely_above_the_guard() -> void:
	var bounds: Vector2 = _size_scale_range()
	assert_gt(bounds.x, 0.0, "size_scale should expose a range")

	for size_scale: float in [bounds.x, 1.0, bounds.y]:
		var profile: EyeProfile = EyeProfile.new()
		profile.size_scale = size_scale
		# The picture is irrelevant to clearance, but a blank one warns, and a
		# suite that prints warnings it means to print teaches people to skim.
		profile.eye_texture = _eye.profile.eye_texture
		var eye: PanopticonEye = _make_eye()
		eye.profile = profile
		add_child(eye)

		assert_almost_eq(eye.scale.x, size_scale, 0.0001, "the rig should take the profile's size")

		for surface: MeshInstance3D in _surfaces_of(eye):
			var lowest: float = _world_bounds_of(surface).position.y
			assert_gt(lowest, GUARD_REACH_Y,
				"at size_scale %.2f, %s reaches down to y=%.2f, into the guard's volume" % [
					size_scale, surface.name, lowest,
				])


## What the eye sits over, it does not sit on: it is clear of the platform's
## whole footprint in height, so a guard walking to the rail cannot touch it and
## a guard looking outward cannot have it in frame.
func test_the_eye_clears_the_platform_it_floats_over() -> void:
	for surface: MeshInstance3D in _surfaces_of(_eye):
		var bounds: AABB = _world_bounds_of(surface)
		assert_gt(bounds.position.y, GUARD_REACH_Y,
			"%s should be above the guard entirely" % surface.name)
		assert_le(0.5 * bounds.size.x, PLATFORM_RADIUS,
			"%s should not overhang the platform it floats over" % surface.name)


func _size_scale_range() -> Vector2:
	for property: Dictionary in EyeProfile.new().get_property_list():
		if String(property["name"]) == "size_scale":
			var bounds: PackedStringArray = String(property["hint_string"]).split(",")
			if bounds.size() >= 2:
				return Vector2(bounds[0].to_float(), bounds[1].to_float())
	return Vector2.ZERO


# --- Scenery, not a mechanic --------------------------------------------------

## The eye has no gameplay and must not acquire any by accident.
##
## A collision shape is the way it would happen: the rifle raycasts against the
## world, so the moment the eye has a body the guard's own shots stop at it.
## There is no reason for it to be solid -- it floats twelve metres over
## everybody's head -- so there is nothing here that could be hit, lit, aimed or
## looked through.
func test_the_eye_is_inert() -> void:
	for node: Node in _descendants_of(_eye):
		assert_null(node as CollisionObject3D,
			"%s: the eye must have no physics body, or the guard shoots their own tower" % node.name)
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
	assert_vec3_almost_eq(material.uv1_scale, PanopticonEye.UV_TILING, 0.0001,
		"the script should lay the picture over every face, whatever the scene was saved with")


## Two eyes in one world do not share a material, so tuning one cannot reach the
## other -- and, in this suite, a test that repictures the eye cannot leak into
## the arena every other test loads.
func test_each_eye_owns_its_own_material() -> void:
	var other: PanopticonEye = _make_eye()
	add_child(other)
	assert_false(_eye.face_material == other.face_material, "each eye should own its face material")


# --- Where it stands ----------------------------------------------------------

## The eye is over the tower in the arena, on the tower's own axis, with its
## middle at the height the rest of the ring was cut against -- and it did not
## disturb the spawn marker [MatchController] puts the guard on.
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
	assert_almost_eq(box.global_position.y, APERTURE_Y, 0.0001,
		"the box should stay at the eye height Cover and InnerKerb were derived from")

	var spawn: Marker3D = arena.get_node_or_null(TestFixtures.TOWER_SPAWN_PATH) as Marker3D
	if not assert_not_null(spawn, "TowerSpawn should still resolve"):
		return
	assert_vec3_almost_eq(spawn.global_position, TOWER_SPAWN_POSITION, 0.0001,
		"the eye must not have moved the guard's spawn")
	assert_lt(Vector2(spawn.global_position.x, spawn.global_position.z).length(), PLATFORM_RADIUS,
		"the guard should spawn on the platform")
