extends SceneTree
var _s: Node
var _p: Node3D
var _dir: Node
var _zone: Area3D
var _t := 0.0
var _did := {}
func _initialize() -> void:
	root.add_child(load("res://real_world_ibra_mod.tscn").instantiate())
func _process(d: float) -> bool:
	_t += d
	if _s == null:
		_s = root.get_child(root.get_child_count() - 1)
		_p = _s.get_node("player"); _dir = _s.get_node("act1")
		_zone = _s.get_node_or_null("act1/GravityFlipZone")
		print("A) zone node found: %s  at %s  monitoring=%s (must be false)" % [
			_zone != null, _zone.global_position.snapped(Vector3.ONE*0.01) if _zone else "-",
			_zone.monitoring if _zone else "-"])
		return false
	if _t > 1.0 and not _did.has("early"):
		_did["early"] = true
		_p.teleport_to(_zone.global_position)   # blunder through it during act 0
	elif _t > 2.6 and not _did.has("check1"):
		_did["check1"] = true
		print("B) walked through during act 0: flipped=%s fired=%s (both must be false)" % [
			_dir._flipped, _zone.get("_fired")])
		_p.enter_bed(Vector3(7.05, 4.42, -11.85), 180.0)
	elif _t > 5.0 and not _did.has("arm"):
		_did["arm"] = true
		root.get_node("/root/GameState").set_act(1)
	elif _t > 12.0 and not _did.has("up"):
		_did["up"] = true
		Input.action_press("interact")
	elif _t > 12.3 and not _did.has("rel"):
		_did["rel"] = true
		Input.action_release("interact")
	elif _t > 15.2 and not _did.has("armed"):
		_did["armed"] = true
		print("C) after get-up: zone monitoring=%s (must be true)" % _zone.monitoring)
		_p.teleport_to(_zone.global_position)
	elif _t > 17.4 and not _did.has("done"):
		_did["done"] = true
		print("D) walked through in act 1: flipped=%s  y=%.2f" % [_dir._flipped, _p.global_position.y])
		quit()
	return false
