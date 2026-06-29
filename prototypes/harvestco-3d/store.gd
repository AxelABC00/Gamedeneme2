# PROTOTYPE - 2D->3D migration, Phase F2 (store page)
# Full-screen 3-tab store overlay (Botlar / Yukseltmeler / Binalar), built in code.
# Reads SimState for costs/info; emits buy_requested(id). world.gd runs sim.buy_item.
# (Production converts this to a store.tscn scene.)
extends CanvasLayer
class_name Store

signal buy_requested(id: int)
signal closed

const TAB_NAMES := ["Botlar", "Yukseltmeler", "Binalar"]

var _tab: int = 0
var _root: Control
var _tab_btns: Array = []
var _list: VBoxContainer
var _rows: Array = []          # [{id, panel, title, desc, swatch, buy}]
var _coins_lbl: Label

func _full_rect(c: Control) -> void:
	# Explicit full-rect (set_anchors_preset alone does not set offsets reliably here).
	c.anchor_left = 0.0; c.anchor_top = 0.0
	c.anchor_right = 1.0; c.anchor_bottom = 1.0
	c.offset_left = 0; c.offset_top = 0
	c.offset_right = 0; c.offset_bottom = 0

func build(sim: SimState) -> void:
	layer = 5
	_root = Control.new()
	add_child(_root)
	_full_rect(_root)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_root.visible = false

	# dim backdrop
	var dim := ColorRect.new()
	dim.color = Color(0.05, 0.04, 0.02, 0.78)
	_root.add_child(dim)
	_full_rect(dim)

	# panel background (rounded cream)
	var panel := PanelContainer.new()
	_root.add_child(panel)
	panel.anchor_left = 0.0; panel.anchor_right = 1.0
	panel.anchor_top = 0.0; panel.anchor_bottom = 1.0
	panel.offset_left = 18; panel.offset_right = -18
	panel.offset_top = 54; panel.offset_bottom = -40
	var pstyle := StyleBoxFlat.new()
	pstyle.bg_color = sim.C_PANEL
	pstyle.set_corner_radius_all(16)
	pstyle.set_content_margin_all(14)
	panel.add_theme_stylebox_override("panel", pstyle)

	# content column anchored explicitly to the panel rect (minus padding) so the
	# ScrollContainer gets a real height to expand into.
	var col := VBoxContainer.new()
	_root.add_child(col)
	col.anchor_left = 0.0; col.anchor_right = 1.0
	col.anchor_top = 0.0; col.anchor_bottom = 1.0
	col.offset_left = 34; col.offset_right = -34
	col.offset_top = 70; col.offset_bottom = -56
	col.add_theme_constant_override("separation", 10)

	# header row: title + coins + close
	var header := HBoxContainer.new()
	col.add_child(header)
	header.add_theme_constant_override("separation", 10)
	var title := Label.new()
	title.text = "MAGAZA"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.25, 0.18, 0.10))
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_coins_lbl = Label.new()
	_coins_lbl.add_theme_font_size_override("font_size", 24)
	_coins_lbl.add_theme_color_override("font_color", Color(0.30, 0.22, 0.08))
	header.add_child(_coins_lbl)
	var close := Button.new()
	close.text = "X"
	close.custom_minimum_size = Vector2(54, 54)
	close.add_theme_font_size_override("font_size", 24)
	close.pressed.connect(func() -> void: close_store())
	header.add_child(close)

	# tab row
	var tabs := HBoxContainer.new()
	col.add_child(tabs)
	tabs.add_theme_constant_override("separation", 6)
	for i in range(TAB_NAMES.size()):
		var b := Button.new()
		b.text = TAB_NAMES[i]
		b.toggle_mode = true
		b.custom_minimum_size = Vector2(0, 50)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 18)
		var idx := i
		b.pressed.connect(func() -> void: _select_tab(idx, sim))
		tabs.add_child(b)
		_tab_btns.append(b)

	# scrollable item list
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_list.add_theme_constant_override("separation", 8)
	scroll.add_child(_list)

	_select_tab(0, sim)

# Rebuild the row set for a tab (item ids change per tab; cheap enough to rebuild).
func _select_tab(t: int, sim: SimState) -> void:
	_tab = t
	for i in range(_tab_btns.size()):
		_tab_btns[i].button_pressed = (i == t)
	for r in _rows:
		r["panel"].queue_free()
	_rows.clear()
	for id in sim.tab_items(t):
		_rows.append(_make_row(id, sim))
	refresh(sim)

func _make_row(id: int, sim: SimState) -> Dictionary:
	var info: Array = sim.item_info(id)   # [accent, letter, title, desc]
	var panel := PanelContainer.new()
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(1, 1, 1, 0.35)
	ps.set_corner_radius_all(10)
	ps.set_content_margin_all(8)
	panel.add_theme_stylebox_override("panel", ps)
	_list.add_child(panel)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	panel.add_child(row)

	# accent swatch with letter
	var swatch := Label.new()
	swatch.text = info[1]
	swatch.custom_minimum_size = Vector2(46, 46)
	swatch.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	swatch.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	swatch.add_theme_font_size_override("font_size", 24)
	var swstyle := StyleBoxFlat.new()
	swstyle.bg_color = info[0]
	swstyle.set_corner_radius_all(8)
	swatch.add_theme_stylebox_override("normal", swstyle)
	row.add_child(swatch)

	# title + desc
	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	texts.add_theme_constant_override("separation", 1)
	row.add_child(texts)
	var title := Label.new()
	title.text = info[2]
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(0.22, 0.15, 0.08))
	texts.add_child(title)
	var desc := Label.new()
	desc.text = info[3]
	desc.add_theme_font_size_override("font_size", 13)
	desc.add_theme_color_override("font_color", Color(0.40, 0.32, 0.22))
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	texts.add_child(desc)

	# buy button
	var buy := Button.new()
	buy.custom_minimum_size = Vector2(96, 56)
	buy.add_theme_font_size_override("font_size", 18)
	var bid := id
	buy.pressed.connect(func() -> void: buy_requested.emit(bid))
	row.add_child(buy)

	return {"id": id, "panel": panel, "title": title, "desc": desc, "swatch": swatch, "buy": buy}

func refresh(sim: SimState) -> void:
	_coins_lbl.text = "%d c" % sim.coins
	for r in _rows:
		var id: int = r["id"]
		var info: Array = sim.item_info(id)
		r["title"].text = info[2]
		r["swatch"].text = info[1]
		var buy: Button = r["buy"]
		buy.text = sim.item_cost_text(id)
		buy.disabled = not sim.item_enabled(id)

func open_store(sim: SimState, tab: int = 0) -> void:
	_root.visible = true
	_select_tab(tab, sim)

func close_store() -> void:
	_root.visible = false
	closed.emit()

func is_open() -> bool:
	return _root != null and _root.visible
