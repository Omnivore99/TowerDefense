class_name Towers
extends RefCounted
## Tower recipes, shape analysis and stat computation (ported from v1.1 towers.ts).
## A placed piece is a Dictionary: {piece, cells: Array[Vector2i], layer}.

const PAIR := {
	"Hook": {"Block": "Gun", "Bar": "Rifle", "Tee": "Machine Gun", "Skew": "Machine Gun"},
	"Block": {"Hook": "Missile", "Bar": "Missile", "Tee": "Bomb", "Skew": "Bomb"},
	"Bar": {"Hook": "Laser", "Block": "Laser", "Tee": "Lightning", "Skew": "Pulsar"},
	"Tee": {"Hook": "Freezer", "Block": "E-Field", "Bar": "E-Field", "Skew": "Freezer"},
	"Skew": {"Hook": "Flamer", "Block": "Acid", "Bar": "Flamer", "Tee": "Virus"},
}
const PURE := {"Hook": "Machine Gun", "Block": "Bomb", "Bar": "Pulsar", "Tee": "Freezer", "Skew": "Acid"}
const TRIPLE := {
	"Hook+Block+Bar": "Rifle", "Hook+Block+Tee": "Missile", "Hook+Block+Skew": "Virus",
	"Hook+Bar+Tee": "Lightning", "Hook+Bar+Skew": "Pulsar", "Hook+Tee+Skew": "Gun",
	"Block+Bar+Tee": "E-Field", "Block+Bar+Skew": "Bomb", "Block+Tee+Skew": "Acid", "Bar+Tee+Skew": "Laser",
}
const FIB_UNIQ: Array[int] = [1, 2, 3, 5, 8, 13, 21, 34, 55, 89, 144]


## Resolve golden wildcards: they take the most common real family among the others.
static func resolve_families(pieces: Array) -> Array[String]:
	var real: Array[String] = []
	for p in pieces:
		if not p.golden:
			real.append(Pieces.family_of(p))
	var wild := "Hook"
	if not real.is_empty():
		var counts := {}
		for f in real:
			counts[f] = counts.get(f, 0) + 1
		wild = real[0]
		for f in real:
			if counts[f] > counts[wild]:
				wild = f
	var out: Array[String] = []
	for p in pieces:
		out.append(wild if p.golden else Pieces.family_of(p))
	return out


static func recipe(fams: Array[String]) -> Dictionary:
	var a := fams[0]
	var b := fams[1]
	var c := fams[2]
	if a == b and b == c:
		return {"type": PURE[a], "pure": true, "hint": "3 %s = %s ★" % [a, PURE[a]]}
	if a == b or a == c or b == c:
		var pair := a if (a == b or a == c) else b
		var odd := ""
		for f in fams:
			if f != pair:
				odd = f
		var t: String = PAIR[pair][odd]
		return {"type": t, "pure": false, "hint": "2 %s + %s = %s" % [pair, odd, t]}
	var sorted := fams.duplicate()
	sorted.sort_custom(func(x, y): return Pieces.FAMILIES.find(x) < Pieces.FAMILIES.find(y))
	var key := "+".join(sorted)
	return {"type": TRIPLE[key], "pure": false, "hint": "%s = %s" % [key.replace("+", " + "), TRIPLE[key]]}


## Every recipe for the recipe book: {fams, type, pure, hint}.
static func all_recipes() -> Array:
	var out: Array = []
	var F := Pieces.FAMILIES
	for f in F:
		var fams: Array[String] = [f, f, f]
		var r := recipe(fams)
		r.fams = fams
		out.append(r)
	for p in F:
		for o in F:
			if p != o:
				var fams2: Array[String] = [p, p, o]
				var r2 := recipe(fams2)
				r2.fams = fams2
				out.append(r2)
	for i in 5:
		for j in range(i + 1, 5):
			for k in range(j + 1, 5):
				var fams3: Array[String] = [F[i], F[j], F[k]]
				var r3 := recipe(fams3)
				r3.fams = fams3
				out.append(r3)
	return out


