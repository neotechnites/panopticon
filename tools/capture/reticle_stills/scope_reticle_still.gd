extends Node3D

## Still rig for tools/pc_shot.sh: a map, the guard's eye in its tower, the rifle fully scoped
## with drop 22 and a 195 m/s round, so the reticle can be seen against that map.

@export var map: PackedScene
@export var eye_height: float = 1.6
@export var scoped_fov: float = 40.0

var _rifle: Rifle


func _ready() -> void:
	add_child(map.instantiate())
	var rules: MatchRules = (load("res://match/rules/default_match_rules.tres") as MatchRules).duplicate() as MatchRules
	rules.guard_projectile_speed = MatchRules.SUGGESTED_PROJECTILE_SPEED
	var profile: WeaponProfile = (load("res://weapons/default_weapon_profile.tres") as WeaponProfile).duplicate() as WeaponProfile
	profile.projectile_gravity = 22.0
	var holder: PlayerController = (load("res://characters/player/player.tscn") as PackedScene).instantiate() as PlayerController
	holder.profile = load("res://characters/player/default_movement_profile.tres") as MovementProfile
	_silence(holder)
	add_child(holder)
	holder.global_position = Vector3(0.0, -500.0, 0.0)
	holder.process_mode = Node.PROCESS_MODE_DISABLED
	_rifle = (load("res://weapons/rifle.tscn") as PackedScene).instantiate() as Rifle
	_silence(_rifle)
	_rifle.profile = profile
	_rifle.rules = rules
	add_child(_rifle)
	_rifle.shooter_body = holder
	var vignette: ScopeVignette = _rifle.get_node(^"ScopeVignette") as ScopeVignette
	vignette.set_process(false)
	vignette.overlay.visible = true
	(vignette.overlay.material as ShaderMaterial).set_shader_parameter("amount", 1.0)
	vignette.reticle.visible = true
	vignette.reticle.modulate.a = 1.0
	(_rifle.get_node(^"ViewModel") as Node3D).visible = false


func _process(_delta: float) -> void:
	var camera: Camera3D = get_viewport().get_camera_3d()
	if camera == null:
		return
	var spawn: Node3D = find_child("TowerSpawn", true, false) as Node3D
	var target: Node3D = find_child("PrisonerStart", true, false) as Node3D
	var vignette: ScopeVignette = _rifle.get_node(^"ScopeVignette") as ScopeVignette
	(vignette.overlay.material as ShaderMaterial).set_shader_parameter(
		"aspect", get_viewport().get_visible_rect().size.x / get_viewport().get_visible_rect().size.y
	)
	if spawn != null and target != null:
		camera.global_position = spawn.global_position + Vector3.UP * eye_height
		camera.look_at(target.global_position + Vector3.UP * 1.0, Vector3.UP)
	camera.fov = scoped_fov
	_rifle.aim_source = camera


func _silence(node: Node) -> void:
	if node is HumanIntentSource:
		(node as HumanIntentSource).capture_mouse_on_ready = false
	if node is WeaponInput:
		(node as WeaponInput).capture_mouse_on_ready = false
	for child: Node in node.get_children():
		_silence(child)
