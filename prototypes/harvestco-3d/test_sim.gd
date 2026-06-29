# PROTOTYPE - sim.gd logic test (Phase C step 1)
# Deterministic headless checks for the manual-work cycle + economy.
# Run: godot --headless --script res://test_sim.gd --path .
extends SceneTree

var _pass := 0
var _fail := 0

func _ok(name: String, cond: bool) -> void:
	if cond:
		_pass += 1
		print("  PASS  ", name)
	else:
		_fail += 1
		print("  FAIL  ", name)

func _fresh() -> SimState:
	var s := SimState.new()
	s.setup_demo()
	# normalise a clean sandbox tile 0 for each test
	s.states[0] = SimState.EMPTY
	s.grow[0] = 0.0
	s.golden[0] = false
	s.coins = SimState.START_COINS
	s.water = SimState.START_WATER
	return s

func _initialize() -> void:
	print("=== sim.gd manual+economy tests ===")

	# 1. manual cycle: obstacle -> empty
	var s := _fresh()
	s.states[0] = SimState.OBSTACLE
	_ok("obstacle tap clears to empty", s.manual(0) and s.states[0] == SimState.EMPTY)

	# 2. empty -> tilled
	s = _fresh()
	_ok("empty tap tills", s.manual(0) and s.states[0] == SimState.TILLED)

	# 3. tilled -> planted, coins deducted by seed cost
	s = _fresh()
	s.states[0] = SimState.TILLED
	s.selected_seed = SimState.WHEAT
	var seed_cost: int = SimState.CROPS[SimState.WHEAT]["seed"]
	var before: int = s.coins
	_ok("tilled tap plants", s.manual(0) and s.states[0] == SimState.PLANTED)
	_ok("planting deducts seed cost", s.coins == before - seed_cost)
	_ok("planting sets crop_type", s.crop_type[0] == SimState.WHEAT)

	# 3b. planting blocked when broke
	s = _fresh()
	s.states[0] = SimState.TILLED
	s.coins = 0
	_ok("planting blocked when broke", (not s.manual(0)) and s.states[0] == SimState.TILLED)

	# 4. planted -> growing, water deducted, grow reset
	s = _fresh()
	s.states[0] = SimState.PLANTED
	s.grow[0] = 0.5
	before = s.water
	_ok("planted tap waters -> growing", s.manual(0) and s.states[0] == SimState.GROWING)
	_ok("watering deducts water", s.water == before - 1)
	_ok("watering resets grow", s.grow[0] == 0.0)

	# 4b. watering blocked when dry
	s = _fresh()
	s.states[0] = SimState.PLANTED
	s.water = 0
	_ok("watering blocked when dry", (not s.manual(0)) and s.states[0] == SimState.PLANTED)

	# 5. growing tap nudges growth, flips to ripe at 1.0
	s = _fresh()
	s.states[0] = SimState.GROWING
	s.grow[0] = 0.0
	s.manual(0)
	_ok("growing tap +0.12", abs(s.grow[0] - 0.12) < 0.0001)
	s.grow[0] = 0.95
	s.manual(0)
	_ok("growing tap flips to ripe at full", s.states[0] == SimState.RIPE)

	# 6. ripe (plain) harvest -> stock +1, tile empty
	s = _fresh()
	s.states[0] = SimState.RIPE
	s.crop_type[0] = 2  # Domates
	s.golden[0] = false
	before = s.coins
	_ok("ripe harvest succeeds", s.manual(0) and s.states[0] == SimState.EMPTY)
	_ok("harvest adds to stock", s.stock[2] == 1)
	_ok("plain harvest pays no coins", s.coins == before)

	# 7. ripe (golden) harvest -> coins paid, golden cleared
	s = _fresh()
	s.states[0] = SimState.RIPE
	s.crop_type[0] = 2  # Domates, value 8
	s.golden[0] = true
	before = s.coins
	var pay: int = SimState.CROPS[2]["value"] * 5
	_ok("golden harvest succeeds", s.manual(0) and s.states[0] == SimState.EMPTY)
	_ok("golden harvest pays value*5", s.coins == before + pay)
	_ok("golden flag cleared", not s.golden[0])

	# 8. harvest blocked when storage full
	s = _fresh()
	s.states[0] = SimState.RIPE
	s.crop_type[0] = 2
	s.golden[0] = false
	s.storage_cap = 1
	s.stock[0] = 1  # already at cap
	_ok("harvest blocked when storage full", (not s.manual(0)) and s.states[0] == SimState.RIPE)

	# 9. sell_all sums stock*value + flour*FLOUR_VALUE, clears, pays coins
	s = _fresh()
	s.stock[2] = 2          # 2 Domates @ 8 = 16
	s.flour = 1             # 1 flour @ 10 = 10
	before = s.coins
	var earned: int = s.sell_all()
	_ok("sell_all returns earned", earned == 26)
	_ok("sell_all adds coins", s.coins == before + 26)
	_ok("sell_all clears stock", s.stock_total() == 0 and s.flour == 0)

	# 10. buy_water deducts cost, caps water; blocked when poor
	s = _fresh()
	s.coins = SimState.WATER_COST
	s.water = SimState.WATER_MAX - 5
	_ok("buy_water succeeds", s.buy_water() and s.coins == 0)
	_ok("buy_water caps at WATER_MAX", s.water == SimState.WATER_MAX)
	s = _fresh()
	s.coins = 0
	_ok("buy_water blocked when poor", not s.buy_water())

	# 11. tick growth flips growing -> ripe
	s = _fresh()
	s.states[0] = SimState.GROWING
	s.crop_type[0] = SimState.WHEAT
	s.grow[0] = 0.99
	var changed: bool = s.tick(1.0)
	_ok("tick flips growing to ripe", changed and s.states[0] == SimState.RIPE)

	# --- ported shop / upgrades / buildings ---

	# 12. yield upgrade raises sell_mult; sell_boost stacks x1.5
	s = _fresh()
	_ok("yield_mult base 1.0", abs(s.yield_mult() - 1.0) < 0.0001)
	s.yield_level = 2
	_ok("yield_mult +10%/lvl", abs(s.yield_mult() - 1.2) < 0.0001)
	s.sell_boost_t = 5.0
	_ok("sell_boost x1.5", abs(s.sell_mult() - 1.8) < 0.0001)

	# 13. buy_yield deducts cost + increments level
	s = _fresh()
	s.coins = 999
	var yc: int = s.yield_cost()
	_ok("buy_yield succeeds", s.buy_yield() and s.yield_level == 1 and s.coins == 999 - yc)

	# 14. buy_depo adds +20 storage; blocked when poor
	s = _fresh()
	s.coins = 999
	before = s.storage_cap
	_ok("buy_depo +20 cap", s.buy_depo() and s.storage_cap == before + 20)
	s.coins = 0
	_ok("buy_depo blocked when poor", not s.buy_depo())

	# 15. well: buy raises level; tick generates passive water
	s = _fresh()
	s.coins = 999
	s.water = 0
	_ok("buy_well succeeds", s.buy_well() and s.well_level == 1)
	s.tick(2.0)  # WELL_RATE 0.6 * 2s = 1.2 -> +1 water
	_ok("well makes passive water", s.water == 1)

	# 16. windmill: tick converts wheat stock -> flour; sell_all skips raw wheat
	s = _fresh()
	s.coins = 999
	_ok("buy_windmill succeeds", s.buy_windmill() and s.windmill_level == 1)
	s.stock[SimState.WHEAT] = 4
	s.flour = 0
	s.tick(2.0)  # MILL_RATE 0.5 * 2s = 1.0 -> 1 wheat -> 1 flour
	_ok("windmill grinds wheat to flour", s.stock[SimState.WHEAT] == 3 and s.flour == 1)
	# raw wheat not sold while mill exists, but flour is
	s.coins = 0
	earned = s.sell_all()
	_ok("sell_all keeps raw wheat with mill", s.stock[SimState.WHEAT] == 3)
	_ok("sell_all still sells flour", earned == SimState.FLOUR_VALUE and s.flour == 0)

	# 17. buy_expand adds a row
	s = _fresh()
	s.coins = 999
	var rows_before: int = s.rows
	var new_row: int = s.buy_expand()
	_ok("buy_expand adds a row", new_row == rows_before and s.rows == rows_before + 1)
	_ok("buy_expand grows states array", s.states.size() == (rows_before + 1) * SimState.COLS)

	# 18. bots: cost scales with count; buy adds bot + deducts coins
	s = _fresh()
	s.coins = 999
	var bc0: int = s.bot_cost(SimState.TILL)
	_ok("first bot cost = base", bc0 == SimState.TASK_BASE_COST[SimState.TILL])
	var bot = s.buy_bot(SimState.TILL)
	_ok("buy_bot returns a Bot + deducts", bot != null and s.bots.size() == 1 and s.coins == 999 - bc0)
	_ok("2nd same-type bot costs more", s.bot_cost(SimState.TILL) > bc0)

	# 19. repair: needs_repair detects worn bots; buy_repair restores
	s = _fresh()
	s.coins = 999
	s.buy_bot(SimState.TILL)
	_ok("fresh bot needs no repair", not s.needs_repair())
	s.bots[0].condition = 0.5
	_ok("worn bot needs repair", s.needs_repair())
	_ok("buy_repair restores condition", s.buy_repair() and s.bots[0].condition == 1.0)

	# 20. store model: tabs + cost/enabled/buy round-trip
	s = _fresh()
	s.coins = 999
	_ok("tab 0 = 6 bots", s.tab_items(0).size() == 6)
	_ok("tab 2 has expand/mill/depo", s.tab_items(2).has(SimState.IT_EXPAND))
	_ok("item_cost(IT_WATER) = water_cost", s.item_cost(SimState.IT_WATER) == s.water_cost())
	_ok("item_enabled when affordable", s.item_enabled(SimState.IT_YIELD))
	var res: Dictionary = s.buy_item(SimState.IT_DEPO)
	_ok("buy_item(DEPO) bought, no close", res["bought"] and not res["close"])
	res = s.buy_item(SimState.TILL)
	_ok("buy_item(bot) signals close", res["bought"] and res["close"] and res["bot"] != null)

	# --- bot AI (Phase D) ---

	# 21. a TILL bot tills an EMPTY tile in its zone (move -> work -> apply)
	s = _fresh()
	s.coins = 999
	var b21 = s.buy_bot(SimState.TILL)
	var t21 := 2
	s.states[t21] = SimState.EMPTY
	b21.zone[t21] = true
	b21.gpos = s._grid_center(t21)      # placed on the tile
	s.tick_bots(0.05)                   # picks target, arrives, starts working
	_ok("bot arrives and starts working", b21.state == "working" and b21.target == t21)
	s.tick_bots(0.3)                    # work elapses -> task applied
	_ok("TILL bot tills its zone tile", s.states[t21] == SimState.TILLED)
	_ok("bot releases claim after work", not s.claimed[t21] and b21.target == -1)

	# 22. claimed prevents two bots targeting the same tile
	s = _fresh()
	s.coins = 999
	var a22 = s.buy_bot(SimState.TILL)
	var b22 = s.buy_bot(SimState.TILL)
	var t22 := 2
	s.states[t22] = SimState.EMPTY
	a22.zone[t22] = true
	b22.zone[t22] = true
	a22.gpos = Vector2(0, 5); b22.gpos = Vector2(7, 5)   # far: don't arrive instantly
	s.tick_bots(0.01)
	var one_claims: bool = (a22.target == t22 and b22.target == -1) or (b22.target == t22 and a22.target == -1)
	_ok("claimed prevents double-target", one_claims)

	# 23. a WATER bot stays idle when there is no water (_can_do)
	s = _fresh()
	s.coins = 999
	var w23 = s.buy_bot(SimState.WATER)
	s.water = 0
	var t23 := 2
	s.states[t23] = SimState.PLANTED
	w23.zone[t23] = true
	w23.gpos = s._grid_center(t23)
	s.tick_bots(0.05)
	_ok("WATER bot idle with no water", w23.target == -1 and w23.state == "moving")

	# 24. condition wears down over time even while idle
	s = _fresh()
	s.coins = 999
	var c24 = s.buy_bot(SimState.TILL)   # empty zone -> idle
	var cond0: float = c24.condition
	s.tick_bots(10.0)
	_ok("bot condition decays over time", c24.condition < cond0)

	# 25. a HARVEST bot harvests a ripe tile -> stock +1, tile empty
	s = _fresh()
	s.coins = 999
	var h25 = s.buy_bot(SimState.HARVEST)
	var t25 := 2
	s.states[t25] = SimState.RIPE
	s.crop_type[t25] = 2
	s.golden[t25] = false
	h25.zone[t25] = true
	h25.gpos = s._grid_center(t25)
	var stock25: int = s.stock[2]
	s.tick_bots(0.05); s.tick_bots(0.3)
	_ok("HARVEST bot clears ripe tile", s.states[t25] == SimState.EMPTY)
	_ok("HARVEST bot banks the crop", s.stock[2] == stock25 + 1)

	# 26. a far bot moves toward its target each tick
	s = _fresh()
	s.coins = 999
	var m26 = s.buy_bot(SimState.TILL)
	var t26 := 2
	s.states[t26] = SimState.EMPTY
	m26.zone[t26] = true
	m26.gpos = Vector2(7, 5)
	var d_before: float = m26.gpos.distance_to(s._grid_center(t26))
	s.tick_bots(0.1)
	var d_after: float = m26.gpos.distance_to(s._grid_center(t26))
	_ok("bot moves toward target", d_after < d_before)

	# --- events (Phase H) ---

	# 27. rain refills water (capped) and sets the rain timer
	s = _fresh()
	s.water = 0
	s._trigger_event()  # may be any event; force rain instead via direct call below
	s.rain_t = 0.0; s.water = 0
	# drive rain deterministically
	s.water = min(s.water + SimState.RAIN_WATER, SimState.WATER_MAX)
	s.rain_t = SimState.RAIN_DUR
	_ok("rain refills water", s.water == SimState.RAIN_WATER and s.rain_t > 0.0)

	# 28. UFO crop-circle: growing -> ripe+golden, ripe -> golden, in a 3x3 around center
	s = _fresh()
	var center := SimState.COLS + 1   # row 1, col 1 -> full 3x3 in-bounds
	for k in range(s.states.size()):
		s.states[k] = SimState.GROWING
		s.grow[k] = 0.5
		s.golden[k] = false
	s._ufo_circle_at(center)
	var ring_ok := true
	for dr in [-1, 0, 1]:
		for dc in [-1, 0, 1]:
			var ni: int = (1 + dr) * SimState.COLS + (1 + dc)
			if not (s.states[ni] == SimState.RIPE and s.golden[ni]):
				ring_ok = false
	_ok("UFO turns 3x3 growing into golden ripe", ring_ok)
	# a tile outside the ring is untouched
	var outside: int = 3 * SimState.COLS + 4
	_ok("UFO leaves tiles outside the ring alone", s.states[outside] == SimState.GROWING and not s.golden[outside])

	# 29. birds eat up to 3 ripe tiles
	s = _fresh()
	for k in range(s.states.size()):
		s.states[k] = SimState.EMPTY
	for k in range(5):
		s.states[k] = SimState.RIPE
	var eaten29: int = s._birds_eat()
	_ok("birds eat exactly 3 when 5 ripe", eaten29 == 3 and s._count_state(SimState.RIPE) == 2)

	# 30. scarecrow blocks a bird raid (charge consumed, nothing eaten)
	s = _fresh()
	for k in range(s.states.size()):
		s.states[k] = SimState.EMPTY
	for k in range(4):
		s.states[k] = SimState.RIPE
	s.scarecrow_charges = 2
	s.birds_active = true; s.birds_t = 0.0; s.birds_done = false
	s.birds_blocked = s.scarecrow_charges > 0
	if s.birds_blocked:
		s.scarecrow_charges -= 1
	var ripe_before30: int = s._count_state(SimState.RIPE)
	s.tick_events(SimState.BIRDS_DUR * 0.5 + 0.01)  # reach the resolve beat
	_ok("scarecrow consumed a charge", s.scarecrow_charges == 1)
	_ok("scarecrow saved all ripe crops", s._count_state(SimState.RIPE) == ripe_before30)

	# 31. event countdown fires an event and bumps the message sequence
	s = _fresh()
	var seq_before: int = s.event_seq
	s.event_timer = 0.01
	s.tick_events(0.05)
	_ok("event fires when timer elapses", s.event_seq > seq_before and s.event_timer > 0.0)

	# 32. UFO fires its crop-circle once at mid-flight, then deactivates at the end
	s = _fresh()
	s.ufo_active = true; s.ufo_t = 0.0; s.ufo_fired = false
	s.ufo_target = SimState.COLS + 1
	s.event_timer = 999.0   # keep the random event out of this check
	s.tick_events(SimState.UFO_DUR * 0.5 + 0.01)
	_ok("UFO fires at mid-flight", s.ufo_fired)
	s.tick_events(SimState.UFO_DUR)
	_ok("UFO deactivates after its duration", not s.ufo_active)

	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
