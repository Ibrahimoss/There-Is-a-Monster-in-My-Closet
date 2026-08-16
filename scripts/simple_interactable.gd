class_name SimpleInteractable
extends Interactable
## A code-built interact spot: one box shape and the base class's prompts.
## Anything scripted (a toy, a hiding spot, a bed) is one of these. Point
## `focus_target` at a node with set_glow(on) and it lights up on hover.

var focus_target: Node3D


static func create(size: Vector3, ar: String, en: String, once := false) -> SimpleInteractable:
	var it := SimpleInteractable.new()
	it.prompt_ar = ar
	it.prompt_en = en
	it.one_shot = once
	var cs := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	cs.shape = box
	it.add_child(cs)
	return it


func _on_focus(on: bool) -> void:
	if focus_target != null and is_instance_valid(focus_target) and focus_target.has_method("set_glow"):
		focus_target.call("set_glow", on)
