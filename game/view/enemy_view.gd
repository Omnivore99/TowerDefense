class_name EnemyView
extends Node3D
## A monster: glossy, gummy, semi-translucent body with rim light and an element-coloured
## inner glow (section 4.1). Motion sells the body type (section 8.1):
## soft bodies hop, stretch and jiggle; coils expand and contract; hard bodies roll, flip, walk.

const SUIT_LIGHT := {"hearts": Color("ffa184"), "diamonds": Color("f2f27a"), "clubs": Color("7cf0c0"), "spades": Color("a6b4ff")}
const SUIT_DARK := {"hearts": Color("e8432f"), "diamonds": Color("a7c92b"), "clubs": Color("15a58f"), "spades": Color("7a3fe0")}
const SIZE_TONE := {"mite": 0.1, "small": 0.0, "medium": 0.4, "large": 0.75, "giant": 0.9, "champion": 0.95, "boss": 1.0}

var e: SimEnemy
var terrain: TerrainView
var body: Node3D
var mat: ShaderMaterial
var parts: Array[Node3D] = []
var r := 0.5
var hop_h := 0.0
var land_t := 9.0
var was_air := false
var roll := 0.0
var yaw := 0.0
var t := 0.0
var hp_back: MeshInstance3D
var hp_fill: MeshInstance3D
var shield_mesh: MeshInstance3D
var dent := 0.0
var built_suit := ""
var soft := false
var coil := false


func setup(en: SimEnemy, tv: TerrainView) -> void:
	e = en
	terrain = tv
	r = e.radius * e.scale
	soft = Bal.SOFT_ARCHS.has(e.arch)
	coil = Bal.COIL_ARCHS.has(e.arch)
	yaw = -e.dir
	_build()


static func suit_color(suit: String, size: String) -> Color:
	return SUIT_LIGHT[suit].lerp(SUIT_DARK[suit], SIZE_TONE[size])


