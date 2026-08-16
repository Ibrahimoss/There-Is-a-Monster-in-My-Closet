class_name NavGraph
extends RefCounted
## Nodes and edges the monster walks along, one per chase room.
##
## Rooms build these in their own local frame and the director bakes them to
## world space once the room is placed. Small enough (under 40 nodes) that
## Dijkstra per query costs nothing, so there is no navmesh anywhere.

var points: Array[Vector3] = []
## Pairs of point indices.
var edges: Array[Vector2i] = []
## Point index -> its neighbour point indices.
var adj: Array[PackedInt32Array] = []


func add(p: Vector3) -> int:
	points.append(p)
	adj.append(PackedInt32Array())
	return points.size() - 1


func link(a: int, b: int) -> void:
	if a == b or a < 0 or b < 0 or a >= points.size() or b >= points.size():
		return
	for e in edges:
		if (e.x == a and e.y == b) or (e.x == b and e.y == a):
			return
	edges.append(Vector2i(a, b))
	adj[a].append(b)
	adj[b].append(a)


## Add a run of points and link them in order. Returns their indices.
func chain(pts: Array[Vector3]) -> PackedInt32Array:
	var out := PackedInt32Array()
	for p in pts:
		out.append(add(p))
	for i in range(1, out.size()):
		link(out[i - 1], out[i])
	return out


func size() -> int:
	return points.size()


## A copy with every point pushed through `xf`. The director calls this once
## the room root is placed, so the monster works in world space.
func transformed(xf: Transform3D) -> NavGraph:
	var g := NavGraph.new()
	for p in points:
		g.add(xf * p)
	for e in edges:
		g.link(e.x, e.y)
	return g


## Index of the point nearest `p` (straight line, ignores edges).
func nearest_node(p: Vector3) -> int:
	var best := -1
	var best_d := INF
	for i in points.size():
		var d := points[i].distance_squared_to(p)
		if d < best_d:
			best_d = d
			best = i
	return best


## Closest point on any edge. Returns {"edge": int, "t": float, "point":
## Vector3, "dist": float}; edge -1 when the graph is empty.
func nearest(p: Vector3) -> Dictionary:
	var out := {"edge": -1, "t": 0.0, "point": p, "dist": INF}
	if edges.is_empty():
		var n := nearest_node(p)
		if n >= 0:
			out["point"] = points[n]
			out["dist"] = points[n].distance_to(p)
		return out
	for i in edges.size():
		var a := points[edges[i].x]
		var b := points[edges[i].y]
		var ab := b - a
		var len2 := ab.length_squared()
		var t := 0.0 if len2 < 1e-9 else clampf((p - a).dot(ab) / len2, 0.0, 1.0)
		var q := a + ab * t
		var d := q.distance_to(p)
		if d < float(out["dist"]):
			out = {"edge": i, "t": t, "point": q, "dist": d}
	return out


func edge_point(edge: int, t: float) -> Vector3:
	if edge < 0 or edge >= edges.size():
		return Vector3.ZERO
	var a := points[edges[edge].x]
	var b := points[edges[edge].y]
	return a.lerp(b, clampf(t, 0.0, 1.0))


## Shortest node-to-node distances from `src`, INF where unreachable.
func distances(src: int) -> PackedFloat32Array:
	var dist := PackedFloat32Array()
	dist.resize(points.size())
	dist.fill(INF)
	if src < 0 or src >= points.size():
		return dist
	dist[src] = 0.0
	var done := {}
	while true:
		var u := -1
		var best := INF
		for i in points.size():
			if not done.has(i) and dist[i] < best:
				best = dist[i]
				u = i
		if u < 0:
			break
		done[u] = true
		for v in adj[u]:
			var nd := dist[u] + points[u].distance_to(points[v])
			if nd < dist[v]:
				dist[v] = nd
	return dist


## First node to walk toward on the shortest route from `src` to `dst`.
func next_node(src: int, dst: int) -> int:
	if src == dst or src < 0 or dst < 0:
		return dst
	var dist := distances(dst)
	var best := -1
	var best_cost := INF
	for v in adj[src]:
		var c := points[src].distance_to(points[v]) + dist[v]
		if c < best_cost:
			best_cost = c
			best = v
	return best if best >= 0 else dst


## Every node reachable from node 0. Tests use it to catch a room that built
## an island of nodes nothing connects to.
func connected() -> bool:
	if points.size() <= 1:
		return true
	var seen := {0: true}
	var stack: Array[int] = [0]
	while not stack.is_empty():
		var u: int = stack.pop_back()
		for v in adj[u]:
			if not seen.has(v):
				seen[v] = true
				stack.append(v)
	return seen.size() == points.size()
