class_name Deploy
extends RefCounted
## Deployment rounds (section 11): supply crates, units on the road, their orders, and the
## damage report that shows which defences did the work and where monsters got through.

const INTERVAL := 0.5

var pool: Array = []  ## unit kinds waiting to be deployed (crate, hangar and garrison)
var units: Array = []  ## {id, kind, x, y, px, py, hp, max, order, priority, cd, alive, life, route, d, dir, blocking, sandbag, moving}
var report: Dictionary = {}  ## source key -> {name, dmg, kills, over}
var leaks: Array = []  ## {x, y, ingress, town}
var report_wave := 0
var last_crate: Array = []
var returned: Array = []  ## kinds of units that came home during the wave (drones)


static func unit_def(kind: String) -> Dictionary:
	return Bal.UNITS[kind]


func capacity(g) -> int:
	return Bal.HANGAR + g.towns.total_housing()


## The board's unit HP (from the running wave, or the next one between waves).
static func unit_hp(g) -> float:
	if not g.wave.is_empty():
		return float(g.wave.unitHp)
	var nw: Dictionary = g.next_wave_preview()
	return float(nw.get("unitHp", 50.0)) if not nw.is_empty() else 50.0


func is_deploy_wave(board_no: int, wave_no: int) -> bool:
	return Bal.DEPLOY_WAVES[board_no - 1].has(wave_no)


# ---------------------------------------------------------------- crates
## A supply crate parachutes onto the base at the start of a deployment wave.
func open_crate(g) -> Array:
	var rng := Rng.new(Rng.sub_seed(g.seed, [611, g.board_no, g.wave_index, g.attempt]))
	var pts: int = Bal.DEPLOY_POINTS[g.board_no - 1]
	if g.has_building("commandPost"):
		pts += int(Bal.COMMAND_POST.points)
	var got: Array = []
	if pts >= 3 and rng.chance(Bal.COMMANDO_CHANCE):
		got.append("commando")
		pts -= 3
	var bag := ["drones", "rifles", "rifles", "tank", "engineer"]
	while pts > 0:
		var opts := bag.filter(func(k): return int(Bal.UNITS[k].points) <= pts)
		var k: String = rng.pick(opts)
		got.append(k)
		pts -= int(Bal.UNITS[k].points)
	for _i in g.towns.count_district("barracks"):
		got.append("rifles")
	pool.append_array(got)
	last_crate = got
	g.events.append({"t": "crate", "units": got})
	return got


# ---------------------------------------------------------------- deploying
## Where a unit could stand: {ok, reason, x, y, route, d}.
func preview(g, kind: String, x: float, y: float) -> Dictionary:
	var def := unit_def(kind)
	var best := _nearest_route_point(g, x, y)
	if best.is_empty():
		return {"ok": false, "reason": "No road yet", "x": x, "y": y}
	if not def.fly and best.dist > 2.5:
		return {"ok": false, "reason": "Units stand on the road (or right beside it)", "x": x, "y": y}
	if g.board.is_core_cell(int(x), int(y)):
		return {"ok": false, "reason": "That is the core", "x": x, "y": y}
	var px: float = best.x if not def.fly else x
	var py: float = best.y if not def.fly else y
	return {"ok": true, "reason": "", "x": px, "y": py, "route": best.route, "d": best.d}


func _nearest_route_point(g, x: float, y: float) -> Dictionary:
	var best := {}
	for r in g.board.routes:
		var d := 0.0
		while d <= r.length:
			var p: Vector3 = r.at(d)
			var dist := Vector2(p.x - x, p.y - y).length()
			if best.is_empty() or dist < best.dist:
				best = {"route": r, "d": d, "x": p.x, "y": p.y, "dist": dist}
			d += 0.5
	return best


func deploy(g, pool_index: int, x: float, y: float, order: String = "hold") -> Dictionary:
	if pool_index < 0 or pool_index >= pool.size():
		return {"ok": false, "reason": "No unit"}
	var kind: String = pool[pool_index]
	var pv := preview(g, kind, x, y)
	if not pv.ok:
		g.events.append({"t": "reject", "reason": pv.reason})
		return pv
	pool.remove_at(pool_index)
	var u := _make(g, kind, pv.x, pv.y, pv.route, pv.d, order)
	g.events.append({"t": "unitDeployed", "id": u.id, "kind": kind, "x": u.x, "y": u.y})
	if kind == "engineer":
		var sb := _make(g, "sandbag", pv.x, pv.y, pv.route, maxf(0.0, pv.d - 1.0), "hold")
		var p: Vector3 = pv.route.at(sb.d)
		sb.x = p.x
		sb.y = p.y
		sb.px = p.x
		sb.py = p.y
		g.events.append({"t": "unitDeployed", "id": sb.id, "kind": "sandbag", "x": sb.x, "y": sb.y})
	return {"ok": true, "unit": u}


