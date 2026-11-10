class_name TerrainView
extends Node3D
## Terraced ground, cobbled roads, glowing ore veins, the paved base plaza, grass tufts and rocks.
## Rebuilt whenever the board's road version changes.

var board: Board
var ground: MeshInstance3D
var decor: Node3D
var built_version := -1
var pending_overlay: MeshInstance3D
var extra_kind: Callable  ## economy: cell -> kind override (forest floor, lake bed, mud)


static func cell_y(b: Board, x: int, y: int) -> float:
	if not Board.in_grid(x, y):
		return 0.0
	return b.h(x, y) * Kit.LH


func setup(b: Board) -> void:
	board = b
	built_version = -1
	rebuild()


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
	var a := p0 + Vector3(0, top, 0)
	var b := p1 + Vector3(0, top, 0)
	var c := p1 + Vector3(0, bottom, 0)
	var e := p0 + Vector3(0, bottom, 0)
	for v in [a, b, c, a, c, e]:
		st.set_normal(n)
		st.set_uv(uv)
		st.add_vertex(v)


func _build_decor() -> void:
	decor = Node3D.new()
	decor.name = "Decor"
	add_child(decor)
	var rng := Rng.new(Rng.sub_seed(board.seed, [1201, board.version]))  # cosmetic stream
	var tufts: Array[Transform3D] = []
	var rocks: Array[Transform3D] = []
	for y in Bal.GRID_H:
		for x in Bal.GRID_W:
			var k := _kind(x, y)
			if k != 0.0:
				continue
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


static func _multimesh(mesh: Mesh, mat: Material, xf: Array[Transform3D]) -> MultiMeshInstance3D:
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xf.size()
	for i in xf.size():
		mm.set_instance_transform(i, xf[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
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
