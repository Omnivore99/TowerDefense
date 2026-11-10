class_name Bot
extends RefCounted
## Headless bot players for the balance harness (ported from v1.1 bots.ts, extended for v2.0).

const SKILLS := {
	"novice": {"waste": 0.25, "colour": 0.0, "stack": 0.0, "spot": "random", "maxMass": 4, "holes": true},
	"average": {"waste": 0.1, "colour": 0.45, "stack": 0.1, "spot": "decent", "maxMass": 6, "holes": false},
	"expert": {"waste": 0.0, "colour": 0.7, "stack": 0.3, "spot": "spiral", "maxMass": 8, "holes": false},
}
const WEAK := {"hearts": "green", "clubs": "red", "diamonds": "blue", "spades": "gold"}
const BUILD_PRIORITY: Array[String] = ["lance", "armory", "blastDoor", "beacon", "powerStation", "harvesterHub", "missileBattery", "research", "recycler", "factory", "shapeFactory"]

var game: Game
var skill: String
var strategy: String
var rng: Rng
var spots: Array = []
var spots_for := -1
var cooldown := 0
var orients: Array = []


func _init(g: Game, skill_id: String, seed_value: int, strategy_id: String = "standard") -> void:
	game = g
	skill = skill_id
	strategy = strategy_id
	rng = Rng.new(seed_value)
	for rot in 4:
		orients.append({"rot": rot, "mirror": false})
		orients.append({"rot": rot, "mirror": true})


## Call once per sim step.
func act() -> void:
	var g := game
	if g.phase == "reveal":
		return
	if g.phase == "cleared":
		g.enter_base()
		return
	if g.phase == "base":
		_shop()
		g.next_board()
		return
	if g.phase != "calm" and g.phase != "wave":
		return
	if spots_for != g.board_no * 1000 + g.attempt:
		_find_spots()
	cooldown -= 1
	if cooldown > 0:
		return
	cooldown = 30 if skill == "novice" else 12
	_strike()
	_pop()
	_arsenal()
	var src := _next_source()
	if not src.is_empty():
		_place_one(src)
		return
	if g.phase == "calm":
		g.ready()


func _next_source() -> Dictionary:
	var g := game
	if not g.must.is_empty():
		return {"zone": "must", "index": 0}
	var i := -1
	for k in g.may.size():
		if g.may[k] != null:
			i = k
			break
	if i >= 0:
		return {"zone": "may", "index": i}
	if g.hold != null:
		return {"zone": "hold", "index": 0}
	return {}


# ------------------------------------------------------------ spot finding
func _find_spots() -> void:
	var g := game
	spots_for = g.board_no * 1000 + g.attempt
	var samples: Array = []
	for r in g.board.routes:
		var d := 0.0
		while d < r.length:
			var p := r.at(d)
			var late := d / r.length
			samples.append(Vector3(p.x, p.y, 0.6 + late if skill == "expert" else 1.0))
			d += 2.0
	var out: Array = []
	var y := 2
	while y < Bal.GRID_H - 2:
		var x := 2
		while x < Bal.GRID_W - 2:
			var i := Board.cell_idx(x, y)
			if g.board.is_road(x, y) or g.board.is_core_cell(x, y) or g.board.ore[i] != 0 or g.board.is_blocked_terrain(i):
				x += 3
				continue
			var near := false
			for dy in range(-2, 3):
				for dx in range(-2, 3):
					if Board.in_grid(x + dx, y + dy) and g.board.is_road(x + dx, y + dy):
						near = true
			if near:
				x += 3
				continue
			var score := 0.0
			for s in samples:
				if (s.x - x) * (s.x - x) + (s.y - y) * (s.y - y) < 196.0:
					score += s.z
			score += maxi(0, g.board.h(x, y)) * 2
			if score > 0.0:
				out.append({"x": x, "y": y, "score": score})
			x += 3
		y += 3
	out.sort_custom(func(a, b): return a.score > b.score)
	spots = out


func _pick_spot() -> Dictionary:
	var g := game
	var free: Array = []
	for s in spots:
		if g.obj_at[Board.cell_idx(s.x, s.y)] != 0:
			continue
		var taken := false
		for t in g.towers:
			if Vector2(t.cx - s.x, t.cy - s.y).length() < 6.0:
				taken = true
				break
		if not taken:
			free.append(s)
	if free.is_empty():
		return {}
	if skill == "novice":
		return rng.pick(free)
	if skill == "average":
		return rng.pick(free.slice(0, maxi(1, ceili(free.size() * 0.25))))
	return free[mini(free.size() - 1, rng.int_range(0, 2))]