func _make(g, kind: String, x: float, y: float, route: Route, d: float, order: String) -> Dictionary:
	var def := unit_def(kind)
	var hp_mult: float = (1.0 + (float(Bal.COMMAND_POST.hp) if g.has_building("commandPost") else 0.0)) * (1.0 + 0.15 * g.cards.f("fieldpromo"))
	var mx: float = float(def.hp) * float(def.members) * unit_hp(g) * hp_mult
	var u := {"id": g.next_id, "kind": kind, "x": x, "y": y, "px": x, "py": y, "hp": mx, "max": mx, "order": order, "priority": "first",
		"cd": 0.3, "ability_cd": 2.0, "alive": true, "life": float(def.get("life", 0.0)), "route": route, "d": d, "dir": route.at(d).z + PI,
		"blocking": 0, "moving": false, "target": 0, "repair_t": 0.0}
	g.next_id += 1
	units.append(u)
	return u


func by_id(id: int) -> Dictionary:
	for u in units:
		if u.id == id:
			return u
	return {}


func set_order(id: int, order: String) -> void:
	var u := by_id(id)
	if not u.is_empty():
		u.order = order


func cycle_priority(id: int) -> String:
	var u := by_id(id)
	if u.is_empty():
		return ""
	var i: int = Bal.PRIORITIES.find(u.priority)
	u.priority = Bal.PRIORITIES[(i + 1) % Bal.PRIORITIES.size()]
	return u.priority


func members_alive(u: Dictionary) -> int:
	var def := unit_def(u.kind)
	if u.hp <= 0.0:
		return 0
	return clampi(ceili(u.hp / u.max * float(def.members)), 1, int(def.members))


static func rank_of(size: String) -> int:
	return int(Bal.UNIT_BLOCK_RANK.get(size, 9))


## How many enemies this unit can hold at once.
func block_cap(u: Dictionary) -> int:
	match u.kind:
		"rifles":
			return members_alive(u)
		"tank":
			return 3
		"sandbag":
			return 4
	return 0


## The unit that stops this enemy this tick (or {}), called from the enemy step.
func blocker_for(e: SimEnemy, nx: float, ny: float) -> Dictionary:
	if e.overland or e.airborne or e.boss or e.champion:
		return {}
	var er := rank_of(e.size)
	for u in units:
		if not u.alive or u.moving:
			continue
		var def := unit_def(u.kind)
		if def.block == "" or er > rank_of(def.block):
			continue
		if u.blocking >= block_cap(u):
			continue
		var dx: float = nx - u.x
		var dy: float = ny - u.y
		if dx * dx + dy * dy < 0.81:
			u.blocking += 1
			return u
	return {}


## The blocked enemy chews the unit like a barrier.
func chew(g, u: Dictionary, e: SimEnemy, dt: float) -> void:
	u.hp -= Bal.COMBAT.barrierChew * sqrt(Bal.SIZES[e.size].hp * e.tier) * unit_hp(g) * dt
	if u.hp <= 0.0:
		_lose(g, u)


func _lose(g, u: Dictionary) -> void:
	if not u.alive:
		return
	u.alive = false
	u.hp = 0.0
	g.events.append({"t": "unitLost", "id": u.id, "kind": u.kind, "x": u.x, "y": u.y})


