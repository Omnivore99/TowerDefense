class_name SimTower
extends RefCounted
## A tower in the simulation. Pieces are placed-piece Dictionaries {piece, cells, layer}.

var id: int = 0
var pieces: Array = []
## Cells per story; layers[0] is the ground footprint.
var layers: Array = []
## Terrain level the tower stands on.
var height: int = 0
var type: String = ""
var hint: String = ""
var active := false
var activate_t := 0.0
var cx := 0.0
var cy := 0.0
var stats: Dictionary = {}
var cooldown := 0.0
var target_id := 0
var angle := -PI / 2.0
var ramp_target := 0
var ramp_t := 0.0
var shots := 0
var kills := 0
var fire_flash := 0.0
var base_tower := false
var corroded := false
## Cached hot-path values (set by Game._rebuild_tower).
var air := false
var reach := 0.0
## v2 targeting (section 9.1): priority id, whether the player chose it, retarget timer.
var priority := ""
var priority_set := false
var retarget_t := 0.0
var aligned := false
## v2 evolutions (section 9.5): mark 1..4, branch -1 (none) / 0 / 1, branch mods, tech id.
var mark := 1
var branch := -1
var mods: Dictionary = {}
var tech := ""
## Damage multiplier from nearby support (Crystal Ward, Lighthouse Grid), refreshed by Game.
var aura_mult := 1.0
var evo_t := 99.0
var fire_drop_t := 0.0


func ground_count() -> int:
	var n := 0
	for p in pieces:
		if p.layer == 0:
			n += 1
	return n


func core_count() -> int:
	var n := 0
	for p in pieces:
		if p.layer == 0 and not Pieces.is_cap(p.piece.kind):
			n += 1
	return n


func copy() -> SimTower:
	var t := SimTower.new()
	t.id = id
	t.pieces = pieces.duplicate(true)
	t.layers = layers.duplicate(true)
	t.height = height
	t.type = type
	t.hint = hint
	t.active = active
	t.activate_t = activate_t
	t.cx = cx
	t.cy = cy
	t.stats = stats.duplicate(true)
	t.cooldown = cooldown
	t.target_id = target_id
	t.angle = angle
	t.shots = shots
	t.kills = kills
	t.base_tower = base_tower
	t.priority = priority
	t.priority_set = priority_set
	t.mark = mark
	t.branch = branch
	t.mods = mods.duplicate(true)
	t.tech = tech
	return t
