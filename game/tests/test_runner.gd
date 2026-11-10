class_name TestRunner
extends RefCounted
## Headless tests: godot --headless --path game -- --tests

static var failures := 0
static var checks := 0


static func check(cond: bool, what: String) -> void:
	checks += 1
	if not cond:
		failures += 1
		printerr("FAIL: ", what)


static func run_all() -> int:
	failures = 0
	checks = 0
	var t0 := Time.get_ticks_msec()
	_test_rng()
	_test_pieces()
	_test_recipes()
	_test_board()
	_test_determinism()
	_test_evolve()
	_test_targeting()
	_test_kits()
	print("%d checks, %d failures (%.1f s)" % [checks, failures, (Time.get_ticks_msec() - t0) / 1000.0])
	return 1 if failures > 0 else 0


static func _test_rng() -> void:
	# reference values from the v1.1 TypeScript Rng (node): new Rng(12345) first 3 values, subSeed(42, 505, 3, 2)
	var r := Rng.new(12345)
	var got := [r.next(), r.next(), r.next()]
	var ref: Array = TestRefs.RNG_12345
	for i in 3:
		check(absf(got[i] - ref[i]) < 1e-12, "rng value %d: %s vs %s" % [i, got[i], ref[i]])
	check(Rng.sub_seed(42, [505, 3, 2]) == TestRefs.SUB_42_505_3_2, "sub_seed %d vs %d" % [Rng.sub_seed(42, [505, 3, 2]), TestRefs.SUB_42_505_3_2])


static func _test_pieces() -> void:
	var c := Pieces.placed_cells("T", 1, false, 10, 10)
	check(c.size() == 4, "T has 4 cells")
	var s := Pieces.Stream.new(Rng.sub_seed(7, [707, 1, 1]), 100)
	var kinds := []
	for i in 8:
		kinds.append(s.next().kind)
	check("".join(kinds) == TestRefs.STREAM_7, "piece stream %s vs %s" % ["".join(kinds), TestRefs.STREAM_7])


static func _test_recipes() -> void:
	check(Towers.all_recipes().size() == 35, "35 recipes")
	var fams: Array[String] = ["Hook", "Hook", "Block"]
	check(Towers.recipe(fams).type == "Gun", "2 Hook + Block = Gun")


static func _test_board() -> void:
	var b := Board.new(1000)
	check(not b.pending.is_empty(), "first road planned")
	b.commit_pending(Callable())
	check(b.routes.size() >= 1, "routes built")
	check(b.veins.size() >= 4, "ore veins placed")


static func _test_determinism() -> void:
	var a := _quick_run(4242)
	var b := _quick_run(4242)
	check(a == b, "same seed + same inputs = same run (%s vs %s)" % [a, b])


static func _quick_run(seed: int) -> String:
	var g := Game.new(seed, "normal", {"tutorial": false})
	g.undo_enabled = false
	var bot := Bot.new(g, "average", seed ^ 0xB07)
	for i in 60 * 60 * 3:
		bot.act()
		g.step()
		g.events.clear()
		if g.phase == "base" or g.phase == "lost":
			break
	return "%s|%d|%d|%.4f|%d" % [g.phase, g.board_no, g.metrics.kills, g.base.essence, g.towers.size()]


