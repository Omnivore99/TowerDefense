class_name Kit
extends RefCounted
## The modular "dusk fortress" kit (section 4.2): shared materials and procedural parts.
## Everything is generated in code so it is reproducible: masonry drums, iron bands,
## crenellations, domes, lens barrels, pipes, portholes, lanterns, paved footprints.
## Towers, evolutions and buildings are assembled from these parts.

const LH := 0.55  ## world height of one terrain level
const BLOCK_H := 0.42  ## height of one piece block (one story deck)

static var _mats := {}
static var _meshes := {}

const STONE_SHADER := """
shader_type spatial;
render_mode blend_mix, cull_back;
uniform vec3 base_col : source_color = vec3(0.21, 0.24, 0.30);
uniform vec3 mortar_col : source_color = vec3(0.10, 0.11, 0.14);
uniform float block_w = 0.62;
uniform float block_h = 0.32;
uniform float rough = 0.85;
uniform vec3 trim_glow : source_color = vec3(0.0);
varying vec3 lpos;
varying vec3 lnrm;
float h21(vec2 p){ p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
void vertex(){ lpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; lnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz); }
void fragment(){
	// triplanar brick pattern: horizontal courses on walls, flagstones on top
	vec3 n = abs(lnrm);
	vec2 uv;
	if (n.y > 0.7) { uv = lpos.xz / vec2(block_w, block_w * 0.8); }
	else { float a = atan(lpos.z, lpos.x); uv = vec2((n.x > n.z ? lpos.z : lpos.x) / block_w, lpos.y / block_h); }
	float row = floor(uv.y);
	uv.x += mod(row, 2.0) * 0.5;
	vec2 cell = floor(uv);
	vec2 f = fract(uv);
	float edge = min(min(f.x, 1.0 - f.x) * block_w, min(f.y, 1.0 - f.y) * block_h);
	float m = smoothstep(0.012, 0.035, edge);
	float v = h21(cell);
	vec3 c = base_col * (0.78 + 0.42 * v);
	c = mix(mortar_col, c, m);
	// chipped edges catch a little light
	c += vec3(0.05, 0.05, 0.06) * smoothstep(0.03, 0.05, edge) * (1.0 - smoothstep(0.05, 0.09, edge));
	ALBEDO = c;
	ROUGHNESS = rough - 0.1 * v;
	METALLIC = 0.0;
	EMISSION = trim_glow;
}
"""

const GROUND_SHADER := """
shader_type spatial;
render_mode cull_back;
varying vec3 wpos;
varying float kind;
varying float lvl;
varying vec3 wn;
float h21(vec2 p){ p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vnoise(vec2 p){ vec2 i = floor(p); vec2 f = fract(p); f = f*f*(3.0-2.0*f);
	return mix(mix(h21(i), h21(i+vec2(1,0)), f.x), mix(h21(i+vec2(0,1)), h21(i+vec2(1,1)), f.x), f.y); }
void vertex(){ wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; kind = UV.x; lvl = UV.y; wn = NORMAL; }
void fragment(){
	float n1 = vnoise(wpos.xz * 0.21);
	float n2 = vnoise(wpos.xz * 1.7);
	// palette is written in sRGB and converted to linear at the end
	vec3 grass = mix(vec3(0.27, 0.38, 0.22), vec3(0.36, 0.45, 0.24), n1);
	grass = mix(grass, vec3(0.30, 0.33, 0.24), smoothstep(0.55, 0.9, vnoise(wpos.xz * 0.07)));
	grass *= 0.86 + 0.24 * n2;
	vec3 col = grass;
	float rough = 0.95;
	if (kind > 0.5 && kind < 1.5) {
		// cobbled road: offset rows of rounded stones
		vec2 uv = wpos.xz * 2.2;
		uv.x += mod(floor(uv.y), 2.0) * 0.5;
		vec2 f = fract(uv) - 0.5;
		float d = length(f * vec2(1.0, 1.25));
		float stone = 1.0 - smoothstep(0.36, 0.48, d);
		float v = h21(floor(uv));
		vec3 cob = vec3(0.47, 0.45, 0.47) * (0.75 + 0.4 * v);
		col = mix(vec3(0.20, 0.19, 0.21), cob, stone);
		rough = 0.8;
	} else if (kind > 1.5 && kind < 2.5) {
		// ore vein: dark rock with glowing amber cracks
		float c = vnoise(wpos.xz * 3.0) + 0.5 * vnoise(wpos.xz * 7.0);
		float crack = 1.0 - smoothstep(0.02, 0.09, abs(c - 0.75));
		col = vec3(0.24, 0.22, 0.25) * (0.8 + 0.4 * n2);
		EMISSION = vec3(1.0, 0.55, 0.15) * crack * 2.2;
		rough = 0.6;
	} else if (kind > 2.5 && kind < 3.5) {
		// paved base plaza
		vec2 uv = wpos.xz * 1.2;
		uv.x += mod(floor(uv.y), 2.0) * 0.5;
		vec2 f = fract(uv);
		float e = min(min(f.x, 1.0 - f.x), min(f.y, 1.0 - f.y));
		col = mix(vec3(0.17, 0.18, 0.21), vec3(0.42, 0.43, 0.48) * (0.8 + 0.3 * h21(floor(uv))), smoothstep(0.02, 0.06, e));
	} else if (kind > 3.5 && kind < 4.5) {
		// scorched road under the strike (cools over time)
		col = vec3(0.14, 0.12, 0.12);
	} else if (kind > 4.5 && kind < 5.5) {
		// lake bed / wet mud
		col = mix(vec3(0.20, 0.17, 0.14), vec3(0.27, 0.23, 0.18), n2);
		rough = 0.35;
	} else if (kind > 5.5 && kind < 6.5) {
		// forest floor: darker moss with needle litter
		col = mix(vec3(0.19, 0.25, 0.15), vec3(0.27, 0.24, 0.17), vnoise(wpos.xz * 2.3));
	}
	// cliffs: darker stone faces
	if (abs(wn.y) < 0.5) { col = vec3(0.30, 0.31, 0.36) * (0.75 + 0.35 * vnoise(vec2(wpos.x + wpos.z, wpos.y * 3.0) * 2.0)); rough = 0.9; }
	// valleys are a little darker, rises a little lighter
	col *= 1.0 + clamp(lvl, -2.0, 3.0) * 0.05;
	ALBEDO = pow(col, vec3(2.2));
	ROUGHNESS = rough;
}
"""

