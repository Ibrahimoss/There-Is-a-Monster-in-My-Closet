class_name PillowTex
extends RefCounted
## The pillow floor, baked at runtime.
##
## Three things live here, in the order the floor is stacked:
##   floor_tex()   a tileable texture of pillows piled three deep, with the
##                 crevices punched to alpha 0 so the black slab under it shows
##                 through and the pile reads as bottomless
##   pillow_mesh() one actual pillow, for the layer of real ones scattered on top
##   scatter()     that mesh as MultiMesh tiles, no collision, so the player
##                 wades through them
##
## The texture is written into a byte buffer rather than with set_pixel: 256
## square is about ninety thousand pixels and GDScript will not do that one
## call at a time inside a level load.

## Fabric under the light. Warm off-white, because the room's own light is warm
## and the palette crush eats anything subtler.
const CLOTH := Color(0.86, 0.83, 0.79)
## How dark each layer sits relative to the top one. The eye reads the gap
## between them as depth, so the bottom layer has to be genuinely dark.
const LAYER_GAIN := [0.26, 0.55, 1.0]
## Light the fake normals are shaded against.
const LIGHT_DIR := Vector3(-0.42, 0.80, -0.43)

static var _tex: ImageTexture
static var _mesh: ArrayMesh
static var _mat: StandardMaterial3D


## Pillows piled three deep, tiling. Cached: one bake per run.
##
## 192 square rather than 256: this is a per-pixel loop in GDScript and the cost
## is the square of the size, while the tile is 2.4 m of floor seen through a
## 320x200 palette crush. It runs behind the fade into the room either way, but
## on web that fade is the only thing covering it.
static func floor_tex(size := 192) -> ImageTexture:
	if _tex != null:
		return _tex
	var w := size
	var buf := PackedByteArray()
	buf.resize(w * w * 4)
	buf.fill(0)
	var height := PackedFloat32Array()
	height.resize(w * w)
	height.fill(-1.0)

	var rng := RandomNumberGenerator.new()
	rng.seed = 20260816
	# back to front: a later layer overwrites an earlier one wherever it is
	# higher, which is what stacks them
	for layer in 3:
		var cells := 5 - layer
		var base := float(layer) * 0.30
		var gain := float(LAYER_GAIN[layer])
		var cell := float(w) / float(cells)
		for gy in cells:
			for gx in cells:
				var cx := (float(gx) + 0.5 + rng.randf_range(-0.22, 0.22)) * cell
				var cy := (float(gy) + 0.5 + rng.randf_range(-0.22, 0.22)) * cell
				var a := cell * rng.randf_range(0.52, 0.68)
				var b := cell * rng.randf_range(0.38, 0.50)
				var ang := rng.randf_range(0.0, PI)
				var warm := rng.randf_range(-0.05, 0.05)
				_stamp(buf, height, w, cx, cy, a, b, ang, base, gain, warm)

	var img := Image.create_from_data(w, w, false, Image.FORMAT_RGBA8, buf)
	_tex = ImageTexture.create_from_image(img)
	return _tex


## One pillow rasterised into the buffer, wrapping at the edges so the tile
## repeats without a seam. Anything lower than what is already there is dropped.
static func _stamp(buf: PackedByteArray, height: PackedFloat32Array, w: int,
		cx: float, cy: float, a: float, b: float, ang: float,
		base: float, gain: float, warm: float) -> void:
	var ca := cos(ang)
	var sa := sin(ang)
	var reach := int(ceil(maxf(a, b))) + 1
	var x0 := int(floor(cx)) - reach
	var y0 := int(floor(cy)) - reach
	var span := reach * 2 + 1
	# the puff's slope, for the fake normal. Steeper than the height itself so
	# the rim actually turns away from the light
	var slope := 2.4

	for dy in span:
		var py := y0 + dy
		var fy := float(py) + 0.5 - cy
		for dx in span:
			var px := x0 + dx
			var fx := float(px) + 0.5 - cx
			var u := (fx * ca + fy * sa) / a
			var v := (-fx * sa + fy * ca) / b
			var au := absf(u)
			var av := absf(v)
			if au >= 1.0 or av >= 1.0:
				continue
			# superellipse, not an ellipse: pillows are square-ish with the
			# corners pulled in, and a plain oval reads as a stone
			var d := au * au * au * au + av * av * av * av
			if d >= 1.0:
				continue
			var puff := pow(1.0 - d, 0.42)
			var h := base + puff * 0.30

			var ix := ((px % w) + w) % w
			var iy := ((py % w) + w) % w
			var idx := iy * w + ix
			if h <= height[idx]:
				continue
			height[idx] = h

			# normal from the puff gradient, spun back out of the pillow's frame
			var nu := u * u * u * slope * (1.0 - d)
			var nv := v * v * v * slope * (1.0 - d)
			var n := Vector3(nu * ca - nv * sa, 1.0, nu * sa + nv * ca).normalized()
			var lam := clampf(n.dot(LIGHT_DIR.normalized()), 0.0, 1.0)
			var shade := 0.26 + 0.74 * lam
			# contact shadow where it meets whatever is under it
			shade *= 0.35 + 0.65 * smoothstep(0.0, 0.30, 1.0 - d)
			# the seam, which is most of what says "pillow" and not "bean bag"
			var seam := absf(d - 0.80)
			if seam < 0.045:
				shade *= 0.72 + 0.28 * (seam / 0.045)

			var lit := shade * gain
			var c := Color(
				CLOTH.r * lit + warm * 0.5,
				CLOTH.g * lit,
				CLOTH.b * lit - warm * 0.4)
			var o := idx * 4
			buf[o] = int(clampf(c.r, 0.0, 1.0) * 255.0)
			buf[o + 1] = int(clampf(c.g, 0.0, 1.0) * 255.0)
			buf[o + 2] = int(clampf(c.b, 0.0, 1.0) * 255.0)
			buf[o + 3] = 255


