class_name PanopticonEye
extends Node3D

## The tower, seen from the ring: a thirty-metre eye that no prisoner can see
## into.
##
## [b]The one thing this class must never do[/b]
##
## Ryan settled guard vision on 2026-09-09 (pod fact
## [code]panopticon.open.guard_vision[/code]): the guard can see the whole ring
## at once -- no part of the course is hidden from the tower by geometry -- but
## the guard's point of view is NOT 360 degrees. They see what they are looking
## at, with an ordinary field of view. Attention is therefore a real, scarce
## resource the guard spends, and the entire tension of the game is that the
## prisoners cannot tell where it is being spent.
##
## So the eye [b]must not carry a single bit of information about the guard[/b].
## It does not turn towards them, brighten towards them, track them, or change
## when they aim, fire, reload, zoom, or leave the tower entirely. There is no
## reference in this file to a camera, to [MatchController], to the rifle or to
## the seat, and adding one would not be a feature -- it would delete the
## mechanic the game is named after.
##
## That is a promise, so it is kept structurally rather than by discipline:
##
## 1. [b]The form is a solid of revolution.[/b] Every piece of the eye is a
##    cylinder, cone or sphere centred on the tower's own vertical axis, with no
##    rotation of its own. A shape with no distinguishable side cannot point at
##    anything, whatever anybody later writes in [method _process]. The pupil is
##    a full 360-degree band, so every prisoner on the ring sees the eye looking
##    dead at them, all the time, from every position -- which is the panopticon
##    exactly.
## 2. [b]The only animation is the wall clock.[/b] [member EyeProfile.pulse_hz]
##    breathes the glow on a timer that knows nothing. Nothing else moves.
## 3. [code]tests/test_tower.gd[/code] asserts both of the above, so a later
##    change that breaks them fails the suite rather than shipping.
##
## [b]How the one-way mirror actually works[/b]
##
## It is not a shader, and it is not a trick: it is what a one-way mirror is.
## The shell is a closed surface of outward-facing geometry that completely
## encloses the guard, and every material on it is backface-culled -- which is
## the engine default and is asserted in [method _ready] because it is
## load-bearing. From outside, the prisoner sees a solid, mirrored wall and
## cannot see the guard's body, let alone their aim. From inside, every triangle
## of that same wall is facing away from the guard and is culled, so the guard
## sees the entire ring with nothing in front of them: no tint, no frame, no
## blind spot, no render cost.
##
## The enclosure is geometric, not a rule. The socket wall is r=8.5 m and the
## platform the guard stands on is r=8.0 m, so a guard who walks to the edge is
## still inside the shell and a guard who walks past the edge has fallen into
## the courtyard. Nothing here has collision and nothing here is on the rifle's
## hit mask, so the guard shoots straight through their own tower and the eye
## costs the physics server nothing.
##
## This was checked on a screen, not assumed. Rendered under GL Compatibility
## from the guard's spawn, from the very edge of their platform and looking
## straight up inside the shell, the frame is pixel-for-pixel identical to the
## same frame with the eye deleted: the tower's own geometry costs the guard not
## one pixel of the ring.
##
## [b]Scenery, not a mechanic[/b]
##
## As of today the eye does nothing at all. It has no state, no signals and no
## gameplay. It is presence. Ideas for what it might do belong in the pod as
## open questions for Ryan, not in this file.
##
## [b]Renderer[/b]
##
## GL Compatibility, which is pinned for this project. Nothing here uses a
## feature that renderer lacks: albedo, metallic, roughness, emission and
## backface culling are the whole surface model, and the form is primitive
## meshes. There is no custom shader to fail to compile.

## Materials the profile is written onto. They are exported rather than found by
## walking the mesh children so that this script never has to guess which
## surface is which: the scene says it, once, in one place.
##
## They are [member Resource.resource_local_to_scene], so each eye owns the
## materials it draws with and writing a profile onto one tower cannot reach
## another -- or, more to the point, cannot leak out of a test and into the rest
## of the suite. [code]tests/test_tower.gd[/code] asserts that the material this
## script writes to is the same object the mesh renders with, because a
## mis-remapped local resource fails silently: the profile is applied perfectly,
## to a copy nothing draws.
@export var shell_material: StandardMaterial3D
@export var iris_material: StandardMaterial3D
@export var pupil_material: StandardMaterial3D

