class_name Fx
extends Node3D
## Pooled, capped effects: puffs (smoke, dust, goo), sparks, brass casings that bounce and
## tinkle, debris, glowing ribbons (tracers, beams, bolts, smoke streaks), rings and decals.
## Oldest effects fade first. Particle counts scale with the quality preset; gameplay never does.

signal casing_landed(pos: Vector3)

const CAPS := {"puff": 900, "spark": 600, "casing": 400, "debris": 300, "ring": 80, "decal": 300, "glob": 240}

var cam: Camera3D
var quality := 1.0  ## 0.5 on the Web preset
var reduced_motion := false
var pools := {}
var ribbons: Array = []  ## {a, b, w, c, life, max, kind, pts}
var ribbon_mesh: ImmediateMesh
var ribbon_add: ImmediateMesh
var rings: Array = []
var decals: Array = []
var decal_root: Node3D
var ground_y: Callable  ## (x, z) -> ground height


class Pool:
	var mm: MultiMesh
	var node: MultiMeshInstance3D
	var cap := 0
	var pos: PackedVector3Array = PackedVector3Array()
	var vel: PackedVector3Array = PackedVector3Array()
	var life: PackedFloat32Array = PackedFloat32Array()
	var maxl: PackedFloat32Array = PackedFloat32Array()
	var size: PackedFloat32Array = PackedFloat32Array()
	var grow: PackedFloat32Array = PackedFloat32Array()
	var col: PackedColorArray = PackedColorArray()
	var grav: PackedFloat32Array = PackedFloat32Array()
	var drag: PackedFloat32Array = PackedFloat32Array()
	var spin: PackedVector3Array = PackedVector3Array()
	var rot: PackedVector3Array = PackedVector3Array()
	var bounced: PackedByteArray = PackedByteArray()
	var n := 0


func _ready() -> void:
	_pool("puff", Kit.sphere(1.0, 8), _particle_mat(false))
	_pool("spark", Kit.sphere(1.0, 6), _particle_mat(true))
	_pool("glob", Kit.sphere(1.0, 8), _glob_mat())
	_pool("casing", Kit.cylinder(0.035, 0.035, 0.13, 6), _casing_mat())
	_pool("debris", Kit.box(Vector3.ONE), _debris_mat())
	ribbon_mesh = ImmediateMesh.new()
	var rmi := MeshInstance3D.new()
	rmi.mesh = ribbon_mesh
	rmi.material_override = _ribbon_mat(false)
	add_child(rmi)
	ribbon_add = ImmediateMesh.new()
	var rmi2 := MeshInstance3D.new()
	rmi2.mesh = ribbon_add
	rmi2.material_override = _ribbon_mat(true)
	add_child(rmi2)
	decal_root = Node3D.new()
	add_child(decal_root)


func _particle_mat(additive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.disable_receive_shadows = true
	return m


func _glob_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.vertex_color_use_as_albedo = true
	m.roughness = 0.1
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = Color(0.3, 0.3, 0.3)
	return m


func _casing_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.85, 0.62, 0.25)
	m.metallic = 1.0
	m.roughness = 0.25
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _debris_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.3, 0.3, 0.34)
	m.roughness = 0.9
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return m


func _ribbon_mat(additive: bool) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	return m


func _pool(name_id: String, mesh: Mesh, mat: Material) -> void:
	var p := Pool.new()
	p.cap = CAPS[name_id]
	p.mm = MultiMesh.new()
	p.mm.transform_format = MultiMesh.TRANSFORM_3D
	p.mm.use_colors = true
	p.mm.mesh = mesh
	p.mm.instance_count = p.cap
	p.mm.visible_instance_count = 0
	p.node = MultiMeshInstance3D.new()
	p.node.multimesh = p.mm
	p.node.material_override = mat
	p.node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if name_id != "casing" and name_id != "debris" else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(p.node)
	for arr in [p.pos, p.vel, p.spin, p.rot]:
		arr.resize(p.cap)
	for arr in [p.life, p.maxl, p.size, p.grow, p.grav, p.drag]:
		arr.resize(p.cap)
	p.col.resize(p.cap)
	p.bounced.resize(p.cap)
	pools[name_id] = p


