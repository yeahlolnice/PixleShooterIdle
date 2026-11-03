class_name DataSchema
extends RefCounted
## Schemas for every file in data/ and a small validator. Pure: no IO, no nodes.
##
## Spec format (plain dictionaries, see docs/DATA.md):
##   {"type": "number", "min": 0, "exclusive_min": 0, "max": 1}
##   {"type": "int", "min": 1}                  # JSON number that must be integral; converted to int
##   {"type": "string"} / {"type": "bool"}
##   {"type": "color"}                          # "#rrggbb" or "#rrggbbaa"; kept as String, use Color.html()
##   {"type": "vec3"}                           # [x, y, z]; converted to Vector3
##   {"type": "array", "items": spec, "min_items": 1}
##   {"type": "map", "values": spec}            # object with free-form keys
##   {"type": "object", "fields": {key: spec}, "optional": ["key", ...]}
##
## To add a data file: add an entry to FILES, document it in docs/DATA.md and
## add a getter in autoload/data_registry.gd.

const _NUM_POS := {"type": "number", "exclusive_min": 0}
const _NUM_NONNEG := {"type": "number", "min": 0}
const _MULTIPLIER := {"type": "number", "min": 0}

const _GUN := {
	"type": "object",
	"fields": {
		"id": {"type": "string"},
		"name": {"type": "string"},
		"price": _NUM_NONNEG,
		"damage": _NUM_POS,
		"headshot_mult": _NUM_POS,
		"fire_rate": _NUM_POS,
		"mag_size": {"type": "int", "min": 1},
		"reload_time_s": _NUM_NONNEG,
		"recoil_deg": _NUM_NONNEG,
		"spread_deg": _NUM_NONNEG,
		"range_m": _NUM_POS,
		"auto": {"type": "bool"},
		"unlock_kills": {"type": "int", "min": 0},
		"color": {"type": "string"},
		# Weapon v2 (TASK-022), all optional; see docs/DATA.md.
		"category": {"type": "string"},
		"pellets": {"type": "int", "min": 1},
		"bloom_deg": _NUM_NONNEG,
		"bloom_max_deg": _NUM_NONNEG,
		"bloom_recovery_deg_s": _NUM_NONNEG,
		"zoom_fov": _NUM_NONNEG,
		"scoped_spread_mult": _NUM_NONNEG,
		"model_length_m": _NUM_POS,
	},
	"optional": ["category", "pellets", "bloom_deg", "bloom_max_deg", "bloom_recovery_deg_s",
		"zoom_fov", "scoped_spread_mult", "model_length_m"],
}

## Per-gun upgrade track (guns.json "upgrades", TASK-024).
const _GUN_UPGRADE := {
	"type": "object",
	"fields": {
		"name": {"type": "string"},
		"step": _NUM_POS,
		"max_level": {"type": "int", "min": 1},
		"min_base_cost": _NUM_NONNEG,
		"cost_mult": _NUM_NONNEG,
		"cost_growth": _NUM_POS,
	},
}

const _BOT := {
	"type": "object",
	"fields": {
		"id": {"type": "string"},
		"name": {"type": "string"},
		"health": _NUM_POS,
		"move_speed": _NUM_NONNEG,
		"reaction_time_s": _NUM_NONNEG,
		"aim_error_deg": _NUM_NONNEG,
		"fire_rate": _NUM_POS,
		"damage": _NUM_NONNEG,
		"sight_range_m": _NUM_POS,
		"cash_mult": _NUM_NONNEG,
		"body_color": {"type": "string"},
		"head_color": {"type": "string"},
	},
}

const _BLOCK := {
	"type": "object",
	"fields": {
		"pos": {"type": "vec3"},
		"size": {"type": "vec3"},
		"color": {"type": "string"},
	},
}

const _ARENA := {
	"type": "object",
	"fields": {
		"id": {"type": "string"},
		"name": {"type": "string"},
		"order": {"type": "int", "min": 1},
		"cash_mult": _NUM_POS,
		"bots_per_wave": {"type": "int", "min": 1},
		"bot_types": {"type": "array", "items": {"type": "string"}, "min_items": 1},
		"bot_mults": {
			"type": "object",
			"fields": {
				"health": _MULTIPLIER,
				"move_speed": _MULTIPLIER,
				"reaction_time": _MULTIPLIER,
				"aim_error": _MULTIPLIER,
				"fire_rate": _MULTIPLIER,
				"damage": _MULTIPLIER,
			},
		},
		"sky_color": {"type": "string"},
		"blocks": {"type": "array", "items": _BLOCK, "min_items": 1},
		"player_spawns": {"type": "array", "items": {"type": "vec3"}, "min_items": 1},
		"bot_spawns": {"type": "array", "items": {"type": "vec3"}, "min_items": 1},
	},
}

