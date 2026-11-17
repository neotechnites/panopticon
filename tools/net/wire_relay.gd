extends SceneTree

## The test network below the transport, as netem and clumsy sit below the application: a UDP relay
## between each client and the host that puts every datagram, ENet's acks and resends included, through
## [NetConditions]. Started by tools/net/run_session.sh for a scenario with "wire-layer": "socket".
##
##   godot --headless --script res://tools/net/wire_relay.gd -- --config=<wire.json> --log=<relay.log>
##
## wire.json: {"host_port": H, "limit": seconds, "links": [{"port": P, "up": {options}, "down": {options},
## "up_seed": n, "down_seed": n}]}; options as [method NetConditions.from_options] reads them.

const LOOP_USEC: int = 250
const REPORT_MS: int = 5000


class Link extends RefCounted:
	var listen: PacketPeerUDP = PacketPeerUDP.new()
	var upstream: PacketPeerUDP = PacketPeerUDP.new()
	var up: NetConditions = null
	var down: NetConditions = null
	var client_ip: String = ""
	var client_port: int = -1


var _links: Array[Link] = []
var _log: FileAccess = null
var _deadline_ms: int = 0
var _report_ms: int = 0


func _initialize() -> void:
	var config_path: String = ""
	var log_path: String = ""
	for argument: String in OS.get_cmdline_user_args():
		if argument.begins_with("--config="):
			config_path = argument.substr(9)
		elif argument.begins_with("--log="):
			log_path = argument.substr(6)
	if not log_path.is_empty():
		_log = FileAccess.open(log_path, FileAccess.WRITE)
	var config: Variant = JSON.parse_string(FileAccess.get_file_as_string(config_path))
	if not config is Dictionary:
		_line("RELAY fail reason=bad-config path=%s" % config_path)
		quit(2)
		return
	var host_port: int = int(config["host_port"])
	_deadline_ms = Time.get_ticks_msec() + int(float(config.get("limit", 300)) * 1000.0)
	for spec: Dictionary in config["links"]:
		var link: Link = Link.new()
		if link.listen.bind(int(spec["port"]), "127.0.0.1") != OK:
			_line("RELAY fail reason=bind port=%d" % int(spec["port"]))
			quit(2)
			return
		link.upstream.bind(0, "127.0.0.1")
		link.upstream.set_dest_address("127.0.0.1", host_port)
		link.up = NetConditions.from_options(spec["up"], int(spec.get("up_seed", 11)))
		link.down = NetConditions.from_options(spec["down"], int(spec.get("down_seed", 7)))
		_line("RELAY link=%d port=%d up %s | down %s" % [_links.size() + 1, int(spec["port"]), link.up.describe(),
			link.down.describe()])
		_links.append(link)
	_line("RELAY ready links=%d host_port=%d" % [_links.size(), host_port])


## One pass every quarter millisecond: the relay's own clock, not a frame's, decides when a datagram leaves.
func _process(_delta: float) -> bool:
	while Time.get_ticks_msec() < _deadline_ms:
		var now: float = float(Time.get_ticks_usec()) / 1000.0
		for link: Link in _links:
			_carry(link, now)
		if Time.get_ticks_msec() - _report_ms >= REPORT_MS:
			_report_ms = Time.get_ticks_msec()
			_report()
		OS.delay_usec(LOOP_USEC)
	_report()
	_line("RELAY end reason=limit")
	return true


func _carry(link: Link, now: float) -> void:
	while link.listen.get_available_packet_count() > 0:
		var datagram: PackedByteArray = link.listen.get_packet()
		link.client_ip = link.listen.get_packet_ip()
		link.client_port = link.listen.get_packet_port()
		link.up.push(0, false, datagram, now)
	while link.upstream.get_available_packet_count() > 0:
		link.down.push(0, false, link.upstream.get_packet(), now)
	for datagram: PackedByteArray in link.up.pop_due(now):
		link.upstream.put_packet(datagram)
	if link.client_port < 0:
		link.down.pop_due(now)
		return
	link.listen.set_dest_address(link.client_ip, link.client_port)
	for datagram: PackedByteArray in link.down.pop_due(now):
		link.listen.put_packet(datagram)


func _report() -> void:
	for i: int in _links.size():
		for direction: String in ["up", "down"]:
			var stats: Dictionary = (_links[i].up if direction == "up" else _links[i].down).stats()
			_line("RELAY link=%d dir=%s offered=%d lost=%d duplicated=%d held=%d" % [i + 1, direction,
				int(stats.get("offered", 0)), int(stats.get("lost", 0)), int(stats.get("duplicated", 0)),
				int(stats.get("held", 0))])


func _line(text: String) -> void:
	var stamped: String = "NL w=%d %s" % [int(Time.get_unix_time_from_system() * 1000.0), text]
	print(stamped)
	if _log != null:
		_log.store_line(stamped)
		_log.flush()
