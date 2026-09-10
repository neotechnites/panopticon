extends TestCase

## [PanopticonEye]: the promise that the tower tells the prisoners nothing.
##
## The eye is scenery, so most of what could be tested about it is a screenshot
## and belongs on a person's monitor. What is here instead are the properties
## that make it a [b]one-way[/b] mirror, because those are exactly the ones that
## can be destroyed by a plausible-looking edit and will not raise anything when
## they are:
##
## - a lid nudged off the axis, or a mesh swapped for one with a front, gives
##   the form a side, and a form with a side points somewhere;
## - a material set to transparent, or to front-face culling, lets a prisoner
##   see the guard, or blinds the guard with the inside of their own tower;
## - a collision shape added "so runners cannot clip it" puts the eye on the
##   rifle's hit mask and the guard starts shooting their own tower.
##
## None of those three would fail any other test in this suite, and none of them
## looks wrong in a diff. So they are asserted here. See the class documentation
## of [PanopticonEye] for the design ruling this defends
## ([code]panopticon.open.guard_vision[/code], resolved 2026-09-09).

const EYE_SCENE_PATH: String = "res://scenes/tower/panopticon_eye.tscn"

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


# --- The form cannot point anywhere -------------------------------------------

## The structural half of the no-leak promise.
##
## Every piece of the eye is a [CylinderMesh] -- a solid of revolution about its
## own Y -- sitting on the tower's axis with no rotation. Such a shape is
## identical from every bearing on the ring, so there is no arrangement of it
## that could indicate a direction, whatever a later [method Node._process]
## does. The pupil in particular is a full 360-degree band: it stares at every
## prisoner at once, which is the only way it can stare at each of them without
## telling any of them anything.
func test_the_form_is_a_solid_of_revolution() -> void:
	var surfaces: Array[MeshInstance3D] = _surfaces_of(_eye)
	assert_eq_int(surfaces.size(), 7, "the eye should have its seven authored surfaces")

	for surface: MeshInstance3D in surfaces:
		var cylinder: CylinderMesh = surface.mesh as CylinderMesh
		assert_not_null(cylinder, "%s should be a CylinderMesh, which has no front" % surface.name)

		var offset: Vector3 = surface.position
		assert_almost_eq(offset.x, 0.0, 0.0001, "%s should sit on the tower's axis in X" % surface.name)
		assert_almost_eq(offset.z, 0.0, 0.0001, "%s should sit on the tower's axis in Z" % surface.name)

		var turn: Quaternion = surface.transform.basis.get_rotation_quaternion()
		assert_almost_eq(turn.angle_to(Quaternion.IDENTITY), 0.0, 0.0001,
			"%s should be unrotated -- a rotated piece has a bearing" % surface.name)

		var scaling: Vector3 = surface.transform.basis.get_scale()
		assert_almost_eq(scaling.x, scaling.z, 0.0001,
			"%s should be scaled equally in X and Z, or it is an ellipse with a long side" % surface.name)


## The behavioural half. Nothing in the eye moves, ever -- not the rig, not a
## single surface -- so a prisoner watching it for a whole round sees the same
## silhouette they saw at spawn.
func test_nothing_in_the_eye_ever_moves() -> void:
	var surfaces: Array[MeshInstance3D] = _surfaces_of(_eye)
	var before: Array[Transform3D] = []
	for surface: MeshInstance3D in surfaces:
		before.append(surface.global_transform)
	var rig_before: Transform3D = _eye.global_transform

	await step_seconds(2.0)

	assert_true(_eye.global_transform.is_equal_approx(rig_before), "the eye rig should not have moved")
	for index: int in surfaces.size():
		assert_true(
			surfaces[index].global_transform.is_equal_approx(before[index]),
			"%s should not have moved" % surfaces[index].name,
		)


# --- The mirror is one-way ----------------------------------------------------

## Opaque, and culled the right way round.
##
## Backface culling is what makes this a mirror rather than a wall: from outside
## the shell is solid, and from inside -- where the guard is -- every triangle of
## it faces away and is dropped, so the guard sees the whole ring through their
## own tower. Reverse it and the guard is sealed in a box. Make it transparent
## and the prisoners can see the guard, which is the one thing the tower exists
## to prevent.
func test_the_shell_is_opaque_from_outside_and_absent_from_inside() -> void:
	for surface: MeshInstance3D in _surfaces_of(_eye):
		var material: StandardMaterial3D = surface.get_surface_override_material(0) as StandardMaterial3D
		if not assert_not_null(material, "%s should have a material" % surface.name):
			continue
		assert_eq_int(material.cull_mode, BaseMaterial3D.CULL_BACK,
			"%s must be backface-culled, or the guard sees the inside of the tower" % surface.name)
		assert_eq_int(material.transparency, BaseMaterial3D.TRANSPARENCY_DISABLED,
			"%s must be opaque, or prisoners can see the guard through it" % surface.name)
		assert_almost_eq(material.albedo_color.a, 1.0, 0.0001,
			"%s must be fully opaque, or prisoners can see the guard through it" % surface.name)
		assert_false(material.no_depth_test,
			"%s must depth-test, or it draws over the ring" % surface.name)


