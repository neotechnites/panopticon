extends SceneTree

## PANOPTICON i18n audit.
##
## [codeblock]
## godot --headless --path . --script res://tools/audit_i18n.gd                 # audit
## godot --headless --path . --script res://tools/audit_i18n.gd -- --list       # also print i18n-skip lines
## godot --headless --path . --script res://tools/audit_i18n.gd -- --fill-pseudo # write missing en_XA cells
## [/codeblock]
##
## Three rules: every key a scene, script or resource references is in the
## table; every table key is referenced; no authored text in a UI scene is raw.
## [method scan] is static so [code]tests/test_i18n.gd[/code] asserts the same
## report this prints. Exit 0 clean, 1 dirty, 2 the table could not be read.

const CSV_PATH: String = "res://assets/locale/strings.csv"
const SOURCE_LOCALE: String = "en"
const PSEUDO_LOCALE: String = "en_XA"

## Where key references are counted. Tests and tools are not the game.
const REFERENCE_ROOTS: Array[String] = ["res://scenes", "res://scripts", "res://resources"]
const REFERENCE_EXTENSIONS: Array[String] = [".gd", ".tscn", ".tres"]

## Scenes whose authored text must be keys. scenes/dev is a dev playground.
const UI_SCENE_ROOTS: Array[String] = ["res://scenes/ui", "res://scenes/hub", "res://scenes/match"]
const TEXT_PROPERTIES: Array[String] = ["text", "tooltip_text", "placeholder_text"]

## Authored text allowed raw: the game's title is a name, not a word.
const RAW_ALLOWLIST: Array[String] = ["PANOPTICON"]

## A quoted token counts as a key only under one of these namespaces.
const KEY_PREFIXES: Array[String] = [
	"MENU_", "PAUSE_", "COMMON_", "DEATH_", "RESULT_", "ROUND_", "SETUP_",
	"MP_", "SETTINGS_", "KEYBIND_", "HUD_", "HUB_", "MAP_",
]

## Trailing comment that marks a dev-only readout left raw on purpose.
const SKIP_MARKER: String = "# i18n-skip:"

const LIST_FLAG: String = "--list"
const FILL_FLAG: String = "--fill-pseudo"

const EXIT_OK: int = 0
const EXIT_FAILED: int = 1
const EXIT_BROKEN: int = 2

const PSEUDO_ACCENTS: Dictionary = {
	"a": "ä", "e": "é", "i": "ï", "o": "ö", "u": "ü", "y": "ý",
	"A": "Å", "E": "É", "I": "Ï", "O": "Ö", "U": "Ü", "Y": "Ý",
}

var _started: bool = false
var _exit_code: int = EXIT_OK


func _process(_delta: float) -> bool:
	if _started:
		quit(_exit_code)
		return true
	_started = true
	_exit_code = _run()
	return false


func _run() -> int:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.has(FILL_FLAG):
		return fill_pseudo()
	var report: Dictionary = scan()
	if report["broken"]:
		printerr("audit_i18n: cannot read %s" % CSV_PATH)
		return EXIT_BROKEN
	print("PANOPTICON i18n audit")
	print("  table      %s (%d keys)" % [CSV_PATH, report["table"].size()])
	print("  references %s" % ", ".join(REFERENCE_ROOTS))
	print("  ui scenes  %s" % ", ".join(UI_SCENE_ROOTS))
	print("")
	if args.has(LIST_FLAG) and not report["skips"].is_empty():
		print("Raw on purpose (%d):" % report["skips"].size())
		for row: Dictionary in report["skips"]:
			print("  %s:%d  -- %s" % [row["path"], row["line"], row["reason"]])
		print("")
	var hits: int = 0
	hits += _print_rows("Referenced but not in the table", report["missing"])
	hits += _print_rows("In the table but never referenced", report["unused"])
	hits += _print_rows("Table keys with no %s text" % PSEUDO_LOCALE, report["no_pseudo"])
	hits += _print_rows("Raw text in a UI scene", report["raw"])
	if hits == 0:
		print("CLEAN  %d keys, %d referenced, %d lines raw on purpose" % [
			report["table"].size(), report["referenced"].size(), report["skips"].size(),
		])
		return EXIT_OK
	print("DIRTY  %d problems" % hits)
	return EXIT_FAILED


