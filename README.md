# Cheat Code Idle

A single-player, first-person, cartoon voxel arena shooter with incremental progression. Kills earn
cash; cash buys cheats (mod menu, **Insert**/**F1**) and guns (buy menu, **B** during freeze time).
Every cheat removes one chore, until you noclip through the map, get banned (prestige) and climb again.

Built with **Godot 4.7.2** (GDScript only). Steam is optional: the game runs without it.

## Quick start (Linux)
```bash
tools/install_godot.sh          # pinned Godot + export templates -> ~/.local/godot, ~/.local/bin/godot
export PATH="$HOME/.local/bin:$PATH"
tools/run_tests.sh              # GUT tests + headless boot; exits non-zero on failure
godot --path .                  # play from source
godot --path . -e               # open the editor
tools/export.sh linux           # -> build/linux/CheatCodeIdle.x86_64
tools/export.sh windows         # -> build/windows/CheatCodeIdle.exe
```
On Windows/macOS install Godot 4.7.2 from godotengine.org, open `project.godot`, and press F5.
`tools/install_godot.sh --no-templates` skips the ~1.2 GB templates if you only need to run tests.
Set `GODOT=/path/to/godot` to use a different binary with the scripts.

## Controls (rebindable)
WASD move · Space or mouse wheel jump · V noclip (with the cheat) · LMB fire · R reload · B buy menu (freeze time) · Insert/F1 mod menu ·
T/Enter chat · Esc pause

## Layout
`autoload/` global services · `core/` pure logic · `cheats/` · `shooter/` (player, weapons, bots,
arenas) · `ui/` · `data/` (all numbers) · `tests/` · `tools/` · `docs/`

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — module map, dependency rules, autoload APIs, EventBus signals
- [docs/DATA.md](docs/DATA.md) — data file formats
- [docs/DECISIONS.md](docs/DECISIONS.md) — decision log
- [docs/BUILD_NOTES.md](docs/BUILD_NOTES.md) — per-build test scripts and feedback requests

## Rules for contributors (human or AI)
- No balance numbers in scripts; put them in `data/*.json` (see DATA.md).
- UI → services → GameState/Economy → DataRegistry. Nothing imports UI. Systems talk via `EventBus`.
- Add GUT tests in `tests/unit/test_<module>.gd`; `tools/run_tests.sh` must pass before merge.
- Third-party: GUT (MIT) in `addons/gut/`.
