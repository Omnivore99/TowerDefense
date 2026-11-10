class_name Hud
extends Control
## The HUD (section 16): MUST USE / MAY USE / Hold on the left, board, wave, integrity,
## resources and next-wave preview on top, the selected object card on the right,
## tutorial and preview text at the bottom, toasts, and the modal screens.

const AMBER := Color(1.0, 0.7, 0.3)
const PANEL_BG := Color(0.07, 0.085, 0.11, 0.9)
const TEXT := Color(0.88, 0.9, 0.95)
const DIM := Color(0.6, 0.64, 0.72)

var w  # World (untyped to avoid a cyclic class reference)
var top_label: RichTextLabel
var res_label: RichTextLabel
var integrity_bar: ProgressBar
var preview_label: RichTextLabel
var ready_btn: Button
var speed_btns: Array[Button] = []
var must_slots: Array[Button] = []
var may_slots: Array[Button] = []
var hold_slot: Button
var discard_btn: Button
var card: PanelContainer
var card_text: RichTextLabel
var hint: RichTextLabel
var tutorial_panel: PanelContainer
var tutorial_text: RichTextLabel
var toasts: VBoxContainer
var modal_layer: Control
var modal: PanelContainer
var undo_bar: ProgressBar
var combo_label: Label
var left_panel: PanelContainer
var _sig := ""


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	theme = _make_theme()
	_build_top()
	_build_left()
	_build_card()
	_build_bottom()
	toasts = VBoxContainer.new()
	toasts.set_anchors_preset(Control.PRESET_CENTER_TOP)
	toasts.offset_left = -260
	toasts.offset_right = 260
	toasts.offset_top = 84
	toasts.offset_bottom = 380
	toasts.mouse_filter = Control.MOUSE_FILTER_IGNORE
	toasts.alignment = BoxContainer.ALIGNMENT_BEGIN
	add_child(toasts)
	combo_label = Label.new()
	combo_label.set_anchors_preset(Control.PRESET_CENTER)
	combo_label.offset_left = -200
	combo_label.offset_right = 200
	combo_label.offset_top = -190
	combo_label.offset_bottom = -130
	combo_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	combo_label.add_theme_font_size_override("font_size", 40)
	combo_label.add_theme_color_override("font_color", AMBER)
	combo_label.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.8))
	combo_label.add_theme_constant_override("outline_size", 8)
	combo_label.modulate.a = 0.0
	combo_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(combo_label)
	modal_layer = Control.new()
	modal_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(modal_layer)


static func _make_theme() -> Theme:
	var t := Theme.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.border_color = Color(1.0, 0.7, 0.3, 0.35)
	sb.set_border_width_all(1)
	sb.set_corner_radius_all(10)
	sb.set_content_margin_all(10)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 6
	t.set_stylebox("panel", "PanelContainer", sb)
	var btn := StyleBoxFlat.new()
	btn.bg_color = Color(0.13, 0.15, 0.2, 0.95)
	btn.border_color = Color(1.0, 0.7, 0.3, 0.25)
	btn.set_border_width_all(1)
	btn.set_corner_radius_all(8)
	btn.set_content_margin_all(8)
	var hov := btn.duplicate()
	hov.bg_color = Color(0.2, 0.22, 0.28, 0.98)
	hov.border_color = Color(1.0, 0.7, 0.3, 0.7)
	var prs := btn.duplicate()
	prs.bg_color = Color(0.3, 0.22, 0.12, 0.98)
	prs.border_color = AMBER
	var dis := btn.duplicate()
	dis.bg_color = Color(0.1, 0.11, 0.14, 0.7)
	dis.border_color = Color(1, 1, 1, 0.08)
	t.set_stylebox("normal", "Button", btn)
	t.set_stylebox("hover", "Button", hov)
	t.set_stylebox("pressed", "Button", prs)
	t.set_stylebox("disabled", "Button", dis)
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_disabled_color", "Button", Color(0.5, 0.52, 0.58))
	t.set_color("font_color", "Label", TEXT)
	t.set_color("default_color", "RichTextLabel", TEXT)
	t.set_font_size("font_size", "Label", 15)
	t.set_font_size("font_size", "Button", 15)
	t.set_font_size("normal_font_size", "RichTextLabel", 15)
	t.set_font_size("bold_font_size", "RichTextLabel", 15)
	var bar_bg := StyleBoxFlat.new()
	bar_bg.bg_color = Color(0.05, 0.06, 0.08)
	bar_bg.set_corner_radius_all(5)
	var bar_fg := StyleBoxFlat.new()
	bar_fg.bg_color = AMBER
	bar_fg.set_corner_radius_all(5)
	t.set_stylebox("background", "ProgressBar", bar_bg)
	t.set_stylebox("fill", "ProgressBar", bar_fg)
	t.set_font_size("font_size", "ProgressBar", 1)
	return t


