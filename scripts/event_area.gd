class_name EventArea
extends Area3D

## An invisible box that fires `triggered` when the player walks into it.
##
## To make a new walk-in event: add an Area3D, attach this script, give it a
## BoxShape3D child sized to the spot, then point a DialogueTrigger at it with
## signal_name = "triggered". Filters to the player, so a wandering monster
## (or a physics prop) passing through stays silent.

signal triggered

## Fire once per game vs every time the player walks in.
@export var once := true

var _fired := false


func _ready() -> void:
	body_entered.connect(_on_body)


func _on_body(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	if _fired and once:
		return
	_fired = true
	triggered.emit()
