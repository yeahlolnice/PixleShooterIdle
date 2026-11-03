# Build notes

One entry per ticket batch, newest first. Keep each entry short; the human should be able to test in
under 2 minutes.

<!-- Template — copy below this line
## Build <date> — <phase / tickets>

**What changed**
- ...

**How to get it**
- Linux: `build/linux/CheatCodeIdle.x86_64` · Windows: `build/windows/CheatCodeIdle.exe`
  (or run from source: `tools/install_godot.sh && godot --path .`)

**Test it in under 2 minutes**
1. ...
2. ...

**Feedback we need**
- ...

**Known issues**
- ...
-->

## Build 2026-11-03 — TASK-001 scaffold (not a gate build)

**What changed**
- Godot 4.7.2 project skeleton, autoloads (EventBus, DataRegistry, GameState, SteamService + stub),
  Economy maths, data files, GUT tests, install/test/export scripts, docs.

**Test it in under 2 minutes**
1. `tools/install_godot.sh` (first time only; downloads ~1.3 GB of editor + templates).
2. `tools/run_tests.sh` → ends with `run_tests: ALL PASSED`.
3. `godot --path .` → you see a blue-grey warehouse with crates from the first-person camera. Nothing
   moves yet; the player controller comes in TASK-002.

**Feedback we need**
- None yet. The first real feedback request is Gate 1: "Is shooting fun?"
