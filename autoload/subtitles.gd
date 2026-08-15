extends CanvasLayer
## Bilingual subtitle display, autoloaded as `Subtitles`.
##
## Speaker and text are separate fields on purpose - see scripts/dialogue.gd.
## Arabic is primary (larger, on top); English is a smaller, dimmer gloss.
##
## The UI is built in code rather than in a .tscn deliberately: two people are
## working this repo and Godot rewrites node IDs on every scene save, so the
## fewer shared .tscn files exist, the fewer merge conflicts happen.

## Preloaded rather than referenced by its `class_name`. Autoloads are parsed
## before Godot's global class cache exists, so on a fresh clone (where
## `.godot/` is gitignored) `Dialogue` is not yet a known identifier and the
## autoload fails to load. Preloading resolves by path and always works.
const DialogueData := preload("res://scripts/dialogue.gd")

const ARABIC_FONT_PATH := "res://assets/fonts/NotoNaskhArabic.ttf"

const AR_SIZE := 34
const EN_SIZE := 20
const SPEAKER_SIZE := 22

var _root: MarginContainer
var _speaker: Label
var _arabic: Label
var _english: Label
var _tween: Tween
var _font: Font
var _serial := 0


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	_load_font()
	_build_ui()
	_root.modulate.a = 0.0
	GameState.language_changed.connect(_on_language_changed)


func _load_font() -> void:
	if ResourceLoader.exists(ARABIC_FONT_PATH):
		_font = load(ARABIC_FONT_PATH)
	else:
		# Godot's built-in font has no Arabic glyphs at all - every Arabic line
		# renders as boxes. Loud warning so this cannot ship unnoticed.
		push_warning(
			"Subtitles: no Arabic font at %s - Arabic text will render as tofu."
			% ARABIC_FONT_PATH
		)


func _build_ui() -> void:
	_root = MarginContainer.new()
	_root.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	# set_anchors_preset does not touch grow direction. Anchored to the bottom
	# edge with the default (grow down) the whole box sits below the screen.
	_root.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_root.add_theme_constant_override("margin_bottom", 72)
	_root.add_theme_constant_override("margin_left", 48)
	_root.add_theme_constant_override("margin_right", 48)
	_root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_root)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_END
	box.add_theme_constant_override("separation", 2)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(box)

	_speaker = _make_label(SPEAKER_SIZE, Color(0.75, 0.75, 0.78))
	_arabic = _make_label(AR_SIZE, Color(0.95, 0.95, 0.95))
	_english = _make_label(EN_SIZE, Color(0.68, 0.68, 0.70))
	box.add_child(_speaker)
	box.add_child(_arabic)
	box.add_child(_english)


func _make_label(size: int, color: Color) -> Label:
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# AUTO lets TextServer pick RTL for Arabic and LTR for English per-label,
	# so the two lines lay out correctly without us tracking language here.
	label.text_direction = Control.TEXT_DIRECTION_AUTO
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", color)
	# Readable over a bright hallway light gap as well as over black.
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	label.add_theme_constant_override("outline_size", 6)
	if _font:
		label.add_theme_font_override("font", _font)
	return label


## Show a line from scripts/dialogue.gd. Both languages are always rendered;
## the language setting only decides which one is primary.
func show_line(id: String, duration := 3.0) -> void:
	if not DialogueData.has_line(id):
		push_warning("Subtitles: unknown line id '%s'" % id)
		return

	var style: int = DialogueData.get_style(id)
	var ar: String = DialogueData.get_text(id, "ar")
	var en: String = DialogueData.get_text(id, "en")
	var speaker_ar: String = DialogueData.get_speaker(id, "ar")
	var speaker_en: String = DialogueData.get_speaker(id, "en")

	# The label carries the whole payoff at the bathroom door, so it is shown
	# in both languages together rather than following the language toggle.
	if speaker_ar.is_empty() and speaker_en.is_empty():
		_speaker.text = ""
		_speaker.visible = false
	else:
		_speaker.text = "%s / %s" % [speaker_ar, speaker_en]
		_speaker.visible = true

	_arabic.text = ar
	_english.text = en

	var italic: bool = style == DialogueData.Style.KID
	_arabic.add_theme_color_override(
		"font_color", Color(0.80, 0.80, 0.86) if italic else Color(0.95, 0.95, 0.95)
	)

	_fade(1.0, 0.25)
	if duration > 0.0:
		# Serial token: if another line starts while this one's timer is
		# pending, the stale timer must not hide the newer line.
		_serial += 1
		var token := _serial
		await get_tree().create_timer(duration).timeout
		if token == _serial:
			hide_line()


func hide_line() -> void:
	_serial += 1  # also invalidates any pending auto-hide
	_fade(0.0, 0.4)


func _fade(target: float, time: float) -> void:
	if _tween and _tween.is_valid():
		_tween.kill()
	_tween = create_tween()
	_tween.tween_property(_root, "modulate:a", target, time)


func _on_language_changed(_lang: String) -> void:
	pass  # Both languages are always visible; nothing to swap.
