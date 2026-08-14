extends RefCounted
## Shared UI palette, font and widget styling, so every screen draws from the
## same visual language instead of Godot's grey defaults.
##
## No `class_name` on purpose - autoloads preload this by path before the
## global class cache exists on a fresh clone. Use:
##   const UiKit := preload("res://scripts/ui_kit.gd")

const FONT_PATH := "res://assets/fonts/NotoNaskhArabic.ttf"

## Off-white text on near-black, one warm accent. Warm tone matches the
## hallway light under the door so the menu uses the game's own colors.
const INK := Color(0.92, 0.91, 0.95)
const INK_DIM := Color(0.56, 0.55, 0.62)
const INK_FAINT := Color(0.37, 0.37, 0.44)
const WARM := Color(0.93, 0.78, 0.52)
const PANEL := Color(0.055, 0.055, 0.075)

static var _font: Font


static func font() -> Font:
	if _font == null and ResourceLoader.exists(FONT_PATH):
		_font = load(FONT_PATH)
	return _font


static func apply_font(c: Control) -> void:
	var f := font()
	if f:
		c.add_theme_font_override("font", f)


static func make_label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.text_direction = Control.TEXT_DIRECTION_AUTO
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	apply_font(l)
	return l


static func style_button(b: Button, accent := false) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = PANEL
	normal.set_border_width_all(1)
	normal.border_color = Color(0.30, 0.29, 0.36)
	normal.set_corner_radius_all(2)
	normal.set_content_margin_all(10)

	var hover: StyleBoxFlat = normal.duplicate()
	hover.border_color = WARM
	hover.bg_color = Color(0.085, 0.080, 0.100)

	var pressed: StyleBoxFlat = hover.duplicate()
	pressed.bg_color = Color(0.030, 0.030, 0.045)

	b.add_theme_stylebox_override("normal", normal)
	b.add_theme_stylebox_override("hover", hover)
	b.add_theme_stylebox_override("pressed", pressed)
	b.add_theme_stylebox_override("focus", hover)
	b.add_theme_color_override("font_color", INK if accent else INK_DIM)
	b.add_theme_color_override("font_hover_color", WARM)
	b.add_theme_color_override("font_pressed_color", WARM)
	b.add_theme_color_override("font_focus_color", INK)
	apply_font(b)
