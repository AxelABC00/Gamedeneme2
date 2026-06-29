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

# --- state ---
var rows: int
var states: PackedInt32Array
var grow: PackedFloat32Array
var crop_type: PackedInt32Array
var golden: Array = []
# economy (ported; used from Phase C onward)
var coins: int = 14
var water: int = 25

# Deterministic demo layout so the 3D view shows the FULL lifecycle at a glance
# (one row per stage). Proves the state->3D mapping for Phase B.
func setup_demo() -> void:
	rows = START_ROWS
	var n := COLS * rows
	states = PackedInt32Array(); states.resize(n)
	grow = PackedFloat32Array(); grow.resize(n)
	crop_type = PackedInt32Array(); crop_type.resize(n)
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
