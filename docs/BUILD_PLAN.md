# Build plan: from Gate 2 to launch

Nov 3, 2026. Source of truth for design is still *Cheat Code Idle — Game Plan*. This file says what
is built, what is missing against that plan, and the ticket backlog to finish the game. Ticket IDs
continue from TASK-015.

## 1. Where the build stands

The factory finished **Phase 1 (Prototype)** and **Phase 2 (Cheat core)** of the plan's five phases,
then stopped, as the PM prompt told it to: *"Do not start a phase until the previous gate is signed
off."* Gate 2 was never signed off, so Phases 3–5 were never started. Most of what looks "missed" is
work that was never scheduled to run yet, not work that failed.

Things that really did go wrong inside Phases 1–2 (all fixed in commits `9d09bc3` and `560f457`):

| Problem | Why the tests missed it |
|---|---|
| Server Slots never added bots (wave size read once at start) | Test checked `extra_bots()` maths, not a wave after buying |
| Recoil only tilted the camera and snapped back | Test checked the offset number, not where the next shot goes |
| Wallhack crashed at round end | No test freed bots while the scanner held them |
| 7 of 12 cheats were buyable but had no code | Data tests passed; nothing asserted "buying X changes the game" |
| Nobody ever ran a windowed build or the Windows binary | All checks were headless |

