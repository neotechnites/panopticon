class_name HubCat
extends RigidBody3D

## A hub cat: shove facing it to pick it up, shove again to huck it. Host-decided;
## clients follow its pose. Hooked from [method MatchController.apply_shove].

enum State { REST, HELD, FLYING }

## Where the cat sits relative to the carrier's head: just under and ahead of the face.
const CARRY_OFFSET: Vector3 = Vector3(0.0, -0.3, -0.55)
const THROW_SPEED: float = 10.0
const THROW_LIFT: float = 2.0
const THROW_SPIN: float = 12.0
## Height off the floor of the cone check: a cat on a ledge above you is out of reach.
const REACH_HEIGHT: float = 2.0
const FACING_DOT: float = 0.5
const FALL_OUT_Y: float = -60.0
const CAT_LAYER: int = 1 << 3
const FUSE_SECONDS: float = 0.5
const RESPAWN_SECONDS: float = 4.0
const HEART_TEXTURE: Texture2D = preload("res://hub/props/cat/fx/heart.png")
const EXPLOSION_SHEET: Texture2D = preload("res://hub/props/cat/fx/explosion_sheet.png")
const EXPLOSION_SOUND: AudioStream = preload("res://hub/props/cat/fx/explosion.wav")
const KEY_TEXTURE: Texture2D = preload("res://hub/props/cat/fx/key_e.png")
## The pet prompt: the E keycap drawn this many times its pixels, this far below the crosshair.
const PROMPT_KEY_SCALE: float = 6.0
const PROMPT_BELOW_CROSSHAIR: float = 90.0
const PROMPT_FONT_SIZE: int = 48

## Frames in the explosion sheet's horizontal strip.
@export var explosion_frames: int = 17
@export var explosion_fps: float = 16.0

static var _all: Array[HubCat] = []

var _state: State = State.REST
var _carrier: PlayerController = null
var _home: Transform3D = Transform3D.IDENTITY
var _local_held: bool = false
var _prompt_layer: CanvasLayer = null
var _pet_tween: Tween = null
var _fuse: int = 0
var _gone: bool = false


func _ready() -> void:
	_home = global_transform
	axis_lock_angular_x = true
	axis_lock_angular_z = true
	collision_layer = CAT_LAYER
	collision_mask = 1
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	_all.append(self)


func _exit_tree() -> void:
	_all.erase(self)
	_set_local_held(false)


## E while this machine's player carries the cat: a squish; eaten before the lobby sees it.
func _input(event: InputEvent) -> void:
	if not _local_held or not event.is_action_pressed(&"interact"):
		return
	get_viewport().set_input_as_handled()
	var mesh: Node3D = get_node_or_null("Mesh") as Node3D
	if mesh == null:
		return
	_spawn_heart()
	if _pet_tween != null:
		_pet_tween.kill()
	mesh.scale = Vector3.ONE
	_pet_tween = create_tween()
	_pet_tween.tween_property(mesh, "scale", Vector3(1.2, 0.75, 1.2), 0.08)
	_pet_tween.tween_property(mesh, "scale", Vector3(0.92, 1.1, 0.92), 0.1)
	_pet_tween.tween_property(mesh, "scale", Vector3.ONE, 0.1)


## A billboarded heart that drifts up and fades; rapid pets stack.
func _spawn_heart() -> void:
	var heart: Sprite3D = Sprite3D.new()
	heart.texture = HEART_TEXTURE
	heart.pixel_size = 0.012
	heart.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	heart.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	heart.shaded = false
	heart.no_depth_test = true
	get_tree().current_scene.add_child(heart)
	var start: Vector3 = global_position + Vector3(randf_range(-0.2, 0.2), 0.6, 0.0)
	heart.global_position = start
	var drift: float = randf_range(-0.4, 0.4)
	var tween: Tween = heart.create_tween().set_parallel(true)
	tween.tween_property(heart, "global_position", start + Vector3(drift, 1.6, 0.0), 2.0)
	tween.tween_property(heart, "modulate:a", 0.0, 2.0).set_delay(0.8)
	tween.chain().tween_callback(heart.queue_free)