func _print_rows(title: String, rows: Array) -> int:
	if rows.is_empty():
		return 0
	print("%s (%d):" % [title, rows.size()])
	for row: Variant in rows:
		if row is Dictionary:
			print("  %s:%d  %s" % [row["path"], row["line"], row["text"]])
		else:
			print("  %s" % row)
	print("")
	return rows.size()


# --- The report ---------------------------------------------------------------

## The whole audit as data: [code]table[/code] key -> {en, xa},
## [code]referenced[/code] key -> [path:line], and the four problem lists.
static func scan() -> Dictionary:
	var table: Dictionary = read_table()
	var report: Dictionary = {
		"broken": table.is_empty(),
		"table": table,
		"referenced": {},
		"missing": [],
		"unused": [],
		"no_pseudo": [],
		"raw": [],
		"skips": [],
	}
	if table.is_empty():
		return report
	var referenced: Dictionary = report["referenced"]
	for root: String in REFERENCE_ROOTS:
		for path: String in _paths_under(root, REFERENCE_EXTENSIONS):
			_collect_references(path, referenced, report["skips"])
	for key: String in referenced:
		if not table.has(key):
			report["missing"].append("%s  (%s)" % [key, ", ".join(referenced[key])])
	for key: String in table:
		if not referenced.has(key):
			report["unused"].append(key)
		if String(table[key]["xa"]).is_empty() or table[key]["xa"] == table[key]["en"]:
			report["no_pseudo"].append(key)
	for root: String in UI_SCENE_ROOTS:
		for path: String in _paths_under(root, [".tscn"]):
			_collect_raw_text(path, table, report["raw"])
	report["missing"].sort()
	report["unused"].sort()
	report["no_pseudo"].sort()
	return report


## The CSV as key -> {"en": ..., "xa": ...}. Empty when it cannot be read.
static func read_table() -> Dictionary:
	var table: Dictionary = {}
	var file: FileAccess = FileAccess.open(CSV_PATH, FileAccess.READ)
	if file == null:
		return table
	var header: PackedStringArray = file.get_csv_line()
	var en_column: int = header.find(SOURCE_LOCALE)
	var xa_column: int = header.find(PSEUDO_LOCALE)
	if en_column < 0:
		return table
	while not file.eof_reached():
		var row: PackedStringArray = file.get_csv_line()
		if row.size() <= en_column or row[0].is_empty():
			continue
		table[row[0]] = {
			"en": row[en_column],
			"xa": row[xa_column] if xa_column >= 0 and xa_column < row.size() else "",
		}
	return table


static func is_key(token: String) -> bool:
	for prefix: String in KEY_PREFIXES:
		if token.begins_with(prefix):
			return token.length() > prefix.length()
	return false


static func _collect_references(path: String, referenced: Dictionary, skips: Array) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var pattern: RegEx = RegEx.create_from_string("\"([A-Z][A-Z0-9]*(?:_[A-Z0-9]+)+)\"")
	var number: int = 0
	while not file.eof_reached():
		var line: String = file.get_line()
		number += 1
		var skip_at: int = line.find(SKIP_MARKER)
		if skip_at >= 0:
			skips.append({
				"path": path, "line": number,
				"reason": line.substr(skip_at + SKIP_MARKER.length()).strip_edges(),
			})
		for found: RegExMatch in pattern.search_all(line):
			var key: String = found.get_string(1)
			if not is_key(key):
				continue
			if not referenced.has(key):
				referenced[key] = []
			referenced[key].append("%s:%d" % [path, number])


