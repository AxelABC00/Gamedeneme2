# PROTOTYPE - 2D->3D migration, Phase F (HUD)
# Real Control nodes (Button/Label), built in code for prototype speed.
# Reads SimState for display; emits signals on actions, world.gd does the work.
# (Production converts this to a hud.tscn scene.)
extends CanvasLayer
class_name Hud

signal sell_pressed
signal buy_water_pressed
signal seed_selected(idx: int)
signal store_pressed
signal tool_selected(idx: int)   # -1 = hand, >=0 = bot index (paint that bot's zone)
signal clear_zone_pressed         # wipe the whole shared work area

var _coins: Label
var _water: Label
var _depo: Label
var _toast: Label
var _seed_btns: Array = []
var _seed_info: Label
var _tools_box: HBoxContainer
var _clear_btn: Button
var _tool_btns: Array = []

func build(sim: SimState) -> void:
	# ---- top stat bar: a rounded translucent panel holding three colored stat chips ----
	var topbg := PanelContainer.new()
	add_child(topbg)
	topbg.anchor_left = 0.0; topbg.anchor_right = 1.0
	topbg.anchor_top = 0.0; topbg.anchor_bottom = 0.0
	topbg.offset_left = 14; topbg.offset_right = -14
	topbg.offset_top = 24; topbg.offset_bottom = 80
	var topsb := StyleBoxFlat.new()
	topsb.bg_color = Color(0.10, 0.13, 0.12, 0.78)
	topsb.set_corner_radius_all(16)
	topsb.set_border_width_all(2)
	topsb.border_color = Color(1, 1, 1, 0.10)
	topsb.content_margin_left = 10; topsb.content_margin_right = 10
	topsb.content_margin_top = 4; topsb.content_margin_bottom = 4
	topbg.add_theme_stylebox_override("panel", topsb)
	var topbar := HBoxContainer.new()
	topbg.add_child(topbar)
	topbar.add_theme_constant_override("separation", 8)
	topbar.alignment = BoxContainer.ALIGNMENT_CENTER
	_coins = _stat(topbar, Color(1.0, 0.84, 0.35))   # gold
	_water = _stat(topbar, Color(0.45, 0.78, 0.98))  # blue
	_depo = _stat(topbar, Color(0.80, 0.90, 0.70))   # leaf

	# ---- bottom controls: fixed-height box pinned to the bottom edge ----
	var vb := VBoxContainer.new()
	add_child(vb)
	vb.anchor_left = 0.0; vb.anchor_right = 1.0
	vb.anchor_top = 1.0; vb.anchor_bottom = 1.0
	vb.offset_left = 12; vb.offset_right = -12
	vb.offset_top = -250; vb.offset_bottom = -26
	vb.add_theme_constant_override("separation", 10)

	# bot tool row: El (hand) + Bolge (paint area), scrollable, with a Temizle button.
	# Rebuilt by refresh_tools() whenever the bot roster or selection changes.
	var toolrow := HBoxContainer.new()
	toolrow.custom_minimum_size = Vector2(0, 46)
	vb.add_child(toolrow)
	toolrow.add_theme_constant_override("separation", 6)
	var tscroll := ScrollContainer.new()
	tscroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tscroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	toolrow.add_child(tscroll)
	_tools_box = HBoxContainer.new()
	_tools_box.add_theme_constant_override("separation", 6)
	tscroll.add_child(_tools_box)
	_clear_btn = Button.new()
	_clear_btn.text = "Temizle"
	_clear_btn.custom_minimum_size = Vector2(88, 46)
	_clear_btn.add_theme_font_size_override("font_size", 16)
	_style_button(_clear_btn, Color(0.55, 0.30, 0.30))
	_clear_btn.pressed.connect(func() -> void: clear_zone_pressed.emit())
	toolrow.add_child(_clear_btn)

	# selected-seed info line (shows buy + sell price of the chosen crop)
	_seed_info = Label.new()
	_seed_info.add_theme_font_size_override("font_size", 17)
	_seed_info.add_theme_color_override("font_color", Color(0.92, 0.95, 0.88))
	_seed_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vb.add_child(_seed_info)

	# seed picker (one button per crop, each shows its buy price)
	var seeds := HBoxContainer.new()
	seeds.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(seeds)
	seeds.add_theme_constant_override("separation", 6)
	for i in range(sim.CROPS.size()):
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 58)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 14)
		b.autowrap_mode = TextServer.AUTOWRAP_OFF
		var idx := i
		b.pressed.connect(func() -> void: seed_selected.emit(idx))
		seeds.add_child(b)
		_seed_btns.append(b)

	# action row: Sat + Su Al + Magaza (styled)
	var actions := HBoxContainer.new()
	vb.add_child(actions)
	actions.add_theme_constant_override("separation", 10)
	var sat := Button.new()
	sat.text = "Sat"
	sat.custom_minimum_size = Vector2(0, 62)
	sat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sat.add_theme_font_size_override("font_size", 22)
	_style_button(sat, Color(0.30, 0.58, 0.32))   # green
	sat.pressed.connect(func() -> void: sell_pressed.emit())
	actions.add_child(sat)
	var su := Button.new()
	su.text = "Su Al (%d)" % sim.WATER_COST
	su.custom_minimum_size = Vector2(0, 62)
	su.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	su.add_theme_font_size_override("font_size", 22)
	_style_button(su, Color(0.24, 0.50, 0.70))    # blue
	su.pressed.connect(func() -> void: buy_water_pressed.emit())
	actions.add_child(su)
	var mag := Button.new()
	mag.text = "Magaza"
	mag.custom_minimum_size = Vector2(0, 62)
	mag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mag.add_theme_font_size_override("font_size", 22)
	_style_button(mag, Color(0.66, 0.46, 0.18))    # amber
	mag.pressed.connect(func() -> void: store_pressed.emit())
	actions.add_child(mag)

	# ---- center toast ----
	_toast = Label.new()
	add_child(_toast)
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)
	_toast.offset_top = 120
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 30)
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_toast.modulate.a = 0.0

	refresh(sim)

