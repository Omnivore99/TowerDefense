class_name PieceIcon
extends Control
## Draws a piece (cells in its colour, glyph dot, golden shine) inside a slot.

var piece: Variant = null
var dim := false
var label := ""


func set_piece(p: Variant, is_dim: bool = false) -> void:
	piece = p
	dim = is_dim
	queue_redraw()


func _draw() -> void:
	var sz := size
	if piece == null:
		return
	if Pieces.is_charter(piece):
		_draw_charter(sz)
		return
	var cells := Pieces.orient_cells(piece.kind, 0, false)
	var w := 0
	var h := 0
	for c in cells:
		w = maxi(w, c.x + 1)
		h = maxi(h, c.y + 1)
	var cs := minf((sz.x - 14) / maxf(w, 2.0), (sz.y - 14) / maxf(h, 2.0))
	cs = minf(cs, 22.0)
	var ox := (sz.x - cs * w) / 2.0
	var oy := (sz.y - cs * h) / 2.0
	var col: Color = Bal.PIECE_BODY.get(piece.color, Color.GRAY)
	if piece.golden:
		col = Color(1.0, 0.84, 0.3)
	if dim:
		col = col.darkened(0.55)
	for c in cells:
		var r := Rect2(ox + c.x * cs + 1, oy + c.y * cs + 1, cs - 2, cs - 2)
		draw_rect(r, col.darkened(0.35))
		draw_rect(r.grow(-2), col)
		draw_rect(Rect2(r.position + Vector2(3, 3), Vector2(r.size.x - 6, 3)), col.lightened(0.35))
	if piece.glyph != "":
		var gc := Color(0.7, 0.9, 1.0) if Pieces.RARE_GLYPHS.has(piece.glyph) else Color(1, 0.95, 0.75)
		draw_circle(Vector2(ox + cs * 0.5, oy + cs * 0.5), cs * 0.22, gc)


## Town Charter: a rolled parchment with a wax seal and a little roof.
func _draw_charter(sz: Vector2) -> void:
	var c := sz / 2.0
	var paper := Color(0.93, 0.84, 0.62).darkened(0.5 if dim else 0.0)
	var r := Rect2(c - Vector2(20, 13), Vector2(40, 26))
	draw_rect(r, paper)
	draw_rect(Rect2(r.position - Vector2(3, 2), Vector2(6, 30)), paper.darkened(0.2))
	draw_rect(Rect2(r.end - Vector2(3, 28), Vector2(6, 30)), paper.darkened(0.2))
	var roof := PackedVector2Array([c + Vector2(-9, 1), c + Vector2(0, -8), c + Vector2(9, 1)])
	draw_colored_polygon(roof, Color(0.45, 0.25, 0.18))
	draw_rect(Rect2(c + Vector2(-6, 1), Vector2(12, 7)), Color(0.35, 0.3, 0.28))
	draw_circle(c + Vector2(13, 9), 4.5, Color(0.75, 0.12, 0.1))
