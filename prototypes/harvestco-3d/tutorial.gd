# PROTOTYPE - NOT FOR PRODUCTION
# Question: do first-run coach hints get a new player farming without confusion?
# Date: 2026-06-29
#
# A tiny one-at-a-time hint carousel anchored low (one-thumb reach). Shown once ever on a
# fresh game; the "seen" flag is a marker file in user://. No class_name — added by path.
extends CanvasLayer

const SEEN := "user://tutorial_seen"
const TEXT := Color(0.98, 0.96, 0.90)
const CARD_BG := Color(0.14, 0.11, 0.08, 0.96)
const ACCENT := Color(0.40, 0.62, 0.32)

# the "do it yourself first, then automate" loop, in player order
const HINTS := [
	"Hoş geldin! 🌱 Boş toprağa dokun: önce çapala.",
	"Aynı kareye tekrar dokun: tohum ek, sonra sula.",
	"Ekin olgunlaşınca dokunup hasat et, parayı topla.",
	"Taşları temizleyerek tarlanı büyüt.",
	"Mağazadan robot al — işini senin yerine yapsınlar!",
]

var _i: int = 0
var _card: Control
var _label: Label
var _btn: Button

func begin() -> void:
	layer = 15
	_build()
	_show_hint()

func _build() -> void:
	var pc := PanelContainer.new()
	pc.anchor_left = 0.0; pc.anchor_right = 1.0
	pc.anchor_top = 1.0; pc.anchor_bottom = 1.0
	pc.offset_left = 18; pc.offset_right = -18
	pc.offset_top = -340; pc.offset_bottom = -276
	var sb := StyleBoxFlat.new()
	sb.bg_color = CARD_BG
	sb.set_corner_radius_all(18)
	sb.set_content_margin_all(18)
	sb.border_color = ACCENT
	sb.set_border_width_all(2)
	pc.add_theme_stylebox_override("panel", sb)
	add_child(pc)
	_card = pc

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	pc.add_child(row)

	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label.add_theme_color_override("font_color", TEXT)
	_label.add_theme_font_size_override("font_size", 21)
	row.add_child(_label)

	_btn = Button.new()
	_btn.custom_minimum_size = Vector2(96, 56)
	_btn.add_theme_color_override("font_color", TEXT)
	_btn.add_theme_font_size_override("font_size", 22)
	var bsb := StyleBoxFlat.new()
	bsb.bg_color = ACCENT
	bsb.set_corner_radius_all(12)
	bsb.set_content_margin_all(10)
	_btn.add_theme_stylebox_override("normal", bsb)
	_btn.add_theme_stylebox_override("hover", bsb)
	_btn.add_theme_stylebox_override("pressed", bsb)
	_btn.pressed.connect(_next)
	row.add_child(_btn)

func _show_hint() -> void:
	_label.text = HINTS[_i]
	_btn.text = "Başla!" if _i == HINTS.size() - 1 else "Tamam →"

func _next() -> void:
	_i += 1
	if _i >= HINTS.size():
		_finish()
	else:
		_show_hint()

func _finish() -> void:
	var f := FileAccess.open(SEEN, FileAccess.WRITE)
	if f != null:
		f.store_string("1")
		f.close()
	queue_free()
