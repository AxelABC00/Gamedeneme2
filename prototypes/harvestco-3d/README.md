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

## Next: Phase C (HIGH risk)
Touch→3D tile mapping: `camera.project_ray_origin/normal` → `Plane(UP,0).intersects_ray`
→ world→tile index → manual work (till/plant/water/harvest). See the migration plan.
