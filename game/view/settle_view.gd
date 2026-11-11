class_name SettleView
extends Node3D
## Towns and units on the map (sections 11 and 12). Towns grow with their level: a hall in
## the centre and one district per quarter (granary silo, barracks, workshop, walls, market
## stalls). Units are small kit-built models: drones, rifle squads, tanks, engineers, commandos.

const DISTRICT_COLOR := {
	"granary": Color(0.95, 0.75, 0.35), "barracks": Color(0.85, 0.3, 0.25), "workshop": Color(1.0, 0.55, 0.2),
	"walls": Color(0.7, 0.75, 0.85), "market": Color(0.45, 0.85, 0.6),
}
## Quarter offsets from the town centre (cells).
const QUARTERS: Array[Vector2] = [Vector2(-2, -2), Vector2(2, -2), Vector2(-2, 2), Vector2(2, 2)]

var w  # World
var town_views := {}  ## town id -> {node, sig, label, smoke_t}
var unit_views := {}  ## unit id -> Node3D


func setup(world) -> void:
	w = world


func clear_all() -> void:
	for k in town_views:
		town_views[k].node.queue_free()
	town_views.clear()
	for k in unit_views:
		unit_views[k].queue_free()
	unit_views.clear()


func _y(x: float, y: float) -> float:
	return w._ground_y(x, y)


func sync(delta: float) -> void:
	var g: Game = w.g
	var seen := {}
	for t in g.towns.list:
		seen[t.id] = true
		var sig := "%d|%s|%s" % [t.level, str(t.districts), t.fallen]
		var tv: Dictionary = town_views.get(t.id, {})
		if tv.is_empty() or tv.sig != sig:
			if not tv.is_empty():
				tv.node.queue_free()
			tv = _town(t)
			tv.sig = sig
			town_views[t.id] = tv
		var hp_max: float = g.towns.max_hp(t)
		tv.label.text = "%s  %d/%d" % [Bal.TOWN_LEVELS[t.level - 1], ceili(t.hp), int(hp_max)] if not t.fallen else "Ruin (rebuild)"
		tv.label.modulate = Color(1, 0.85, 0.6) if t.hp >= hp_max * 0.5 or t.fallen else Color(1, 0.45, 0.35)
		tv.smoke_t -= delta
		if tv.smoke_t <= 0.0:
			tv.smoke_t = 0.6 if t.fallen else 1.4
			var p := Vector3(t.x + randf_range(-2.5, 2.5), _y(t.x, t.y) + (0.6 if t.fallen else 1.6), t.y + randf_range(-2.5, 2.5))
			w.fx.smoke(p, 1, Color(0.25, 0.25, 0.27, 0.55) if t.fallen else Color(0.75, 0.75, 0.78, 0.35), 0.25, 1.2, 2.5)
	for id in town_views.keys():
		if not seen.has(id):
			town_views[id].node.queue_free()
			town_views.erase(id)
	var useen := {}
	var a: float = w.alpha
	for u in g.deploy.units:
		if not u.alive:
			continue
		useen[u.id] = true
		var n: Node3D = unit_views.get(u.id)
		if n == null:
			n = _unit(u)
			unit_views[u.id] = n
		var x: float = lerpf(u.px, u.x, a)
		var y: float = lerpf(u.py, u.y, a)
		var fly: bool = Bal.UNITS[u.kind].fly
		n.position = Vector3(x, _y(x, y) + (1.6 + 0.12 * sin(Time.get_ticks_msec() * 0.006 + u.id) if fly else 0.0), y)
		n.rotation.y = lerp_angle(n.rotation.y, -u.dir, 1.0 - pow(0.001, delta))
		var hp_bar: MeshInstance3D = n.get_node_or_null("Hp")
		if hp_bar != null:
			var f: float = clampf(u.hp / u.max, 0.0, 1.0)
			hp_bar.scale.x = maxf(0.02, f)
			hp_bar.visible = f < 0.999
		var mem: Node3D = n.get_node_or_null("Members")
		if mem != null:
			var alive: int = g.deploy.members_alive(u)
			for i in mem.get_child_count():
				mem.get_child(i).visible = i < alive
		var blink: Node3D = n.get_node_or_null("Blink")
		if blink != null:
			blink.visible = fmod(Time.get_ticks_msec() / 1000.0 + u.id * 0.3, 0.8) < 0.2
	for id in unit_views.keys():
		if not useen.has(id):
			var nd: Node3D = unit_views[id]
			var tw := nd.create_tween()
			tw.tween_property(nd, "scale", Vector3(1.4, 0.01, 1.4), 0.25)
			tw.tween_callback(nd.queue_free)
			unit_views.erase(id)