func _panel(parent: Control) -> PanelContainer:
	var p := PanelContainer.new()
	p.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(p)
	return p


func _rich(parent: Control, min_w: float = 0.0) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.autowrap_mode = TextServer.AUTOWRAP_OFF if min_w == 0.0 else TextServer.AUTOWRAP_WORD_SMART
	r.custom_minimum_size = Vector2(min_w, 0)
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r


func _build_top() -> void:
	var p := _panel(self)
	p.set_anchors_preset(Control.PRESET_TOP_WIDE)
	p.offset_left = 12
	p.offset_right = -12
	p.offset_top = 10
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 18)
	p.add_child(hb)
	top_label = _rich(hb)
	var ib := VBoxContainer.new()
	ib.custom_minimum_size = Vector2(180, 0)
	hb.add_child(ib)
	var il := Label.new()
	il.text = "Base integrity"
	il.add_theme_font_size_override("font_size", 12)
	il.add_theme_color_override("font_color", DIM)
	ib.add_child(il)
	integrity_bar = ProgressBar.new()
	integrity_bar.custom_minimum_size = Vector2(180, 12)
	integrity_bar.max_value = Bal.BASE_INTEGRITY
	integrity_bar.show_percentage = false
	ib.add_child(integrity_bar)
	res_label = _rich(hb)
	preview_label = _rich(hb)
	preview_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for s in [0.5, 1.0, 2.0, 3.0]:
		var b := Button.new()
		b.text = ("½×" if s == 0.5 else "%d×" % int(s))
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(42, 0)
		b.pressed.connect(func(): w.set_speed(s))
		hb.add_child(b)
		speed_btns.append(b)
	var pause := Button.new()
	pause.text = "❚❚"
	pause.tooltip_text = "Pause (P)"
	pause.pressed.connect(func(): w.toggle_pause())
	hb.add_child(pause)
	ready_btn = Button.new()
	ready_btn.text = "Ready ⏎"
	ready_btn.custom_minimum_size = Vector2(110, 0)
	ready_btn.pressed.connect(func(): w.call_ready())
	hb.add_child(ready_btn)


func _slot(parent: Control, zone: String, index: int) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(96, 84)
	var icon := PieceIcon.new()
	icon.name = "Icon"
	icon.set_anchors_preset(Control.PRESET_FULL_RECT)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	b.add_child(icon)
	b.pressed.connect(func(): w.select_source({"zone": zone, "index": index}))
	b.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_RIGHT:
			w.hold_swap({"zone": zone, "index": index}))
	parent.add_child(b)
	return b


func _section(parent: Control, txt: String) -> void:
	var l := Label.new()
	l.text = txt
	l.add_theme_font_size_override("font_size", 12)
	l.add_theme_color_override("font_color", DIM)
	parent.add_child(l)


