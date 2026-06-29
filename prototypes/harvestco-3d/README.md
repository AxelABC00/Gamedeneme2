# HarvestCo 3D — 2D→3D Migration (Phases A+B)

> PROTOTYPE / production-candidate seed. Not yet production code.
> Follows the roadmap in [`design/3d-migration-plan.md`](../../design/3d-migration-plan.md).

## Hypothesis
The 2D `_draw()` prototype's **game logic is render-independent** and can be lifted
into a headless `sim.gd`, with a separate 3D `world.gd` rendering it — proving the
"keep the logic, replace the view" migration before tackling the risky touch→3D step.

## What's here (Phase A + B)
- **`sim.gd`** — game state + rules, ported from `prototypes/bot-orchestration-concept/`.
  Pure data/math, **no visuals, no input** (a `RefCounted`, unit-testable). Tile
  lifecycle (EMPTY→TILLED→PLANTED→GROWING→RIPE, OBSTACLE), the 7-crop table, golden
  tiles, and time-based growth (`tick`). `setup_demo()` seeds one row per stage so the
  full lifecycle is visible at a glance.
- **`world.gd`** (Node3D) — reads `sim` and renders it: cozy environment/sun/soft
  shadows/SSAO + angled camera (from the look-test), a real `MeshInstance3D` soil
  grid colored by tile state, rocks on obstacles, and a **procedural plant per tile**
  (stem + foliage + colored fruit) whose height tracks growth and whose fruit color is
  the crop's signature color (gold + emissive for golden tiles). Growth animates live.
- **`assets/`** — Quaternius CC0 `small_farm.glb` (farmhouse) + `crops.glb` (kept for
  later; the procedural plants replaced it for clear stage readability).

## Architecture (the point of this phase)
`sim.gd` ⟶ `world.gd`. Logic never imports rendering; the view only reads sim state.
This is the `sim.gd` / `world.gd` split from the migration plan. Input (touch→3D
raycast) and bots are deliberately **not** here — those are Phases C and D.

## How to run
- **Editor:** open this folder in Godot 4.3 and press Play.
- **Verification screenshot (headless-ish):**
  ```
  godot --headless --import --path .        # once, to import the .glb assets
  VERIFY_SHOT=1 godot --path .              # writes _shot_3d.png then quits (~20s; Forward+ shader compile)
  ```

## Status: Phase A+B CONCLUDED ✓
Screenshot (`_shot_3d.png`) confirms the logic→3D mapping: every tile state renders
distinctly, growth animates, golden crops glow. The logic/view split holds.

## Findings
- The port was near-verbatim — tile states, crop table, and growth math moved with no
  logic changes. Confirms the migration plan's core premise.
- Procedural primitives (stem/foliage/fruit) read the lifecycle more clearly than the
  generic dirt-patch `crops.glb`; real per-stage crop models are a Phase G polish step.
- **Portrait framing of an 8-wide field** needs a pulled-back, raised camera (fov 58,
  ~y13/z13). Confirms the plan's "variable aspect ratio" risk is real and worth solving
  generically in production.

## Phase C CONCLUDED ✓ — touch→3D hand-farming is playable
Done in two steps (logic first, then input):
- **Economy ported into `sim.gd`** — `manual()` (one tap = next lifecycle step),
  `harvest_tile()`, `sell_all()`, `buy_water()`, `stock_total()`, `sell_mult()`, plus
  coins/water/stock/flour state. `manual()` returns `bool` (acted / blocked) — the
  green/red flash is the view's job, not the logic's. Verified by `test_sim.gd`
  (`godot --headless --script res://test_sim.gd`) → **26/26 deterministic checks pass**.
- **Raycast input in `world.gd`** — `_unhandled_input` → `_tap` → `_tile_under`
  (`camera.project_ray_origin/normal` → `Plane(UP, 0.10).intersects_ray` → world → tile
  index) → `sim.manual(idx)` → `_refresh_tile` (soil tint + rock + plant) + a quick
  green/red feedback pop. Per-tile nodes are tracked so a single tile updates in place.
- Verified headlessly with `TAP_TEST=1 VERIFY_SHOT=1` — `unproject → _tile_under`
  round-trips correctly (corner/neighbour/front tiles), and a programmatic harvest
  resets the front tile to empty soil in `_shot_3d.png`.

## Phase F CONCLUDED ✓ — real Control-node HUD
The loop is now self-sustaining: the `_draw`-era debt is paid off with real Control nodes.
- **`hud.gd`** (CanvasLayer, code-built Controls; becomes `hud.tscn` at production) —
  top bar reads coins / water / depo (x/cap); bottom holds a per-crop **seed picker**
  (one Button each, modulated by the crop color, selected one prefixed `>`), **Sat**
  (`sell_all`), and **Su Al** (`buy_water`). Emits `sell_pressed` / `buy_water_pressed`
  / `seed_selected(idx)`; `world.gd` runs the sim funcs, then `hud.refresh(sim)` + a
  fading center `toast`. `refresh` is also called after every tap so readouts stay live.
