extends TestCase

## Every word a player reads comes out of locale/strings.csv.
##
## The audit in tools/audit_i18n.gd is the instrument; these tests read its
## report so the suite and the audit can never disagree. The pseudo-locale
## (en_XA: bracketed, accented, a third longer) is the layout check: force it
## through the dev setting and anything that clips is visible at once.

const Audit: GDScript = preload("res://tools/audit_i18n.gd")

var _report: Dictionary = {}
var _locale_before: String = ""


func before_each() -> void:
	_report = Audit.scan()
	_locale_before = TranslationServer.get_locale()


func after_each() -> void:
	TranslationServer.set_locale(_locale_before)


func test_the_table_reads() -> void:
	assert_false(bool(_report["broken"]), "strings.csv is readable and has an en column")
	assert_gt(float(_report["table"].size()), 100.0, "and holds the game's words, not a stub")


func test_every_referenced_key_is_in_the_table() -> void:
	var missing: Array = _report["missing"]
	assert_true(missing.is_empty(), "keys used but not in strings.csv: %s" % ", ".join(missing))


func test_every_table_key_is_referenced() -> void:
	var unused: Array = _report["unused"]
	assert_true(unused.is_empty(), "keys in strings.csv nothing uses: %s" % ", ".join(unused))


func test_ui_scenes_carry_no_raw_text() -> void:
	var raw: Array = _report["raw"]
	var lines: PackedStringArray = PackedStringArray()
	for row: Dictionary in raw:
		lines.append("%s:%d %s" % [row["path"], row["line"], row["text"]])
	assert_true(raw.is_empty(), "authored text that is not a key: %s" % "; ".join(lines))


func test_every_key_has_pseudo_text() -> void:
	var bare: Array = _report["no_pseudo"]
	assert_true(
		bare.is_empty(),
		"keys with no en_XA cell (run audit_i18n.gd -- --fill-pseudo): %s" % ", ".join(bare),
	)


## The loaded translations are the two the table declares, English being the
## fallback for any locale the game does not have.
func test_both_locales_are_loaded() -> void:
	var loaded: PackedStringArray = TranslationServer.get_loaded_locales()
	assert_true(loaded.has("en"), "English is loaded; got %s" % [loaded])
	assert_true(loaded.has("en_XA"), "the pseudo-locale is loaded; got %s" % [loaded])
	TranslationServer.set_locale("fr")
	assert_eq_string(TranslationServer.translate("MENU_PLAY"), "Play", "an unknown locale falls back to English")


func test_switching_locale_changes_a_label() -> void:
	var label: Label = Label.new()
	label.text = "MENU_PLAY"
	add_child(label)
	TranslationServer.set_locale("en")
	label.notification(Node.NOTIFICATION_TRANSLATION_CHANGED)
	var english: String = label.atr(label.text)
	var english_width: float = label.get_minimum_size().x
	assert_eq_string(english, "Play", "in English the key reads as the word")

	TranslationServer.set_locale("en_XA")
	label.notification(Node.NOTIFICATION_TRANSLATION_CHANGED)
	var pseudo: String = label.atr(label.text)
	assert_true(pseudo != english, "the pseudo-locale changes what the label shows")
	assert_true(pseudo.begins_with("[") and pseudo.ends_with("]"), "and brackets it: %s" % pseudo)
	assert_gt(label.get_minimum_size().x, english_width, "and the label grows, which is the point")
	assert_eq_string(label.text, "MENU_PLAY", "while the authored text stays the key")
	label.queue_free()


## Script-built strings go through tr() and format(), so a value keeps its
## place inside the translated sentence.
func test_formatted_strings_keep_their_values_under_the_pseudo_locale() -> void:
	TranslationServer.set_locale("en_XA")
	var text: String = TranslationServer.translate("HUD_ROUND").format({"round": 7})
	assert_true(text.contains("7"), "the number survives: %s" % text)
	assert_false(text.contains("{round}"), "and the placeholder does not: %s" % text)


func test_the_dev_setting_forces_the_locale() -> void:
	var settings: GameSettings = GameSettings.new()
	settings.locale = "en_XA"
	settings.clamp_all()
	assert_eq_string(settings.locale, "en_XA", "a loaded locale is kept")
	settings.apply_locale()
	assert_eq_string(TranslationServer.get_locale(), "en_XA", "and applied")

	settings.locale = "xx_NOWHERE"
	settings.clamp_all()
	assert_eq_string(settings.locale, "", "a locale the game does not have is dropped")
	settings.apply_locale()
	assert_true(TranslationServer.get_locale() != "en_XA", "and the system locale is back")
