class_name Door
extends Node3D
## A doorway made functional at runtime by adopting one of the house model's
## door panel meshes.
##
## house.fbx ships every panel already closed in its frame, as a static mesh
## whose node origin sits exactly on the hinge edge. So a working door is:
## put a world-aligned hinge node at that origin, reparent the panel under it,
## give it a collider and an interact area, and rotate the hinge about world Y.
## The panel's own (FBX-rotated) axes are never touched.
##
## Tree after setup():
##   Door (this - at the hinge pivot, world-aligned, never rotates)
##   ├── Hinge (rotates about Y - swing lives here)
##   │   ├── <adopted panel MeshInstance3D>
##   │   ├── Body (AnimatableBody3D + box - blocks the player)
##   │   └── Interact (DoorInteract area - thicker than the body so the
##   │                 interact ray meets it before the panel's collider)
##   └── Spill nodes (optional under-door light rig; static, does not swing)

signal opened
signal closed

const OPEN_DUR := 1.2
const CLOSE_DUR := 1.0
## Interact box thickness. Must exceed the panel body (~0.07 m) by enough that
## the ray always hits the area first.
const INTERACT_THICKNESS := 0.35
const SPILL_COLOR := Color(1.0, 0.78, 0.50)

## A locked door only ever rattles. Dad's bedroom stays this way forever.
var locked := false
## The script may drive this door, but the player's interact is refused -
## optionally with a subtitle line (the closet: the kid will not open it).
var script_locked := false
var blocked_line := ""
var open_deg := 90.0
## +1 / -1: which way around world Y the panel swings open.
var swing := -1.0

var _hinge: Node3D
var _panel: MeshInstance3D
var _body: AnimatableBody3D
var _area: DoorInteract
var _spill_sliver: MeshInstance3D
var _spill_light: OmniLight3D
var _spill_side := Vector3.ZERO
var _spill_energy := 0.7
var _spill_color := SPILL_COLOR
var _spill_enabled := false

var _closed_aabb := AABB()
## World axis the closed panel is thin along, and hinge -> panel centre.
var _normal := Vector3(0, 0, 1)
var _hinge_to_center := Vector3(1, 0, 0)
var _open := false
var _animating := false
## Resting angle in degrees when "closed" - nonzero while standing ajar.
var _base_deg := 0.0
## Direction the current/last open used (+1/-1). Player opens pick this per
## press so the panel swings away from them; the director uses `swing`.
var _open_dir := -1.0
var _tween: Tween


## Adopts `panel` (must be inside the tree). The Door node itself must also be
## in the tree before calling this.
func setup(panel: MeshInstance3D) -> void:
	_panel = panel
	global_position = panel.global_position
	global_basis = Basis.IDENTITY

	_hinge = Node3D.new()
	_hinge.name = "Hinge"
	add_child(_hinge)
	panel.reparent(_hinge, true)

	_closed_aabb = _world_aabb(panel)
	_normal = Vector3(0, 0, 1) if _closed_aabb.size.z < _closed_aabb.size.x else Vector3(1, 0, 0)
	_hinge_to_center = _closed_aabb.get_center() - global_position
	_hinge_to_center.y = 0.0

	_body = AnimatableBody3D.new()
	_body.name = "Body"
	# sync_to_physics only forwards the body's OWN local transform changes to the
	# physics server. This body never moves locally, its parent (the hinge) does,
	# so with sync on the collider stays at the closed pose forever and no door
	# can be walked through. Off, CollisionObject3D pushes the global transform
	# whenever the hinge rotates, which is what a scripted door needs.
	_body.sync_to_physics = false
	_body.collision_layer = 1
	_body.collision_mask = 0
	var body_shape := CollisionShape3D.new()
	var body_box := BoxShape3D.new()
	body_box.size = _closed_aabb.size
	body_shape.shape = body_box
	_body.add_child(body_shape)
	_hinge.add_child(_body)
	_body.global_position = _closed_aabb.get_center()

	_area = DoorInteract.new()
	_area.name = "Interact"
	_area.door = self
	var area_shape := CollisionShape3D.new()
	var area_box := BoxShape3D.new()
	var area_size := _closed_aabb.size
	# Fatten the thin (thickness) axis; trim height a touch off the floor.
	if area_size.x < area_size.z:
		area_size.x = INTERACT_THICKNESS
	else:
		area_size.z = INTERACT_THICKNESS
	area_size.y = maxf(area_size.y - 0.15, 0.5)
	area_box.size = area_size
	area_shape.shape = area_box
	_area.add_child(area_shape)
	_hinge.add_child(_area)
	_area.global_position = _closed_aabb.get_center() + Vector3(0.0, 0.05, 0.0)


