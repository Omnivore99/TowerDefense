class_name Economy
extends RefCounted
## v2.0 economy (sections 5.1, 6): forests, lakes, the harvest structures on them, pimples
## and the Resource Lance. Owned by Game; deterministic like the rest of the sim.
##
## Per-cell state lives in packed arrays indexed by Board.cell_idx:
##   tree:  0 none, 1 tree, 2 stump (buildable)
##   forest_of / lake_of: node id + 1 (0 = none)
##   water: 1 while the cell is lake water (blocks building), 2 mud flat (drying)

var g  # Game (untyped to avoid a cyclic class reference)
var tree := PackedByteArray()
var forest_of := PackedInt32Array()
var lake_of := PackedInt32Array()
var water := PackedByteArray()
var forests: Array = []  ## {id, cells: Array[int], max, regrow}
var lakes: Array = []  ## {id, cells: Array[int], units, max, dry_t}
var pimples: Array = []  ## {id, cell, harvester, node, M, T, age, pearl}
var craters: Array = []  ## {cell, cool} (cool = waves before it can sprout again)
var scorched: Array = []  ## {x, y, r, t} orbital scorch marks (cosmetic, stay for the run)
var version := 0  ## bumps whenever trees, water or pimples change (views rebuild)
var ground_version := 0  ## bumps when the ground itself changes (lakes drain or dry)
var pimple_income := 0.0
var other_income := 0.0


func _init(game) -> void:
	g = game
	var n := Bal.GRID_W * Bal.GRID_H
	tree.resize(n)
	forest_of.resize(n)
	lake_of.resize(n)
	water.resize(n)


func attach(board: Board) -> void:
	board.terrain_blocker = func(i: int) -> bool: return tree[i] == 1 or water[i] == 1
	board.on_new_road = func(p: Dictionary, near: Dictionary) -> void: _on_new_road(board, p, near)


# ---------------------------------------------------------------- queries
func is_forest(i: int) -> bool:
	return forest_of[i] != 0


func is_water(i: int) -> bool:
	return water[i] == 1


func blocked_reason(i: int) -> String:
	if tree[i] == 1:
		return "Trees: drop a piece here to make a lumber camp"
	if water[i] == 1:
		return "Water: build a pump on the shore"
	return "Blocked"


## Extra ground kind for the terrain view: 5 lake bed / mud, 6 forest floor, -1 = default.
func ground_kind(i: int) -> float:
	if water[i] != 0:
		return 5.0
	if forest_of[i] != 0:
		return 6.0
	return -1.0


func lance_level() -> int:
	return int(g.base.get("lanceLevel", 0)) if g.has_building("lance") else 0


func lance_charges_max() -> int:
	var lv := lance_level()
	return 0 if lv == 0 else Bal.LANCE.charges[lv - 1]


func pimple_cap() -> int:
	return Bal.PIMPLE.cap + (1 if lance_level() >= 3 else 0)


# ---------------------------------------------------------------- node placement
func _on_new_road(board: Board, p: Dictionary, near: Dictionary) -> void:
	# a road that crosses a forest or lake clears it
	for cell in near:
		_clear_cell(cell)
	var rng := Rng.new(Rng.sub_seed(g.seed, [313, p.board]))
	var nf: int = Bal.FOREST.perNewRoad + (1 if p.board == 1 else 0)
	for _k in nf:
		_place_node(board, rng, near, "forest")
	for _k in Bal.LAKE.perNewRoad:
		_place_node(board, rng, near, "lake")
	version += 1


func _clear_cell(i: int) -> void:
	tree[i] = 0
	if water[i] != 0:
		water[i] = 0
	forest_of[i] = 0
	lake_of[i] = 0


