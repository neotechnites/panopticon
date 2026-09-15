extends SceneTree

## Headless probe of the ring, for staging a shot by numbers. Runs on the Mac.
##
## [codeblock]
## godot --headless --path . --script res://tools/capture/stages/probe_ring.gd -- --clear
## godot --headless --path . --script res://tools/capture/stages/probe_ring.gd -- --floor --pads
## godot --headless --path . --script res://tools/capture/stages/probe_ring.gd -- --los=195.8:51.8:1;193.4:49.5:1
## godot --headless --path . --script res://tools/capture/stages/probe_ring.gd -- --heights=195,196,197 --radii=47,49,51,53,55
## godot --headless --path . --script res://tools/capture/stages/probe_ring.gd -- --aabb
## [/codeblock]
##
## --clear   the pad- and trap-free stretches of deck: every bearing whose
##           walkable band (r 47.5-56.5) holds no boost pad or trap footprint,
##           printed as runs. Where a melee, a pack or a conga can play without
##           anything launching or killing a body (Ryan on the first melee:
##           "around the demon pad which is messing them up").
## --floor   a map of the ring's floor by raycast, one character per cell,
##           2 deg by 0.5 m from r 44 to 60: '.' deck at y 23, '#' something
##           taller, '_' lower, ' ' nothing.
## --pads    every Area3D and every node with pad/trap/kill/powerup/portal in its
##           name, in ring coordinates, with its footprint.
## --los     for each deg:r:h, whether the tower's eye sees it, and what blocks it.
## --heights the floor height under each bearing in --heights at each radius in --radii.
## --aabb    every mesh's bounding box in ring coordinates (rocks, cover).
##
## Every number a stage file quotes (a rock's shadow, a pad's edge, a lane's
## width) came off one of these.

const RING_SCENE: String = "res://scenes/ring/bentham_ring.tscn"
const DECK_Y: float = 23.0
const LANE_BAND := Vector2(47.5, 56.5)
const CLEAR_MARGIN: float = 0.5

var _frames: int = 0
var _opts: Dictionary = {}
var _ring: Node = null


func _initialize() -> void:
	_opts = BotHarness.parse_arguments({
		"clear": false, "floor": false, "pads": false, "aabb": false,
		"los": "", "heights": "", "radii": "47,49,51,53,55",
	})


func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 1:
		_ring = (load(RING_SCENE) as PackedScene).instantiate()
		root.add_child(_ring)
		return false
	if _frames < 6:
		return false
	if bool(_opts.get("_error", false)):
		quit(2)
		return true
	var asked: bool = false
	if bool(_opts["floor"]):
		_floor_map()
		asked = true
	if bool(_opts["pads"]):
		_pads()
		asked = true
	if bool(_opts["clear"]):
		_clear()
		asked = true
	if String(_opts["los"]) != "":
		_los()
		asked = true
	if String(_opts["heights"]) != "":
		_heights()
		asked = true
	if bool(_opts["aabb"]):
		_aabbs()
		asked = true
	if not asked:
		_clear()
		_pads()
	quit(0)
	return true


func _space() -> PhysicsDirectSpaceState3D:
	return root.get_world_3d().direct_space_state


func _eye() -> Vector3:
	var spawn: Node3D = _find(_ring, "TowerSpawn") as Node3D
	return spawn.global_position + Vector3.UP * 1.6 if spawn != null else Vector3(0.0, 27.0, 0.0)


# --- Footprints ----------------------------------------------------------------

## Every launcher and killer on the ring, as {name, kind, deg, r, aabb}.
func _hazards() -> Array:
	var out: Array = []
	for node: Node in _walk(_ring):
		var spatial: Node3D = node as Node3D
		if spatial == null:
			continue
		var lower: String = node.name.to_lower()
		var is_pad: bool = node is BoostPad or lower.contains("pad")
		var is_trap: bool = node is TrapVolume or lower.contains("trap") or lower.contains("kill")
		if not (is_pad or is_trap):
			continue
		var box: AABB = _footprint(spatial)
		var p: Vector3 = spatial.global_position
		out.append({
			"name": String(node.get_path()), "kind": "pad" if is_pad else "trap",
			"deg": _bearing(p), "r": Vector2(p.x, p.z).length(), "aabb": box,
		})
	return out