## Emit one particle. Returns false when the pool is full (the oldest is replaced).
func emit(pool_id: String, pos: Vector3, vel: Vector3, life: float, size: float, col: Color, grav: float = 0.0, drag: float = 0.0, grow: float = 0.0) -> void:
	var p: Pool = pools[pool_id]
	var i := p.n
	if p.n >= p.cap:
		# replace the oldest (smallest remaining life fraction)
		var worst := 0
		var wl := 9.0
		for k in p.cap:
			var f := p.life[k] / p.maxl[k]
			if f < wl:
				wl = f
				worst = k
		i = worst
	else:
		p.n += 1
	p.pos[i] = pos
	p.vel[i] = vel
	p.life[i] = life
	p.maxl[i] = life
	p.size[i] = size
	p.grow[i] = grow
	p.col[i] = col
	p.grav[i] = grav
	p.drag[i] = drag
	p.spin[i] = Vector3(randf_range(-12, 12), randf_range(-12, 12), randf_range(-12, 12))
	p.rot[i] = Vector3(randf() * TAU, randf() * TAU, 0)
	p.bounced[i] = 0


func _step_pool(id: String, p: Pool, delta: float) -> void:
	var i := 0
	while i < p.n:
		p.life[i] -= delta
		if p.life[i] <= 0.0:
			# swap-remove
			var last := p.n - 1
			p.pos[i] = p.pos[last]
			p.vel[i] = p.vel[last]
			p.life[i] = p.life[last]
			p.maxl[i] = p.maxl[last]
			p.size[i] = p.size[last]
			p.grow[i] = p.grow[last]
			p.col[i] = p.col[last]
			p.grav[i] = p.grav[last]
			p.drag[i] = p.drag[last]
			p.spin[i] = p.spin[last]
			p.rot[i] = p.rot[last]
			p.bounced[i] = p.bounced[last]
			p.n -= 1
			continue
		var v := p.vel[i]
		v.y -= p.grav[i] * delta
		v *= maxf(0.0, 1.0 - p.drag[i] * delta)
		var np := p.pos[i] + v * delta
		if p.grav[i] > 0.0 and ground_y.is_valid():
			var gy: float = ground_y.call(np.x, np.z) + 0.03
			if np.y < gy and v.y < 0.0:
				np.y = gy
				if id == "casing" and p.bounced[i] < 2:
					if p.bounced[i] == 0:
						casing_landed.emit(np)
					v = Vector3(v.x * 0.5, -v.y * 0.35, v.z * 0.5)
					p.bounced[i] += 1
					p.spin[i] *= 0.5
				else:
					v = Vector3(v.x * 0.6, 0.0, v.z * 0.6)
					p.spin[i] *= 0.6
		p.vel[i] = v
		p.pos[i] = np
		p.rot[i] += p.spin[i] * delta
		i += 1
	var mm := p.mm
	for k in p.n:
		var f := p.life[k] / p.maxl[k]
		var s := p.size[k] * (1.0 + p.grow[k] * (1.0 - f))
		var b := Basis.from_euler(p.rot[k]).scaled(Vector3.ONE * s) if (id == "casing" or id == "debris") else Basis().scaled(Vector3.ONE * s)
		mm.set_instance_transform(k, Transform3D(b, p.pos[k]))
		var c := p.col[k]
		var fade := f if id != "casing" else minf(1.0, f * 4.0)
		mm.set_instance_color(k, Color(c.r, c.g, c.b, c.a * fade))
	mm.visible_instance_count = p.n


func _process(delta: float) -> void:
	for id in pools:
		_step_pool(id, pools[id], delta)
	_draw_ribbons(delta)
	_step_rings(delta)
	_step_decals(delta)


# ----------------------------------------------------------------- ribbons (tracers, beams, bolts)
func ribbon(a: Vector3, b: Vector3, w: float, c: Color, life: float, additive: bool = true, jag: int = 0) -> void:
	var pts := PackedVector3Array([a])
	if jag > 0:
		var n := jag
		for i in range(1, n):
			var t := float(i) / n
			var p := a.lerp(b, t)
			var amp := a.distance_to(b) * 0.08
			pts.append(p + Vector3(randf_range(-amp, amp), randf_range(-amp, amp) * 0.6, randf_range(-amp, amp)))
	pts.append(b)
	ribbons.append({"pts": pts, "w": w, "c": c, "life": life, "max": life, "add": additive})


