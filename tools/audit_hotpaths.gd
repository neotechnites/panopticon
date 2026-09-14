extends SceneTree

## Lints the per-tick code paths for the work that is not allowed to happen in
## them.
##
## [codeblock]
## godot --headless --path . --script res://tools/audit_hotpaths.gd
## [/codeblock]
##
## Exits 0 when every hot path is clean, 1 when there is a hit, 2 when the audit
## could not read the tree at all.
##
## [b]What it is for[/b]
##
## Every finding in [code]docs/PERF_REVIEW.md[/code] §3 has the same shape: a
## fresh allocation, a node lookup or a group sweep inside a function that runs
## sixty times a second, multiplied by the number of bots. A review finds those
## weeks late. This finds them on the merge, which is the only time they are
## cheap to fix.
##
## [b]What counts as a hot path[/b]
##
## The body of [code]_process[/code], [code]_physics_process[/code],
## [code]_integrate_forces[/code], or any function whose name begins
## [code]tick[/code] or [code]_tick[/code] -- the naming this repo already uses
## for the per-tick state machines in [code]scripts/bot/[/code]. The signature
## line itself is not scanned: a type hint is not an allocation.
##
## [b]It is text, not a parser[/b]
##
## Comments are stripped and string literals are blanked before the rules run, so
## a [code]#[/code] or a [code]get_node([/code] inside a string is not a hit.
## Beyond that this is deliberately a lint and not a compiler: it cannot tell a
## pooled [code].new()[/code] from a fresh one, or a cached array from a rebuilt
## one. That is what the allowlist is for.
##
## [b]The allowlist[/b]
##
## A trailing [code]# hot-ok: <reason>[/code] on the line clears it. The reason is
## required and is printed by [code]--list[/code], because an allowlist nobody can
## read is an allowlist that grows. Blanket-allowing a file or a rule is not
## possible on purpose.

const SCAN_ROOT: String = "res://scripts"

## Directory names never descended into.
const SKIP_DIRECTORIES: Array[String] = [".godot", ".git", "export", "build", "_scratch"]

## The marker that clears a line, and the shortest reason accepted after it.
const ALLOW_MARKER: String = "hot-ok:"
const MIN_REASON_LENGTH: int = 4

## Functions whose whole body is a hot path.
const HOT_NAMES: Array[String] = ["_process", "_physics_process", "_integrate_forces"]

## Prefixes that also make a function a hot path.
const HOT_PREFIXES: Array[String] = ["tick", "_tick"]

## Prints every allowlisted line and its reason, then the hits.
const LIST_FLAG: String = "--list"

const EXIT_OK: int = 0
const EXIT_FAILED: int = 1
const EXIT_BROKEN: int = 2

## One rule: a name, a compiled pattern, and the sentence printed when it fires.
class Rule extends RefCounted:
	var id: String
	var regex: RegEx
	var why: String

	func _init(rule_id: String, pattern: String, reason: String) -> void:
		id = rule_id
		regex = RegEx.new()
		var error: int = regex.compile(pattern)
		if error != OK:
			push_error("audit_hotpaths: rule %s has a bad pattern" % rule_id)
		why = reason


var _started: bool = false
var _finished: bool = false
var _exit_code: int = EXIT_OK
var _list: bool = false
var _rules: Array[Rule] = []


func _initialize() -> void:
	_list = OS.get_cmdline_user_args().has(LIST_FLAG)
	_rules = _build_rules()


## Quitting from [method _initialize] exits before stdout is flushed, so the work
## happens here -- the same reason [code]tools/run_tests.gd[/code] does.
func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	if _finished:
		quit(_exit_code)
		return true
	return false


