# PROTOTYPE - NOT FOR PRODUCTION
# Concept: cozy robot farming. Manual-first -> buy specialist bots -> paint zones -> automate.
# v6: economy (seed cost, water resource, bot maintenance).
# v7: HarvestCo-inspired (robotized): rocks + Temizleyici bot, golden crops, Verim+/Hiz+/Dura+,
#     tabbed shop. Reference game: HarvestCo.
# v8: 4th crop (Bugday) + Degirmen processing chain (wheat->flour), Depo/storage + Sat,
#     otomatik Su Kuyusu (passive water), Altin Avcisi bot, random events (Yagmur/UFO/Tuccar/Kuslar),
#     HUD shortcuts (+Su, Sat). Art/UI direction (cozy 3D look) is a LATER art phase.
# Date: 2026-06-29
extends Node2D

const COLS := 5
const START_ROWS := 6
const MAX_ROWS := 8
const TOP_MARGIN := 150.0
const BOT_SPEED := 160.0
const WORK_TIME := 0.25
const MAX_BOTS := 14
const OBSTACLE_CHANCE := 0.14
const GOLDEN_CHANCE := 0.08

# Economy
const START_COINS := 14
const START_WATER := 25
const WATER_MAX := 99
const WATER_BUNDLE := 25
const WATER_BUNDLE_COST := 4
const MAINT_DECAY := 1.0 / 150.0

# Storage / processing
const FLOUR_VALUE := 10
const WHEAT := 3            # crop index of Bugday
const MILL_RATE := 0.5      # wheat->flour per second per windmill level
const WELL_RATE := 0.6      # water per second per well level

# Random events
const EVENT_MIN := 22.0
const EVENT_MAX := 40.0

# Tile lifecycle
const EMPTY := 0
const TILLED := 1
const PLANTED := 2
const GROWING := 3
const RIPE := 4
const OBSTACLE := 5

# Bot task / shop-bot ids (0..5)
const TILL := 0
const PLANT := 1
const WATER := 2
const HARVEST := 3
const CLEAN := 4
const GOLD_HUNT := 5
const TASK_LETTER := ["S", "E", "U", "H", "T", "A"]
const TASK_NAME := ["Suren", "Eken", "Sulayan", "Hasatci", "Temizleyici", "Altin Avcisi"]
const TASK_DESC := [
	"Bos topragi surer",
	"Surulmus yere tohum eker",
	"Ekili tohumu sular",
	"Olgun urunu toplar (depoya)",
	"Tas/engelleri temizler",
	"Olgun toplar, altin sansi yuksek",
]
const TASK_BASE_COST := [8, 10, 12, 15, 9, 26]

# Shop item ids (6+)
const IT_WATER := 6
const IT_REPAIR := 7
const IT_YIELD := 8
const IT_SPEED := 9
const IT_DURA := 10
const IT_WELL := 11
const IT_EXPAND := 12
const IT_WINDMILL := 13
const IT_DEPO := 14

# Crops (index 3 = Bugday = WHEAT)
const CROPS := [
	{"name": "Pancar", "grow": 3.0, "value": 2, "seed": 1, "col": Color("#9B5E7A")},
	{"name": "Patates", "grow": 5.0, "value": 4, "seed": 2, "col": Color("#C9A86A")},
	{"name": "Domates", "grow": 8.0, "value": 8, "seed": 4, "col": Color("#E07A5F")},
	{"name": "Bugday", "grow": 6.0, "value": 3, "seed": 2, "col": Color("#E3C567")},
]

# Palette
const C_BG := Color("#F5E6C8")
const C_SOIL := Color("#7B5B3A")
const C_TILLED := Color("#5E4429")
const C_GROW_A := Color("#A3B899")
const C_GROW_B := Color("#5DBB63")
const C_SUN := Color("#F2C46D")
const C_WATER := Color("#7FA8C9")
const C_BOT_LINE := Color("#7B5B3A")
const C_PANEL := Color("#EAD7AE")
const C_ROCK := Color("#8C8C84")
const C_GOLD := Color("#F4C542")
const C_RED := Color("#C25B5B")
const TASK_COL := [Color("#7B5B3A"), Color("#5DBB63"), Color("#7FA8C9"), Color("#F2C46D"), Color("#8C8C84"), Color("#F4C542")]

class Bot:
	var pos: Vector2
	var task: int = 0
	var seed: int = 0
	var zone: Dictionary = {}
	var target: int = -1
	var state: String = "moving"
	var work: float = 0.0
	var age: float = 0.0
	var condition: float = 1.0

class Ring:
	var pos: Vector2
	var t: float = 0.0
	var col: Color = Color("#F2C46D")

var rows: int
var tile: float
var origin: Vector2
var states: PackedInt32Array
var grow: PackedFloat32Array
var crop_type: PackedInt32Array
var golden: Array = []
var claimed: Array = []
var bots: Array = []
var rings: Array = []
var harvested: int = 0
var coins: int = 0
var water: int = 0
var selected_seed: int = 0
var current_tool: int = -1
var painting: bool = false
var store_open: bool = false
var store_tab: int = 0
var clock: float = 0.0
# Upgrades / buildings
var yield_level: int = 0
var speed_level: int = 0
var dura_level: int = 0
var well_level: int = 0
var windmill_level: int = 0
var depo_level: int = 0
var storage_cap: int = 30
# Storage
var stock: Array = []        # per-crop raw counts
var flour: int = 0
var water_acc: float = 0.0
var mill_acc: float = 0.0
# Events
var event_timer: float = 0.0
var event_text: String = ""
var event_flash: float = 0.0
var sell_boost_t: float = 0.0

