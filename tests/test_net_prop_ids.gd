extends TestCase

## Phase 6: every scene prop's id (the u16 hash of its path in its scene) is unique in every shipped scene.

const HUB_SCENE_PATH: String = "res://hub/hub.tscn"
const MATCH_SCENE_PATH: String = "res://match/match.tscn"


func test_no_two_props_share_an_id_in_any_shipped_scene() -> void:
	var hub: Node = (load(HUB_SCENE_PATH) as PackedScene).instantiate()
	_assert_unique(hub, "", "the hub")
	hub.free()
	var shell: Node = (load(MATCH_SCENE_PATH) as PackedScene).instantiate()
	var arena: Node = shell.get_node("Arena")
	var prefix: String = String(shell.get_path_to(arena)) + "/"
	shell.free()
	for map: MapDefinition in MapCatalog.all():
		var scene: PackedScene = load(map.scene_path) as PackedScene if not map.scene_path.is_empty() else null
		if not assert_not_null(scene, "%s has a scene" % map.id):
			continue
		var root: Node = scene.instantiate()
		_assert_unique(root, prefix, String(map.id))
		root.free()


func _assert_unique(root: Node, prefix: String, what: String) -> void:
	var seen: Dictionary[int, String] = {}
	var props: int = 0
	for node: Node in root.find_children("*", "", true, false):
		if not node.has_method(&"net_record"):
			continue
		props += 1
		var path: String = prefix + String(root.get_path_to(node))
		var id: int = NetProp.id_of(NodePath(path))
		assert_false(seen.has(id), "%s: %s and %s share id %d" % [what, seen.get(id, ""), path, id])
		seen[id] = path
	print("PROOF prop ids: %s has %d props, all distinct" % [what, props])
