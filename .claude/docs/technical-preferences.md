# Technical Preferences

<!-- Populated by /setup-engine. Updated as the user makes decisions throughout development. -->
<!-- All agents reference this file for project-specific standards and conventions. -->

## Engine & Language

- **Engine**: Godot 4.3
- **Language**: GDScript
- **Rendering**: Mobile renderer (GL Compatibility fallback for older devices)
- **Physics**: Godot 2D physics (default) — light use; most logic is grid/tick based

## Input & Platform

<!-- Written by /setup-engine. Read by /ux-design, /ux-review, /test-setup, /team-ui, and /dev-story -->
<!-- to scope interaction specs, test helpers, and implementation to the correct input methods. -->

- **Target Platforms**: Mobile (Android / iOS)
- **Input Methods**: Touch
- **Primary Input**: Touch (single-finger / one-thumb)
- **Gamepad Support**: None
- **Touch Support**: Full
- **Platform Notes**: Portrait orientation. One-thumb reachable UI. No hover-only
  interactions. Tap is the only required gesture; drag optional. Design for small
  screens and variable DPI; respect safe areas / notches.

## Naming Conventions

- **Classes**: PascalCase (e.g., `SeedBot`)
- **Variables**: snake_case (e.g., `move_speed`)
- **Signals/Events**: snake_case past tense (e.g., `crop_harvested`)
- **Files**: snake_case matching class (e.g., `seed_bot.gd`)
- **Scenes/Prefabs**: PascalCase matching root node (e.g., `SeedBot.tscn`)
- **Constants**: UPPER_SNAKE_CASE (e.g., `MAX_BOTS`)

## Performance Budgets

- **Target Framerate**: 60 FPS
- **Frame Budget**: 16.6 ms
- **Draw Calls**: < 200 (mobile; batch sprites, use atlases)
- **Memory Ceiling**: < 512 MB (mid-range mobile target)

## Testing

- **Framework**: GUT (Godot Unit Test) — GDScript test runner
- **Minimum Coverage**: [TO BE CONFIGURED]
- **Required Tests**: Balance formulas (decay/yield rates), gameplay systems (bot work cycle), idle accrual math

## Forbidden Patterns

<!-- Add patterns that should never appear in this project's codebase -->
- [None configured yet — add as architectural decisions are made]

## Allowed Libraries / Addons

<!-- Add approved third-party dependencies here -->
- [None configured yet — add as dependencies are approved]

## Architecture Decisions Log

<!-- Quick reference linking to full ADRs in docs/architecture/ -->
- [No ADRs yet — use /architecture-decision to create one]

## Engine Specialists

<!-- Written by /setup-engine when engine is configured. -->
<!-- Read by /code-review, /architecture-decision, /architecture-review, and team skills -->
<!-- to know which specialist to spawn for engine-specific validation. -->

- **Primary**: godot-specialist
- **Language/Code Specialist**: godot-gdscript-specialist (all .gd files)
- **Shader Specialist**: godot-shader-specialist (.gdshader files, VisualShader resources)
- **UI Specialist**: godot-specialist (no dedicated UI specialist — primary covers all UI)
- **Additional Specialists**: godot-gdextension-specialist (GDExtension / native C++ bindings only)
- **Routing Notes**: Invoke primary for architecture decisions, ADR validation, and cross-cutting code review. Invoke GDScript specialist for code quality, signal architecture, static typing enforcement, and GDScript idioms. Invoke shader specialist for material design and shader code (key for "decent graphics" goal). Invoke GDExtension specialist only when native extensions are involved.

### File Extension Routing

<!-- Skills use this table to select the right specialist per file type. -->
<!-- If a row says [TO BE CONFIGURED], fall back to Primary for that file type. -->

| File Extension / Type | Specialist to Spawn |
|-----------------------|---------------------|
| Game code (.gd files) | godot-gdscript-specialist |
| Shader / material files (.gdshader, VisualShader) | godot-shader-specialist |
| UI / screen files (Control nodes, CanvasLayer) | godot-specialist |
| Scene / prefab / level files (.tscn, .tres) | godot-specialist |
| Native extension / plugin files (.gdextension, C++) | godot-gdextension-specialist |
| General architecture review | godot-specialist |