func _ready() -> void:
	randomize()
	var vp := get_viewport_rect().size
	tile = vp.x / float(COLS)
	rows = START_ROWS
	coins = START_COINS
	water = START_WATER
	storage_cap = 30
	origin = Vector2(0.0, TOP_MARGIN)
	event_timer = randf_range(EVENT_MIN, EVENT_MAX)
	stock.clear()
	for _c in range(CROPS.size()):
		stock.append(0)
	var n := COLS * rows
	states = PackedInt32Array()
	states.resize(n)
	grow = PackedFloat32Array()
	grow.resize(n)
	crop_type = PackedInt32Array()
	crop_type.resize(n)
	golden.clear()
	claimed.clear()
	for i in range(n):
		states[i] = OBSTACLE if randf() < OBSTACLE_CHANCE else EMPTY
		grow[i] = 0.0
		crop_type[i] = 0
		golden.append(false)
		claimed.append(false)

func yield_mult() -> float:
	return 1.0 + 0.10 * float(yield_level)

func sell_mult() -> float:
	var m := yield_mult()
	if sell_boost_t > 0.0:
		m *= 1.5
	return m

func bot_speed() -> float:
	return BOT_SPEED * (1.0 + 0.15 * float(speed_level))

func wear_rate() -> float:
	return MAINT_DECAY * pow(0.8, float(dura_level))

func raw_count() -> int:
	var t := 0
	for c in stock:
		t += int(c)
	return t

func stock_total() -> int:
	return raw_count() + flour

func _tile_center(idx: int) -> Vector2:
	var c := idx % COLS
	var r := idx / COLS
	return origin + Vector2((c + 0.5) * tile, (r + 0.5) * tile)

func _tile_at(pos: Vector2) -> int:
	if pos.y < origin.y or pos.x < 0.0 or pos.x > COLS * tile:
		return -1
	var c := int(pos.x / tile)
	var r := int((pos.y - origin.y) / tile)
	if r < 0 or r >= rows or c < 0 or c >= COLS:
		return -1
	return r * COLS + c

func _needs(task: int, s: int) -> bool:
	match task:
		TILL:
			return s == EMPTY
		PLANT:
			return s == TILLED
		WATER:
			return s == PLANTED
		HARVEST, GOLD_HUNT:
			return s == RIPE
		CLEAN:
			return s == OBSTACLE
	return false

func _process(delta: float) -> void:
	clock += delta

	# Crop growth
	for i in range(states.size()):
		if states[i] == GROWING:
			var ct := crop_type[i]
			var gt: float = CROPS[ct]["grow"]
			grow[i] += delta / gt
			if grow[i] >= 1.0:
				grow[i] = 1.0
				states[i] = RIPE
				golden[i] = randf() < GOLDEN_CHANCE

	# Passive buildings
	if well_level > 0 and water < WATER_MAX:
		water_acc += float(well_level) * WELL_RATE * delta
		while water_acc >= 1.0 and water < WATER_MAX:
			water += 1
			water_acc -= 1.0
	if windmill_level > 0 and int(stock[WHEAT]) > 0:
		mill_acc += float(windmill_level) * MILL_RATE * delta
		while mill_acc >= 1.0 and int(stock[WHEAT]) > 0:
			stock[WHEAT] = int(stock[WHEAT]) - 1
			flour += 1
			mill_acc -= 1.0

	# Events
	if sell_boost_t > 0.0:
		sell_boost_t -= delta
	if event_flash > 0.0:
		event_flash -= delta
	event_timer -= delta
	if event_timer <= 0.0:
		_trigger_event()
		event_timer = randf_range(EVENT_MIN, EVENT_MAX)

	# Bots
	var wr := wear_rate()
	var spd := bot_speed()
	for bot in bots:
		bot.age += delta
		bot.condition = max(bot.condition - wr * delta, 0.0)
		if bot.condition <= 0.0 or not _can_do(bot):
			_release(bot)
			bot.target = -1
			bot.state = "moving"
			continue
		if bot.state == "moving":
			if bot.target == -1 or not (bot.target in bot.zone) or not _needs(bot.task, states[bot.target]):
				_release(bot)
				_pick_target(bot)
			if bot.target == -1:
				continue
			var tp := _tile_center(bot.target)
			var to_t: Vector2 = tp - bot.pos
			var d: float = to_t.length()
			if d <= 2.0:
				bot.state = "working"
				bot.work = WORK_TIME
			else:
				bot.pos += to_t.normalized() * min(spd * delta, d)
		elif bot.state == "working":
			bot.work -= delta
			if bot.work <= 0.0:
				_apply_task(bot)
				_release(bot)
				bot.target = -1
				bot.state = "moving"

	for ring in rings:
		ring.t += delta
	rings = rings.filter(func(rg): return rg.t < 0.45)

	queue_redraw()

