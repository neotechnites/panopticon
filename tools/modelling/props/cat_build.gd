extends SceneTree

## Builds hub/props/cat/cat_mesh.tres: a sitting low-poly grey cat, ~0.35 m, flat-shaded vertex colours.
## Run: godot --headless --script res://tools/modelling/props/cat_build.gd

const OUT: String = "res://hub/props/cat/cat_mesh.tres"
const GREY := Color(0.50, 0.50, 0.52)
const DARK := Color(0.27, 0.27, 0.29)
const LIGHT := Color(0.68, 0.68, 0.70)
const EYE := Color(0.78, 0.80, 0.22)
const PINK := Color(0.72, 0.52, 0.52)
const NOSE := Color(0.32, 0.22, 0.22)

var _st: SurfaceTool = SurfaceTool.new()
var _tris: int = 0


func _init() -> void:
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_body()
	_head()
	_legs()
	_tail()
	var mat: StandardMaterial3D = StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.vertex_color_is_srgb = true
	mat.roughness = 1.0
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_st.set_material(mat)
	var mesh: ArrayMesh = _st.commit()
	print("cat tris: ", _tris)
	var err: int = ResourceSaver.save(mesh, OUT)
	print("saved ", OUT, " err=", err)
	quit()


func _tri(a: Vector3, b: Vector3, c: Vector3, col: Color, out_hint: Vector3) -> void:
	var n: Vector3 = (b - a).cross(c - a).normalized()
	if n.dot(out_hint) < 0.0:
		var t: Vector3 = b
		b = c
		c = t
		n = -n
	for p: Vector3 in [a, c, b]:  # Godot fronts are clockwise.
		_st.set_color(col)
		_st.set_normal(n)
		_st.add_vertex(p)
	_tris += 1


func _quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, col: Color, centre: Vector3) -> void:
	var mid: Vector3 = (a + b + c + d) * 0.25
	_tri(a, b, c, col, mid - centre)
	_tri(a, c, d, col, mid - centre)


## Rings are [centre, rx, rz]; colour_of(ring, side, face_mid) picks each band face's colour.
func _loft(rings: Array, sides: int, colour_of: Callable, cap_col: Color) -> void:
	var pts: Array = []
	for r: Array in rings:
		var row: Array = []
		for s: int in sides:
			var ang: float = TAU * (float(s) + 0.5) / float(sides)
			row.append(r[0] + Vector3(cos(ang) * r[1], 0.0, sin(ang) * r[2]))
		pts.append(row)
	for i: int in rings.size() - 1:
		var axis_mid: Vector3 = (rings[i][0] + rings[i + 1][0]) * 0.5
		for s: int in sides:
			var a: Vector3 = pts[i][s]
			var b: Vector3 = pts[i][(s + 1) % sides]
			var c: Vector3 = pts[i + 1][(s + 1) % sides]
			var d: Vector3 = pts[i + 1][s]
			var mid: Vector3 = (a + b + c + d) * 0.25
			_quad(a, b, c, d, colour_of.call(i, s, mid), axis_mid)
	for end: int in [0, rings.size() - 1]:
		var c0: Vector3 = rings[end][0]
		var hint: Vector3 = Vector3.DOWN if end == 0 else Vector3.UP
		for s: int in sides:
			_tri(c0, pts[end][s], pts[end][(s + 1) % sides], cap_col, hint)


func _box(centre: Vector3, half: Vector3, col: Color, front_col: Color = Color(0, 0, 0, 0)) -> void:
	var c: Array = []
	for i: int in 8:
		c.append(centre + Vector3(half.x * (1 if i & 1 else -1), half.y * (1 if i & 2 else -1), half.z * (1 if i & 4 else -1)))
	_quad(c[0], c[1], c[3], c[2], col, centre)  # back -z
	_quad(c[4], c[5], c[7], c[6], front_col if front_col.a > 0.0 else col, centre)  # front +z
	_quad(c[0], c[2], c[6], c[4], col, centre)
	_quad(c[1], c[3], c[7], c[5], col, centre)
	_quad(c[0], c[1], c[5], c[4], col, centre)
	_quad(c[2], c[3], c[7], c[6], col, centre)


