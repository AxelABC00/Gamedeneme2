# PROTOTYPE - 2D->3D migration, Phase A+B
# sim.gd — game state + rules, render-independent (ported from the 2D prototype).
# No visuals, no input here. world.gd reads this and renders it in 3D.
# Date: 2026-06-29
extends RefCounted
class_name SimState

# --- grid / lifecycle (ported verbatim from prototypes/bot-orchestration-concept) ---
const COLS := 8
const START_ROWS := 6
const MAX_ROWS := 8
const GOLDEN_CHANCE := 0.08
const OBSTACLE_CHANCE := 0.14

const EMPTY := 0
const TILLED := 1
const PLANTED := 2
const GROWING := 3
const RIPE := 4
const OBSTACLE := 5

# Bot tasks (0..5) + shop metadata (ported from 2D)
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
const TASK_COL := [Color("#7B5B3A"), Color("#5DBB63"), Color("#7FA8C9"), Color("#F2C46D"), Color("#8C8C84"), Color("#F4C542")]

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
const IT_SCARE := 15

# Store palette accents (ported; the 3D store reads these for row tinting)
const C_SOIL := Color("#7B5B3A")
const C_GROW_A := Color("#A3B899")
const C_GROW_B := Color("#5DBB63")
const C_WATER := Color("#7FA8C9")
const C_GOLD := Color("#F4C542")
const C_RED := Color("#C25B5B")
const C_PANEL := Color("#EAD7AE")

const CROPS := [
	{"name": "Pancar", "grow": 3.0, "value": 2, "seed": 1, "col": Color("#9B5E7A")},
	{"name": "Patates", "grow": 5.0, "value": 4, "seed": 2, "col": Color("#C9A86A")},
	{"name": "Domates", "grow": 8.0, "value": 8, "seed": 4, "col": Color("#E07A5F")},
	{"name": "Bugday", "grow": 6.0, "value": 3, "seed": 2, "col": Color("#E3C567")},
	{"name": "Kabak", "grow": 7.0, "value": 6, "seed": 3, "col": Color("#E08A2F")},
	{"name": "Uzum", "grow": 9.0, "value": 10, "seed": 4, "col": Color("#7D5BA6")},
	{"name": "Karpuz", "grow": 11.0, "value": 13, "seed": 5, "col": Color("#3FA34D")},
]

# --- economy constants (ported) ---
const WHEAT := 3            # CROPS index of Bugday (sold as flour when a mill exists)
const START_COINS := 14
const START_WATER := 25
const WATER_MAX := 99
const WATER_BUNDLE := 25
const WATER_COST := 4
const FLOUR_VALUE := 10
const START_STORAGE := 20

# --- bots / buildings / events constants (ported) ---
const MAX_BOTS := 14
const BOT_SPEED := 160.0     # base px/s (legacy 2D view tuning; unused in 3D)
const BOT_SPEED_TILES := 2.4 # base movement speed in grid tiles/sec (sim-space)
const BOT_ARRIVE := 0.06     # grid distance at which a bot starts working its target
const WORK_TIME := 0.25
const MAINT_DECAY := 1.0 / 900.0   # ~15 min to fully wear; worn bots slow down, never hard-stop
const COND_FLOOR := 0.30           # condition never drops below this, so bots always keep working
const COND_SPEED_MIN := 0.5        # slowest a fully-worn bot moves/works (fraction of normal)
const MILL_RATE := 0.5      # wheat->flour per second per windmill level
const WELL_RATE := 0.6      # water per second per well level
const SCARECROW_MAX := 5
const SELL_BOOST_DUR := 18.0
# random events (Phase H) — ported from the 2D prototype
const EVENT_MIN := 45.0      # seconds between events (min)
const EVENT_MAX := 80.0      # seconds between events (max)
const RAIN_DUR := 5.0
const UFO_DUR := 5.5
const BIRDS_DUR := 4.0
const BIRD_COUNT := 6
const RAIN_WATER := 25       # water refilled by a rain event

# --- state ---
var rows: int
var states: PackedInt32Array
var grow: PackedFloat32Array
var crop_type: PackedInt32Array
var golden: Array = []
# economy (ported; drives manual work from Phase C)
var coins: int = START_COINS
var water: int = START_WATER
var stock: PackedInt32Array        # harvested crops awaiting sale, per crop type
var flour: int = 0
var harvested: int = 0
var storage_cap: int = START_STORAGE
var selected_seed: int = WHEAT     # which crop a tap plants (HUD picker)

