# HarvestCo — 2D → Low-Poly 3D Migration Plan

> Status: ACTIVE. Decision made 2026-06-29 — art direction = **low-poly 3D** (over
> pixel art), validated by `prototypes/lowpoly-look-test/`. This doc is the roadmap
> for porting the 2D `_draw()` prototype (`prototypes/bot-orchestration-concept/`)
> into a low-poly 3D production build.

## Core principle: logic carries over, only presentation changes
The current `main.gd` fuses two concerns: **(A) game logic** (tile states, bot AI,
claim system, economy, events) and **(B) rendering** (`_draw()` 2D). Logic is pure
data/math and is render-independent — it ports almost verbatim. All the work is
rewriting **(B)**: `_draw` → 3D scene (models + lighting + camera) and touch → 3D
tile mapping.

So this is **keep the logic, replace the view** — not a from-scratch rewrite.

## Project structure (graduates from single-file prototype)
Split the monolith into layers:
- `sim.gd` — game state + rules (port of current logic, headless/testable, no visuals)
- `world.gd` (Node3D) — reads sim, renders it in 3D, owns input (touch→3D raycast)
- `hud.tscn` (CanvasLayer + real Control nodes) — UI, finally off `_draw()`

Why: tuning balance without touching the view; unit tests on formulas/AI (per
coding-standards); and it pays off the deferred "real Control nodes" UI debt.

## Phased migration (each phase = playable + screenshot-verifiable)

| # | Phase | Output | Risk |
|---|-------|--------|------|
| A | 3D scaffold | look-test world/camera/lighting + empty 5×N field grid (real MeshInstance3D tiles) | Low |
| B | Logic port | `sim.gd` = tile states + growth + economy; view colors tiles by state (no input yet) | Low-Med |
| C | Touch→3D tile | tap → camera ray → ground plane → tile index → **manual work** (till/plant/water/harvest). Manual core loop playable in 3D | **HIGH** (heart of the plan) |
| D | Bots | bot = 3D model moving toward targets; zone painting (drag→ray→tiles) | Med |
| E | Buildings | farmhouse/mill/well/depot as 3D models, tap-to-act | Med |
| F | HUD | `_draw` HUD → real Control nodes (Button/Label), safe-area/notch | Med |
| G | Crop stages + polish | Quaternius 5-stage crop models (mesh swap), shadow/AO tuning | Low |
| H | Event visuals + audio | rain (GPUParticles3D), UFO/birds/trader in 3D, juice + sound | Med-High |

Milestone after C: hand-farmed 3D field. After D: the automation core (bots) runs in 3D.

## Key technical decisions / risks
1. **Touch → 3D tile (riskiest, Phase C).** `camera.project_ray_origin/normal(pos)`
   → `Plane(Vector3.UP,0).intersects_ray()` → world pos → `floor((world-origin)/TILE)`.
   Same logic as the 2D hit-test, just with a screen→world step. Drag-to-paint zones
   uses the same ray.
2. **Mobile renderer ≠ Forward+.** The look-test's SSAO is **Forward+ only** — not on
   the mobile renderer. Compensate with soft shadows + the models' baked vertex shading
   (+ optional baked lightmaps). Still cozy, but mobile is a touch flatter than the
   desktop screenshot. Know this up front.
3. **Variable aspect ratio.** Portrait, but phones vary (19.5:9 vs 4:3). Fixed camera
   angle + frame the field to fit any ratio by distance (optional slight orbit/pan).
   Look-test is fixed 540×960; production must adapt.
4. **UI rewrite debt (Phase F).** Prototype drew UI via `_draw` (deliberately deferred).
   Production needs real Control nodes for touch hit-testing, scaling, safe areas.
5. **Asset sourcing.** Look-test has one crop + one building. Production needs:
   - Quaternius **Crops PACK** (5 growth stages, ~100 models) — maps to PLANTED→GROWING→RIPE
   - a real **robot/bot** model (currently a cube)
   - farm **animals**, extra **buildings** (mill/well/depot/barn), tree/rock variety
     (Kenney Nature Kit). All CC0/free, glTF → drag-drop into Godot 4.3.

## Recommended first step
**Phase A + B together**: real 5×N field grid (from the look-test base) + port current
`main.gd` logic into `sim.gd`, tiles colored by state. Cheaply proves the logic/view
split and lays the foundation; then tackle the risky Phase C (touch→3D) on solid ground.

## Asset sources (CC0 / free)
- Quaternius — https://quaternius.com / https://poly.pizza/u/Quaternius
- Kenney Nature Kit — https://kenney.nl/assets/nature-kit
