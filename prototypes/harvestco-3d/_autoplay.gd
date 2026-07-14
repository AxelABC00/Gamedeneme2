# Headless economy autoplayer: plays sim.gd with a reasonable reinvesting strategy and
# logs game-time to key progression milestones, to measure how long the game actually lasts.
# Run: godot --headless --path . --script res://_autoplay.gd
extends SceneTree

var s
var TILL; var PLANT; var WATER; var HARVEST; var CLEAN

func _init():
	seed(12345)
	var Sim := load("res://sim.gd") as GDScript
	s = Sim.new()
	s.new_game()
	TILL = s.TILL; PLANT = s.PLANT; WATER = s.WATER; HARVEST = s.HARVEST; CLEAN = s.CLEAN

	var dt := 0.2
	var t := 0.0
	var max_t := 7200.0        # simulate up to 2 hours of game-time
	var tap_acc := 0.0
	var buy_acc := 0.0
	var log := {}              # milestone -> game-time seconds
	var next_snapshot := 300.0

	while t < max_t:
		# --- manual tapping (bootstraps the early game before bots cover the cycle) ---
		tap_acc += 3.0 * dt     # ~3 taps/sec
		while tap_acc >= 1.0:
			tap_acc -= 1.0
			_manual_tap()

		# --- purchases (once/sec) ---
		buy_acc += dt
		if buy_acc >= 1.0:
			buy_acc -= 1.0
			_assign_zones()
			_buy_pass()
			_pick_best_seed()

		s.tick(dt)
		t += dt

		# --- milestone logging ---
		_mark(log, "first_bot", t, s.bots.size() >= 1)
		_mark(log, "cycle_bots(TPWH)", t, _has_cycle())
		_mark(log, "crop_Cilek_60", t, s.harvested >= 60)
		_mark(log, "crop_Misir_400", t, s.harvested >= 400)
		_mark(log, "crop_Aycicek_1800", t, s.harvested >= 1800)
		_mark(log, "crop_AltinElma_6000", t, s.harvested >= 6000)
		_mark(log, "crop_Mantar_18000", t, s.harvested >= 18000)
		_mark(log, "crop_Ejder_45000", t, s.harvested >= 45000)
		_mark(log, "rows_max_20", t, s.rows >= 20)
		_mark(log, "prestige_1_star", t, s.prestige_gain() >= 1)
		_mark(log, "prestige_5_stars", t, s.prestige_gain() >= 5)
		_mark(log, "prestige_10_stars", t, s.prestige_gain() >= 10)
		_mark(log, "prestige_25_stars", t, s.prestige_gain() >= 25)
		_mark(log, "all_milestones_done", t, not s.milestone_active())
		_mark(log, "bots_28", t, s.bots.size() >= 28)

		if t >= next_snapshot:
			next_snapshot += 300.0
			print("[%4dm%02ds] coins=%d earned=%d harv=%d rows=%d bots=%d stars_avail=%d yield=%d sera=%d pazar=%d well=%d" % [
				int(t) / 60, int(t) % 60, s.coins, s.season_earned, s.harvested, s.rows,
				s.bots.size(), s.prestige_gain(), s.yield_level, s.sera_level, s.pazar_level, s.well_level])

	print("\n=== MILESTONE TIMELINE (game-time to reach) ===")
	for k in ["first_bot", "cycle_bots(TPWH)", "crop_Cilek_60", "crop_Misir_400",
			"crop_Aycicek_1800", "crop_AltinElma_6000", "crop_Mantar_18000", "crop_Ejder_45000",
			"rows_max_20", "bots_28", "prestige_1_star", "prestige_5_stars", "prestige_10_stars",
			"prestige_25_stars", "all_milestones_done"]:
		if log.has(k):
			var sec: float = log[k]
			print("  %-22s %3dm %02ds" % [k, int(sec) / 60, int(sec) % 60])
		else:
			print("  %-22s  (not reached in %dm)" % [k, int(max_t) / 60])
	print("final: coins=%d season_earned=%d harvested=%d rows=%d bots=%d" % [s.coins, s.season_earned, s.harvested, s.rows, s.bots.size()])
	quit()

func _mark(log, key, t, cond):
	if cond and not log.has(key):
		log[key] = t

