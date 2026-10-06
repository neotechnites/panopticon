extends SceneTree

## The ring scene alone, as the editor opens it (no match, no capture grade), from
## one camera pose: the reference a capture's brightness is checked against.
## [code]godot --path . --script res://tools/capture/ring_still.gd --write-movie x.avi --fixed-fps 60 -- --pos=x,y,z --look=x,y,z --fov=75 --frames=30[/code]

const RING: String = "res://maps/bentham_ring/bentham_ring.tscn"

var _frames: int = 0
var _want: int = 30


func _initialize() -> void:
	var opts: Dictionary = {"pos": "0,27,47", "look": "0,23,0", "fov": "75", "frames": "30", "shimmer": "1"}
	for arg: String in OS.get_cmdline_user_args():
		var eq: int = arg.find("=")
		if arg.begins_with("--") and eq > 0:
			opts[arg.substr(2, eq - 2)] = arg.substr(eq + 1)
	_want = int(opts["frames"])
	var ring: Node = (load(RING) as PackedScene).instantiate()
	root.add_child(ring)
	if opts["shimmer"] == "0":
		ring.get_node(^"HeatShimmer").queue_free()
	var cam := Camera3D.new()
	cam.fov = float(opts["fov"])
	cam.far = 400.0
	cam.near = 0.05
	cam.look_at_from_position(_vec(opts["pos"]), _vec(opts["look"]), Vector3.UP)
	cam.current = true
	root.add_child(cam)


func _process(_delta: float) -> bool:
	_frames += 1
	return _frames >= _want


static func _vec(spec: String) -> Vector3:
	var p: PackedStringArray = spec.split(",")
	return Vector3(float(p[0]), float(p[1]), float(p[2]))