## Shape of a footprint: {w, h, cells, holes, golden, mirror, rotational, perfect, surface}.
static func analyse_shape(cells: Array) -> Dictionary:
	var x0 := 99999
	var y0 := 99999
	var x1 := -99999
	var y1 := -99999
	for c in cells:
		x0 = mini(x0, c.x)
		y0 = mini(y0, c.y)
		x1 = maxi(x1, c.x)
		y1 = maxi(y1, c.y)
	var w := x1 - x0 + 1
	var h := y1 - y0 + 1
	var set := {}
	for c in cells:
		set[(c.y - y0) * 64 + (c.x - x0)] = true
	var has := func(x: int, y: int) -> bool: return x >= 0 and y >= 0 and x < 64 and set.has(y * 64 + x)
	# holes: empty cells in the bbox not reachable from outside
	var outside := {}
	var q: Array[Vector2i] = []
	for x in range(-1, w + 1):
		q.append(Vector2i(x, -1))
		q.append(Vector2i(x, h))
	for y in range(0, h):
		q.append(Vector2i(-1, y))
		q.append(Vector2i(w, y))
	for p in q:
		outside[(p.y + 1) * 80 + (p.x + 1)] = true
	while not q.is_empty():
		var p: Vector2i = q.pop_back()
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var nx: int = p.x + d.x
			var ny: int = p.y + d.y
			if nx < -1 or ny < -1 or nx > w or ny > h:
				continue
			var k := (ny + 1) * 80 + (nx + 1)
			if outside.has(k) or has.call(nx, ny):
				continue
			outside[k] = true
			q.append(Vector2i(nx, ny))
	var holes: Array[Vector2i] = []
	for y in h:
		for x in w:
			if not has.call(x, y) and not outside.has((y + 1) * 80 + (x + 1)):
				holes.append(Vector2i(x + x0, y + y0))
	var mx := true
	var my := true
	var rot := true
	var perim := 0
	for key in set:
		var x: int = key % 64
		var y: int = key / 64
		if not has.call(w - 1 - x, y):
			mx = false
		if not has.call(x, h - 1 - y):
			my = false
		if not has.call(w - 1 - x, h - 1 - y):
			rot = false
		if not has.call(x + 1, y):
			perim += 1
		if not has.call(x - 1, y):
			perim += 1
		if not has.call(x, y + 1):
			perim += 1
		if not has.call(x, y - 1):
			perim += 1
	var ratio := float(maxi(w, h)) / float(mini(w, h))
	var min_perim := 2 * ceili(2.0 * sqrt(cells.size()))
	var surface := clampf((float(perim) / min_perim - 1.2) * 0.35, -Bal.SHAPE.surfaceMax, Bal.SHAPE.surfaceMax)
	return {
		"w": w, "h": h, "cells": cells.size(), "holes": holes,
		"golden": ratio >= Bal.SHAPE.goldenMin and ratio <= Bal.SHAPE.goldenMax,
		"mirror": mx or my, "rotational": rot, "perfect": set.size() == w * h and cells.size() >= 4,
		"surface": surface,
	}


static func is_fib_spire(counts: Array) -> bool:
	if counts.size() < 3:
		return false
	for i in counts.size() - 1:
		var a := FIB_UNIQ.find(counts[i])
		var b := FIB_UNIQ.find(counts[i + 1])
		if a < 0 or b < 0 or a != b + 1:
			return false
	return true


static func majority_color(pieces: Array) -> Dictionary:
	var counts := {"red": 0, "gold": 0, "green": 0, "blue": 0}
	var wild := 0
	for p in pieces:
		if p.golden:
			wild += 1
		else:
			counts[p.color] += 1
	var sorted: Array = ["red", "gold", "green", "blue"]
	sorted.sort_custom(func(a, b): return counts[a] > counts[b])
	var top: String = sorted[0]
	var color := top if counts[top] + wild > counts[sorted[1]] else ""
	var non_zero: Array = sorted.filter(func(c): return counts[c] > 0)
	var resonance: String = non_zero[0] if (pieces.size() >= 3 and non_zero.size() == 1) else ""
	return {"color": color, "resonance": resonance}


static func bbox(cells: Array) -> Rect2i:
	var x0 := 99999
	var y0 := 99999
	var x1 := -99999
	var y1 := -99999
	for c in cells:
		x0 = mini(x0, c.x)
		y0 = mini(y0, c.y)
		x1 = maxi(x1, c.x)
		y1 = maxi(y1, c.y)
	return Rect2i(x0, y0, x1 - x0, y1 - y0)


static func tower_families(t: SimTower) -> Array[String]:
	var core: Array = []
	for p in t.pieces:
		if p.layer == 0 and not Pieces.is_cap(p.piece.kind):
			core.append(p.piece)
			if core.size() == 3:
				break
	return resolve_families(core)