## Optional under-door light rig. `side` is the world direction pointing into
## the room that sees the glow. Fakes what shadowless lights cannot do: light
## that reads as leaking under a *closed* door (sliver) and flooding through an
## *open* one (the light alone). `color` defaults to household warm, the
## closet uses a cold one.
func add_spill(side: Vector3, energy := 0.7, color := SPILL_COLOR) -> void:
	_spill_side = side.normalized()
	_spill_energy = energy
	_spill_color = color

	var width_axis := Vector3(0, 0, 1) if _closed_aabb.size.x < _closed_aabb.size.z \
		else Vector3(1, 0, 0)
	var width := absf(_closed_aabb.size.dot(width_axis))
	var center := _closed_aabb.get_center()
	var floor_y := _closed_aabb.position.y

	_spill_sliver = MeshInstance3D.new()
	_spill_sliver.name = "SpillSliver"
	var box := BoxMesh.new()
	box.size = width_axis * (width - 0.08) + Vector3(0.012, 0.012, 0.012) \
		+ _spill_side.abs() * 0.10
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = _spill_color
	box.material = mat
	_spill_sliver.mesh = box
	add_child(_spill_sliver)
	_spill_sliver.global_position = Vector3(center.x, floor_y + 0.012, center.z) \
		+ _spill_side * 0.06

	_spill_light = OmniLight3D.new()
	_spill_light.name = "SpillLight"
	_spill_light.light_color = _spill_color
	# Wide enough that the floor pool leads the eye even when the door itself
	# is occluded by an intervening doorway.
	_spill_light.omni_range = 2.8
	_spill_light.omni_attenuation = 1.8
	_spill_light.shadow_enabled = false
	add_child(_spill_light)
	_spill_light.global_position = Vector3(center.x, floor_y + 0.3, center.z) \
		+ _spill_side * 0.45

	_update_spill()


func set_spill(on: bool) -> void:
	_spill_enabled = on
	_update_spill()


func is_open() -> bool:
	return _open


## `dir` +1/-1 overrides the configured swing for this open (player opens pass
## the side they are on so the panel never sweeps through them). 0 = `swing`.
func open(duration := OPEN_DUR, dir := 0.0) -> void:
	if _open or _animating:
		return
	_animating = true
	_open_dir = swing if dir == 0.0 else signf(dir)
	AudioBus.sfx_at("door_open", global_position, -4.0)
	_update_spill()
	_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(_hinge, "rotation:y", deg_to_rad(open_deg * _open_dir), duration)
	await _tween.finished
	_animating = false
	_open = true
	_base_deg = 0.0
	_update_spill()
	opened.emit()


## Rotation sign that swings the panel away from `pos`. Which sign moves the
## panel toward +normal depends on where the hinge sits, so it is derived from
## the geometry rather than assumed.
func swing_away_from(pos: Vector3) -> float:
	var side := signf((pos - global_position).dot(_normal))
	if side == 0.0:
		side = 1.0
	var plus_moves_to := signf(_hinge_to_center.rotated(Vector3.UP, 0.2).dot(_normal))
	if plus_moves_to == 0.0:
		plus_moves_to = 1.0
	return -side * plus_moves_to


func close(duration := CLOSE_DUR) -> void:
	if not _open or _animating:
		return
	_animating = true
	AudioBus.sfx_at("door_close", global_position, -6.0)
	_tween = create_tween().set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tween.tween_property(_hinge, "rotation:y", 0.0, duration)
	await _tween.finished
	AudioBus.sfx_at("door_latch", global_position, -8.0)
	_animating = false
	_open = false
	_base_deg = 0.0
	_update_spill()
	closed.emit()