# upgrades / buildings (ported)
var yield_level: int = 0
var speed_level: int = 0
var dura_level: int = 0
var well_level: int = 0
var windmill_level: int = 0
var depo_level: int = 0
var scarecrow_charges: int = 0
var sell_boost_t: float = 0.0      # trader event boost (set in Phase H events)
var water_acc: float = 0.0         # passive-well fractional water accumulator
var mill_acc: float = 0.0          # windmill fractional flour accumulator

# --- events (Phase H) — pure logic; world.gd reads these to render the 3D spectacle ---
var event_timer: float = 0.0       # counts down to the next random event
var event_msg: String = ""         # latest banner text (view shows it on event_seq change)
var event_seq: int = 0             # bumped whenever a new message should be shown (view watches this)
var rain_t: float = 0.0            # rain remaining (sec)
var ufo_active: bool = false
var ufo_t: float = 0.0             # 0..UFO_DUR flight progress
var ufo_target: int = -1
var ufo_fired: bool = false        # crop-circle applied once at mid-flight
var birds_active: bool = false
var birds_t: float = 0.0
var birds_blocked: bool = false    # a scarecrow charge repelled this flock
var birds_done: bool = false       # the eat/repel beat already resolved this flock

# bots — full logic state. gpos is the bot's position in GRID space (col,row floats),
# render-independent; world.gd maps gpos -> 3D each frame. AI/timing live here (sim).
class Bot:
	var task: int = 0
	var seed: int = 0
	var zone: Dictionary = {}    # {tile_idx: true} — painted work area
	var target: int = -1
	var state: String = "moving" # "moving" | "working"
	var work: float = 0.0
	var age: float = 0.0
	var condition: float = 1.0
	var gpos: Vector2 = Vector2.ZERO
	var home: Vector2 = Vector2.ZERO  # parking spot at the front edge when idle
var bots: Array = []
var claimed: Array = []          # per-tile: a bot has reserved this tile (no double-targeting)

# Deterministic demo layout so the 3D view shows the FULL lifecycle at a glance
# (one row per stage). Proves the state->3D mapping for Phase B.
func setup_demo() -> void:
	rows = START_ROWS
	var n := COLS * rows
	states = PackedInt32Array(); states.resize(n)
	grow = PackedFloat32Array(); grow.resize(n)
	crop_type = PackedInt32Array(); crop_type.resize(n)
	stock = PackedInt32Array(); stock.resize(CROPS.size())
	claimed.clear(); claimed.resize(n)
	event_timer = randf_range(EVENT_MIN, EVENT_MAX)
	golden.clear()
	for i in range(n):
		golden.append(false)
		crop_type[i] = i % CROPS.size()
		var r: int = i / COLS
		var c: int = i % COLS
		match r:
			0:
				states[i] = OBSTACLE if (c % 3 == 0) else EMPTY
			1:
				states[i] = TILLED
			2:
				states[i] = PLANTED
			3:
				states[i] = GROWING
				grow[i] = 0.35
			4:
				states[i] = GROWING
				grow[i] = 0.80
			_:
				states[i] = RIPE
				grow[i] = 1.0
				golden[i] = (c % 4 == 0)

# A fresh farm for a brand-new player: empty plots with a scattering of rocks to clear.
# Economy/upgrades stay at the constructor defaults (START_COINS, START_WATER, ...).
func new_game() -> void:
	rows = START_ROWS
	var n := COLS * rows
	states = PackedInt32Array(); states.resize(n)
	grow = PackedFloat32Array(); grow.resize(n)
	crop_type = PackedInt32Array(); crop_type.resize(n)
	stock = PackedInt32Array(); stock.resize(CROPS.size())
	claimed.clear(); claimed.resize(n)
	golden.clear()
	for i in range(n):
		golden.append(false)
		crop_type[i] = 0
		grow[i] = 0.0
		states[i] = OBSTACLE if randf() < OBSTACLE_CHANCE else EMPTY
	event_timer = randf_range(EVENT_MIN, EVENT_MAX)

