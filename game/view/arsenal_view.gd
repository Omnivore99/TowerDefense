class_name ArsenalView
extends Node3D
## Kits on the map (section 10): road traps, wooden-and-brass metronomes with swinging
## pendulums, torpedo ram launchers and their rockets, and the base ring (howitzers, the
## air-strike antenna and the orbital uplink dish). Rebuilt from the sim's Arsenal each frame.

const KIND_COLOR := {
	"decay": Color(0.45, 1.0, 0.35), "thunder": Color(1.0, 0.75, 0.3), "molasses": Color(1.0, 0.6, 0.15), "unmaking": Color(0.75, 0.45, 1.0),
}

var w  # World
var views := {}  ## kit id -> Node3D
var pad_views := {}  ## pad index -> {node, kind, barrel, top}
var rocket_views := {}  ## rocket id -> Node3D
var rocket_trails := {}  ## rocket id -> Array[Vector3]
var shell_views := {}  ## shell id -> Node3D
var scorch_n := 0
var pendulums := {}  ## metronome id -> Node3D (pivot)
var recoil := {}  ## pad index -> 0..1


func setup(world) -> void:
	w = world


func clear_all() -> void:
	for d in [views, rocket_views, shell_views]:
		for k in d:
			d[k].queue_free()
		d.clear()
	for k in pad_views:
		pad_views[k].node.queue_free()
	pad_views.clear()
	pendulums.clear()
	scorch_n = 0


func _y(x: float, y: float) -> float:
	return w._ground_y(x, y)


func sync(delta: float) -> void:
	var a: Arsenal = w.g.arsenal
	var seen := {}
	for tr in a.traps:
		seen[tr.id] = true
		if not views.has(tr.id):
			views[tr.id] = _trap(tr)
		var n: Node3D = views[tr.id]
		var blink := n.get_node_or_null("Blink") as MeshInstance3D
		if blink != null:
			blink.visible = fmod(Time.get_ticks_msec() / 1000.0, 1.2) < 0.15
	for m in a.metronomes:
		seen[m.id] = true
		if not views.has(m.id):
			views[m.id] = _metronome(m)
		var piv: Node3D = pendulums[m.id]
		var k: float = m.tick_t / Bal.METRONOME.tick
		var amp: float = clampf(m.amp, 0.0, 1.3)
		piv.rotation.z = -m.side * amp * 0.75 * cos(PI * k)
	for r in a.rams:
		seen[r.id] = true
		if not views.has(r.id):
			views[r.id] = _ram(r)
		var tube: Node3D = views[r.id].get_node("Tube")
		tube.rotation.y = lerp_angle(tube.rotation.y, -r.angle, 1.0 - pow(0.01, delta))
		var lbl: MeshInstance3D = views[r.id].get_node("Variant")
		lbl.material_override = Kit.glow(Color(1.0, 0.55, 0.2) if r.variant == "impact" else Color(0.5, 0.9, 1.0), 2.5)
	for id in views.keys():
		if not seen.has(id):
			views[id].queue_free()
			views.erase(id)
			pendulums.erase(id)
	_sync_pads(a, delta)
	_sync_rockets(a)
	_sync_shells(a)
	var sc: Array = w.g.eco.scorched
	while scorch_n < sc.size():
		var s: Dictionary = sc[scorch_n]
		scorch_n += 1
		var p := Vector3(s.x, _y(s.x, s.y) + 0.04, s.y)
		w.fx.decal(p, s.r * 1.4, Color(0.02, 0.02, 0.025, 0.92), 99999.0)


