class_name NetProp
extends RefCounted

## A scene prop whose state rides the snapshot (DESIGN 3.4): it calls [method register] from its _ready,
## answers [code]net_record(tick)[/code] on the host and [code]net_apply(record, tick)[/code] at a client's playout clock.


## [param path]'s u16 id: FNV-1a of a prop's path relative to its scene root, the same on every machine.
static func id_of(path: NodePath) -> int:
	var hash: int = 0x811C9DC5
	for byte: int in String(path).to_utf8_buffer():
		hash = ((hash ^ byte) * 0x01000193) & 0xFFFFFFFF
	return (hash >> 16) ^ (hash & 0xFFFF)


## Register [param prop] with the [NetMatch] of the scene it stands in, once, from its first ready.
## Returns that NetMatch, or null in a scene that has none (a test world, a bot harness).
static func register(prop: Node) -> NetMatch:
	var net: NetMatch = NetMatch.of_scene(prop)
	if net != null:
		net.register_prop(prop)
	return net


## True on the machine that decides a prop: the host, or a game with no session. A session that has
## just closed leaves no peer at all, and nobody decides for it.
static func is_authority(prop: Node) -> bool:
	return prop.multiplayer.multiplayer_peer != null and prop.multiplayer.is_server()


## A host tick sent as its low 16 bits, back to the tick nearest [param near] (DESIGN 2 wrap rules).
static func nearest_tick(low: int, near: int) -> int:
	var delta: int = (low - near) & 0xFFFF
	return near + (delta - 0x10000 if delta >= 0x8000 else delta)
