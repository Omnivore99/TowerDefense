class_name TerrainView
extends Node3D
## Terraced ground, cobbled roads, glowing ore veins, the paved base plaza, grass tufts and rocks.
## Cliff faces are broken into jagged rock with boulders at their feet. Around the board a
## sculpted landscape (rolling hills, pine woods, dark mountains) fills the view when the
## camera tilts toward the horizon. The board is rebuilt whenever its road version changes;
## the outer landscape only when the board (seed) changes.

const OUTER_STEP := 4.0
const OUTER_REACH := 220.0

static var _noise: FastNoiseLite
static var _ridge: FastNoiseLite
static var _board_ref: Board

var board: Board
var ground: MeshInstance3D
var decor: Node3D
var built_version := -1
var pending_overlay: MeshInstance3D
var outer: Node3D
var outer_seed := -1
var extra_kind: Callable  ## economy: cell -> kind override (forest floor, lake bed, mud)


static func cell_y(b: Board, x: int, y: int) -> float:
	if not Board.in_grid(x, y):
		return 0.0
	return b.h(x, y) * Kit.LH


func setup(b: Board) -> void:
	board = b
	_board_ref = b
	built_version = -1
	rebuild()
	if outer_seed != b.seed or outer == null:
		_build_outer()


func _kind(x: int, y: int) -> float:
	var i := Board.cell_idx(x, y)
	if extra_kind.is_valid():
		var k: float = extra_kind.call(i)
		if k >= 0.0:
			return k
	if board.road[i] == 1:
		return 1.0
	if board.ore[i] != 0:
		return 2.0
	if Vector2(x + 0.5, y + 0.5).distance_to(Board.CORE_PT) < Bal.CORE_RADIUS + 1.6:
		return 3.0
	return 0.0


func rebuild() -> void:
	if board == null:
		return
	built_version = board.version
	if ground != null:
		ground.queue_free()
	if decor != null:
		decor.queue_free()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var gw := Bal.GRID_W
	var gh := Bal.GRID_H
	for y in gh:
		for x in gw:
			var h := board.h(x, y)
			var top := h * Kit.LH
			var k := _kind(x, y)
			if k == 1.0:
				top -= 0.04  # roads sit a touch below the grass
			var uv := Vector2(k, h)
			_top(st, x, y, top, uv)
			# side walls where a neighbour is lower (cliffs), and the map edge skirt
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + d.x
				var ny: int = y + d.y
				var nb := -4.0 * Kit.LH
				if Board.in_grid(nx, ny):
					nb = board.h(nx, ny) * Kit.LH
					if _kind(nx, ny) == 1.0:
						nb -= 0.04
				if nb < top - 0.001:
					_wall(st, x, y, d, top, nb, Vector2(0.0, h))
	st.generate_tangents()
	var mesh := st.commit()
	ground = MeshInstance3D.new()
	ground.mesh = mesh
	ground.material_override = Kit.ground_material()
	ground.name = "Ground"
	add_child(ground)
	_build_decor()


func _top(st: SurfaceTool, x: int, y: int, top: float, uv: Vector2) -> void:
	var a := Vector3(x, top, y)
	var b := Vector3(x + 1, top, y)
	var c := Vector3(x + 1, top, y + 1)
	var d := Vector3(x, top, y + 1)
	for v in [a, b, c, a, c, d]:
		st.set_normal(Vector3.UP)
		st.set_uv(uv)
		st.add_vertex(v)


