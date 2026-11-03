# Architecture — Cheat Code Idle

Godot **4.7.2-stable** (pinned in `tools/godot_version.txt`), GDScript only, Forward+ on desktop.
Design source of truth: the game plan in the project vault (`context/Cheat Code Idle — Game Plan.md`).
Decisions and their reasons: [DECISIONS.md](DECISIONS.md). Data formats: [DATA.md](DATA.md).

## 1. Module map

```
project.godot  export_presets.cfg  .gutconfig.json  README.md
addons/gut/          vendored GUT 9.7.1 (tests only, excluded from exports)
autoload/            global singletons (see §3)
  event_bus.gd         signals only
  data_registry.gd     loads + validates data/*.json, typed getters
  game_state.gd        the serialisable save state
  steam_service.gd     Steam facade -> steam_backend.gd interface
  steam_service_stub.gd  (+ steam_service_godotsteam.gd in Phase 5)
  chat_system.gd       (TASK-013) event-driven chat
core/                pure or scene-free logic, unit-testable
  economy.gd           static pure maths (class_name Economy)
  data_schema.gd       schemas + validator (class_name DataSchema)
  layers.gd            physics layer bits (class_name Layers)
  match_tracker.gd  round_controller.gd  shop_service.gd  save_service.gd   (TASK-005/006/008)
cheats/              cheat_base.gd, cheat_system.gd, one script per cheat  (TASK-009+)
shooter/             everything in the 3D world
  player/              player.tscn (+ player.gd, TASK-002)
  weapons/             weapon.gd, weapon_manager.gd  (TASK-004)
  bots/                bot.gd, bot_spawner.gd  (TASK-003)
  arenas/              arena.tscn + arena_builder.gd
ui/                  hud/ buy_menu/ mod_menu/ chat/ pause_menu/ theme/   (TASK-005/006/010/013/020)
audio/               sfx_synth.gd (procedural sounds), sfx_player.gd (EventBus -> sounds, SFX bus)  (TASK-028)
shaders/             wallhack outline etc. (must compile on Compatibility renderer)
scenes/main.tscn     composition root (main.gd)
data/                every balance/content number (JSON)
tests/unit/ tests/integration/ tests/fixtures/ (fixtures carry .gdignore)
tools/               install_godot.sh, run_tests.sh, export.sh (later sim_player.gd)
docs/                this file, DATA.md, DECISIONS.md, BUILD_NOTES.md
```

## 2. Dependency rules

```
 UI (ui/*)  ──calls──▶  services (ShopService, CheatSystem, RoundController)
     ▲                         │
     │ listens                 ▼
 EventBus  ◀──emits──  GameState / Economy / shooter nodes  ──reads──▶  DataRegistry ──▶ data/*.json
```

1. **Data flows one way:** UI → services → GameState/Economy → DataRegistry. Nothing outside `ui/` may
   reference a UI script, scene or node path. UI reads state and listens to EventBus; it changes state
   only by calling a service method (never by editing GameState fields).