## Show or hide the pet prompt on this machine.
func _set_local_held(held: bool) -> void:
	_local_held = held
	if held and _prompt_layer == null:
		_prompt_layer = CanvasLayer.new()
		var row: HBoxContainer = HBoxContainer.new()
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override(&"separation", 24)
		var key: TextureRect = TextureRect.new()
		key.texture = KEY_TEXTURE
		key.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		key.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		key.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		key.custom_minimum_size = Vector2(KEY_TEXTURE.get_width(), KEY_TEXTURE.get_height()) * PROMPT_KEY_SCALE
		row.add_child(key)
		var label: Label = Label.new()
		label.text = tr("HUB_CAT_PET_PROMPT")
		label.add_theme_color_override(&"font_outline_color", Color.BLACK)
		label.add_theme_constant_override(&"outline_size", 14)
		label.add_theme_font_size_override(&"font_size", PROMPT_FONT_SIZE)
		row.add_child(label)
		row.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
		row.grow_horizontal = Control.GROW_DIRECTION_BOTH
		row.grow_vertical = Control.GROW_DIRECTION_BOTH
		row.offset_top += PROMPT_BELOW_CROSSHAIR
		row.offset_bottom += PROMPT_BELOW_CROSSHAIR
		_prompt_layer.add_child(row)
		add_child(_prompt_layer)
	elif not held and _prompt_layer != null:
		_prompt_layer.queue_free()
		_prompt_layer = null


func _announce_held(held: bool) -> void:
	var peer: int = 1
	if held and is_instance_valid(_carrier):
		for child: Node in _carrier.get_children():
			if child is PlayerNetLink:
				peer = (child as PlayerNetLink).owner_peer_id
	if _networked():
		rpc(&"_held_by", peer if held else 0)
	_held_by(peer if held else 0)


## Authority to everyone: which peer carries the cat now, 0 for none.
@rpc("authority", "reliable", "call_remote", 1)
func _held_by(peer: int) -> void:
	var mine: int = 1
	if _networked():
		mine = multiplayer.get_unique_id()
	_set_local_held(peer != 0 and peer == mine)


## Spend [param body]'s shove on a cat: throw the one it carries, else lift one in reach.
## True when a cat took the shove. Authority only, like the shove itself.
static func claim_shove(body: PlayerController, forward: Vector3, reach: float) -> bool:
	if body == null:
		return false
	var best: HubCat = null
	var best_distance: float = 0.0
	for cat: HubCat in _all:
		if cat._carrier == body:
			cat._throw()
			return true
	var here: Vector3 = body.global_position
	for cat: HubCat in _all:
		if cat._state == State.HELD or cat._gone:
			continue
		var offset: Vector3 = cat.global_position - here
		if absf(offset.y) > REACH_HEIGHT:
			continue
		offset.y = 0.0
		var distance: float = offset.length()
		if distance > reach or (distance > 1e-3 and forward.dot(offset / distance) < FACING_DOT):
			continue
		if best == null or distance < best_distance:
			best = cat
			best_distance = distance
	if best == null:
		return false
	best._pick_up(body)
	return true


## True while [param body] holds a cat.
static func is_carrying(body: PlayerController) -> bool:
	for cat: HubCat in _all:
		if cat._carrier == body:
			return true
	return false


func _pick_up(body: PlayerController) -> void:
	_fuse += 1
	_carrier = body
	_state = State.HELD
	collision_layer = 0
	collision_mask = 0
	freeze = true
	_announce_held(true)


func _throw() -> void:
	var look: Basis = _carry_basis()
	global_transform = _carry_transform()
	_carrier = null
	_announce_held(false)
	_state = State.FLYING
	collision_layer = CAT_LAYER
	collision_mask = 1
	freeze = false
	sleeping = false
	linear_velocity = -look.z * THROW_SPEED + Vector3.UP * THROW_LIFT
	angular_velocity = Vector3.UP * THROW_SPIN
	_fuse += 1
	var mine: int = _fuse
	get_tree().create_timer(FUSE_SECONDS).timeout.connect(func() -> void: _explode(mine))