func _wall(st: SurfaceTool, x: int, y: int, d: Vector2i, top: float, bottom: float, uv: Vector2) -> void:
	var n := Vector3(d.x, 0, d.y)
	var p0: Vector3
	var p1: Vector3
	if d.x == 1:
		p0 = Vector3(x + 1, 0, y + 1)
		p1 = Vector3(x + 1, 0, y)
	elif d.x == -1:
		p0 = Vector3(x, 0, y)
		p1 = Vector3(x, 0, y + 1)
	elif d.y == 1:
		p0 = Vector3(x, 0, y + 1)
		p1 = Vector3(x + 1, 0, y + 1)
	else:
		p0 = Vector3(x + 1, 0, y)
		p1 = Vector3(x, 0, y)
	# a jagged rock face: the edges stay put (so neighbouring faces and the grass meet),
	# the inside bulges outward by a noise amount that depends only on world position
	var cols := 3
	var rows := maxi(1, int(ceil((top - bottom) / 0.28)))
	var grid: Array = []
	for r in rows + 1:
		var line: Array = []
		var fy := float(r) / rows
		for c in cols + 1:
			var fx := float(c) / cols
			var v := p0.lerp(p1, fx) + Vector3(0, lerpf(top, bottom, fy), 0)
			if r > 0 and r < rows and c > 0 and c < cols and top - bottom > 0.3:
				var j := _hash3(v)
				v += n * (0.05 + 0.13 * j.x) + Vector3(0, (j.y - 0.5) * 0.08, 0)
				v += (p1 - p0).normalized() * (j.z - 0.5) * 0.12
			line.append(v)
		grid.append(line)
	for r in rows:
		for c in cols:
			var a: Vector3 = grid[r][c]
			var b: Vector3 = grid[r][c + 1]
			var cc: Vector3 = grid[r + 1][c + 1]
			var e: Vector3 = grid[r + 1][c]
			_tri(st, a, b, cc, n, uv)
			_tri(st, a, cc, e, n, uv)


## Flat-shaded triangle; the facet normal is pulled toward the wall normal so faces stay
## readable as cliffs (the shader colours anything steep as rock).
static func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, uv: Vector2) -> void:
	var fn := (c - a).cross(b - a).normalized()
	if fn.dot(n) < 0.0:
		fn = -fn
	fn = (fn + n * 0.6).normalized()
	for v in [a, b, c]:
		st.set_normal(fn)
		st.set_uv(uv)
		st.add_vertex(v)


static func _hash3(v: Vector3) -> Vector3:
	var k := Vector3(v.x * 12.9898 + v.y * 78.233 + v.z * 37.719, v.x * 39.346 + v.y * 11.135 + v.z * 83.155, v.x * 73.156 + v.y * 52.235 + v.z * 9.151)
	return Vector3(fposmod(sin(k.x) * 43758.5453, 1.0), fposmod(sin(k.y) * 43758.5453, 1.0), fposmod(sin(k.z) * 43758.5453, 1.0))


func _build_decor() -> void:
	decor = Node3D.new()
	decor.name = "Decor"
	add_child(decor)
	var rng := Rng.new(Rng.sub_seed(board.seed, [1201, board.version]))  # cosmetic stream
	var tufts: Array[Transform3D] = []
	var rocks: Array[Transform3D] = []
	var boulders: Array[Transform3D] = []
	for y in Bal.GRID_H:
		for x in Bal.GRID_W:
			var k := _kind(x, y)
			if k != 0.0:
				continue
			# scree: boulders at the foot of a taller neighbour's cliff
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if Board.in_grid(nx, ny) and board.h(nx, ny) > board.h(x, y) and rng.next() < 0.45:
					var bs := rng.range_f(0.14, 0.32)
					var along := rng.range_f(0.1, 0.9)
					var bx: float = x + 0.5 + d.x * 0.36 + (along - 0.5) * absf(d.y)
					var bz: float = y + 0.5 + d.y * 0.36 + (along - 0.5) * absf(d.x)
					var basis := Basis.from_euler(Vector3(rng.range_f(-0.4, 0.4), rng.range_f(0, TAU), rng.range_f(-0.4, 0.4)))
					boulders.append(Transform3D(basis.scaled(Vector3(bs * 1.2, bs * 0.8, bs)), Vector3(bx, board.h(x, y) * Kit.LH + bs * 0.25, bz)))
			var r := rng.next()
			var top := board.h(x, y) * Kit.LH
			if r < 0.16:
				var s := rng.range_f(0.5, 1.1)
				tufts.append(Transform3D(Basis(Vector3.UP, rng.range_f(0, TAU)).scaled(Vector3(s, s * rng.range_f(0.8, 1.4), s)), Vector3(x + rng.next(), top, y + rng.next())))
			elif r < 0.175:
				var s2 := rng.range_f(0.12, 0.3)
				rocks.append(Transform3D(Basis(Vector3.UP, rng.range_f(0, TAU)).scaled(Vector3(s2 * 1.3, s2 * 0.7, s2)), Vector3(x + rng.next(), top + s2 * 0.2, y + rng.next())))
	decor.add_child(_multimesh(_tuft_mesh(), Kit.std("grass", Color(0.24, 0.32, 0.26), 0.0, 0.9), tufts))
	decor.add_child(_multimesh(Kit.sphere(1.0, 7), Kit.stone(Color(0.25, 0.27, 0.32)), rocks))
	if not boulders.is_empty():
		decor.add_child(_multimesh(_boulder_mesh(), Kit.std("boulder", Color(0.27, 0.28, 0.32), 0.0, 0.92), boulders))