2. **Systems talk through EventBus**, not through node paths. Direct calls are fine *downward*
   (service → GameState, weapon → DataRegistry) but never sideways between gameplay systems
   (bots do not call the HUD; the round controller does not reach into the player's children).
3. **`core/economy.gd` is pure**: static functions, no state, no IO, no autoload access, no numeric
   literals other than 0 and 1 (a unit test enforces this).
4. **No balance numbers in scripts.** Speeds, damage, prices, timings, chances, colours, counts live in
   `data/*.json` and are read through DataRegistry. Allowed in code: 0, 1, -1, array indices, physics
   layer bits, UI layout pixels, and engine constants. The reviewer rejects other literals.
5. **Cheats never edit raw fields.** They write into modifier dictionaries on the player/weapon
   (`player.modifiers["move_speed_mult"]`, `weapon.modifiers["mag_mult"]`), so `remove()` restores base
   stats exactly. Owners compute effective values as `base * product(mults)`.
6. **Steam is optional.** Only `steam_service*.gd` may mention GodotSteam's `Steam` singleton.
7. **Web-safe:** GDScript only, no GDExtension in gameplay, shaders must also compile on
   `gl_compatibility` (set as the `.web` renderer override in project.godot).
8. **Autoload order** (project.godot): EventBus → DataRegistry → GameState → SteamService (→ ChatSystem,
   CheatSystem later). An autoload may use only the autoloads listed before it in its `_ready()`.

## 3. Autoload APIs

### EventBus (`autoload/event_bus.gd`)
Signals only (plus `emit_chat_event`). Emitter column = the only code that should emit it.

| Signal | Args | Emitter | Typical listeners |
|---|---|---|---|
| `bot_damaged` | `bot: Node, info: {amount, headshot, gun_id, position, health_left}` | bot (TASK-003) | HUD hit marker, juice |
| `bot_killed` | `bot: Node, info: {headshot: bool, gun_id: String, position: Vector3, bot_type: String}` | bot, once per death | MatchTracker (cash), ChatSystem, spawner |
| `player_spawned` | `player: Node` | main.gd / player respawn | CheatSystem (re-apply), HUD, bots (target) |
| `player_damaged` | `amount: float, health_left: float, source: Node` (source may be null) | player | HUD, screen shake |
| `player_died` | `info: {position: Vector3, killer: Node}` | player | MatchTracker (streak reset), WeaponManager (gun reset), ChatSystem |
| `weapon_fired` | `gun_id: String` | weapon | audio, chat triggers |
| `ammo_changed` | `in_mag: int, mag_size: int` (`mag_size <= 0` = infinite) | weapon | HUD |
| `gun_equipped` | `gun_id: String` | WeaponManager | HUD, buy menu |
| `gun_upgraded` | `gun_id: String, stat: String, level: int` | ShopService.buy_upgrade | WeaponManager (re-applies), buy menu |
| `arena_selected` | `arena_id: String` | ArenaService.select | Main (rebuilds the world, restarts rounds), buy menu |
| `kill_rewarded` | `cash: float, info: Dictionary` (bot_killed payload) | MatchTracker | HUD kill feed + hit marker, HitFx "+$" pop-up |
| `scope_changed` | `scoped: bool` | WeaponManager.set_aiming | HUD scope overlay, audio |
| `loot_collected` | `value: float` | LootPickup.collect | audio |
| `cheat_fired` | `cheat_id: String` | Triggerbot, Spinbot (after a shot) | HUD CheatFx (crosshair flash, whip streak) |
| `round_state_changed` | `state: StringName, info: {round: int, duration: float}` | RoundController | spawner, buy menu, HUD, ChatSystem |
| `cash_changed` | `total: float, delta: float` | GameState only | HUD, mod/buy menus, ChatSystem (first_cash) |
| `kills_changed` | `kills: int, lifetime_kills: int` | GameState only | CheatSystem (unlocks), HUD |
| `cheat_unlocked` | `cheat_id: String` | CheatSystem | mod menu, ChatSystem |
| `cheat_purchased` | `cheat_id: String, level: int` (1 = first buy) | CheatSystem | mod menu, ChatSystem |
| `cheat_toggled` | `cheat_id: String, enabled: bool` | CheatSystem | mod menu, legit-mode bonus |
| `menu_toggled` | `menu_id: StringName ("buy_menu"/"mod_menu"/"chat"/"pause"), open: bool` | each menu | player (stop look/fire), mouse capture |
| `chat_event` | `event_name: StringName, payload: Dictionary` | any system via `emit_chat_event` | ChatSystem |
| `chat_message_posted` | `channel: StringName ("system"/"seller"/"bot"), sender: String, text: String` | ChatSystem | chat UI |
| `game_state_loaded` | — | SaveService | every UI (full refresh) |

Round state constants: `EventBus.ROUND_FREEZE`, `ROUND_LIVE`, `ROUND_SUMMARY` (`&"freeze"`, `&"live"`,
`&"summary"`). Cycle: freeze → live → summary → freeze.

Known chat event names (payload in braces). ChatSystem derives most of them from EventBus signals,
so no module needs to emit them; the rest arrive via `emit_chat_event`:
- derived: `first_match {}` (first freeze ever), `round_start {round}` (every freeze),
  `round_live {round}`, `first_cash {amount, total}` (first positive `cash_changed` ever),
  `cheat_unlocked {cheat_id}`, `cheat_purchased {cheat_id, level}`,
  `cheat_first_use {cheat_id}` (first `cheat_toggled(id, true)` per cheat), `player_died {}`,
  `bot_killed {headshot, bot_type}`.
- emitted by future systems: `mod_spawned {bot}`, `prestige {count}`.
Every payload with `cheat_id` also gets `{cheat_name}`.

### ChatSystem (`autoload/chat_system.gd`, TASK-013)
Matches events against `data/chat.json` triggers and posts lines via `EventBus.chat_message_posted`.
Once-only triggers set `GameState.chat_flags[<once_key or id>]`, so they never repeat after a load.
The flag is written when the line actually posts (not when it is queued), so saving while a delayed
line waits does not lose it; a queued line also blocks its trigger from queueing again.
| Method | Notes |
|---|---|
| `handle_event(name, payload, gate_flag = "") -> Array[Dictionary]` | runs triggers; zero-delay lines post now, others queue |
| `tick(delta)` | posts due queued lines (called from `_process`) |
| `post(channel, sender, text) -> bool` | adds to `history`; emits unless the channel is muted |
| `set_channel_muted(channel, muted)`, `is_muted(channel)` | persisted in `user://settings.cfg`; emits `mute_changed` |
| `visible_history()`, `channel_color(channel)`, `format_line(...)`, `ui_text(key)` | for the chat UI |
| static `substitute`, `matches`, `once_flag`, `filter_muted`, `format_value` | pure, unit-tested |
UI: `ui/chat/chat_box.tscn` (corner lines that fade; T/Enter opens the log with the bot-mute toggle,
Esc closes; emits `menu_toggled("chat", ...)`).

### DataRegistry (`autoload/data_registry.gd`)
Loads every file in `core/data_schema.gd::FILES` at startup, validates it, converts integer fields to
`int` and `[x,y,z]` fields to `Vector3`, checks cross-references (unique ids, starter gun exists, arena
bot types exist, colour names exist in the palette). Errors are `push_error`ed as
`res://data/<file>.json: <key path>: <problem>` and kept in `errors()`. Returned containers are shared:
**treat as read-only**.

| Method | Returns |
|---|---|
| `reload(dir := "res://data") -> bool` | reloads everything; emits `data_loaded(ok)` |
| `is_valid() -> bool`, `errors() -> PackedStringArray` | validation result |
| `economy() -> Dictionary` | economy.json |
| `player() -> Dictionary` | player.json |
| `guns() -> Array`, `gun(id) -> Dictionary`, `starter_gun_id() -> String` | guns.json (`{}` if unknown id) |
| `bots() -> Array`, `bot(id) -> Dictionary` | bots.json |
| `arenas() -> Array` (sorted by `order`), `arena(id)`, `first_arena_id()` | arenas.json |
| `bot_stats(bot_id, arena_id) -> Dictionary` | bot stats × arena `bot_mults` |
| `color(name) -> Color`, `palette() -> Dictionary` | palette.json |
| `chat() -> Dictionary` | chat.json |
| `get_file(stem) -> Variant` | raw access for files without a typed getter yet |
| static `load_dir(dir)`, `load_file(path, spec, errors)`, `cross_validate(data, errors)`, `resolve_bot_stats(bot, arena)` | pure helpers used by tests |

Adding a data file: schema in `core/data_schema.gd::FILES`, a typed getter here, a section in DATA.md.

### GameState (`autoload/game_state.gd`)
Fields: `cash: float`, `kills: int` (this run), `lifetime_kills: int`, `owned_guns: Array[String]`
(bought guns held; starter never listed), `equipped_gun_id: String` (`""` = starter), `cheat_levels`,
`cheat_enabled`, `server_slots`, `prestige_count`, `hax_points`, `rootkit`, `chat_flags`.
Read fields freely; change them only through methods (or, for cheat/chat dictionaries, only from
CheatSystem/ChatSystem).

| Method | Notes |
|---|---|
| `new_game()` | defaults + `economy.starting_cash` |
| `add_cash(amount)` | emits `cash_changed(total, amount)` |
| `can_afford(price) -> bool`, `try_spend(price) -> bool` | spend emits `cash_changed(total, -price)` |
| `add_kill()` | +1 kills and lifetime; emits `kills_changed` |
| `add_owned_gun(id)`, `owns_gun(id)`, `clear_loadout()` | death penalty = `clear_loadout()`; cash/kills kept |
| `to_dict() -> Dictionary`, `from_dict(d)` | JSON-safe; `save_version` = `SAVE_VERSION`; missing keys → defaults |
| static `migrate(d) -> Dictionary` | version upgrade hook (TASK-008) |

### SteamService (`autoload/steam_service.gd`)
Facade; backend chosen once in `_ready()` and logged once:
`[SteamService] backend: stub (GodotSteam not found)`. Backend interface: `autoload/steam_backend.gd`.

| Method | Stub behaviour |
|---|---|
| `backend_name() -> String` | `"stub"` |
| `is_steam_running() -> bool` | false |
| `get_player_name() -> String` | `"Player"` |
| `unlock_achievement(id) -> bool`, `set_stat(name, value) -> bool` | remembered in memory, true |
| `save_file(name, text) -> bool` | atomic write to `user://name` (tmp + rename) |
| `load_file(name) -> String` | text or `""` |
| `file_exists(name)`, `delete_file(name)` | user:// |
| static `godotsteam_present()`, `select_backend(steam_present)` | used by tests |

GodotSteam (Phase 5) adds `autoload/steam_service_godotsteam.gd` extending `steam_backend.gd`;
`select_backend` picks it automatically when the `Steam` singleton exists.

### CheatSystem (`cheats/cheat_system.gd`, autoload after SteamService)
Owns the 12 cheats and mod-menu upgrades (Server Slots) as `CheatBase` resources built from
`data/cheats.json`, and is the only writer of `GameState.cheat_levels/cheat_enabled/server_slots`.
- Queries: `cheats()`, `upgrades()`, `get_cheat(id)`, `level(id)`, `is_owned`, `is_enabled`,
  `is_unlocked`, `is_maxed`, `next_cost`, `can_purchase`, `any_cheat_active()` (cheats only),
  `effect(id, key)` (neutral unless owned and enabled), `extra_bots()`.
- Actions: `purchase(id)` (first buy enables the cheat and emits `cheat_purchased` then
  `cheat_toggled(id, true)`), `set_enabled(id, on)` / `toggle(id)` (calls `apply()` / `remove()`),
  `refresh_unlocks()` (call after prestige changes).
- Re-applies owned+enabled cheats on `player_spawned`, `gun_equipped` and `game_state_loaded`.
- `CheatBase` (`cheats/cheat_base.gd`): `apply(player, level)`, `remove(player)`, `cost(level)`,
  `max_level`, `value_at(key, level)`. Default apply/remove handle `player`/`weapon` effects;
  per-cheat scripts (named in data) override for custom behaviour.

### Economy (`core/economy.gd`, `class_name Economy`, static)

| Function | Formula |
|---|---|
| `cost(base, growth, level)` | `base * growth^level`; level = levels already owned (0 → base) |
| `cost_range(base, growth, level, count)` | sum of the next `count` costs |
| `cash_per_kill(base, headshot, streak, multipliers)` | `base * (headshot ? headshot_mult : 1) * streak_multiplier * global_mult` |
| `streak_multiplier(streak, step, cap)` | `1 + min(streak*step, cap)`; streak = kills before this one since last death |
| `can_afford(cash, price)` | `price <= cash` |
| `hax_points(lifetime_kills, divisor)` | `floor(sqrt(lifetime_kills / divisor))` |

`multipliers` keys match `economy.json.kill_reward` (`headshot_mult`, `streak_step`, `streak_cap`) plus
`global_mult` (arena `cash_mult` × prestige × Rootkit), so callers pass `kill_reward` merged with
`global_mult`. Bot `cash_mult` scales `base`.

## 4. Scenes and nodes

- `scenes/main.tscn` (`main.gd`): `WorldEnvironment`, `Sun`, `Arena` (instance), `Player` (instance),
  `UI` (CanvasLayer for HUD/menus). main.gd builds the arena from `DataRegistry.arena(id)`, places the
  player on `player_spawns[0]`, emits `player_spawned`. Later tickets add `RoundController`,
  `BotSpawner` and UI scenes as children here.
- `shooter/player/player.tscn`: `Player (CharacterBody3D, group "player", layer player, mask world)`
  → `CollisionShape3D` (capsule r 0.4, h 1.8) · `Head (y 1.6)` → `Camera3D` → `WeaponMount`.
  TASK-002 attaches `player.gd`; TASK-004 puts the WeaponManager under `WeaponMount`.
- `shooter/arenas/arena.tscn` (`arena_builder.gd`): `build(arena_def)` creates `Blocks/` (one box mesh
  per block, palette material) and one `Collision` StaticBody3D (WORLD layer) with a box shape per
  block; exposes `player_spawns`, `bot_spawns: Array[Vector3]`, `block_count()`, signal `built(id)`.
  TASK-002 adds merged meshes and a runtime `NavigationRegion3D` bake.
- `shooter/loot/`: `LootDropper` (child of Main; listens to `bot_killed`, drops bonus cash per
  economy.json `loot`) and `LootPickup` (group "loot", parented to the BotSpawner so round-end
  cleanup frees it; pays `GameState.add_cash` when the player is close; Loot Magnet pulls it).

### Physics layers (`core/layers.gd`)
| Bit | Name | Used by |
|---|---|---|
| 1 | world | arena blocks |
| 2 | player | player body |
| 3 | bots | bot bodies |
| 4 | hitboxes | bot head/body `Area3D`s — weapon raycasts mask this + world |
| 5 | pickups | coins, loot magnet |

## 5. Input map (project.godot, rebindable via InputMap)
`move_forward` W · `move_back` S · `move_left` A · `move_right` D · `jump` Space · `fire` LMB ·
`reload` R · `buy_menu` B · `mod_menu` Insert **and** F1 · `chat` T / Enter · `pause` Esc.
Physical keycodes are used so the layout works on AZERTY etc. Never check raw keys in gameplay code;
use the action names. Buy-menu hotkeys 1–9 are handled inside the buy menu (TASK-006).

## 6. Rendering
Forward+ for desktop (`rendering/renderer/rendering_method`). The web demo uses the Compatibility
renderer (`rendering_method.web="gl_compatibility"`), so shaders and materials must avoid
Forward+-only features (SDFGI, volumetric fog, compute) unless guarded. Art is flat-colour voxels:
`StandardMaterial3D` with the palette colour, no textures needed yet.

## 7. Testing and tooling
- `tools/install_godot.sh` — downloads the pinned editor (headless-capable) + export templates to
  `~/.local/godot`, symlinks `~/.local/bin/godot`.
- `tools/run_tests.sh` — import, GUT (`.gutconfig.json`: `tests/unit`, `tests/integration`), then a
  120-frame headless boot of main.tscn; fails on any test failure, `SCRIPT ERROR`/parse error, an
  `ERROR:` during boot, or if the SteamService line is not logged exactly once.
- `tools/export.sh linux|windows|all [--debug]` → `build/<platform>/`.
- GUT treats unexpected `push_error` as a test failure. Pure helpers (`DataRegistry.load_dir`,
  `load_file`) return errors instead of pushing them so tests can assert on them.
- Test naming: `tests/unit/test_<module>.gd`; integration tests instantiate `scenes/main.tscn`.
