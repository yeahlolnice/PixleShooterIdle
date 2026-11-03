# Decisions

Short records: what was decided, why, and who decided. Newest at the bottom.
When the plan is silent, pick the simplest option that fits the design, record it here, and keep going.

| # | Decision | Why | Source |
|---|---|---|---|
| D1 | Engine: Godot 4, GDScript only; pinned to **4.7.2-stable** in `tools/godot_version.txt` | Free, light, native Win/Linux exports, keeps a web demo possible | Plan / TASK-001 |
| D2 | Renderer: Forward+ on desktop; Compatibility (`gl_compatibility`) override for web; shaders must compile on both | Web demo stays possible | Plan |
| D3 | Steam via GodotSteam behind `SteamService`; stub backend chosen automatically when the `Steam` singleton is missing; GodotSteam wired in Phase 5 | Game must run without Steam | Plan |
| D4 | All balance/content numbers in `data/*.json`, validated by `DataRegistry` against schemas in `core/data_schema.gd` | Easy agent + human editing; reviewers reject literals | Plan |
| D5 | Numbers are 64-bit floats with short-format display (1.2K, 3.4M); a mantissa/exponent BigNumber is added only if the balance pass needs it | Floats reach ~1e308; simpler | PM plan |
| D6 | Working title in game: **Cheat Code Idle** (repo name "Pixle Shoot Idle") | Default until the human says otherwise | PM default (Q1) |
| D7 | Platforms at launch: Windows + Linux. No macOS (needs Apple signing) | Brief lists Windows and Linux | PM default (Q2) |
| D8 | Mod menu bound to **Insert and F1** by default, both rebindable | Many laptops lack Insert | PM default (Q3) |
| D9 | "Active ×3 bonus" from the plan is dropped; only the legit-mode coin (50% chance of +1 coin per kill while all cheats are off) is implemented | Plan mentions it once without a definition | PM default (Q6) |
| D10 | No offline/idle earnings | Plan | Plan |
| D11 | Cheat cost = `base × growth^level` with growth 1.15 stored in data | Plan formula | Plan |
| D12 | Hax Points = `floor(sqrt(lifetime_kills / 1000))`, divisor in economy.json | Plan formula | Plan |
| D13 | Prestige unlocks: God Mode after ban 1, Spinbot after ban 2, Noclip after ban 3 | Plan | Plan |
| D14 | Death costs only the current gun and streak; cash, kills, cheats are kept | Plan | Plan |
| D15 | Difficulty scales per arena (`arenas.json.bot_mults`), never with time | Plan | Plan |
| D16 | Tests: GUT 9.7.1 vendored in `addons/gut`, excluded from exports | Plan; GUT 9.7.x supports Godot 4.7 | Architect |
| D17 | Systems communicate through the `EventBus` autoload; data flows UI → services → GameState/Economy → DataRegistry; nothing imports UI | Keeps modules testable and swappable | Architect |
| D18 | `EventBus.round_state_changed` carries `(state: StringName, info: {round, duration})`, states `freeze/live/summary` as `EventBus.ROUND_*` constants | Listeners need the round number and duration; StringName logs and serialises well | Architect |
| D19 | Kill streak for cash = kills before this one since the last death (first kill = 0); bonus `1 + min(streak × step, cap)` with step 0.1, cap 1.0 (max ×2) | Plan says streaks pay more but gives no formula | Architect |
| D20 | Starting values: base 10 cash/kill, headshot ×1.5, pistols 0 / 80 / 150 | First buyable gun in ~8 kills; matches "first cheat < 2 min" pacing with Speed Hack at 10 kills | Architect (tune at Gate 1) |
| D21 | Arena blocks are axis-aligned boxes with `pos` = centre; colours are palette names, never hex | Simplest voxel layout format; one shared palette | Architect |
| D22 | `GameState.owned_guns` lists bought guns currently held (never the starter); `clear_loadout()` on death | CS-style "keep until death" | Architect |
| D23 | Saves go through `SteamService.save_file/load_file`; the stub writes atomically (tmp + rename) to `user://` | Steam Cloud can plug in later without touching SaveService | Plan / Architect |
| D24 | Input uses physical keycodes | Same physical WASD on non-QWERTY layouts | Architect |
| D25 | `.gitattributes` forces LF line endings | The factory git config has `core.autocrlf=true`, which would break shell scripts | Architect |
| D26 | Godot is installed to `~/.local/godot` (symlink `~/.local/bin/godot`); scripts honour `$GODOT` | No root needed in fresh containers | Architect |
| D27 | Save file `user://save.json` (via SteamService), pretty JSON with full float precision; dict without `save_version` = v0, migrated step by step in `GameState.migrate`; newer versions load known keys with a warning | Round-trip must be exact; migrations stay one small step per bump | Bea (TASK-008) |
| D28 | Corrupt save (unparseable or not a JSON object) is copied to `save.corrupt.json`, removed and replaced by a new game with a logged warning; wrongly typed fields fall back to defaults | Never crash, never silently lose the bad file | Bea (TASK-008) |
| D29 | Persistence is opt-in: `Main._enter_tree` calls `GameState.enable_persistence()` (export `use_save_file`); autosave on `round_summary` and on window close. SteamService picks its backend in `_enter_tree` so it is ready first | Tests never touch the player's save; saved gun is equipped on boot | Bea (TASK-008) |