static func _multimesh(mesh: Mesh, mat: Material, xf: Array[Transform3D]) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	if mat != null:
		mmi.material_override = mat
	return mmi


## A tuft of grass: a few crossed blades.
static func _tuft_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in 5:
		var a := TAU * i / 5.0
		var dir := Vector3(cos(a), 0, sin(a))
		var side := Vector3(-dir.z, 0, dir.x) * 0.035
		var tip := dir * 0.12 + Vector3(0, 0.26 + 0.05 * (i % 2), 0)
		st.set_normal(Vector3(dir.x, 0.6, dir.z).normalized())
		st.add_vertex(-side)
		st.add_vertex(side)
		st.add_vertex(tip)
		st.add_vertex(side)
		st.add_vertex(-side)
		st.add_vertex(tip)
	return st.commit()


## Where the sim cell (x, y) sits in the world (cell centre, on top of the ground).
func cell_pos(x: float, y: float) -> Vector3:
	var cx := clampi(floori(x), 0, Bal.GRID_W - 1)
	var cy := clampi(floori(y), 0, Bal.GRID_H - 1)
	return Vector3(x, board.h(cx, cy) * Kit.LH, y)


## A low-poly faceted boulder (an icosphere-ish hull with jittered points).
static func _boulder_mesh() -> ArrayMesh:
	var src := SphereMesh.new()
	src.radius = 1.0
	src.height = 1.6
	src.radial_segments = 7
	src.rings = 4
	var arr := src.get_mesh_arrays()
	var verts: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
	var idx: PackedInt32Array = arr[Mesh.ARRAY_INDEX]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var moved := PackedVector3Array()
	for v in verts:
		var j := _hash3(v.snapped(Vector3.ONE * 0.01))
		moved.append(v * (0.8 + 0.35 * j.x))
	for i in range(0, idx.size(), 3):
		var a := moved[idx[i]]
		var b := moved[idx[i + 1]]
		var c := moved[idx[i + 2]]
		var n := (b - a).cross(c - a).normalized()
		if n.dot((a + b + c) / 3.0) < 0.0:
			n = -n
		for v in [a, b, c]:
			st.set_normal(n)
			st.add_vertex(v)
	return st.commit()


# ------------------------------------------------------------------ the outer landscape
static func _ensure_noise() -> void:
	if _noise != null:
		return
	_noise = FastNoiseLite.new()
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.018
	_noise.fractal_octaves = 4
	_ridge = FastNoiseLite.new()
	_ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_ridge.frequency = 0.006
	_ridge.fractal_type = FastNoiseLite.FRACTAL_RIDGED
	_ridge.fractal_octaves = 4


static func _edge_dist(x: float, z: float) -> float:
	var dx := maxf(maxf(-x, x - Bal.GRID_W), 0.0)
	var dz := maxf(maxf(-z, z - Bal.GRID_H), 0.0)
	return sqrt(dx * dx + dz * dz)


## Height of the landscape outside the board. At the board's edge it tucks just under the
## nearest edge cells (so no seam shows), then rolls into hills and, further out, mountains.
static func outer_height(x: float, z: float) -> float:
	_ensure_noise()
	var d := _edge_dist(x, z)
	var lip := -1.0
	if _board_ref != null:
		var cx := clampi(floori(x), 0, Bal.GRID_W - 1)
		var cz := clampi(floori(z), 0, Bal.GRID_H - 1)
		var lo := 99
		for k in range(-4, 5):
			var sx := clampi(cx + (k if (x >= 0.0 and x < Bal.GRID_W) else 0), 0, Bal.GRID_W - 1)
			var sz := clampi(cz + (k if (z >= 0.0 and z < Bal.GRID_H) else 0), 0, Bal.GRID_H - 1)
			lo = mini(lo, _board_ref.h(sx, sz))
		lip = lo * Kit.LH - 0.35
	var hills := _noise.get_noise_2d(x, z) * 2.6 + 1.2
	var ridge := maxf(0.0, _ridge.get_noise_2d(x, z) + 0.15)
	var mountains := ridge * ridge * 46.0 + ridge * 8.0
	var near := smoothstep(0.0, 14.0, d)
	var far := smoothstep(30.0, 120.0, d)
	return lip + near * (hills + d * 0.025) + far * mountains


