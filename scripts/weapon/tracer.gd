class_name Tracer
extends MeshInstance3D

## The visible line a shot leaves behind, from muzzle to impact.
##
## [b]This is a mechanic.[/b] PANOPTICON's tower is a sniper with one bullet at
## a time; without a tracer, shooting would be free information -- the tower
## would learn a runner's position and give up nothing. The tracer is the price:
## it hangs in the air for [member WeaponProfile.tracer_lifetime] seconds along
## the exact line the shot took, so anyone who sees it can back-project it to
## roughly where the tower was standing and what it was looking at. Every shot
## is therefore a broadcast, and the decision to fire is a decision to be
## located. Tune the lifetime and you tune how expensive shooting is.
##
## [b]Why geometry and not a line[/b]
##
## The obvious implementation is an [ImmediateMesh] with
## [constant Mesh.PRIMITIVE_LINES], and it is wrong here. The project renders
## with GL Compatibility, where hardware line width is effectively pinned to one
## pixel on every desktop GL driver: the tracer would be a hairline at three
## metres and a hairline at three hundred, so distance would carry no weight and
## [member WeaponProfile.tracer_width] would do nothing.
##
## So the tracer is built as real geometry with real thickness. Rather than
## billboard a single quad towards the camera -- which needs the camera, needs
## updating every frame, and degenerates when you look straight down the barrel
## -- it is two quads crossed at right angles along the shot axis, an X in
## cross-section. From any viewing angle at least one of the two quads is close
## to face-on, so the tracer presents a consistent width from everywhere, is
## built once, and never needs to know where a camera is. That last property is
## what lets a headless bot match spawn tracers without a viewport.
##
## The node is [member Node3D.top_level], so it is pinned to world space at the
## moment of the shot and does not ride along with the shooter's camera as it
## keeps turning. A tracer that followed the muzzle would betray nothing, which
## would defeat the entire purpose above.

## Seconds since the shot. Drives the fade.
var _age: float = 0.0

var _lifetime: float = 0.0
var _fade_exponent: float = 1.0
var _color: Color = Color.WHITE
var _material: StandardMaterial3D = null


## Create a tracer along [param from] -> [param to] in world space, parent it to
## [param parent] and hand it back.
##
## The tracer owns its own lifetime and frees itself; callers are not expected
## to keep the reference, and [Rifle] deliberately does not.
static func spawn(parent: Node, from: Vector3, to: Vector3, profile: WeaponProfile) -> Tracer:
	var tracer: Tracer = Tracer.new()
	tracer.configure(from, to, profile)
	parent.add_child(tracer)
	return tracer


## Build the geometry and the material. Called by [method spawn] before the node
## enters the tree, so the first rendered frame already shows the full-brightness
## tracer rather than an untextured white one.
func configure(from: Vector3, to: Vector3, profile: WeaponProfile) -> void:
	_lifetime = profile.tracer_lifetime
	_fade_exponent = profile.tracer_fade_exponent
	_color = profile.tracer_color

	# top_level before the transform: the tracer is a world-space fact about
	# where a shot went, not a child of whatever was holding the rifle.
	top_level = true
	cast_shadow = SHADOW_CASTING_SETTING_OFF
	global_transform = Transform3D(Basis.IDENTITY, from)

	mesh = _build_ribbon(to - from, profile.tracer_width)
	_material = _build_material()
	material_override = _material
	_apply_fade()


func _process(delta: float) -> void:
	_age += delta
	if _lifetime <= 0.0 or _age >= _lifetime:
		queue_free()
		return
	_apply_fade()


## Two quads crossed along [param axis], expressed in the tracer's local space
## with the muzzle at the origin. Four triangles, twelve vertices, no indices --
## at the volumes a single-shot weapon produces this is far cheaper than the
## bookkeeping needed to share them.
func _build_ribbon(axis: Vector3, width: float) -> ImmediateMesh:
	var mesh_out: ImmediateMesh = ImmediateMesh.new()
	var length: float = axis.length()
	if length <= 0.0:
		return mesh_out

	var forward: Vector3 = axis / length
	# Any vector not parallel to the shot will do as a seed for the cross
	# section; UP fails only when firing exactly vertically, hence the fallback.
	var seed_up: Vector3 = Vector3.UP if absf(forward.dot(Vector3.UP)) < 0.99 else Vector3.RIGHT
	var side: Vector3 = forward.cross(seed_up).normalized()
	var other: Vector3 = forward.cross(side).normalized()

	var half: float = width * 0.5
	mesh_out.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	_add_quad(mesh_out, axis, side * half)
	_add_quad(mesh_out, axis, other * half)
	mesh_out.surface_end()
	return mesh_out


## One quad spanning the shot, [param half_width] to either side of the axis.
## Winding is not maintained because the material disables culling -- a tracer
## must look identical from both sides or the X cross-section would show gaps.
func _add_quad(mesh_out: ImmediateMesh, axis: Vector3, half_width: Vector3) -> void:
	var near_a: Vector3 = -half_width
	var near_b: Vector3 = half_width
	var far_a: Vector3 = axis - half_width
	var far_b: Vector3 = axis + half_width
	mesh_out.surface_add_vertex(near_a)
	mesh_out.surface_add_vertex(near_b)
	mesh_out.surface_add_vertex(far_b)
	mesh_out.surface_add_vertex(near_a)
	mesh_out.surface_add_vertex(far_b)
	mesh_out.surface_add_vertex(far_a)


## Unshaded, additive, unculled, depth-write off.
##
## Unshaded because a tracer is a light source, not a lit surface, and a lit one
## would go black in the ring's shadowed cover. Additive so it reads as hot
## against both the pale deck and the dark tower. Depth-write off so overlapping
## tracers and the fading tail do not punch holes in one another. All four are
## supported by the GL Compatibility renderer, which is the constraint that
## rules out most of the fancier options.
func _build_material() -> StandardMaterial3D:
	var material: StandardMaterial3D = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.no_depth_test = false
	material.disable_receive_shadows = true
	material.albedo_color = _color
	return material


func _apply_fade() -> void:
	if _material == null:
		return
	var remaining: float = 1.0 if _lifetime <= 0.0 else clampf(1.0 - _age / _lifetime, 0.0, 1.0)
	var faded: Color = _color
	faded.a = _color.a * pow(remaining, _fade_exponent)
	_material.albedo_color = faded


## Current alpha, 1.0 at the shot and 0.0 when spent. Exposed so a headless
## check can assert the fade actually runs without needing a viewport to look at.
func get_fade() -> float:
	if _lifetime <= 0.0:
		return 0.0
	return clampf(1.0 - _age / _lifetime, 0.0, 1.0)
