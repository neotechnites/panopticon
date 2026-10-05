class_name MouseFocus
extends RefCounted

## The one owner of [member Input.mouse_mode]: visible while any menu holds it,
## else captured if play wants the mouse. Nothing else writes the mode.

static var _holders: Dictionary = {}
static var _play_wants: bool = false


## A menu is open; the cursor shows until [method release] is called for it.
static func hold(menu: Object) -> void:
	_holders[menu.get_instance_id()] = true
	_apply()


## The menu closed. Play's wish decides the mode again.
static func release(menu: Object) -> void:
	_holders.erase(menu.get_instance_id())
	_apply()


## Play asks for the mouse (or lets it go); a open menu still wins.
static func set_play_wants(wants: bool) -> void:
	_play_wants = wants
	_apply()


static func is_held() -> bool:
	for id: int in _holders.keys():
		if is_instance_id_valid(id):
			return true
		_holders.erase(id)
	return false


## The mode the owner wants now; headless has no cursor, so tests read this.
static func wanted_mode() -> Input.MouseMode:
	if _play_wants and not is_held():
		return Input.MOUSE_MODE_CAPTURED
	return Input.MOUSE_MODE_VISIBLE


static func _apply() -> void:
	Input.mouse_mode = wanted_mode()
