class_name DialogueTrigger
extends Node

## Binds one game event to one dialogue sequence, editor-only, no code.
##
## Drop a Node in the scene per event, attach this script, then in the
## inspector: point source_path at the node that owns the event, type the
## signal's name, and write the lines. When that signal fires, the lines play.
##
## Example: source_path = the bathroom door, signal_name = "opened",
## lines = ["huh...", "did i leave that open?"].

## Node whose signal starts this dialogue.
@export var source_path: NodePath
## Signal on that node, e.g. "opened", "closed", "refused", "body_entered".
@export var signal_name := ""
## The lines, in order. One entry = one caption on screen.
@export var lines: PackedStringArray = []
## Fire once and never again (a first-time story beat) vs every time.
@export var once := true
## Seconds to wait after the event before the first line appears.
@export var delay := 0.0
## Path to the DialogueUI. Leave as-is if the scene uses the default layout.
@export var dialogue_path: NodePath = NodePath("/root/real world/DialogueLayer/dialouge ui")

var _fired := false


func _ready() -> void:
	if signal_name.is_empty():
		push_warning("DialogueTrigger '%s': no signal_name set." % name)
		return
	var source := get_node_or_null(source_path)
	if source == null:
		push_warning("DialogueTrigger '%s': nothing at '%s'." % [name, source_path])
		return
	if not source.has_signal(signal_name):
		push_warning("DialogueTrigger '%s': %s has no signal '%s'." %
			[name, source.name, signal_name])
		return
	# Swallow whatever args the signal carries (Area3D's body_entered passes a
	# body, Door's opened passes nothing) so any signal lands in _fire.
	var argc: int = source.get_signal_list().filter(
		func(s): return s.name == signal_name)[0].args.size()
	source.connect(signal_name, _fire if argc == 0 else _fire.unbind(argc))


func _fire() -> void:
	if _fired and once:
		return
	_fired = true
	var ui := get_node_or_null(dialogue_path)
	if ui == null or not ui.has_method("play"):
		push_warning("DialogueTrigger '%s': no DialogueUI at '%s'." % [name, dialogue_path])
		return
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	ui.play(Array(lines))
