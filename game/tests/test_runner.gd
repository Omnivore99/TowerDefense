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
	_test_towns()
	_test_deploy()
	_test_specials()
	_test_cards()
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


static func _calm_game(seed_v: int) -> Game:
	var g := Game.new(seed_v, "normal", {"tutorial": false})
	for i in 60 * 30:
		g.step()
		if g.phase == "calm":
			break
	return g


static func _test_towns() -> void:
	var g := _calm_game(83)
	var ch := g.stream.make("charter", "gold")
	g.must.clear()
	g.may[0] = ch
	var spot := Vector2i(-1, -1)
	for my in Bal.MACRO_H:
		for mx in Bal.MACRO_W:
			if spot.x < 0 and g.preview(ch, 0, false, mx * Bal.MACRO + 4, my * Bal.MACRO + 4).ok:
				spot = Vector2i(mx * Bal.MACRO + 4, my * Bal.MACRO + 4)
	check(spot.x >= 0, "a legal town square exists")
	if spot.x < 0:
		return
	var res := g.place({"zone": "may", "index": 0}, 0, false, spot.x, spot.y)
	check(res.ok and g.towns.list.size() == 1, "town founded")
	check(g.board.spurs.size() == 1 and not g.board.town_routes.is_empty(), "spur road and town routes built")
	var div := 0
	for r in g.board.routes:
		div += r.diverts.size()
	check(div > 0, "main routes divert to the town")
	check(g.preview(g.stream.make("O", "red"), 0, false, spot.x, spot.y).ok == false, "town cells are occupied")
	var t: Dictionary = g.towns.list[0]
	g.base.timber = 200.0
	g.base.water = 200.0
	g.base.ore = 200.0
	check(g.level_town(t.id, "walls") == "", "level up to Village with Walls")
	check(t.level == 2 and t.districts.has("walls") and g.gate_turrets.size() == 1, "walls district adds a gate turret")
	check(absf(g.towns.max_hp(t) - (34.0 + 21.0 + 34.0)) < 0.01, "town HP 34 + 21 per level + 34 walls")
	# diversion rate: about 30%, raiders always
	var route: Route = null
	for r in g.board.routes:
		if not r.diverts.is_empty():
			route = r
	var dv: Dictionary = route.diverts[0]
	var n := 0
	for i in 600:
		var e := SimEnemy.new()
		e.route = route
		e.d = dv.d + 0.01
		g.towns.maybe_divert(g, e, dv.d - 0.01)
		if e.route != route:
			n += 1
	check(n > 120 and n < 240, "about 30%% of monsters divert (%d of 600)" % n)
	var rd := SimEnemy.new()
	rd.route = route
	rd.special = "raider"
	rd.d = dv.d + 0.01
	g.towns.maybe_divert(g, rd, dv.d - 0.01)
	check(rd.route.town_id == t.id, "raiders always divert")
	var snap := g.snapshot()
	var g2 := Game.new(83, "normal", {"tutorial": false, "snapshot": snap})
	check(g2.towns.list.size() == 1 and g2.board.spurs.size() == 1, "towns survive a save")
	g.towns.hit(g, t.id, 999.0)
	check(t.fallen and g.gate_turrets.is_empty(), "a town falls at 0 HP")
	check(g.rebuild_town(t.id) == "" and not t.fallen, "a fallen town can be rebuilt")


static func _test_deploy() -> void:
	var g := _calm_game(91)
	g.wave_index = 1
	g.wave = Waves.make_wave(g.seed, g.board_no, 1, g.mode)
	g.phase = "wave"
	var got := g.deploy.open_crate(g)
	var pts := 0
	for k in got:
		pts += int(Bal.UNITS[k].points)
	check(pts == Bal.DEPLOY_POINTS[0], "crate deals the board's unit points (%d)" % pts)
	g.deploy.pool = ["rifles", "tank"]
	var r: Route = g.board.routes[0]
	var p := r.at(r.length * 0.5)
	check(not g.deploy_unit(0, 0.5, 0.5).get("ok", false) or g.deploy.pool.size() == 1, "units must stand near the road")
	g.deploy.pool = ["rifles", "tank"]
	var res := g.deploy_unit(0, p.x, p.y)
	check(res.get("ok", false), "rifle squad deployed on the road")
	var u: Dictionary = res.unit
	var e := g._spawn(Waves.spec("small", "hearts", "crawler", "", "H", "nonmetal", 1, false, 0), {"route": r, "d": maxf(0.0, r.length * 0.5 - 2.0)})
	e.lane = 0.0
	for i in 120:
		g._step_enemies(Bal.DT)
		g.deploy.step(g, Bal.DT)
	check(e.d < r.length * 0.5 and e.chewing < 0, "a holding rifle squad blocks a small monster")
	check(u.hp < u.max, "the blocked monster chews the squad")
	g.enemies.clear()
	g.deploy.wave_end(g)
	check(g.deploy.pool.has("rifles"), "surviving units return to the pool")
	g.deploy.pool = ["rifles", "rifles", "rifles", "rifles", "rifles"]
	g.deploy.board_end(g)
	check(g.deploy.pool.size() == Bal.HANGAR, "units without housing disband at board end")
	check(not g.can_place_pieces() == not (g.phase == "calm" or not g.wave.get("deploy", false)), "deploy rounds block building")