# ------------------------------------------------------------------ towns
func _town(t: Dictionary) -> Dictionary:
	var n := Node3D.new()
	add_child(n)
	var gy := _y(t.x, t.y)
	n.position = Vector3(t.x, gy, t.y)
	var stone := Kit.stone(Color(0.32, 0.3, 0.3))
	var ruin: bool = t.fallen
	# paved plaza and lanes
	Kit.add(n, Kit.box(Vector3(7.6, 0.06, 7.6)), Kit.std("town_pave", Color(0.33, 0.31, 0.29), 0.0, 0.95), Vector3(0, 0.03, 0))
	Kit.add(n, Kit.box(Vector3(7.2, 0.07, 0.8)), Kit.std("town_lane", Color(0.42, 0.39, 0.36), 0.0, 0.9), Vector3(0, 0.04, 0))
	Kit.add(n, Kit.box(Vector3(0.8, 0.07, 7.2)), Kit.std("town_lane", Color(0.42, 0.39, 0.36), 0.0, 0.9), Vector3(0, 0.04, 0))
	# town hall
	var hall_h: float = 0.9 + 0.25 * t.level
	Kit.drum(n, 0.95, hall_h, 0.0)
	Kit.add(n, Kit.cone(1.15, 0.9 + 0.1 * t.level, 8), Kit.roof(), Vector3(0, hall_h + 0.45 + 0.05 * t.level, 0))
	if t.level >= 5:
		Kit.crenellations(n, 1.0, hall_h, 10)
		Kit.add(n, Kit.cylinder(0.04, 0.04, 1.0, 6), Kit.dark_iron(), Vector3(0, hall_h + 1.5, 0))
		Kit.add(n, Kit.box(Vector3(0.5, 0.3, 0.02)), Kit.glow(Color(1.0, 0.75, 0.3), 1.5), Vector3(0.27, hall_h + 1.85, 0))
	Kit.windows(n, 0.96, hall_h * 0.55, 6, Kit.amber(2.0 if not ruin else 0.0))
	for qi in 4:
		var q: Vector2 = QUARTERS[qi]
		var d: String = t.districts[qi]
		var qn := Node3D.new()
		n.add_child(qn)
		qn.position = Vector3(q.x, 0, q.y)
		if d == "":
			_houses(qn, t.level, qi)
		else:
			_district(qn, d, qi)
	if ruin:
		for c in n.get_children():
			if c is Node3D:
				(c as Node3D).scale.y *= 0.35
		Kit.add(n, Kit.box(Vector3(7.6, 0.08, 7.6)), Kit.std("ash", Color(0.06, 0.055, 0.05, 0.8), 0.0, 1.0), Vector3(0, 0.07, 0))
	var label := Label3D.new()
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.font_size = 64
	label.pixel_size = 0.006
	label.outline_size = 12
	label.position = Vector3(0, 3.6, 0)
	label.no_depth_test = true
	n.add_child(label)
	n.scale = Vector3(1, 0.01, 1)
	var tw := n.create_tween()
	tw.tween_property(n, "scale", Vector3.ONE, 0.6).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return {"node": n, "label": label, "smoke_t": 0.5}