func _place_node(board: Board, rng: Rng, near: Dictionary, kind: String) -> void:
	var spec: Dictionary = Bal.FOREST if kind == "forest" else Bal.LAKE
	for _tries in 300:
		var w := rng.int_range(spec.side[0], spec.side[1])
		var h := rng.int_range(spec.side[0], spec.side[1])
		var x := rng.int_range(1, Bal.GRID_W - w - 1)
		var y := rng.int_range(1, Bal.GRID_H - h - 1)
		if Vector2(x + w / 2.0, y + h / 2.0).distance_to(Board.CORE_PT) < 12.0:
			continue
		var ok := true
		var near_road := false
		for dy in range(-2, h + 2):
			if not ok:
				break
			for dx in range(-2, w + 2):
				var cx := x + dx
				var cy := y + dy
				if not Board.in_grid(cx, cy):
					continue
				var i := Board.cell_idx(cx, cy)
				if board.road[i] == 1 or board.ore[i] != 0 or forest_of[i] != 0 or lake_of[i] != 0 or g.obj_at[i] != 0 or g.tower_at[i] != 0:
					ok = false
					break
		if not ok:
			continue
		for dy in range(-8, h + 8):
			if near_road:
				break
			for dx in range(-8, w + 8):
				if Board.in_grid(x + dx, y + dy) and near.has(Board.cell_idx(x + dx, y + dy)):
					near_road = true
					break
		if not near_road:
			continue
		# an organic blob inside the rectangle (corners trimmed by an ellipse test)
		var cells: Array[int] = []
		for dy in h:
			for dx in w:
				var ex := (dx + 0.5 - w / 2.0) / (w / 2.0)
				var ey := (dy + 0.5 - h / 2.0) / (h / 2.0)
				if ex * ex + ey * ey <= 1.05 + rng.range_f(-0.15, 0.1):
					cells.append(Board.cell_idx(x + dx, y + dy))
		if kind == "forest":
			var id := forests.size() + 1
			var n_trees := mini(cells.size(), rng.int_range(Bal.FOREST.trees[0], Bal.FOREST.trees[1]))
			var order := cells.duplicate()
			rng.shuffle(order)
			for c in cells:
				forest_of[c] = id
			for k in n_trees:
				tree[order[k]] = 1
			forests.append({"id": id, "cells": cells, "max": n_trees, "regrow": 0})
		else:
			var id2 := lakes.size() + 1
			# the lake sits in a basin one level below its surroundings
			var lvl: int = board.height[cells[0]] - 1
			for c in cells:
				lake_of[c] = id2
				water[c] = 1
				board.height[c] = lvl
			board.version += 1
			var units := float(rng.int_range(Bal.LAKE.units[0], Bal.LAKE.units[1]))
			lakes.append({"id": id2, "cells": cells, "units": units, "max": units, "dry_t": -1})
		return


# ---------------------------------------------------------------- harvest structures
## What dropping these cells would harvest: {} when nothing.
func preview_harvest(cells: Array) -> Dictionary:
	var ore_n := 0
	var forest_n := 0
	var shore_n := 0
	var on_water := false
	for c in cells:
		var i := Board.cell_idx(c.x, c.y)
		if g.board.ore[i] != 0:
			ore_n += 1
		if forest_of[i] != 0:
			forest_n += 1
		if water[i] == 1:
			on_water = true
		elif _touches_water(c):
			shore_n += 1
	if on_water:
		return {"ok": false, "reason": "Pumps go on the shore, not in the water", "cells": cells}
	if ore_n > 0:
		return {"ok": true, "cells": cells, "kind": "harvester", "node": "ore", "gained": ["Mine: %d ore per wave" % ore_n], "lost": [], "holes": []}
	if forest_n > 0:
		return {"ok": true, "cells": cells, "kind": "harvester", "node": "forest", "gained": ["Lumber camp: %d timber per wave" % forest_n], "lost": [], "holes": []}
	if shore_n > 0:
		return {"ok": true, "cells": cells, "kind": "harvester", "node": "lake", "gained": ["Pump: %d water per wave" % (shore_n * Bal.LAKE.perShoreCell)], "lost": [], "holes": []}
	return {}