# ------------------------------------------------------------------ traps
func _trap(tr: Dictionary) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	n.position = Vector3(tr.x, _y(tr.x, tr.y), tr.y)
	match tr.kind:
		"landmine":
			Kit.add(n, Kit.cylinder(0.28, 0.32, 0.08, 14), Kit.dark_iron(), Vector3(0, 0.04, 0))
			Kit.add(n, Kit.cylinder(0.08, 0.08, 0.05, 8), Kit.brass(), Vector3(0, 0.1, 0))
			var b := Kit.add(n, Kit.sphere(0.04, 6), Kit.glow(Color(1, 0.2, 0.15), 6.0), Vector3(0.15, 0.1, 0))
			b.name = "Blink"
		"betty":
			Kit.add(n, Kit.cylinder(0.14, 0.16, 0.22, 10), Kit.iron(), Vector3(0, 0.11, 0))
			Kit.add(n, Kit.cylinder(0.02, 0.02, 0.12, 4), Kit.brass(), Vector3(0, 0.28, 0))
			var b2 := Kit.add(n, Kit.sphere(0.035, 6), Kit.glow(Color(1, 0.6, 0.15), 6.0), Vector3(0, 0.36, 0))
			b2.name = "Blink"
		"claymore":
			n.rotation.y = -tr.dir
			Kit.add(n, Kit.box(Vector3(0.12, 0.26, 0.42)), Kit.std("olive", Color(0.25, 0.3, 0.18), 0.1, 0.8), Vector3(0, 0.2, 0))
			Kit.add(n, Kit.box(Vector3(0.02, 0.02, 1.4)), Kit.glow(Color(1, 0.9, 0.6), 1.0), Vector3(0, 0.55, 0), Vector3(0, PI / 2.0, 0))
			var b3 := Kit.add(n, Kit.sphere(0.03, 6), Kit.glow(Color(1, 0.2, 0.15), 6.0), Vector3(0.07, 0.3, 0))
			b3.name = "Blink"
		"spike", "tar":
			for c in tr.cells:
				var p := Vector3(c.x + 0.5, _y(c.x + 0.5, c.y + 0.5) + 0.02, c.y + 0.5) - n.position
				if tr.kind == "tar":
					Kit.add(n, Kit.box(Vector3(0.98, 0.04, 0.98)), Kit.std("tar", Color(0.03, 0.025, 0.02), 0.0, 0.08), p)
				else:
					Kit.add(n, Kit.box(Vector3(0.94, 0.06, 0.94)), Kit.dark_iron(), p)
					for i in 4:
						var o := Vector3(-0.22 + 0.44 * (i % 2), 0.12, -0.22 + 0.44 * (i / 2))
						Kit.add(n, Kit.cone(0.07, 0.22, 6), Kit.iron(), p + o)
	n.scale = Vector3(1, 0.01, 1)
	var tw := n.create_tween()
	tw.tween_property(n, "scale", Vector3.ONE, Bal.T_S).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return n


func spike_punch(id: int) -> void:
	var n: Node3D = views.get(id)
	if n == null:
		return
	n.scale = Vector3(1, 1.8, 1)
	var tw := n.create_tween()
	tw.tween_property(n, "scale", Vector3.ONE, 0.2)


# ------------------------------------------------------------------ metronomes
func _metronome(m: Dictionary) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	n.position = Vector3(m.x, _y(m.x, m.y), m.y)
	var c: Color = KIND_COLOR.get(m.kind, Color.WHITE)
	Kit.add(n, Kit.bevel_box(Vector3(1.6, 0.2, 1.6), 0.05), Kit.stone(Color(0.2, 0.21, 0.25)), Vector3(0, 0.1, 0))
	# a wooden pyramid case
	Kit.add(n, Kit.cylinder(0.25, 0.7, 2.2, 4), Kit.wood(), Vector3(0, 1.3, -0.15), Vector3(0, PI / 4.0, 0))
	Kit.add(n, Kit.box(Vector3(0.5, 1.6, 0.04)), Kit.dark_iron(), Vector3(0, 1.25, 0.21))
	var piv := Node3D.new()
	piv.position = Vector3(0, 0.55, 0.3)
	n.add_child(piv)
	Kit.add(piv, Kit.box(Vector3(0.05, 2.1, 0.05)), Kit.brass(), Vector3(0, 1.05, 0))
	Kit.add(piv, Kit.bevel_box(Vector3(0.24, 0.2, 0.12), 0.03), Kit.glow(c, 2.4), Vector3(0, 1.45, 0))
	Kit.add(n, Kit.torus(0.75, 0.82, 24), Kit.glow(c, 1.2), Vector3(0, 0.22, 0))
	pendulums[m.id] = piv
	return n


# ------------------------------------------------------------------ rams
func _ram(r: Dictionary) -> Node3D:
	var n := Node3D.new()
	add_child(n)
	n.position = Vector3(r.x, _y(r.x, r.y), r.y)
	Kit.add(n, Kit.bevel_box(Vector3(2.7, 0.4, 2.7), 0.08), Kit.stone(Color(0.18, 0.19, 0.23)), Vector3(0, 0.2, 0))
	Kit.drum(n, 0.8, 0.5, 0.4)
	var tube := Node3D.new()
	tube.name = "Tube"
	tube.position = Vector3(0, 1.1, 0)
	n.add_child(tube)
	Kit.add(tube, Kit.cylinder(0.32, 0.36, 1.8, 14), Kit.dark_iron(), Vector3(0.5, 0, 0), Vector3(0, 0, PI / 2.0))
	Kit.add(tube, Kit.torus(0.3, 0.4, 14), Kit.brass(), Vector3(1.35, 0, 0), Vector3(0, 0, PI / 2.0))
	var v := Kit.add(n, Kit.sphere(0.12, 8), Kit.glow(Color(1, 0.55, 0.2), 2.5), Vector3(0, 0.95, 0.85))
	v.name = "Variant"
	return n


