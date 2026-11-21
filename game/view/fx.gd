class_name Fx
extends Node3D
## Pooled, capped effects: puffs (smoke, dust, goo), sparks, brass casings that bounce and
## tinkle, debris, glowing ribbons (tracers, beams, bolts, smoke streaks), rings and decals.
## Oldest effects fade first. Particle counts scale with the quality preset; gameplay never does.
## Puffs are soft, noisy billboards that can start as fire (heat) and cool to smoke; sparks
## are additive streaks stretched along their velocity (tracers, embers, muzzle flashes).
## A small pool of short-lived lights makes flashes and explosions light up the ground.

const SPARK_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled;
varying vec4 col;
void vertex(){
	col = COLOR;
	float size = length(MODEL_MATRIX[0].xyz);
	vec4 c = VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0);
	vec3 v = (VIEW_MATRIX * vec4(INSTANCE_CUSTOM.xyz, 0.0)).xyz;
	float sp = length(v.xy);
	vec2 ax = sp > 0.001 ? v.xy / sp : vec2(0.0, 1.0);
	vec2 pr = vec2(-ax.y, ax.x);
	float len = size + sp * INSTANCE_CUSTOM.w;
	vec2 off = ax * VERTEX.y * len * 2.6 + pr * VERTEX.x * size * 2.6;
	POSITION = PROJECTION_MATRIX * vec4(c.xyz + vec3(off, 0.0), 1.0);
}
void fragment(){
	vec2 q = UV * 2.0 - 1.0;
	float d = length(q);
	float a = pow(clamp(1.0 - d, 0.0, 1.0), 1.6);
	float core = pow(clamp(1.0 - d * 1.8, 0.0, 1.0), 2.0);
	ALBEDO = col.rgb * 1.6 + vec3(1.0, 0.95, 0.85) * core * 1.4;
	ALPHA = a * col.a;
}
"""

const PUFF_SHADER := """
shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled, shadows_disabled;
varying vec4 col;
varying vec4 cust;
float h21(vec2 p){ p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vnoise(vec2 p){ vec2 i = floor(p); vec2 f = fract(p); f = f*f*(3.0-2.0*f);
	return mix(mix(h21(i), h21(i+vec2(1,0)), f.x), mix(h21(i+vec2(0,1)), h21(i+vec2(1,1)), f.x), f.y); }
void vertex(){
	col = COLOR;
	cust = INSTANCE_CUSTOM;
	float size = length(MODEL_MATRIX[0].xyz);
	vec4 c = VIEW_MATRIX * vec4(MODEL_MATRIX[3].xyz, 1.0);
	float r = cust.z * 6.2831;
	vec2 o = VERTEX.xy * size * 2.8;
	o = vec2(o.x * cos(r) - o.y * sin(r), o.x * sin(r) + o.y * cos(r));
	POSITION = PROJECTION_MATRIX * vec4(c.xyz + vec3(o, 0.0), 1.0);
}
void fragment(){
	vec2 q = UV * 2.0 - 1.0;
	float age = 1.0 - cust.y;
	vec2 nuv = UV * 2.6 + vec2(cust.z * 17.0, cust.z * 9.0) + vec2(0.0, age * 0.6);
	float n = vnoise(nuv) * 0.6 + vnoise(nuv * 2.3) * 0.4;
	float d = length(q) + (n - 0.5) * 0.55;
	float shape = 1.0 - smoothstep(0.35, 0.95, d);
	// lit from above: the top of each puff is a little lighter
	float shade = mix(0.72, 1.18, clamp(1.0 - UV.y + (n - 0.5) * 0.4, 0.0, 1.0));
	vec3 c = col.rgb * shade * 1.35;
	// fire: hot puffs start white-gold, cool through orange to the smoke colour
	float heat = cust.x * pow(cust.y, 2.2);
	vec3 fire = mix(vec3(1.0, 0.32, 0.06), vec3(1.0, 0.86, 0.45), clamp(heat * 1.4 - (d * 0.6), 0.0, 1.0));
	c = mix(c, fire * (1.2 + 2.6 * heat), clamp(heat * 1.6, 0.0, 1.0));
	ALBEDO = c;
	ALPHA = shape * col.a;
}
"""

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
	var heat: PackedFloat32Array = PackedFloat32Array()
	var seed: PackedFloat32Array = PackedFloat32Array()
	var stretch := 0.0  ## sparks: streak length per unit of speed (0 = none / not a billboard)
	var billboard := false
	var n := 0


## Lights for flashes: a handful, reused oldest-first.
var lights: Array = []  ## {node, life, max, energy}
const LIGHT_CAP := 8


func _ready() -> void:
	_pool("puff", _quad(), _billboard_mat("puff", PUFF_SHADER))
	_pool("spark", _quad(), _billboard_mat("spark", SPARK_SHADER))
	pools.puff.billboard = true
	pools.spark.billboard = true
	pools.spark.stretch = 0.045
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


static func _quad() -> QuadMesh:
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	return q


func _billboard_mat(key: String, code: String) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = Kit._shader("fx_" + key, code)
	return m


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
	p.mm.use_custom_data = true
	p.mm.mesh = mesh
	p.mm.instance_count = p.cap
	p.mm.visible_instance_count = 0
	p.node = MultiMeshInstance3D.new()
	p.node.multimesh = p.mm
	p.node.material_override = mat
	p.node.extra_cull_margin = 4.0
	p.node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF if name_id != "casing" and name_id != "debris" else GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	add_child(p.node)
	for arr in [p.pos, p.vel, p.spin, p.rot]:
		arr.resize(p.cap)
	for arr in [p.life, p.maxl, p.size, p.grow, p.grav, p.drag, p.heat, p.seed]:
		arr.resize(p.cap)
	p.col.resize(p.cap)
	p.bounced.resize(p.cap)
	pools[name_id] = p


## Emit one particle. Returns false when the pool is full (the oldest is replaced).
func emit(pool_id: String, pos: Vector3, vel: Vector3, life: float, size: float, col: Color, grav: float = 0.0, drag: float = 0.0, grow: float = 0.0, heat: float = 0.0) -> void:
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
	p.heat[i] = heat
	p.seed[i] = randf()


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
			p.heat[i] = p.heat[last]
			p.seed[i] = p.seed[last]
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
		if p.billboard:
			if p.stretch > 0.0:
				var v := p.vel[k]
				mm.set_instance_custom_data(k, Color(v.x, v.y, v.z, p.stretch))
			else:
				mm.set_instance_custom_data(k, Color(p.heat[k], f, p.seed[k], 0.0))
	mm.visible_instance_count = p.n


func _process(delta: float) -> void:
	for id in pools:
		_step_pool(id, pools[id], delta)
	_draw_ribbons(delta)
	_step_lights(delta)
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
	var big := maxf(1.0, r * 0.6)
	flash(pos + Vector3(0, 0.6, 0), Color(1.0, 0.62, 0.3), 5.0 * big, 3.0 + r * 2.2, 0.35)
	emit("spark", pos + Vector3(0, 0.3, 0), Vector3.ZERO, 0.14, r * 0.8, Color(1.0, 0.9, 0.6, 1.0), 0.0, 0.0, 1.0)
	# fireball: hot puffs that roll outward and up, cooling into a smoke column
	var nf := maxi(4, int(10 * quality * big))
	for i in nf:
		var d := Vector3(randf_range(-1, 1), randf_range(0.1, 0.9), randf_range(-1, 1)).normalized()
		emit("puff", pos + d * 0.2 * r, d * randf_range(1.5, 3.2) * maxf(0.7, r * 0.5), randf_range(0.6, 1.1), 0.28 * big * randf_range(0.8, 1.3), Color(0.36, 0.34, 0.34, 0.62), -0.8, 2.2, 1.4, 1.0)
	smoke(pos + Vector3(0, 0.3, 0), 6, Color(0.33, 0.31, 0.31, 0.5), 0.35 * big, 1.8, 1.3)
	# sparks and glowing embers that arc out and fall
	var ne := maxi(4, int(16 * quality * big))
	for i in ne:
		var d := Vector3(randf_range(-1, 1), randf_range(0.4, 1.4), randf_range(-1, 1)).normalized()
		emit("spark", pos + Vector3(0, 0.3, 0), d * randf_range(4.0, 9.0) * maxf(0.7, r * 0.45), randf_range(0.3, 0.8), randf_range(0.03, 0.06), Color(1.0, randf_range(0.45, 0.7), 0.2), 9.0, 1.2)
	burst(pos, 8, 5.0, Color(0.3, 0.28, 0.27), 0.12, 1.2, "debris", 14.0)
	ring(pos + Vector3(0, 0.1, 0), 0.2, r * 1.3, 0.38, Color(c.r, c.g, c.b, 0.7))
	decal(pos, r * 0.75, Color(0.04, 0.035, 0.035, 0.7), 8.0)


## A muzzle flash along dir: a hot star, a streaked cone, a little smoke and a light blink.
func muzzle(pos: Vector3, dir: Vector3, c: Color = Color(1.0, 0.78, 0.4), size: float = 1.0, light: bool = true) -> void:
	var d := dir.normalized() if dir.length_squared() > 1e-6 else Vector3.FORWARD
	emit("spark", pos, Vector3.ZERO, 0.06, 0.14 * size, Color(c.r, c.g, c.b, 1.0))
	emit("spark", pos + d * 0.1 * size, d * 14.0 * size, 0.05, 0.07 * size, c)
	for i in maxi(1, int(3 * quality)):
		var side := Vector3(randf_range(-1, 1), randf_range(-0.6, 0.8), randf_range(-1, 1)) * 0.45
		emit("spark", pos, (d + side).normalized() * randf_range(5.0, 9.0) * size, 0.05, 0.04 * size, c)
	if randf() < 0.6:
		emit("puff", pos + d * 0.15, d * 0.8 + Vector3(0, 0.4, 0), 0.6, 0.09 * size, Color(0.55, 0.55, 0.58, 0.35), -0.3, 1.5, 2.0)
	if light:
		flash(pos + d * 0.2, c, 1.6 * size, 2.2 + size, 0.07)


## Fire and smoke trail behind a rocket (called per frame).
func rocket_trail(pos: Vector3, vel: Vector3) -> void:
	emit("spark", pos, -vel * 0.4, 0.06, 0.08, Color(1.0, 0.55, 0.2))
	emit("puff", pos, -vel * 0.05 + Vector3(randf_range(-0.2, 0.2), 0.3, randf_range(-0.2, 0.2)), randf_range(0.7, 1.1), 0.1, Color(0.6, 0.6, 0.63, 0.45), -0.2, 1.2, 2.2, 0.7)


## A short-lived point light (the oldest one is reused when all are busy).
func flash(pos: Vector3, c: Color, energy: float, rng: float, life: float) -> void:
	if quality < 1.0 and energy < 2.0:
		return
	var L: Dictionary
	if lights.size() < LIGHT_CAP:
		var o := OmniLight3D.new()
		o.shadow_enabled = false
		o.omni_attenuation = 1.6
		add_child(o)
		L = {"node": o, "life": 0.0, "max": 1.0, "energy": 0.0}
		lights.append(L)
	else:
		L = lights[0]
		for l in lights:
			if l.life < L.life:
				L = l
	var node: OmniLight3D = L.node
	node.position = pos
	node.light_color = c
	node.omni_range = rng
	node.visible = true
	L.life = life
	L.max = life
	L.energy = energy
	node.light_energy = energy


func _step_lights(delta: float) -> void:
	for l in lights:
		if l.life <= 0.0:
			continue
		l.life -= delta
		var node: OmniLight3D = l.node
		if l.life <= 0.0:
			node.visible = false
		else:
			var f: float = l.life / l.max
			node.light_energy = l.energy * f * f


## Artillery impact (section 10.6): flash, rising stem, a rolling cap that billows out over
## 2.6 s, a ground shockwave and a burnt crater.
func mushroom(pos: Vector3, r: float) -> void:
	flash(pos + Vector3(0, 1.5, 0), Color(1.0, 0.7, 0.4), 9.0, 6.0 + r * 3.0, 0.8)
	emit("spark", pos + Vector3(0, 0.6, 0), Vector3.ZERO, 0.25, r * 1.3, Color(1.0, 0.95, 0.8, 1.0), 0.0, 0.0, 1.2)
	burst(pos + Vector3(0, 0.3, 0), 30, 8.0, Color(1.0, 0.55, 0.2), 0.12, 0.6)
	for i in 14:
		var j := Vector3(randf_range(-0.25, 0.25), 0.2, randf_range(-0.25, 0.25))
		emit("puff", pos + j, Vector3(0, 2.2 + i * 0.22, 0), 2.6, 0.32 + 0.025 * i, Color(0.42, 0.36, 0.32, 0.75), 0.0, 1.1, 0.5, 0.8)
	for i in 22:
		var a := i * TAU / 22.0
		emit("puff", pos + Vector3(0, 1.2, 0), Vector3(cos(a) * 1.7, 4.4, sin(a) * 1.7), 2.6, 0.55, Color(0.52, 0.4, 0.32, 0.8), 0.0, 1.3, 0.9, 1.0)
		emit("spark", pos + Vector3(0, 1.0, 0), Vector3(cos(a) * 1.2, 3.8, sin(a) * 1.2), 0.9, 0.3, Color(1.0, 0.5, 0.15, 0.8), 0.0, 1.3, 0.6)
	ring(pos + Vector3(0, 0.1, 0), 0.3, r * 2.6, 0.7, Color(1.0, 0.85, 0.6, 0.7))
	burst(pos, 12, 6.0, Color(0.3, 0.28, 0.27), 0.14, 1.4, "debris", 14.0)
	decal(pos, r * 0.9, Color(0.03, 0.025, 0.02, 0.85), 30.0)


## The orbital beam (section 10.8): white core, blue fringe, 1 s.
func beam(pos: Vector3, life: float = 1.0) -> void:
	var top := pos + Vector3(0, 70, 0)
	flash(pos + Vector3(0, 2.0, 0), Color(0.7, 0.85, 1.0), 12.0, 14.0, life)
	ribbon(top, pos, 2.6, Color(0.35, 0.6, 1.0, 0.8), life)
	ribbon(top, pos, 1.1, Color(1.0, 1.0, 1.0, 1.0), life * 0.9)
	burst(pos + Vector3(0, 0.3, 0), 40, 9.0, Color(0.75, 0.88, 1.0), 0.1, 0.8)
	ring(pos + Vector3(0, 0.1, 0), 0.5, 4.0, 0.5, Color(0.8, 0.9, 1.0, 0.9))
