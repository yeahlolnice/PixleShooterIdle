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
| `round.respawn_delay_s` | optional seconds | a killed bot is replaced after this (trickle, D62) |
| `round.freeze_time_s` / `live_time_s` / `summary_time_s` | seconds | round phase lengths |
| `mod_menu_time_scale` | 0 < x ≤ 1 | `Engine.time_scale` while the mod menu is open |
| `legit_mode.coin_chance` / `coin_value` | 0–1 / cash | all-cheats-off bonus per kill (Phase 4) |
| `collateral.pierce` / `damage_falloff` / `bonus_cash_mult` | int / 0–1 / ≥ 0 | extra bots one bullet passes through (guns may override with `pierce`), damage kept per bot passed, and bonus cash per bot when one bullet kills 2+ ("COLLATERAL xN") |
| `multi_kill.window_s` / `step` / `cap` | s / ≥ 0 / ≥ 1 | kills within `window_s` of the last chain; kill cash × (1 + (chain − 1) × step), capped. Player kills only |
| `free_trial.round` / `seconds` / `cheats` | int / s / {cheat_id: level} | once per save, when that round goes live, these cheats run at these levels for `seconds` without being owned (D64) |
| `sentries.damage` / `fire_rate` / `range_m` / `turn_speed_deg_s` / `cash_mult` | per shot / shots·s⁻¹ / m / °·s⁻¹ / 0–1 | Sentry.exe base stats; kills pay `cash_mult` × a no-streak kill (D66) |
| `loot.drop_chance` | 0–1 | chance a kill drops a bonus-cash pickup (`shooter/loot/`) |
| `loot.cash_mult` | number ≥ 0 | pickup value = this × that kill's cash (paid on top of the kill reward) |
| `loot.lifetime_s` / `pickup_radius_m` | s / m | pickup vanishes after / is collected within this distance of the player |
| `loot.magnet_speed_m_s` | m/s | how fast Loot Magnet pulls pickups in |
| `hax_points.kills_divisor` | number > 0 | `floor(sqrt(lifetime_kills / divisor))` |

## player.json
`max_health`, `move_speed` (m/s), `ground_accel`, `ground_friction` (m/s²), `air_accel` (Source
sv_airaccelerate, ~12), `air_speed_cap` (m/s; in-air speed cap along the wish direction, CS 30 u ≈ 0.72),
`jump_velocity` (m/s), `gravity` (m/s²), `mouse_sensitivity` (degrees per mouse pixel),
`pitch_limit_deg` (0–90), `respawn_delay_s`. Optional `shake` (TASK-027): `on_hit` / `on_fire` (metres of camera view
offset added per hit taken / shot fired), `max`, `decay_per_s`; the player's `shake_scale` (settings, TASK-044) scales it.

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
| `recoil_deg` | degrees | aim kick per shot (moves the real aim up; no auto-recovery) |
| `spread_deg` | degrees | random cone half-angle |
| `range_m` | metres | hitscan length |
| `auto` | bool | hold to fire |
| `unlock_kills` | int ≥ 0 | kills this run (resets on ban) before it can be bought; locked guns show "needs N kills" |
| `color` | palette name | viewmodel colour |
| `category` | optional string | buy-menu row and viewmodel shape: `pistol` (default), `smg`, `shotgun`, `rifle`, `sniper`, `lmg`, `special` |
| `pellets` | optional int ≥ 1 | rays per shot (shotgun); `damage` is per pellet; ammo and recoil per shot |
| `bloom_deg` / `bloom_max_deg` / `bloom_recovery_deg_s` | optional degrees | spread added per shot, its cap, and recovery per second once you stop firing (1.5× the fire interval after the last shot) |
| `zoom_fov` | optional degrees | camera FOV while holding aim (RMB); 0 / missing = no scope. Mouse look slows by the zoom ratio |
| `scoped_spread_mult` | optional ≥ 0 | spread multiplier while scoped (sniper: 0 = pinpoint scoped, wide unscoped) |
| `model_length_m` | optional metres | viewmodel body length (default 0.3) |
| `pierce` | optional int ≥ 0 | overrides economy.json `collateral.pierce` (sniper 4, shotgun pellets 0) |

Top-level `upgrades` (optional, TASK-024): `stat -> {name, step, max_level, min_base_cost, cost_mult, cost_growth}` for `damage` and `fire_rate`. Level n multiplies the stat by `1 + step × n`; the next level costs `max(gun price, min_base_cost) × cost_mult × cost_growth^n`. Upgrades are bought for the gun in hand from the buy menu, saved in `GameState.gun_upgrades`, kept through death, reset on ban.