func _touches_water(c: Vector2i) -> bool:
	for d in Game.DIRS4:
		var x: int = c.x + d.x
		var y: int = c.y + d.y
		if Board.in_grid(x, y) and water[Board.cell_idx(x, y)] == 1:
			return true
	return false


## Fill in a new harvester's node data (called by Game when it is placed).
func setup_harvester(h: Dictionary) -> void:
	var node := "ore"
	var forest_n := 0
	var shore_n := 0
	var lake_id := 0
	var forest_id := 0
	for c in h.cells:
		var i := Board.cell_idx(c.x, c.y)
		if g.board.ore[i] != 0:
			node = "ore"
			break
		if forest_of[i] != 0:
			forest_n += 1
			forest_id = forest_of[i]
		elif _touches_water(c):
			shore_n += 1
			for d in Game.DIRS4:
				var x: int = c.x + d.x
				var y: int = c.y + d.y
				if Board.in_grid(x, y) and lake_of[Board.cell_idx(x, y)] != 0:
					lake_id = lake_of[Board.cell_idx(x, y)]
	if h.oreCells == 0:
		if forest_n > 0:
			node = "forest"
		elif shore_n > 0:
			node = "lake"
	h.node = node
	h.forestCells = forest_n
	h.shoreCells = shore_n
	h.forest = forest_id
	h.lake = lake_id
	h.timberAcc = 0.0
	h.age = 0
	# trees under a lumber camp become stumps (the camp sits among them)
	for c in h.cells:
		var i2 := Board.cell_idx(c.x, c.y)
		if tree[i2] == 1:
			tree[i2] = 2
	version += 1


## Per-wave output of a structure, in its own resource.
func output(h: Dictionary) -> float:
	match h.get("node", "ore"):
		"forest":
			var f: Dictionary = forests[h.forest - 1] if h.forest > 0 else {}
			if f.is_empty() or _trees_left(f) == 0:
				return 0.0
			return float(h.forestCells) * Bal.FOREST.perCell
		"lake":
			var l: Dictionary = lakes[h.lake - 1] if h.lake > 0 else {}
			if l.is_empty():
				return 0.0
			return minf(float(h.shoreCells * Bal.LAKE.perShoreCell), l.units)
	var o: float = h.oreCells
	return o * (1.0 + Bal.BUILDING_FX.harvesterHub * g.building_mult("harvesterHub"))


func _trees_left(f: Dictionary) -> int:
	var n := 0
	for c in f.cells:
		if tree[c] == 1:
			n += 1
	return n


func resource_of(node: String) -> String:
	return {"ore": "ore", "forest": "timber", "lake": "water"}[node]


# ---------------------------------------------------------------- wave end
## Called by Game at the end of every wave: output, depletion, regrowth, pimples.
func end_wave(rng: Rng) -> Dictionary:
	var gained := {"ore": 0.0, "timber": 0.0, "water": 0.0}
	for h in g.harvesters:
		var out := output(h)
		if out <= 0.0:
			continue
		var res := resource_of(h.node)
		gained[res] += out
		match h.node:
			"forest":
				h.timberAcc += out
				var f: Dictionary = forests[h.forest - 1]
				while h.timberAcc >= Bal.FOREST.timberPerTree and _trees_left(f) > 0:
					h.timberAcc -= Bal.FOREST.timberPerTree
					_fell_tree(f, rng)
			"lake":
				var l: Dictionary = lakes[h.lake - 1]
				l.units = maxf(0.0, l.units - out)
				if l.units <= 0.0 and l.dry_t < 0:
					l.dry_t = 1
					for c in l.cells:
						water[c] = 2
					version += 1
					ground_version += 1
	for k in gained:
		g.base[k] = g.base.get(k, 0.0) + gained[k]
		other_income += gained[k]
	# regrowth: 1 tree every 2 waves per forest up to its maximum
	for f in forests:
		f.regrow += 1
		if f.regrow >= Bal.FOREST.regrowEvery:
			f.regrow = 0
			if _trees_left(f) < f.max:
				var free: Array = []
				for c in f.cells:
					if tree[c] == 0 and g.obj_at[c] == 0 and g.tower_at[c] == 0 and g.board.road[c] == 0:
						free.append(c)
				if not free.is_empty():
					tree[rng.pick(free)] = 1
					version += 1
	# drained lakes dry into buildable land after one wave
	for l in lakes:
		if l.dry_t > 0:
			l.dry_t -= 1
		elif l.dry_t == 0:
			l.dry_t = -2
			for c in l.cells:
				water[c] = 0
			version += 1
			ground_version += 1
	_grow_pimples(rng)
	return gained


