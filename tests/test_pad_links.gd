extends TestCase

## The bake's pad flights on the shipped map: none ends where it trips a pad that
## has no flight of its own, and a pad with no flight is not ground to walk on.

const SETTLE_TICKS: int = 4

## A bake whose pad stage is broken after it settles: one live pad's flight is sent off the
## mesh. Faults are kept rather than pushed as engine errors, so the suite can read them.
class BrokenPadBake extends RingBake:
	var broken: BoostPad = null
	var reported: PackedStringArray = PackedStringArray()

	func _resolve_pad_landings() -> void:
		super()
		for pad: BoostPad in _pad_landing:
			broken = pad
			_pad_landing[pad] = pad.global_position + Vector3(500.0, 0.0, 500.0)
			return

	func _pad_fault(fault: String) -> void:
		reported.append(fault)

var _arena: Node3D = null
var _bake: RingBake = null
var _pads: Array[BoostPad] = []
var _linked: Dictionary[BoostPad, RingBake.Link] = {}


func before_each() -> void:
	_arena = TestFixtures.make_arena()
	add_child(_arena)
	await step_ticks(SETTLE_TICKS)
	var runner: PlayerController = (load(TestFixtures.RUNNER_SCENE_PATH) as PackedScene).instantiate() as PlayerController
	_bake = RingBake.ensure(_arena, runner.profile)
	runner.free()
	await step_ticks(SETTLE_TICKS)
	_pads.clear()
	_linked.clear()
	for node: Node in _arena.find_children("*", "BoostPad", true, false):
		_pads.append(node as BoostPad)
	for index: int in _bake.get_link_count():
		var link: RingBake.Link = _bake.get_link(index)
		if link.pad != null:
			_linked[link.pad] = link


func test_no_pad_flight_ends_on_a_pad_with_no_flight_of_its_own() -> void:
	if not assert_gt(float(_linked.size()), 0.0, "the map has pad flights"):
		return
	for link: RingBake.Link in _linked.values():
		for pad: BoostPad in _pads:
			if _linked.has(pad):
				continue
			var local: Vector3 = pad.global_transform.affine_inverse() * link.end
			var half: Vector3 = pad.footprint_metres * 0.5
			var trips: bool = (
				absf(local.x) <= half.x + RingBake.PAD_TRIP_METRES
				and absf(local.z) <= half.z + RingBake.PAD_TRIP_METRES
			)
			assert_false(trips, "%s's flight comes down clear of %s" % [link.pad.name, pad.name])


func test_a_pad_with_no_flight_is_cut_out_of_the_mesh() -> void:
	var idle: int = 0
	for pad: BoostPad in _pads:
		if _linked.has(pad):
			continue
		idle += 1
		assert_true(is_nan(_bake.height_at(pad.global_position)), "%s has no flight and no mesh on its plate" % pad.name)
	print("    %d pads, %d with a flight, %d cut out" % [_pads.size(), _linked.size(), idle])


## Dense pads: the link a body is over is the nearest pad's, not the first in the list.
func test_the_pad_link_near_a_point_is_the_nearest_pads() -> void:
	for pad: BoostPad in _linked:
		var found: RingBake.Link = _bake.pad_link_near(pad.global_position + Vector3.UP * 0.5)
		assert_true(found != null and found.pad == pad, "over %s the link found is its own" % pad.name)


## The shipped map bakes to a sound pad contract: every flight lands, every pad without one is cut out.
func test_the_pad_bake_reports_no_fault_on_the_shipped_map() -> void:
	assert_eq_int(_bake.pad_faults().size(), 0, "no pad fault: %s" % ", ".join(_bake.pad_faults()))


## A pad stage that leaves a flight landing off the mesh is caught by the bake itself, by pad name.
func test_the_bake_names_a_pad_whose_flight_does_not_land() -> void:
	var runner: PlayerController = (load(TestFixtures.RUNNER_SCENE_PATH) as PackedScene).instantiate() as PlayerController
	var bake: BrokenPadBake = BrokenPadBake.new()
	bake._movement = runner.profile
	runner.free()
	bake.bake_from(_arena)
	if assert_not_null(bake.broken, "the map has a live pad to break"):
		assert_eq_int(bake.reported.size(), 1, "the bake reports exactly the one broken pad")
		assert_true(bake.reported.size() > 0 and bake.reported[0].begins_with(String(bake.broken.name)), "by name")
	bake.free()


## Nowhere on the mesh does a body overlap the trigger of a pad with no flight: walking the
## carve's edge must not fire it.
func test_no_mesh_point_puts_a_body_on_a_pad_with_no_flight() -> void:
	var checked: int = 0
	for pad: BoostPad in _pads:
		if _linked.has(pad):
			continue
		var half: Vector3 = pad.footprint_metres * 0.5
		for step: int in 9:
			var reach: float = RingBake.BODY_RADIUS_METRES * float(step) / 8.0
			for sample: int in 32:
				var t: float = float(sample) / 8.0
				var f: float = (t - floorf(t)) * 2.0 - 1.0
				var hx: float = half.x + reach
				var hz: float = half.z + reach
				var local: Vector3 = [
					Vector3(f * hx, 0.0, -hz), Vector3(hx, 0.0, f * hz), Vector3(-f * hx, 0.0, hz), Vector3(-hx, 0.0, -f * hz),
				][int(t)]
				var point: Vector3 = pad.global_transform * local
				var height: float = _bake.height_at(point)
				checked += 1
				if not is_nan(height) and absf(height - pad.global_position.y) < 1.0:
					assert_true(false, "%s: mesh %.2f m off its trigger, inside a body's radius" % [pad.name, reach])
					return
	assert_gt(float(checked), 0.0, "the map has pads with no flight to check")
