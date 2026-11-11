class_name Board
extends RefCounted
## The persistent map: terrain, ore veins and the road network.
## Board 1 lays the first spiral-guided road. Every later board strikes in one new road
## that joins the network as close to the core as it can, going around towers when it must.
## A path is a Dictionary: {ingress, start: Vector2, path: Array[int] of macro ids, revealed, joins_at (-1 = core), board}.

const MW := Bal.MACRO_W
const MH := Bal.MACRO_H
const GW := Bal.GRID_W
const GH := Bal.GRID_H
const CORE_ID := Bal.CORE_MACRO.y * Bal.MACRO_W + Bal.CORE_MACRO.x
const CORE_PT := Vector2(Bal.CORE_MACRO.x * Bal.MACRO + Bal.MACRO / 2.0, Bal.CORE_MACRO.y * Bal.MACRO + Bal.MACRO / 2.0)

var seed: int
var height := PackedInt32Array()
var road := PackedByteArray()
## Ore vein index + 1 per cell.
var ore := PackedInt32Array()
var veins: Array[Vector2i] = []
var paths: Array = []
var routes: Array[Route] = []
## Town spur roads (section 12): {town, path: [junction macro, ..., town macro]}.
var spurs: Array = []
var town_routes: Array[Route] = []
## The road being struck in this board (shown by the reveal), or {}.
var pending: Dictionary = {}
var pending_cells: Array[int] = []
## Bumped whenever road cells change, so the view can rebuild.
var version := 0
var min_length: int
var cost := PackedFloat32Array()
## Optional hook: extra resource nodes (forests, lakes) placed per new road. Set by Game (economy).
var on_new_road: Callable


static func mid(mx: int, my: int) -> int:
	return my * MW + mx


static func mxy(m: int) -> Vector2i:
	return Vector2i(m % MW, m / MW)


static func cell_idx(x: int, y: int) -> int:
	return y * GW + x


