class_name Arsenal
extends RefCounted
## Kits (section 10): the Kit belt, road traps, metronomes, torpedo rams and the base ring
## (howitzers, air-strike antenna, orbital uplink). The Game owns one Arsenal and passes itself
## into step() so there is no reference cycle.

var belt: Array = []
var traps: Array = []  ## {id, kind, cells, x, y, hits, armed, dir, hit_ids, burn}
var trap_at := {}  ## cell index -> trap id
var metronomes: Array = []  ## {id, kind, cells, x, y, amp, tick_t, side, ticks}
var rams: Array = []  ## {id, variant, cells, x, y, cd, retool, priority, angle}
var pads: Array = []  ## 6 entries: {} (empty) or {kind, cd, ready, cal, rif, auto, angle, priority}
var shells: Array = []  ## howitzer shells in flight {id, sx, sy, tx, ty, x, y, t, dur, dmg, r, cluster}
var rockets: Array = []  ## ram rockets {id, variant, route, d, x, y, px, py, travelled, hit, alive, dmg, ram}
var blasts: Array = []  ## scheduled air-strike / orbital damage {at, x, y, r, dmg, kind, hit}
var off_at := {}  ## cell index -> metronome or ram id
var assist_t := 0.0
var t := 0.0


func _init() -> void:
	belt.resize(Bal.KIT_BELT)
	belt.fill("")
	pads.resize(6)
	for i in 6:
		pads[i] = {}


# ---------------------------------------------------------------- base ring
static func pad_pos(i: int) -> Vector2:
	var a := PI / 6.0 + i * PI / 3.0
	return Board.CORE_PT + Vector2(cos(a), sin(a)) * 4.6


static func pads_unlocked(base: Dictionary) -> int:
	var n := 0
	for i in range(3, Bal.BASE_SQUARES.size()):
		if i < int(base.unlocked):
			n += 2
	return n


func pad_count(kind: String) -> int:
	var n := 0
	for p in pads:
		if p.get("kind", "") == kind:
			n += 1
	return n


func free_pad(base: Dictionary) -> int:
	for i in pads_unlocked(base):
		if pads[i].is_empty():
			return i
	return -1


# ---------------------------------------------------------------- buying
func kit_blocked(g, id: String) -> String:
	var k: Dictionary = Bal.KITS[id]
	if not g.has_building("armory") and id != "landmine" and id != "spike":
		return "Build the Armory first"
	if k.where == "ring":
		if free_pad(g.base) < 0:
			return "No free base-ring pad" if pads_unlocked(g.base) > 0 else "Base ring opens with base square 4"
		if id == "howitzer" and pad_count("howitzer") >= int(Bal.HOWITZER.max):
			return "Up to 3 howitzers"
		if id != "howitzer" and pad_count(id) >= 1:
			return "Only one"
	elif belt.find("") < 0:
		return "Kit belt full"
	if not Evolve.can_afford(g.base, kit_cost(g, id)):
		return "Not enough resources"
	return ""


## Kit cost after Workshop districts (-20% Ore and Timber each, up to -60%).
func kit_cost(g, id: String) -> Dictionary:
	var c: Dictionary = Bal.KITS[id].cost.duplicate()
	var n: int = g.towns.count_district("workshop") if g.towns != null else 0
	if n > 0 and Bal.KITS[id].where != "ring":
		var f := 1.0 - minf(0.6, Bal.TOWN.workshop * n)
		for k in ["ore", "timber"]:
			if c.has(k):
				c[k] = ceilf(float(c[k]) * f)
	return c


func buy(g, id: String) -> String:
	var err := kit_blocked(g, id)
	if err != "":
		return err
	var k: Dictionary = Bal.KITS[id]
	Evolve.pay(g.base, kit_cost(g, id))
	if k.where == "ring":
		var i := free_pad(g.base)
		var pad := {"kind": id, "cd": 2.0, "ready": false, "cal": 0, "rif": 0, "auto": 0, "angle": PI, "priority": "most", "charge": 0.0}
		if id == "airstrike":
			pad.charge = 0.0
		pads[i] = pad
		g.events.append({"t": "kitBuilt", "kind": id, "pad": i})
	else:
		belt[belt.find("")] = id
		g.events.append({"t": "kitBought", "kind": id})
	return ""