## The world-space box of a node's collision shapes (or its own position, 1 m).
func _footprint(spatial: Node3D) -> AABB:
	var box := AABB(spatial.global_position - Vector3(0.5, 0.5, 0.5), Vector3(1.0, 1.0, 1.0))
	var found: bool = false
	for node: Node in _walk(spatial):
		var shape_node: CollisionShape3D = node as CollisionShape3D
		if shape_node == null or shape_node.shape == null:
			continue
		var local: AABB = shape_node.shape.get_debug_mesh().get_aabb()
		var world: AABB = shape_node.global_transform * local
		box = world if not found else box.merge(world)
		found = true
	return box


func _pads() -> void:
	print("hazards (bearing, radius, footprint in ring coordinates):")
	for h: Dictionary in _hazards():
		var box: AABB = h["aabb"]
		var corners: Array = [box.position, box.end, Vector3(box.position.x, 0.0, box.end.z), Vector3(box.end.x, 0.0, box.position.z)]
		var deg_lo: float = 999.0
		var deg_hi: float = -999.0
		var r_lo: float = 999.0
		var r_hi: float = 0.0
		for c: Vector3 in corners:
			var d: float = _bearing(c)
			var span: float = fposmod(d - float(h["deg"]) + 180.0, 360.0) - 180.0
			deg_lo = minf(deg_lo, float(h["deg"]) + span)
			deg_hi = maxf(deg_hi, float(h["deg"]) + span)
			r_lo = minf(r_lo, Vector2(c.x, c.z).length())
			r_hi = maxf(r_hi, Vector2(c.x, c.z).length())
		print("  %-5s %6.1f deg r %5.1f  spans %6.1f-%6.1f deg, r %5.1f-%5.1f, y %5.1f-%5.1f  %s" % [
			h["kind"], h["deg"], h["r"], deg_lo, deg_hi, r_lo, r_hi, box.position.y, box.end.y, h["name"],
		])


## Bearings whose whole walkable band is clear of every hazard footprint.
func _clear() -> void:
	var hazards: Array = _hazards()
	var clear: Array = []
	for step: int in 360:
		var deg: float = float(step)
		var blocked: bool = false
		var r: float = LANE_BAND.x
		while r <= LANE_BAND.y and not blocked:
			var p: Vector3 = Vector3(cos(deg_to_rad(deg)) * r, DECK_Y + 0.5, sin(deg_to_rad(deg)) * r)
			for h: Dictionary in hazards:
				var box: AABB = (h["aabb"] as AABB).grow(CLEAR_MARGIN)
				if box.position.y > DECK_Y + 4.0 or box.end.y < DECK_Y - 4.0:
					continue
				# Flat containment: a trap sits a few cm under the deck, a pad on it.
				if p.x >= box.position.x and p.x <= box.end.x and p.z >= box.position.z and p.z <= box.end.z:
					blocked = true
					break
			r += 0.5
		clear.append(not blocked)
	print("clear deck (no pad or trap footprint across r %.1f-%.1f, %.1f m margin):" % [LANE_BAND.x, LANE_BAND.y, CLEAR_MARGIN])
	var start: int = -1
	for step: int in 361:
		var ok: bool = clear[step % 360]
		if ok and start < 0:
			start = step
		elif not ok and start >= 0:
			if step - start >= 4:
				print("  %3d-%3d deg  (%d deg)" % [start, step - 1, step - start])
			start = -1
	print("(a stretch under 4 deg is not listed; check --pads for what breaks it)")


# --- The floor ------------------------------------------------------------------