# ------------------------------------------------------------ placement
func _place_one(src: Dictionary) -> void:
	var g := game
	var piece: Dictionary = g.get_piece(src)
	var cfg: Dictionary = SKILLS[skill]
	if rng.chance(cfg.waste):
		g.discard(src)
		return
	if skill != "novice" and (Pieces.is_cap(piece.kind) or rng.chance(0.5)) and _harvest_wanted(src, piece):
		return
	var towers: Array[SimTower] = []
	for t in g.towers:
		if not t.base_tower:
			towers.append(t)
	if rng.chance(cfg.stack) or (Pieces.is_cap(piece.kind) and cfg.stack > 0.0):
		var ts: Array = towers.filter(func(t): return t.active)
		ts.sort_custom(func(a, b): return a.stats.get("dps", 0.0) > b.stats.get("dps", 0.0))
		for t in ts:
			var pv := _best_on(t, piece, "story")
			if not pv.is_empty() and _commit(src, pv):
				return
	for t in towers:
		if t.type == "":
			var pv2 := _best_on(t, piece, "tower")
			if not pv2.is_empty() and _commit(src, pv2):
				return
	if Pieces.is_cap(piece.kind) and _harvest(src, piece):
		return
	var mass_targets: Array = towers.filter(func(t): return t.active and t.ground_count() < cfg.maxMass)
	var want_colour: bool = rng.chance(cfg.colour) and piece.color == WEAK[g.dominant()]
	if not mass_targets.is_empty() and (rng.chance(0.45) or want_colour):
		mass_targets.sort_custom(func(a, b):
			var ca := -10 if (want_colour and a.stats.get("color", "") == piece.color) else 0
			var cb := -10 if (want_colour and b.stats.get("color", "") == piece.color) else 0
			if ca != cb:
				return ca < cb
			return a.stats.get("dps", 0.0) > b.stats.get("dps", 0.0))
		for t in mass_targets.slice(0, 4):
			var pv3 := _best_on(t, piece, "tower")
			if not pv3.is_empty() and _commit(src, pv3):
				return
	for _tries in 6:
		var spot := _pick_spot()
		if spot.is_empty():
			break
		for o in orients:
			var pv4 := g.preview(piece, o.rot, o.mirror, spot.x, spot.y)
			if pv4.ok and pv4.kind == "tower" and pv4.get("towerId", 0) == 0:
				if g.place(src, o.rot, o.mirror, spot.x, spot.y).ok:
					return
		spots.erase(spot)
	if _harvest(src, piece):
		return
	for t in mass_targets:
		var pv5 := _best_on(t, piece, "tower")
		if not pv5.is_empty() and _commit(src, pv5):
			return
	g.discard(src)


## Pop pimples with the Lance: experts wait for ripeness, average bots pop anything worth
## at least 60%, novices never pop.
func _pop() -> void:
	var g := game
	if skill == "novice" or g.eco.charges() <= 0:
		return
	var min_frac := 0.99 if skill == "expert" else 0.6
	for p in g.eco.pimples:
		var st: String = g.eco.stage(p)
		var last_chance: bool = st == "turning"
		if g.eco.value_frac(p) >= min_frac or (last_chance and skill == "expert"):
			g.pop_pimple(p.id)
			return


func _harvest(src: Dictionary, piece: Dictionary) -> bool:
	var g := game
	# forests and lake shores first when we have few of those structures
	var have := {"ore": 0, "forest": 0, "lake": 0}
	for h in g.harvesters:
		have[h.get("node", "ore")] += 1
	var targets: Array[Vector2i] = []
	if have.forest <= have.lake:
		for f in g.eco.forests:
			if not f.cells.is_empty():
				targets.append(Vector2i(f.cells[f.cells.size() / 2] % Bal.GRID_W, f.cells[f.cells.size() / 2] / Bal.GRID_W))
	for l in g.eco.lakes:
		if l.units > 0.0 and not l.cells.is_empty():
			var c: int = l.cells[0]
			targets.append(Vector2i(c % Bal.GRID_W, c / Bal.GRID_W - 1))
	if have.forest > have.lake:
		for f in g.eco.forests:
			if not f.cells.is_empty():
				targets.append(Vector2i(f.cells[0] % Bal.GRID_W, f.cells[0] / Bal.GRID_W))
	if have.ore >= 2:
		for tc in targets:
			for o in orients:
				for d in [Vector2i(0, 0), Vector2i(-1, 0), Vector2i(0, -1), Vector2i(1, 0)]:
					var pv := g.preview(piece, o.rot, o.mirror, tc.x + d.x, tc.y + d.y)
					if pv.ok and pv.kind == "harvester":
						if g.place(src, o.rot, o.mirror, tc.x + d.x, tc.y + d.y).ok:
							return true
	for v in g.board.veins:
		for o in orients:
			for dy in 3:
				for dx in 3:
					var pv := g.preview(piece, o.rot, o.mirror, v.x + dx, v.y + dy)
					if pv.ok and pv.kind == "harvester":
						if g.place(src, o.rot, o.mirror, v.x + dx, v.y + dy).ok:
							return true
	return false