const PAD_UPGRADES := {"cal": {"name": "Caliber", "cost": 34.0, "note": "+50% damage"}, "rif": {"name": "Rifling", "cost": 21.0, "note": "+21% range"}, "auto": {"name": "Autoloader", "cost": 34.0, "note": "-30% reload"}}


func upgrade_pad(g, i: int, which: String) -> String:
	var p: Dictionary = pads[i]
	if p.get("kind", "") != "howitzer" and not (p.get("kind", "") == "airstrike" and which == "rif"):
		return "Nothing to upgrade"
	if int(p.get(which, 0)) >= 1:
		return "Already upgraded"
	var c: float = PAD_UPGRADES[which].cost
	if g.base.ore < c:
		return "Not enough Ore"
	g.base.ore -= c
	p[which] = 1
	return ""


# ---------------------------------------------------------------- placing
static func footprint(id: String, rot: int) -> Vector2i:
	var sz: Vector2i = Bal.KITS[id].size
	return Vector2i(sz.y, sz.x) if rot % 2 == 1 else sz


static func kit_cells(id: String, rot: int, cx: int, cy: int) -> Array[Vector2i]:
	var sz := footprint(id, rot)
	var out: Array[Vector2i] = []
	var ox := cx - (sz.x - 1) / 2
	var oy := cy - (sz.y - 1) / 2
	for y in sz.y:
		for x in sz.x:
			out.append(Vector2i(ox + x, oy + y))
	return out


func _road_kits_in(g, m: int) -> int:
	var n := 0
	for tr in traps:
		var c: Vector2i = tr.cells[0]
		if Board.mid(c.x / Bal.MACRO, c.y / Bal.MACRO) == m:
			n += 1
	for rp in g.road_pieces:
		if rp.macro == m:
			n += 1
	return n


## {ok, reason, cells} for placing belt kit id at (cx, cy).
func preview(g, id: String, rot: int, cx: int, cy: int) -> Dictionary:
	var cells := kit_cells(id, rot, cx, cy)
	var where: String = Bal.KITS[id].where
	var b: Board = g.board
	var bad := func(r: String) -> Dictionary: return {"ok": false, "reason": r, "cells": cells}
	for c in cells:
		if not Board.in_grid(c.x, c.y):
			return bad.call("Off the map")
		var i := Board.cell_idx(c.x, c.y)
		if b.is_core_cell(c.x, c.y):
			return bad.call("That is the core")
		if trap_at.has(i) or off_at.has(i) or g.towns.town_at.has(i):
			return bad.call("Kit already there")
		if where == "road":
			if not b.is_road(c.x, c.y):
				return bad.call("Traps go on the road")
			if g.obj_at[i] != 0:
				return bad.call("Road piece there")
		else:
			if b.is_road(c.x, c.y):
				return bad.call("Not on the road")
			if g.tower_at[i] != 0 or g.obj_at[i] != 0:
				return bad.call("Something is built there")
			if g.board.is_blocked_terrain(i):
				return bad.call(g.blocked_reason(i))
	if where == "road":
		var m := Board.mid(cells[0].x / Bal.MACRO, cells[0].y / Bal.MACRO)
		if _road_kits_in(g, m) >= Bal.ROAD_KITS_PER_SQUARE:
			return bad.call("2 road kits per square")
	if where == "roadside":
		var touch := false
		for c in cells:
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = c + d
				if Board.in_grid(n.x, n.y) and b.is_road(n.x, n.y):
					touch = true
		if not touch:
			return bad.call("Rams must touch a road")
	return {"ok": true, "reason": "", "cells": cells}


