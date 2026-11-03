# Data files

Every balance and content number lives in `data/*.json`. Scripts read them only through the
`DataRegistry` autoload. Schemas are enforced by `core/data_schema.gd`; a bad file logs
`res://data/<file>.json: <key path>: <problem>` at startup and fails `tools/run_tests.sh`.

Conventions:
- Units: metres, seconds (`_s`), degrees (`_deg`), per-second rates. Multipliers are plain factors (1 = neutral).
- `int` fields must be whole numbers; they are converted to `int`. `vec3` is `[x, y, z]` → `Vector3`.
- Colour fields hold a **palette name** (key in palette.json), never a hex code, except in palette.json itself.
- Ids are `snake_case` and unique within their file.
- All values are starting points for tuning; the human can edit them without touching code.

Adding a file: add its schema to `DataSchema.FILES`, a typed getter to `data_registry.gd`, and a
section here. Files without a schema still load (raw, via `DataRegistry.get_file(stem)`) with a log note.

## economy.json
| Key | Type | Meaning |
|---|---|---|
| `starting_cash` | number ≥ 0 | cash for a new game |
| `cost_growth` | number > 0 | default growth for `Economy.cost` (1.15 per plan) |
| `kill_reward.base_cash` | number ≥ 0 | cash per kill before multipliers |
| `kill_reward.headshot_mult` | number > 0 | headshot cash factor |
| `kill_reward.streak_step` | number ≥ 0 | bonus fraction per kill in the current streak |
| `kill_reward.streak_cap` | number ≥ 0 | max total streak bonus fraction (1.0 = up to ×2) |
| `round.freeze_time_s` / `live_time_s` / `summary_time_s` | seconds | round phase lengths |
| `mod_menu_time_scale` | 0 < x ≤ 1 | `Engine.time_scale` while the mod menu is open |
| `legit_mode.coin_chance` / `coin_value` | 0–1 / cash | all-cheats-off bonus per kill (Phase 4) |
| `hax_points.kills_divisor` | number > 0 | `floor(sqrt(lifetime_kills / divisor))` |

## player.json
`max_health`, `move_speed` (m/s), `ground_accel`, `air_accel`, `ground_friction` (m/s²),
`jump_velocity` (m/s), `gravity` (m/s²), `mouse_sensitivity` (degrees per mouse pixel),
`pitch_limit_deg` (0–90), `respawn_delay_s`.

## guns.json
```json
{ "starter_gun": "<gun id>", "guns": [ { ...gun... } ] }
```
| Gun key | Type | Meaning |
|---|---|---|
| `id`, `name` | string | id + display name |
| `price` | number ≥ 0 | buy-menu price (starter is 0) |
| `damage` | number > 0 | body damage per hit |
| `headshot_mult` | number > 0 | damage factor on head hitbox |
| `fire_rate` | shots/s > 0 | |
| `mag_size` | int ≥ 1 | |
| `reload_time_s` | seconds | |
| `recoil_deg` | degrees | camera kick per shot |
| `spread_deg` | degrees | random cone half-angle |
| `range_m` | metres | hitscan length |
| `auto` | bool | hold to fire |
| `unlock_kills` | int ≥ 0 | lifetime kills before it shows in the buy menu |
| `color` | palette name | viewmodel colour |

## bots.json
```json
{ "bots": [ { ...bot... } ] }
```
`id`, `name`, `health`, `move_speed` (m/s), `reaction_time_s` (delay before first shot after seeing the
player), `aim_error_deg` (random cone half-angle of bot shots), `fire_rate` (shots/s), `damage` (per hit),
`sight_range_m`, `cash_mult` (scales `kill_reward.base_cash`), `body_color`, `head_color` (palette names).

## arenas.json
```json
{ "arenas": [ { ...arena... } ] }
```
| Key | Type | Meaning |
|---|---|---|
| `id`, `name` | string | |
| `order` | int ≥ 1 | progression order (`DataRegistry.arenas()` is sorted by it) |
| `cash_mult` | number > 0 | `global_mult` factor for kills here (plan: ×10 per arena) |
| `bots_per_wave` | int ≥ 1 | base wave size (+ `GameState.server_slots`) |
| `bot_types` | array of bot ids | which bots spawn here |
| `bot_mults` | object | `health`, `move_speed`, `fire_rate`, `damage` multiply the stat; `reaction_time`, `aim_error` multiply those (lower = harder bots) |
| `sky_color` | palette name | background colour |
| `blocks` | array of `{pos: vec3, size: vec3, color}` | axis-aligned boxes; `pos` is the **centre**, y up, floor top at y = 0 |
| `player_spawns`, `bot_spawns` | array of vec3 | feet positions |

## palette.json
```json
{ "colors": { "<name>": "#rrggbb", ... } }
```
The one shared palette. `missing` (magenta) is the fallback for unknown names. Every colour used by
any other file must exist here (checked at load).

## Coming in later tickets
`cheats.json` (TASK-009: 12 cheats + Server Slots, tab, unlock rule, base cost, per-level curves),
`chat.json` (TASK-013: triggers, channel, once flag, delay, lines with `{placeholders}`).

## Bot hit chance (TASK-003)

Bots fire hitscan shots with direction uniform inside a cone of `aim_error_deg` (grunt 14 deg x arena `aim_error`).
Hit probability on a 0.4 m-radius player is `(r / (d * tan(err)))^2` (see `Bot.hit_probability`):
about 2.6% at 10 m and 10% at 5 m on arena_1 (unit-tested bounds: <10% at 10 m, <30% at 5 m).
With fire_rate 0.7/s and damage 5 that is roughly 0.1 damage/s at mid range.
Head hits use the shooting gun's `headshot_mult`; body hits are 1x.
