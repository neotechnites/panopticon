extends RefCounted

## What every stage reaches for: ring-polar geometry, the tower's dials, pads
## and traps, the guard's watch, the HUD's crosshair. Static, stateless.

const DECK_Y: float = 23.0


# --- Geometry: the ring's own polar coordinates -------------------------------
## x = cos(deg) * r, z = sin(deg) * r; heights are metres over the deck.

static func ring_point(degrees: float, radius: float, height: float = 0.0) -> Vector3:
	var angle: float = deg_to_rad(degrees)
	return Vector3(cos(angle) * radius, DECK_Y + height, sin(angle) * radius)


## Along the ring, bearing rising.
static func tangent_at(degrees: float) -> Vector3:
	var angle: float = deg_to_rad(degrees)
	return Vector3(-sin(angle), 0.0, cos(angle))


## Outward from the arena's axis.
static func radial_at(degrees: float) -> Vector3:
	var angle: float = deg_to_rad(degrees)
	return Vector3(cos(angle), 0.0, sin(angle))


static func bearing_of(point: Vector3) -> float:
	return fposmod(rad_to_deg(atan2(point.z, point.x)), 360.0)


static func radius_of(point: Vector3) -> float:
	return Vector2(point.x, point.z).length()


## "deg,r" or "deg,r,h" from a command line, as a point.
static func polar(spec: String, fallback: Vector3) -> Vector3:
	var parts: PackedStringArray = spec.split(",")
	if parts.size() < 2:
		return fallback
	return ring_point(float(parts[0]), float(parts[1]), float(parts[2]) if parts.size() > 2 else 0.0)


## The flat direction from [param from] to [param to].
static func toward(from: Vector3, to: Vector3) -> Vector3:
	var flat: Vector3 = Vector3(to.x - from.x, 0.0, to.z - from.z)
	return flat.normalized() if flat.length_squared() > 0.0001 else Vector3.FORWARD


# --- The tower ----------------------------------------------------------------

## A tower that watches and never fires.
static func dead_shooter(profile: ShooterProfile) -> void:
	profile.shot_confidence_threshold = 1.0
	profile.sure_shot_confidence = 1.0


## The shipped brain with its patience removed: quick, and accurate.
static func quick_shooter(profile: ShooterProfile) -> void:
	profile.scan_yaw_rate = 2.4
	profile.reaction_seconds = 0.08
	profile.shot_confidence_threshold = 0.15
	profile.aim_error_degrees = 0.3
	profile.confident_range = 120.0
	profile.decoy_suspicion_seconds = 0.0


## The one-shot-one-kill guard of the cover shot: no aim error, no lead error,
## a lens that turns as fast as a thrown body, and a shot only once the aim is
## on them. Ryan: "the sniper should not miss the first shot".
static func dead_eye_shooter(profile: ShooterProfile) -> void:
	profile.scan_yaw_rate = 2.4
	profile.reaction_seconds = 0.03
	profile.reaction_floor_seconds = 0.0
	profile.reaction_spread = 0.0
	profile.aim_tolerance_degrees = 0.5
	profile.max_comfortable_track_rate = 10.0
	profile.aim_error_degrees = 0.0
	profile.lead_error_seconds = 0.0
	profile.velocity_read_seconds = 0.05
	profile.tracking_omega = 30.0
	profile.max_yaw_rate = 30.0
	profile.max_pitch_rate = 30.0
	profile.confident_range = 120.0
	profile.decoy_suspicion_seconds = 0.0
	profile.shot_confidence_threshold = 1.0
	profile.sure_shot_confidence = 1.0


## Lock (1.0) or unlock the seated brain's trigger. False when nobody holds the rifle yet.
static func set_trigger(seat: BotTowerSeat, threshold: float) -> bool:
	var shooter: TowerShooter = seat.get_active_shooter() if seat != null else null
	if shooter == null or shooter.profile == null:
		return false
	shooter.profile.shot_confidence_threshold = threshold
	shooter.profile.sure_shot_confidence = threshold if threshold >= 1.0 else 0.0
	return true


## Stand the tower's brain down: the rifle stays where it is, for a hand to take.
static func stand_down(seat: BotTowerSeat) -> TowerShooter:
	var shooter: TowerShooter = seat.get_active_shooter() if seat != null else null
	if shooter != null:
		shooter.set_physics_process(false)
	return shooter