func place(g, slot: int, rot: int, cx: int, cy: int) -> Dictionary:
	if slot < 0 or slot >= belt.size() or belt[slot] == "":
		return {"ok": false, "reason": "Empty slot"}
	var id: String = belt[slot]
	var pv := preview(g, id, rot, cx, cy)
	if not pv.ok:
		g.events.append({"t": "reject", "reason": pv.reason, "cells": pv.cells})
		return pv
	belt[slot] = ""
	var cells: Array = pv.cells
	var sx := 0.0
	var sy := 0.0
	for c in cells:
		sx += c.x + 0.5
		sy += c.y + 0.5
	sx /= cells.size()
	sy /= cells.size()
	var kid: int = g.next_id
	g.next_id += 1
	var where: String = Bal.KITS[id].where
	if where == "road":
		var tr := {"id": kid, "kind": id, "cells": cells, "x": sx, "y": sy, "hits": int(Bal.TRAP.spikeHits) + 8 * g.cards.n("trapsmith"), "armed": true, "dir": _road_dir(g, sx, sy) + PI, "hit_ids": {}, "burn": 0.0}
		traps.append(tr)
		for c in cells:
			trap_at[Board.cell_idx(c.x, c.y)] = kid
	elif id.begins_with("metronome"):
		metronomes.append({"id": kid, "kind": id.trim_prefix("metronome_"), "cells": cells, "x": sx, "y": sy, "amp": 1.0, "tick_t": 0.0, "side": 1, "ticks": 0})
		for c in cells:
			off_at[Board.cell_idx(c.x, c.y)] = kid
	else:
		rams.append({"id": kid, "variant": id.trim_prefix("ram_"), "cells": cells, "x": sx, "y": sy, "cd": 1.0, "retool": 0.0, "priority": "first", "angle": _road_dir(g, sx, sy) + PI})
		for c in cells:
			off_at[Board.cell_idx(c.x, c.y)] = kid
	g.events.append({"t": "kitPlaced", "kind": id, "id": kid, "x": sx, "y": sy})
	return {"ok": true, "id": kid}


## Heading of the nearest road (direction enemies walk) at a point.
func _road_dir(g, x: float, y: float) -> float:
	var best := INF
	var dir := 0.0
	for r: Route in g.board.routes:
		var hit := _nearest_on(r, x, y)
		if hit.x < best:
			best = hit.x
			dir = r.at(hit.y).z
	return dir


## Vector2(distance, d along route) of the route point nearest to (x, y).
static func _nearest_on(r: Route, x: float, y: float) -> Vector2:
	var best := INF
	var bd := 0.0
	var p := Vector2(x, y)
	for i in range(1, r.pts.size()):
		var a := r.pts[i - 1]
		var b := r.pts[i]
		var ab := b - a
		var l2 := ab.length_squared()
		var k := 0.0 if l2 == 0.0 else clampf((p - a).dot(ab) / l2, 0.0, 1.0)
		var q := a + ab * k
		var dd := q.distance_squared_to(p)
		if dd < best:
			best = dd
			bd = r.cum[i - 1] + sqrt(l2) * k
	return Vector2(sqrt(best), bd)


func retool_ram(id: int) -> bool:
	for r in rams:
		if r.id == id:
			r.variant = "grinder" if r.variant == "impact" else "impact"
			r.retool = 2.0
			r.cd = maxf(r.cd, 2.0)
			return true
	return false


func ram_by_id(id: int) -> Dictionary:
	for r in rams:
		if r.id == id:
			return r
	return {}


func kit_at_cell(i: int) -> Dictionary:
	var id: int = off_at.get(i, trap_at.get(i, 0))
	if id == 0:
		return {}
	for l in [metronomes, rams, traps]:
		for k in l:
			if k.id == id:
				return k
	return {}


# ---------------------------------------------------------------- metronome shove
## Timing: a well-timed shove lands within the window of the end of a swing.
static func well_timed(m: Dictionary) -> bool:
	var tick: float = Bal.METRONOME.tick
	var w: float = Bal.METRONOME.window
	return m.tick_t > tick - w or m.tick_t < w


