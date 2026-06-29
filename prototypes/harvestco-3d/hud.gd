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
signal erase_toggled(on: bool)

var _coins: Label
var _water: Label
var _depo: Label
var _toast: Label
var _seed_btns: Array = []
var _tools_box: HBoxContainer
var _erase_btn: Button
var _tool_btns: Array = []

func build(sim: SimState) -> void:
	# ---- top stat bar (explicit anchors+offsets; presets alone don't set offsets) ----
	var topbar := HBoxContainer.new()
	add_child(topbar)
	topbar.anchor_left = 0.0; topbar.anchor_right = 1.0
	topbar.anchor_top = 0.0; topbar.anchor_bottom = 0.0
	topbar.offset_left = 18; topbar.offset_right = -18
	topbar.offset_top = 30; topbar.offset_bottom = 70
	topbar.add_theme_constant_override("separation", 22)
	topbar.alignment = BoxContainer.ALIGNMENT_CENTER
	_coins = _stat("Para 0")
	_water = _stat("Su 0")
	_depo = _stat("Depo 0/0")
	topbar.add_child(_coins)
	topbar.add_child(_water)
	topbar.add_child(_depo)

	# ---- bottom controls: fixed-height box pinned to the bottom edge ----
	var vb := VBoxContainer.new()
	add_child(vb)
	vb.anchor_left = 0.0; vb.anchor_right = 1.0
	vb.anchor_top = 1.0; vb.anchor_bottom = 1.0
	vb.offset_left = 12; vb.offset_right = -12
	vb.offset_top = -250; vb.offset_bottom = -26
	vb.add_theme_constant_override("separation", 10)

	# bot tool row: El (hand) + one chip per owned bot, scrollable, with a Sil toggle.
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
	_erase_btn = Button.new()
	_erase_btn.text = "Sil"
	_erase_btn.toggle_mode = true
	_erase_btn.custom_minimum_size = Vector2(64, 46)
	_erase_btn.add_theme_font_size_override("font_size", 18)
	_erase_btn.toggled.connect(func(p: bool) -> void: erase_toggled.emit(p))
	toolrow.add_child(_erase_btn)

	# seed picker (one button per crop)
	var seeds := HBoxContainer.new()
	seeds.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vb.add_child(seeds)
	seeds.add_theme_constant_override("separation", 6)
	for i in range(sim.CROPS.size()):
		var b := Button.new()
		b.custom_minimum_size = Vector2(0, 50)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_font_size_override("font_size", 16)
		var idx := i
		b.pressed.connect(func() -> void: seed_selected.emit(idx))
		seeds.add_child(b)
		_seed_btns.append(b)

	# action row: Sat + Su Al
	var actions := HBoxContainer.new()
	vb.add_child(actions)
	actions.add_theme_constant_override("separation", 10)
	var sat := Button.new()
	sat.text = "Sat"
	sat.custom_minimum_size = Vector2(0, 62)
	sat.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sat.add_theme_font_size_override("font_size", 22)
	sat.pressed.connect(func() -> void: sell_pressed.emit())
	actions.add_child(sat)
	var su := Button.new()
	su.text = "Su Al (%d)" % sim.WATER_COST
	su.custom_minimum_size = Vector2(0, 62)
	su.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	su.add_theme_font_size_override("font_size", 22)
	su.pressed.connect(func() -> void: buy_water_pressed.emit())
	actions.add_child(su)
	var mag := Button.new()
	mag.text = "Magaza"
	mag.custom_minimum_size = Vector2(0, 62)
	mag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mag.add_theme_font_size_override("font_size", 22)
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

func _stat(t: String) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", 26)
	return l

func refresh(sim: SimState) -> void:
	_coins.text = "Para %d" % sim.coins
	_water.text = "Su %d" % sim.water
	_depo.text = "Depo %d/%d" % [sim.stock_total(), sim.storage_cap]
	for i in range(_seed_btns.size()):
		var b: Button = _seed_btns[i]
		var col: Color = sim.CROPS[i]["col"]
		var cname: String = sim.CROPS[i]["name"]
		if i == sim.selected_seed:
			b.modulate = col.lightened(0.35)
			b.text = "> " + cname
		else:
			b.modulate = col
			b.text = cname

# Rebuild the bot tool chips (El + one per bot). current_tool: -1 = hand.
func refresh_tools(sim: SimState, current_tool: int, erase: bool) -> void:
	for b in _tool_btns:
		b.queue_free()
	_tool_btns.clear()

	var hand := Button.new()
	hand.text = "El"
	hand.toggle_mode = true
	hand.button_pressed = current_tool == -1
	hand.custom_minimum_size = Vector2(56, 46)
	hand.add_theme_font_size_override("font_size", 18)
	hand.pressed.connect(func() -> void: tool_selected.emit(-1))
	_tools_box.add_child(hand)
	_tool_btns.append(hand)

	for i in range(sim.bots.size()):
		var bot = sim.bots[i]
		var b := Button.new()
		b.text = sim.TASK_LETTER[bot.task]
		b.toggle_mode = true
		b.button_pressed = current_tool == i
		b.custom_minimum_size = Vector2(46, 46)
		b.add_theme_font_size_override("font_size", 20)
		b.modulate = sim.TASK_COL[bot.task].lightened(0.12)
		var idx := i
		b.pressed.connect(func() -> void: tool_selected.emit(idx))
		_tools_box.add_child(b)
		_tool_btns.append(b)

	_erase_btn.button_pressed = erase

func toast(text: String) -> void:
	_toast.text = text
	_toast.modulate.a = 1.0
	var tw := create_tween()
	tw.tween_interval(0.7)
	tw.tween_property(_toast, "modulate:a", 0.0, 0.7)