**Process fixes for the next phases** (put these in the PM prompt):
- Every gameplay ticket needs one **behaviour test in a real scene** ("buy X, play N ticks, assert
  the world changed"), not only data/unit tests.
- A cheat, gun, bot or arena is not "done" until it is reachable in normal play *and* does something.
  Nothing appears in a menu before its code exists.
- Each gate build includes **screenshots from a windowed run** (xvfb + `--write-movie` or a
  screenshot hook), so visuals and UI get looked at before the human does.
- Gates: the human signs off within a day, or the PM may start the next phase's *independent*
  tickets (content, art, audio) while gate feedback is pending.

## 2. What exists today

| Area | Built |
|---|---|
| Shooter | FPS controller, CS-style air strafing/bhop, hitscan weapons, recoil that moves aim, 3 pistols |
| World | 1 arena (Warehouse), voxel blocks + navmesh, 1 bot type (Grunt) that wanders/chases/shoots |
| Loop | Freeze → live → summary rounds, waves, kill cash with headshot/streak, MatchTracker summary |
| Shops | Buy menu (B, freeze time), mod menu (Insert): tabs, locked "???" rows, injector bar, 0.2× slow-mo |
| Cheats | All 12 + Server Slots have code and tests (the last 7 are new and **not yet play-tested**) |
| Loot | Bonus cash drops + Loot Magnet (added to give the magnet a job; D47) |
| Chat | SYSTEM + seller tutorial lines, 2 bot lines, log, bot mute |
| Data/infra | All numbers in `data/*.json` with schema checks, save/load + autosave, Steam stub, GUT tests, Linux/Windows export scripts, `--dev-cash` |

## 3. Gaps against the plan

**Content**
- Arenas: 1 of 4 (missing Rooftop, Pixel City, Server Room), no arena select or unlock, so the
  "×10 cash per arena" gate does not exist.
- Bots: 1 of 5 types (missing Sniper, Rusher, Heavy, **Mod**).
- Guns: 3 pistols of ~10 (missing SMG, shotgun, rifle, sniper, LMG, golden rifle, confetti cannon).
  The weapon code is single-ray hitscan only: no pellets, scope or projectiles.
- Gun upgrades (damage and fire-rate levels per gun) do not exist.

**Progression**
- Prestige / "Get Banned" is missing entirely: no ban flow, no Hax Points payout, no Rootkit perk
  shop. GameState already has the fields, and God Mode/Spinbot/Noclip already gate on bans, so
  **those three cheats are unreachable in normal play** today.
- Legit-mode coin: data only, not implemented.
- Anti-cheat Mods that disable a cheat: not implemented. The chat line for it exists but nothing triggers it.
- Big-number handling: no number formatting (1.2K / 3.4M / 1.2e15). The plan's mantissa class is
  probably overkill (floats reach 1e308), but the formatting is needed.
- No balance pass, and no simulated-player tool for one.

**Feel / art / audio (all Phase 3 "juice")**
- No hit markers, headshot ding, damage or `+$12` pop-ups, screen shake, kill feed or death screen.
- Cheat visuals from the plan: aimbot FOV circle and red laser, God Mode rainbow shimmer, ESP price tags
  on loot. Also missing: any HUD readout for noclip fuel or god-mode time.
- Bots are two coloured boxes (no faces), guns are grey boxes, and there are no coin/confetti death bursts.
- Audio: one procedural gunshot noise. No hit, coin, UI or kill sounds, and no music. The music was
  meant to layer up with active cheats.
- Mod menu skins: not implemented.

**UX**
- No title screen, pause menu, settings (sensitivity, FOV, volume, keybinds, graphics) or credits.
  The README lists "Esc pause", but no code handles it.
- Chat: bot reactions to how obvious you are ("bro is walling", "HOW IS HE IN THE FLOOR") are mostly
  missing, and the `mod_spawned` and `prestige` triggers have lines but no emitter.

**Platform (Phase 5)**
- GodotSteam backend, achievements, Steam Cloud, demo build, Mac export and Steam Deck/perf work are
  all missing, and `--dev-cash` still works in release builds (D42).

**Housekeeping**
- New `*.gd.uid` files from the last commit are untracked; commit them.
- Local `data/cheats.json` has hand-edited test values (unlock 1 / cost 1). Replace with a
  `--dev-unlock-all` flag so data files never need editing to test.
- Plan's "active ×3 bonus" was dropped (D9) but is still named in the plan's risk section; update the plan.

## 4. Backlog

Sizes: S ≈ half a day of agent work, M ≈ 1–2 days, L ≈ 3+ days. "Test" = automated behaviour test;
"Human" = what the owner checks at the gate. Tickets in the same phase without a "needs" can run in
parallel.

### Phase 2.5 — Stabilise and sign off Gate 2 (≈ 2–3 days)

**Status (Nov 3): TASK-016…021 done** (200 tests green, windowed tour in `build/screens/`). The tour
also caught and fixed "AMMO ∞" at round start and `det == 0` errors from bots popping to zero
scale. Waiting on the human Gate 2 sign-off (see BUILD_NOTES.md).

| ID | Ticket | Size | Acceptance |
|---|---|---|---|
| TASK-016 | Run the full GUT suite on the last two commits; fix failures | S | `tools/run_tests.sh` green |
| TASK-017 | Commit `.uid` files; add `--dev-unlock-all` (debug builds only, along with `--dev-cash`); revert hand-edited `cheats.json` | S | Test: flags ignored in a release-feature build |
| TASK-018 | Windowed smoke script: boot, buy each cheat via flags, capture screenshots per cheat into `build/screens/` | M | Screens attached to the build note |
| TASK-019 | Number formatting (`Fmt.cash(1234567) = "$1.23M"`) used by HUD, menus, chat | S | Unit tests for K/M/B/T/e-notation |
| TASK-020 | Pause menu (Esc): resume, settings stub, quit to desktop; pauses the round | S | Test: round timer stops while paused |
| TASK-021 | Cheat status HUD strip: active cheat icons, noclip fuel bar, god-mode timer, "disabled by Mod" state | M | Human: readable at a glance |
| — | **Gate 2 sign-off**: play 15 min with the new cheats; answer the Gate 2 feel questions | — | Human |

### Phase 3 — Vertical slice (≈ 2–3 weeks)

| ID | Ticket | Size | Acceptance |
|---|---|---|---|
| TASK-022 | Weapon system v2: pellets (shotgun), scope/zoom (sniper), sustained fire with spread bloom (SMG/LMG), per-gun viewmodel + fire anim | L | Tests: pellet count/spread; zoom FOV; bloom grows/recovers |
| TASK-023 | Gun ladder data: SMG, shotgun, rifle, sniper, LMG with prices/unlock kills; buy menu categories | M (needs 022) | Test: each gun buyable, kept until death, reset on death |
| TASK-024 | Gun upgrades: damage + fire-rate levels per gun in buy menu, saved, reset on prestige | M (needs 023) | Test: upgrade changes damage; persists through save |
| TASK-025 | Bot types: Sniper (holds range, uses cover, long sight) and Rusher (fast, strafes) with per-type AI params in `bots.json` | L | Tests: sniper keeps distance; rusher strafes |
| TASK-026 | Arena 2 Rooftop + arena progression: unlock rule, arena select in freeze time, cash ×10, harder bot mults | L | Test: unlock → select → cash per kill ×10 |
| TASK-027 | Juice pack: hit marker + headshot ding, damage numbers, `+$12` pop-ups, screen shake (setting), kill feed, death screen with killer | M | Human: shooting feels punchy |
| TASK-028 | Audio pack: procedural SFX bank (shots per gun, hits, headshot, coin, UI click, buy, unlock, death), audio bus + volume | M | Every EventBus gameplay signal has a sound |
| TASK-029 | Voxel art pass v1: bot faces and per-type silhouettes, gun models, coin/confetti death burst, arena themes, one palette texture | L | Human: art approval |
| TASK-030 | Cheat visuals: aimbot FOV circle + red laser, god-mode shimmer, ESP price tags on loot, triggerbot crosshair flash, spinbot whip trail | M | Human: each cheat is visible on screen |
| TASK-031 | Store page drafts: description, feature bullets, capsule art brief, 5 screenshot shot-list | S | Human: approve text |
| — | **Gate 3**: "Are friends hooked?" Give 2–3 friends the build | — | Human |

### Phase 4 — Full content (≈ 3–4 weeks)

| ID | Ticket | Size | Acceptance |
|---|---|---|---|
| TASK-032 | Prestige "Get Banned": ban screen (fake VAC-style parody), reset rules per D-log, Hax Points = ⌊√(lifetime/1000)⌋, `prestige` chat event | L | Test: ban resets cash/guns/gun upgrades/cheats/slots/run kills, keeps lifetime + Hax Points |
| TASK-033 | Rootkit perk shop (`rootkit.json`): global cash ×, starting cheat levels, cheaper guns, starting cash | M (needs 032) | Test: each perk changes the next run |
| TASK-034 | Heavy bot (high HP, slow, armour on body so headshots matter) | M | Test: body damage reduced |
| TASK-035 | Mods (anti-cheat bots): hunt the player, on hit suspend a random active cheat for 30 s; immune to Aimbot/Triggerbot/Spinbot lock and Hitbox Expander, so they must be killed by hand; `mod_spawned` chat; CheatSystem `suspend(id, s)` API shown in mod menu + HUD | L | Tests: suspend/resume; aimbot ignores Mods; manual kill clears suspension |
| TASK-036 | Arenas 3–4: Pixel City, Server Room (final, Mods common) | L | Test: each loads, navmesh bakes, unlock chain |
| TASK-037 | Legit-mode coin: 50% extra coin per kill while all cheats are off; HUD "LEGIT" badge | S | Test: coin only with all cheats off |
| TASK-038 | Bot chat reactions per cheat (walling, aimbot snaps, bhop speed, noclip "in the floor", god mode), rate-limited | M | Test: trigger per cheat-use event; rate limit |
| TASK-039 | Joke guns: golden rifle, confetti cannon (kill = confetti burst), unlocked by kills | M (needs 022) | Human: fun |
| TASK-040 | Mod menu skins: unlockable themes (by bans/kills), saved setting | S | Test: skin persists |
| TASK-041 | Music: chiptune-synthwave loop with stems that layer in as more cheats are active | M | Test: stem count follows active cheats |
| — | **Gate 4**: "Content locked" | — | Human |

### Phase 5 — Polish and launch (≈ 3–4 weeks)

| ID | Ticket | Size | Acceptance |
|---|---|---|---|
| TASK-042 | Simulated-player balance tool (`tools/sim_player.gd`): model kills/min per cheat set, output cash/min CSV + chart per level | L | Report shows targets: 1st cheat < 2 min, 1st ban 2–3 h, noclip 10–12 h |
| TASK-043 | Balance pass from the sim + playtests (data only) | M (needs 042) | Sim hits targets ±20% |
| TASK-044 | Title screen, settings menu (sensitivity, FOV, volume per bus, keybinds, graphics quality, screen shake, chat mute), credits | M | Settings persist in `settings.cfg` |
| TASK-045 | GodotSteam backend: achievements (first cheat, each cheat maxed, each ban, noclip, legit 100 kills), Steam Cloud save, overlay | L | Human: works on a Steam dev build |
| TASK-046 | Demo build: feature flag limiting to arena 1–2, first 6 cheats, no prestige; "wishlist" end screen | M | Test: demo flag hides locked content |
| TASK-047 | Performance: MultiMesh arena blocks, bot cap, pooled tracers/particles, Steam Deck preset | M | 60 fps with 50 bots on Deck-class hardware |
| TASK-048 | Release hardening: dev flags debug-only, crash log file, save backup rotation, Mac export preset | M | Release build ignores dev flags |
| TASK-049 | Accessibility: colour-blind safe outlines/palette option, hold-vs-toggle options, subtitle-sized chat | S | Human |
| — | **Gate 5**: release decision | — | Human |

## 5. Extra polish (optional, not in the plan)

Ranked by fun per effort; pick freely once Phase 4 is in.

1. **Kill-streak announcer** in chat and HUD ("TRIPLE KILL", "HE'S ON A RAMPAGE" from bots).
2. **Ban cutscene**: fake "VAC detected" screen, hammer, account-reset animation before the Rootkit shop.
3. **Cheat combos**: small bonuses for pairs (Bhop + Speed Hack = speed trail, Wallhack + Aimbot = "rage" badge, ×1.1 cash).
4. **End-of-run stats screen** at each ban: total kills, time, top cheat, fastest bhop speed.
5. **Viewmodel polish**: reload animations, inspect key, weapon sway and bob.
6. **Bot personalities**: random names and taunts from `chat.json`; "rage quit" when you kill them 3 times.
7. **Photo mode / replay of the last kill** (great for store screenshots and trailers).
8. **Daily challenge seed**: one arena, fixed cheats, local best only (fits single-player).

## 6. Suggested order and parallel tracks

- Do Phase 2.5 first; it is small and unblocks honest play-testing.
- In Phase 3, run three tracks in parallel: **weapons** (022→023→024, 039 later), **world**
  (025, 026), **feel** (027, 028, 029, 030). They touch different folders.
- In Phase 4, prestige (032→033) is the critical path, because God Mode, Spinbot and Noclip
  are unreachable until it lands. Start it first.
- Keep TASK-042 (sim tool) early in Phase 5, or even late Phase 4, since balancing blocks the demo.