func _build() -> void:
	for c in get_children():
		c.queue_free()
	parts.clear()
	built_suit = e.suit
	body = Node3D.new()
	add_child(body)
	var bc := suit_color(e.suit, e.size)
	var gc: Color = Bal.GROUPS[e.group].color
	if e.group == "nonmetal":
		gc = bc.lightened(0.3)
	mat = Kit.jelly_material(bc, gc)
	var dark := Kit.std("enemy_dark", Color(0.06, 0.06, 0.08), 0.3, 0.4)
	match e.arch:
		"hopper", "crawler", "blob":
			var sq := 0.85 if e.arch == "crawler" else 1.0
			var m := Kit.add(body, Kit.sphere(1.0, 18), mat, Vector3(0, r * sq, 0), Vector3.ZERO, Vector3(r, r * sq, r))
			if e.arch == "blob":
				m.scale = Vector3(r * 1.15, r * 0.8, r * 1.15)
				m.position.y = r * 0.8
			if e.arch == "crawler":
				for i in 3:
					Kit.add(body, Kit.sphere(1.0, 10), mat, Vector3(-r * (0.6 + i * 0.45), r * 0.45, 0), Vector3.ZERO, Vector3.ONE * r * (0.55 - i * 0.12))
			_eyes(Vector3(r * 0.72, r * 1.05 * sq, 0), r)
		"slinky":
			for i in 7:
				var ring := Kit.add(body, Kit.torus(0.62, 1.0, 16), mat, Vector3(-i * r * 0.32, r * 0.75, 0), Vector3(0, 0, PI / 2), Vector3.ONE * r * 0.75)
				parts.append(ring)
			_eyes(Vector3(r * 0.4, r * 1.0, 0), r * 0.8)
		"roller":
			var ball := Kit.add(body, Kit.sphere(1.0, 16), mat, Vector3(0, r, 0), Vector3.ZERO, Vector3.ONE * r)
			parts.append(ball)
			Kit.add(ball, Kit.torus(0.92, 1.06, 18), dark, Vector3.ZERO, Vector3(PI / 2, 0, 0))
			Kit.add(ball, Kit.torus(0.92, 1.06, 18), dark, Vector3.ZERO, Vector3(0, 0, 0))
			_eyes(Vector3(r * 0.85, r * 1.2, 0), r * 0.7)
		"swinger":
			Kit.add(body, Kit.sphere(1.0, 14), mat, Vector3(0, r * 1.2, 0), Vector3.ZERO, Vector3(r * 0.7, r * 0.9, r * 0.7))
			for z in [-1, 1]:
				var arm := Node3D.new()
				body.add_child(arm)
				arm.position = Vector3(0, r * 1.5, z * r * 0.75)
				Kit.add(arm, Kit.cylinder(r * 0.12, r * 0.1, r * 1.1, 8), mat, Vector3(0, -r * 0.5, 0))
				Kit.add(arm, Kit.sphere(r * 0.22, 8), mat, Vector3(0, -r * 1.05, 0))
				parts.append(arm)
			for z in [-1, 1]:
				Kit.add(body, Kit.cylinder(r * 0.13, r * 0.1, r * 0.6, 8), mat, Vector3(0, r * 0.3, z * r * 0.3))
			_eyes(Vector3(r * 0.55, r * 1.45, 0), r * 0.7)
		"tumbler":
			var cube := Kit.add(body, Kit.bevel_box(Vector3.ONE * 1.4, 0.25), mat, Vector3(0, r, 0), Vector3.ZERO, Vector3.ONE * r)
			parts.append(cube)
			_eyes(Vector3(r * 0.72, r * 1.15, 0), r * 0.75)
		"beetle":
			Kit.add(body, Kit.sphere(1.0, 16, true), mat, Vector3(0, r * 0.25, 0), Vector3.ZERO, Vector3(r * 1.2, r * 1.1, r))
			Kit.add(body, Kit.torus(0.95, 1.05, 16), dark, Vector3(0, r * 0.25, 0), Vector3.ZERO, Vector3(r * 1.2, r, r))
			Kit.add(body, Kit.box(Vector3(2.2, 0.06, 0.08)), dark, Vector3(0, r * 0.9, 0), Vector3.ZERO, Vector3(r, r, r))
			for i in 3:
				for z in [-1, 1]:
					var leg := Kit.add(body, Kit.cylinder(r * 0.06, r * 0.05, r * 0.7, 6), dark, Vector3((i - 1) * r * 0.6, r * 0.2, z * r * 1.0), Vector3(z * 0.9, 0, 0))
					parts.append(leg)
			_eyes(Vector3(r * 1.15, r * 0.5, 0), r * 0.6)
		"nautilus":
			Kit.add(body, Kit.sphere(1.0, 12), mat, Vector3(r * 0.5, r * 0.35, 0), Vector3.ZERO, Vector3(r * 0.9, r * 0.4, r * 0.55))
			var shell := Node3D.new()
			body.add_child(shell)
			shell.position = Vector3(-r * 0.1, r * 0.95, 0)
			for i in 5:
				var s := r * (0.85 - i * 0.15)
				Kit.add(shell, Kit.torus(s * 0.45, s, 16), mat, Vector3(-i * r * 0.08, i * r * 0.05, 0), Vector3(PI / 2, 0, 0))
			_eyes(Vector3(r * 1.25, r * 0.6, 0), r * 0.55)
		"balloon":
			var b := Kit.add(body, Kit.sphere(1.0, 16), mat, Vector3(0, 3.2 + r, 0), Vector3.ZERO, Vector3(r, r * 1.15, r))
			parts.append(b)
			Kit.add(body, Kit.cylinder(0.015, 0.015, 3.0, 4, false), dark, Vector3(0, 1.7, 0))
			Kit.add(body, Kit.box(Vector3(0.3, 0.2, 0.3)), Kit.wood(), Vector3(0, 0.2, 0))
			_eyes(Vector3(r * 0.85, 3.2 + r * 1.2, 0), r * 0.7)
		"walker":
			Kit.add(body, Kit.sphere(1.0, 16), mat, Vector3(0, r * 2.3, 0), Vector3.ZERO, Vector3(r * 0.9, r * 0.75, r * 0.8))
			for z in [-1, 1]:
				var leg2 := Node3D.new()
				body.add_child(leg2)
				leg2.position = Vector3(0, r * 1.8, z * r * 0.45)
				Kit.add(leg2, Kit.cylinder(r * 0.16, r * 0.12, r * 1.8, 8), mat, Vector3(0, -r * 0.9, 0))
				Kit.add(leg2, Kit.bevel_box(Vector3(0.5, 0.15, 0.3), 0.05), dark, Vector3(r * 0.1, -r * 1.8, 0), Vector3.ZERO, Vector3.ONE * r)
				parts.append(leg2)
			_eyes(Vector3(r * 0.8, r * 2.45, 0), r * 0.7)
		_:
			Kit.add(body, Kit.sphere(1.0, 14), mat, Vector3(0, r, 0), Vector3.ZERO, Vector3.ONE * r)
			_eyes(Vector3(r * 0.8, r * 1.1, 0), r)
	# tiers add spikes and crests; champions and bosses get crowns
	if e.tier >= 2 and e.arch != "balloon":
		for i in e.tier:
			Kit.add(body, Kit.cone(r * 0.12, r * 0.4, 6), dark, Vector3(-r * 0.3 + i * r * 0.22, r * (1.9 if e.arch in ["swinger", "walker"] else 1.6), 0), Vector3(0, 0, -0.3))
	if e.champion or e.boss:
		var crown_y := r * (2.9 if e.arch == "walker" else 2.0)
		Kit.add(body, Kit.torus(r * 0.3, r * 0.42, 12), Kit.brass(), Vector3(0, crown_y, 0))
		for i in 5:
			var a := TAU * i / 5.0
			Kit.add(body, Kit.cone(r * 0.07, r * 0.25, 5), Kit.brass(), Vector3(cos(a) * r * 0.36, crown_y + r * 0.13, sin(a) * r * 0.36))
		Kit.add(body, Kit.sphere(r * 0.08, 8), Kit.glow(Color(1, 0.3, 0.2), 4.0), Vector3(r * 0.4, crown_y + 0.05, 0))
	if e.golden:
		Kit.add(body, Kit.torus(r * 1.1, r * 1.2, 20), Kit.glow(Color(1, 0.85, 0.3), 3.0), Vector3(0, 0.05, 0))
	# health bar (billboard)
	hp_back = MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(1, 0.12)
	hp_back.mesh = q
	hp_back.material_override = _bar_mat(Color(0, 0, 0, 0.6))
	add_child(hp_back)
	hp_fill = MeshInstance3D.new()
	hp_fill.mesh = q
	hp_fill.material_override = _bar_mat(Color(0.5, 1.0, 0.55, 0.95))
	add_child(hp_fill)
	hp_back.visible = false
	hp_fill.visible = false
	if e.shield_max > 0.0 or e.ability == "alkaline":
		shield_mesh = Kit.add(self, Kit.sphere(1.0, 14), Kit.glass(Color(0.55, 0.85, 1.0)), Vector3(0, r, 0), Vector3.ZERO, Vector3.ONE * r * 1.45)
		shield_mesh.visible = e.shield > 0.0