func shove(g, id: int, strength: float = 1.0) -> String:
	for m in metronomes:
		if m.id != id:
			continue
		var timed := well_timed(m)
		if timed:
			m.amp = minf(Bal.METRONOME.max, m.amp + Bal.METRONOME.timedShove * strength)
		else:
			m.amp = minf(maxf(1.0, m.amp), m.amp + Bal.METRONOME.shove * strength)
		g.events.append({"t": "shove", "id": m.id, "x": m.x, "y": m.y, "timed": timed, "amp": m.amp})
		return "timed" if timed else "ok"
	return ""


func nearest_metronome(x: float, y: float, within: float = 8.0) -> int:
	var best := within * within
	var out := 0
	for m in metronomes:
		var d: float = (m.x - x) * (m.x - x) + (m.y - y) * (m.y - y)
		if d < best:
			best = d
			out = m.id
	return out


# ---------------------------------------------------------------- strikes (player calls)
func airstrike_pad() -> Dictionary:
	for p in pads:
		if p.get("kind", "") == "airstrike":
			return p
	return {}


func orbital_pad() -> Dictionary:
	for p in pads:
		if p.get("kind", "") == "orbital":
			return p
	return {}


func airstrike_radius() -> float:
	var p := airstrike_pad()
	return float(Bal.AIRSTRIKE.radius) + (13.0 if int(p.get("rif", 0)) > 0 else 0.0)


func can_airstrike(g) -> bool:
	var p := airstrike_pad()
	return not p.is_empty() and p.ready and g.phase == "wave"


func can_orbital(g) -> bool:
	var p := orbital_pad()
	return not p.is_empty() and p.ready and g.phase == "wave"


func airstrike(g, x: float, y: float, dir: float) -> bool:
	if not can_airstrike(g):
		return false
	if Vector2(x, y).distance_to(Board.CORE_PT) > airstrike_radius():
		return false
	var p := airstrike_pad()
	p.ready = false
	p.charge = 0.0
	var n: int = Bal.AIRSTRIKE.len
	var unit: float = g.wave.get("unitHp", 50.0)
	for i in n:
		var k := (i - (n - 1) / 2.0)
		blasts.append({"at": t + 0.4 + 0.6 * i / float(n), "x": x + cos(dir) * k, "y": y + sin(dir) * k, "r": Bal.AIRSTRIKE.width / 2.0, "dmg": Bal.AIRSTRIKE.units * unit, "kind": "air", "hit": {}})
	g.events.append({"t": "airstrike", "x": x, "y": y, "dir": dir, "len": n})
	return true


func orbital(g, x: float, y: float) -> bool:
	if not can_orbital(g):
		return false
	var p := orbital_pad()
	p.ready = false
	p.cd = Bal.ORBITAL.recharge
	var unit: float = g.wave.get("unitHp", 50.0)
	var d0: float = Bal.ORBITAL.delay
	blasts.append({"at": t + d0, "x": x, "y": y, "r": Bal.ORBITAL.r0, "dmg": Bal.ORBITAL.units * unit, "kind": "orbital", "hit": {}})
	blasts.append({"at": t + d0, "x": x, "y": y, "r": Bal.ORBITAL.r0, "r1": Bal.ORBITAL.r1, "dur": d0, "dmg": Bal.ORBITAL.ringUnits * unit, "kind": "ring", "hit": {}, "start": t + d0})
	g.events.append({"t": "orbital", "x": x, "y": y, "delay": d0})
	if g.eco != null:
		g.eco.scorch(x, y, Bal.ORBITAL.r1 * 0.5)
	return true


# ---------------------------------------------------------------- sim step
func step(g, dt: float) -> void:
	t += dt
	var wave_on: bool = g.phase == "wave"
	var unit: float = g.wave.get("unitHp", 50.0)
	_step_pads(g, dt, wave_on, unit)
	_step_shells(g, dt)
	_step_blasts(g)
	if not wave_on:
		return
	_step_traps(g, dt, unit)
	_step_metronomes(g, dt, unit)
	_step_rams(g, dt, unit)
	_step_rockets(g, dt, unit)


