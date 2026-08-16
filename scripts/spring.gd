class_name Spring3
extends RefCounted
## Damped spring on a Vector3. Semi-implicit Euler, dt clamped so a hitch
## can't blow it up. zeta 1 = critically damped, below 1 overshoots a little.

var value := Vector3.ZERO
var vel := Vector3.ZERO
var target := Vector3.ZERO
var omega := 12.0
var zeta := 0.7


func _init(w := 12.0, z := 0.7) -> void:
	omega = w
	zeta = z


func step(delta: float) -> void:
	var dt := minf(delta, 1.0 / 30.0)
	vel += (-2.0 * zeta * omega * vel - omega * omega * (value - target)) * dt
	value += vel * dt


func kick(impulse: Vector3) -> void:
	vel += impulse


func reset(v := Vector3.ZERO) -> void:
	value = v
	vel = Vector3.ZERO
	target = v