## The rules. Assignment patterns use a lookbehind so [code]+=[/code] and
## [code]==[/code] are not read as a fresh binding.
func _build_rules() -> Array[Rule]:
	var assign: String = "(?<![=!<>+\\-*/%])=\\s*"
	return [
		Rule.new("node-lookup", "\\bget_node\\s*\\(", "resolve the path once and keep the reference"),
		Rule.new("node-search", "\\bfind_child(ren)?\\s*\\(", "a tree walk per tick; cache the node"),
		Rule.new("group-sweep", "get_tree\\(\\)\\.get_nodes_in_group\\s*\\(", "allocates an array per call; fetch once per frame"),
		Rule.new("string-build", "\\bstr\\s*\\(", "builds a string per tick; format only when something is shown"),
		Rule.new("string-format", "\"[^\"]*\"\\s*%|^\\s*[)\\]]?\\s*%\\s*[\\[(]", "a format per tick; format only when something is shown"),
		Rule.new("string-concat", "\"\\s*\\+|\\+\\s*\"", "concatenation allocates; format only when something is shown"),
		Rule.new("array-literal", assign + "\\[|\\bArray\\s*(\\[[^\\]]*\\])?\\s*\\(", "a fresh array per tick; reuse a member and clear() it"),
		Rule.new("dictionary-literal", assign + "\\{|\\bDictionary\\s*(\\[[^\\]]*\\])?\\s*\\(", "a fresh dictionary per tick; reuse a member or use a typed class"),
		Rule.new("packed-array", "\\bPacked[A-Za-z0-9]*Array\\s*\\(", "a fresh packed array per tick; resize a member once"),
		Rule.new("duplicate", "\\.duplicate\\s*\\(", "copies the whole container per tick; take a read-only reference"),
		Rule.new("object-new", "\\.new\\s*\\(", "an object per tick; pool it"),
		Rule.new("ray-query", "\\bintersect_(ray|shape)\\s*\\(", "rays must be spent through the cover finder's budget"),
	]


func _run() -> void:
	var paths: PackedStringArray = _gdscript_paths(SCAN_ROOT)
	if paths.is_empty():
		printerr("Nothing to scan under %s" % SCAN_ROOT)
		_exit_code = EXIT_BROKEN
		_finished = true
		return
	paths.sort()

	print("PANOPTICON hot-path audit")
	print("  scanning   %s (%d scripts)" % [SCAN_ROOT, paths.size()])
	print("  hot paths  %s, and any %s" % [
		", ".join(HOT_NAMES), " / ".join(HOT_PREFIXES).replace("tick", "tick*"),
	])
	print("  allowlist  a trailing \"# %s <reason>\" on the line" % ALLOW_MARKER)
	print("")

	var hits: Array[Dictionary] = []
	var allowed: Array[Dictionary] = []
	var functions: int = 0
	for path: String in paths:
		functions += _scan(path, hits, allowed)

	if _list and not allowed.is_empty():
		print("Allowed (%d):" % allowed.size())
		for row: Dictionary in allowed:
			print("  %s:%d  %s  -- %s" % [row["path"], row["line"], row["rule"], row["reason"]])
		print("")

	if hits.is_empty():
		print("CLEAN  %d hot functions, %d lines allowlisted, 0 hits" % [functions, allowed.size()])
		_exit_code = EXIT_OK
		_finished = true
		return

	var current: String = ""
	for row: Dictionary in hits:
		var path: String = String(row["path"])
		if path != current:
			current = path
			print(path)
		print("  %5d  %-18s %s" % [int(row["line"]), String(row["rule"]), String(row["code"])])
		print("         %-18s %s" % ["", String(row["why"])])
	print("")
	print("DIRTY  %d hot functions, %d lines allowlisted, %d hits" % [
		functions, allowed.size(), hits.size(),
	])
	print("       Fix them, or clear the line with a trailing \"# %s <reason>\"." % ALLOW_MARKER)
	_exit_code = EXIT_FAILED
	_finished = true


