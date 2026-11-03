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

## Build 2026-11-03 — TASK-013 chat system (Phase 2, not a gate build)

**What changed**
- New ChatSystem autoload: every instruction (WASD/SPACE/mouse, LEFT CLICK, B to buy in freeze time,
  INSERT for the mod menu, T/ENTER for the log) arrives as chat lines from `data/chat.json`.
  Channels: SYSTEM (yellow), seller DM x_Hax_x (magenta), bots (white).
- Corner chat box fades out; T or ENTER opens a scrollable log with a "Mute bot chat" toggle
  (stored in `user://settings.cfg`, not in the save).
- Once-only tutorial lines are remembered in the save and are only marked as seen once they actually show.

**Test it in under 2 minutes**
1. `tools/run_tests.sh` → ends with `run_tests: ALL PASSED`.
2. Delete your save, run `godot --path .`: the welcome + B hint appear during freeze time, the shoot hint
   when the round goes live, and x_Hax_x DMs you about INSERT after your first kill.
3. Press T, tick "Mute bot chat", die once: no "gg ez" from bots, but the SYSTEM death hint still shows.

**Feedback we need**
- Does the chat-only tutorial read naturally, and is the corner box readable while fighting?
- First cheat purchase posts three lines: SYSTEM "X injected" (now), seller "pleasure doing business"
  (+1.5 s), seller "see? X on" (+4 s, because the first purchase also toggles the cheat on, D29).
  Is that order and pacing OK, or too chatty?

**Known issues**
- Not checked in a windowed build by the developer (headless tests only); `mod_spawned` and `prestige`
  lines exist in chat.json but nothing emits those events until their tickets land.

## Build 2026-11-03 — Phase 1 Prototype (TASK-002..007) — GATE: "Is shooting fun?"

**What changed**
- First-person movement, blocky arena, grunt bots (wander/chase/weak return fire, head/body hitboxes),
  data-driven pistols, round loop (freeze 8 s -> live 120 s -> summary 5 s), kill cash with headshot/streak
  bonuses, HUD, buy menu (B, freeze time only).
- Integration fixes (TASK-007): Main now spawns/clears bots through a BotSpawner on the round controller's
  signals (nothing spawned bots before); Weapon hitscans now damage real Bot hitboxes (the weapon called
  `apply_damage`, bots only had `take_hit`, and bot hitboxes use meta `hit_kind`, not `headshot`).
- New `tests/integration/test_prototype_loop.gd`: freeze -> live, head-shot a bot through the weapon fire
  path, cash rises by the Economy amount, player dies, gun resets to starter, cash kept. 74/74 tests pass.

**How to get it**
- Linux: `build/linux/CheatCodeIdle.x86_64` · Windows: `build/windows/CheatCodeIdle.exe` (both exported OK;
  Windows build not run). From source: `tools/install_godot.sh && godot --path .`

**Test it in under 2 minutes**
1. Launch. Freeze time (8 s): press **B**, buy a pistol you can afford (start cash may be $0: then skip).
2. Round goes live: bots appear. WASD + mouse, Space to jump, left click to fire, R to reload.
3. Kill 5+ bots; try headshots (head cube pays more) and watch the cash and streak on the HUD.
4. Let a bot kill you: you respawn with the starter pistol, keep cash.
5. Wait for the 2 min round to end and read the summary; next round freezes again.

**Feedback we need — "Is shooting fun?"**
- Mouse sensitivity / look speed: too fast, too slow, or fine?
- Bot accuracy and reaction: too weak, too deadly, or fair? Do they feel like they notice you?
- Time-to-kill: how many body shots / headshots per grunt? Satisfying or spongey?
- Pistol prices vs. cash per kill: how many kills until you can afford the next gun? Too grindy?
- Recoil/spread/reload feel on each pistol; is hit feedback (no hit markers yet) missing?
- Do 7 bots per wave feel empty or crowded in this arena?

**Known issues**
- BUG: HUD shows "AMMO ∞" until the first shot, and after equipping/buying a gun: `EventBus.ammo_changed` is
  only emitted in `Weapon.try_fire`, not on equip/reload finish (repro: start game, look at bottom-right). Fix: emit
  `ammo_changed(ammo, mag_size())` from `WeaponManager.equip` and `_finish_reload` (HUD must be ready first).
- No hit marker, sound for hits, or death screen yet (Phase 3 juice).
- Not verified: Windows binary runs; mouse input and live bot return fire (headless/xvfb only, no input).
- Export log under xvfb shows harmless ZINK/ALSA warnings (no GPU/audio in the container).

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