func _has_cycle() -> bool:
	return s.type_count(TILL) >= 1 and s.type_count(PLANT) >= 1 and s.type_count(WATER) >= 1 and s.type_count(HARVEST) >= 1

# one manual action on the highest-value tile that needs work
func _manual_tap() -> void:
	var n: int = s.states.size()
	# harvest ripe first (income), then keep the cycle moving
	for want in [s.RIPE, s.TILLED, s.EMPTY, s.PLANTED, s.OBSTACLE]:
		for i in range(n):
			if s.states[i] == want:
				if want == s.TILLED and s.coins < int(s.CROPS[s.selected_seed]["seed"]):
					continue
				if want == s.PLANTED and s.water <= 0:
					continue
				s.manual(i)
				return

func _assign_zones() -> void:
	var n: int = s.states.size()
	for b in s.bots:
		for i in range(n):
			b.zone[i] = true

func _pick_best_seed() -> void:
	# highest-value unlocked crop we can afford to seed (so plant bots don't stall)
	var best: int = s.WHEAT
	var best_val: int = -1
	for i in range(s.CROPS.size()):
		if not s.crop_unlocked(i):
			continue
		if int(s.CROPS[i]["seed"]) > s.coins:
			continue
		if int(s.CROPS[i]["value"]) > best_val:
			best_val = int(s.CROPS[i]["value"]); best = i
	s.selected_seed = best

# Greedy reinvestment: buy the first worthwhile thing we can afford while keeping a buffer.
func _buy_pass() -> void:
	# sell stored crops to coins every pass (a real player taps Sat / the depot)
	if s.stock_total() > 0:
		s.sell_all()
	# keep enough to plant + a small reserve
	var buffer := 5 + int(s.CROPS[s.selected_seed]["seed"])
	# 1) complete one full cycle of bots first
	for task in [TILL, PLANT, WATER, HARVEST, CLEAN]:
		if s.type_count(task) < 1 and s.coins - s.bot_cost(task) >= buffer:
			s.buy_bot(task); return
	# 2) keep water available if no well yet
	if s.well_level == 0 and s.water < 8 and s.coins - s.water_cost() >= buffer:
		s.buy_water(); return
	# 3) growth engine: well, sera, yield, a few more harvest/plant bots, expand
	var plans := [
		["well", s.well_cost(), s.well_level < 4],
		["sera", s.sera_cost(), s.sera_level < 6],
		["yield", s.yield_cost(), s.yield_level < 10],
		["speed", s.speed_cost(), s.speed_level < 8],
		["expand", s.expand_cost(), s.can_expand()],
		["harvest", s.bot_cost(HARVEST), s.type_count(HARVEST) < 9 and s.bots.size() < s.MAX_BOTS],
		["plant", s.bot_cost(PLANT), s.type_count(PLANT) < 7 and s.bots.size() < s.MAX_BOTS],
		["water", s.bot_cost(WATER), s.type_count(WATER) < 6 and s.bots.size() < s.MAX_BOTS],
		["till", s.bot_cost(TILL), s.type_count(TILL) < 6 and s.bots.size() < s.MAX_BOTS],
		["depot", s.depo_cost(), s.storage_cap < 200],
		["pazar", s.pazar_cost(), s.pazar_level < 6],
		["kompost", s.kompost_cost(), s.kompost_level < 6],
		["windmill", s.windmill_cost(), s.windmill_level < 3],
		["clean", s.bot_cost(CLEAN), s.type_count(CLEAN) < 2 and s.bots.size() < s.MAX_BOTS],
	]
	# buy the cheapest eligible plan we can afford (keeps steady reinvestment)
	var best_name := ""
	var best_cost := 1 << 30
	for p in plans:
		if p[2] and int(p[1]) < best_cost and s.coins - int(p[1]) >= buffer:
			best_cost = int(p[1]); best_name = p[0]
	match best_name:
		"well": s.buy_well()
		"sera": s.buy_sera()
		"yield": s.buy_yield()
		"speed": s.buy_speed()
		"expand": s.buy_expand()
		"depot": s.buy_depo()
		"pazar": s.buy_pazar()
		"kompost": s.buy_kompost()
		"windmill": s.buy_windmill()
		"harvest": s.buy_bot(HARVEST)
		"plant": s.buy_bot(PLANT)
		"water": s.buy_bot(WATER)
		"till": s.buy_bot(TILL)
		"clean": s.buy_bot(CLEAN)