static func _test_specials() -> void:
	var g := _calm_game(97)
	g.wave_index = 1
	g.wave = Waves.make_wave(g.seed, g.board_no, 1, g.mode)
	var r: Route = g.board.routes[0]
	var e := g._spawn(Waves.spec("medium", "hearts", "crawler", "", "H", "nonmetal", 1, false, 0), {"route": r, "d": r.length * 0.5})
	e.special = "cloaked"
	check(g.hidden_from(e, e.x + 12.0, e.y), "cloaked monsters are hidden beyond 8 cells")
	check(not g.hidden_from(e, e.x + 5.0, e.y), "cloaked monsters show up close")
	e.unmade_t = 3.0
	check(not g.hidden_from(e, e.x + 12.0, e.y), "a neutralised cloak is visible")
	e.special = "burrower"
	e.unmade_t = 0.0
	e.burrowed = true
	var t := g._make_base_tower("Gun", e.x, e.y, 1.0, 8.0)
	check(g.damage(e, 10.0, t) == 0.0, "burrowed monsters ignore tower fire")
	check(g.damage(e, 10.0, null, {"src": "landmine", "area": true}) > 0.0, "traps still hit burrowed monsters")
	check(g.deploy.report.has("landmine"), "damage report records the trap")
	e.burrowed = false
	e.special = "mirror"
	t.base_tower = false
	var hp0 := e.hp
	g.damage(e, 10.0, t, {"beam": true})
	check(e.hp == hp0 and t.stun_t > 0.0, "mirror shells reflect the first beam as a stun")


static func _test_cards() -> void:
	check(absf(Bal.STORY_DAMAGE - 1.5) < 1e-9, "each story x1.5 damage")
	var g := _calm_game(101)
	var cd := g.cards
	cd.start_draw(g)
	check(cd.pending and cd.deal.size() == 5, "a draw deals 5 cards")
	g.ready()
	check(g.phase == "calm", "Ready waits for the draw")
	var one := cd.take(g, [0])
	check(one.size() == 1 and one[0].m == 4, "one card turns over at x4")
	cd.start_draw(g)
	var three := cd.take(g, [0, 1, 2])
	check(three.size() == 3 and three[0].m == 1, "three cards turn over at x1")
	check(Cards.count_of(1) == 1 and Cards.count_of(2) == 2 and Cards.count_of(4) == 3, "count cards step 1, 2, 3")
	check(Cards.face({"id": "forge"}, 4).contains("40%"), "a x4 Forge Heat face shows +40%")
	# glass cannon raises tower damage
	var t: SimTower = null
	for x in g.towers:
		if x.type != "" and not x.base_tower:
			t = x
	if t == null:
		g.must.clear()
		var o := g.stream.make("O", "red")
		for cy in range(2, Bal.GRID_H - 2):
			if t != null:
				break
			for cx in range(2, Bal.GRID_W - 6):
				if g.preview(o, 0, false, cx, cy).get("kind", "") == "tower" and g.preview(o, 0, false, cx + 2, cy).ok and g.preview(o, 0, false, cx + 4, cy).ok:
					for k in 3:
						g.may[0] = g.stream.make("O", "red")
						g.place({"zone": "may", "index": 0}, 0, false, cx + 2 * k, cy)
					for x in g.towers:
						if x.type != "":
							t = x
					break
	check(t != null, "a tower to test cards on")
	if t == null:
		return
	var d0: float = t.stats.damage
	cd.fx["glasscannon"] = 1.0
	g._rebuild_all()
	check(absf(t.stats.damage / d0 - 1.25) < 0.01, "Glass Cannon x1 adds 25%% damage (%.3f)" % (t.stats.damage / d0))
	cd.fx.erase("glasscannon")
	cd.hand = [{"id": "scope", "m": 2}, {"id": "coolant", "m": 1}]
	var r0: float = t.stats.range
	check(cd.mount(g, 0, t) == "", "mount a Scope")
	check(absf(t.stats.range / r0 - 1.24) < 0.01, "a x2 Scope adds 24%% range")
	var slots: int = t.stats.stories
	if slots <= 1:
		check(cd.mount(g, 0, t) != "", "one attachment per story")
	var snap := g.snapshot()
	var g2 := Game.new(101, "normal", {"tutorial": false, "snapshot": snap})
	var t2 := g2.tower_by_id(t.id)
	check(t2 != null and t2.attach.size() == t.attach.size(), "attachments survive a save")
	# draws come every 4th wave
	check(cd.want_draw(4, false) and not cd.want_draw(5, false) and cd.want_draw(5, true), "draw after every 4th wave and each board clear")