func _fell_tree(f: Dictionary, rng: Rng) -> void:
	var alive: Array = []
	for c in f.cells:
		if tree[c] == 1:
			alive.append(c)
	if alive.is_empty():
		return
	var c2: int = rng.pick(alive)
	tree[c2] = 2
	version += 1
	g.events.append({"t": "treeFell", "cell": c2})


## Between boards: lakes refill 34% (a dried lake does not come back).
func refill_lakes() -> void:
	for l in lakes:
		if l.dry_t == -1:
			l.units = minf(l.max, l.units + l.max * Bal.LAKE.refill)


# ---------------------------------------------------------------- pimples
func _grow_pimples(rng: Rng) -> void:
	var keep: Array = []
	for p in pimples:
		p.age += 1
		if stage(p) == "gone":
			_crater(p.cell)
			g.events.append({"t": "pimpleWither", "cell": p.cell})
			continue
		keep.append(p)
	pimples = keep
	for c in craters:
		c.cool -= 1
	craters = craters.filter(func(c): return not (c.get("scorch", false) and c.cool <= 0))
	for h in g.harvesters:
		h.age = int(h.get("age", 0)) + 1
		if h.age % Bal.PIMPLE.every != 0:
			continue
		var alive := 0
		for p in pimples:
			if p.harvester == h.id:
				alive += 1
		if alive >= pimple_cap():
			continue
		var spots := _free_neighbours(h.cells)
		if spots.is_empty():
			continue
		var cell: int = rng.pick(spots)
		var p2 := {"id": g.next_id, "cell": cell, "harvester": h.id, "node": h.node, "M": rng.pick([2, 3, 4, 5]), "T": rng.pick([1, 2, 3]), "age": 0, "pearl": rng.chance(Bal.PIMPLE.pearlChance)}
		g.next_id += 1
		pimples.append(p2)
		g.events.append({"t": "pimpleSprout", "cell": cell, "id": p2.id})
	version += 1


func _free_neighbours(cells: Array) -> Array:
	var own := {}
	for c in cells:
		own[Board.cell_idx(c.x, c.y)] = true
	var taken := {}
	for p in pimples:
		taken[p.cell] = true
	for c in craters:
		if c.cool > 0:
			taken[c.cell] = true
	var out: Array = []
	for c in cells:
		for d in Game.DIRS4:
			var x: int = c.x + d.x
			var y: int = c.y + d.y
			if not Board.in_grid(x, y):
				continue
			var i := Board.cell_idx(x, y)
			if own.has(i) or taken.has(i) or g.board.road[i] == 1 or g.obj_at[i] != 0 or g.tower_at[i] != 0:
				continue
			if tree[i] == 1 or water[i] != 0 or g.board.is_core_cell(x, y):
				continue
			if not out.has(i):
				out.append(i)
	return out


func _crater(cell: int) -> void:
	craters.append({"cell": cell, "cool": Bal.PIMPLE.craterCool})
	version += 1


## Orbital scorch: cells in radius cannot sprout pimples for craterCool waves; the mark stays.
func scorch(x: float, y: float, r: float) -> void:
	scorched.append({"x": x, "y": y, "r": r, "t": g.time})
	for yy in range(floori(y - r), ceili(y + r)):
		for xx in range(floori(x - r), ceili(x + r)):
			if Board.in_grid(xx, yy) and Vector2(xx + 0.5 - x, yy + 0.5 - y).length() <= r:
				craters.append({"cell": Board.cell_idx(xx, yy), "cool": Bal.PIMPLE.craterCool, "scorch": true})
	version += 1


