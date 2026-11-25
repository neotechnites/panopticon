extends NetPowerRig

## A cat in a client's hands when its host goes: nothing of it, nor the pet prompt that eats the
## interact key, outlives the session on that client.

const CAT: int = MatchRules.RunnerAbility.CAT_GRENADE


func test_a_cat_in_a_clients_hands_when_the_host_goes_is_cleared_from_its_screen() -> void:
	if not await stand_up():
		return
	a_keys.tap_power(CAT)
	var offered: bool = await until(func() -> bool:
		var view: CatView = power_of(a_links, A_SEAT).get_cat_view()
		return view != null and view.is_petting())
	if not assert_true(offered, "A holds its cat and is offered the pet"):
		return
	host.leave()
	await until(func() -> bool: return not a.is_established())
	await step_ticks(30)
	var mine: RunnerPower = power_of(a_links, A_SEAT)
	print("PROOF h1b: 30 ticks after the host left: established=%s prompts=%d" % [str(a.is_established()), _prompts()])
	assert_eq_int(_prompts(), 0, "no pet prompt (which eats the interact key) is left up")
	# The cat is drawn in the session's scene: it goes with it, as SessionFlow changes scene.
	for link: PlayerNetLink in a_links:
		link.controller.queue_free()
	await step_ticks(2)
	var drawn: int = 0
	for node: Node in a.get_tree().root.find_children("*", "Node3D", true, false):
		if node is CatView and not node.is_queued_for_deletion() and a.get_parent().is_ancestor_of(node):
			drawn += 1
	assert_eq_int(drawn, 0, "no cat is left drawn once the session's scene is gone")
	assert_null(mine if is_instance_valid(mine) else null, "the power went with its body")


func _prompts() -> int:
	var prompts: int = 0
	for node: Node in a.get_parent().find_children("*", "CanvasLayer", true, false):
		if not node.is_queued_for_deletion() and node.get_parent() is CatView:
			prompts += 1
	return prompts
