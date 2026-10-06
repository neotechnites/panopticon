extends SceneTree
## Bakes hell's top-down lava mask for the heat shimmer: R soft lava cover, G/B lowest/highest lava y.
## Run: godot --headless --path . --script res://tools/build_heat_mask.gd (after the map's lava changes).

const SCENE: String = "res://maps/bentham_ring/bentham_ring.tscn"
const OUT: String = "res://maps/bentham_ring/materials/heat_mask.png"
const LAVA: PackedStringArray = ["LavaSea", "LavaRiver", "LavaCrack"]
# Must match heat_shimmer.gdshader's mask_* uniforms.
const SIZE: int = 256
const ORIGIN: Vector2 = Vector2(-80.0, -80.0)
const SPAN: float = 160.0
const Y_LO: float = -16.0
const Y_SPAN: float = 64.0
const STEP: float = 0.25
const BLUR_PX: int = 3


func _init() -> void:
	var root: Node = (load(SCENE) as PackedScene).instantiate()
	var cover: PackedFloat32Array = PackedFloat32Array()
	cover.resize(SIZE * SIZE)
	var lo: PackedFloat32Array = PackedFloat32Array()
	lo.resize(SIZE * SIZE)
	lo.fill(INF)
	var hi: PackedFloat32Array = PackedFloat32Array()
	hi.resize(SIZE * SIZE)
	hi.fill(-INF)
	for node: Node in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = node as MeshInstance3D
		var mesh: ArrayMesh = mi.mesh as ArrayMesh
		if mesh == null:
			continue
		var xf: Transform3D = _global(mi)
		for s: int in mesh.get_surface_count():
			var mat: Material = mi.get_active_material(s)
			if mat == null or not LAVA.has(mat.resource_name):
				continue
			var arrays: Array = mesh.surface_get_arrays(s)
			var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null else PackedInt32Array()
			var count: int = idx.size() if not idx.is_empty() else verts.size()
			for t: int in range(0, count, 3):
				var a: Vector3 = xf * verts[idx[t] if not idx.is_empty() else t]
				var b: Vector3 = xf * verts[idx[t + 1] if not idx.is_empty() else t + 1]
				var c: Vector3 = xf * verts[idx[t + 2] if not idx.is_empty() else t + 2]
				_splat(a, b, c, cover, lo, hi)
	root.free()
	var img: Image = Image.create(SIZE, SIZE, false, Image.FORMAT_RGB8)
	for y: int in SIZE:
		for x: int in SIZE:
			var m: float = 0.0
			var wsum: float = 0.0
			var l: float = INF
			var h: float = -INF
			for dy: int in range(-BLUR_PX, BLUR_PX + 1):
				for dx: int in range(-BLUR_PX, BLUR_PX + 1):
					var sx: int = clampi(x + dx, 0, SIZE - 1)
					var sy: int = clampi(y + dy, 0, SIZE - 1)
					var i: int = sy * SIZE + sx
					var g: float = exp(-float(dx * dx + dy * dy) / float(BLUR_PX * BLUR_PX))
					m += cover[i] * g
					wsum += g
					l = minf(l, lo[i])
					h = maxf(h, hi[i])
			var r: float = clampf(m / wsum * 2.0, 0.0, 1.0)
			var gl: float = clampf((l - Y_LO) / Y_SPAN, 0.0, 1.0) if l < INF else 1.0
			var bh: float = clampf((h - Y_LO) / Y_SPAN, 0.0, 1.0) if h > -INF else 0.0
			img.set_pixel(x, y, Color(r, gl, bh))
	img.save_png(ProjectSettings.globalize_path(OUT))
	print("heat mask -> ", OUT)
	quit()


func _global(node: Node3D) -> Transform3D:
	var xf: Transform3D = node.transform
	var p: Node = node.get_parent()
	while p != null:
		if p is Node3D:
			xf = (p as Node3D).transform * xf
		p = p.get_parent()
	return xf


func _splat(a: Vector3, b: Vector3, c: Vector3, cover: PackedFloat32Array, lo: PackedFloat32Array, hi: PackedFloat32Array) -> void:
	var n: int = maxi(1, int(ceil(maxf(a.distance_to(b), maxf(b.distance_to(c), c.distance_to(a))) / STEP)))
	for i: int in n + 1:
		for j: int in n + 1 - i:
			var u: float = float(i) / n
			var v: float = float(j) / n
			var p: Vector3 = a + (b - a) * u + (c - a) * v
			var px: int = int((p.x - ORIGIN.x) / SPAN * SIZE)
			var pz: int = int((p.z - ORIGIN.y) / SPAN * SIZE)
			if px < 0 or pz < 0 or px >= SIZE or pz >= SIZE:
				continue
			var k: int = pz * SIZE + px
			cover[k] = 1.0
			lo[k] = minf(lo[k], p.y)
			hi[k] = maxf(hi[k], p.y)
