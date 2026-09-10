class_name BotVariants
extends RefCounted

## Builds the arms of a sweep, from a base [MatchRules] and a JSON spec.
##
## [b]The spec file[/b]
##
## [codeblock]
## {
##   "base_rules": "res://resources/rules/default_match_rules.tres",
##   "notes": "does a faster floor reload settle the tower sooner?",
##   "variants": [
##     {"name": "baseline",     "notes": "shipped defaults", "overrides": {}},
##     {"name": "floor_0_5",    "overrides": {"reload_floor_seconds": 0.5}}
##   ]
## }
## [/codeblock]
##
## Every arm starts as a DUPLICATE of the base rules and then has its overrides
## written onto it, so an arm differs from the baseline in exactly the fields it
## names and a sweep of one field really is a sweep of one field.
##
## An override naming a field [MatchRules] does not have is a hard error rather
## than a shrug. A typo that silently measured the baseline twice and reported a
## difference of zero is the single most expensive failure this file can have.

const DEFAULT_RULES_PATH: String = "res://resources/rules/default_match_rules.tres"


## Load [param path] as a rules resource, or return null and say why.
static func load_rules(path: String) -> MatchRules:
	var rules: MatchRules = load(path) as MatchRules
	if rules == null:
		push_error("BotVariants could not load a MatchRules from %s" % path)
		return null
	# The .tres is one shared instance for the whole process. Every caller here
	# gets a private copy; nobody sweeps the file on disk by accident.
	return rules.duplicate() as MatchRules


## A single-arm sweep: the rules at [param path], unmodified.
static func single(path: String, variant_name: String) -> Array[BotVariant]:
	var rules: MatchRules = load_rules(path)
	if rules == null:
		return []
	var variant: BotVariant = BotVariant.new()
	variant.name = variant_name
	variant.notes = "rules loaded verbatim from %s" % path
	variant.rules = rules
	return [variant]


## Parse a spec file into arms. Returns an empty array and pushes an error if
## the file, the base rules, or any override cannot be honoured.
static func from_spec_file(path: String) -> Array[BotVariant]:
	var text: String = FileAccess.get_file_as_string(path)
	if text.is_empty():
		push_error("BotVariants could not read a sweep spec at %s" % path)
		return []

	var parsed: Variant = JSON.parse_string(text)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("BotVariants expected a JSON object at the root of %s" % path)
		return []

	var spec: Dictionary = parsed
	var base_path: String = String(spec.get("base_rules", DEFAULT_RULES_PATH))
	var entries: Array = spec.get("variants", [])
	if entries.is_empty():
		push_error("BotVariants found no \"variants\" array in %s" % path)
		return []

	var built: Array[BotVariant] = []
	for entry: Variant in entries:
		if typeof(entry) != TYPE_DICTIONARY:
			push_error("BotVariants expected every entry of \"variants\" to be an object")
			return []
		var variant: BotVariant = _build_one(entry, base_path)
		if variant == null:
			return []
		built.append(variant)
	return built


static func _build_one(entry: Dictionary, base_path: String) -> BotVariant:
	var rules: MatchRules = load_rules(String(entry.get("base_rules", base_path)))
	if rules == null:
		return null

	var variant: BotVariant = BotVariant.new()
	variant.name = String(entry.get("name", "variant"))
	variant.notes = String(entry.get("notes", ""))
	variant.rules = rules

	var overrides: Dictionary = entry.get("overrides", {})
	for key: Variant in overrides:
		var field: String = String(key)
		if not _has_field(rules, field):
			push_error(
				"BotVariants: variant \"%s\" overrides \"%s\", which MatchRules does not have."
				% [variant.name, field]
			)
			return null
		rules.set(field, _coerce(rules.get(field), overrides[key]))

	var problems: PackedStringArray = rules.validate()
	for problem: String in problems:
		push_warning("BotVariants: variant \"%s\": %s" % [variant.name, problem])
	return variant


static func _has_field(rules: MatchRules, field: String) -> bool:
	for entry: Dictionary in rules.get_property_list():
		if String(entry.get("name", "")) == field:
			return true
	return false


## Bring [param incoming] to the type [param current] already has.
##
## JSON has exactly one number type, so every integer rule -- prisoner_count,
## an enum, rounds_to_win_match -- arrives as a float, and a packed lane array
## arrives as a generic array. Converting explicitly rather than trusting
## [method Object.set] keeps a spec file honest about what it set.
static func _coerce(current: Variant, incoming: Variant) -> Variant:
	match typeof(current):
		TYPE_INT:
			return int(incoming)
		TYPE_FLOAT:
			return float(incoming)
		TYPE_BOOL:
			return bool(incoming)
		TYPE_STRING:
			return String(incoming)
		TYPE_PACKED_FLOAT32_ARRAY:
			var packed: PackedFloat32Array = PackedFloat32Array()
			var source: Array = incoming
			for number: Variant in source:
				packed.append(float(number))
			return packed
		_:
			return incoming