func _pick_target(bot: Bot) -> void:
	var best := -1
	var best_d := INF
	for key in bot.zone:
		var i: int = key
		if i >= claimed.size() or claimed[i]:
			continue
		if not _needs(bot.task, states[i]):
			continue
		var d := bot.pos.distance_squared_to(_tile_center(i))
		if d < best_d:
			best_d = d
			best = i
	bot.target = best
	if best != -1:
		claimed[best] = true

func _release(bot: Bot) -> void:
	if bot.target != -1 and bot.target < claimed.size():
		claimed[bot.target] = false

func _can_do(bot: Bot) -> bool:
	match bot.task:
		WATER:
			return water > 0
		PLANT:
			return coins >= int(CROPS[bot.seed]["seed"])
	return true

func _apply_task(bot: Bot) -> void:
	var idx := bot.target
	match bot.task:
		TILL:
			states[idx] = TILLED
		PLANT:
			var sc: int = CROPS[bot.seed]["seed"]
			if coins < sc:
				return
			coins -= sc
			states[idx] = PLANTED
			crop_type[idx] = bot.seed
		WATER:
			if water <= 0:
				return
			water -= 1
			states[idx] = GROWING
			grow[idx] = 0.0
		HARVEST:
			if _harvest_tile(idx, 5, 0.0):
				states[idx] = EMPTY
		GOLD_HUNT:
			if _harvest_tile(idx, 8, 0.25):
				states[idx] = EMPTY
		CLEAN:
			states[idx] = EMPTY

func _harvest_tile(idx: int, gold_mult: int, find_chance: float) -> bool:
	var ct: int = crop_type[idx]
	var is_gold: bool = golden[idx] or randf() < find_chance
	if is_gold:
		var base: int = CROPS[ct]["value"]
		var pay: int = int(round(float(base) * sell_mult())) * gold_mult
		coins += pay
		harvested += 1
		golden[idx] = false
		_add_ring(_tile_center(idx), C_GOLD)
		return true
	if stock_total() >= storage_cap:
		return false
	stock[ct] = int(stock[ct]) + 1
	harvested += 1
	return true

func _manual(idx: int) -> Color:
	match states[idx]:
		OBSTACLE:
			states[idx] = EMPTY
			return C_ROCK
		EMPTY:
			states[idx] = TILLED
			return C_SOIL
		TILLED:
			var sc: int = CROPS[selected_seed]["seed"]
			if coins < sc:
				return C_RED
			coins -= sc
			states[idx] = PLANTED
			crop_type[idx] = selected_seed
			return C_GROW_A
		PLANTED:
			if water <= 0:
				return C_RED
			water -= 1
			states[idx] = GROWING
			grow[idx] = 0.0
			return C_WATER
		GROWING:
			grow[idx] = min(grow[idx] + 0.12, 1.0)
			return C_GROW_A
		RIPE:
			var wasg: bool = golden[idx]
			if _harvest_tile(idx, 5, 0.0):
				states[idx] = EMPTY
				return C_GOLD if wasg else C_SUN
			return C_RED
	return C_SUN

func _sell_all() -> void:
	var earned := 0
	for ct in range(stock.size()):
		var v: int = CROPS[ct]["value"]
		earned += int(round(float(v) * sell_mult())) * int(stock[ct])
		stock[ct] = 0
	earned += int(round(float(FLOUR_VALUE) * sell_mult())) * flour
	flour = 0
	coins += earned
	if earned > 0:
		var vp := get_viewport_rect().size
		_add_ring(Vector2(vp.x * 0.5, origin.y * 0.5), C_GROW_B)

func _trigger_event() -> void:
	var r := randi() % 4
	if r == 3 and _count_state(RIPE) == 0:
		r = 0
	match r:
		0:
			water = min(water + 25, WATER_MAX)
			event_text = "Yagmur yagdi! Su deposu doldu."
		1:
			_ufo_circle()
			event_text = "UFO gecti! Tarla cemberi - altin urunler!"
		2:
			sell_boost_t = 18.0
			event_text = "Gezgin tuccar geldi! Satis x1.5 (18 sn)"
		3:
			var eaten := _birds_eat()
			event_text = "Kuslar %d olgun urunu yedi!" % eaten
	event_flash = 2.8

func _count_state(s: int) -> int:
	var n := 0
	for v in states:
		if v == s:
			n += 1
	return n

func _ufo_circle() -> void:
	if states.size() == 0:
		return
	var center := randi() % states.size()
	var cc := center % COLS
	var cr := center / COLS
	for dr in range(-1, 2):
		for dc in range(-1, 2):
			var nc := cc + dc
			var nr := cr + dr
			if nc < 0 or nc >= COLS or nr < 0 or nr >= rows:
				continue
			var ni := nr * COLS + nc
			if states[ni] == GROWING:
				states[ni] = RIPE
				grow[ni] = 1.0
				golden[ni] = true
			elif states[ni] == RIPE:
				golden[ni] = true

func _birds_eat() -> int:
	var ripe: Array = []
	for i in range(states.size()):
		if states[i] == RIPE:
			ripe.append(i)
	ripe.shuffle()
	var n: int = min(3, ripe.size())
	for k in range(n):
		var i: int = ripe[k]
		states[i] = EMPTY
		golden[i] = false
	return n

func _add_ring(pos: Vector2, col: Color) -> void:
	var ring := Ring.new()
	ring.pos = pos
	ring.col = col
	rings.append(ring)

