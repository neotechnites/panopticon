class_name HubCat
extends RigidBody3D

## A hub cat: shove facing it to pick it up, shove again to huck it. Host-decided; a client
## takes it from its record in the snapshot ([NetProp]). Hooked from [method MatchController.apply_shove].

enum State { REST, HELD, FLYING, GONE }
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
const MEOW_SOUND: AudioStream = preload("res://hub/props/cat/fx/meow.wav")
const PURR_SOUND: AudioStream = preload("res://hub/props/cat/fx/purr.wav")
const MEOW_DB: float = 2.0
const PURR_DB: float = 8.0
const EXPLOSION_SOUND: AudioStream = preload("res://hub/props/cat/fx/explosion.wav")
const KEY_TEXTURE: Texture2D = preload("res://hub/props/cat/fx/key_e.png")
## The pet prompt: the E keycap drawn this many times its pixels, this far below the crosshair.
const PROMPT_KEY_SCALE: float = 3.0
const PROMPT_BELOW_CROSSHAIR: float = 90.0
const PROMPT_FONT_SIZE: int = 24
## Extra drop below the crosshair, as a fraction of screen height.
const PROMPT_SCREEN_DROP: float = 0.1

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
## The seat carrying this cat, -1 for nobody: the host's word on every machine.
var _carrier_seat: int = -1
var _purr: AudioStreamPlayer3D = null


func _ready() -> void:
	_home = global_transform
	axis_lock_angular_x = true
	axis_lock_angular_z = true
	collision_layer = CAT_LAYER
	collision_mask = 1
	freeze_mode = RigidBody3D.FREEZE_MODE_KINEMATIC
	freeze = true
	_all.append(self)
	add_to_group(NetProp.GROUP)


func _exit_tree() -> void:
	_all.erase(self)
	_set_local_held(false)


## E while this machine's player carries the cat: a squish; eaten before the lobby sees it.
func _input(event: InputEvent) -> void:
	if not _local_held or not event.is_action_pressed(&"interact"):
		return
	get_viewport().set_input_as_handled()
	var mesh: MeshInstance3D = get_node_or_null("Mesh") as MeshInstance3D
	if mesh == null:
		return
	if _purr == null:
		_purr = become_happy(mesh)
	_pet_tween = pet(mesh, _pet_tween)


## One pet of [param mesh]: a heart and a squish. Returns the squish, which replaces [param tween].
static func pet(mesh: MeshInstance3D, tween: Tween) -> Tween:
	spawn_heart(mesh)
	if tween != null:
		tween.kill()
	mesh.scale = Vector3.ONE
	var squish: Tween = mesh.create_tween()
	squish.tween_property(mesh, "scale", Vector3(1.2, 0.75, 1.2), 0.08)
	squish.tween_property(mesh, "scale", Vector3(0.92, 1.1, 0.92), 0.1)
	squish.tween_property(mesh, "scale", Vector3.ONE, 0.1)
	return squish


## First pet: meow, swap to the happy face (mesh surface 2) and purr; returns the purr.
static func become_happy(mesh: MeshInstance3D) -> AudioStreamPlayer3D:
	if mesh.mesh != null and mesh.mesh.get_surface_count() > 2:
		mesh.set_surface_override_material(1, mesh.mesh.surface_get_material(2))
		mesh.set_surface_override_material(2, mesh.mesh.surface_get_material(1))
	var meow: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	meow.stream = MEOW_SOUND
	meow.volume_db = MEOW_DB
	meow.finished.connect(meow.queue_free)
	mesh.add_child(meow)
	meow.play()
	var purr: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	purr.stream = PURR_SOUND
	purr.volume_db = PURR_DB
	mesh.add_child(purr)
	purr.play()
	return purr


## Back to the neutral face and silence.
func _become_neutral() -> void:
	var mesh: MeshInstance3D = get_node_or_null("Mesh") as MeshInstance3D
	if mesh != null:
		mesh.set_surface_override_material(1, null)
		mesh.set_surface_override_material(2, null)
	if _purr != null:
		_purr.queue_free()
		_purr = null