static func in_grid(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < GW and y < GH


static func macro_centre(m: int) -> Vector2:
	var p := mxy(m)
	return Vector2(p.x * Bal.MACRO + Bal.MACRO / 2.0, p.y * Bal.MACRO + Bal.MACRO / 2.0)


static func edge_key(a: int, b: int) -> int:
	return a * 1000 + b if a < b else b * 1000 + a


static func core_dist(m: int) -> int:
	var p := mxy(m)
	return maxi(absi(p.x - Bal.CORE_MACRO.x), absi(p.y - Bal.CORE_MACRO.y))


static func neighbours(m: int) -> Array[int]:
	var p := mxy(m)
	var out: Array[int] = []
	if p.x > 0:
		out.append(m - 1)
	if p.x < MW - 1:
		out.append(m + 1)
	if p.y > 0:
		out.append(m - MW)
	if p.y < MH - 1:
		out.append(m + MW)
	return out


func _init(seed_value: int, data: Dictionary = {}) -> void:
	seed = seed_value
	height.resize(GW * GH)
	road.resize(GW * GH)
	ore.resize(GW * GH)
	var rng := Rng.new(Rng.sub_seed(seed, [101, 1]))
	min_length = Bal.ROAD.minLenBase + rng.int_range(-Bal.ROAD.minLenJitter, Bal.ROAD.minLenJitter)
	cost.resize(MW * MH)
	if not data.is_empty():
		_load(data)
		rebuild_road()
		return
	pending = _plan_first_road()
	pending_cells = cells_of(pending)
	_make_terrain()


# ------------------------------------------------------------- serialisation
func serialize() -> Dictionary:
	var ps: Array = []
	for p in paths:
		ps.append(_path_to_json(p))
	var vs: Array = []
	for v in veins:
		vs.append([v.x, v.y])
	var sp: Array = []
	for x in spurs:
		sp.append({"town": x.town, "path": Array(x.path)})
	return {"seed": seed, "height": Array(height), "ore": Array(ore), "veins": vs, "paths": ps, "cost": Array(cost), "spurs": sp}


func _load(d: Dictionary) -> void:
	height = PackedInt32Array(d.height)
	ore = PackedInt32Array(d.ore)
	veins.clear()
	for v in d.veins:
		veins.append(Vector2i(int(v[0]), int(v[1])))
	paths.clear()
	for p in d.paths:
		paths.append(_path_from_json(p))
	cost = PackedFloat32Array(d.cost)
	spurs.clear()
	for x in d.get("spurs", []):
		var path: Array[int] = []
		for m in x.path:
			path.append(int(m))
		spurs.append({"town": int(x.town), "path": path})


static func _path_to_json(p: Dictionary) -> Dictionary:
	return {"ingress": p.ingress, "start": [p.start.x, p.start.y], "path": Array(p.path), "revealed": p.revealed, "joins_at": p.joins_at, "board": p.board}


static func _path_from_json(p: Dictionary) -> Dictionary:
	var path: Array[int] = []
	for m in p.path:
		path.append(int(m))
	return {"ingress": int(p.ingress), "start": Vector2(p.start[0], p.start[1]), "path": path, "revealed": int(p.revealed), "joins_at": int(p.joins_at), "board": int(p.board)}


# ------------------------------------------------------------- fields
func _spiral_field(rng: Rng) -> PackedFloat32Array:
	var arms := rng.int_range(2, 3)
	var theta0 := rng.range_f(0.0, TAU)
	var pts := PackedVector2Array()
	var b := (2.0 * log(Bal.PHI)) / PI
	for k in arms:
		var off := theta0 + (k * TAU) / arms
		var th := -6.0
		while th < 16.0:
			var r: float = Bal.ROAD.spiralA * exp(b * th)
			if r > 30.0:
				break
			pts.append(Vector2(Bal.CORE_MACRO.x + 0.5 + r * cos(th + off), Bal.CORE_MACRO.y + 0.5 + r * sin(th + off)))
			th += 0.05
	var f := PackedFloat32Array()
	f.resize(MW * MH)
	for m in MW * MH:
		var c := mxy(m)
		var cp := Vector2(c.x + 0.5, c.y + 0.5)
		var best := 1e9
		for p in pts:
			var d := cp.distance_squared_to(p)
			if d < best:
				best = d
		f[m] = sqrt(best)
	return f


func _cost_field(rng: Rng) -> PackedFloat32Array:
	var field := _spiral_field(rng)
	var c := PackedFloat32Array()
	c.resize(field.size())
	for m in c.size():
		c[m] = 1.0 + Bal.ROAD.spiralK * minf(4.0, field[m]) + rng.range_f(0.0, Bal.ROAD.noise)
	return c


## Cells covered by the road segment between two points (3 cells wide).
static func seg_cells(a: Vector2, b: Vector2) -> Array[int]:
	var out: Array[int] = []
	var x0 := minf(a.x, b.x)
	var x1 := maxf(a.x, b.x)
	var y0 := minf(a.y, b.y)
	var y1 := maxf(a.y, b.y)
	var ystart := floori(y0) - 1
	var yend := maxi(ceili(y1), floori(y0) + 1)
	var xstart := floori(x0) - 1
	var xend := maxi(ceili(x1), floori(x0) + 1)
	for y in range(ystart, yend):
		for x in range(xstart, xend):
			if in_grid(x, y):
				out.append(cell_idx(x, y))
	return out


static func edge_start(m: int) -> Vector2:
	var p := mxy(m)
	var c := macro_centre(m)
	var opts: Array[Vector2] = []
	if p.x == 0:
		opts.append(Vector2(0, c.y))
	if p.x == MW - 1:
		opts.append(Vector2(GW, c.y))
	if p.y == 0:
		opts.append(Vector2(c.x, 0))
	if p.y == MH - 1:
		opts.append(Vector2(c.x, GH))
	var best := opts[0]
	for o in opts:
		if o.distance_to(CORE_PT) > best.distance_to(CORE_PT):
			best = o
	return best


## Dijkstra on the macro grid with terminal costs.
## terminal(m) returns extra cost when this macro ends the road, or -1 if it cannot end here.
func _route_macro(from: int, c: PackedFloat32Array, forbidden: Dictionary, terminal: Callable, avoid: Dictionary, edge_cost: Callable = Callable()) -> Array[int]:
	var n := MW * MH
	var dist := PackedFloat64Array()
	dist.resize(n)
	dist.fill(INF)
	var prev := PackedInt32Array()
	prev.resize(n)
	prev.fill(-1)
	var done := PackedByteArray()
	done.resize(n)
	dist[from] = 0.0
	var best_end := -1
	var best_total := INF
	while true:
		var u := -1
		var best := INF
		for i in n:
			if done[i] == 0 and dist[i] < best:
				best = dist[i]
				u = i
		if u < 0 or best >= best_total:
			break
		done[u] = 1
		if u != from:
			var tc: float = terminal.call(u)
			if tc >= 0.0:
				if dist[u] + tc < best_total:
					best_total = dist[u] + tc
					best_end = u
				continue
		for v in neighbours(u):
			if done[v] == 1 or forbidden.has(v):
				continue
			var nd := dist[u] + c[v] + (2.5 if (avoid.has(v) and core_dist(v) > 2) else 0.0)
			if edge_cost.is_valid():
				nd += float(edge_cost.call(u, v))
			if nd < dist[v]:
				dist[v] = nd
				prev[v] = u
	var out: Array[int] = []
	if best_end < 0:
		return out
	var cur := best_end
	while cur >= 0:
		out.append(cur)
		cur = prev[cur]
	out.reverse()
	return out


static func _has_hairpin(path: Array[int]) -> bool:
	for i in path.size():
		for j in range(i + 3, path.size()):
			var a := mxy(path[i])
			var b := mxy(path[j])
			if absi(a.x - b.x) + absi(a.y - b.y) == 1 and core_dist(path[i]) > 2 and core_dist(path[j]) > 2:
				return true
	return false


# ------------------------------------------------------------- roads
func _road_macros() -> Dictionary:
	var s := {}
	for p in paths:
		for c in p.path:
			if c != CORE_ID:
				s[c] = true
	return s


func _plan_first_road() -> Dictionary:
	var best: Dictionary = {}
	var best_score := -INF
	var best_cost := PackedFloat32Array()
	for attempt in Bal.ROAD.attempts:
		var rng := Rng.new(Rng.sub_seed(seed, [202, 1, attempt]))
		var c := _cost_field(rng)
		var edge_cells: Array = []
		for m in c.size():
			var p := mxy(m)
			if (p.x == 0 or p.y == 0 or p.x == MW - 1 or p.y == MH - 1) and core_dist(m) >= 4:
				edge_cells.append(m)
		var ing: int = rng.pick(edge_cells)
		var path := _curl_route(ing, c, rng)
		if path.is_empty() or _has_hairpin(path):
			continue
		var ps := {"ingress": ing, "start": edge_start(ing), "path": path, "revealed": 1, "joins_at": -1, "board": 1}
		var len := path_length(ps, [ps])
		var score := 1000.0 - absf(len - min_length - 20) if len >= min_length else len
		if best.is_empty() or score > best_score:
			best = ps
			best_score = score
			best_cost = c
		if len >= min_length and len <= min_length + 50:
			break
	assert(not best.is_empty(), "road generation failed")
	cost = best_cost
	return best


func _curl_route(ing: int, c: PackedFloat32Array, rng: Rng) -> Array[int]:
	var to_core := func(m: int) -> float: return 0.0 if m == CORE_ID else -1.0
	var direct := _route_macro(ing, c, {}, to_core, {})
	if direct.is_empty():
		return direct
	if direct.size() * Bal.MACRO >= min_length:
		return direct
	# pick a waypoint around the core on the opposite side from the ingress so the road curls
	var ip := mxy(ing)
	var ang := atan2(ip.y - Bal.CORE_MACRO.y, ip.x - Bal.CORE_MACRO.x) + PI + rng.range_f(-0.9, 0.9)
	var r := rng.range_f(2.2, 3.6)
	var wx := clampi(roundi(Bal.CORE_MACRO.x + r * cos(ang)), 0, MW - 1)
	var wy := clampi(roundi(Bal.CORE_MACRO.y + r * sin(ang)), 0, MH - 1)
	var way := mid(wx, wy)
	if way == CORE_ID or core_dist(way) < 2:
		return direct
	var to_way := func(m: int) -> float: return 0.0 if m == way else -1.0
	var first := _route_macro(ing, c, {CORE_ID: true}, to_way, {})
	if first.is_empty():
		return direct
	var forb := {}
	for i in first.size() - 1:
		forb[first[i]] = true
	var second := _route_macro(way, c, forb, to_core, {})
	if second.is_empty():
		return direct
	var out: Array[int] = first.duplicate()
	for i in range(1, second.size()):
		out.append(second[i])
	return out


## Road distance (macro steps) from every road macro to the core.
func _road_distance() -> Dictionary:
	var nxt := {}
	for p in paths:
		for i in p.path.size() - 1:
			nxt[p.path[i]] = p.path[i + 1]
	var out := {}
	for p in paths:
		for c in p.path:
			_walk_dist(c, nxt, out)
	return out


func _walk_dist(m: int, nxt: Dictionary, out: Dictionary) -> int:
	if m == CORE_ID:
		return 0
	if out.has(m):
		return out[m]
	out[m] = 999
	var d := 999
	if nxt.has(m):
		d = _walk_dist(nxt[m], nxt, out) + 1
	out[m] = d
	return d


## Plan the road a new board strikes in. It starts on an unused edge far from the other spawns,
## prefers to join the network close to the core, and routes around cells where blocked(cell) is true.
## Returns {path, destroys: cells of objects the strike will have to clear}.
func plan_road(b: int, blocked: Callable) -> Dictionary:
	var rng := Rng.new(Rng.sub_seed(seed, [202, b]))
	var c := _cost_field(rng)
	var used := _road_macros()
	var starts: Array[Vector2i] = []
	for p in paths:
		starts.append(mxy(p.ingress))
	var cands: Array = []
	for m in c.size():
		var p := mxy(m)
		if not (p.x == 0 or p.y == 0 or p.x == MW - 1 or p.y == MH - 1):
			continue
		if used.has(m) or core_dist(m) < 5:
			continue
		var touching := false
		for nb in neighbours(m):
			if used.has(nb):
				touching = true
		if touching:
			continue
		var far := 99
		for q in starts:
			far = mini(far, absi(q.x - p.x) + absi(q.y - p.y))
		cands.append({"m": m, "score": mini(far, 12) + core_dist(m) * 0.8 + rng.range_f(0.0, 4.0)})
	cands.sort_custom(func(a, z): return a.score > z.score)
	var rd := _road_distance()
	var avoid := {}
	for u in used:
		for v in neighbours(u):
			avoid[v] = true
	var edge_blocked := {}
	var is_blocked := func(a: int, z: int) -> bool:
		var k := edge_key(a, z)
		if not edge_blocked.has(k):
			var hit := false
			for cell in seg_cells(macro_centre(a), macro_centre(z)):
				if blocked.call(cell):
					hit = true
					break
			edge_blocked[k] = hit
		return edge_blocked[k]
	var fallback: Dictionary = {}
	for ci in mini(6, cands.size()):
		var ing: int = cands[ci].m
		var start_pt := edge_start(ing)
		var start_cells := seg_cells(start_pt, macro_centre(ing))
		var start_blocked := false
		for cell in start_cells:
			if blocked.call(cell):
				start_blocked = true
		var term := func(m: int) -> float:
			if m == CORE_ID:
				return 0.0
			if used.has(m):
				return Bal.JOIN_K * float(rd.get(m, 50))
			return -1.0
		var ecost := func(a: int, z: int) -> float: return Bal.BLOCKED_EDGE_COST if is_blocked.call(a, z) else 0.0
		var path := _route_macro(ing, c, {}, term, avoid, ecost)
		if path.size() < 2:
			continue
		var end := path[path.size() - 1]
		var ps := {"ingress": ing, "start": start_pt, "path": path, "revealed": 1, "joins_at": -1 if end == CORE_ID else end, "board": b}
		var destroys := {}
		if start_blocked:
			for cell in start_cells:
				if blocked.call(cell):
					destroys[cell] = true
		for i in path.size() - 1:
			if is_blocked.call(path[i], path[i + 1]):
				for cell in seg_cells(macro_centre(path[i]), macro_centre(path[i + 1])):
					if blocked.call(cell):
						destroys[cell] = true
		var res := {"path": ps, "destroys": destroys.keys()}
		if destroys.is_empty():
			return res
		if fallback.is_empty() or res.destroys.size() < fallback.destroys.size():
			fallback = res
	assert(not fallback.is_empty(), "no road could be planned")
	return fallback


## Cells covered by a spur road (junction centre to town centre).
func spur_cells(path: Array) -> Array[int]:
	var out := {}
	for i in path.size() - 1:
		for cell in seg_cells(macro_centre(path[i]), macro_centre(path[i + 1])):
			out[cell] = true
	var arr: Array[int] = []
	for k in out:
		arr.append(k)
	return arr


func is_road_macro(m: int) -> bool:
	for p in paths:
		if p.path.has(m):
			return true
	for sp in spurs:
		if sp.path.has(m):
			return true
	return false


func add_spur(town_id: int, path: Array[int], occupied: Callable = Callable()) -> void:
	spurs.append({"town": town_id, "path": path})
	rebuild_road(occupied)


func remove_spur(town_id: int, occupied: Callable = Callable()) -> void:
	spurs = spurs.filter(func(x): return x.town != town_id)
	rebuild_road(occupied)


## Cells covered by a path.
func cells_of(p: Dictionary) -> Array[int]:
	var out := {}
	for cell in seg_cells(p.start, macro_centre(p.path[0])):
		out[cell] = true
	for i in p.path.size() - 1:
		for cell in seg_cells(macro_centre(p.path[i]), macro_centre(p.path[i + 1])):
			out[cell] = true
	var arr: Array[int] = []
	for k in out:
		arr.append(k)
	return arr


func set_pending(p: Dictionary) -> void:
	pending = p
	pending_cells = cells_of(p)


## Road length in cells for a path, following joins to the core.
func path_length(p: Dictionary, all: Array = paths) -> float:
	var len := (p.start as Vector2).distance_to(macro_centre(p.path[0]))
	len += (p.path.size() - 1) * Bal.MACRO
	var j: int = p.joins_at
	var guard := 0
	while j >= 0 and guard < 10:
		guard += 1
		var host: Dictionary = {}
		for q in all:
			if q != p and q.path.has(j) and q.path[q.path.size() - 1] != j:
				host = q
				break
		if host.is_empty():
			break
		len += (host.path.size() - 1 - host.path.find(j)) * Bal.MACRO
		j = host.joins_at
	return len


func reveal_total() -> int:
	return pending.path.size() if not pending.is_empty() else 1


## Commit the pending road: lay its cells, flatten the ground around it (never under objects),
## rebuild routes and add resource nodes near it.
func commit_pending(occupied: Callable) -> void:
	if pending.is_empty():
		return
	var p := pending
	p.revealed = p.path.size()
	paths.append(p)
	pending = {}
	pending_cells = []
	rebuild_road(occupied)
	var rng := Rng.new(Rng.sub_seed(seed, [303, p.board]))
	var count: int = rng.int_range(Bal.ORE.min, Bal.ORE.max) if p.board == 1 else Bal.ORE.perNewRoad
	var near := {}
	for cell in cells_of(p):
		near[cell] = true
	_make_ore(rng, count, near, occupied)
	if on_new_road.is_valid():
		on_new_road.call(p, near)


## Lay road cells for every committed path, flatten around them and rebuild routes.
func rebuild_road(occupied: Callable = Callable()) -> void:
	road.fill(0)
	for p in paths:
		for cell in cells_of(p):
			road[cell] = 1
	for sp in spurs:
		for cell in spur_cells(sp.path):
			road[cell] = 1
	for y in GH:
		for x in GW:
			var i := cell_idx(x, y)
			if height[i] == 0 or (occupied.is_valid() and occupied.call(i)):
				continue
			var near := false
			for dy in range(-1, 2):
				for dx in range(-1, 2):
					if in_grid(x + dx, y + dy) and road[cell_idx(x + dx, y + dy)] == 1:
						near = true
			if near or Vector2(x + 0.5, y + 0.5).distance_to(CORE_PT) < Bal.CORE_RADIUS + 2:
				height[i] = 0
	for i in road.size():
		if road[i] == 1:
			ore[i] = 0
	_build_routes()
	version += 1


func _build_routes() -> void:
	var nxt := {}
	for p in paths:
		for i in p.path.size() - 1:
			var a: int = p.path[i]
			var l: Array = nxt.get(a, [])
			if not l.has(p.path[i + 1]):
				l.append(p.path[i + 1])
			nxt[a] = l
	routes.clear()
	for ingress in paths.size():
		var p: Dictionary = paths[ingress]
		var found: Array = []
		_dfs(p.path[0], [p.path[0]], {p.path[0]: true}, nxt, found)
		for macros in found:
			var pts := PackedVector2Array([p.start])
			for m in macros:
				pts.append(macro_centre(m))
			routes.append(Route.make(ingress, pts))
	# town spurs: a diverted copy of each route that passes the junction
	town_routes.clear()
	for sp in spurs:
		var j := macro_centre(sp.path[0])
		for r in routes:
			var k := -1
			for i in r.pts.size():
				if r.pts[i].distance_to(j) < 0.01:
					k = i
					break
			if k < 0:
				continue
			var tp := PackedVector2Array()
			for i in k + 1:
				tp.append(r.pts[i])
			for i in range(1, sp.path.size()):
				tp.append(macro_centre(sp.path[i]))
			var tr := Route.make(r.ingress, tp)
			tr.town_id = sp.town
			town_routes.append(tr)
			r.diverts.append({"town": sp.town, "route": tr, "d": r.cum[k]})


func _dfs(c: int, acc: Array, seen: Dictionary, nxt: Dictionary, found: Array) -> void:
	if found.size() >= 4:
		return
	if c == CORE_ID:
		found.append(acc.duplicate())
		return
	for n in nxt.get(c, []):
		if seen.has(n):
			continue
		seen[n] = true
		acc.append(n)
		_dfs(n, acc, seen, nxt, found)
		acc.pop_back()
		seen.erase(n)


# ------------------------------------------------------------- terrain & ore
func _make_terrain() -> void:
	var rng := Rng.new(Rng.sub_seed(seed, [404, 1]))
	var planned := {}
	if not pending.is_empty():
		for m in pending.path:
			planned[m] = true
	for m in MW * MH:
		if planned.has(m) or core_dist(m) < 1:
			continue
		var nf: int = rng.pick(Bal.TERRAIN.featuresPerMacro)
		var mp := mxy(m)
		for _f in nf:
			var s: int = rng.pick(Bal.TERRAIN.blobSizes)
			var h: int
			if rng.chance(0.6):
				h = rng.int_range(Bal.TERRAIN.rise[0], Bal.TERRAIN.rise[1])
			else:
				h = rng.int_range(Bal.TERRAIN.valley[0], Bal.TERRAIN.valley[1])
			var ox := mp.x * Bal.MACRO + rng.int_range(0, Bal.MACRO - s)
			var oy := mp.y * Bal.MACRO + rng.int_range(0, Bal.MACRO - s)
			for y in s:
				for x in s:
					if s >= 5 and (x == 0 or x == s - 1) and (y == 0 or y == s - 1):
						continue
					height[cell_idx(ox + x, oy + y)] = h


func _make_ore(rng: Rng, n: int, near: Dictionary, occupied: Callable) -> void:
	var added := 0
	var sz: int = Bal.ORE.size
	for _tries in 600:
		if added >= n:
			break
		var x := rng.int_range(1, GW - sz - 1)
		var y := rng.int_range(1, GH - sz - 1)
		var ok := Vector2(x, y).distance_to(CORE_PT) > 10.0
		for dy in range(-2, sz + 2):
			if not ok:
				break
			for dx in range(-2, sz + 2):
				var cx := x + dx
				var cy := y + dy
				if not in_grid(cx, cy):
					continue
				var i := cell_idx(cx, cy)
				if road[i] == 1 or ore[i] != 0 or (occupied.is_valid() and occupied.call(i)) or is_blocked_terrain(i):
					ok = false
					break
		var near_road := false
		if ok:
			for dy in range(-10, 13):
				if near_road:
					break
				for dx in range(-10, 13):
					if in_grid(x + dx, y + dy) and near.has(cell_idx(x + dx, y + dy)):
						near_road = true
						break
		if not ok or not near_road:
			continue
		veins.append(Vector2i(x, y))
		added += 1
		for dy in sz:
			for dx in sz:
				ore[cell_idx(x + dx, y + dy)] = veins.size()
				height[cell_idx(x + dx, y + dy)] = 0


## Overridden by the economy layer: forest and lake cells block ore and towers.
var terrain_blocker: Callable


func is_blocked_terrain(i: int) -> bool:
	return terrain_blocker.is_valid() and terrain_blocker.call(i)


func is_core_cell(x: int, y: int) -> bool:
	return absf(x + 0.5 - CORE_PT.x) < Bal.CORE_RADIUS and absf(y + 0.5 - CORE_PT.y) < Bal.CORE_RADIUS


func h(x: int, y: int) -> int:
	return height[cell_idx(x, y)]


func is_road(x: int, y: int) -> bool:
	return road[cell_idx(x, y)] == 1
