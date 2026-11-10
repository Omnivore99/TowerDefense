class_name EcoView
extends Node3D
## Forests (instanced trees and stumps), lakes (water that visibly drains), pimples
## (glossy domes that ripen and turn), permanent craters, and the working machines on
## harvest structures (mines, lumber camps, pumps).

const PIMPLE_SHADER := """
shader_type spatial;
render_mode cull_back;
uniform float turn = 0.0;      // 0 white .. 1 black
uniform float ripe = 0.0;      // 1 while ripe (glint)
uniform float t = 0.0;
uniform vec3 tint : source_color = vec3(1.0);
varying vec3 lp;
void vertex(){ lp = VERTEX; }
void fragment(){
	vec3 white = mix(vec3(0.96, 0.95, 0.92), tint, 0.12);
	vec3 dull = vec3(0.62, 0.58, 0.40);
	vec3 black = vec3(0.07, 0.065, 0.06);
	vec3 c = turn < 0.5 ? mix(white, dull, turn * 2.0) : mix(dull, black, (turn - 0.5) * 2.0);
	ALBEDO = c;
	ROUGHNESS = mix(0.08, 0.85, turn);
	SPECULAR = mix(0.9, 0.2, turn);
	CLEARCOAT = 1.0 - turn;
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 3.0);
	// a glint sweeps across every 1.618 s while ripe
	float g = fract(t / 1.618);
	float sweep = smoothstep(0.06, 0.0, abs(lp.x * 1.4 + lp.y - (g * 3.0 - 1.2)));
	EMISSION = vec3(1.0) * sweep * ripe * 2.5 + tint * fres * 0.25 * (1.0 - turn);
}
"""

const WATER_SHADER := """
shader_type spatial;
render_mode cull_back, blend_mix, depth_draw_always;
uniform float t = 0.0;
varying vec3 wp;
void vertex(){ wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment(){
	float r = sin(wp.x * 2.1 + t * 1.3) * 0.5 + sin(wp.z * 1.7 - t * 1.1) * 0.5;
	vec3 deep = vec3(0.04, 0.10, 0.16);
	vec3 shallow = vec3(0.10, 0.26, 0.32);
	ALBEDO = mix(deep, shallow, 0.5 + 0.2 * r);
	ROUGHNESS = 0.05;
	METALLIC = 0.0;
	SPECULAR = 0.9;
	NORMAL_MAP = normalize(vec3(0.5 + 0.06 * r, 0.5 + 0.06 * cos(wp.x * 3.0 + t), 1.0));
	ALPHA = 0.86;
}
"""

const RES_COLOR := {"ore": Color(0.95, 0.55, 0.25), "timber": Color(1.0, 0.75, 0.3), "water": Color(0.55, 0.85, 1.0)}

var w  # World
var eco: Economy
var built := -1
var trees_mm: MultiMeshInstance3D
var stumps_mm: MultiMeshInstance3D
var craters_mm: MultiMeshInstance3D
var lake_nodes := {}  ## lake id -> MeshInstance3D
var pimple_nodes := {}  ## pimple id -> MeshInstance3D
var pimple_mat_shader: Shader
var water_mat: ShaderMaterial
var machines := {}  ## harvester id -> {node, kind, parts}
var t := 0.0


func setup(world, e: Economy) -> void:
	w = world
	eco = e
	built = -1
	for c in get_children():
		c.queue_free()
	lake_nodes.clear()
	pimple_nodes.clear()
	machines.clear()
	trees_mm = _mm(_tree_mesh(), null)
	stumps_mm = _mm(Kit.cylinder(0.14, 0.17, 0.16, 8), Kit.wood())
	var crater_mat := StandardMaterial3D.new()
	crater_mat.albedo_color = Color(0.09, 0.08, 0.07)
	crater_mat.roughness = 1.0
	craters_mm = _mm(Kit.torus(0.18, 0.36, 14), crater_mat)
	pimple_mat_shader = Shader.new()
	pimple_mat_shader.code = PIMPLE_SHADER
	var ws := Shader.new()
	ws.code = WATER_SHADER
	water_mat = ShaderMaterial.new()
	water_mat.shader = ws


func _mm(mesh: Mesh, mat: Material) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mmi.multimesh = mm
	if mat != null:
		mmi.material_override = mat
	add_child(mmi)
	return mmi


