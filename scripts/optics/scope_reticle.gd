class_name ScopeReticle
extends Control

## A duplex crosshair drawn over the [ScopeVignette], centred on the shot line, with holdover
## marks placed where [WeaponProjectile] actually lands at each range under this match's drop.

## Sizes are in pixels of a 1080-line screen and scale with the window.
const REFERENCE_HEIGHT: float = 1080.0
## Holdover marks this can show at once; extra distances are ignored.
const MAX_MARKS: int = 8
## Farthest a fine arm may run out from centre, as a fraction of the clear radius.
const ARM_CAP: float = 0.85
## How far the shot line is projected to find the aim point on screen, metres.
const AIM_PROBE_METRES: float = 1000.0

@export_group("Lines")
## Width of the fine cross, the holdover marks and the windage ticks.
@export_range(0.5, 8.0, 0.25) var line_thickness: float = 2.0
## Width of the thick outer posts.
@export_range(1.0, 24.0, 0.5) var post_thickness: float = 8.0
## Main line colour: dark, so it reads on marble and ice.
@export var line_color: Color = Color(0.04, 0.04, 0.05, 1.0)
## Edge drawn around every line: light, so it reads on hell.
@export var edge_color: Color = Color(0.93, 0.9, 0.78, 0.9)
## Width of that edge on each side.
@export_range(0.0, 4.0, 0.25) var edge_thickness: float = 1.25
## Radius of the open centre around the aim point.
@export_range(0.0, 40.0, 0.5) var gap: float = 7.0
## Where the posts end and the fine cross begins, as a fraction of the clear radius.
@export_range(0.1, 0.9, 0.01) var post_start: float = 0.5
## Length of the taper from post to fine line.
@export_range(0.0, 60.0, 1.0) var taper_length: float = 14.0

@export_group("Holdover")
## Draw drop marks down the lower arm. None are drawn when the round does not fall.
@export var holdover_marks: bool = true
## Target distances in metres, ascending, one mark each.
@export var mark_distances: PackedFloat32Array = PackedFloat32Array([25.0, 50.0, 75.0, 100.0, 125.0, 150.0, 200.0, 250.0])
## Half-width of a short mark; long marks are twice this.
@export_range(2.0, 40.0, 0.5) var mark_half_width: float = 8.0
## Distances that are a multiple of this get a long, labelled mark.
@export_range(1.0, 500.0, 1.0) var long_mark_every: float = 50.0
## Draw the distance beside each long mark.
@export var mark_labels: bool = true
## Label font size.
@export_range(6, 40, 1) var label_size: int = 14
## Draw lead ticks for a prisoner crossing at full run on the horizontal arms.
@export var windage_ticks: bool = true

## The Ads beside the vignette; the rifle and its holder are read through it.
var ads: RifleAds = null

var _centre: Vector2 = Vector2.ZERO
var _marks: PackedVector2Array = PackedVector2Array()
var _mark_index: PackedInt32Array = PackedInt32Array()
var _mark_count: int = 0
var _crossings: PackedVector3Array = PackedVector3Array()
var _lead: float = 0.0
var _unit: float = 1.0
var _clear_radius: float = 0.0
var _outer_radius: float = 0.0
var _labels: PackedStringArray = PackedStringArray()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marks.resize(MAX_MARKS)
	_mark_index.resize(MAX_MARKS)
	_crossings.resize(MAX_MARKS)
	_labels.resize(MAX_MARKS)
	for i: int in range(MAX_MARKS):
		_labels[i] = ""


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	refresh()
	queue_redraw()


# --- Public API ---------------------------------------------------------------

## Recompute the aim point, holdover marks and lead ticks from the rifle and camera.
func refresh() -> void:
	_mark_count = 0
	_lead = 0.0
	var camera: Camera3D = _camera()
	var rifle: Rifle = _rifle()
	var viewport: Viewport = get_viewport()
	if camera == null or viewport == null:
		return
	var height: float = viewport.get_visible_rect().size.y
	_unit = height / REFERENCE_HEIGHT
	_read_radii(height)
	var source: Node3D = camera if rifle == null or rifle.aim_source == null else rifle.aim_source
	var origin: Vector3 = source.global_position
	var aim: Vector3 = -source.global_transform.basis.z.normalized()
	_centre = _to_local(camera.unproject_position(origin + aim * AIM_PROBE_METRES))
	if rifle == null or rifle.profile == null:
		return
	var charge: float = rifle.get_charge()
	var speed: float = rifle.get_shot_speed(charge)
	if speed <= 0.0:
		return
	if windage_ticks:
		_lead = _lead_pixels(camera, origin, aim, speed, source)
	var gravity: float = rifle.profile.projectile_gravity
	if not holdover_marks or gravity <= 0.0:
		return
	var count: int = mini(mark_distances.size(), MAX_MARKS)
	var landed: int = trace_crossings(
		origin, aim, speed, gravity, rifle.profile.projectile_step_metres,
		rifle.profile.projectile_max_flight_seconds, rifle.profile.get_charged_range(charge),
		get_physics_process_delta_time(), mark_distances, count, _crossings
	)
	var limit: float = _clear_radius * ARM_CAP - mark_half_width * _unit
	var last: float = gap * _unit + line_thickness * _unit
	for i: int in range(landed):
		var point: Vector2 = _to_local(camera.unproject_position(_crossings[i]))
		var offset: float = point.distance_to(_centre)
		if offset > limit:
			break
		# A mark inside the open centre or on top of the last one would hide the aim, so it is skipped.
		if offset < last + 3.0 * line_thickness * _unit:
			continue
		last = offset
		_marks[_mark_count] = point
		_mark_index[_mark_count] = i
		_mark_count += 1


