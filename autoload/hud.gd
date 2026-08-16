extends CanvasLayer
## Gameplay overlay, autoloaded as `HUD`: film grain, stamina vignette, the
## beam "seen" vignette, aim dot, interact prompt, caught flash.
##
## Hidden by default - gameplay scenes call `HUD.set_active(true)`; menu and
## cutscene scenes leave it off. Stamina has no bar anywhere: it is darkness
## closing in from the edges, plus the player's audible/visible breathing.
##
## Two layers: this one (9) sits under the Doom filter (90) so the vignettes
## and covers get crushed with the image; `_top` (96) carries the reticle and
## prompt above the filter so text stays readable, in the same font family as
## the captions (95).

const UiKit := preload("res://scripts/ui_kit.gd")
const DOOM_FONT := preload("res://assets/fonts/Amazdoomleft-epw3.ttf")
const TOP_LAYER := 96

## Soft permanent vignette. Grain is off: the Doom filter dithers already.
const GRAIN_SHADER := """
shader_type canvas_item;
uniform float grain_strength = 0.0;
uniform float vignette_strength = 0.22;
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

## World prompt: a small key icon + label projected onto the thing you are
## looking at. Eases in with a little scale, glides between targets, scales
## with distance, fades with depth.
const KEY_ICON := preload("res://assets/icons/keyboard_r.png")
const CAPTION := Color(1.0, 1.0, 0.93)
const WP_IN := 0.22
const WP_OUT := 0.12
const WP_FOLLOW := 24.0
const WP_NEAR := 1.35
const WP_SCALE_MIN := 0.85
const WP_SCALE_MAX := 1.2
const WP_FADE_FAR := 2.5
const WP_FADE_BAND := 0.6
const WP_OFFSET_Y := -18.0
const WP_MARGIN := 28.0

var _top: CanvasLayer
var _wp: Control
var _wp_box: HBoxContainer
var _wp_text: Label
var _wp_target: Node = null
var _wp_pos := Vector2.ZERO
var _wp_alpha := 0.0
var _wp_scale := 1.0
var _wp_tween: Tween
var _wp_text_tween: Tween
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
	# after the player's _process, so the projected prompt does not trail a
	# frame behind the camera and swim on turns
	process_priority = 100
	visible = false

	_top = CanvasLayer.new()
	_top.name = "Top"
	_top.layer = TOP_LAYER
	_top.visible = false
	add_child(_top)

	_grain = _shader_rect(GRAIN_SHADER)
	_stamina_rect = _shader_rect(STAMINA_SHADER)
	_stamina_mat = _stamina_rect.material
	_seen_rect = _shader_rect(SEEN_SHADER)
	_seen_mat = _seen_rect.material
	_covers_rect = _shader_rect(COVERS_SHADER)
	_covers_mat = _covers_rect.material
	_build_reticle()
	_build_world_prompt()
	_build_flash()


func _process(delta: float) -> void:
	_update_world_prompt(delta)


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
	_top.add_child(dot_center)

	_dot = ColorRect.new()
	_dot.custom_minimum_size = Vector2(3, 3)
	_dot.color = DOT_IDLE
	_dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	dot_center.add_child(_dot)

	# Key hint + prompt, hanging just below centre. Doom face, caption outline.
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top.add_child(center)

	var box := VBoxContainer.new()
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 3)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	center.add_child(box)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 64)
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(spacer)

	_key_hint = _doom_label("R", 18, UiKit.WARM)
	_key_hint.visible = false
	box.add_child(_key_hint)

	_prompt = _doom_label("", 26, Color(1.0, 1.0, 0.93))
	_prompt.visible = false
	box.add_child(_prompt)


static func _doom_label(text: String, size: int, color: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", DOOM_FONT)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0.09, 0.055, 0.03, 1.0))
	l.add_theme_constant_override("outline_size", 8)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l


func _build_flash() -> void:
	_flash = ColorRect.new()
	_flash.set_anchors_preset(Control.PRESET_FULL_RECT)
	_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_flash.color = Color(1, 1, 1, 0)
	add_child(_flash)


func _build_world_prompt() -> void:
	_wp = Control.new()
	_wp.name = "WorldPrompt"
	_wp.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wp.modulate.a = 0.0
	_wp.visible = false
	_top.add_child(_wp)

	_wp_box = HBoxContainer.new()
	_wp_box.add_theme_constant_override("separation", 8)
	_wp_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wp.add_child(_wp_box)

	var icon := TextureRect.new()
	icon.texture = KEY_ICON
	icon.custom_minimum_size = Vector2(30, 30)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_wp_box.add_child(icon)

	_wp_text = _doom_label("", 26, CAPTION)
	_wp_text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_wp_box.add_child(_wp_text)


## The thing under the reticle changed. null clears. Same target with a new
## prompt (Open -> Close) just re-reads the text with a small dip.
func set_world_target(t: Node) -> void:
	if t == _wp_target:
		if t != null:
			_retext(_prompt_of(t))
		return
	var had := _wp_target != null and _wp_alpha > 0.05
	_wp_target = t
	_dot.color = DOT_ACTIVE if t != null else DOT_IDLE
	if t == null:
		_wp_tween_out()
		return
	_wp_text.text = _prompt_of(t)
	_wp_box.reset_size()
	if not had:
		# first appearance snaps to the anchor, target switches glide
		_wp_pos = _project(t)
	_wp_tween_in()


func _prompt_of(t: Node) -> String:
	if t.has_method("get_prompt"):
		return String(t.call("get_prompt"))
	return "Use"


func _retext(text: String) -> void:
	if _wp_text.text == text:
		return
	_wp_text.text = text
	_wp_box.reset_size()
	if _wp_text_tween != null and _wp_text_tween.is_valid():
		_wp_text_tween.kill()
	_wp_text.modulate.a = 0.45
	_wp_text_tween = create_tween()
	_wp_text_tween.tween_property(_wp_text, "modulate:a", 1.0, 0.14)


func _wp_tween_in() -> void:
	if _wp_tween != null and _wp_tween.is_valid():
		_wp_tween.kill()
	_wp.visible = true
	_wp_scale = 0.86
	_wp_tween = create_tween().set_parallel(true)
	_wp_tween.tween_property(self, "_wp_alpha", 1.0, WP_IN).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_wp_tween.tween_property(self, "_wp_scale", 1.0, WP_IN).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


func _wp_tween_out() -> void:
	if _wp_tween != null and _wp_tween.is_valid():
		_wp_tween.kill()
	_wp_tween = create_tween()
	_wp_tween.tween_property(self, "_wp_alpha", 0.0, WP_OUT)


func _project(t: Node) -> Vector2:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return _wp_pos
	var wpos: Vector3 = t.call("get_prompt_anchor") if t.has_method("get_prompt_anchor") \
		else (t as Node3D).global_position if t is Node3D else cam.global_position + cam.global_basis * Vector3(0, 0, -1.5)
	return cam.unproject_position(wpos)


func _update_world_prompt(delta: float) -> void:
	if _wp_target != null and not is_instance_valid(_wp_target):
		_wp_target = null
		_wp_tween_out()
	if _wp_target == null:
		_wp.modulate.a = _wp_alpha
		if _wp_alpha <= 0.01:
			_wp.visible = false
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var wpos: Vector3 = _wp_target.call("get_prompt_anchor") if _wp_target.has_method("get_prompt_anchor") \
		else (_wp_target as Node3D).global_position if _wp_target is Node3D else cam.global_position
	if cam.is_position_behind(wpos):
		_wp.visible = false
		return
	_wp.visible = true
	var sp := cam.unproject_position(wpos)
	var vr := get_viewport().get_visible_rect()
	sp = sp.clamp(vr.position + Vector2(WP_MARGIN, WP_MARGIN), vr.end - Vector2(WP_MARGIN, WP_MARGIN))
	_wp_pos = _wp_pos.lerp(sp, 1.0 - exp(-WP_FOLLOW * delta))
	var dist := cam.global_position.distance_to(wpos)
	var s := clampf(WP_NEAR / maxf(dist, 0.5), WP_SCALE_MIN, WP_SCALE_MAX)
	var depth_a := clampf((WP_FADE_FAR - dist) / WP_FADE_BAND, 0.45, 1.0)
	var size := _wp_box.size
	_wp.pivot_offset = size * 0.5
	_wp.size = size
	_wp.position = _wp_pos - Vector2(size.x * 0.5, size.y) + Vector2(0.0, WP_OFFSET_Y)
	_wp.scale = Vector2.ONE * s * _wp_scale
	_wp.modulate.a = _wp_alpha * depth_a


## Gameplay scenes turn the HUD on; menus turn it off.
func set_active(active: bool) -> void:
	visible = active
	_top.visible = active
	if not active:
		clear()


func show_prompt(text: String, key := "R") -> void:
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