func _build_left() -> void:
	left_panel = _panel(self)
	left_panel.position = Vector2(12, 84)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	left_panel.add_child(vb)
	_section(vb, "MUST USE")
	var mg := GridContainer.new()
	mg.columns = 1
	vb.add_child(mg)
	for i in Bal.MUST_VISIBLE:
		must_slots.append(_slot(mg, "must", i))
	_section(vb, "MAY USE")
	var yg := GridContainer.new()
	yg.columns = 2
	vb.add_child(yg)
	for i in Bal.MAY_SLOTS + 1:
		may_slots.append(_slot(yg, "may", i))
	_section(vb, "HOLD (H)")
	hold_slot = _slot(vb, "hold", 0)
	discard_btn = Button.new()
	discard_btn.text = "Discard"
	discard_btn.tooltip_text = "Throw the selected piece away (Recycler turns it into Essence)"
	discard_btn.pressed.connect(func(): w.discard_selected())
	vb.add_child(discard_btn)


func _build_card() -> void:
	card = _panel(self)
	card.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	card.offset_left = -330
	card.offset_right = -12
	card.offset_top = 84
	card.custom_minimum_size = Vector2(318, 0)
	var vb := VBoxContainer.new()
	card.add_child(vb)
	card_text = _rich(vb, 296)
	card.visible = false


func _build_bottom() -> void:
	hint = _rich(self, 640)
	hint.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	hint.offset_left = -320
	hint.offset_right = 320
	hint.offset_top = -120
	hint.offset_bottom = -64
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	hint.add_theme_constant_override("outline_size", 6)
	tutorial_panel = _panel(self)
	tutorial_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	tutorial_panel.offset_left = -300
	tutorial_panel.offset_right = 300
	tutorial_panel.offset_top = -64
	tutorial_panel.offset_bottom = -12
	tutorial_text = _rich(tutorial_panel, 580)
	tutorial_panel.visible = false
	undo_bar = ProgressBar.new()
	undo_bar.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	undo_bar.offset_left = -60
	undo_bar.offset_right = 60
	undo_bar.offset_top = -132
	undo_bar.offset_bottom = -126
	undo_bar.max_value = Bal.UNDO_SECONDS
	undo_bar.show_percentage = false
	undo_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(undo_bar)