func _step_pads(g, dt: float, wave_on: bool, unit: float) -> void:
	for i in pads.size():
		var p: Dictionary = pads[i]
		if p.is_empty():
			continue
		match p.kind:
			"howitzer":
				p.cd -= dt
				if not wave_on or p.cd > 0.0:
					continue
				var pos := pad_pos(i)
				var rng: float = Bal.HOWITZER.range * (1.21 if p.rif > 0 else 1.0)
				var tgt: SimEnemy = null
				var best := -INF
				for e: SimEnemy in g.enemies:
					if not e.alive or e.immune:
						continue
					var dist := Vector2(e.x - pos.x, e.y - pos.y).length()
					if dist > rng or dist < Bal.HOWITZER.minRange:
						continue
					var sc: float = g.priority_score(p.priority, e, pos.x, pos.y)
					if sc > best:
						best = sc
						tgt = e
				if tgt == null:
					continue
				var flight: float = Bal.HOWITZER.flight
				var lead := tgt.route.at(tgt.d + tgt.speed * tgt.slow_mult * flight)
				p.angle = atan2(lead.y - pos.y, lead.x - pos.x)
				p.cd = Bal.HOWITZER.reload * (0.7 if p.auto > 0 else 1.0)
				var dmg: float = Bal.HOWITZER.units * unit * (1.5 if p.cal > 0 else 1.0) * (1.0 + Bal.TECH_PERK_DMG if Evolve.level_of(g.base, "steam") >= 2 else 1.0)
				var sid: int = g.next_id
				g.next_id += 1
				shells.append({"id": sid, "sx": pos.x, "sy": pos.y, "tx": lead.x, "ty": lead.y, "x": pos.x, "y": pos.y, "t": 0.0, "dur": flight, "dmg": dmg * (1.0 + 0.12 * g.cards.f("artillery")), "r": Bal.HOWITZER.radius * (1.0 + 0.08 * g.cards.f("artillery")), "cluster": Evolve.level_of(g.base, "steam") >= 5})
				g.events.append({"t": "howitzer", "pad": i, "x": pos.x, "y": pos.y, "tx": lead.x, "ty": lead.y, "dur": flight, "id": sid})
			"airstrike":
				if not p.ready and wave_on:
					p.charge += dt * (1.0 + 0.1 * g.cards.f("airsup"))
					if p.charge >= Bal.AIRSTRIKE.every:
						p.ready = true
						g.events.append({"t": "strikeReady", "kind": "airstrike"})
			"orbital":
				if not p.ready:
					p.cd -= dt if wave_on else 0.0
					if p.cd <= 0.0:
						p.ready = true
						g.events.append({"t": "strikeReady", "kind": "orbital"})


func _step_shells(g, dt: float) -> void:
	for s in shells:
		s.t += dt
		var k := minf(1.0, s.t / s.dur)
		s.x = lerpf(s.sx, s.tx, k)
		s.y = lerpf(s.sy, s.ty, k)
		if k >= 1.0:
			_area(g, s.tx, s.ty, s.r, s.dmg, true, true, "howitzer")
			g.events.append({"t": "shellHit", "x": s.tx, "y": s.ty, "r": s.r, "id": s.id})
			if s.cluster:
				for j in 5:
					var a := j * TAU / 5.0
					var bx: float = s.tx + cos(a) * 2.6
					var by: float = s.ty + sin(a) * 2.6
					_area(g, bx, by, 1.4, s.dmg * 0.3, true, true, "howitzer")
					g.events.append({"t": "explode", "x": bx, "y": by, "r": 1.4, "color": "gold"})
	shells = shells.filter(func(s): return s.t < s.dur)


func _step_blasts(g) -> void:
	var keep: Array = []
	for b in blasts:
		if b.kind == "ring":
			if t < b.start:
				keep.append(b)
				continue
			var k := minf(1.0, (t - b.start) / b.dur)
			var r: float = lerpf(b.r, b.r1, k)
			for e: SimEnemy in g.enemies:
				if e.alive and not b.hit.has(e.id):
					var d := Vector2(e.x - b.x, e.y - b.y).length()
					if d <= r + e.radius and d >= b.r - 0.5:
						b.hit[e.id] = true
						g.damage(e, b.dmg, null, {"area": true, "ignoreShield": true, "src": "orbital"})
			if k < 1.0:
				keep.append(b)
			continue
		if t < b.at:
			keep.append(b)
			continue
		_area(g, b.x, b.y, b.r, b.dmg, false, true, b.kind)
		g.events.append({"t": "blast", "x": b.x, "y": b.y, "r": b.r, "kind": b.kind})
	blasts = keep