- Mobile: explicit top/bottom anchors + safe-area margins + large (50–62px) tap targets.
  Center stays clear so field taps fall through; toast is `MOUSE_FILTER_IGNORE`.
- Verified `HUD_TEST=1 VERIFY_SHOT=1` — signal→handler→sim wiring all PASS (Sat +24 coins,
  Su Al water +25/coins −4, seed pick updates `selected_seed`); `_shot_3d.png` shows the
  full HUD laid out correctly over the field.

## Phase F2 CONCLUDED ✓ — store page + homestead buildings (2D parity, part 1)
Closes the biggest parity gap from the 2D build: the full economy and a real store.
- **Economy/upgrade/building logic ported into `sim.gd`** (near-verbatim from 2D): all
  upgrade levels (yield/speed/dura/well/windmill/depo), passive buildings (well makes
  water, windmill grinds wheat→flour in `tick`), `sell_mult`/`yield_mult`/`bot_speed`/
  `wear_rate`, every cost formula, `buy_*` funcs, field expansion, bot data+cost (`buy_bot`
  returns a `Bot`; AI movement is Phase D), and the store item model
  (`tab_items`/`item_info`/`item_cost`/`item_enabled`/`buy_item`). Verified by
  `test_sim.gd` → **52/52 deterministic checks pass**.
- **`store.gd`** (CanvasLayer overlay, code-built) — a real 3-tab store page
  (**Botlar / Yukseltmeler / Binalar**), scrollable rows with accent swatch + title +
  desc + live cost button (disabled when unaffordable/unavailable). Emits
  `buy_requested(id)`; `world.gd` runs `sim.buy_item`, refreshes, and **closes on bot
  purchase** so the player can place it (Phase D). Opened by the HUD **Magaza** button.
- **Homestead buildings next to the farmhouse** (`world.gd`) — procedural windmill, well,
  and depot in a band beside the farmhouse, each a tappable `StaticBody3D`
  (physics-raycast in `_tap`): **well = Su Al, depot = Sat, farmhouse = Magaza,
  windmill = Magaza→Binalar**. Field expansion rebuilds the plot live.
- Verified `STORE_TEST=1` (open → buy upgrade keeps store open → buy bot closes store,
  all PASS) and screenshots of the homestead band + all three store tabs.

## Phase D CONCLUDED ✓ — bot AI + nice robots + zone painting (2D parity, part 2)
The **automation core** — "automate your labor" — is now live in 3D.
- **Bot AI ported into `sim.gd`, render-independent** — each `Bot` carries a grid-space
  `gpos: Vector2` (col,row floats), so movement/targeting/work-timing all happen in the
  sim and the view just reads it. `tick_bots(delta)`: condition decay, `_pick_target`
  (TILL/CLEAN bots spread to untouched tiles, others go nearest), a `claimed[]` array so
  no two bots fight over a tile, move→work state machine in grid space, `_apply_task`
  (TILL/PLANT/WATER/HARVEST/GOLD_HUNT/CLEAN), `_can_do` gating (WATER needs water, PLANT
  needs coins), plus a soft push-apart so idle bots don't stack. Verified by `test_sim.gd`
  → **61/61 deterministic checks pass** (tests 21–26 cover buy→paint→work, claim
  exclusion, idle-without-water, condition decay, harvest+bank, long-range travel).
- **Nice procedural robot (`world.gd: _make_bot`)** — a cute low-poly farmbot: dark
  tracked base + 4 wheels, cream chassis, **task-colour glowing belly panel**, head with
  a dark visor and two glowing task-colour eyes, an antenna topped with a glowing bulb,
  and two little arms. Colour-coded per specialist (matches the store/tool swatches), so
  you read a bot's job at a glance. `_sync_bots` smooth-follows `_grid_to_world(gpos)`,
  faces travel direction (`atan2`+`lerp_angle`), and bobs while working.
- **Zone painting** — a HUD **tool row** (`El` hand + one colour chip per owned bot + a
  `Sil` erase toggle); selecting a bot shows its zone as glowing tinted tiles and
  tap/drag paints (or erases) that bot's work area. Buying a bot auto-selects it.
  Reuses `_tile_under` for tap+drag (`InputEventScreenDrag` / mouse-motion).
- Verified `BOT_TEST=1` (buy→paint→tick→tile worked + view node spawned, all PASS) and
  `BOT_SHOW=1 VERIFY_SHOT=1` — `_shot_3d.png` shows specialist bots out on the field
  tilling/harvesting/cleaning with their painted zones.

