class_name Towns
extends RefCounted
## Towns (section 12): one macro square of four districts, linked to the road by a spur.
## About 30% of walking monsters that pass the junction divert to the town and hit its HP.
## Towns level up with Timber, Water and Ore, produce from nearby nodes, and house units.

var list: Array = []  ## {id, macro, x, y, level, hp, districts: [4], fallen, junction, spent, market_used}
var town_at := {}  ## cell index -> town id
var charters_bought := 0


static func macro_cells(m: int) -> Array[int]:
	var p := Board.mxy(m)
	var out: Array[int] = []
	for y in Bal.MACRO:
		for x in Bal.MACRO:
			out.append(Board.cell_idx(p.x * Bal.MACRO + x, p.y * Bal.MACRO + y))
	return out


func max_towns(board_no: int) -> int:
	return 1 + board_no / 2


func by_id(id: int) -> Dictionary:
	for t in list:
		if t.id == id:
			return t
	return {}


func max_hp(t: Dictionary) -> float:
	return Bal.TOWN.hp + Bal.TOWN.hpPerLevel * (t.level - 1) + Bal.TOWN.wallsHp * t.districts.count("walls") + _civic_hp

## Civic Pride card: +13 town HP per multiplier (set by Game from the card state).
var _civic_hp := 0.0
var _civic_prod := 0.0


func housing(t: Dictionary) -> int:
	if t.fallen:
		return 0
	return Bal.TOWN.housing + Bal.TOWN.housingPerLevel * (t.level - 1) + Bal.TOWN.barracksHousing * t.districts.count("barracks")


func total_housing() -> int:
	var n := 0
	for t in list:
		n += housing(t)
	return n


func count_district(kind: String) -> int:
	var n := 0
	for t in list:
		if not t.fallen:
			n += t.districts.count(kind)
	return n


## Free districts: a town of level L has min(L, 4) districts.
func free_district_slots(t: Dictionary) -> int:
	return mini(t.level, 4) - (4 - t.districts.count(""))


# ---------------------------------------------------------------- placing
## {ok, reason, macro, cells, spur}
func preview(g, cx: int, cy: int) -> Dictionary:
	var m := Board.mid(clampi(cx, 0, Bal.GRID_W - 1) / Bal.MACRO, clampi(cy, 0, Bal.GRID_H - 1) / Bal.MACRO)
	var cells := macro_cells(m)
	var pts: Array[Vector2i] = []
	for i in cells:
		pts.append(Vector2i(i % Bal.GRID_W, i / Bal.GRID_W))
	var bad := func(r: String) -> Dictionary: return {"ok": false, "reason": r, "cells": pts, "kind": "town"}
	if g.phase != "calm":
		return bad.call("Found towns between waves")
	var alive := list.filter(func(t): return not t.fallen).size()
	if alive >= max_towns(g.board_no):
		return bad.call("Up to %d towns on this board" % max_towns(g.board_no))
	if m == Board.CORE_ID:
		return bad.call("That is the core")
	var b: Board = g.board
	if b.is_road_macro(m):
		return bad.call("Towns need a square without road")
	var h0: int = b.height[cells[0]]
	for i in cells:
		if b.road[i] == 1:
			return bad.call("Towns need a square without road")
		if b.height[i] != h0:
			return bad.call("Towns need level ground")
		if g.cell_taken(i):
			return bad.call("Something is built there")
		if b.is_blocked_terrain(i):
			return bad.call("Clear land only (no trees or water)")
	var spur := _plan_spur(g, m)
	if spur.is_empty():
		return bad.call("Must be within 13 cells of a road")
	for i in b.spur_cells(spur):
		if b.road[i] == 1 or cells.has(i):
			continue
		if g.cell_taken(i) or b.is_blocked_terrain(i):
			return bad.call("The spur road is blocked")
	return {"ok": true, "reason": "", "cells": pts, "kind": "town", "macro": m, "spur": spur}


