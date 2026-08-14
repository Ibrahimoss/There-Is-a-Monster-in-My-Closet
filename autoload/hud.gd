extends CanvasLayer
## Gameplay overlay, autoloaded as `HUD`: film grain, stamina vignette, the
## beam "seen" vignette, aim dot, interact prompt, caught flash.
##
## Hidden by default - gameplay scenes call `HUD.set_active(true)`; menu and
## cutscene scenes leave it off. Stamina has no bar anywhere: it is darkness
## closing in from the edges, plus the player's audible/visible breathing.
##
## Draw order (bottom → top): grain, stamina, seen, reticle/prompt, flash.

const UiKit := preload("res://scripts/ui_kit.gd")

## Constant film grain + a soft permanent vignette, cheap way to not look
## like raw engine output.
const GRAIN_SHADER := """
shader_type canvas_item;
uniform float grain_strength = 0.06;
uniform float vignette_strength = 0.26;
void fragment() {
	float g = fract(sin(dot(
		UV * vec2(1687.0, 921.0) + vec2(TIME * 61.7, TIME * 41.3),
		vec2(12.9898, 78.233))) * 43758.5453);
	float d = length(UV - vec2(0.5)) * 1.4142;
	float v = smoothstep(0.55, 1.15, d) * vignette_strength;
	float a = clamp(v + (g - 0.5) * grain_strength, 0.0, 1.0);
	COLOR = vec4(0.0, 0.0, 0.0, a);
}
"""

## Stamina: black edges that close in as it empties, with a slow pulse while
## exhausted.
const STAMINA_SHADER := """
shader_type canvas_item;
uniform float amount = 0.0;
uniform float pulse = 0.0;
void fragment() {
	float d = length(UV - vec2(0.5)) * 1.4142;
	float inner = 0.42 - amount * 0.22;
	float v = smoothstep(inner, 1.08 - amount * 0.30, d);
	float breathe = 1.0 + pulse * 0.35 * sin(TIME * 6.2831 * 1.35);
	float a = v * amount * 0.62 * breathe;
	COLOR = vec4(0.0, 0.0, 0.0, clamp(a, 0.0, 0.88));
}
"""

## Beam detection: white bleeding in from the edges as the light finds you.
const SEEN_SHADER := """
shader_type canvas_item;
uniform float amount = 0.0;
void fragment() {
	float d = length(UV - vec2(0.5)) * 1.4142;
	float v = smoothstep(0.15, 1.0, d);
	COLOR = vec4(1.0, 1.0, 1.0, v * amount);
}
"""

## Blanket mask for under-covers. Rises from the bottom and leaves a soft
## slit near the top, mostly dark but light changes still read through the
## gap. Edge moves slowly so it feels like cloth.
const COVERS_SHADER := """
shader_type canvas_item;
uniform float amount = 0.0;
void fragment() {
	float wave = 0.015 * sin(UV.x * 21.0 + TIME * 0.6)
		+ 0.010 * sin(UV.x * 47.0 - TIME * 0.35);
	float breathe = 0.008 * sin(TIME * 2.2);
	float edge = 1.0 - amount * 0.94 + (wave + breathe) * amount;
	float a = smoothstep(edge - 0.025, edge + 0.07, UV.y) * 0.985;
	float d = abs(UV.x - 0.5) * 2.0;
	a = max(a, amount * smoothstep(0.55, 1.05, d) * 0.9);
	COLOR = vec4(0.012, 0.010, 0.008, a * clamp(amount * 3.0, 0.0, 1.0));
}
"""

const DOT_IDLE := Color(1, 1, 1, 0.16)
const DOT_ACTIVE := Color(0.93, 0.78, 0.52, 0.9)

var _grain: ColorRect
var _stamina_rect: ColorRect
var _stamina_mat: ShaderMaterial
var _seen_rect: ColorRect
var _seen_mat: ShaderMaterial
var _covers_rect: ColorRect
var _covers_mat: ShaderMaterial
var _covers_amount := 0.0
var _covers_tween: Tween
var _dot: ColorRect
var _key_hint: Label
var _prompt: Label
var _prompt_tween: Tween
var _flash: ColorRect
var _flash_tween: Tween