## A billboarded heart that drifts up off [param over] and fades; rapid pets stack.
static func spawn_heart(over: Node3D) -> void:
	var heart: Sprite3D = Sprite3D.new()
	heart.texture = HEART_TEXTURE
	heart.pixel_size = 0.012
	heart.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	heart.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	heart.shaded = false
	heart.no_depth_test = true
	over.get_tree().current_scene.add_child(heart)
	var start: Vector3 = over.global_position + Vector3(randf_range(-0.2, 0.2), 0.6, 0.0)
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
		_prompt_layer = make_pet_prompt()
		add_child(_prompt_layer)
	elif not held and _prompt_layer != null:
		_prompt_layer.queue_free()
		_prompt_layer = null


## The E keycap and "Pet cat", just under the crosshair.
static func make_pet_prompt() -> CanvasLayer:
	var layer: CanvasLayer = CanvasLayer.new()
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
	label.text = TranslationServer.translate("HUB_CAT_PET_PROMPT")
	label.add_theme_color_override(&"font_outline_color", Color.BLACK)
	label.add_theme_constant_override(&"outline_size", 14)
	label.add_theme_font_size_override(&"font_size", PROMPT_FONT_SIZE)
	row.add_child(label)
	row.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	row.grow_horizontal = Control.GROW_DIRECTION_BOTH
	row.grow_vertical = Control.GROW_DIRECTION_BOTH
	row.anchor_top += PROMPT_SCREEN_DROP
	row.anchor_bottom += PROMPT_SCREEN_DROP
	row.offset_top += PROMPT_BELOW_CROSSHAIR
	row.offset_bottom += PROMPT_BELOW_CROSSHAIR
	layer.add_child(row)
	return layer


## The host's carrier changed: every machine reads the seat from the record; this one's prompt now.
func _announce_held(held: bool) -> void:
	var link: PlayerNetLink = PlayerNetLink.of(_carrier) if held and is_instance_valid(_carrier) else null
	_carrier_seat = link.seat_index if link != null else (0 if held else -1)
	# With no link there is no session, and whoever carries the cat is this machine's player.
	_set_local_held(held and (link == null or link.is_owned_here()))


## Spend [param body]'s shove on a cat: throw the one it carries, else lift one in reach.
## True when a cat took the shove. Authority only, like the shove itself.
static func claim_shove(body: PlayerController, forward: Vector3, reach: float) -> bool:
	if body == null:
		return false
	for cat: HubCat in _all:
		if cat._carrier == body:
			cat._throw()
			return true
	var best: HubCat = _free_in_reach(body, forward, reach)
	if best == null:
		return false
	best._pick_up(body)
	return true


## True when [param body]'s swing now would lift a cat: a lift is free, so the throw can follow at
## once. Read on every machine, so the owner's swing gate predicts the cooldown the host spends.
static func swing_lifts(body: PlayerController, forward: Vector3, reach: float) -> bool:
	return body != null and not is_carrying(body) and _free_in_reach(body, forward, reach) != null


## The nearest cat nobody carries inside [param body]'s reach and facing cone, or null.
static func _free_in_reach(body: PlayerController, forward: Vector3, reach: float) -> HubCat:
	var best: HubCat = null
	var best_distance: float = 0.0
	var here: Vector3 = body.global_position
	for cat: HubCat in _all:
		if cat._carrier_seat >= 0 or cat._gone or cat.multiplayer != body.multiplayer:
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
	return best


## True while [param body] holds a cat: on the host its carrier, elsewhere the seat its record names.
static func is_carrying(body: PlayerController) -> bool:
	var link: PlayerNetLink = PlayerNetLink.of(body)
	for cat: HubCat in _all:
		if cat._carrier == body or (link != null and cat._carrier_seat == link.seat_index):
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
	var at: Vector3 = global_position + Vector3.UP * 0.3
	_state = State.REST
	freeze = true
	linear_velocity = Vector3.ZERO
	angular_velocity = Vector3.ZERO
	var net: NetMatch = NetMatch.of(self) if _networked() else null
	if net != null:
		net.get_session().replicator.send_event(NetEvents.Type.CAT_BLAST, NetCodec.pack_point(0, at))
	_go()
	_show_blast(at)
	get_tree().create_timer(RESPAWN_SECONDS).timeout.connect(_returned)