const JELLY_SHADER := """
shader_type spatial;
render_mode blend_mix, cull_back, depth_draw_opaque;
uniform vec3 body : source_color = vec3(0.4, 0.8, 0.5);
uniform vec3 glow : source_color = vec3(0.4, 1.0, 0.5);
uniform float flash = 0.0;
uniform float lag = 0.0;
uniform vec2 lag_dir = vec2(0.0, 0.0);
uniform float wobble = 0.0;
uniform float t = 0.0;
uniform float alpha = 0.92;
uniform float dissolve = 0.0;
varying vec3 lp;
void vertex(){
	lp = VERTEX;
	float hgt = clamp(VERTEX.y, 0.0, 2.0);
	// the top of the body lags behind the base (jelly), plus a small wobble
	VERTEX.xz -= lag_dir * lag * hgt * hgt;
	VERTEX.xz += vec2(sin(t * 9.0 + VERTEX.y * 4.0), cos(t * 8.0 + VERTEX.y * 3.0)) * wobble * hgt * 0.08;
}
void fragment(){
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 2.5);
	ALBEDO = body;
	ROUGHNESS = 0.18;
	METALLIC = 0.0;
	SPECULAR = 0.8;
	float inner = 0.35 + 0.25 * sin(t * 3.0 + lp.y * 5.0);
	EMISSION = glow * (inner * 0.25 + fres * 0.55) + vec3(1.0) * flash * 1.6;
	RIM = 0.8;
	RIM_TINT = 0.4;
	ALPHA = alpha * (1.0 - dissolve);
}
"""


static func stone(tint: Color = Color(0.21, 0.24, 0.30), glow: Color = Color.BLACK) -> ShaderMaterial:
	var key := "stone%s%s" % [tint.to_html(), glow.to_html()]
	if _mats.has(key):
		return _mats[key]
	var sh := Shader.new()
	sh.code = STONE_SHADER
	var m := ShaderMaterial.new()
	m.shader = _shader("stone", STONE_SHADER)
	m.set_shader_parameter("base_col", tint)
	m.set_shader_parameter("trim_glow", Vector3(glow.r, glow.g, glow.b))
	_mats[key] = m
	return m


static func _shader(key: String, code: String) -> Shader:
	var k := "shader_" + key
	if not _mats.has(k):
		var sh := Shader.new()
		sh.code = code
		_mats[k] = sh
	return _mats[k]


static func ground_material() -> ShaderMaterial:
	if not _mats.has("ground"):
		var m := ShaderMaterial.new()
		m.shader = _shader("ground", GROUND_SHADER)
		_mats["ground"] = m
	return _mats["ground"]


static func jelly_material(body: Color, glow: Color) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = _shader("jelly", JELLY_SHADER)
	m.set_shader_parameter("body", body)
	m.set_shader_parameter("glow", glow)
	m.render_priority = 1
	return m