func _type_count(task: int) -> int:
	var n := 0
	for bot in bots:
		if bot.task == task:
			n += 1
	return n

func _bot_cost(task: int) -> int:
	var base: int = TASK_BASE_COST[task]
	return int(round(float(base) * pow(1.4, float(_type_count(task)))))

func _buy_bot(task: int) -> bool:
	if bots.size() >= MAX_BOTS:
		return false
	var cost := _bot_cost(task)
	if coins < cost:
		return false
	coins -= cost
	var bot := Bot.new()
	bot.task = task
	bot.seed = selected_seed
	bot.pos = origin + Vector2(COLS * tile * 0.5, rows * tile * 0.5)
	bots.append(bot)
	current_tool = bots.size() - 1
	return true

func water_cost() -> int:
	return WATER_BUNDLE_COST

func _buy_water() -> void:
	if coins < WATER_BUNDLE_COST:
		return
	coins -= WATER_BUNDLE_COST
	water = min(water + WATER_BUNDLE, WATER_MAX)

func repair_cost() -> int:
	return max(3, 3 * bots.size())

func needs_repair() -> bool:
	for b in bots:
		if b.condition < 0.999:
			return true
	return false

func _buy_repair() -> void:
	if bots.is_empty() or not needs_repair():
		return
	var c := repair_cost()
	if coins < c:
		return
	coins -= c
	for b in bots:
		b.condition = 1.0

func yield_cost() -> int:
	return int(round(15.0 * pow(1.6, float(yield_level))))

func speed_cost() -> int:
	return int(round(12.0 * pow(1.6, float(speed_level))))

func dura_cost() -> int:
	return int(round(18.0 * pow(1.7, float(dura_level))))

func well_cost() -> int:
	return int(round(20.0 * pow(1.6, float(well_level))))

func windmill_cost() -> int:
	return int(round(30.0 * pow(1.8, float(windmill_level))))

func depo_cost() -> int:
	return int(round(18.0 * pow(1.5, float(depo_level))))

func _buy_yield() -> void:
	var c := yield_cost()
	if coins >= c:
		coins -= c
		yield_level += 1

func _buy_speed() -> void:
	var c := speed_cost()
	if coins >= c:
		coins -= c
		speed_level += 1

func _buy_dura() -> void:
	var c := dura_cost()
	if coins >= c:
		coins -= c
		dura_level += 1

func _buy_well() -> void:
	var c := well_cost()
	if coins >= c:
		coins -= c
		well_level += 1

func _buy_windmill() -> void:
	var c := windmill_cost()
	if coins >= c:
		coins -= c
		windmill_level += 1

func _buy_depo() -> void:
	var c := depo_cost()
	if coins >= c:
		coins -= c
		depo_level += 1
		storage_cap += 20

func can_expand() -> bool:
	return rows < MAX_ROWS

func expand_cost() -> int:
	return int(round(15.0 * pow(1.5, float(rows - START_ROWS))))

func _buy_expand() -> void:
	if not can_expand():
		return
	var cost := expand_cost()
	if coins < cost:
		return
	coins -= cost
	var base := states.size()
	rows += 1
	states.resize(base + COLS)
	grow.resize(base + COLS)
	crop_type.resize(base + COLS)
	for k in range(COLS):
		states[base + k] = OBSTACLE if randf() < OBSTACLE_CHANCE else EMPTY
		grow[base + k] = 0.0
		crop_type[base + k] = 0
		golden.append(false)
		claimed.append(false)

# ---- Shop item model ----

func _tab_items(tab: int) -> Array:
	match tab:
		0:
			return [TILL, PLANT, WATER, HARVEST, CLEAN, GOLD_HUNT]
		1:
			return [IT_WATER, IT_REPAIR, IT_YIELD, IT_SPEED, IT_DURA, IT_WELL]
		_:
			return [IT_EXPAND, IT_WINDMILL, IT_DEPO]

func _item_cost(id: int) -> int:
	if id <= GOLD_HUNT:
		return _bot_cost(id)
	match id:
		IT_WATER:
			return water_cost()
		IT_REPAIR:
			return repair_cost()
		IT_YIELD:
			return yield_cost()
		IT_SPEED:
			return speed_cost()
		IT_DURA:
			return dura_cost()
		IT_WELL:
			return well_cost()
		IT_WINDMILL:
			return windmill_cost()
		IT_DEPO:
			return depo_cost()
		IT_EXPAND:
			return expand_cost()
	return 0

func _item_enabled(id: int) -> bool:
	var cost := _item_cost(id)
	if id <= GOLD_HUNT:
		return coins >= cost and bots.size() < MAX_BOTS
	match id:
		IT_REPAIR:
			return (not bots.is_empty()) and needs_repair() and coins >= cost
		IT_EXPAND:
			return can_expand() and coins >= cost
		_:
			return coins >= cost