func _sync_rockets(a: Arsenal) -> void:
	var seen := {}
	for k in a.rockets:
		seen[k.id] = true
		var n: Node3D = rocket_views.get(k.id)
		if n == null:
			n = Node3D.new()
			add_child(n)
			if k.variant == "impact":
				Kit.add(n, Kit.sphere(0.32, 12), Kit.dark_iron(), Vector3(0, 0.32, 0))
				Kit.add(n, Kit.torus(0.3, 0.36, 14), Kit.glow(Color(1, 0.55, 0.2), 3.0), Vector3(0, 0.32, 0), Vector3(PI / 2.0, 0, 0))
			else:
				for i in 6:
					var seg := Kit.add(n, Kit.sphere(0.2 - i * 0.02, 8), Kit.copper() if i > 0 else Kit.glow(Color(0.5, 0.9, 1.0), 2.5), Vector3.ZERO)
					seg.name = "S%d" % i
			rocket_views[k.id] = n
			rocket_trails[k.id] = []
		var pos := Vector3(lerpf(k.px, k.x, w.alpha), 0, lerpf(k.py, k.y, w.alpha))
		pos.y = _y(pos.x, pos.z)
		var trail: Array = rocket_trails[k.id]
		trail.push_front(pos)
		if trail.size() > 30:
			trail.pop_back()
		if k.variant == "impact":
			n.position = pos + Vector3(0, absf(sin(Time.get_ticks_msec() * 0.02)) * 0.2, 0)
			n.rotation.y = -k.dir
			n.get_child(0).rotation.z -= 0.3
			if randf() < 0.5:
				w.fx.smoke(pos + Vector3(0, 0.3, 0), 1, Color(0.5, 0.5, 0.52, 0.5), 0.2, 0.8, 0.4)
				w.fx.burst(pos + Vector3(0, 0.1, 0), 2, 2.5, Color(1, 0.7, 0.3), 0.04, 0.2)
		else:
			n.position = Vector3.ZERO
			for i in 6:
				var seg2: Node3D = n.get_node("S%d" % i)
				var p: Vector3 = trail[mini(i * 4, trail.size() - 1)]
				var wig := sin(Time.get_ticks_msec() * 0.015 + i) * 0.2
				seg2.position = p + Vector3(sin(k.dir) * wig, 0.22, -cos(k.dir) * wig)
	for id in rocket_views.keys():
		if not seen.has(id):
			rocket_views[id].queue_free()
			rocket_views.erase(id)
			rocket_trails.erase(id)


# ------------------------------------------------------------------ base ring
func _sync_pads(a: Arsenal, delta: float) -> void:
	var unlocked := Arsenal.pads_unlocked(w.g.base)
	for i in 6:
		var kind: String = a.pads[i].get("kind", "") if i < unlocked else "locked"
		var pv: Dictionary = pad_views.get(i, {})
		if pv.is_empty() or pv.kind != kind:
			if not pv.is_empty():
				pv.node.queue_free()
			pv = _pad(i, kind)
			pad_views[i] = pv
		var p: Dictionary = a.pads[i]
		match kind:
			"howitzer":
				var rc: float = recoil.get(i, 0.0)
				recoil[i] = maxf(0.0, rc - delta * 1.6)
				var top: Node3D = pv.top
				top.rotation.y = lerp_angle(top.rotation.y, -p.angle, 1.0 - pow(0.05, delta))
				pv.barrel.position.x = 0.9 - 0.6 * rc * rc
			"airstrike":
				pv.top.rotation.y += delta * (2.0 if p.ready else 0.5)
			"orbital":
				pv.top.rotation.y += delta * 0.3
				pv.top.rotation.z = 0.5 + 0.1 * sin(Time.get_ticks_msec() * 0.0007)