static func _bar_mat(c: Color) -> StandardMaterial3D:
	var key := "bar" + c.to_html()
	if Kit._mats.has(key):
		return Kit._mats[key]
	var m := StandardMaterial3D.new()
	m.albedo_color = c
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.no_depth_test = true
	m.render_priority = 10
	Kit._mats[key] = m
	return m


func _eyes(pos: Vector3, s: float) -> void:
	var white := Kit.std("eye_white", Color(0.95, 0.95, 0.92), 0.0, 0.2)
	var pupil := Kit.std("eye_pupil", Color(0.03, 0.03, 0.05), 0.0, 0.1)
	var glowing := e.tier >= 3 or e.champion or e.boss
	for z in [-1, 1]:
		var p := pos + Vector3(0, 0, z * s * 0.32)
		Kit.add(body, Kit.sphere(1.0, 10), white if not glowing else Kit.glow(Color(1, 0.85, 0.5), 2.5), p, Vector3.ZERO, Vector3.ONE * s * 0.2)
		Kit.add(body, Kit.sphere(1.0, 8), pupil if not glowing else Kit.glow(Color(1, 0.2, 0.1), 3.0), p + Vector3(s * 0.12, 0, 0), Vector3.ZERO, Vector3.ONE * s * 0.11)


func hit() -> void:
	dent = 1.0


