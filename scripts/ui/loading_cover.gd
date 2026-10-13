class_name LoadingCover
extends CanvasLayer

## An opaque screen over a scene that is still loading. After [method release] the world draws
## underneath it (first-draw shader compiles land here) and it lifts once frame times settle.

## A frame longer than this is still settling.
const SETTLED_MS: int = 40
## Settled frames in a row before the cover lifts.
const SETTLED_FRAMES: int = 8
## The cover lifts after this long released, settled or not.
const MAX_HOLD_MS: int = 4000

var _released_ms: int = -1
var _last_ms: int = 0
var _calm: int = 0


func _init() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	var back: ColorRect = ColorRect.new()
	back.color = Color.BLACK
	back.mouse_filter = Control.MOUSE_FILTER_IGNORE
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	var label: Label = Label.new()
	label.text = tr("MP_LOADING")
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.set_anchors_preset(Control.PRESET_FULL_RECT)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_size_override(&"font_size", 32)
	back.add_child(label)


## The world is drawing now: start watching frame times.
func release() -> void:
	if _released_ms < 0:
		_released_ms = Time.get_ticks_msec()
		_last_ms = _released_ms


func is_covering() -> bool:
	return is_inside_tree()


func _process(_delta: float) -> void:
	if _released_ms < 0:
		return
	var now: int = Time.get_ticks_msec()
	_calm = _calm + 1 if now - _last_ms <= SETTLED_MS else 0
	_last_ms = now
	if _calm >= SETTLED_FRAMES or now - _released_ms >= MAX_HOLD_MS:
		queue_free()