func _pad(i: int, kind: String) -> Dictionary:
	var n := Node3D.new()
	add_child(n)
	var pp := Arsenal.pad_pos(i)
	n.position = Vector3(pp.x, _y(pp.x, pp.y) + 0.1, pp.y)
	var out := {"node": n, "kind": kind, "top": null, "barrel": null}
	if kind == "locked":
		return out
	Kit.add(n, Kit.cylinder(0.95, 1.05, 0.22, 8), Kit.stone(Color(0.2, 0.21, 0.25)), Vector3(0, 0.11, 0))
	Kit.add(n, Kit.torus(0.9, 0.98, 24), Kit.amber(1.5 if kind != "" else 0.6), Vector3(0, 0.23, 0))
	var top := Node3D.new()
	top.position = Vector3(0, 0.24, 0)
	n.add_child(top)
	out.top = top
	match kind:
		"howitzer":
			Kit.add(top, Kit.bevel_box(Vector3(1.1, 0.35, 0.8), 0.05), Kit.dark_iron(), Vector3(0, 0.25, 0))
			Kit.add(top, Kit.cylinder(0.3, 0.3, 0.12, 12), Kit.brass(), Vector3(0, 0.25, 0.45), Vector3(PI / 2.0, 0, 0))
			Kit.add(top, Kit.cylinder(0.3, 0.3, 0.12, 12), Kit.brass(), Vector3(0, 0.25, -0.45), Vector3(PI / 2.0, 0, 0))
			var elev := Node3D.new()
			elev.position = Vector3(0, 0.55, 0)
			elev.rotation.z = 0.55
			top.add_child(elev)
			var barrel := Node3D.new()
			barrel.position = Vector3(0.9, 0, 0)
			elev.add_child(barrel)
			Kit.add(barrel, Kit.cylinder(0.1, 0.14, 2.4, 12), Kit.dark_iron(), Vector3.ZERO, Vector3(0, 0, PI / 2.0))
			Kit.add(barrel, Kit.torus(0.1, 0.16, 12), Kit.brass(), Vector3(1.15, 0, 0), Vector3(0, 0, PI / 2.0))
			out.barrel = barrel
		"airstrike":
			Kit.add(top, Kit.cylinder(0.06, 0.1, 1.6, 8), Kit.dark_iron(), Vector3(0, 0.8, 0))
			for k in 3:
				Kit.add(top, Kit.box(Vector3(1.4 - k * 0.3, 0.04, 0.06)), Kit.brass(), Vector3(0, 0.8 + k * 0.35, 0))
			Kit.add(top, Kit.sphere(0.08, 8), Kit.glow(Color(1, 0.3, 0.2), 5.0), Vector3(0, 1.65, 0))
		"orbital":
			Kit.add(top, Kit.cylinder(0.15, 0.25, 0.8, 10), Kit.dark_iron(), Vector3(0, 0.4, 0))
			var dish := Kit.add(top, Kit.sphere(0.95, 16, true), Kit.std("dish", Color(0.75, 0.76, 0.8), 0.6, 0.35), Vector3(0, 1.05, 0), Vector3(PI, 0, 0), Vector3(1, 0.35, 1))
			dish.name = "Dish"
			Kit.add(top, Kit.cylinder(0.02, 0.02, 0.8, 4), Kit.brass(), Vector3(0, 1.3, 0))
			Kit.add(top, Kit.sphere(0.08, 8), Kit.glow(Color(0.6, 0.85, 1.0), 4.0), Vector3(0, 1.7, 0))
	n.scale = Vector3(1, 0.01, 1)
	var tw := n.create_tween()
	tw.tween_property(n, "scale", Vector3.ONE, Bal.T_M).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return out


func fire_howitzer(i: int) -> Vector3:
	recoil[i] = 1.0
	var pv: Dictionary = pad_views.get(i, {})
	if pv.is_empty() or pv.barrel == null:
		return Vector3.ZERO
	return (pv.barrel as Node3D).global_transform * Vector3(1.3, 0, 0)


func _sync_shells(a: Arsenal) -> void:
	var seen := {}
	for s in a.shells:
		seen[s.id] = true
		var n: Node3D = shell_views.get(s.id)
		if n == null:
			n = Node3D.new()
			add_child(n)
			Kit.add(n, Kit.sphere(0.16, 8), Kit.glow(Color(1, 0.7, 0.35), 3.0))
			shell_views[s.id] = n
		var k: float = clampf((s.t + w.alpha * Bal.DT) / s.dur, 0.0, 1.0)
		var x := lerpf(s.sx, s.tx, k)
		var z := lerpf(s.sy, s.ty, k)
		var base_y := lerpf(_y(s.sx, s.sy) + 1.5, _y(s.tx, s.ty), k)
		n.position = Vector3(x, base_y + 18.0 * 4.0 * k * (1.0 - k), z)
		if randf() < 0.6:
			w.fx.smoke(n.position, 1, Color(0.6, 0.6, 0.62, 0.35), 0.15, 0.7, 0.1)
	for id in shell_views.keys():
		if not seen.has(id):
			shell_views[id].queue_free()
			shell_views.erase(id)
