class_name Cards
extends RefCounted
## Rogue-lite card draws (section 14). A draw deals 5 face-down cards whose backs show the
## category. The player turns over 1 (x4), 2 (x2) or 3 (x1). Effects stack for the run.
## fx[id] holds the summed multiplier of every copy taken; count cards also add to cnt[id].
## Attachments go to a hand and are mounted on towers (one per story).

var fx := {}  ## card id -> summed multiplier (1, 2 or 4 per copy)
var cnt := {}  ## count card id -> summed count (1, 2 or 3 per copy)
var pairs: Array = []  ## Prism Balance colour pairs [{a, b, m}]
var hand: Array = []  ## attachments waiting to be mounted [{id, m}]
var draws := 0
var pending := false  ## a draw is waiting for the player
var deal: Array = []  ## current deal [{id, cat, rarity, pair?}]
var peeked: Array = []  ## indices peeked with Pearls
var shuffles := 0
var blood_moon := false  ## next draw: 7 cards, 4 flips
var taken_log: Array = []  ## [{id, m}] for the run summary


func f(id: String) -> float:
	return float(fx.get(id, 0.0))


func n(id: String) -> int:
	return int(cnt.get(id, 0))


static func value(id: String, m: int) -> float:
	return float(Bal.CARDS[id].get("v", 0.0)) * m


static func count_of(m: int) -> int:
	return int(Bal.CARD_COUNT.get(m, 1))


## Face text with the value after the multiplier.
static func face(c: Dictionary, m: int) -> String:
	var def: Dictionary = Bal.CARDS[c.id]
	var v := value(c.id, m)
	var t: String = def.fmt
	t = t.replace("{p}", "%d%%" % roundi(v * 100.0))
	t = t.replace("{p2}", "%d%%" % roundi(0.05 * m * 100.0))
	t = t.replace("{p3}", "%d%%" % roundi(0.08 * m * 100.0))
	t = t.replace("{p4}", "%d%%" % roundi(0.08 * m * 100.0))
	t = t.replace("{s}", "%.2g" % v)
	t = t.replace("{c}", "%.1f" % v)
	t = t.replace("{n}", str(count_of(m)))
	t = t.replace("{hp}", str(13 * m))
	t = t.replace("{every}", str(golden_every(count_of(m))))
	if c.has("pair"):
		t = t.replace("{pair}", "%s and %s" % [c.pair[0], c.pair[1]])
	return t


static func golden_every(count: int) -> int:
	return 13 if count <= 1 else (8 if count == 2 else 5)


# ---------------------------------------------------------------- the draw
func want_draw(run_waves: int, board_cleared: bool) -> bool:
	return board_cleared or (run_waves > 0 and run_waves % Bal.CARD_DRAW_EVERY == 0)


func start_draw(g) -> void:
	draws += 1
	pending = true
	peeked = []
	shuffles = 0
	_deal(g)
	g.events.append({"t": "cardDraw", "n": deal.size()})


func _deal(g) -> void:
	var rng := Rng.new(Rng.sub_seed(g.seed, [1212, draws, shuffles]))
	var ids: Array = Bal.CARDS.keys()
	var by_rarity := {"common": [], "uncommon": [], "rare": []}
	for id in ids:
		by_rarity[Bal.CARDS[id].rarity].append(id)
	deal = []
	var k: int = 7 if blood_moon else Bal.CARD_DEAL
	for _i in k:
		var r := rng.next()
		var rar := "common" if r < Bal.CARD_RARITY.common else ("uncommon" if r < Bal.CARD_RARITY.common + Bal.CARD_RARITY.uncommon else "rare")
		var id: String = rng.pick(by_rarity[rar])
		var c := {"id": id, "cat": Bal.CARDS[id].cat, "rarity": rar}
		if id == "prism":
			var cols: Array = Pieces.COLORS.duplicate()
			var a: String = rng.pick(cols)
			cols.erase(a)
			c["pair"] = [a, rng.pick(cols)]
		deal.append(c)


func max_flips() -> int:
	return 4 if blood_moon else 3


func peek(g, i: int) -> String:
	if not pending or i < 0 or i >= deal.size() or peeked.has(i):
		return "Nothing to peek"
	if int(g.base.pearls) < Bal.CARD_PEEK_PEARLS:
		return "Needs %d Pearl" % Bal.CARD_PEEK_PEARLS
	g.base.pearls = int(g.base.pearls) - Bal.CARD_PEEK_PEARLS
	peeked.append(i)
	return ""


func reshuffle(g) -> String:
	if not pending:
		return "No draw"
	if int(g.base.pearls) < Bal.CARD_SHUFFLE_PEARLS:
		return "Needs %d Pearls" % Bal.CARD_SHUFFLE_PEARLS
	g.base.pearls = int(g.base.pearls) - Bal.CARD_SHUFFLE_PEARLS
	shuffles += 1
	peeked = []
	_deal(g)
	g.events.append({"t": "cardShuffle"})
	return ""


## Turn over the chosen cards. Returns the taken cards [{id, m, ...}] or [] on a bad choice.
func take(g, picks: Array) -> Array:
	if not pending or picks.is_empty() or picks.size() > max_flips():
		return []
	var m: int = Bal.CARD_MULT[picks.size()]
	var out: Array = []
	var was_blood := blood_moon
	blood_moon = false
	for i in picks:
		if int(i) < 0 or int(i) >= deal.size():
			continue
		var c: Dictionary = deal[int(i)].duplicate()
		c["m"] = m
		_apply(g, c)
		out.append(c)
	var missed: Array = []
	for i in deal.size():
		if not picks.has(i):
			missed.append(deal[i])
	pending = false
	deal = []
	g.events.append({"t": "cardsTaken", "cards": out, "missed": missed, "blood": was_blood})
	g._rebuild_all()
	return out