## Boom at the cat's spot, then the cat sits out a few seconds and returns home.
func _explode(fuse: int) -> void:
	if fuse != _fuse or _gone or not is_inside_tree():
		return
	_gone = true
	var scene: Node = get_tree().current_scene
	var blast: AnimatedSprite3D = AnimatedSprite3D.new()
	var frames: SpriteFrames = SpriteFrames.new()
	frames.add_animation(&"boom")
	frames.set_animation_loop(&"boom", false)
	frames.set_animation_speed(&"boom", explosion_fps)
	var width: int = EXPLOSION_SHEET.get_width() / maxi(explosion_frames, 1)
	for i: int in explosion_frames:
		var atlas: AtlasTexture = AtlasTexture.new()
		atlas.atlas = EXPLOSION_SHEET
		atlas.region = Rect2(i * width, 0, width, EXPLOSION_SHEET.get_height())
		frames.add_frame(&"boom", atlas)
	blast.sprite_frames = frames
	blast.pixel_size = 0.02
	blast.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	blast.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	blast.shaded = false
	blast.no_depth_test = true
	scene.add_child(blast)
	blast.global_position = global_position + Vector3.UP * 0.3
	blast.animation_finished.connect(blast.queue_free)
	blast.play(&"boom")
	var sound: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	sound.stream = EXPLOSION_SOUND
	scene.add_child(sound)
	sound.global_position = blast.global_position
	sound.finished.connect(sound.queue_free)
	sound.play()
	visible = false
	_state = State.REST
	freeze = true
	collision_layer = 0
	collision_mask = 0
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = _home
	get_tree().create_timer(RESPAWN_SECONDS).timeout.connect(_respawn)


func _respawn() -> void:
	_gone = false
	visible = true
	collision_layer = CAT_LAYER
	collision_mask = 1


func _carry_basis() -> Basis:
	if _carrier.head != null:
		return _carrier.head.global_basis.orthonormalized()
	return _carrier.global_basis.orthonormalized()


func _carry_transform() -> Transform3D:
	var origin: Vector3 = _carrier.global_position + Vector3.UP * 1.5
	if _carrier.head != null:
		origin = _carrier.head.global_position
	var look: Basis = _carry_basis()
	return Transform3D(Basis(Vector3.UP, look.get_euler().y), origin + look * CARRY_OFFSET)


func _physics_process(_delta: float) -> void:
	if not multiplayer.is_server() or _state == State.REST:
		return
	if _state == State.HELD:
		if not is_instance_valid(_carrier) or not _carrier.is_inside_tree():
			_drop()
		else:
			global_transform = _carry_transform()
	elif global_position.y < FALL_OUT_Y:
		_settle(_home)
		return
	elif sleeping:
		_settle(Transform3D(Basis(Vector3.UP, rotation.y), global_position))
		return
	if _networked():
		rpc(&"_pose", global_position, rotation.y)


func _drop() -> void:
	_carrier = null
	_announce_held(false)
	_state = State.FLYING
	collision_layer = CAT_LAYER
	collision_mask = 1
	freeze = false
	sleeping = false
	linear_velocity = Vector3.ZERO


func _settle(where: Transform3D) -> void:
	_state = State.REST
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	global_transform = where
	if _networked():
		rpc(&"_rest", where.origin, where.basis.get_euler().y)


func _networked() -> bool:
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	return peer != null and not (peer is OfflineMultiplayerPeer)


## Authority to everyone, every tick the cat is carried or flying.
@rpc("authority", "unreliable_ordered", "call_remote", 3)
func _pose(at: Vector3, yaw: float) -> void:
	if multiplayer.is_server() or not at.is_finite() or not is_finite(yaw):
		return
	global_transform = Transform3D(Basis(Vector3.UP, yaw), at)


## Authority to everyone, once, where the cat came to rest.
@rpc("authority", "reliable", "call_remote", 0)
func _rest(at: Vector3, yaw: float) -> void:
	_pose(at, yaw)
