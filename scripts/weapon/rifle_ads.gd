class_name RifleAds
extends Node

## Blends [code]Rifle/ViewModel[/code] between its authored hip pose and an
## aimed pose, so a zoom raises the rifle to the eye instead of leaving it at
## the hip while only the field of view narrows.
##
## [b]Why there is no clock in this file[/b]
##
## Ryan asked for the raise to take the same half second as the zoom, and for
## the two to arrive together. The only way that is GUARANTEED rather than
## merely tuned to match is a single clock driving both, so this node keeps
## none of its own: [method WeaponOptic.get_shaped_progress] already is exactly
## that value -- 0 at hipfire, 1 at full zoom, eased by
## [member ZoomProfile.transition_smoothing], reaching 1.0 in precisely
## [member ZoomProfile.zoom_in_seconds] and 0.0 in precisely
## [member ZoomProfile.zoom_out_seconds] at any framerate, and already
## continuous across a feathered zoom button (see [method WeaponOptic._shape]).
## Reading it here rather than re-deriving a second progress value is what makes
## the pose and the FOV arrive on the same tick instead of merely close to it.
##
## [b]This node does not write [member view_model]'s transform.[/b]
## [RifleRecoil] is the sole writer of that node -- see its own
## [member RifleRecoil.pose_source] -- specifically so a shot fired while aimed
## kicks from the AIMED pose and the two systems never both write the same
## node on the same frame. This node only answers
## [method get_current_base_pose]: the hip transform and the aimed transform,
## blended by the optic's shaped progress.
## [method Transform3D.interpolate_with] does the blend, which slerps the
## rotation rather than lerping the basis columns -- a naive lerp would shrink
## the model mid-transition on any pose that both rotates and keeps scale.
##
## [b]The aimed pose[/b] is authored as position, rotation and scale below,
## exactly like the hip pose is authored on ViewModel's own transform in
## [code]scenes/weapon/rifle.tscn[/code], so it can be nudged in the inspector
## without touching code. The rotation is zero: the hip pose is deliberately
## tilted off-axis so the barrel does not sit on the crosshair (see ViewModel's
## own [code]editor_description[/code]), and aiming is exactly the act of
## undoing that -- lining the rifle up with the point of aim. Zero rotation is
## not laziness here, it is the whole trick: with the model's own -Z parallel
## to the camera's, the rifle is a straight line running away from the eye that
## CONVERGES ON THE CROSSHAIR at infinity, which is what makes it read as
## pointed at what the shot will hit. Any tilt breaks that convergence and the
## rifle immediately reads as aimed somewhere else.
##
## [b]Where the numbers came from[/b] -- they were rendered and looked at, from
## the guard's own eye, at the shipped 100 degree display FOV and the zoomed 40
## it becomes, against man-sized targets at 20, 35 and 60 m. The first version
## of this file was tuned blind and put the receiver across the whole screen;
## see [code]tools/_scratch/ads_view.gd[/code], which is the harness that
## produced the pictures, and docs/MODELLING.md for how it is run on the PC.
##
## [b]Why the scope is not centred on the eye[/b]
##
## Because it cannot be. The scope
## ([code]tools/modelling/rifle_build.py[/code], the SCOPE_ block) is a solid
## brick 0.12 m wide and 0.078 m deep whose rear cup now runs 58 mm further
## back than it used to; it has no bore through it and no glass in it, and
## putting its optical axis on the view axis therefore puts an opaque slab
## across the middle of the screen -- which is exactly what the previous
## numbers did. Ryan settled the question directly: "the scope doesnt actually
## need to be see through". So the rifle comes up UNDER the sight line: the
## whole model sits just below the eye, running away to the vanishing point,
## with the field the shot goes through left clear above it, and [ScopeVignette]
## supplies the optic. That is the same trade every game that does not render a
## second view through its scope makes.

## The node this blends: [code]Rifle/ViewModel[/code]. Its transform at
## [method _ready] is captured as the hip pose -- the same authored value
## [RifleRecoil] captures as its own rest transform.
@export var view_model: Node3D

## The optic whose progress drives the blend. Wired at runtime by
## [method MatchController._attach_rifle], mirroring how it wires
## [member Rifle.aim_source] -- the optic lives on the holder's head, not in
## this scene, so it cannot be an ext_resource here.
##
## Left null, the blend simply never leaves the hip pose, which is what makes
## an unwired rifle (a bot's stowed spare, a bare test fixture) safe by default.
@export var optic: WeaponOptic