func _area(g, x: float, y: float, r: float, dmg: float, ground_only: bool, air_ok: bool = true, src: String = "") -> int:
	var n := 0
	for e: SimEnemy in g.enemies:
		if not e.alive:
			continue
		if ground_only and e.airborne and not air_ok:
			continue
		if Vector2(e.x - x, e.y - y).length() <= r + e.radius:
			g.damage(e, dmg, null, {"area": true, "splash": true, "src": src})
			n += 1
	return n


func _step_traps(g, dt: float, unit: float) -> void:
	var gone: Array = []
	for tr in traps:
		var cx: float = tr.x
		var cy: float = tr.y
		match tr.kind:
			"landmine":
				for e: SimEnemy in g.enemies:
					if e.alive and not e.airborne and not e.overland and Vector2(e.x - cx, e.y - cy).length() < 0.7 + e.radius * 0.5:
						_area(g, cx, cy, Bal.TRAP.landmineR, Bal.TRAP.landmineUnits * unit, false, true, "landmine")
						g.events.append({"t": "trap", "kind": "landmine", "x": cx, "y": cy, "r": Bal.TRAP.landmineR})
						gone.append(tr)
						break
			"betty":
				for e: SimEnemy in g.enemies:
					if e.alive and not e.overland and Vector2(e.x - cx, e.y - cy).length() < 1.0 + e.radius * 0.5:
						_area(g, cx, cy, Bal.TRAP.bettyR, Bal.TRAP.bettyUnits * unit, false, true, "betty")
						g.events.append({"t": "trap", "kind": "betty", "x": cx, "y": cy, "r": Bal.TRAP.bettyR})
						gone.append(tr)
						break
			"claymore":
				for e: SimEnemy in g.enemies:
					if e.alive and not e.overland and Vector2(e.x - cx, e.y - cy).length() < 0.8 + e.radius * 0.5:
						var dir: float = tr.dir
						for o: SimEnemy in g.enemies:
							if not o.alive:
								continue
							var dx := o.x - cx
							var dy := o.y - cy
							var dist := sqrt(dx * dx + dy * dy)
							if dist > Bal.TRAP.claymoreLen + o.radius:
								continue
							var diff := absf(wrapf(atan2(dy, dx) - dir, -PI, PI))
							if dist < 1.2 or diff < 0.6:
								g.damage(o, Bal.TRAP.claymoreUnits * unit, null, {"area": true, "src": "claymore"})
						g.events.append({"t": "trap", "kind": "claymore", "x": cx, "y": cy, "dir": tr.dir, "r": Bal.TRAP.claymoreLen})
						gone.append(tr)
						break
			"spike":
				for e: SimEnemy in g.enemies:
					if not e.alive or e.airborne or e.overland or tr.hit_ids.has(e.id):
						continue
					if _inside(tr.cells, e.x, e.y):
						tr.hit_ids[e.id] = true
						g.damage(e, Bal.TRAP.spikeUnits * unit, null, {"single": true, "src": "spike"})
						g._add_dot(e, {"kind": "bleed", "dps": 0.25 * unit, "t": 2.0, "tower": 0})
						tr.hits -= 1
						g.events.append({"t": "trap", "kind": "spike", "x": e.x, "y": e.y, "id": tr.id})
						if tr.hits <= 0:
							gone.append(tr)
							break
			"tar":
				if tr.burn > 0.0:
					tr.burn -= dt
				for e: SimEnemy in g.enemies:
					if not e.alive or e.airborne or e.overland or not _inside(tr.cells, e.x, e.y):
						continue
					g._slow(e, Bal.TRAP.tarSlow, 0.25)
					e.tarred = 0.3
					if tr.burn > 0.0:
						g.damage(e, 2.0 * unit * dt, null, {"dot": true, "area": true, "src": "tar"})
					elif tr.burn > -5.0:
						for dd in e.dots:
							if dd.kind == "burn":
								tr.burn = 3.0
								g.events.append({"t": "trap", "kind": "tarFire", "x": tr.x, "y": tr.y, "id": tr.id})
								break
	for tr in gone:
		_remove_trap(tr)