func _draw_ribbons(delta: float) -> void:
	ribbon_mesh.clear_surfaces()
	ribbon_add.clear_surfaces()
	if cam == null:
		return
	var eye := cam.global_position
	var alive: Array = []
	var any_n := false
	var any_a := false
	for r in ribbons:
		r.life -= delta
		if r.life > 0.0:
			alive.append(r)
			if r.add:
				any_a = true
			else:
				any_n = true
	ribbons = alive
	for pass_add in [false, true]:
		if (pass_add and not any_a) or (not pass_add and not any_n):
			continue
		var im: ImmediateMesh = ribbon_add if pass_add else ribbon_mesh
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for r in ribbons:
			if r.add != pass_add:
				continue
			var f: float = r.life / r.max
			var c: Color = r.c
			c.a *= f
			var pts: PackedVector3Array = r.pts
			for i in pts.size() - 1:
				var a := pts[i]
				var b := pts[i + 1]
				var dir := (b - a)
				var side: Vector3 = dir.cross(eye - (a + b) * 0.5).normalized() * r.w * (0.4 + 0.6 * f)
				im.surface_set_color(c)
				im.surface_add_vertex(a - side)
				im.surface_add_vertex(a + side)
				im.surface_add_vertex(b + side)
				im.surface_add_vertex(a - side)
				im.surface_add_vertex(b + side)
				im.surface_add_vertex(b - side)
		im.surface_end()


# ----------------------------------------------------------------- rings (shockwaves, aura pulses)
func ring(pos: Vector3, r0: float, r1: float, life: float, c: Color, flat: bool = true) -> void:
	if rings.size() >= CAPS.ring:
		var old: Dictionary = rings.pop_front()
		old.node.queue_free()
	var mi := MeshInstance3D.new()
	mi.mesh = Kit.torus(0.9, 1.0, 32)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = c
	mi.material_override = m
	mi.position = pos
	if not flat:
		mi.rotation.x = PI / 2.0
	add_child(mi)
	rings.append({"node": mi, "r0": r0, "r1": r1, "life": life, "max": life, "c": c, "mat": m})


func _step_rings(delta: float) -> void:
	var keep: Array = []
	for r in rings:
		r.life -= delta
		if r.life <= 0.0:
			r.node.queue_free()
			continue
		var k: float = 1.0 - r.life / r.max
		var e := 1.0 - pow(1.0 - k, 3.0)
		var rad := lerpf(r.r0, r.r1, e)
		r.node.scale = Vector3(rad, rad * 0.5 + 0.2, rad)
		var c: Color = r.c
		c.a *= 1.0 - k
		r.mat.albedo_color = c
		keep.append(r)
	rings = keep


# ----------------------------------------------------------------- decals (scorch, splat, crater)
func decal(pos: Vector3, radius: float, c: Color, life: float = 6.0, fade_in: float = 0.0) -> MeshInstance3D:
	if decals.size() >= CAPS.decal:
		var old: Dictionary = decals.pop_front()
		old.node.queue_free()
	var mi := MeshInstance3D.new()
	mi.mesh = _decal_mesh()
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.albedo_texture = _decal_tex()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 1.0
	m.metallic_specular = 0.0
	m.disable_receive_shadows = true
	mi.material_override = m
	mi.position = pos + Vector3(0, 0.02 + randf() * 0.01, 0)
	mi.scale = Vector3(radius, 1, radius * randf_range(0.8, 1.0))
	mi.rotation.y = randf() * TAU
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	decal_root.add_child(mi)
	decals.append({"node": mi, "life": life, "max": life, "c": c, "mat": m})
	return mi


static var _dmesh: PlaneMesh
static var _dtex: GradientTexture2D


static func _decal_mesh() -> PlaneMesh:
	if _dmesh == null:
		_dmesh = PlaneMesh.new()
		_dmesh.size = Vector2(2, 2)
	return _dmesh


## Soft round splat: opaque centre, ragged fade to the edge.
static func _decal_tex() -> GradientTexture2D:
	if _dtex == null:
		var gr := Gradient.new()
		gr.set_color(0, Color(1, 1, 1, 1))
		gr.set_color(1, Color(1, 1, 1, 0))
		gr.add_point(0.55, Color(1, 1, 1, 0.85))
		_dtex = GradientTexture2D.new()
		_dtex.gradient = gr
		_dtex.fill = GradientTexture2D.FILL_RADIAL
		_dtex.fill_from = Vector2(0.5, 0.5)
		_dtex.fill_to = Vector2(0.5, 0.0)
		_dtex.width = 64
		_dtex.height = 64
	return _dtex


func _step_decals(delta: float) -> void:
	var keep: Array = []
	for d in decals:
		d.life -= delta
		if d.life <= 0.0:
			d.node.queue_free()
			continue
		var f: float = minf(1.0, d.life / minf(2.0, d.max))
		var c: Color = d.c
		c.a *= f
		d.mat.albedo_color = c
		keep.append(d)
	decals = keep