func _ready() -> void:
	layer = 9
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false

	_grain = _shader_rect(GRAIN_SHADER)
	_stamina_rect = _shader_rect(STAMINA_SHADER)
	_stamina_mat = _stamina_rect.material
	_seen_rect = _shader_rect(SEEN_SHADER)
	_seen_mat = _seen_rect.material
	_covers_rect = _shader_rect(COVERS_SHADER)
	_covers_mat = _covers_rect.material
	_build_reticle()
	_build_flash()


func _shader_rect(code: String) -> ColorRect:
	var shader := Shader.new()
	shader.code = code
	var mat := ShaderMaterial.new()
	mat.shader = shader
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = mat
	rect.color = Color.WHITE
	add_child(rect)
	return rect


func _build_reticle() -> void:
	# A 3px dot, barely there until something is interactable, then warm.
	var dot_center := CenterContainer.new()
	dot_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	dot_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dot_center)

	_dot = ColorRect.new()
	_dot.custom_minimum_size = Vector2(3, 3)
	_dot.color = DOT_IDLE
	_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot_center.add_child(_dot)

	# Key hint + localized prompt, hanging just below centre.
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 3)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(box)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 64)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(spacer)

	_key_hint = UiKit.make_label("F", 13, UiKit.WARM)
	_key_hint.visible = false
	box.add_child(_key_hint)

	_prompt = UiKit.make_label("", 19, UiKit.INK)
	_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_prompt.add_theme_constant_override("outline_size", 6)
	_prompt.visible = false
	box.add_child(_prompt)


func _build_flash() -> void:
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(1, 1, 1, 0)
	add_child(_flash)


## Gameplay scenes turn the HUD on; menus turn it off.
func set_active(active: bool) -> void:
	visible = active
	if not active:
		clear()


func show_prompt(text: String, key := "F") -> void:
	if text.is_empty():
		hide_prompt()
		return
	var changed := _prompt.text != text or not _prompt.visible
	_prompt.text = text
	_key_hint.text = key
	_prompt.visible = true
	_key_hint.visible = true
	_dot.color = DOT_ACTIVE
	if changed:
		# small fade-in when the prompt text changes so it reads as feedback
		if _prompt_tween and _prompt_tween.is_valid():
			_prompt_tween.kill()
		_prompt.modulate = Color(1, 1, 1, 0.35)
		_prompt_tween = create_tween()
		_prompt_tween.tween_property(_prompt, "modulate", Color.WHITE, 0.16)


func hide_prompt() -> void:
	_prompt.visible = false
	_key_hint.visible = false
	_dot.color = DOT_IDLE


## Driven every physics frame by the player. 1.0 = full stamina.
func set_stamina(normalized: float, exhausted: bool) -> void:
	_stamina_mat.set_shader_parameter("amount", clampf(1.0 - normalized, 0.0, 1.0))
	_stamina_mat.set_shader_parameter("pulse", 1.0 if exhausted else 0.0)


## 0 = unseen, 1 = caught. Driven every frame by the beam system.
func set_seen(amount: float) -> void:
	_seen_mat.set_shader_parameter("amount", clampf(amount, 0.0, 1.0))


## 0 = out in the room, 1 = fully under the blanket.
func set_covers(amount: float) -> void:
	_covers_amount = clampf(amount, 0.0, 1.0)
	_covers_mat.set_shader_parameter("amount", _covers_amount)


func tween_covers(target: float, duration := 0.4) -> void:
	if _covers_tween and _covers_tween.is_valid():
		_covers_tween.kill()
	_covers_tween = create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_covers_tween.tween_method(set_covers, _covers_amount, clampf(target, 0.0, 1.0), duration)


## The caught sting. White, loud, and over quickly - being caught should cost
## a few seconds, never a restart.
func flash_white(hold := 0.12, fade := 0.5) -> void:
	if _flash_tween and _flash_tween.is_valid():
		_flash_tween.kill()
	_flash.color = Color(1, 1, 1, 1)
	_flash_tween = create_tween()
	_flash_tween.tween_interval(hold)
	_flash_tween.tween_property(_flash, "color:a", 0.0, fade)


func clear() -> void:
	hide_prompt()
	set_seen(0.0)
	set_stamina(1.0, false)
	set_covers(0.0)
	_flash.color = Color(1, 1, 1, 0)
