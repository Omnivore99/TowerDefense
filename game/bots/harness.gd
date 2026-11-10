class_name Harness
extends RefCounted
## Balance harness: runs full 7-board runs with bots and reports per-board metrics.
## godot --headless --path game -- --bots --seeds 8 --mode normal --skill novice,average,expert --json

const MAX_STEPS_PER_BOARD := 60 * 60 * 40
## --boards N stops each run after board N (CI smoke runs).
static var max_boards := 99


static func empty_acc() -> Array:
	var acc: Array = []
	for i in Bal.BOARDS:
		acc.append({"board": i + 1, "clears": 0, "hp": 0.0, "dangerT": 0.0, "waveT": 0.0, "runs": 0, "extra": {}})
	return acc


static func run_skill(skill: String, mode: String, seeds: Array, strategy: String = "standard", verbose: bool = false) -> Dictionary:
	var t0 := Time.get_ticks_msec()
	var acc := empty_acc()
	for seed in seeds:
		run_seed(acc, skill, mode, seed, strategy, verbose)
	return summarize(acc, skill, mode, strategy, (Time.get_ticks_msec() - t0) / 1000.0)


## One full run; adds its first-attempt board results to acc.
static func run_seed(acc: Array, skill: String, mode: String, seed: int, strategy: String, verbose: bool) -> void:
	var t0 := Time.get_ticks_msec()
	if true:
		var g := Game.new(seed, mode, {"tutorial": false})
		g.undo_enabled = false
		var bot := Bot.new(g, skill, seed ^ 0xB07, strategy)
		var steps := 0
		var board := 1
		while true:
			bot.act()
			g.step()
			g.events.clear()
			steps += 1
			if g.phase == "lost" or g.phase == "victory" or g.phase == "cleared" or steps > MAX_STEPS_PER_BOARD:
				if not g.all_metrics.is_empty():
					var m: Dictionary = g.all_metrics[g.all_metrics.size() - 1]
					if m.attempt == 1 and m.board == board:
						var a: Dictionary = acc[board - 1]
						a.runs += 1
						a.clears += 1 if m.cleared else 0
						a.hp += m.baseLost
						a.dangerT += m.dangerTime
						a.waveT += m.waveTime
						for k in m.get("extra", {}):
							a.extra[k] = a.extra.get(k, 0.0) + float(m.extra[k])
				if g.phase == "victory" or steps > MAX_STEPS_PER_BOARD:
					break
				if g.phase == "lost":
					if g.attempt >= 3:
						if g.board_no >= Bal.BOARDS:
							break
						g.phase = "cleared"
					else:
						g.retry_board()
						steps = 0
						continue
				bot.act()
				bot.act()
				board = g.board_no
				if board > max_boards:
					break
				steps = 0
				if verbose:
					printerr("%s seed %d: board %d (%.1f s)" % [skill, seed, board, (Time.get_ticks_msec() - t0) / 1000.0])


static func merge_acc(into: Array, other: Array) -> void:
	for i in into.size():
		var a: Dictionary = into[i]
		var b: Dictionary = other[i]
		for k in ["clears", "hp", "dangerT", "waveT", "runs"]:
			a[k] += b[k]
		for k in b.extra:
			a.extra[k] = a.extra.get(k, 0.0) + float(b.extra[k])


static func summarize(acc: Array, skill: String, mode: String, strategy: String, seconds: float) -> Dictionary:
	var rows: Array = []
	for a in acc:
		var row := {
			"board": a.board, "runs": a.runs,
			"clear": float(a.clears) / a.runs if a.runs > 0 else 0.0,
			"hpLost": a.hp / a.runs if a.runs > 0 else 0.0,
			"danger": a.dangerT / a.waveT if a.waveT > 0.0 else 0.0,
		}
		for k in a.extra:
			row[k] = a.extra[k] / maxf(1.0, a.runs)
		rows.append(row)
	return {"skill": skill, "mode": mode, "strategy": strategy, "rows": rows, "seconds": seconds}


