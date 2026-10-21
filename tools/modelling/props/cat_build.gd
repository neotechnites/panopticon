extends SceneTree

## Builds hub/props/cat/cat_mesh.tres: a chubby standing low-poly grey cat with a ^ ^ 3 face.
## Run: godot --headless --script res://tools/modelling/props/cat_build.gd

const OUT: String = "res://hub/props/cat/cat_mesh.tres"
const GREY := Color(0.52, 0.52, 0.54)
const INK := Color(0.12, 0.12, 0.13)

var _st: SurfaceTool = SurfaceTool.new()
var _tris: int = 0


func _init() -> void:
	_st.begin(Mesh.PRIMITIVE_TRIANGLES)
	_body()
	_head()
	_face()
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


## Like [method _loft] but along +Z: rings are [centre, rx, ry].
func _loft_z(rings: Array, sides: int, col: Color) -> void:
	var pts: Array = []
	for r: Array in rings:
		var row: Array = []
		for s: int in sides:
			var ang: float = TAU * (float(s) + 0.5) / float(sides)
			row.append(r[0] + Vector3(cos(ang) * r[1], sin(ang) * r[2], 0.0))
		pts.append(row)
	for i: int in rings.size() - 1:
		var axis_mid: Vector3 = (rings[i][0] + rings[i + 1][0]) * 0.5
		for s: int in sides:
			_quad(pts[i][s], pts[i][(s + 1) % sides], pts[i + 1][(s + 1) % sides], pts[i + 1][s], col, axis_mid)
	for end: int in [0, rings.size() - 1]:
		var hint: Vector3 = Vector3.FORWARD if end == 0 else Vector3.BACK
		for s: int in sides:
			_tri(rings[end][0], pts[end][s], pts[end][(s + 1) % sides], col, hint)


func _box(centre: Vector3, half: Vector3, col: Color) -> void:
	var c: Array = []
	for i: int in 8:
		c.append(centre + Vector3(half.x * (1 if i & 1 else -1), half.y * (1 if i & 2 else -1), half.z * (1 if i & 4 else -1)))
	_quad(c[0], c[1], c[3], c[2], col, centre)  # back -z
	_quad(c[4], c[5], c[7], c[6], col, centre)  # front +z
	_quad(c[0], c[2], c[6], c[4], col, centre)
	_quad(c[1], c[3], c[7], c[5], col, centre)
	_quad(c[0], c[1], c[5], c[4], col, centre)
	_quad(c[2], c[3], c[7], c[6], col, centre)


const HEAD_RINGS: Array = [
	[Vector3(0, 0.20, 0.19), 0.05, 0.045],
	[Vector3(0, 0.235, 0.20), 0.085, 0.072],
	[Vector3(0, 0.285, 0.205), 0.088, 0.074],
	[Vector3(0, 0.325, 0.198), 0.058, 0.05],
]


func _body() -> void:
	_loft_z([
		[Vector3(0, 0.19, -0.2), 0.05, 0.05],
		[Vector3(0, 0.18, -0.15), 0.115, 0.105],
		[Vector3(0, 0.165, -0.05), 0.14, 0.125],
		[Vector3(0, 0.165, 0.05), 0.135, 0.12],
		[Vector3(0, 0.18, 0.13), 0.095, 0.09],
		[Vector3(0, 0.2, 0.17), 0.05, 0.05],
	], 8, GREY)


func _head() -> void:
	_loft(HEAD_RINGS, 8, func(_i: int, _s: int, _mid: Vector3) -> Color: return GREY, GREY)
	for sx: float in [-1.0, 1.0]:
		var x: float = 0.045 * sx
		var b0: Vector3 = Vector3(x - 0.024, 0.318, 0.18)
		var b1: Vector3 = Vector3(x + 0.024, 0.318, 0.18)
		var b2: Vector3 = Vector3(x, 0.318, 0.22)
		var apex: Vector3 = Vector3(x * 1.3, 0.385, 0.195)
		var ec: Vector3 = (b0 + b1 + b2 + apex) * 0.25
		_tri(b0, b1, apex, GREY, Vector3.FORWARD)
		_tri(b1, b2, apex, GREY, b1 + b2 - ec * 2.0)
		_tri(b2, b0, apex, GREY, b2 + b0 - ec * 2.0)
		_tri(b0, b2, b1, GREY, Vector3.DOWN)


## Front of the head's surface at height [param y] (the octagon's front flat), plus a hair.
func _front_z(y: float) -> float:
	var k: float = cos(TAU * 0.5 / 8.0)
	for i: int in HEAD_RINGS.size() - 1:
		var a: Array = HEAD_RINGS[i]
		var b: Array = HEAD_RINGS[i + 1]
		if y >= a[0].y and y <= b[0].y:
			var t: float = (y - a[0].y) / (b[0].y - a[0].y)
			return lerpf(a[0].z + a[2] * k, b[0].z + b[2] * k, t) + 0.004
	return HEAD_RINGS[0][0].z


## A dark line on the face from [param a] to [param b] (x, y), thickness [param w].
func _ink(a: Vector2, b: Vector2, w: float) -> void:
	var n: Vector2 = (b - a).orthogonal().normalized() * w * 0.5
	var pts: Array = [a - n, b - n, b + n, a + n]
	var v: Array = []
	for p: Vector2 in pts:
		v.append(Vector3(p.x, p.y, _front_z(p.y)))
	_quad(v[0], v[1], v[2], v[3], INK, Vector3(0, 0.27, 0.0))


func _face() -> void:
	for sx: float in [-1.0, 1.0]:  # happy closed eyes: ^ ^
		var x: float = 0.038 * sx
		_ink(Vector2(x - 0.017, 0.272), Vector2(x, 0.287), 0.007)
		_ink(Vector2(x, 0.287), Vector2(x + 0.017, 0.272), 0.007)
	var mouth: Array = [Vector2(-0.018, 0.252), Vector2(-0.009, 0.243), Vector2(0.0, 0.251),
		Vector2(0.009, 0.243), Vector2(0.018, 0.252)]  # a "3" on its side
	for i: int in mouth.size() - 1:
		_ink(mouth[i], mouth[i + 1], 0.006)


func _legs() -> void:
	for sx: float in [-1.0, 1.0]:
		for z: float in [-0.11, 0.09]:
			_box(Vector3(0.068 * sx, 0.055, z), Vector3(0.026, 0.055, 0.026), GREY)


func _tail() -> void:
	var path: Array = [
		Vector3(0.0, 0.21, -0.19), Vector3(0.0, 0.27, -0.24), Vector3(0.0, 0.34, -0.245),
		Vector3(0.0, 0.39, -0.21),
	]
	var r: float = 0.02
	var frames: Array = []
	for i: int in path.size():
		var t: Vector3 = (path[mini(i + 1, path.size() - 1)] - path[maxi(i - 1, 0)]).normalized()
		var side: Vector3 = t.cross(Vector3.RIGHT).normalized()
		var up: Vector3 = side.cross(t).normalized()
		var ring: Array = []
		for k: int in 4:
			var ang: float = TAU * (float(k) + 0.5) / 4.0
			ring.append(path[i] + (side * cos(ang) + up * sin(ang)) * r)
		frames.append(ring)
	for i: int in path.size() - 1:
		var centre: Vector3 = (path[i] + path[i + 1]) * 0.5
		for k: int in 4:
			_quad(frames[i][k], frames[i][(k + 1) % 4], frames[i + 1][(k + 1) % 4], frames[i + 1][k], GREY, centre)
	_quad(frames[-1][0], frames[-1][1], frames[-1][2], frames[-1][3], GREY, path[-2])