## bots.json
```json
{ "bots": [ { ...bot... } ] }
```
`id`, `name`, `health`, `move_speed` (m/s), `reaction_time_s` (delay before first shot after seeing the
player), `aim_error_deg` (random cone half-angle of bot shots), `fire_rate` (shots/s), `damage` (per hit),
`sight_range_m`, `cash_mult` (scales `kill_reward.base_cash`), `body_color`, `head_color` (palette names).

Optional behaviour fields (TASK-025): `behaviour` (`grunt` default, `sniper`, `rusher`),
`shoot_range_ratio` (0–1 of sight range where it stops to shoot; default 0.7), `keep_distance_m` (sniper backs
off inside this), `wander_radius_m` (default 8; snipers stay near their perch), `strafe_speed` (m/s, scaled by
the arena move_speed mult) and `strafe_switch_s` (rusher flips direction about this often, jittered ±40%).
`body_size` (optional vec3, default [0.7, 1.2, 0.4]): torso box and its hitbox; the head sits on top (TASK-029).

## arenas.json
```json
{ "arenas": [ { ...arena... } ] }
```
| Key | Type | Meaning |
|---|---|---|
| `id`, `name` | string | |
| `order` | int ≥ 1 | progression order (`DataRegistry.arenas()` is sorted by it) |
| `cash_mult` | number > 0 | `global_mult` factor for kills here (plan: ×10 per arena) |
| `entrances` / `column_gap_s` | optional vec3[] / seconds | non-sniper bots enter here in single file, one per entrance every `column_gap_s` (default 0.6), then march on the player (D62) |
| `sentry_spots` | optional vec3[] | where Sentry.exe turrets deploy, in order (one per Deploy level) |
| `unlock_kills` | optional int ≥ 0 | lifetime kills to unlock (default 0); unlocked arenas stay unlocked through bans. Picked in the buy menu's SERVER row during freeze time (ArenaService, `GameState.current_arena_id`) |
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

## cheats.json
```json
{ "cost_growth": 1.15, "tabs": ["Movement", "Visuals", "Combat", "Rage"],
  "cheats":   [ { "id", "name", "tab", "order", "unlock": {"kills": n} | {"prestige": n},
                  "base_cost", "max_level", "effects": [effect, ...],
                  "cost_growth"?, "script"? } ],
  "upgrades": [ same shape, e.g. server_slots, plus "resets_on_prestige"? ] }
```
| Key | Meaning |
|---|---|
| `cost_growth` | price growth per level; next price = `base_cost × growth^level_owned` (entry may override) |
| `order` | ladder position; mod menu sorts by it |
| `unlock.kills` | **lifetime** kills needed (a ban never re-locks a kill cheat) |
| `unlock.prestige` | bans needed (God Mode 1, Spinbot 2, Noclip 3). Exactly one of kills/prestige |
| `script` | optional `res://cheats/*.gd` extending CheatBase for custom apply/remove |
| effect `type: "number"` | `from` at level 1 → `to` at `max_level`; `curve` is `linear` or `exp` (geometric; from/to non-zero, same sign) |
| effect `type: "bool"` | true from `from_level` up (e.g. Infinite Ammo `infinite_reload` at max) |
| effect `target` | `player` → `player.set_stat_mod(key)`; `weapon` → `weapon.set_modifier(key)`; `cheat`/`game` → read via `CheatSystem.effect(id, key)` |

Neutral (off/unowned) values: `false` for bools, `1.0` for player/weapon multipliers, `0.0` for
cheat/game values. Each player/weapon modifier key belongs to one cheat only.
Speed Hack, Infinite Ammo and Auto Bhop name scripts in `cheats/`. Auto Bhop's `cheat` effects
(`max_hop_speed_mult`, `uncapped`) are handed to `Player.set_bhop()` by its
`apply()` and cleared by `remove()`; see DECISIONS D39, D43, D51.
Server Slots' level is stored in `GameState.server_slots`; its `extra_bots` effect is added to
`arenas.json bots_per_wave` by RoundController via `CheatSystem.extra_bots()`.

### Wallhack (TASK-012, `cheats/wallhack.gd`)
`radius_m` is the outline range around the player; `whole_map` (max level) makes it unlimited;
`health_bars` shows a bar above outlined bots from that level. Bots in range get
`shaders/wallhack_outline.gdshader` as `next_pass` on their part materials (neon from palette.json).
The range check runs on a 0.2 s timer, not per frame. Bots freed or queued for deletion (round end)
are dropped from the outline set without being touched.