# --- save / load (Phase: production hardening) ---
# Serialize the whole mutable game state to a plain Dictionary (JSON-friendly).
func to_dict() -> Dictionary:
	var bot_list: Array = []
	for b in bots:
		var zone_keys: Array = []
		for k in b.zone:
			zone_keys.append(int(k))
		bot_list.append({
			"task": b.task, "seed": b.seed, "zone": zone_keys,
			"target": b.target, "state": b.state, "work": b.work,
			"age": b.age, "condition": b.condition,
			"gx": b.gpos.x, "gy": b.gpos.y, "hx": b.home.x, "hy": b.home.y,
		})
	return {
		"v": 1,
		"rows": rows,
		"states": _arr_i(states),
		"grow": _arr_f(grow),
		"crop_type": _arr_i(crop_type),
		"golden": golden.duplicate(),
		"coins": coins, "water": water,
		"stock": _arr_i(stock), "flour": flour,
		"harvested": harvested, "storage_cap": storage_cap,
		"selected_seed": selected_seed,
		"yield_level": yield_level, "speed_level": speed_level,
		"dura_level": dura_level, "well_level": well_level,
		"windmill_level": windmill_level, "depo_level": depo_level,
		"scarecrow_charges": scarecrow_charges,
		"event_timer": event_timer,
		"bots": bot_list,
	}

# Restore state written by to_dict(). Transient event visuals always start cleared.
func from_dict(d: Dictionary) -> void:
	rows = int(d.get("rows", START_ROWS))
	states = _pack_i(d.get("states", []))
	grow = _pack_f(d.get("grow", []))
	crop_type = _pack_i(d.get("crop_type", []))
	golden = (d.get("golden", []) as Array).duplicate()
	var n := states.size()
	if grow.size() != n: grow.resize(n)
	if crop_type.size() != n: crop_type.resize(n)
	while golden.size() < n: golden.append(false)
	claimed.clear(); claimed.resize(n)
	coins = int(d.get("coins", START_COINS))
	water = int(d.get("water", START_WATER))
	stock = _pack_i(d.get("stock", []))
	if stock.size() != CROPS.size(): stock.resize(CROPS.size())
	flour = int(d.get("flour", 0))
	harvested = int(d.get("harvested", 0))
	storage_cap = int(d.get("storage_cap", START_STORAGE))
	selected_seed = int(d.get("selected_seed", WHEAT))
	yield_level = int(d.get("yield_level", 0))
	speed_level = int(d.get("speed_level", 0))
	dura_level = int(d.get("dura_level", 0))
	well_level = int(d.get("well_level", 0))
	windmill_level = int(d.get("windmill_level", 0))
	depo_level = int(d.get("depo_level", 0))
	scarecrow_charges = int(d.get("scarecrow_charges", 0))
	event_timer = float(d.get("event_timer", randf_range(EVENT_MIN, EVENT_MAX)))
	rain_t = 0.0; ufo_active = false; birds_active = false; sell_boost_t = 0.0
	bots.clear()
	for bd in (d.get("bots", []) as Array):
		var b := Bot.new()
		b.task = int(bd.get("task", 0))
		b.seed = int(bd.get("seed", 0))
		b.target = int(bd.get("target", -1))
		b.state = String(bd.get("state", "moving"))
		b.work = float(bd.get("work", 0.0))
		b.age = float(bd.get("age", 0.0))
		b.condition = float(bd.get("condition", 1.0))
		b.gpos = Vector2(float(bd.get("gx", 0.0)), float(bd.get("gy", 0.0)))
		b.home = Vector2(float(bd.get("hx", 0.0)), float(bd.get("hy", 0.0)))
		b.zone = {}
		for k in (bd.get("zone", []) as Array):
			b.zone[int(k)] = true
		bots.append(b)

func _arr_i(p) -> Array:
	var a: Array = []
	for v in p: a.append(int(v))
	return a

func _arr_f(p) -> Array:
	var a: Array = []
	for v in p: a.append(float(v))
	return a

func _pack_i(a) -> PackedInt32Array:
	var p := PackedInt32Array()
	for v in (a as Array): p.append(int(v))
	return p

func _pack_f(a) -> PackedFloat32Array:
	var p := PackedFloat32Array()
	for v in (a as Array): p.append(float(v))
	return p

# Time-based growth (ported). Returns true if any tile changed stage (view refresh).
func tick(delta: float) -> bool:
	var changed := false
	for i in range(states.size()):
		if states[i] == GROWING:
			var gt: float = CROPS[crop_type[i]]["grow"]
			grow[i] += delta / gt
			if grow[i] >= 1.0:
				grow[i] = 1.0
				states[i] = RIPE
				changed = true

	# Passive buildings (ported): well makes water, windmill turns wheat into flour.
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

	if sell_boost_t > 0.0:
		sell_boost_t = max(sell_boost_t - delta, 0.0)

	if tick_events(delta):
		changed = true

	if tick_bots(delta):
		changed = true
	return changed