## A stylised dusk pine: dark trunk and three stacked cones, built into one mesh.
static func _tree_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var trunk := Kit.cylinder(0.07, 0.1, 0.5, 6)
	var xf := Transform3D(Basis(), Vector3(0, 0.25, 0))
	st.set_color(Color(0.28, 0.2, 0.14))
	st.append_from(trunk, 0, xf)
	var layers := [[0.55, 0.75, 0.55], [0.44, 0.65, 0.95], [0.3, 0.55, 1.3]]
	for l in layers:
		var cone := Kit.cone(l[0], l[1], 8)
		st.append_from(cone, 0, Transform3D(Basis(), Vector3(0, l[2], 0)))
	var mesh := st.commit()
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.16, 0.27, 0.19)
	m.roughness = 0.85
	mesh.surface_set_material(0, m)
	return mesh


func _cell_xyz(i: int, lift: float = 0.0) -> Vector3:
	var x := i % Bal.GRID_W
	var y := i / Bal.GRID_W
	return Vector3(x + 0.5, w.g.board.h(x, y) * Kit.LH + lift, y + 0.5)


static func _hash(i: int) -> float:
	var h := (i * 2654435761) & 0xFFFFFFFF
	return float(h % 10007) / 10007.0


# ------------------------------------------------------------------ rebuild on change
func sync(delta: float) -> void:
	t += delta
	if eco.version != built:
		built = eco.version
		_rebuild_static()
	_sync_pimples()
	_sync_machines(delta)
	water_mat.set_shader_parameter("t", t)


func _rebuild_static() -> void:
	var trees: Array[Transform3D] = []
	var stumps: Array[Transform3D] = []
	for f in eco.forests:
		for c in f.cells:
			var tv: int = eco.tree[c]
			if tv == 0:
				continue
			var hh := _hash(c)
			var pos := _cell_xyz(c) + Vector3((hh - 0.5) * 0.4, 0, (_hash(c + 7) - 0.5) * 0.4)
			var b := Basis(Vector3.UP, hh * TAU)
			if tv == 1:
				trees.append(Transform3D(b.scaled(Vector3.ONE * (0.85 + 0.5 * hh)), pos))
			else:
				stumps.append(Transform3D(b, pos + Vector3(0, 0.08, 0)))
	_fill(trees_mm, trees)
	_fill(stumps_mm, stumps)
	var cr: Array[Transform3D] = []
	for c in eco.craters:
		cr.append(Transform3D(Basis().scaled(Vector3(1, 0.25, 1)), _cell_xyz(c.cell, 0.02)))
	_fill(craters_mm, cr)
	# lakes
	for l in eco.lakes:
		var n: MeshInstance3D = lake_nodes.get(l.id)
		if n == null:
			n = MeshInstance3D.new()
			n.mesh = _lake_mesh(l)
			n.material_override = water_mat
			n.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(n)
			lake_nodes[l.id] = n
		var full: float = l.units / maxf(1.0, l.max)
		n.visible = eco.water[l.cells[0]] == 1
		n.position.y = Kit.LH * (0.15 + 0.8 * full)


func _fill(mmi: MultiMeshInstance3D, xs: Array[Transform3D]) -> void:
	mmi.multimesh.instance_count = xs.size()
	for i in xs.size():
		mmi.multimesh.set_instance_transform(i, xs[i])


func _lake_mesh(l: Dictionary) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var base_y: float = w.g.board.height[l.cells[0]] * Kit.LH
	for c in l.cells:
		var x: float = c % Bal.GRID_W
		var z: float = c / Bal.GRID_W
		var a := Vector3(x, base_y, z)
		st.set_normal(Vector3.UP)
		st.add_vertex(a)
		st.add_vertex(a + Vector3(1, 0, 0))
		st.add_vertex(a + Vector3(1, 0, 1))
		st.add_vertex(a)
		st.add_vertex(a + Vector3(1, 0, 1))
		st.add_vertex(a + Vector3(0, 0, 1))
	return st.commit()


