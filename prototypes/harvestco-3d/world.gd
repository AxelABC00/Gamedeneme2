# PROTOTYPE - 2D->3D migration, Phase A+B
# world.gd — reads SimState and renders it as a low-poly 3D field.
# No input yet (Phase C). Proves the logic(sim)/view(this) split + live growth.
# Date: 2026-06-29
extends Node3D

const TILE := 1.0

var sim: SimState
var _cam: Camera3D
var _crop_nodes: Array = []          # per-tile crop Node3D (or null)
var _soil_nodes: Array = []          # per-tile soil MeshInstance3D
var _rock_nodes: Array = []          # per-tile obstacle rock (or null)
var _last_state: PackedInt32Array
var _last_bucket: PackedInt32Array   # growth bucket, to know when to rebuild
var _hud: Hud
var _store: Store
var _buildings: Array = []           # [{node, kind, aabb}] homestead buildings (tappable)
var _bot_nodes: Array = []           # parallel to sim.bots: {root, task, phase, prev}
var _zone_markers: Array = []        # glowing tiles showing the selected bot's zone
var _tool: int = -1                  # active tool: -1 = hand (manual farm), >=0 = bot index
var _erase: bool = false             # zone paint vs erase
# event visuals (Phase H) — created lazily, shown/hidden by _sync_events from sim state
var _rain: GPUParticles3D
var _ufo: Node3D
var _birds: Node3D
var _trader: Node3D
var _scarecrow: Node3D
var _last_event_seq: int = 0         # toast fires when sim bumps event_seq
const PICK_Y := 0.10                 # soil surface height for tap raycast
const BOT_SCALE := 1.45              # robots read clearly at the pulled-back camera
const B_FARM := "farm"
const B_WELL := "well"
const B_DEPOT := "depot"
const B_MILL := "mill"

func _ready() -> void:
	sim = SimState.new()
	sim.setup_demo()

	_build_environment()
	_build_ground()
	_build_soil_tiles()
	_build_props()

	var n: int = sim.states.size()
	_crop_nodes.resize(n)
	_last_state = PackedInt32Array(); _last_state.resize(n)
	_last_bucket = PackedInt32Array(); _last_bucket.resize(n)
	for i in range(n):
		_crop_nodes[i] = null
		_last_state[i] = -1
		_last_bucket[i] = -1
		_refresh_crop(i)

	_build_hud()

	if OS.has_environment("VERIFY_SHOT"):
		_shoot()

# ---------------------------------------------------------------- HUD (Phase F)
func _build_hud() -> void:
	_hud = Hud.new()
	add_child(_hud)
	_hud.build(sim)
	_hud.sell_pressed.connect(_on_sell)
	_hud.buy_water_pressed.connect(_on_buy_water)
	_hud.seed_selected.connect(_on_seed_selected)
	_hud.store_pressed.connect(_on_open_store)
	_hud.tool_selected.connect(_on_tool_selected)
	_hud.erase_toggled.connect(_on_erase_toggled)

	_store = Store.new()
	add_child(_store)
	_store.build(sim)
	_store.buy_requested.connect(_on_store_buy)

	_hud.refresh_tools(sim, _tool, _erase)

func _on_open_store() -> void:
	_store.open_store(sim, 0)

# Player bought something in the store. Run the sim, react to the result.
func _on_store_buy(id: int) -> void:
	var res: Dictionary = sim.buy_item(id)
	if not res["bought"]:
		_hud.toast("Para yetmiyor")
		return
	# expanding the field adds a row of tiles — rebuild the plot so it shows up
	if res["row"] >= 0:
		_rebuild_field()
	_hud.refresh(sim)
	_store.refresh(sim)
	if res["close"]:
		# a bot was bought — close, auto-select it, and let the player paint its zone
		_store.close_store()
		_tool = sim.bots.size() - 1
		_erase = false
		_hud.refresh_tools(sim, _tool, _erase)
		_update_zone_view()
		_hud.toast("Bot geldi - bolge boya")
	else:
		# upgrades/buildings can change bot count visuals (e.g. repair) — keep tools fresh
		_hud.refresh_tools(sim, _tool, _erase)

# Rebuild the entire soil/crop plot after the field grows (buy_expand).
func _rebuild_field() -> void:
	for n in _soil_nodes:
		if n != null:
			n.queue_free()
	for n in _rock_nodes:
		if n != null:
			n.queue_free()
	for n in _crop_nodes:
		if n != null:
			n.queue_free()
	_soil_nodes.clear()
	_rock_nodes.clear()
	_crop_nodes.clear()
	_build_soil_tiles()
	var n2: int = sim.states.size()
	_crop_nodes.resize(n2)
	_last_state = PackedInt32Array(); _last_state.resize(n2)
	_last_bucket = PackedInt32Array(); _last_bucket.resize(n2)
	for i in range(n2):
		_crop_nodes[i] = null
		_last_state[i] = -1
		_last_bucket[i] = -1
		_refresh_crop(i)

func _on_sell() -> void:
	var earned: int = sim.sell_all()
	_hud.refresh(sim)
	_hud.toast("Sattin: +%d" % earned if earned > 0 else "Depo bos")

func _on_buy_water() -> void:
	if sim.buy_water():
		_hud.refresh(sim)
		_hud.toast("Su +%d" % sim.WATER_BUNDLE)
	else:
		_hud.toast("Para yetmiyor")

func _on_seed_selected(idx: int) -> void:
	sim.selected_seed = idx
	_hud.refresh(sim)

# Player picked a tool: -1 = hand (manual farm), >=0 = paint that bot's zone.
func _on_tool_selected(idx: int) -> void:
	_tool = idx
	_hud.refresh_tools(sim, _tool, _erase)
	_update_zone_view()

func _on_erase_toggled(on: bool) -> void:
	_erase = on

func _process(delta: float) -> void:
	sim.tick(delta)
	# Rebuild a tile's plant when its state or growth bucket changes (6 visible steps).
	for i in range(sim.states.size()):
		var s: int = sim.states[i]
		var bucket: int = int(sim.grow[i] * 6.0)
		if s != _last_state[i] or bucket != _last_bucket[i]:
			_refresh_crop(i)
	_sync_bots(delta)
	_sync_events(delta)

# ---------------------------------------------------------------- input (Phase C)
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch and event.pressed:
		_tap(event.position)
	elif event is InputEventScreenDrag:
		_paint_at(event.position)        # finger drag paints a zone
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_tap(event.position)
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) != 0:
		_paint_at(event.position)        # mouse drag paints a zone (editor testing)

func _tap(screen_pos: Vector2) -> void:
	if _store != null and _store.is_open():
		return
	# buildings sit above the soil plane — check them first
	var kind := _building_under(screen_pos)
	if kind != "":
		_on_building_tapped(kind)
		return
	# a bot tool is active -> a tap paints a single zone tile
	if _tool >= 0:
		_paint_at(screen_pos)
		return
	var idx := _tile_under(screen_pos)
	if idx < 0:
		return
	var ok: bool = sim.manual(idx)
	_refresh_tile(idx)
	_feedback(idx, ok)
	if _hud != null:
		_hud.refresh(sim)

