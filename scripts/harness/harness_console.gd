class_name HarnessConsole
extends RefCounted

## The console half of the harness: the header, the per-match line, the summary
## table and the totals.
##
## Split from [BotHarness] so that the two entry points under
## [code]tools/harness/[/code] are nothing but argument defaults and an exit
## code. What a run PRINTS is as much a part of an unattended tool as what it
## writes, and having one copy of it means a single match and a sweep report
## themselves in the same words.
##
## Everything printed here is also in the JSON. Nothing is computed for the
## console alone, so a number read off a terminal and a number read off a file
## cannot disagree.

## Build a harness, run [param variants] through it, print the report, and hand
## back the aggregate with an [code]unresolved_total[/code] the caller turns
## into an exit code. A coroutine: await it.
static func run_and_report(
	tree: SceneTree, variants: Array[BotVariant], options: Dictionary, title: String
) -> Dictionary:
	var matches: int = int(options.get("matches", 1))
	var seed_value: int = int(options.get("seed", BotHarness.DEFAULT_SEED))
	var max_seconds: float = float(options.get("max-seconds", BotHarness.DEFAULT_MAX_SIM_SECONDS))
	var compression: int = int(options.get("compression", BotHarness.DEFAULT_COMPRESSION))
	var out_dir: String = String(options.get("out", BotHarness.DEFAULT_OUT_DIR))

	print(title)
	print("  engine       %s" % String(Engine.get_version_info().get("string", "unknown")))
	print("  physics      %d Hz simulated, %dx compressed" % [BotHarness.SIM_HZ, compression])
	print("  variants     %d" % variants.size())
	print("  matches      %d per variant" % maxi(matches, 1))
	print("  seed         %d%s" % [seed_value, " (entropy)" if seed_value == 0 else ""])
	print("  ceiling      %.0f simulated seconds per match" % max_seconds)
	print("")

	var harness: BotHarness = BotHarness.new()
	harness.name = "BotHarness"
	tree.root.add_child(harness)
	harness.progress.connect(_on_progress)

	var report: Dictionary = await harness.run(
		variants, matches, seed_value, max_seconds, out_dir, compression
	)

	tree.root.remove_child(harness)
	harness.free()

	print("")
	_print_summary(report)
	return report


static func _on_progress(line: String) -> void:
	print(line)


static func _print_summary(report: Dictionary) -> void:
	var arms: Array = report.get("variants", [])
	var unresolved_total: int = int(report.get("unresolved_total", 0))
	var matches_total: int = int(report.get("matches_total", 0))

	print("%-14s %7s %7s %7s %9s %9s %8s %8s %9s" % [
		"variant", "matches", "resolv", "unresol", "sec med", "sec mean", "rounds", "seats", "hit rate",
	])
	for entry: Variant in arms:
		var arm: Dictionary = entry
		print("%-14s %7d %7d %7d %9.1f %9.1f %8.1f %8.1f %8.1f%%" % [
			String(arm.get("variant", "?")),
			int(arm.get("matches", 0)),
			int(arm.get("resolved", 0)),
			int(arm.get("unresolved", 0)),
			float(arm.get("seconds_median", 0.0)),
			float(arm.get("seconds_mean", 0.0)),
			float(arm.get("rounds_median", 0.0)),
			float(arm.get("seat_changes_median", 0.0)),
			float(arm.get("hit_rate", 0.0)) * 100.0,
		])

	var wall: float = float(report.get("wall_seconds", 0.0))
	print("")
	print("%s  %d matches, %d unresolved, %.1f s wall clock (%.2f s per match)" % [
		"CLEAN" if unresolved_total == 0 else "UNRESOLVED MATCHES PRESENT",
		matches_total,
		unresolved_total,
		wall,
		wall / float(maxi(matches_total, 1)),
	])
	print("results  %s" % String(report.get("output_directory", "")))
