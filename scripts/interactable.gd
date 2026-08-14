class_name Interactable
extends Area3D
## Base for everything the player can look at and press interact on.
##
## Lives on its own physics layer (INTERACTABLE) so the player's interact ray
## can target interactables without also hitting walls, and so interactables
## never block movement.

signal interacted(by: Node3D)

## Physics layer 3. Keep in sync with the player's interact ray mask.
const LAYER := 4

@export var prompt_ar := "تفاعل"
@export var prompt_en := "Interact"
@export var enabled := true
## Interactables that should only ever fire once (picking up the toy, opening
## the panel). Saves every subclass reimplementing the same guard.
@export var one_shot := false

var _used := false


func _ready() -> void:
	collision_layer = LAYER
	collision_mask = 0  # Detected by raycast only; detects nothing itself.
	monitoring = false


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
	interacted.emit(by)
	_on_interact(by)


func get_prompt() -> String:
	return prompt_ar if GameState.language == "ar" else prompt_en


## Override: extra availability rules (act gating, "only once the light is on").
func _can_interact() -> bool:
	return true


## Override: what this thing actually does.
func _on_interact(_by: Node3D) -> void:
	pass