# Advances all active events + the countdown to the next one. Returns true if a tile
# changed (UFO crop-circle / birds eating) so the view refreshes affected tiles.
func tick_events(delta: float) -> bool:
	var changed := false
	if rain_t > 0.0:
		rain_t = max(rain_t - delta, 0.0)
	if ufo_active:
		ufo_t += delta
		# fire the crop-circle once at mid-flight (render-independent; view drops the beam then)
		if not ufo_fired and ufo_t >= UFO_DUR * 0.5 and ufo_target >= 0:
			_ufo_circle_at(ufo_target)
			ufo_fired = true
			changed = true
		if ufo_t >= UFO_DUR:
			ufo_active = false
	if birds_active:
		birds_t += delta
		if not birds_done and birds_t >= BIRDS_DUR * 0.5:
			birds_done = true
			if birds_blocked:
				_emit_event("Korkuluk kuslari kacirdi!")
			else:
				var eaten := _birds_eat()
				_emit_event("Kuslar %d olgun urunu yedi!" % eaten)
				if eaten > 0:
					changed = true
		if birds_t >= BIRDS_DUR:
			birds_active = false
	event_timer -= delta
	if event_timer <= 0.0:
		_trigger_event()
		event_timer = randf_range(EVENT_MIN, EVENT_MAX)
	return changed

# Set the banner text + bump the sequence so the view shows a fresh toast.
func _emit_event(msg: String) -> void:
	event_msg = msg
	event_seq += 1

func _count_state(s: int) -> int:
	var n := 0
	for v in states:
		if v == s:
			n += 1
	return n

func _trigger_event() -> void:
	# Weighted pool: rain/UFO are rare spectacle, trader/birds common.
	# rain x2, trader x3, ufo x1; birds x3 only when there is ripe to eat.
	var pool: Array = [0, 0, 2, 2, 2, 1]
	if _count_state(RIPE) > 0:
		pool.append(3); pool.append(3); pool.append(3)
	var r: int = pool[randi() % pool.size()]
	match r:
		0:
			water = min(water + RAIN_WATER, WATER_MAX)
			rain_t = RAIN_DUR
			# rain waters every planted tile for free (PLANTED -> GROWING), so it
			# visibly "wets the soil" and pushes the whole field along at once.
			for i in range(states.size()):
				if states[i] == PLANTED:
					states[i] = GROWING
					grow[i] = 0.0
			_emit_event("Yagmur yagiyor! Topraklar suluyor.")
		1:
			ufo_active = true
			ufo_t = 0.0
			ufo_fired = false
			ufo_target = randi() % states.size()
			_emit_event("UFO geldi! Tarla cemberi - altin urunler!")
		2:
			sell_boost_t = SELL_BOOST_DUR
			_emit_event("Gezgin tuccar geldi! Satis x1.5 (18 sn)")
		3:
			birds_active = true
			birds_t = 0.0
			birds_done = false
			birds_blocked = scarecrow_charges > 0
			if birds_blocked:
				scarecrow_charges -= 1
			_emit_event("Kuslar geliyor!")

# UFO 3x3 crop-circle: growing tiles snap ripe, ripe tiles turn golden (x value).
func _ufo_circle_at(center: int) -> void:
	if states.size() == 0 or center < 0 or center >= states.size():
		return
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

# Birds eat up to 3 random ripe crops. Returns how many were eaten.
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