## No surface of the eye is ever between the guard and the ring.
##
## Backface culling already hides the shell from inside, but that is only true
## while the guard is inside. This is the geometry that keeps them there and
## keeps the interior clear: over every height a guard can reach, the only part
## of the eye that exists is at least as far from the axis as the edge of the
## platform they are standing on. So they cannot walk out of the shell, and
## nothing in it can appear in front of their face.
func test_the_guard_volume_is_clear_of_the_eye() -> void:
	var rig_scale: float = _eye.scale.x
	assert_almost_eq(rig_scale, _eye.scale.y, 0.0001, "the rig should be scaled uniformly")

	var reaching: PackedStringArray = PackedStringArray()
	for surface: MeshInstance3D in _surfaces_of(_eye):
		var cylinder: CylinderMesh = surface.mesh as CylinderMesh
		if cylinder == null:
			continue
		var half: float = 0.5 * cylinder.height * rig_scale
		var centre: float = surface.position.y * rig_scale
		var low: float = maxf(centre - half, 0.0)
		var high: float = minf(centre + half, GUARD_REACH_Y)
		if low > high:
			continue  # Entirely above or below anywhere a guard can be.
		reaching.append(surface.name)

		# The radius is linear in height, so the narrowest point of the overlap
		# is at one of its two ends.
		var narrowest: float = minf(
			_radius_at(cylinder, centre - half, centre + half, low) * rig_scale,
			_radius_at(cylinder, centre - half, centre + half, high) * rig_scale,
		)
		assert_ge(narrowest, PLATFORM_RADIUS,
			"%s reaches into the guard's volume at r=%.2f, inside the platform edge" % [surface.name, narrowest])

	# The socket is a wall the guard stands inside; everything else -- the lids,
	# the iris, the pupil, the crown -- must be over their head entirely, so that
	# the seal does not depend on culling alone.
	assert_eq_string(", ".join(reaching), "Socket",
		"only the socket wall should reach the height a guard can stand at")


func _radius_at(cylinder: CylinderMesh, bottom_y: float, top_y: float, y: float) -> float:
	var span: float = top_y - bottom_y
	if is_zero_approx(span):
		return maxf(cylinder.bottom_radius, cylinder.top_radius)
	return lerpf(cylinder.bottom_radius, cylinder.top_radius, clampf((y - bottom_y) / span, 0.0, 1.0))


# --- Scenery, not a mechanic --------------------------------------------------

## The eye has no gameplay and must not acquire any by accident.
##
## A collision shape is the way it would happen: the rifle raycasts against the
## world, so the moment the tower has a body the guard's own shots stop at their
## own wall. There is no reason for the eye to be solid -- the platform's edge
## already contains the guard -- so there is nothing here that could be hit,
## lit, aimed or looked through.
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

## What the resource says is what the tower is, and it lands on the material the
## mesh actually draws with.
##
## The second half of that matters more than it looks. The materials are
## local-to-scene, so each instance gets duplicates; if the duplication ever
## stopped remapping the exports on the rig, every value below would still be
## written, to an object nothing renders, and the eye would quietly go back to
## its authored colours with the profile appearing to work.
func test_the_profile_reaches_the_rendered_material() -> void:
	var profile: EyeProfile = EyeProfile.new()
	profile.iris_color = Color(0.9, 0.2, 0.1)
	profile.iris_metallic = 0.25
	profile.iris_roughness = 0.75
	profile.shell_color = Color(0.4, 0.5, 0.6)
	profile.pupil_color = Color(0.7, 0.7, 0.7)

	var eye: PanopticonEye = _make_eye()
	eye.profile = profile
	add_child(eye)

	var iris: MeshInstance3D = eye.get_node("IrisLower") as MeshInstance3D
	assert_same(iris.get_surface_override_material(0), eye.iris_material,
		"the rendered iris material should be the one the script writes to")

	var material: StandardMaterial3D = iris.get_surface_override_material(0) as StandardMaterial3D
	assert_true(material.albedo_color.is_equal_approx(profile.iris_color), "iris colour should come from the profile")
	assert_almost_eq(material.metallic, profile.iris_metallic, 0.0001, "iris mirror strength should come from the profile")
	assert_almost_eq(material.roughness, profile.iris_roughness, 0.0001, "iris polish should come from the profile")

	var shell: StandardMaterial3D = (eye.get_node("Socket") as MeshInstance3D).get_surface_override_material(0) as StandardMaterial3D
	assert_true(shell.albedo_color.is_equal_approx(profile.shell_color), "shell colour should come from the profile")

	var pupil: StandardMaterial3D = (eye.get_node("Pupil") as MeshInstance3D).get_surface_override_material(0) as StandardMaterial3D
	assert_true(pupil.albedo_color.is_equal_approx(profile.pupil_color), "pupil colour should come from the profile")


