class_name NetWires
extends RefCounted

## The conditioned sockets of an in-process rig: which machines' sends go through a [LossyPeer], and
## a freeze of one machine. One per rig; every rig conditions its wires through this.

var _wires: Dictionary[NetSession, LossyPeer] = {}


## Put [param session]'s sends through [param conditions] (clean when null). Call before the socket
## has a peer: swapped in under a live connection, the engine forgets who it is connected to.
func wrap(session: NetSession, conditions: NetConditions = null) -> LossyPeer:
	var wire: LossyPeer = _wires.get(session)
	if wire == null:
		wire = LossyPeer.new(session.multiplayer.multiplayer_peer)
		session.multiplayer.multiplayer_peer = wire
		_wires[session] = wire
	if conditions != null:
		wire.conditions = conditions
	return wire


## [param session]'s wire, or null when it is on the bare socket.
func of(session: NetSession) -> LossyPeer:
	return _wires.get(session)


func clear() -> void:
	_wires.clear()


## Stop [param session]'s machine for [param ms] real milliseconds: its socket goes unserviced and its
## scripts stop. Its physics server is shared with the process and keeps stepping (the multi-process
## harness freezes a whole process). Needs a wire; resolves when the machine runs again.
func freeze(session: NetSession, ms: float) -> void:
	var wire: LossyPeer = of(session)
	if wire == null:
		push_error("NetWires.freeze: %s has no wire; wrap it before it connects" % session.get_path())
		return
	var branch: Node = session.get_parent()
	var mode: Node.ProcessMode = branch.process_mode
	wire.freeze(ms)
	branch.process_mode = Node.PROCESS_MODE_DISABLED
	while wire.is_frozen():
		await session.get_tree().process_frame
	branch.process_mode = mode