func _body() -> void:
	var rings: Array = [
		[Vector3(0, 0.0, -0.01), 0.085, 0.11],
		[Vector3(0, 0.07, -0.01), 0.095, 0.115],
		[Vector3(0, 0.15, 0.0), 0.08, 0.09],
		[Vector3(0, 0.215, 0.025), 0.056, 0.056],
		[Vector3(0, 0.25, 0.035), 0.04, 0.04],
	]
	_loft(rings, 8, func(i: int, _s: int, mid: Vector3) -> Color:
		if mid.z > 0.06:
			return LIGHT if i < 3 else GREY  # pale chest
		if (i == 0 or i == 2) and mid.z < 0.02:
			return DARK  # tabby stripes over the back
		return GREY, DARK)


func _head() -> void:
	var rings: Array = [
		[Vector3(0, 0.235, 0.04), 0.035, 0.035],
		[Vector3(0, 0.262, 0.045), 0.065, 0.055],
		[Vector3(0, 0.30, 0.045), 0.07, 0.058],
		[Vector3(0, 0.335, 0.04), 0.045, 0.04],
	]
	_loft(rings, 8, func(i: int, _s: int, mid: Vector3) -> Color:
		if i == 2 and absf(mid.x) < 0.03 and mid.z < 0.06:
			return DARK
		return GREY, DARK)
	_box(Vector3(0, 0.272, 0.1), Vector3(0.026, 0.018, 0.016), LIGHT)
	_tri(Vector3(-0.008, 0.286, 0.117), Vector3(0.008, 0.286, 0.117), Vector3(0, 0.278, 0.117), NOSE, Vector3.BACK)
	for sx: float in [-1.0, 1.0]:
		var x: float = 0.03 * sx
		_quad(Vector3(x - 0.01, 0.296, 0.102), Vector3(x + 0.01, 0.296, 0.102),
			Vector3(x + 0.01, 0.31, 0.098), Vector3(x - 0.01, 0.31, 0.098), EYE, Vector3(x, 0.30, 0.0))
		var b0: Vector3 = Vector3(x - 0.02, 0.325, 0.03)
		var b1: Vector3 = Vector3(x + 0.02, 0.325, 0.03)
		var b2: Vector3 = Vector3(x, 0.325, 0.065)
		var apex: Vector3 = Vector3(x * 1.25, 0.385, 0.04)
		var ec: Vector3 = (b0 + b1 + b2 + apex) * 0.25
		_tri(b0, b1, apex, DARK, Vector3.FORWARD)
		_tri(b1, b2, apex, PINK if sx < 0.0 else DARK, b1 + b2 - ec * 2.0)
		_tri(b2, b0, apex, DARK if sx < 0.0 else PINK, b2 + b0 - ec * 2.0)
		_tri(b0, b2, b1, DARK, Vector3.DOWN)


func _legs() -> void:
	for sx: float in [-1.0, 1.0]:
		_box(Vector3(0.032 * sx, 0.075, 0.085), Vector3(0.016, 0.075, 0.016), GREY)
		_box(Vector3(0.032 * sx, 0.01, 0.1), Vector3(0.018, 0.01, 0.022), LIGHT)


func _tail() -> void:
	var path: Array = [
		Vector3(0.0, 0.03, -0.115), Vector3(0.065, 0.022, -0.125), Vector3(0.115, 0.02, -0.07),
		Vector3(0.125, 0.02, 0.0), Vector3(0.1, 0.022, 0.065),
	]
	var r: float = 0.016
	var frames: Array = []
	for i: int in path.size():
		var t: Vector3 = (path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)]).normalized()
		var side: Vector3 = t.cross(Vector3.UP).normalized()
		var up: Vector3 = side.cross(t).normalized()
		var ring: Array = []
		for k: int in 4:
			var ang: float = TAU * (float(k) + 0.5) / 4.0
			ring.append(path[i] + (side * cos(ang) + up * sin(ang)) * r)
		frames.append(ring)
	for i: int in path.size() - 1:
		var col: Color = DARK if i == path.size() - 2 or i == 1 else GREY
		var centre: Vector3 = (path[i] + path[i + 1]) * 0.5
		for k: int in 4:
			_quad(frames[i][k], frames[i][(k + 1) % 4], frames[i + 1][(k + 1) % 4], frames[i + 1][k], col, centre)
	_quad(frames[-1][0], frames[-1][1], frames[-1][2], frames[-1][3], DARK, path[-2])