## Look and size. Falls back to a default-constructed [EyeProfile] with a
## warning rather than to nothing, because an eye that silently failed to appear
## is a bug that reads as "the tower is just a platform again".
@export var profile: EyeProfile

## Emission energy the pulse swings around, taken from the profile at ready so
## that [method _process] never touches the resource.
var _glow_energy: float = 0.0

## Seconds since this node entered the tree. Its own clock rather than
## [method Time.get_ticks_msec] so that the pulse is unaffected by how long the
## menu was open, and so a headless run with no display never accumulates one.
var _pulse_time: float = 0.0


func _ready() -> void:
	if profile == null:
		push_warning("PanopticonEye has no EyeProfile; falling back to defaults.")
		profile = EyeProfile.new()

	scale = Vector3.ONE * profile.size_scale

	_apply_shell()
	_apply_iris()
	_apply_pupil()

	_glow_energy = profile.iris_glow_energy
	set_process(_pulses())


func _process(delta: float) -> void:
	_pulse_time += delta
	iris_material.emission_energy_multiplier = glow_energy_at(_pulse_time)


## The iris glow [param seconds] into the breath.
##
## A pure function of the clock and the profile, which is the whole argument for
## letting the eye move at all: it takes no guard, no camera and no match state,
## so there is no value anybody could pass it that would make it say something.
## It is public so the suite can assert the shape of the breath without racing
## the render clock -- see [code]tests/test_tower.gd[/code].
##
## The breath dips rather than swings, so that
## [member EyeProfile.iris_glow_energy] is the brightest the eye ever gets and
## the value in the inspector is the value on the screen. It also means the
## first frame drawn matches the frame [method _ready] set up, with no pop.
func glow_energy_at(seconds: float) -> float:
	var dip: float = 0.5 - 0.5 * cos(TAU * profile.pulse_hz * seconds)
	return _glow_energy * (1.0 - profile.pulse_depth * dip)


## Whether the glow moves at all. Both knobs have to be non-zero, so either one
## alone is enough to nail the eye perfectly still.
func _pulses() -> bool:
	return iris_material != null and profile.pulse_hz > 0.0 and profile.pulse_depth > 0.0


func _apply_shell() -> void:
	if not _usable(shell_material, "shell_material"):
		return
	shell_material.albedo_color = profile.shell_color
	shell_material.roughness = profile.shell_roughness


func _apply_iris() -> void:
	if not _usable(iris_material, "iris_material"):
		return
	iris_material.albedo_color = profile.iris_color
	iris_material.metallic = profile.iris_metallic
	iris_material.roughness = profile.iris_roughness
	iris_material.emission_enabled = profile.iris_glow_energy > 0.0
	iris_material.emission = profile.iris_glow
	iris_material.emission_energy_multiplier = profile.iris_glow_energy


func _apply_pupil() -> void:
	if not _usable(pupil_material, "pupil_material"):
		return
	pupil_material.albedo_color = profile.pupil_color
	pupil_material.metallic = profile.pupil_metallic
	pupil_material.roughness = profile.pupil_roughness


## Reports a missing material, and refuses to let a front-face-culled or
## depth-testless one through quietly.
##
## Both of those settings would turn the shell inside out for the guard: with
## culling off or reversed, the far wall of the tower draws in front of the
## guard's face and they lose the ring they are supposed to be able to see all
## of. It is one line to get wrong in the inspector and it cannot be seen in a
## headless run, so it is checked here as well as in the suite.
func _usable(material: StandardMaterial3D, field: String) -> bool:
	if material == null:
		push_error("PanopticonEye.%s is unset; the eye will render untextured." % field)
		return false
	if material.cull_mode != BaseMaterial3D.CULL_BACK:
		push_error("PanopticonEye.%s must be backface-culled, or the guard sees the inside of the tower." % field)
	if material.no_depth_test:
		push_error("PanopticonEye.%s has depth testing off; it would draw over the whole ring." % field)
	return true