static func std(key: String, albedo: Color, metal: float, rough: float, emission: Color = Color.BLACK, energy: float = 1.0) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = albedo
	m.metallic = metal
	m.roughness = rough
	if emission != Color.BLACK:
		m.emission_enabled = true
		m.emission = emission
		m.emission_energy_multiplier = energy
	_mats[key] = m
	return m


static func iron() -> StandardMaterial3D:
	return std("iron", Color(0.13, 0.14, 0.16), 0.85, 0.42)


static func dark_iron() -> StandardMaterial3D:
	return std("dark_iron", Color(0.08, 0.085, 0.1), 0.9, 0.5)


static func brass() -> StandardMaterial3D:
	return std("brass", Color(0.62, 0.45, 0.2), 0.95, 0.32)


static func copper() -> StandardMaterial3D:
	return std("copper", Color(0.55, 0.3, 0.18), 0.9, 0.36)


static func wood() -> StandardMaterial3D:
	return std("wood", Color(0.3, 0.2, 0.13), 0.0, 0.8)


static func roof() -> StandardMaterial3D:
	return std("roof", Color(0.24, 0.32, 0.45), 0.2, 0.6)


## Warm amber glass for windows, domes, portholes, lanterns.
static func amber(energy: float = 3.0) -> StandardMaterial3D:
	return std("amber%.1f" % energy, Color(1.0, 0.62, 0.25), 0.0, 0.25, Color(1.0, 0.55, 0.18), energy)


static func glow(c: Color, energy: float = 3.0) -> StandardMaterial3D:
	return std("glow%s%.1f" % [c.to_html(), energy], c, 0.0, 0.3, c, energy)


static func glass(c: Color = Color(1.0, 0.7, 0.35)) -> StandardMaterial3D:
	var key := "glass" + c.to_html()
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(c.r, c.g, c.b, 0.55)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.roughness = 0.08
	m.metallic = 0.1
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 1.6
	m.rim_enabled = true
	m.rim = 0.6
	_mats[key] = m
	return m


## Piece block material: glossy, in a deep version of the piece colour so the slate
## masonry stays dominant and the colour reads mostly as light (seams, trim, footprint).
static func piece_block(color_id: String, golden: bool = false) -> StandardMaterial3D:
	var key := "piece_%s_%s" % [color_id, golden]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	var c: Color = Bal.PIECE_BODY.get(color_id, Color.GRAY)
	var slate := Color(0.22, 0.24, 0.29)
	var body: Color = slate.lerp(c, 0.55).darkened(0.15)
	if golden:
		body = Color(0.95, 0.75, 0.3)
	m.albedo_color = body
	m.roughness = 0.32
	m.metallic = 0.1 if not golden else 0.85
	m.clearcoat_enabled = true
	m.clearcoat = 0.5
	m.emission_enabled = true
	m.emission = c
	m.emission_energy_multiplier = 0.06 if not golden else 0.4
	_mats[key] = m
	return m


static func ghost_mat(ok: bool) -> StandardMaterial3D:
	var key := "ghost%s" % ok
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	var c := Color(0.55, 0.85, 1.0, 0.45) if ok else Color(1.0, 0.3, 0.25, 0.45)
	m.albedo_color = c
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.emission_enabled = true
	m.emission = Color(c.r, c.g, c.b)
	m.emission_energy_multiplier = 0.8
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.no_depth_test = false
	_mats[key] = m
	return m


static func unshaded(c: Color, additive: bool = false) -> StandardMaterial3D:
	var key := "unsh%s%s" % [c.to_html(), additive]
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	if additive:
		m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.vertex_color_use_as_albedo = true
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	_mats[key] = m
	return m


