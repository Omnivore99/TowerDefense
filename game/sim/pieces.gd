class_name Pieces
extends RefCounted
## Piece set, orientations, families, colours, glyphs and the seeded piece stream.
## A piece is a Dictionary: {id, kind, color, glyph ("" = none), golden}.

const FAMILIES: Array[String] = ["Hook", "Block", "Bar", "Tee", "Skew"]
const COLORS: Array[String] = ["red", "gold", "green", "blue"]
const COMMON_GLYPHS: Array[String] = ["range", "damage", "rate", "pierce"]
const RARE_GLYPHS: Array[String] = ["chain", "crit", "slow", "essence"]
const GLYPH_LABEL := {
	"range": "+Range", "damage": "+Damage", "rate": "+Rate", "pierce": "+Pierce",
	"chain": "Chain", "crit": "Crit", "slow": "Slow on hit", "essence": "Double Essence",
}
const SHAPES := {
	"I": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(3, 0)],
	"O": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(0, 1), Vector2i(1, 1)],
	"T": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0), Vector2i(1, 1)],
	"S": [Vector2i(1, 0), Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1)],
	"Z": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(1, 1), Vector2i(2, 1)],
	"J": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)],
	"L": [Vector2i(2, 0), Vector2i(0, 1), Vector2i(1, 1), Vector2i(2, 1)],
	"c1": [Vector2i(0, 0)],
	"c2": [Vector2i(0, 0), Vector2i(1, 0)],
	"c3": [Vector2i(0, 0), Vector2i(1, 0), Vector2i(2, 0)],
	"cL": [Vector2i(0, 0), Vector2i(0, 1), Vector2i(1, 1)],
}
const FAMILY_OF := {"I": "Bar", "O": "Block", "T": "Tee", "S": "Skew", "Z": "Skew", "J": "Hook", "L": "Hook"}
const KINDS_OF_FAMILY := {"Hook": ["J", "L"], "Block": ["O"], "Bar": ["I"], "Tee": ["T"], "Skew": ["S", "Z"]}
const CAP_KINDS: Array[String] = ["c1", "c2", "c3", "cL"]


static func is_cap(kind: String) -> bool:
	return kind.begins_with("c")


static func family_of(p: Dictionary) -> String:
	if is_cap(p.kind):
		return ""
	return FAMILY_OF[p.kind]


static func make(id: int, kind: String, color: String, glyph: String = "", golden: bool = false) -> Dictionary:
	return {"id": id, "kind": kind, "color": color, "glyph": glyph, "golden": golden}


## rot = clockwise quarter turns, mirror flag. Returns cells normalised to the origin.
static func orient_cells(kind: String, rot: int, mirror: bool) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for c in SHAPES[kind]:
		cells.append(Vector2i(-c.x if mirror else c.x, c.y))
	var r := ((rot % 4) + 4) % 4
	for _i in r:
		for k in cells.size():
			cells[k] = Vector2i(-cells[k].y, cells[k].x)
	var mx := 999
	var my := 999
	for c in cells:
		mx = mini(mx, c.x)
		my = mini(my, c.y)
	for k in cells.size():
		cells[k] = Vector2i(cells[k].x - mx, cells[k].y - my)
	return cells


## Cells of a piece placed so the cursor cell sits near the piece centre.
static func placed_cells(kind: String, rot: int, mirror: bool, cx: int, cy: int) -> Array[Vector2i]:
	var cells := orient_cells(kind, rot, mirror)
	var w := 0
	var h := 0
	for c in cells:
		w = maxi(w, c.x + 1)
		h = maxi(h, c.y + 1)
	var ox := cx - floori((w - 1) / 2.0)
	var oy := cy - floori((h - 1) / 2.0)
	for k in cells.size():
		cells[k] = Vector2i(cells[k].x + ox, cells[k].y + oy)
	return cells


## Seeded piece stream. Each board gets its own stream so a seed reproduces the pieces.
class Stream:
	extends RefCounted
	var rng: Rng
	var next_id: int
	## Shape Factory: force the next core piece family ("" = none).
	var forced_family := ""

	func _init(seed_value: int, id_base: int = 1) -> void:
		rng = Rng.new(seed_value)
		next_id = id_base

	func next() -> Dictionary:
		# Roll every random value in a fixed order so forcing a family never shifts the stream.
		var cap_roll := rng.next()
		var kind_w: String = rng.weighted(Bal.PIECE_WEIGHTS)
		var cap_kind: String = rng.pick(Pieces.CAP_KINDS)
		var color: String = rng.pick(Pieces.COLORS)
		var g := rng.next()
		var common: String = rng.pick(Pieces.COMMON_GLYPHS)
		var rare: String = rng.pick(Pieces.RARE_GLYPHS)
		var fam_pick := rng.next()
		var kind := cap_kind if cap_roll < Bal.CAP_CHANCE else kind_w
		if forced_family != "":
			var opts: Array = Pieces.KINDS_OF_FAMILY[forced_family]
			kind = opts[int(floor(fam_pick * opts.size()))]
			forced_family = ""
		var glyph := ""
		var golden := false
		if g < Bal.GLYPH_GOLDEN and not Pieces.is_cap(kind):
			golden = true
		elif g < Bal.GLYPH_GOLDEN + Bal.GLYPH_RARE:
			glyph = rare
		elif g < Bal.GLYPH_GOLDEN + Bal.GLYPH_RARE + Bal.GLYPH_COMMON:
			glyph = common
		var p := Pieces.make(next_id, kind, color, glyph, golden)
		next_id += 1
		return p

	func make(kind: String, color: String, glyph: String = "", golden: bool = false) -> Dictionary:
		var p := Pieces.make(next_id, kind, color, glyph, golden)
		next_id += 1
		return p
