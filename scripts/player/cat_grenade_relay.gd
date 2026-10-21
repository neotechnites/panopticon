class_name CatGrenadeRelay
extends Node

## The host's cat grenades drawn on every other machine, and their blast played everywhere.
## One per tree at /root/CatGrenadeRelay, so the host's calls land on every peer.
## E on the cat this machine's player holds pets it, as the hub cat is petted.

const NODE_NAME: StringName = &"CatGrenadeRelay"
const EXPLOSION_SHEET: Texture2D = preload("res://hub/props/cat/fx/explosion_sheet.png")
const EXPLOSION_SOUND: AudioStream = preload("res://hub/props/cat/fx/explosion.wav")
const EXPLOSION_FRAMES: int = 17
const EXPLOSION_FPS: float = 16.0
const ENDED_MEMORY: int = 64

static var _instance: CatGrenadeRelay = null

var _shown: Dictionary[int, MeshInstance3D] = {}
## Cats already gone here, so a late unreliable pose cannot redraw one.
var _ended: Dictionary[int, bool] = {}
var _next_id: int = 0
var _held_id: int = 0
var _held_mesh: MeshInstance3D = null
var _prompt: CanvasLayer = null
var _purr: AudioStreamPlayer3D = null
var _pet_tween: Tween = null


## Put the relay in [param tree] if it is not there yet.
static func ensure(tree: SceneTree) -> void:
	if tree == null or is_instance_valid(_instance):
		return
	var existing: Node = tree.root.get_node_or_null(NodePath(NODE_NAME))
	if existing is CatGrenadeRelay:
		_instance = existing
		return
	_instance = CatGrenadeRelay.new()
	_instance.name = NODE_NAME
	tree.root.add_child.call_deferred(_instance)


static func get_relay() -> CatGrenadeRelay:
	return _instance if is_instance_valid(_instance) else null


func next_id() -> int:
	_next_id += 1
	return _next_id


## Authority: where cat [param cat_id] is this tick, and which peer holds it (0 for none).
func pose(cat_id: int, at: Vector3, yaw: float, holder: int, mesh: MeshInstance3D) -> void:
	_track_held(cat_id, holder, mesh)
	if _networked():
		rpc(&"_pose", cat_id, at, yaw, holder)


## Authority: cat [param cat_id] went off at [param at].
func blast(cat_id: int, at: Vector3) -> void:
	_blast(cat_id, at)
	if _networked():
		rpc(&"_blast", cat_id, at)


## Authority: cat [param cat_id] is gone without a blast.
func gone(cat_id: int) -> void:
	_gone(cat_id)
	if _networked():
		rpc(&"_gone", cat_id)


@rpc("authority", "unreliable_ordered", "call_remote", 3)
func _pose(cat_id: int, at: Vector3, yaw: float, holder: int) -> void:
	if multiplayer.is_server() or _ended.has(cat_id) or not at.is_finite() or not is_finite(yaw):
		return
	var mesh: MeshInstance3D = _shown.get(cat_id, null)
	if not is_instance_valid(mesh):
		var scene: Node = get_tree().current_scene
		if scene == null:
			return
		mesh = MeshInstance3D.new()
		mesh.mesh = CatGrenade.MESH
		scene.add_child(mesh)
		_shown[cat_id] = mesh
	mesh.global_transform = Transform3D(Basis(Vector3.UP, yaw), at)
	_track_held(cat_id, holder, mesh)


@rpc("authority", "reliable", "call_remote", 0)
func _blast(cat_id: int, at: Vector3) -> void:
	_gone(cat_id)
	var scene: Node = get_tree().current_scene
	if scene == null or not at.is_finite():
		return
	var blast_sprite: AnimatedSprite3D = AnimatedSprite3D.new()
	var frames: SpriteFrames = SpriteFrames.new()
	frames.add_animation(&"boom")
	frames.set_animation_loop(&"boom", false)
	frames.set_animation_speed(&"boom", EXPLOSION_FPS)
	var width: int = EXPLOSION_SHEET.get_width() / EXPLOSION_FRAMES
	for i: int in EXPLOSION_FRAMES:
		var atlas: AtlasTexture = AtlasTexture.new()
		atlas.atlas = EXPLOSION_SHEET
		atlas.region = Rect2(i * width, 0, width, EXPLOSION_SHEET.get_height())
		frames.add_frame(&"boom", atlas)
	blast_sprite.sprite_frames = frames
	blast_sprite.pixel_size = 0.02
	blast_sprite.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	blast_sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	blast_sprite.shaded = false
	blast_sprite.no_depth_test = true
	scene.add_child(blast_sprite)
	blast_sprite.global_position = at
	blast_sprite.animation_finished.connect(blast_sprite.queue_free)
	blast_sprite.play(&"boom")
	var sound: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	sound.stream = EXPLOSION_SOUND
	scene.add_child(sound)
	sound.global_position = at
	sound.finished.connect(sound.queue_free)
	sound.play()


@rpc("authority", "reliable", "call_remote", 0)
func _gone(cat_id: int) -> void:
	if _ended.size() >= ENDED_MEMORY:
		_ended.clear()
	_ended[cat_id] = true
	if _held_id == cat_id:
		_track_held(cat_id, 0, null)
	var mesh: MeshInstance3D = _shown.get(cat_id, null)
	if is_instance_valid(mesh):
		mesh.queue_free()
	_shown.erase(cat_id)


## Pet the held cat: [method HubCat.pet], and the first pet makes it happy. The cook rides the intent.
func _input(event: InputEvent) -> void:
	if _held_id == 0 or not is_instance_valid(_held_mesh) or not event.is_action_pressed(&"interact"):
		return
	get_viewport().set_input_as_handled()
	if _purr == null:
		_purr = HubCat.become_happy(_held_mesh)
	_pet_tween = HubCat.pet(_held_mesh, _pet_tween)


## Show the pet prompt while this machine's player holds [param cat_id].
func _track_held(cat_id: int, holder: int, mesh: MeshInstance3D) -> void:
	var mine: bool = holder != 0 and holder == multiplayer.get_unique_id() and mesh != null
	if mine and (_held_id != cat_id or _held_mesh != mesh):
		_held_id = cat_id
		_held_mesh = mesh
		_purr = null
		_pet_tween = null
		if _prompt == null:
			_prompt = HubCat.make_pet_prompt()
			add_child(_prompt)
	elif not mine and _held_id == cat_id:
		_held_id = 0
		_held_mesh = null
		_purr = null
		_pet_tween = null
		if _prompt != null:
			_prompt.queue_free()
			_prompt = null


func _networked() -> bool:
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	return peer != null and not (peer is OfflineMultiplayerPeer) and multiplayer.is_server()
