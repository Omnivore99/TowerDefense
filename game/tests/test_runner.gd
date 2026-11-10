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