## Shortest macro path from a road macro to the town macro, at most 2 steps (about 13 cells).
func _plan_spur(g, m: int) -> Array[int]:
	var b: Board = g.board
	var best: Array[int] = []
	for n in Board.neighbours(m):
		if n != Board.CORE_ID and b.is_road_macro(n) and not _is_town_macro(n):
			var p: Array[int] = [n, m]
			if best.is_empty() or Board.core_dist(n) < Board.core_dist(best[0]):
				best = p
	if not best.is_empty():
		return best
	for n in Board.neighbours(m):
		if n == Board.CORE_ID or b.is_road_macro(n) or _is_town_macro(n):
			continue
		for n2 in Board.neighbours(n):
			if n2 != Board.CORE_ID and n2 != m and b.is_road_macro(n2) and not _is_town_macro(n2):
				var p2: Array[int] = [n2, n, m]
				if best.is_empty() or Board.core_dist(n2) < Board.core_dist(best[0]):
					best = p2
	return best


func _is_town_macro(m: int) -> bool:
	for t in list:
		if t.macro == m:
			return true
	return false


func place(g, pv: Dictionary) -> Dictionary:
	var c := Board.macro_centre(pv.macro)
	var t := {"id": g.next_id, "macro": pv.macro, "x": c.x, "y": c.y, "level": 1, "hp": Bal.TOWN.hp, "districts": ["", "", "", ""],
		"fallen": false, "junction": pv.spur[0], "spent": {}, "market_used": false, "prod": {}}
	g.next_id += 1
	list.append(t)
	for i in macro_cells(pv.macro):
		town_at[i] = t.id
	var spur: Array[int] = []
	spur.assign(pv.spur)
	g.board.add_spur(t.id, spur, g.occupied_fn())
	g.events.append({"t": "townFounded", "id": t.id, "x": t.x, "y": t.y, "spur": pv.spur})
	return t


# ---------------------------------------------------------------- growing
func level_cost(t: Dictionary) -> Dictionary:
	if t.level >= 5:
		return {}
	return Bal.TOWN_LEVEL_COST[t.level - 1]


## Level up the town and pick the district for the newly unlocked quarter ("" at level 5).
func level_up(g, id: int, district: String) -> String:
	var t := by_id(id)
	if t.is_empty() or t.fallen:
		return "No town"
	if t.level >= 5:
		return "Already a Citadel"
	var c := level_cost(t)
	if not Evolve.can_afford(g.base, c):
		return "Not enough resources"
	if t.level < 4 and not Bal.DISTRICTS.has(district):
		return "Pick a district"
	Evolve.pay(g.base, c)
	for k in c:
		t.spent[k] = t.spent.get(k, 0.0) + c[k]
	t.level += 1
	if t.level <= 4:
		t.districts[t.districts.find("")] = district
	t.hp = max_hp(t)
	g.events.append({"t": "townLevel", "id": t.id, "level": t.level, "district": district, "x": t.x, "y": t.y})
	g._refresh_gate_turrets()
	return ""


## A fallen town is rebuilt for half of everything spent on it (plus the charter's worth in Timber).
func rebuild_cost(t: Dictionary) -> Dictionary:
	var c := {"timber": 10.0}
	for k in t.spent:
		c[k] = c.get(k, 0.0) + ceilf(t.spent[k] / 2.0)
	return c


func rebuild(g, id: int) -> String:
	var t := by_id(id)
	if t.is_empty() or not t.fallen:
		return "Not a ruin"
	var c := rebuild_cost(t)
	if not Evolve.can_afford(g.base, c):
		return "Not enough resources"
	Evolve.pay(g.base, c)
	t.fallen = false
	t.hp = max_hp(t)
	g.events.append({"t": "townRebuilt", "id": t.id, "x": t.x, "y": t.y})
	g._refresh_gate_turrets()
	return ""


func market(g, id: int, from: String, to: String) -> String:
	var t := by_id(id)
	if t.is_empty() or t.fallen or not t.districts.has("market"):
		return "No Market"
	if t.market_used:
		return "Market used this wave"
	var amount: float = floorf(float(g.base[from]) / Bal.TOWN.market)
	if amount <= 0.0:
		return "Not enough %s" % from
	g.base[from] = float(g.base[from]) - amount * Bal.TOWN.market
	if to == "pearls":
		g.base.pearls = int(g.base.pearls) + int(amount)
	else:
		g.base[to] = float(g.base[to]) + amount
	t.market_used = true
	return ""