# ----------------------------------------------------------------- per-frame update
func refresh(g: Game) -> void:
	if g == null:
		return
	var wave_txt := "Board %d · Wave %d of %d" % [g.board_no, maxi(g.wave_index, 1 if g.phase == "wave" else g.wave_index), g.waves_in_board()]
	var phase_txt: String = {"reveal": "the road strikes in…", "calm": "calm", "wave": "wave!", "cleared": "board cleared", "base": "base", "lost": "base fell", "victory": "victory"}.get(g.phase, g.phase)
	top_label.text = "[b]%s[/b]  [color=#8a93a6]%s · %s[/color]" % [wave_txt, Bal.MODES[g.mode].name, phase_txt]
	integrity_bar.value = maxi(0, g.integrity)
	var buf := " +%d" % g.buffer if g.buffer > 0 else ""
	var lance := ""
	if g.eco.lance_level() > 0:
		lance = "   [color=#f2efe6]➶ %d/%d[/color]" % [g.eco.charges(), g.eco.lance_charges_max()]
	var pearls := "   [color=#e8f4ff]● %d[/color]" % g.base.pearls if g.base.pearls > 0 else ""
	res_label.text = "[color=#ffcf6b]◆ %d[/color]   [color=#f08c40]⬢ %d[/color]   [color=#e0b060]▮ %d[/color]   [color=#8cd8ff]≈ %d[/color]%s%s   [color=#8a93a6]%d/%d%s[/color]" % [int(g.base.essence), int(g.base.ore), int(g.base.timber), int(g.base.water), pearls, lance, maxi(0, g.integrity), Bal.BASE_INTEGRITY, buf]
	res_label.tooltip_text = "Essence, Ore, Timber, Water, Pearls, Lance charges, base integrity"
	var nw := g.next_wave_preview()
	if g.phase == "calm" and not nw.is_empty():
		var counts := {}
		for e in nw.enemies:
			counts[e.size] = counts.get(e.size, 0) + 1
		var parts: PackedStringArray = []
		for s in ["mite", "small", "medium", "large", "giant", "champion", "boss"]:
			if counts.has(s):
				parts.append("%d %s" % [counts[s], s])
		preview_label.text = "[color=#8a93a6]Next:[/color] %s  [color=#8a93a6]· mostly %s[/color]" % [", ".join(parts), Waves.SUIT_SYMBOL[nw.dominant]]
	elif g.phase == "wave":
		preview_label.text = "[color=#8a93a6]%d monsters on the road[/color]" % g.enemies.size()
	else:
		preview_label.text = ""
	ready_btn.disabled = g.phase != "calm"
	ready_btn.text = "Ready ⏎" if g.phase == "calm" else ("…" if g.phase == "wave" else "Ready ⏎")
	for i in speed_btns.size():
		speed_btns[i].button_pressed = is_equal_approx([0.5, 1.0, 2.0, 3.0][i], w.speed)
	# slots
	var sig := "%s|%s|%s|%s|%s" % [_ids(g.must), _ids(g.may), str(g.hold.id) if g.hold != null else "-", g.may_locked(), str(w.selected)]
	if sig != _sig:
		_sig = sig
		for i in must_slots.size():
			var p: Variant = g.must[i] if i < g.must.size() else null
			_set_slot(must_slots[i], p, false, w.selected.get("zone", "") == "must" and w.selected.index == i)
		for i in may_slots.size():
			may_slots[i].visible = i < g.may.size()
			var p2: Variant = g.may[i] if i < g.may.size() else null
			_set_slot(may_slots[i], p2, g.may_locked(), w.selected.get("zone", "") == "may" and w.selected.index == i)
		_set_slot(hold_slot, g.hold, g.may_locked(), w.selected.get("zone", "") == "hold")
		must_slots[0].get_parent().get_parent().get_child(0).text = "MUST USE" + (" (+%d)" % (g.must.size() - Bal.MUST_VISIBLE) if g.must.size() > Bal.MUST_VISIBLE else "")
	discard_btn.disabled = w.selected.is_empty()
	discard_btn.text = "Recycle (+%d ◆)" % int(Bal.BUILDING_FX.recycler * g.building_mult("recycler")) if g.can_recycle() else "Discard"
	var ul := g.undo_left()
	undo_bar.visible = ul > 0.0
	undo_bar.value = ul
	if not g.tutorial.is_empty():
		tutorial_panel.visible = true
		tutorial_text.text = "[color=#ffcf6b]Tip[/color]  " + g.tutorial.text
	else:
		tutorial_panel.visible = false
	if combo_label.modulate.a > 0.0:
		combo_label.modulate.a = maxf(0.0, combo_label.modulate.a - get_process_delta_time() * 0.8)


func _ids(arr: Array) -> String:
	var s := ""
	for p in arr:
		s += (str(p.id) if p != null else "-") + ","
	return s


func _set_slot(b: Button, p: Variant, locked: bool, selected: bool) -> void:
	var icon: PieceIcon = b.get_node("Icon")
	icon.set_piece(p, locked)
	b.disabled = p == null
	b.modulate = Color(1.25, 1.1, 0.85) if selected else Color.WHITE
	if p != null:
		var fam := Pieces.family_of(p)
		var tip := ("Cap (%s)" % p.kind) if fam == "" else fam
		if p.golden:
			tip = "Golden piece: counts as any family and colour"
		elif p.glyph != "":
			tip += " · glyph: " + Pieces.GLYPH_LABEL[p.glyph]
		b.tooltip_text = "%s, %s%s" % [tip, p.color, "\nLocked: place MUST USE pieces first" if locked else ""]


func set_hint(txt: String) -> void:
	hint.text = txt


func toast(txt: String, color: Color = TEXT, secs: float = 2.4) -> void:
	var l := Label.new()
	l.text = txt
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	l.add_theme_constant_override("outline_size", 6)
	l.add_theme_font_size_override("font_size", 20)
	toasts.add_child(l)
	if toasts.get_child_count() > 5:
		toasts.get_child(0).queue_free()
	var tw := create_tween()
	tw.tween_interval(secs)
	tw.tween_property(l, "modulate:a", 0.0, 0.6)
	tw.tween_callback(l.queue_free)


