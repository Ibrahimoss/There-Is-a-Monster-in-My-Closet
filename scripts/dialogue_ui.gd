class_name DialogueUI
extends Control

## Timed caption dialogue. No input — lines type out, hold, fade, and the next
## one follows. Call play() with an Array of lines:
##
##     get_node("%DialogueUI").play([
##         "what was that noise?",
##         "it came from the closet...",
##     ])
##
## Calling play() while an event is on screen queues the new event after it.
## Lines can be plain Strings, or { "text": ..., "hold": seconds } dictionaries
## when one line needs to linger longer than the length-based default.

signal line_shown(text: String)
signal event_finished
## Emitted when the whole queue drains, not after each play() call.
signal all_finished

@export_group("Timing")
## Characters revealed per second. 0 shows each line instantly.
@export var chars_per_second := 28.0
## Every line stays at least this long (seconds), on top of the typing time.
@export var hold_base := 1.1
## Extra hold per character, so long lines get read, short ones don't drag.
@export var hold_per_char := 0.045
@export var fade_time := 0.35
## Quiet beat between one line and the next.
@export var line_gap := 0.25

var _queue: Array = []  # Array of events; an event is an Array of lines
var _label: Label
var _busy := false


func _ready() -> void:
	_label = $Text
	_label.modulate.a = 0.0
	# The mouse must fall through to the game, not die on a fullscreen Control.
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label.mouse_filter = Control.MOUSE_FILTER_IGNORE


## Queue an event: an Array of lines shown one after another.
func play(lines: Array) -> void:
	if lines.is_empty():
		return
	_queue.append(lines)
	if not _busy:
		_run()


func clear() -> void:
	_queue.clear()
	# Let the current line's await chain see the wipe and bail out.
	_busy = false
	_label.modulate.a = 0.0
	_label.text = ""


func _run() -> void:
	_busy = true
	while not _queue.is_empty():
		var event: Array = _queue.pop_front()
		for line in event:
			if not _busy:
				return  # clear() was called mid-event
			await _show_line(line)
		event_finished.emit()
	_busy = false
	all_finished.emit()


func _show_line(line: Variant) -> void:
	var text: String = line.get("text", "") if line is Dictionary else str(line)
	var hold_override: float = line.get("hold", -1.0) if line is Dictionary else -1.0

	_label.text = text
	line_shown.emit(text)

	# Type it out.
	if chars_per_second > 0.0:
		_label.visible_characters = 0
		_label.modulate.a = 1.0
		var count := _label.get_total_character_count()
		var shown := 0.0
		while shown < count:
			if not _busy:
				return
			shown += chars_per_second * get_process_delta_time()
			_label.visible_characters = int(shown)
			await get_tree().process_frame
		_label.visible_characters = -1
	else:
		_label.visible_characters = -1
		var tween_in := create_tween()
		tween_in.tween_property(_label, "modulate:a", 1.0, fade_time)
		await tween_in.finished

	var hold := hold_override if hold_override >= 0.0 \
		else hold_base + hold_per_char * text.length()
	await get_tree().create_timer(hold).timeout
	if not _busy:
		return

	var tween_out := create_tween()
	tween_out.tween_property(_label, "modulate:a", 0.0, fade_time)
	await tween_out.finished

	if line_gap > 0.0:
		await get_tree().create_timer(line_gap).timeout