# Paint (or erase) the active bot's work zone at the tapped tile.
func _paint_at(screen_pos: Vector2) -> void:
	if _store != null and _store.is_open():
		return
	if _tool < 0 or _tool >= sim.bots.size():
		return
	var idx := _tile_under(screen_pos)
	if idx < 0:
		return
	var bot = sim.bots[_tool]
	if _erase:
		bot.zone.erase(idx)
	else:
		if bot.zone.has(idx):
			return
		bot.zone[idx] = true
	_update_zone_view()

# Show the selected bot's zone as glowing tinted tiles (its task colour).
func _update_zone_view() -> void:
	for m in _zone_markers:
		if m != null:
			m.queue_free()
	_zone_markers.clear()
	if _tool < 0 or _tool >= sim.bots.size():
		return
	var bot = sim.bots[_tool]
	var col: Color = sim.TASK_COL[bot.task]
	for key in bot.zone:
		var i: int = key
		if i >= sim.states.size():
			continue
		var cr := _tile_cr(i)
		var mk := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(TILE * 0.94, 0.02, TILE * 0.94)
		mk.mesh = bm
		var mat := _mat(col, 0.4, 0.0)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color.a = 0.5
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = 0.6
		mk.material_override = mat
		mk.position = _tile_pos(cr.x, cr.y) + Vector3(0, 0.22, 0)
		add_child(mk)
		_zone_markers.append(mk)

# Physics raycast against homestead building bodies. Returns the kind or "".
func _building_under(screen_pos: Vector2) -> String:
	if _cam == null:
		return ""
	var from: Vector3 = _cam.project_ray_origin(screen_pos)
	var to: Vector3 = from + _cam.project_ray_normal(screen_pos) * 100.0
	var space := get_world_3d().direct_space_state
	var q := PhysicsRayQueryParameters3D.create(from, to)
	var hit := space.intersect_ray(q)
	if hit.is_empty():
		return ""
	for b in _buildings:
		if b["body"] == hit.get("collider"):
			return b["kind"]
	return ""

func _on_building_tapped(kind: String) -> void:
	match kind:
		B_WELL:
			_on_buy_water()
		B_DEPOT:
			_on_sell()
		B_FARM:
			_store.open_store(sim, 0)
		B_MILL:
			_store.open_store(sim, 2)

# Screen -> camera ray -> soil plane -> tile index (-1 if off the plot). The heart of Phase C.
func _tile_under(screen_pos: Vector2) -> int:
	if _cam == null:
		return -1
	var from: Vector3 = _cam.project_ray_origin(screen_pos)
	var dir: Vector3 = _cam.project_ray_normal(screen_pos)
	var plane := Plane(Vector3.UP, PICK_Y)
	var hit = plane.intersects_ray(from, dir)
	if hit == null:
		return -1
	var world: Vector3 = hit
	var o := _origin()
	var c := int(round((world.x - o.x) / TILE))
	var r := int(round((world.z - o.z) / TILE))
	if c < 0 or c >= SimState.COLS or r < 0 or r >= sim.rows:
		return -1
	return r * SimState.COLS + c

# Rebuild every visual for one tile after its state changed (soil tint, rock, plant).
func _refresh_tile(idx: int) -> void:
	var soil: MeshInstance3D = _soil_nodes[idx]
	if soil != null:
		soil.material_override = _mat(_soil_color(sim.states[idx]), 1.0)
	var rock: Node3D = _rock_nodes[idx]
	if sim.states[idx] == SimState.OBSTACLE and rock == null:
		var cr := _tile_cr(idx)
		_add_rock(idx, _tile_pos(cr.x, cr.y), 0.10)
	elif sim.states[idx] != SimState.OBSTACLE and rock != null:
		rock.queue_free()
		_rock_nodes[idx] = null
	_refresh_crop(idx)

# Quick green (ok) / red (blocked) pop so taps read clearly while testing.
func _feedback(idx: int, ok: bool) -> void:
	var cr := _tile_cr(idx)
	var marker := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.18
	sm.height = 0.36
	marker.mesh = sm
	var col := Color(0.45, 0.95, 0.45) if ok else Color(0.95, 0.35, 0.30)
	var m := _mat(col, 0.3, 0.0)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 2.0
	marker.material_override = m
	add_child(marker)
	marker.position = _tile_pos(cr.x, cr.y) + Vector3(0, 0.5, 0)
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(marker, "scale", Vector3(2.2, 2.2, 2.2), 0.35)
	tw.tween_property(marker, "position:y", 1.1, 0.35)
	var m2 := m  # fade alpha
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	tw.tween_property(m2, "albedo_color:a", 0.0, 0.35)
	tw.chain().tween_callback(marker.queue_free)

# ---------------------------------------------------------------- layout
func _origin() -> Vector3:
	return Vector3(-(SimState.COLS - 1) * TILE * 0.5, 0.0, -(sim.rows - 1) * TILE * 0.5)

func _tile_pos(c: int, r: int) -> Vector3:
	return _origin() + Vector3(c * TILE, 0.0, r * TILE)

func _tile_cr(i: int) -> Vector2i:
	return Vector2i(i % SimState.COLS, i / SimState.COLS)

# Grid-space (col,row floats) -> 3D world position. Bots live in grid space (sim).
func _grid_to_world(g: Vector2) -> Vector3:
	return _origin() + Vector3(g.x * TILE, 0.0, g.y * TILE)

# ---------------------------------------------------------------- bots (Phase D)
# Spawn a view node for any new sim bot, then drive every bot's transform from its
# grid position each frame (the sim already moves gpos; we just render + animate).
func _sync_bots(delta: float) -> void:
	while _bot_nodes.size() < sim.bots.size():
		var i: int = _bot_nodes.size()
		var bot = sim.bots[i]
		var node := _make_bot(bot.task)
		add_child(node)
		node.position = _grid_to_world(bot.gpos)
		_bot_nodes.append({"root": node, "task": bot.task, "phase": 0.0})

	for i in range(sim.bots.size()):
		var bot = sim.bots[i]
		var nd: Dictionary = _bot_nodes[i]
		var root: Node3D = nd["root"]
		var ground := _grid_to_world(bot.gpos)
		var prev := root.position
		# face travel direction
		var move := Vector2(ground.x - prev.x, ground.z - prev.z)
		if move.length() > 0.0008:
			var ang := atan2(move.x, move.y)
			root.rotation.y = lerp_angle(root.rotation.y, ang, min(1.0, delta * 9.0))
		# a little working bob; rolls to a stop when moving
		var y := 0.0
		if bot.state == "working":
			nd["phase"] = float(nd["phase"]) + delta * 11.0
			y = absf(sin(float(nd["phase"]))) * 0.09
		else:
			nd["phase"] = 0.0
		root.position = Vector3(ground.x, y, ground.z)
		# shrink a touch when worn out (condition low), else full size
		if bot.condition < 0.35:
			root.scale = Vector3.ONE * BOT_SCALE * (0.9 + bot.condition * 0.1)
		else:
			root.scale = Vector3.ONE * BOT_SCALE