func _item_info(id: int) -> Array:
	# [accent, letter, title, desc]
	if id <= GOLD_HUNT:
		return [TASK_COL[id], TASK_LETTER[id], TASK_NAME[id] + " bot", TASK_DESC[id]]
	match id:
		IT_WATER:
			return [C_WATER, "+", "Su Al (+%d)" % WATER_BUNDLE, "Su deposunu doldurur"]
		IT_REPAIR:
			return [C_RED, "!", "Botlari Onar", "Yipranan botlarin bakimini yapar"]
		IT_YIELD:
			return [C_GOLD, "%", "Verim+ (sv.%d)" % yield_level, "Satis degerini %%10 artirir"]
		IT_SPEED:
			return [C_GROW_B, ">", "Bot Hizi+ (sv.%d)" % speed_level, "Botlar %%15 daha hizli calisir"]
		IT_DURA:
			return [C_SOIL, "#", "Dayaniklilik+ (sv.%d)" % dura_level, "Botlar daha yavas yipranir"]
		IT_WELL:
			return [C_WATER, "~", "Su Kuyusu (sv.%d)" % well_level, "Pasif olarak su uretir"]
		IT_WINDMILL:
			return [C_GROW_A, "M", "Degirmen (sv.%d)" % windmill_level, "Bugdayi una cevirir (un pahali)"]
		IT_DEPO:
			return [C_SOIL, "D", "Depo+ (%d)" % storage_cap, "Depolama kapasitesini artirir"]
		IT_EXPAND:
			return [C_GROW_A, "+", "Tarla Buyut", "+1 sira ekler (%d/%d)" % [rows, MAX_ROWS]]
	return [C_PANEL, "?", "?", ""]

func _item_cost_text(id: int) -> String:
	if id == IT_EXPAND and not can_expand():
		return "MAX"
	if id == IT_REPAIR and bots.is_empty():
		return "-"
	return "%d c" % _item_cost(id)

func _buy_item(id: int) -> bool:
	# returns true if the store should close (bot bought, to paint zone)
	if id <= GOLD_HUNT:
		return _buy_bot(id)
	match id:
		IT_WATER:
			_buy_water()
		IT_REPAIR:
			_buy_repair()
		IT_YIELD:
			_buy_yield()
		IT_SPEED:
			_buy_speed()
		IT_DURA:
			_buy_dura()
		IT_WELL:
			_buy_well()
		IT_WINDMILL:
			_buy_windmill()
		IT_DEPO:
			_buy_depo()
		IT_EXPAND:
			_buy_expand()
	return false

# ---- HUD rects ----

func _shop_btn_rect() -> Rect2:
	var vp := get_viewport_rect().size
	return Rect2(vp.x - 92.0, 8.0, 84.0, 34.0)

func _sat_btn_rect() -> Rect2:
	var vp := get_viewport_rect().size
	return Rect2(vp.x - 182.0, 8.0, 84.0, 34.0)

func _su_btn_rect() -> Rect2:
	var vp := get_viewport_rect().size
	return Rect2(vp.x - 272.0, 8.0, 84.0, 34.0)

func _seed_rects() -> Array:
	var vp := get_viewport_rect().size
	var m := 8.0
	var n := CROPS.size()
	var w := (vp.x - float(n + 1) * m) / float(n)
	var out: Array = []
	for k in range(n):
		out.append(Rect2(m + float(k) * (w + m), 50.0, w, 34.0))
	return out

func _tool_rects() -> Array:
	var out: Array = []
	var x := 10.0
	var y := 92.0
	var w := 50.0
	var h := 38.0
	var m := 6.0
	out.append(Rect2(x, y, w, h))
	for i in range(bots.size()):
		out.append(Rect2(x + float(i + 1) * (w + m), y, w, h))
	return out

const TAB_NAMES := ["Botlar", "Yukselt", "Ciftlik"]
const STORE_ROW_H := 80.0
const STORE_ROW_GAP := 9.0
const STORE_Y0 := 150.0

func _store_tab_rects() -> Array:
	var vp := get_viewport_rect().size
	var m := 8.0
	var w := (vp.x - 48.0 - 2.0 * m) / 3.0
	var out: Array = []
	for k in range(3):
		out.append(Rect2(24.0 + float(k) * (w + m), 100.0, w, 40.0))
	return out

func _store_item_rects(count: int) -> Array:
	var vp := get_viewport_rect().size
	var out: Array = []
	for k in range(count):
		out.append(Rect2(24.0, STORE_Y0 + float(k) * (STORE_ROW_H + STORE_ROW_GAP), vp.x - 48.0, STORE_ROW_H))
	return out

func _store_close_rect() -> Rect2:
	var vp := get_viewport_rect().size
	return Rect2(24.0, vp.y - 70.0, vp.x - 48.0, 54.0)