## The cat went off: hidden at home until it returns.
func _go() -> void:
	_gone = true
	_carrier_seat = -1
	_become_neutral()
	_set_local_held(false)
	visible = false
	collision_layer = 0
	collision_mask = 0
	global_transform = _home


## The cat is back on its spot.
func _returned() -> void:
	_gone = false
	visible = true
	collision_layer = CAT_LAYER
	collision_mask = 1
	global_transform = _home


## A cat blast heard from the host's event ring, drawn by the first hub cat under [param root].
static func blast_in(root: Node, at: Vector3) -> void:
	for cat: HubCat in _all:
		if is_instance_valid(cat) and root.is_ancestor_of(cat):
			cat._show_blast(at)
			return


## [NetProp]: state and carrying seat (u8: state, seat + 1 above it), position and yaw.
func net_record() -> PackedByteArray:
	var buffer: StreamPeerBuffer = StreamPeerBuffer.new()
	buffer.put_u8((State.GONE if _gone else _state) | ((_carrier_seat + 1) << 2))
	buffer.put_16(NetCodec.quantise_metres(global_position.x))
	buffer.put_16(NetCodec.quantise_metres(global_position.y))
	buffer.put_16(NetCodec.quantise_metres(global_position.z))
	buffer.put_u16(NetCodec.quantise_turn(rotation.y))
	return buffer.data_array


func net_apply(record: PackedByteArray) -> void:
	if record.size() != 9:
		return
	var state: State = (record[0] & 3) as State
	if state == State.GONE:
		if not _gone:
			_go()
		return
	if _gone:
		_returned()
	_state = state
	var seat: int = (record[0] >> 2) - 1
	if seat != _carrier_seat:
		_carrier_seat = seat
		var link: PlayerNetLink = _link_of_seat(seat)
		_carrier = link.controller if link != null and state == State.HELD else null
		_set_local_held(link != null and link.is_owned_here())
	if state != State.HELD:
		global_transform = Transform3D(
			Basis(Vector3.UP, NetCodec.turn_of(record.decode_u16(7))), NetCodec.event_point(record, 1)
		)


## The link of [param seat] on this machine, or null.
func _link_of_seat(seat: int) -> PlayerNetLink:
	var net: NetMatch = NetMatch.of(self)
	return net.get_session().replicator.find_link(seat) if net != null and seat >= 0 else null


func _show_blast(at: Vector3) -> void:
	var scene: Node = get_tree().current_scene
	if scene == null:
		scene = get_parent()
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
	blast.pixel_size = 0.06
	blast.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	blast.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	blast.shaded = false
	blast.no_depth_test = true
	scene.add_child(blast)
	blast.global_position = at
	blast.animation_finished.connect(blast.queue_free)
	blast.play(&"boom")
	var sound: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	sound.stream = EXPLOSION_SOUND
	scene.add_child(sound)
	sound.global_position = at
	sound.finished.connect(sound.queue_free)
	sound.play()


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
	if not _is_authority():
		# Carried in the hands this machine draws.
		if _state == State.HELD and is_instance_valid(_carrier) and not _gone:
			global_transform = _carry_transform()
		return
	if _state == State.REST:
		return
	if _state == State.HELD:
		if not is_instance_valid(_carrier) or not _carrier.is_inside_tree():
			_drop()
		else:
			# Carried in the hands the host draws: a remote carrier's, its playout behind (render-only, off every layer).
			var link: PlayerNetLink = PlayerNetLink.of(_carrier)
			global_transform = _carry_transform()
			if link != null:
				global_position += link.drawn_offset()
	elif global_position.y < FALL_OUT_Y:
		_settle(_home)
	elif sleeping:
		_settle(Transform3D(Basis(Vector3.UP, rotation.y), global_position))


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


## True on the machine that moves the cat: the host, or a game with no session. A session that
## has just closed leaves no peer at all, and nobody moves the cat for it.
func _is_authority() -> bool:
	return multiplayer.multiplayer_peer != null and multiplayer.is_server()


func _networked() -> bool:
	var peer: MultiplayerPeer = multiplayer.multiplayer_peer
	return peer != null and not (peer is OfflineMultiplayerPeer)