# A cute low-poly farm robot. Task colour shows on the belly panel, eyes, and antenna
# bulb so each specialist reads at a glance (matches the store swatches).
func _make_bot(task: int) -> Node3D:
	var accent: Color = sim.TASK_COL[task]
	var root := Node3D.new()

	# dark tracked base + four wheels
	var base := MeshInstance3D.new()
	var basem := BoxMesh.new()
	basem.size = Vector3(0.42, 0.12, 0.50)
	base.mesh = basem
	base.material_override = _mat(Color(0.17, 0.17, 0.20), 0.6, 0.15)
	base.position = Vector3(0, 0.11, 0)
	root.add_child(base)
	for sx in [-0.24, 0.24]:
		for sz in [-0.17, 0.17]:
			var wheel := MeshInstance3D.new()
			var wm := CylinderMesh.new()
			wm.top_radius = 0.10; wm.bottom_radius = 0.10; wm.height = 0.07; wm.radial_segments = 10
			wheel.mesh = wm
			wheel.material_override = _mat(Color(0.09, 0.09, 0.10), 0.5, 0.2)
			wheel.rotation_degrees = Vector3(0, 0, 90)
			wheel.position = Vector3(sx, 0.10, sz)
			root.add_child(wheel)

	# cream chassis
	var body := MeshInstance3D.new()
	var bodym := BoxMesh.new()
	bodym.size = Vector3(0.40, 0.34, 0.40)
	body.mesh = bodym
	body.material_override = _mat(Color(0.93, 0.91, 0.87), 0.5, 0.05)
	body.position = Vector3(0, 0.35, 0)
	root.add_child(body)

	# task-colour belly panel (glows softly)
	var panel := MeshInstance3D.new()
	var pm := BoxMesh.new()
	pm.size = Vector3(0.30, 0.16, 0.02)
	panel.mesh = pm
	var pmat := _mat(accent, 0.4, 0.1)
	pmat.emission_enabled = true; pmat.emission = accent; pmat.emission_energy_multiplier = 0.45
	panel.material_override = pmat
	panel.position = Vector3(0, 0.33, 0.205)
	root.add_child(panel)

	# head + dark visor + two glowing eyes
	var head := MeshInstance3D.new()
	var hm := BoxMesh.new()
	hm.size = Vector3(0.30, 0.22, 0.28)
	head.mesh = hm
	head.material_override = _mat(Color(0.97, 0.96, 0.93), 0.45, 0.05)
	head.position = Vector3(0, 0.63, 0)
	root.add_child(head)
	var visor := MeshInstance3D.new()
	var vm := BoxMesh.new()
	vm.size = Vector3(0.26, 0.10, 0.03)
	visor.mesh = vm
	visor.material_override = _mat(Color(0.10, 0.12, 0.16), 0.15, 0.4)
	visor.position = Vector3(0, 0.64, 0.14)
	root.add_child(visor)
	for ex in [-0.06, 0.06]:
		var eye := MeshInstance3D.new()
		var em := SphereMesh.new()
		em.radius = 0.028; em.height = 0.056; em.radial_segments = 8; em.rings = 6
		eye.mesh = em
		var emat := _mat(accent, 0.2, 0.0)
		emat.emission_enabled = true; emat.emission = accent.lightened(0.3); emat.emission_energy_multiplier = 2.6
		eye.material_override = emat
		eye.position = Vector3(ex, 0.645, 0.16)
		root.add_child(eye)

	# antenna + task-colour bulb
	var ant := MeshInstance3D.new()
	var am := CylinderMesh.new()
	am.top_radius = 0.012; am.bottom_radius = 0.016; am.height = 0.16; am.radial_segments = 6
	ant.mesh = am
	ant.material_override = _mat(Color(0.30, 0.30, 0.32), 0.5, 0.3)
	ant.position = Vector3(0.0, 0.82, 0.0)
	root.add_child(ant)
	var bulb := MeshInstance3D.new()
	var blm := SphereMesh.new()
	blm.radius = 0.04; blm.height = 0.08; blm.radial_segments = 8; blm.rings = 6
	bulb.mesh = blm
	var blmat := _mat(accent, 0.2, 0.0)
	blmat.emission_enabled = true; blmat.emission = accent; blmat.emission_energy_multiplier = 2.0
	bulb.material_override = blmat
	bulb.position = Vector3(0, 0.92, 0)
	root.add_child(bulb)

	# two little side arms
	for sx in [-0.245, 0.245]:
		var arm := MeshInstance3D.new()
		var arm_m := BoxMesh.new()
		arm_m.size = Vector3(0.06, 0.20, 0.08)
		arm.mesh = arm_m
		arm.material_override = _mat(Color(0.85, 0.83, 0.80), 0.5, 0.05)
		arm.position = Vector3(sx, 0.37, 0.05)
		root.add_child(arm)

	root.scale = Vector3.ONE * BOT_SCALE
	return root

# ---------------------------------------------------------------- events (Phase H)
# The field is centred on the world origin (_origin() is symmetric), so the field
# centre is ~Vector3.ZERO; half-extents come straight from the grid dimensions.
func _field_half() -> Vector2:
	return Vector2((SimState.COLS - 1) * TILE * 0.5, (sim.rows - 1) * TILE * 0.5)

# Reads sim event state each frame and drives every event visual. Pure view: it never
# changes the sim — sim.tick already advanced the events; we just show what's happening.
func _sync_events(delta: float) -> void:
	if sim.event_seq != _last_event_seq:
		_last_event_seq = sim.event_seq
		if _hud:
			_hud.toast(sim.event_msg)
	_sync_rain()
	_sync_ufo(delta)
	_sync_birds()
	_sync_trader()
	_sync_scarecrow()

func _sync_rain() -> void:
	var on: bool = sim.rain_t > 0.0
	if on and _rain == null:
		_rain = _make_rain()
		add_child(_rain)
	if _rain:
		_rain.emitting = on
		_rain.visible = on

func _sync_ufo(delta: float) -> void:
	if not sim.ufo_active:
		if _ufo:
			_ufo.visible = false
		return
	if _ufo == null:
		_ufo = _make_ufo()
		add_child(_ufo)
	_ufo.visible = true
	var f: float = clamp(sim.ufo_t / SimState.UFO_DUR, 0.0, 1.0)
	var half := _field_half()
	var x: float = lerp(-half.x - 3.0, half.x + 3.0, f)
	# hover over the target tile's z while it works the crop-circle, otherwise mid-field
	var tz := 0.0
	if sim.ufo_target >= 0:
		tz = _tile_pos(sim.ufo_target % SimState.COLS, sim.ufo_target / SimState.COLS).z
	_ufo.position = Vector3(x, 4.6, tz)
	_ufo.rotate_y(delta * 2.5)

func _sync_birds() -> void:
	if not sim.birds_active:
		if _birds:
			_birds.visible = false
		return
	if _birds == null:
		_birds = _make_birds()
		add_child(_birds)
	_birds.visible = true
	var f: float = clamp(sim.birds_t / SimState.BIRDS_DUR, 0.0, 1.0)
	var half := _field_half()
	var x: float = lerp(-half.x - 4.0, half.x + 4.0, f)
	var y: float = 4.2 - sin(f * PI) * 2.3   # dip toward the crops at mid-flight, stay readable
	_birds.position = Vector3(x, y, 0.0)