# ============================================================================
# Bot AI (ported from the 2D prototype). Render-independent: positions are in
# GRID space (gpos), movement/targeting/work-timing all happen here. world.gd
# only reads bot.gpos / bot.state each frame to drive the 3D models.
# Returns true if any tile state changed (so the view refreshes that tile).
# ============================================================================
func tick_bots(delta: float) -> bool:
	var changed := false
	var wr := wear_rate()
	var spd := bot_speed_tiles()
	for i in range(bots.size()):
		var bot: Bot = bots[i]
		bot.age += delta
		# Worn bots slow down but never fully stop (floor) — so they never just freeze.
		bot.condition = max(bot.condition - wr * delta, COND_FLOOR)
		var cond_f: float = lerp(COND_SPEED_MIN, 1.0, inverse_lerp(COND_FLOOR, 1.0, bot.condition))
		var bspd: float = spd * cond_f
		# Can't do this task right now (no water / no coins) — head home and wait.
		if not _can_do(bot):
			_release(bot)
			bot.target = -1
			bot.state = "moving"
			_go_home(bot, i, bspd, delta)
			continue
		if bot.state == "moving":
			if bot.target == -1 or not (bot.target in bot.zone) or not needs(bot.task, states[bot.target]):
				_release(bot)
				_pick_target(bot)
			if bot.target == -1:
				# nothing to do — walk to the parking spot instead of blocking the field
				_go_home(bot, i, bspd, delta)
				continue
			var tp := _grid_center(bot.target)
			var to_t: Vector2 = tp - bot.gpos
			var d: float = to_t.length()
			if d <= BOT_ARRIVE:
				bot.gpos = tp
				bot.state = "working"
				bot.work = WORK_TIME / cond_f   # worn bots also work a little slower
			else:
				bot.gpos += to_t.normalized() * min(bspd * delta, d)
		elif bot.state == "working":
			bot.work -= delta
			if bot.work <= 0.0:
				if _apply_task(bot):
					changed = true
				_release(bot)
				bot.target = -1
				bot.state = "moving"

	# Keep bots from stacking/blocking each other. Two passes so chains of bots
	# resolve in one tick instead of jittering apart over several frames. A working
	# bot is anchored on its tile (moving it would break harvesting), so when a mover
	# meets a worker the mover takes the FULL push around it.
	var min_gap := 0.62
	for _pass in range(2):
		for a in range(bots.size()):
			for b in range(a + 1, bots.size()):
				var ba: Bot = bots[a]
				var bb: Bot = bots[b]
				if ba.state == "working" and bb.state == "working":
					continue
				var dv: Vector2 = bb.gpos - ba.gpos
				var dd: float = dv.length()
				if dd >= min_gap:
					continue
				var dir: Vector2 = dv.normalized() if dd > 0.01 else Vector2(cos(float(a + b)), sin(float(a + b)))
				var overlap: float = min_gap - dd
				var a_movable: bool = ba.state != "working"
				var b_movable: bool = bb.state != "working"
				if a_movable and b_movable:
					var half: Vector2 = dir * overlap * 0.5
					ba.gpos -= half
					bb.gpos += half
				elif a_movable:
					ba.gpos -= dir * overlap
				elif b_movable:
					bb.gpos += dir * overlap
	return changed

# Grid-space center of a tile (col, row).
func _grid_center(i: int) -> Vector2:
	return Vector2(float(i % COLS), float(i / COLS))

# Idle bots walk to a parking spot just in front of the field, spread across the
# width by index, so they never stand in the working area blocking other bots.
func _go_home(bot: Bot, i: int, spd: float, delta: float) -> void:
	var home_x: float = fposmod(float(i) * 1.6 + 0.6, float(COLS))
	var home := Vector2(home_x, float(rows) + 0.7)
	var to_h: Vector2 = home - bot.gpos
	var d: float = to_h.length()
	if d > 0.05:
		bot.gpos += to_h.normalized() * min(spd * delta, d)

func _pick_target(bot: Bot) -> void:
	var best := -1
	var best_score := INF
	# Suren/temizleyici: spread out to bakir (untouched) tiles, don't pile in one corner.
	var spread: bool = bot.task == TILL or bot.task == CLEAN
	for key in bot.zone:
		var i: int = key
		if i >= claimed.size() or claimed[i]:
			continue
		if not needs(bot.task, states[i]):
			continue
		var d: float = bot.gpos.distance_squared_to(_grid_center(i))
		var score: float = d
		if spread:
			score = float(_worked_neighbors(i)) * 1.0e7 + d
		if score < best_score:
			best_score = score
			best = i
	bot.target = best
	if best != -1:
		claimed[best] = true

func _worked_neighbors(i: int) -> int:
	var r: int = i / COLS
	var c: int = i % COLS
	var n := 0
	for off in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
		var nr: int = r + off.y
		var nc: int = c + off.x
		if nr < 0 or nr >= rows or nc < 0 or nc >= COLS:
			continue
		var s: int = states[nr * COLS + nc]
		if s != EMPTY and s != OBSTACLE:
			n += 1
	return n

func _release(bot: Bot) -> void:
	if bot.target != -1 and bot.target < claimed.size():
		claimed[bot.target] = false

func _can_do(bot: Bot) -> bool:
	match bot.task:
		WATER:
			return water > 0
		PLANT:
			return coins >= int(CROPS[selected_seed]["seed"])
	return true

