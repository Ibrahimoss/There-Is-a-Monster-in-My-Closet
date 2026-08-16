class_name Interactable
extends Area3D
## Base for everything the player can look at and press interact on.
##
## Lives on its own physics layer (INTERACTABLE) so the player's interact ray
## can target interactables without also hitting walls, and so interactables
## never block movement.
##
## Prompt hooks used by the world prompt: get_prompt(), get_prompt_anchor()
## (where the label sits, world space), set_focused() (hover in/out).

signal interacted(by: Node3D)
signal focus_changed(on: bool)

## Physics layer 3. Keep in sync with the player's interact ray mask.
const LAYER := 4

@export var prompt_ar := "تفاعل"
@export var prompt_en := "Interact"
## Disabled interactables drop off the ray layer entirely. The ray stops at the
## first shape it meets, so an inert box left on the layer would still eat the
## ray and hide whatever sits behind it.
@export var enabled := true: set = _set_enabled
## Interactables that should only ever fire once (picking up the toy, opening
## the panel). Saves every subclass reimplementing the same guard.
@export var one_shot := false
## Where the world prompt hangs, local to this node.
@export var prompt_anchor_offset := Vector3.ZERO

var _used := false
var _focused := false


func _ready() -> void:
	collision_layer = LAYER if enabled else 0
	collision_mask = 0  # Detected by raycast only; detects nothing itself.
	monitoring = false


func _set_enabled(value: bool) -> void:
	enabled = value
	collision_layer = LAYER if (value and not (one_shot and _used)) else 0


func can_interact() -> bool:
	if not enabled:
		return false
	if one_shot and _used:
		return false
	return _can_interact()


func interact(by: Node3D) -> void:
	if not can_interact():
		return
	_used = true
	if one_shot:
		collision_layer = 0
	interacted.emit(by)
	_on_interact(by)


func get_prompt() -> String:
	return prompt_ar if GameState.language == "ar" else prompt_en


func get_prompt_anchor() -> Vector3:
	return to_global(prompt_anchor_offset)


func set_focused(on: bool) -> void:
	if _focused == on:
		return
	_focused = on
	focus_changed.emit(on)
	_on_focus(on)


func is_focused() -> bool:
	return _focused


## Override: extra availability rules (act gating, "only once the light is on").
func _can_interact() -> bool:
	return true


## Override: what this thing actually does.
func _on_interact(_by: Node3D) -> void:
	pass


## Override: hover in/out response (a glow, a nudge).
func _on_focus(_on: bool) -> void:
	pass