## Scan one file, appending to [param hits] and [param allowed]. Returns how many
## hot functions it found.
func _scan(path: String, hits: Array[Dictionary], allowed: Array[Dictionary]) -> int:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return 0
	var lines: PackedStringArray = file.get_as_text().split("\n")
	file.close()

	var signature: RegEx = RegEx.new()
	var _ok: int = signature.compile("^(\\t*)(static\\s+)?func\\s+([A-Za-z0-9_]+)\\s*\\(")

	var found: int = 0
	var hot_indent: int = -1
	for number: int in lines.size():
		var line: String = lines[number]
		var stripped: String = line.strip_edges()

		var match_: RegExMatch = signature.search(line)
		if match_ != null:
			var indent: int = match_.get_string(1).length()
			var name: String = match_.get_string(3)
			hot_indent = indent if _is_hot(name) else -1
			if hot_indent >= 0:
				found += 1
			continue

		if hot_indent < 0 or stripped.is_empty():
			continue
		if _indent_of(line) <= hot_indent:
			# Dedented back out of the function, so the hot path has ended.
			hot_indent = -1
			continue

		_check(path, number + 1, line, hits, allowed)
	return found


## Run every rule over one line of a hot path.
func _check(
	path: String, number: int, line: String, hits: Array[Dictionary], allowed: Array[Dictionary]
) -> void:
	var code: String = _strip_comment(line)
	if code.strip_edges().is_empty():
		return
	var blanked: String = _blank_strings_but_keep_quotes(code)
	var reason: String = _allow_reason(line)

	for rule: Rule in _rules:
		if rule.regex.search(blanked) == null:
			continue
		var row: Dictionary = {
			"path": path, "line": number, "rule": rule.id,
			"code": code.strip_edges(), "why": rule.why, "reason": reason,
		}
		if reason.is_empty():
			hits.append(row)
		else:
			allowed.append(row)


func _is_hot(name: String) -> bool:
	if HOT_NAMES.has(name):
		return true
	for prefix: String in HOT_PREFIXES:
		if name.begins_with(prefix):
			return true
	return false


func _indent_of(line: String) -> int:
	var count: int = 0
	while count < line.length() and (line[count] == "\t" or line[count] == " "):
		count += 1
	return count


## The reason on a [code]# hot-ok:[/code] comment, or "" if there is none. A bare
## marker is not an entry: a line nobody explained is a line still to explain.
func _allow_reason(line: String) -> String:
	var at: int = line.find(ALLOW_MARKER)
	if at < 0:
		return ""
	var reason: String = line.substr(at + ALLOW_MARKER.length()).strip_edges()
	return reason if reason.length() >= MIN_REASON_LENGTH else ""


## Everything before an unquoted [code]#[/code].
func _strip_comment(line: String) -> String:
	var quote: String = ""
	var index: int = 0
	while index < line.length():
		var character: String = line[index]
		if character == "\\" and not quote.is_empty():
			index += 2
			continue
		if quote.is_empty() and (character == "\"" or character == "'"):
			quote = character
		elif character == quote:
			quote = ""
		elif quote.is_empty() and character == "#":
			return line.substr(0, index)
		index += 1
	return line


## The line with every string literal's CONTENTS blanked. The quotes stay, so a
## format is still recognisable while [code]get_node([/code] in a string is not.
func _blank_strings_but_keep_quotes(line: String) -> String:
	var out: String = ""
	var quote: String = ""
	var index: int = 0
	while index < line.length():
		var character: String = line[index]
		if character == "\\" and not quote.is_empty():
			out += "  "
			index += 2
			continue
		if quote.is_empty() and (character == "\"" or character == "'"):
			quote = character
			out += character
		elif character == quote:
			quote = ""
			out += character
		elif quote.is_empty():
			out += character
		else:
			out += " "
		index += 1
	return out


## Every [code].gd[/code] under [param dir_path], recursively.
func _gdscript_paths(dir_path: String) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry.begins_with(".") or SKIP_DIRECTORIES.has(entry):
			entry = dir.get_next()
			continue
		var full: String = dir_path.path_join(entry)
		if dir.current_is_dir():
			found.append_array(_gdscript_paths(full))
		elif entry.ends_with(".gd"):
			found.append(full)
		entry = dir.get_next()
	dir.list_dir_end()
	return found