## The only place the guard looks first. [param only] drops the ring's own
## watch points, or the dwell on them is where the rifle is when the beat lands.
static func watch(root: Node, degrees: float, radius: float, only: bool = false) -> void:
	if only:
		for node: Node in root.get_tree().get_nodes_in_group(TowerShooter.WATCH_GROUP):
			node.remove_from_group(TowerShooter.WATCH_GROUP)
	var marker := Marker3D.new()
	marker.name = "ClipWatch%d" % int(degrees)
	marker.add_to_group(TowerShooter.WATCH_GROUP)
	root.add_child(marker)
	# First in tree order is first on the guard's scan.
	root.move_child(marker, 0)
	marker.global_position = ring_point(degrees, radius, 1.0)


## Take one body out of the rifle's target group for the clip (a shover with
## no cover to hide in behind the lens).
static func hide_from_the_rifle(body: PlayerController) -> void:
	body.remove_from_group(MatchController.RUNNER_GROUP)


# --- Pads and traps -----------------------------------------------------------

## Every boost pad on the ring switched off: a thrown body flying over one is
## launched again. Returns how many.
static func disarm_pads(root: Node) -> int:
	var count: int = 0
	for node: Node in _walk(root):
		if node is BoostPad:
			(node as Area3D).monitoring = false
			count += 1
	return count


## Every trap (lava, kill volumes) switched off, or only those under [param section].
static func disarm_traps(root: Node, section: NodePath = NodePath(), only: String = "") -> int:
	var count: int = 0
	var from: Node = root
	if not section.is_empty():
		from = root.get_node_or_null(section)
		if from == null:
			return 0
	for node: Node in _walk(from):
		if node is TrapVolume and (only.is_empty() or node.name == only):
			(node as Area3D).monitoring = false
			count += 1
	return count


static func _walk(from: Node) -> Array[Node]:
	var out: Array[Node] = []
	var pending: Array[Node] = [from]
	while not pending.is_empty():
		var node: Node = pending.pop_back()
		out.append(node)
		for child: Node in node.get_children():
			pending.append(child)
	return out


static func find_node(from: Node, wanted: String) -> Node:
	for node: Node in _walk(from):
		if node.name == wanted:
			return node
	return null


static func find_kind(from: Node, wanted: String) -> Node:
	for node: Node in _walk(from):
		if node.is_class(wanted):
			return node
		var script: Script = node.get_script() as Script
		if script != null and String(script.get_global_name()) == wanted:
			return node
	return null


# --- The HUD ------------------------------------------------------------------

## The HUD back on with nothing in it but the crosshair. Ryan: "i know i said
## no hud, but there should be a crosshair" -- on the guard POV only.
static func show_only_the_crosshair(root: Node) -> bool:
	var hud: CanvasLayer = find_node(root, "HUD") as CanvasLayer
	if hud == null:
		return false
	var hud_root: Control = hud.get_node_or_null(^"Root") as Control
	if hud_root == null:
		return false
	for child: Node in hud_root.get_children():
		var control: CanvasItem = child as CanvasItem
		if control != null:
			control.visible = child.name == "Crosshair"
	hud_root.visible = true
	hud.visible = true
	return true


## The guard's scope opened past a tall frame's width: the shipped clear centre
## is a circle sized for a 16:9 window and leaves a small disc on black at 9:16.
static func open_the_scope(guard: PlayerController, clear_fraction: float = 0.74) -> void:
	var optic: WeaponOptic = guard.get_node_or_null(^"Optic") as WeaponOptic
	if optic == null or optic.profile == null:
		return
	var copy: ZoomProfile = optic.profile.duplicate() as ZoomProfile
	copy.vignette_clear_fraction = clear_fraction
	optic.profile = copy


## Which participant a body is.
static func participant_of(match_controller: MatchController, body: PlayerController) -> MatchParticipant:
	return match_controller.resolve_participant(body) if body != null else null


## A body is on the deck (not buried under it, not fallen into the pit).
static func on_deck(body: Node3D) -> bool:
	return absf(body.global_position.y - DECK_Y) <= 6.0
