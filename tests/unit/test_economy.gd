extends GutTest
## Economy is pure: table-driven cases with explicit inputs.

const COST_CASES := [
	# [base, growth, level, expected]
	[100.0, 1.15, 0, 100.0],
	[100.0, 1.15, 1, 115.0],
	[100.0, 1.15, 2, 132.25],
	[100.0, 1.15, 10, 404.5557735],
	[50.0, 2.0, 3, 400.0],
	[0.0, 1.15, 5, 0.0],
	[100.0, 1.15, -1, 100.0],  # negative level clamps to first purchase
]

const KILL_CASES := [
	# [base, headshot, streak, multipliers, expected]
	[10.0, false, 0, {}, 10.0],
	[10.0, true, 0, {}, 10.0],  # no headshot_mult given -> neutral
	[10.0, true, 0, {"headshot_mult": 1.5}, 15.0],
	[10.0, false, 3, {"streak_step": 0.1, "streak_cap": 1.0}, 13.0],
	[10.0, false, 50, {"streak_step": 0.1, "streak_cap": 1.0}, 20.0],  # capped
	[10.0, true, 2, {"headshot_mult": 2.0, "streak_step": 0.25, "streak_cap": 1.0, "global_mult": 10.0}, 300.0],
	[10.0, false, -4, {"streak_step": 0.1, "streak_cap": 1.0}, 10.0],  # negative streak is no bonus
	[10.0, false, 0, {"global_mult": 0.0}, 0.0],
]


func test_cost_table() -> void:
	for c in COST_CASES:
		assert_almost_eq(Economy.cost(c[0], c[1], c[2]), c[3], 0.0001, "cost%s" % [c])


func test_cash_per_kill_table() -> void:
	for c in KILL_CASES:
		assert_almost_eq(Economy.cash_per_kill(c[0], c[1], c[2], c[3]), c[4], 0.0001, "cash_per_kill%s" % [c])


func test_cost_range_sums_levels() -> void:
	var expected := Economy.cost(100.0, 1.15, 2) + Economy.cost(100.0, 1.15, 3) + Economy.cost(100.0, 1.15, 4)
	assert_almost_eq(Economy.cost_range(100.0, 1.15, 2, 3), expected, 0.0001)
	assert_eq(Economy.cost_range(100.0, 1.15, 0, 0), 0.0)


func test_can_afford() -> void:
	assert_true(Economy.can_afford(100.0, 100.0))
	assert_true(Economy.can_afford(100.0, 0.0))
	assert_false(Economy.can_afford(99.99, 100.0))


func test_hax_points_formula() -> void:
	assert_eq(Economy.hax_points(0, 1000.0), 0)
	assert_eq(Economy.hax_points(999, 1000.0), 0)
	assert_eq(Economy.hax_points(1000, 1000.0), 1)
	assert_eq(Economy.hax_points(4000, 1000.0), 2)
	assert_eq(Economy.hax_points(15999, 1000.0), 3)
	assert_eq(Economy.hax_points(100, 0.0), 0)


func test_values_from_shipped_economy_json() -> void:
	var eco := DataRegistry.economy()
	var rules: Dictionary = eco["kill_reward"]
	var base: float = rules["base_cash"]
	assert_almost_eq(Economy.cash_per_kill(base, true, 0, rules), base * rules["headshot_mult"], 0.0001)
	assert_almost_eq(Economy.cost(base, eco["cost_growth"], 1), base * eco["cost_growth"], 0.0001)


func test_economy_script_has_no_numeric_literals_besides_0_and_1() -> void:
	# Guard for the data-driven rule: balance numbers belong in data/economy.json.
	var source := FileAccess.get_file_as_string("res://core/economy.gd")
	var regex := RegEx.new()
	regex.compile("(?<![\\w.])\\d+(\\.\\d+)?(?![\\w])")
	var bad: Array = []
	for line in source.split("\n"):
		var code := line.split("#")[0]
		if code.strip_edges().begins_with("##"):
			continue
		for m in regex.search_all(code):
			if float(m.get_string()) != 0.0 and float(m.get_string()) != 1.0:
				bad.append("%s  <- %s" % [line.strip_edges(), m.get_string()])
	assert_eq(bad, [], "numeric literals found in economy.gd")