# ------------------------------------------------------------------ pimples
func _sync_pimples() -> void:
	var seen := {}
	for p in eco.pimples:
		seen[p.id] = true
		var n: MeshInstance3D = pimple_nodes.get(p.id)
		if n == null:
			n = MeshInstance3D.new()
			n.mesh = Kit.sphere(0.4, 18, true)
			var m := ShaderMaterial.new()
			m.shader = pimple_mat_shader
			m.set_shader_parameter("tint", RES_COLOR[eco.resource_of(p.node)])
			n.material_override = m
			add_child(n)
			n.position = _cell_xyz(p.cell)
			n.scale = Vector3.ONE * 0.05
			pimple_nodes[p.id] = n
		var gr := eco.growth(p)
		var st := eco.stage(p)
		var beat := 0.0
		if st == "ripe":
			var ph := fmod(t, 1.0)
			beat = 0.05 * exp(-ph * 8.0) + 0.03 * exp(-maxf(0.0, ph - 0.18) * 8.0) * float(ph > 0.18)
		var goal := Vector3(gr, gr * (0.85 + 0.15 * gr), gr) * (1.0 + beat) + Vector3(1, 1, 1) * 0.02 * sin(t * 2.0 + p.id)
		n.scale = n.scale.lerp(goal, 0.15)
		var mat := n.material_override as ShaderMaterial
		mat.set_shader_parameter("turn", eco.turn(p) if st == "turning" else 0.0)
		mat.set_shader_parameter("ripe", 1.0 if st == "ripe" else 0.0)
		mat.set_shader_parameter("t", t + p.id)
	for id in pimple_nodes.keys():
		if not seen.has(id):
			pimple_nodes[id].queue_free()
			pimple_nodes.erase(id)


func pimple_world(cell: int) -> Vector3:
	return _cell_xyz(cell, 0.3)


## Hover text for a pimple: stage, value in %, and waves left at this value.
func pimple_hint(p: Dictionary) -> String:
	var st := eco.stage(p)
	var pct := roundi(eco.value_frac(p) * 100.0)
	var res := eco.resource_of(p.node)
	var v := roundf(eco.base_value(p) * eco.value_frac(p))
	var left := ""
	match st:
		"growing":
			left = "ripe in %d wave%s" % [p.M - p.age - 1, "" if p.M - p.age - 1 == 1 else "s"]
		"ripe":
			left = "[color=#ffffff]RIPE now[/color], 1 in 3 holds a Pearl"
		"turning":
			left = "turning: %d wave%s until it withers" % [p.M + p.T - p.age, "" if p.M + p.T - p.age == 1 else "s"]
	return "[b]Pimple[/b] · %s · %d%% (%d %s) · %s\n[color=#8a93a6]Click to pop with the Lance (%d charge%s left)[/color]" % [st, pct, v, res, left, eco.charges(), "" if eco.charges() == 1 else "s"]


# ------------------------------------------------------------------ harvest machines
func _sync_machines(delta: float) -> void:
	var seen := {}
	for h in w.g.harvesters:
		seen[h.id] = true
		var m: Dictionary = machines.get(h.id, {})
		if m.is_empty():
			m = _build_machine(h)
			machines[h.id] = m
		_animate(m, h, delta)
	for id in machines.keys():
		if not seen.has(id):
			machines[id].node.queue_free()
			machines.erase(id)