func _remove_trap(tr: Dictionary) -> void:
	traps.erase(tr)
	for c in tr.cells:
		trap_at.erase(Board.cell_idx(c.x, c.y))


static func _inside(cells: Array, x: float, y: float) -> bool:
	var c := Vector2i(floori(x), floori(y))
	return cells.has(c)


func _step_metronomes(g, dt: float, unit: float) -> void:
	assist_t += dt
	var assist: bool = g.metronome_assist and assist_t >= 8.0
	if assist:
		assist_t = 0.0
	var rr: float = Bal.METRONOME.radius
	for m in metronomes:
		if assist:
			m.amp = minf(maxf(1.0, m.amp), m.amp + Bal.METRONOME.shove * 0.5)
		if m.amp < Bal.METRONOME.stop:
			m.amp = 0.0
			continue
		m.tick_t += dt
		if m.tick_t < Bal.METRONOME.tick:
			continue
		m.tick_t -= Bal.METRONOME.tick
		m.side = -m.side
		m.ticks += 1
		var a: float = m.amp
		for e: SimEnemy in g.enemies:
			if not e.alive or Vector2(e.x - m.x, e.y - m.y).length() > rr + e.radius:
				continue
			match m.kind:
				"decay":
					var found := false
					for dd in e.dots:
						if dd.kind == "rot":
							dd.stacks = mini(int(Bal.METRONOME.rotStacks), int(dd.stacks) + 1)
							dd.dps = Bal.METRONOME.rotFrac * unit * a * dd.stacks
							dd.t = Bal.METRONOME.rotT
							found = true
					if not found:
						e.dots.append({"kind": "rot", "dps": Bal.METRONOME.rotFrac * unit * a, "t": Bal.METRONOME.rotT, "tower": 0, "stacks": 1})
				"thunder":
					g.damage(e, Bal.METRONOME.thunderUnits * unit * a, null, {"area": true, "src": "metronome_thunder"})
				"molasses":
					g._slow(e, 1.0 - (1.0 - Bal.METRONOME.molasses) * a, Bal.METRONOME.molassesT)
				"unmaking":
					e.shield *= 1.0 - Bal.METRONOME.unmakeShield * a
					e.unmade_t = 3.0
					e.immune = false
		m.amp *= 1.0 - (1.0 - Bal.METRONOME.decay) * maxf(0.2, 1.0 - 0.15 * g.cards.f("clockwork"))
		g.events.append({"t": "tick", "id": m.id, "x": m.x, "y": m.y, "kind": m.kind, "amp": a, "side": m.side})


func _step_rams(g, dt: float, unit: float) -> void:
	for r in rams:
		if r.retool > 0.0:
			r.retool -= dt
		r.cd -= dt
		if r.cd > 0.0 or r.retool > 0.0:
			continue
		# a target within reach of road upstream of the launch point, on any route near the ram
		var best: SimEnemy = null
		var best_s := -INF
		var best_route: Route = null
		var best_d := 0.0
		for rt: Route in g.board.routes:
			var hit := _nearest_on(rt, r.x, r.y)
			if hit.x > 3.2:
				continue
			for e: SimEnemy in g.enemies:
				if not e.alive or e.route != rt or e.overland:
					continue
				if e.d > hit.y or e.d < hit.y - Bal.RAM.reach:
					continue
				var sc: float = g.priority_score(r.priority, e, r.x, r.y)
				if sc > best_s:
					best_s = sc
					best = e
					best_route = rt
					best_d = hit.y
		if best == null:
			continue
		r.cd = Bal.RAM.impactReload if r.variant == "impact" else Bal.RAM.grinderReload
		var p0 := best_route.at(best_d)
		r.angle = atan2(p0.y - r.y, p0.x - r.x)
		var rid: int = g.next_id
		g.next_id += 1
		rockets.append({"id": rid, "variant": r.variant, "route": best_route, "d": best_d, "x": p0.x, "y": p0.y, "px": r.x, "py": r.y, "travelled": 0.0, "hit": {}, "alive": true, "ram": r.id, "dir": p0.z + PI})
		g.events.append({"t": "ramFire", "id": r.id, "rocket": rid, "variant": r.variant, "x": r.x, "y": r.y})


