class_name PressSource
extends IntentSource

## A scripted device for the networking tests: levels that stand, and taps that last one tick,
## which is what a key is. [BotIntentSource] holds a power key down for as long as it is set.

var held: MoveIntent = MoveIntent.new()
## How this device's seat picks a power on every machine (its rig's), for [method tap_power].
var pick: Callable = Callable()
var _taps: Array[StringName] = []
## Ticks polled, so a test can tell which tick a tap went out on.
var polls: int = 0


## Press [param key] (a [MoveIntent] flag name) on the next tick only.
func tap(key: StringName) -> void:
	_taps.append(key)


## Pick [param which] (as a hub stand would) and press use on the next tick only.
func tap_power(which: int) -> void:
	if pick.is_valid():
		pick.call(which)
	_taps.append(&"ability_pressed")


func poll(_delta: float) -> MoveIntent:
	polls += 1
	_intent.copy_from(held)
	for key: StringName in _taps:
		_intent.set(key, true)
	_taps.clear()
	return _intent