func _sync_trader() -> void:
	var on: bool = sim.sell_boost_t > 0.0
	if not on:
		if _trader:
			_trader.visible = false
		return
	if _trader == null:
		_trader = _make_trader()
		var half := _field_half()
		# park it in front of the plot (toward the camera) so it's clearly in frame
		_trader.position = Vector3(-1.6, 0.0, half.y + 2.0)
		add_child(_trader)
	_trader.visible = true

func _sync_scarecrow() -> void:
	var on: bool = sim.scarecrow_charges > 0
	if not on:
		if _scarecrow:
			_scarecrow.visible = false
		return
	if _scarecrow == null:
		_scarecrow = _make_scarecrow()
		# stand it on a front-corner tile so it's close to the camera and clearly readable
		_scarecrow.position = _tile_pos(0, sim.rows - 1)
		add_child(_scarecrow)
	_scarecrow.visible = true

# slanted blue raindrop streaks falling over the whole field (preprocess so a single
# headless frame already shows rain).
func _make_rain() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.position = Vector3(0.0, 5.0, 0.0)
	p.amount = 240
	p.lifetime = 1.1
	p.preprocess = 1.0
	var half := _field_half()
	var mat := ParticleProcessMaterial.new()
	mat.direction = Vector3(0.1, -1.0, 0.0)
	mat.spread = 2.0
	mat.gravity = Vector3(0.0, -26.0, 0.0)
	mat.initial_velocity_min = 6.0
	mat.initial_velocity_max = 9.0
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(half.x + 1.5, 0.2, half.y + 1.5)
	p.process_material = mat
	var drop := BoxMesh.new()
	drop.size = Vector3(0.035, 0.42, 0.035)
	var dmat := _mat(Color(0.62, 0.80, 1.0, 0.65))
	dmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	drop.material = dmat
	p.draw_pass_1 = drop
	return p

func _make_ufo() -> Node3D:
	var root := Node3D.new()
	var disc := MeshInstance3D.new()
	var dm := CylinderMesh.new()
	dm.top_radius = 0.45; dm.bottom_radius = 1.15; dm.height = 0.3
	disc.mesh = dm
	disc.material_override = _mat(Color(0.55, 0.58, 0.66), 0.25, 0.85)
	root.add_child(disc)
	var dome := MeshInstance3D.new()
	var sm := SphereMesh.new(); sm.radius = 0.5; sm.height = 0.7
	dome.mesh = sm; dome.position.y = 0.22
	var glass := _mat(Color(0.45, 0.95, 0.6, 0.7))
	glass.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glass.emission_enabled = true
	glass.emission = Color(0.35, 1.0, 0.5)
	glass.emission_energy_multiplier = 1.6
	dome.material_override = glass
	root.add_child(dome)
	# glowing under-belly lights
	for a in range(6):
		var ang: float = TAU * float(a) / 6.0
		var light := MeshInstance3D.new()
		var ls := SphereMesh.new(); ls.radius = 0.1; ls.height = 0.2
		light.mesh = ls
		light.position = Vector3(cos(ang) * 0.9, -0.12, sin(ang) * 0.9)
		var lm := _mat(Color(1.0, 0.9, 0.3))
		lm.emission_enabled = true; lm.emission = Color(1.0, 0.85, 0.2); lm.emission_energy_multiplier = 2.0
		light.material_override = lm
		root.add_child(light)
	# abduction beam
	var beam := MeshInstance3D.new()
	var cone := CylinderMesh.new(); cone.top_radius = 0.25; cone.bottom_radius = 1.5; cone.height = 4.2
	beam.mesh = cone; beam.position.y = -2.3
	var bm := _mat(Color(0.4, 1.0, 0.5, 0.22))
	bm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bm.emission_enabled = true; bm.emission = Color(0.4, 1.0, 0.5); bm.emission_energy_multiplier = 1.0
	beam.material_override = bm
	root.add_child(beam)
	return root

func _make_birds() -> Node3D:
	var root := Node3D.new()
	var dark := _mat(Color(0.13, 0.13, 0.16), 0.8, 0.0)
	for k in range(SimState.BIRD_COUNT):
		var b := Node3D.new()
		b.position = Vector3(randf_range(-1.8, 1.8), randf_range(-0.6, 0.6), randf_range(-1.8, 1.8))
		for s in [-1.0, 1.0]:
			var w := MeshInstance3D.new()
			var wm := BoxMesh.new(); wm.size = Vector3(0.55, 0.07, 0.2)
			w.mesh = wm
			w.material_override = dark
			w.position = Vector3(s * 0.2, 0.0, 0.0)
			w.rotation.z = -s * 0.5
			b.add_child(w)
		root.add_child(b)
	return root

func _make_trader() -> Node3D:
	var root := Node3D.new()
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = Vector3(1.1, 0.6, 0.8)
	body.mesh = bm; body.position.y = 0.55
	body.material_override = _mat(Color(0.55, 0.35, 0.18), 0.7)
	root.add_child(body)
	# striped canopy
	var top := MeshInstance3D.new()
	var tm := BoxMesh.new(); tm.size = Vector3(1.25, 0.16, 0.95)
	top.mesh = tm; top.position.y = 0.95
	top.material_override = _mat(Color(0.85, 0.25, 0.25), 0.6)
	root.add_child(top)
	# goods crate (glowing accent so the boost reads at a glance)
	var crate := MeshInstance3D.new()
	var cm := BoxMesh.new(); cm.size = Vector3(0.3, 0.3, 0.3)
	crate.mesh = cm; crate.position = Vector3(0.0, 0.95 + 0.23, 0.0)
	var gold := _mat(Color(1.0, 0.84, 0.3))
	gold.emission_enabled = true; gold.emission = Color(1.0, 0.8, 0.25); gold.emission_energy_multiplier = 1.2
	crate.material_override = gold
	root.add_child(crate)
	for wz in [-0.32, 0.32]:
		for wx in [-0.45, 0.45]:
			var wheel := MeshInstance3D.new()
			var whm := CylinderMesh.new(); whm.top_radius = 0.22; whm.bottom_radius = 0.22; whm.height = 0.1
			wheel.mesh = whm
			wheel.rotation.z = PI * 0.5
			wheel.position = Vector3(wx, 0.22, wz)
			wheel.material_override = _mat(Color(0.15, 0.12, 0.1))
			root.add_child(wheel)
	return root

func _make_scarecrow() -> Node3D:
	var root := Node3D.new()
	var post := MeshInstance3D.new()
	var pm := BoxMesh.new(); pm.size = Vector3(0.1, 1.3, 0.1)
	post.mesh = pm; post.position.y = 0.65
	post.material_override = _mat(Color(0.45, 0.3, 0.16), 0.9)
	root.add_child(post)
	var arms := MeshInstance3D.new()
	var am := BoxMesh.new(); am.size = Vector3(1.0, 0.1, 0.1)
	arms.mesh = am; arms.position.y = 0.95
	arms.material_override = _mat(Color(0.45, 0.3, 0.16), 0.9)
	root.add_child(arms)
	var head := MeshInstance3D.new()
	var hm := SphereMesh.new(); hm.radius = 0.18; hm.height = 0.36
	head.mesh = hm; head.position.y = 1.4
	head.material_override = _mat(Color(0.85, 0.72, 0.4), 0.85)
	root.add_child(head)
	var hat := MeshInstance3D.new()
	var hatm := CylinderMesh.new(); hatm.top_radius = 0.12; hatm.bottom_radius = 0.32; hatm.height = 0.18
	hat.mesh = hatm; hat.position.y = 1.56
	hat.material_override = _mat(Color(0.5, 0.32, 0.15), 0.9)
	root.add_child(hat)
	return root

