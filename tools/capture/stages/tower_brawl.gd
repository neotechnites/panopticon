extends "res://tools/capture/stages/stage.gd"

## tower_brawl: the match's opening tower brawl (MatchController.start_brawl, rules.open_with_tower_brawl), as the game runs it.
## Ryan (short 9, L6): "everyone starts in the tower, and the way you get to be the sniper, is to be the last one standing in it"
## {Shot of starting shove tower minigame in hell}.
##
## [code]--shot=s3_open_lane --stage=tower_brawl --bots=3 --shimmer=0 --look=social --seed=20261017[/code]: four players, all in
## the tower room, only the shove; the game's own brawl bots shove each other out of the windows; the last one standing takes the
## seat and the round starts with him as the sniper. Run_clip arms a round straight after start_match (a stage is driven), so the
## first tick calls start_brawl() again: the same call the match's opening makes; the fight is the game's own.
##
## The numbers (headless probe, hell): room floor y 26.98, brawl floor r 6.57, ceiling 32.6 (5.3 m up), piers at 0/90/180/270
## deg 6.9 m out, open windows between. The lens hangs inside the room under the ceiling against the cam_deg pier, looking down
## across the floor at the standing bodies (portrait: the frame's height is the room's depth); after the win it rides the seat
## holder from the same pier and closes in on him (fov 72 to zoom_fov over zoom_s) as he takes the window, the sniper now. Smoke 20261017: outs 2.75, 6.37, 7.28; Runner_2 seated 8.80.
##
## Dials (--set=): cam_deg (0.0, the pier the lens hangs on), cam_r (5.2), cam_h (4.3, over the floor), fov (72.0),
## follow (0.55, share of the look on the bodies, the rest on the room's middle), rate (3.0, look easing per s),
## drift (0.03 m, handheld), zoom_fov (40.0), zoom_s (2.5), orbit (6.0 deg/s round the room once he is seated; a held lens froze 1.1 s).
## --pov=runner (Ryan on n1: "why is the last shot not from the perspective of a player?"): ride (2, roster index) is a brawler on the
## game's own brawl brain (until it joins, his hand turns him onto watch, 1), shoved and shoving; won, he looks out after the last man
## thrown; seated, a hand scopes the runners (park_deg 25) and drops one (fire_at 3.5 s after the seat).

const GUARD_HAND := preload("res://tools/capture/stages/guard_hand.gd")

var _started: bool = false
var _pos: Vector3 = Vector3.ZERO
var _look: Vector3 = Vector3.ZERO
var _placed: bool = false
var _won: bool = false
var _seated_at: float = -1.0
var _ride: MatchParticipant = null
var _last_out: Vector3 = Vector3.ZERO
var _after: Node = null
var _hand: Node = null
var _sat: bool = false
var _won_at: float = -1.0
var _grace: Node = null
var _joins_at: float = 0.0


func bots() -> int:
	return 3


func tune_rules(rules: MatchRules) -> void:
	rules.map_id = &"bentham_ring"
	rules.open_with_tower_brawl = true
	rules.open_with_race = false


## The shipped tower brain once he is seated: the winner shoots as the game's bot would.
func tune_shooter(_profile: ShooterProfile) -> void:
	pass