# ---- Input ----

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_press(event.position)
		else:
			painting = false
	elif event is InputEventScreenDrag:
		if painting:
			_paint(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press(event.position)
		else:
			painting = false
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		if painting:
			_paint(event.position)

func _press(pos: Vector2) -> void:
	if store_open:
		_press_store(pos)
		return

	if _shop_btn_rect().has_point(pos):
		store_open = true
		return
	if _sat_btn_rect().has_point(pos):
		_sell_all()
		return
	if _su_btn_rect().has_point(pos):
		_buy_water()
		return

	var seeds := _seed_rects()
	for k in range(seeds.size()):
		if (seeds[k] as Rect2).has_point(pos):
			selected_seed = k
			return

	var trs := _tool_rects()
	for i in range(trs.size()):
		if (trs[i] as Rect2).has_point(pos):
			current_tool = i - 1
			return

	var idx := _tile_at(pos)
	if idx == -1:
		return
	if current_tool == -1:
		var col := _manual(idx)
		_add_ring(pos, col)
	else:
		painting = true
		_paint(pos)

func _press_store(pos: Vector2) -> void:
	if _store_close_rect().has_point(pos):
		store_open = false
		return
	var tabs := _store_tab_rects()
	for k in range(3):
		if (tabs[k] as Rect2).has_point(pos):
			store_tab = k
			return
	var items := _tab_items(store_tab)
	var rrs := _store_item_rects(items.size())
	for i in range(items.size()):
		if (rrs[i] as Rect2).has_point(pos):
			if _buy_item(items[i]):
				store_open = false
			return

func _paint(pos: Vector2) -> void:
	if current_tool < 0 or current_tool >= bots.size():
		return
	var idx := _tile_at(pos)
	if idx == -1:
		return
	bots[current_tool].zone[idx] = true

# ---- Drawing ----

func _tile_color(idx: int) -> Color:
	match states[idx]:
		EMPTY:
			return C_SOIL
		OBSTACLE:
			return C_SOIL.darkened(0.05)
		TILLED:
			return C_TILLED
		PLANTED:
			return C_TILLED.lerp(C_SOIL, 0.25)
		_:
			return C_TILLED.darkened(0.12)

func _draw() -> void:
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), C_BG, true)
	var font := ThemeDB.fallback_font

	for i in range(states.size()):
		var c := i % COLS
		var r := i / COLS
		var pos := origin + Vector2(c * tile, r * tile)
		var rect := Rect2(pos + Vector2(2, 2), Vector2(tile - 4, tile - 4))
		draw_rect(rect, _tile_color(i), true)
		draw_rect(rect, C_TILLED.darkened(0.15), false, 2.0)
		if states[i] == OBSTACLE:
			_draw_rock(pos)
		else:
			if states[i] != EMPTY:
				for fr in range(3):
					var fy := pos.y + tile * (0.32 + 0.18 * float(fr))
					draw_line(Vector2(pos.x + 10.0, fy), Vector2(pos.x + tile - 10.0, fy), C_SOIL.darkened(0.18), 1.5)
			_draw_crop(i, pos)

	for bi in range(bots.size()):
		var bot: Bot = bots[bi]
		var zcol: Color = TASK_COL[bot.task]
		var sel := bi == current_tool
		var wdt := 4.0 if sel else 1.5
		var alpha := 0.95 if sel else 0.30
		for key in bot.zone:
			var idx: int = key
			var cc := idx % COLS
			var rr := idx / COLS
			var zpos := origin + Vector2(cc * tile, rr * tile)
			var zrect := Rect2(zpos + Vector2(3, 3), Vector2(tile - 6, tile - 6))
			draw_rect(zrect, Color(zcol.r, zcol.g, zcol.b, alpha), false, wdt)

	for ring in rings:
		var a: float = 1.0 - (ring.t / 0.45)
		var ring_rad: float = 6.0 + ring.t * 70.0
		draw_arc(ring.pos, ring_rad, 0.0, TAU, 24, Color(ring.col.r, ring.col.g, ring.col.b, a * 0.85), 3.0)

	for bot in bots:
		var scl: float = clamp(bot.age / 0.2, 0.0, 1.0)
		var rad: float = tile * 0.26 * (0.5 + 0.5 * scl)
		var bcol: Color = TASK_COL[bot.task]
		draw_circle(bot.pos, rad, bcol)
		draw_arc(bot.pos, rad, 0.0, TAU, 20, C_BOT_LINE, 2.0)
		draw_string(font, bot.pos + Vector2(-rad * 0.4, rad * 0.45), TASK_LETTER[bot.task], HORIZONTAL_ALIGNMENT_LEFT, -1, int(rad * 1.2), C_BG)
		if bot.state == "working":
			draw_arc(bot.pos, rad + 5.0, 0.0, TAU, 20, C_SUN, 3.0)
		if bot.condition < 0.999:
			var ccol := C_GROW_B.lerp(C_RED, 1.0 - bot.condition)
			draw_arc(bot.pos, rad + 9.0, -PI / 2.0, -PI / 2.0 + bot.condition * TAU, 22, ccol, 2.5)
		if bot.condition <= 0.0:
			draw_string(font, bot.pos + Vector2(-4, -rad - 8.0), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, C_RED)

	_draw_hud(font, vp)

	if event_flash > 0.0:
		_draw_event(font, vp)

	if store_open:
		_draw_store()