func _floor_map() -> void:
	var space: PhysicsDirectSpaceState3D = _space()
	var radii: Array[float] = []
	var r: float = 44.0
	while r <= 60.01:
		radii.append(r)
		r += 0.5
	print("deg  r44" + " ".repeat(radii.size() - 4) + "r60")
	var deg: float = 0.0
	while deg < 360.0:
		var line: String = "%5.1f " % deg
		for rr: float in radii:
			var a: float = deg_to_rad(deg)
			var from: Vector3 = Vector3(cos(a) * rr, 30.0, sin(a) * rr)
			var query := PhysicsRayQueryParameters3D.create(from, from + Vector3(0.0, -12.0, 0.0))
			var hit: Dictionary = space.intersect_ray(query)
			if hit.is_empty():
				line += " "
			elif float(hit["position"].y) > DECK_Y + 0.3:
				line += "#"
			elif float(hit["position"].y) < DECK_Y - 0.3:
				line += "_"
			else:
				line += "."
		print(line)
		deg += 2.0


func _heights() -> void:
	var space: PhysicsDirectSpaceState3D = _space()
	for a_s: String in String(_opts["heights"]).split(",", false):
		var a: float = float(a_s)
		var line: String = "deg %6.1f:" % a
		for r_s: String in String(_opts["radii"]).split(",", false):
			var r: float = float(r_s)
			var top := Vector3(cos(deg_to_rad(a)) * r, DECK_Y + 8.3, sin(deg_to_rad(a)) * r)
			var q := PhysicsRayQueryParameters3D.create(top, top + Vector3(0.0, -30.0, 0.0))
			q.collision_mask = 0xFFFFFFFF
			var hit: Dictionary = space.intersect_ray(q)
			var y: float = float(hit.get("position", Vector3(0.0, -99.0, 0.0)).y)
			line += "  r%4.1f=%+5.2f" % [r, y - DECK_Y]
		print(line)


# --- Line of sight ----------------------------------------------------------------

func _los() -> void:
	var space: PhysicsDirectSpaceState3D = _space()
	var eye: Vector3 = _eye()
	print("tower eye at %v" % eye)
	for spec: String in String(_opts["los"]).split(";", false):
		var p: PackedStringArray = spec.split(":")
		if p.size() < 2:
			continue
		var a: float = float(p[0])
		var r: float = float(p[1])
		var h: float = float(p[2]) if p.size() > 2 else 1.0
		var at := Vector3(cos(deg_to_rad(a)) * r, DECK_Y + h, sin(deg_to_rad(a)) * r)
		var q := PhysicsRayQueryParameters3D.create(eye, at)
		q.collision_mask = 0xFFFFFFFF
		var hit: Dictionary = space.intersect_ray(q)
		var blocked: bool = not hit.is_empty() and (hit["position"] as Vector3).distance_to(at) > 0.3
		var by: String = ""
		if blocked:
			by = " by %s at %v" % [(hit["collider"] as Node).name, hit["position"]]
		print("  %s: %s%s" % [spec, "BLOCKED" if blocked else "open", by])


func _aabbs() -> void:
	for node: Node in _walk(_ring):
		var mesh: MeshInstance3D = node as MeshInstance3D
		if mesh == null:
			continue
		var box: AABB = mesh.global_transform * mesh.get_aabb()
		if box.size.x > 30.0 or box.size.z > 30.0:
			continue
		var c: Vector3 = box.get_center()
		print("mesh %-44s %6.1f deg r %5.1f  y %5.2f..%5.2f  size %v" % [
			node.get_path(), _bearing(c), Vector2(c.x, c.z).length(), box.position.y, box.end.y, box.size,
		])


# --- Helpers ------------------------------------------------------------------------

static func _bearing(p: Vector3) -> float:
	return fposmod(rad_to_deg(atan2(p.z, p.x)), 360.0)


static func _walk(from: Node) -> Array[Node]:
	var out: Array[Node] = []
	var pending: Array[Node] = [from]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		out.append(node)
		for child: Node in node.get_children():
			pending.append(child)
	return out


static func _find(from: Node, wanted: String) -> Node:
	for node: Node in _walk(from):
		if node.name == wanted:
			return node
	return null
