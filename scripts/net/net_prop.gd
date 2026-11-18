class_name NetProp
extends RefCounted

## A scene prop whose lasting state rides the snapshot (DESIGN 3.4 PROPS). It joins [constant GROUP]
## at ready and answers [code]net_record() -> PackedByteArray[/code] on the host and
## [code]net_apply(record)[/code] on a client, which takes it when the playout clock reaches it.

const GROUP: StringName = &"net_props"


## [param prop]'s u16 id: FNV-1a of its scene file and its path in it, the same on every machine
## that loaded that scene, whatever else is in the tree.
static func id_of(prop: Node) -> int:
	var root: Node = prop.owner if prop.owner != null else prop.get_parent()
	var key: String = "%s:%s" % [root.scene_file_path if root != null else "", root.get_path_to(prop) if root != null else prop.name]
	var hash: int = 0x811C9DC5
	for byte: int in key.to_utf8_buffer():
		hash = ((hash ^ byte) * 0x01000193) & 0xFFFFFFFF
	return (hash >> 16) ^ (hash & 0xFFFF)
