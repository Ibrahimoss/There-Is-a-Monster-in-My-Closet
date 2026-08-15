extends Node
signal monster_seen          # declare at the top of any script

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	monster_seen.emit.call_deferred()
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass
