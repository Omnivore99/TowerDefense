class_name Game
extends RefCounted
## The whole game simulation: pure logic, fixed 60 Hz timestep, no Nodes, no engine physics.
## The view, audio and UI read state and drain `events`; bots drive it headless.
## Ported from v1.1 src/sim/game.ts and extended for v2.0.

const DT := Bal.DT
const SUIT_WEAK := {"hearts": "green", "clubs": "red", "diamonds": "blue", "spades": "gold"}
const SUIT_RESIST := {"hearts": "red", "clubs": "green", "diamonds": "gold", "spades": "blue"}
const HOP_CYCLE: float = Bal.ARCH.hopperCycle
const HOP_AIR: float = Bal.ARCH.hopperAir
const SLINKY_CYCLE: float = Bal.ARCH.slinkyCycle
const TUMBLER_FLIP: float = Bal.ARCH.tumblerFlip
const DIRS4: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var seed: int
var mode: String
var board_no := 1
var attempt := 1
## reveal | calm | wave | cleared | base | lost | victory
var phase := "reveal"
var base: Dictionary
var board: Board
var board_made := false
var time := 0.0
var phase_t := 0.0
var tutorial: Dictionary = {}
var tutorial_enabled := true
var discovered := {}
var discovered_elements := {}
var undo_enabled := true
var last_place: Dictionary = {}
var board_snapshot: Dictionary = {}
var strike_destroys: Array = []

# pieces
var stream: Pieces.Stream
var must: Array = []
var may: Array = []
var hold: Variant = null
var hold_locked := false
var piece_timer := 0.0
var shape_factory_used := false

var reveal_step := 0.0

# entities
var towers: Array[SimTower] = []
var tower_at := PackedInt32Array()
var obj_at := PackedInt32Array()
## Road pieces: {id, kind (barrier|mine), piece, cells, macro, hp, maxHp, mines: Array[bool], entry: {Route: d}}
var road_pieces: Array = []
## Harvesters: {id, piece, cells, oreCells}
var harvesters: Array = []
var enemies: Array[SimEnemy] = []
var projectiles: Array[SimProjectile] = []
## Puddles: {x, y, r, t, dps, tower, maxTargets}
var puddles: Array = []
## Tanks: {id, route, d, x, y, px, py, dir, cd, alive}
var tanks: Array = []
var battery_tower: SimTower = null
var next_id := 1

# waves
var wave_index := 0
var wave: Dictionary = {}
var spawn_queue: Array = []
var wave_t := 0.0
var integrity := Bal.BASE_INTEGRITY
var buffer := 0
var factory_t := 0.0

var combo := {"n": 0, "last": -99.0, "peak": 0}
var metrics: Dictionary = {}
var all_metrics: Array = []
var events: Array = []
var combat: Rng
var wave_rng: Rng
var _tower_index := {}
var eco: Economy
var arsenal: Arsenal
var towns: Towns
var deploy: Deploy
## Walls districts put a small Gun turret at each town gate.
var gate_turrets: Array[SimTower] = []
var metronome_assist := false
var _aura_t := 0.0


func _init(seed_value: int, mode_id: String = "normal", opts: Dictionary = {}) -> void:
	seed = seed_value & 0xFFFFFFFF
	mode = mode_id
	base = new_base()
	eco = Economy.new(self)
	arsenal = Arsenal.new()
	towns = Towns.new()
	deploy = Deploy.new()
	tutorial_enabled = opts.get("tutorial", true)
	tower_at.resize(Bal.GRID_W * Bal.GRID_H)
	obj_at.resize(Bal.GRID_W * Bal.GRID_H)
	combat = Rng.new(Rng.sub_seed(seed, [909]))
	wave_rng = Rng.new(Rng.sub_seed(seed, [808]))
	var snap: Dictionary = opts.get("snapshot", {})
	if not snap.is_empty():
		restore(snap)
	board_snapshot = snapshot()
	start_board(snap.get("boardNo", 1) if not snap.is_empty() else 1)


# ================================================================ base
static func new_base() -> Dictionary:
	var b := []
	for _s in Bal.BASE_SQUARES:
		b.append("")
	return {"unlocked": Bal.BASE_START_SQUARES, "buildings": b, "essence": 0.0, "ore": 0.0, "timber": 0.0, "water": 0.0, "pearls": 0, "lanceLevel": 0, "lanceCharges": 0,
		"tech": {"steam": 0, "aether": 0, "alchemy": 0}, "freeTech": false, "freeTechGiven": false, "researchTech": "", "charterGiven": false}


func has_building(id: String) -> bool:
	return base.buildings.has(id)


## Effect multiplier for a building: 0 if absent, 1 normally, 1.236 with Harmony (exact fit).
func building_mult(id: String) -> float:
	var i: int = base.buildings.find(id)
	if i < 0:
		return 0.0
	return 1.0 + Bal.HARMONY if Bal.BASE_SQUARES[i].size == Bal.BUILDINGS[id].size else 1.0


func is_harmony(square: int) -> bool:
	var id: String = base.buildings[square]
	return id != "" and Bal.BASE_SQUARES[square].size == Bal.BUILDINGS[id].size


func golden_base() -> bool:
	for b in base.buildings:
		if b == "":
			return false
	return true


func can_build(square: int, id: String) -> String:
	if square >= base.unlocked:
		return "Square locked"
	if base.buildings[square] != "":
		return "Square taken"
	if has_building(id):
		return "Already built"
	if Bal.BASE_SQUARES[square].size < Bal.BUILDINGS[id].size:
		return "Square too small"
	if base.essence < Bal.BUILDINGS[id].cost:
		return "Not enough Essence"
	return ""


# ================================================================ snapshots
func snapshot() -> Dictionary:
	var ts: Array = []
	for t in towers:
		if not t.base_tower:
			ts.append({"id": t.id, "pieces": t.pieces.duplicate(true), "height": t.height, "kills": t.kills,
				"mark": t.mark, "branch": t.branch, "priority": t.priority, "prioritySet": t.priority_set})
	var rps: Array = []
	for r in road_pieces:
		rps.append({"id": r.id, "kind": r.kind, "piece": r.piece.duplicate(), "cells": r.cells.duplicate(), "macro": r.macro, "mines": r.mines.duplicate()})
	return {
		"boardNo": board_no,
		"base": base.duplicate(true),
		"board": board.serialize() if board_made else {},
		"towers": ts,
		"roadPieces": rps,
		"harvesters": harvesters.duplicate(true),
		"must": must.duplicate(true),
		"may": may.duplicate(true),
		"hold": hold.duplicate() if hold != null else null,
		"nextId": next_id,
		"eco": eco.serialize(),
		"arsenal": arsenal.serialize(),
		"towns": towns.serialize(),
		"deploy": deploy.serialize(),
	}


func restore(snap: Dictionary) -> void:
	var s: Dictionary = snap.duplicate(true)
	board_no = s.boardNo
	base = s.base
	board_made = not s.board.is_empty()
	if board_made:
		board = Board.new(seed, s.board)
		eco = Economy.new(self)
		eco.attach(board)
		eco.load_data(s.get("eco", {}))
	next_id = maxi(next_id, s.nextId)
	tower_at.fill(0)
	obj_at.fill(0)
	towers.clear()
	for o in s.towers:
		var t := _blank_tower(o.id, o.height)
		t.pieces = o.pieces
		t.kills = o.kills
		t.mark = int(o.get("mark", 1))
		t.branch = int(o.get("branch", -1))
		t.priority = o.get("priority", "")
		t.priority_set = o.get("prioritySet", false)
		_rebuild_tower(t)
		if t.type != "":
			t.active = true
			t.activate_t = 99.0
		for c in t.layers[0]:
			tower_at[Board.cell_idx(c.x, c.y)] = t.id
		towers.append(t)
	_reindex()
	road_pieces.clear()
	for r in s.roadPieces:
		var rp: Dictionary = r
		rp.hp = 0.0
		rp.maxHp = 0.0
		rp.entry = {}
		road_pieces.append(rp)
		for c in rp.cells:
			obj_at[Board.cell_idx(c.x, c.y)] = rp.id
	arsenal = Arsenal.new()
	arsenal.load_data(s.get("arsenal", {}))
	towns = Towns.new()
	towns.load_data(s.get("towns", {}))
	deploy = Deploy.new()
	deploy.load_data(s.get("deploy", {}))
	for k in ["tech", "freeTech", "freeTechGiven", "researchTech", "charterGiven"]:
		if not base.has(k):
			base[k] = new_base()[k]
	harvesters = s.harvesters
	for h in harvesters:
		for c in h.cells:
			obj_at[Board.cell_idx(c.x, c.y)] = h.id
	must = s.must
	may = s.may
	hold = s.hold
	_recompute_entries()
	_refresh_gate_turrets()


func _blank_tower(id: int, h: int) -> SimTower:
	var t := SimTower.new()
	t.id = id
	t.height = h
	return t


func _reindex() -> void:
	_tower_index.clear()
	for t in towers:
		_tower_index[t.id] = t


func tower_by_id(id: int) -> SimTower:
	return _tower_index.get(id, null)


## Where barriers and mines sit along each route (routes change when a road is added).
func _recompute_entries() -> void:
	if not board_made:
		return
	for rp in road_pieces:
		rp.entry = _entries_for(rp.cells)


func _entries_for(cells: Array) -> Dictionary:
	var out := {}
	var set := {}
	for c in cells:
		set[c] = true
	for r in board.routes + board.town_routes:
		var d := 0.0
		while d < r.length:
			var p := r.at(d)
			if set.has(Vector2i(floori(p.x), floori(p.y))):
				out[r] = d
				break
			d += 0.25
	return out


# ================================================================ board flow
func start_board(b: int) -> void:
	board_no = b
	stream = Pieces.Stream.new(Rng.sub_seed(seed, [707, b, attempt]), b * 100000 + attempt * 10000)
	combat = Rng.new(Rng.sub_seed(seed, [909, b, attempt]))
	wave_rng = Rng.new(Rng.sub_seed(seed, [808, b]))
	strike_destroys = []
	if not board_made:
		board = Board.new(seed)
		board_made = true
		eco.attach(board)
	else:
		var plan := board.plan_road(b, func(c: int) -> bool: return obj_at[c] != 0 or tower_at[c] != 0 or arsenal.off_at.has(c) or towns.town_at.has(c))
		board.set_pending(plan.path)
		strike_destroys = plan.destroys
	enemies.clear()
	projectiles.clear()
	puddles.clear()
	tanks.clear()
	deploy.units.clear()
	deploy.reset_report(0)
	last_place = {}
	var slots := Bal.MAY_SLOTS + (1 if has_building("beacon") else 0)
	var kept: Array = may.filter(func(p): return p != null)
	may = []
	for _i in slots:
		may.append(null)
	for p in kept:
		add_piece(p, true)
	hold_locked = false
	wave_index = 0
	wave = {}
	spawn_queue = []
	integrity = Bal.BASE_INTEGRITY
	buffer = roundi(Bal.BUILDING_FX.blastDoor * building_mult("blastDoor"))
	combo = {"n": 0, "last": -99.0, "peak": 0}
	reveal_step = 0.0
	metrics = {
		"board": b, "attempt": attempt, "cleared": false, "baseLost": 0.0, "integrity": Bal.BASE_INTEGRITY, "waveTime": 0.0, "dangerTime": 0.0,
		"maxBacklog": 0, "backlogOver2": 0.0, "combosPeak": 0, "kills": 0, "leaks": 0, "earlyCalls": 0, "piecesPlaced": 0,
	}
	battery_tower = _make_battery() if has_building("missileBattery") else null
	if b >= 2 and not base.freeTechGiven:
		base.freeTech = true
	tutorial = {}
	_set_phase("reveal")
	events.append({"t": "strike", "path": board.pending, "destroys": strike_destroys.size()})


func is_tutorial() -> bool:
	return board_no == 1 and tutorial_enabled


func _set_phase(p: String) -> void:
	phase = p
	phase_t = 0.0
	events.append({"t": "phase", "phase": p})


func _finish_reveal() -> void:
	if not strike_destroys.is_empty():
		var hit := {}
		for c in strike_destroys:
			hit[c] = true
		for t in towers.duplicate():
			var touched := false
			for c in t.layers[0]:
				if hit.has(Board.cell_idx(c.x, c.y)):
					touched = true
			if not touched:
				continue
			towers.erase(t)
			for c in t.layers[0]:
				tower_at[Board.cell_idx(c.x, c.y)] = 0
			for p in t.pieces:
				add_piece(p.piece, true)
			events.append({"t": "destroyed", "x": t.cx, "y": t.cy, "cells": t.layers[0]})
		for h in harvesters.duplicate():
			var touched_h := false
			for c in h.cells:
				if hit.has(Board.cell_idx(c.x, c.y)):
					touched_h = true
			if not touched_h:
				continue
			harvesters.erase(h)
			for c in h.cells:
				obj_at[Board.cell_idx(c.x, c.y)] = 0
			add_piece(h.piece, true)
			events.append({"t": "destroyed", "x": h.cells[0].x, "y": h.cells[0].y, "cells": h.cells})
		for r in road_pieces.duplicate():
			var touched_r := false
			for c in r.cells:
				if hit.has(Board.cell_idx(c.x, c.y)):
					touched_r = true
			if not touched_r:
				continue
			road_pieces.erase(r)
			for c in r.cells:
				obj_at[Board.cell_idx(c.x, c.y)] = 0
		strike_destroys = []
		_reindex()
	board.commit_pending(occupied_fn())
	_recompute_entries()
	events.append({"t": "revealDone"})
	eco.refill_lance()
	if is_tutorial():
		tutorial = {"step": 0, "text": "Drag a piece from the tray onto the board, near the road. Three touching pieces become a tower."}
		add_piece(stream.make("J", "red"), true)
		add_piece(stream.make("L", "red"), true)
		add_piece(stream.make("O", "gold"), true)
	else:
		var n := Bal.BOARD_START_PIECES[board_no - 1]
		if building_mult("beacon") > 1.0:
			n += 1
		for _i in n:
			add_piece(stream.next(), true)
		if has_building("research") and board_no % 3 == 0:
			var r := wave_rng
			add_piece(stream.make(r.pick(["T", "I", "O", "L"]), r.pick(["red", "gold", "green", "blue"]), r.pick(Pieces.RARE_GLYPHS)), true)
			if building_mult("research") > 1.0:
				add_piece(stream.make(r.pick(["c1", "c2", "c3"]), "gold", r.pick(Pieces.COMMON_GLYPHS)), true)
	if board_no >= 2 and not base.charterGiven:
		base.charterGiven = true
		add_piece(stream.make("charter", "gold"), true)
		events.append({"t": "charter"})
	_set_phase("calm")


func ready() -> void:
	if phase != "calm":
		return
	if is_tutorial() and not tutorial.is_empty() and tutorial.step < 3:
		tutorial.step = 3
	if phase_t <= Bal.EARLY_CALL_WINDOW and not (is_tutorial() and wave_index == 0):
		base.essence += Bal.EARLY_CALL_BONUS
		metrics.earlyCalls += 1
		events.append({"t": "early"})
	_start_wave()


func _start_wave() -> void:
	wave_index += 1
	wave = Waves.make_wave(seed, board_no, wave_index, mode)
	deploy.reset_report(wave_index)
	if wave.get("deploy", false):
		deploy.open_crate(self)
	spawn_queue = []
	var at := 0.0
	var k := 0
	for n in wave.bursts:
		var t := at
		for _j in n:
			var sp: Dictionary = wave.enemies[k]
			k += 1
			spawn_queue.append({"at": t, "spec": sp})
			t += Bal.PACK_SPACING[sp.size]
		at = maxf(at + Bal.BURST_GAP, t + 0.8)
	wave_t = 0.0
	eco.refill_lance()
	piece_timer = Bal.WAVE_PIECE_INTERVAL
	factory_t = 3.0
	shape_factory_used = false
	for rp in road_pieces:
		if rp.kind == "barrier" and rp.maxHp == 0.0:
			_arm_barrier(rp)
	if not tutorial.is_empty():
		tutorial = {"step": 4, "text": "Here they come. Pieces now arrive every 4 seconds: keep building!"}
	_set_phase("wave")
	events.append({"t": "waveStart", "index": wave_index})


func _end_wave() -> void:
	events.append({"t": "waveEnd", "index": wave_index})
	var gained := eco.end_wave(Rng.new(Rng.sub_seed(seed, [515, board_no, wave_index, attempt])))
	if gained.ore + gained.timber + gained.water > 0.0:
		events.append({"t": "harvest", "ore": gained.ore, "timber": gained.timber, "water": gained.water})
	arsenal.wave_end()
	deploy.wave_end(self)
	var town_got := towns.end_wave(self)
	if town_got.ore + town_got.timber + town_got.water > 0.0:
		events.append({"t": "townHarvest", "ore": town_got.ore, "timber": town_got.timber, "water": town_got.water})
	for _i in towns.count_district("workshop"):
		var slot: int = arsenal.belt.find("")
		if slot >= 0:
			arsenal.belt[slot] = "landmine"
			events.append({"t": "kitBought", "kind": "landmine", "free": true})
	projectiles.clear()
	puddles.clear()
	tanks.clear()
	tutorial = {}
	if wave_index >= Bal.WAVES_PER_BOARD[board_no - 1]:
		metrics.cleared = true
		_finish_metrics()
		_set_phase("victory" if board_no >= Bal.BOARDS else "cleared")
	else:
		for _i in Bal.CALM_PIECES:
			add_piece(stream.next(), true)
		_set_phase("calm")


func _finish_metrics() -> void:
	metrics.integrity = integrity
	metrics.baseLost = maxf(0.0, Bal.BASE_INTEGRITY - integrity) / Bal.BASE_INTEGRITY
	metrics.combosPeak = combo.peak
	var tot := eco.pimple_income + eco.other_income
	var marks := [0, 0, 0, 0]
	for t in towers:
		if t.type != "":
			marks[t.mark - 1] += 1
	metrics["extra"] = {"pimpleShare": eco.pimple_income / tot if tot > 0.0 else 0.0, "timber": base.timber, "water": base.water, "pearls": base.pearls,
		"mk2": marks[1], "mk3": marks[2], "mk4": marks[3], "techMax": tech_level(best_tech()), "kits": arsenal.traps.size() + arsenal.metronomes.size() + arsenal.rams.size(),
		"pads": 6 - arsenal.pads.count({}), "towns": towns.list.filter(func(t): return not t.fallen).size(),
		"townLevels": towns.list.reduce(func(a, t): return a + int(t.level), 0), "units": deploy.pool.size()}
	all_metrics.append(metrics.duplicate())


## After a cleared board: open the base screen (unlocks the next spiral square).
func enter_base() -> void:
	if phase != "cleared":
		return
	base.unlocked = mini(Bal.BASE_SQUARES.size(), maxi(base.unlocked, 2 + board_no))
	_set_phase("base")


func next_board() -> void:
	if phase != "base" or board_no >= Bal.BOARDS:
		return
	attempt = 1
	eco.refill_lakes()
	arsenal.next_board()
	deploy.board_end(self)
	if has_building("research"):
		var rt: String = base.researchTech if base.researchTech != "" else best_tech()
		base.tech[rt] = int(base.tech[rt]) + 1
	board_no += 1
	board_snapshot = snapshot()
	start_board(board_no)


## Restore everything to how it was when this board began, then play it again.
func retry_board() -> void:
	var b: int = board_snapshot.boardNo
	restore(board_snapshot)
	attempt += 1
	start_board(b)


func build(square: int, id: String) -> String:
	var err := can_build(square, id)
	if err != "":
		return err
	base.essence -= Bal.BUILDINGS[id].cost
	base.buildings[square] = id
	if id == "lance":
		base.lanceLevel = 1
	events.append({"t": "build", "square": square, "id": id})
	return ""


func convert_ore(keep: float = 0.0) -> void:
	var n := floorf(maxf(0.0, base.ore - keep) / Bal.ORE_TO_ESSENCE)
	base.essence += n
	base.ore -= n * Bal.ORE_TO_ESSENCE


## Upgrade the Resource Lance one level (Essence). Returns "" or a reason.
func upgrade_lance() -> String:
	var lv: int = base.get("lanceLevel", 0)
	if not has_building("lance"):
		return "Build the Lance first"
	if lv >= Bal.LANCE.charges.size():
		return "Fully upgraded"
	var cost: float = Bal.LANCE.upgrade[lv - 1]
	if base.essence < cost:
		return "Not enough Essence"
	base.essence -= cost
	base.lanceLevel = lv + 1
	events.append({"t": "lanceUp", "level": lv + 1})
	return ""


## Pop a pimple with the Lance (the player clicks it, anywhere on the map).
func pop_pimple(id: int) -> bool:
	return not eco.pop(id).is_empty()


# ================================================================ pieces & queues
func add_piece(p: Dictionary, to_may: bool) -> void:
	if to_may:
		var i := may.find(null)
		if i >= 0:
			may[i] = p
			events.append({"t": "piece", "zone": "may"})
			return
	must.append(p)
	events.append({"t": "piece", "zone": "must"})


func may_locked() -> bool:
	return not must.is_empty()


## Source: {zone: must|may|hold, index}
func get_piece(s: Dictionary) -> Variant:
	if s.zone == "must":
		return must[s.index] if s.index < must.size() else null
	if s.zone == "may":
		return null if may_locked() else (may[s.index] if s.index < may.size() else null)
	return null if may_locked() else hold


func _take_piece(s: Dictionary) -> Variant:
	var p: Variant = get_piece(s)
	if p == null:
		return null
	if s.zone == "must":
		must.remove_at(s.index)
	elif s.zone == "may":
		may[s.index] = null
	else:
		hold = null
	return p


## Swap a piece with the Hold slot (once per placement, as in modern Tetris).
func hold_swap(s: Dictionary) -> bool:
	if hold_locked or s.zone == "hold":
		return false
	var p: Variant = null
	if s.zone == "must":
		p = must[s.index] if s.index < must.size() else null
	elif not may_locked():
		p = may[s.index]
	if p == null:
		return false
	var prev: Variant = hold
	hold = p
	if s.zone == "must":
		if prev != null:
			must[s.index] = prev
		else:
			must.remove_at(s.index)
	else:
		may[s.index] = prev
	hold_locked = true
	return true


func can_recycle() -> bool:
	return has_building("recycler")


func recycle(s: Dictionary) -> bool:
	if not can_recycle() or phase == "reveal":
		return false
	var p: Variant = _take_piece(s)
	if p == null:
		return false
	var e: float = Bal.BUILDING_FX.recycler * building_mult("recycler")
	base.essence += e
	hold_locked = false
	events.append({"t": "recycle", "essence": e})
	_tutorial_advance("placed")
	return true


## Throw a piece away (bots, and players without a Recycler via the discard button).
func discard(s: Dictionary) -> bool:
	if can_recycle():
		return recycle(s)
	var p: Variant = _take_piece(s)
	if p == null:
		return false
	hold_locked = false
	events.append({"t": "discard"})
	return true


func choose_family(f: String) -> bool:
	if not has_building("shapeFactory") or shape_factory_used:
		return false
	stream.forced_family = f
	shape_factory_used = true
	return true


# ================================================================ technology & evolutions
func tech_level(tech: String) -> int:
	return Evolve.level_of(base, tech)


func best_tech() -> String:
	var best := "steam"
	for k in Bal.TECHS:
		if int(base.tech[k]) > int(base.tech[best]):
			best = k
	return best


func tech_open_cost(tech: String) -> float:
	if tech_level(tech) >= 1:
		return -1.0
	return 0.0 if base.freeTech else Bal.TECH_OPEN_COST


## Open a technology at level 1 (free once from board 2, then 13 Essence each).
func open_tech(tech: String) -> String:
	var c := tech_open_cost(tech)
	if c < 0.0:
		return "Already open"
	if base.essence < c:
		return "Not enough Essence"
	base.essence -= c
	if base.freeTech:
		base.freeTech = false
		base.freeTechGiven = true
	base.tech[tech] = maxi(1, int(base.tech[tech]))
	events.append({"t": "techUp", "tech": tech, "level": tech_level(tech)})
	_rebuild_all()
	return ""


func _add_tech(tech: String, n: int) -> void:
	var before := tech_level(tech)
	base.tech[tech] = int(base.tech[tech]) + n
	var after := tech_level(tech)
	if after > before:
		events.append({"t": "techUp", "tech": tech, "level": after})
		_rebuild_all()


func _rebuild_all() -> void:
	for t in towers:
		_rebuild_tower(t)


func evolve_blocked(tower_id: int, branch: int = -1) -> String:
	var t := tower_by_id(tower_id)
	if t == null:
		return "No tower"
	return Evolve.blocked(base, t, branch)


## Evolve a tower to its next mark. branch (0/1) is needed for Mk III. Returns "" or a reason.
func evolve(tower_id: int, branch: int = -1) -> String:
	var t := tower_by_id(tower_id)
	if t == null:
		return "No tower"
	var err := Evolve.blocked(base, t, branch)
	if err != "":
		events.append({"t": "reject", "reason": err, "cells": t.layers[0]})
		return err
	Evolve.pay(base, Evolve.cost(t, branch))
	if t.mark == 2:
		t.branch = branch
	t.mark += 1
	t.evo_t = 0.0
	_rebuild_tower(t)
	if t.mark == 3:
		_add_tech(t.tech, 1)
	elif t.mark == 4:
		_add_tech(t.tech, 2)
	events.append({"t": "evolve", "towerId": t.id, "mark": t.mark, "tech": t.tech, "x": t.cx, "y": t.cy})
	return ""


func set_priority(tower_id: int, pr: String, all_of_type: bool = false) -> void:
	var t := tower_by_id(tower_id)
	if t == null:
		return
	for o in towers:
		if o == t or (all_of_type and o.type == t.type):
			o.priority = pr
			o.priority_set = true


func cycle_priority(tower_id: int) -> String:
	var t := tower_by_id(tower_id)
	if t == null:
		return ""
	var i := Bal.PRIORITIES.find(t.priority)
	set_priority(tower_id, Bal.PRIORITIES[(i + 1) % Bal.PRIORITIES.size()])
	return t.priority


# ================================================================ kits
func buy_kit(id: String) -> String:
	return arsenal.buy(self, id)


func place_kit(slot: int, rot: int, cx: int, cy: int) -> Dictionary:
	if not can_place_pieces():
		return {"ok": false, "reason": "Not now"}
	return arsenal.place(self, slot, rot, cx, cy)


func can_orbital() -> bool:
	return arsenal.can_orbital(self)


func orbital(x: float, y: float) -> bool:
	return arsenal.orbital(self, x, y)


func can_airstrike() -> bool:
	return arsenal.can_airstrike(self)


func airstrike(x: float, y: float, dir: float) -> bool:
	return arsenal.airstrike(self, x, y, dir)


# ================================================================ placement
func level_at(t: SimTower, x: int, y: int) -> int:
	var c := Vector2i(x, y)
	for l in range(t.layers.size() - 1, -1, -1):
		if t.layers[l].has(c):
			return l + 1
	return 0


func can_place_pieces() -> bool:
	return phase == "calm" or (phase == "wave" and not is_deploy_round())


## Deployment round (section 11): no pieces arrive and none can be placed.
func is_deploy_round() -> bool:
	return phase == "wave" and wave.get("deploy", false)


## Every cell something stands on (pieces, kits, towns).
func cell_taken(i: int) -> bool:
	return obj_at[i] != 0 or tower_at[i] != 0 or arsenal.off_at.has(i) or arsenal.trap_at.has(i) or towns.town_at.has(i)


func occupied_fn() -> Callable:
	return func(c: int) -> bool: return obj_at[c] != 0 or tower_at[c] != 0 or towns.town_at.has(c)


# ---------------------------------------------------------------- towns (section 12)
func charter_cost() -> Dictionary:
	return Bal.CHARTER_COSTS[mini(towns.charters_bought, Bal.CHARTER_COSTS.size() - 1)]


func buy_charter() -> String:
	if not has_building("armory"):
		return "Build the Armory first"
	if may.find(null) < 0:
		return "MAY USE is full"
	var c := charter_cost()
	if not Evolve.can_afford(base, c):
		return "Not enough resources"
	Evolve.pay(base, c)
	towns.charters_bought += 1
	add_piece(stream.make("charter", "gold"), true)
	events.append({"t": "charter"})
	return ""


func level_town(id: int, district: String) -> String:
	return towns.level_up(self, id, district)


func rebuild_town(id: int) -> String:
	return towns.rebuild(self, id)


func town_market(id: int, from: String, to: String) -> String:
	return towns.market(self, id, from, to)


func _refresh_gate_turrets() -> void:
	gate_turrets.clear()
	if towns == null:
		return
	for t in towns.list:
		if t.fallen or not t.districts.has("walls"):
			continue
		var gt := _make_base_tower("Gun", float(t.x), float(t.y), float(t.districts.count("walls")), 9.0)
		gt.hint = "Gate turret"
		gate_turrets.append(gt)


# ---------------------------------------------------------------- deployment (section 11)
func deploy_unit(pool_index: int, x: float, y: float, order: String = "hold") -> Dictionary:
	if phase != "wave" and phase != "calm":
		return {"ok": false, "reason": "Not now"}
	return deploy.deploy(self, pool_index, x, y, order)


## Cloaked monsters are invisible beyond 8 cells; burrowed ones are underground.
func hidden_from(e: SimEnemy, x: float, y: float) -> bool:
	if e.burrowed:
		return true
	if e.special == "cloaked" and e.special_on():
		var r: float = Bal.SPECIAL_FX.cloakRange
		return (e.x - x) * (e.x - x) + (e.y - y) * (e.y - y) > r * r
	return false


func _bad(reason: String, cells: Array) -> Dictionary:
	return {"ok": false, "reason": reason, "cells": cells, "kind": "invalid", "gained": [], "lost": [], "holes": []}


## Preview a placement: {ok, reason, cells, kind (tower|story|harvester|barrier|mine|invalid), towerId, mergeIds, layer, resultType, needs, hint, gained, lost, holes, dps, range}
func preview(piece: Dictionary, rot: int, mirror: bool, cx: int, cy: int) -> Dictionary:
	if Pieces.is_charter(piece):
		var tp := towns.preview(self, cx, cy)
		tp.merge({"gained": ["Found a town here"] if tp.ok else [], "lost": [], "holes": []})
		if not tp.ok:
			tp.kind = "invalid"
		return tp
	var cells := Pieces.placed_cells(piece.kind, rot, mirror, cx, cy)
	if not can_place_pieces():
		return _bad("Deployment round: no building" if is_deploy_round() else "Wait for the road", cells)
	for c in cells:
		if not Board.in_grid(c.x, c.y):
			return _bad("Off the board", cells)
		if board.is_core_cell(c.x, c.y):
			return _bad("That is the core", cells)
		if obj_at[Board.cell_idx(c.x, c.y)] != 0 or towns.town_at.has(Board.cell_idx(c.x, c.y)):
			return _bad("Occupied", cells)
		if arsenal.off_at.has(Board.cell_idx(c.x, c.y)) or arsenal.trap_at.has(Board.cell_idx(c.x, c.y)):
			return _bad("A kit is there", cells)
		if board.is_blocked_terrain(Board.cell_idx(c.x, c.y)) and not eco.is_forest(Board.cell_idx(c.x, c.y)):
			return _bad(blocked_reason(Board.cell_idx(c.x, c.y)), cells)
	var under := {}
	for c in cells:
		var v := tower_at[Board.cell_idx(c.x, c.y)]
		if v != 0:
			under[v] = true
	if not under.is_empty():
		return _preview_story(piece, cells, under)

	var road_n := 0
	for c in cells:
		if board.is_road(c.x, c.y):
			road_n += 1
	if road_n > 0:
		if road_n < cells.size():
			return _bad("Road pieces must sit fully on the road", cells)
		if Pieces.is_cap(piece.kind):
			return _bad("Caps cannot go on the road", cells)
		var macros := {}
		for c in cells:
			macros[Board.mid(c.x / Bal.MACRO, c.y / Bal.MACRO)] = true
		for rp in road_pieces:
			if macros.has(rp.macro):
				return _bad("One road piece per square", cells)
		var kind := "barrier" if piece.kind == "O" else "mine"
		return {"ok": true, "cells": cells, "kind": kind, "gained": ["Barrier: blocks the road" if kind == "barrier" else "Mine field: %d mines" % cells.size()], "lost": [], "holes": []}
	var h0 := board.h(cells[0].x, cells[0].y)
	for c in cells:
		if board.h(c.x, c.y) != h0:
			return _bad("A piece must sit on one height", cells)
	var harvest := _preview_harvest(piece, cells)
	if not harvest.is_empty():
		return harvest

	var adj := _adjacent_towers(cells, h0)
	var ground_count := 1
	for t in adj:
		ground_count += t.ground_count()
	if ground_count > Bal.MAX_GROUND_PIECES:
		return _bad("Towers hold at most %d ground pieces" % Bal.MAX_GROUND_PIECES, cells)
	var ordered := _merge_order(adj)
	var virt := _virtual_tower(ordered, {"piece": piece, "cells": cells, "layer": 0}, h0)
	var before: Dictionary = ordered[0].stats if not ordered.is_empty() else {}
	var merge_ids: Array = []
	if adj.size() > 1:
		for t in adj:
			merge_ids.append(t.id)
	return _describe(virt, before, cells, merge_ids, ordered[0].id if not ordered.is_empty() else 0)


## Harvest structures. v1.1: only ore veins. Overridden by the economy (forests, lakes) in milestone 3.
func _preview_harvest(_piece: Dictionary, cells: Array) -> Dictionary:
	var pv := eco.preview_harvest(cells)
	if not pv.is_empty() and not pv.ok:
		return _bad(pv.reason, cells)
	return pv


func blocked_reason(i: int) -> String:
	if arsenal != null and (arsenal.off_at.has(i) or arsenal.trap_at.has(i)):
		return "A kit is there"
	return eco.blocked_reason(i)


func _adjacent_towers(cells: Array, h0: int) -> Array[SimTower]:
	var adj := {}
	for c in cells:
		for d in DIRS4:
			var nx: int = c.x + d.x
			var ny: int = c.y + d.y
			if not Board.in_grid(nx, ny):
				continue
			var id := tower_at[Board.cell_idx(nx, ny)]
			if id != 0 and tower_by_id(id).height == h0:
				adj[id] = true
	var out: Array[SimTower] = []
	for id in adj:
		out.append(tower_by_id(id))
	return out


func _preview_story(piece: Dictionary, cells: Array, under: Dictionary) -> Dictionary:
	if under.size() > 1:
		return _bad("A story must rest on one tower", cells)
	var t := tower_by_id(under.keys()[0])
	for c in cells:
		if tower_at[Board.cell_idx(c.x, c.y)] != t.id:
			return _bad("A story must rest fully on the tower", cells)
	if not t.active:
		return _bad("Finish the tower first: 3 pieces", cells)
	var lv := level_at(t, cells[0].x, cells[0].y)
	for c in cells:
		if level_at(t, c.x, c.y) != lv:
			return _bad("Uneven support", cells)
	if lv >= Bal.MAX_STORIES:
		return _bad("Max %d stories" % Bal.MAX_STORIES, cells)
	var existing: Array = t.layers[lv] if lv < t.layers.size() else []
	if not existing.is_empty():
		var touches := false
		for c in cells:
			for e in existing:
				if absi(e.x - c.x) + absi(e.y - c.y) == 1:
					touches = true
		if not touches:
			return _bad("Must touch the story it extends", cells)
	var new_layer: Array = existing + cells
	var below: Array = t.layers[lv - 1]
	if new_layer.size() >= below.size():
		return _bad("Each story needs fewer cells than the one below", cells)
	var nb := Towers.bbox(new_layer)
	var bb := Towers.bbox(below)
	if nb.size.x > bb.size.x or nb.size.y > bb.size.y:
		return _bad("A story must be smaller in all respects", cells)
	var virt := _virtual_tower([t], {"piece": piece, "cells": cells, "layer": lv}, t.height)
	var p := _describe(virt, t.stats, cells, [], t.id)
	p.kind = "story"
	p.layer = lv
	return p


func _merge_order(ts: Array[SimTower]) -> Array[SimTower]:
	var out: Array[SimTower] = ts.duplicate()
	out.sort_custom(func(a: SimTower, b: SimTower) -> bool:
		if (a.type != "") != (b.type != ""):
			return a.type != ""
		var ga := a.ground_count()
		var gb := b.ground_count()
		if ga != gb:
			return ga > gb
		return a.id < b.id)
	return out


func _virtual_tower(ordered: Array, add: Dictionary, h: int) -> SimTower:
	var t := _blank_tower(-1, h)
	for o in ordered:
		t.pieces.append_array(o.pieces)
	t.pieces.append(add)
	_rebuild_tower(t)
	return t


func _rebuild_tower(t: SimTower) -> void:
	var max_l := 0
	for p in t.pieces:
		max_l = maxi(max_l, p.layer)
	t.layers = []
	for l in max_l + 1:
		var cells: Array[Vector2i] = []
		for p in t.pieces:
			if p.layer == l:
				cells.append_array(p.cells)
		t.layers.append(cells)
	if t.core_count() >= 3:
		var r := Towers.recipe(Towers.tower_families(t))
		t.type = r.type
		t.hint = r.hint
	else:
		t.type = ""
	var g: Array = t.layers[0]
	var sx := 0.0
	var sy := 0.0
	for c in g:
		sx += c.x + 0.5
		sy += c.y + 0.5
	t.cx = sx / g.size()
	t.cy = sy / g.size()
	t.stats = Towers.compute_stats(t, stat_ctx())
	if t.type == "":
		t.mark = 1
		t.branch = -1
	Evolve.apply(t, base)
	if t.type != "" and not t.priority_set:
		t.priority = Bal.PRIORITY_DEFAULT.get(t.type, "first")
	t.air = Bal.TOWERS[t.type].air if t.type != "" else false
	t.reach = t.stats.get("range", 0.0)


func stat_ctx() -> Dictionary:
	return {"powerStation": Bal.BUILDING_FX.powerStation * building_mult("powerStation"), "goldenBase": golden_base()}


func _describe(virt: SimTower, before: Dictionary, cells: Array, merge_ids: Array, tower_id: int) -> Dictionary:
	var after := virt.stats
	var shape: Dictionary = after.shape if not after.is_empty() else Towers.analyse_shape(virt.layers[0])
	var prev_keys := {}
	for b in before.get("bonuses", []):
		if b.good:
			prev_keys[b.key] = true
	var next_keys := {}
	for b in after.get("bonuses", []):
		if b.good:
			next_keys[b.key] = true
	var gained: Array = []
	for b in after.get("bonuses", []):
		if b.good and not prev_keys.has(b.key) and b.key != "surface" and b.key != "mass":
			gained.append(b.label)
	var lost: Array = []
	for b in before.get("bonuses", []):
		if b.good and not next_keys.has(b.key) and b.key != "surface":
			lost.append(b.label)
	var core := virt.core_count()
	var nh: int = shape.holes.size()
	if nh > 0 and not after.is_empty():
		lost.append("%d hole%s: −%d%% damage" % [nh, "s" if nh > 1 else "", nh * 10])
	if not merge_ids.is_empty():
		gained.push_front("Merges %d towers: keeps %s" % [merge_ids.size(), virt.type if virt.type != "" else "pile"])
	return {
		"ok": true, "cells": cells, "kind": "tower", "towerId": tower_id, "mergeIds": merge_ids, "resultType": virt.type,
		"needs": maxi(0, 3 - core), "hint": virt.hint, "gained": gained, "lost": lost, "holes": shape.holes,
		"dps": after.get("dps", 0.0), "range": after.get("range", 0.0),
	}


func place(s: Dictionary, rot: int, mirror: bool, cx: int, cy: int) -> Dictionary:
	var piece: Variant = get_piece(s)
	if piece == null:
		return {"ok": false, "reason": "Place MUST USE pieces first" if (may_locked() and s.zone != "must") else "No piece", "cells": [], "kind": "invalid", "gained": [], "lost": [], "holes": []}
	var pv := preview(piece, rot, mirror, cx, cy)
	if not pv.ok:
		events.append({"t": "reject", "reason": pv.get("reason", "Illegal")})
		return pv
	var undo_state: Dictionary = _capture_undo() if undo_enabled else {}
	if pv.kind == "town":
		_take_piece(s)
		hold_locked = false
		last_place = {}
		towns.place(self, pv)
		_recompute_entries()
		return pv
	_take_piece(s)
	hold_locked = false
	metrics.piecesPlaced += 1
	var cells: Array = pv.cells
	if undo_enabled:
		last_place = {"t": time, "pieceId": piece.id, "cells": cells, "color": piece.color, "state": undo_state}
	match pv.kind:
		"barrier", "mine":
			var rp := {
				"id": next_id, "kind": pv.kind, "piece": piece, "cells": cells,
				"macro": Board.mid(cells[0].x / Bal.MACRO, cells[0].y / Bal.MACRO),
				"hp": 0.0, "maxHp": 0.0, "mines": [], "entry": _entries_for(cells),
			}
			next_id += 1
			for _c in cells:
				rp.mines.append(true)
			if rp.kind == "barrier" and phase == "wave":
				_arm_barrier(rp)
			road_pieces.append(rp)
			for c in cells:
				obj_at[Board.cell_idx(c.x, c.y)] = rp.id
			events.append({"t": "place", "pieceId": piece.id, "cells": cells, "size": cells.size(), "kind": pv.kind, "color": piece.color})
		"harvester":
			_place_harvester(piece, cells, pv)
		"story":
			var t := tower_by_id(pv.towerId)
			var before := t.stats
			t.pieces.append({"piece": piece, "cells": cells, "layer": pv.layer})
			_rebuild_tower(t)
			events.append({"t": "place", "pieceId": piece.id, "cells": cells, "size": cells.size(), "kind": "story", "towerId": t.id, "pieceCount": t.pieces.size(), "color": piece.color, "layer": pv.layer})
			_bonus_events(t, before)
			_tutorial_advance("story")
		_:
			var h0 := board.h(cells[0].x, cells[0].y)
			var ordered := _merge_order(_adjacent_towers(cells, h0))
			var t: SimTower
			var before2: Dictionary = ordered[0].stats if not ordered.is_empty() else {}
			var was_active: bool = ordered[0].active if not ordered.is_empty() else false
			if ordered.is_empty():
				t = _blank_tower(next_id, h0)
				next_id += 1
				towers.append(t)
			else:
				t = ordered[0]
				for k in range(1, ordered.size()):
					var other := ordered[k]
					t.pieces.append_array(other.pieces)
					t.kills += other.kills
					towers.erase(other)
					events.append({"t": "merged", "into": t.id, "from": other.id})
			t.pieces.append({"piece": piece, "cells": cells, "layer": 0})
			_rebuild_tower(t)
			_reindex()
			for c in t.layers[0]:
				tower_at[Board.cell_idx(c.x, c.y)] = t.id
			events.append({"t": "place", "pieceId": piece.id, "cells": cells, "size": cells.size(), "kind": "tower", "towerId": t.id, "pieceCount": t.pieces.size(), "color": piece.color, "layer": 0})
			if t.type != "" and not was_active:
				t.active = true
				t.activate_t = 0.0
				t.cooldown = 0.0
				discovered[t.type] = true
				events.append({"t": "activate", "towerId": t.id, "type": t.type})
				_tutorial_advance("activate")
			elif was_active:
				_tutorial_advance("mass")
			_bonus_events(t, before2)
	_tutorial_advance("placed")
	return pv


func _place_harvester(piece: Dictionary, cells: Array, _pv: Dictionary) -> void:
	var ore_cells := 0
	for c in cells:
		if board.ore[Board.cell_idx(c.x, c.y)] != 0:
			ore_cells += 1
	var h := {"id": next_id, "piece": piece, "cells": cells, "oreCells": ore_cells, "node": "ore"}
	next_id += 1
	eco.setup_harvester(h)
	harvesters.append(h)
	for c in cells:
		obj_at[Board.cell_idx(c.x, c.y)] = h.id
	events.append({"t": "place", "pieceId": piece.id, "cells": cells, "size": cells.size(), "kind": "harvester", "color": piece.color, "harvesterId": h.id})


func _capture_undo() -> Dictionary:
	var ts: Array = []
	for t in towers:
		ts.append(t.copy())
	return {
		"towers": ts, "towerAt": tower_at.duplicate(), "objAt": obj_at.duplicate(),
		"roadPieces": road_pieces.duplicate(), "harvesters": harvesters.duplicate(),
		"must": must.duplicate(), "may": may.duplicate(), "hold": hold, "holdLocked": hold_locked,
		"placed": metrics.piecesPlaced, "tutorial": tutorial.duplicate(), "discovered": discovered.duplicate(),
	}


## Seconds left to undo the last placement (0 when it can no longer be undone).
func undo_left() -> float:
	if last_place.is_empty() or not can_place_pieces():
		return 0.0
	return maxf(0.0, Bal.UNDO_SECONDS - (time - last_place.t))


## Take back the last placement: the piece returns to its slot as if it was never placed.
func undo() -> bool:
	var lp := last_place
	if lp.is_empty() or undo_left() <= 0.0:
		return false
	var u: Dictionary = lp.state
	var live := {}
	for t in towers:
		live[t.id] = t
	var restored: Array[SimTower] = []
	for t in u.towers:
		var cur: SimTower = live.get(t.id, null)
		if cur != null and cur.pieces.size() == t.pieces.size():
			restored.append(cur)
			continue
		if cur != null:
			t.cooldown = cur.cooldown
			t.kills = cur.kills
			t.angle = cur.angle
			t.activate_t = maxf(t.activate_t, cur.activate_t)
		restored.append(t)
	towers = restored
	_reindex()
	tower_at = u.towerAt
	obj_at = u.objAt
	road_pieces = u.roadPieces
	harvesters = u.harvesters
	must = u.must
	may = u.may
	hold = u.hold
	hold_locked = u.holdLocked
	metrics.piecesPlaced = u.placed
	tutorial = u.tutorial
	discovered = u.discovered
	last_place = {}
	events.append({"t": "undo", "pieceId": lp.pieceId, "cells": lp.cells, "color": lp.color})
	return true


func _bonus_events(t: SimTower, before: Dictionary) -> void:
	if t.stats.is_empty():
		return
	var prev := {}
	for b in before.get("bonuses", []):
		prev[b.key] = true
	for b in t.stats.bonuses:
		if b.good and not prev.has(b.key) and ["golden", "mirror", "rot", "perfect", "spire", "res", "pure"].has(b.key):
			events.append({"t": "bonus", "towerId": t.id, "label": b.label, "key": b.key})


func _tutorial_advance(what: String) -> void:
	if tutorial.is_empty():
		return
	var step: int = tutorial.step
	if step == 0 and what == "activate":
		tutorial = {"step": 1, "text": "A Gun! Two Hooks and a Block make a Gun. This new piece is MUST USE: place it before the tray unlocks. Try adding it to your Gun for extra mass."}
		add_piece(stream.make("T", "red"), false)
	elif step == 1 and (what == "mass" or what == "placed") and must.is_empty():
		tutorial = {"step": 2, "text": "Caps are small pieces. Drop this one on top of your tower to build a story: more damage and range. (R rotates, F mirrors.)"}
		add_piece(stream.make("c2", "red"), true)
	elif step == 2 and (what == "story" or what == "placed"):
		tutorial = {"step": 3, "text": "Story 2! Press Ready when you are set." if what == "story" else "Press Ready when you are set."}


# ================================================================ simulation step
func step() -> void:
	var dt := DT
	time += dt
	phase_t += dt
	if phase == "reveal":
		_step_reveal(dt)
		return
	if phase != "wave" and phase != "calm":
		return
	for t in towers:
		if t.active:
			t.activate_t += dt
			t.evo_t += dt
	if phase == "calm":
		arsenal.step(self, dt)
		return
	wave_t += dt
	metrics.waveTime += dt
	metrics.maxBacklog = maxi(metrics.maxBacklog, must.size())
	if must.size() > 2:
		metrics.backlogOver2 += dt
	if not wave.get("deploy", false):
		piece_timer -= dt
		if piece_timer <= 0.0:
			piece_timer += Bal.WAVE_PIECE_INTERVAL
			add_piece(stream.next(), false)
	while not spawn_queue.is_empty() and spawn_queue[0].at <= wave_t:
		var item: Dictionary = spawn_queue.pop_front()
		_spawn(item.spec)
	for e in enemies:
		e.px = e.x
		e.py = e.y
	for p in projectiles:
		p.px = p.x
		p.py = p.y
	for k in tanks:
		k.px = k.x
		k.py = k.y
	_step_enemies(dt)
	_step_towers(dt)
	if battery_tower != null:
		_fire_tower(battery_tower, dt)
	for gt in gate_turrets:
		_fire_tower(gt, dt)
	_step_projectiles(dt)
	_step_puddles(dt)
	_step_tanks(dt)
	deploy.step(self, dt)
	_step_mines()
	arsenal.step(self, dt)
	var alive_e: Array[SimEnemy] = []
	var danger := false
	for e in enemies:
		if e.alive:
			alive_e.append(e)
			if e.d / e.route.length > 0.75:
				danger = true
	enemies = alive_e
	var alive_p: Array[SimProjectile] = []
	for p in projectiles:
		if p.alive:
			alive_p.append(p)
	projectiles = alive_p
	if danger:
		metrics.dangerTime += dt
	if integrity <= 0 and phase == "wave":
		_finish_metrics()
		_set_phase("lost")
		return
	if spawn_queue.is_empty() and enemies.is_empty():
		_end_wave()


func _step_reveal(dt: float) -> void:
	var total := board.reveal_total()
	var secs := Bal.REVEAL_SECONDS if board.paths.is_empty() else Bal.REVEAL_STRIKE_SECONDS
	reveal_step += (total / secs) * dt
	if not board.pending.is_empty():
		board.pending.revealed = mini(board.pending.path.size(), floori(reveal_step) + 1)
	if reveal_step >= total + 0.5:
		_finish_reveal()


# ---------------------------------------------------------------- enemies
func _spawn(sp: Dictionary, at: Dictionary = {}, hp_override: float = -1.0, gen: int = 0) -> SimEnemy:
	var sz: Dictionary = Bal.SIZES[sp.size]
	var route: Route
	var overland := false
	if not at.is_empty():
		route = at.route
	elif sp.arch == "balloon":
		var p: Dictionary = wave_rng.pick(board.paths)
		route = Route.make(-1, PackedVector2Array([p.start, Board.CORE_PT]))
		overland = true
	elif sp.arch == "walker":
		var side := wave_rng.int_range(0, 3)
		var tt := wave_rng.range_f(0.1, 0.9)
		var start: Vector2
		match side:
			0: start = Vector2(0, tt * Bal.GRID_H)
			1: start = Vector2(Bal.GRID_W, tt * Bal.GRID_H)
			2: start = Vector2(tt * Bal.GRID_W, 0)
			_: start = Vector2(tt * Bal.GRID_W, Bal.GRID_H)
		route = Route.make(-1, PackedVector2Array([start, Board.CORE_PT]))
		overland = true
	else:
		var ing := wave_rng.int_range(0, board.paths.size() - 1)
		var opts: Array = board.routes.filter(func(r: Route) -> bool: return r.ingress == ing)
		route = wave_rng.pick(opts if not opts.is_empty() else board.routes)
	if not at.is_empty() and route.ingress < 0:
		overland = true
	var tier: int = sp.get("tier", 1)
	var max_hp: float = hp_override if hp_override >= 0.0 else float(wave.unitHp) * Waves.hp_weight(sp)
	var start_d: float = at.get("d", 0.0)
	var p0 := route.at(start_d)
	var lane := 0.0
	if not overland:
		lane = (wave_rng.next() * 2.0 - 1.0) * Bal.LANE_SPREAD * (0.3 if (sp.size == "champion" or sp.size == "boss" or sp.size == "giant") else 1.0)
	var e := SimEnemy.new()
	e.id = next_id
	next_id += 1
	e.size = sp.size
	e.suit = sp.suit
	e.arch = sp.arch
	e.ability = sp.ability
	e.golden = sp.golden
	e.boss = sp.get("boss", false)
	e.champion = sp.get("champion", false)
	e.special = sp.get("special", "")
	e.element = sp.get("element", "H")
	e.group = sp.get("group", "nonmetal")
	e.tier = tier
	e.gen = gen
	e.hp = max_hp
	e.max_hp = max_hp
	e.lane = lane
	e.sdir = p0.z
	e.summon_t = Bal.CHAMPION.summonEvery * 0.6
	e.route = route
	e.overland = overland
	e.d = start_d
	e.x = p0.x
	e.y = p0.y
	e.px = p0.x
	e.py = p0.y
	e.dir = p0.z
	e.speed = sz.speed
	e.radius = sz.radius
	e.anim_t = wave_rng.next() * 10.0
	e.ability_t = wave_rng.next() * 3.0
	e.scale = (1.25 if e.ability == "post" else 1.0) * Bal.TIER_SCALE[tier - 1] * (pow(0.8, gen) if gen > 0 else 1.0)
	if e.ability == "noble":
		e.shield = max_hp * Bal.ABILITIES.shield
		e.shield_max = e.shield
	if e.arch == "roller":
		e.speed *= Bal.ARCH.rollerSpeed
	if e.arch == "nautilus":
		e.speed *= Bal.ARCH.nautilusSpeed
	if e.arch == "balloon":
		e.speed *= Bal.ARCH.balloonSpeed
	if e.ability == "precious":
		e.speed *= Bal.ABILITIES.hoarderSpeed
	_place_on_route(e)
	e.px = e.x
	e.py = e.y
	enemies.append(e)
	if e.element != "" and not discovered_elements.has(e.element) and gen == 0:
		discovered_elements[e.element] = true
		events.append({"t": "discover", "element": e.element, "group": e.group})
	if (e.champion or e.boss) and gen == 0:
		events.append({"t": "champion", "x": e.x, "y": e.y, "boss": e.boss})
	events.append({"t": "spawn", "id": e.id})
	return e


## Position on the road, spread across its width so swarms move as a crowd.
func _place_on_route(e: SimEnemy) -> void:
	var p := e.route.at(e.d)
	e.dir = p.z
	if e.overland:
		e.x = p.x
		e.y = p.y
		e.sdir = p.z
		return
	var diff := p.z - e.sdir
	while diff > PI:
		diff -= TAU
	while diff < -PI:
		diff += TAU
	e.sdir += diff * minf(1.0, DT * 7.0)
	var wob := sin(e.anim_t * 1.7 + e.id) * 0.12
	var off := e.lane + wob
	e.x = p.x - sin(e.sdir) * off
	e.y = p.y + cos(e.sdir) * off


func _step_enemies(dt: float) -> void:
	for e in enemies:
		e.herald_boost = false
	var hr2: float = Bal.ABILITIES.heraldRadius * Bal.ABILITIES.heraldRadius
	for e in enemies:
		if e.alive and e.ability == "chalcogen":
			for o in enemies:
				if o != e and (o.x - e.x) * (o.x - e.x) + (o.y - e.y) * (o.y - e.y) < hr2:
					o.herald_boost = true
	for e in enemies:
		if not e.alive:
			continue
		e.anim_t += dt
		e.ability_t += dt
		if e.hit_flash > 0.0:
			e.hit_flash -= dt
		if e.arch == "hopper":
			e.gait = fmod(e.anim_t, HOP_CYCLE) / HOP_CYCLE
			e.airborne = e.gait < HOP_AIR
		elif e.arch == "slinky":
			e.gait = fmod(e.anim_t, SLINKY_CYCLE) / SLINKY_CYCLE
			e.stretched = sin(e.gait * TAU) > 0.0
		else:
			e.gait = fmod(e.anim_t, 1.0)
		if e.arch == "tumbler" and fmod(e.anim_t, TUMBLER_FLIP) < dt:
			e.suit = Waves.SUITS[(Waves.SUITS.find(e.suit) + 1) % 4]
		if e.vuln_t > 0.0:
			e.vuln_t -= dt
		if e.unmade_t > 0.0:
			e.unmade_t -= dt
		var unmade := e.unmade_t > 0.0
		match e.ability:
			"lanthanide":
				if not unmade:
					e.hp = minf(e.max_hp, e.hp + e.max_hp * Bal.ABILITIES.regen * dt)
			"metalloid":
				e.immune = not unmade and fmod(e.ability_t, Bal.ABILITIES.phaseEvery) > Bal.ABILITIES.phaseEvery - Bal.ABILITIES.phaseTime
			"noble":
				if not unmade and time - e.last_hit_t > Bal.ABILITIES.shieldDelay and e.shield < e.shield_max:
					e.shield = minf(e.shield_max, e.shield + e.shield_max * Bal.ABILITIES.shieldRecharge * dt)
			"alkaline":
				if e.ability_t >= Bal.ABILITIES.bearerEvery:
					e.ability_t = 0.0
					for o in enemies:
						if o != e and o.alive and Vector2(o.x - e.x, o.y - e.y).length() < Bal.ABILITIES.bearerRadius:
							o.shield = maxf(o.shield, o.max_hp * Bal.ABILITIES.bearerShield)
		if e.champion and not e.overland:
			e.summon_t -= dt
			if e.summon_t <= 0.0:
				e.summon_t = Bal.CHAMPION.summonEvery
				for k in Bal.CHAMPION.summonCount:
					var m := _spawn(Waves.spec("mite", e.suit, "crawler", "", "H", "nonmetal", 1, false, 0),
						{"route": e.route, "d": maxf(0.0, e.d - 0.6 - k * 0.5)}, float(wave.get("unitHp", 50.0)) * Bal.SIZES.mite.hp, 1)
					m.lane = (k - 1) * 0.8
				events.append({"t": "summon", "x": e.x, "y": e.y, "n": Bal.CHAMPION.summonCount})
		if not e.dots.is_empty():
			for dd in e.dots:
				dd.t -= dt
				damage(e, dd.dps * dt, tower_by_id(dd.tower), {"dot": true})
				if not e.alive:
					break
			if not e.alive:
				continue
			e.dots = e.dots.filter(func(x): return x.t > 0.0)
		if e.slow_t > 0.0:
			e.slow_t -= dt
			if e.slow_t <= 0.0:
				e.slow_mult = 1.0
		var v := e.speed * e.slow_mult * (Bal.ABILITIES.heraldSpeed if e.herald_boost else 1.0)
		if e.ability == "alkali" and fmod(e.ability_t, Bal.ABILITIES.alkaliEvery) < Bal.ABILITIES.alkaliBurst:
			v *= Bal.ABILITIES.alkaliMult
		if e.arch == "roller" and e.route.near_corner(e.d, 2.5):
			v *= Bal.ARCH.rollerBrake
		if e.stun_t > 0.0:
			e.stun_t -= dt
			v = 0.0
		if e.special != "":
			v = _step_special(e, v, dt)
			if not e.sap.is_empty():
				continue
		e.chewing = 0
		if not e.overland:
			for rp in road_pieces:
				if rp.kind != "barrier" or rp.hp <= 0.0:
					continue
				if not rp.entry.has(e.route):
					continue
				var stop: float = rp.entry[e.route] - 0.6
				if e.d <= stop + 0.01 and e.d + v * dt >= stop:
					e.d = maxf(e.d, stop)
					e.chewing = rp.id
					rp.hp -= Bal.COMBAT.barrierChew * sqrt(Bal.SIZES[e.size].hp * e.tier) * float(wave.get("unitHp", 1.0)) * dt
					if rp.hp <= 0.0:
						_break_barrier(rp)
					break
		if e.chewing == 0 and not e.overland and v > 0.0:
			var nxt := e.route.at(e.d + v * dt)
			var u := deploy.blocker_for(e, nxt.x, nxt.y)
			if not u.is_empty():
				e.chewing = -int(u.id)
				deploy.chew(self, u, e, dt)
		if e.chewing == 0:
			var prev_d := e.d
			e.d += v * dt
			if not e.route.diverts.is_empty():
				towns.maybe_divert(self, e, prev_d)
		_place_on_route(e)
		if e.d >= e.route.length:
			_leak(e)


## Leaper, Sapper and Burrower movement. Returns the speed to use this tick.
func _step_special(e: SimEnemy, v: float, dt: float) -> float:
	var on := e.special_on()
	match e.special:
		"burrower":
			e.burrow_t += dt
			var every: float = Bal.SPECIAL_FX.burrowEvery
			var was := e.burrowed
			e.burrowed = on and fmod(e.burrow_t, every) > every - float(Bal.SPECIAL_FX.burrowTime)
			if e.burrowed != was:
				events.append({"t": "burrow", "id": e.id, "down": e.burrowed, "x": e.x, "y": e.y})
		"leaper":
			if e.leap_t > 0.0:
				e.leap_t -= dt
				e.airborne = true
				return v + 3.0 / 0.7
			if not on or e.overland:
				return v
			for tr in arsenal.traps:
				if e.leapt.has(tr.id):
					continue
				var dx: float = tr.x - e.x
				var dy: float = tr.y - e.y
				if dx * dx + dy * dy < 3.2 and dx * cos(e.dir) + dy * sin(e.dir) > 0.0:
					e.leapt[tr.id] = true
					e.leap_t = 0.7
					e.airborne = true
					events.append({"t": "leap", "id": e.id, "x": e.x, "y": e.y})
					return v + 3.0 / 0.7
			for rp in road_pieces:
				if rp.kind != "mine" or e.leapt.has(rp.id):
					continue
				var c: Vector2i = rp.cells[0]
				var mx: float = c.x + 0.5 - e.x
				var my: float = c.y + 0.5 - e.y
				if mx * mx + my * my < 3.2 and mx * cos(e.dir) + my * sin(e.dir) > 0.0:
					e.leapt[rp.id] = true
					e.leap_t = 0.7
					e.airborne = true
					events.append({"t": "leap", "id": e.id, "x": e.x, "y": e.y})
					return v + 3.0 / 0.7
		"sapper":
			if e.sap.is_empty():
				if not on or e.sap_done or e.overland or fmod(e.anim_t, 1.0) > dt:
					return v
				var tgt := _sap_target(e)
				if tgt.is_empty():
					return v
				e.sap = tgt
				e.sap["phase"] = "go"
				e.sap["t"] = 0.0
				events.append({"t": "sapper", "id": e.id, "x": e.x, "y": e.y})
			_step_sap(e, v, dt)
	return v


func _sap_target(e: SimEnemy) -> Dictionary:
	var r: float = Bal.SPECIAL_FX.sapRange
	var best := {}
	var bd := r
	for h in harvesters:
		for c in h.cells:
			var dd := Vector2(c.x + 0.5 - e.x, c.y + 0.5 - e.y).length()
			if dd < bd:
				bd = dd
				best = {"kind": "harvester", "id": h.id, "x": c.x + 0.5, "y": c.y + 0.5}
	for p in eco.pimples:
		var px: float = p.cell % Bal.GRID_W + 0.5
		var py: float = p.cell / Bal.GRID_W + 0.5
		var dd2 := Vector2(px - e.x, py - e.y).length()
		if dd2 < bd:
			bd = dd2
			best = {"kind": "pimple", "id": p.id, "x": px, "y": py}
	return best


func _step_sap(e: SimEnemy, v: float, dt: float) -> void:
	var sp := e.sap
	var home := e.route.at(e.d)
	var to := Vector2(sp.x - e.x, sp.y - e.y) if sp.phase != "back" else Vector2(home.x - e.x, home.y - e.y)
	var dist := to.length()
	match sp.phase:
		"go", "back":
			var stepd := minf(dist, maxf(v, 0.4) * dt)
			if dist > 0.001:
				e.x += to.x / dist * stepd
				e.y += to.y / dist * stepd
				e.dir = atan2(to.y, to.x)
			if dist < 0.6:
				if sp.phase == "go":
					sp.phase = "work"
				else:
					e.sap = {}
					e.sap_done = true
		"work":
			sp.t += dt
			if sp.t >= Bal.SPECIAL_FX.sapTime:
				sp.phase = "back"
				if sp.kind == "pimple":
					for p in eco.pimples:
						if p.id == sp.id:
							eco.spoil(p)
							break
				else:
					for h in harvesters:
						if h.id == sp.id:
							h["sapped"] = true
				events.append({"t": "sabotage", "kind": sp.kind, "x": sp.x, "y": sp.y})


func _arm_barrier(rp: Dictionary) -> void:
	var unit: float = wave.unitHp if not wave.is_empty() else Waves.make_wave(seed, board_no, wave_index + 1, mode).unitHp
	rp.maxHp = Bal.COMBAT.barrierUnits * unit
	rp.hp = rp.maxHp


func _break_barrier(rp: Dictionary) -> void:
	var c: Vector2i = rp.cells[0]
	events.append({"t": "barrierBreak", "x": c.x + 1, "y": c.y + 1})
	road_pieces.erase(rp)
	for cc in rp.cells:
		obj_at[Board.cell_idx(cc.x, cc.y)] = 0


func _leak(e: SimEnemy) -> void:
	e.alive = false
	e.leaked = true
	var dmg: int = Bal.SIZES[e.size].leak + (Bal.ABILITIES.growerLeak if e.ability == "post" else 0) + (1 if e.tier >= 3 else 0)
	if is_tutorial() and wave_t < 20.0:
		dmg = 0
	deploy.record_leak(e)
	if e.route.town_id != 0:
		towns.hit(self, e.route.town_id, float(dmg))
		return
	var from_buffer := mini(buffer, dmg)
	buffer -= from_buffer
	integrity -= dmg - from_buffer
	metrics.leaks += 1
	events.append({"t": "leak", "dmg": dmg, "x": e.x, "y": e.y})


## Apply damage with suit, archetype and ability rules. Returns damage dealt.
## o: {single, area, beam, dot, splash, ignoreShield, fx, fy, crit}
func damage(e: SimEnemy, amount: float, t: SimTower, o: Dictionary = {}) -> float:
	if not e.alive:
		return 0.0
	var is_dot: bool = o.get("dot", false)
	if e.burrowed and (o.get("unit", false) or (t != null and t.type != "Bomb")):
		return 0.0
	if e.special == "mirror" and not e.mirror_used and o.get("beam", false) and t != null and not t.base_tower and e.special_on():
		e.mirror_used = true
		t.stun_t = Bal.SPECIAL_FX.mirrorStun
		events.append({"t": "mirror", "x": e.x, "y": e.y, "x2": t.cx, "y2": t.cy, "towerId": t.id})
		return 0.0
	if e.immune:
		if not is_dot and combat.chance(0.2):
			events.append({"t": "immune", "x": e.x, "y": e.y})
		return 0.0
	var m := 1.0
	var color: String = t.stats.get("color", "") if (t != null and not t.stats.is_empty()) else ""
	if color != "":
		if SUIT_WEAK[e.suit] == color:
			m *= Bal.SUIT_STRONG
		elif SUIT_RESIST[e.suit] == color:
			m *= Bal.SUIT_WEAK_MULT
	if e.arch == "swinger":
		if o.get("single", false) and combat.chance(Bal.ARCH.swingerParry):
			events.append({"t": "parry", "x": e.x, "y": e.y})
			return 0.0
		if o.get("beam", false) or o.get("area", false):
			m *= Bal.ARCH.swingerWeak
	if e.arch == "slinky" and e.stretched and o.get("splash", false):
		m *= Bal.ARCH.slinkySplash
	if e.arch == "blob" and (o.get("splash", false) or o.get("area", false)):
		m *= Bal.ARCH.blobSplash
	if e.arch == "beetle" and o.get("single", false):
		m *= Bal.ARCH.beetleBullet
	if e.arch == "nautilus" and o.has("fx"):
		var a := atan2(o.fy - e.y, o.fx - e.x)
		var diff := fmod(absf(a - e.dir), TAU)
		if diff > PI:
			diff = TAU - diff
		if diff < PI / 3.0:
			m *= Bal.ARCH.nautilusFront
	if e.vuln_t > 0.0:
		m *= 1.0 + e.vuln
	var pierce_armor := false
	if t != null:
		m *= t.aura_mult
		pierce_armor = t.mods.has("armor")
	var dmg := amount * m
	var crit := false
	if t != null and not t.stats.is_empty() and t.stats.critChance > 0.0 and not is_dot and combat.chance(t.stats.critChance):
		dmg *= Bal.GLYPHS.critMult
		crit = true
	var unit: float = wave.get("unitHp", 50.0)
	if e.ability == "transition" and not is_dot and not pierce_armor:
		var arm: float = Bal.ABILITIES.armor * unit * (0.5 if e.unmade_t > 0.0 else 1.0)
		dmg = maxf(dmg * Bal.ABILITIES.armorFloor, dmg - arm)
	if not is_dot:
		e.last_hit_t = time
	if e.shield > 0.0 and not o.get("ignoreShield", false) and not pierce_armor:
		var s := minf(e.shield, dmg)
		e.shield -= s
		dmg -= s
	e.hp -= dmg
	var key: String = ("t%d" % t.id) if t != null else String(o.get("src", "other"))
	deploy.record(key, _source_name(key, t), dmg + minf(0.0, e.hp), maxf(0.0, -e.hp), e.hp <= 0.0)
	if t != null:
		e.last_tower = t.id
	if not is_dot:
		e.hit_flash = 0.08
	if crit:
		events.append({"t": "hit", "x": e.x, "y": e.y, "amount": dmg, "crit": true})
	if t != null and not t.stats.is_empty() and not is_dot:
		if t.stats.slowTrait > 0.0:
			_slow(e, 1.0 - t.stats.slowTrait, 0.5)
		if t.stats.slowOnHit > 0.0:
			_slow(e, Bal.GLYPHS.slowOnHit, Bal.GLYPHS.slowTime)
		if t.stats.dotTrait > 0.0:
			_add_dot(e, {"kind": "burn", "dps": amount * t.stats.dotTrait / 2.0, "t": 2.0, "tower": t.id})
	if e.boss:
		var frac := e.hp / e.max_hp
		while e.shed < 4 and frac <= 0.8 - e.shed * 0.2:
			_boss_shed(e)
	if e.hp <= 0.0:
		_kill(e, t)
	return dmg


func _source_name(key: String, t: SimTower) -> String:
	if t != null:
		return t.hint if t.base_tower else "%s Mk %s" % [t.type, ["I", "II", "III", "IV"][t.mark - 1]]
	if key.begins_with("u"):
		var u := deploy.by_id(int(key.substr(1)))
		return deploy.unit_name(u.kind) if not u.is_empty() else "Unit"
	if Bal.KITS.has(key):
		return Bal.KITS[key].name
	return key.capitalize()


func _slow(e: SimEnemy, mult: float, t: float) -> void:
	if e.size == "boss" or e.size == "champion":
		mult = 1.0 - (1.0 - mult) * 0.5
	e.slow_mult = minf(e.slow_mult, mult)
	e.slow_t = maxf(e.slow_t, t)


func _add_dot(e: SimEnemy, d: Dictionary) -> void:
	for x in e.dots:
		if x.kind == d.kind and x.tower == d.tower:
			x.t = maxf(x.t, d.t)
			x.dps = maxf(x.dps, d.dps)
			return
	e.dots.append(d)


func _boss_shed(e: SimEnemy) -> void:
	var n: int = [1, 1, 2, 3, 5][e.shed]
	e.shed += 1
	for i in n:
		_spawn(Waves.spec("small", wave_rng.pick(Waves.SUITS), "hopper", "", "H", "nonmetal", 1, false, 0), {"route": e.route, "d": maxf(0.0, e.d - 0.5 - i * 0.4)}, wave.unitHp, 1)
	events.append({"t": "explode", "x": e.x, "y": e.y, "r": 2.0, "color": "gold", "big": true})


func _kill(e: SimEnemy, t: SimTower) -> void:
	e.alive = false
	metrics.kills += 1
	var essence: float = Bal.SIZES[e.size].essence * Bal.TIER_ESSENCE[e.tier - 1] * (t.stats.get("essenceMult", 1.0) if t != null else 1.0)
	if e.gen > 0:
		essence = maxf(0.25, essence / 2.0)
	if e.ability == "precious":
		essence += Bal.ABILITIES.hoarderEssence
	base.essence += essence
	if t != null:
		t.kills += 1
		var sp: int = t.mods.get("spread", 0)
		if sp > 0 and not e.dots.is_empty():
			for o in _near(t, e, sp, 3.0):
				for dd in e.dots:
					if dd.kind in ["evo", "burn", "virus", "poison"]:
						_add_dot(o, dd.duplicate())
				events.append({"t": "bolt", "x1": e.x, "y1": e.y, "x2": o.x, "y2": o.y, "miss": false, "towerId": t.id, "spread": true})
		if t.tech == "alchemy" and tech_level("alchemy") >= 5:
			_puddle(e.x, e.y, 1.4, t.stats.dps * 0.25, t.id, 3.0)
	if e.golden:
		add_piece(stream.make(combat.pick(["T", "L", "I", "O"]), "gold", "", true), true)
	if e.boss and e.shed < 5:
		e.shed = 4
		_boss_shed(e)
	if e.champion:
		var o: float = Bal.CHAMPION.lootOre
		var ess: float = Bal.CHAMPION.lootEssence
		base.essence += ess
		base.ore += o
		add_piece(stream.make(combat.pick(["T", "L", "I", "O", "J"]), "gold", "", true), true)
		events.append({"t": "loot", "x": e.x, "y": e.y, "essence": ess, "ore": o, "golden": true})
	var split: bool = e.ability == "actinide" and e.gen < Bal.ABILITIES.splitGenerations - 1 and not e.champion
	if split:
		for i in 2:
			var c := _spawn(Waves.spec(e.size, e.suit, e.arch, "actinide", e.element, e.group, e.tier, false, 0),
				{"route": e.route, "d": maxf(0.0, e.d - 0.4 + i * 0.8)}, e.max_hp * Bal.ABILITIES.splitHp, e.gen + 1)
			c.lane = clampf(e.lane + (0.5 if i == 1 else -0.5), -1.0, 1.0)
			_place_on_route(c)
			c.px = c.x
			c.py = c.y
	for kind in ["virus", "poison"]:
		var dd: Dictionary = {}
		for x in e.dots:
			if x.kind == kind:
				dd = x
				break
		if dd.is_empty():
			continue
		var n := 0
		for o2 in enemies:
			if n >= 2:
				break
			if o2.alive and o2 != e and Vector2(o2.x - e.x, o2.y - e.y).length() < 3.0:
				var nd := dd.duplicate()
				nd.t = Bal.COMBAT.virusDuration if kind == "virus" else 3.0
				_add_dot(o2, nd)
				n += 1
	events.append({"t": "kill", "id": e.id, "x": e.x, "y": e.y, "size": e.size, "suit": e.suit, "arch": e.arch, "split": split, "essence": essence, "group": e.group, "tier": e.tier, "champion": e.champion or e.boss, "tower": t.id if t != null else 0})
	if time - combo.last <= Bal.COMBO_WINDOW:
		combo.n += 1
	else:
		combo.n = 1
	combo.last = time
	combo.peak = maxi(combo.peak, combo.n)
	if Bal.COMBO_STEPS.has(combo.n) or (combo.n > 21 and combo.n % 13 == 0):
		events.append({"t": "combo", "n": combo.n, "x": e.x, "y": e.y})


# ---------------------------------------------------------------- towers
func can_hit(t: SimTower, e: SimEnemy) -> bool:
	if not e.alive:
		return false
	if e.arch == "balloon" and not t.air:
		return false
	if e.burrowed and t.type != "Bomb":
		return false
	return true


func in_range(t: SimTower, e: SimEnemy, r: float) -> bool:
	if e.special == "cloaked" and e.special_on():
		r = minf(r, Bal.SPECIAL_FX.cloakRange)
	var rr: float = r + e.radius
	return (e.x - t.cx) * (e.x - t.cx) + (e.y - t.cy) * (e.y - t.cy) <= rr * rr


## Score of an enemy under a targeting priority (section 9.1). Higher is better; always > 0.
func priority_score(pr: String, e: SimEnemy, ox: float, oy: float) -> float:
	var prog := e.d / e.route.length if e.route.length > 0.0 else 0.0
	var sc := 0.0
	match pr:
		"last": sc = 1.01 - prog
		"most": sc = e.threat() + 0.01
		"least": sc = 1.0 / (1.0 + e.threat())
		"fastest": sc = e.speed * e.slow_mult + 0.01
		"slowest": sc = 1.0 / (0.1 + e.speed * e.slow_mult)
		"strongest": sc = e.hp + 0.01
		"weakest": sc = 1.0 / (1.0 + e.hp)
		"specials": sc = prog + 0.01 + (10.0 if (e.ability != "" or e.special != "" or e.boss or e.champion) else 0.0)
		"air": sc = prog + 0.01 + (10.0 if (e.airborne or e.arch == "balloon") else 0.0)
		"closest": sc = 1.0 / (0.5 + Vector2(e.x - ox, e.y - oy).length())
		_: sc = prog + 0.01
	if e.immune:
		sc *= 0.1
	return sc


func _pick_target(t: SimTower, r: float) -> SimEnemy:
	var best: SimEnemy = null
	var best_score := -INF
	var cur: SimEnemy = null
	var cur_score := 0.0
	var pr := t.priority if t.priority != "" else "first"
	for e in enemies:
		if not can_hit(t, e) or not in_range(t, e, r):
			continue
		var score := priority_score(pr, e, t.cx, t.cy)
		if e.id == t.target_id:
			cur = e
			cur_score = score
		if score > best_score:
			best_score = score
			best = e
	# hysteresis: keep the current target unless another beats it by 15%
	if cur != null and best_score <= cur_score * Bal.TARGET_HYSTERESIS:
		return cur
	return best


## Swing the turret toward (x, y) at its turn rate. True when aligned enough to fire.
func _aim(t: SimTower, x: float, y: float, dt: float) -> bool:
	var want := atan2(y - t.cy, x - t.cx)
	var diff := wrapf(want - t.angle, -PI, PI)
	var rate: float = Bal.TURN_RATE.get(t.type, 6.0) * (1.6 if t.base_tower else 1.0)
	var stepa := rate * dt
	if absf(diff) <= stepa:
		t.angle = want
	else:
		t.angle = wrapf(t.angle + signf(diff) * stepa, -PI, PI)
	t.aligned = absf(wrapf(want - t.angle, -PI, PI)) < Bal.AIM_TOLERANCE
	return t.aligned


## Current target for a tracking tower, re-evaluated 10 times a second (with hysteresis).
func _track(t: SimTower, r: float, dt: float) -> SimEnemy:
	t.retarget_t -= dt
	var cur := _enemy_by_id(t.target_id) if t.target_id != 0 else null
	if cur != null and not (can_hit(t, cur) and in_range(t, cur, r)):
		cur = null
	if cur == null or t.retarget_t <= 0.0:
		t.retarget_t = 0.1
		cur = _pick_target(t, r)
	t.target_id = cur.id if cur != null else 0
	return cur


## Support auras: Crystal Ward towers buff neighbours; Aether level 5 links Aether towers.
func _refresh_auras() -> void:
	var grid := tech_level("aether") >= 5
	for t in towers:
		t.aura_mult = 1.0
	for w in towers:
		var b: float = w.mods.get("buff", 0.0)
		if b <= 0.0 and not (grid and w.tech == "aether"):
			continue
		for t in towers:
			if t == w or t.stats.is_empty():
				continue
			var d2 := (t.cx - w.cx) * (t.cx - w.cx) + (t.cy - w.cy) * (t.cy - w.cy)
			if b > 0.0 and d2 <= 36.0:
				t.aura_mult += b
			if grid and w.tech == "aether" and t.tech == "aether" and d2 <= 100.0 and w.id < t.id:
				t.aura_mult += Bal.LIGHTHOUSE_GRID
				w.aura_mult += Bal.LIGHTHOUSE_GRID


func _step_towers(dt: float) -> void:
	var halogens: Array[SimEnemy] = []
	for e in enemies:
		if e.alive and e.ability == "halogen":
			halogens.append(e)
	var r2: float = Bal.ABILITIES.corrosiveRadius * Bal.ABILITIES.corrosiveRadius
	_aura_t -= dt
	if _aura_t <= 0.0:
		_aura_t = 0.5
		_refresh_auras()
	for t in towers:
		if not t.active or t.stats.is_empty() or t.activate_t < Bal.COMBAT.activateTime:
			continue
		var corroded := false
		for e in halogens:
			if (e.x - t.cx) * (e.x - t.cx) + (e.y - t.cy) * (e.y - t.cy) < r2:
				corroded = true
				break
		t.corroded = corroded
		if t.stun_t > 0.0:
			t.stun_t -= dt
			continue
		_fire_tower(t, dt * Bal.ABILITIES.corrosiveRate if corroded else dt)


func _enemy_by_id(id: int) -> SimEnemy:
	for e in enemies:
		if e.id == id:
			return e
	return null


func _fire_tower(t: SimTower, dt: float) -> void:
	var s := t.stats
	var def: Dictionary = Bal.TOWERS[t.type]
	t.cooldown -= dt
	t.fire_drop_t -= dt
	if t.fire_flash > 0.0:
		t.fire_flash -= dt
	if def.kind == "beam":
		var tgt := _track(t, s.range, dt)
		if tgt == null:
			t.ramp_t = 0.0
			t.ramp_target = 0
			return
		if tgt.id != t.ramp_target:
			t.ramp_t = 0.0
			t.ramp_target = tgt.id
		if not _aim(t, tgt.x, tgt.y, dt):
			return
		t.ramp_t += dt * (1.2 if tech_level("aether") >= 2 else 1.0)
		var lo: float = Bal.COMBAT.laserRampLo
		var hi: float = Bal.COMBAT.laserRampHi
		var mult := lo + (hi - lo) * minf(1.0, t.ramp_t / Bal.COMBAT.laserRampT)
		damage(tgt, s.dps * dt * mult, t, {"beam": true, "fx": t.cx, "fy": t.cy})
		var multi: int = t.mods.get("multi", 0)
		if multi > 0 and tgt.alive:
			for e in _near(t, tgt, multi, 5.0):
				if in_range(t, e, s.range):
					damage(e, s.dps * dt * mult * 0.6, t, {"beam": true})
		if t.mods.has("fire") and t.fire_drop_t <= 0.0:
			t.fire_drop_t = 0.35
			_puddle(tgt.x, tgt.y, 0.9, s.dps * 0.3, t.id, t.mods.fire, "fire")
		if t.cooldown <= 0.0:
			t.cooldown = s.interval * 3.0
			t.shots += 1
			_on_hit_extras(t, tgt, s.damage * 3.0 * mult)
		return
	if def.kind == "aura":
		if t.cooldown > 0.0:
			return
		var targets: Array[SimEnemy] = []
		for e in enemies:
			if targets.size() >= s.maxTargets:
				break
			if can_hit(t, e) and in_range(t, e, s.range):
				targets.append(e)
		if targets.is_empty():
			t.target_id = 0
			return
		t.cooldown = s.interval
		t.target_id = targets[0].id
		t.fire_flash = 0.1
		events.append({"t": "aura", "towerId": t.id})
		for e in targets:
			damage(e, s.damage, t, {"area": true})
			if t.type == "Freezer":
				_slow(e, Bal.COMBAT.freezerSlow, s.interval + 0.15)
			if not t.mods.is_empty():
				_evo_hit(t, e, s.damage, true)
		return
	var tgt2 := _track(t, s.range, dt)
	if tgt2 == null:
		return
	var ax := tgt2.x
	var ay := tgt2.y
	if def.kind == "lob" or def.kind == "puddle":
		var lp := tgt2.route.at(tgt2.d + tgt2.speed * tgt2.slow_mult * Bal.COMBAT.lobTime * 0.8)
		ax = lp.x
		ay = lp.y
	var aligned := _aim(t, ax, ay, dt)
	if t.cooldown > 0.0 or not aligned:
		return
	t.cooldown = maxf(t.cooldown + s.interval, s.interval * 0.5)
	t.shots += 1
	t.fire_flash = 0.08
	var dmg: float = s.damage
	if s.spire and t.shots % Bal.SHAPE.spireCritEvery == 0:
		dmg *= Bal.SHAPE.spireCrit
	var color: String = s.color
	match def.kind:
		"bullet":
			projectiles.append(_proj("bullet", t, tgt2, dmg, Bal.COMBAT.bulletSpeed))
			_shot_event(t, def.kind, tgt2.x, tgt2.y, color)
		"homing":
			projectiles.append(_proj("homing", t, tgt2, dmg, Bal.COMBAT.missileSpeed))
			_shot_event(t, def.kind, tgt2.x, tgt2.y, color)
			var sv: int = t.mods.get("salvo", 0)
			var others := _near(t, tgt2, sv, 6.0)
			for k in sv:
				var e2: SimEnemy = others[k % others.size()] if not others.is_empty() else tgt2
				var pr := _proj("homing", t, e2, dmg * 0.7, Bal.COMBAT.missileSpeed * (0.85 + 0.05 * k))
				pr.sx += cos(k * 2.1) * 0.4
				pr.sy += sin(k * 2.1) * 0.4
				projectiles.append(pr)
		"lob", "puddle":
			var lead := tgt2.route.at(tgt2.d + tgt2.speed * tgt2.slow_mult * Bal.COMBAT.lobTime * 0.8)
			var p := _proj("lob" if def.kind == "lob" else "acid", t, tgt2, dmg, 0.0)
			p.tx = lead.x
			p.ty = lead.y
			p.dur = Bal.COMBAT.lobTime
			projectiles.append(p)
			_shot_event(t, def.kind, lead.x, lead.y, color)
			var sv2: int = t.mods.get("salvo", 0)
			for k in sv2:
				var pb := _proj("lob", t, tgt2, dmg * 0.5, 0.0)
				var a := combat.range_f(0.0, TAU)
				var rr := combat.range_f(0.8, 2.2)
				pb.tx = lead.x + cos(a) * rr
				pb.ty = lead.y + sin(a) * rr
				pb.dur = Bal.COMBAT.lobTime * combat.range_f(0.9, 1.15)
				projectiles.append(pb)
		"hitscan":
			var lp2: int = t.mods.get("pierce", 0)
			if lp2 > 0:
				_shot_event(t, "rail", t.cx + cos(t.angle) * s.range, t.cy + sin(t.angle) * s.range, color)
				_line(t, t.angle, s.range, dmg * 0.8, lp2, tgt2)
			else:
				_shot_event(t, def.kind, tgt2.x, tgt2.y, color)
			damage(tgt2, dmg, t, {"single": true, "ignoreShield": true, "fx": t.cx, "fy": t.cy})
			_on_hit_extras(t, tgt2, dmg)
		"pierce":
			var ang := t.angle
			var ca := cos(ang)
			var sa := sin(ang)
			_shot_event(t, def.kind, t.cx + ca * s.range, t.cy + sa * s.range, color)
			for e in enemies:
				if not can_hit(t, e):
					continue
				var dx := e.x - t.cx
				var dy := e.y - t.cy
				var along := dx * ca + dy * sa
				var perp := absf(-dx * sa + dy * ca)
				if along > 0.0 and along <= s.range and perp < 0.9 + e.radius * 0.5:
					damage(e, dmg, t, {"fx": t.cx, "fy": t.cy})
			_on_hit_extras(t, tgt2, dmg)
		"bolt":
			var miss := combat.chance(Bal.COMBAT.lightningMiss)
			var a := combat.range_f(0.0, TAU)
			var r := combat.range_f(0.0, s.area * 1.5 if miss else s.area * 0.6)
			var bx := tgt2.x + cos(a) * r
			var by := tgt2.y + sin(a) * r
			events.append({"t": "bolt", "x1": t.cx, "y1": t.cy, "x2": bx, "y2": by, "miss": miss, "towerId": t.id})
			var n := 0
			for e in enemies:
				if n >= s.maxTargets or not can_hit(t, e):
					continue
				var reach: float = 1.5 + e.radius * 0.5
				if Vector2(e.x - bx, e.y - by).length_squared() <= reach * reach:
					damage(e, dmg, t, {"area": true})
					n += 1
			if n > 0:
				_on_hit_extras(t, tgt2, dmg)
		"cone":
			var n2 := 0
			_shot_event(t, def.kind, tgt2.x, tgt2.y, color)
			for e in enemies:
				if n2 >= s.maxTargets or not can_hit(t, e) or not in_range(t, e, s.range):
					continue
				var diff := fmod(absf(atan2(e.y - t.cy, e.x - t.cx) - t.angle), TAU)
				if diff > PI:
					diff = TAU - diff
				if diff > Bal.COMBAT.flamerCone:
					continue
				damage(e, dmg * (1.0 - Bal.COMBAT.flamerBurn), t, {"area": true, "fx": t.cx, "fy": t.cy})
				_add_dot(e, {"kind": "burn", "dps": dmg * Bal.COMBAT.flamerBurn / s.interval / 2.0 * 0.5, "t": 2.0, "tower": t.id})
				if not t.mods.is_empty():
					_evo_hit(t, e, dmg, true)
				n2 += 1
		"virus":
			var cand: Array[SimEnemy] = []
			for e in enemies:
				if not can_hit(t, e) or not in_range(t, e, s.range):
					continue
				var infected := false
				for dd in e.dots:
					if dd.kind == "virus":
						infected = true
				if not infected:
					cand.append(e)
			cand.sort_custom(func(a1: SimEnemy, b1: SimEnemy) -> bool: return a1.progress() > b1.progress())
			var pool: Array[SimEnemy] = []
			if cand.is_empty():
				pool.append(tgt2)
			else:
				pool.assign(cand.slice(0, s.maxTargets))
			for e in pool:
				_shot_event(t, def.kind, e.x, e.y, color)
				_add_dot(e, {"kind": "virus", "dps": s.dps, "t": Bal.COMBAT.virusDuration, "tower": t.id})
				if not t.mods.is_empty():
					_evo_hit(t, e, s.damage, true)


func _shot_event(t: SimTower, kind: String, x2: float, y2: float, color: String) -> void:
	events.append({"t": "shot", "towerId": t.id, "kind": kind, "x1": t.cx, "y1": t.cy, "x2": x2, "y2": y2, "color": color})


func _proj(kind: String, t: SimTower, tgt: SimEnemy, dmg: float, spd: float) -> SimProjectile:
	var p := SimProjectile.new()
	p.id = next_id
	next_id += 1
	p.kind = kind
	p.x = t.cx
	p.y = t.cy
	p.px = t.cx
	p.py = t.cy
	p.sx = t.cx
	p.sy = t.cy
	p.tx = tgt.x
	p.ty = tgt.y
	p.target_id = tgt.id
	p.speed = spd
	p.damage = dmg
	p.tower = t.id
	p.color = t.stats.get("color", "")
	return p


func _near(t: SimTower, tgt: SimEnemy, n: int, r: float) -> Array[SimEnemy]:
	var cand: Array[SimEnemy] = []
	for e in enemies:
		if e.alive and e != tgt and can_hit(t, e) and Vector2(e.x - tgt.x, e.y - tgt.y).length() < r:
			cand.append(e)
	cand.sort_custom(func(a: SimEnemy, b: SimEnemy) -> bool:
		return Vector2(a.x - tgt.x, a.y - tgt.y).length_squared() < Vector2(b.x - tgt.x, b.y - tgt.y).length_squared())
	return cand.slice(0, n)