const _CHAT_TRIGGER := {
	"type": "object",
	"fields": {
		"id": {"type": "string"},
		"event": {"type": "string"},
		"channel": {"type": "string"},
		"once": {"type": "bool"},
		"once_key": {"type": "string"},
		"delay_s": _NUM_NONNEG,
		"chance": {"type": "number", "min": 0, "max": 1},
		"sender": {"type": "string"},
		"when": {"type": "map", "values": {"type": "string"}},
		"lines": {"type": "array", "items": {"type": "string"}, "min_items": 1},
	},
	"optional": ["once_key", "chance", "sender", "when"],
}

const _CHEAT_EFFECT := {
	"type": "object",
	"fields": {
		"key": {"type": "string"},
		"target": {"type": "string"},
		"type": {"type": "string"},
		"from": {"type": "number"},
		"to": {"type": "number"},
		"curve": {"type": "string"},
		"from_level": {"type": "int", "min": 1},
	},
	"optional": ["from", "to", "curve", "from_level"],
}

## Cheats and mod-menu upgrades (Server Slots) share one shape.
const _CHEAT := {
	"type": "object",
	"fields": {
		"id": {"type": "string"},
		"name": {"type": "string"},
		"tab": {"type": "string"},
		"order": {"type": "int", "min": 1},
		"unlock": {
			"type": "object",
			"fields": {"kills": {"type": "int", "min": 0}, "prestige": {"type": "int", "min": 0}},
			"optional": ["kills", "prestige"],
		},
		"base_cost": _NUM_NONNEG,
		"cost_growth": _NUM_POS,
		"max_level": {"type": "int", "min": 1},
		"script": {"type": "string"},
		"resets_on_prestige": {"type": "bool"},
		"effects": {"type": "array", "items": _CHEAT_EFFECT},
	},
	"optional": ["cost_growth", "script", "resets_on_prestige"],
}

## file stem -> root spec. Every file listed here is required.
const FILES := {
	"economy": {
		"type": "object",
		"fields": {
			"starting_cash": _NUM_NONNEG,
			"cost_growth": _NUM_POS,
			"kill_reward": {
				"type": "object",
				"fields": {
					"base_cash": _NUM_NONNEG,
					"headshot_mult": _NUM_POS,
					"streak_step": _NUM_NONNEG,
					"streak_cap": _NUM_NONNEG,
				},
			},
			"round": {
				"type": "object",
				"fields": {
					"freeze_time_s": _NUM_NONNEG,
					"live_time_s": _NUM_POS,
					"summary_time_s": _NUM_NONNEG,
				},
			},
			"mod_menu_time_scale": {"type": "number", "exclusive_min": 0, "max": 1},
			"legit_mode": {
				"type": "object",
				"fields": {
					"coin_chance": {"type": "number", "min": 0, "max": 1},
					"coin_value": _NUM_NONNEG,
				},
			},
			"loot": {
				"type": "object",
				"fields": {
					"drop_chance": {"type": "number", "min": 0, "max": 1},
					"cash_mult": _NUM_NONNEG,
					"lifetime_s": _NUM_POS,
					"pickup_radius_m": _NUM_POS,
					"magnet_speed_m_s": _NUM_NONNEG,
				},
			},
			"hax_points": {
				"type": "object",
				"fields": {"kills_divisor": _NUM_POS},
			},
		},
	},
	"player": {
		"type": "object",
		"fields": {
			"max_health": _NUM_POS,
			"move_speed": _NUM_POS,
			"ground_accel": _NUM_POS,
			"air_accel": _NUM_NONNEG,
			"air_speed_cap": _NUM_NONNEG,
			"ground_friction": _NUM_NONNEG,
			"jump_velocity": _NUM_POS,
			"gravity": _NUM_POS,
			"mouse_sensitivity": _NUM_POS,
			"pitch_limit_deg": {"type": "number", "exclusive_min": 0, "max": 90},
			"respawn_delay_s": _NUM_NONNEG,
		},
	},
	"guns": {
		"type": "object",
		"fields": {
			"starter_gun": {"type": "string"},
			"upgrades": {"type": "map", "values": _GUN_UPGRADE},
			"guns": {"type": "array", "items": _GUN, "min_items": 1},
		},
		"optional": ["upgrades"],
	},
	"bots": {
		"type": "object",
		"fields": {
			"bots": {"type": "array", "items": _BOT, "min_items": 1},
		},
	},
	"arenas": {
		"type": "object",
		"fields": {
			"arenas": {"type": "array", "items": _ARENA, "min_items": 1},
		},
	},
	"chat": {
		"type": "object",
		"fields": {
			"channels": {
				"type": "map",
				"values": {
					"type": "object",
					"fields": {
						"sender": {"type": "string"},
						"color": {"type": "string"},
						"format": {"type": "string"},
					},
				},
			},
			"ui": {"type": "map", "values": {"type": "string"}},
			"box": {
				"type": "object",
				"fields": {
					"visible_lines": {"type": "int", "min": 1},
					"fade_after_s": _NUM_NONNEG,
					"fade_time_s": _NUM_POS,
					"log_max_lines": {"type": "int", "min": 1},
				},
			},
			"bot_names": {"type": "array", "items": {"type": "string"}, "min_items": 1},
			"triggers": {"type": "array", "items": _CHAT_TRIGGER, "min_items": 1},
		},
	},
	"cheats": {
		"type": "object",
		"fields": {
			"cost_growth": _NUM_POS,
			"tabs": {"type": "array", "items": {"type": "string"}, "min_items": 1},
			"cheats": {"type": "array", "items": _CHEAT, "min_items": 1},
			"upgrades": {"type": "array", "items": _CHEAT},
		},
	},
	"palette": {
		"type": "object",
		"fields": {
			"colors": {"type": "map", "values": {"type": "color"}},
		},
	},
}