# Applies a bot's task to its target tile. Returns true if the tile changed.
func _apply_task(bot: Bot) -> bool:
	var i := bot.target
	if i < 0 or i >= states.size():
		return false
	match bot.task:
		TILL:
			states[i] = TILLED
			return true
		PLANT:
			# plant whatever crop the player currently has selected, so changing the
			# crop in the HUD changes what the planting bots sow.
			var sc: int = CROPS[selected_seed]["seed"]
			if coins < sc:
				return false
			coins -= sc
			states[i] = PLANTED
			crop_type[i] = selected_seed
			return true
		WATER:
			if water <= 0:
				return false
			water -= 1
			states[i] = GROWING
			grow[i] = 0.0
			return true
		HARVEST:
			if harvest_tile(i, 5, 0.0, true):
				states[i] = EMPTY
				return true
			return false
		GOLD_HUNT:
			if harvest_tile(i, 8, 0.25, true):
				states[i] = EMPTY
				return true
			return false
		CLEAN:
			states[i] = EMPTY
			return true
	return false

# --- manual work + economy (ported from the 2D _manual cycle) ---
# One tap advances a tile to its next state. Returns true if an action happened,
# false if it was blocked (not enough coins/water, storage full) — the view uses
# this to flash green/red. No rendering here.
func manual(idx: int) -> bool:
	match states[idx]:
		OBSTACLE:
			states[idx] = EMPTY
			return true
		EMPTY:
			states[idx] = TILLED
			return true
		TILLED:
			var sc: int = CROPS[selected_seed]["seed"]
			if coins < sc:
				return false
			coins -= sc
			states[idx] = PLANTED
			crop_type[idx] = selected_seed
			return true
		PLANTED:
			if water <= 0:
				return false
			water -= 1
			states[idx] = GROWING
			grow[idx] = 0.0
			return true
		GROWING:
			grow[idx] = min(grow[idx] + 0.12, 1.0)
			if grow[idx] >= 1.0:
				states[idx] = RIPE
			return true
		RIPE:
			if harvest_tile(idx, 5, 0.0):
				states[idx] = EMPTY
				return true
			return false
	return false

func raw_count() -> int:
	var t := 0
	for v in stock:
		t += v
	return t

func stock_total() -> int:
	return raw_count() + flour

# --- multipliers (ported) ---
func yield_mult() -> float:
	return 1.0 + 0.10 * float(yield_level)

func sell_mult() -> float:
	var m := yield_mult()
	if sell_boost_t > 0.0:
		m *= 1.5
	return m

func bot_speed() -> float:
	return BOT_SPEED * (1.0 + 0.15 * float(speed_level))

# Movement speed in GRID tiles/sec (sim-space; world.gd scales to 3D units).
func bot_speed_tiles() -> float:
	return BOT_SPEED_TILES * (1.0 + 0.15 * float(speed_level))

func wear_rate() -> float:
	return MAINT_DECAY * pow(0.8, float(dura_level))

# overflow_sell: when storage is full, sell the crop straight to coins instead of
# failing (used by harvest BOTS so they never stall on a full depot). Manual harvest
# leaves it false, so a full depot still blocks the player (red flash → go sell).
func harvest_tile(idx: int, gold_mult: int, find_chance: float, overflow_sell: bool = false) -> bool:
	var ct: int = crop_type[idx]
	var is_gold: bool = golden[idx] or randf() < find_chance
	if is_gold:
		var base: int = CROPS[ct]["value"]
		coins += int(round(float(base) * sell_mult())) * gold_mult
		harvested += 1
		golden[idx] = false
		return true
	if stock_total() >= storage_cap:
		if not overflow_sell:
			return false  # storage full — manual harvest is blocked
		# depot full → overflow: sell this crop directly for coins so bots keep flowing
		coins += int(round(float(CROPS[ct]["value"]) * sell_mult()))
		harvested += 1
		return true
	stock[ct] = int(stock[ct]) + 1
	harvested += 1
	return true

# Sell all stored crops (+ flour) for coins. Returns coins earned.
# Wheat is NOT sold raw when a windmill exists — it becomes (pricier) flour instead.
func sell_all() -> int:
	var earned := 0
	for ct in range(stock.size()):
		if ct == WHEAT and windmill_level > 0:
			continue
		earned += int(round(float(CROPS[ct]["value"]) * sell_mult())) * int(stock[ct])
		stock[ct] = 0
	earned += int(round(float(FLOUR_VALUE) * sell_mult())) * flour
	flour = 0
	coins += earned
	return earned

