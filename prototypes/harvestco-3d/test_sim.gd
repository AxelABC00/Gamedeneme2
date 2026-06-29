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

	print("=== %d passed, %d failed ===" % [_pass, _fail])
	quit(1 if _fail > 0 else 0)
