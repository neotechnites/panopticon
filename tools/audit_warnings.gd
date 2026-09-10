extends SceneTree

## Proves that every GDScript in the project compiles with the project's own
## warnings promoted to errors.
##
## [codeblock]
## godot --headless --path . --script res://tools/audit_warnings.gd
## [/codeblock]
##
## Exits 0 when the project is clean, 1 when a script fails, and 2 when the
## audit itself could not be run.
##
## [b]Two ways of doing this that do not work[/b]
##
## Both were tried on this project and both reported a clean bill of health for
## code that was not clean. They are the reason this file is a hundred lines of
## copying and subprocesses instead of a for loop.
##
## 1. [b][method @GDScript.load] alone tests nothing.[/b] Handed a script that
##    would fail to compile under warnings-as-errors, [ResourceLoader] prints the
##    diagnostic and still hands back a non-null [GDScript]. A checker written as
##    [code]if load(path) != null: passed += 1[/code] therefore passes
##    everything, forever, including files that will not run. Only
##    [method GDScript.reload] returns an [enum Error] a script can branch on,
##    and that is what the child below branches on.
## 2. [b]A copied project that is never imported has no class cache.[/b] The
##    global [code]class_name[/code] registry lives in
##    [code].godot/global_script_class_cache.cfg[/code], which is built by the
##    import step and is not in version control. Copy the project, skip the
##    import, and every custom type in every file resolves to "Could not find
##    type" -- an audit that floods with hundreds of failures that say nothing
##    about the code. The copy below is imported before anything is loaded in it.
##
## [b]The dance[/b]
##
## COPY the project to a temporary directory. IMPORT the copy, so it has a class
## cache of its own. PROMOTE the copy's warning levels to errors -- in the copy,
## because [code]project.godot[/code] is not this tool's to edit and a developer
## who ran this must not find their settings changed. RELOAD every script in a
## child Godot launched against the copy, and report what the engine says.
##
## The child is a separate process for the same reason
## [code]tools/run_tests.gd[/code] uses one: a compile diagnostic goes to stderr,
## a program cannot read its own stderr, and the parent needs the text to tell a
## warning from an error and to put it in the report.

## Warning levels, as [code]project.godot[/code] stores them.
const LEVEL_IGNORE: int = 0
const LEVEL_WARN: int = 1
const LEVEL_ERROR: int = 2

## Prefix of the warning keys inside project.godot's [code][debug][/code] section.
const WARNING_PREFIX: String = "gdscript/warnings/"

## Directory names never copied into the audit workspace. [code].godot[/code] is
## the one that matters -- carrying a stale cache across would defeat the import
## step -- and the rest are hidden or generated anyway.
const SKIP_DIRECTORIES: Array[String] = [".godot", ".git", "export", "build", "_scratch"]

## Printed by the child around its report, so the parent can tell "the child ran
## and found nothing" from "the child never started".
const REPORT_BEGIN: String = "AUDIT-BEGIN"
const REPORT_END: String = "AUDIT-END"

const CHILD_FLAG: String = "--child"

## Keeps the temporary copy on disk and prints its path. For diagnosing the
## audit itself.
const KEEP_FLAG: String = "--keep"

const EXIT_OK: int = 0
const EXIT_FAILED: int = 1
const EXIT_BROKEN: int = 2

var _is_child: bool = false
var _keep_workspace: bool = false
var _started: bool = false
var _finished: bool = false
var _exit_code: int = EXIT_OK


func _initialize() -> void:
	var user_args: PackedStringArray = OS.get_cmdline_user_args()
	_is_child = user_args.has(CHILD_FLAG)
	_keep_workspace = user_args.has(KEEP_FLAG)


## All work happens here: quitting from [method _initialize] exits before stdout
## is flushed, and a report nobody sees is worse than no report.
func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		if _is_child:
			_run_child()
		else:
			_run_audit()
	if _finished:
		quit(_exit_code)
		return true
	return false


# --- The child: reload every script -------------------------------------------

