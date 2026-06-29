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

# Bot tasks (kept for Phase D; lifecycle rules already reference them)
const TILL := 0
const PLANT := 1
const WATER := 2
const HARVEST := 3
const CLEAN := 4
const GOLD_HUNT := 5

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
var selected_seed: int = WHEAT     # which crop a tap plants (HUD picker comes in Phase F)

# Deterministic demo layout so the 3D view shows the FULL lifecycle at a glance
# (one row per stage). Proves the state->3D mapping for Phase B.
func setup_demo() -> void:
	rows = START_ROWS
	var n := COLS * rows
	states = PackedInt32Array(); states.resize(n)
	grow = PackedFloat32Array(); grow.resize(n)
	crop_type = PackedInt32Array(); crop_type.resize(n)
	stock = PackedInt32Array(); stock.resize(CROPS.size())
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
	return changed

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

func stock_total() -> int:
	var t := 0
	for v in stock:
		t += v
	return t

# Multipliers are 1.0 until upgrades/buildings land (Phase E). Hook kept for parity.
func sell_mult() -> float:
	return 1.0

func harvest_tile(idx: int, gold_mult: int, find_chance: float) -> bool:
	var ct: int = crop_type[idx]
	var is_gold: bool = golden[idx] or randf() < find_chance
	if is_gold:
		var base: int = CROPS[ct]["value"]
		coins += int(round(float(base) * sell_mult())) * gold_mult
		harvested += 1
		golden[idx] = false
		return true
	if stock_total() >= storage_cap:
		return false  # storage full — can't harvest plain crops
	stock[ct] = int(stock[ct]) + 1
	harvested += 1
	return true

# Sell all stored crops (+ flour) for coins. Returns coins earned.
func sell_all() -> int:
	var earned := 0
	for ct in range(stock.size()):
		earned += int(round(float(CROPS[ct]["value"]) * sell_mult())) * int(stock[ct])
		stock[ct] = 0
	earned += int(round(float(FLOUR_VALUE) * sell_mult())) * flour
	flour = 0
	coins += earned
	return earned

# Buy one water bundle. Returns true if affordable.
func buy_water() -> bool:
	if coins < WATER_COST:
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
