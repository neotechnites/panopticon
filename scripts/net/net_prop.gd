class_name NetProp
extends RefCounted

## A scene prop whose state rides the snapshot (DESIGN 3.4): it joins [constant GROUP], answers
## [code]net_record()[/code] on the host and [code]net_apply(record)[/code] at a client's playout clock.

const GROUP: StringName = &"net_props"


## [param prop]'s u16 id: FNV-1a of its scene file and path in it, the same on every machine.
static func id_of(prop: Node) -> int:
	var root: Node = prop.owner if prop.owner != null else prop.get_parent()
	var key: String = "%s:%s" % [root.scene_file_path if root != null else "", root.get_path_to(prop) if root != null else prop.name]
	var hash: int = 0x811C9DC5
	for byte: int in key.to_utf8_buffer():
		hash = ((hash ^ byte) * 0x01000193) & 0xFFFFFFFF
	return (hash >> 16) ^ (hash & 0xFFFF)
