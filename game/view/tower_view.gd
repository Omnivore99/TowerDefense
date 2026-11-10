class_name TowerView
extends Node3D
## A tower assembled from its pieces: glossy piece blocks stacked in story decks with glowing
## seams (the footprint stays readable), a slate masonry drum that grows with stories,
## and the weapon module on top that swings onto targets and recoils.

var tower: SimTower
var terrain: TerrainView
var piece_count := -1
var built_type := ""
var built_stories := -1
var head: Node3D
var barrel: Node3D
var spin: Node3D
var muzzle_local := Vector3.ZERO
var yaw := 0.0
var recoil := 0.0
var spin_v := 0.0
var activate_anim := 1.0
var body: Node3D
var top_y := 0.0
var glow_color := Color(1, 0.6, 0.2)
var base_y := 0.0
var flash_light: OmniLight3D
## The newest piece falls in from above with squash and stretch (section 7).
var drop: Node3D
var drop_t := 9.0
var drop_base := Vector3.ZERO
var prev_count := -1
var built_mark := 1
## Evolving plays a scaffold-up, hammering and pop animation (1.618 s).
var scaffold: Node3D
var evo_anim := 9.0
var evo_rings: Array[Node3D] = []
var hammer_cb: Callable


func setup(t: SimTower, tv: TerrainView) -> void:
	tower = t
	terrain = tv
	yaw = -t.angle
	rebuild()


func needs_rebuild() -> bool:
	return tower.pieces.size() != piece_count or tower.type != built_type or tower.mark != built_mark