# Buy one water bundle. Returns true if affordable AND the tank isn't already full
# (don't charge coins for water that would overflow the cap).
func buy_water() -> bool:
	if coins < WATER_COST or water >= WATER_MAX:
		return false
	coins -= WATER_COST
	water = min(water + WATER_BUNDLE, WATER_MAX)
	return true

func needs(task: int, s: int) -> bool:
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

func idx(c: int, r: int) -> int:
	return r * COLS + c

# ============================================================================
# Shop / upgrades / buildings (ported verbatim from the 2D prototype).
# Pure logic — the 3D store page (view) just reads costs/info and calls buy_item.
# ============================================================================

func type_count(task: int) -> int:
	var n := 0
	for bot in bots:
		if bot.task == task:
			n += 1
	return n

func bot_cost(task: int) -> int:
	var base: int = TASK_BASE_COST[task]
	return int(round(float(base) * pow(1.4, float(type_count(task)))))

# Returns the new bot (so the view can place/animate it) or null if not bought.
func buy_bot(task: int) -> Bot:
	if bots.size() >= MAX_BOTS:
		return null
	var cost := bot_cost(task)
	if coins < cost:
		return null
	coins -= cost
	var bot := Bot.new()
	bot.task = task
	bot.seed = selected_seed
	# Spawn in front of the field (toward the camera), spread by index so new bots
	# don't stack. gpos is grid space: x in [0,COLS), y = rows means "front edge".
	bot.gpos = Vector2(fposmod(float(bots.size()) * 1.7 + 0.7, float(COLS)), float(rows) + 0.4)
	bots.append(bot)
	return bot

func water_cost() -> int:
	return WATER_COST

func repair_cost() -> int:
	return max(3, 3 * bots.size())

func needs_repair() -> bool:
	for b in bots:
		if b.condition < 0.999:
			return true
	return false

func buy_repair() -> bool:
	if bots.is_empty() or not needs_repair():
		return false
	var c := repair_cost()
	if coins < c:
		return false
	coins -= c
	for b in bots:
		b.condition = 1.0
	return true

func yield_cost() -> int:
	return int(round(15.0 * pow(1.6, float(yield_level))))

func speed_cost() -> int:
	return int(round(12.0 * pow(1.6, float(speed_level))))

func dura_cost() -> int:
	return int(round(18.0 * pow(1.7, float(dura_level))))

func well_cost() -> int:
	return int(round(20.0 * pow(1.6, float(well_level))))

func scare_cost() -> int:
	return 16

func windmill_cost() -> int:
	return int(round(30.0 * pow(1.8, float(windmill_level))))

func depo_cost() -> int:
	return int(round(18.0 * pow(1.5, float(depo_level))))

func buy_yield() -> bool:
	var c := yield_cost()
	if coins < c:
		return false
	coins -= c
	yield_level += 1
	return true

func buy_speed() -> bool:
	var c := speed_cost()
	if coins < c:
		return false
	coins -= c
	speed_level += 1
	return true

func buy_dura() -> bool:
	var c := dura_cost()
	if coins < c:
		return false
	coins -= c
	dura_level += 1
	return true

func buy_well() -> bool:
	var c := well_cost()
	if coins < c:
		return false
	coins -= c
	well_level += 1
	return true

func buy_scare() -> bool:
	var c := scare_cost()
	if coins < c:
		return false
	coins -= c
	scarecrow_charges = int(min(scarecrow_charges + SCARECROW_MAX, 99))
	return true

func buy_windmill() -> bool:
	var c := windmill_cost()
	if coins < c:
		return false
	coins -= c
	windmill_level += 1
	return true

func buy_depo() -> bool:
	var c := depo_cost()
	if coins < c:
		return false
	coins -= c
	depo_level += 1
	storage_cap += 20
	return true

func can_expand() -> bool:
	return rows < MAX_ROWS

func expand_cost() -> int:
	return int(round(15.0 * pow(1.5, float(rows - START_ROWS))))

# Adds one new row of tiles (some obstacles). Returns the new row index or -1.
func buy_expand() -> int:
	if not can_expand():
		return -1
	var cost := expand_cost()
	if coins < cost:
		return -1
	coins -= cost
	var base := states.size()
	var new_row := rows
	rows += 1
	states.resize(base + COLS)
	grow.resize(base + COLS)
	crop_type.resize(base + COLS)
	claimed.resize(base + COLS)
	for k in range(COLS):
		states[base + k] = OBSTACLE if randf() < OBSTACLE_CHANCE else EMPTY
		grow[base + k] = 0.0
		crop_type[base + k] = 0
		claimed[base + k] = false
		golden.append(false)
	return new_row

