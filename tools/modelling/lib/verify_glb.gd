extends SceneTree

## Proves a freshly built [code].glb[/code] actually imports and instantiates in
## Godot, on the PC, before anybody puts it in [code]assets/models/[/code].
##
## [codeblock]
## godot --headless --path <scratch project> --script res://verify_glb.gd
## [/codeblock]
##
## The scratch project is written by [code]tools/modelling/model[/code] and holds
## exactly two files that matter: [code]model.glb[/code] and, optionally,
## [code]contract.json[/code]. Verification happens in a throwaway project rather
## than in PANOPTICON itself so that a broken model can never dirty the real
## [code].godot/[/code] import cache, and so that this can be run against a
## candidate model that is not in the repo yet.
##
## Exits 0 when the model imported clean and met its contract, 1 otherwise.
##
## [b]What "verified" means here[/b]
##
## Not "the file exists". A [code].glb[/code] can import with warnings, lose its
## skin, land with a mesh but no [AnimationPlayer], or come in under node names
## the game's [NodePath]s do not match -- and every one of those failures looks
## like a gameplay bug days later rather than a modelling bug now. So this walks
## the instantiated tree and reports what is actually in it, then checks that
## against the contract the build script declared:
##
## [codeblock]
## {
##   "node_paths": ["Armature/Skeleton3D/Runner", "AnimationPlayer"],
##   "animations": ["Run"],
##   "bones":      ["Hips", "Spine", ...],
##   "max_tris":   700,
##   "surfaces":   1
## }
## [/codeblock]
##
## [b]The import step is not optional and its output is not noise.[/b] Godot
## imports a [code].glb[/code] on first load and prints its complaints once,
## then never again -- so a second run of a broken model is silent and green.
## [code]model[/code] therefore deletes the scratch [code].godot/[/code] before
## every verify, which is what makes a zero-warning result mean something.

const MODEL_PATH := "res://model.glb"
const CONTRACT_PATH := "res://contract.json"

var _failures: PackedStringArray = []


func _init() -> void:
	print("VERIFY begin %s" % MODEL_PATH)

	if not ResourceLoader.exists(MODEL_PATH):
		_fail("no imported resource at %s -- the import step did not produce one" % MODEL_PATH)
		_finish()
		return

	var packed: PackedScene = load(MODEL_PATH) as PackedScene
	if packed == null:
		_fail("%s did not load as a PackedScene" % MODEL_PATH)
		_finish()
		return

	var root: Node = packed.instantiate()
	if root == null:
		_fail("PackedScene.instantiate() returned null")
		_finish()
		return

	var found_paths: PackedStringArray = []
	var meshes: Array[MeshInstance3D] = []
	var skeletons: Array[Skeleton3D] = []
	var players: Array[AnimationPlayer] = []
	_walk(root, root, found_paths, meshes, skeletons, players)

	print("VERIFY root=%s (%s)" % [root.name, root.get_class()])
	for p: String in found_paths:
		print("VERIFY node %s" % p)

	var total_tris := 0
	var total_surfaces := 0
	for mi: MeshInstance3D in meshes:
		var m: Mesh = mi.mesh
		if m == null:
			_fail("MeshInstance3D '%s' has no mesh" % mi.name)
			continue
		total_surfaces += m.get_surface_count()
		for s: int in m.get_surface_count():
			var arrays: Array = m.surface_get_arrays(s)
			var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
			var vtx: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
			var tris: int = (idx.size() / 3) if idx.size() > 0 else (vtx.size() / 3)
			total_tris += tris
			var mat: Material = m.surface_get_material(s)
			print("VERIFY mesh %s surface %d: %d tris, %d verts, material=%s" % [
				mi.name, s, tris, vtx.size(),
				("<none>" if mat == null else mat.resource_name)])
		var aabb: AABB = m.get_aabb()
		print("VERIFY aabb %s pos=(%.4f,%.4f,%.4f) size=(%.4f,%.4f,%.4f)" % [
			mi.name, aabb.position.x, aabb.position.y, aabb.position.z,
			aabb.size.x, aabb.size.y, aabb.size.z])

	var bone_names: PackedStringArray = []
	for sk: Skeleton3D in skeletons:
		print("VERIFY skeleton %s: %d bones" % [sk.name, sk.get_bone_count()])
		for b: int in sk.get_bone_count():
			bone_names.append(sk.get_bone_name(b))
		print("VERIFY bones %s" % ", ".join(bone_names))

	var anim_names: PackedStringArray = []
	for ap: AnimationPlayer in players:
		for a: StringName in ap.get_animation_list():
			var clip: Animation = ap.get_animation(a)
			anim_names.append(String(a))
			print("VERIFY animation '%s' length=%.4fs loop=%d tracks=%d" % [
				a, clip.length, clip.loop_mode, clip.get_track_count()])

	print("VERIFY totals tris=%d surfaces=%d meshes=%d skeletons=%d players=%d" % [
		total_tris, total_surfaces, meshes.size(), skeletons.size(), players.size()])

	_check_contract(found_paths, bone_names, anim_names, total_tris, total_surfaces)

	root.free()
	_finish()


func _walk(node: Node, root: Node, paths: PackedStringArray,
		meshes: Array[MeshInstance3D], skeletons: Array[Skeleton3D],
		players: Array[AnimationPlayer]) -> void:
	if node != root:
		paths.append(String(root.get_path_to(node)))
	if node is MeshInstance3D:
		meshes.append(node as MeshInstance3D)
	elif node is Skeleton3D:
		skeletons.append(node as Skeleton3D)
	elif node is AnimationPlayer:
		players.append(node as AnimationPlayer)
	for child: Node in node.get_children():
		_walk(child, root, paths, meshes, skeletons, players)


func _check_contract(paths: PackedStringArray, bones: PackedStringArray,
		anims: PackedStringArray, tris: int, surfaces: int) -> void:
	if not FileAccess.file_exists(CONTRACT_PATH):
		print("VERIFY no contract.json -- structural report only")
		return
	var text: String = FileAccess.get_file_as_string(CONTRACT_PATH)
	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		_fail("contract.json is not a JSON object")
		return
	var contract: Dictionary = parsed as Dictionary

	for required: Variant in contract.get("node_paths", []):
		if not paths.has(String(required)):
			_fail("contract: missing node path '%s' (the game's NodePath will break)" % required)

	for required: Variant in contract.get("animations", []):
		if not anims.has(String(required)):
			_fail("contract: missing animation '%s' (have: %s)" % [required, ", ".join(anims)])

	for required: Variant in contract.get("bones", []):
		if not bones.has(String(required)):
			_fail("contract: missing bone '%s'" % required)

	if contract.has("max_tris") and tris > int(contract["max_tris"]):
		_fail("contract: %d tris exceeds budget of %d" % [tris, int(contract["max_tris"])])

	if contract.has("surfaces") and surfaces != int(contract["surfaces"]):
		_fail("contract: %d surfaces, expected %d" % [surfaces, int(contract["surfaces"])])

	if contract.has("height"):
		pass  # height is reported by the Blender side; kept here for symmetry

	if _failures.is_empty():
		print("VERIFY contract satisfied")


func _fail(msg: String) -> void:
	_failures.append(msg)
	printerr("VERIFY FAIL: %s" % msg)


func _finish() -> void:
	if _failures.is_empty():
		print("VERIFY OK")
		quit(0)
	else:
		for f: String in _failures:
			print("VERIFY FAILURE %s" % f)
		print("VERIFY FAILED (%d)" % _failures.size())
		quit(1)