# ---------------------------------------------------------------- build
func _build_soil_tiles() -> void:
	var n: int = sim.states.size()
	_soil_nodes.resize(n)
	_rock_nodes.resize(n)
	# Raised soil bed under the plot.
	var bed := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(SimState.COLS * TILE + 0.4, 0.18, sim.rows * TILE + 0.4)
	bed.mesh = bm
	bed.material_override = _mat(Color(0.30, 0.21, 0.14), 1.0)
	bed.position = Vector3(0, -0.04, 0)
	add_child(bed)

	for i in range(n):
		var cr := _tile_cr(i)
		var p := _tile_pos(cr.x, cr.y)
		var soil := MeshInstance3D.new()
		var sm := BoxMesh.new()
		var h := 0.10
		sm.size = Vector3(TILE * 0.92, h, TILE * 0.92)
		soil.mesh = sm
		soil.material_override = _mat(_soil_color(sim.states[i]), 1.0)
		soil.position = p + Vector3(0, h * 0.5, 0)
		add_child(soil)
		_soil_nodes[i] = soil
		_rock_nodes[i] = null
		if sim.states[i] == SimState.OBSTACLE:
			_add_rock(i, p, h)

func _add_rock(i: int, p: Vector3, h: float) -> void:
	var rock := MeshInstance3D.new()
	var rmesh := SphereMesh.new()
	rmesh.radius = 0.26
	rmesh.height = 0.42
	rmesh.radial_segments = 6
	rmesh.rings = 3
	rock.mesh = rmesh
	rock.material_override = _mat(Color(0.55, 0.55, 0.52), 0.95)
	rock.position = p + Vector3(0.0, h + 0.12, 0.0)
	add_child(rock)
	_rock_nodes[i] = rock

# Build a simple procedural plant so each lifecycle stage reads clearly in 3D.
# (Real per-stage Quaternius crop models come in Phase G — this proves the mapping.)
func _refresh_crop(i: int) -> void:
	_last_state[i] = sim.states[i]
	_last_bucket[i] = int(sim.grow[i] * 6.0)
	var existing: Node3D = _crop_nodes[i]
	if existing != null:
		existing.queue_free()
		_crop_nodes[i] = null
	var s: int = sim.states[i]
	if s != SimState.PLANTED and s != SimState.GROWING and s != SimState.RIPE:
		return
	var cr := _tile_cr(i)
	var holder := Node3D.new()
	add_child(holder)
	holder.position = _tile_pos(cr.x, cr.y) + Vector3(0, 0.10, 0)
	_crop_nodes[i] = holder

	var grow_f: float = sim.grow[i] if s == SimState.GROWING else (1.0 if s == SimState.RIPE else 0.0)
	var stem_h: float
	match s:
		SimState.PLANTED:
			stem_h = 0.10
		SimState.GROWING:
			stem_h = 0.14 + grow_f * 0.42
		_:
			stem_h = 0.58

	# stem
	var stem := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.03
	cm.bottom_radius = 0.05
	cm.height = stem_h
	cm.radial_segments = 5
	stem.mesh = cm
	stem.material_override = _mat(Color(0.32, 0.54, 0.25), 0.9)
	stem.position = Vector3(0, stem_h * 0.5, 0)
	holder.add_child(stem)

	# foliage
	var leaf := MeshInstance3D.new()
	var lr: float = 0.07 + stem_h * 0.20
	var sm := SphereMesh.new()
	sm.radius = lr
	sm.height = lr * 2.0
	sm.radial_segments = 6
	sm.rings = 4
	leaf.mesh = sm
	leaf.material_override = _mat(Color(0.27, 0.50, 0.23), 0.9)
	leaf.position = Vector3(0, stem_h + lr * 0.3, 0)
	holder.add_child(leaf)

	# ripe fruit — crop's signature color, gold + glow if golden
	if s == SimState.RIPE:
		var crop_col: Color = sim.CROPS[sim.crop_type[i]]["col"]
		var is_gold: bool = bool(sim.golden[i])
		var fruit := MeshInstance3D.new()
		var fr: float = 0.16 if is_gold else 0.14
		var fm := SphereMesh.new()
		fm.radius = fr
		fm.height = fr * 2.0
		fruit.mesh = fm
		var fmat := _mat(Color(0.97, 0.78, 0.18) if is_gold else crop_col, 0.45, 0.0)
		if is_gold:
			fmat.emission_enabled = true
			fmat.emission = Color(1.0, 0.84, 0.22)
			fmat.emission_energy_multiplier = 2.2
		fruit.material_override = fmat
		# sit the fruit as a crown above the foliage so its colour reads
		fruit.position = Vector3(0, stem_h + lr * 1.4 + fr * 0.5, 0)
		holder.add_child(fruit)

# Homestead band behind the field: farmhouse | windmill | well | depot (left->right),
# each tappable (well=Su Al, depot=Sat, farmhouse/mill=Magaza). Mirrors the 2D layout.
func _build_props() -> void:
	var back_z := _origin().z - 2.1

	var farm: PackedScene = load("res://assets/small_farm.glb")
	var inst: Node3D = farm.instantiate()
	add_child(inst)
	_scale_to(inst, 2.3, Vector3(-3.0, 0.0, back_z - 0.2))
	_register_building(inst, B_FARM, Vector3(-3.0, 0.9, back_z - 0.2), Vector3(2.3, 2.0, 2.3))

	_build_windmill(Vector3(-0.7, 0.0, back_z))
	_build_well(Vector3(1.3, 0.0, back_z))
	_build_depot(Vector3(3.1, 0.0, back_z))

	for t in [Vector3(4.6, 0, back_z + 0.6),
			Vector3(-4.8, 0, back_z + 0.4)]:
		_tree(t)

# Procedural windmill (= Degirmen): stone tower + spinning-look blades.
func _build_windmill(at: Vector3) -> void:
	var root := Node3D.new()
	add_child(root)
	root.position = at
	var tower := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.34
	tm.bottom_radius = 0.5
	tm.height = 1.5
	tm.radial_segments = 10
	tower.mesh = tm
	tower.material_override = _mat(Color(0.74, 0.70, 0.62), 0.95)
	tower.position = Vector3(0, 0.75, 0)
	root.add_child(tower)
	var roof := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 0.0
	rm.bottom_radius = 0.46
	rm.height = 0.45
	rm.radial_segments = 10
	roof.mesh = rm
	roof.material_override = _mat(Color(0.55, 0.30, 0.22), 0.9)
	roof.position = Vector3(0, 1.7, 0)
	root.add_child(roof)
	# blades (a + cross of flat boxes on the front face)
	var hub := Node3D.new()
	hub.position = Vector3(0, 1.3, 0.5)
	root.add_child(hub)
	for a in range(4):
		var blade := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.10, 0.7, 0.04)
		blade.mesh = bm
		blade.material_override = _mat(Color(0.90, 0.86, 0.74), 0.9)
		blade.position = Vector3(0, 0.0, 0)
		blade.rotation_degrees = Vector3(0, 0, a * 45.0 + 22.5)
		blade.position = Vector3(sin(deg_to_rad(a * 90.0)) * 0.4, cos(deg_to_rad(a * 90.0)) * 0.4, 0)
		blade.rotation_degrees = Vector3(0, 0, a * 90.0)
		hub.add_child(blade)
	_register_building(root, B_MILL, at + Vector3(0, 0.9, 0), Vector3(1.1, 2.0, 1.1))