# ---- store item model (ported) ----
# Tab 0 = bots, 1 = upgrades/consumables, 2 = buildings.
func tab_items(tab: int) -> Array:
	match tab:
		0:
			return [TILL, PLANT, WATER, HARVEST, CLEAN, GOLD_HUNT]
		1:
			return [IT_WATER, IT_REPAIR, IT_SCARE, IT_YIELD, IT_SPEED, IT_DURA, IT_WELL]
		_:
			return [IT_EXPAND, IT_WINDMILL, IT_DEPO]

func item_cost(id: int) -> int:
	if id <= GOLD_HUNT:
		return bot_cost(id)
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
		IT_SCARE:
			return scare_cost()
		IT_WINDMILL:
			return windmill_cost()
		IT_DEPO:
			return depo_cost()
		IT_EXPAND:
			return expand_cost()
	return 0

func item_enabled(id: int) -> bool:
	var cost := item_cost(id)
	if id <= GOLD_HUNT:
		return coins >= cost and bots.size() < MAX_BOTS
	match id:
		IT_REPAIR:
			return (not bots.is_empty()) and needs_repair() and coins >= cost
		IT_EXPAND:
			return can_expand() and coins >= cost
		_:
			return coins >= cost

# [accent: Color, letter: String, title: String, desc: String]
func item_info(id: int) -> Array:
	if id <= GOLD_HUNT:
		return [TASK_COL[id], TASK_LETTER[id], TASK_NAME[id] + " bot", TASK_DESC[id]]
	match id:
		IT_WATER:
			return [C_WATER, "+", "Su Al (+%d)" % WATER_BUNDLE, "Su deposunu doldurur"]
		IT_REPAIR:
			return [C_RED, "!", "Botlari Onar", "Yipranan botlarin bakimini yapar"]
		IT_YIELD:
			return [C_GOLD, "%", "Verim+ (sv.%d)" % yield_level, "Satis degerini %10 artirir"]
		IT_SPEED:
			return [C_GROW_B, ">", "Bot Hizi+ (sv.%d)" % speed_level, "Botlar %15 daha hizli calisir"]
		IT_DURA:
			return [C_SOIL, "#", "Dayaniklilik+ (sv.%d)" % dura_level, "Botlar daha yavas yipranir"]
		IT_WELL:
			return [C_WATER, "~", "Su Kuyusu (sv.%d)" % well_level, "Pasif olarak su uretir"]
		IT_SCARE:
			return [C_GROW_A, "K", "Korkuluk (sarj %d)" % scarecrow_charges, "Kus saldirisini kovar (+%d sarj)" % SCARECROW_MAX]
		IT_WINDMILL:
			return [C_GROW_A, "M", "Degirmen (sv.%d)" % windmill_level, "Bugdayi una cevirir (un pahali)"]
		IT_DEPO:
			return [C_SOIL, "D", "Depo+ (%d)" % storage_cap, "Depolama kapasitesini artirir"]
		IT_EXPAND:
			return [C_GROW_A, "+", "Tarla Buyut", "+1 sira ekler (%d/%d)" % [rows, MAX_ROWS]]
	return [C_PANEL, "?", "?", ""]

func item_cost_text(id: int) -> String:
	if id == IT_EXPAND and not can_expand():
		return "MAX"
	if id == IT_REPAIR and bots.is_empty():
		return "-"
	return "%d c" % item_cost(id)

# Returns a result dict: {bought: bool, close: bool, bot: Bot|null, row: int}.
# close=true means the store should close (bot bought, so the player can paint a zone).
func buy_item(id: int) -> Dictionary:
	if id <= GOLD_HUNT:
		var b := buy_bot(id)
		return {"bought": b != null, "close": b != null, "bot": b, "row": -1}
	var ok := false
	var row := -1
	match id:
		IT_WATER:
			ok = buy_water()
		IT_REPAIR:
			ok = buy_repair()
		IT_YIELD:
			ok = buy_yield()
		IT_SPEED:
			ok = buy_speed()
		IT_DURA:
			ok = buy_dura()
		IT_WELL:
			ok = buy_well()
		IT_SCARE:
			ok = buy_scare()
		IT_WINDMILL:
			ok = buy_windmill()
		IT_DEPO:
			ok = buy_depo()
		IT_EXPAND:
			row = buy_expand()
			ok = row >= 0
	return {"bought": ok, "close": false, "bot": null, "row": row}
