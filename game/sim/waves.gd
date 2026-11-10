class_name Waves
extends RefCounted
## Wave composition: Fibonacci counts, packs of one form/element/tier, the HP budget and champions.
## An enemy spec is a Dictionary {size, suit, arch, ability, element, group, tier, golden, boss, champion, pack, special}.

const SUITS: Array[String] = ["hearts", "diamonds", "clubs", "spades"]
const SUIT_SYMBOL := {"hearts": "♥", "diamonds": "♦", "clubs": "♣", "spades": "♠"}


static func dominant_suit(seed: int, b: int) -> String:
	return Rng.new(Rng.sub_seed(seed, [606, b])).pick(SUITS)


static func tension(b: int, i: int) -> float:
	var w := Bal.WAVES_PER_BOARD[b - 1]
	if w == 1:
		var single: Array = Bal.TENSION.single
		return single[b - 1] if b - 1 < single.size() else 0.9
	var t: float = Bal.TENSION.start + (Bal.TENSION.end - Bal.TENSION.start) * (i - 1) / float(w - 1)
	var spikes: Array = Bal.TENSION.spikes
	if i != w and spikes.has(i):
		t *= Bal.TENSION.spike
	elif i != w and spikes.has(i - 1):
		t *= Bal.TENSION.exhale
	return t


static func wave_count(b: int, i: int) -> Dictionary:
	var rung := mini(Bal.WAVE_LADDER.size() - 1, b / 2 + (i - 1) / 3)
	var count := Bal.WAVE_LADDER[rung]
	var k := -1
	for j in range(2, Bal.FIB.size()):
		if Bal.FIB[j] == count:
			k = j
			break
	return {"count": count, "split": [Bal.FIB[k - 1], Bal.FIB[k - 3], Bal.FIB[k - 4]]}


static func hp_budget(b: int, i: int, mode: String) -> float:
	var s := Bal.BOARD_START_PIECES[b - 1]
	return Bal.H_B[b - 1] * pow(s + (i - 1) * Bal.PIECES_PER_WAVE_CYCLE, Bal.HP_ALPHA) / pow(5.0, Bal.HP_ALPHA - 1.0) * tension(b, i) * float(Bal.MODES[mode].hp)


## Element groups a pack may carry on board b.
static func groups_for(b: int) -> Array[String]:
	var out: Array[String] = []
	for g in Bal.GROUPS:
		if g != "nonmetal" and Bal.GROUPS[g].fromBoard <= b:
			out.append(g)
	return out


static func has_champion(b: int, i: int) -> bool:
	if b < Bal.CHAMPION.fromBoard:
		return false
	var w := Bal.WAVES_PER_BOARD[b - 1]
	for x in Bal.CHAMPION.waves[b - 1]:
		if (w if x == 0 else x) == i:
			return true
	return false


## HP weight of one monster inside the wave budget.
static func hp_weight(e: Dictionary) -> float:
	return float(Bal.SIZES[e.size].hp) * Bal.TIER_HP[e.tier - 1] * (Bal.ABILITIES.growerHp if e.ability == "post" else 1.0)


static func spec(size: String, suit: String, arch: String, ability: String, element: String, group: String, tier: int, golden: bool, pack: int) -> Dictionary:
	return {"size": size, "suit": suit, "arch": arch, "ability": ability, "element": element, "group": group, "tier": tier, "golden": golden, "boss": false, "champion": false, "pack": pack, "special": ""}