func _houses(qn: Node3D, level: int, seed_i: int) -> void:
	var n_h := clampi(1 + level, 2, 5)
	for i in n_h:
		var a := TAU * float(i) / n_h + seed_i
		var p := Vector3(cos(a) * 1.1, 0, sin(a) * 1.1)
		var hh := 0.45 + 0.1 * ((i + seed_i) % 3)
		Kit.add(qn, Kit.bevel_box(Vector3(0.75, hh, 0.6)), Kit.std("plaster", Color(0.78, 0.72, 0.62), 0.0, 0.9), p + Vector3(0, hh / 2.0, 0), Vector3(0, a, 0))
		Kit.add(qn, Kit.cone(0.6, 0.45, 4), Kit.roof(), p + Vector3(0, hh + 0.22, 0), Vector3(0, a + PI / 4.0, 0))
		if i == 0:
			Kit.add(qn, Kit.box(Vector3(0.12, 0.35, 0.12)), Kit.stone(), p + Vector3(0.18, hh + 0.35, 0))


func _district(qn: Node3D, d: String, qi: int) -> void:
	var col: Color = DISTRICT_COLOR[d]
	match d:
		"granary":
			for i in 2:
				var p := Vector3(-0.6 + 1.2 * i, 0, 0)
				Kit.add(qn, Kit.cylinder(0.5, 0.55, 1.5, 14), Kit.wood(), p + Vector3(0, 0.75, 0))
				Kit.add(qn, Kit.cone(0.62, 0.55, 14), Kit.std("granary_roof", Color(0.55, 0.32, 0.18), 0.0, 0.8), p + Vector3(0, 1.78, 0))
			for i in 4:
				Kit.add(qn, Kit.cylinder(0.18, 0.18, 0.3, 8), Kit.std("sack", Color(0.85, 0.75, 0.5), 0.0, 1.0), Vector3(-1.2 + 0.4 * i, 0.15, 1.2))
		"barracks":
			Kit.add(qn, Kit.bevel_box(Vector3(2.6, 0.8, 1.2)), Kit.stone(Color(0.3, 0.29, 0.28)), Vector3(0, 0.4, -0.4))
			Kit.add(qn, Kit.box(Vector3(2.8, 0.12, 1.4)), Kit.roof(), Vector3(0, 0.86, -0.4))
			Kit.add(qn, Kit.cylinder(0.03, 0.03, 1.6, 6), Kit.dark_iron(), Vector3(1.2, 0.8, 0.9))
			Kit.add(qn, Kit.box(Vector3(0.5, 0.32, 0.02)), Kit.std("flag", col, 0.0, 0.8, col, 0.4), Vector3(1.46, 1.45, 0.9))
			for i in 3:
				Kit.add(qn, Kit.box(Vector3(0.2, 0.45, 0.2)), Kit.std("target", Color(0.7, 0.55, 0.35), 0.0, 0.9), Vector3(-1.0 + 0.7 * i, 0.22, 1.0))
		"workshop":
			Kit.add(qn, Kit.bevel_box(Vector3(2.0, 1.0, 1.6)), Kit.stone(Color(0.27, 0.27, 0.3)), Vector3(0, 0.5, 0))
			Kit.add(qn, Kit.box(Vector3(2.2, 0.12, 1.8)), Kit.dark_iron(), Vector3(0, 1.05, 0))
			Kit.add(qn, Kit.cylinder(0.18, 0.22, 1.2, 10), Kit.copper(), Vector3(0.6, 1.6, 0.4))
			var gear := Kit.add(qn, Kit.torus(0.25, 0.42, 12), Kit.brass(), Vector3(-1.05, 0.7, 0), Vector3(0, 0, PI / 2.0))
			gear.name = "Gear"
			Kit.add(qn, Kit.box(Vector3(0.6, 0.5, 0.05)), Kit.glow(Color(1.0, 0.5, 0.15), 2.0), Vector3(0, 0.45, 0.81))
		"walls":
			var r := 1.6
			for i in 4:
				var a := PI / 2.0 * i
				var p := Vector3(cos(a), 0, sin(a)) * r
				Kit.add(qn, Kit.bevel_box(Vector3(0.4, 1.0, 2.6)), Kit.stone(), p + Vector3(0, 0.5, 0), Vector3(0, a, 0))
			Kit.drum(qn, 0.5, 1.6, 0.0)
			Kit.crenellations(qn, 0.52, 1.6, 6)
			var gun := Kit.add(qn, Kit.cylinder(0.07, 0.07, 0.7, 8), Kit.dark_iron(), Vector3(0, 1.85, 0.3), Vector3(PI / 2.0, 0, 0))
			gun.name = "Gun"
			Kit.lantern(qn, Vector3(0.45, 1.6, -0.45))
		"market":
			for i in 4:
				var p := Vector3(-0.9 + 1.2 * (i % 2) + 0.3, 0, -0.7 + 1.4 * (i / 2))
				for k in 4:
					var lx := (k % 2) * 0.8 - 0.4
					var lz := (k / 2) * 0.6 - 0.3
					Kit.add(qn, Kit.cylinder(0.03, 0.03, 0.7, 4), Kit.wood(), p + Vector3(lx, 0.35, lz))
				var aw := Color(0.85, 0.3, 0.25) if i % 2 == 0 else Color(0.95, 0.8, 0.4)
				Kit.add(qn, Kit.box(Vector3(1.0, 0.06, 0.8)), Kit.std("awning%d" % (i % 2), aw, 0.0, 0.9), p + Vector3(0, 0.72, 0), Vector3(0.12, 0, 0))
				Kit.add(qn, Kit.box(Vector3(0.8, 0.25, 0.5)), Kit.wood(), p + Vector3(0, 0.15, 0))


