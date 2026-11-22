class_name Evolve
extends RefCounted
## Evolution and technology rules (section 9.5): costs, requirements, tech levels and the
## stat changes each mark and branch makes. Pure functions over base and tower state.


## Technology level 0..5 from points (levels need 1, 2, 3, 5, 8 points).
static func tech_level(points: int) -> int:
	var lv := 0
	var need := 0
	for step in Bal.TECH_LEVEL_POINTS:
		need += step
		if points >= need:
			lv += 1
	return lv


## Points still needed for the next level (0 at level 5).
static func points_to_next(points: int) -> int:
	var need := 0
	for step in Bal.TECH_LEVEL_POINTS:
		need += step
		if points < need:
			return need - points
	return 0


static func level_of(base: Dictionary, tech: String) -> int:
	var pts: Dictionary = base.get("tech", {})
	return tech_level(int(pts.get(tech, 0)))


static func size_factor(t: SimTower) -> float:
	return 1.0 + Bal.EVO.sizeFactorPerPiece * maxf(0.0, t.ground_count() - 3)


static func branches(type: String) -> Array:
	return Bal.BRANCHES.get(type, [])


static func branch_def(t: SimTower) -> Dictionary:
	var bs := branches(t.type)
	if t.branch < 0 or t.branch >= bs.size():
		return {}
	return bs[t.branch]


## The resource cost of the next mark as {res: amount}. branch picks the technology for Mk III.
static func cost(t: SimTower, branch: int) -> Dictionary:
	var f := size_factor(t)
	var out := {}
	if t.mark == 1:
		out = {"ore": ceilf(Bal.EVO.mk2.ore * f), "timber": ceilf(Bal.EVO.mk2.timber * f)}
	elif t.mark == 2 or t.mark == 3:
		var b := branch if t.mark == 2 else t.branch
		var bs := branches(t.type)
		if b < 0 or b >= bs.size():
			return {}
		var tech: String = bs[b].tech
		var res: Array = Bal.TECH_RES[tech]
		var key := "mk3" if t.mark == 2 else "mk4"
		var split: Array = Bal.EVO[key].split
		out[res[0]] = ceilf(split[0] * f)
		out[res[1]] = out.get(res[1], 0.0) + ceilf(split[1] * f)
		if t.mark == 3:
			out["pearls"] = float(Bal.EVO.mk4.pearls)
	return out


static func can_afford(base: Dictionary, c: Dictionary) -> bool:
	for k in c:
		if float(base.get(k, 0.0)) < float(c[k]) - 0.0001:
			return false
	return true


static func pay(base: Dictionary, c: Dictionary) -> void:
	for k in c:
		if k == "pearls":
			base.pearls = int(base.pearls) - int(c[k])
		else:
			base[k] = float(base[k]) - float(c[k])


## "" when the tower can take its next mark (with branch for Mk III), otherwise the reason.
static func blocked(base: Dictionary, t: SimTower, branch: int) -> String:
	if t.type == "" or t.base_tower:
		return "Not a tower"
	if t.mark >= 4:
		return "Fully evolved"
	if t.mark == 2:
		var bs := branches(t.type)
		if branch < 0 or branch >= bs.size():
			return "Pick a branch"
		if level_of(base, bs[branch].tech) < Bal.EVO.mk3.techLevel:
			return "%s is not open yet" % Bal.TECH_NAME[bs[branch].tech]
	if t.mark == 3 and level_of(base, t.tech) < Bal.EVO.mk4.techLevel:
		return "Needs %s level %d" % [Bal.TECH_NAME[t.tech], Bal.EVO.mk4.techLevel]
	if not can_afford(base, cost(t, branch)):
		return "Not enough resources"
	return ""


static func cost_text(c: Dictionary) -> String:
	var icons := {"ore": "⬢", "timber": "▮", "water": "≈", "pearls": "●", "essence": "◆"}
	var parts: Array[String] = []
	for k in ["ore", "timber", "water", "essence", "pearls"]:
		if c.has(k):
			parts.append("%d %s" % [int(c[k]), icons[k]])
	return "  ".join(parts)


## Apply mark, branch and technology perks to freshly computed stats (called from _rebuild_tower).
static func apply(t: SimTower, base: Dictionary) -> void:
	t.mods = {}
	t.tech = ""
	if t.stats.is_empty():
		return
	var s := t.stats
	var dmg := 1.0
	var rng := 1.0
	var rate := 1.0
	if t.mark >= 2:
		dmg *= Bal.EVO.mk2.dmg
		rng *= Bal.EVO.mk2.range
	var bd := branch_def(t)
	if t.mark >= 3 and not bd.is_empty():
		t.tech = bd.tech
		dmg *= Bal.EVO.mk3.dmg
		rng *= Bal.EVO.mk3.range
		t.mods = (bd.m4 if t.mark >= 4 else bd.m3).duplicate(true)
		if t.mark >= 4:
			dmg *= Bal.EVO.mk4.dmg
			rng *= Bal.EVO.mk4.range
	dmg *= float(t.mods.get("dmg", 1.0))
	rng *= float(t.mods.get("range", 1.0))
	rate *= float(t.mods.get("rate", 1.0))
	# technology perks
	var kind: String = Bal.TOWERS[t.type].kind
	if level_of(base, "steam") >= 2 and kind in ["bullet", "lob", "homing", "hitscan", "pierce"]:
		dmg *= 1.0 + Bal.TECH_PERK_DMG
	if t.tech != "":
		var lv := level_of(base, t.tech)
		dmg *= 1.0 + 0.05 * maxi(0, mini(lv, 4) - 2)
	s.damage *= dmg
	s.dps *= dmg * rate
	s.interval /= rate
	s.range *= rng
	if kind != "hitscan":
		s.pierce = int(s.pierce) + int(t.mods.get("pierce", 0))
	s.chain = int(s.chain) + int(t.mods.get("chain", 0))
	s["mark"] = t.mark
	s["tech"] = t.tech