## Keep a target number of mines, lumber camps and pumps (v2 economy): returns true if placed.
func _harvest_wanted(src: Dictionary, piece: Dictionary) -> bool:
	var g := game
	var have := {"ore": 0, "forest": 0, "lake": 0}
	for h in g.harvesters:
		have[h.get("node", "ore")] += 1
	var b := g.board_no
	var want := {"ore": 2 + b / 2, "forest": 1 + b / 2, "lake": (b + 1) / 3}
	var node := ""
	for k in ["forest", "ore", "lake"]:
		if have[k] < want[k]:
			node = k
			break
	if node == "":
		return false
	var cand: Array[Vector2i] = []
	match node:
		"ore":
			cand.assign(g.board.veins)
		"forest":
			for f in g.eco.forests:
				for c in f.cells:
					if g.eco.tree[c] == 1:
						cand.append(Vector2i(c % Bal.GRID_W, c / Bal.GRID_W))
		"lake":
			for l in g.eco.lakes:
				if l.units <= 0.0:
					continue
				for c in l.cells:
					var v := Vector2i(c % Bal.GRID_W, c / Bal.GRID_W)
					for d in Game.DIRS4:
						var n: Vector2i = v + d
						if Board.in_grid(n.x, n.y) and g.eco.water[Board.cell_idx(n.x, n.y)] == 0:
							cand.append(n)
	if cand.is_empty():
		return false
	# nearest to the core first (safer, shorter view distance), a few tries
	cand.sort_custom(func(a, z): return Vector2(a).distance_squared_to(Board.CORE_PT) < Vector2(z).distance_squared_to(Board.CORE_PT))
	for tc in cand.slice(0, 24):
		for o in orients:
			var pv := g.preview(piece, o.rot, o.mirror, tc.x, tc.y)
			if pv.ok and pv.kind == "harvester" and pv.get("node", "") == node:
				if g.place(src, o.rot, o.mirror, tc.x, tc.y).ok:
					return true
	return false


## Best legal placement of a piece onto/next to a tower.
func _best_on(t: SimTower, piece: Dictionary, kind: String) -> Dictionary:
	var g := game
	var cfg: Dictionary = SKILLS[skill]
	var ground: Array = t.layers[0]
	var bb := Towers.bbox(ground)
	var x0 := bb.position.x - 4
	var x1 := bb.end.x + 4
	var y0 := bb.position.y - 4
	var y1 := bb.end.y + 4
	var best: Dictionary = {}
	var best_score := -INF
	var top: Array = t.layers[t.layers.size() - 1]
	var own := {}
	for c in ground:
		own[c] = true
	var top_set := {}
	for c in top:
		top_set[c] = true
	for o in orients:
		if piece.kind == "O" and (o.rot + (1 if o.mirror else 0)) > 0:
			continue
		for cy in range(y0, y1 + 1):
			for cx in range(x0, x1 + 1):
				var cells := Pieces.placed_cells(piece.kind, o.rot, o.mirror, cx, cy)
				if kind == "story":
					var all_own := true
					var any_top := false
					for c in cells:
						if not own.has(c):
							all_own = false
							break
						if top_set.has(c):
							any_top = true
					if not all_own or not any_top:
						continue
				else:
					var bad := false
					var touches := false
					for c in cells:
						if not Board.in_grid(c.x, c.y) or own.has(c):
							bad = true
							break
						if own.has(c + Vector2i(1, 0)) or own.has(c + Vector2i(-1, 0)) or own.has(c + Vector2i(0, 1)) or own.has(c + Vector2i(0, -1)):
							touches = true
					if bad or not touches:
						continue
				var pv := g.preview(piece, o.rot, o.mirror, cx, cy)
				if not pv.ok or pv.kind != kind or pv.get("towerId", 0) != t.id or not pv.get("mergeIds", []).is_empty():
					continue
				if not cfg.holes and not pv.holes.is_empty():
					continue
				var score: float = pv.get("dps", 0.0) + pv.gained.size() * 3 - pv.lost.size() * 3
				if skill == "novice":
					score = rng.next()
				if score > best_score:
					best_score = score
					best = pv
					best.o = o
					best.cx = cx
					best.cy = cy
	return best


