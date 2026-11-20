class_name CatView
extends Node3D

## A cat as it is drawn, shared by the hub cat and the cat power (DESIGN 9): the carry pose and throw,
## the blast, and the pet prompt with its hearts, meow and purr on the machine whose player carries it.

const MESH: Mesh = preload("res://hub/props/cat/cat_mesh.tres")
## Where a carried cat sits relative to the carrier's head: just under and ahead of the face.
const CARRY_OFFSET: Vector3 = Vector3(0.0, -0.3, -0.55)
const THROW_SPEED: float = 10.0
const THROW_LIFT: float = 2.0
const THROW_SPIN: float = 12.0
const EXPLOSION_SHEET: Texture2D = preload("res://hub/props/cat/fx/explosion_sheet.png")
const EXPLOSION_SOUND: AudioStream = preload("res://hub/props/cat/fx/explosion.wav")
const EXPLOSION_FRAMES: int = 17
const EXPLOSION_FPS: float = 16.0
const HEART_TEXTURE: Texture2D = preload("res://hub/props/cat/fx/heart.png")
const MEOW_SOUND: AudioStream = preload("res://hub/props/cat/fx/meow.wav")
const PURR_SOUND: AudioStream = preload("res://hub/props/cat/fx/purr.wav")
const MEOW_DB: float = 2.0
const PURR_DB: float = 8.0
const KEY_TEXTURE: Texture2D = preload("res://hub/props/cat/fx/key_e.png")
## The pet prompt: the E keycap drawn this many times its pixels, this far below the crosshair.
const PROMPT_KEY_SCALE: float = 3.0
const PROMPT_BELOW_CROSSHAIR: float = 90.0
const PROMPT_FONT_SIZE: int = 24
## Extra drop below the crosshair, as a fraction of screen height.
const PROMPT_SCREEN_DROP: float = 0.1

var mesh: MeshInstance3D = null
var _prompt: CanvasLayer = null
var _purr: AudioStreamPlayer3D = null
var _pet_tween: Tween = null


func _init() -> void:
	name = "CatView"
	mesh = MeshInstance3D.new()
	mesh.name = "Mesh"
	mesh.mesh = MESH
	add_child(mesh)
	set_process_input(false)


## Offer this machine's player the pet, or take the offer and the happiness away.
func set_petting(on: bool) -> void:
	if on == (_prompt != null):
		return
	set_process_input(on)
	if on:
		_prompt = make_pet_prompt()
		add_child(_prompt)
		return
	_prompt.queue_free()
	_prompt = null
	become_neutral(mesh, _purr)
	_purr = null
	_pet_tween = null


func is_petting() -> bool:
	return _prompt != null


## E while the prompt is up: a squish and a heart; the first makes the cat happy. The cook rides the intent.
func _input(event: InputEvent) -> void:
	if _prompt == null or not event.is_action_pressed(&"interact"):
		return
	get_viewport().set_input_as_handled()
	if _purr == null:
		_purr = become_happy(mesh)
	_pet_tween = pet(mesh, _pet_tween)


## The look basis of [param carrier]: its head's when it has one.
static func carry_basis(carrier: PlayerController) -> Basis:
	if carrier.head != null:
		return carrier.head.global_basis.orthonormalized()
	return carrier.global_basis.orthonormalized()


## Where a cat carried by [param carrier] is: upright, under and ahead of its face.
static func carry_transform(carrier: PlayerController) -> Transform3D:
	var origin: Vector3 = carrier.global_position + Vector3.UP * 1.5
	if carrier.head != null:
		origin = carrier.head.global_position
	var look: Basis = carry_basis(carrier)
	return Transform3D(Basis(Vector3.UP, look.get_euler().y), origin + look * CARRY_OFFSET)


## The speed a cat leaves [param carrier]'s hands at when it is hucked.
static func throw_velocity(carrier: PlayerController) -> Vector3:
	return -carry_basis(carrier).z * THROW_SPEED + Vector3.UP * THROW_LIFT