# ----------------------------------------------------------------- composite effects
func burst(pos: Vector3, n: int, speed: float, c: Color, size: float = 0.12, life: float = 0.5, pool: String = "spark", grav: float = 6.0) -> void:
	var count := maxi(1, int(n * quality))
	for i in count:
		var d := Vector3(randf_range(-1, 1), randf_range(0.2, 1.2), randf_range(-1, 1)).normalized()
		emit(pool, pos, d * speed * randf_range(0.4, 1.0), life * randf_range(0.6, 1.2), size * randf_range(0.6, 1.3), c, grav, 1.5)


func smoke(pos: Vector3, n: int, c: Color = Color(0.55, 0.57, 0.62, 0.5), size: float = 0.25, life: float = 1.6, rise: float = 0.8) -> void:
	var count := maxi(1, int(n * quality))
	for i in count:
		var v := Vector3(randf_range(-0.4, 0.4), rise * randf_range(0.5, 1.2), randf_range(-0.4, 0.4))
		emit("puff", pos + Vector3(randf_range(-0.1, 0.1), 0, randf_range(-0.1, 0.1)), v, life * randf_range(0.7, 1.2), size * randf_range(0.7, 1.2), c, -0.2, 0.8, 1.6)


func explosion(pos: Vector3, r: float, c: Color) -> void:
	emit("spark", pos + Vector3(0, 0.3, 0), Vector3.ZERO, 0.18, r * 0.9, Color(1.0, 0.9, 0.6, 0.9), 0.0, 0.0, 0.8)
	burst(pos + Vector3(0, 0.2, 0), 18, 7.0 * maxf(0.6, r * 0.5), Color(1.0, 0.6, 0.25), 0.1, 0.45)
	smoke(pos, 10, Color(0.35, 0.33, 0.33, 0.55), 0.35 * maxf(1.0, r * 0.6), 1.4, 1.2)
	burst(pos, 8, 5.0, Color(0.3, 0.28, 0.27), 0.12, 1.2, "debris", 14.0)
	ring(pos + Vector3(0, 0.1, 0), 0.2, r * 1.3, 0.38, Color(c.r, c.g, c.b, 0.7))
	decal(pos, r * 0.75, Color(0.04, 0.035, 0.035, 0.7), 8.0)


## Artillery impact (section 10.6): flash, rising stem, a rolling cap that billows out over
## 2.6 s, a ground shockwave and a burnt crater.
func mushroom(pos: Vector3, r: float) -> void:
	emit("spark", pos + Vector3(0, 0.6, 0), Vector3.ZERO, 0.25, r * 1.3, Color(1.0, 0.95, 0.8, 1.0), 0.0, 0.0, 1.2)
	burst(pos + Vector3(0, 0.3, 0), 30, 8.0, Color(1.0, 0.55, 0.2), 0.12, 0.6)
	for i in 14:
		var j := Vector3(randf_range(-0.25, 0.25), 0.2, randf_range(-0.25, 0.25))
		emit("puff", pos + j, Vector3(0, 2.2 + i * 0.22, 0), 2.6, 0.32 + 0.025 * i, Color(0.42, 0.36, 0.32, 0.75), 0.0, 1.1, 0.5)
	for i in 22:
		var a := i * TAU / 22.0
		emit("puff", pos + Vector3(0, 1.2, 0), Vector3(cos(a) * 1.7, 4.4, sin(a) * 1.7), 2.6, 0.55, Color(0.52, 0.4, 0.32, 0.8), 0.0, 1.3, 0.9)
		emit("spark", pos + Vector3(0, 1.0, 0), Vector3(cos(a) * 1.2, 3.8, sin(a) * 1.2), 0.9, 0.3, Color(1.0, 0.5, 0.15, 0.8), 0.0, 1.3, 0.6)
	ring(pos + Vector3(0, 0.1, 0), 0.3, r * 2.6, 0.7, Color(1.0, 0.85, 0.6, 0.7))
	burst(pos, 12, 6.0, Color(0.3, 0.28, 0.27), 0.14, 1.4, "debris", 14.0)
	decal(pos, r * 0.9, Color(0.03, 0.025, 0.02, 0.85), 30.0)


## The orbital beam (section 10.8): white core, blue fringe, 1 s.
func beam(pos: Vector3, life: float = 1.0) -> void:
	var top := pos + Vector3(0, 70, 0)
	ribbon(top, pos, 2.6, Color(0.35, 0.6, 1.0, 0.8), life)
	ribbon(top, pos, 1.1, Color(1.0, 1.0, 1.0, 1.0), life * 0.9)
	burst(pos + Vector3(0, 0.3, 0), 40, 9.0, Color(0.75, 0.88, 1.0), 0.1, 0.8)
	ring(pos + Vector3(0, 0.1, 0), 0.5, 4.0, 0.5, Color(0.8, 0.9, 1.0, 0.9))