func _build_machine(h: Dictionary) -> Dictionary:
	var n := Node3D.new()
	add_child(n)
	var mat := Kit.piece_block(h.piece.color, h.piece.golden)
	var seam := Kit.glow(Bal.PIECE_GLOW.get(h.piece.color, Color(1, 0.6, 0.2)), 1.3)
	var ctr := Vector3.ZERO
	for c in h.cells:
		var p := _cell_xyz(Board.cell_idx(c.x, c.y))
		ctr += p
		Kit.add(n, Kit.bevel_box(Vector3(0.86, 0.3, 0.86), 0.06), mat, p + Vector3(0, 0.15, 0))
		Kit.add(n, Kit.box(Vector3(0.9, 0.03, 0.9)), seam, p + Vector3(0, 0.015, 0))
	ctr /= float(h.cells.size())
	var parts := {}
	match h.get("node", "ore"):
		"ore":
			# smoke stack, conveyor with ore chunks, drill rig
			var c0 := _cell_xyz(Board.cell_idx(h.cells[0].x, h.cells[0].y))
			Kit.add(n, Kit.cylinder(0.09, 0.12, 0.8, 8), Kit.dark_iron(), c0 + Vector3(0.2, 0.7, 0.2))
			parts.stack = c0 + Vector3(0.2, 1.15, 0.2)
			var drill := Kit.add(n, Kit.cone(0.17, 0.5, 8), Kit.brass(), ctr + Vector3(0, 0.6, 0), Vector3(PI, 0, 0))
			parts.drill = drill
			var belt := Kit.add(n, Kit.box(Vector3(1.4, 0.05, 0.22)), Kit.dark_iron(), ctr + Vector3(0, 0.34, 0.35))
			parts.chunks = []
			for k in 3:
				var ch := Kit.add(n, Kit.box(Vector3(0.1, 0.08, 0.1)), Kit.glow(Color(1, 0.55, 0.2), 1.5), belt.position + Vector3(-0.6 + 0.4 * k, 0.07, 0))
				parts.chunks.append(ch)
			parts.belt_x = belt.position.x
		"forest":
			# a chopping arm with an axe head, and a log pile
			var arm := Node3D.new()
			arm.position = ctr + Vector3(0, 0.55, 0)
			n.add_child(arm)
			Kit.add(arm, Kit.box(Vector3(0.06, 0.06, 0.6)), Kit.wood(), Vector3(0, 0, 0.3))
			Kit.add(arm, Kit.box(Vector3(0.22, 0.14, 0.04)), Kit.iron(), Vector3(0, 0, 0.6))
			parts.arm = arm
			for k in 3:
				Kit.add(n, Kit.cylinder(0.07, 0.07, 0.6, 8), Kit.wood(), ctr + Vector3(-0.3, 0.38 + 0.12 * (k % 2), -0.25 + 0.15 * k), Vector3(0, 0, PI / 2.0))
		"lake":
			# pump house with a nodding beam and a pipe toward the water
			var house := Kit.add(n, Kit.bevel_box(Vector3(0.5, 0.4, 0.5), 0.05), Kit.stone(), ctr + Vector3(0, 0.5, 0))
			Kit.add(n, Kit.cone(0.42, 0.25, 4), Kit.roof(), house.position + Vector3(0, 0.32, 0), Vector3(0, PI / 4.0, 0))
			var beam := Node3D.new()
			beam.position = ctr + Vector3(0, 1.0, 0)
			n.add_child(beam)
			Kit.add(beam, Kit.box(Vector3(0.9, 0.06, 0.08)), Kit.dark_iron())
			Kit.add(beam, Kit.box(Vector3(0.12, 0.3, 0.12)), Kit.iron(), Vector3(0.45, -0.15, 0))
			parts.beam = beam
			var lk: int = h.get("lake", 0)
			if lk > 0:
				var l: Dictionary = eco.lakes[lk - 1]
				var best := Vector3.ZERO
				var bd := INF
				for c in l.cells:
					var p2 := _cell_xyz(c)
					var d := p2.distance_squared_to(ctr)
					if d < bd:
						bd = d
						best = p2
				Kit.pipe(n, ctr + Vector3(0, 0.35, 0), Vector3(best.x, ctr.y + 0.2, best.z), 0.05, Kit.copper())
	return {"node": n, "parts": parts, "kind": h.get("node", "ore"), "puff": 0.0, "chop": 0.0}


func _animate(m: Dictionary, h: Dictionary, delta: float) -> void:
	var p: Dictionary = m.parts
	var working: bool = w.g.phase == "wave" or w.g.phase == "calm"
	if not working:
		return
	match m.kind:
		"ore":
			p.drill.rotation.y += delta * 6.0
			p.drill.position.y = p.drill.position.y + sin(t * 4.0 + h.id) * 0.004
			for ch in p.chunks:
				ch.position.x += delta * 0.4
				if ch.position.x > p.belt_x + 0.65:
					ch.position.x -= 1.3
			m.puff -= delta
			if m.puff <= 0.0:
				m.puff = 1.2 + _hash(h.id) * 0.6
				w.fx.smoke(p.stack, 2, Color(0.55, 0.55, 0.58, 0.45), 0.16, 1.6, 0.9)
		"forest":
			# chop, chop, chop: three swings, the third heavier, then a pause
			m.chop += delta
			var cyc := fmod(m.chop, 2.4)
			var k := int(cyc / 0.5)
			var f := fmod(cyc, 0.5) / 0.5
			if k < 3:
				p.arm.rotation.x = -1.2 * (1.0 - f) * (1.0 - f) + 0.15
				if f < delta / 0.5 and w.sfx != null:
					w.sfx.play_at("chop", p.arm.global_position, -6.0 if k < 2 else -2.0, 1.0 if k < 2 else 0.85)
			else:
				p.arm.rotation.x = lerpf(p.arm.rotation.x, -1.0, 0.1)
		"lake":
			p.beam.rotation.z = sin(t * 2.2 + h.id) * 0.35