static func make_wave(seed: int, b: int, i: int, mode: String) -> Dictionary:
	var rng := Rng.new(Rng.sub_seed(seed, [505, b, i]))
	var wc := wave_count(b, i)
	var count: int = wc.count
	var split: Array = wc.split
	var dominant := dominant_suit(seed, b)
	var sizes: Array = []
	for _k in split[0]:
		sizes.append("small")
	for _k in split[1]:
		sizes.append("medium")
	for _k in split[2]:
		sizes.append("large")
	rng.shuffle(sizes)
	# larger monsters drift toward later packs (JS sort with a noisy comparator: emulate with keyed noise)
	var keyed: Array = []
	for s in sizes:
		keyed.append({"s": s, "k": float(Bal.SIZES[s].hp) + (rng.next() - 0.5) * 1.6})
	keyed.sort_custom(func(a, z): return a.k < z.k)
	sizes.clear()
	for x in keyed:
		sizes.append(x.s)
	var packs: Array = []
	var left := sizes.size()
	var at := 0
	var k := 0
	while left > 0:
		var n := mini(left, Bal.BURSTS[mini(k, Bal.BURSTS.size() - 1)])
		packs.append(sizes.slice(at, at + n))
		at += n
		left -= n
		k += 1
	var archs: Array = Bal.ARCHETYPES_BY_BOARD[b - 1]
	var groups := groups_for(b)
	var odds: Array = Bal.TIER_ODDS[b - 1]
	var enemies: Array = []
	for pi in packs.size():
		var pack: Array = packs[pi]
		var all_small := true
		for s in pack:
			if s != "small":
				all_small = false
		var mites := all_small and pack.size() >= 2 and rng.chance(Bal.MITE_SHARE[b - 1])
		var forms: Array = archs
		if mites:
			forms = Bal.MITE_FORMS.filter(func(f): return archs.has(f))
		var arch: String = rng.pick(forms if not forms.is_empty() else archs)
		var ability := ""
		if not groups.is_empty() and rng.chance(Bal.ABILITIES.chanceByBoard[b - 1]):
			ability = rng.pick(groups)
		var group := ability if ability != "" else "nonmetal"
		var element: String = rng.pick(Bal.GROUPS[group].symbols)
		var r := rng.next()
		var tier := 1
		for t in 4:
			r -= odds[t]
			if r <= 0.0:
				tier = t + 1
				break
		var suit: String = dominant if rng.chance(Bal.DOMINANT_SHARE) else rng.pick(SUITS)
		for size in pack:
			var nn := Bal.MITES_PER_SMALL if mites else 1
			for _q in nn:
				enemies.append(spec("mite" if mites else size, suit, arch, ability, element, group, tier, rng.chance(Bal.ABILITIES.goldenChance), pi))
	if b >= Bal.ARCH.balloonFromBoard:
		var nb: int = count / Bal.ARCH.balloonEvery
		for e in enemies:
			if nb > 0 and e.size == "small" and e.arch != "balloon":
				e.arch = "balloon"
				nb -= 1
	if b >= Bal.ARCH.walkerFromBoard:
		var nw: int = count / Bal.ARCH.walkerEvery
		for e in enemies:
			if nw > 0 and e.size == "large":
				e.size = "giant"
				e.arch = "walker"
				nw -= 1
	var last := packs.size()
	if has_champion(b, i):
		var ab := ""
		if not groups.is_empty():
			ab = rng.pick(groups)
		var grp := ab if ab != "" else "nonmetal"
		var cand: Array = archs.filter(func(a): return a != "crawler")
		var ch := spec("champion", dominant, rng.pick(cand), ab, rng.pick(Bal.GROUPS[grp].symbols), grp, 4, false, last)
		ch.champion = true
		enemies.append(ch)
	if b == 7 and i == Bal.WAVES_PER_BOARD[6]:
		var boss := spec("boss", dominant, "nautilus", "", "Og", "nonmetal", 4, false, last + 1)
		boss.boss = true
		enemies.append(boss)
	var bursts: Array[int] = []
	for e in enemies:
		while bursts.size() <= e.pack:
			bursts.append(0)
		bursts[e.pack] += 1
	var budget := hp_budget(b, i, mode)
	var sum_hp := 0.0
	for e in enemies:
		sum_hp += hp_weight(e)
	var nonzero: Array[int] = []
	for x in bursts:
		if x > 0:
			nonzero.append(x)
	return {
		"board": b, "index": i, "count": count, "split": split, "enemies": enemies, "bursts": nonzero,
		"budget": budget, "unitHp": budget / sum_hp, "dominant": dominant,
	}
