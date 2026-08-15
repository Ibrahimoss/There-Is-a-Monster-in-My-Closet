class_name DoomFilter
extends CanvasLayer

## Full-screen Doom filter. Drop this node into a scene and everything the
## camera renders below it gets the 320x200 palette treatment.
##
## The palette LUT is baked by tools/doomify.py so the world and any sprites you
## run through that script come out of the same transform. Regenerate with:
##
##     python tools/doomify.py --emit-lut assets/doom_lut.png --lut-size 32

const FILTER_SHADER := preload("res://scripts/doom_filter.gdshader")
const DEFAULT_LUT := "res://assets/textures/doom_lut.png"

@export var lut: Texture2D
## Doom's framebuffer was 320x200. Higher keeps more detail and less crunch.
@export var virtual_resolution := Vector2i(320, 200)
@export var pixelate := true
## 0 = untouched, 1 = full Doom. Handy to tween for a flashback or a hit.
@export_range(0.0, 1.0) var amount := 1.0:
	set(value):
		amount = value
		_push("amount", value)
## COLORMAP-style darkening, applied before the palette snap.
@export_range(0.0, 1.0) var darkness := 0.0:
	set(value):
		darkness = value
		_push("darkness", value)
@export_range(0.0, 2.0) var dither := 0.6:
	set(value):
		dither = value
		_push("dither", value)

var _rect: ColorRect
var _mat: ShaderMaterial


func _ready() -> void:
	layer = 90  # under the wake-up overlay at 100, over the 3D view

	var texture := lut
	if texture == null:
		if not ResourceLoader.exists(DEFAULT_LUT):
			push_warning(
				"DoomFilter: no LUT at %s — run tools/doomify.py --emit-lut to bake one."
				% DEFAULT_LUT)
			return
		texture = load(DEFAULT_LUT)

	_mat = ShaderMaterial.new()
	_mat.shader = FILTER_SHADER
	_mat.set_shader_parameter("lut_tex", texture)
	_mat.set_shader_parameter("lut_size", float(texture.get_height()))
	_mat.set_shader_parameter("virtual_resolution", Vector2(virtual_resolution))
	_mat.set_shader_parameter("pixelate", pixelate)
	_mat.set_shader_parameter("amount", amount)
	_mat.set_shader_parameter("darkness", darkness)
	_mat.set_shader_parameter("dither", dither)

	_rect = ColorRect.new()
	_rect.name = "DoomFilterRect"
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.material = _mat
	add_child(_rect)


func _push(name: String, value: Variant) -> void:
	if _mat != null:
		_mat.set_shader_parameter(name, value)
