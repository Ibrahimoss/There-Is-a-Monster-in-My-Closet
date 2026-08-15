class_name MeshUtil
extends RefCounted
## Small mesh helpers shared by doors, props and the toy.


## World-space AABB of a MeshInstance3D (transforms all 8 corners).
static func world_aabb(mi: MeshInstance3D) -> AABB:
	var local: AABB = mi.mesh.get_aabb()
	var xf := mi.global_transform
	var result := AABB(xf * local.get_endpoint(0), Vector3.ZERO)
	for i in range(1, 8):
		result = result.expand(xf * local.get_endpoint(i))
	return result


## Duplicates every surface material of `mi` as a StandardMaterial3D override
## with emission enabled at zero energy, so a hover glow can be tweened per
## instance without touching the shared FBX material. Returns the overrides.
static func make_glow_overrides(mi: MeshInstance3D, color: Color) -> Array[StandardMaterial3D]:
	var out: Array[StandardMaterial3D] = []
	if mi.mesh == null:
		return out
	for s in mi.mesh.get_surface_count():
		var mat := mi.get_active_material(s)
		if mat is StandardMaterial3D:
			var dup := (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
			dup.emission_enabled = true
			dup.emission = color
			dup.emission_energy_multiplier = 0.0
			mi.set_surface_override_material(s, dup)
			out.append(dup)
	return out
