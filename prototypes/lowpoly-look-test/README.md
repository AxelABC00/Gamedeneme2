# Low-Poly 3D Look Test (throwaway)

## Hypothesis
*"If we render HarvestCo as low-poly 3D with cozy lighting (warm sun + soft shadows
+ SSAO), it will read as more 'realistic/quality' than pixel art and match the
HarvestCo reference — and free CC0 assets exist that make the art cheap."*

This validates the **art direction decision** (low-poly 3D vs pixel art) before
committing to the 2D→3D production rewrite. It is NOT the game — no gameplay, no
input, no logic. Just a static dressed scene to judge the look.

## What's real vs placeholder
- **Real CC0 assets** (Quaternius, via poly.pizza, public domain):
  - `assets/crops.glb` — crop/plant model (used for the growing rows)
  - `assets/small_farm.glb` — farmhouse building
- **Placeholder / procedural** (built in code, replaced later):
  - Soil tiles, raised bed, grass (Godot primitives)
  - Pine trees (cones + cylinder)
  - Bots (colored cubes with a glowing eye) — real robot art is a later step

## How to run
```
godot --path .            # opens the windowed scene
```
Screenshot mode (saves `_shot_lowpoly.png` then quits — needs a real GPU window,
not --headless; allow ~15-20s for Forward+ shader compile):
```
VERIFY_SHOT=1 godot --path .
```
`INSPECT=1 godot --headless --path .` dumps the glb node structure to stderr.

## Status
**Concluded.** Look approved direction = low-poly 3D.

## Findings
- Low-poly 3D + Godot Forward+ lighting (warm DirectionalLight3D, soft shadows,
  SSAO, gentle glow, ACES tonemap) gives a cozy, "more realistic" feel that beats
  pixel art for the stated goal.
- Free CC0 assets (Kenney Nature Kit, Quaternius Crops/Farm/Animals) drop straight
  into Godot 4.3 as glTF — **art is not the blocker**.
- The real work for the production phase is the engineering of the 3D scene:
  Node3D world, angled camera, lighting, and **touch → 3D tile raycasting** to port
  the existing 2D tap input. All game logic (tile states, bot AI, claim system,
  economy) is render-independent and carries over unchanged.

## Asset sources (CC0 / free)
- Quaternius — https://quaternius.com / https://poly.pizza/u/Quaternius
- Kenney Nature Kit — https://kenney.nl/assets/nature-kit