## Glyph and resonance extras after a primary hit.
func _on_hit_extras(t: SimTower, tgt: SimEnemy, dmg: float) -> void:
	var s := t.stats
	if s.pierce > 0:
		for e in _near(t, tgt, s.pierce, 1.8):
			damage(e, dmg * 0.7, t)
	if s.chain > 0:
		for e in _near(t, tgt, s.chain, 4.0):
			events.append({"t": "bolt", "x1": tgt.x, "y1": tgt.y, "x2": e.x, "y2": e.y, "miss": false, "towerId": t.id})
			damage(e, dmg * 0.6, t)
	match s.resonance:
		"red":
			for e in _near(t, tgt, 4, 1.5):
				damage(e, dmg * Bal.RESONANCE.burnSplash, t, {"splash": true})
				_add_dot(e, {"kind": "burn", "dps": dmg * 0.1, "t": 2.0, "tower": t.id})
		"gold":
			for e in _near(t, tgt, Bal.RESONANCE.ricochet, 5.0):
				events.append({"t": "shot", "towerId": t.id, "kind": "ricochet", "x1": tgt.x, "y1": tgt.y, "x2": e.x, "y2": e.y, "color": "gold"})
				damage(e, dmg * 0.5, t, {"single": true})
		"blue":
			events.append({"t": "explode", "x": tgt.x, "y": tgt.y, "r": Bal.RESONANCE.blueSplash, "color": "blue"})
			for e in _near(t, tgt, 5, Bal.RESONANCE.blueSplash):
				damage(e, dmg * 0.5, t, {"splash": true})
		"green":
			_add_dot(tgt, {"kind": "poison", "dps": dmg * 0.15, "t": 3.0, "tower": t.id})
	if not t.mods.is_empty() and tgt.alive:
		_evo_hit(t, tgt, dmg, false)


## Branch effects on a hit (section 9.5). area = the hit came from an aura, cone or virus.
func _evo_hit(t: SimTower, tgt: SimEnemy, dmg: float, area: bool) -> void:
	var m := t.mods
	if m.has("splash"):
		var sr: float = m.splash
		if not area:
			events.append({"t": "explode", "x": tgt.x, "y": tgt.y, "r": sr, "color": t.stats.get("color", "")})
		for e in _near(t, tgt, 6, sr):
			damage(e, dmg * (0.25 if area else 0.5), t, {"splash": true, "area": true})
	if not tgt.alive:
		return
	if m.has("dot"):
		_add_dot(tgt, {"kind": "evo", "dps": dmg * float(m.dot), "t": 3.0, "tower": t.id})
	if m.has("slow"):
		_slow(tgt, m.slow[0], m.slow[1])
	if m.has("stun"):
		_stun(tgt, m.stun)
	if m.has("knock") and not (tgt.boss or tgt.champion):
		var kn: float = m.knock * (minf(1.0, t.stats.interval) if area else 1.0)
		tgt.d = maxf(0.0, tgt.d - kn)
	if m.has("vuln"):
		tgt.vuln = maxf(tgt.vuln, m.vuln)
		tgt.vuln_t = 3.0
	if m.has("puddle") and (not area or t.fire_drop_t <= 0.0):
		t.fire_drop_t = 1.5
		_puddle(tgt.x, tgt.y, m.puddle, t.stats.dps * 0.4, t.id)


func _stun(e: SimEnemy, secs: float) -> void:
	if e.stun_cd > time:
		return
	if e.boss or e.champion:
		secs *= 0.5
	e.stun_t = maxf(e.stun_t, secs)
	e.stun_cd = time + secs + 0.8
	events.append({"t": "stun", "x": e.x, "y": e.y, "id": e.id})


## Hits up to n enemies along a line (rail beams), skipping one already hit.
func _line(t: SimTower, ang: float, length: float, dmg: float, n: int, skip: SimEnemy) -> void:
	var ca := cos(ang)
	var sa := sin(ang)
	var hit := 0
	for e in enemies:
		if hit >= n or e == skip or not can_hit(t, e):
			continue
		var dx := e.x - t.cx
		var dy := e.y - t.cy
		var along := dx * ca + dy * sa
		if along > 0.0 and along <= length and absf(-dx * sa + dy * ca) < 0.7 + e.radius * 0.5:
			damage(e, dmg, t, {"beam": true, "ignoreShield": true})
			hit += 1


func _puddle(x: float, y: float, r: float, dps: float, tower_id: int, secs: float = -1.0, kind: String = "acid") -> void:
	if secs < 0.0:
		secs = Bal.COMBAT.acidLinger + (1.0 if tech_level("alchemy") >= 2 else 0.0)
	puddles.append({"x": x, "y": y, "r": r, "t": secs, "dps": dps, "tower": tower_id, "maxTargets": 6, "kind": kind})
	events.append({"t": "puddle", "x": x, "y": y, "r": r, "kind": kind, "secs": secs})


func _tower_or_battery(id: int) -> SimTower:
	var tw := tower_by_id(id)
	if tw == null and battery_tower != null and battery_tower.id == id:
		return battery_tower
	return tw


func _step_projectiles(dt: float) -> void:
	for p in projectiles:
		if not p.alive:
			continue
		var tw := _tower_or_battery(p.tower)
		if p.kind == "lob" or p.kind == "acid":
			p.t += dt
			var k := minf(1.0, p.t / p.dur)
			p.x = p.sx + (p.tx - p.sx) * k
			p.y = p.sy + (p.ty - p.sy) * k
			if k >= 1.0:
				p.alive = false
				if p.kind == "acid":
					var pr: float = tw.stats.area if tw != null else 2.0
					if tw != null and tw.mods.has("puddle"):
						pr = maxf(pr, tw.mods.puddle)
					_puddle(p.tx, p.ty, pr, (tw.stats.dps if tw != null else 5.0) * 0.5, p.tower)
					if tw != null and tw.mods.has("vuln"):
						for e in enemies:
							if e.alive and Vector2(e.x - p.tx, e.y - p.ty).length() < pr:
								e.vuln = maxf(e.vuln, tw.mods.vuln)
								e.vuln_t = 3.0
				else:
					_explode(p, tw)
			continue
		var tgt := _enemy_by_id(p.target_id)
		if tgt != null and tgt.alive:
			p.tx = tgt.x
			p.ty = tgt.y
		else:
			tgt = null
		var dx := p.tx - p.x
		var dy := p.ty - p.y
		var dist := sqrt(dx * dx + dy * dy)
		var step_len := p.speed * dt
		if dist <= step_len + 0.3:
			p.x = p.tx
			p.y = p.ty
			p.alive = false
			if p.kind == "homing":
				_explode(p, tw)
			elif tgt != null and tw != null:
				damage(tgt, p.damage, tw, {"single": true, "fx": p.sx, "fy": p.sy})
				_on_hit_extras(tw, tgt, p.damage)
				events.append({"t": "impact", "x": p.x, "y": p.y, "color": p.color})
		else:
			p.x += dx / dist * step_len
			p.y += dy / dist * step_len


func _explode(p: SimProjectile, tw: SimTower) -> void:
	var r: float = tw.stats.area if tw != null else 1.5
	events.append({"t": "explode", "x": p.x, "y": p.y, "r": r, "color": p.color})
	var n := 0
	var mx: int = tw.stats.maxTargets if tw != null else 5
	var sorted: Array[SimEnemy] = []
	for e in enemies:
		if e.alive:
			sorted.append(e)
	sorted.sort_custom(func(a: SimEnemy, b: SimEnemy) -> bool:
		return Vector2(a.x - p.x, a.y - p.y).length_squared() < Vector2(b.x - p.x, b.y - p.y).length_squared())
	var first: SimEnemy = null
	for e in sorted:
		if n >= mx:
			break
		if tw != null and not can_hit(tw, e):
			continue
		var reach: float = r + e.radius + (0.6 if (e.arch == "slinky" and e.stretched) else 0.0)
		if Vector2(e.x - p.x, e.y - p.y).length() > reach:
			continue
		if e.airborne and p.kind == "lob":
			continue
		damage(e, p.damage, tw, {"area": true, "splash": true, "fx": p.sx, "fy": p.sy})
		if first == null:
			first = e
		n += 1
	if first != null and tw != null:
		_on_hit_extras(tw, first, p.damage)


func _step_puddles(dt: float) -> void:
	for pd in puddles:
		pd.t -= dt
		var tw := tower_by_id(pd.tower)
		var n := 0
		var rr: float = pd.r + 0.3
		for e in enemies:
			if n >= pd.maxTargets or not e.alive or e.airborne or e.overland:
				continue
			if (e.x - pd.x) * (e.x - pd.x) + (e.y - pd.y) * (e.y - pd.y) <= rr * rr:
				damage(e, pd.dps * dt, tw, {"dot": true, "area": true})
				n += 1
	puddles = puddles.filter(func(p): return p.t > 0.0)


func _step_mines() -> void:
	if wave.is_empty():
		return
	var burst := maxf(Bal.COMBAT.mineBurst, Bal.COMBAT.mineBurstUnit * float(wave.unitHp))
	for rp in road_pieces.duplicate():
		if rp.kind != "mine":
			continue
		for i in rp.cells.size():
			if not rp.mines[i]:
				continue
			var cx: float = rp.cells[i].x + 0.5
			var cy: float = rp.cells[i].y + 0.5
			var trig := false
			for e in enemies:
				if e.alive and not e.overland and not e.airborne and Vector2(e.x - cx, e.y - cy).length() < 0.9:
					trig = true
					break
			if not trig:
				continue
			rp.mines[i] = false
			events.append({"t": "mine", "x": cx, "y": cy})
			for e in enemies:
				if e.alive and not e.overland and not e.airborne and Vector2(e.x - cx, e.y - cy).length() <= Bal.COMBAT.mineRadius + e.radius:
					damage(e, burst, null, {"area": true, "splash": true})
		if not rp.mines.has(true):
			road_pieces.erase(rp)
			for c in rp.cells:
				obj_at[Board.cell_idx(c.x, c.y)] = 0


func _step_tanks(dt: float) -> void:
	var mult := building_mult("factory")
	for k in tanks:
		k.d -= Bal.BUILDING_FX.tankSpeed * dt
		var p: Vector3 = k.route.at(k.d)
		k.x = p.x
		k.y = p.y
		k.dir = p.z + PI
		if k.d <= 0.0:
			k.alive = false
			continue
		k.cd -= dt
		if k.cd <= 0.0:
			var tgt: SimEnemy = null
			for e in enemies:
				if e.alive and not e.overland and Vector2(e.x - k.x, e.y - k.y).length() < Bal.BUILDING_FX.tankRange:
					tgt = e
					break
			if tgt != null:
				k.cd = 0.382
				events.append({"t": "shot", "towerId": -1, "kind": "tank", "x1": k.x, "y1": k.y, "x2": tgt.x, "y2": tgt.y, "color": "gold"})
				damage(tgt, Bal.BUILDING_FX.tankDps * 0.382 * mult * (float(wave.unitHp) / 100.0 if not wave.is_empty() else 1.0), null, {"single": true})
	tanks = tanks.filter(func(k): return k.alive)


func _make_base_tower(type: String, x: float, y: float, mult: float, rng: float) -> SimTower:
	var def: Dictionary = Bal.TOWERS[type]
	var t := _blank_tower(next_id, 0)
	next_id += 1
	t.layers = [[Vector2i(int(x), int(y))]]
	t.type = type
	t.active = true
	t.activate_t = 99.0
	t.cx = x
	t.cy = y
	t.base_tower = true
	t.air = false
	var dmg: float = def.dps * def.interval * mult
	t.stats = {
		"damage": dmg, "interval": def.interval, "range": rng, "area": def.get("area", 0.0), "maxTargets": def.get("maxTargets", 1), "dps": dmg / def.interval,
		"pierce": 0, "chain": 0, "critChance": 0.0, "slowOnHit": 0.0, "essenceMult": 1.0, "slowTrait": 0.0, "dotTrait": 0.0, "color": "", "resonance": "",
		"spire": false, "pure": false, "stories": 1, "bonuses": [], "shape": Towers.analyse_shape([Vector2i.ZERO]), "hint": "",
	}
	return t


func _make_battery() -> SimTower:
	var mult := building_mult("missileBattery")
	var def: Dictionary = Bal.TOWERS["Missile"]
	var t := _blank_tower(next_id, 0)
	next_id += 1
	t.layers = [[Vector2i(int(Board.CORE_PT.x), int(Board.CORE_PT.y))]]
	t.type = "Missile"
	t.hint = "Base Missile Battery"
	t.active = true
	t.activate_t = 99.0
	t.cx = Board.CORE_PT.x
	t.cy = Board.CORE_PT.y
	t.base_tower = true
	t.air = true
	var dmg: float = def.dps * def.interval * 2.0 * mult
	t.stats = {
		"damage": dmg, "interval": def.interval, "range": Bal.BUILDING_FX.batteryRange, "area": def.area, "maxTargets": def.maxTargets, "dps": dmg / def.interval,
		"pierce": 0, "chain": 0, "critChance": 0.0, "slowOnHit": 0.0, "essenceMult": 1.0, "slowTrait": 0.0, "dotTrait": 0.0, "color": "", "resonance": "",
		"spire": false, "pure": false, "stories": 1, "bonuses": [], "shape": Towers.analyse_shape([Vector2i.ZERO]), "hint": "",
	}
	return t


# ================================================================ helpers for UI and bots
func next_wave_preview() -> Dictionary:
	if wave_index >= Bal.WAVES_PER_BOARD[board_no - 1]:
		return {}
	return Waves.make_wave(seed, board_no, wave_index + 1, mode)


func waves_in_board() -> int:
	return Bal.WAVES_PER_BOARD[board_no - 1]


func dominant() -> String:
	return Waves.dominant_suit(seed, board_no)


func drain_events() -> Array:
	var e := events
	events = []
	return e