## The floor material: the baked pile over nothing. Scissor rather than blend,
## so the crevices are a hole in the mesh and the black slab beneath is what you
## are actually looking into.
static func floor_material(repeat := 2.4) -> StandardMaterial3D:
	if _mat != null:
		return _mat
	var m := StandardMaterial3D.new()
	m.albedo_texture = floor_tex()
	m.albedo_color = Color(1, 1, 1)
	m.roughness = 1.0
	m.metallic = 0.0
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.5
	# world triplanar would tile per axis and the floor only needs one plane, but
	# it is also how every other chase surface is mapped and it keeps the tiles
	# from having to carry their own uvs
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	var s := 1.0 / maxf(repeat, 0.01)
	m.uv1_scale = Vector3(s, s, s)
	_mat = m
	return m


## One pillow. A grid pinched to nothing at the rim, mirrored top and bottom, so
## the corners draw in the way a stuffed corner does. About seventy triangles.
static func pillow_mesh(size := Vector3(0.56, 0.22, 0.40), seg := 6) -> ArrayMesh:
	if _mesh != null:
		return _mesh
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var n := seg + 1
	# top then bottom, each a full grid; they meet exactly at the rim where the
	# puff is zero, so the result is closed without a skirt
	for side in [1.0, -1.0]:
		for j in seg:
			for i in seg:
				var quad := [Vector2i(i, j), Vector2i(i + 1, j), Vector2i(i + 1, j + 1), Vector2i(i, j + 1)]
				var order := [0, 1, 2, 0, 2, 3] if side > 0.0 else [0, 2, 1, 0, 3, 2]
				for k in order:
					var g: Vector2i = quad[int(k)]
					var u := float(g.x) / float(seg) * 2.0 - 1.0
					var v := float(g.y) / float(seg) * 2.0 - 1.0
					var h := _puff(u) * _puff(v)
					st.set_uv(Vector2(float(g.x) / float(seg), float(g.y) / float(seg)))
					st.add_vertex(Vector3(
						u * size.x * 0.5,
						side * h * size.y * 0.5,
						v * size.z * 0.5))
	st.generate_normals()
	_mesh = st.commit()
	return _mesh


static func _puff(t: float) -> float:
	var a := clampf(1.0 - pow(absf(t), 2.6), 0.0, 1.0)
	return pow(a, 0.45)


## The loose layer on top: real pillows, one MultiMesh per tile so GL
## compatibility can still light them, and no collision anywhere, so you have to
## push through the things rather than climb them.
static func scatter(parent: Node3D, area: Vector2, centre: Vector3, per_tile: int,
		tile: float, rng: RandomNumberGenerator, mat: Material) -> Array[MultiMeshInstance3D]:
	var out: Array[MultiMeshInstance3D] = []
	var mesh := pillow_mesh()
	var nx := maxi(1, int(ceil(area.x / tile)))
	var nz := maxi(1, int(ceil(area.y / tile)))
	var step_x := area.x / float(nx)
	var step_z := area.y / float(nz)
	for tz in nz:
		for tx in nx:
			var mid := centre + Vector3(
				(float(tx) + 0.5) * step_x - area.x * 0.5,
				0.0,
				(float(tz) + 0.5) * step_z - area.y * 0.5)
			var mm := MultiMesh.new()
			mm.transform_format = MultiMesh.TRANSFORM_3D
			mm.use_colors = true
			mm.mesh = mesh
			mm.instance_count = per_tile
			for i in per_tile:
				var p := Vector3(
					rng.randf_range(-0.5, 0.5) * step_x,
					rng.randf_range(-0.02, 0.06),
					rng.randf_range(-0.5, 0.5) * step_z)
				var b := Basis(Vector3.UP, rng.randf_range(0.0, TAU))
				# a small tip, so they lie at angles instead of paving the floor
				b = Basis(b * Vector3(1, 0, 0), rng.randf_range(-0.22, 0.22)) * b
				b = b.scaled(Vector3.ONE * rng.randf_range(0.82, 1.34))
				mm.set_instance_transform(i, Transform3D(b, p))
				var g := rng.randf_range(0.72, 1.0)
				mm.set_instance_color(i, Color(g, g * 0.99, g * 0.96))
			var mmi := MultiMeshInstance3D.new()
			mmi.multimesh = mm
			mmi.material_override = mat
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			mmi.position = mid
			parent.add_child(mmi)
			out.append(mmi)
	return out