func _commit(src: Dictionary, pv: Dictionary) -> bool:
	return game.place(src, pv.o.rot, pv.o.mirror, pv.cx, pv.cy).ok


## Orbital and air strikes on the densest pack.
func _strike() -> void:
	var g := game
	var orb := g.can_orbital()
	var air := g.can_airstrike()
	if not orb and not air:
		return
	var best := {}
	for e in g.enemies:
		var n := 0
		for o in g.enemies:
			if Vector2(o.x - e.x, o.y - e.y).length() < 5.0:
				n += 1
		if best.is_empty() or n > best.n:
			best = {"x": e.x, "y": e.y, "n": n, "dir": e.dir}
	if best.is_empty() or best.n < (4 if skill == "expert" else 6):
		return
	if orb:
		g.orbital(best.x, best.y)
	elif air:
		g.airstrike(best.x, best.y, best.dir)


## Technology, evolutions and kits (average and expert only).
func _arsenal() -> void:
	var g := game
	if skill == "novice":
		return
	if g.base.freeTech:
		g.open_tech(_wanted_tech())
	var reserve := 0.0 if skill == "expert" else 8.0
	# evolve the strongest towers first
	var ts: Array = g.towers.filter(func(t): return t.type != "" and t.mark < 4)
	ts.sort_custom(func(a, b): return a.stats.dps * a.ground_count() > b.stats.dps * b.ground_count())
	for t in ts.slice(0, 4):
		var br: int = t.branch
		if t.mark == 2:
			br = _branch_for(t)
			if br < 0:
				continue
		if g.evolve_blocked(t.id, br) == "" and g.base.ore >= reserve:
			g.evolve(t.id, br)
			return
	# open a second technology when rich
	if skill == "expert" and g.base.essence > 40.0:
		for k in Bal.TECHS:
			if g.tech_level(k) == 0:
				g.open_tech(k)
				break
	# kits: howitzers on the ring, landmines near the core
	for id in ["orbital", "airstrike", "howitzer"]:
		if g.arsenal.kit_blocked(g, id) == "":
			g.buy_kit(id)
			return
	if g.base.ore > 8.0 and g.arsenal.traps.size() < 2 * g.board_no and g.arsenal.belt.find("") >= 0 and g.arsenal.kit_blocked(g, "landmine") == "":
		g.buy_kit("landmine")
	var slot: int = g.arsenal.belt.find("landmine")
	if slot >= 0 and not g.board.routes.is_empty():
		var r: Route = rng.pick(g.board.routes)
		var p := r.at(r.length * rng.range_f(0.55, 0.85))
		g.place_kit(slot, 0, floori(p.x), floori(p.y))


func _branch_for(t: SimTower) -> int:
	var bs := Evolve.branches(t.type)
	var best := -1
	var best_lv := 0
	for i in bs.size():
		var lv := game.tech_level(bs[i].tech)
		if lv > best_lv:
			best_lv = lv
			best = i
	return best


## The technology most of the current towers can branch into.
func _wanted_tech() -> String:
	var votes := {"steam": 0.0, "aether": 0.0, "alchemy": 0.0}
	for t in game.towers:
		for b in Evolve.branches(t.type):
			votes[b.tech] += t.stats.get("dps", 1.0)
	var best := "steam"
	for k in votes:
		if votes[k] > votes[best]:
			best = k
	return best


func _shop() -> void:
	var g := game
	g.convert_ore(0.0 if skill == "novice" else 21.0)
	while true:
		var bought := false
		for id in BUILD_PRIORITY:
			var best_sq := -1
			var best_diff := 999
			for i in Bal.BASE_SQUARES.size():
				if g.can_build(i, id) != "":
					continue
				var diff := absi(Bal.BASE_SQUARES[i].size - Bal.BUILDINGS[id].size)
				if diff < best_diff:
					best_diff = diff
					best_sq = i
			if best_sq < 0:
				continue
			if skill != "novice" and Bal.BASE_SQUARES[best_sq].size > Bal.BUILDINGS[id].size * 2 and g.board_no < 5:
				continue
			if g.build(best_sq, id) == "":
				bought = true
				break
		if not bought:
			break