## Runs inside the imported, promoted copy. Prints one line per script.
##
## [b]The one script not reloaded here is this one[/b], because
## [method GDScript.reload] refuses while an instance of the script exists and
## this script is currently running. It is not unaudited: it is compiled under
## the promoted warnings like everything else, and a script that fails to compile
## does not execute -- so if this file carried a warning, the child would print a
## parse error and never reach [constant REPORT_BEGIN]. The parent treats a
## missing terminator as a broken audit and prints the diagnostic, which is a
## stricter check than the reload it is standing in for.
func _run_child() -> void:
	var paths: PackedStringArray = _gdscript_paths("res://")
	paths.sort()

	var self_path: String = get_script().resource_path
	var ordered: PackedStringArray = PackedStringArray()
	for path: String in paths:
		if path != self_path:
			ordered.append(path)

	print(REPORT_BEGIN)
	var failures: int = 0
	for path: String in ordered:
		var script: GDScript = load(path) as GDScript
		if script == null:
			# The honest null case: the resource loader gave up entirely.
			print("  FAIL  %s  (not loadable as a GDScript)" % path)
			failures += 1
			continue

		# The load above proves nothing on its own -- see the class docs. This is
		# the call that returns something worth branching on.
		var error: int = script.reload(false)
		if error != OK:
			print("  FAIL  %s  (reload returned %d: %s)" % [path, error, error_string(error)])
			failures += 1
		else:
			print("  ok    %s" % path)

	print("  self  %s  (compiled, not reloadable while running)" % self_path)
	print("%s scripts=%d failures=%d" % [REPORT_END, ordered.size(), failures])
	_exit_code = EXIT_OK if failures == 0 else EXIT_FAILED
	_finished = true


# --- The parent: copy, import, promote, launch --------------------------------

func _run_audit() -> void:
	var source: String = ProjectSettings.globalize_path("res://")
	var workspace: String = OS.get_temp_dir().path_join(
		"panopticon_audit_%d" % Time.get_ticks_usec()
	)

	print("PANOPTICON warnings audit")
	print("  project    %s" % source)
	print("  workspace  %s" % workspace)

	# --- COPY ---
	var copied: int = _copy_tree(source, workspace)
	if copied < 0:
		printerr("Could not copy the project into %s" % workspace)
		_exit_code = EXIT_BROKEN
		_finished = true
		return
	print("  copied     %d files" % copied)

	# --- IMPORT ---
	# Without this the copy has no .godot/global_script_class_cache.cfg and every
	# custom type in the project reports as unknown. See the class docs.
	var import_log: Array = []
	var import_code: int = OS.execute(
		OS.get_executable_path(),
		PackedStringArray(["--headless", "--path", workspace, "--import"]),
		import_log, true, false,
	)
	if import_code != 0:
		printerr("Importing the copy failed (exit %d):" % import_code)
		printerr(_joined(import_log))
		_cleanup(workspace)
		_exit_code = EXIT_BROKEN
		_finished = true
		return
	if not _class_cache_exists(workspace):
		printerr("The copy imported but produced no global class cache; every")
		printerr("custom type would report as unknown and the audit would be noise.")
		_cleanup(workspace)
		_exit_code = EXIT_BROKEN
		_finished = true
		return

	# --- PROMOTE ---
	var promoted: PackedStringArray = _promote_warnings(workspace.path_join("project.godot"))
	if promoted.is_empty():
		printerr("No enabled GDScript warnings found in project.godot; there is")
		printerr("nothing for this audit to enforce. Enable some under [debug].")
		_cleanup(workspace)
		_exit_code = EXIT_BROKEN
		_finished = true
		return
	print("  enforcing  %s" % ", ".join(promoted))
	print("")

	# --- RELOAD ---
	var child_log: Array = []
	var child_code: int = OS.execute(
		OS.get_executable_path(),
		PackedStringArray([
			"--headless", "--path", workspace,
			"--script", get_script().resource_path,
			"--", CHILD_FLAG,
		]),
		child_log, true, false,
	)
	var transcript: String = _joined(child_log)

	if not transcript.contains(REPORT_END):
		# The child never got as far as printing its own terminator. The usual
		# cause is this very file failing to compile under the promoted warnings,
		# which Godot reports and then exits 0 from, so the exit code cannot be
		# trusted here.
		printerr("The audit child did not complete. Its output was:")
		printerr(transcript)
		_cleanup(workspace)
		_exit_code = EXIT_BROKEN
		_finished = true
		return

	print(_rewrite_workspace_paths(transcript, workspace).strip_edges(false, true))

	var diagnostics: PackedStringArray = _diagnostics(transcript)
	if not diagnostics.is_empty():
		print("")
		print("Compiler output:")
		for line: String in diagnostics:
			print("    %s" % _rewrite_workspace_paths(line, workspace))

	_cleanup(workspace)

	print("")
	if child_code == 0 and diagnostics.is_empty():
		print("CLEAN  every script compiles with the project's warnings as errors")
		_exit_code = EXIT_OK
	else:
		print("DIRTY  see above")
		_exit_code = EXIT_FAILED
	_finished = true


# --- Promotion ----------------------------------------------------------------

