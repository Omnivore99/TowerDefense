extends SceneTree
## Dev probe: run an expert bot to a board and print economy and evolution state.

func _init() -> void:
	var g := Game.new(11, "normal", {"tutorial": false})
	g.undo_enabled = false
	var bot := Bot.new(g, "expert", 99)
	var last_b := 0
	for i in 60 * 60 * 40:
		bot.act()
		g.step()
		g.events.clear()
		if g.phase == "lost":
			g.retry_board()
		if g.board_no != last_b and g.phase == "calm":
			last_b = g.board_no
			var have := {}
			for h in g.harvesters:
				have[h.get("node", "ore")] = have.get(h.get("node", "ore"), 0) + 1
			var marks := [0, 0, 0, 0]
			for t in g.towers:
				if t.type != "":
					marks[t.mark - 1] += 1
			print("board %d  harv %s  forests %d lakes %d  ore %.0f timber %.0f water %.0f ess %.0f  marks %s  tech %s  pads %s belt %s traps %d" % [g.board_no, have, g.eco.forests.size(), g.eco.lakes.size(), g.base.ore, g.base.timber, g.base.water, g.base.essence, marks, g.base.tech, g.arsenal.pads.map(func(p): return p.get("kind", "")), g.arsenal.belt, g.arsenal.traps.size()])
		if g.board_no >= 5:
			break
	quit()