# Procedural well (= Su Kuyusu): stone ring + water + roof on posts.
func _build_well(at: Vector3) -> void:
	var root := Node3D.new()
	add_child(root)
	root.position = at
	var ring := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.42
	cm.bottom_radius = 0.42
	cm.height = 0.5
	cm.radial_segments = 12
	ring.mesh = cm
	ring.material_override = _mat(Color(0.58, 0.58, 0.55), 0.95)
	ring.position = Vector3(0, 0.25, 0)
	root.add_child(ring)
	var water := MeshInstance3D.new()
	var wm := CylinderMesh.new()
	wm.top_radius = 0.34
	wm.bottom_radius = 0.34
	wm.height = 0.05
	wm.radial_segments = 12
	water.mesh = wm
	var wmat := _mat(sim.C_WATER, 0.2, 0.0)
	wmat.emission_enabled = true
	wmat.emission = sim.C_WATER.darkened(0.2)
	wmat.emission_energy_multiplier = 0.5
	water.material_override = wmat
	water.position = Vector3(0, 0.46, 0)
	root.add_child(water)
	for sx in [-0.36, 0.36]:
		var post := MeshInstance3D.new()
		var pm := CylinderMesh.new()
		pm.top_radius = 0.05
		pm.bottom_radius = 0.06
		pm.height = 0.8
		post.mesh = pm
		post.material_override = _mat(Color(0.45, 0.30, 0.18), 0.95)
		post.position = Vector3(sx, 0.9, 0)
		root.add_child(post)
	var roof := MeshInstance3D.new()
	var rm := CylinderMesh.new()
	rm.top_radius = 0.0
	rm.bottom_radius = 0.6
	rm.height = 0.4
	rm.radial_segments = 4
	roof.mesh = rm
	roof.material_override = _mat(Color(0.55, 0.30, 0.22), 0.9)
	roof.position = Vector3(0, 1.5, 0)
	roof.rotation_degrees = Vector3(0, 45, 0)
	root.add_child(roof)
	_register_building(root, B_WELL, at + Vector3(0, 0.6, 0), Vector3(1.0, 1.6, 1.0))

# Procedural depot (= Depo): barn-like crate with a lid.
func _build_depot(at: Vector3) -> void:
	var root := Node3D.new()
	add_child(root)
	root.position = at
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.9, 0.8, 0.8)
	body.mesh = bm
	body.material_override = _mat(Color(0.62, 0.42, 0.26), 0.95)
	body.position = Vector3(0, 0.4, 0)
	root.add_child(body)
	var lid := MeshInstance3D.new()
	var lm := BoxMesh.new()
	lm.size = Vector3(1.0, 0.16, 0.9)
	lid.mesh = lm
	lid.material_override = _mat(Color(0.45, 0.30, 0.18), 0.9)
	lid.position = Vector3(0, 0.88, 0)
	root.add_child(lid)
	# corner straps for a crate read
	for sx in [-0.43, 0.43]:
		var strap := MeshInstance3D.new()
		var sm := BoxMesh.new()
		sm.size = Vector3(0.06, 0.8, 0.82)
		strap.mesh = sm
		strap.material_override = _mat(Color(0.35, 0.24, 0.15), 0.9)
		strap.position = Vector3(sx, 0.4, 0)
		root.add_child(strap)
	_register_building(root, B_DEPOT, at + Vector3(0, 0.5, 0), Vector3(1.0, 1.0, 0.9))

# Give a building a physics body so taps can hit it (raycast in _tap).
func _register_building(node: Node3D, kind: String, center: Vector3, size: Vector3) -> void:
	var body := StaticBody3D.new()
	body.position = center
	add_child(body)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = size
	shape.shape = box
	body.add_child(shape)
	_buildings.append({"node": node, "kind": kind, "body": body})

func _build_ground() -> void:
	var grass := MeshInstance3D.new()
	var gm := PlaneMesh.new()
	gm.size = Vector2(50, 50)
	grass.mesh = gm
	grass.material_override = _mat(Color(0.40, 0.56, 0.28), 0.95)
	grass.position = Vector3(0, -0.06, 0)
	add_child(grass)

# ---------------------------------------------------------------- environment (from look-test)
func _build_environment() -> void:
	var env := Environment.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.52, 0.70, 0.92)
	sky_mat.sky_horizon_color = Color(0.86, 0.88, 0.84)
	sky_mat.ground_horizon_color = Color(0.82, 0.80, 0.74)
	sky_mat.ground_bottom_color = Color(0.55, 0.52, 0.46)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.6
	env.ssao_enabled = true
	env.ssao_radius = 0.6
	env.ssao_intensity = 2.2
	env.glow_enabled = true
	env.glow_intensity = 0.25
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.adjustment_enabled = true
	env.adjustment_saturation = 1.12
	env.adjustment_contrast = 1.04
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	var sun := DirectionalLight3D.new()
	sun.light_color = Color(1.0, 0.94, 0.82)
	sun.light_energy = 1.35
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun.directional_shadow_blend_splits = true
	sun.shadow_blur = 1.5
	sun.rotation_degrees = Vector3(-52, -42, 0)
	add_child(sun)

	var fill := DirectionalLight3D.new()
	fill.light_color = Color(0.70, 0.80, 1.0)
	fill.light_energy = 0.25
	fill.rotation_degrees = Vector3(-30, 140, 0)
	add_child(fill)

	var cam := Camera3D.new()
	cam.fov = 58.0
	add_child(cam)
	cam.global_position = Vector3(0.0, 12.6, 13.2)
	cam.look_at(Vector3(0.0, 0.0, -0.4), Vector3.UP)
	_cam = cam

# ---------------------------------------------------------------- helpers
func _tree(at: Vector3) -> void:
	var trunk := MeshInstance3D.new()
	var tm := CylinderMesh.new()
	tm.top_radius = 0.10
	tm.bottom_radius = 0.14
	tm.height = 0.7
	trunk.mesh = tm
	trunk.material_override = _mat(Color(0.42, 0.28, 0.17), 1.0)
	trunk.position = at + Vector3(0, 0.35, 0)
	add_child(trunk)
	var greens := [Color(0.24, 0.44, 0.22), Color(0.28, 0.50, 0.25), Color(0.33, 0.56, 0.29)]
	for i in range(3):
		var cone := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.0
		cm.bottom_radius = 0.55 - i * 0.13
		cm.height = 0.55
		cm.radial_segments = 7
		cone.mesh = cm
		cone.material_override = _mat(greens[i], 1.0)
		cone.position = at + Vector3(0, 0.75 + i * 0.34, 0)
		add_child(cone)