## Stats for a tower. ctx: {powerStation: float, goldenBase: bool, storyDamage: float, mods: Dictionary}.
static func compute_stats(t: SimTower, ctx: Dictionary) -> Dictionary:
	if t.type == "":
		return {}
	var def: Dictionary = Bal.TOWERS[t.type]
	var ground_core := 0
	var ground_caps := 0
	var extra_pieces: Array = []
	for p in t.pieces:
		if p.layer != 0:
			continue
		if Pieces.is_cap(p.piece.kind):
			ground_caps += 1
		else:
			ground_core += 1
			if ground_core > 3:
				extra_pieces.append(p.piece)
	var fams := tower_families(t)
	var rec := recipe(fams)
	var pure: bool = rec.pure
	var shape := analyse_shape(t.layers[0])
	var bonuses: Array = []

	var n := maxf(3.0, ground_core + 0.5 * ground_caps)
	var mass := pow(n / 3.0, Bal.MASS_EXP)
	var dmg := mass
	var rate := 1.0
	var range_mul := 1.0
	var slow_trait := 0.0
	var dot_trait := 0.0
	for f in resolve_families(extra_pieces):
		match f:
			"Hook": rate += Bal.TRAITS.Hook
			"Block": dmg *= 1.0 + Bal.TRAITS.Block
			"Bar": range_mul += Bal.TRAITS.Bar
			"Tee": slow_trait += Bal.TRAITS.Tee
			"Skew": dot_trait += Bal.TRAITS.Skew
	if n > 3:
		bonuses.append({"key": "mass", "label": "Mass ×%.2f" % mass, "good": true})
	var nh: int = shape.holes.size()
	if nh > 0:
		dmg *= maxf(0.3, 1.0 + Bal.SHAPE.hole * nh)
		bonuses.append({"key": "holes", "label": "%d hole%s −%d%% damage" % [nh, "s" if nh > 1 else "", nh * 10], "good": false})
	if shape.golden:
		range_mul += Bal.SHAPE.golden
		bonuses.append({"key": "golden", "label": "Golden footprint +10% range", "good": true})
	if shape.mirror:
		rate += Bal.SHAPE.mirror
		bonuses.append({"key": "mirror", "label": "Mirror symmetry +15% rate", "good": true})
	if shape.rotational:
		dmg *= 1.0 + Bal.SHAPE.rotational
		bonuses.append({"key": "rot", "label": "Rotational symmetry +15% damage", "good": true})
	if shape.perfect:
		dmg *= 1.0 + Bal.SHAPE.perfect
		rate += Bal.SHAPE.perfect
		range_mul += Bal.SHAPE.perfect
		bonuses.append({"key": "perfect", "label": "Perfect Block +25% everything", "good": true})
	rate += shape.surface
	if absf(shape.surface) > 0.01:
		bonuses.append({"key": "surface", "label": "Surface %s%d%% rate" % ["+" if shape.surface > 0 else "−", roundi(absf(shape.surface) * 100)], "good": shape.surface > 0})

	var stories := mini(Bal.MAX_STORIES + 1, t.layers.size() + (1 if pure else 0))
	var story_dmg: float = ctx.get("storyDamage", Bal.STORY_DAMAGE)
	dmg *= pow(story_dmg, stories - 1)
	range_mul += Bal.STORY_RANGE * (stories - 1)
	if pure:
		bonuses.append({"key": "pure", "label": "Pure tower: +1 free story", "good": true})
	var counts: Array = []
	for l in t.layers:
		counts.append(l.size())
	var spire := is_fib_spire(counts)
	if spire:
		bonuses.append({"key": "spire", "label": "Fibonacci Spire: every 13th shot ×φ²", "good": true})

	var pierce := 0
	var chain := 0
	var crit := 0.0
	var slow_on_hit := 0.0
	var essence_mult := 1.0
	for p in t.pieces:
		match p.piece.glyph:
			"range": range_mul += Bal.GLYPHS.range
			"damage": dmg *= 1.0 + Bal.GLYPHS.damage
			"rate": rate += Bal.GLYPHS.rate
			"pierce": pierce += Bal.GLYPHS.pierce
			"chain": chain += Bal.GLYPHS.chain
			"crit": crit += Bal.GLYPHS.critChance
			"slow": slow_on_hit = Bal.GLYPHS.slowOnHit
			"essence": essence_mult = 2.0
	if def.energy and ctx.get("powerStation", 0.0) > 0.0:
		dmg *= 1.0 + ctx.powerStation
	if ctx.get("goldenBase", false):
		dmg *= 1.0 + Bal.GOLDEN_BASE_DAMAGE

	var all_pieces: Array = []
	for p in t.pieces:
		all_pieces.append(p.piece)
	var mc := majority_color(all_pieces)
	if mc.resonance != "":
		var txt: String = {"red": "burn splash", "gold": "ricochet to %d more" % Bal.RESONANCE.ricochet, "blue": "3-cell splash", "green": "poison spreads on kill"}[mc.resonance]
		bonuses.append({"key": "res", "label": "Resonance: " + txt, "good": true})
	var rng_cells: float = def.range * range_mul + (t.height * Bal.RISE_RANGE if t.height > 0 else 0.0)
	var interval: float = def.interval / rate
	var damage: float = def.dps * def.interval * dmg
	return {
		"damage": damage, "interval": interval, "range": rng_cells, "area": def.area, "maxTargets": def.maxTargets,
		"dps": damage / interval,
		"pierce": pierce, "chain": chain, "critChance": crit, "slowOnHit": slow_on_hit, "essenceMult": essence_mult,
		"slowTrait": slow_trait, "dotTrait": dot_trait,
		"color": mc.color, "resonance": mc.resonance,
		"spire": spire, "pure": pure, "stories": stories, "bonuses": bonuses, "shape": shape, "hint": rec.hint,
	}