static func _collect_raw_text(path: String, table: Dictionary, raw: Array) -> void:
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return
	var letters: RegEx = RegEx.create_from_string("[A-Za-z]")
	var number: int = 0
	while not file.eof_reached():
		var line: String = file.get_line()
		number += 1
		for property: String in TEXT_PROPERTIES:
			var lead: String = property + " = \""
			if not line.begins_with(lead) or not line.ends_with("\""):
				continue
			var value: String = line.substr(lead.length(), line.length() - lead.length() - 1)
			if value.is_empty() or RAW_ALLOWLIST.has(value) or letters.search(value) == null:
				continue
			if is_key(value) and table.has(value):
				continue
			raw.append({"path": path, "line": number, "text": line})


static func _paths_under(dir_path: String, extensions: Array[String]) -> PackedStringArray:
	var found: PackedStringArray = PackedStringArray()
	var dir: DirAccess = DirAccess.open(dir_path)
	if dir == null:
		return found
	dir.list_dir_begin()
	var entry: String = dir.get_next()
	while entry != "":
		if entry.begins_with("."):
			entry = dir.get_next()
			continue
		var full: String = dir_path.path_join(entry)
		if dir.current_is_dir():
			found.append_array(_paths_under(full, extensions))
		else:
			for extension: String in extensions:
				if entry.ends_with(extension):
					found.append(full)
					break
		entry = dir.get_next()
	dir.list_dir_end()
	found.sort()
	return found


# --- The pseudo locale --------------------------------------------------------

## English made visibly foreign and about a third longer, placeholders intact:
## "Play" -> "[Pläý ~~~~]". A layout that survives this survives most locales.
static func pseudo(english: String) -> String:
	if english.is_empty():
		return ""
	var out: String = ""
	var depth: int = 0
	for character: String in english:
		if character == "{":
			depth += 1
		if depth > 0:
			out += character
			if character == "}":
				depth -= 1
			continue
		out += String(PSEUDO_ACCENTS.get(character, character))
	var chunks: int = maxi(1, int(ceilf(english.length() * 0.3 / 5.0)))
	return "[" + out + " ~~~~".repeat(chunks) + "]"


## Rewrite the CSV with every empty en_XA cell filled from its English.
static func fill_pseudo() -> int:
	var file: FileAccess = FileAccess.open(CSV_PATH, FileAccess.READ)
	if file == null:
		printerr("audit_i18n: cannot read %s" % CSV_PATH)
		return EXIT_BROKEN
	var rows: Array[PackedStringArray] = []
	while not file.eof_reached():
		var row: PackedStringArray = file.get_csv_line()
		if row.size() == 1 and row[0].is_empty():
			continue
		rows.append(row)
	file.close()
	if rows.is_empty():
		return EXIT_BROKEN
	var header: PackedStringArray = rows[0]
	var en_column: int = header.find(SOURCE_LOCALE)
	var xa_column: int = header.find(PSEUDO_LOCALE)
	if en_column < 0 or xa_column < 0:
		printerr("audit_i18n: the header needs both %s and %s" % [SOURCE_LOCALE, PSEUDO_LOCALE])
		return EXIT_BROKEN
	var filled: int = 0
	for index: int in range(1, rows.size()):
		var row: PackedStringArray = rows[index]
		while row.size() <= xa_column:
			row.append("")
		if row[xa_column].is_empty():
			row[xa_column] = pseudo(row[en_column])
			filled += 1
		rows[index] = row
	var out: FileAccess = FileAccess.open(CSV_PATH, FileAccess.WRITE)
	if out == null:
		return EXIT_BROKEN
	for row: PackedStringArray in rows:
		out.store_line(_csv_line(row))
	out.close()
	print("filled %d %s cells in %s" % [filled, PSEUDO_LOCALE, CSV_PATH])
	return EXIT_OK


static func _csv_line(row: PackedStringArray) -> String:
	var cells: PackedStringArray = PackedStringArray()
	for cell: String in row:
		if cell.contains(",") or cell.contains("\"") or cell.contains("\n"):
			cells.append("\"" + cell.replace("\"", "\"\"") + "\"")
		else:
			cells.append(cell)
	return ",".join(cells)