func _build_outer() -> void:
	if outer != null:
		outer.queue_free()
	outer_seed = board.seed
	_ensure_noise()
	_noise.seed = board.seed
	_ridge.seed = board.seed + 77
	outer = Node3D.new()
	outer.name = "Landscape"
	add_child(outer)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var s := OUTER_STEP
	var x0 := -OUTER_REACH
	var z0 := -OUTER_REACH
	var nx := int((Bal.GRID_W + 2.0 * OUTER_REACH) / s)
	var nz := int((Bal.GRID_H + 2.0 * OUTER_REACH) / s)
	var hs := PackedFloat32Array()
	hs.resize((nx + 1) * (nz + 1))
	for j in nz + 1:
		for i in nx + 1:
			hs[j * (nx + 1) + i] = outer_height(x0 + i * s, z0 + j * s)
	for j in nz:
		for i in nx:
			var cx := x0 + (i + 0.5) * s
			var cz := z0 + (j + 0.5) * s
			if cx > 0.0 and cx < Bal.GRID_W and cz > 0.0 and cz < Bal.GRID_H:
				continue
			var q := [Vector2i(i, j), Vector2i(i + 1, j), Vector2i(i + 1, j + 1), Vector2i(i, j + 1)]
			var p: Array[Vector3] = []
			var nrm: Array[Vector3] = []
			for c in q:
				var hh: float = hs[c.y * (nx + 1) + c.x]
				p.append(Vector3(x0 + c.x * s, hh, z0 + c.y * s))
				var hl: float = hs[c.y * (nx + 1) + maxi(c.x - 1, 0)]
				var hr: float = hs[c.y * (nx + 1) + mini(c.x + 1, nx)]
				var hd: float = hs[maxi(c.y - 1, 0) * (nx + 1) + c.x]
				var hu: float = hs[mini(c.y + 1, nz) * (nx + 1) + c.x]
				nrm.append(Vector3(hl - hr, 2.0 * s, hd - hu).normalized())
			for k in [0, 1, 2, 0, 2, 3]:
				st.set_normal(nrm[k])
				st.set_uv(Vector2(7.0, p[k].y / Kit.LH))
				st.add_vertex(p[k])
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = Kit.ground_material()
	mi.name = "Hills"
	outer.add_child(mi)
	# pine woods in clusters on the gentler slopes, thinning out up the mountains
	var rng := Rng.new(Rng.sub_seed(board.seed, [1301]))
	var pines: Array[Transform3D] = []
	var stones: Array[Transform3D] = []
	var tries := 9000
	for t in tries:
		var x := rng.range_f(-150.0, Bal.GRID_W + 150.0)
		var z := rng.range_f(-150.0, Bal.GRID_H + 150.0)
		var d := _edge_dist(x, z)
		if d < 2.5:
			continue
		var y := outer_height(x, z)
		var slope := absf(outer_height(x + 1.0, z) - y) + absf(outer_height(x, z + 1.0) - y)
		var cluster := _noise.get_noise_2d(x * 2.3 + 400.0, z * 2.3)
		if slope < 0.7 and cluster > 0.05 and y < 14.0:
			var sc := rng.range_f(1.4, 2.6) * (1.0 + clampf(d / 80.0, 0.0, 1.0))
			pines.append(Transform3D(Basis(Vector3.UP, rng.range_f(0, TAU)).scaled(Vector3(sc, sc * rng.range_f(0.9, 1.3), sc)), Vector3(x, y - 0.1, z)))
		elif slope < 1.4 and rng.next() < 0.08:
			var bs := rng.range_f(0.4, 1.4)
			stones.append(Transform3D(Basis.from_euler(Vector3(rng.range_f(-0.3, 0.3), rng.range_f(0, TAU), 0)).scaled(Vector3(bs * 1.3, bs * 0.8, bs)), Vector3(x, y, z)))
	outer.add_child(_multimesh(EcoView._tree_mesh(), null, pines))
	outer.add_child(_multimesh(_boulder_mesh(), Kit.std("boulder", Color(0.27, 0.28, 0.32), 0.0, 0.92), stones))