func _apply(g, c: Dictionary) -> void:
	var id: String = c.id
	var m: int = c.m
	taken_log.append({"id": id, "m": m})
	if Bal.CARDS[id].cat == "attachment":
		hand.append({"id": id, "m": m})
		return
	if id == "prism":
		pairs.append({"a": c.pair[0], "b": c.pair[1], "m": m})
		return
	fx[id] = f(id) + m
	if Bal.CARDS[id].get("count", false) or id == "lancemastery":
		cnt[id] = n(id) + count_of(m)
	match id:
		"glasscannon":
			g.base["integrityPenalty"] = int(g.base.get("integrityPenalty", 0)) + 5
			g.integrity -= 5
		"bloodmoon":
			blood_moon = true
			g.base["hpBoostBoard"] = g.board_no + 1
		"civicpride":
			for t in g.towns.list:
				t.hp += 13.0 * m


## Mount an attachment from the hand on a tower (one per story).
func mount(g, hand_i: int, t: SimTower) -> String:
	if hand_i < 0 or hand_i >= hand.size():
		return "No attachment"
	if t == null or t.type == "" or t.base_tower:
		return "Pick a tower"
	if t.attach.size() >= free_slots_total(t):
		return "No free slot (one per story)"
	t.attach.append(hand[hand_i])
	hand.remove_at(hand_i)
	g._rebuild_tower(t)
	g.events.append({"t": "attach", "id": t.attach.back().id, "tower": t.id, "x": t.cx, "y": t.cy})
	return ""


static func free_slots_total(t: SimTower) -> int:
	return int(t.stats.get("stories", 1))


# ---------------------------------------------------------------- tower stats
static func majority(t: SimTower) -> String:
	var counts := {}
	for p in t.pieces:
		var c: String = p.piece.color
		counts[c] = counts.get(c, 0) + 1
	var best := ""
	var bn := 0
	for c in counts:
		if counts[c] > bn:
			bn = counts[c]
			best = c
	return best


static func has_colour(t: SimTower, col: String) -> bool:
	for p in t.pieces:
		if p.piece.color == col:
			return true
	return false


## Attachment multiplier sums on a tower.
static func att(t: SimTower, id: String) -> int:
	var s := 0
	for a in t.attach:
		if a.id == id:
			s += int(a.m)
	return s


static func att_count(t: SimTower, id: String) -> int:
	var s := 0
	for a in t.attach:
		if a.id == id:
			s += count_of(int(a.m))
	return s


## Card perks on freshly computed stats (after evolutions).
func apply(t: SimTower) -> void:
	if t.stats.is_empty():
		return
	var s := t.stats
	var col := majority(t)
	s["cardColour"] = col
	var dmg := 1.0
	var rate := 1.0
	var rng := 1.0
	var stories: int = int(s.stories)
	dmg *= 1.0 + 0.04 * f("tallorder") * stories
	dmg *= 1.0 + 0.25 * f("glasscannon")
	if col == "red":
		rate *= 1.0 + 0.10 * f("forge")
	for pr in pairs:
		if has_colour(t, pr.a) and has_colour(t, pr.b):
			dmg *= 1.0 + 0.10 * pr.m
	if col == "gold":
		s.chain = int(s.chain) + n("ricochet")
	dmg *= 1.0 + 0.15 * att(t, "overcharger")
	dmg *= 1.0 + 0.15 * att(t, "dronepod")
	dmg *= 1.0 + 0.5 * att_count(t, "twin")
	var kind: String = Bal.TOWERS[t.type].kind if Bal.TOWERS.has(t.type) else ""
	if kind == "beam":
		dmg *= 1.0 + 0.6 * att_count(t, "splitter")
	rate *= 1.0 + 0.12 * att(t, "coolant")
	rng *= 1.0 + 0.12 * att(t, "scope")
	s.critChance = float(s.critChance) + 0.05 * att(t, "scope")
	s.chain = int(s.chain) + att_count(t, "tesla")
	s["turnMult"] = 1.0 + 0.5 * att(t, "gyro")
	s["gyro"] = 0.08 * att(t, "gyro")
	s["spotter"] = att(t, "spotter") > 0
	s["airBonus"] = 0.10 * att(t, "spotter")
	s["seismic"] = 0.2 * att(t, "seismic")
	s["shrapnel"] = 0.20 * att(t, "shrapnel")
	s["afterburn"] = 0.30 * att(t, "afterburn")
	s.damage *= dmg
	s.dps *= dmg * rate
	s.interval /= rate
	s.range *= rng


# ---------------------------------------------------------------- save
func serialize() -> Dictionary:
	return {"fx": fx.duplicate(), "cnt": cnt.duplicate(), "pairs": pairs.duplicate(true), "hand": hand.duplicate(true), "draws": draws,
		"blood": blood_moon, "log": taken_log.duplicate(true)}


func load_data(d: Dictionary) -> void:
	if d.is_empty():
		return
	fx = d.fx.duplicate()
	cnt = d.cnt.duplicate()
	pairs = d.pairs.duplicate(true)
	hand = d.hand.duplicate(true)
	draws = int(d.draws)
	blood_moon = d.get("blood", false)
	taken_log = d.get("log", []).duplicate(true)
	pending = false
	deal = []