func combo(n: int) -> void:
	var names := {3: "Triple", 5: "Penta", 8: "Octo", 13: "Fibonacci 13", 21: "Fibonacci Cascade"}
	combo_label.text = "%s ×%d" % [names.get(n, "Combo"), n]
	combo_label.modulate.a = 1.0
	combo_label.scale = Vector2.ONE * 1.3
	combo_label.pivot_offset = combo_label.size / 2.0
	var tw := create_tween()
	tw.tween_property(combo_label, "scale", Vector2.ONE, Bal.T_M).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# ----------------------------------------------------------------- tower card
func show_tower(t: SimTower, g: Game) -> void:
	if t == null or t.stats.is_empty():
		if t != null and t.type == "":
			card.visible = true
			card_text.text = "[b]Unfinished pile[/b]\n[color=#8a93a6]%d of 3 core pieces. Add touching pieces to make a tower.[/color]" % t.core_count()
			return
		card.visible = false
		return
	card.visible = true
	var s := t.stats
	var def: Dictionary = Bal.TOWERS[t.type]
	var col: String = s.color
	var lines: PackedStringArray = []
	lines.append("[font_size=20][b]%s[/b][/font_size]  [color=#8a93a6]Mk I[/color]" % t.type)
	lines.append("[color=#8a93a6]%s · %s[/color]" % [def.note, t.hint])
	lines.append("")
	lines.append("Damage [b]%.0f[/b] every %.2f s  ·  DPS [b]%.0f[/b]" % [s.damage, s.interval, s.dps])
	lines.append("Range [b]%.1f[/b] cells  ·  Stories [b]%d[/b]  ·  Kills [b]%d[/b]" % [s.range, s.stories, t.kills])
	if col != "":
		lines.append("Colour [color=%s]%s[/color]%s" % [Bal.PIECE_GLOW[col].to_html(false), col, ("  · resonance" if s.resonance != "" else "")])
	var good: PackedStringArray = []
	for b in s.bonuses:
		good.append(("[color=#7dffb0]+ %s[/color]" if b.good else "[color=#ff8a7a]− %s[/color]") % b.label)
	if not good.is_empty():
		lines.append("")
		lines.append("\n".join(good))
	if t.corroded:
		lines.append("[color=#b6ff5c]Corroded: firing at 70%[/color]")
	card_text.text = "\n".join(lines)


func hide_card() -> void:
	card.visible = false


# ----------------------------------------------------------------- modals
func close_modal() -> void:
	if modal != null:
		modal.queue_free()
		modal = null
	modal_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE


func open_modal(title: String, body_bb: String, buttons: Array, wide: float = 520.0) -> VBoxContainer:
	close_modal()
	modal_layer.mouse_filter = Control.MOUSE_FILTER_STOP
	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.03, 0.05, 0.55)
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	modal = PanelContainer.new()
	modal.set_anchors_preset(Control.PRESET_CENTER)
	modal.custom_minimum_size = Vector2(wide, 0)
	modal_layer.add_child(modal)
	modal.add_child(dim)
	dim.show_behind_parent = true
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	modal.add_child(vb)
	var tl := Label.new()
	tl.text = title
	tl.add_theme_font_size_override("font_size", 26)
	tl.add_theme_color_override("font_color", AMBER)
	vb.add_child(tl)
	if body_bb != "":
		var b := _rich(vb, wide - 24)
		b.text = body_bb
	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 10)
	hb.name = "Buttons"
	for bt in buttons:
		var btn := Button.new()
		btn.text = bt[0]
		btn.custom_minimum_size = Vector2(120, 40)
		btn.pressed.connect(bt[1])
		hb.add_child(btn)
	vb.add_child(hb)
	modal.reset_size()
	modal.position = (get_viewport_rect().size - modal.size) / 2.0
	_recentre.call_deferred()
	return vb


func _recentre() -> void:
	if modal != null:
		modal.reset_size()
		modal.position = (get_viewport_rect().size - modal.size) / 2.0


func has_modal() -> bool:
	return modal != null
