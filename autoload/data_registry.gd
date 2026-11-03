extends Node
## Loads and validates every data/*.json file once at startup and serves typed,
## read-only views of it. All balance and content numbers come from here.
##
## Rules for callers:
##   - Treat returned dictionaries/arrays as read-only (duplicate before editing).
##   - Never read data/*.json directly; add a getter here instead.
##   - Schemas live in core/data_schema.gd; file formats in docs/DATA.md.
##
## Errors name the file and key, e.g.
##   "res://data/guns.json: guns[1].damage: expected number, got String"
## They are pushed with push_error() at startup and kept in errors().

signal data_loaded(ok: bool)

const DEFAULT_DIR := "res://data"

var _data: Dictionary = {}          # file stem -> validated root value
var _errors := PackedStringArray()
var _dir := DEFAULT_DIR


func _ready() -> void:
	reload()


## (Re)loads every file from `dir`. Returns true when there were no errors.
func reload(dir: String = DEFAULT_DIR) -> bool:
	_dir = dir
	var result := load_dir(dir)
	_data = result["data"]
	_errors = result["errors"]
	for message in _errors:
		push_error("[DataRegistry] " + message)
	data_loaded.emit(_errors.is_empty())
	return _errors.is_empty()


func is_valid() -> bool:
	return _errors.is_empty()


func errors() -> PackedStringArray:
	return _errors


# --- Typed getters ------------------------------------------------------------

## Whole economy.json (see docs/DATA.md for keys).
func economy() -> Dictionary:
	return _data.get("economy", {})


## Whole player.json: movement and health tuning.
func player() -> Dictionary:
	return _data.get("player", {})


## All guns in file order.
func guns() -> Array:
	return _data.get("guns", {}).get("guns", [])


## One gun by id, or {} if unknown.
func gun(id: String) -> Dictionary:
	return _find_by_id(guns(), id)


## Id of the free gun every round starts with.
func starter_gun_id() -> String:
	return _data.get("guns", {}).get("starter_gun", "")


func bots() -> Array:
	return _data.get("bots", {}).get("bots", [])


func bot(id: String) -> Dictionary:
	return _find_by_id(bots(), id)


## All arenas sorted by "order" (progression order).
func arenas() -> Array:
	var list: Array = _data.get("arenas", {}).get("arenas", []).duplicate()
	list.sort_custom(func(a, b): return a["order"] < b["order"])
	return list


func arena(id: String) -> Dictionary:
	return _find_by_id(arenas(), id)


func first_arena_id() -> String:
	var list := arenas()
	return list[0]["id"] if not list.is_empty() else ""


## Bot stats for `bot_id` with the arena's bot_mults applied:
## health, move_speed, fire_rate, damage are multiplied; reaction_time_s and
## aim_error_deg are multiplied by reaction_time / aim_error (lower = harder).
func bot_stats(bot_id: String, arena_id: String) -> Dictionary:
	return resolve_bot_stats(bot(bot_id), arena(arena_id))


## Palette colour by name. Unknown names warn and fall back to the palette's "missing" entry
## (opaque white if the palette has no "missing" entry).
func color(name: String) -> Color:
	var colors: Dictionary = palette()
	if colors.has(name):
		return Color.html(colors[name])
	push_warning("[DataRegistry] unknown palette colour '%s'" % name)
	return Color.html(colors["missing"]) if colors.has("missing") else Color.WHITE


## name -> "#rrggbb" for the one shared palette.
func palette() -> Dictionary:
	return _data.get("palette", {}).get("colors", {})


## Raw access for files that do not have a typed getter yet (e.g. cheats, chat
## once their tickets land). Prefer adding a typed getter.
func get_file(stem: String) -> Variant:
	return _data.get(stem)


# --- Pure helpers (static, unit-tested) ---------------------------------------

static func resolve_bot_stats(bot_def: Dictionary, arena_def: Dictionary) -> Dictionary:
	var stats := bot_def.duplicate()
	var mults: Dictionary = arena_def.get("bot_mults", {})
	stats["health"] = bot_def.get("health", 0.0) * mults.get("health", 1.0)
	stats["move_speed"] = bot_def.get("move_speed", 0.0) * mults.get("move_speed", 1.0)
	stats["fire_rate"] = bot_def.get("fire_rate", 0.0) * mults.get("fire_rate", 1.0)
	stats["damage"] = bot_def.get("damage", 0.0) * mults.get("damage", 1.0)
	stats["reaction_time_s"] = bot_def.get("reaction_time_s", 0.0) * mults.get("reaction_time", 1.0)
	stats["aim_error_deg"] = bot_def.get("aim_error_deg", 0.0) * mults.get("aim_error", 1.0)
	return stats