# ----------------------------------------------------------------- meshes
## A bevelled box (soft edges), cached by size.
static func bevel_box(size: Vector3, bevel: float = 0.06) -> ArrayMesh:
	var key := "bbox%s%.3f" % [size, bevel]
	if _meshes.has(key):
		return _meshes[key]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var h := size / 2.0
	var b := bevel
	# 6 inset faces + 12 bevel strips + 8 corner triangles (chamfer)
	var faces := [
		[Vector3(0, 1, 0), Vector3(1, 0, 0), Vector3(0, 0, 1)],
		[Vector3(0, -1, 0), Vector3(1, 0, 0), Vector3(0, 0, -1)],
		[Vector3(1, 0, 0), Vector3(0, 0, 1), Vector3(0, 1, 0)],
		[Vector3(-1, 0, 0), Vector3(0, 0, -1), Vector3(0, 1, 0)],
		[Vector3(0, 0, 1), Vector3(-1, 0, 0), Vector3(0, 1, 0)],
		[Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(0, 1, 0)],
	]
	var pts := func(n: Vector3, u: Vector3, v: Vector3) -> Array:
		var c := Vector3(n.x * h.x, n.y * h.y, n.z * h.z)
		var hu := absf(u.x) * h.x + absf(u.y) * h.y + absf(u.z) * h.z - b
		var hv := absf(v.x) * h.x + absf(v.y) * h.y + absf(v.z) * h.z - b
		return [c - u * hu - v * hv, c + u * hu - v * hv, c + u * hu + v * hv, c - u * hu + v * hv]
	for f in faces:
		var p: Array = pts.call(f[0], f[1], f[2])
		st.set_normal(f[0])
		_quad(st, p[0], p[1], p[2], p[3], f[0])
	# chamfer strips between adjacent faces and corner triangles: approximate with a convex hull rebuild
	var corners: Array[Vector3] = []
	for f in faces:
		corners.append_array(pts.call(f[0], f[1], f[2]))
	var hull := _hull_mesh(corners)
	_meshes[key] = hull
	return hull


static func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3, n: Vector3) -> void:
	var ab := b - a
	var ac := c - a
	var flip := ab.cross(ac).dot(n) < 0.0
	st.set_normal(n)
	if flip:
		st.add_vertex(a)
		st.add_vertex(c)
		st.add_vertex(b)
		st.add_vertex(a)
		st.add_vertex(d)
		st.add_vertex(c)
	else:
		st.add_vertex(a)
		st.add_vertex(b)
		st.add_vertex(c)
		st.add_vertex(a)
		st.add_vertex(c)
		st.add_vertex(d)


## Convex hull of points as a flat-shaded mesh (used for chamfered boxes).
static func _hull_mesh(points: Array[Vector3]) -> ArrayMesh:
	var shape := ConvexPolygonShape3D.new()
	shape.points = PackedVector3Array(points)
	var dbg := shape.get_debug_mesh()
	# debug mesh is lines; build triangles via Geometry3D convex hull planes instead
	var planes: Array[Plane] = []
	var pts := PackedVector3Array(points)
	var n := pts.size()
	for i in n:
		for j in range(i + 1, n):
			for k in range(j + 1, n):
				var pl := Plane(pts[i], pts[j], pts[k])
				if pl.normal.length_squared() < 0.5:
					continue
				var side := 0
				var ok := true
				for q in n:
					var dd := pl.distance_to(pts[q])
					if absf(dd) < 1e-4:
						continue
					var sgn := 1 if dd > 0 else -1
					if side == 0:
						side = sgn
					elif sgn != side:
						ok = false
						break
				if not ok:
					continue
				if side > 0:
					pl = Plane(-pl.normal, -pl.d)
				var dup := false
				for e in planes:
					if e.normal.dot(pl.normal) > 0.9999 and absf(e.d - pl.d) < 1e-4:
						dup = true
						break
				if not dup:
					planes.append(pl)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for pl in planes:
		var on: Array[Vector3] = []
		for q in pts:
			if absf(pl.distance_to(q)) < 1e-4 and not on.has(q):
				on.append(q)
		if on.size() < 3:
			continue
		var c := Vector3.ZERO
		for q in on:
			c += q
		c /= on.size()
		var u := (on[0] - c).normalized()
		var v := pl.normal.cross(u)
		on.sort_custom(func(a: Vector3, b2: Vector3) -> bool:
			return atan2((a - c).dot(v), (a - c).dot(u)) < atan2((b2 - c).dot(v), (b2 - c).dot(u)))
		for i in range(1, on.size() - 1):
			st.set_normal(pl.normal)
			st.add_vertex(on[0])
			st.set_normal(pl.normal)
			st.add_vertex(on[i + 1])
			st.set_normal(pl.normal)
			st.add_vertex(on[i])
	return st.commit()


static func cylinder(r_top: float, r_bot: float, h: float, segs: int = 16, cap: bool = true) -> CylinderMesh:
	var key := "cyl%.3f_%.3f_%.3f_%d_%s" % [r_top, r_bot, h, segs, cap]
	if _meshes.has(key):
		return _meshes[key]
	var m := CylinderMesh.new()
	m.top_radius = r_top
	m.bottom_radius = r_bot
	m.height = h
	m.radial_segments = segs
	m.rings = 1
	m.cap_top = cap
	m.cap_bottom = cap
	_meshes[key] = m
	return m


