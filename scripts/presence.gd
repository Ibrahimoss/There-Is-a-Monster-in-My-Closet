extends Node
## Runtime decoration of the level scene, autoloaded as `Presence`.
##
## The level scene (real_world.tscn) is edited by hand and stays plain: bare
## player node, door meshes with the Door script, lamps, dialogue triggers.
## Everything mechanical that does not need placing in the editor is attached
## here at runtime, by node name, once the player reports in from _ready:
## door registration, props (switches, drawers, lids, tap), later the rest.
##
## Feature flags below so any of it can be switched off from one place.
## Scripts are preloaded by path: autoloads parse before the global class
## cache exists on a fresh clone, so class names are not safe here.

const DoorScript := preload("res://scripts/door.gd")

const DECORATE_DOORS := true
const DECORATE_PROPS := true

var _player: CharacterBody3D
var _root: Node
var _doors: Array[MeshInstance3D] = []


## Called (deferred) by the player once it is in the tree, so the whole level
## is ready by the time this runs.
func on_player_ready(player: CharacterBody3D) -> void:
	_player = player
	# the level root: the player's scene owner in play, whatever holds it in tests
	_root = player.owner if player.owner != null else get_tree().current_scene
	if _root == null:
		return
	_doors.clear()
	if DECORATE_DOORS:
		_collect_doors(_root)


func get_doors() -> Array[MeshInstance3D]:
	return _doors


func get_player() -> CharacterBody3D:
	return _player


func _collect_doors(node: Node) -> void:
	if node is DoorScript:
		_doors.append(node as MeshInstance3D)
	for c in node.get_children():
		_collect_doors(c)