# ---------------------------------------------------------------- stepping
func step(g, dt: float) -> void:
	if units.is_empty():
		return
	var unit := unit_hp(g)
	for u in units:
		u.px = u.x
		u.py = u.y
	for u in units:
		if not u.alive:
			continue
		var def := unit_def(u.kind)
		if u.kind == "sandbag":
			continue
		if def.fly:
			_step_drones(g, u, def, dt, unit)
			continue
		var tgt := _pick(g, u, float(def.range))
		u.moving = false
		if u.order == "advance" and tgt == null and u.d > 0.5:
			u.d = maxf(0.0, u.d - float(def.speed) * dt)
			var p: Vector3 = u.route.at(u.d)
			u.x = p.x
			u.y = p.y
			u.dir = p.z + PI
			u.moving = true
			if u.kind == "tank":
				for e in g.enemies:
					if e.alive and e.size == "mite" and not e.overland and Vector2(e.x - u.x, e.y - u.y).length() < 0.9:
						g.damage(e, e.hp + e.shield + 1.0, null, {"src": "u%d" % u.id, "unit": true, "ignoreShield": true})
						g.events.append({"t": "crush", "x": e.x, "y": e.y})
		elif u.order == "advance" and tgt != null:
			u.order = "hold"
		match u.kind:
			"engineer":
				_step_engineer(g, u, def, dt, unit)
			"commando":
				_step_commando(g, u, def, dt)
		if tgt != null:
			u.dir = atan2(tgt.y - u.y, tgt.x - u.x)
		u.cd -= dt
		if u.cd > 0.0 or tgt == null or float(def.dps) <= 0.0:
			continue
		u.cd = INTERVAL
		var dmg: float = float(def.dps) * members_alive(u) * unit / 10.0 * INTERVAL * (1.0 + 0.15 * g.cards.f("fieldpromo"))
		g.events.append({"t": "shot", "towerId": -u.id, "kind": "unit_" + u.kind, "x1": u.x, "y1": u.y, "x2": tgt.x, "y2": tgt.y, "color": "gold"})
		if def.has("splash"):
			var r: float = def.splash
			for e in g.enemies.duplicate():
				if e.alive and not e.overland and Vector2(e.x - tgt.x, e.y - tgt.y).length() <= r + e.radius:
					g.damage(e, dmg, null, {"src": "u%d" % u.id, "unit": true, "area": true, "splash": true})
		else:
			g.damage(tgt, dmg, null, {"src": "u%d" % u.id, "unit": true, "single": true})
	for u in units:
		u.blocking = 0
	units = units.filter(func(x): return x.alive)


func _pick(g, u: Dictionary, r: float) -> SimEnemy:
	var def := unit_def(u.kind)
	var best: SimEnemy = null
	var best_s := -1.0
	for e in g.enemies:
		if not e.alive:
			continue
		if e.arch == "balloon" and not def.fly:
			continue
		if g.hidden_from(e, u.x, u.y):
			continue
		var dx: float = e.x - u.x
		var dy: float = e.y - u.y
		var rr: float = r + e.radius
		if dx * dx + dy * dy > rr * rr:
			continue
		var s: float = g.priority_score(u.priority, e, u.x, u.y)
		if s > best_s:
			best_s = s
			best = e
	return best


func _step_drones(g, u: Dictionary, def: Dictionary, dt: float, unit: float) -> void:
	u.life -= dt
	if u.life <= 0.0:
		u.alive = false
		returned.append(u.kind)
		g.events.append({"t": "unitHome", "id": u.id, "kind": u.kind, "x": u.x, "y": u.y})
		return
	var tgt := _pick(g, u, 14.0)
	if tgt == null:
		return
	var to := Vector2(tgt.x - u.x, tgt.y - u.y)
	var dist := to.length()
	if dist > 2.0:
		var step: float = minf(dist - 2.0, float(def.speed) * dt)
		u.x += to.x / dist * step
		u.y += to.y / dist * step
	u.dir = atan2(to.y, to.x)
	u.cd -= dt
	if u.cd <= 0.0 and dist <= float(def.range) + tgt.radius:
		u.cd = INTERVAL
		g._slow(tgt, float(def.slow), 0.6)
		var dmg: float = float(def.dps) * members_alive(u) * unit / 10.0 * INTERVAL * (1.0 + 0.15 * g.cards.f("fieldpromo"))
		g.events.append({"t": "shot", "towerId": -u.id, "kind": "unit_drones", "x1": u.x, "y1": u.y, "x2": tgt.x, "y2": tgt.y, "color": "blue"})
		g.damage(tgt, dmg, null, {"src": "u%d" % u.id, "unit": true, "single": true})


