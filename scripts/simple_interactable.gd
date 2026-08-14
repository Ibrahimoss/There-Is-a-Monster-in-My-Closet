class_name SimpleInteractable
extends Interactable
## A code-built interact spot: one box shape and the base class's prompts.
## Everything scripted (the toy, hiding spots, the bed) is one of these.


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
