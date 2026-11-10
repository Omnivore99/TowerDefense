class_name SimEnemy
extends RefCounted
## A monster in the simulation. Movement and abilities are sim state; the view adds animation.

var id := 0
var size := "small"
var suit := "hearts"
var arch := "crawler"
var ability := ""
var element := "H"
var group := "nonmetal"
var tier := 1
var golden := false
var boss := false
var champion := false
## v2 specials: leaper, sapper, raider, mirror, burrower, cloaked ("" = none).
var special := ""
var gen := 0
var hp := 0.0
var max_hp := 0.0
var shield := 0.0
var shield_max := 0.0
var lane := 0.0
var sdir := 0.0
var last_hit_t := -99.0
var summon_t := 0.0
var route: Route
var overland := false
var d := 0.0
var x := 0.0
var y := 0.0
var px := 0.0
var py := 0.0
var dir := 0.0
var speed := 0.0
var slow_t := 0.0
var slow_mult := 1.0
## DoTs: Array of Dictionaries {kind, dps, t, tower}.
var dots: Array = []
var anim_t := 0.0
var airborne := false
var stretched := false
var immune := false
var ability_t := 0.0
var herald_boost := false
var chewing := 0
var last_tower := 0
var shed := 0
var alive := true
var scale := 1.0
## Cached Bal.SIZES[size].radius (hot path).
var radius := 0.55
var hit_flash := 0.0
## Gait phase 0..1 (view uses it to drive hops and coil stretches).
var gait := 0.0
## Damage bookkeeping for the damage report: source key -> damage.
var leaked := false


func threat() -> float:
	var leak: float = Bal.SIZES[size].leak
	return hp * leak * (1.5 if (tier >= 3 or champion or boss) else 1.0)


func progress() -> float:
	return d / route.length if route.length > 0.0 else 0.0