func tick(_delta: float) -> void:
	if _grace != null and elapsed() >= _joins_at:
		_grace.release()
		_grace.queue_free()
		_grace = null
		_ride.brain.input.command.clear()
	if _after != null and elapsed() >= _won_at + MatchController.BRAWL_END_SECONDS - 0.1:
		# The game seats a bot body only on its own input: handed back, its last brawl command dropped.
		_after.release()
		_after.queue_free()
		_after = null
		_ride.brain.input.command.clear()
	if _sat and _hand == null:
		_scope_the_runners()
	elif _hand != null:
		LIB.stand_down(seat())   # the round's start wakes the tower brain again: the hand keeps the rifle
		if OS.has_environment("STAGE_DEBUG") and Engine.get_physics_frames() % 30 == 0:
			var eye: Camera3D = clip.root.get_viewport().get_camera_3d()
			var seen: String = ""
			for p: MatchParticipant in controller().get_participants():
				if p != _ride and p.body != null and eye.is_position_in_frustum(p.body.global_position + Vector3.UP):
					seen += " %s %.0f deg" % [p.body.name, LIB.bearing_of(p.body.global_position)]
			say("scope fov %.0f on:%s" % [eye.fov, seen])
	if _started:
		return
	_started = true
	var match_controller: MatchController = controller()
	match_controller.brawl_started.connect(func() -> void: print("[event] %6.2f  brawl_start" % elapsed()))
	match_controller.brawler_out.connect(
		func(p: MatchParticipant, _throw: Vector3) -> void:
			print("[event] %6.2f  brawl_out  %s" % [elapsed(), p.body.name])
			_last_out = p.body.global_position
			_report_win()
	)
	match_controller.seat_changed.connect(func(p: MatchParticipant, _turns: int) -> void: _sat = _ride != null and p == _ride)
	match_controller.start_brawl()
	if String(clip._options.get("pov", "")) == "runner":
		var roster: Array[MatchParticipant] = match_controller.get_participants()
		_ride = roster[clampi(int(option("ride", 2)), 0, roster.size() - 1)]
		stage_body(_ride.body)
		# Until the game's brawl brain joins him in, a hand turns him round onto the first fight instead of a held stare at the wall.
		_joins_at = elapsed() + MatchController.BRAWL_GRACE_SECONDS + MatchController.BRAWL_BOT_STAGGER_SECONDS * float(_ride.index) - 0.05
		var watched: MatchParticipant = roster[clampi(int(option("watch", 1)), 0, roster.size() - 1)]
		_grace = drive(_ride.brain, [{"do": "steer", "on": true, "rate": 240.0, "gain": 6.0}, {"do": "human", "on": true},
			{"do": "hold", "seconds": float(option("turn_at", 0.3))}, {"do": "watch", "body": watched.body, "seconds": 30.0, "height": 1.2}], int(_ride.index), "BrawlGraceEyes")
	say("tower_brawl: %d in the room, floor y %.2f r %.2f" % [match_controller.get_participants().size(), match_controller._brawl_floor_y, match_controller._brawl_floor_radius])


func _report_win() -> void:
	var standing: Array = _standing()
	if standing.size() == 1 and not _won:
		_won = true
		print("[event] %6.2f  brawl_won  %s" % [elapsed(), (standing[0] as MatchParticipant).body.name])
		if standing[0] == _ride:
			_eyes_out()


## Won: the POV's own hand turns him out the window and down after the last man thrown, until the seat takes him.
func _eyes_out() -> void:
	var at: Vector3 = _ride.body.global_position
	var away: Vector3 = Vector3(_last_out.x - at.x, 0.0, _last_out.z - at.z)
	away = away.normalized() if away.length() > 0.2 else -_ride.body.global_transform.basis.z
	var below: Vector3 = at + away * 7.0 + Vector3.DOWN * 5.0
	_won_at = elapsed()
	var steps: Array = [{"do": "steer", "on": true, "rate": 240.0, "gain": 6.0}, {"do": "human", "on": true},
		{"do": "hold", "seconds": 0.7, "look_at": below}, {"do": "steer", "on": true, "rate": 40.0, "gain": 3.0}]
	# Then a slow pan round the emptied room until the seat takes him: a held stare froze 0.77 s on the PC take.
	for i: int in range(1, 40):
		steps.append({"do": "hold", "seconds": 0.3, "look_at": at + away.rotated(Vector3.UP, deg_to_rad(12.0 * i)) * 7.0 + Vector3.DOWN * 2.0})
	_after = drive(_ride.brain as RunnerBrain, steps, int(_ride.index), "BrawlWinnerEyes")


## Seated: the brain stands down and a hand scopes the runners below (the run_clip scope paints for a guard POV).
func _scope_the_runners() -> void:
	var shooter: TowerShooter = LIB.stand_down(seat())
	if shooter == null or shooter.controller != _ride.body:
		return
	var pool: Array = []
	for p: MatchParticipant in controller().get_participants():
		if p != _ride and p.body != null:
			pool.append(p.body)
	# He takes the opening a guard aims from (seat_deg, seat_r out): a clear line over the lake, no pier in the scope.
	LIB.guard_to_window(_ride.body, float(option("seat_deg", 25.0)), float(option("seat_r", 6.2)))
	_hand = GUARD_HAND.new()
	_hand.name = "BrawlWinnerHand"
	clip.root.add_child(_hand)
	_hand.install(_ride.body, controller(), elapsed())
	_hand.start_at = elapsed()
	_hand.park = LIB.ring_point(float(option("park_deg", 25.0)), 52.0, 1.0)
	_hand.beats.append({"from": pool, "seconds": 120.0, "fire_at": float(option("fire_at", 3.5)), "clear": true, "watch": true, "hold": true})
	clip._pov = "guard"
	say("tower_brawl: %s seated, hand on %d runners" % [_ride.body.name, pool.size()])