static func format_table(results: Array) -> String:
	var lines: PackedStringArray = []
	for r in results:
		lines.append("\n%s / %s on %s (%.1f s)" % [r.skill.to_upper(), r.strategy, r.mode, r.seconds])
		lines.append("board | runs | clear | base HP lost | danger")
		for row in r.rows:
			lines.append("  %d   |  %2d  | %4d%% |    %4d%%     | %4d%%" % [row.board, row.runs, roundi(row.clear * 100), roundi(row.hpLost * 100), roundi(row.danger * 100)])
	return "\n".join(lines)


static func run_cli(args: PackedStringArray) -> void:
	if args.has("--boards"):
		max_boards = int(args[args.find("--boards") + 1])
	var arg := func(k: String, d: String) -> String:
		var i := args.find("--" + k)
		return args[i + 1] if i >= 0 and i + 1 < args.size() else d
	var n := int(arg.call("seeds", "6"))
	var mode: String = arg.call("mode", "normal")
	var skills: PackedStringArray = arg.call("skill", "novice,average,expert").split(",")
	var strategies: PackedStringArray = arg.call("strategy", "standard").split(",")
	var seeds: Array = []
	for i in n:
		seeds.append(1000 + i * 7919)
	# child process: one seed, write its accumulator to a file
	if args.has("--single"):
		var acc1 := empty_acc()
		run_seed(acc1, arg.call("skill", "average"), mode, int(arg.call("seed", "1000")), arg.call("strategy", "standard"), false)
		var f1 := FileAccess.open(arg.call("out", "user://acc.json"), FileAccess.WRITE)
		f1.store_string(JSON.stringify(acc1))
		return
	var jobs := int(arg.call("jobs", str(maxi(1, OS.get_processor_count()))))
	var results: Array = []
	var t0 := Time.get_ticks_msec()
	for st in strategies:
		for s in skills:
			var t1 := Time.get_ticks_msec()
			var acc: Array
			if jobs <= 1:
				acc = empty_acc()
				for seed in seeds:
					run_seed(acc, s, mode, seed, st, args.has("--verbose"))
			else:
				acc = _run_parallel(s, mode, st, seeds, jobs)
			results.append(summarize(acc, s, mode, st, (Time.get_ticks_msec() - t1) / 1000.0))
			printerr("%s / %s done (%.0f s total)" % [s, st, (Time.get_ticks_msec() - t0) / 1000.0])
	print(format_table(results))
	if args.has("--json"):
		var dir := "res://../reports"
		DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(dir))
		var path := ProjectSettings.globalize_path(dir) + "/harness-%s-%d.json" % [mode, int(Time.get_unix_time_from_system())]
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(results, "  "))
			print("JSON written to ", path)
		print(JSON.stringify(results))


static func _run_parallel(skill: String, mode: String, strategy: String, seeds: Array, jobs: int) -> Array:
	var exe := OS.get_executable_path()
	var proj := ProjectSettings.globalize_path("res://")
	var tmp := OS.get_cache_dir() + "/std-harness"
	DirAccess.make_dir_recursive_absolute(tmp)
	var acc := empty_acc()
	var queue: Array = seeds.duplicate()
	var running := {}
	while not queue.is_empty() or not running.is_empty():
		while running.size() < jobs and not queue.is_empty():
			var seed: int = queue.pop_front()
			var out := "%s/%s-%s-%s-%d.json" % [tmp, skill, strategy, mode, seed]
			if FileAccess.file_exists(out):
				DirAccess.remove_absolute(out)
			var pid := OS.create_process(exe, ["--headless", "--path", proj, "--", "--bots", "--single", "--skill", skill, "--strategy", strategy, "--mode", mode, "--seed", str(seed), "--out", out])
			running[pid] = out
		OS.delay_msec(200)
		for pid in running.keys():
			if not OS.is_process_running(pid):
				var out2: String = running[pid]
				running.erase(pid)
				var txt := FileAccess.get_file_as_string(out2)
				var data: Variant = JSON.parse_string(txt)
				if data is Array:
					merge_acc(acc, data)
				else:
					printerr("harness child failed: ", out2)
	return acc
