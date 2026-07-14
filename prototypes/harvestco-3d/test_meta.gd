extends SceneTree

func _init():
	var Sim := load("res://sim.gd") as GDScript
	var ok := true
	var s = Sim.new()
	s.new_game()

	# --- crop unlocks ---
	if not s.crop_unlocked(0): ok = false; print("FAIL crop0 should be unlocked")
	if s.crop_unlocked(7): ok = false; print("FAIL crop7 (Cilek) should be locked at harvested=0")
	if s.crop_count() != 11: ok = false; print("FAIL crop_count ", s.crop_count())
	s.harvested = 40
	if not s.crop_unlocked(7): ok = false; print("FAIL crop7 should unlock at harvested=40")
	if s.crop_unlocked(8): ok = false; print("FAIL crop8 should still be locked at 40")

	# --- earn + prestige gain ---
	s.season_earned = 0
	var before = s.coins
	s._earn(250)
	if s.coins != before + 250: ok = false; print("FAIL _earn coins")
	if s.season_earned != 250: ok = false; print("FAIL season_earned ", s.season_earned)
	if s.prestige_gain() != 1: ok = false; print("FAIL prestige_gain(250)=", s.prestige_gain())
	if not s.prestige_available(): ok = false; print("FAIL prestige_available")

	# --- do prestige: stars banked, season reset, upgrades wiped, harvested kept ---
	s.yield_level = 3
	var g = s.do_prestige()
	if g != 1: ok = false; print("FAIL do_prestige gain ", g)
	if s.stars != 1: ok = false; print("FAIL stars ", s.stars)
	if s.season_earned != 0: ok = false; print("FAIL season not reset")
	if s.yield_level != 0: ok = false; print("FAIL yield not reset")
	if s.harvested != 40: ok = false; print("FAIL harvested should persist ", s.harvested)
	if abs(s.prestige_mult() - 1.15) > 0.001: ok = false; print("FAIL prestige_mult ", s.prestige_mult())
	# sell_mult now includes the star bonus (yield_level=0 -> 1.0 * 1.15)
	if abs(s.sell_mult() - 1.15) > 0.001: ok = false; print("FAIL sell_mult ", s.sell_mult())

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

	print("SIMTEST ", "PASS" if ok else "FAIL")
	quit()