## The aim point, in the viewport's canvas coordinates.
func get_screen_centre() -> Vector2:
	return get_global_transform_with_canvas() * _centre


## How many holdover marks are on screen.
func get_mark_count() -> int:
	return _mark_count


## Mark [param i] in the viewport's canvas coordinates.
func get_mark_screen_position(i: int) -> Vector2:
	return get_global_transform_with_canvas() * _marks[i]


## The distance in metres mark [param i] stands for.
func get_mark_distance(i: int) -> float:
	return mark_distances[_mark_index[i]]


## Lead tick offset from centre, pixels; 0.0 when none is drawn.
func get_lead_pixels() -> float:
	return _lead


## Fly a round as [method WeaponProjectile.advance] does, one physics tick at a time, and write
## where it crosses each plane [param distances] metres down [param aim]. Returns how many it reached.
static func trace_crossings(
	origin: Vector3, aim: Vector3, speed: float, gravity: float, step_metres: float,
	max_flight: float, travel_range: float, tick_delta: float,
	distances: PackedFloat32Array, count: int, out: PackedVector3Array
) -> int:
	var velocity: Vector3 = aim.normalized() * maxf(speed, 0.001)
	var step_cap: float = maxf(step_metres, 0.05)
	var flight_cap: float = maxf(max_flight, 0.05)
	var range_left: float = maxf(travel_range, 0.0)
	var pos: Vector3 = origin
	var flight: float = 0.0
	var found: int = 0
	while found < count and tick_delta > 0.0:
		flight += tick_delta
		var remaining: float = tick_delta
		while remaining > 0.0:
			var step: float = minf(remaining, step_cap / velocity.length())
			velocity.y -= gravity * step
			var to: Vector3 = pos + velocity * step
			var travelled: float = pos.distance_to(to)
			var spent: bool = travelled >= range_left
			if spent and travelled > 0.0:
				to = to.lerp(pos, (travelled - range_left) / travelled)
			found = _note_crossings(origin, aim, pos, to, distances, count, found, out)
			if spent or found >= count:
				return found
			range_left -= travelled
			pos = to
			remaining -= step
			if flight >= flight_cap:
				return found
	return found


# --- Internals ----------------------------------------------------------------

static func _note_crossings(
	origin: Vector3, aim: Vector3, from: Vector3, to: Vector3,
	distances: PackedFloat32Array, count: int, found: int, out: PackedVector3Array
) -> int:
	var a: float = (from - origin).dot(aim)
	var b: float = (to - origin).dot(aim)
	while found < count and b >= distances[found] and b > a:
		out[found] = from.lerp(to, (distances[found] - a) / (b - a))
		found += 1
	return found


func _rifle() -> Rifle:
	if ads == null:
		return null
	return ads.get_parent() as Rifle


func _camera() -> Camera3D:
	var rifle: Rifle = _rifle()
	if rifle != null and rifle.aim_source is Camera3D:
		return rifle.aim_source as Camera3D
	var viewport: Viewport = get_viewport()
	return viewport.get_camera_3d() if viewport != null else null


## Pixels a full-run crossing target must be led by: its run over the round's flight time.
func _lead_pixels(camera: Camera3D, origin: Vector3, aim: Vector3, speed: float, source: Node3D) -> float:
	var holder: PlayerController = _rifle().shooter_body as PlayerController
	if holder == null or holder.profile == null:
		return 0.0
	var rules: MatchRules = _rifle().rules
	var run: float = holder.profile.ground_speed * (rules.runner_speed_multiplier if rules != null else 1.0)
	var right: Vector3 = source.global_transform.basis.x.normalized()
	var point: Vector3 = origin + aim * AIM_PROBE_METRES + right * (AIM_PROBE_METRES * run / speed)
	return absf(_to_local(camera.unproject_position(point)).x - _centre.x)


