class_name PressSource
extends IntentSource

## A scripted device for the networking tests: levels that stand, and taps that last one tick,
## which is what a key is. [BotIntentSource] holds a power key down for as long as it is set.

var held: MoveIntent = MoveIntent.new()
var _taps: Array[StringName] = []
var _slots: PackedInt32Array = PackedInt32Array()
## Ticks polled, so a test can tell which tick a tap went out on.
var polls: int = 0


## Press [param key] (a [MoveIntent] flag name) on the next tick only.
func tap(key: StringName) -> void:
	_taps.append(key)


## Press power key [param slot] on the next tick only.
func tap_slot(slot: int) -> void:
	_slots.append(slot)


func poll(_delta: float) -> MoveIntent:
	polls += 1
	_intent.copy_from(held)
	for key: StringName in _taps:
		_intent.set(key, true)
	_taps.clear()
	if not _slots.is_empty():
		_intent.ability_slot = _slots[0]
		_slots.remove_at(0)
	return _intent