@export_group("Aimed pose")
## Position of ViewModel's origin at full aim, in the same camera-space metres
## as the authored hip position -- (0,0,0) is the eye, -Z is downrange.
##
## [b]x = 0[/b]: dead centre. The hip pose holds the rifle out to the right;
## aiming brings it in front of the face, and the symmetry is most of what
## reads as "aimed" at a glance.
##
## [b]y = -0.083[/b] -- THE SCOPE ON THE EYE LINE.: the model's origin is on the bore line, so this is how
## far the barrel sits below the eye. It is the number that decides how much of
## the screen the rifle eats. Raise it (toward zero) and the model climbs over
## the crosshair; drop it further and the rifle stops looking like it came up
## at all. At -0.175 the top of the scope clears the point of aim while still
## filling the bottom of the frame, and the base of a man at 20 m is the
## closest thing it hides.
##
## [b]z = -0.24[/b]: 24 cm in front of the eye, well clear of the 0.05 m near
## plane even with the stock's recoil pad (local +Z 0.34) at the back of the
## model and the kick shoving it a further few centimetres toward the camera.
## Pulling it closer drops the model lower in frame rather than making it
## bigger, because the whole rifle is behind the eye's own plane at that point;
## pushing it away raises it toward the crosshair.
@export var aim_position: Vector3 = Vector3(0.0, -0.083, -0.20)

## Euler degrees at full aim, Godot's YXZ order -- the same convention the hip
## pose uses. Zero on purpose, and it is load-bearing: see the class notes.
## Parallel to the view axis is what makes the model converge on the crosshair
## down its own length. Nudge this and the rifle reads as pointing somewhere
## the shot will not go.
@export var aim_rotation_degrees: Vector3 = Vector3.ZERO

## Uniform scale at full aim. Equal to the hip scale on purpose -- the sense of
## the rifle coming toward the eye is carried by [member aim_position] alone,
## and a model that also grows reads as a model growing rather than a rifle
## approaching. It is exported anyway because it costs nothing and the blend
## slerps rather than lerps (see [method get_current_base_pose]), so a
## different value here is safe rather than merely untested.
@export var aim_scale: float = 0.75

## ViewModel's transform at [method _ready], before anything has blended it.
## The hip end of every blend, and never re-derived from wherever the node
## happens to be -- the same guarantee [member RifleRecoil._rest] makes, for
## the same reason.
var _hip: Transform3D = Transform3D.IDENTITY
var _has_hip: bool = false


func _ready() -> void:
	if view_model == null:
		push_error("RifleAds has no ViewModel to pose; the model will not raise.")
		return
	_hip = view_model.transform
	_has_hip = true


## The hip/aim blend for the current instant, with no recoil in it -- read every
## tick by [RifleRecoil], never written to [member view_model] here. See the
## class notes for why the progress comes from [member optic] rather than a
## clock of this node's own.
func get_current_base_pose() -> Transform3D:
	if not _has_hip:
		return Transform3D.IDENTITY
	if view_model == null:
		return _hip
	var t: float = 0.0 if optic == null else optic.get_shaped_progress()
	if t <= 0.0:
		return _hip
	if t >= 1.0:
		return _aim_transform()
	return _hip.interpolate_with(_aim_transform(), t)


## ViewModel's authored hip transform, for tests and for anything that would
## rather not assume [method get_current_base_pose] is at rest to find it.
func get_hip_transform() -> Transform3D:
	return _hip


## The transition, 0.0 at hipfire and 1.0 at full aim, already eased: exactly
## the number [method get_current_base_pose] blends the pose with.
##
## Published here so that [ScopeVignette] -- which hangs beside this node in
## [code]scenes/weapon/rifle.tscn[/code] and has no optic of its own -- draws on
## the same clock the pose and the field of view run on, without a second wire
## from [method MatchController._attach_rifle] that could be left null. Reads
## 0.0 with no optic, which is what makes an unwired rifle draw no vignette.
func get_aim_progress() -> float:
	if optic == null:
		return 0.0
	return optic.get_shaped_progress()


## The tunables the current optic is running on, or null if there is no optic.
##
## The same one wire, for the same reason: every number the vignette draws with
## lives on [ZoomProfile] beside the zoom's own numbers, and this is how a node
## that only knows about the rifle reaches the profile that only the holder's
## head knows about.
func get_zoom_profile() -> ZoomProfile:
	if optic == null:
		return null
	return optic.profile


## [member aim_position], [member aim_rotation_degrees] and [member aim_scale]
## composed the same way the hip pose itself is: a pure rotation, then a
## uniform scale, so the exported degrees mean degrees rather than a
## scale-skewed approximation of them.
func _aim_transform() -> Transform3D:
	var basis: Basis = Basis.from_euler(
		Vector3(
			deg_to_rad(aim_rotation_degrees.x),
			deg_to_rad(aim_rotation_degrees.y),
			deg_to_rad(aim_rotation_degrees.z),
		)
	).scaled(Vector3.ONE * aim_scale)
	return Transform3D(basis, aim_position)
