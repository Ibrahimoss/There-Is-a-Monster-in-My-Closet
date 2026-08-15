extends Control
## Title screen and web gesture gate.
##
## Composition, not centering: title block upper-left, menu stack lower-left,
## and the game's opening image - a door open a crack, warm light and dust -
## on the right third. Background parallaxes a few pixels with the mouse; the
## menu items slide on hover; everything enters and leaves through black.
##
## The click requirement is structural on web (pointer lock + audio both need
## a user gesture), so the whole screen is built around the one thing the
## player must do anyway.

const UiKit := preload("res://scripts/ui_kit.gd")

const GAME_SCENE := "res://scenes/house/House.tscn"

const BG_SHADER := """
shader_type canvas_item;
uniform vec2 parallax = vec2(0.0);

float hash1(float n) {
	return fract(sin(n * 12.9898) * 43758.5453);
}

void fragment() {
	vec2 uv = UV + parallax;
	vec3 col = vec3(0.008, 0.008, 0.014);

	// The door gap: a warm seam on the right third, taller than the screen.
	float slit_x = 0.68;
	float x = abs(uv.x - slit_x);
	float flick = 0.87
		+ 0.06 * sin(TIME * 3.1)
		+ 0.04 * sin(TIME * 7.7 + 1.7)
		+ 0.025 * sin(TIME * 17.0);
	vec3 warm = vec3(1.0, 0.80, 0.52);
	float core = smoothstep(0.0035, 0.0, x);
	float glow = exp(-x * x * 420.0) * 0.17;
	float vertical = smoothstep(1.05, 0.15, abs(uv.y - 0.5) * 1.7);
	col += warm * (core * 0.9 + glow) * vertical * flick;

	// Spill pooling on the floor at the base of the seam.
	float floor_spill = exp(-x * x * 55.0) * smoothstep(0.55, 1.0, uv.y) * 0.055;
	col += warm * floor_spill * flick;

	// Dust motes drifting up the shaft. Seven is plenty.
	for (int i = 0; i < 7; i++) {
		float fi = float(i);
		float speed = 0.010 + 0.008 * hash1(fi * 3.7);
		float py = fract(hash1(fi * 1.3) + TIME * speed);
		float wander = sin(TIME * (0.3 + hash1(fi * 5.1) * 0.4) + fi * 2.2);
		float px = slit_x + (hash1(fi * 7.7) - 0.5) * 0.045 + wander * 0.008;
		float md = distance(uv, vec2(px, 1.0 - py));
		float mote = exp(-md * md * 140000.0);
		col += warm * mote * 0.30 * flick * sin(py * 3.14159);
	}

	// Film grain.
	float g = fract(sin(dot(uv * 1400.0 + TIME * 37.0, vec2(12.9898, 78.233))) * 43758.5453);
	col += (g - 0.5) * 0.04;

	// Vignette, weighted low-centre so the title corner stays darkest.
	float d = distance(uv, vec2(0.46, 0.52));
	col *= 1.0 - smoothstep(0.32, 1.0, d) * 0.75;

	COLOR = vec4(col, 1.0);
}
"""

var _bg_mat: ShaderMaterial
var _begin: Button
var _ar_btn: Button
var _en_btn: Button
var _starting := false


func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	HUD.set_active(false)
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_build_bg()
	_build_title_block()
	_build_menu_stack()
	_build_footer()
	_refresh_langs()
	Fade.fade_in(1.4)

	var pulse := create_tween().set_loops()
	pulse.tween_property(_begin, "modulate:a", 0.75, 1.7) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(_begin, "modulate:a", 1.0, 1.7) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)


func _process(_delta: float) -> void:
	# A few pixels of parallax makes the background a place, not a poster.
	var vp := get_viewport_rect().size
	if vp.x > 0.0 and vp.y > 0.0:
		var m := get_viewport().get_mouse_position()
		var off := (m / vp - Vector2(0.5, 0.5)) * 0.014
		_bg_mat.set_shader_parameter("parallax", off)


func _build_bg() -> void:
	var bg := ColorRect.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var shader := Shader.new()
	shader.code = BG_SHADER
	_bg_mat = ShaderMaterial.new()
	_bg_mat.shader = shader
	bg.material = _bg_mat
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bg)


