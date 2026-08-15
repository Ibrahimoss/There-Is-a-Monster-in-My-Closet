class_name StairGate
extends Node3D
## Child gate across the top of the stairs. Built from boxes at runtime with
## the banister's own wood material so it belongs to the house. Latched shut,
## the kid can't open it: interact rattles it.
##
## Spans world Z (posts at either end), faces along X. `length` is the gap it
## closes, `height` is a real stair gate, low enough that the kid sees over.

const HEIGHT := 0.82
const RAIL := 0.045
const SLAT := 0.028
const SLAT_GAP := 0.11
const PROMPT_AR := "مقفول"
const PROMPT_EN := "Locked"

var _length := 1.2
var _material: Material
var _frame: Node3D
var _area: GateInteract
var _shake_tween: Tween


func setup(length: float, material: Material) -> void:
	_length = length
	_material = material
	_frame = Node3D.new()
	_frame.name = "Frame"
	add_child(_frame)

	var half := length * 0.5
	# posts
	_box(Vector3(RAIL, HEIGHT, RAIL), Vector3(0.0, HEIGHT * 0.5, -half + RAIL * 0.5))
	_box(Vector3(RAIL, HEIGHT, RAIL), Vector3(0.0, HEIGHT * 0.5, half - RAIL * 0.5))
	# rails
	var span := length - RAIL * 2.0
	_box(Vector3(RAIL * 0.8, RAIL, span), Vector3(0.0, HEIGHT - RAIL * 0.5, 0.0))
	_box(Vector3(RAIL * 0.8, RAIL, span), Vector3(0.0, 0.10 + RAIL * 0.5, 0.0))
	# slats
	var slat_h := HEIGHT - RAIL - 0.10 - RAIL
	var count := int(floorf(span / (SLAT + SLAT_GAP)))
	var step := span / float(count)
	for i in count:
		var z := -span * 0.5 + step * (float(i) + 0.5)
		_box(Vector3(SLAT, slat_h, SLAT), Vector3(0.0, 0.10 + RAIL + slat_h * 0.5, z))
	# latch plate on the wall-side post
	_box(Vector3(RAIL * 1.4, 0.06, 0.05), Vector3(0.0, HEIGHT * 0.62, half - RAIL - 0.02))

	var body := StaticBody3D.new()
	body.name = "Body"
	body.collision_layer = 1
	body.collision_mask = 0
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(0.08, HEIGHT, length)
	cs.shape = box
	cs.position = Vector3(0.0, HEIGHT * 0.5, 0.0)
	body.add_child(cs)
	add_child(body)

	_area = GateInteract.new()
	_area.name = "Interact"
	_area.gate = self
	_area.prompt_ar = PROMPT_AR
	_area.prompt_en = PROMPT_EN
	var acs := CollisionShape3D.new()
	var abox := BoxShape3D.new()
	abox.size = Vector3(0.36, HEIGHT, length)
	acs.shape = abox
	acs.position = Vector3(0.0, HEIGHT * 0.5, 0.0)
	_area.add_child(acs)
	add_child(_area)


func _box(size: Vector3, pos: Vector3) -> void:
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	if _material:
		mi.material_override = _material
	mi.position = pos
	_frame.add_child(mi)


## Latched: a short rattle and the lock sound.
func rattle() -> void:
	AudioBus.sfx_at("door_locked", global_position, -8.0)
	if _shake_tween and _shake_tween.is_valid():
		_shake_tween.kill()
	_shake_tween = create_tween()
	var amp := deg_to_rad(1.6)
	_shake_tween.tween_property(_frame, "rotation:z", amp, 0.05)
	_shake_tween.tween_property(_frame, "rotation:z", -amp * 0.6, 0.06)
	_shake_tween.tween_property(_frame, "rotation:z", amp * 0.3, 0.05)
	_shake_tween.tween_property(_frame, "rotation:z", 0.0, 0.09)


class GateInteract:
	extends Interactable

	var gate: StairGate

	func _on_interact(_by: Node3D) -> void:
		gate.rattle()