### Aimbot, Triggerbot, Spinbot (`cheats/aimbot.gd`, `triggerbot.gd`, `spinbot.gd`)
All three extend `DriverCheat` (`cheats/driver_cheat.gd`): `apply()` puts a `<Id>Driver` node under
the player that runs each physics tick while the player is alive with no menu open. Targets are
live bots whose head (`Head` mesh) the camera can see (`cheats/cheat_targeting.gd`, line of sight on
the world layer only). Cheat shots go through `WeaponManager.cheat_fire()` (fire rate, ammo, menus,
freeze time all apply).
- Aimbot: `fov_deg` = max angle off the crosshair to lock (180 = anywhere); `snap_speed` = fraction
  of the remaining angle turned per physics tick (1 = snap); `instant_headshot` (max) sets the
  weapon's `force_headshot` modifier so every bot hit counts as a headshot.
- Triggerbot: `delay_s` = how long the crosshair must stay on the same bot before it fires.
- Spinbot: `spin_interval_s` = time between snap-and-shoot to the nearest visible bot in any
  direction; `constant_fire` (max) stays locked and fires whenever the gun allows.

### Hitbox Expander (`cheats/hitbox_expander.gd`)
`head_scale` multiplies every bot's head hitbox (`Bot.HEAD_SIZE`; the head mesh is unchanged). It is
the static `Bot.head_hitbox_scale`, so bots spawned later use it too; `remove()` resets it to 1.

### God Mode, Noclip, Loot Magnet (`cheats/god_mode.gd`, `noclip.gd`, `loot_magnet.gd`)
- God Mode: `invuln_after_kill_s` = invulnerability after each kill (does not stack; the longer
  of what is left and the new grant wins); `permanent` (max) ignores all damage. Falling below
  `player.json fall_kill_y` still kills. Handed to `Player.set_god_mode()`.
- Noclip: the `noclip` action (V) toggles flight (no gravity or world collision, fly where you look,
  hold jump to rise). `burst_s` = flight seconds per round, refilled at freeze time;
  `max_wall_thickness_m` = deepest geometry one pass may go through (plus the body's own size);
  `unlimited_flight` (max) = no time limit. Flight never ends inside geometry. Handed to
  `Player.set_noclip()`.
- Loot Magnet: `radius_m` = loot within this distance of the player is pulled in at
  `economy.json loot.magnet_speed_m_s`. Loot itself: see economy.json `loot` above.

## chat.json
Every chat line and chat UI string. Read by the `ChatSystem` autoload.
| Key | Type | Meaning |
|---|---|---|
| `channels.<id>` | `{sender, color, format}` | `system` / `seller` / `bot`. `sender` is the shown name (`""` = random from `bot_names`), `color` a palette name, `format` the display line with `{sender}` and `{text}` |
| `ui.<key>` | string | chat UI labels (`log_title`, `mute_bots`) |
| `box.visible_lines` | int ≥ 1 | lines kept in the corner box |
| `box.fade_after_s` / `fade_time_s` | seconds | a corner line starts fading after / fades over |
| `box.log_max_lines` | int ≥ 1 | history kept for the scrollable log |
| `bot_names` | string[] | random senders for bot lines |
| `triggers[]` | object | see below |

Trigger fields: `id` (unique), `event` (an event name, see ARCHITECTURE.md §3 "chat events"),
`channel`, `once` (bool: fire once per save), `delay_s`, `lines` (one is picked at random).
Optional: `once_key` (flag name with placeholders, e.g. `"unlock_{cheat_id}"` = once per cheat; default
`id`), `when` (`{payload_key: "value"}`, all must match, compared as text), `chance` (0–1), `sender`
(overrides the channel sender). `{key}` in lines is replaced by payload values (whole numbers print
without `.0`); `{cheat_name}` is derived from `cheat_id` (cheats.json `name`, else "Speed Hack" from
`speed_hack`). Unknown placeholders are left as written.

## Bot hit chance (TASK-003)

Bots fire hitscan shots with direction uniform inside a cone of `aim_error_deg` (grunt 14 deg x arena `aim_error`).
Hit probability on a 0.4 m-radius player is `(r / (d * tan(err)))^2` (see `Bot.hit_probability`):
about 2.6% at 10 m and 10% at 5 m on arena_1 (unit-tested bounds: <10% at 10 m, <30% at 5 m).
With fire_rate 0.7/s and damage 5 that is roughly 0.1 damage/s at mid range.
Head hits use the shooting gun's `headshot_mult`; body hits are 1x.
