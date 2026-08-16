class_name Prop
extends Node3D
## A thing in the level you can use: adopts one of the house's meshes at
## runtime, gives it a pivot to move about, an interact area for the ray, an
## optional body so it blocks, and a hover glow. Subclasses decide what a
## press does (HingedProp swings, SlidingProp slides, SwitchProp flicks).
##
## Tree after adopt():
##   Prop (this, at the pivot point, world-aligned, never moves)
##   └── Pivot (subclasses animate this)
##       ├── <adopted MeshInstance3D>
##       ├── Interact (PropInteract area, layer 4)
##       └── Body (optional AnimatableBody3D, layer 1)

signal toggled(open: bool)
signal used(by: Node3D)

const GLOW_COLOR := Color(1.0, 0.86, 0.55)
const GLOW_ENERGY := 0.16
const HOVER_IN := 0.25
const HOVER_OUT := 0.35

enum PivotMode { ORIGIN, CENTER, MIN_X, MAX_X, MIN_Z, MAX_Z, BOTTOM, TOP }

var mesh: MeshInstance3D
var pivot: Node3D
var area: PropInteract
var body: AnimatableBody3D
var is_open := false
var busy := false
## Where the world prompt hangs, in Pivot space. Defaults to the mesh centre.
var anchor_local := Vector3.ZERO
## Both languages, like interactable.gd: the setting decides which shows.
## Callers that only set the English pair still read sensibly in Arabic,
## because the fallback is the other language rather than an empty prompt.
var prompt_open := "Open"
var prompt_close := "Close"
var prompt_open_ar := "افتح"
var prompt_close_ar := "سكر"

var _aabb := AABB()
var _glow_mats: Array[StandardMaterial3D] = []
var _glow_tween: Tween
var _tween: Tween


## Must already be in the tree. `interact_pad` grows the ray box so thin
## things (a switch plate) are aimable.
func adopt(mi: MeshInstance3D, pivot_mode: PivotMode, interact_pad: Vector3, solid := false) -> void:
	mesh = mi
	_aabb = MeshUtil.world_aabb(mi)
	var c := _aabb.get_center()
	var p := c
	match pivot_mode:
		PivotMode.ORIGIN:
			p = mi.global_position
		PivotMode.MIN_X:
			p = Vector3(_aabb.position.x, c.y, c.z)
		PivotMode.MAX_X:
			p = Vector3(_aabb.end.x, c.y, c.z)
		PivotMode.MIN_Z:
			p = Vector3(c.x, c.y, _aabb.position.z)
		PivotMode.MAX_Z:
			p = Vector3(c.x, c.y, _aabb.end.z)
		PivotMode.BOTTOM:
			p = Vector3(c.x, _aabb.position.y, c.z)
		PivotMode.TOP:
			p = Vector3(c.x, _aabb.end.y, c.z)
		_:
			p = c
	global_position = p
	global_basis = Basis.IDENTITY

	pivot = Node3D.new()
	pivot.name = "Pivot"
	add_child(pivot)
	mi.reparent(pivot, true)

	area = PropInteract.new()
	area.name = "Interact"
	area.prop = self
	var acs := CollisionShape3D.new()
	var abox := BoxShape3D.new()
	abox.size = _aabb.size + interact_pad
	acs.shape = abox
	area.add_child(acs)
	pivot.add_child(area)
	area.global_position = c
	anchor_local = pivot.to_local(c)

	if solid:
		body = AnimatableBody3D.new()
		body.name = "Body"
		body.sync_to_physics = false
		body.collision_layer = 1
		body.collision_mask = 0
		var bcs := CollisionShape3D.new()
		var bbox := BoxShape3D.new()
		bbox.size = _aabb.size
		bcs.shape = bbox
		body.add_child(bcs)
		pivot.add_child(body)
		body.global_position = c

	_glow_mats = MeshUtil.make_glow_overrides(mi, GLOW_COLOR)


func get_prompt() -> String:
	if GameState.language == "ar":
		var ar: String = prompt_close_ar if is_open else prompt_open_ar
		if not ar.is_empty():
			return ar
	return prompt_close if is_open else prompt_open


func can_use() -> bool:
	return not busy and _can()


func set_glow(on: bool) -> void:
	if _glow_tween != null and _glow_tween.is_valid():
		_glow_tween.kill()
	_glow_tween = create_tween().set_parallel(true)
	for m in _glow_mats:
		_glow_tween.tween_property(m, "emission_energy_multiplier",
			GLOW_ENERGY if on else 0.0, HOVER_IN if on else HOVER_OUT)


## Starts a guarded tween: kills the previous one, marks busy. Subclasses
## append their steps and finish with `t.tween_callback(_done)`.
func _begin() -> Tween:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	busy = true
	_tween = create_tween()
	return _tween


func _done() -> void:
	busy = false


## Override: extra availability (a seat only lifts when the lid is up).
func _can() -> bool:
	return true


## Override: what a press does. Default toggles open/closed via _animate.
func _press(by: Node3D) -> void:
	used.emit(by)
	_animate(not is_open)


## Override: move the pivot to the open/closed pose. Must set is_open and
## emit toggled, and end with busy cleared (use _begin/_done).
func _animate(open: bool) -> void:
	is_open = open
	toggled.emit(open)


class PropInteract:
	extends "res://scripts/interactable.gd"

	var prop: Prop

	func get_prompt() -> String:
		return prop.get_prompt()

	func get_prompt_anchor() -> Vector3:
		return prop.pivot.to_global(prop.anchor_local)

	func _can_interact() -> bool:
		return prop.can_use()

	func _on_interact(by: Node3D) -> void:
		prop._press(by)

	func _on_focus(on: bool) -> void:
		prop.set_glow(on)
