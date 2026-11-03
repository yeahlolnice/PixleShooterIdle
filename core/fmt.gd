class_name Fmt
extends RefCounted
## Display formatting for big numbers, shared by HUD, menus and chat-facing UI.
##   Fmt.number(1299)      -> "1.2K"   (one decimal, rounded down: never shows more than you have)
##   Fmt.cash(6000000)     -> "$6M"
##   Fmt.number(2.5e40)    -> "2.5e40" (past the last suffix)
## Below 1000 it prints the whole number (rounded down).

const SUFFIXES := ["", "K", "M", "B", "T", "Qa", "Qi", "Sx", "Sp", "Oc", "No", "Dc"]


static func number(value: float) -> String:
	if not is_finite(value):
		return "∞" if value > 0.0 else ("-∞" if value < 0.0 else "?")
	var v := absf(value)
	var prefix := "-" if value < 0.0 else ""
	if v < 1000.0:
		return prefix + str(int(floor(v)))
	var tier := 0
	while v >= 1000.0 and tier < SUFFIXES.size() - 1:
		v /= 1000.0
		tier += 1
	var shown := _one_decimal(v)
	if float(shown) < 1000.0:
		return prefix + shown + SUFFIXES[tier]
	# Past "Dc" (or rounding up to "1000Dc"): scientific, mantissa floored to one decimal.
	var exponent := int(floor(log(absf(value)) / log(10.0)))
	var mantissa := absf(value) / pow(10.0, exponent)
	if mantissa >= 9.9999999:  # log() landed just under a power of ten
		mantissa /= 10.0
		exponent += 1
	elif mantissa < 1.0:
		mantissa *= 10.0
		exponent -= 1
	return prefix + _one_decimal(maxf(mantissa, 1.0)) + "e" + str(exponent)


static func cash(value: float) -> String:
	return ("-$" + number(-value)) if value < 0.0 else ("$" + number(value))


## Floors to one decimal and drops a trailing ".0".
static func _one_decimal(v: float) -> String:
	var text := "%.1f" % (floor(v * 10.0 + 0.000001) / 10.0)
	return text.left(-2) if text.ends_with(".0") else text
