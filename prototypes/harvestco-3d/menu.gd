# PROTOTYPE - NOT FOR PRODUCTION
# Question: does a real shell (main menu / pause / settings) make this feel shippable?
# Date: 2026-06-29
#
# All overlays live on one CanvasLayer above the HUD. Talks to world.gd and settings.gd
# purely by duck-typed method/field access (both passed into setup) so nothing here needs
# a class_name — keeps console/headless runs parsing.
extends CanvasLayer

const ACCENT := Color(0.40, 0.62, 0.32)        # cozy farm green
const ACCENT_DK := Color(0.30, 0.49, 0.24)
const PANEL_BG := Color(0.16, 0.13, 0.10, 0.96) # warm dark brown
const TEXT := Color(0.96, 0.93, 0.86)

var _world: Node
var _settings: Node
var _dim: ColorRect
var _panel: Control            # the active centered panel (rebuilt per screen)
var _pause_btn: Button         # small in-game pause button, top-right

func setup(world: Node, settings: Node) -> void:
	_world = world
	_settings = settings
	layer = 20
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.45)
	_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	_dim.visible = false
	add_child(_dim)

# ---------------------------------------------------------------- screens

func show_main(has_save: bool) -> void:
	_set_pause_visible(false)
	_dim.visible = true
	_clear_panel()
	var box := _panel_box("HarvestCo")
	if has_save:
		box.add_child(_btn("Devam Et", _on_continue))
	box.add_child(_btn("Yeni Oyun", _on_new_game))
	box.add_child(_btn("Ayarlar", func(): _show_settings(false)))

func _on_new_game() -> void:
	_hide_overlay()
	_set_pause_visible(true)
	_world.start_new_game()

func _on_continue() -> void:
	_hide_overlay()
	_set_pause_visible(true)
	_world.continue_game()

# pause overlay (raised by the in-game pause button)
func _show_pause() -> void:
	_world.set_paused(true)
	_dim.visible = true
	_clear_panel()
	var box := _panel_box("Duraklatıldı")
	box.add_child(_btn("Devam", _on_resume))
	box.add_child(_btn("Ayarlar", func(): _show_settings(true)))
	box.add_child(_btn("Ana Menü", _on_to_main))

func _on_resume() -> void:
	_hide_overlay()
	_world.set_paused(false)

func _on_to_main() -> void:
	# autosave (set_paused already did) then rebuild the scene → fresh main menu
	_world.autosave()
	get_tree().reload_current_scene()

# settings panel — reachable from main menu and from pause
func _show_settings(from_pause: bool) -> void:
	_dim.visible = true
	_clear_panel()
	var box := _panel_box("Ayarlar")

	box.add_child(_toggle("Müzik", _settings.music_on, func(v):
		_settings.music_on = v; _settings.apply(); _settings.save_settings()))
	box.add_child(_slider(_settings.music_vol, func(v):
		_settings.music_vol = v; _settings.apply()))

	box.add_child(_toggle("Ses Efektleri", _settings.sfx_on, func(v):
		_settings.sfx_on = v; _settings.apply(); _settings.save_settings()))
	box.add_child(_slider(_settings.sfx_vol, func(v):
		_settings.sfx_vol = v; _settings.apply()))

	box.add_child(_btn("Geri", func():
		_settings.save_settings()
		if from_pause: _show_pause()
		else: show_main(_world.has_save())))

# ---------------------------------------------------------------- in-game pause button

func _set_pause_visible(v: bool) -> void:
	if v and _pause_btn == null:
		_pause_btn = Button.new()
		_pause_btn.text = "II"
		_pause_btn.anchor_left = 1.0; _pause_btn.anchor_right = 1.0
		_pause_btn.offset_left = -64; _pause_btn.offset_right = -14
		_pause_btn.offset_top = 88; _pause_btn.offset_bottom = 136
		_style_button(_pause_btn)
		_pause_btn.pressed.connect(_show_pause)
		add_child(_pause_btn)
	if _pause_btn != null:
		_pause_btn.visible = v

func _hide_overlay() -> void:
	_dim.visible = false
	_clear_panel()

# ---------------------------------------------------------------- widgets

func _clear_panel() -> void:
	if _panel != null:
		_panel.queue_free()
		_panel = null

# A centered card with a title; returns the VBox to add rows into.
func _panel_box(title: String) -> VBoxContainer:
	var pc := PanelContainer.new()
	pc.set_anchors_preset(Control.PRESET_CENTER)
	pc.grow_horizontal = Control.GROW_DIRECTION_BOTH
	pc.grow_vertical = Control.GROW_DIRECTION_BOTH
	pc.custom_minimum_size = Vector2(380, 0)
	var sb := StyleBoxFlat.new()
	sb.bg_color = PANEL_BG
	sb.set_corner_radius_all(22)
	sb.set_content_margin_all(26)
	sb.border_color = Color(0, 0, 0, 0.35)
	sb.set_border_width_all(2)
	pc.add_theme_stylebox_override("panel", sb)
	add_child(pc)
	_panel = pc

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	pc.add_child(vb)

	var lbl := Label.new()
	lbl.text = title
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.add_theme_color_override("font_color", TEXT)
	lbl.add_theme_font_size_override("font_size", 34)
	vb.add_child(lbl)
	return vb

func _btn(text: String, cb: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 64)
	_style_button(b)
	b.pressed.connect(cb)
	return b

func _style_button(b: Button) -> void:
	b.add_theme_color_override("font_color", TEXT)
	b.add_theme_color_override("font_hover_color", Color(1, 1, 1))
	b.add_theme_color_override("font_pressed_color", Color(0.9, 0.95, 0.9))
	b.add_theme_font_size_override("font_size", 24)
	for state in ["normal", "hover", "pressed"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = ACCENT_DK if state == "pressed" else ACCENT
		if state == "hover":
			sb.bg_color = ACCENT.lightened(0.08)
		sb.set_corner_radius_all(14)
		sb.set_content_margin_all(12)
		b.add_theme_stylebox_override(state, sb)

func _toggle(text: String, on: bool, cb: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_color_override("font_color", TEXT)
	lbl.add_theme_font_size_override("font_size", 22)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(lbl)
	var cb_btn := CheckButton.new()
	cb_btn.button_pressed = on
	cb_btn.toggled.connect(func(v): cb.call(v))
	row.add_child(cb_btn)
	return row

func _slider(val: float, cb: Callable) -> HSlider:
	var s := HSlider.new()
	s.min_value = 0.0
	s.max_value = 1.0
	s.step = 0.05
	s.value = val
	s.custom_minimum_size = Vector2(0, 36)
	s.value_changed.connect(func(v): cb.call(v))
	return s