func _step_rockets(g, dt: float, unit: float) -> void:
	for k in rockets:
		k.px = k.x
		k.py = k.y
		var step_len: float = Bal.RAM.speed * dt
		k.d -= step_len
		k.travelled += step_len
		var p: Vector3 = k.route.at(k.d)
		k.x = p.x
		k.y = p.y
		k.dir = p.z + PI
		if k.variant == "impact":
			for e: SimEnemy in g.enemies:
				if e.alive and not e.overland and Vector2(e.x - k.x, e.y - k.y).length() < 0.6 + e.radius:
					_area(g, k.x, k.y, Bal.RAM.impactR, Bal.RAM.impactUnits * unit, false, true, "ram_impact")
					g.events.append({"t": "ramHit", "x": k.x, "y": k.y, "r": Bal.RAM.impactR, "id": k.id})
					k.alive = false
					break
		else:
			for e: SimEnemy in g.enemies:
				if e.alive and not k.hit.has(e.id) and Vector2(e.x - k.x, e.y - k.y).length() < 0.7 + e.radius:
					k.hit[e.id] = true
					g.damage(e, Bal.RAM.grinderUnits * unit, null, {"single": true, "src": "ram_grinder"})
					g.events.append({"t": "impact", "x": e.x, "y": e.y, "color": "gold"})
		if k.alive and (k.travelled >= Bal.RAM.reach or k.d <= 0.0):
			k.alive = false
			g.events.append({"t": "ramHit", "x": k.x, "y": k.y, "r": 1.0, "id": k.id, "fizzle": true})
	rockets = rockets.filter(func(k): return k.alive)


## Called at the start of a new board: tar pits last the board; rockets and shells clear.
func next_board() -> void:
	var gone: Array = []
	for tr in traps:
		if tr.kind == "tar":
			gone.append(tr)
	for tr in gone:
		_remove_trap(tr)
	rockets.clear()
	shells.clear()
	blasts.clear()


func wave_end() -> void:
	rockets.clear()
	for tr in traps:
		tr.hit_ids = {}


# ---------------------------------------------------------------- save
func serialize() -> Dictionary:
	var tr: Array = []
	for x in traps:
		var c: Dictionary = x.duplicate(true)
		c.hit_ids = {}
		tr.append(c)
	var pd: Array = []
	for p in pads:
		pd.append(p.duplicate(true))
	return {"belt": belt.duplicate(), "traps": tr, "metronomes": metronomes.duplicate(true), "rams": rams.duplicate(true), "pads": pd}


func load_data(d: Dictionary) -> void:
	if d.is_empty():
		return
	belt = d.belt.duplicate()
	traps = d.traps.duplicate(true)
	metronomes = d.metronomes.duplicate(true)
	rams = d.rams.duplicate(true)
	pads = d.pads.duplicate(true)
	trap_at.clear()
	off_at.clear()
	for x in traps:
		x.cells = _cells(x.cells)
		for c in x.cells:
			trap_at[Board.cell_idx(c.x, c.y)] = x.id
	for l in [metronomes, rams]:
		for x in l:
			x.cells = _cells(x.cells)
			for c in x.cells:
				off_at[Board.cell_idx(c.x, c.y)] = x.id


static func _cells(a: Array) -> Array:
	var out: Array = []
	for c in a:
		if c is Vector2i:
			out.append(c)
		elif c is Dictionary:
			out.append(Vector2i(int(c.x), int(c.y)))
		else:
			out.append(Vector2i(int(c[0]), int(c[1])))
	return out