func _read_radii(height: float) -> void:
	var clear: float = 0.46
	var soft: float = 0.3
	var profile: ZoomProfile = ads.get_zoom_profile() if ads != null else null
	if profile != null:
		clear = profile.vignette_clear_fraction
		soft = profile.vignette_softness
	_clear_radius = clear * height * 0.5
	_outer_radius = (clear + soft) * height * 0.5


func _to_local(canvas_point: Vector2) -> Vector2:
	return get_global_transform_with_canvas().affine_inverse() * canvas_point


func _draw() -> void:
	_draw_pass(true)
	_draw_pass(false)


## Every line twice: once grown by the edge in [member edge_color], then the core over it.
func _draw_pass(edge: bool) -> void:
	var grow: float = edge_thickness * _unit if edge else 0.0
	var color: Color = edge_color if edge else line_color
	var fine: float = line_thickness * _unit * 0.5
	var post: float = post_thickness * _unit * 0.5
	var taper: float = taper_length * _unit
	var hole: float = gap * _unit
	var base: float = _clear_radius * post_start
	var cap: float = _clear_radius * ARM_CAP
	var lowest: float = 0.0
	for i: int in range(_mark_count):
		lowest = maxf(lowest, _marks[i].y - _centre.y)
	var side: float = clampf(_lead + 10.0 * _unit, base, cap) if _lead > 0.0 else base
	var bottom: float = clampf(lowest + 12.0 * _unit, base, cap) if _mark_count > 0 else base
	_arm(Vector2.UP, base, hole, fine, post, taper, grow, color)
	_arm(Vector2.DOWN, bottom, hole, fine, post, taper, grow, color)
	_arm(Vector2.LEFT, side, hole, fine, post, taper, grow, color)
	_arm(Vector2.RIGHT, side, hole, fine, post, taper, grow, color)
	if _lead > 0.0:
		var tick: float = 5.0 * _unit
		var left: Vector2 = _centre + Vector2(-_lead, 0.0)
		var right: Vector2 = _centre + Vector2(_lead, 0.0)
		_bar(left + Vector2(0.0, -tick), left + Vector2(0.0, tick), fine, fine, grow, color)
		_bar(right + Vector2(0.0, -tick), right + Vector2(0.0, tick), fine, fine, grow, color)
	for i: int in range(_mark_count):
		var long: bool = is_zero_approx(fmod(mark_distances[_mark_index[i]], long_mark_every))
		var half: float = mark_half_width * _unit * (2.0 if long else 1.0)
		var at: Vector2 = _marks[i]
		_bar(at + Vector2(-half, 0.0), at + Vector2(half, 0.0), fine, fine, grow, color)
		if long and mark_labels:
			_label(at + Vector2(half + 4.0 * _unit, 0.0), _mark_index[i], edge)


## One arm: post from the vignette edge in to [param inner], a taper, then fine line to the gap.
func _arm(dir: Vector2, inner: float, hole: float, fine: float, post: float, taper: float, grow: float, color: Color) -> void:
	var outer: float = maxf(_outer_radius, inner + taper)
	var neck: float = maxf(inner - taper, hole)
	_bar(_centre + dir * outer, _centre + dir * inner, post, post, grow, color)
	_bar(_centre + dir * inner, _centre + dir * neck, post, fine, grow, color)
	if neck > hole:
		_bar(_centre + dir * neck, _centre + dir * hole, fine, fine, grow, color)


## A quad from [param a] to [param b] with half-widths [param wa] and [param wb], grown by [param grow].
func _bar(a: Vector2, b: Vector2, wa: float, wb: float, grow: float, color: Color) -> void:
	var along: Vector2 = (b - a).normalized()
	var across: Vector2 = Vector2(-along.y, along.x)
	var p: Vector2 = a - along * grow
	var q: Vector2 = b + along * grow
	draw_colored_polygon(PackedVector2Array([
		p + across * (wa + grow), q + across * (wb + grow),
		q - across * (wb + grow), p - across * (wa + grow),
	]), color)


func _label(at: Vector2, index: int, edge: bool) -> void:
	var font: Font = get_theme_default_font()
	var font_size: int = maxi(int(round(label_size * _unit)), 6)
	if _labels[index].is_empty():
		_labels[index] = tr("HUD_SCOPE_RANGE").format({"metres": int(mark_distances[index])})
	var baseline: Vector2 = at + Vector2(0.0, font.get_ascent(font_size) * 0.5 - font.get_descent(font_size) * 0.5)
	var outline: int = maxi(int(round(edge_thickness * 2.0 * _unit)), 1)
	if edge:
		draw_string_outline(font, baseline, _labels[index], HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, outline, edge_color)
	else:
		draw_string(font, baseline, _labels[index], HORIZONTAL_ALIGNMENT_LEFT, -1.0, font_size, line_color)
