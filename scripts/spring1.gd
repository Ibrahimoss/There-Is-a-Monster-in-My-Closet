class_name Spring1
extends RefCounted
## Damped spring on a float. Same model as Spring3.

var value := 0.0
var vel := 0.0
var target := 0.0
var omega := 12.0
var zeta := 0.7


func _init(w := 12.0, z := 0.7) -> void:
	omega = w
	zeta = z


func step(delta: float) -> void:
	var dt := minf(delta, 1.0 / 30.0)
	vel += (-2.0 * zeta * omega * vel - omega * omega * (value - target)) * dt
	value += vel * dt


func kick(impulse: float) -> void:
	vel += impulse


func reset(v := 0.0) -> void:
	value = v
	vel = 0.0
	target = v