func _soil_color(s: int) -> Color:
	match s:
		SimState.EMPTY:
			return Color(0.50, 0.37, 0.23)
		SimState.OBSTACLE:
			return Color(0.46, 0.34, 0.21)
		SimState.TILLED:
			return Color(0.36, 0.26, 0.16)
		SimState.PLANTED:
			return Color(0.41, 0.30, 0.18)
		_:
			return Color(0.34, 0.25, 0.15)

# Scale a glb instance so its largest footprint == target, optionally reposition to sit on ground.
func _scale_to(inst: Node3D, target: float, at = null) -> void:
	inst.scale = Vector3.ONE
	var ab := _local_aabb(inst)
	var span: float = max(ab.size.x, ab.size.z)
	if span < 0.0001:
		span = max(ab.size.y, 0.0001)
	var sc: float = target / span
	inst.scale = Vector3(sc, sc, sc)
	if at != null:
		var pos: Vector3 = at
		inst.position = pos + Vector3(0, -ab.position.y * sc, 0)

func _local_aabb(root: Node3D) -> AABB:
	var acc := AABB()
	var first := true
	var inv := root.global_transform.affine_inverse()
	for node in _all_meshes(root):
		var mi: MeshInstance3D = node
		if mi.mesh == null:
			continue
		var lt: Transform3D = inv * mi.global_transform
		var ab: AABB = lt * mi.mesh.get_aabb()
		if first:
			acc = ab
			first = false
		else:
			acc = acc.merge(ab)
	return acc

func _all_meshes(n: Node) -> Array:
	var out: Array = []
	if n is MeshInstance3D:
		out.append(n)
	for c in n.get_children():
		out.append_array(_all_meshes(c))
	return out