static func sphere(r: float, segs: int = 16, hemi: bool = false) -> SphereMesh:
	var key := "sph%.3f_%d_%s" % [r, segs, hemi]
	if _meshes.has(key):
		return _meshes[key]
	var m := SphereMesh.new()
	m.radius = r
	m.height = r * (1.0 if hemi else 2.0)
	m.is_hemisphere = hemi
	m.radial_segments = segs
	m.rings = maxi(4, segs / 2)
	_meshes[key] = m
	return m


static func torus(inner: float, outer: float, segs: int = 24) -> TorusMesh:
	var key := "tor%.3f_%.3f_%d" % [inner, outer, segs]
	if _meshes.has(key):
		return _meshes[key]
	var m := TorusMesh.new()
	m.inner_radius = inner
	m.outer_radius = outer
	m.rings = segs
	m.ring_segments = 8
	_meshes[key] = m
	return m


static func box(size: Vector3) -> BoxMesh:
	var key := "box%s" % size
	if _meshes.has(key):
		return _meshes[key]
	var m := BoxMesh.new()
	m.size = size
	_meshes[key] = m
	return m


static func cone(r: float, h: float, segs: int = 12) -> CylinderMesh:
	return cylinder(0.001, r, h, segs)


static func add(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3 = Vector3.ZERO, rot: Vector3 = Vector3.ZERO, scl: Vector3 = Vector3.ONE) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	mi.scale = scl
	parent.add_child(mi)
	return mi


# ----------------------------------------------------------------- composite parts
## A masonry drum (round stone tower segment) with an iron band on top.
static func drum(parent: Node3D, r: float, h: float, y: float, tint: Color = Color(0.21, 0.24, 0.30), band: bool = true) -> void:
	add(parent, cylinder(r, r * 1.04, h, 20), stone(tint), Vector3(0, y + h / 2.0, 0))
	if band:
		add(parent, cylinder(r * 1.07, r * 1.07, 0.07, 20), iron(), Vector3(0, y + h - 0.04, 0))


## A ring of crenellations on top of a drum.
static func crenellations(parent: Node3D, r: float, y: float, n: int = 8, tint: Color = Color(0.21, 0.24, 0.30)) -> void:
	add(parent, cylinder(r * 1.08, r * 1.08, 0.1, 20), stone(tint), Vector3(0, y + 0.05, 0))
	for i in n:
		var a := TAU * i / n
		add(parent, box(Vector3(r * 0.42, 0.18, 0.16)), stone(tint), Vector3(cos(a) * r, y + 0.19, sin(a) * r), Vector3(0, -a + PI / 2.0, 0))


## Glowing windows / portholes around a drum.
static func windows(parent: Node3D, r: float, y: float, n: int, glow_mat: Material, porthole: bool = false, phase: float = 0.0) -> void:
	for i in n:
		var a := TAU * i / n + phase
		var p := Vector3(cos(a) * r, y, sin(a) * r)
		if porthole:
			add(parent, cylinder(0.075, 0.075, 0.06, 10), glow_mat, p, Vector3(0, -a, PI / 2.0))
			add(parent, torus(0.07, 0.1, 12), brass(), p, Vector3(0, -a, PI / 2.0))
		else:
			add(parent, box(Vector3(0.05, 0.2, 0.11)), glow_mat, p, Vector3(0, -a, 0))


## A pipe from a to b (straight cylinder).
static func pipe(parent: Node3D, a: Vector3, b: Vector3, r: float = 0.035, mat: Material = null) -> void:
	var mi := add(parent, cylinder(r, r, a.distance_to(b), 8, false), mat if mat != null else brass(), (a + b) / 2.0)
	var dir := (b - a).normalized()
	if absf(dir.dot(Vector3.UP)) < 0.999:
		mi.basis = Basis.looking_at(dir, Vector3.UP) * Basis(Vector3.RIGHT, PI / 2.0)


## Glass dome with an iron rim (ref 2).
static func dome(parent: Node3D, r: float, y: float, glow_c: Color) -> MeshInstance3D:
	add(parent, torus(r * 0.92, r * 1.05, 20), iron(), Vector3(0, y, 0))
	return add(parent, sphere(r, 16, true), glass(glow_c), Vector3(0, y, 0))


## A lantern on a short post.
static func lantern(parent: Node3D, pos: Vector3, h: float = 0.35) -> void:
	add(parent, cylinder(0.02, 0.02, h, 6, false), dark_iron(), pos + Vector3(0, h / 2.0, 0))
	add(parent, box(Vector3(0.09, 0.12, 0.09)), amber(4.0), pos + Vector3(0, h + 0.06, 0))
	add(parent, cone(0.08, 0.06, 6), dark_iron(), pos + Vector3(0, h + 0.15, 0))