## Engineers repair barriers, towns and other units nearby, and re-arm spike traps.
func _step_engineer(g, u: Dictionary, def: Dictionary, dt: float, unit: float) -> void:
	u.repair_t -= dt
	if u.repair_t > 0.0:
		return
	u.repair_t = 1.0
	var amount: float = float(def.repair) * unit
	var r: float = def.range
	var did := false
	for rp in g.road_pieces:
		if rp.kind == "barrier" and rp.maxHp > 0.0 and rp.hp < rp.maxHp:
			var c: Vector2i = rp.cells[0]
			if Vector2(c.x + 1 - u.x, c.y + 1 - u.y).length() <= r:
				rp.hp = minf(rp.maxHp, rp.hp + amount)
				did = true
	for t in g.towns.list:
		if not t.fallen and t.hp < g.towns.max_hp(t) and Vector2(t.x - u.x, t.y - u.y).length() <= r + 4.0:
			t.hp = minf(g.towns.max_hp(t), t.hp + amount / unit)
			did = true
	for o in units:
		if o != u and o.alive and o.blocking == 0 and o.hp < o.max and Vector2(o.x - u.x, o.y - u.y).length() <= r:
			o.hp = minf(o.max, o.hp + amount)
			did = true
	for tr in g.arsenal.traps:
		if tr.kind == "spike" and tr.hits < int(Bal.TRAP.spikeHits) and Vector2(tr.x - u.x, tr.y - u.y).length() <= r:
			tr.hits = mini(int(Bal.TRAP.spikeHits), tr.hits + 2)
			did = true
	if did:
		g.events.append({"t": "repair", "x": u.x, "y": u.y})


## Commandos neutralise: finish a weakened non-boss enemy, or switch off a special for 8 s.
func _step_commando(g, u: Dictionary, def: Dictionary, dt: float) -> void:
	u.ability_cd -= dt
	if u.ability_cd > 0.0:
		return
	var r: float = def.range
	var best: SimEnemy = null
	var quiet: SimEnemy = null
	for e in g.enemies:
		if not e.alive or e.boss or e.champion or g.hidden_from(e, u.x, u.y):
			continue
		if Vector2(e.x - u.x, e.y - u.y).length() > r + e.radius:
			continue
		if e.hp <= e.max_hp * float(def.execute):
			if best == null or e.hp > best.hp:
				best = e
		elif (e.special != "" or e.ability != "") and e.unmade_t <= 0.0 and quiet == null:
			quiet = e
	if best != null:
		u.ability_cd = def.every
		g.events.append({"t": "execute", "x": best.x, "y": best.y, "x1": u.x, "y1": u.y})
		g.damage(best, best.hp + best.shield + 1.0, null, {"src": "u%d" % u.id, "unit": true, "ignoreShield": true})
	elif quiet != null:
		u.ability_cd = def.every
		quiet.unmade_t = maxf(quiet.unmade_t, float(def.disable))
		g.events.append({"t": "neutralise", "x": quiet.x, "y": quiet.y, "x1": u.x, "y1": u.y})


# ---------------------------------------------------------------- wave and board end
## Surviving units return to the pool (garrison or hangar).
func wave_end(g) -> void:
	for u in units:
		if u.kind != "sandbag" and u.alive:
			pool.append(u.kind)
	pool.append_array(returned)
	returned.clear()
	units.clear()


## At the end of a board units without housing disband with a salute.
func board_end(g) -> void:
	var cap := capacity(g)
	if pool.size() > cap:
		var gone := pool.size() - cap
		pool.resize(cap)
		g.events.append({"t": "salute", "n": gone})


## A fallen town loses the units it housed.
func town_fell(g, _town_id: int) -> void:
	var cap := capacity(g)
	if pool.size() > cap:
		var lost := pool.size() - cap
		pool.resize(cap)
		g.events.append({"t": "garrisonLost", "n": lost})


# ---------------------------------------------------------------- damage report
func reset_report(wave_no: int) -> void:
	report = {}
	leaks = []
	report_wave = wave_no


func record(key: String, name: String, dmg: float, over: float, killed: bool) -> void:
	var r: Dictionary = report.get(key, {})
	if r.is_empty():
		r = {"name": name, "dmg": 0.0, "kills": 0, "over": 0.0}
		report[key] = r
	r.dmg += dmg
	r.over += over
	if killed:
		r.kills += 1


func record_leak(e: SimEnemy) -> void:
	leaks.append({"x": e.x, "y": e.y, "ingress": e.route.ingress, "town": e.route.town_id, "size": e.size})


## Sorted rows for the report panel: [{key, name, dmg, kills, over, share}].
func report_rows() -> Array:
	var tot := 0.0
	for k in report:
		tot += report[k].dmg
	var rows: Array = []
	for k in report:
		var r: Dictionary = report[k].duplicate()
		r["key"] = k
		r["share"] = r.dmg / tot if tot > 0.0 else 0.0
		rows.append(r)
	rows.sort_custom(func(a, b): return a.dmg > b.dmg)
	return rows


func unit_name(kind: String) -> String:
	return Bal.UNITS[kind].name


# ---------------------------------------------------------------- save
func serialize() -> Dictionary:
	return {"pool": pool.duplicate()}


func load_data(d: Dictionary) -> void:
	pool = d.get("pool", []).duplicate()
	units.clear()