func _draw_hud(font: Font, vp: Vector2) -> void:
	# Top buttons
	var su := _su_btn_rect()
	var su_on := coins >= WATER_BUNDLE_COST
	draw_rect(su, C_WATER if su_on else C_WATER.lerp(C_BG, 0.5), true)
	draw_rect(su, C_BOT_LINE, false, 2.0)
	draw_string(font, su.position + Vector2(8, 23), "+Su %d" % WATER_BUNDLE, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, C_BG)

	var sat := _sat_btn_rect()
	var sat_on := stock_total() > 0
	draw_rect(sat, C_GROW_B if sat_on else C_GROW_B.lerp(C_BG, 0.55), true)
	draw_rect(sat, C_BOT_LINE, false, 2.0)
	draw_string(font, sat.position + Vector2(12, 24), "Sat", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, C_BG)

	var sb := _shop_btn_rect()
	draw_rect(sb, C_BOT_LINE.lerp(C_BG, 0.1), true)
	draw_rect(sb, C_SUN, false, 2.0)
	draw_string(font, sb.position + Vector2(8, 24), "Magaza", HORIZONTAL_ALIGNMENT_LEFT, -1, 17, C_BG)

	# Status lines
	draw_string(font, Vector2(12, 24), "Para %d   Su %d/%d" % [coins, water, WATER_MAX], HORIZONTAL_ALIGNMENT_LEFT, -1, 21, C_SOIL)
	var line2 := "Depo %d/%d   Un %d" % [stock_total(), storage_cap, flour]
	if sell_boost_t > 0.0:
		line2 += "   x1.5!"
	draw_string(font, Vector2(12, 44), line2, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, C_BOT_LINE)

	# Seed selector
	var seeds := _seed_rects()
	for k in range(seeds.size()):
		var sr: Rect2 = seeds[k]
		var cd: Dictionary = CROPS[k]
		var ssel := k == selected_seed
		var base_col: Color = cd["col"]
		var sfill: Color = base_col if ssel else base_col.lerp(C_BG, 0.6)
		draw_rect(sr, sfill, true)
		draw_rect(sr, C_SUN if ssel else C_BOT_LINE, false, 2.0 if ssel else 1.0)
		draw_string(font, sr.position + Vector2(5, 16), "%s" % cd["name"], HORIZONTAL_ALIGNMENT_LEFT, sr.size.x - 8.0, 13, C_TILLED)
		draw_string(font, sr.position + Vector2(5, 30), "a%d s%d" % [int(cd["seed"]), int(cd["value"])], HORIZONTAL_ALIGNMENT_LEFT, sr.size.x - 8.0, 12, C_TILLED)

	# Tool palette
	var trs := _tool_rects()
	var hand_rect: Rect2 = trs[0]
	var hsel := current_tool == -1
	draw_rect(hand_rect, C_SUN if hsel else C_BG.lerp(C_SUN, 0.3), true)
	draw_rect(hand_rect, C_BOT_LINE, false, 2.0 if hsel else 1.0)
	draw_string(font, hand_rect.position + Vector2(10, 26), "El", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, C_TILLED)
	for i in range(bots.size()):
		var tr: Rect2 = trs[i + 1]
		var bot: Bot = bots[i]
		var bcol: Color = TASK_COL[bot.task]
		var bsel := current_tool == i
		draw_rect(tr, bcol if bsel else bcol.lerp(C_BG, 0.55), true)
		draw_rect(tr, C_SUN if bsel else C_BOT_LINE, false, 2.0 if bsel else 1.0)
		draw_string(font, tr.position + Vector2(18, 26), TASK_LETTER[bot.task], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, C_BG if bsel else C_TILLED)

	# Hint
	var hint := ""
	if current_tool == -1:
		hint = "El: tas->temizle, sur>ek>sula. Hasat depoya gider - 'Sat' ile paraya cevir."
	else:
		hint = "%s botu secili - parmakla bolgesini boya" % TASK_NAME[current_tool]
	var hy: float = min(origin.y + rows * tile + 24.0, vp.y - 16.0)
	draw_string(font, Vector2(14, hy), hint, HORIZONTAL_ALIGNMENT_LEFT, vp.x - 20.0, 16, C_BOT_LINE)

func _draw_event(font: Font, vp: Vector2) -> void:
	var a: float = clamp(event_flash / 2.8, 0.0, 1.0)
	var bw := vp.x - 60.0
	var br := Rect2(30.0, vp.y * 0.30, bw, 58.0)
	draw_rect(br, Color(C_SOIL.r, C_SOIL.g, C_SOIL.b, 0.92 * a), true)
	draw_rect(br, Color(C_GOLD.r, C_GOLD.g, C_GOLD.b, a), false, 3.0)
	draw_string(font, br.position + Vector2(16, 37), event_text, HORIZONTAL_ALIGNMENT_LEFT, bw - 32.0, 21, Color(1, 1, 1, a))

func _store_row(r: Rect2, accent: Color, letter: String, title: String, desc: String, cost_text: String, on: bool) -> void:
	var font := ThemeDB.fallback_font
	draw_rect(r, C_PANEL, true)
	draw_rect(r, accent, false, 3.0)
	draw_rect(Rect2(r.position + Vector2(8, 8), Vector2(50, r.size.y - 16)), accent if on else accent.lerp(C_BG, 0.5), true)
	draw_string(font, r.position + Vector2(18, r.size.y * 0.5 + 11), letter, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, C_BG)
	draw_string(font, r.position + Vector2(72, 33), title, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 190.0, 22, C_SOIL)
	draw_string(font, r.position + Vector2(72, 59), desc, HORIZONTAL_ALIGNMENT_LEFT, r.size.x - 190.0, 15, C_BOT_LINE)
	var cc: Color = C_GROW_B if on else Color(0.62, 0.42, 0.42)
	draw_string(font, r.position + Vector2(r.size.x - 104.0, r.size.y * 0.5 + 9), cost_text, HORIZONTAL_ALIGNMENT_LEFT, 100.0, 24, cc)