## Rewrite every enabled warning in [param project_file] to error level.
##
## Text surgery rather than [ConfigFile], deliberately: project.godot's
## [code][input][/code] section stores serialised [InputEvent] objects, and a
## round trip through a config parser is a chance to mangle the keybinds of the
## copy the audit is about to run. Only lines that already read
## [code]gdscript/warnings/x=1[/code] are touched.
##
## Returns the names promoted, so the report can say what it enforced.
func _promote_warnings(project_file: String) -> PackedStringArray:
	var promoted: PackedStringArray = PackedStringArray()
	var file: FileAccess = FileAccess.open(project_file, FileAccess.READ)
	if file == null:
		return promoted
	var text: String = file.get_as_text()
	file.close()

	var rebuilt: PackedStringArray = PackedStringArray()
	for line: String in text.split("\n"):
		var trimmed: String = line.strip_edges()
		if trimmed.begins_with(WARNING_PREFIX) and trimmed.contains("="):
			var parts: PackedStringArray = trimmed.split("=", true, 1)
			var key: String = parts[0].trim_prefix(WARNING_PREFIX)
			var value: String = parts[1].strip_edges()
			if value.is_valid_int() and int(value) >= LEVEL_WARN:
				promoted.append(key)
				rebuilt.append("%s%s=%d" % [WARNING_PREFIX, key, LEVEL_ERROR])
				continue
		rebuilt.append(line)

	if promoted.is_empty():
		return promoted

	var out: FileAccess = FileAccess.open(project_file, FileAccess.WRITE)
	if out == null:
		return PackedStringArray()
	out.store_string("\n".join(rebuilt))
	out.close()
	return promoted


# --- Workspace ----------------------------------------------------------------

## Recursive copy. Returns the number of files copied, or -1 on failure.
##
## Hidden entries are skipped, which is how [code].godot[/code] and
## [code].git[/code] stay behind; [constant SKIP_DIRECTORIES] names them anyway
## so the intent does not depend on that default.
func _copy_tree(from: String, to: String) -> int:
	if DirAccess.make_dir_recursive_absolute(to) != OK:
		return -1
	var dir: DirAccess = DirAccess.open(from)
	if dir == null:
		return -1

	var count: int = 0
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry.begins_with(".") or SKIP_DIRECTORIES.has(entry):
			entry = dir.get_next()
			continue
		var source: String = from.path_join(entry)
		var target: String = to.path_join(entry)
		if dir.current_is_dir():
			var nested: int = _copy_tree(source, target)
			if nested < 0:
				dir.list_dir_end()
				return -1
			count += nested
		elif DirAccess.copy_absolute(source, target) == OK:
			count += 1
		entry = dir.get_next()
	dir.list_dir_end()
	return count


## True when the copy's import produced a class cache with real entries in it.
##
## An empty cache is the dangerous state rather than a missing one: it exists,
## so a file-exists check passes, and yet every [code]class_name[/code] in the
## project resolves to an unknown type and the audit fills with hundreds of
## failures about types that are perfectly fine. Insist on content.
func _class_cache_exists(workspace: String) -> bool:
	var path: String = workspace.path_join(".godot/global_script_class_cache.cfg")
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return false
	var text: String = file.get_as_text()
	file.close()
	return text.contains("\"class\":")


func _cleanup(workspace: String) -> void:
	if _keep_workspace:
		print("  workspace kept at %s" % workspace)
		return
	# Belt and braces before a recursive delete: this must only ever be able to
	# remove a directory this run created inside the system temp directory.
	if not workspace.begins_with(OS.get_temp_dir()) or not workspace.get_file().begins_with("panopticon_audit_"):
		printerr("Refusing to remove %s: it is not an audit workspace." % workspace)
		return
	_remove_tree(workspace)


func _remove_tree(path: String) -> void:
	var dir: DirAccess = DirAccess.open(path)
	if dir == null:
		return
	dir.include_hidden = true
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		var child: String = path.path_join(entry)
		if dir.current_is_dir():
			_remove_tree(child)
		else:
			DirAccess.remove_absolute(child)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)


# --- Reporting ----------------------------------------------------------------

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


## Compiler complaints in the child's transcript.
##
## With every enabled warning promoted to an error, a warning and an error are
## the same event, so one filter catches both. The list is what turns "reload
## returned 43" into a line and a reason.
func _diagnostics(transcript: String) -> PackedStringArray:
	var lines: PackedStringArray = PackedStringArray()
	for line: String in transcript.split("\n"):
		var trimmed: String = line.strip_edges()
		if trimmed.is_empty():
			continue
		if trimmed.contains("SCRIPT ERROR") or trimmed.contains("WARNING:") or trimmed.begins_with("ERROR:"):
			lines.append(trimmed)
		elif trimmed.begins_with("at: ") and not lines.is_empty():
			# The location line Godot prints under a diagnostic.
			lines.append(trimmed)
	return lines


## Put the temporary workspace's paths back into project terms, so a failure
## names a file the developer can open.
func _rewrite_workspace_paths(text: String, workspace: String) -> String:
	return text.replace(workspace, ProjectSettings.globalize_path("res://").trim_suffix("/"))


func _joined(chunks: Array) -> String:
	var text: String = ""
	for chunk: Variant in chunks:
		text += String(chunk)
	return text