func _standing() -> Array:
	var out: Array = []
	for p: MatchParticipant in controller().get_participants():
		if p.is_running and p.body != null and controller().get_phase() == MatchController.Phase.BRAWL:
			out.append(p)
	return out


func _seated() -> PlayerController:
	for p: MatchParticipant in controller().get_participants():
		if p.is_shooter and p.body != null:
			return p.body
	return null


func lens(delta: float) -> bool:
	var cam: Camera3D = camera()
	var match_controller: MatchController = controller()
	if cam == null or not _started:
		return false
	var centre: Vector3 = match_controller._tower_point
	var floor_y: float = match_controller._brawl_floor_y
	var deg: float = float(option("cam_deg", 0.0))
	if _seated_at >= 0.0:
		# Seated: the lens walks round the room on its radius (orbit deg/s), so a still sniper is never a frozen frame.
		deg += float(option("orbit", 6.0)) * (elapsed() - _seated_at)
	var t: float = elapsed()
	var drift: float = float(option("drift", 0.03))
	var sway: Vector3 = Vector3(sin(t * 0.83) + 0.4 * sin(t * 2.1), 0.6 * sin(t * 1.31), cos(t * 0.71)) * drift
	var want_pos: Vector3 = Vector3(cos(deg_to_rad(deg)), 0.0, sin(deg_to_rad(deg))) * float(option("cam_r", 5.2))
	want_pos = Vector3(centre.x + want_pos.x, floor_y + float(option("cam_h", 4.3)), centre.z + want_pos.z) + sway
	var middle: Vector3 = Vector3(centre.x, floor_y + 0.8, centre.z)
	var want_look: Vector3 = middle
	var bodies: Array = []
	if match_controller.get_phase() == MatchController.Phase.BRAWL:
		for p: MatchParticipant in _standing():
			bodies.append(p.body.global_position + Vector3.UP * 0.9)
	else:
		var guard: PlayerController = _seated()
		if guard != null:
			# Seated: the lens stays on its pier and closes in on him (fov to zoom_fov over zoom_s) as he takes the window.
			if _seated_at < 0.0:
				_seated_at = t
			bodies.append(guard.head.global_position)
	if not bodies.is_empty():
		var mean: Vector3 = Vector3.ZERO
		for b: Vector3 in bodies:
			mean += b
		mean /= float(bodies.size())
		# The last one standing is the shot: the look goes all the way onto him (and onto the seat holder after).
		var share: float = float(option("follow", 0.55)) if match_controller.get_phase() == MatchController.Phase.BRAWL and bodies.size() > 1 else 1.0
		want_look = middle.lerp(mean, share)
	if not _placed:
		_placed = true
		_pos = want_pos
		_look = want_look
	_pos = want_pos
	_look = _look.lerp(want_look, 1.0 - exp(-float(option("rate", 3.0)) * delta))
	cam.global_position = _pos
	cam.look_at(_look, Vector3.UP)
	var wide: float = float(option("fov", 72.0))
	var zoom: float = clampf((t - _seated_at) / float(option("zoom_s", 2.5)), 0.0, 1.0) if _seated_at >= 0.0 else 0.0
	cam.fov = lerpf(wide, float(option("zoom_fov", 40.0)), smoothstep(0.0, 1.0, zoom))
	cam.current = true
	if OS.has_environment("STAGE_DEBUG") and Engine.get_physics_frames() % 30 == 0:
		var line: String = "phase %d look %s" % [match_controller.get_phase(), str(_look.snapped(Vector3.ONE * 0.1))]
		for p: MatchParticipant in match_controller.get_participants():
			if p.body != null:
				var seen: bool = cam.is_position_in_frustum(p.body.global_position + Vector3.UP)
				line += " %s %s%s%s" % [p.body.name, str(p.body.global_position.snapped(Vector3.ONE * 0.1)), " in" if seen else " OUT", " S" if p.is_shooter else ""]
		say(line)
	return true