## Stage of a pimple: growing, ripe, turning, gone.
## age 0 is the wave it sprouted; it grows for M-1 waves, is ripe on wave M, turns for T waves.
func stage(p: Dictionary) -> String:
	var k: int = p.age + 1
	if k < p.M:
		return "growing"
	if k == p.M:
		return "ripe"
	if k <= p.M + p.T:
		return "turning"
	return "gone"


## 0..1 growth (size), and 0..1 turning (white -> black).
func growth(p: Dictionary) -> float:
	return clampf(float(p.age + 1) / float(p.M), 0.15, 1.0)


func turn(p: Dictionary) -> float:
	var k: int = p.age + 1
	return clampf(float(k - p.M) / float(p.T), 0.0, 1.0)


## Value as a fraction of V.
func value_frac(p: Dictionary) -> float:
	var k: int = p.age + 1
	match stage(p):
		"growing":
			var den := maxi(1, p.M - 2)
			return 0.236 + (0.382 - 0.236) * clampf(float(k - 1) / den, 0.0, 1.0)
		"ripe":
			return 1.0
		"turning":
			var j: int = k - p.M
			return pow(Bal.PHI, -2.0 * j / p.T)
	return 0.0


func base_value(p: Dictionary) -> float:
	for h in g.harvesters:
		if h.id == p.harvester:
			return maxf(Bal.PIMPLE.minValue, Bal.PIMPLE.valueMult * output(h))
	return Bal.PIMPLE.minValue


func pimple_at(cell: int) -> Dictionary:
	for p in pimples:
		if p.cell == cell:
			return p
	return {}


func charges() -> int:
	return int(g.base.get("lanceCharges", 0))


## Pop a pimple with the Lance. Returns the event dictionary, or {} if it could not.
func pop(pimple_id: int) -> Dictionary:
	if charges() <= 0:
		return {}
	var p: Dictionary = {}
	for q in pimples:
		if q.id == pimple_id:
			p = q
	if p.is_empty():
		return {}
	g.base.lanceCharges = charges() - 1
	var st := stage(p)
	var res := resource_of(p.node)
	var amount := roundf(base_value(p) * value_frac(p))
	var black := st == "turning" and turn(p) >= 1.0
	g.base[res] = g.base.get(res, 0.0) + amount
	pimple_income += amount
	var pearl := st == "ripe" and bool(p.pearl)
	if pearl:
		g.base.pearls = int(g.base.get("pearls", 0)) + 1
	pimples.erase(p)
	_crater(p.cell)
	var ev := {"t": "pop", "cell": p.cell, "stage": st, "black": black, "res": res, "amount": amount, "pearl": pearl, "frac": value_frac(p) if amount > 0 else 0.0}
	g.events.append(ev)
	return ev


func refill_lance() -> void:
	g.base.lanceCharges = lance_charges_max()


# ---------------------------------------------------------------- save
func serialize() -> Dictionary:
	return {
		"tree": Array(tree), "forest_of": Array(forest_of), "lake_of": Array(lake_of), "water": Array(water),
		"forests": forests.duplicate(true), "lakes": lakes.duplicate(true), "pimples": pimples.duplicate(true), "craters": craters.duplicate(true),
		"scorched": scorched.duplicate(true),
	}


func load_data(d: Dictionary) -> void:
	if d.is_empty():
		return
	tree = PackedByteArray(d.tree)
	forest_of = PackedInt32Array(d.forest_of)
	lake_of = PackedInt32Array(d.lake_of)
	water = PackedByteArray(d.water)
	forests = d.forests.duplicate(true)
	lakes = d.lakes.duplicate(true)
	pimples = d.pimples.duplicate(true)
	craters = d.craters.duplicate(true)
	scorched = d.get("scorched", []).duplicate(true)
	version += 1