func rebuild() -> void:
	for c in get_children():
		c.queue_free()
	head = null
	barrel = null
	spin = null
	var grew := prev_count >= 0 and tower.pieces.size() > prev_count
	prev_count = tower.pieces.size()
	piece_count = tower.pieces.size()
	drop = null
	built_type = tower.type
	var evolved := tower.mark > built_mark and built_mark >= 1 and piece_count == tower.pieces.size()
	built_mark = tower.mark
	evo_rings.clear()
	scaffold = null
	var t := tower
	base_y = t.height * Kit.LH
	var color_id: String = t.stats.get("color", "") if not t.stats.is_empty() else ""
	if color_id == "" and not t.pieces.is_empty():
		color_id = t.pieces[0].piece.color
	glow_color = Bal.PIECE_GLOW.get(color_id, Color(1, 0.65, 0.25))
	# paved footprint: a glowing tile in the tower colour with a dark flagstone on top,
	# so the Tetris footprint reads as a lit outline (ref 5)
	var tile := Kit.glow(glow_color, 2.2)
	var flag := Kit.stone(Color(0.17, 0.18, 0.22))
	for c in t.layers[0]:
		Kit.add(self, Kit.box(Vector3(1.0, 0.04, 1.0)), tile, Vector3(c.x + 0.5, base_y + 0.02, c.y + 0.5))
		Kit.add(self, Kit.bevel_box(Vector3(0.9, 0.08, 0.9), 0.03), flag, Vector3(c.x + 0.5, base_y + 0.05, c.y + 0.5))
	# piece blocks, one deck per story, each with a glowing seam strip in the piece colour
	for pi in t.pieces.size():
		var p: Dictionary = t.pieces[pi]
		var parent: Node3D = self
		if grew and pi == t.pieces.size() - 1:
			drop = Node3D.new()
			add_child(drop)
			parent = drop
			drop_t = 0.0
			var pc := Vector2.ZERO
			for c in p.cells:
				pc += Vector2(c.x + 0.5, c.y + 0.5)
			pc /= float(p.cells.size())
			drop_base = Vector3(pc.x, base_y + 0.09 + p.layer * Kit.BLOCK_H, pc.y)
			drop.position = drop_base
		var off: Vector3 = drop_base if parent == drop else Vector3.ZERO
		var mat := Kit.piece_block(p.piece.color, p.piece.golden)
		var seam := Kit.glow(Bal.PIECE_GLOW.get(p.piece.color, glow_color), 1.3)
		for c in p.cells:
			var y: float = base_y + 0.09 + p.layer * Kit.BLOCK_H + Kit.BLOCK_H / 2.0
			Kit.add(parent, Kit.bevel_box(Vector3(0.84, Kit.BLOCK_H - 0.04, 0.84), 0.07), mat, Vector3(c.x + 0.5, y, c.y + 0.5) - off)
			Kit.add(parent, Kit.box(Vector3(0.88, 0.035, 0.88)), seam, Vector3(c.x + 0.5, y - Kit.BLOCK_H / 2.0 + 0.01, c.y + 0.5) - off)
			if p.piece.glyph != "":
				var gc := Color(0.7, 0.9, 1.0) if Pieces.RARE_GLYPHS.has(p.piece.glyph) else Color(1, 0.95, 0.75)
				Kit.add(parent, Kit.cylinder(0.14, 0.14, 0.02, 10), Kit.glow(gc, 3.0), Vector3(c.x + 0.5, y + Kit.BLOCK_H / 2.0, c.y + 0.5) - off)
	var stories := t.layers.size()
	top_y = base_y + 0.09 + stories * Kit.BLOCK_H
	if t.type == "":
		return
	# the slate masonry tower rises from the top deck (ref 2: each story adds a ring,
	# portholes, pipes and finally a glowing dome)
	body = Node3D.new()
	body.name = "Body"
	add_child(body)
	var top_cells: Array = t.layers[stories - 1]
	var cx := 0.0
	var cy := 0.0
	for c in top_cells:
		cx += c.x + 0.5
		cy += c.y + 0.5
	cx /= top_cells.size()
	cy /= top_cells.size()
	var mass := t.ground_count()
	var r := clampf(0.36 + 0.16 * sqrt(top_cells.size()), 0.5, 0.95)
	var seg_h := 0.5
	var drum_h := 0.75 + seg_h * (stories - 1)
	body.position = Vector3(cx, top_y, cy)
	# plinth, then one drum segment per story, each a little narrower, with an iron band
	Kit.add(body, Kit.cylinder(r * 1.18, r * 1.25, 0.16, 20), Kit.stone(Color(0.19, 0.2, 0.24)), Vector3(0, 0.08, 0))
	var y0 := 0.16
	for i in stories:
		var rr := r * (1.0 - 0.05 * i)
		var hh := 0.75 if i == 0 else seg_h
		Kit.drum(body, rr, hh, y0)
		if i == 0:
			Kit.windows(body, rr * 1.01, y0 + hh * 0.5, 4, Kit.amber(3.0), false, 0.4)
		else:
			Kit.windows(body, rr * 1.01, y0 + hh * 0.5, 3 + i, Kit.amber(3.5), true, 0.3 * i)
		# coloured trim ring: the tower's majority colour as light (ref 4)
		Kit.add(body, Kit.torus(rr * 1.02, rr * 1.1, 20), Kit.glow(glow_color, 2.2), Vector3(0, y0 + 0.05, 0), Vector3.ZERO, Vector3(1, 0.45, 1))
		y0 += hh
	drum_h = y0
	var rt := r * (1.0 - 0.05 * (stories - 1))
	if stories >= 2:
		for i in mini(stories - 1, 3):
			var a := PI * 0.7 * i + 0.5
			Kit.pipe(body, Vector3(cos(a) * rt * 1.12, 0.2, sin(a) * rt * 1.12), Vector3(cos(a) * rt * 1.12, drum_h - 0.08, sin(a) * rt * 1.12), 0.045)
	if stories >= 3:
		Kit.dome(body, rt * 0.55, drum_h, glow_color.lerp(Color(1, 0.65, 0.25), 0.5))
	var crown := stories >= 5
	if crown or t.mark >= 2:
		Kit.crenellations(body, rt, drum_h, 10 if crown else 8)
	_evo_parts(t, rt, drum_h)
	# weapon module on top (on the dome for 3+ stories, so it rises with the tower)
	var s := (0.95 + 0.05 * (mass - 3) + 0.06 * stories) * (1.0 + 0.1 * (t.mark - 1))
	var w := Weapons.build(t.type, body, glow_color, s)
	head = w.head
	head.position = Vector3(0, drum_h + (rt * 0.3 if stories >= 3 else 0.0), 0)
	barrel = w.barrel
	spin = w.spin
	muzzle_local = w.muzzle
	if crown:
		Kit.add(body, Kit.cylinder(0.025, 0.025, 1.2, 6), Kit.dark_iron(), Vector3(-rt * 0.8, drum_h + 0.6, 0))
		Kit.add(body, Kit.box(Vector3(0.02, 0.36, 0.26)), Kit.glow(glow_color, 1.5), Vector3(-rt * 0.8, drum_h + 1.0, 0.14))
	# a small warm light so the tower lights its surroundings at dusk
	flash_light = OmniLight3D.new()
	flash_light.light_color = glow_color.lerp(Color(1, 0.7, 0.4), 0.5)
	flash_light.light_energy = 0.6
	flash_light.omni_range = 2.5 + r * 2.0
	flash_light.position = Vector3(0, drum_h * 0.6, 0)
	flash_light.shadow_enabled = false
	body.add_child(flash_light)
	head.rotation.y = yaw
	if t.mark >= 4:
		body.scale = Vector3.ONE * 1.15
	if built_stories >= 0 and built_stories != stories:
		activate_anim = 0.3
	built_stories = stories
	if evolved:
		_start_scaffold(rt, drum_h)