## Validates `value` against `spec`. Appends "path: message" strings to `errors`
## and returns a normalised copy (ints converted, vec3 -> Vector3).
static func validate(value: Variant, spec: Dictionary, path: String, errors: PackedStringArray) -> Variant:
	var kind: String = spec.get("type", "")
	match kind:
		"number":
			if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
				errors.append("%s: expected number, got %s" % [_p(path), _type_name(value)])
				return value
			_check_range(float(value), spec, path, errors)
			return float(value)
		"int":
			if typeof(value) != TYPE_FLOAT and typeof(value) != TYPE_INT:
				errors.append("%s: expected integer, got %s" % [_p(path), _type_name(value)])
				return value
			if float(value) != floor(float(value)):
				errors.append("%s: expected integer, got %s" % [_p(path), value])
				return value
			_check_range(float(value), spec, path, errors)
			return int(value)
		"string":
			if typeof(value) != TYPE_STRING:
				errors.append("%s: expected string, got %s" % [_p(path), _type_name(value)])
			return value
		"bool":
			if typeof(value) != TYPE_BOOL:
				errors.append("%s: expected true/false, got %s" % [_p(path), _type_name(value)])
			return value
		"color":
			if typeof(value) != TYPE_STRING or not Color.html_is_valid(value):
				errors.append("%s: expected colour string like \"#ff8800\", got %s" % [_p(path), JSON.stringify(value)])
			return value
		"vec3":
			if typeof(value) != TYPE_ARRAY or value.size() != 3:
				errors.append("%s: expected [x, y, z], got %s" % [_p(path), JSON.stringify(value)])
				return value
			for i in range(value.size()):
				if typeof(value[i]) != TYPE_FLOAT and typeof(value[i]) != TYPE_INT:
					errors.append("%s[%d]: expected number, got %s" % [_p(path), i, _type_name(value[i])])
					return value
			return Vector3(value[0], value[1], value[2])
		"array":
			if typeof(value) != TYPE_ARRAY:
				errors.append("%s: expected array, got %s" % [_p(path), _type_name(value)])
				return value
			if value.size() < int(spec.get("min_items", 0)):
				errors.append("%s: needs at least %d item(s), has %d" % [_p(path), spec["min_items"], value.size()])
			var out_arr: Array = []
			for i in range(value.size()):
				out_arr.append(validate(value[i], spec["items"], "%s[%d]" % [_p(path), i], errors))
			return out_arr
		"map":
			if typeof(value) != TYPE_DICTIONARY:
				errors.append("%s: expected object, got %s" % [_p(path), _type_name(value)])
				return value
			var out_map := {}
			for key in value:
				out_map[key] = validate(value[key], spec["values"], "%s.%s" % [_p(path), key], errors)
			return out_map
		"object":
			if typeof(value) != TYPE_DICTIONARY:
				errors.append("%s: expected object, got %s" % [_p(path), _type_name(value)])
				return value
			var out_obj: Dictionary = value.duplicate()
			var optional: Array = spec.get("optional", [])
			var fields: Dictionary = spec.get("fields", {})
			for key in fields:
				var child_path := "%s.%s" % [_p(path), key] if path != "" else String(key)
				if not value.has(key):
					if not optional.has(key):
						errors.append("%s: missing required key" % child_path)
					continue
				out_obj[key] = validate(value[key], fields[key], child_path, errors)
			return out_obj
	errors.append("%s: schema error, unknown type '%s'" % [_p(path), kind])
	return value


static func _check_range(v: float, spec: Dictionary, path: String, errors: PackedStringArray) -> void:
	if spec.has("min") and v < float(spec["min"]):
		errors.append("%s: %s is below minimum %s" % [_p(path), v, spec["min"]])
	if spec.has("exclusive_min") and v <= float(spec["exclusive_min"]):
		errors.append("%s: %s must be greater than %s" % [_p(path), v, spec["exclusive_min"]])
	if spec.has("max") and v > float(spec["max"]):
		errors.append("%s: %s is above maximum %s" % [_p(path), v, spec["max"]])


static func _p(path: String) -> String:
	return path if path != "" else "(root)"


static func _join(path: String, key: String) -> String:
	return key if path == "" else "%s.%s" % [path, key]


static func _type_name(value: Variant) -> String:
	return type_string(typeof(value))