## Two eyes in one world do not share a material, so tuning one cannot reach the
## other -- and, in this suite, a test that recolours the eye cannot leak into
## the arena every other test loads.
func test_each_eye_owns_its_own_materials() -> void:
	var other: PanopticonEye = _make_eye()
	add_child(other)
	assert_false(_eye.iris_material == other.iris_material, "each eye should own its iris material")
	assert_false(_eye.shell_material == other.shell_material, "each eye should own its shell material")


## The pulse breathes on the wall clock and on nothing else, and it stops dead
## when either knob is zero.
##
## This is the only moving part of the eye, and the reason it is allowed to move
## is that it is ignorant: [method PanopticonEye.glow_energy_at] takes a number
## of seconds and nothing else, so there is no value anybody could hand it that
## would make it say something about the guard.
##
## The breath is asserted through that function rather than by awaiting frames.
## It runs on the render clock, the runner compresses the physics clock, and how
## many render frames land inside a simulated second is a fact about the host
## machine -- an earlier version of this test asserted the phase after
## [method TestCase.step_seconds] and failed on a busy laptop.
func test_the_pulse_knows_nothing_and_can_be_switched_off() -> void:
	var still: EyeProfile = EyeProfile.new()
	still.pulse_depth = 0.0
	var frozen: PanopticonEye = _make_eye()
	frozen.profile = still
	add_child(frozen)

	assert_false(frozen.is_processing(), "an eye with no breath should not process at all")
	assert_almost_eq(frozen.iris_material.emission_energy_multiplier, still.iris_glow_energy, 0.0001,
		"a still eye should sit at the glow its profile asks for")

	var breathing: EyeProfile = EyeProfile.new()
	breathing.pulse_hz = 1.0
	breathing.pulse_depth = 0.5
	var alive: PanopticonEye = _make_eye()
	alive.profile = breathing
	add_child(alive)

	var crest: float = breathing.iris_glow_energy
	var trough: float = crest * (1.0 - breathing.pulse_depth)

	assert_true(alive.is_processing(), "a breathing eye should process")
	assert_almost_eq(alive.iris_material.emission_energy_multiplier, crest, 0.0001,
		"the first frame drawn should match what _ready set up, with no pop")
	assert_almost_eq(alive.glow_energy_at(0.0), crest, 0.0001, "the breath should start at its crest")
	assert_almost_eq(alive.glow_energy_at(0.5), trough, 0.0001, "half a one-hertz breath should be the trough")
	assert_almost_eq(alive.glow_energy_at(1.0), crest, 0.0001, "a whole breath should return to the crest")
	assert_almost_eq(alive.glow_energy_at(0.25), 0.5 * (crest + trough), 0.0001,
		"a quarter breath should be halfway down")

	# The eye never brightens past what the profile asked for, at any moment of
	# the breath. Emission that overshot would read as a flare, and a flare is
	# the exact shape of a tell.
	for step: int in 40:
		var energy: float = alive.glow_energy_at(0.025 * float(step))
		assert_between(energy, trough - 0.0001, crest + 0.0001,
			"the glow should stay between the trough and the crest")


# --- Where it stands ----------------------------------------------------------

## The eye is on the tower in the arena, on the tower's own axis, and it did not
## disturb the spawn marker [MatchController] puts the guard on.
func test_the_eye_stands_on_the_tower_in_the_arena() -> void:
	var arena: Node3D = TestFixtures.make_arena()
	add_child(arena)

	var eye: PanopticonEye = arena.get_node_or_null(^"Tower/Eye") as PanopticonEye
	if not assert_not_null(eye, "the arena's tower should carry an Eye"):
		return
	assert_almost_eq(eye.global_position.x, 0.0, 0.0001, "the eye should be on the arena's axis in X")
	assert_almost_eq(eye.global_position.z, 0.0, 0.0001, "the eye should be on the arena's axis in Z")

	var spawn: Marker3D = arena.get_node_or_null(TestFixtures.TOWER_SPAWN_PATH) as Marker3D
	if not assert_not_null(spawn, "TowerSpawn should still resolve"):
		return
	assert_vec3_almost_eq(spawn.global_position, TOWER_SPAWN_POSITION, 0.0001,
		"the eye must not have moved the guard's spawn")
	assert_lt(Vector2(spawn.global_position.x, spawn.global_position.z).length(), PLATFORM_RADIUS,
		"the guard should spawn inside the shell")
