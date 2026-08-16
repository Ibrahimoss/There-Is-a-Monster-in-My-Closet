class_name Toy
extends Node3D
## The kid's bear (CC-BY, see assets/ATTRIBUTION.md). Scaled at runtime to
## plush size with its feet at this node's origin, so you place it where it
## stands. Face is local +Z.

const MODEL := preload("res://assets/toy/bear.glb")
const DISSOLVE_SHADER := preload("res://scripts/dissolve.gdshader")
## Plush size. The house is at 2.5m-door scale so keep him small.
const HEIGHT := 0.35
const GLOW_COLOR := Color(1.0, 0.86, 0.55)
const GLOW_ENERGY := 0.2

var _model: Node3D
var _meshes: Array[MeshInstance3D] = []
var _glow_mats: Array[StandardMaterial3D] = []
var _glow_tween: Tween
var _hop_tween: Tween
var _burn_mats: Array[ShaderMaterial] = []
var _burn := 0.0


func _ready() -> void:
	_model = MODEL.instantiate() as Node3D
	add_child(_model)
	_collect_meshes(_model, _meshes)
	if _meshes.is_empty():
		push_warning("Toy: bear.glb has no meshes")
		return
	var world := MeshUtil.world_aabb(_meshes[0])
	for i in range(1, _meshes.size()):
		world = world.merge(MeshUtil.world_aabb(_meshes[i]))
	var s := HEIGHT / maxf(world.size.y, 0.001)
	_model.scale *= s
	# Centred in x and z, feet on the origin. The measurement is in world axes
	# and `_model.position` is local, so it has to come back through this node's
	# own basis first: the toy is turned to face the room, and without the turn
	# the correction lands on the wrong side and doubles the offset it was meant
	# to remove - which is what had the bear standing beside its plinth rather
	# than on it.
	var off := world.get_center() - global_position
	off.y = world.position.y - global_position.y
	_model.position -= global_transform.basis.orthonormalized().inverse() * off * s


## Hover glow, same recipe as doors.
func set_glow(on: bool) -> void:
	if _glow_mats.is_empty():
		for mi in _meshes:
			_glow_mats.append_array(MeshUtil.make_glow_overrides(mi, GLOW_COLOR))
	if _glow_tween != null and _glow_tween.is_valid():
		_glow_tween.kill()
	_glow_tween = create_tween().set_parallel(true)
	for m in _glow_mats:
		_glow_tween.tween_property(m, "emission_energy_multiplier",
			GLOW_ENERGY if on else 0.0, 0.25 if on else 0.35)


## A little jump on the spot when noticed or picked up.
func hop(height := 0.02) -> void:
	if _hop_tween != null and _hop_tween.is_valid():
		_hop_tween.kill()
	var base := _model.position
	_hop_tween = create_tween()
	_hop_tween.tween_property(_model, "position:y", base.y + height, 0.12) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_hop_tween.tween_property(_model, "position:y", base.y, 0.16) \
		.set_trans(Tween.TRANS_BOUNCE).set_ease(Tween.EASE_OUT)


func get_meshes() -> Array[MeshInstance3D]:
	return _meshes


## 0 whole, 1 gone. The burn materials are built on the first call above zero,
## copying whatever the glb shipped so the fur still reads while it goes.
func set_dissolve(amount: float) -> void:
	var a := clampf(amount, 0.0, 1.0)
	if _burn_mats.is_empty():
		if a <= 0.0:
			return
		_build_burn()
	_burn = a
	for m in _burn_mats:
		m.set_shader_parameter("threshold", a)


func get_dissolve() -> float:
	return _burn


func _build_burn() -> void:
	for mi in _meshes:
		if mi.mesh == null:
			continue
		for s in mi.mesh.get_surface_count():
			var src := mi.get_active_material(s) as StandardMaterial3D
			var sm := ShaderMaterial.new()
			sm.shader = DISSOLVE_SHADER
			if src != null:
				if src.albedo_texture != null:
					sm.set_shader_parameter("albedo_tex", src.albedo_texture)
					sm.set_shader_parameter("has_tex", true)
				sm.set_shader_parameter("tint", src.albedo_color)
			sm.set_shader_parameter("threshold", 0.0)
			mi.set_surface_override_material(s, sm)
			_burn_mats.append(sm)


static func _collect_meshes(node: Node, out: Array[MeshInstance3D]) -> void:
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		_collect_meshes(child, out)
