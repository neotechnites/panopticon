extends TestCase

## The bake's pad flights on the shipped map: none ends where it trips a pad that
## has no flight of its own, and a pad with no flight is not ground to walk on.

const SETTLE_TICKS: int = 4

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
				absf(local.x) <= half.x + RingBake.PAD_CLEARANCE_METRES
				and absf(local.z) <= half.z + RingBake.PAD_CLEARANCE_METRES
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
