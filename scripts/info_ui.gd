extends Control

## On-screen key prompts.
##
## R icon    — shown while the player's interact ray is on something usable.
## WASD icons — shown once, at game start, if the player hasn't moved for
##              idle_time seconds; hides forever the moment they move.

@export var player_path: NodePath = NodePath("../../player")
## Seconds of standing still at game start before the movement hint appears.
@export var idle_time := 5.0
@export var fade_speed := 6.0

var _player: Node
var _r: TextureRect
var _wasd: Control

enum Hint { WAITING, SHOWING, DONE }
var _hint := Hint.WAITING
var _idle := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_r = $RPrompt
	_wasd = $WasdHint
	_r.modulate.a = 0.0
	_wasd.modulate.a = 0.0
	_player = get_node_or_null(player_path)
	if _player == null:
		push_warning("InfoUI: no player at '%s' — prompts disabled." % player_path)
		set_process(false)


func _process(delta: float) -> void:
	_update_r(delta)
	_update_wasd(delta)


func _update_r(delta: float) -> void:
	var show := false
	if not _player.cinematic and _player.ray != null:
		var target: Node = _player.ray.get_collider()
		while target != null and not target.has_method("interact"):
			target = target.get_parent()
		show = target != null
	_r.modulate.a = move_toward(_r.modulate.a, 1.0 if show else 0.0, fade_speed * delta)


func _update_wasd(delta: float) -> void:
	if _hint == Hint.DONE and _wasd.modulate.a <= 0.0:
		return

	var moved := Input.get_vector("move_left", "move_right", "move_forward", "move_back") != Vector2.ZERO

	match _hint:
		Hint.WAITING:
			if moved:
				_hint = Hint.DONE  # they found the keys on their own
			else:
				_idle += delta
				if _idle >= idle_time:
					_hint = Hint.SHOWING
		Hint.SHOWING:
			if moved:
				_hint = Hint.DONE

	var target := 1.0 if _hint == Hint.SHOWING else 0.0
	_wasd.modulate.a = move_toward(_wasd.modulate.a, target, fade_speed * delta)
