extends SceneTree
func _init() -> void:
	var g := Game.new(1000, "normal", {"tutorial": false})
	g.undo_enabled = false
	var bot := Bot.new(g, "average", 1000 ^ 0xB07)
	var tb := 0
	var ts := 0
	var steps := 0
	var maxe := 0
	while g.board_no < 6 or g.phase != "base":
		var a := Time.get_ticks_usec()
		bot.act()
		var b := Time.get_ticks_usec()
		g.step()
		var c := Time.get_ticks_usec()
		g.events.clear()
		tb += b - a
		ts += c - b
		steps += 1
		maxe = maxi(maxe, g.enemies.size())
		if g.phase == "lost":
			g.retry_board()
		if steps > 60 * 60 * 60:
			break
	print("bot %.1f s, sim %.1f s, steps %d, max enemies %d, towers %d" % [tb / 1e6, ts / 1e6, steps, maxe, g.towers.size()])
	quit()