## Mk II lanterns, Mk III technology module, Mk IV rings of light (section 9.5, ref 4).
func _evo_parts(t: SimTower, rt: float, drum_h: float) -> void:
	if t.mark >= 2:
		for i in 4:
			var a := PI / 4.0 + i * PI / 2.0
			Kit.lantern(body, Vector3(cos(a) * rt * 1.05, drum_h, sin(a) * rt * 1.05), 0.3)
	if t.mark < 3:
		return
	var tech := t.tech
	match tech:
		"steam":
			# smoke stack, brass gears and boiler pipes
			Kit.add(body, Kit.cylinder(0.09, 0.11, 0.9, 10), Kit.dark_iron(), Vector3(-rt * 0.75, drum_h + 0.25, -rt * 0.3))
			Kit.add(body, Kit.torus(0.08, 0.13, 10), Kit.brass(), Vector3(-rt * 0.75, drum_h + 0.7, -rt * 0.3), Vector3(PI / 2, 0, 0))
			for i in 2:
				Kit.add(body, Kit.cylinder(0.16, 0.16, 0.05, 12), Kit.brass(), Vector3(rt * 0.95, 0.45 + 0.35 * i, 0), Vector3(0, 0, PI / 2))
			Kit.pipe(body, Vector3(rt * 0.9, 0.3, rt * 0.4), Vector3(rt * 0.9, drum_h, rt * 0.4), 0.05, Kit.brass())
		"aether":
			# floating amber rings and lens crystals
			for i in 2:
				var ring := Kit.add(body, Kit.torus(rt * (1.15 + 0.15 * i), rt * (1.22 + 0.15 * i), 28), Kit.amber(3.0 + i), Vector3(0, drum_h * (0.45 + 0.3 * i), 0))
				evo_rings.append(ring)
			for i in 3:
				var a := i * TAU / 3.0
				Kit.add(body, Kit.sphere(0.08, 8), Kit.glass(Color(1.0, 0.8, 0.45)), Vector3(cos(a) * rt * 1.2, drum_h + 0.15, sin(a) * rt * 1.2))
		"alchemy":
			# copper vats with glowing ooze and glass pipes
			for i in 2:
				var a := PI * 0.25 + i * PI
				var vp := Vector3(cos(a) * rt * 1.15, 0.0, sin(a) * rt * 1.15)
				Kit.add(body, Kit.cylinder(0.17, 0.19, 0.42, 12), Kit.copper(), vp + Vector3(0, 0.36, 0))
				Kit.add(body, Kit.cylinder(0.15, 0.15, 0.03, 12), Kit.glow(Color(0.55, 1.0, 0.2), 3.0), vp + Vector3(0, 0.58, 0))
				Kit.pipe(body, vp + Vector3(0, 0.55, 0), Vector3(cos(a) * rt * 0.6, drum_h - 0.05, sin(a) * rt * 0.6), 0.04, Kit.glass(Color(0.5, 1.0, 0.3)))
	if t.mark >= 4:
		var c: Color = {"steam": Color(1.0, 0.55, 0.2), "aether": Color(1.0, 0.75, 0.35), "alchemy": Color(0.5, 1.0, 0.3)}.get(tech, glow_color)
		for i in 3:
			var ring := Kit.add(body, Kit.torus(rt * (1.35 + 0.12 * i), rt * (1.4 + 0.12 * i), 32), Kit.glow(c, 2.5), Vector3(0, 0.25 + drum_h * 0.28 * i, 0), Vector3.ZERO, Vector3(1, 0.4, 1))
			evo_rings.append(ring)


