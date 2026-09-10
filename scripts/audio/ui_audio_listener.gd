class_name UIAudioListener
extends Node

## Makes a menu audible without any menu knowing about audio.
##
## Drop it under a [MainMenu], a [PauseMenu] or a whole match root and it
## subscribes to every [BaseButton] in that subtree, plus the two menu-level
## signals worth hearing. No UI script is edited.
##
## [b]What comes from where[/b]
## [codeblock]
##   BaseButton.pressed        -> ui.click
##   BaseButton.focus_entered  -> ui.focus
##   BaseButton.mouse_entered  -> ui.focus
##   PauseMenu.opened          -> ui.menu_opened
##   PauseMenu.closed          -> ui.menu_closed
##   SettingsScreen.closed     -> ui.back
## [/codeblock]
##
## [b]Why it watches [signal SceneTree.node_added] instead of walking once.[/b]
## Every menu in this project builds its own controls in code -- see
## [method MainMenu._build] and [method SettingsScreen._build] -- and Godot runs
## a child's [method Node._ready] before its parent's, so a listener parented
## under a menu is ready before that menu has created a single button. Worse,
## the settings screen is constructed and destroyed on demand, so a one-shot
## walk would go stale the first time it is opened. Subscribing to the tree
## itself is the only version that catches all of it, costs two casts per node
## added, and needs no bookkeeping: a signal to a freed node disconnects itself.
##
## [b]ui.focus is rate limited, not debounced by this file.[/b] A mouse dragged
## down a column of buttons emits [signal Control.mouse_entered] once per
## button, which is a machine gun. The fix lives on the cue as
## [member AudioCue.min_retrigger_seconds], because how often a sound may
## retrigger is a mixing decision and mixing decisions live in the bank.

## The director to post to. Leave unset to use whichever director is in the tree.
@export var director: AudioDirector = null

## The subtree to wire. Defaults to the root of the scene this node is in, so a
## single audio node wires every menu in it; point it at one menu to scope it.
## A [Node] rather than a [Control] because [PauseMenu] is a [CanvasLayer].
@export var root: Node = null

## Emit [constant AudioEvents.UI_CLICK] for button presses.
@export var wire_clicks: bool = true

## Emit [constant AudioEvents.UI_FOCUS] when focus or the mouse lands on a
## button.
@export var wire_focus: bool = true

## Emit the menu-level events: [constant AudioEvents.UI_MENU_OPENED],
## [constant AudioEvents.UI_MENU_CLOSED] and [constant AudioEvents.UI_BACK].
@export var wire_menus: bool = true

var _root: Node = null


## Subscribes in [method Node._enter_tree] so that controls a menu builds in its
## own [method Node._ready] are caught by [signal SceneTree.node_added] rather
## than missed. The deferred sweep behind it is the safety net for controls that
## were already in the tree when this node arrived.
func _enter_tree() -> void:
	_root = root
	if _root == null:
		_root = _default_search_root()
	if _root == null:
		return
	var tree: SceneTree = get_tree()
	if not tree.node_added.is_connected(_on_node_added):
		tree.node_added.connect(_on_node_added)
	_wire_subtree.call_deferred(_root)


func _exit_tree() -> void:
	var tree: SceneTree = get_tree()
	if tree != null and tree.node_added.is_connected(_on_node_added):
		tree.node_added.disconnect(_on_node_added)


## The highest ancestor below the [SceneTree]'s root window. See
## [method MatchAudioListener._default_search_root] for why this is not
## [member Node.owner].
func _default_search_root() -> Node:
	if not is_inside_tree():
		return get_parent()
	var window: Window = get_tree().root
	var node: Node = self
	while node.get_parent() != null and node.get_parent() != window:
		node = node.get_parent()
	return node


func _on_node_added(node: Node) -> void:
	if _root == null or not is_instance_valid(_root):
		return
	if node != _root and not _root.is_ancestor_of(node):
		return
	wire_node(node)


## Wire [param node] and everything under it. Public so a menu that builds a
## detached subtree and attaches it in one go can force a pass.
func _wire_subtree(node: Node) -> void:
	if node == null or not is_instance_valid(node):
		return
	wire_node(node)
	for child: Node in node.get_children():
		_wire_subtree(child)


## Subscribe to whichever of the interesting signals [param node] has. Idempotent.
func wire_node(node: Node) -> void:
	var button: BaseButton = node as BaseButton
	if button != null:
		if wire_clicks:
			_bind(button.pressed, _on_button_pressed)
		if wire_focus:
			_bind(button.focus_entered, _on_button_focused)
			_bind(button.mouse_entered, _on_button_focused)
		return
	if not wire_menus:
		return
	var pause: PauseMenu = node as PauseMenu
	if pause != null:
		_bind(pause.opened, _on_menu_opened)
		_bind(pause.closed, _on_menu_closed)
		return
	var settings: SettingsScreen = node as SettingsScreen
	if settings != null:
		_bind(settings.closed, _on_settings_closed)


func _bind(source: Signal, handler: Callable) -> void:
	if not source.is_connected(handler):
		source.connect(handler)


func _post(event: StringName) -> void:
	if director != null:
		director.post(event)
		return
	AudioDirector.post_event(event)


func _on_button_pressed() -> void:
	_post(AudioEvents.UI_CLICK)


func _on_button_focused() -> void:
	_post(AudioEvents.UI_FOCUS)


func _on_menu_opened() -> void:
	_post(AudioEvents.UI_MENU_OPENED)


func _on_menu_closed() -> void:
	_post(AudioEvents.UI_MENU_CLOSED)


## The settings screen is the one place in the project with a real "backed out
## of rather than confirmed" signal, so it is what [constant AudioEvents.UI_BACK]
## is wired to. Anything else that gains one connects here too.
func _on_settings_closed() -> void:
	_post(AudioEvents.UI_BACK)
