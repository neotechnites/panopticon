@tool
class_name MacLift
extends CanvasLayer
## macOS-only output stage: a shadow lift drawn over the finished frame, so the Mac
## matches Ryan's Windows HDR monitors. Windows never builds it; scene lighting is untouched.

const SHADER: Shader = preload("res://scripts/fx/mac_lift.gdshader")
const SDR_GAIN: float = 2.0


static func wanted() -> bool:
	return OS.get_name() == "macOS" and DisplayServer.get_name() != "headless"


func _ready() -> void:
	# The autoload copy of a @tool script also spawns in the editor; the plugin owns that.
	if not wanted() or (Engine.is_editor_hint() and get_parent() == get_tree().root):
		queue_free()
		return
	layer = 100
	var rect: ColorRect = ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var mat: ShaderMaterial = ShaderMaterial.new()
	mat.shader = SHADER
	mat.set_shader_parameter("sdr_gain", SDR_GAIN)
	rect.material = mat
	add_child(rect)
