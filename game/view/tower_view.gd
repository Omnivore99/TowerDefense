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


func setup(t: SimTower, tv: TerrainView) -> void:
	tower = t
	terrain = tv
	yaw = -t.angle
	rebuild()


func needs_rebuild() -> bool:
	return tower.pieces.size() != piece_count or tower.type != built_type


func rebuild() -> void:
	for c in get_children():
		c.queue_free()
	head = null
	barrel = null
	spin = null
	piece_count = tower.pieces.size()
	built_type = tower.type
	var t := tower
	base_y = t.height * Kit.LH
	var color_id: String = t.stats.get("color", "") if not t.stats.is_empty() else ""
	if color_id == "" and not t.pieces.is_empty():
		color_id = t.pieces[0].piece.color
	glow_color = Bal.PIECE_GLOW.get(color_id, Color(1, 0.65, 0.25))
	# glowing footprint tile under every ground cell (seams show between blocks)
	var tile := Kit.glow(glow_color, 1.6)
	for c in t.layers[0]:
		Kit.add(self, Kit.box(Vector3(0.98, 0.03, 0.98)), tile, Vector3(c.x + 0.5, base_y + 0.015, c.y + 0.5))
	# piece blocks, one deck per story
	for p in t.pieces:
		var mat := Kit.piece_block(p.piece.color, p.piece.golden)
		for c in p.cells:
			var y: float = base_y + 0.03 + p.layer * Kit.BLOCK_H + Kit.BLOCK_H / 2.0
			Kit.add(self, Kit.bevel_box(Vector3(0.86, Kit.BLOCK_H - 0.02, 0.86), 0.07), mat, Vector3(c.x + 0.5, y, c.y + 0.5))
			if p.piece.glyph != "":
				var gc := Color(0.7, 0.9, 1.0) if Pieces.RARE_GLYPHS.has(p.piece.glyph) else Color(1, 0.95, 0.75)
				Kit.add(self, Kit.cylinder(0.14, 0.14, 0.02, 10), Kit.glow(gc, 3.0), Vector3(c.x + 0.5, y + Kit.BLOCK_H / 2.0, c.y + 0.5))
	var stories := t.layers.size()
	top_y = base_y + 0.03 + stories * Kit.BLOCK_H
	if t.type == "":
		return
	# masonry drum on the top deck, sized to the top layer
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
	var r := clampf(0.28 + 0.12 * sqrt(top_cells.size()), 0.36, 0.7)
	var drum_h := 0.55 + 0.12 * stories
	body.position = Vector3(cx, top_y, cy)
	Kit.drum(body, r, drum_h, 0.0)
	Kit.windows(body, r * 1.01, drum_h * 0.55, 4 + stories, Kit.amber(3.0), stories >= 3, 0.4)
	if stories >= 2:
		Kit.add(body, Kit.torus(r * 1.0, r * 1.12, 18), Kit.glow(glow_color, 2.0), Vector3(0, drum_h * 0.25, 0), Vector3.ZERO, Vector3(1, 0.5, 1))
	if stories >= 4:
		for i in 2:
			var a := PI * i + 0.6
			Kit.pipe(body, Vector3(cos(a) * r * 1.05, 0.05, sin(a) * r * 1.05), Vector3(cos(a) * r * 1.05, drum_h - 0.05, sin(a) * r * 1.05), 0.04)
	var crown := stories >= 5
	if crown:
		Kit.crenellations(body, r, drum_h, 8)
	# weapon module
	var s := 0.85 + 0.06 * (mass - 3) + 0.05 * stories
	var w := Weapons.build(t.type, body, glow_color, s)
	head = w.head
	head.position = Vector3(0, drum_h, 0)
	barrel = w.barrel
	spin = w.spin
	muzzle_local = w.muzzle
	if crown:
		# story 5 crown: banners and a spire
		Kit.add(body, Kit.cylinder(0.02, 0.02, 1.0, 6), Kit.dark_iron(), Vector3(-r * 0.7, drum_h + 0.5, 0))
		Kit.add(body, Kit.box(Vector3(0.02, 0.3, 0.22)), Kit.glow(glow_color, 1.5), Vector3(-r * 0.7, drum_h + 0.82, 0.12))
	head.rotation.y = yaw
	if built_stories >= 0 and built_stories != stories:
		activate_anim = 0.3
	built_stories = stories


func play_activate() -> void:
	activate_anim = 0.0


func on_fire() -> void:
	recoil = 1.0
	spin_v = minf(spin_v + 8.0, 40.0)


func muzzle_world() -> Vector3:
	if head == null:
		return global_position + Vector3(tower.cx, top_y + 0.5, tower.cy)
	return head.global_transform * muzzle_local


func _process(delta: float) -> void:
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
