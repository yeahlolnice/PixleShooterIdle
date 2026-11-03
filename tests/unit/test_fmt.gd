extends GutTest
## Fmt: big-number display used by HUD, mod menu and buy menu.


func test_small_numbers_are_whole_and_rounded_down() -> void:
	assert_eq(Fmt.number(0), "0")
	assert_eq(Fmt.number(12.9), "12")
	assert_eq(Fmt.number(999.9), "999")


func test_suffixes_one_decimal_rounded_down() -> void:
	assert_eq(Fmt.number(1000), "1K")
	assert_eq(Fmt.number(1299), "1.2K", "never shows more than you have")
	assert_eq(Fmt.number(999999), "999.9K")
	assert_eq(Fmt.number(6000000), "6M")
	assert_eq(Fmt.number(2.5e9), "2.5B")
	assert_eq(Fmt.number(1.0e12), "1T")
	assert_eq(Fmt.number(3.0e33), "3Dc")


func test_scientific_past_last_suffix() -> void:
	assert_eq(Fmt.number(2.5e40), "2.5e40")
	assert_eq(Fmt.number(1.0e36), "1e36")


func test_negative_and_non_finite() -> void:
	assert_eq(Fmt.number(-1500), "-1.5K")
	assert_eq(Fmt.number(INF), "∞")


func test_cash_prefix() -> void:
	assert_eq(Fmt.cash(12), "$12")
	assert_eq(Fmt.cash(1234567), "$1.2M")
	assert_eq(Fmt.cash(-1500), "-$1.5K")
