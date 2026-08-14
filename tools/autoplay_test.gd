extends Node
## Headless soft-lock test: drives the whole scripted opening the way a player
## would (take toy → hide him → bed → covers → emerge → sleep) and reports
## whether the director's await chain reaches the nightmare fade. Run:
##   godot --headless --path . res://tools/AutoplayTest.tscn
## Prints AUTOPLAY OK / AUTOPLAY FAIL. Never shipped.

const TIMEOUT := 240.0

var _house: Node3D
var _director: Node = null
var _t := 0.0


func _ready() -> void:
	_house = (load("res://scenes/house/House.tscn") as PackedScene).instantiate() as Node3D
	add_child(_house)
	_watchdog()
	_drive()


func _watchdog() -> void:
	await get_tree().create_timer(TIMEOUT).timeout
	print("AUTOPLAY FAIL: timed out after %.0fs in act %d" % [TIMEOUT, GameState.current_act])
	get_tree().quit(1)


func _step(seconds: float) -> void:
	_t += seconds
	await get_tree().create_timer(seconds).timeout


func _wait_for(what: String, check: Callable, max_wait := 90.0) -> bool:
	var waited := 0.0
	while not bool(check.call()):
		await _step(0.2)
		waited += 0.2
		if waited > max_wait:
			print("AUTOPLAY FAIL: gave up waiting for %s (t=%.0fs)" % [what, _t])
			get_tree().quit(1)
			return false
	print("AUTOPLAY: %s (t=%.0fs)" % [what, _t])
	return true


func _drive() -> void:
	# NOTE: lambdas capture locals by value - anything a lambda writes must be
	# a member, hence _director.
	await _wait_for("director exists", func() -> bool:
		_director = _house.get_node_or_null("OpeningDirector")
		return _director != null)
	var player := get_tree().get_first_node_in_group("player") as CharacterBody3D

	# Act 0: wait for the toy to become takeable, then play through the beats.
	await _wait_for("take spot enabled", func() -> bool:
		return is_instance_valid(_director._take_spot) and _director._take_spot.enabled)
	_director._take_spot.interact(player)

	await _wait_for("put-back spots enabled", func() -> bool:
		return _director._putback_spots[1].enabled)
	await _step(1.0)  # putback during the hug tween on purpose, stress test
	_director._putback_spots[1].interact(player)

	await _wait_for("bed enabled", func() -> bool:
		return is_instance_valid(_director._bed) and _director._bed.enabled)
	_director._bed.interact(player)

	await _wait_for("player in bed", func() -> bool: return player.in_bed)
	await _wait_for("Act 1 started", func() -> bool:
		return GameState.current_act == GameState.Act.CLOSET)

	# Hide when asked (the director waits for under_covers after its lines).
	await _step(16.0)
	player.under_covers = true
	print("AUTOPLAY: hid under covers (t=%.0fs)" % _t)

	# Dad's whole visit plays out; wait for the pin to release, then emerge.
	await _wait_for("covers pinned", func() -> bool: return player.covers_locked, 30.0)
	await _wait_for("covers released", func() -> bool: return not player.covers_locked, 90.0)
	player.under_covers = false
	print("AUTOPLAY: emerged (t=%.0fs)" % _t)

	await _wait_for("sleep prompt enabled", func() -> bool:
		return is_instance_valid(_director._sleep) and _director._sleep.enabled, 30.0)
	_director._sleep.interact(player)

	await _wait_for("nightmare act reached", func() -> bool:
		return GameState.current_act == GameState.Act.NIGHTMARE, 30.0)

	assert(GameState.toy_location == GameState.ToySpot.UNDER_SINK)
	await _step(6.0)  # let the fade-out and ambience stop run
	print("AUTOPLAY OK: full opening completed in %.0fs, toy_location=%d, checkpoint=%s" % [
		_t, GameState.toy_location, GameState.get_checkpoint()
	])
	get_tree().quit(0)