func _draw_store() -> void:
	var vp := get_viewport_rect().size
	var font := ThemeDB.fallback_font
	draw_rect(Rect2(Vector2.ZERO, vp), C_BG, true)
	draw_string(font, Vector2(24, 78), "MAGAZA", HORIZONTAL_ALIGNMENT_LEFT, -1, 34, C_SOIL)
	draw_string(font, Vector2(vp.x - 230.0, 70.0), "Para %d   Su %d" % [coins, water], HORIZONTAL_ALIGNMENT_LEFT, -1, 22, C_SOIL)

	var tabs := _store_tab_rects()
	for k in range(3):
		var tr: Rect2 = tabs[k]
		var on := k == store_tab
		draw_rect(tr, C_SOIL if on else C_PANEL, true)
		draw_rect(tr, C_BOT_LINE, false, 2.0)
		draw_string(font, tr.position + Vector2(tr.size.x * 0.5 - 36.0, 27), TAB_NAMES[k], HORIZONTAL_ALIGNMENT_LEFT, -1, 19, C_BG if on else C_SOIL)

	var items := _tab_items(store_tab)
	var rrs := _store_item_rects(items.size())
	for i in range(items.size()):
		var id: int = items[i]
		var info := _item_info(id)
		var accent: Color = info[0]
		var letter: String = info[1]
		var title: String = info[2]
		var desc: String = info[3]
		_store_row(rrs[i], accent, letter, title, desc, _item_cost_text(id), _item_enabled(id))

	var cr := _store_close_rect()
	draw_rect(cr, C_SOIL, true)
	draw_rect(cr, C_BOT_LINE, false, 2.0)
	draw_string(font, cr.position + Vector2(cr.size.x * 0.5 - 40.0, 36), "Kapat", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, C_BG)

func _draw_rock(pos: Vector2) -> void:
	var c := pos + Vector2(tile * 0.5, tile * 0.55)
	draw_circle(c, tile * 0.22, C_ROCK)
	draw_circle(c + Vector2(-tile * 0.12, tile * 0.05), tile * 0.13, C_ROCK.darkened(0.1))
	draw_circle(c + Vector2(tile * 0.13, tile * 0.02), tile * 0.11, C_ROCK.lightened(0.08))
	draw_arc(c, tile * 0.22, 0.0, TAU, 18, C_ROCK.darkened(0.25), 2.0)

func _draw_crop(idx: int, pos: Vector2) -> void:
	var center := pos + Vector2(tile * 0.5, tile * 0.5)
	var base := pos + Vector2(tile * 0.5, tile * 0.78)
	var ct := crop_type[idx]
	var col: Color = CROPS[ct]["col"]
	match states[idx]:
		PLANTED:
			draw_circle(base, tile * 0.06, C_SOIL.darkened(0.2))
			draw_line(base, base - Vector2(0, tile * 0.10), C_GROW_A, 2.0)
			var dp := pos + Vector2(tile * 0.78, tile * 0.22)
			draw_arc(dp, tile * 0.07, 0.0, TAU, 14, Color(C_WATER.r, C_WATER.g, C_WATER.b, 0.95), 2.0)
			draw_circle(dp + Vector2(0, tile * 0.02), tile * 0.02, C_WATER)
		GROWING:
			var g: float = grow[idx]
			var h := tile * (0.12 + 0.32 * g)
			var top := base - Vector2(0, h)
			var sc := C_GROW_A.lerp(col, g)
			draw_line(base, top, sc, 3.0)
			draw_circle(top + Vector2(-tile * 0.08, tile * 0.02), tile * 0.06 * (0.5 + g), sc)
			draw_circle(top + Vector2(tile * 0.08, tile * 0.02), tile * 0.06 * (0.5 + g), sc)
			draw_circle(top, tile * 0.07 * (0.4 + 0.6 * g), sc)
			draw_arc(center, tile * 0.40, 0.0, TAU, 28, Color(C_BG.r, C_BG.g, C_BG.b, 0.5), 2.0)
			draw_arc(center, tile * 0.40, -PI / 2.0, -PI / 2.0 + g * TAU, 28, C_GROW_B, 4.0)
		RIPE:
			var breathe := 1.0 + 0.06 * sin(clock * 3.0 + float(idx))
			var halo: Color = C_GOLD if golden[idx] else C_SUN
			draw_circle(center, tile * 0.42, Color(halo.r, halo.g, halo.b, 0.20 if golden[idx] else 0.18))
			var top2 := base - Vector2(0, tile * 0.40)
			draw_line(base, top2, C_GROW_B, 3.0)
			var rr := tile * 0.12 * breathe
			var fruit: Color = C_GOLD if golden[idx] else col
			draw_circle(top2, rr, fruit)
			draw_circle(top2 + Vector2(-tile * 0.13, tile * 0.06), rr * 0.85, fruit)
			draw_circle(top2 + Vector2(tile * 0.13, tile * 0.06), rr * 0.85, fruit)
			draw_circle(top2 - Vector2(rr * 0.3, rr * 0.3), rr * 0.3, C_SUN if not golden[idx] else Color("#FFF3C4"))
			if golden[idx]:
				draw_arc(top2, rr * 1.5, 0.0, TAU, 18, C_GOLD, 2.0)