## Phase H CONCLUDED ✓ — random events (2D parity, part 3)
The last 2D parity gap is closed: the field now has weather and visitors.
- **Event logic ported into `sim.gd`, render-independent** — `tick_events(delta)` runs an
  `event_timer` (45–80s) that fires `_trigger_event()` from a weighted pool (rain ×2,
  trader ×3, UFO ×1, birds ×3 only when there's ripe to eat). Each event is pure state:
  `rain_t` (refills water), `ufo_active/ufo_t/ufo_target` (a 3×3 `_ufo_circle_at` crop-circle
  fired once at mid-flight — growing→golden-ripe, ripe→golden), `birds_active/birds_t`
  (`_birds_eat` removes up to 3 ripe, **repelled by a scarecrow charge**), `sell_boost_t`
  (trader x1.5 for 18s). A message contract (`event_msg` + `event_seq`) lets the view toast
  without the sim knowing about UI. Verified by `test_sim.gd` → **70/70 deterministic checks**
  (tests 27–32: rain refill, UFO ring + outside-untouched, birds eat-3, scarecrow block,
  timer fires, UFO mid-flight fire + end deactivate).
- **3D event visuals (`world.gd: _sync_events` + builders)** — a glowing green **flying saucer**
  with under-belly lights and an abduction beam that flies across and drops a golden crop-circle;
  **blue rain streaks** (GPUParticles, preprocessed) over the whole plot; a **dark bird flock**
  that swoops in and dips at the crops; a **striped trader cart** parked in front during the sell
  boost; and a **scarecrow** that stands in the field while charges remain. Each is created lazily
  and shown/hidden purely from sim state; new-event messages toast via the HUD.
- Verified `EVENT_TEST=1` (every event spawns/updates its node, toast syncs to `event_seq`,
  all hide when state clears — all PASS) and `EVENT_SHOW=<rain|ufo|birds|trader|scarecrow>`
  screenshots showing each spectacle on the field.

## Status: full 2D→3D parity reached ✓
Store + buildings (F2), bots (D), and events (H) are all live in 3D. The logic/view split
held across every phase — game logic ported near-verbatim into `sim.gd`; only presentation
and input were rewritten. See [`design/3d-migration-plan.md`](../../design/3d-migration-plan.md).

## Polish pass — audio, shadows, and the production shell ✓
With parity reached, this pass hardens the build toward "feels like a real game" (still a
prototype — see standards note below).
- **Crisper shadows** (`world.gd: _build_environment`) — the blocky directional shadows are
  fixed: `directional_shadow_max_distance` tightened to 38 m (the unset 100 m default was
  spreading the atlas thin), 2 PSSM splits + blend, a 4096 atlas, and `shadow_normal_bias` /
  `shadow_blur` tuned to kill acne without peter-panning. SSAO softened to match.
- **Audio buses + settings** (`settings.gd`, new) — a `Music` and an `SFX` bus are created at
  startup (before `music.gd`/`sfx.gd` are added, so they can route to them). The player's
  mute/volume choices persist to `user://settings.json`. `music.gd` and `sfx.gd` now route to
  those buses (Master fallback).
- **Save / Load** (`save.gd` + `SimState.to_dict/from_dict/new_game`) — the whole game
  (field, economy, upgrades, buildings, **bots** incl. their painted zones) serializes to
  `user://save.json`. Autosaves every 20 s, on pause, and on focus-out / close. Round-trip
  verified lossless (`_savetest` harness, since removed). Bots' 3D nodes auto-respawn from the
  loaded sim via the existing lazy `_sync_bots`.
- **Main menu / pause / settings** (`menu.gd`, new — a `CanvasLayer` shell) — `world.gd` now
  boots to a **main menu** (Yeni Oyun / Devam Et / Ayarlar) instead of straight into the demo.
  An in-game **pause button** raises a Resume / Ayarlar / Ana Menü overlay; `_process` and
  input freeze while paused. New Game starts a fresh farm (rocks to clear); Continue loads the
  save. The VERIFY_SHOT test harness still boots the rich demo directly.
- **Onboarding** (`tutorial.gd`, new) — first-ever new game shows a 5-step coach card carousel
  (çapala → ek+sula → hasat → temizle+büyüt → robot al), anchored low for one-thumb reach.
  A `user://tutorial_seen` marker shows it only once.

> All new files are loaded **by path** (`load("res://x.gd")`) with untyped vars and duck-typed
> calls — never by `class_name` — because new scripts aren't in the global class cache during
> console/headless runs that skip the editor import (the same gotcha that first broke
> `CozyMusic`). Test hooks: `MENU_SHOT=1` / `PLAY_SHOT=1` (windowed binary, no `--headless`)
> screenshot the menu / in-game shell.

> **Prototype standards apply** (`.claude/rules/prototype-code.md`): this is a
> production-*candidate* seed, not production code. If/when it graduates, the shell is rewritten
> to production standards (scene files, DI, tests) — it is not migrated verbatim.
