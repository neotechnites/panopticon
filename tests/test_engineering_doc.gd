extends TestCase

## The engineering standard has to exist, and it has to stay one page.
##
## [code]docs/ENGINEERING.md[/code] is required reading in [code]CLAUDE.md[/code],
## so a standard nobody finishes is a standard nobody follows. A page is what an
## agent reads before its first edit; three pages is what it skims. The gate is
## the length, because length is the only part of "still readable" a test can
## measure.
##
## Written at 698 words. The ceiling is 900 -- room for a real addition, not for
## the drift that turns a standard back into a review.

const DOC_PATH: String = "res://docs/ENGINEERING.md"

## One page, with headroom. See the class docs for why this is the gate.
const MAX_WORDS: int = 900

## Sections the standard is not the standard without.
const REQUIRED_HEADINGS: Array[String] = [
	"## Invariants", "## Hot paths", "## Done", "## Modelling", "## Content",
]


func test_the_standard_exists_and_is_one_page() -> void:
	var file: FileAccess = FileAccess.open(DOC_PATH, FileAccess.READ)
	if not assert_not_null(file, "%s must exist -- CLAUDE.md sends every agent to it" % DOC_PATH):
		return
	var text: String = file.get_as_text()
	file.close()

	assert_gt(float(text.length()), 0.0, "%s must not be empty" % DOC_PATH)

	# Whitespace-separated tokens, which is what `wc -w` counts, so the number in
	# a report and the number this gate sees are the same number.
	var flat: String = text.replace("\n", " ").replace("\r", " ").replace("\t", " ")
	var words: int = 0
	for word: String in flat.split(" ", false):
		if not word.is_empty():
			words += 1
	assert_le(
		float(words),
		float(MAX_WORDS),
		"%s is %d words; the ceiling is %d so it stays one page" % [DOC_PATH, words, MAX_WORDS],
	)

	for heading: String in REQUIRED_HEADINGS:
		assert_true(text.contains(heading), "%s must keep the section \"%s\"" % [DOC_PATH, heading])
