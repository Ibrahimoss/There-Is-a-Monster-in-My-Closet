extends Node

## Faint fluorescent buzz on every bulkhead fixture.
##
## One looping AudioStreamPlayer3D per light, found by node name so new
## fixtures pick it up automatically. Godot attenuates by distance, so the
## buzz simply rises as the kid walks under a light and fades as he leaves —
## no proximity checks per frame.

const BUZZ := preload("res://assets/audio/light_buzz.mp3")

## Fixtures whose name starts with any of these get a buzz.
@export var name_prefixes: PackedStringArray = ["bulk head", "Bulkhead"]
## Where to search. Empty means this node's parent (drop it under act1).
@export var search_root: NodePath
## Present rather than faint — the sewer should sound electrical.
@export_range(-60.0, 0.0, 0.5, "suffix:dB") var volume_db := -20.0
## Metres. Past this the buzz is silent, so lights don't bleed room to room.
@export var max_distance := 9.0
## Where it starts falling off. Larger carries the buzz further before it dies.
@export var unit_size := 3.0
## Small per-light pitch drift so three fixtures don't phase into one tone.
@export var pitch_jitter := 0.05

@export_group("Flicker")
## Bad fluorescent: mostly steady, then a burst of stutter. Off keeps them lit.
@export var flicker := true
## Seconds between stutter bursts, per fixture, picked randomly in this range.
@export var calm_min := 1.4
@export var calm_max := 6.5
## How long a burst lasts.
@export var burst_min := 0.12
@export var burst_max := 0.55
## Energy floor during a stutter, as a fraction of the fixture's own energy.
@export_range(0.0, 1.0) var dim_to := 0.08

var count := 0

# per light: [light, base_energy, next_change, is_dim, burst_until]
var _flickers: Array = []

# Something whose presence kills nearby lights (dad). Lights inside the
# radius fall to nothing and come back when it moves on.
var _dark_source: Node3D
var _dark_radius := 0.0
var _dark_fade := 5.0


## Point this at dad once he shows up. Pass null to give the lights back.
func set_dark_source(node: Node3D, radius: float, fade := 5.0) -> void:
	_dark_source = node
	_dark_radius = radius
	_dark_fade = fade
	if node != null:
		set_process(true)


func _ready() -> void:
	var root: Node = get_node_or_null(search_root) if search_root != NodePath() else get_parent()
	if root == null:
		push_warning("LightBuzz: nothing to search.")
		return

	for node in _fixtures(root):
		_add_buzz(node)
		if flicker:
			_arm_flicker(node)
	set_process(flicker and not _flickers.is_empty())


## One entry per light in the fixture, each on its own clock so six tubes
## never stutter in unison.
func _arm_flicker(fixture: Node3D) -> void:
	for child in fixture.get_children():
		if child is Light3D:
			var light := child as Light3D
			_flickers.append([light, light.light_energy,
				randf_range(0.0, calm_max), false, 0.0])


func _process(dt: float) -> void:
	var now := float(Time.get_ticks_msec()) / 1000.0
	var dark_valid: bool = _dark_source != null and is_instance_valid(_dark_source)
	for f in _flickers:
		var light: Light3D = f[0]
		if not is_instance_valid(light):
			continue

		# whatever is stalking the tunnel takes the lights with it
		if dark_valid:
			var near: bool = light.global_position.distance_to(
				_dark_source.global_position) <= _dark_radius
			if near:
				light.light_energy = move_toward(light.light_energy, 0.0, _dark_fade * dt)
				continue
			if light.light_energy < f[1]:
				# it has moved off; the tube stutters back to life
				light.light_energy = move_toward(light.light_energy, f[1], _dark_fade * 0.6 * dt)
				f[2] = now + randf_range(0.2, 0.8)
				continue

		if now < f[2]:
			continue
		if f[3]:
			# inside a burst: snap between dim and full every few frames
			light.light_energy = f[1] * (dim_to if randf() < 0.55 else 1.0)
			f[2] = now + randf_range(0.02, 0.09)
			if now >= f[4]:
				f[3] = false
				light.light_energy = f[1]
				f[2] = now + randf_range(calm_min, calm_max)
		else:
			f[3] = true
			f[4] = now + randf_range(burst_min, burst_max)
			f[2] = now


func _fixtures(root: Node) -> Array[Node3D]:
	var out: Array[Node3D] = []
	for child in root.get_children():
		if child is Node3D:
			for prefix in name_prefixes:
				if String(child.name).begins_with(prefix):
					out.append(child)
					break
	return out


func _add_buzz(fixture: Node3D) -> void:
	var player := AudioStreamPlayer3D.new()
	player.stream = BUZZ
	player.volume_db = volume_db
	player.unit_size = unit_size
	player.max_distance = max_distance
	player.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	# start each fixture at a different point in the loop, or they beat together
	fixture.add_child(player)
	player.play(randf() * maxf(BUZZ.get_length() - 0.1, 0.1))
	count += 1