## The blast's billboard, not yet played.
static func build_blast_sprite() -> AnimatedSprite3D:
	var blast: AnimatedSprite3D = AnimatedSprite3D.new()
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
	blast.sprite_frames = frames
	blast.pixel_size = 0.06
	blast.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	blast.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	blast.shaded = false
	blast.no_depth_test = true
	return blast


## Play a cat's blast, sprite and sound, at [param at] under [param stage].
static func play_blast(stage: Node, at: Vector3) -> void:
	if stage == null or not at.is_finite():
		return
	var blast: AnimatedSprite3D = build_blast_sprite()
	stage.add_child(blast)
	blast.global_position = at
	blast.animation_finished.connect(blast.queue_free)
	blast.play(&"boom")
	var sound: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	sound.stream = EXPLOSION_SOUND
	stage.add_child(sound)
	sound.global_position = at
	sound.finished.connect(sound.queue_free)
	sound.play()


## One pet of [param cat_mesh]: a heart and a squish. Returns the squish, which replaces [param tween].
static func pet(cat_mesh: MeshInstance3D, tween: Tween) -> Tween:
	spawn_heart(cat_mesh)
	if tween != null:
		tween.kill()
	cat_mesh.scale = Vector3.ONE
	var squish: Tween = cat_mesh.create_tween()
	squish.tween_property(cat_mesh, "scale", Vector3(1.2, 0.75, 1.2), 0.08)
	squish.tween_property(cat_mesh, "scale", Vector3(0.92, 1.1, 0.92), 0.1)
	squish.tween_property(cat_mesh, "scale", Vector3.ONE, 0.1)
	return squish


## First pet: meow, swap to the happy face (mesh surface 2) and purr; returns the purr.
static func become_happy(cat_mesh: MeshInstance3D) -> AudioStreamPlayer3D:
	if cat_mesh.mesh != null and cat_mesh.mesh.get_surface_count() > 2:
		cat_mesh.set_surface_override_material(1, cat_mesh.mesh.surface_get_material(2))
		cat_mesh.set_surface_override_material(2, cat_mesh.mesh.surface_get_material(1))
	var meow: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	meow.stream = MEOW_SOUND
	meow.volume_db = MEOW_DB
	meow.finished.connect(meow.queue_free)
	cat_mesh.add_child(meow)
	meow.play()
	var purr: AudioStreamPlayer3D = AudioStreamPlayer3D.new()
	purr.stream = PURR_SOUND
	purr.volume_db = PURR_DB
	cat_mesh.add_child(purr)
	purr.play()
	return purr


## Back to the neutral face, and [param purr] (if any) silenced.
static func become_neutral(cat_mesh: MeshInstance3D, purr: AudioStreamPlayer3D) -> void:
	if cat_mesh != null:
		cat_mesh.set_surface_override_material(1, null)
		cat_mesh.set_surface_override_material(2, null)
	if is_instance_valid(purr):
		purr.queue_free()


## A billboarded heart that drifts up off [param over] and fades; rapid pets stack.
static func spawn_heart(over: Node3D) -> void:
	var heart: Sprite3D = Sprite3D.new()
	heart.texture = HEART_TEXTURE
	heart.pixel_size = 0.012
	heart.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	heart.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	heart.shaded = false
	heart.no_depth_test = true
	var stage: Node = over.get_tree().current_scene
	(stage if stage != null else over.get_parent()).add_child(heart)
	var start: Vector3 = over.global_position + Vector3(randf_range(-0.2, 0.2), 0.6, 0.0)
	heart.global_position = start
	var drift: float = randf_range(-0.4, 0.4)
	var tween: Tween = heart.create_tween().set_parallel(true)
	tween.tween_property(heart, "global_position", start + Vector3(drift, 1.6, 0.0), 2.0)
	tween.tween_property(heart, "modulate:a", 0.0, 2.0).set_delay(0.8)
	tween.chain().tween_callback(heart.queue_free)


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