## alpha: interpolation between the previous and current sim step.
func sync(alpha: float, delta: float) -> void:
	t += delta
	if e.suit != built_suit:
		var bc := suit_color(e.suit, e.size)
		mat.set_shader_parameter("body", bc)
		built_suit = e.suit
	var x := lerpf(e.px, e.x, alpha)
	var z := lerpf(e.py, e.y, alpha)
	var ground := terrain.cell_pos(x, z).y if not e.overland else 0.0
	if e.overland and e.arch == "walker":
		ground = terrain.cell_pos(x, z).y
	position = Vector3(x, ground, z)
	yaw = lerp_angle(yaw, -e.sdir, 1.0 - pow(0.001, delta))
	body.rotation.y = yaw
	var sx := 1.0
	var sy := 1.0
	var lift := 0.0
	var lag := 0.0
	match e.arch:
		"hopper":
			var g := e.gait
			var air: float = Bal.ARCH.hopperAir
			if g < air:
				var k := g / air
				lift = sin(k * PI) * (0.55 + r * 0.6)
				# stretch on take-off, round at the apex
				var st := 1.0 + 0.25 * (1.0 - k) * (1.0 - k) * 1.2
				sy = st
				sx = 1.0 / sqrt(st)
				was_air = true
			else:
				if was_air:
					land_t = 0.0
					was_air = false
				land_t += delta
				# squash on landing, overshoot wobble that settles over 0.382 s
				var w := exp(-land_t * 9.0) * cos(land_t * 30.0)
				sy = 1.0 - 0.3 * w
				sx = 1.0 + 0.22 * w
			lag = (1.0 if g < air else -0.6) * 0.35
		"crawler", "blob":
			var wave := sin(e.gait * TAU * 2.0)
			sy = 1.0 + 0.08 * wave
			sx = 1.0 - 0.05 * wave
			lag = 0.25 + 0.1 * wave
		"slinky":
			# anchor the rear, stretch the front forward (up to 2x), then pull the rear up
			var s := 0.5 + 0.5 * sin(e.gait * TAU)
			for i in parts.size():
				var ring: Node3D = parts[i]
				var frac := float(i) / (parts.size() - 1)
				ring.position.x = -i * r * 0.32 * (1.0 + s * 1.0) + s * r * 0.8
				ring.position.y = r * 0.75 + sin(frac * PI) * s * r * 0.9
		"roller":
			roll += e.speed * e.slow_mult * delta / maxf(0.2, r)
			if not parts.is_empty():
				parts[0].rotation.z = -roll
		"tumbler":
			if not parts.is_empty():
				var f := fmod(e.anim_t, Bal.ARCH.tumblerFlip) / Bal.ARCH.tumblerFlip
				var flip := smoothstep(0.7, 1.0, f) * PI / 2.0
				parts[0].rotation.z = -flip
				lift = sin(flip * 2.0) * r * 0.3
		"swinger":
			for i in parts.size():
				parts[i].rotation.z = sin(e.anim_t * 6.0 + i * PI) * 0.8
		"walker":
			for i in parts.size():
				parts[i].rotation.z = sin(e.anim_t * 3.0 + i * PI) * 0.45
			lift = absf(sin(e.anim_t * 3.0)) * 0.12
		"beetle":
			for i in parts.size():
				parts[i].rotation.y = sin(e.anim_t * 14.0 + i) * 0.4
		"balloon":
			lift = sin(e.anim_t * 1.3) * 0.25
	if dent > 0.0:
		dent = maxf(0.0, dent - delta * 7.0)
		sx *= 1.0 + 0.12 * dent
		sy *= 1.0 - 0.15 * dent
	body.position.y = lift
	body.scale = Vector3(sx, sy, sx)
	mat.set_shader_parameter("t", t)
	mat.set_shader_parameter("lag", lag * r * 0.5)
	mat.set_shader_parameter("lag_dir", Vector2(cos(-yaw), sin(-yaw)) * -1.0)
	mat.set_shader_parameter("flash", clampf(e.hit_flash / 0.08, 0.0, 1.0))
	mat.set_shader_parameter("wobble", 1.0 if soft else 0.3)
	mat.set_shader_parameter("alpha", 0.35 if e.immune else 0.93)
	# health bar
	var frac2 := clampf(e.hp / e.max_hp, 0.0, 1.0)
	var show := frac2 < 0.999 or e.champion or e.boss
	hp_back.visible = show
	hp_fill.visible = show
	if show:
		var w2 := clampf(r * 2.2, 0.8, 3.0)
		var top := r * 2.4 + 0.45 + (3.2 if e.arch == "balloon" else 0.0) + (r * 1.2 if e.arch == "walker" else 0.0)
		hp_back.position = Vector3(0, top, 0)
		hp_back.scale = Vector3(w2, 1, 1)
		hp_fill.position = Vector3(0, top, 0)
		hp_fill.scale = Vector3(w2 * frac2, 0.8, 1)
	if shield_mesh != null:
		shield_mesh.visible = e.shield > 0.0
		shield_mesh.position.y = r + lift