func _stat(parent: Node, color: Color) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", 24)
	l.add_theme_color_override("font_color", color)
	l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	parent.add_child(l)
	return l

func refresh(sim: SimState) -> void:
	_coins.text = "Para %d" % sim.coins
	_water.text = "Su %d" % sim.water
	_depo.text = "Depo %d/%d" % [sim.stock_total(), sim.storage_cap]
	for i in range(_seed_btns.size()):
		var b: Button = _seed_btns[i]
		var col: Color = sim.CROPS[i]["col"]
		var cname: String = sim.CROPS[i]["name"]
		var buy: int = int(sim.CROPS[i]["seed"])
		var selected: bool = i == sim.selected_seed
		# crop-tinted button: dark fill by default, bright when selected
		var base: Color = col.darkened(0.30) if not selected else col.lightened(0.10)
		_style_button(b, base, selected)
		b.text = "%s\nAl %d" % [cname, buy]
	# show buy + sell for the currently selected crop on the info line
	if _seed_info != null and sim.selected_seed >= 0 and sim.selected_seed < sim.CROPS.size():
		var c: Dictionary = sim.CROPS[sim.selected_seed]
		_seed_info.text = "%s  -  Al %d para  /  Sat ~%d para" % [c["name"], int(c["seed"]), int(c["value"])]

# ---- button styling helpers (rounded StyleBoxFlat, replaces the flat default look) ----
func _box(col: Color, corner: int) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(corner)
	sb.set_border_width_all(2)
	sb.border_color = col.lightened(0.22)
	sb.content_margin_left = 8; sb.content_margin_right = 8
	sb.content_margin_top = 4; sb.content_margin_bottom = 4
	sb.shadow_color = Color(0, 0, 0, 0.28)
	sb.shadow_size = 3
	sb.shadow_offset = Vector2(0, 2)
	return sb

func _style_button(b: Button, base: Color, highlight: bool = false) -> void:
	var c := base.lightened(0.06) if highlight else base
	b.add_theme_stylebox_override("normal", _box(c, 12))
	b.add_theme_stylebox_override("hover", _box(c.lightened(0.12), 12))
	b.add_theme_stylebox_override("pressed", _box(c.darkened(0.18), 12))
	b.add_theme_stylebox_override("disabled", _box(c.darkened(0.40), 12))
	b.add_theme_stylebox_override("focus", _box(c, 12))
	if highlight:
		var fb := _box(c, 12)
		fb.border_color = Color(1, 1, 1, 0.9)
		fb.set_border_width_all(3)
		b.add_theme_stylebox_override("normal", fb)
	b.add_theme_color_override("font_color", Color(1, 1, 1))
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_pressed_color", Color(1, 1, 1))
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.5))

# toggle-style tool button: dim when off, bright (pressed style) when on
func _style_tool(b: Button, base: Color) -> void:
	b.add_theme_stylebox_override("normal", _box(base.darkened(0.38), 10))
	b.add_theme_stylebox_override("hover", _box(base.darkened(0.18), 10))
	b.add_theme_stylebox_override("pressed", _box(base.lightened(0.14), 10))
	b.add_theme_stylebox_override("focus", _box(base.darkened(0.38), 10))
	b.add_theme_color_override("font_color", Color(1, 1, 1))
	b.add_theme_color_override("font_pressed_color", Color(1, 1, 1))

# Tool row: only two modes now — "El" (manual hand farming) and "Bolge" (paint the
# shared work area all bots share). No per-bot chips: bots run autonomously.
# Hidden entirely until the player owns at least one bot.
func refresh_tools(sim: SimState, current_tool: int) -> void:
	for b in _tool_btns:
		b.queue_free()
	_tool_btns.clear()

	var has_bots: bool = not sim.bots.is_empty()
	_clear_btn.visible = has_bots
	if not has_bots:
		return

	var hand := Button.new()
	hand.text = "El"
	hand.toggle_mode = true
	hand.button_pressed = current_tool == -1
	hand.custom_minimum_size = Vector2(76, 46)
	hand.add_theme_font_size_override("font_size", 18)
	_style_tool(hand, Color(0.30, 0.40, 0.52))
	hand.pressed.connect(func() -> void: tool_selected.emit(-1))
	_tools_box.add_child(hand)
	_tool_btns.append(hand)

	var paint := Button.new()
	paint.text = "Bolge (%d bot)" % sim.bots.size()
	paint.toggle_mode = true
	paint.button_pressed = current_tool >= 0
	paint.custom_minimum_size = Vector2(150, 46)
	paint.add_theme_font_size_override("font_size", 18)
	_style_tool(paint, Color(0.20, 0.52, 0.62))
	paint.pressed.connect(func() -> void: tool_selected.emit(0))
	_tools_box.add_child(paint)
	_tool_btns.append(paint)

func toast(text: String) -> void:
	_toast.text = text
	_toast.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(0.7)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.7)