func _mat(col: Color, rough: float = 1.0, metal: float = 0.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.roughness = rough
	m.metallic = metal
	return m

func _shoot() -> void:
	if OS.has_environment("TAP_TEST"):
		_verify_taps()
	if OS.has_environment("HUD_TEST"):
		_verify_hud()
	if OS.has_environment("STORE_TEST"):
		_verify_store()
	if OS.has_environment("STORE_SHOW"):
		sim.coins = 999
		_store.open_store(sim, int(OS.get_environment("STORE_SHOW")) if OS.get_environment("STORE_SHOW").is_valid_int() else 0)
	if OS.has_environment("BOT_TEST"):
		_verify_bots()
	if OS.has_environment("EVENT_TEST"):
		_verify_events()
	var bot_show: bool = OS.has_environment("BOT_SHOW")
	if bot_show:
		_setup_bot_demo()
	var event_show: bool = OS.has_environment("EVENT_SHOW")
	if event_show:
		_setup_event_demo(OS.get_environment("EVENT_SHOW"))
	# bots need a few seconds to walk out; events are short, so shoot them mid-animation
	var wait := 2.0
	if bot_show:
		wait = 5.5
	elif event_show:
		wait = 1.5
	get_tree().create_timer(wait).timeout.connect(func() -> void:
		var img := get_viewport().get_texture().get_image()
		img.save_png("res://_shot_3d.png")
		get_tree().quit()
	)

# Headless sanity check for the screen->tile->manual chain: find each tile's screen
# position via unproject (inverse of the tap raycast), tap it, assert the round-trip.
func _verify_taps() -> void:
	print("=== TAP_TEST: screen->tile round-trip ===")
	var ok := true
	for i: int in [0, 1, sim.states.size() - 1]:  # obstacle/empty corner, neighbour, front tile
		var cr := _tile_cr(i)
		var world := _tile_pos(cr.x, cr.y) + Vector3(0, PICK_Y, 0)
		var screen := _cam.unproject_position(world)
		var got: int = _tile_under(screen)
		var pass_i: bool = got == i
		ok = ok and pass_i
		print("  tile %d -> screen %s -> tile %d   %s" % [i, str(screen.round()), got, "PASS" if pass_i else "FAIL"])
	# exercise the full action on a known tile (front row is RIPE in the demo)
	var last := sim.states.size() - 1
	var before_state := sim.states[last]
	var got_action: bool = sim.manual(last)
	_refresh_tile(last)
	print("  manual(front RIPE tile): state %d -> %d, action=%s" % [before_state, sim.states[last], str(got_action)])
	print("=== TAP_TEST %s ===" % ["PASS" if ok else "FAIL"])

# Smoke test for the HUD signal -> handler -> sim -> refresh wiring (Phase F).
func _verify_hud() -> void:
	print("=== HUD_TEST: signal -> handler -> sim ===")
	var ok := true
	# Sat: stock something, emit sell_pressed, coins must rise.
	sim.stock[2] = 3  # 3 Domates @ 8
	var c0: int = sim.coins
	_hud.sell_pressed.emit()
	var sell_ok: bool = sim.coins == c0 + 24 and sim.stock_total() == 0
	ok = ok and sell_ok
	print("  Sat: coins %d -> %d, depo=%d   %s" % [c0, sim.coins, sim.stock_total(), "PASS" if sell_ok else "FAIL"])
	# Su Al: emit buy_water_pressed, water must rise, coins drop by cost.
	var w0: int = sim.water; c0 = sim.coins
	_hud.buy_water_pressed.emit()
	var buy_ok: bool = sim.water == min(w0 + sim.WATER_BUNDLE, sim.WATER_MAX) and sim.coins == c0 - sim.WATER_COST
	ok = ok and buy_ok
	print("  Su Al: water %d -> %d, coins %d -> %d   %s" % [w0, sim.water, c0 + sim.WATER_COST, sim.coins, "PASS" if buy_ok else "FAIL"])
	# Seed picker: emit seed_selected(2), selected_seed must update.
	_hud.seed_selected.emit(2)
	var seed_ok: bool = sim.selected_seed == 2
	ok = ok and seed_ok
	print("  Seed pick: selected_seed=%d   %s" % [sim.selected_seed, "PASS" if seed_ok else "FAIL"])
	print("=== HUD_TEST %s ===" % ["PASS" if ok else "FAIL"])

# Buy a few specialist bots and paint them zones, so a screenshot shows live work.
func _setup_bot_demo() -> void:
	sim.coins = 9999
	# clear a working band so till/plant/water bots have something to do
	for i in range(min(sim.states.size(), SimState.COLS * 2)):
		if sim.states[i] != SimState.OBSTACLE:
			sim.states[i] = SimState.EMPTY
		_refresh_tile(i)
	var till = sim.buy_bot(SimState.TILL)
	var harv = sim.buy_bot(SimState.HARVEST)
	var clean = sim.buy_bot(SimState.CLEAN)
	# till bot works the cleared band; harvester works the ripe back rows; cleaner the rocks
	for i in range(SimState.COLS * 2):
		if i < sim.states.size():
			till.zone[i] = true
			clean.zone[i] = true
	for i in range(sim.states.size()):
		harv.zone[i] = true
		clean.zone[i] = true
	_tool = 0
	_hud.refresh_tools(sim, _tool, _erase)
	_update_zone_view()
	# advance the sim a bit so bots are already out on the field for the shot
	for _k in range(120):
		sim.tick(1.0 / 30.0)
		_sync_bots(1.0 / 30.0)

# Smoke test for the bot pipeline: buy -> paint zone -> tick -> tile worked + node spawned.
func _verify_bots() -> void:
	print("=== BOT_TEST: buy -> paint -> work ===")
	var ok := true
	sim.coins = 999
	var b = sim.buy_bot(SimState.TILL)
	var spawned: bool = b != null and sim.bots.size() >= 1
	ok = ok and spawned
	print("  buy_bot: bots=%d   %s" % [sim.bots.size(), "PASS" if spawned else "FAIL"])
	# paint a known empty tile into its zone
	var t := 2
	sim.states[t] = SimState.EMPTY
	b.zone[t] = true
	b.gpos = sim._grid_center(t)
	for _k in range(20):
		sim.tick(0.05)
	var worked: bool = sim.states[t] == SimState.TILLED
	ok = ok and worked
	print("  work: tile %d state=%d   %s" % [t, sim.states[t], "PASS" if worked else "FAIL"])
	# the view spawns a node for the bot
	_sync_bots(0.016)
	var node_ok: bool = _bot_nodes.size() == sim.bots.size() and sim.bots.size() > 0
	ok = ok and node_ok
	print("  view node spawned: %d nodes   %s" % [_bot_nodes.size(), "PASS" if node_ok else "FAIL"])
	print("=== BOT_TEST %s ===" % ["PASS" if ok else "FAIL"])

# Force one event live so a screenshot shows its 3D spectacle. EVENT_SHOW=<which>.
func _setup_event_demo(which: String) -> void:
	sim.coins = 9999
	# guarantee ripe crops so birds/UFO have something to act on, and clear smoke
	for i in range(sim.states.size()):
		if sim.states[i] != SimState.OBSTACLE:
			sim.states[i] = SimState.GROWING
			sim.grow[i] = 0.9
			sim.golden[i] = false
		_refresh_tile(i)
	match which:
		"rain":
			sim.rain_t = SimState.RAIN_DUR
			sim._emit_event("Yagmur yagiyor!")
		"ufo":
			sim.ufo_active = true; sim.ufo_t = 0.0; sim.ufo_fired = false
			sim.ufo_target = SimState.COLS * 2 + 4
			sim._emit_event("UFO geldi!")
		"birds":
			for i in range(SimState.COLS):
				sim.states[i] = SimState.RIPE; sim.grow[i] = 1.0
			sim.birds_active = true; sim.birds_t = 0.0; sim.birds_done = false
			sim.birds_blocked = false
			sim._emit_event("Kuslar geliyor!")
		"scarecrow":
			sim.scarecrow_charges = SimState.SCARECROW_MAX
			sim._emit_event("Korkuluk dikildi!")
		_:  # trader is the default spectacle
			sim.sell_boost_t = SimState.SELL_BOOST_DUR
			sim._emit_event("Gezgin tuccar geldi!")
	# advance a little so the visual is mid-animation for the shot (+1.5s real wait in _shoot
	# keeps UFO/birds/rain inside their durations: ~0.5 + 1.5 = 2.0s < every event length)
	for _k in range(15):
		sim.tick(1.0 / 30.0)

# Smoke test for the event view: each event spawns/updates its 3D node.
func _verify_events() -> void:
	print("=== EVENT_TEST: sim event -> 3D visual ===")
	var ok := true
	# rain
	sim.rain_t = SimState.RAIN_DUR
	_sync_events(0.016)
	var rain_ok: bool = _rain != null and _rain.visible
	ok = ok and rain_ok
	print("  rain visual: %s" % ["PASS" if rain_ok else "FAIL"])
	# ufo
	sim.ufo_active = true; sim.ufo_t = 1.0; sim.ufo_target = 5
	_sync_events(0.016)
	var ufo_ok: bool = _ufo != null and _ufo.visible
	ok = ok and ufo_ok
	print("  ufo visual: %s" % ["PASS" if ufo_ok else "FAIL"])
	# birds
	sim.birds_active = true; sim.birds_t = 1.0
	_sync_events(0.016)
	var birds_ok: bool = _birds != null and _birds.visible
	ok = ok and birds_ok
	print("  birds visual: %s" % ["PASS" if birds_ok else "FAIL"])
	# trader
	sim.sell_boost_t = SimState.SELL_BOOST_DUR
	_sync_events(0.016)
	var trader_ok: bool = _trader != null and _trader.visible
	ok = ok and trader_ok
	print("  trader visual: %s" % ["PASS" if trader_ok else "FAIL"])
	# scarecrow
	sim.scarecrow_charges = 3
	_sync_events(0.016)
	var scare_ok: bool = _scarecrow != null and _scarecrow.visible
	ok = ok and scare_ok
	print("  scarecrow visual: %s" % ["PASS" if scare_ok else "FAIL"])
	# toast fired on the latest event_seq bump
	sim._emit_event("test")
	_sync_events(0.016)
	var toast_ok: bool = _last_event_seq == sim.event_seq
	ok = ok and toast_ok
	print("  toast synced to event_seq: %s" % ["PASS" if toast_ok else "FAIL"])
	# events hide when their state clears
	sim.rain_t = 0.0; sim.ufo_active = false; sim.birds_active = false
	sim.sell_boost_t = 0.0; sim.scarecrow_charges = 0
	_sync_events(0.016)
	var hidden_ok: bool = not _rain.visible and not _ufo.visible and not _birds.visible \
		and not _trader.visible and not _scarecrow.visible
	ok = ok and hidden_ok
	print("  events hide when cleared: %s" % ["PASS" if hidden_ok else "FAIL"])
	print("=== EVENT_TEST %s ===" % ["PASS" if ok else "FAIL"])

# Smoke test for the store: open -> buy upgrade (coins drop) -> buy bot (store closes).
func _verify_store() -> void:
	print("=== STORE_TEST: open -> buy -> wire ===")
	var ok := true
	sim.coins = 999
	_on_open_store()
	var open_ok: bool = _store.is_open()
	ok = ok and open_ok
	print("  open: is_open=%s   %s" % [str(open_ok), "PASS" if open_ok else "FAIL"])
	# buy a depot (tab 2 building) — coins fall, storage grows, store stays open
	var c0: int = sim.coins
	var cap0: int = sim.storage_cap
	_store.buy_requested.emit(SimState.IT_DEPO)
	var depo_ok: bool = sim.coins < c0 and sim.storage_cap == cap0 + 20 and _store.is_open()
	ok = ok and depo_ok
	print("  buy depo: coins %d->%d cap %d->%d open=%s   %s" % [c0, sim.coins, cap0, sim.storage_cap, str(_store.is_open()), "PASS" if depo_ok else "FAIL"])
	# buy a bot — store should close so player can paint a zone
	var b0: int = sim.bots.size()
	_store.buy_requested.emit(SimState.TILL)
	var bot_ok: bool = sim.bots.size() == b0 + 1 and not _store.is_open()
	ok = ok and bot_ok
	print("  buy bot: bots %d->%d closed=%s   %s" % [b0, sim.bots.size(), str(not _store.is_open()), "PASS" if bot_ok else "FAIL"])
	print("=== STORE_TEST %s ===" % ["PASS" if ok else "FAIL"])