## Drift to a slightly-open resting pose (the closet, mid-Act 1). Not "open":
## the prompt still reads Open and open() animates from here.
func set_ajar(deg := 6.0, duration := 0.6) -> void:
	if _open or _animating:
		return
	_base_deg = deg
	var t := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	t.tween_property(_hinge, "rotation:y", deg_to_rad(deg * swing), duration)


## Instant ajar, for initial placement only.
func set_ajar_instant(deg: float) -> void:
	_base_deg = deg
	_hinge.rotation.y = deg_to_rad(deg * swing)


## Instant fully open, for initial placement. `dir` +1/-1, 0 = `swing`.
func set_open_instant(dir := 0.0) -> void:
	_open_dir = swing if dir == 0.0 else signf(dir)
	_hinge.rotation.y = deg_to_rad(open_deg * _open_dir)
	_open = true
	_base_deg = 0.0
	_update_spill()


## Small shudder without unlatching. Silent on purpose, the caller plays
## whatever sound fits the moment.
func shake(intensity := 1.0) -> void:
	if _animating:
		return
	var base := deg_to_rad(_base_deg * swing)
	var amp := deg_to_rad(0.9) * intensity * swing
	var t := create_tween()
	t.tween_property(_hinge, "rotation:y", base + amp, 0.05)
	t.tween_property(_hinge, "rotation:y", base + amp * 0.3, 0.06)
	t.tween_property(_hinge, "rotation:y", base + amp * 0.7, 0.05)
	t.tween_property(_hinge, "rotation:y", base, 0.12)


## Locked-door feedback rattle.
func jiggle(intensity := 1.0) -> void:
	if _animating:
		return
	AudioBus.sfx_at("door_locked", global_position, -6.0)
	var base := deg_to_rad(_base_deg * swing)
	var amp := deg_to_rad(1.3) * intensity * swing
	var t := create_tween()
	t.tween_property(_hinge, "rotation:y", base + amp, 0.06)
	t.tween_property(_hinge, "rotation:y", base, 0.05)
	t.tween_property(_hinge, "rotation:y", base + amp * 0.6, 0.05)
	t.tween_property(_hinge, "rotation:y", base, 0.08)


## What the player's interact press does. The awaitable open()/close() are for
## the director; from the player they are fire-and-forget. Opens swing away
## from the side the player is standing on.
func player_interact(by: Node3D = null) -> void:
	if _animating:
		return
	if locked:
		jiggle()
		return
	if script_locked:
		if blocked_line != "":
			Subtitles.show_line(blocked_line, 2.2)
		jiggle(0.4)
		return
	if _open:
		close()
	elif by:
		open(OPEN_DUR, swing_away_from(by.global_position))
	else:
		open()


func _update_spill() -> void:
	if _spill_sliver == null:
		return
	if not _spill_enabled:
		_spill_sliver.visible = false
		_spill_light.visible = false
		return
	# Closed: a strip under the door. Open (or opening): the strip is gone and
	# the room-side light carries the flood.
	var closed_now := not _open and not _animating
	_spill_sliver.visible = closed_now
	_spill_light.visible = true
	_spill_light.light_energy = _spill_energy * (0.55 if closed_now else 1.0)


static func _world_aabb(mi: MeshInstance3D) -> AABB:
	var local: AABB = mi.mesh.get_aabb()
	var xf := mi.global_transform
	var result := AABB(xf * local.get_endpoint(0), Vector3.ZERO)
	for i in range(1, 8):
		result = result.expand(xf * local.get_endpoint(i))
	return result


## The interact target. Thicker than the panel's collider so the ray (which now
## also collides with bodies) reaches it first.
class DoorInteract:
	extends Interactable

	var door: Door

	func _ready() -> void:
		super()

	func get_prompt() -> String:
		var ar := GameState.language == "ar"
		if door.locked:
			return "مقفول" if ar else "Locked"
		if door.is_open():
			return "أغلق" if ar else "Close"
		return "افتح" if ar else "Open"

	func _can_interact() -> bool:
		return not door._animating

	func _on_interact(by: Node3D) -> void:
		door.player_interact(by)
