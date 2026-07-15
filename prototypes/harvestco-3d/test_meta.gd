extends SceneTree

func _init():
	var Sim := load("res://sim.gd") as GDScript
	var ok := true
	var s = Sim.new()
	s.new_game()

	# --- crop unlocks ---
	if not s.crop_unlocked(0): ok = false; print("FAIL crop0 should be unlocked")
	if s.crop_unlocked(7): ok = false; print("FAIL crop7 (Cilek) should be locked at harvested=0")
	if s.crop_count() != 20: ok = false; print("FAIL crop_count ", s.crop_count())
	s.harvested = 60
	if not s.crop_unlocked(7): ok = false; print("FAIL crop7 (Cilek) should unlock at harvested=60")
	if s.crop_unlocked(8): ok = false; print("FAIL crop8 (Misir) should still be locked at 60")

	# --- earn + prestige gain ---
	s.season_earned = 0
	var before = s.coins
	s._earn(15000)
	if s.coins != before + 15000: ok = false; print("FAIL _earn coins")
	if s.season_earned != 15000: ok = false; print("FAIL season_earned ", s.season_earned)
	if s.prestige_gain() != 1: ok = false; print("FAIL prestige_gain(15000)=", s.prestige_gain())
	if not s.prestige_available(): ok = false; print("FAIL prestige_available")

	# --- do prestige: stars banked, season reset, upgrades wiped, harvested kept ---
	s.yield_level = 3
	var g = s.do_prestige()
	if g != 1: ok = false; print("FAIL do_prestige gain ", g)
	if s.stars != 1: ok = false; print("FAIL stars ", s.stars)
	if s.season_earned != 0: ok = false; print("FAIL season not reset")
	if s.yield_level != 0: ok = false; print("FAIL yield not reset")
	if s.harvested != 60: ok = false; print("FAIL harvested should persist ", s.harvested)
	if abs(s.prestige_mult() - 1.10) > 0.001: ok = false; print("FAIL prestige_mult ", s.prestige_mult())
	# sell_mult now includes the star bonus (yield_level=0 -> 1.0 * 1.10)
	if abs(s.sell_mult() - 1.10) > 0.001: ok = false; print("FAIL sell_mult ", s.sell_mult())

	# --- milestones: stops at first unsatisfied (bots>=1) ---
	s.milestone_idx = 0
	s.bots = []
	var coins_pre = s.coins
	s.check_milestones()
	if s.milestone_idx != 2: ok = false; print("FAIL milestone_idx ", s.milestone_idx)
	if s.coins != coins_pre + 30: ok = false; print("FAIL milestone reward ", s.coins - coins_pre)

	# --- caps raised ---
	if s.MAX_ROWS != 20: ok = false; print("FAIL MAX_ROWS ", s.MAX_ROWS)
	if s.MAX_BOTS != 30: ok = false; print("FAIL MAX_BOTS ", s.MAX_BOTS)

	# --- save round-trip of new fields ---
	s.stars = 4; s.season_earned = 999; s.milestone_idx = 5
	var d = s.to_dict()
	var b = Sim.new()
	b.from_dict(JSON.parse_string(JSON.stringify(d)))
	if b.stars != 4: ok = false; print("FAIL save stars ", b.stars)
	if b.season_earned != 999: ok = false; print("FAIL save season ", b.season_earned)
	if b.milestone_idx != 5: ok = false; print("FAIL save milestone ", b.milestone_idx)

	# --- new buildings (Sera / Pazar / Kompost) on a fresh sim ---
	var c = Sim.new()
	c.new_game()
	# greenhouse growth multiplier
	c.sera_level = 2
	if abs(c.growth_mult() - 1.3) > 0.001: ok = false; print("FAIL growth_mult ", c.growth_mult())
	# market passive coin trickle: pazar 4 * MARKET_RATE(0.3)/s * 1s = 1.2 -> 1 coin
	c.pazar_level = 4
	var cbefore = c.coins
	var sbefore = c.season_earned
	c.tick(1.0)
	if c.coins < cbefore + 1: ok = false; print("FAIL market income ", c.coins - cbefore)
	if c.season_earned <= sbefore: ok = false; print("FAIL market not counted as season income")
	# compost golden bonus
	c.kompost_level = 5
	if abs(c.kompost_bonus() - 0.10) > 0.001: ok = false; print("FAIL kompost_bonus ", c.kompost_bonus())
	# buy funcs increment levels
	c.coins = 100000
	if not c.buy_sera() or c.sera_level != 3: ok = false; print("FAIL buy_sera")
	if not c.buy_pazar() or c.pazar_level != 5: ok = false; print("FAIL buy_pazar")
	if not c.buy_kompost() or c.kompost_level != 6: ok = false; print("FAIL buy_kompost")

	# --- store model: crops tab + building tab + info-only crop rows ---
	var crop_tab = c.tab_items(3)
	if crop_tab.size() != 20: ok = false; print("FAIL crop tab size ", crop_tab.size())
	if int(crop_tab[0]) != c.IT_CROP: ok = false; print("FAIL crop tab first id ", crop_tab[0])
	var bld_tab = c.tab_items(2)
	if not (c.IT_SERA in bld_tab and c.IT_PAZAR in bld_tab and c.IT_KOMPOST in bld_tab):
		ok = false; print("FAIL building tab missing new buildings")
	if c.item_enabled(c.IT_CROP + 0): ok = false; print("FAIL crop row should be info-only (disabled)")
	if c.item_cost_text(c.IT_CROP + 0) != "Acik": ok = false; print("FAIL crop0 cost text ", c.item_cost_text(c.IT_CROP + 0))
	c.harvested = 0
	if c.item_cost_text(c.IT_CROP + 7) != "Kilit": ok = false; print("FAIL crop7 should read Kilit")
	if c.buy_item(c.IT_CROP + 0)["bought"]: ok = false; print("FAIL crop row should not be buyable")

	# --- unlock announce ---
	# tier order: 9 open-from-start crops (unlock 0), then Cilek(60) at position 9
	c.unlocked_seen = 0
	c.harvested = 60
	if not c._check_unlocks(): ok = false; print("FAIL _check_unlocks should fire at 60")
	if c.unlocked_seen != 10: ok = false; print("FAIL unlocked_seen ", c.unlocked_seen)

	# --- barn raises the bot cap ---
	var bn = Sim.new(); bn.new_game()
	if bn.max_bots() != bn.BOT_CAP_BASE: ok = false; print("FAIL base max_bots ", bn.max_bots())
	bn.coins = 1000000
	if not bn.buy_barn() or bn.barn_level != 1: ok = false; print("FAIL buy_barn")
	if bn.max_bots() != bn.BOT_CAP_BASE + bn.BARN_STEP: ok = false; print("FAIL max_bots after barn ", bn.max_bots())
	# --- water tower raises water cap ---
	var wc0 = bn.water_cap()
	if not bn.buy_sukule() or bn.sukule_level != 1: ok = false; print("FAIL buy_sukule")
	if bn.water_cap() != wc0 + bn.SUKULE_WATER: ok = false; print("FAIL water_cap after tower ", bn.water_cap())
	# --- shipping depot auto-sells stock over time ---
	bn.buy_nakliye()   # level 1 -> ships every SHIP_BASE/1 = 6s
	bn.stock[0] = 6
	var nc0 = bn.coins
	bn.tick(6.5)
	if bn.stock_total() != 0: ok = false; print("FAIL nakliye should auto-sell stock ", bn.stock_total())
	if bn.coins <= nc0: ok = false; print("FAIL nakliye should add coins")

	# --- save round-trip of the new building fields ---
	c.sera_level = 4; c.pazar_level = 2; c.kompost_level = 3; c.barn_level = 5; c.unlocked_seen = 9
	c.sukule_level = 3; c.nakliye_level = 2
	var e = Sim.new()
	e.from_dict(JSON.parse_string(JSON.stringify(c.to_dict())))
	if e.sera_level != 4 or e.pazar_level != 2 or e.kompost_level != 3: ok = false; print("FAIL save building levels")
	if e.barn_level != 5: ok = false; print("FAIL save barn_level ", e.barn_level)
	if e.sukule_level != 3 or e.nakliye_level != 2: ok = false; print("FAIL save water/shipping levels")
	if e.unlocked_seen != 9: ok = false; print("FAIL save unlocked_seen ", e.unlocked_seen)

	print("SIMTEST ", "PASS" if ok else "FAIL")
	quit()