func _build_title_block() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_TOP_LEFT)
	margin.add_theme_constant_override("margin_left", 84)
	margin.add_theme_constant_override("margin_top", 96)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(box)

	var title := UiKit.make_label("في وحش في دولابي", 58, UiKit.INK)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	title.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	title.add_theme_constant_override("outline_size", 10)
	box.add_child(title)

	# English subtitle, letterspaced small caps under the Arabic.
	var sub := Label.new()
	sub.text = "THERE IS A MONSTER IN MY CLOSET"
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	sub.add_theme_font_size_override("font_size", 14)
	sub.add_theme_color_override("font_color", UiKit.INK_DIM)
	var fv := FontVariation.new()
	if UiKit.font():
		fv.base_font = UiKit.font()
	fv.spacing_glyph = 4
	sub.add_theme_font_override("font", fv)
	box.add_child(sub)

	var rule_pad := Control.new()
	rule_pad.custom_minimum_size = Vector2(0, 10)
	box.add_child(rule_pad)

	var rule := ColorRect.new()
	rule.color = Color(UiKit.WARM.r, UiKit.WARM.g, UiKit.WARM.b, 0.55)
	rule.custom_minimum_size = Vector2(150, 1)
	rule.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	box.add_child(rule)


func _build_menu_stack() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	margin.grow_vertical = Control.GROW_DIRECTION_BEGIN
	margin.add_theme_constant_override("margin_left", 84)
	margin.add_theme_constant_override("margin_bottom", 84)
	add_child(margin)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 16)
	margin.add_child(box)

	_begin = _menu_item("ابدأ  ·  Begin", 26, true)
	_begin.pressed.connect(_on_begin)
	box.add_child(_wrap_hover(_begin))

	# Language, inline: a dim label and two flat toggles.
	var langs := HBoxContainer.new()
	langs.add_theme_constant_override("separation", 14)
	box.add_child(langs)

	var lang_label := UiKit.make_label("اللغة", 16, UiKit.INK_FAINT)
	langs.add_child(lang_label)

	_ar_btn = _menu_item("عربي", 16, false)
	_ar_btn.pressed.connect(_set_lang.bind("ar"))
	langs.add_child(_ar_btn)

	_en_btn = _menu_item("English", 16, false)
	_en_btn.pressed.connect(_set_lang.bind("en"))
	langs.add_child(_en_btn)

	var hint_pad := Control.new()
	hint_pad.custom_minimum_size = Vector2(0, 6)
	box.add_child(hint_pad)

	# Controls, once, here. Nothing in the game itself explains keys beyond
	# the prompt that appears when a thing can be used.
	var keys := VBoxContainer.new()
	keys.add_theme_constant_override("separation", 1)
	box.add_child(keys)
	for line: String in [
		"WASD حركة  ·  F تفاعل  ·  Shift ركض  ·  Space اختباء",
		"WASD move  ·  F use  ·  Shift run  ·  Space hide",
	]:
		var l := UiKit.make_label(line, 12, UiKit.INK_FAINT)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		keys.add_child(l)

	box.add_child(UiKit.make_label(
		"يُفضَّل استخدام السماعات · headphones recommended", 12, UiKit.INK_FAINT
	))


func _build_footer() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	margin.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	margin.grow_vertical = Control.GROW_DIRECTION_BEGIN
	margin.add_theme_constant_override("margin_right", 28)
	margin.add_theme_constant_override("margin_bottom", 22)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	margin.add_child(UiKit.make_label(
		"Game Zanga 14 · أحلام", 12, UiKit.INK_FAINT
	))


## Flat text menu item - no boxes. Hover turns it warm; the wrapper slides it.
func _menu_item(text: String, size: int, primary: bool) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", size)
	b.add_theme_color_override("font_color", UiKit.INK if primary else UiKit.INK_DIM)
	b.add_theme_color_override("font_hover_color", UiKit.WARM)
	b.add_theme_color_override("font_pressed_color", UiKit.WARM)
	b.add_theme_color_override("font_focus_color", UiKit.INK)
	UiKit.apply_font(b)
	return b


## Wraps a menu item so hover slides it right a few pixels.
func _wrap_hover(btn: Button) -> Control:
	var row := HBoxContainer.new()
	var pad := Control.new()
	pad.custom_minimum_size = Vector2(0, 0)
	row.add_child(pad)
	row.add_child(btn)
	btn.mouse_entered.connect(_slide.bind(pad, 12.0))
	btn.mouse_exited.connect(_slide.bind(pad, 0.0))
	return row


func _slide(pad: Control, to: float) -> void:
	var t := create_tween()
	t.tween_property(pad, "custom_minimum_size:x", to, 0.16) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _set_lang(lang: String) -> void:
	GameState.set_language(lang)
	_refresh_langs()


func _refresh_langs() -> void:
	var active := GameState.language
	_ar_btn.add_theme_color_override(
		"font_color", UiKit.WARM if active == "ar" else UiKit.INK_DIM
	)
	_en_btn.add_theme_color_override(
		"font_color", UiKit.WARM if active == "en" else UiKit.INK_DIM
	)


func _on_begin() -> void:
	if _starting:
		return
	_starting = true
	# Unlock and capture INSIDE the gesture handler - after any await the
	# browser no longer counts this as a user gesture.
	AudioBus.unlock()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	GameState.reset()
	await Fade.fade_out(0.7)
	get_tree().change_scene_to_file(GAME_SCENE)