func _start_scaffold(rt: float, drum_h: float) -> void:
	scaffold = Node3D.new()
	body.add_child(scaffold)
	var iron := Kit.dark_iron()
	for i in 4:
		var a := PI / 4.0 + i * PI / 2.0
		var p := Vector3(cos(a) * rt * 1.45, 0, sin(a) * rt * 1.45)
		Kit.add(scaffold, Kit.box(Vector3(0.05, drum_h + 0.6, 0.05)), iron, p + Vector3(0, (drum_h + 0.6) / 2.0, 0))
	for j in 3:
		Kit.add(scaffold, Kit.torus(rt * 1.4, rt * 1.48, 4), Kit.wood(), Vector3(0, 0.3 + j * (drum_h + 0.3) / 3.0, 0), Vector3(0, PI / 4.0, 0))
	evo_anim = 0.0


func play_activate() -> void:
	activate_anim = 0.0


func on_fire() -> void:
	recoil = 1.0
	if flash_light != null:
		flash_light.light_energy = 2.2
	spin_v = minf(spin_v + 8.0, 40.0)


func muzzle_world() -> Vector3:
	if head == null:
		return global_position + Vector3(tower.cx, top_y + 0.5, tower.cy)
	return head.global_transform * muzzle_local


func _process(delta: float) -> void:
	if evo_anim < Bal.PHI:
		evo_anim += delta
		if scaffold != null:
			var k := evo_anim / Bal.PHI
			scaffold.scale = Vector3(1, minf(1.0, k * 3.0), 1)
			if fmod(evo_anim, 0.25) < delta and k < 0.8 and hammer_cb.is_valid():
				hammer_cb.call(self)
			if evo_anim >= Bal.PHI:
				scaffold.queue_free()
				scaffold = null
				activate_anim = 0.45
	for i in evo_rings.size():
		evo_rings[i].rotation.y += delta * (0.6 + 0.3 * i) * (1 if i % 2 == 0 else -1)
	if drop != null and drop_t < 1.0:
		drop_t += delta
		var fall := Bal.T_S  # 0.236 s fall
		if drop_t < fall:
			var k := drop_t / fall
			drop.position = drop_base + Vector3(0, 2.6 * (1.0 - k * k), 0)
			drop.scale = Vector3(0.95, 1.08, 0.95)
		else:
			var lt := drop_t - fall
			var wv := exp(-lt * 10.0) * cos(lt * 28.0)
			drop.position = drop_base
			drop.scale = Vector3(1.0 + 0.08 * wv, 1.0 - 0.14 * wv, 1.0 + 0.08 * wv)
	if flash_light != null and flash_light.light_energy > 0.6:
		flash_light.light_energy = maxf(0.6, flash_light.light_energy - delta * 10.0)
	if tower == null or head == null:
		return
	# turn visibly toward the sim's aim angle
	var goal := -tower.angle
	yaw = lerp_angle(yaw, goal, 1.0 - pow(0.0005, delta))
	head.rotation.y = yaw
	if recoil > 0.0:
		recoil = maxf(0.0, recoil - delta * 6.0)
		if barrel != null:
			barrel.position.x = -0.12 * recoil * recoil
	if spin != null:
		spin_v = maxf(0.0, spin_v - delta * 12.0)
		spin.rotation.x += spin_v * delta
	if activate_anim < 1.0:
		activate_anim = minf(1.0, activate_anim + delta / Bal.T_L)
		var k := activate_anim
		var e := 1.0 + 0.25 * sin(k * PI) * (1.0 - k)
		body.scale = Vector3(e, k * e, e) if k > 0.01 else Vector3(1, 0.01, 1)
	var crystal := head.find_child("Crystal", true, false)
	if crystal != null:
		crystal.rotation.x += delta * 1.5
	var orb := head.find_child("Orb", true, false) as Node3D
	if orb != null:
		orb.scale = Vector3.ONE * (1.0 + 0.08 * sin(Time.get_ticks_msec() * 0.01))
