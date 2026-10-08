extends Node3D

## Capture-only: one map with two guards and two finishers in the tower room, each pair holding the old rifle and the new.
## tools/shot.gd poses it by camera x: 8000 is relative to the tower spawn, 8200+100n to body n alone, 9000+n looks out of body n (y = raise, the optic's linear progress).

const RUNNER: PackedScene = preload("res://characters/bots/ring_runner.tscn")
const PALETTE: RunnerPalette = preload("res://match/rules/default_runner_palette.tres")
const RELATIVE_X: float = 8000.0
const SOLO_X: float = 8200.0
## Metres the tower spawn sits over its floor.
const FLOOR_CLEARANCE: float = 0.25
const EYES_X: float = 9000.0
## Per body: metres right and back of the tower spawn, guard (else finisher), new rifle (else old).
const CAST: Array = [
	[-1.0, 0.0, true, false],
	[1.0, 0.0, true, true],
	[-1.0, 2.5, false, false],
	[1.0, 2.5, false, true],
]

@export_file("*.tscn") var map_scene: String = ""
@export var old_rifle: PackedScene
@export var new_rifle: PackedScene
@export var third_person_fov: float = 40.0

var _spawn: Vector3 = Vector3.ZERO
var _bodies: Array[PlayerController] = []
var _shot_camera: Camera3D = null


func _ready() -> void:
	var arena: Node = (load(map_scene) as PackedScene).instantiate()
	add_child(arena)
	_spawn = (arena.get_node(^"Tower/TowerSpawn") as Node3D).global_position
	var light: CharacterLight = CharacterLight.for_arena(arena)
	for row: Array in CAST:
		_bodies.append(_stand(row, light))


func _process(_delta: float) -> void:
	if _shot_camera == null:
		for child: Node in get_tree().root.get_children():
			if child is Camera3D:
				_shot_camera = child as Camera3D
	if _shot_camera == null or _bodies.size() < CAST.size():
		return
	var asked: Vector3 = _shot_camera.global_position
	if asked.x < RELATIVE_X - 500.0:
		return
	var ahead: Vector3 = -_shot_camera.global_transform.basis.z
	if asked.x >= EYES_X - 0.5:
		_look_out_of(_alone(clampi(roundi(asked.x - EYES_X), 0, _bodies.size() - 1)), ahead, asked.y)
		_shot_camera.global_position = _spawn + Vector3.UP * 3.0
	elif asked.x >= SOLO_X - 50.0:
		var n: int = clampi(roundi((asked.x - SOLO_X) / 100.0), 0, _bodies.size() - 1)
		var feet: Vector3 = _spawn + Vector3(0.0, -FLOOR_CLEARANCE, float(CAST[n][1]))
		_look_from(feet + asked - Vector3(SOLO_X + 100.0 * n, 0.0, 0.0), ahead, _alone(n))
	else:
		_alone(-1)
		_look_from(_spawn + asked - Vector3(RELATIVE_X, 0.0, 0.0), ahead, null)


## Every body back in its row, then body n (if any) to where the match stands its kind: the spawn, or the finisher's offset.
func _alone(n: int) -> PlayerController:
	for i: int in _bodies.size():
		var place: Vector3 = _spawn + Vector3(0.0 if i == n else float(CAST[i][0]), 0.0, float(CAST[i][1]))
		var off: Vector3 = _bodies[i].global_position - place
		if Vector2(off.x, off.z).length() > 0.01:
			_bodies[i].global_position = place
	return _bodies[n] if n >= 0 else null


func _look_from(eye: Vector3, ahead: Vector3, only: PlayerController) -> void:
	PrisonerAvatar.release_viewed_body()
	for body: PlayerController in _bodies:
		body.visible = only == null or body == only
	_shot_camera.global_position = eye
	_shot_camera.look_at(eye + ahead, Vector3.UP)
	_shot_camera.fov = third_person_fov
	_shot_camera.make_current()


func _look_out_of(viewed: PlayerController, ahead: Vector3, raised: float) -> void:
	for body: PlayerController in _bodies:
		body.visible = body == viewed
	viewed.rotation.y = atan2(-ahead.x, -ahead.z)
	viewed.call(&"_set_pitch", asin(clampf(ahead.y, -1.0, 1.0)))
	var optic: WeaponOptic = viewed.get_node(^"Optic") as WeaponOptic
	optic.set_process(false)
	optic.set(&"_progress", raised)
	optic.call(&"_apply")
	(viewed.get_node(^"Head/Camera") as Camera3D).make_current()
	PrisonerAvatar.set_viewed_body(viewed)


func _stand(row: Array, light: CharacterLight) -> PlayerController:
	var body: PlayerController = RUNNER.instantiate() as PlayerController
	for unwanted: String in ["Brain", "BotInput"]:
		var node: Node = body.get_node_or_null(NodePath(unwanted))
		if node != null:
			body.remove_child(node)
			node.free()
	var intent: MannequinIntent = MannequinIntent.new()
	body.add_child(intent)
	body.intent_source = intent
	body.position = _spawn + Vector3(float(row[0]), 0.0, float(row[1]))
	add_child(body)
	var is_guard: bool = row[2]
	var is_new: bool = row[3]
	body.is_guard = is_guard
	body.is_armed = not is_guard
	var rifle: Rifle = (new_rifle if is_new else old_rifle).instantiate() as Rifle
	rifle.get_node(^"HumanTrigger").process_mode = Node.PROCESS_MODE_DISABLED
	body.head.add_child(rifle)
	rifle.aim_source = body.get_node(^"Head/Camera") as Node3D
	rifle.shooter_body = body
	(rifle.get_node(^"Ads") as RifleAds).optic = body.get_node(^"Optic") as WeaponOptic
	# The new rifle's scope draws as it does for the human at the keyboard, so a look out of it shows the vignette too.
	(rifle.get_node(^"ScopeVignette") as ScopeVignette).set_local_holder(is_new)
	var avatar: PrisonerAvatar = body.get_node(^"Avatar") as PrisonerAvatar
	_dress(avatar.mesh, PALETTE.color_for_index(0 if is_guard else 1), light)
	# The old rifle stays as main draws it; the new one is lit as MatchController._light_weapon lights it.
	if is_new:
		for node: Node in rifle.get_node(^"ViewModel/Model").find_children("*", "MeshInstance3D", true, false):
			var mesh: MeshInstance3D = node as MeshInstance3D
			for surface: int in mesh.mesh.get_surface_count():
				mesh.set_surface_override_material(surface, light.apply(mesh.mesh.surface_get_material(surface)))
	return body


## MatchController._tinted_material and _fade_body, for a body no match owns.
func _dress(mesh: MeshInstance3D, colour: Color, light: CharacterLight) -> void:
	var shirt: int = MatchController.shirt_surface_of(mesh)
	for surface: int in mesh.mesh.get_surface_count():
		var material: BaseMaterial3D = mesh.mesh.surface_get_material(surface) as BaseMaterial3D
		if surface == shirt:
			material = material.duplicate() as BaseMaterial3D
			material.albedo_color = MatchController.tint_color(colour)
			material.emission_enabled = true
			material.emission = Color(colour.r, colour.g, colour.b, 1.0)
			material.emission_energy_multiplier = 0.9
		var lit: Material = light.apply(material)
		if surface == shirt or lit != material:
			mesh.set_surface_override_material(surface, lit)