# ---------------------------------------------------------------- combat
## A diverted monster reached the town gates.
func hit(g, town_id: int, dmg: float) -> void:
	var t := by_id(town_id)
	if t.is_empty() or t.fallen:
		return
	t.hp -= dmg
	g.events.append({"t": "townHit", "id": t.id, "x": t.x, "y": t.y, "dmg": dmg})
	if t.hp <= 0.0:
		t.hp = 0.0
		t.fallen = true
		g.events.append({"t": "townFell", "id": t.id, "x": t.x, "y": t.y})
		g._refresh_gate_turrets()
		g.deploy.town_fell(g, t.id)


## Roll for diversion when a monster passes a spur junction.
func maybe_divert(g, e: SimEnemy, prev_d: float) -> void:
	if e.route.diverts.is_empty() or e.overland:
		return
	for dv in e.route.diverts:
		if prev_d < dv.d and e.d >= dv.d:
			var t := by_id(dv.town)
			if t.is_empty() or t.fallen:
				continue
			if e.boss or e.champion or e.arch == "balloon" or e.arch == "walker":
				continue
			if e.special == "raider" or g.combat.chance(Bal.TOWN.divert):
				e.route = dv.route
				return


# ---------------------------------------------------------------- production
func end_wave(g) -> Dictionary:
	var got := {"ore": 0.0, "timber": 0.0, "water": 0.0}
	for t in list:
		t.market_used = false
		if t.fallen:
			continue
		var p := production(g, t)
		for k in p:
			got[k] += p[k]
	for k in got:
		g.base[k] = float(g.base[k]) + got[k]
	return got


## Per-wave production: for each node with cells within 13 cells, 1 + cells / 8, x level, x Granary.
func production(g, t: Dictionary) -> Dictionary:
	var r: float = Bal.TOWN.prodRange
	var c := Vector2(t.x, t.y)
	var out := {"ore": 0.0, "timber": 0.0, "water": 0.0}
	var ore_n := 0
	var x0 := maxi(0, floori(t.x - r))
	var x1 := mini(Bal.GRID_W - 1, ceili(t.x + r))
	var y0 := maxi(0, floori(t.y - r))
	var y1 := mini(Bal.GRID_H - 1, ceili(t.y + r))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if g.board.ore[Board.cell_idx(x, y)] != 0 and c.distance_to(Vector2(x + 0.5, y + 0.5)) <= r:
				ore_n += 1
	if ore_n > 0:
		out.ore += 1.0 + ore_n / 8.0
	for f in g.eco.forests:
		var n := 0
		for i in f.cells:
			if g.eco.tree[i] == 1 and c.distance_to(Vector2(i % Bal.GRID_W + 0.5, i / Bal.GRID_W + 0.5)) <= r:
				n += 1
		if n > 0:
			out.timber += 1.0 + n / 8.0
	for l in g.eco.lakes:
		if l.units <= 0.0:
			continue
		var n2 := 0
		for i in l.cells:
			if c.distance_to(Vector2(i % Bal.GRID_W + 0.5, i / Bal.GRID_W + 0.5)) <= r:
				n2 += 1
		if n2 > 0:
			out.water += 1.0 + n2 / 8.0
	var mult: float = t.level * (1.0 + Bal.TOWN.granary * t.districts.count("granary")) * (1.0 + _civic_prod)
	for k in out:
		out[k] = floorf(out[k] * mult * 10.0) / 10.0
	t.prod = out
	return out


# ---------------------------------------------------------------- save
func serialize() -> Dictionary:
	return {"list": list.duplicate(true), "charters": charters_bought}


func load_data(d: Dictionary) -> void:
	if d.is_empty():
		return
	list = d.list.duplicate(true)
	charters_bought = int(d.get("charters", 0))
	town_at.clear()
	for t in list:
		for i in macro_cells(int(t.macro)):
			town_at[i] = t.id