static func _test_evolve() -> void:
	check(Evolve.tech_level(0) == 0 and Evolve.tech_level(1) == 1 and Evolve.tech_level(3) == 2, "tech levels 1/3")
	check(Evolve.tech_level(6) == 3 and Evolve.tech_level(11) == 4 and Evolve.tech_level(19) == 5, "tech levels 6/11/19")
	check(Bal.BRANCHES.size() == 13, "13 towers have branches")
	var n := 0
	for k in Bal.BRANCHES:
		n += Bal.BRANCHES[k].size()
	check(n == 26, "26 branches")
	var g := Game.new(77, "normal", {"tutorial": false})
	var t := SimTower.new()
	t.id = 9001
	t.type = "Laser"
	t.pieces = [{"piece": {"kind": "T"}, "cells": [Vector2i(0, 0)], "layer": 0}]
	t.layers = [[Vector2i(0, 0)]]
	t.stats = {"damage": 10.0, "dps": 10.0, "interval": 1.0, "range": 5.0, "pierce": 0, "chain": 0}
	g.towers.append(t)
	g._reindex()
	check(Evolve.cost(t, -1).ore == 8.0 and Evolve.cost(t, -1).timber == 5.0, "Mk II costs 8 ore + 5 timber")
	check(g.evolve(9001) == "Not enough resources", "Mk II needs resources")
	g.base.ore = 100.0
	g.base.timber = 100.0
	g.base.water = 100.0
	g.base.pearls = 5
	Evolve.apply(t, g.base)
	t.mark = 2
	check(Evolve.blocked(g.base, t, 0) != "", "Mk III blocked while Aether is closed")
	g.base.essence = 13.0
	check(g.open_tech("aether") == "", "open Aether for 13 essence")
	check(g.tech_level("aether") == 1, "Aether level 1")
	g.towers.erase(t)
	t.type = "Laser"
	t.mark = 2
	var c := Evolve.cost(t, 0)
	check(c.get("ore", 0.0) == 13.0 and c.get("water", 0.0) == 8.0, "Mk III Aether split 13 ore / 8 water (%s)" % c)


static func _test_targeting() -> void:
	var g := Game.new(78, "normal", {"tutorial": false})
	var r := Route.make(0, PackedVector2Array([Vector2(0, 0), Vector2(100, 0)]))
	var a := SimEnemy.new()
	a.route = r
	a.d = 60.0
	a.hp = 10.0
	a.speed = 1.0
	var b := SimEnemy.new()
	b.route = r
	b.d = 20.0
	b.hp = 90.0
	b.speed = 3.0
	check(g.priority_score("first", a, 0, 0) > g.priority_score("first", b, 0, 0), "First picks the furthest along")
	check(g.priority_score("strongest", b, 0, 0) > g.priority_score("strongest", a, 0, 0), "Strongest picks most HP")
	check(g.priority_score("fastest", b, 0, 0) > g.priority_score("fastest", a, 0, 0), "Fastest picks the fastest")
	check(g.priority_score("weakest", a, 0, 0) > g.priority_score("weakest", b, 0, 0), "Weakest picks least HP")
	var t := SimTower.new()
	t.type = "Rifle"
	t.angle = 0.0
	check(not g._aim(t, -10.0, 0.0, 1.0 / 60.0), "slow rifle is not aligned after one step on a reverse target")
	for i in 120:
		g._aim(t, -10.0, 0.0, 1.0 / 60.0)
	check(t.aligned, "rifle aligns within 2 s")


static func _test_kits() -> void:
	var g := Game.new(79, "normal", {"tutorial": false})
	for i in 60 * 30:
		g.step()
		if g.phase == "calm":
			break
	g.base.ore = 50.0
	check(g.buy_kit("howitzer") != "", "howitzer needs the Armory")
	check(g.buy_kit("landmine") == "", "buy a landmine")
	check(g.arsenal.belt[0] == "landmine", "landmine on the belt")
	var r: Route = g.board.routes[0]
	var p := r.at(r.length * 0.5)
	var res := g.place_kit(0, 0, floori(p.x), floori(p.y))
	check(res.ok, "landmine placed on the road (%s)" % res.get("reason", ""))
	check(g.arsenal.traps.size() == 1, "one trap")
	var m := {"id": 1, "kind": "thunder", "amp": 1.0, "tick_t": 0.0, "side": 1, "ticks": 0, "x": 0.0, "y": 0.0, "cells": []}
	g.arsenal.metronomes.append(m)
	g.phase = "wave"
	for i in roundi(19.0 / Bal.DT):
		g.arsenal._step_metronomes(g, Bal.DT, 50.0)
	check(m.amp < 0.12, "metronome nearly stops after about 19 s (amp %.3f)" % m.amp)