## Loads and validates every schema'd file in `dir`. Does not push errors.
## Returns {"data": {stem: value}, "errors": PackedStringArray}.
static func load_dir(dir: String) -> Dictionary:
	var data := {}
	var errors := PackedStringArray()
	for stem in DataSchema.FILES:
		var path := "%s/%s.json" % [dir, stem]
		var value: Variant = load_file(path, DataSchema.FILES[stem], errors)
		if value != null:
			data[stem] = value
	# Files without a schema are loaded raw so new tickets can iterate, but warned about.
	for file_name in DirAccess.get_files_at(dir):
		if file_name.get_extension() != "json":
			continue
		var stem := file_name.get_basename()
		if DataSchema.FILES.has(stem):
			continue
		var raw: Variant = _parse_json("%s/%s" % [dir, file_name], errors)
		if raw != null:
			data[stem] = raw
			print("[DataRegistry] note: %s/%s has no schema in core/data_schema.gd" % [dir, file_name])
	if errors.is_empty():
		cross_validate(data, errors)
	return {"data": data, "errors": errors}


## Parses and validates one file. Returns the normalised value or null.
static func load_file(path: String, spec: Dictionary, errors: PackedStringArray) -> Variant:
	var raw: Variant = _parse_json(path, errors)
	if raw == null:
		return null
	var file_errors := PackedStringArray()
	var value: Variant = DataSchema.validate(raw, spec, "", file_errors)
	for e in file_errors:
		errors.append("%s: %s" % [path, e])
	return value if file_errors.is_empty() else null


## References between files: ids unique, starter gun exists, arena bot types
## exist, every colour name used exists in the palette.
static func cross_validate(data: Dictionary, errors: PackedStringArray) -> void:
	var colors: Dictionary = data.get("palette", {}).get("colors", {})
	var guns_list: Array = data.get("guns", {}).get("guns", [])
	var bots_list: Array = data.get("bots", {}).get("bots", [])
	var arenas_list: Array = data.get("arenas", {}).get("arenas", [])
	_check_unique_ids("guns.json: guns", guns_list, errors)
	_check_unique_ids("bots.json: bots", bots_list, errors)
	_check_unique_ids("arenas.json: arenas", arenas_list, errors)
	var starter: String = data.get("guns", {}).get("starter_gun", "")
	if _find_by_id(guns_list, starter).is_empty():
		errors.append("guns.json: starter_gun: '%s' is not a gun id" % starter)
	for i in range(guns_list.size()):
		_check_color(colors, guns_list[i]["color"], "guns.json: guns[%d].color" % i, errors)
	for i in range(bots_list.size()):
		_check_color(colors, bots_list[i]["body_color"], "bots.json: bots[%d].body_color" % i, errors)
		_check_color(colors, bots_list[i]["head_color"], "bots.json: bots[%d].head_color" % i, errors)
	for a in range(arenas_list.size()):
		var arena_def: Dictionary = arenas_list[a]
		_check_color(colors, arena_def["sky_color"], "arenas.json: arenas[%d].sky_color" % a, errors)
		for t in arena_def["bot_types"]:
			if _find_by_id(bots_list, t).is_empty():
				errors.append("arenas.json: arenas[%d].bot_types: '%s' is not a bot id" % [a, t])
		var blocks: Array = arena_def["blocks"]
		for b in range(blocks.size()):
			_check_color(colors, blocks[b]["color"], "arenas.json: arenas[%d].blocks[%d].color" % [a, b], errors)


static func _check_unique_ids(where: String, list: Array, errors: PackedStringArray) -> void:
	var seen := {}
	for i in range(list.size()):
		var id: String = list[i]["id"]
		if seen.has(id):
			errors.append("%s[%d].id: duplicate id '%s'" % [where, i, id])
		seen[id] = true


static func _check_color(colors: Dictionary, name: String, where: String, errors: PackedStringArray) -> void:
	if not colors.has(name):
		errors.append("%s: '%s' is not in palette.json" % [where, name])


static func _parse_json(path: String, errors: PackedStringArray) -> Variant:
	if not FileAccess.file_exists(path):
		errors.append("%s: file missing" % path)
		return null
	var text := FileAccess.get_file_as_string(path)
	var json := JSON.new()
	if json.parse(text) != OK:
		errors.append("%s: invalid JSON at line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


static func _find_by_id(list: Array, id: String) -> Dictionary:
	for item in list:
		if typeof(item) == TYPE_DICTIONARY and item.get("id") == id:
			return item
	return {}