# ------------------------------------------------------------------ units
func _unit(u: Dictionary) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	var khaki := Kit.std("khaki", Color(0.42, 0.42, 0.3), 0.1, 0.8)
	var helmet := Kit.std("helmet", Color(0.3, 0.33, 0.25), 0.4, 0.5)
	match u.kind:
		"drones":
			var mem := Node3D.new()
			mem.name = "Members"
			n.add_child(mem)
			for i in 3:
				var d := Node3D.new()
				mem.add_child(d)
				d.position = Vector3(cos(TAU * i / 3.0) * 0.55, 0.1 * i, sin(TAU * i / 3.0) * 0.55)
				Kit.add(d, Kit.box(Vector3(0.28, 0.08, 0.28)), Kit.dark_iron())
				for k in 4:
					var rp := Vector3(0.2 * (1 if k % 2 == 0 else -1), 0.05, 0.2 * (1 if k < 2 else -1))
					Kit.add(d, Kit.cylinder(0.11, 0.11, 0.01, 10), Kit.glow(Color(0.7, 0.85, 1.0), 0.6), rp)
			var b := Kit.add(n, Kit.sphere(0.05, 6), Kit.glow(Color(0.3, 0.7, 1.0), 6.0), Vector3(0, 0.12, 0))
			b.name = "Blink"
		"rifles":
			var mem2 := Node3D.new()
			mem2.name = "Members"
			n.add_child(mem2)
			for i in 5:
				var s := Node3D.new()
				mem2.add_child(s)
				s.position = Vector3(-0.2 + 0.35 * float(i % 2), 0, -0.6 + 0.3 * i)
				Kit.add(s, Kit.cylinder(0.09, 0.11, 0.32, 8), khaki, Vector3(0, 0.22, 0))
				Kit.add(s, Kit.sphere(0.08, 8), Kit.std("skin", Color(0.85, 0.7, 0.55), 0.0, 0.8), Vector3(0, 0.45, 0))
				Kit.add(s, Kit.sphere(0.1, 8, true), helmet, Vector3(0, 0.48, 0))
				Kit.add(s, Kit.box(Vector3(0.3, 0.03, 0.03)), Kit.dark_iron(), Vector3(0.15, 0.3, 0.06))
		"tank":
			Kit.add(n, Kit.bevel_box(Vector3(1.3, 0.35, 0.85)), Kit.std("tank_hull", Color(0.33, 0.36, 0.26), 0.4, 0.6), Vector3(0, 0.3, 0))
			for sgn in [-1, 1]:
				Kit.add(n, Kit.box(Vector3(1.4, 0.22, 0.2)), Kit.dark_iron(), Vector3(0, 0.12, 0.45 * sgn))
			var tur := Node3D.new()
			tur.name = "Turret"
			n.add_child(tur)
			tur.position = Vector3(0, 0.55, 0)
			Kit.add(tur, Kit.cylinder(0.3, 0.34, 0.22, 12), Kit.std("tank_hull", Color(0.33, 0.36, 0.26), 0.4, 0.6))
			Kit.add(tur, Kit.cylinder(0.05, 0.06, 0.8, 8), Kit.dark_iron(), Vector3(0.5, 0.03, 0), Vector3(0, 0, PI / 2.0))
		"engineer":
			Kit.add(n, Kit.bevel_box(Vector3(0.9, 0.35, 0.5)), Kit.std("truck", Color(0.85, 0.65, 0.2), 0.3, 0.6), Vector3(0, 0.3, 0))
			Kit.add(n, Kit.box(Vector3(0.3, 0.3, 0.46)), Kit.glass(Color(0.6, 0.8, 1.0)), Vector3(0.35, 0.6, 0))
			Kit.add(n, Kit.box(Vector3(0.06, 0.06, 1.0)), Kit.dark_iron(), Vector3(-0.2, 0.9, 0), Vector3(0.6, PI / 2.0, 0))
			for sgn in [-1, 1]:
				for k in [-1, 1]:
					Kit.add(n, Kit.cylinder(0.12, 0.12, 0.08, 10), Kit.dark_iron(), Vector3(0.28 * k, 0.12, 0.27 * sgn), Vector3(PI / 2.0, 0, 0))
		"commando":
			Kit.add(n, Kit.cylinder(0.11, 0.13, 0.42, 8), Kit.std("stealth", Color(0.1, 0.1, 0.13), 0.2, 0.6), Vector3(0, 0.28, 0))
			Kit.add(n, Kit.sphere(0.11, 8), Kit.std("stealth", Color(0.1, 0.1, 0.13), 0.2, 0.6), Vector3(0, 0.58, 0))
			Kit.add(n, Kit.box(Vector3(0.06, 0.04, 0.18)), Kit.glow(Color(0.3, 1.0, 0.7), 5.0), Vector3(0.09, 0.6, 0))
		"sandbag":
			for i in 5:
				Kit.add(n, Kit.bevel_box(Vector3(0.42, 0.18, 0.26), 0.07), Kit.std("sandbag", Color(0.66, 0.58, 0.4), 0.0, 1.0), Vector3(0, 0.09 + 0.17 * (i / 3), -0.45 + 0.45 * (i % 3) + 0.2 * (i / 3)))
	var hp := Kit.add(n, Kit.box(Vector3(0.9, 0.05, 0.05)), Kit.glow(Color(0.4, 1.0, 0.5), 1.5), Vector3(0, 1.0, 0))
	hp.name = "Hp"
	hp.visible = false
	n.scale = Vector3(1.4, 0.01, 1.4)
	var tw := n.create_tween()
	tw.tween_property(n, "scale", Vector3.ONE * 1.4, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return n


func town_at_point(x: float, y: float) -> int:
	var g: Game = w.g
	return int(g.towns.town_at.get(Board.cell_idx(clampi(int(x), 0, Bal.GRID_W - 1), clampi(int(y), 0, Bal.GRID_H - 1)), 0))


func unit_at_point(x: float, y: float) -> int:
	var best := 0
	var bd := 1.2
	for u in w.g.deploy.units:
		if u.alive and u.kind != "sandbag":
			var d := Vector2(u.x - x, u.y - y).length()
			if d < bd:
				bd = d
				best = u.id
	return best
